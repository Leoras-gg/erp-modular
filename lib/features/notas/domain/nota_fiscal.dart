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
// Conceito POO: herança permite compartilhar campos e comportamentos
// comuns (criadoEm, status, tipo, valorTotal...) sem repetir código.
// NotaFiscal só declara o que é ESPECÍFICO dela — o resto herda.
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
// ============================================================
// PROBLEMA DO NAMESPACE — LEIA COM ATENÇÃO
// ============================================================
// O XML da NF-e declara um namespace padrão na tag raiz:
//   xmlns="http://www.portalfiscal.inf.br/nfe"
//
// O que isso significa na prática:
// Quando um XML tem namespace padrão, TODAS as tags dentro dele
// pertencem implicitamente a esse namespace. Uma tag <infNFe>
// sem namespace declarado, dentro de um documento com namespace
// padrão, na verdade se chama:
//   {http://www.portalfiscal.inf.br/nfe}infNFe
//
// O problema que isso causava:
// O método findAllElements('infNFe') sem especificar o namespace
// procurava por uma tag chamada literalmente 'infNFe' sem namespace
// e não encontrava nada — porque a tag tem namespace implícito.
// Resultado: o parse falhava silenciosamente ou lançava exceção.
//
// A solução implementada:
// Criamos uma função auxiliar _findTag() que tenta PRIMEIRO com
// o namespace oficial da NF-e, e se não encontrar, tenta sem
// namespace. Isso torna o parser robusto para:
//   - XMLs com namespace declarado (padrão NF-e real)
//   - XMLs sem namespace (alguns XMLs de teste ou versões antigas)
//   - XMLs com prefixo de namespace (ex: <nfe:infNFe>)
//
// INPUT ESPERADO do fromXml():
//   xmlContent: String com o conteúdo completo do arquivo XML
//   empresaId:  String UUID da empresa que está importando
//
// OUTPUT ESPERADO do fromXml():
//   NotaFiscal com id='' (será preenchido pelo banco ao salvar)
//   e todos os campos extraídos do XML
//   OU lança FormatException se o XML for inválido

import 'package:xml/xml.dart';
import 'documento_fiscal.dart';
import 'item_nota.dart';

class NotaFiscal extends DocumentoFiscal {
  // ============================================================
  // DADOS DO EMITENTE
  // ============================================================

  // CNPJ do emitente (14 dígitos, sem pontuação)
  // Corresponde à tag <CNPJ> dentro de <emit> no XML
  // Juridicamente identifica o emitente perante a SEFAZ
  final String emitenteCnpj;

  // Razão social ou nome fantasia do emitente
  // Corresponde à tag <xNome> dentro de <emit> no XML
  final String emitenteNome;

  // UF do emitente (ex: SP, RJ, MG)
  // Corresponde à tag <UF> dentro de <enderEmit> no XML
  // Importante: determina qual SEFAZ estadual autorizou a nota
  final String emitenteUf;

  // ============================================================
  // ITENS DA NOTA
  // ============================================================
  // Lista de produtos que compõem esta nota fiscal.
  //
  // CONCEITO POO — COMPOSIÇÃO:
  // NotaFiscal CONTÉM uma lista de ItemNota.
  // Isso é composição — um objeto composto de outros objetos.
  // É diferente de herança: NotaFiscal não É um ItemNota,
  // ela TEM uma coleção deles.
  //
  // Cada ItemNota corresponde a uma tag <det> no XML.
  // Uma NF-e pode ter até 990 itens (limitação do leiaute 4.0).
  final List<ItemNota> itens;

  // Construtor com super() passando campos para DocumentoFiscal
  // Conceito: o construtor da subclasse chama o da superclasse
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
  // Usado quando buscamos notas já salvas no Supabase.
  // O parâmetro itens é opcional — pode vir vazio na listagem
  // e preenchido quando carregamos a nota completa com seus itens.
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
  //     <infNFe Id="NFe...44dígitos...">   ← informações principais
  //       <ide>            ← identificação da nota
  //         <nNF>          ← número da nota
  //         <serie>        ← série
  //         <dhEmi>        ← data/hora de emissão ISO 8601
  //         <tpNF>         ← tipo: 0=entrada, 1=saída
  //       </ide>
  //       <emit>           ← dados do emitente (fornecedor)
  //         <CNPJ>         ← CNPJ do emitente (14 dígitos)
  //         <xNome>        ← razão social
  //         <enderEmit>
  //           <UF>         ← estado do emitente
  //         </enderEmit>
  //       </emit>
  //       <total>          ← totais da nota
  //         <ICMSTot>
  //           <vNF>        ← valor total da nota
  //         </ICMSTot>
  //       </total>
  //       <det nItem="1">  ← item 1 (repete para cada produto)
  //         <prod>         ← dados do produto
  //           ...
  //         </prod>
  //       </det>
  //     </infNFe>
  //   </NFe>
  //   <protNFe>            ← protocolo de autorização da SEFAZ
  //     <infProt>
  //       <chNFe>          ← chave de acesso (44 dígitos) — confirmação
  //     </infProt>
  //   </protNFe>
  // </nfeProc>
  //
  // IMPORTANTE: O XML pode vir como <nfeProc> (com protocolo)
  // ou como <NFe> diretamente (sem protocolo — contingência).
  // O parser deve tratar ambos os casos — nossa função _findTag()
  // cuida disso buscando na árvore inteira independente da raiz.
  static NotaFiscal fromXml(String xmlContent, String empresaId) {
    // ============================================================
    // PASSO 1: PARSE DO XML EM ÁRVORE DE NÓS
    // ============================================================
    // XmlDocument.parse() converte a String de texto XML em uma
    // árvore de objetos que podemos navegar programaticamente.
    // Se o XML estiver malformado (tag não fechada, caractere inválido...),
    // lança XmlParserException aqui mesmo antes de continuar.
    final document = XmlDocument.parse(xmlContent);

    // ============================================================
    // PASSO 2: FUNÇÃO AUXILIAR PARA LIDAR COM NAMESPACE
    // ============================================================
    // CONCEITO: closure em Dart
    // Uma closure é uma função definida dentro de outra função
    // que "captura" variáveis do escopo externo.
    // Aqui, _findTag captura 'document' e a constante 'ns'
    // sem precisar recebê-los como parâmetros.
    //
    // Por que precisamos disso?
    // O XML oficial da NF-e tem namespace padrão declarado:
    //   xmlns="http://www.portalfiscal.inf.br/nfe"
    // Quando namespace padrão está presente, findAllElements('infNFe')
    // não encontra nada — a tag pertence ao namespace, não ao espaço
    // sem nome. Precisamos especificar o namespace NA BUSCA.
    //
    // Mas XMLs de teste frequentemente não têm namespace.
    // A solução: tentar COM namespace primeiro, depois SEM.
    // Isso garante compatibilidade com ambos os formatos.
    const ns = 'http://www.portalfiscal.inf.br/nfe';

    // _findTag: busca uma tag em qualquer nó da árvore XML,
    // com fallback para busca sem namespace.
    //
    // Parâmetro node: o nó XML onde iniciar a busca
    // Parâmetro tag: nome da tag a procurar (ex: 'infNFe', 'emit')
    // Retorno: Iterable de XmlElement com todos os resultados
    Iterable<XmlElement> findTag(XmlNode node, String tag) {
      // Tenta primeiro com namespace oficial da NF-e
      var resultado = node.findAllElements(tag, namespace: ns);
      // Se não encontrou, tenta sem namespace (XMLs sem declaração)
      if (resultado.isEmpty) {
        resultado = node.findAllElements(tag);
      }
      return resultado;
    }

    // ============================================================
    // PASSO 3: LOCALIZA O NÓ RAIZ DE INFORMAÇÕES (<infNFe>)
    // ============================================================
    // <infNFe> contém TUDO da nota — identificação, emitente,
    // destinatário, produtos, impostos, totais.
    // É o nó mais importante do XML da NF-e.
    final infNFeList = findTag(document, 'infNFe');
    if (infNFeList.isEmpty) {
      throw FormatException(
        'Tag <infNFe> não encontrada no XML. '
        'Verifique se o arquivo é uma NF-e válida no leiaute 4.0. '
        'O arquivo pode estar corrompido ou ser de outro tipo (CT-e, MDF-e).',
      );
    }
    final infNFe = infNFeList.first;

    // ============================================================
    // PASSO 4: EXTRAÇÃO DA CHAVE DE ACESSO
    // ============================================================
    // A chave de acesso fica no ATRIBUTO Id da tag <infNFe>:
    //   <infNFe Id="NFe35260412345678000195550010000001231123456786">
    //
    // Formato: prefixo "NFe" + 44 dígitos
    // getAttribute('Id') retorna: "NFe35260412345678000195550010000001231123456786"
    // replaceFirst remove o "NFe" deixando só os 44 dígitos:
    //   "35260412345678000195550010000001231123456786"
    //
    // Por que 44 dígitos? Cada posição tem significado legal:
    //   [0-1]   = código IBGE do estado (ex: 35 = SP)
    //   [2-5]   = AAMM de emissão (ex: 2604 = abril/2026)
    //   [6-19]  = CNPJ do emitente (14 dígitos)
    //   [20-21] = modelo (55 = NF-e)
    //   [22-24] = série (ex: 001)
    //   [25-33] = número da nota (9 dígitos)
    //   [34]    = forma de emissão (1 = normal)
    //   [35-42] = código numérico aleatório (8 dígitos)
    //   [43]    = dígito verificador módulo 11
    final idAtributo = infNFe.getAttribute('Id') ?? '';
    final chaveAcesso = idAtributo.replaceFirst('NFe', '');

    // Validação: chave deve ter exatamente 44 dígitos
    if (chaveAcesso.length != 44) {
      throw FormatException(
        'Chave de acesso inválida: esperado 44 dígitos, '
        'encontrado ${chaveAcesso.length}. '
        'O atributo Id da tag <infNFe> pode estar incorreto.',
      );
    }

    // ============================================================
    // PASSO 5: IDENTIFICAÇÃO DA NOTA (<ide>)
    // ============================================================
    // A tag <ide> contém os dados de identificação do documento.
    // Usamos findTag(infNFe, 'ide') para buscar DENTRO de infNFe.
    // O .first acessa o primeiro (e único) resultado.
    final ide = findTag(infNFe, 'ide').first;

    // Número da nota — tag <nNF>
    // Exemplo: "123" ou "000001234"
    final numero = _texto(ide, 'nNF', findTag);

    // Série da nota — tag <serie>
    // Exemplo: "1" ou "001"
    final serie = _texto(ide, 'serie', findTag);

    // Tipo da operação — tag <tpNF>
    // 0 = entrada (nota de compra recebida)
    // 1 = saída (nota de venda emitida)
    // Convertemos para string descritiva para legibilidade no sistema
    final tpNF = _texto(ide, 'tpNF', findTag);
    final tipo = tpNF == '0' ? 'entrada' : 'saida';

    // Data e hora de emissão — tag <dhEmi>
    // Formato ISO 8601: "2026-04-01T09:30:00-03:00"
    // DateTime.parse() converte para objeto DateTime considerando timezone
    final dhEmi = _texto(ide, 'dhEmi', findTag);
    final dataEmissao = DateTime.parse(dhEmi);

    // ============================================================
    // PASSO 6: DADOS DO EMITENTE (<emit>)
    // ============================================================
    // O emitente é quem assinou e emitiu a nota.
    // Na importação de compras: é o fornecedor.
    // Na emissão de vendas: é a própria empresa.
    final emit = findTag(infNFe, 'emit').first;

    // CNPJ pode ser de pessoa jurídica (14 dígitos)
    // ou CPF de pessoa física (11 dígitos) — ambos ocorrem na NF-e.
    // Tentamos CNPJ primeiro (mais comum em operações B2B de almoxarifado),
    // depois CPF como fallback.
    // ?? é o operador null-coalescing: usa o valor da direita se a esquerda for null
    final emitenteCnpj = _textoOpcional(emit, 'CNPJ', findTag) ??
        _textoOpcional(emit, 'CPF', findTag) ??
        '';
    final emitenteNome = _texto(emit, 'xNome', findTag);

    // UF fica dentro de <enderEmit> (endereço do emitente)
    final enderEmit = findTag(emit, 'enderEmit').first;
    final emitenteUf = _texto(enderEmit, 'UF', findTag);

    // ============================================================
    // PASSO 7: VALOR TOTAL (<total>/<ICMSTot>/<vNF>)
    // ============================================================
    // <vNF> = valor total da NF-e
    // É o valor que aparece no DANFE e que foi autorizado pela SEFAZ.
    // Pode diferir da soma dos itens se houver frete, seguros, descontos.
    //
    // double.parse() converte String "275.00" para double 275.0
    // O XML usa ponto como separador decimal (padrão internacional)
    final total = findTag(infNFe, 'total').first;
    final icmsTot = findTag(total, 'ICMSTot').first;
    final valorTotal = double.parse(_texto(icmsTot, 'vNF', findTag));

    // ============================================================
    // PASSO 8: ITENS DA NOTA (<det>)
    // ============================================================
    // Cada tag <det nItem="N"> representa um produto na nota.
    // findTag retorna um Iterable — usamos .map() para transformar
    // cada <det> em um objeto ItemNota via _parsearItem().
    //
    // CONCEITO: map() em coleções
    // Transforma cada elemento de uma coleção aplicando uma função.
    // Aqui: Iterable<XmlElement> → List<ItemNota>
    final detElements = findTag(infNFe, 'det');
    final itens = detElements.map((det) {
      // notaId é passado vazio — será preenchido ao salvar no banco
      return _parsearItem(det, '', findTag);
    }).toList(); // .toList() materializa o Iterable em List

    // ============================================================
    // PASSO 9: MONTAGEM DO OBJETO NotaFiscal
    // ============================================================
    // id: será gerado pelo PostgreSQL (gen_random_uuid())
    // criadoEm: data/hora local de importação (não a data fiscal)
    // status: sempre 'importada' — início da máquina de estados
    // xmlUrl: null por ora — será preenchido após upload ao Storage
    return NotaFiscal(
      id: '',
      empresaId: empresaId,
      chaveAcesso: chaveAcesso,
      numero: numero,
      serie: serie,
      tipo: tipo,
      status: 'importada',
      dataEmissao: dataEmissao,
      valorTotal: valorTotal,
      xmlUrl: null,
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
  // Extrai os dados de produto de uma tag <det> do XML.
  //
  // Parâmetros:
  //   det:     o elemento XmlElement da tag <det nItem="N">
  //   notaId:  UUID da nota (vazio ao importar, preenchido ao salvar)
  //   findTag: a função auxiliar de namespace passada como parâmetro
  //            Conceito: funções são objetos em Dart — podem ser
  //            passadas como argumentos (higher-order functions)
  //
  // INPUT esperado: <det nItem="1"><prod>...</prod><imposto>...</imposto></det>
  // OUTPUT esperado: ItemNota com todos os campos fiscais extraídos
  static ItemNota _parsearItem(
    XmlElement det,
    String notaId,
    Iterable<XmlElement> Function(XmlNode, String) findTag,
  ) {
    // nItem é um ATRIBUTO da tag <det>, não uma tag filha
    // Exemplo: <det nItem="1"> → getAttribute('nItem') retorna "1"
    final nItem = int.parse(det.getAttribute('nItem') ?? '0');

    // <prod> contém todos os dados comerciais do produto
    final prod = findTag(det, 'prod').first;

    // Dados de identificação do produto no sistema do EMITENTE
    // (não é nosso código interno — é o código que o fornecedor usa)
    final codigoProdutoEmitente = _texto(prod, 'cProd', findTag);
    final descricaoProduto = _texto(prod, 'xProd', findTag);

    // NCM — 8 dígitos que classificam o produto para fins tributários
    // CFOP — 4 dígitos que identificam a natureza fiscal da operação
    // Ver comentários detalhados em item_nota.dart
    final ncm = _texto(prod, 'NCM', findTag);
    final cfop = _texto(prod, 'CFOP', findTag);

    // Unidade e quantidade comercial
    // uCom = unidade como aparece na nota (UN, KG, MT, CX, RL...)
    // qCom = quantidade com até 4 casas decimais no XML
    final unidadeMedida = _texto(prod, 'uCom', findTag);
    final quantidade = double.parse(_texto(prod, 'qCom', findTag));

    // Valores monetários — o XML usa ponto decimal com até 10 casas
    final valorUnitario = double.parse(_texto(prod, 'vUnCom', findTag));
    final valorTotalItem = double.parse(_texto(prod, 'vProd', findTag));

    // ---- Código de barras EAN ----
    // cEAN pode ser:
    //   "7891234567895" → código EAN-13 válido
    //   "SEM GTIN"      → produto não tem código de barras
    //   ausente         → tag não existe no XML
    // Normalizamos para null quando não há código
    final cEAN = _textoOpcional(prod, 'cEAN', findTag);
    final codigoBarras = (cEAN == null || cEAN == 'SEM GTIN') ? null : cEAN;

    // ---- Dados de lote (<rastro>) ----
    // A tag <rastro> é OPCIONAL — só presente quando o emitente
    // informa dados de rastreabilidade por lote.
    // Comum em: medicamentos, alimentos, produtos controlados,
    // matérias-primas industriais com controle de qualidade.
    //
    // Conceito: verificamos se a tag existe antes de acessar
    // para evitar exceção de "elemento não encontrado"
    String? lote;
    DateTime? dataFabricacao;
    DateTime? dataValidade;

    final rastros = findTag(prod, 'rastro');
    if (rastros.isNotEmpty) {
      final rastro = rastros.first;

      // nLote: número do lote definido pelo fabricante
      lote = _textoOpcional(rastro, 'nLote', findTag);

      // dFab e dVal: datas no formato AAAA-MM-DD
      // DateTime.parse() converte diretamente para o objeto DateTime
      final dFab = _textoOpcional(rastro, 'dFab', findTag);
      if (dFab != null) dataFabricacao = DateTime.parse(dFab);

      final dVal = _textoOpcional(rastro, 'dVal', findTag);
      if (dVal != null) dataValidade = DateTime.parse(dVal);
    }

    return ItemNota(
      id: '',         // será gerado pelo banco
      notaId: notaId, // vazio ao importar, preenchido ao salvar
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
      valorTotal: valorTotalItem,
      quantidadeConferida: 0, // inicia em zero — será incrementado na conferência
    );
  }

  // ============================================================
  // MÉTODOS AUXILIARES DE EXTRAÇÃO DE TEXTO
  // ============================================================
  // Estes métodos agora recebem a função findTag como parâmetro.
  //
  // CONCEITO: higher-order functions (funções de ordem superior)
  // Em Dart, funções são cidadãos de primeira classe — podem ser
  // armazenadas em variáveis e passadas como argumentos.
  // O tipo do parâmetro findTag é:
  //   Iterable<XmlElement> Function(XmlNode, String)
  // Isso declara "uma função que recebe XmlNode e String e retorna
  // Iterable<XmlElement>" — exatamente o tipo da nossa closure.

  // _texto: extrai texto de uma tag filha — lança FormatException se não encontrar
  // Usar quando o campo é OBRIGATÓRIO no leiaute da NF-e
  static String _texto(
    XmlElement parent,
    String tag,
    Iterable<XmlElement> Function(XmlNode, String) findTag,
  ) {
    final elements = findTag(parent, tag);
    if (elements.isEmpty) {
      throw FormatException(
        'Tag <$tag> não encontrada no XML. '
        'Este campo é obrigatório no leiaute NF-e 4.0. '
        'O XML pode estar incompleto ou ser de uma versão diferente.',
      );
    }
    // .trim() remove espaços e quebras de linha extras que podem
    // aparecer em XMLs formatados com indentação
    return elements.first.innerText.trim();
  }

  // _textoOpcional: extrai texto — retorna null se tag não existir
  // Usar quando o campo é OPCIONAL no leiaute da NF-e
  static String? _textoOpcional(
    XmlElement parent,
    String tag,
    Iterable<XmlElement> Function(XmlNode, String) findTag,
  ) {
    final elements = findTag(parent, tag);
    if (elements.isEmpty) return null;
    final texto = elements.first.innerText.trim();
    // Retorna null também se o texto estiver vazio
    return texto.isEmpty ? null : texto;
  }

  // ============================================================
  // PROPRIEDADES DERIVADAS ESPECÍFICAS DA NF-e
  // ============================================================
  // CONCEITO: computed properties
  // Calculadas a partir dos dados existentes — sem armazenar estado extra.
  // A UI usa estas propriedades sem precisar recalcular.

  // Total de itens na nota
  int get totalItens => itens.length;

  // Todos os itens foram conferidos pelo operador
  // .every() retorna true se TODOS os elementos satisfazem a condição
  bool get todosItensConferidos => itens.every((item) => item.conferido);

  // Existe ao menos um item com divergência de quantidade
  // .any() retorna true se ALGUM elemento satisfaz a condição
  bool get temDivergencia => itens.any((item) => item.divergente);

  // Serialização para o banco — só campos da tabela notas_fiscais
  // Os itens são salvos separadamente em nota_itens
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