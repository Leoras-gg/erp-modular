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

// lib/features/conferencia/presentation/conferencia_ativa_screen.dart
//
// REFATORAÇÃO: usa conferenciaAtivaProvider exclusivamente.
// Estado completamente isolado da lista de conferências.
// Ao voltar, este provider não interfere na lista.
//
// MELHORIA: _ItemConferenciaCard agora exibe descricao_produto
// em vez do ID parcial do notaItemId.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/vinculacao_notifier.dart';
import 'widgets/item_pendente_card.dart';
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
    // Usa o provider de conferência ATIVA — isolado da lista
    Future.microtask(() => ref
        .read(conferenciaAtivaProvider.notifier)
        .carregar(widget.conferenciaId));
  }

  @override
  Widget build(BuildContext context) {
    // Observa somente o provider ativo — sem interferência da lista
    final state = ref.watch(conferenciaAtivaProvider);

    // ============================================================
    // LISTENER: navega de volta automaticamente ao concluir
    // ============================================================
    // Quando a conferência é finalizada com sucesso, o estado muda
    // para ConferenciaAtivaCarregada com status='concluida'.
    // Neste momento: mostramos SnackBar de sucesso e fazemos pop().
    // Isso evita que a tela fique "presa" na conferência concluída
    // e resolve o loop de carregamento ao voltar para a lista.
    ref.listen<ConferenciaAtivaState>(conferenciaAtivaProvider, (prev, next) {
      if (next is ConferenciaAtivaCarregada &&
          next.conferencia.status == 'concluida' &&
          prev is! ConferenciaAtivaCarregada) {
        // Aguarda o frame atual terminar antes de navegar
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Conferência concluída com sucesso!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          // Pop automático — volta para a lista de conferências
          Navigator.of(context).pop();
        });
      }

      // Também navega de volta se for cancelada durante o uso
      if (next is ConferenciaAtivaCarregada &&
          next.conferencia.status == 'cancelada' &&
          (prev is ConferenciaAtivaCarregada &&
              prev.conferencia.status != 'cancelada')) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pop();
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conferência'),
        actions: [
          if (state is ConferenciaAtivaCarregada) ...[
            if (state.conferencia.status == 'em_andamento')
              IconButton(
                icon: const Icon(Icons.pause),
                tooltip: 'Pausar',
                onPressed: () => ref
                    .read(conferenciaAtivaProvider.notifier)
                    .pausar(widget.conferenciaId),
              ),
            if (state.conferencia.status == 'pausada')
              IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Retomar',
                onPressed: () => ref
                    .read(conferenciaAtivaProvider.notifier)
                    .retomar(widget.conferenciaId),
              ),
          ],
        ],
      ),
      body: switch (state) {
        ConferenciaAtivaInicial() || ConferenciaAtivaCarregando() =>
          const Center(child: CircularProgressIndicator()),

        ConferenciaAtivaCarregada(:final conferencia) =>
          _ConteudoConferencia(
            conferencia: conferencia,
            conferenciaId: widget.conferenciaId,
          ),

        ConferenciaAtivaErro(:final mensagem) => Center(
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
                        .read(conferenciaAtivaProvider.notifier)
                        .carregar(widget.conferenciaId),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          ),
      },
      bottomNavigationBar: state is ConferenciaAtivaCarregada &&
        state.conferencia.ativa &&
        state.conferencia.status == 'em_andamento'
    ? _BarraAcoes(
        conferencia: state.conferencia,
        temPendencias: () {
          final v = ref.read(
              vinculacaoProvider(widget.conferenciaId));
          if (v is VinculacaoCarregada) return !v.todosVinculados;
          return false;
        }(),
      )
    : null,
    );
  }
}

class _ConteudoConferencia extends ConsumerWidget {
  final Conferencia conferencia;
  final String conferenciaId;

  const _ConteudoConferencia({
    required this.conferencia,
    required this.conferenciaId,
  });

  

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vinculacaoState =
        ref.watch(vinculacaoProvider(conferenciaId));

    return Column(
      children: [
        _BarraProgresso(conferencia: conferencia),

        // Banner de pendências de vinculação
        if (vinculacaoState is VinculacaoCarregada)
          _BannerPendencias(
            totalPendentes: vinculacaoState.totalPendentes,
            todosVinculados: vinculacaoState.todosVinculados,
          ),

        Expanded(
          child: CustomScrollView(
            slivers: [
              // Seção de itens pendentes de vinculação
              if (vinculacaoState is VinculacaoCarregada &&
                  !vinculacaoState.todosVinculados) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      'Vincular itens (${vinculacaoState.totalPendentes})',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(
                              color: Colors.amber.shade800,
                              fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      child: ItemPendenteCard(
                        item: vinculacaoState.itens[i],
                        conferenciaId: conferenciaId,
                      ),
                    ),
                    childCount: vinculacaoState.itens.length,
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Divider(
                      height: 32, indent: 16, endIndent: 16),
                ),
              ],

              // Seção de itens a conferir
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Itens para conferir (${conferencia.itens.length})',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    child: _ItemConferenciaCard(
                      item: conferencia.itens[i],
                      conferenciaId: conferenciaId,
                      bloqueado:
                          conferencia.status != 'em_andamento',
                    ),
                  ),
                  childCount: conferencia.itens.length,
                ),
              ),
              const SliverToBoxAdapter(
                  child: SizedBox(height: 16)),
            ],
          ),
        ),
      ],
    );
  }
}

class _BarraProgresso extends StatelessWidget {
  final Conferencia conferencia;

  const _BarraProgresso({
    required this.conferencia,
  });

  @override
  Widget build(BuildContext context) {
    final total = conferencia.itens.length;
    final pendentes = conferencia.totalItensPendentes;
    final conferidos = total - pendentes;
    final progresso = total == 0 ? 0.0 : conferidos / total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: progresso),
          const SizedBox(height: 6),
          Text(
            '$conferidos de $total item(ns) conferidos',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _BannerPendencias extends StatelessWidget {
  final int totalPendentes;
  final bool todosVinculados;

  const _BannerPendencias({
    required this.totalPendentes,
    required this.todosVinculados,
  });

  @override
  Widget build(BuildContext context) {
    if (todosVinculados) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.green.shade50,
        child: Row(
          children: [
            Icon(Icons.check_circle,
                color: Colors.green.shade700, size: 16),
            const SizedBox(width: 8),
            Text('Todos os itens vinculados — pode finalizar',
                style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.amber.shade50,
      child: Row(
        children: [
          Icon(Icons.warning_amber,
              color: Colors.amber.shade800, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$totalPendentes item(ns) precisam ser vinculados antes de finalizar.',
              style: TextStyle(
                  color: Colors.amber.shade800,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

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
          ? _formatarQtd(widget.item.quantidadeConferida)
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatarQtd(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toString();

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
    ref.read(conferenciaAtivaProvider.notifier).registrarItem(
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
                  child: Text(
                    // CORREÇÃO: exibe o nome do produto em vez do ID
                    // descricaoProduto vem do JOIN com nota_itens no repositório
                    item.descricaoProduto ?? 'Item ${item.notaItemId.substring(0, 8)}...',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            // Chips fiscais quando disponíveis
            if (item.ncm != null || item.cfop != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  if (item.ncm != null)
                    _Chip(label: 'NCM', valor: item.ncm!),
                  if (item.cfop != null)
                    _Chip(label: 'CFOP', valor: item.cfop!),
                  if (item.codigoBarras != null)
                    _Chip(label: 'EAN', valor: item.codigoBarras!),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Esperado: ${_formatarQtd(item.quantidadeEsperada)}'
                        ' ${item.unidadeMedidaNota ?? ''}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                      if (item.quantidadeConferida > 0)
                        Text(
                          'Conferido: ${_formatarQtd(item.quantidadeConferida)}',
                          style: TextStyle(
                            color: item.divergente ? Colors.orange : Colors.green,
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

class _BarraAcoes extends ConsumerWidget {
  final Conferencia conferencia;
  final bool temPendencias;

  const _BarraAcoes({
    required this.conferencia,
    required this.temPendencias,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final podeFinalizar =
        !temPendencias && conferencia.todosItensVerificados;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 12),
        child: Row(
          children: [
            OutlinedButton(
              onPressed: () => _cancelar(context, ref),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: podeFinalizar
                    ? () => ref
                        .read(conferenciaAtivaProvider.notifier)
                        .tentarFinalizar(conferencia.id)
                    : null,
                child: Text(
                  temPendencias
                      ? 'Vincule os itens primeiro'
                      : conferencia.temDivergencia
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

  void _cancelar(BuildContext context, WidgetRef ref) {
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
              ref.read(conferenciaAtivaProvider.notifier).cancelar(
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
      child: Text(label,
          style: TextStyle(
              color: cor, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String valor;
  const _Chip({required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$label: $valor',
          style: Theme.of(context).textTheme.bodySmall),
    );
  }
}