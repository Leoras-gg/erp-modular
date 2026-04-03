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
// Adiciona este import no topo do arquivo:
import 'dart:convert';

class SupabaseNotaFiscalRepository implements INotaFiscalRepository {
  final _client = Supabase.instance.client;

  static const _tabelaNotas = 'notas_fiscais';
  static const _tabelaItens = 'nota_itens';
  static const _bucketXml = 'xmls-nfe'; // bucket no Supabase Storage

@override
  Future<Resultado<List<NotaFiscal>>> buscarTodas() async {
    try {
      // Busca as notas sem join por ora — o join com itens
      // estava causando falha silenciosa quando nota_id estava ausente
      // no map retornado pelo Supabase. Buscamos as notas primeiro,
      // depois buscamos os counts de itens separadamente.
      final data = await _client
          .from(_tabelaNotas)
          .select()
          .isFilter('inativo_em', null)
          .order('data_emissao', ascending: false);

      // Para cada nota, busca o count de itens
      // Conceito: Promise.all equivalente em Dart com Future.wait
      final notas = await Future.wait(
        (data as List).map((map) async {
          // Conta os itens desta nota no banco
          final itensData = await _client
              .from(_tabelaItens)
              .select('id')
              .eq('nota_id', map['id'] as String);

          // Cria ItemNota mínimos só para ter o count correto na UI
          final itensMinimos = (itensData as List).map((i) =>
            ItemNota.fromMapMinimo({
              'id': i['id'] as String,
              'nota_id': map['id'] as String, // garante nota_id preenchido
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
            .map((item) => {
                  ...item.toMap(),
                  'nota_id': notaId, // vincula ao id real gerado pelo banco
                })
            .toList();

        await _client.from(_tabelaItens).insert(itensParaSalvar);
      }

      // ---- Passo 3: Upload do XML para o Storage ----
      // Convertemos a String XML para bytes usando utf8.encode()
      // que é o método correto em Dart para String → Uint8List
      String? xmlUrl;
      try {
        final caminhoStorage = '${nota.empresaId}/$notaId.xml';
        // utf8.encode retorna List<int> com os bytes UTF-8 do XML
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
      } catch (_) {
        // Storage falhou — nota e itens já salvos no banco
        // xmlUrl permanece null — pode ser corrigido manualmente
      }

      return buscarPorId(notaId);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        return Falha(
          TipoFalha.duplicidade,
          'Esta nota fiscal já foi importada anteriormente.',
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