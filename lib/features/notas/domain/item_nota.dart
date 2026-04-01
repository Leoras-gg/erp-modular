// lib/features/notas/domain/item_nota.dart
//
// ============================================================
// CONTEXTO LEGAL — LEIA ANTES DE MODIFICAR
// ============================================================
// ItemNota representa um produto dentro de uma NF-e.
// No XML da NF-e, cada item está dentro da tag <det> (detalhe).
// Pode haver até 990 itens por nota (limitação do leiaute NF-e 4.0).
//
// CAMPOS FISCAIS CRÍTICOS:
//
// NCM — Nomenclatura Comum do Mercosul
//   8 dígitos que classificam o produto para fins tributários.
//   Determina as alíquotas de IPI, PIS, COFINS e ICMS.
//   Erros no NCM podem gerar autuações fiscais.
//   Exemplo: 73181500 = parafusos de ferro ou aço
//
// CFOP — Código Fiscal de Operações e Prestações
//   4 dígitos que identificam a natureza da operação fiscal.
//   Determina como a operação impacta créditos e débitos de ICMS.
//   Exemplos:
//     1102 — compra para industrialização (entrada, mesmo estado)
//     2102 — compra para industrialização (entrada, outro estado)
//     5102 — venda de produção do estabelecimento (saída)
//
// cEAN — Código de Barras EAN
//   EAN-13 (13 dígitos) ou EAN-8 (8 dígitos).
//   Pode ser 'SEM GTIN' quando o produto não tem código de barras.
//   Este campo é o elo entre o item da nota e o produto no estoque.
//
// qCom e uCom — Quantidade e Unidade Comercial
//   Quantidade e unidade como aparecem na nota (ex: 150 UN, 2,5 KG).
//   Pode diferir da unidade tributável (qTrib, uTrib) usada para cálculo de impostos.
//
// ATENÇÃO: os valores monetários no XML usam ponto como separador decimal
// e podem ter até 10 casas decimais. O parse deve tratar isso corretamente.

class ItemNota {
  // Identificador único do item no sistema
  final String id;

  // Referência à nota fiscal pai
  final String notaId;

  // Referência ao produto no catálogo (pode ser null se produto ainda não cadastrado)
  // Null = produto veio na nota mas não existe no sistema ainda
  final String? produtoId;

  // ============================================================
  // CAMPOS DIRETOS DO XML
  // ============================================================

  // Número sequencial do item na nota (1, 2, 3...)
  // Corresponde ao atributo nItem da tag <det> no XML
  final int numeroItem;

  // Código do produto no sistema do EMITENTE (não nosso código interno)
  // Corresponde à tag <cProd> no XML
  // Usado para localizar o produto no nosso catálogo por barcode ou código
  final String codigoProdutoEmitente;

  // Descrição do produto como vem na nota do fornecedor
  // Corresponde à tag <xProd> no XML
  final String descricaoProduto;

  // NCM — Nomenclatura Comum do Mercosul (8 dígitos)
  // Corresponde à tag <NCM> no XML
  // Campo crítico para tributação — ver contexto legal acima
  final String ncm;

  // CFOP — Código Fiscal de Operações
  // Corresponde à tag <CFOP> no XML
  // Campo crítico para escrituração fiscal — ver contexto legal acima
  final String cfop;

  // Código de barras EAN do produto
  // Corresponde à tag <cEAN> no XML
  // Pode ser 'SEM GTIN' para produtos sem código de barras
  final String? codigoBarras;

  // Número do lote do produto (quando informado pelo emitente)
  // Corresponde à tag <nLote> dentro de <rastro> no XML
  // Importante para rastreabilidade e controle de qualidade
  final String? lote;

  // Data de fabricação do lote (quando informada)
  // Corresponde à tag <dFab> dentro de <rastro> no XML
  final DateTime? dataFabricacao;

  // Data de validade do lote (quando informada)
  // Corresponde à tag <dVal> dentro de <rastro> no XML
  final DateTime? dataValidade;

  // ============================================================
  // QUANTIDADES E VALORES
  // ============================================================

  // Quantidade comercial — como aparece na nota
  // Corresponde à tag <qCom> no XML
  final double quantidade;

  // Unidade comercial (UN, KG, MT, CX, RL...)
  // Corresponde à tag <uCom> no XML
  final String unidadeMedida;

  // Valor unitário comercial
  // Corresponde à tag <vUnCom> no XML
  final double valorUnitario;

  // Valor total do item (quantidade * valorUnitario)
  // Corresponde à tag <vProd> no XML
  // Nota: pode haver descontos e acréscimos que alteram o valor final
  final double valorTotal;

  // ============================================================
  // CONTROLE DE CONFERÊNCIA
  // ============================================================

  // Quantidade efetivamente conferida pelo operador do almoxarifado
  // Começa em 0 e vai sendo incrementada conforme o leitor lê os itens
  final double quantidadeConferida;

  const ItemNota({
    required this.id,
    required this.notaId,
    this.produtoId,
    required this.numeroItem,
    required this.codigoProdutoEmitente,
    required this.descricaoProduto,
    required this.ncm,
    required this.cfop,
    this.codigoBarras,
    this.lote,
    this.dataFabricacao,
    this.dataValidade,
    required this.quantidade,
    required this.unidadeMedida,
    required this.valorUnitario,
    required this.valorTotal,
    this.quantidadeConferida = 0,
  });

  // Propriedades derivadas de conferência
  bool get conferido => quantidadeConferida >= quantidade;
  bool get divergente => quantidadeConferida > 0 && quantidadeConferida != quantidade;
  double get quantidadePendente => quantidade - quantidadeConferida;

  factory ItemNota.fromMap(Map<String, dynamic> map) {
    return ItemNota(
      id: map['id'] as String,
      notaId: map['nota_id'] as String,
      produtoId: map['produto_id'] as String?,
      numeroItem: map['numero_item'] as int,
      codigoProdutoEmitente: map['codigo_produto_emitente'] as String,
      descricaoProduto: map['descricao_produto'] as String,
      ncm: map['ncm'] as String,
      cfop: map['cfop'] as String,
      codigoBarras: map['codigo_barras'] as String?,
      lote: map['lote'] as String?,
      dataFabricacao: map['data_fabricacao'] != null
          ? DateTime.parse(map['data_fabricacao'] as String)
          : null,
      dataValidade: map['data_validade'] != null
          ? DateTime.parse(map['data_validade'] as String)
          : null,
      quantidade: (map['quantidade'] as num).toDouble(),
      unidadeMedida: map['unidade_medida'] as String,
      valorUnitario: (map['valor_unitario'] as num).toDouble(),
      valorTotal: (map['valor_total'] as num).toDouble(),
      quantidadeConferida: (map['quantidade_conferida'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nota_id': notaId,
      'produto_id': produtoId,
      'numero_item': numeroItem,
      'codigo_produto_emitente': codigoProdutoEmitente,
      'descricao_produto': descricaoProduto,
      'ncm': ncm,
      'cfop': cfop,
      'codigo_barras': codigoBarras,
      'lote': lote,
      'data_fabricacao': dataFabricacao?.toIso8601String(),
      'data_validade': dataValidade?.toIso8601String(),
      'quantidade': quantidade,
      'unidade_medida': unidadeMedida,
      'valor_unitario': valorUnitario,
      'valor_total': valorTotal,
      'quantidade_conferida': quantidadeConferida,
    };
  }

  ItemNota copyWith({
    String? produtoId,
    double? quantidadeConferida,
  }) {
    return ItemNota(
      id: id,
      notaId: notaId,
      produtoId: produtoId ?? this.produtoId,
      numeroItem: numeroItem,
      codigoProdutoEmitente: codigoProdutoEmitente,
      descricaoProduto: descricaoProduto,
      ncm: ncm,
      cfop: cfop,
      codigoBarras: codigoBarras,
      lote: lote,
      dataFabricacao: dataFabricacao,
      dataValidade: dataValidade,
      quantidade: quantidade,
      unidadeMedida: unidadeMedida,
      valorUnitario: valorUnitario,
      valorTotal: valorTotal,
      quantidadeConferida: quantidadeConferida ?? this.quantidadeConferida,
    );
  }
}