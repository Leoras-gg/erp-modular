// lib/features/conferencia/presentation/widgets/vinculacao_bottom_sheet.dart
//
// RESPONSABILIDADE: busca e seleção de produto existente para vincular.
// Retorna ProdutoVinculado via Navigator.pop() ao selecionar.
// Providers com autoDispose — descartados ao fechar o bottom sheet.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/item_pendente_vinculacao.dart';

final _resultadosProvider =
    FutureProvider.autoDispose.family<List<ProdutoVinculado>, String>(
  (ref, query) async {
    if (query.trim().length < 2) return [];

    final q = query.trim().toLowerCase();
    final client = Supabase.instance.client;

    final results = await client
        .from('produtos')
        .select('id, nome, codigo_interno, unidade_medida, produto_barcodes(barcode)')
        .or('nome.ilike.%$q%,codigo_interno.ilike.%$q%')
        .isFilter('inativo_em', null)
        .limit(20);

    return (results as List).map((row) {
      final barcodes = row['produto_barcodes'] as List?;
      final barcode = barcodes?.isNotEmpty == true
          ? barcodes!.first['barcode'] as String?
          : null;

      return ProdutoVinculado(
        id: row['id'] as String,
        nome: row['nome'] as String,
        codigoInterno: row['codigo_interno'] as String,
        barcode: barcode,
        unidadeMedida: row['unidade_medida'] as String,
      );
    }).toList();
  },
);

class VinculacaoBottomSheet extends ConsumerStatefulWidget {
  final ItemPendenteVinculacao itemPendente;

  const VinculacaoBottomSheet({super.key, required this.itemPendente});

  // Helper estático para abrir e aguardar resultado
  static Future<ProdutoVinculado?> abrir(
    BuildContext context,
    ItemPendenteVinculacao item,
  ) {
    return showModalBottomSheet<ProdutoVinculado>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => ProviderScope(
        child: VinculacaoBottomSheet(itemPendente: item),
      ),
    );
  }

  @override
  ConsumerState<VinculacaoBottomSheet> createState() =>
      _VinculacaoBottomSheetState();
}

class _VinculacaoBottomSheetState
    extends ConsumerState<VinculacaoBottomSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
   final asyncResultados = ref.watch(_resultadosProvider(_query));
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vincular item da nota',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),

                // Card com dados do item da nota
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: colorScheme.outline.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Item da nota (fornecedor):',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text(widget.itemPendente.descricaoProduto,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: [
                          _InfoChip('NCM: ${widget.itemPendente.ncm}'),
                          _InfoChip('CFOP: ${widget.itemPendente.cfop}'),
                          _InfoChip(
                              '${_qtd(widget.itemPendente.quantidade)} ${widget.itemPendente.unidadeMedida}'),
                          if (widget.itemPendente.codigoBarras != null)
                            _InfoChip('EAN: ${widget.itemPendente.codigoBarras}'),
                          if (widget.itemPendente.lote != null)
                            _InfoChip('Lote: ${widget.itemPendente.lote}'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Campo de busca
                TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Nome, código interno ou código de barras...',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _controller.clear();
                             setState(() {
  _query = '';
});
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) =>
                      setState(() {
                        _query = v;
                      }),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // Resultados
          Expanded(
            child: switch (asyncResultados) {
              AsyncLoading() =>
                const Center(child: CircularProgressIndicator()),

              AsyncError(:final error) =>
                Center(child: Text('Erro: $error')),

              AsyncData() when _query.trim().length < 2 =>
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search, size: 48,
                          color: colorScheme.onSurfaceVariant),
                      const SizedBox(height: 8),
                      Text('Digite ao menos 2 caracteres',
                          style: TextStyle(
                              color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),

              AsyncData(:final value) when value.isEmpty =>
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 48,
                          color: colorScheme.onSurfaceVariant),
                      const SizedBox(height: 8),
                      const Text('Nenhum produto encontrado'),
                    ],
                  ),
                ),

              AsyncData(:final value) => ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: value.length,
                  itemBuilder: (ctx, i) => _ResultadoCard(
                    produto: value[i],
                    onSelecionar: () => Navigator.pop(context, value[i]),
                  ),
                ),
            },
          ),
        ],
      ),
    );
  }

  String _qtd(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toString();
}

class _ResultadoCard extends StatelessWidget {
  final ProdutoVinculado produto;
  final VoidCallback onSelecionar;

  const _ResultadoCard(
      {required this.produto, required this.onSelecionar});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.inventory_2_outlined,
              color: colorScheme.onPrimaryContainer),
        ),
        title: Text(produto.nome,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cód: ${produto.codigoInterno} • ${produto.unidadeMedida}'),
            if (produto.barcode != null)
              Text('EAN: ${produto.barcode}',
                  style: TextStyle(
                      color: colorScheme.onSurfaceVariant, fontSize: 11)),
          ],
        ),
        trailing: FilledButton(
          onPressed: onSelecionar,
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12)),
          child: const Text('Vincular'),
        ),
        isThreeLine: produto.barcode != null,
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  const _InfoChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}