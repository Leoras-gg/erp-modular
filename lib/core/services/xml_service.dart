// lib/core/services/xml_service.dart
//
// CAMADA: core/services
// RESPONSABILIDADE: serviço transversal de leitura e validação
// de arquivos XML fiscais.
//
// CONCEITO ARQUITETURAL — Por que fica em core/services/?
// Serviços em core/ são TRANSVERSAIS — podem ser usados por
// múltiplos módulos. O XmlService não pertence só ao módulo
// de notas porque outros documentos fiscais futuros (CT-e,
// MDF-e) também precisariam de parse de XML.
// Regra: se a lógica pertence a UM módulo → features/modulo/domain/
//         se pode ser reutilizada → core/services/
//
// FLUXO COMPLETO DE IMPORTAÇÃO:
//
//   [1] Usuário clica em "Importar XML"
//         ↓
//   [2] XmlService.selecionarArquivo()
//       → abre seletor de arquivo nativo do SO
//       → retorna Resultado<String> com conteúdo do XML
//         ↓
//   [3] XmlService.extrairChaveAcesso()
//       → extrai os 44 dígitos para verificar duplicidade
//       → retorna Resultado<String>
//         ↓
//   [4] INotaFiscalRepository.verificarDuplicidade()
//       → verifica no banco se chave já existe
//         ↓
//   [5] XmlService.processarXml()
//       → chama validarNFe() + NotaFiscal.fromXml()
//       → retorna Resultado<NotaFiscal>
//         ↓
//   [6] INotaFiscalRepository.importar()
//       → salva nota + itens + XML no banco/storage
//
// VALIDAÇÕES IMPLEMENTADAS:
//   ✓ XML bem formado (tags balanceadas, caracteres válidos)
//   ✓ Presença das tags obrigatórias do leiaute NF-e 4.0
//   ✓ Chave de acesso com exatamente 44 dígitos
//   ✓ Pelo menos um item (<det>) na nota
//   ✓ Tratamento de namespace padrão da NF-e
//
// VALIDAÇÕES NÃO IMPLEMENTADAS (fora do escopo):
//   ✗ Assinatura digital ICP-Brasil (requer certificado da cadeia)
//   ✗ Consulta de autenticidade na SEFAZ (requer webservice)
//   ✗ Validação do dígito verificador da chave de acesso
//   ✗ Consistência entre chave e campos (CNPJ, data, número...)
//
// LIMITAÇÃO CONHECIDA DOCUMENTADA:
// O sistema importa assumindo que o XML é autêntico.
// A responsabilidade de verificar autenticidade é do operador.
// Em ambiente produtivo crítico, recomenda-se adicionar
// consulta ao webservice NfeConsultaProtocolo da SEFAZ.

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart';
import '../../features/notas/domain/nota_fiscal.dart';
import '../errors/resultado.dart';

class XmlService {
  // ============================================================
  // CONSTANTES — definições do leiaute NF-e
  // ============================================================

  // Namespace oficial da NF-e definido pelo MOC (Manual de Orientação
  // ao Contribuinte) disponível em www.nfe.fazenda.gov.br
  // Todas as tags do XML NF-e pertencem implicitamente a este namespace
  // quando ele é declarado na raiz com xmlns="..."

  // A chave de acesso tem SEMPRE 44 dígitos — é uma regra do leiaute
  static const _tamanhoChaveAcesso = 44;

  // Tags que DEVEM existir em qualquer XML NF-e válido
  // Se alguma delas estiver ausente, o XML está incompleto ou corrompido
  static const _tagsObrigatorias = ['infNFe', 'ide', 'emit', 'det', 'total'];

  // ============================================================
  // FUNÇÃO AUXILIAR DE NAMESPACE — usada em todos os métodos
  // ============================================================
  // Cria uma função de busca que tenta com namespace e sem namespace.
  //
  // CONCEITO: factory method para funções
  // _criarFindTag() retorna UMA FUNÇÃO (não um valor).
  // Isso permite criar a função uma vez por chamada e reutilizá-la
  // em múltiplas buscas sem repetir a lógica de namespace.
  //
  // O tipo de retorno é:
  //   Iterable<XmlElement> Function(XmlNode, String)
  // Ou seja: uma função que recebe XmlNode + String e retorna Iterable.
  static Iterable<XmlElement> Function(XmlNode, String) _criarFindTag() {
    return (XmlNode node, String tag) {
      // Usa localName para ignorar prefixos de namespace
      // Compatível com todos os formatos de NF-e
      final filhos = node.children
          .whereType<XmlElement>()
          .where((e) => e.localName == tag);
      if (filhos.isNotEmpty) return filhos;

      return node.descendants
          .whereType<XmlElement>()
          .where((e) => e.localName == tag);
    };
  }

  // ============================================================
  // MÉTODO PRINCIPAL — selecionar e ler arquivo
  // ============================================================
  // Abre o seletor de arquivo nativo do sistema operacional,
  // filtra para .xml e retorna o conteúdo como String.
  //
  // INPUT: nenhum — abre diálogo interativo com o usuário
  //
  // OUTPUT: Resultado<String>
  //   Sucesso → conteúdo do arquivo XML como String
  //   Falha(validacao)    → usuário cancelou ou arquivo não é XML
  //   Falha(desconhecido) → erro ao ler o arquivo do disco
  Future<Resultado<String>> selecionarArquivo() async {
    try {
      // FilePicker.platform abre o seletor nativo do SO:
      // - Windows: diálogo "Abrir arquivo" do Windows Explorer
      // - Linux: diálogo GTK ou Qt dependendo do desktop
      // - macOS: diálogo nativo do Finder
      // - Android/iOS: seletor de arquivos do sistema
      //
      // type: FileType.custom + allowedExtensions: limita ao tipo .xml
      // Isso filtra na UI do seletor, não só no código Flutter
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml'],
        dialogTitle: 'Selecionar arquivo XML de NF-e',
        allowMultiple: false, // uma nota por vez — múltiplas no futuro
      );

      // Resultado null ou lista vazia = usuário clicou em Cancelar
      // Não é um erro — é uma ação válida do usuário
      if (result == null || result.files.isEmpty) {
        return Falha(
          TipoFalha.validacao,
          'Nenhum arquivo selecionado.',
        );
      }

      final arquivo = result.files.first;

      // Verificação defensiva de extensão
      // O FilePicker já filtra, mas verificamos novamente por segurança
      // Conceito: defense in depth — múltiplas camadas de validação
      if (arquivo.extension?.toLowerCase() != 'xml') {
        return Falha(
          TipoFalha.xmlInvalido,
          'O arquivo selecionado não é um XML. '
          'Selecione o arquivo XML da NF-e (extensão .xml).',
        );
      }

      // File() cria uma referência ao arquivo no sistema de arquivos
      // readAsString() lê o conteúdo como texto
      // Encoding padrão: UTF-8, que é o encoding obrigatório da NF-e
      final file = File(arquivo.path!);
      final conteudo = await file.readAsString();

      return Sucesso(conteudo);
    } catch (e) {
      return Falha(
        TipoFalha.desconhecido,
        'Erro ao ler o arquivo. '
        'Verifique se você tem permissão de leitura: ${e.toString()}',
        detalhes: e,
      );
    }
  }

  // ============================================================
  // VALIDAÇÃO ESTRUTURAL DO XML
  // ============================================================
  // Verifica se o conteúdo é estruturalmente válido como NF-e.
  // Esta é validação ESTRUTURAL — não verifica assinatura digital.
  //
  // INPUT: xmlContent — String com o conteúdo do arquivo XML
  //
  // OUTPUT: Resultado<bool>
  //   Sucesso(true)        → XML é estruturalmente válido
  //   Falha(xmlInvalido)   → XML malformado ou incompleto
  Resultado<bool> validarNFe(String xmlContent) {
    // ---- Passo 1: verifica se é XML bem formado ----
    // XmlDocument.parse() lança XmlParserException se o XML
    // tiver erros de sintaxe: tag não fechada, atributo sem aspas,
    // caractere inválido fora de CDATA, etc.
    XmlDocument document;
    try {
      document = XmlDocument.parse(xmlContent);
    } catch (e) {
      return Falha(
        TipoFalha.xmlInvalido,
        'O arquivo não é um XML válido. '
        'O arquivo pode estar corrompido ou truncado. '
        'Tente exportar novamente do sistema de origem.',
        detalhes: e,
      );
    }

    // Cria a função de busca com suporte a namespace
    final findTag = _criarFindTag();

    // ---- Passo 2: verifica tags obrigatórias ----
    // Cada tag da lista _tagsObrigatorias deve existir no XML.
    // Usamos findTag que busca em TODA a árvore (findAllElements),
    // então funciona independente de onde a tag está na hierarquia.
    for (final tag in _tagsObrigatorias) {
      if (findTag(document, tag).isEmpty) {
        return Falha(
          TipoFalha.xmlInvalido,
          'XML inválido: tag <$tag> não encontrada. '
          'Verifique se o arquivo é uma NF-e no leiaute 4.0. '
          'CT-e, MDF-e e NFC-e têm estrutura diferente.',
        );
      }
    }

    // ---- Passo 3: verifica chave de acesso ----
    try {
      final infNFe = findTag(document, 'infNFe').first;
      final idAtributo = infNFe.getAttribute('Id') ?? '';
      final chave = idAtributo.replaceFirst('NFe', '');

      if (chave.length != _tamanhoChaveAcesso) {
        return Falha(
          TipoFalha.xmlInvalido,
          'Chave de acesso inválida: '
          'encontrado ${chave.length} dígitos, '
          'esperado $_tamanhoChaveAcesso. '
          'O atributo Id da tag <infNFe> está incorreto.',
        );
      }

      // ---- Passo 4: verifica se tem pelo menos um item ----
      // Uma NF-e sem itens não faz sentido operacionalmente
      if (findTag(document, 'det').isEmpty) {
        return Falha(
          TipoFalha.xmlInvalido,
          'Nenhum item (<det>) encontrado na nota. '
          'Uma NF-e deve ter ao menos um produto.',
        );
      }
    } catch (e) {
      return Falha(
        TipoFalha.xmlInvalido,
        'Erro ao validar a estrutura do XML.',
        detalhes: e,
      );
    }

    return Sucesso(true);
  }

  // ============================================================
  // EXTRAÇÃO RÁPIDA DA CHAVE DE ACESSO
  // ============================================================
  // Extrai apenas a chave sem parsear a nota inteira.
  // Usado ANTES do processamento completo para verificar
  // duplicidade no banco — se a nota já existe, não processamos.
  // Isso evita trabalho desnecessário de parse para notas repetidas.
  //
  // INPUT: xmlContent — String com o conteúdo do XML
  //
  // OUTPUT: Resultado<String>
  //   Sucesso → String com os 44 dígitos da chave
  //   Falha   → XML inválido ou chave não encontrada
  Resultado<String> extrairChaveAcesso(String xmlContent) {
    try {
      final document = XmlDocument.parse(xmlContent);
      final findTag = _criarFindTag();

      final infNFeList = findTag(document, 'infNFe');
      if (infNFeList.isEmpty) {
        return Falha(
          TipoFalha.xmlInvalido,
          'Tag <infNFe> não encontrada. Não foi possível extrair a chave.',
        );
      }

      final infNFe = infNFeList.first;
      final idAtributo = infNFe.getAttribute('Id') ?? '';
      final chave = idAtributo.replaceFirst('NFe', '');

      if (chave.length != _tamanhoChaveAcesso) {
        return Falha(
          TipoFalha.xmlInvalido,
          'Chave de acesso inválida no XML: '
          '${chave.length} dígitos encontrados.',
        );
      }

      return Sucesso(chave);
    } catch (e) {
      return Falha(
        TipoFalha.xmlInvalido,
        'Não foi possível extrair a chave de acesso do XML.',
        detalhes: e,
      );
    }
  }

  // ============================================================
  // PROCESSAMENTO COMPLETO — validação + parse
  // ============================================================
  // Método de conveniência que combina validação estrutural
  // com o parse completo da nota.
  //
  // Por que separar validarNFe() do processarXml()?
  // Porque o Notifier chama extrairChaveAcesso() entre os dois
  // para verificar duplicidade. O fluxo é:
  //   validarNFe → extrairChave → verificarDuplicidade → processarXml
  //
  // INPUT:
  //   xmlContent: String com o conteúdo do XML
  //   empresaId:  UUID da empresa que está importando
  //
  // OUTPUT: Resultado<NotaFiscal>
  //   Sucesso → NotaFiscal completa pronta para salvar no banco
  //   Falha   → erro de validação ou parse
  Resultado<NotaFiscal> processarXml(
    String xmlContent,
    String empresaId,
  ) {
    // Passo 1: valida estrutura antes de tentar parsear
    // Fail fast — falha cedo com mensagem clara em vez de
    // deixar estourar uma exceção confusa dentro do fromXml()
    final validacao = validarNFe(xmlContent);
    if (validacao is Falha) {
      // Propaga o erro da validação com tipo e mensagem originais
      return Falha(
        (validacao as Falha).tipo,
        (validacao as Falha).mensagem,
        detalhes: (validacao as Falha).detalhes,
      );
    }

    // Passo 2: parseia o XML e cria o objeto NotaFiscal
    // NotaFiscal.fromXml() pode lançar FormatException
    // para campos obrigatórios ausentes
    try {
      final nota = NotaFiscal.fromXml(xmlContent, empresaId);
      return Sucesso(nota);
    } on FormatException catch (e) {
      // FormatException tem um campo .message com descrição detalhada
      return Falha(
        TipoFalha.xmlInvalido,
        e.message,
        detalhes: e,
      );
    } catch (e) {
      return Falha(
        TipoFalha.desconhecido,
        'Erro inesperado ao processar o XML. '
        'Tente novamente ou contate o suporte.',
        detalhes: e,
      );
    }
  }
}