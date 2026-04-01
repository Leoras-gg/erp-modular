// lib/features/estoque/domain/produto.dart
//
// CAMADA: domain
// RESPONSABILIDADE: representar um produto do estoque com todos
// os seus atributos de negócio. Esta classe não sabe nada sobre
// banco de dados, Flutter ou Supabase — é Dart puro.
//
// CONCEITOS POO APLICADOS:
// - Encapsulamento: todos os campos são final — imutável após criação
// - Factory Pattern: fromMap() centraliza criação a partir do banco
// - Composição: Produto contém List<String> de barcodes
// - Value Object: dois produtos com o mesmo id são o mesmo produto

class Produto {
  final String id;
  final String empresaId;

  // Identificação
  final String codigoInterno;
  final String nome;
  final String? descricao;

  // Unidade e medida
  // Exemplos: UN, KG, MT, RL (rolo), CX (caixa)
  final String unidadeMedida;

  // Fiscal
  // NCM: Nomenclatura Comum do Mercosul — 8 dígitos
  // CEST: Código Especificador da Substituição Tributária
  final String? ncm;
  final String? cest;

  // Preços — usando double por ora, ideal seria Decimal em produção
  final double precoCusto;
  final double precoVenda;

  // Estoque
  final double estoqueMinimo;
  final double quantidadeAtual;

  // Localização física no armazém
  // Exemplo: "Prateleira A3 — Corredor 2 — Armazém B"
  final String? localizacaoFisica;

  // URL da imagem no Supabase Storage
  final String? imagemUrl;

  // Se o produto aceita lotes reprocessados
  // Conceito de negócio: item que passou por reprocesso mantém
  // referência ao lote original para rastreabilidade completa
  final bool permiteReprocesso;

  // Lista de códigos de barras associados
  // Conceito de composição: Produto contém múltiplos barcodes
  // Um produto pode ter EAN-13, EAN-8, QR Code e código interno
  final List<String> barcodes;

  // Soft delete — null significa ativo, preenchido significa inativo
  // Conceito: nunca deletar registros com histórico de transações
  final DateTime? inativoEm;

  final DateTime criadoEm;

  // Construtor com todos os campos nomeados e obrigatórios
  // Conceito: impossível criar um Produto sem os dados essenciais
  const Produto({
    required this.id,
    required this.empresaId,
    required this.codigoInterno,
    required this.nome,
    this.descricao,
    required this.unidadeMedida,
    this.ncm,
    this.cest,
    required this.precoCusto,
    required this.precoVenda,
    required this.estoqueMinimo,
    required this.quantidadeAtual,
    this.localizacaoFisica,
    this.imagemUrl,
    required this.permiteReprocesso,
    required this.barcodes,
    this.inativoEm,
    required this.criadoEm,
  });

  // ============================================================
  // FACTORY PATTERN — fromMap
  // ============================================================
  // Cria um Produto a partir dos dados brutos do Supabase.
  // Quem chama este método não precisa saber como o banco
  // organiza os campos — recebe um Produto válido ou erro.
  //
  // O operador ?? fornece valor padrão quando o campo é null.
  // O operador as faz type casting seguro.
  factory Produto.fromMap(Map<String, dynamic> map) {
    return Produto(
      id: map['id'] as String,
      empresaId: map['empresa_id'] as String,
      codigoInterno: map['codigo_interno'] as String,
      nome: map['nome'] as String,
      descricao: map['descricao'] as String?,
      unidadeMedida: map['unidade_medida'] as String? ?? 'UN',
      ncm: map['ncm'] as String?,
      cest: map['cest'] as String?,
      precoCusto: (map['preco_custo'] as num?)?.toDouble() ?? 0.0,
      precoVenda: (map['preco_venda'] as num?)?.toDouble() ?? 0.0,
      estoqueMinimo: (map['estoque_minimo'] as num?)?.toDouble() ?? 0.0,
      quantidadeAtual: (map['quantidade_atual'] as num?)?.toDouble() ?? 0.0,
      localizacaoFisica: map['localizacao_fisica'] as String?,
      imagemUrl: map['imagem_url'] as String?,
      permiteReprocesso: map['permite_reprocesso'] as bool? ?? false,
      // barcodes vem como lista separada (JOIN com produto_barcodes)
      // Se não vier no map, assume lista vazia
      barcodes: (map['barcodes'] as List<dynamic>?)
              ?.map((b) => b.toString())
              .toList() ??
          [],
      inativoEm: map['inativo_em'] != null
          ? DateTime.parse(map['inativo_em'] as String)
          : null,
      criadoEm: DateTime.parse(map['criado_em'] as String),
    );
  }

  // ============================================================
  // toMap — serialização de volta para o banco
  // ============================================================
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'empresa_id': empresaId,
      'codigo_interno': codigoInterno,
      'nome': nome,
      'descricao': descricao,
      'unidade_medida': unidadeMedida,
      'ncm': ncm,
      'cest': cest,
      'preco_custo': precoCusto,
      'preco_venda': precoVenda,
      'estoque_minimo': estoqueMinimo,
      'quantidade_atual': quantidadeAtual,
      'localizacao_fisica': localizacaoFisica,
      'imagem_url': imagemUrl,
      'permite_reprocesso': permiteReprocesso,
      'inativo_em': inativoEm?.toIso8601String(),
      'criado_em': criadoEm.toIso8601String(),
    };
  }

  // ============================================================
  // PROPRIEDADES DERIVADAS — computed properties
  // ============================================================
  // Conceito: lógica de negócio encapsulada no domínio
  // A UI não decide se o estoque está baixo — o Produto decide

  // Produto está com estoque abaixo do mínimo configurado
  bool get estoqueBaixo => quantidadeAtual <= estoqueMinimo;

  // Produto está ativo (não foi soft deleted)
  bool get ativo => inativoEm == null;

  // ============================================================
  // IGUALDADE POR VALOR
  // ============================================================
  // Dois produtos com o mesmo id são o mesmo produto,
  // independente de quais outros campos diferem
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Produto && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Produto(id: $id, codigo: $codigoInterno, nome: $nome, '
      'qtd: $quantidadeAtual $unidadeMedida)';

  // ============================================================
  // copyWith — imutabilidade com atualização
  // ============================================================
  // Conceito: em vez de mutar o objeto, cria um novo com campos alterados.
  // Padrão muito usado com Riverpod para atualizar estado.
  // Exemplo: produto.copyWith(quantidadeAtual: novaQtd)
  Produto copyWith({
    String? id,
    String? empresaId,
    String? codigoInterno,
    String? nome,
    String? descricao,
    String? unidadeMedida,
    String? ncm,
    String? cest,
    double? precoCusto,
    double? precoVenda,
    double? estoqueMinimo,
    double? quantidadeAtual,
    String? localizacaoFisica,
    String? imagemUrl,
    bool? permiteReprocesso,
    List<String>? barcodes,
    DateTime? inativoEm,
    DateTime? criadoEm,
  }) {
    return Produto(
      id: id ?? this.id,
      empresaId: empresaId ?? this.empresaId,
      codigoInterno: codigoInterno ?? this.codigoInterno,
      nome: nome ?? this.nome,
      descricao: descricao ?? this.descricao,
      unidadeMedida: unidadeMedida ?? this.unidadeMedida,
      ncm: ncm ?? this.ncm,
      cest: cest ?? this.cest,
      precoCusto: precoCusto ?? this.precoCusto,
      precoVenda: precoVenda ?? this.precoVenda,
      estoqueMinimo: estoqueMinimo ?? this.estoqueMinimo,
      quantidadeAtual: quantidadeAtual ?? this.quantidadeAtual,
      localizacaoFisica: localizacaoFisica ?? this.localizacaoFisica,
      imagemUrl: imagemUrl ?? this.imagemUrl,
      permiteReprocesso: permiteReprocesso ?? this.permiteReprocesso,
      barcodes: barcodes ?? this.barcodes,
      inativoEm: inativoEm ?? this.inativoEm,
      criadoEm: criadoEm ?? this.criadoEm,
    );
  }
}