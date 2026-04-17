// lib/features/conferencia/presentation/conferencia_lista_screen.dart
//
// CAMADA: presentation
// RESPONSABILIDADE: listar as conferências de uma nota e permitir
// iniciar nova conferência ou continuar uma existente.
//
// CORREÇÃO DE BUG IMPORTANTE:
// Antes, a navegação para a tela ativa acontecia DENTRO do build()
// quando o estado virava ConferenciaAtiva.
// Isso causava loop infinito de push no GoRouter, porque cada rebuild
// agendava uma nova navegação.
//
// SOLUÇÃO:
// - transformar a tela em ConsumerStatefulWidget
// - carregar os dados em initState()
// - escutar transições de estado com ref.listen()
// - navegar apenas UMA vez quando o estado mudar para ConferenciaAtiva
//
// CONCEITO APLICADO:
// build() deve ser puro — desenhar interface.
// Navegação é efeito colateral e deve ficar fora do build.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/conferencia_notifier.dart';
import '../domain/conferencia.dart';
import '../../notas/application/nota_fiscal_notifier.dart';

class ConferenciaListaScreen extends ConsumerStatefulWidget {
  final String notaId;

  const ConferenciaListaScreen({
    super.key,
    required this.notaId,
  });

  @override
  ConsumerState<ConferenciaListaScreen> createState() =>
      _ConferenciaListaScreenState();
}

class _ConferenciaListaScreenState
    extends ConsumerState<ConferenciaListaScreen> {
  // Flag de proteção para impedir navegação repetida.
  // Sem isso, qualquer mudança sucessiva para ConferenciaAtiva
  // poderia tentar navegar várias vezes.
  bool _navegouParaAtiva = false;

  @override
  void initState() {
    super.initState();

    // Carrega a lista da nota uma única vez ao abrir a tela.
    Future.microtask(
      () => ref.read(conferenciaProvider.notifier).carregarPorNota(widget.notaId),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Escuta mudanças de estado para navegar FORA do build visual.
    ref.listen<ConferenciaState>(conferenciaProvider, (previous, next) {
      // Só navega quando ocorre a transição para ConferenciaAtiva
      // pela primeira vez.
      final virouAtiva =
          previous is! ConferenciaAtiva && next is ConferenciaAtiva;

      if (virouAtiva && !_navegouParaAtiva) {
        _navegouParaAtiva = true;
        context.push('/conferencia/${next.conferencia.id}');
      }

      // Se voltarmos para estados de lista/vazio, liberamos a navegação futura.
      if (next is ConferenciaListaCarregada || next is ConferenciaVazio) {
        _navegouParaAtiva = false;
      }
    });

    final state = ref.watch(conferenciaProvider);
    final asyncNota = ref.watch(notaDetalheProvider(widget.notaId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conferências'),
      ),
      body: switch (state) {
        ConferenciaInicial() || ConferenciaCarregando() =>
          const Center(child: CircularProgressIndicator()),

        ConferenciaVazio() => _EstadoVazio(
            onIniciar: () => asyncNota.whenData((nota) {
              final itensNota = nota.itens
                  .map((i) => {'id': i.id, 'quantidade': i.quantidade})
                  .toList();

              ref.read(conferenciaProvider.notifier).iniciar(
                    widget.notaId,
                    itensNota,
                  );
            }),
          ),

        ConferenciaListaCarregada(:final conferencias) => _ListaConferencias(
            conferencias: conferencias,
            onIniciarNova: () => asyncNota.whenData((nota) {
              final itensNota = nota.itens
                  .map((i) => {'id': i.id, 'quantidade': i.quantidade})
                  .toList();

              ref.read(conferenciaProvider.notifier).iniciar(
                    widget.notaId,
                    itensNota,
                  );
            }),
          ),

        // IMPORTANTE:
        // Aqui não navegamos mais no build.
        // Só mostramos um loading enquanto o listener faz a navegação.
        ConferenciaAtiva() =>
          const Center(child: CircularProgressIndicator()),

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
                      .carregarPorNota(widget.notaId),
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

  const _ListaConferencias({
    required this.conferencias,
    required this.onIniciarNova,
  });

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

  const _ConferenciaCard({
    required this.conferencia,
  });

  @override
  Widget build(BuildContext context) {
    final corStatus = switch (conferencia.status) {
      'concluida' => Colors.green,
      'cancelada' => Colors.grey,
      'pausada' => Colors.orange,
      _ => Theme.of(context).colorScheme.primary,
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
        'criada' => 'Criada',
        'em_andamento' => 'Em andamento',
        'pausada' => 'Pausada',
        'aguardando_aprovacao' => 'Aguardando aprovação',
        'concluida' => 'Concluída',
        'cancelada' => 'Cancelada',
        _ => s,
      };

  String _formatarData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _EstadoVazio extends StatelessWidget {
  final VoidCallback onIniciar;

  const _EstadoVazio({
    required this.onIniciar,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          const Text(
            'Nenhuma conferência iniciada',
            style: TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Inicie uma conferência para registrar os itens recebidos',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
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