// lib/features/notas/infrastructure/supabase_nota_fiscal_repository.dart
//
// CAMADA: infrastructure
// RESPONSABILIDADE: implementar INotaFiscalRepository usando Supabase.
//
// OPERAÇÃO CRÍTICA — importar():
// A importação de uma NF-e envolve múltiplas operações no banco:
// 1. INSERT em notas_fiscais
// 2. INSERT em nota_itens (um por item)
// 3. Upload do XML para o Supabase Storage
//
// Idealmente seria uma transação atômica (tudo ou nada).
// O Supabase não suporta transações via cliente Dart diretamente,
// então usamos a ordem: nota → itens → storage.
// Se o storage falhar, a nota e os itens já estão no banco —
// o xmlUrl ficará null e pode ser corrigido manualmente.
// Esta é uma limitação conhecida documentada aqui.

// Adiciona este import no topo do arquivo:
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/resultado.dart';
import '../domain/i_nota_fiscal_repository.dart';
import '../domain/item_nota.dart';
import '../domain/nota_fiscal.dart';


class SupabaseNotaFiscalRepository implements INotaFiscalRepository {
  final _client = Supabase.instance.client;

  static const _tabelaNotas = 'notas_fiscais';
  static const _tabelaItens = 'nota_itens';
  static const _bucketXml = 'xmls-nfe'; // bucket no Supabase Storage

@override
  Future<Resultado<List<NotaFiscal>>> buscarTodas() async {
    try {
      // Busca apenas as notas — sem join com itens
      // O join estava causando problemas com o fromMapMinimo
      // Estratégia: busca notas, depois count de itens por nota em paralelo
      final data = await _client
          .from(_tabelaNotas)
          .select()
          .isFilter('inativo_em', null)
          .order('data_emissao', ascending: false);

      // Future.wait executa todas as queries em paralelo
      // Conceito: paralelismo com Future.wait — mais eficiente que
      // executar uma query por vez em sequência (await dentro de loop)
      final notas = await Future.wait(
        (data as List).map((map) async {
          final notaId = map['id'] as String;

          // Busca apenas o id dos itens — só precisamos do count
          final itensData = await _client
              .from(_tabelaItens)
              .select('id')
              .eq('nota_id', notaId);

          // Monta itens mínimos passando nota_id explicitamente
          // CORREÇÃO: nota_id era ausente antes, causando count errado
          final itensMinimos = (itensData as List).map((i) =>
            ItemNota.fromMapMinimo({
              'id': i['id'] as String,
              'nota_id': notaId,  // garantido aqui — não vem do SELECT
            }),
          ).toList();

          return NotaFiscal.fromMap(map, itens: itensMinimos);
        }),
      );

      return Sucesso(notas);
    } on PostgrestException catch (e) {
      return Falha(TipoFalha.servidor, 'Erro ao buscar notas', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }

  @override
  Future<Resultado<NotaFiscal>> importar({
    required NotaFiscal nota,
    required String xmlContent,
  }) async {
    try {
      // ---- Passo 1: INSERT da nota ----
      // toMap() da NotaFiscal também não inclui 'id' — banco gera
      final notaData = await _client
          .from(_tabelaNotas)
          .insert(nota.toMap())
          .select()
          .single();

      final notaId = notaData['id'] as String;

      // ---- Passo 2: INSERT dos itens ----
      // CORREÇÃO CRÍTICA: ItemNota.toMap() não inclui 'id' vazio
      // Antes: {'id': '', 'nota_id': notaId, ...} → erro UUID no PostgreSQL
      // Agora: {'nota_id': notaId, ...} → banco gera UUID automaticamente
      if (nota.itens.isNotEmpty) {
        final itensParaSalvar = nota.itens.map((item) {
          final map = item.toMap(); // sem 'id'
          map['nota_id'] = notaId;  // sobrescreve o notaId vazio do parse
          return map;
        }).toList();

        // INSERT de todos os itens de uma vez (batch insert)
        // Mais eficiente que inserir um por vez
        await _client.from(_tabelaItens).insert(itensParaSalvar);
      }

      // ---- Passo 3: Upload do XML para Storage ----
      // utf8.encode converte String para List<int> de bytes UTF-8
      // Necessário porque uploadBinary espera Uint8List
      String? xmlUrl;
      try {
        final caminhoStorage = '${nota.empresaId}/$notaId.xml';
        final xmlBytes = utf8.encode(xmlContent);

        await _client.storage
            .from(_bucketXml)
            .uploadBinary(
              caminhoStorage,
              xmlBytes,
              fileOptions: const FileOptions(
                contentType: 'application/xml',
                upsert: false,
              ),
            );

        xmlUrl = _client.storage
            .from(_bucketXml)
            .getPublicUrl(caminhoStorage);

        await _client
            .from(_tabelaNotas)
            .update({'xml_url': xmlUrl})
            .eq('id', notaId);
      } catch (storageError) {
        // Storage falhou mas nota e itens estão salvos
        // Limitação conhecida: sem transação atômica no cliente Supabase
        // xmlUrl ficará null — aceitável, não bloqueia o fluxo operacional
      }

      // Retorna a nota completa com itens reais do banco
      return buscarPorId(notaId);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        return Falha(
          TipoFalha.duplicidade,
          'Esta nota fiscal já foi importada anteriormente.',
        );
      }
      // MELHORIA: expõe o erro real para diagnóstico
      return Falha(
        TipoFalha.servidor,
        'Erro ao importar nota: ${e.message} (código: ${e.code})',
        detalhes: e,
      );
    } catch (e) {
      return Falha(
        TipoFalha.desconhecido,
        'Erro inesperado ao importar: ${e.toString()}',
        detalhes: e,
      );
    }
  }
  
  @override
  Future<Resultado<NotaFiscal>> buscarPorId(String id) async {
    try {
      // Busca a nota
      final notaData = await _client
          .from(_tabelaNotas)
          .select()
          .eq('id', id)
          .single();

      // Busca os itens da nota
      final itensData = await _client
          .from(_tabelaItens)
          .select()
          .eq('nota_id', id)
          .order('numero_item', ascending: true);

      final itens = (itensData as List)
          .map((map) => ItemNota.fromMap(map))
          .toList();

      return Sucesso(NotaFiscal.fromMap(notaData, itens: itens));
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') {
        return Falha(TipoFalha.naoEncontrado, 'Nota fiscal não encontrada');
      }
      return Falha(TipoFalha.servidor, 'Erro ao buscar nota', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }

  @override
  Future<Resultado<bool>> verificarDuplicidade(String chaveAcesso) async {
    try {
      final data = await _client
          .from(_tabelaNotas)
          .select('id')
          .eq('chave_acesso', chaveAcesso)
          .maybeSingle(); // retorna null se não encontrar, sem erro

      return Sucesso(data != null);
    } on PostgrestException catch (e) {
      return Falha(TipoFalha.servidor, 'Erro ao verificar duplicidade', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }

  @override
  Future<Resultado<void>> atualizarStatus(
      String id, String novoStatus) async {
    try {
      await _client
          .from(_tabelaNotas)
          .update({'status': novoStatus})
          .eq('id', id);

      return Sucesso(null);
    } on PostgrestException catch (e) {
      return Falha(TipoFalha.servidor, 'Erro ao atualizar status', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }

  @override
  Future<Resultado<void>> inativar(String id) async {
    try {
      await _client
          .from(_tabelaNotas)
          .update({'inativo_em': DateTime.now().toIso8601String()})
          .eq('id', id);

      return Sucesso(null);
    } on PostgrestException catch (e) {
      return Falha(TipoFalha.servidor, 'Erro ao inativar nota', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }
}