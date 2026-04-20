// lib/features/conferencia/domain/conferencia_item.dart
//
// CAMADA: domain
// RESPONSABILIDADE: representar um item dentro de uma conferência.
//
// CONCEITO: cada ConferenciaItem corresponde a um ItemNota da nota fiscal.
// Ele rastreia quanto foi esperado (da nota) e quanto foi conferido
// fisicamente pelo operador no almoxarifado.
//
// RELAÇÃO COM ItemNota:
// ConferenciaItem NÃO herda de ItemNota — ele REFERENCIA um ItemNota.
// Isso é composição por referência: o ConferenciaItem sabe o ID do
// ItemNota correspondente, mas não duplica seus dados fiscais.
// Quando precisar exibir NCM ou descrição, busca via nota_item_id.
//
// INPUT do fromMap(): Map<String, dynamic> vindo do Supabase
// OUTPUT esperado: objeto imutável com dados de conferência do item

class ConferenciaItem {
  final String id;
  final String conferenciaId;

  // Referência ao item da nota fiscal correspondente
  // Via este ID buscamos descrição, NCM, CFOP, código de barras
  final String notaItemId;

  // Quantidade que a nota diz que deve estar chegando
  // Vem do campo 'quantidade' do ItemNota
  final double quantidadeEsperada;

  // Quantidade que o operador efetivamente contou fisicamente
  // Começa em 0 e é incrementada conforme o operador registra
  final double quantidadeConferida;

  // Observação opcional do operador (ex: "caixa amassada", "item faltante")
  final String? observacao;

  // Quando este item foi conferido pela última vez
  // null = ainda não conferido
  final DateTime? conferidoEm;

  final DateTime criadoEm;

  // Adiciona estes campos à classe ConferenciaItem:

  // Campos extras vindos do JOIN com nota_itens
  // São opcionais — só existem quando a conferência é carregada com JOIN
  // Conceito: dados de exibição trazidos junto para evitar N queries
  final String? descricaoProduto;
  final String? ncm;
  final String? cfop;
  final String? codigoBarras;
  final String? unidadeMedidaNota;

  const ConferenciaItem({
    required this.id,
    required this.conferenciaId,
    required this.notaItemId,
    required this.quantidadeEsperada,
    required this.quantidadeConferida,
    this.observacao,
    this.conferidoEm,
    required this.criadoEm,
    // Campos de exibição — opcionais
    this.descricaoProduto,
    this.ncm,
    this.cfop,
    this.codigoBarras,
    this.unidadeMedidaNota,
  });

  // ============================================================
  // PROPRIEDADES DERIVADAS — lógica de negócio no domínio
  // ============================================================

  // Item totalmente conferido: quantidade confere com o esperado
  bool get conferido => quantidadeConferida >= quantidadeEsperada;

  // Item com divergência: foi conferido mas quantidade não bate
  // Conceito: diferente de "não conferido" — divergente significa
  // que o operador olhou e encontrou quantidade diferente
  bool get divergente =>
      quantidadeConferida > 0 &&
      quantidadeConferida != quantidadeEsperada;

  // Quanto ainda falta conferir
  double get quantidadePendente =>
      (quantidadeEsperada - quantidadeConferida).clamp(0, double.infinity);

  // Percentual de conclusão do item (0.0 a 1.0)
  double get percentualConferido =>
      quantidadeEsperada > 0
          ? (quantidadeConferida / quantidadeEsperada).clamp(0.0, 1.0)
          : 0.0;

  factory ConferenciaItem.fromMap(Map<String, dynamic> map) {
    return ConferenciaItem(
      id: map['id'] as String,
      conferenciaId: map['conferencia_id'] as String,
      notaItemId: map['nota_item_id'] as String,
      quantidadeEsperada: (map['quantidade_esperada'] as num).toDouble(),
      quantidadeConferida:
          (map['quantidade_conferida'] as num?)?.toDouble() ?? 0,
      observacao: map['observacao'] as String?,
      conferidoEm: map['conferido_em'] != null
          ? DateTime.parse(map['conferido_em'] as String)
          : null,
      criadoEm: DateTime.parse(map['criado_em'] as String),
      // Campos extras do join
      descricaoProduto: map['descricao_produto'] as String?,
      ncm: map['ncm'] as String?,
      cfop: map['cfop'] as String?,
      codigoBarras: map['codigo_barras'] as String?,
      unidadeMedidaNota: map['unidade_medida_nota'] as String?,
    );
  }

  // toMap() sem 'id' — banco gera via gen_random_uuid()
  // REGRA: nunca incluir 'id' em INSERT quando UUID é gerado pelo banco
  Map<String, dynamic> toMap() {
    return {
      'conferencia_id': conferenciaId,
      'nota_item_id': notaItemId,
      'quantidade_esperada': quantidadeEsperada,
      'quantidade_conferida': quantidadeConferida,
      'observacao': observacao,
      'conferido_em': conferidoEm?.toIso8601String(),
      'criado_em': criadoEm.toIso8601String(),
    };
  }

  ConferenciaItem copyWith({
    double? quantidadeConferida,
    String? observacao,
    DateTime? conferidoEm,
  }) {
    return ConferenciaItem(
      id: id,
      conferenciaId: conferenciaId,
      notaItemId: notaItemId,
      quantidadeEsperada: quantidadeEsperada,
      quantidadeConferida: quantidadeConferida ?? this.quantidadeConferida,
      observacao: observacao ?? this.observacao,
      conferidoEm: conferidoEm ?? this.conferidoEm,
      criadoEm: criadoEm,
      
    );
  }
}