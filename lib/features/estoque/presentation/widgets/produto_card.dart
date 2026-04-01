// lib/features/estoque/presentation/widgets/produto_card.dart
//
// CAMADA: presentation
// RESPONSABILIDADE: exibir um produto em formato de card na listagem.
// Widget privado do módulo de estoque — não é reutilizado fora dele.
//
// CONCEITOS APLICADOS:
// - Composição de widgets: card composto por partes menores
// - Props como parâmetros: widget recebe Produto e callbacks
// - Propriedades derivadas do domínio: estoqueBaixo vem do Produto

import 'package:flutter/material.dart';
import '../../domain/produto.dart';

class ProdutoCard extends StatelessWidget {
  final Produto produto;
  final VoidCallback? onTap;
  final VoidCallback? onInativar;

  const ProdutoCard({
    super.key,
    required this.produto,
    this.onTap,
    this.onInativar,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // ---- INDICADOR DE ESTOQUE ----
              // Conceito: propriedade derivada do domínio — a UI
              // não decide se o estoque está baixo, só exibe
              _IndicadorEstoque(
                baixo: produto.estoqueBaixo,
                quantidade: produto.quantidadeAtual,
                unidade: produto.unidadeMedida,
              ),
              const SizedBox(width: 16),

              // ---- DADOS DO PRODUTO ----
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      produto.nome,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cód: ${produto.codigoInterno}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    if (produto.localizacaoFisica != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            produto.localizacaoFisica!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // ---- MENU DE AÇÕES ----
              if (onInativar != null)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'inativar') onInativar?.call();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'inativar',
                      child: Row(
                        children: [
                          Icon(Icons.block, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Inativar produto'),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Widget privado — indicador visual de quantidade em estoque
class _IndicadorEstoque extends StatelessWidget {
  final bool baixo;
  final double quantidade;
  final String unidade;

  const _IndicadorEstoque({
    required this.baixo,
    required this.quantidade,
    required this.unidade,
  });

  @override
  Widget build(BuildContext context) {
    // Cor muda conforme o estado do estoque
    // Conceito: feedback visual imediato baseado em regra de negócio
    final cor = baixo ? Colors.red.shade400 : Colors.green.shade400;

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            // Formata número: remove casas decimais se for inteiro
            quantidade == quantidade.truncate()
                ? quantidade.toInt().toString()
                : quantidade.toStringAsFixed(2),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: cor,
            ),
          ),
          Text(
            unidade,
            style: TextStyle(fontSize: 10, color: cor),
          ),
        ],
      ),
    );
  }
}