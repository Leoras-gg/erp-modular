// lib/features/conferencia/presentation/widgets/item_pendente_card.dart
//
// RESPONSABILIDADE: card de um item pendente de vinculação.
// Estados: Pendente (âmbar) e Vinculado (verde).
// Botões: Vincular / Trocar vínculo / Desvincular / Cadastrar (futuro).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/errors/resultado.dart';
import '../../application/vinculacao_notifier.dart';
import '../../domain/item_pendente_vinculacao.dart';
import 'vinculacao_bottom_sheet.dart';

class ItemPendenteCard extends ConsumerWidget {
  final ItemPendenteVinculacao item;
  final String conferenciaId;

  const ItemPendenteCard({
    super.key,
    required this.item,
    required this.conferenciaId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    final (corBorda, corBadge, labelBadge, iconeBadge) = item.vinculado
        ? (Colors.green, Colors.green, 'Vinculado', Icons.check_circle)
        : (Colors.amber, Colors.amber, 'Não cadastrado', Icons.warning_amber);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: corBorda.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge de estado
            Row(
              children: [
                Icon(iconeBadge, color: corBadge, size: 18),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: corBadge.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: corBadge.withValues(alpha: 0.4)),
                  ),
                  child: Text(labelBadge,
                      style: TextStyle(
                          color: corBadge,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Descrição do item na nota
            Text(item.descricaoProduto,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),

            // Dados fiscais
            Wrap(
              spacing: 6, runSpacing: 4,
              children: [
                _Chip('NCM: ${item.ncm}'),
                _Chip('CFOP: ${item.cfop}'),
                _Chip('${_qtd(item.quantidade)} ${item.unidadeMedida}'),
                if (item.codigoBarras != null)
                  _Chip('EAN: ${item.codigoBarras}'),
                if (item.lote != null) _Chip('Lote: ${item.lote}'),
              ],
            ),

            // Produto vinculado
            if (item.vinculado) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.link, size: 16, color: Colors.green.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vinculado: ${item.produtoVinculado!.nome}',
                          style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Cód: ${item.produtoVinculado!.codigoInterno}',
                          style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 10),

            // Botões de ação
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _abrirVinculacao(context, ref),
                    icon: Icon(
                        item.vinculado ? Icons.swap_horiz : Icons.link,
                        size: 18),
                    label: Text(item.vinculado
                        ? 'Trocar vínculo'
                        : 'Vincular a existente'),
                    style: FilledButton.styleFrom(
                      backgroundColor: item.vinculado
                          ? colorScheme.secondary
                          : colorScheme.primary,
                    ),
                  ),
                ),
                if (item.vinculado) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _desvincular(context, ref),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red),
                    child: const Icon(Icons.link_off, size: 18),
                  ),
                ],
                if (item.pendente) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Cadastro de produtos será implementado em breve.'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Cadastrar'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirVinculacao(BuildContext context, WidgetRef ref) async {
    final produto =
        await VinculacaoBottomSheet.abrir(context, item);
    if (produto == null) return;

    final resultado = await ref
        .read(vinculacaoProvider(conferenciaId).notifier)
        .vincular(item: item, produto: produto);

    if (resultado is Falha && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text((resultado).mensagem),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _desvincular(BuildContext context, WidgetRef ref) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover vínculo'),
        content: Text(
            'Remover vínculo com "${item.produtoVinculado?.nome}"?\n\n'
            'O item voltará como "Não cadastrado".'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final resultado = await ref
        .read(vinculacaoProvider(conferenciaId).notifier)
        .desvincular(item);

    if (resultado is Falha && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text((resultado).mensagem),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _qtd(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toString();
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color:
            Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}