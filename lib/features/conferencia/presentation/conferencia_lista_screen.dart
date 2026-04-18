// lib/features/conferencia/presentation/conferencia_lista_screen.dart
//
// CAMADA: presentation
// RESPONSABILIDADE: listar as conferências de uma nota e permitir
// iniciar nova conferência ou continuar uma existente.
//
// ============================================================
// CORREÇÕES APLICADAS
// ============================================================
// BUG 1 — loop / falha na navegação:
// Antes, a tela tentou usar ref.listen dentro do build e ainda ficou
// com um listen duplicado/aninhado, o que quebrou o fluxo e gerou
// comportamento inconsistente.
//
// SOLUÇÃO:
// - usar ref.listenManual no initState()
// - guardar a subscription em _sub
// - fechar a subscription no dispose()
// - controlar a navegação com a flag _navegouParaAtiva
//
// BUG 2 — botão "Iniciar conferência" falhando silenciosamente:
// Antes, o clique usava asyncNota.whenData(...) no build.
// Se a nota ainda estivesse carregando, nada acontecia.
//
// SOLUÇÃO:
// - criar _iniciarConferencia()
// - usar ref.read(notaDetalheProvider(widget.notaId)) no momento do clique
// - tratar loading, error e data com feedback para o usuário
//
// CONCEITO APLICADO:
// build() deve ser o mais puro possível — focado em desenhar a UI.
// Navegação e side effects ficam no ciclo de vida e em métodos próprios.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/conferencia_notifier.dart';
import '../domain/conferencia.dart';
import '../../notas/application/nota_fiscal_notifier.dart';

class ConferenciaListaScreen extends ConsumerStatefulWidget {
  final String notaId;

  const ConferenciaListaScreen({super.key, required this.notaId});

  @override
  ConsumerState<ConferenciaListaScreen> createState() =>
      _ConferenciaListaScreenState();
}

class _ConferenciaListaScreenState
    extends ConsumerState<ConferenciaListaScreen> {
  // Protege contra múltiplos pushes da mesma rota.
  bool _navegouParaAtiva = false;

  // Listener manual do Riverpod.
  // Como esta tela faz side effect de navegação, listenManual é mais seguro
  // do que ref.listen no build.
  ProviderSubscription<ConferenciaState>? _sub;

  @override
  void initState() {
    super.initState();

    _sub = ref.listenManual<ConferenciaState>(conferenciaProvider, (
      previous,
      next,
    ) {
      final virouAtiva =
          previous is! ConferenciaAtiva && next is ConferenciaAtiva;

      if (virouAtiva && !_navegouParaAtiva) {
        _navegouParaAtiva = true;

        context.push('/conferencia/${next.conferencia.id}').then((_) {
          // Quando a tela ativa fecha, recarregamos a lista da nota.
          // Isso evita voltar para uma tela presa em estado antigo.
          if (!mounted) return;

          _navegouParaAtiva = false;

          ref.read(conferenciaProvider.notifier).carregarPorNota(widget.notaId);
        });
      }

      if (next is ConferenciaListaCarregada ||
          next is ConferenciaVazio ||
          next is ConferenciaErro) {
        // Garante reset da flag ao voltar para estados de lista
        _navegouParaAtiva = false;
      }
    });

    // CORREÇÃO: reseta a flag ao entrar na tela
    _navegouParaAtiva = false;

    // Carrega as conferências da nota ao abrir a tela.
    Future.microtask(
      () =>
          ref.read(conferenciaProvider.notifier).carregarPorNota(widget.notaId),
    );
  }

  @override
  void didUpdateWidget(covariant ConferenciaListaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Se a tela passar a apontar para outra nota,
    // recarrega as conferências da nova nota.
    if (oldWidget.notaId != widget.notaId) {
      _navegouParaAtiva = false;

      Future.microtask(
        () => ref
            .read(conferenciaProvider.notifier)
            .carregarPorNota(widget.notaId),
      );
    }
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  // ============================================================
  // _iniciarConferencia
  // ============================================================
  // CORREÇÃO BUG 1:
  // Usa ref.read() para pegar o valor mais recente da nota no momento
  // do clique — não depende de um asyncNota capturado no build().
  //
  // Se a nota ainda estiver carregando, mostramos feedback.
  // Se houver erro, mostramos SnackBar.
  // Se estiver pronta, iniciamos a conferência normalmente.
  void _iniciarConferencia() {
    final asyncNota = ref.read(notaDetalheProvider(widget.notaId));

    asyncNota.when(
      loading: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Carregando dados da nota, aguarde...'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      error: (e, _) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar nota: $e'),
            backgroundColor: Colors.red,
          ),
        );
      },
      data: (nota) {
        final itensNota = nota.itens
            .map((i) => {'id': i.id, 'quantidade': i.quantidade})
            .toList();

        ref
            .read(conferenciaProvider.notifier)
            .iniciar(widget.notaId, itensNota);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(conferenciaProvider);

    // asyncNota removido do build().
    // Agora ele é lido sob demanda em _iniciarConferencia().

    return Scaffold(
      appBar: AppBar(title: const Text('Conferências')),
      body: switch (state) {
        ConferenciaInicial() || ConferenciaCarregando() => const Center(
          child: CircularProgressIndicator(),
        ),

        ConferenciaVazio() => _EstadoVazio(onIniciar: _iniciarConferencia),

        ConferenciaListaCarregada(:final conferencias) => _ListaConferencias(
          conferencias: conferencias,
          onIniciarNova: _iniciarConferencia,
        ),

        // Enquanto a navegação acontece, mostramos loading.
        ConferenciaAtiva() => const Center(child: CircularProgressIndicator()),

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

  const _ConferenciaCard({required this.conferencia});

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

  const _EstadoVazio({required this.onIniciar});

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
