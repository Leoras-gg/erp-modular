// lib/features/conferencia/presentation/conferencias_gerais_screen.dart
//
// CAMADA: presentation
// RESPONSABILIDADE: lista TODAS as conferências de TODAS as notas,
// agrupadas por nota fiscal, com ID visível para rastreabilidade.
//
// Esta tela é o ponto central de operação do almoxarifado —
// o operador vê tudo que está em andamento, pausado ou pendente
// de aprovação sem precisar navegar por nota a nota.
//
// PROVIDER: FutureProvider simples — carrega uma vez, refresh manual.
// Sem family porque não há parâmetro — lista todas da empresa.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/conferencia.dart';
import '../domain/conferencia_item.dart';

// Provider que busca todas as conferências da empresa agrupadas por nota
final todasConferenciasProvider =
    FutureProvider.autoDispose<List<_GrupoNota>>((ref) async {
  final client = Supabase.instance.client;

  // Busca conferências com dados da nota fiscal para exibição
  final data = await client
      .from('conferencias')
      .select('''
        id, nota_id, status, iniciado_em, concluido_em, cancelado_em,
        notas_fiscais (numero, serie, emitente_nome, valor_total),
        conferencia_itens (id, quantidade_esperada, quantidade_conferida)
      ''')
      .isFilter('inativo_em', null)
      .order('iniciado_em', ascending: false);

  // Agrupa por nota_id
  final grupos = <String, _GrupoNota>{};

  for (final row in data as List) {
    final notaId = row['nota_id'] as String;
    final notaData = row['notas_fiscais'] as Map<String, dynamic>?;
    final itensData = row['conferencia_itens'] as List? ?? [];

    final itensConferidos =
        itensData.where((i) => (i['quantidade_conferida'] as num) > 0).length;

    final conf = _ConferenciaResumo(
      id: row['id'] as String,
      status: row['status'] as String,
      iniciadoEm: DateTime.parse(row['iniciado_em'] as String),
      concluidoEm: row['concluido_em'] != null
          ? DateTime.parse(row['concluido_em'] as String)
          : null,
      canceladoEm: row['cancelado_em'] != null
          ? DateTime.parse(row['cancelado_em'] as String)
          : null,
      totalItens: itensData.length,
      itensConferidos: itensConferidos,
    );

    if (grupos.containsKey(notaId)) {
      grupos[notaId]!.conferencias.add(conf);
    } else {
      grupos[notaId] = _GrupoNota(
        notaId: notaId,
        numero: notaData?['numero']?.toString() ?? '?',
        serie: notaData?['serie']?.toString() ?? '?',
        emitenteNome: notaData?['emitente_nome'] as String? ?? 'Fornecedor',
        valorTotal: (notaData?['valor_total'] as num?)?.toDouble() ?? 0,
        conferencias: [conf],
      );
    }
  }

  return grupos.values.toList();
});

// Modelos locais para agrupamento
class _GrupoNota {
  final String notaId;
  final String numero;
  final String serie;
  final String emitenteNome;
  final double valorTotal;
  final List<_ConferenciaResumo> conferencias;

  _GrupoNota({
    required this.notaId,
    required this.numero,
    required this.serie,
    required this.emitenteNome,
    required this.valorTotal,
    required this.conferencias,
  });

  // Tem alguma conferência ativa (não terminal)
  bool get temAtiva => conferencias.any(
      (c) => c.status != 'concluida' && c.status != 'cancelada');
}

class _ConferenciaResumo {
  final String id;
  final String status;
  final DateTime iniciadoEm;
  final DateTime? concluidoEm;
  final DateTime? canceladoEm;
  final int totalItens;
  final int itensConferidos;

  _ConferenciaResumo({
    required this.id,
    required this.status,
    required this.iniciadoEm,
    this.concluidoEm,
    this.canceladoEm,
    required this.totalItens,
    required this.itensConferidos,
  });

  bool get ativa =>
      status != 'concluida' && status != 'cancelada';

  // ID abreviado para exibição — primeiros 8 chars são suficientes
  // para identificação visual + busca
  String get idCurto => id.substring(0, 8).toUpperCase();
}

// ============================================================
// TELA PRINCIPAL
// ============================================================
class ConferenciasGeraisScreen extends ConsumerWidget {
  const ConferenciasGeraisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncGrupos = ref.watch(todasConferenciasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conferências'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(todasConferenciasProvider),
          ),
        ],
      ),
      body: switch (asyncGrupos) {
        AsyncLoading() =>
          const Center(child: CircularProgressIndicator()),

        AsyncError(:final error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline,
                      size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(error.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () =>
                        ref.invalidate(todasConferenciasProvider),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          ),

        AsyncData(:final value) when value.isEmpty => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_outlined,
                    size: 64,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant),
                const SizedBox(height: 16),
                const Text('Nenhuma conferência registrada',
                    style: TextStyle(fontSize: 18)),
                const SizedBox(height: 8),
                Text(
                  'As conferências aparecerão aqui após\n'
                  'serem iniciadas a partir das notas fiscais.',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

        AsyncData(:final value) => ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: value.length,
            itemBuilder: (ctx, i) =>
                _GrupoNotaCard(grupo: value[i]),
          ),
      },
    );
  }
}

// ============================================================
// CARD DE GRUPO (por nota fiscal)
// ============================================================
class _GrupoNotaCard extends StatelessWidget {
  final _GrupoNota grupo;

  const _GrupoNotaCard({required this.grupo});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho da nota
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.receipt_outlined,
                    size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NF-e ${grupo.numero} / Série ${grupo.serie}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        grupo.emitenteNome,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                                color: colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  'R\$ ${grupo.valorTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Conferências desta nota
          ...grupo.conferencias.map((conf) =>
              _ConferenciaResumoTile(conf: conf, notaId: grupo.notaId)),
        ],
      ),
    );
  }
}

// ============================================================
// TILE DE CONFERÊNCIA (dentro do card da nota)
// ============================================================
class _ConferenciaResumoTile extends StatelessWidget {
  final _ConferenciaResumo conf;
  final String notaId;

  const _ConferenciaResumoTile({
    required this.conf,
    required this.notaId,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final (cor, icone) = switch (conf.status) {
      'concluida'            => (Colors.green, Icons.check_circle),
      'cancelada'            => (Colors.grey, Icons.cancel),
      'pausada'              => (Colors.orange, Icons.pause_circle),
      'aguardando_aprovacao' => (Colors.amber, Icons.pending),
      _                      => (colorScheme.primary, Icons.assignment_outlined),
    };

    return InkWell(
      onTap: conf.ativa
          ? () => context.push('/conferencia/${conf.id}')
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Icon(icone, color: cor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _labelStatus(conf.status),
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: cor),
                      ),
                      const SizedBox(width: 8),
                      // ID visível para rastreabilidade
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '#${conf.idCurto}',
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
                  Text(
                    '${conf.itensConferidos}/${conf.totalItens} itens'
                    ' • ${_formatarData(conf.iniciadoEm)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            if (conf.ativa)
              const Icon(Icons.arrow_forward_ios, size: 14),
          ],
        ),
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