// lib/features/estoque/presentation/movimentacoes_screen.dart
//
// CAMADA: presentation
// RESPONSABILIDADE: histórico de movimentações de um produto.
//
// PROVIDER: FutureProvider.family parametrizado por produtoId.
// Sem estado global — sem risco de contaminação entre produtos.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/movimentacao.dart';
import '../infrastructure/supabase_movimentacao_repository.dart';
import '../../../core/errors/resultado.dart';

final movimentacoesProdutoProvider =
    FutureProvider.family<List<Movimentacao>, String>(
  (ref, produtoId) async {
    final repo = SupabaseMovimentacaoRepository();
    final resultado = await repo.buscarPorProduto(produtoId);
    return switch (resultado) {
      Sucesso(:final dados) => dados,
      Falha(:final mensagem) => throw Exception(mensagem),
    };
  },
);

class MovimentacoesScreen extends ConsumerWidget {
  final String produtoId;
  final String nomeProduto;

  const MovimentacoesScreen({
    super.key,
    required this.produtoId,
    required this.nomeProduto,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncMovs = ref.watch(movimentacoesProdutoProvider(produtoId));

    return Scaffold(
      appBar: AppBar(
        title: Text('Histórico — $nomeProduto'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(movimentacoesProdutoProvider(produtoId)),
          ),
        ],
      ),
      body: switch (asyncMovs) {
        AsyncLoading() =>
          const Center(child: CircularProgressIndicator()),

        AsyncError(:final error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline,
                      size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(error.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => ref.invalidate(
                        movimentacoesProdutoProvider(produtoId)),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          ),

        AsyncData(:final value) when value.isEmpty => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history,
                    size: 64,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant),
                const SizedBox(height: 16),
                const Text('Nenhuma movimentação registrada',
                    style: TextStyle(fontSize: 18)),
                const SizedBox(height: 8),
                Text(
                  'As movimentações aparecerão após\na conclusão de conferências.',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

        AsyncData(:final value) => ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: value.length,
            itemBuilder: (ctx, i) => _MovimentacaoCard(mov: value[i]),
          ),
      },
    );
  }
}

class _MovimentacaoCard extends StatelessWidget {
  final Movimentacao mov;
  const _MovimentacaoCard({required this.mov});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final (cor, icone) = switch (mov.tipo) {
      'entrada' => (Colors.green, Icons.arrow_downward),
      'saida'   => (Colors.red, Icons.arrow_upward),
      _         => (Colors.blue, Icons.swap_horiz),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Ícone de direção
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icone, color: cor),
                ),
                const SizedBox(width: 12),
                // Nome e código de barras
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mov.nomeProduto ?? 'Produto',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (mov.codigoBarrasProduto != null)
                        Text(
                          mov.codigoBarrasProduto!,
                          style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11,
                              fontFamily: 'monospace'),
                        ),
                    ],
                  ),
                ),
                // Quantidade e saldo
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${mov.ehEntrada ? '+' : '-'}${_qtd(mov.quantidade)}'
                      ' ${mov.unidadeMedida ?? ''}',
                      style: TextStyle(
                          color: cor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                    Text(
                      'Saldo: ${_qtd(mov.saldoPosterior)}',
                      style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Chips: tipo, origem, lote
            Wrap(
              spacing: 6, runSpacing: 4,
              children: [
                _Chip(_labelTipo(mov.tipo), cor),
                _Chip(_labelOrigem(mov.origem), colorScheme.primary),
                if (mov.lote != null)
                  _Chip('Lote: ${mov.lote}', Colors.teal),
              ],
            ),
            const SizedBox(height: 6),

            // Linha de rastreabilidade — ID e nota vinculada
            Row(
              children: [
                // ID da movimentação
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '#${mov.id.substring(0, 8).toUpperCase()}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (mov.notaId != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.receipt_outlined,
                      size: 12, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 3),
                  Text(
                    'NF vinculada',
                    style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant),
                  ),
                ],
                const Spacer(),
                // Data e hora
                Text(
                  _formatarData(mov.criadoEm),
                  style: TextStyle(
                      color: colorScheme.onSurfaceVariant, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _qtd(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toStringAsFixed(3);

  String _labelTipo(String t) =>
      switch (t) { 'entrada' => 'Entrada', 'saida' => 'Saída', _ => 'Ajuste' };

  String _labelOrigem(String o) => switch (o) {
    'conferencia' => 'Conferência NF-e',
    'manual'      => 'Lançamento manual',
    _             => 'Ajuste de inventário',
  };

  String _formatarData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}  '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

class _Chip extends StatelessWidget {
  final String label;
  final Color cor;
  const _Chip(this.label, this.cor);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cor.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: cor, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}