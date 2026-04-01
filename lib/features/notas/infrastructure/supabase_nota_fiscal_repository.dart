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
      final data = await _client
          .from(_tabelaNotas)
          .select()
          .isFilter('inativo_em', null)
          .order('data_emissao', ascending: false);

      final notas = (data as List)
          .map((map) => NotaFiscal.fromMap(map))
          .toList();

      return Sucesso(notas);
    } on PostgrestException catch (e) {
      return Falha(TipoFalha.servidor, 'Erro ao buscar notas', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
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
  Future<Resultado<NotaFiscal>> importar({
    required NotaFiscal nota,
    required String xmlContent,
  }) async {
    try {
      // ---- Passo 1: Salva a nota fiscal ----
      final notaData = await _client
          .from(_tabelaNotas)
          .insert(nota.toMap())
          .select()
          .single();

      final notaId = notaData['id'] as String;

      // ---- Passo 2: Salva os itens ----
      if (nota.itens.isNotEmpty) {
        final itensParaSalvar = nota.itens
            .map((item) => {...item.toMap(), 'nota_id': notaId})
            .toList();

        await _client.from(_tabelaItens).insert(itensParaSalvar);
      }

      // ---- Passo 3: Upload do XML para o Storage ----
      // Caminho: empresa_id/nota_id.xml
      // Isso organiza os XMLs por empresa no Storage
      String? xmlUrl;
      try {
        final caminhoStorage =
            '${nota.empresaId}/$notaId.xml';

        await _client.storage
            .from(_bucketXml)
            .uploadBinary(
              caminhoStorage,
              xmlContent.codeUnits
                  .map((c) => c & 0xFF)
                  .toList() as dynamic,
              fileOptions: const FileOptions(
                contentType: 'application/xml',
                upsert: false,
              ),
            );

        xmlUrl = _client.storage
            .from(_bucketXml)
            .getPublicUrl(caminhoStorage);

        // Atualiza a nota com a URL do XML
        await _client
            .from(_tabelaNotas)
            .update({'xml_url': xmlUrl})
            .eq('id', notaId);
      } catch (storageError) {
        // Storage falhou — nota e itens já estão no banco
        // Registra o erro mas não falha a importação inteira
        // xmlUrl permanece null — pode ser corrigido manualmente
      }

      // Busca a nota completa para retornar
      return buscarPorId(notaId);
    } on PostgrestException catch (e) {
      // Código 23505 = violação de unique constraint (chave duplicada)
      if (e.code == '23505') {
        return Falha(
          TipoFalha.duplicidade,
          'Esta nota fiscal já foi importada anteriormente. '
          'Chave de acesso já existe no sistema.',
        );
      }
      return Falha(TipoFalha.servidor, 'Erro ao importar nota', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado ao importar', detalhes: e);
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