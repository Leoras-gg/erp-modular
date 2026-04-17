// lib/features/conferencia/presentation/conferencia_lista_screen.dart
//
// CAMADA: presentation
// RESPONSABILIDADE: listar as conferências de uma nota e permitir
// iniciar nova conferência ou continuar uma existente.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../application/conferencia_notifier.dart';
import '../domain/conferencia.dart';
import '../../notas/application/nota_fiscal_notifier.dart';

class ConferenciaListaScreen extends ConsumerWidget {
  final String notaId;
  const ConferenciaListaScreen({super.key, required this.notaId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conferenciaProvider);

    // Carrega conferências ao abrir
    ref.listen(conferenciaProvider, (_, _) {});
    if (state is ConferenciaInicial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(conferenciaProvider.notifier).carregarPorNota(notaId);
      });
    }

    // Carrega a nota para ter os itens disponíveis para iniciar conferência
    final asyncNota = ref.watch(notaDetalheProvider(notaId));

    return Scaffold(
      appBar: AppBar(title: const Text('Conferências')),
      body: switch (state) {
        ConferenciaInicial() || ConferenciaCarregando() =>
          const Center(child: CircularProgressIndicator()),

        ConferenciaVazio() => _EstadoVazio(
            onIniciar: () => asyncNota.whenData((nota) {
              final itensNota = nota.itens
                  .map((i) => {'id': i.id, 'quantidade': i.quantidade})
                  .toList();
              ref.read(conferenciaProvider.notifier).iniciar(notaId, itensNota);
            }),
          ),

        ConferenciaListaCarregada(:final conferencias) =>
          _ListaConferencias(
            conferencias: conferencias,
            onIniciarNova: () => asyncNota.whenData((nota) {
              final itensNota = nota.itens
                  .map((i) => {'id': i.id, 'quantidade': i.quantidade})
                  .toList();
              ref.read(conferenciaProvider.notifier).iniciar(notaId, itensNota);
            }),
          ),

        ConferenciaAtiva(:final conferencia) => Builder(
            builder: (ctx) {
              // Navega para a tela ativa quando conferência for iniciada
              WidgetsBinding.instance.addPostFrameCallback((_) {
                context.push('/conferencia/${conferencia.id}');
              });
              return const Center(child: CircularProgressIndicator());
            },
          ),

        ConferenciaErro(:final mensagem) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(mensagem, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => ref
                      .read(conferenciaProvider.notifier)
                      .carregarPorNota(notaId),
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
      },
    );
  }
}

class _ListaConferencias extends StatelessWidget {
  final List<Conferencia> conferencias;
  final VoidCallback onIniciarNova;
  const _ListaConferencias(
      {required this.conferencias, required this.onIniciarNova});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: conferencias.length,
            itemBuilder: (context, i) =>
                _ConferenciaCard(conferencia: conferencias[i]),
          ),
        ),
        // Botão nova conferência — apenas se não houver conferência ativa
        if (conferencias.every((c) => c.cancelada || c.concluida))
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onIniciarNova,
                icon: const Icon(Icons.add),
                label: const Text('Nova conferência'),
              ),
            ),
          ),
      ],
    );
  }
}

class _ConferenciaCard extends StatelessWidget {
  final Conferencia conferencia;
  const _ConferenciaCard({required this.conferencia});

  @override
  Widget build(BuildContext context) {
    final corStatus = switch (conferencia.status) {
      'concluida' => Colors.green,
      'cancelada' => Colors.grey,
      'pausada'   => Colors.orange,
      _           => Theme.of(context).colorScheme.primary,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          conferencia.concluida
              ? Icons.check_circle
              : conferencia.cancelada
                  ? Icons.cancel
                  : Icons.assignment_outlined,
          color: corStatus,
        ),
        title: Text(
          _labelStatus(conferencia.status),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${conferencia.totalItensConferidos}/${conferencia.itens.length} itens • '
          '${_formatarData(conferencia.iniciadoEm)}',
        ),
        trailing: conferencia.ativa
            ? const Icon(Icons.arrow_forward_ios, size: 16)
            : null,
        onTap: conferencia.ativa
            ? () => context.push('/conferencia/${conferencia.id}')
            : null,
      ),
    );
  }

  String _labelStatus(String s) => switch (s) {
    'criada'               => 'Criada',
    'em_andamento'         => 'Em andamento',
    'pausada'              => 'Pausada',
    'aguardando_aprovacao' => 'Aguardando aprovação',
    'concluida'            => 'Concluída',
    'cancelada'            => 'Cancelada',
    _                      => s,
  };

  String _formatarData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _EstadoVazio extends StatelessWidget {
  final VoidCallback onIniciar;
  const _EstadoVazio({required this.onIniciar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          const Text('Nenhuma conferência iniciada',
              style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Text('Inicie uma conferência para registrar os itens recebidos',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onIniciar,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Iniciar conferência'),
          ),
        ],
      ),
    );
  }
}