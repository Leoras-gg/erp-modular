// lib/features/notas/presentation/notas_screen.dart
//
// CAMADA: presentation
// RESPONSABILIDADE: tela principal do fluxo de notas fiscais.
// Exibe a lista de notas importadas e permite importar novas.
//
// ESTADOS TRATADOS:
// - Carregando: CircularProgressIndicator
// - Lista: cards das notas com status colorido
// - Vazio: convite para importar
// - Erro: mensagem com botão de tentar novamente
// - Duplicada: diálogo especial de decisão
// - Importada: banner de sucesso

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/nota_fiscal_notifier.dart';
import '../domain/nota_fiscal.dart';

class NotasScreen extends ConsumerWidget {
  const NotasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notaFiscalProvider);

    // Reage ao estado NotaDuplicada mostrando diálogo
    // ref.listen é diferente de ref.watch — executa efeito colateral
    // sem reconstruir o widget completo
    ref.listen(notaFiscalProvider, (previous, next) {
      if (next is NotaDuplicada) {
        _mostrarDialogoDuplicidade(context, ref, next);
      }
      if (next is NotaFiscalImportada) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.mensagem),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notas Fiscais'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(notaFiscalProvider.notifier).recarregar(),
          ),
        ],
      ),
      body: switch (state) {
        NotaFiscalInicial() || NotaFiscalCarregando() =>
          const Center(child: CircularProgressIndicator()),

        NotaFiscalListaCarregada(:final notas) =>
          _ListaNotas(notas: notas),

        NotaFiscalImportada(:final nota) =>
          _ListaNotas(notas: [nota]),

        NotaFiscalVazio() => _EstadoVazio(
            onImportar: () =>
                ref.read(notaFiscalProvider.notifier).importarXml(),
          ),

        NotaFiscalErro(:final mensagem) => _EstadoErro(
            mensagem: mensagem,
            onRetentar: () =>
                ref.read(notaFiscalProvider.notifier).recarregar(),
          ),

        // NotaDuplicada é tratada via ref.listen acima
        NotaDuplicada() =>
          const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            ref.read(notaFiscalProvider.notifier).importarXml(),
        icon: const Icon(Icons.upload_file),
        label: const Text('Importar XML'),
      ),
    );
  }

  // Diálogo especial para nota duplicada
  // Usuário pode navegar para a nota existente ou cancelar
  void _mostrarDialogoDuplicidade(
    BuildContext context,
    WidgetRef ref,
    NotaDuplicada state,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber, color: Colors.amber, size: 48),
        title: const Text('Nota já importada'),
        content: Text(state.mensagem),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(notaFiscalProvider.notifier).recarregar();
            },
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: navegar para a nota existente quando
              // a tela de detalhes for implementada
              ref.read(notaFiscalProvider.notifier).recarregar();
            },
            child: const Text('Ver nota existente'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// LISTA DE NOTAS
// ============================================================
class _ListaNotas extends StatelessWidget {
  final List<NotaFiscal> notas;

  const _ListaNotas({required this.notas});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: notas.length,
      itemBuilder: (context, index) {
        return _NotaCard(nota: notas[index]);
      },
    );
  }
}

// ============================================================
// CARD DE NOTA FISCAL
// ============================================================
class _NotaCard extends StatelessWidget {
  final NotaFiscal nota;

  const _NotaCard({required this.nota});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Número e série
                Text(
                  'NF-e ${nota.numero} / Série ${nota.serie}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                // Badge de status com cor
                _StatusBadge(status: nota.status),
              ],
            ),
            const SizedBox(height: 8),

            // Emitente
            Text(
              nota.emitenteNome,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              'CNPJ: ${_formatarCnpj(nota.emitenteCnpj)} — ${nota.emitenteUf}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${nota.totalItens} item(ns)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'R\$ ${nota.valorTotal.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Formata CNPJ: 00.000.000/0000-00
  String _formatarCnpj(String cnpj) {
    if (cnpj.length != 14) return cnpj;
    return '${cnpj.substring(0, 2)}.'
        '${cnpj.substring(2, 5)}.'
        '${cnpj.substring(5, 8)}/'
        '${cnpj.substring(8, 12)}-'
        '${cnpj.substring(12)}';
  }
}

// Badge colorido por status
class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (cor, label) = switch (status) {
      'importada'        => (Colors.blue, 'Importada'),
      'em_conferencia'   => (Colors.orange, 'Em conferência'),
      'conferida'        => (Colors.teal, 'Conferida'),
      'divergente'       => (Colors.red, 'Divergente'),
      'finalizada'       => (Colors.green, 'Finalizada'),
      'cancelada'        => (Colors.grey, 'Cancelada'),
      _                  => (Colors.grey, status),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: cor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// Estado vazio
class _EstadoVazio extends StatelessWidget {
  final VoidCallback onImportar;

  const _EstadoVazio({required this.onImportar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.upload_file_outlined, size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text('Nenhuma nota importada',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Clique em "Importar XML" para começar',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onImportar,
            icon: const Icon(Icons.upload_file),
            label: const Text('Importar XML'),
          ),
        ],
      ),
    );
  }
}

// Estado de erro
class _EstadoErro extends StatelessWidget {
  final String mensagem;
  final VoidCallback onRetentar;

  const _EstadoErro({required this.mensagem, required this.onRetentar});

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
            Text(mensagem, textAlign: TextAlign.center),
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