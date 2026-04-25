// lib/features/conferencia/application/vinculacao_notifier.dart
//
// CAMADA: application
// RESPONSABILIDADE: gerenciar itens pendentes de vinculação.
//
// PROVIDER: NotifierProvider.family parametrizado por conferenciaId.
// Cada conferência tem estado isolado — sem provider global.
// Mesma lição da Sessão 9: um provider por responsabilidade.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/resultado.dart';
import '../domain/item_pendente_vinculacao.dart';

// ============================================================
// SEALED CLASS DE ESTADO
// ============================================================
sealed class VinculacaoState {}

class VinculacaoInicial    extends VinculacaoState {}
class VinculacaoCarregando extends VinculacaoState {}

class VinculacaoCarregada extends VinculacaoState {
  final List<ItemPendenteVinculacao> itens;
  VinculacaoCarregada(this.itens);

  bool get todosVinculados =>
      itens.every((i) => i.vinculado);

  int get totalPendentes =>
      itens.where((i) => i.pendente).length;
}

// Nenhum item pendente — todos os itens já têm produto_id
class VinculacaoSemPendencias extends VinculacaoState {}

class VinculacaoErro extends VinculacaoState {
  final String mensagem;
  VinculacaoErro(this.mensagem);
}

// ============================================================
// NOTIFIER
// ============================================================
class VinculacaoNotifier extends Notifier<VinculacaoState> {
  VinculacaoNotifier(this.conferenciaId);

  final String conferenciaId;
  final _client = Supabase.instance.client;

  @override
  VinculacaoState build() {
    Future.microtask(carregar);
    return VinculacaoInicial();
  }

  Future<void> carregar() async {
    state = VinculacaoCarregando();

    try {
      final data = await _client
          .from('conferencia_itens')
          .select('''
            id,
            nota_itens (
              id,
              produto_id,
              descricao_produto,
              ncm,
              cfop,
              codigo_barras,
              quantidade,
              unidade_medida,
              lote
            )
          ''')
          .eq('conferencia_id', conferenciaId);

      final pendentes = <ItemPendenteVinculacao>[];

      for (final row in data as List) {
        final notaItem = row['nota_itens'] as Map<String, dynamic>?;
        if (notaItem == null) continue;

        if (notaItem['produto_id'] != null) continue;

        pendentes.add(
          ItemPendenteVinculacao(
            conferenciaItemId: row['id'] as String,
            notaItemId: notaItem['id'] as String,
            descricaoProduto:
                notaItem['descricao_produto'] as String? ?? 'Sem descrição',
            ncm: notaItem['ncm'] as String? ?? '',
            cfop: notaItem['cfop'] as String? ?? '',
            codigoBarras: notaItem['codigo_barras'] as String?,
            quantidade: (notaItem['quantidade'] as num).toDouble(),
            unidadeMedida: notaItem['unidade_medida'] as String? ?? 'UN',
            lote: notaItem['lote'] as String?,
          ),
        );
      }

      state = pendentes.isEmpty
          ? VinculacaoSemPendencias()
          : VinculacaoCarregada(pendentes);
    } catch (e) {
      state = VinculacaoErro('Erro ao verificar pendências: $e');
    }
  }

  Future<Resultado<void>> vincular({
    required ItemPendenteVinculacao item,
    required ProdutoVinculado produto,
  }) async {
    try {
      await _client
          .from('nota_itens')
          .update({'produto_id': produto.id})
          .eq('id', item.notaItemId);

      if (state is VinculacaoCarregada) {
        final novos = (state as VinculacaoCarregada).itens.map((i) {
          return i.notaItemId == item.notaItemId
              ? i.copyWith(produtoVinculado: produto)
              : i;
        }).toList();

        state = VinculacaoCarregada(novos);
      }

      return Sucesso(null);
    } on PostgrestException catch (e) {
      return Falha(
        TipoFalha.servidor,
        'Erro ao vincular: ${e.message}',
        detalhes: e,
      );
    } catch (e) {
      return Falha(
        TipoFalha.desconhecido,
        'Erro inesperado',
        detalhes: e,
      );
    }
  }

  Future<Resultado<void>> desvincular(ItemPendenteVinculacao item) async {
    try {
      await _client
          .from('nota_itens')
          .update({'produto_id': null})
          .eq('id', item.notaItemId);

      if (state is VinculacaoCarregada) {
        final novos = (state as VinculacaoCarregada).itens.map((i) {
          return i.notaItemId == item.notaItemId
              ? i.copyWith(limparVinculo: true)
              : i;
        }).toList();

        state = VinculacaoCarregada(novos);
      }

      return Sucesso(null);
    } on PostgrestException catch (e) {
      return Falha(
        TipoFalha.servidor,
        'Erro ao desvincular: ${e.message}',
        detalhes: e,
      );
    } catch (e) {
      return Falha(
        TipoFalha.desconhecido,
        'Erro inesperado',
        detalhes: e,
      );
    }
  }
}

final vinculacaoProvider =
    NotifierProvider.family<VinculacaoNotifier, VinculacaoState, String>(
  VinculacaoNotifier.new,
);