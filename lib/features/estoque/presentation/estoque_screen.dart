// lib/features/estoque/presentation/estoque_screen.dart
//
// CAMADA: presentation
// RESPONSABILIDADE: tela principal do módulo de estoque.
// Exibe a listagem de produtos com busca, pull-to-refresh
// e estados visuais para cada situação possível.
//
// CONCEITOS APLICADOS:
// - ConsumerWidget: observa produtoProvider via Riverpod
// - switch sobre sealed class: garante tratamento de todos os estados
// - Separação clara: tela só exibe e captura eventos — lógica no Notifier

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/produto_notifier.dart';
import 'widgets/produto_card.dart';

class EstoqueScreen extends ConsumerWidget {
  const EstoqueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(produtoProvider);

    return Scaffold(
      // ---- HEADER ----
      appBar: AppBar(
        title: const Text('Estoque'),
        actions: [
          // Botão de recarregar manual
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
            onPressed: () =>
                ref.read(produtoProvider.notifier).recarregar(),
          ),
        ],
      ),

      // ---- CONTEÚDO ----
      body: Column(
        children: [
          // Barra de busca — sempre visível
          _BarraBusca(
            onChanged: (termo) =>
                ref.read(produtoProvider.notifier).buscarPorTermo(termo),
          ),

          // Conteúdo principal — muda conforme o estado
          Expanded(
            // switch sobre a sealed class — Dart garante exaustividade
            child: switch (state) {
              ProdutoInicial() || ProdutoCarregando() =>
                const Center(child: CircularProgressIndicator()),

              ProdutoCarregado(:final produtos, :final termo) =>
                _ListaProdutos(
                  produtos: produtos,
                  termo: termo,
                  onInativar: (id) =>
                      ref.read(produtoProvider.notifier).inativar(id),
                ),

              ProdutoVazio(:final mensagem) => _EstadoVazio(mensagem),

              ProdutoErro(:final mensagem) => _EstadoErro(
                  mensagem: mensagem,
                  onRetentar: () =>
                      ref.read(produtoProvider.notifier).recarregar(),
                ),
            },
          ),
        ],
      ),

      // ---- FAB — botão de adicionar produto ----
      // TODO: navegar para tela de cadastro quando implementada
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cadastro de produtos em desenvolvimento'),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Novo produto'),
      ),
    );
  }
}

// ============================================================
// BARRA DE BUSCA
// ============================================================
class _BarraBusca extends StatefulWidget {
  final ValueChanged<String> onChanged;

  const _BarraBusca({required this.onChanged});

  @override
  State<_BarraBusca> createState() => _BarraBuscaState();
}

class _BarraBuscaState extends State<_BarraBusca> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: 'Buscar por nome ou código...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          // Botão de limpar — aparece quando há texto
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                  },
                )
              : null,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

// ============================================================
// LISTA DE PRODUTOS
// ============================================================
class _ListaProdutos extends StatelessWidget {
  final List<dynamic> produtos;
  final String termo;
  final ValueChanged<String> onInativar;

  const _ListaProdutos({
    required this.produtos,
    required this.termo,
    required this.onInativar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Contador de resultados
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                termo.isNotEmpty
                    ? '${produtos.length} resultado(s) para "$termo"'
                    : '${produtos.length} produto(s) cadastrado(s)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Lista com pull-to-refresh
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => onInativar(''),
            child: ListView.builder(
              itemCount: produtos.length,
              itemBuilder: (context, index) {
                final produto = produtos[index];
                return ProdutoCard(
                  produto: produto,
                  onTap: () {
                    // TODO: navegar para tela de detalhes
                  },
                  onInativar: () => _confirmarInativacao(context, produto),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // Diálogo de confirmação antes de inativar
  // Conceito: ações destrutivas sempre pedem confirmação
  void _confirmarInativacao(BuildContext context, dynamic produto) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Inativar produto'),
        content: Text(
          'Deseja inativar "${produto.nome}"?\n\n'
          'O produto não será excluído — ficará inativo e não aparecerá nas listagens.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              onInativar(produto.id);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Inativar'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ESTADO VAZIO
// ============================================================
class _EstadoVazio extends StatelessWidget {
  final String mensagem;

  const _EstadoVazio(this.mensagem);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            mensagem,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ESTADO DE ERRO
// ============================================================
class _EstadoErro extends StatelessWidget {
  final String mensagem;
  final VoidCallback onRetentar;

  const _EstadoErro({
    required this.mensagem,
    required this.onRetentar,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              mensagem,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetentar,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}