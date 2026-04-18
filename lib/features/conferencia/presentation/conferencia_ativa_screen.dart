// lib/features/conferencia/presentation/conferencia_ativa_screen.dart
//
// CAMADA: presentation
// RESPONSABILIDADE: tela principal do processo de conferência física.
//
// CORREÇÃO DE BUG IMPORTANTE:
// Antes, a tela só chamava abrirConferencia() quando o estado global
// era ConferenciaInicial.
// Isso é frágil porque o mesmo provider estava sendo usado também
// pela tela de lista.
// Resultado: ao abrir a tela ativa, o provider podia estar em
// ConferenciaListaCarregada, e a carga da conferência nunca acontecia.
//
// SOLUÇÃO:
// - transformar em ConsumerStatefulWidget
// - carregar a conferência em initState()
// - recarregar se o conferenciaId mudar
// - remover side effects do build()

// CORREÇÃO APLICADA:
// O carregamento inicial foi movido para initState() com
// Future.microtask(), evitando o padrão problemático de chamar
// métodos no build() para carregar dados.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/conferencia_notifier.dart';
import '../domain/conferencia.dart';
import '../domain/conferencia_item.dart';

class ConferenciaAtivaScreen extends ConsumerStatefulWidget {
  final String conferenciaId;

  const ConferenciaAtivaScreen({super.key, required this.conferenciaId});

  @override
  ConsumerState<ConferenciaAtivaScreen> createState() =>
      _ConferenciaAtivaScreenState();
}

class _ConferenciaAtivaScreenState
    extends ConsumerState<ConferenciaAtivaScreen> {

  @override
  void initState() {
    super.initState();
    // Carrega a conferência uma única vez ao abrir a tela
    // Future.microtask() garante que roda após o primeiro build()
    Future.microtask(() => ref
        .read(conferenciaProvider.notifier)
        .abrirConferencia(widget.conferenciaId));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(conferenciaProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conferência'),
        actions: [
          if (state is ConferenciaAtiva) ...[
            if (state.conferencia.status == 'em_andamento')
              IconButton(
                icon: const Icon(Icons.pause),
                tooltip: 'Pausar',
                onPressed: () => ref
                    .read(conferenciaProvider.notifier)
                    .pausar(widget.conferenciaId),
              ),
            if (state.conferencia.status == 'pausada')
              IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Retomar',
                onPressed: () => ref
                    .read(conferenciaProvider.notifier)
                    .retomar(widget.conferenciaId),
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
                        .abrirConferencia(widget.conferenciaId),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          ),

        _ => const Center(child: CircularProgressIndicator()),
      },
      bottomNavigationBar: state is ConferenciaAtiva &&
              state.conferencia.ativa &&
              state.conferencia.status == 'em_andamento'
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
        _BarraProgresso(conferencia: conferencia),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: conferencia.itens.length,
            itemBuilder: (context, index) => _ItemConferenciaCard(
              item: conferencia.itens[index],
              conferenciaId: conferencia.id,
              bloqueado: conferencia.status != 'em_andamento',
            ),
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
                '$conferidos de $total itens',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              _BadgeStatus(status: conferencia.status),
            ],
          ),
          const SizedBox(height: 8),
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
              style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// CARD DE ITEM
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
    _controller = TextEditingController(
      text: widget.item.quantidadeConferida > 0
          ? widget.item.quantidadeConferida.toStringAsFixed(
              widget.item.quantidadeConferida ==
                      widget.item.quantidadeConferida.truncate()
                  ? 0
                  : 2)
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirmar() {
    final texto = _controller.text.trim().replaceAll(',', '.');
    if (texto.isEmpty) return;

    final quantidade = double.tryParse(texto);
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
                  // Exibe ID parcial do item enquanto a tela de detalhe
                  // não resolve o nome completo via nota_item_id
                  child: Text(
                    'Item ${item.notaItemId.substring(0, 8)}...',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                          style: TextStyle(
                            color: item.divergente
                                ? Colors.orange
                                : Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!widget.bloqueado)
                  SizedBox(
                    width: 110,
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
                          tooltip: 'Confirmar',
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
// BARRA DE AÇÕES — Finalizar e Cancelar
// ============================================================
class _BarraAcoes extends ConsumerWidget {
  final Conferencia conferencia;

  const _BarraAcoes({required this.conferencia});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final podeFinalizar = conferencia.todosItensVerificados;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            OutlinedButton(
              onPressed: () => _mostrarDialogoCancelar(context, ref),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: podeFinalizar
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
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BADGE DE STATUS — privado ao arquivo
// ============================================================
class _BadgeStatus extends StatelessWidget {
  final String status;

  const _BadgeStatus({required this.status});

  @override
  Widget build(BuildContext context) {
    final (cor, label) = switch (status) {
      'em_andamento'         => (Colors.blue, 'Em andamento'),
      'pausada'              => (Colors.orange, 'Pausada'),
      'aguardando_aprovacao' => (Colors.amber, 'Aguard. aprovação'),
      'concluida'            => (Colors.green, 'Concluída'),
      'cancelada'            => (Colors.grey, 'Cancelada'),
      _                      => (Colors.grey, status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
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