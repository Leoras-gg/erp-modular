// lib/features/estoque/domain/movimentacao.dart
//
// CAMADA: domain
// RESPONSABILIDADE: representa uma movimentação de estoque.
//
// IMUTABILIDADE:
// Movimentações são registros permanentes de auditoria.
// Uma vez criada, nunca é alterada nem deletada.
// Para corrigir um erro, cria-se uma movimentação de ajuste
// compensatória — o histórico permanece intacto.
// Por isso NÃO tem inativo_em nem copyWith.
//
// CAMPOS DE EXIBIÇÃO (nomeProduto, codigoBarrasProduto, unidadeMedida):
// Vêm do JOIN com a tabela produtos ao buscar o histórico.
// São opcionais — preenchidos apenas quando a query inclui JOIN.
// Evitam N queries adicionais na listagem de histórico.

class Movimentacao {
  final String id;
  final String empresaId;
  final String produtoId;

  // 'entrada' | 'saida' | 'ajuste'
  final String tipo;

  // Quantidade movimentada — sempre positiva
  // O tipo e a variação de saldo indicam a direção
  final double quantidade;

  // Saldo imediatamente antes e depois desta movimentação
  // Permite reconstruir o histórico mesmo se quantidade_atual mudar
  final double saldoAnterior;
  final double saldoPosterior;

  // 'conferencia' | 'manual' | 'ajuste'
  final String origem;

  // Referências opcionais à origem
  final String? conferenciaId;
  final String? notaId;

  // Rastreabilidade de lote
  final String? lote;
  final String? observacao;

  final String operadorId;
  final DateTime criadoEm;

  // ---- Campos de exibição (JOIN com produtos) ----
  final String? nomeProduto;
  final String? codigoBarrasProduto;
  final String? unidadeMedida;

  const Movimentacao({
    required this.id,
    required this.empresaId,
    required this.produtoId,
    required this.tipo,
    required this.quantidade,
    required this.saldoAnterior,
    required this.saldoPosterior,
    required this.origem,
    this.conferenciaId,
    this.notaId,
    this.lote,
    this.observacao,
    required this.operadorId,
    required this.criadoEm,
    this.nomeProduto,
    this.codigoBarrasProduto,
    this.unidadeMedida,
  });

  // Variação de saldo — positivo = entrada, negativo = saída
  double get variacao => saldoPosterior - saldoAnterior;

  bool get ehEntrada => variacao > 0;

  factory Movimentacao.fromMap(Map<String, dynamic> map) {
    return Movimentacao(
      id: map['id'] as String,
      empresaId: map['empresa_id'] as String,
      produtoId: map['produto_id'] as String,
      tipo: map['tipo'] as String,
      quantidade: (map['quantidade'] as num).toDouble(),
      saldoAnterior: (map['saldo_anterior'] as num).toDouble(),
      saldoPosterior: (map['saldo_posterior'] as num).toDouble(),
      origem: map['origem'] as String,
      conferenciaId: map['conferencia_id'] as String?,
      notaId: map['nota_id'] as String?,
      lote: map['lote'] as String?,
      observacao: map['observacao'] as String?,
      operadorId: map['operador_id'] as String,
      criadoEm: DateTime.parse(map['criado_em'] as String),
      nomeProduto: map['nome_produto'] as String?,
      codigoBarrasProduto: map['codigo_barras_produto'] as String?,
      unidadeMedida: map['unidade_medida'] as String?,
    );
  }

  // toMap() sem 'id' — banco gera via gen_random_uuid()
  // Só para INSERT — movimentações são imutáveis
  Map<String, dynamic> toMap() {
    return {
      'empresa_id': empresaId,
      'produto_id': produtoId,
      'tipo': tipo,
      'quantidade': quantidade,
      'saldo_anterior': saldoAnterior,
      'saldo_posterior': saldoPosterior,
      'origem': origem,
      'conferencia_id': conferenciaId,
      'nota_id': notaId,
      'lote': lote,
      'observacao': observacao,
      'operador_id': operadorId,
      'criado_em': criadoEm.toIso8601String(),
    };
  }
}