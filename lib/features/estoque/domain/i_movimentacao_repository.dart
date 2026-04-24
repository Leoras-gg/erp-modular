// lib/features/estoque/domain/i_movimentacao_repository.dart
//
// CAMADA: domain
// RESPONSABILIDADE: contrato do repositório de movimentações.
//
// Sem métodos de update ou delete — imutabilidade por design.
// Correções são feitas via nova movimentação de ajuste.

import '../../../core/errors/resultado.dart';
import 'movimentacao.dart';

abstract class IMovimentacaoRepository {
  // Histórico de movimentações de um produto.
  // JOIN com produtos para nome e código de barras.
  // Ordenado por data decrescente.
  Future<Resultado<List<Movimentacao>>> buscarPorProduto(String produtoId);

  // Movimentações de uma conferência específica.
  Future<Resultado<List<Movimentacao>>> buscarPorConferencia(
      String conferenciaId);

  // Registra entradas ao finalizar uma conferência sem divergência.
  // Fluxo por item:
  //   1. Resolve produto_id via nota_item_id → nota_itens.produto_id
  //   2. Se produto_id null → pula (item não vinculado)
  //   3. Busca saldo atual → cria Movimentacao → atualiza produto
  //   4. Atualiza status da nota para 'conferida'
  Future<Resultado<List<Movimentacao>>> registrarEntradaConferencia({
    required String conferenciaId,
    required String notaId,
    required String operadorId,
    required String empresaId,
    required List<Map<String, dynamic>> itensConferencia,
  });

  // Ajuste manual de saldo com motivo obrigatório.
  Future<Resultado<Movimentacao>> registrarAjuste({
    required String produtoId,
    required String empresaId,
    required String operadorId,
    required double novaQuantidade,
    required String motivo,
  });
}