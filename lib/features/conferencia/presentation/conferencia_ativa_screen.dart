// lib/features/conferencia/presentation/conferencia_ativa_screen.dart
//
// CAMADA: presentation
// RESPONSABILIDADE: tela principal do processo de conferência física.
// O operador vê os itens da nota e registra as quantidades conferidas.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/conferencia_notifier.dart';
import '../domain/conferencia.dart';
import '../domain/conferencia_item.dart';

class ConferenciaAtivaScreen extends ConsumerWidget {
  final String conferenciaId;
  const ConferenciaAtivaScreen({super.key, required this.conferenciaId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conferenciaProvider);

    // Carrega a conferência ao abrir a tela
    ref.listen(conferenciaProvider, (_, _) {});

    // Inicializa se ainda não foi carregada
    if (state is ConferenciaInicial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(conferenciaProvider.notifier).abrirConferencia(conferenciaId);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conferência'),
        actions: [
          if (state is ConferenciaAtiva) ...[
            // Botão pausar — disponível quando em_andamento
            if (state.conferencia.status == 'em_andamento')
              IconButton(
                icon: const Icon(Icons.pause),
                tooltip: 'Pausar conferência',
                onPressed: () => ref
                    .read(conferenciaProvider.notifier)
                    .pausar(conferenciaId),
              ),
            // Botão retomar — disponível quando pausada
            if (state.conferencia.status == 'pausada')
              IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Retomar conferência',
                onPressed: () => ref
                    .read(conferenciaProvider.notifier)
                    .retomar(conferenciaId),
              ),
          ],
        ],
      ),
      body: switch (state) {
        ConferenciaInicial() || ConferenciaCarregando() =>
          const Center(child: CircularProgressIndicator()),

        ConferenciaAtiva(:final conferencia) =>
          _ConteudoConferencia(conferencia: conferencia),

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
                        .abrirConferencia(conferenciaId),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          ),

        _ => const Center(child: CircularProgressIndicator()),
      },
      // Botão de finalizar — aparece quando há itens verificados
      bottomNavigationBar: state is ConferenciaAtiva &&
              state.conferencia.ativa &&
              state.conferencia.status != 'pausada'
          ? _BarraAcoes(conferencia: state.conferencia)
          : null,
    );
  }
}

// ============================================================
// CONTEÚDO DA CONFERÊNCIA
// ============================================================
class _ConteudoConferencia extends StatelessWidget {
  final Conferencia conferencia;
  const _ConteudoConferencia({required this.conferencia});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Barra de progresso geral
        _BarraProgresso(conferencia: conferencia),

        // Lista de itens
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: conferencia.itens.length,
            itemBuilder: (context, index) {
              return _ItemConferenciaCard(
                item: conferencia.itens[index],
                conferenciaId: conferencia.id,
                bloqueado: conferencia.status == 'pausada' ||
                    conferencia.status == 'aguardando_aprovacao' ||
                    conferencia.concluida ||
                    conferencia.cancelada,
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================
// BARRA DE PROGRESSO
// ============================================================
class _BarraProgresso extends StatelessWidget {
  final Conferencia conferencia;
  const _BarraProgresso({required this.conferencia});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final total = conferencia.itens.length;
    final conferidos = conferencia.totalItensConferidos;
    final percentual = conferencia.percentualConcluido;

    // Cor do status
    final corStatus = switch (conferencia.status) {
      'pausada'              => Colors.orange,
      'aguardando_aprovacao' => Colors.amber,
      'concluida'            => Colors.green,
      'cancelada'            => Colors.grey,
      _                      => colorScheme.primary,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      color: colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$conferidos de $total itens conferidos',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: corStatus.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: corStatus.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _labelStatus(conferencia.status),
                  style: TextStyle(
                    color: corStatus,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Barra de progresso linear
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentual,
              minHeight: 8,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                conferencia.temDivergencia ? Colors.orange : corStatus,
              ),
            ),
          ),
          if (conferencia.temDivergencia) ...[
            const SizedBox(height: 4),
            Text(
              'Atenção: existem itens com divergência de quantidade',
              style: TextStyle(
                color: Colors.orange.shade700,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _labelStatus(String status) => switch (status) {
    'criada'               => 'Criada',
    'em_andamento'         => 'Em andamento',
    'pausada'              => 'Pausada',
    'divergente'           => 'Divergente',
    'aguardando_aprovacao' => 'Aguard. aprovação',
    'concluida'            => 'Concluída',
    'cancelada'            => 'Cancelada',
    _                      => status,
  };
}

// ============================================================
// CARD DE ITEM DA CONFERÊNCIA
// ============================================================
class _ItemConferenciaCard extends ConsumerStatefulWidget {
  final ConferenciaItem item;
  final String conferenciaId;
  final bool bloqueado;

  const _ItemConferenciaCard({
    required this.item,
    required this.conferenciaId,
    required this.bloqueado,
  });

  @override
  ConsumerState<_ItemConferenciaCard> createState() =>
      _ItemConferenciaCardState();
}

class _ItemConferenciaCardState
    extends ConsumerState<_ItemConferenciaCard> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // Preenche com a quantidade já conferida (se houver)
    _controller = TextEditingController(
      text: widget.item.quantidadeConferida > 0
          ? widget.item.quantidadeConferida.toString()
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirmar() {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return;

    final quantidade = double.tryParse(texto.replaceAll(',', '.'));
    if (quantidade == null || quantidade < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantidade inválida')),
      );
      return;
    }

    ref.read(conferenciaProvider.notifier).registrarItem(
          conferenciaId: widget.conferenciaId,
          conferenciaItemId: widget.item.id,
          quantidadeConferida: quantidade,
        );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final colorScheme = Theme.of(context).colorScheme;

    // Cor do card baseada no estado do item
    final corBorda = item.conferido
        ? Colors.green
        : item.divergente
            ? Colors.orange
            : colorScheme.outline;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: corBorda.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Ícone de status do item
                Icon(
                  item.conferido
                      ? Icons.check_circle
                      : item.divergente
                          ? Icons.warning_amber
                          : Icons.radio_button_unchecked,
                  color: item.conferido
                      ? Colors.green
                      : item.divergente
                          ? Colors.orange
                          : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Item ${item.notaItemId.substring(0, 8)}...',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Quantidade esperada vs conferida
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Esperado: ${item.quantidadeEsperada}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                      if (item.quantidadeConferida > 0)
                        Text(
                          'Conferido: ${item.quantidadeConferida}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: item.divergente
                                        ? Colors.orange
                                        : Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                    ],
                  ),
                ),

                // Campo de entrada da quantidade
                if (!widget.bloqueado)
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _controller,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: 'Qtd',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.check, size: 18),
                          onPressed: _confirmar,
                          tooltip: 'Confirmar quantidade',
                        ),
                      ),
                      onSubmitted: (_) => _confirmar(),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// BARRA DE AÇÕES — botões finalizar e cancelar
// ============================================================
class _BarraAcoes extends ConsumerWidget {
  final Conferencia conferencia;
  const _BarraAcoes({required this.conferencia});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Cancelar
            OutlinedButton(
              onPressed: () => _mostrarDialogoCancelar(context, ref),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 12),
            // Finalizar
            Expanded(
              child: FilledButton(
                onPressed: conferencia.todosItensVerificados
                    ? () => ref
                        .read(conferenciaProvider.notifier)
                        .tentarFinalizar(conferencia.id)
                    : null,
                child: Text(
                  conferencia.temDivergencia
                      ? 'Enviar para aprovação'
                      : 'Finalizar conferência',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoCancelar(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar conferência'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Informe o motivo do cancelamento:'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Motivo...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              ref.read(conferenciaProvider.notifier).cancelar(
                    conferencia.id,
                    controller.text.trim(),
                  );
              Navigator.pop(context); // volta para a lista
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Confirmar cancelamento'),
          ),
        ],
      ),
    );
  }
}