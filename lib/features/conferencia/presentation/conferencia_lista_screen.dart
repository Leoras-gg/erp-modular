// lib/features/conferencia/presentation/conferencia_lista_screen.dart
//
// CAMADA: presentation
// RESPONSABILIDADE: listar conferências de uma nota e iniciar/continuar.
//
// ============================================================
// HISTÓRICO DE BUGS CORRIGIDOS NESTE ARQUIVO
// ============================================================
//
// BUG 1 — Loop infinito de navegação:
//   CAUSA: a tela era ConsumerWidget (stateless). Quando o estado
//   virava ConferenciaAtiva, o build() executava e chamava
//   addPostFrameCallback com context.push(). Cada push() causava
//   rebuild → novo push() → loop infinito.
//   CORREÇÃO: convertido para ConsumerStatefulWidget. Navegação
//   acontece FORA do build(), como side effect do listener.
//
// BUG 2 — ref.listen fora do build():
//   CAUSA: ref.listen() só funciona dentro do build(). No initState()
//   ele lança assertion error do Riverpod.
//   CORREÇÃO: uso de ref.listenManual() — projetado para lifecycle
//   manual fora do build(). Requer close() explícito no dispose().
//
// BUG 4 — Estado inconsistente ao voltar da tela ativa:
//   CAUSA: um provider servindo dois contextos. Ao voltar, estado
//   ficava em ConferenciaAtiva e a lista não recarregava.
//   CORREÇÃO: ao voltar da tela ativa (.then() do push), recarrega
//   explicitamente a lista com carregarPorNota().

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../application/conferencia_notifier.dart';
import '../domain/conferencia.dart';
import '../../notas/application/nota_fiscal_notifier.dart';

// ============================================================
// TELA — ConsumerStatefulWidget (não ConsumerWidget)
// ============================================================
// CONCEITO: ConsumerStatefulWidget quando precisamos de:
//   1. ref fora do build() (listenManual, initState, dispose)
//   2. estado local (flag _navegouParaAtiva)
//   3. recursos com lifecycle (ProviderSubscription)
// ConsumerWidget é suficiente quando só precisamos de ref.watch()
// dentro do build(). Aqui precisamos de mais — daí o Stateful.
class ConferenciaListaScreen extends ConsumerStatefulWidget {
  final String notaId;

  const ConferenciaListaScreen({super.key, required this.notaId});

  @override
  ConsumerState<ConferenciaListaScreen> createState() =>
      _ConferenciaListaScreenState();
}

class _ConferenciaListaScreenState
    extends ConsumerState<ConferenciaListaScreen> {

  // Flag que previne múltiplos pushes para a tela ativa.
  // Sem ela, o listener poderia ser chamado mais de uma vez
  // antes da navegação completar, causando pushes duplicados.
  bool _navegouParaAtiva = false;

  // Subscription manual — necessária porque usamos listenManual.
  // Deve ser fechada no dispose() para evitar memory leak.
  ProviderSubscription<ConferenciaState>? _sub;

  @override
  void initState() {
    super.initState();

    // ============================================================
    // ref.listenManual — uso CORRETO fora do build()
    // ============================================================
    // ref.listen() só funciona dentro do build().
    // ref.listenManual() foi criado para casos como este:
    // lifecycle manual, fora do ciclo de renderização.
    // Requer close() explícito no dispose().
    _sub = ref.listenManual<ConferenciaState>(
      conferenciaProvider,
      (previous, next) {
        // ---- Detecta transição para ConferenciaAtiva ----
        // Só navega se:
        //   1. O estado MUDOU para ConferenciaAtiva (não estava antes)
        //   2. Ainda não navegamos (flag protege contra pushes duplos)
        final virouAtiva =
            previous is! ConferenciaAtiva && next is ConferenciaAtiva;

        if (virouAtiva && !_navegouParaAtiva) {
          _navegouParaAtiva = true;

          // push() navega para a tela ativa.
          // .then() executa quando o usuário VOLTA da tela ativa.
          // Neste momento recarregamos a lista para refletir o
          // estado atual das conferências daquela nota.
          context
              .push('/conferencia/${(next as ConferenciaAtiva).conferencia.id}')
              .then((_) {
            if (!mounted) return;

            // Reseta a flag — permite navegar para uma nova
            // conferência ativa no futuro
            _navegouParaAtiva = false;

            // Recarrega a lista ao voltar — corrige Bug 4
            ref
                .read(conferenciaProvider.notifier)
                .carregarPorNota(widget.notaId);
          });
        }

        // Reseta flag quando volta para estados de lista
        if (next is ConferenciaListaCarregada ||
            next is ConferenciaVazio ||
            next is ConferenciaErro) {
          _navegouParaAtiva = false;
        }
      },
    );

    // ============================================================
    // Future.microtask — carrega dados APÓS o primeiro build()
    // ============================================================
    // Chamar carregarPorNota() diretamente no initState() pode
    // causar setState() durante build() — erro do Flutter.
    // Future.microtask() agenda a execução para o próximo microtask,
    // após o build() inicial, evitando esse conflito.
    Future.microtask(
      () => ref
          .read(conferenciaProvider.notifier)
          .carregarPorNota(widget.notaId),
    );
  }

  @override
  void dispose() {
    // OBRIGATÓRIO: fecha a subscription para evitar memory leak.
    // Sem isso, o listener continua ativo mesmo após a tela ser
    // removida da árvore de widgets.
    _sub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ref.watch() continua no build() — comportamento normal
    final state = ref.watch(conferenciaProvider);

    // notaDetalheProvider carrega os itens da nota para
    // iniciar uma nova conferência com as quantidades corretas
    final asyncNota = ref.watch(notaDetalheProvider(widget.notaId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conferências'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref
                .read(conferenciaProvider.notifier)
                .carregarPorNota(widget.notaId),
          ),
        ],
      ),
      body: switch (state) {
        ConferenciaInicial() || ConferenciaCarregando() =>
          const Center(child: CircularProgressIndicator()),

        ConferenciaVazio() => _EstadoVazio(
            onIniciar: () => _iniciarConferencia(asyncNota),
          ),

        ConferenciaListaCarregada(:final conferencias) =>
          _ListaConferencias(
            conferencias: conferencias,
            onIniciarNova: () => _iniciarConferencia(asyncNota),
          ),

        // ConferenciaAtiva é tratado pelo listener no initState
        // A tela mostra loading enquanto a navegação acontece
        ConferenciaAtiva() =>
          const Center(child: CircularProgressIndicator()),

        ConferenciaErro(:final mensagem) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
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
          ),
      },
    );
  }

  // Método auxiliar — extrai lógica de iniciar do build()
  void _iniciarConferencia(AsyncValue<dynamic> asyncNota) {
    asyncNota.whenData((nota) {
      final itensNota = nota.itens
          .map((i) => {
                'id': i.id,
                'quantidade': i.quantidade,
              })
          .toList();
      ref
          .read(conferenciaProvider.notifier)
          .iniciar(widget.notaId, itensNota);
    });
  }
}

// ============================================================
// LISTA DE CONFERÊNCIAS
// ============================================================
class _ListaConferencias extends StatelessWidget {
  final List<Conferencia> conferencias;
  final VoidCallback onIniciarNova;

  const _ListaConferencias({
    required this.conferencias,
    required this.onIniciarNova,
  });

  @override
  Widget build(BuildContext context) {
    // Permite nova conferência só se não houver nenhuma ativa
    final temAtivaOuEmAndamento = conferencias.any(
      (c) => !c.cancelada && !c.concluida,
    );

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
        if (!temAtivaOuEmAndamento)
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

// ============================================================
// CARD DE CONFERÊNCIA
// ============================================================
class _ConferenciaCard extends StatelessWidget {
  final Conferencia conferencia;

  const _ConferenciaCard({required this.conferencia});

  @override
  Widget build(BuildContext context) {
    final corStatus = switch (conferencia.status) {
      'concluida'            => Colors.green,
      'cancelada'            => Colors.grey,
      'pausada'              => Colors.orange,
      'aguardando_aprovacao' => Colors.amber,
      _                      => Theme.of(context).colorScheme.primary,
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
          '${conferencia.totalItensConferidos}/${conferencia.itens.length} itens'
          ' • ${_formatarData(conferencia.iniciadoEm)}',
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
    'em_andamento'         => 'Em andamento',
    'pausada'              => 'Pausada',
    'aguardando_aprovacao' => 'Aguardando aprovação',
    'concluida'            => 'Concluída',
    'cancelada'            => 'Cancelada',
    _                      => s,
  };

  String _formatarData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}

// ============================================================
// ESTADO VAZIO
// ============================================================
class _EstadoVazio extends StatelessWidget {
  final VoidCallback onIniciar;

  const _EstadoVazio({required this.onIniciar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
      ),
    );
  }
}