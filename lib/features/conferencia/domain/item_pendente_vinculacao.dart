// lib/features/conferencia/domain/item_pendente_vinculacao.dart
//
// CAMADA: domain
// RESPONSABILIDADE: representa um item da nota sem produto vinculado.
//
// VETOR TEMPORÁRIO EM MEMÓRIA:
// Existe apenas em tempo de execução dentro do VinculacaoNotifier.
// Não é persistido no banco — é uma estrutura de trabalho.
//
// CICLO DE VIDA:
//   1. VinculacaoNotifier detecta itens sem produto_id em nota_itens
//   2. Instancia esta classe com os dados da nota (para exibição)
//   3. Operador vincula → produtoVinculado é preenchido via copyWith
//   4. UPDATE é feito em nota_itens.produto_id (persistência real)
//   5. Ao fechar a tela, a lista em memória é descartada
//   6. Na próxima conferência da mesma nota, o vínculo já existe no banco

class ItemPendenteVinculacao {
  // IDs para operações no banco
  final String conferenciaItemId;
  final String notaItemId; // alvo do UPDATE nota_itens SET produto_id

  // Dados da nota — pré-carregados para exibição
  final String descricaoProduto;
  final String ncm;
  final String cfop;
  final String? codigoBarras;
  final double quantidade;
  final String unidadeMedida;
  final String? lote;

  // null = pendente | não-null = resolvido pelo operador
  final ProdutoVinculado? produtoVinculado;

  const ItemPendenteVinculacao({
    required this.conferenciaItemId,
    required this.notaItemId,
    required this.descricaoProduto,
    required this.ncm,
    required this.cfop,
    this.codigoBarras,
    required this.quantidade,
    required this.unidadeMedida,
    this.lote,
    this.produtoVinculado,
  });

  bool get pendente  => produtoVinculado == null;
  bool get vinculado => produtoVinculado != null;

  ItemPendenteVinculacao copyWith({
    ProdutoVinculado? produtoVinculado,
    bool limparVinculo = false,
  }) {
    return ItemPendenteVinculacao(
      conferenciaItemId: conferenciaItemId,
      notaItemId: notaItemId,
      descricaoProduto: descricaoProduto,
      ncm: ncm,
      cfop: cfop,
      codigoBarras: codigoBarras,
      quantidade: quantidade,
      unidadeMedida: unidadeMedida,
      lote: lote,
      produtoVinculado: limparVinculo
          ? null
          : (produtoVinculado ?? this.produtoVinculado),
    );
  }
}

// Dados mínimos do produto selecionado para exibição e persistência
class ProdutoVinculado {
  final String id;
  final String nome;
  final String codigoInterno;
  final String? barcode;
  final String unidadeMedida;

  const ProdutoVinculado({
    required this.id,
    required this.nome,
    required this.codigoInterno,
    this.barcode,
    required this.unidadeMedida,
  });

  factory ProdutoVinculado.fromMap(Map<String, dynamic> map) {
    return ProdutoVinculado(
      id: map['id'] as String,
      nome: map['nome'] as String,
      codigoInterno: map['codigo_interno'] as String,
      barcode: map['barcode'] as String?,
      unidadeMedida: map['unidade_medida'] as String,
    );
  }
}