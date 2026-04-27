// lib/features/conferencia/presentation/conferencia_lista_screen.dart
//
// REFATORAÇÃO: agora usa conferenciaListaProvider exclusivamente.
// Não tem mais acesso ao estado da conferência ativa — isso é
// responsabilidade da ConferenciaAtivaScreen.
//
// FLUXO CORRIGIDO:
// 1. initState → listenManual em conferenciaListaProvider
// 2. iniciar() retorna o ID da nova conferência
// 3. navegamos diretamente com esse ID — sem depender de estado
// 4. ao voltar, recarregamos a lista — provider da lista está limpo

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

  @override
  void initState() {
    super.initState();
    // Carrega a lista ao entrar na tela
    Future.microtask(() => ref
        .read(conferenciaListaProvider.notifier)
        .carregar(widget.notaId));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(conferenciaListaProvider);
    final asyncNota = ref.watch(notaDetalheProvider(widget.notaId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conferências'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref
                .read(conferenciaListaProvider.notifier)
                .carregar(widget.notaId),
          ),
        ],
      ),
      body: switch (state) {
        ConferenciaListaInicial() || ConferenciaListaCarregando() =>
          const Center(child: CircularProgressIndicator()),

        ConferenciaListaVazio() => _EstadoVazio(
            onIniciar: () => _iniciar(asyncNota),
          ),

        ConferenciaListaCarregada(:final conferencias) =>
          _ListaConferencias(
            conferencias: conferencias,
            onIniciarNova: () => _iniciar(asyncNota),
          ),

        ConferenciaListaErro(:final mensagem) => Center(
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
                        .read(conferenciaListaProvider.notifier)
                        .carregar(widget.notaId),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          ),
      },
    );
  }

  // Inicia conferência e navega diretamente com o ID retornado
  // SEM depender de mudança de estado para disparar a navegação
  // Isso elimina o loop de push que existia antes
  Future<void> _iniciar(AsyncValue<dynamic> asyncNota) async {
    final notaData = ref.read(notaDetalheProvider(widget.notaId));

    await notaData.when(
      loading: () async {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Carregando nota, aguarde...')),
        );
      },
      error: (e, _) async {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar nota: $e'),
            backgroundColor: Colors.red,
          ),
        );
      },
      data: (nota) async {
        final itensNota = nota.itens
            .map((i) => {'id': i.id, 'quantidade': i.quantidade})
            .toList();

        // iniciar() retorna o ID da nova conferência
        final conferenciaId = await ref
            .read(conferenciaListaProvider.notifier)
            .iniciar(widget.notaId, itensNota);

        if (conferenciaId != null && mounted) {
          // Navega diretamente com o ID — sem listener de estado
          await context.push('/conferencia/$conferenciaId');
          // Ao voltar, recarrega a lista
          if (mounted) {
            ref
                .read(conferenciaListaProvider.notifier)
                .carregar(widget.notaId);
          }
        }
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
    final temAtivaOuEmAndamento =
        conferencias.any((c) => !c.cancelada && !c.concluida);

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: conferencias.length,
            itemBuilder: (context, i) => _ConferenciaCard(
              conferencia: conferencias[i],
              onTap: () async {
                await context.push('/conferencia/${conferencias[i].id}');
                // Recarrega ao voltar de qualquer conferência
              },
            ),
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

class _ConferenciaCard extends StatelessWidget {
  final Conferencia conferencia;
  final VoidCallback onTap;

  const _ConferenciaCard({
    required this.conferencia,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final corStatus = switch (conferencia.status) {
      'concluida'            => Colors.green,
      'cancelada'            => Colors.grey,
      'pausada'              => Colors.orange,
      'aguardando_aprovacao' => Colors.amber,
      _                      => colorScheme.primary,
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
        // Título com status + ID abreviado
        title: Row(
          children: [
            Text(
              _labelStatus(conferencia.status),
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: corStatus),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '#${conferencia.id.substring(0, 8).toUpperCase()}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${conferencia.totalItensConferidos}/${conferencia.itens.length} itens'
          ' • ${_formatarData(conferencia.iniciadoEm)}',
        ),
        trailing: conferencia.ativa
            ? const Icon(Icons.arrow_forward_ios, size: 16)
            : null,
        onTap: conferencia.ativa ? onTap : null,
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
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

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
      ),
    );
  }
}