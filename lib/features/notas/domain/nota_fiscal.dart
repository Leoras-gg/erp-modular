// lib/features/notas/domain/nota_fiscal.dart
//
// ============================================================
// CONTEXTO LEGAL — LEIA ANTES DE MODIFICAR
// ============================================================
// NotaFiscal representa especificamente a NF-e (modelo 55).
// Estende DocumentoFiscal adicionando campos específicos da NF-e.
//
// HERANÇA APLICADA:
// DocumentoFiscal (campos comuns a qualquer doc fiscal)
//   └── NotaFiscal (campos específicos da NF-e)
//
// DADOS DO EMITENTE:
// O emitente é quem emite a nota — o fornecedor na compra,
// a própria empresa na venda. O CNPJ do emitente é parte da
// chave de acesso e tem valor legal.
//
// FACTORY fromXml():
// Este é o método mais crítico desta classe. Ele recebe o
// conteúdo do arquivo XML e extrai todos os campos necessários.
// O parse segue o leiaute da NF-e versão 4.0.
//
// NAMESPACE DO XML:
// O XML da NF-e usa o namespace:
//   http://www.portalfiscal.inf.br/nfe
// Todas as tags estão dentro deste namespace.
// O parser deve considerar isso ao navegar a árvore XML.

import 'package:xml/xml.dart';
import 'documento_fiscal.dart';
import 'item_nota.dart';

class NotaFiscal extends DocumentoFiscal {
  // ============================================================
  // DADOS DO EMITENTE
  // ============================================================

  // CNPJ do emitente (14 dígitos, sem pontuação)
  // Corresponde à tag <CNPJ> dentro de <emit> no XML
  final String emitenteCnpj;

  // Razão social ou nome fantasia do emitente
  // Corresponde à tag <xNome> dentro de <emit> no XML
  final String emitenteNome;

  // UF do emitente (ex: SP, RJ, MG)
  // Corresponde à tag <UF> dentro de <enderEmit> no XML
  // Importante: determina qual SEFAZ autorizou a nota
  final String emitenteUf;

  // ============================================================
  // ITENS DA NOTA
  // ============================================================
  // Lista de produtos que compõem esta nota.
  // Composição: NotaFiscal contém List<ItemNota>
  // Cada ItemNota corresponde a uma tag <det> no XML
  final List<ItemNota> itens;

  const NotaFiscal({
    required super.id,
    required super.empresaId,
    required super.chaveAcesso,
    required super.numero,
    required super.serie,
    required super.tipo,
    required super.status,
    required super.dataEmissao,
    required super.valorTotal,
    super.xmlUrl,
    super.inativoEm,
    required super.criadoEm,
    required this.emitenteCnpj,
    required this.emitenteNome,
    required this.emitenteUf,
    required this.itens,
  });

  // ============================================================
  // FACTORY fromMap — cria NotaFiscal a partir do banco
  // ============================================================
  factory NotaFiscal.fromMap(
    Map<String, dynamic> map, {
    List<ItemNota> itens = const [],
  }) {
    return NotaFiscal(
      id: map['id'] as String,
      empresaId: map['empresa_id'] as String,
      chaveAcesso: map['chave_acesso'] as String,
      numero: map['numero'] as String,
      serie: map['serie'] as String,
      tipo: map['tipo'] as String,
      status: map['status'] as String,
      dataEmissao: DateTime.parse(map['data_emissao'] as String),
      valorTotal: (map['valor_total'] as num).toDouble(),
      xmlUrl: map['xml_url'] as String?,
      inativoEm: map['inativo_em'] != null
          ? DateTime.parse(map['inativo_em'] as String)
          : null,
      criadoEm: DateTime.parse(map['criado_em'] as String),
      emitenteCnpj: map['emitente_cnpj'] as String,
      emitenteNome: map['emitente_nome'] as String,
      emitenteUf: map['emitente_uf'] as String,
      itens: itens,
    );
  }

  // ============================================================
  // FACTORY fromXml — MÉTODO MAIS CRÍTICO DA CLASSE
  // ============================================================
  // Recebe o conteúdo bruto do arquivo XML da NF-e e extrai
  // todos os campos necessários para o sistema.
  //
  // ESTRUTURA DO XML NF-e (simplificada):
  //
  // <nfeProc>              ← raiz quando é XML com protocolo de autorização
  //   <NFe>
  //     <infNFe>           ← informações principais da nota
  //       <ide>            ← identificação da nota
  //         <cNF>          ← código numérico (parte da chave)
  //         <nNF>          ← número da nota
  //         <serie>        ← série
  //         <dhEmi>        ← data/hora de emissão
  //         <tpNF>         ← tipo: 0=entrada, 1=saída
  //       </ide>
  //       <emit>           ← dados do emitente
  //         <CNPJ>         ← CNPJ do emitente
  //         <xNome>        ← razão social
  //         <enderEmit>
  //           <UF>         ← estado
  //         </enderEmit>
  //       </emit>
  //       <total>          ← totais da nota
  //         <ICMSTot>
  //           <vNF>        ← valor total da nota
  //         </ICMSTot>
  //       </total>
  //       <det nItem="1">  ← item 1 (repete para cada produto)
  //         <prod>
  //           <cProd>      ← código do produto no emitente
  //           <cEAN>       ← código de barras EAN
  //           <xProd>      ← descrição do produto
  //           <NCM>        ← NCM do produto
  //           <CFOP>       ← CFOP da operação
  //           <uCom>       ← unidade comercial
  //           <qCom>       ← quantidade comercial
  //           <vUnCom>     ← valor unitário
  //           <vProd>      ← valor total do item
  //           <rastro>     ← informações de lote (quando presente)
  //             <nLote>    ← número do lote
  //             <dFab>     ← data de fabricação (AAAA-MM-DD)
  //             <dVal>     ← data de validade (AAAA-MM-DD)
  //           </rastro>
  //         </prod>
  //       </det>
  //     </infNFe>
  //   </NFe>
  //   <protNFe>            ← protocolo de autorização da SEFAZ
  //     <infProt>
  //       <chNFe>          ← chave de acesso (44 dígitos)
  //       <dhRecbto>       ← data/hora de autorização
  //       <nProt>          ← número do protocolo
  //       <cStat>          ← código do status (100 = autorizada)
  //     </infProt>
  //   </protNFe>
  // </nfeProc>
  //
  // IMPORTANTE: O XML pode vir como <nfeProc> (com protocolo)
  // ou como <NFe> diretamente (sem protocolo — contingência).
  // O parser deve tratar ambos os casos.
  static NotaFiscal fromXml(String xmlContent, String empresaId) {
    // Parseia o conteúdo XML em uma árvore de nós
    final document = XmlDocument.parse(xmlContent);

    // ---- Localiza a raiz correta ----
    // O XML pode ter dois formatos:
    // 1. <nfeProc> quando vem com protocolo de autorização (mais comum)
    // 2. <NFe> quando vem sem protocolo (contingência ou download direto)
    final raiz = document.rootElement;

    // Localiza o nó <infNFe> — contém todas as informações da nota
    // findElements busca filhos diretos, findAllElements busca em toda a árvore
    final infNFe = raiz.findAllElements('infNFe').first;

    // ============================================================
    // EXTRAÇÃO DA CHAVE DE ACESSO
    // ============================================================
    // A chave fica no atributo Id da tag <infNFe>
    // Formato: "NFe" + 44 dígitos
    // Removemos o prefixo "NFe" para ficar só com os 44 dígitos
    final idAtributo = infNFe.getAttribute('Id') ?? '';
    final chaveAcesso = idAtributo.replaceFirst('NFe', '');

    // Validação básica da chave — deve ter exatamente 44 dígitos
    if (chaveAcesso.length != 44) {
      throw FormatException(
        'Chave de acesso inválida: esperado 44 dígitos, '
        'encontrado ${chaveAcesso.length}. '
        'Verifique se o arquivo XML é uma NF-e válida.',
      );
    }

    // ============================================================
    // IDENTIFICAÇÃO DA NOTA (<ide>)
    // ============================================================
    final ide = infNFe.findElements('ide').first;

    final numero = _texto(ide, 'nNF');
    final serie = _texto(ide, 'serie');

    // tpNF: 0 = entrada (compra), 1 = saída (venda)
    // Convertemos para string descritiva para facilitar leitura no sistema
    final tpNF = _texto(ide, 'tpNF');
    final tipo = tpNF == '0' ? 'entrada' : 'saida';

    // dhEmi: data e hora de emissão no formato ISO 8601
    // Exemplo: 2024-03-15T14:30:00-03:00
    // DateTime.parse lida com o timezone automaticamente
    final dhEmi = _texto(ide, 'dhEmi');
    final dataEmissao = DateTime.parse(dhEmi);

    // ============================================================
    // DADOS DO EMITENTE (<emit>)
    // ============================================================
    final emit = infNFe.findElements('emit').first;

    // CNPJ pode ter 14 dígitos (pessoa jurídica) ou CPF com 11 dígitos
    // Para NF-e de empresa, sempre será CNPJ
    final emitenteCnpj = _textoOpcional(emit, 'CNPJ') ??
        _textoOpcional(emit, 'CPF') ?? '';
    final emitenteNome = _texto(emit, 'xNome');

    // UF fica dentro de <enderEmit>
    final enderEmit = emit.findElements('enderEmit').first;
    final emitenteUf = _texto(enderEmit, 'UF');

    // ============================================================
    // VALOR TOTAL DA NOTA (<total>/<ICMSTot>/<vNF>)
    // ============================================================
    final total = infNFe.findElements('total').first;
    final icmsTot = total.findElements('ICMSTot').first;
    final valorTotal = double.parse(_texto(icmsTot, 'vNF'));

    // ============================================================
    // ITENS DA NOTA (<det>)
    // ============================================================
    // Cada tag <det> representa um produto na nota
    // O atributo nItem indica o número sequencial do item
    final detElements = infNFe.findElements('det');
    final itens = detElements.map((det) {
      return _parsearItem(det, ''); // notaId será preenchido ao salvar
    }).toList();

    // ============================================================
    // MONTAGEM DO OBJETO NotaFiscal
    // ============================================================
    // O id será gerado pelo banco (gen_random_uuid())
    // criadoEm será preenchido pelo banco (default now())
    // Usamos valores temporários que serão substituídos ao salvar
    return NotaFiscal(
      id: '', // será preenchido pelo banco
      empresaId: empresaId,
      chaveAcesso: chaveAcesso,
      numero: numero,
      serie: serie,
      tipo: tipo,
      status: 'importada', // status inicial sempre 'importada'
      dataEmissao: dataEmissao,
      valorTotal: valorTotal,
      xmlUrl: null, // será preenchido após upload do XML ao Storage
      criadoEm: DateTime.now(),
      emitenteCnpj: emitenteCnpj,
      emitenteNome: emitenteNome,
      emitenteUf: emitenteUf,
      itens: itens,
    );
  }

  // ============================================================
  // MÉTODO PRIVADO — parse de um item (<det>)
  // ============================================================
  static ItemNota _parsearItem(XmlElement det, String notaId) {
    final nItem = int.parse(det.getAttribute('nItem') ?? '0');
    final prod = det.findElements('prod').first;

    final codigoProdutoEmitente = _texto(prod, 'cProd');
    final descricaoProduto = _texto(prod, 'xProd');
    final ncm = _texto(prod, 'NCM');
    final cfop = _texto(prod, 'CFOP');
    final unidadeMedida = _texto(prod, 'uCom');
    final quantidade = double.parse(_texto(prod, 'qCom'));
    final valorUnitario = double.parse(_texto(prod, 'vUnCom'));
    final valorTotal = double.parse(_texto(prod, 'vProd'));

    // cEAN pode ser 'SEM GTIN' quando o produto não tem código de barras
    final cEAN = _textoOpcional(prod, 'cEAN');
    final codigoBarras = (cEAN == null || cEAN == 'SEM GTIN') ? null : cEAN;

    // ---- Dados de lote (<rastro>) ----
    // A tag <rastro> é opcional — só presente quando o emitente
    // informa dados de rastreabilidade (lote, validade)
    String? lote;
    DateTime? dataFabricacao;
    DateTime? dataValidade;

    final rastros = prod.findElements('rastro');
    if (rastros.isNotEmpty) {
      // Pega o primeiro rastro (pode haver múltiplos em casos específicos)
      final rastro = rastros.first;
      lote = _textoOpcional(rastro, 'nLote');

      // Datas no formato AAAA-MM-DD
      final dFab = _textoOpcional(rastro, 'dFab');
      if (dFab != null) dataFabricacao = DateTime.parse(dFab);

      final dVal = _textoOpcional(rastro, 'dVal');
      if (dVal != null) dataValidade = DateTime.parse(dVal);
    }

    return ItemNota(
      id: '', // será gerado pelo banco
      notaId: notaId,
      numeroItem: nItem,
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
    );
  }

  // ============================================================
  // MÉTODOS AUXILIARES DE EXTRAÇÃO DE TEXTO
  // ============================================================

  // Extrai texto de uma tag filha — lança erro se não encontrar
  static String _texto(XmlElement parent, String tag) {
    final elements = parent.findElements(tag);
    if (elements.isEmpty) {
      throw FormatException(
        'Tag <$tag> não encontrada no XML. '
        'Verifique se o arquivo é uma NF-e válida no leiaute 4.0.',
      );
    }
    return elements.first.innerText.trim();
  }

  // Extrai texto de uma tag filha — retorna null se não encontrar
  static String? _textoOpcional(XmlElement parent, String tag) {
    final elements = parent.findElements(tag);
    if (elements.isEmpty) return null;
    final texto = elements.first.innerText.trim();
    return texto.isEmpty ? null : texto;
  }

  // Propriedades derivadas específicas da NF-e
  int get totalItens => itens.length;
  bool get todosItensConferidos => itens.every((item) => item.conferido);
  bool get temDivergencia => itens.any((item) => item.divergente);

  Map<String, dynamic> toMap() {
    return {
      'empresa_id': empresaId,
      'chave_acesso': chaveAcesso,
      'numero': numero,
      'serie': serie,
      'tipo': tipo,
      'status': status,
      'data_emissao': dataEmissao.toIso8601String(),
      'valor_total': valorTotal,
      'xml_url': xmlUrl,
      'emitente_cnpj': emitenteCnpj,
      'emitente_nome': emitenteNome,
      'emitente_uf': emitenteUf,
      'inativo_em': inativoEm?.toIso8601String(),
      'criado_em': criadoEm.toIso8601String(),
    };
  }
}