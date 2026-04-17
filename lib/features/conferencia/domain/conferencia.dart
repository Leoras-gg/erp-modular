// lib/features/conferencia/domain/conferencia.dart
//
// CAMADA: domain
// RESPONSABILIDADE: representar uma conferência física de mercadorias.
//
// ============================================================
// CONTEXTO DE NEGÓCIO
// ============================================================
// Uma conferência é o processo físico de verificar se os produtos
// que chegaram ao almoxarifado correspondem ao que está na nota fiscal.
// O operador pega a nota (já importada no sistema) e confere item a item,
// registrando as quantidades físicas encontradas.
//
// MÁQUINA DE ESTADOS (definida na Sessão 4, implementada aqui):
//
//   criada ──────────────────→ em_andamento
//   em_andamento ────────────→ pausada (qualquer operador pode pausar)
//   pausada ─────────────────→ em_andamento (qualquer operador retoma)
//   em_andamento ────────────→ aguardando_aprovacao (se houver divergência)
//   aguardando_aprovacao ────→ em_andamento (supervisor rejeita)
//   aguardando_aprovacao ────→ concluida (supervisor aprova)
//   em_andamento ────────────→ concluida (sem divergência)
//   em_andamento ────────────→ cancelada (operador cancela)
//   pausada ─────────────────→ cancelada (operador cancela)
//   concluida ───────────────→ reaberta → em_andamento (supervisor)
//
// CONCEITO: Finite State Machine (FSM) no domínio
// O método podeTransicionar() centraliza as regras de transição válidas.
// Nenhum outro código decide se uma transição é válida — só o domínio.

import 'conferencia_item.dart';

class Conferencia {
  final String id;
  final String empresaId;

  // Referência à nota fiscal sendo conferida
  final String notaId;

  // Status atual — uma das 8 strings da máquina de estados
  final String status;

  // Operador que está ou estava realizando a conferência
  final String operadorId;

  // Lista de itens desta conferência
  // Um item por ItemNota da nota fiscal vinculada
  final List<ConferenciaItem> itens;

  // Timestamps de ciclo de vida
  final DateTime iniciadoEm;
  final DateTime? concluidoEm;
  final DateTime? canceladoEm;
  final String? motivoCancelamento;

  // Dados de reabertura — preenchidos quando supervisor reabre
  final String? reabertoPortId;
  final DateTime? reabertoEm;
  final String? motivoReabertura;

  final DateTime? inativoEm;
  final DateTime criadoEm;

  const Conferencia({
    required this.id,
    required this.empresaId,
    required this.notaId,
    required this.status,
    required this.operadorId,
    required this.itens,
    required this.iniciadoEm,
    this.concluidoEm,
    this.canceladoEm,
    this.motivoCancelamento,
    this.reabertoPortId,
    this.reabertoEm,
    this.motivoReabertura,
    this.inativoEm,
    required this.criadoEm,
  });

  // ============================================================
  // PROPRIEDADES DERIVADAS — lógica de negócio no domínio
  // ============================================================

  bool get ativa =>
      status == 'criada' ||
      status == 'em_andamento' ||
      status == 'pausada' ||
      status == 'aguardando_aprovacao' ||
      status == 'reaberta';

  bool get concluida => status == 'concluida';
  bool get cancelada => status == 'cancelada';

  // Quantos itens já foram conferidos (quantidade bateu ou foi registrada)
  int get totalItensConferidos =>
      itens.where((i) => i.conferido || i.divergente).length;

  // Quantos itens ainda estão pendentes de conferência
  int get totalItensPendentes =>
      itens.where((i) => !i.conferido && !i.divergente).length;

  // Percentual geral de conclusão da conferência
  double get percentualConcluido =>
      itens.isEmpty ? 0 : totalItensConferidos / itens.length;

  // Existe algum item com divergência de quantidade
  bool get temDivergencia => itens.any((i) => i.divergente);

  // Todos os itens foram verificados (conferidos ou divergentes)
  bool get todosItensVerificados =>
      itens.isNotEmpty && itens.every((i) => i.conferido || i.divergente);

  // ============================================================
  // VALIDAÇÃO DE TRANSIÇÕES — core da máquina de estados
  // ============================================================
  // Retorna true se a transição para novoStatus é válida
  // a partir do status atual.
  // Conceito: o domínio protege suas invariantes — nenhuma
  // transição inválida pode ocorrer sem passar por aqui.
  bool podeTransicionar(String novoStatus) {
    return switch (status) {
      'criada'                => novoStatus == 'em_andamento' ||
                                 novoStatus == 'cancelada',
      'em_andamento'          => novoStatus == 'pausada' ||
                                 novoStatus == 'aguardando_aprovacao' ||
                                 novoStatus == 'concluida' ||
                                 novoStatus == 'cancelada',
      'pausada'               => novoStatus == 'em_andamento' ||
                                 novoStatus == 'cancelada',
      'aguardando_aprovacao'  => novoStatus == 'em_andamento' ||
                                 novoStatus == 'concluida',
      'concluida'             => novoStatus == 'reaberta',
      'reaberta'              => novoStatus == 'em_andamento',
      _                       => false, // cancelada não pode transicionar
    };
  }

  factory Conferencia.fromMap(
    Map<String, dynamic> map, {
    List<ConferenciaItem> itens = const [],
  }) {
    return Conferencia(
      id: map['id'] as String,
      empresaId: map['empresa_id'] as String,
      notaId: map['nota_id'] as String,
      status: map['status'] as String,
      operadorId: map['operador_id'] as String,
      itens: itens,
      iniciadoEm: DateTime.parse(map['iniciado_em'] as String),
      concluidoEm: map['concluido_em'] != null
          ? DateTime.parse(map['concluido_em'] as String)
          : null,
      canceladoEm: map['cancelado_em'] != null
          ? DateTime.parse(map['cancelado_em'] as String)
          : null,
      motivoCancelamento: map['motivo_cancelamento'] as String?,
      reabertoPortId: map['reaberto_por'] as String?,
      reabertoEm: map['reaberto_em'] != null
          ? DateTime.parse(map['reaberto_em'] as String)
          : null,
      motivoReabertura: map['motivo_reabertura'] as String?,
      inativoEm: map['inativo_em'] != null
          ? DateTime.parse(map['inativo_em'] as String)
          : null,
      criadoEm: DateTime.parse(map['criado_em'] as String),
    );
  }

  // toMap() sem 'id' — banco gera o UUID
  Map<String, dynamic> toMap() {
    return {
      'empresa_id': empresaId,
      'nota_id': notaId,
      'status': status,
      'operador_id': operadorId,
      'iniciado_em': iniciadoEm.toIso8601String(),
      'concluido_em': concluidoEm?.toIso8601String(),
      'cancelado_em': canceladoEm?.toIso8601String(),
      'motivo_cancelamento': motivoCancelamento,
      'reaberto_por': reabertoPortId,
      'reaberto_em': reabertoEm?.toIso8601String(),
      'motivo_reabertura': motivoReabertura,
      'inativo_em': inativoEm?.toIso8601String(),
      'criado_em': criadoEm.toIso8601String(),
    };
  }

  Conferencia copyWith({
    String? status,
    List<ConferenciaItem>? itens,
    DateTime? concluidoEm,
    DateTime? canceladoEm,
    String? motivoCancelamento,
  }) {
    return Conferencia(
      id: id,
      empresaId: empresaId,
      notaId: notaId,
      status: status ?? this.status,
      operadorId: operadorId,
      itens: itens ?? this.itens,
      iniciadoEm: iniciadoEm,
      concluidoEm: concluidoEm ?? this.concluidoEm,
      canceladoEm: canceladoEm ?? this.canceladoEm,
      motivoCancelamento: motivoCancelamento ?? this.motivoCancelamento,
      reabertoPortId: reabertoPortId,
      reabertoEm: reabertoEm,
      motivoReabertura: motivoReabertura,
      inativoEm: inativoEm,
      criadoEm: criadoEm,
    );
  }
}