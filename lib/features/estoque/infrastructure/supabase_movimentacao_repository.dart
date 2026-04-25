// lib/features/estoque/infrastructure/supabase_movimentacao_repository.dart
//
// CAMADA: infrastructure
//
// CORREÇÃO CRÍTICA implementada aqui:
// ConferenciaItem NÃO tem produto_id diretamente.
// O loop resolve: nota_item_id → nota_itens.produto_id via query.
// Se produto_id for null, o item é pulado (não vinculado ainda).

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/resultado.dart';
import '../domain/i_movimentacao_repository.dart';
import '../domain/movimentacao.dart';

class SupabaseMovimentacaoRepository implements IMovimentacaoRepository {
  final _client = Supabase.instance.client;

  static const _tabela             = 'movimentacoes';
  static const _tabelaProdutos     = 'produtos';
  static const _tabelaNotaItens    = 'nota_itens';
  //static const _tabelaConferencias = 'conferencias';
  static const _tabelaNotas        = 'notas_fiscais';
  static const _tabelaBarcodes     = 'produto_barcodes';

  @override
  Future<Resultado<List<Movimentacao>>> buscarPorProduto(
      String produtoId) async {
    try {
      // JOIN com produtos para nome e unidade_medida
      final data = await _client
          .from(_tabela)
          .select('*, $_tabelaProdutos(nome, unidade_medida)')
          .eq('produto_id', produtoId)
          .order('criado_em', ascending: false);

      // Barcode principal — query separada (Supabase não faz múltiplos
      // joins aninhados facilmente no cliente Dart)
      String? codigoBarras;
      try {
        final barcodeData = await _client
            .from(_tabelaBarcodes)
            .select('barcode')
            .eq('produto_id', produtoId)
            .eq('principal', true)
            .maybeSingle();
        codigoBarras = barcodeData?['barcode'] as String?;
      } catch (_) {
        // barcode é opcional — não bloqueia
      }

      final movs = (data as List).map((map) {
        final produto = map[_tabelaProdutos] as Map<String, dynamic>?;
        return Movimentacao.fromMap({
          ...map,
          'nome_produto': produto?['nome'] as String?,
          'unidade_medida': produto?['unidade_medida'] as String?,
          'codigo_barras_produto': codigoBarras,
        });
      }).toList();

      return Sucesso(movs);
    } on PostgrestException catch (e) {
      return Falha(TipoFalha.servidor,
          'Erro ao buscar movimentações: ${e.message}', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }

  @override
  Future<Resultado<List<Movimentacao>>> buscarPorConferencia(
      String conferenciaId) async {
    try {
      final data = await _client
          .from(_tabela)
          .select('*, $_tabelaProdutos(nome, unidade_medida)')
          .eq('conferencia_id', conferenciaId)
          .order('criado_em', ascending: true);

      final movs = (data as List).map((map) {
        final produto = map[_tabelaProdutos] as Map<String, dynamic>?;
        return Movimentacao.fromMap({
          ...map,
          'nome_produto': produto?['nome'] as String?,
          'unidade_medida': produto?['unidade_medida'] as String?,
        });
      }).toList();

      return Sucesso(movs);
    } on PostgrestException catch (e) {
      return Falha(TipoFalha.servidor,
          'Erro ao buscar movimentações: ${e.message}', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }

  @override
  Future<Resultado<List<Movimentacao>>> registrarEntradaConferencia({
    required String conferenciaId,
    required String notaId,
    required String operadorId,
    required String empresaId,
    required List<Map<String, dynamic>> itensConferencia,
  }) async {
    final movsCriadas = <Movimentacao>[];
    int itensPulados = 0;

    try {
      for (final item in itensConferencia) {
        final notaItemId = item['nota_item_id'] as String?;
        final qtdConferida =
            (item['quantidade_conferida'] as num?)?.toDouble() ?? 0;

        if (notaItemId == null || qtdConferida <= 0) continue;

        // Resolve produto_id via nota_itens
        // ConferenciaItem só tem nota_item_id, não produto_id diretamente
        final notaItemData = await _client
            .from(_tabelaNotaItens)
            .select('produto_id, lote')
            .eq('id', notaItemId)
            .maybeSingle();

        if (notaItemData == null) continue;

        final produtoId = notaItemData['produto_id'] as String?;
        if (produtoId == null) {
          // Item não vinculado — não gera movimentação
          itensPulados++;
          continue;
        }

        final lote =
            notaItemData['lote'] as String? ?? item['lote'] as String?;

        // Busca saldo atual
        final prodData = await _client
            .from(_tabelaProdutos)
            .select('quantidade_atual')
            .eq('id', produtoId)
            .single();

        final saldoAnterior =
            (prodData['quantidade_atual'] as num).toDouble();
        final saldoPosterior = saldoAnterior + qtdConferida;

        // Cria a movimentação
        final movData = await _client
            .from(_tabela)
            .insert({
              'empresa_id': empresaId,
              'produto_id': produtoId,
              'tipo': 'entrada',
              'quantidade': qtdConferida,
              'saldo_anterior': saldoAnterior,
              'saldo_posterior': saldoPosterior,
              'origem': 'conferencia',
              'conferencia_id': conferenciaId,
              'nota_id': notaId,
              'lote': lote,
              'operador_id': operadorId,
              'criado_em': DateTime.now().toIso8601String(),
            })
            .select()
            .single();

        movsCriadas.add(Movimentacao.fromMap(movData));

        // Atualiza saldo do produto
        await _client
            .from(_tabelaProdutos)
            .update({'quantidade_atual': saldoPosterior})
            .eq('id', produtoId);
      }

      // Atualiza status da nota para 'conferida'
      await _client
          .from(_tabelaNotas)
          .update({'status': 'conferida'})
          .eq('id', notaId);

      return Sucesso(movsCriadas);
    } on PostgrestException catch (e) {
      return Falha(
        TipoFalha.servidor,
        'Erro ao registrar movimentações: ${e.message} (${e.code}). '
        '${movsCriadas.length} já criada(s). $itensPulados sem vínculo.',
        detalhes: e,
      );
    } catch (e) {
      return Falha(TipoFalha.desconhecido,
          'Erro inesperado ao registrar movimentações', detalhes: e);
    }
  }

  @override
  Future<Resultado<Movimentacao>> registrarAjuste({
    required String produtoId,
    required String empresaId,
    required String operadorId,
    required double novaQuantidade,
    required String motivo,
  }) async {
    try {
      final prodData = await _client
          .from(_tabelaProdutos)
          .select('quantidade_atual')
          .eq('id', produtoId)
          .single();

      final saldoAnterior =
          (prodData['quantidade_atual'] as num).toDouble();
      final variacao = novaQuantidade - saldoAnterior;

      final movData = await _client
          .from(_tabela)
          .insert({
            'empresa_id': empresaId,
            'produto_id': produtoId,
            'tipo': 'ajuste',
            'quantidade': variacao.abs(),
            'saldo_anterior': saldoAnterior,
            'saldo_posterior': novaQuantidade,
            'origem': 'ajuste',
            'observacao': motivo,
            'operador_id': operadorId,
            'criado_em': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      await _client
          .from(_tabelaProdutos)
          .update({'quantidade_atual': novaQuantidade})
          .eq('id', produtoId);

      return Sucesso(Movimentacao.fromMap(movData));
    } on PostgrestException catch (e) {
      return Falha(TipoFalha.servidor,
          'Erro ao registrar ajuste: ${e.message}', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }
}