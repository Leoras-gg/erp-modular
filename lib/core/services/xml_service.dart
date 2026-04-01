// lib/core/services/xml_service.dart
//
// CAMADA: core/services
// RESPONSABILIDADE: serviço transversal de leitura e validação
// de arquivos XML fiscais. Não pertence a nenhum módulo específico
// porque outros módulos futuros (CT-e, MDF-e) também podem usar.
//
// CONCEITO ARQUITETURAL:
// Serviços em core/ são transversais — usados por múltiplos módulos.
// A regra: se a lógica pertence a um único módulo, fica em
// features/modulo/domain/. Se pode ser reutilizada, fica em core/services/.
//
// FLUXO DE IMPORTAÇÃO DE NF-e:
//
//   Usuário seleciona arquivo XML
//         ↓
//   XmlService.lerArquivo() → lê bytes do arquivo
//         ↓
//   XmlService.validarNFe() → verifica se é NF-e válida
//         ↓
//   NotaFiscal.fromXml()   → extrai dados do XML
//         ↓
//   SupabaseNotaFiscalRepository.importar() → salva no banco
//
// VALIDAÇÕES IMPLEMENTADAS:
// 1. Verifica se o arquivo é XML bem formado
// 2. Verifica se contém as tags obrigatórias da NF-e
// 3. Verifica se a chave de acesso tem 44 dígitos
// 4. NÃO valida assinatura digital (requer certificado ICP-Brasil)
// 5. NÃO consulta SEFAZ (requer integração com webservice)
//
// LIMITAÇÕES CONHECIDAS (para documentação técnica):
// - A validação da assinatura digital exige o certificado da
//   cadeia ICP-Brasil, o que está fora do escopo deste sistema.
// - A consulta de autenticidade na SEFAZ exigiria integração
//   com o webservice NfeConsultaProtocolo, também fora do escopo.
// - O sistema importa e processa o XML assumindo que ele é
//   autêntico — a responsabilidade de verificar a autenticidade
//   é do operador que está importando o arquivo.

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart';
import '../../features/notas/domain/nota_fiscal.dart';
import '../errors/resultado.dart';

class XmlService {
  // ============================================================
  // CONSTANTES — definições do leiaute NF-e
  // ============================================================

  // Namespace oficial da NF-e — todas as tags pertencem a este namespace
  // Definido pelo Manual de Orientação ao Contribuinte (MOC) da SEFAZ
  static const _namespacePfe =
      'http://www.portalfiscal.inf.br/nfe';

  // Tamanho obrigatório da chave de acesso
  static const _tamanhoChaveAcesso = 44;

  // Tags obrigatórias que todo XML de NF-e deve conter
  static const _tagsObrigatorias = ['infNFe', 'ide', 'emit', 'det', 'total'];

  // ============================================================
  // MÉTODO PRINCIPAL — selecionar e processar arquivo
  // ============================================================
  // Abre o seletor de arquivo do sistema operacional,
  // lê o XML selecionado e retorna o conteúdo como String.
  //
  // Retorna Falha se:
  // - Usuário cancelar a seleção
  // - Arquivo não for XML
  // - Arquivo não puder ser lido
  Future<Resultado<String>> selecionarArquivo() async {
    try {
      // FilePicker abre o diálogo nativo do sistema operacional
      // type: FileType.custom limita aos tipos especificados
      // allowedExtensions: só permite .xml
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml'],
        dialogTitle: 'Selecionar arquivo XML de NF-e',
        // allowMultiple: false — importação de uma nota por vez
        allowMultiple: false,
      );

      // Usuário cancelou a seleção
      if (result == null || result.files.isEmpty) {
        return Falha(
          TipoFalha.validacao,
          'Nenhum arquivo selecionado',
        );
      }

      final arquivo = result.files.first;

      // Verificação adicional de extensão (segurança defensiva)
      if (arquivo.extension?.toLowerCase() != 'xml') {
        return Falha(
          TipoFalha.xmlInvalido,
          'O arquivo selecionado não é um XML. '
          'Selecione o arquivo XML da NF-e.',
        );
      }

      // Lê o conteúdo do arquivo como String
      // Encoding: NF-e usa UTF-8 conforme o MOC
      final file = File(arquivo.path!);
      final conteudo = await file.readAsString();

      return Sucesso(conteudo);
    } catch (e) {
      return Falha(
        TipoFalha.desconhecido,
        'Erro ao ler o arquivo: ${e.toString()}',
        detalhes: e,
      );
    }
  }

  // ============================================================
  // VALIDAÇÃO DO XML
  // ============================================================
  // Verifica se o conteúdo é um XML de NF-e estruturalmente válido.
  // Esta validação é ESTRUTURAL — não verifica assinatura digital.
  //
  // Retorna Sucesso(true) se válido, Falha se inválido.
  Resultado<bool> validarNFe(String xmlContent) {
    // ---- Passo 1: verifica se é XML bem formado ----
    XmlDocument document;
    try {
      document = XmlDocument.parse(xmlContent);
    } catch (e) {
      return Falha(
        TipoFalha.xmlInvalido,
        'O arquivo não é um XML válido. '
        'Verifique se o arquivo não está corrompido.',
        detalhes: e,
      );
    }

    // ---- Passo 2: verifica tags obrigatórias ----
    for (final tag in _tagsObrigatorias) {
      final elements = document.findAllElements(tag);
      if (elements.isEmpty) {
        return Falha(
          TipoFalha.xmlInvalido,
          'XML inválido: tag <$tag> não encontrada. '
          'Verifique se o arquivo é uma NF-e no leiaute 4.0.',
        );
      }
    }

    // ---- Passo 3: verifica chave de acesso ----
    try {
      final infNFe = document.findAllElements('infNFe').first;
      final idAtributo = infNFe.getAttribute('Id') ?? '';
      final chave = idAtributo.replaceFirst('NFe', '');

      if (chave.length != _tamanhoChaveAcesso) {
        return Falha(
          TipoFalha.xmlInvalido,
          'Chave de acesso inválida: '
          'encontrado ${chave.length} dígitos, '
          'esperado $_tamanhoChaveAcesso. '
          'O arquivo pode não ser uma NF-e válida.',
        );
      }

      // ---- Passo 4: verifica se tem pelo menos um item ----
      final itens = document.findAllElements('det');
      if (itens.isEmpty) {
        return Falha(
          TipoFalha.xmlInvalido,
          'XML inválido: nenhum item encontrado na nota. '
          'Uma NF-e deve ter pelo menos um produto.',
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
  // EXTRAÇÃO DA CHAVE DE ACESSO
  // ============================================================
  // Método utilitário para obter a chave sem parsear a nota inteira.
  // Usado para verificar duplicidade antes de processar o XML completo.
  Resultado<String> extrairChaveAcesso(String xmlContent) {
    try {
      final document = XmlDocument.parse(xmlContent);
      final infNFe = document.findAllElements('infNFe').first;
      final idAtributo = infNFe.getAttribute('Id') ?? '';
      final chave = idAtributo.replaceFirst('NFe', '');

      if (chave.length != _tamanhoChaveAcesso) {
        return Falha(
          TipoFalha.xmlInvalido,
          'Chave de acesso inválida no XML.',
        );
      }

      return Sucesso(chave);
    } catch (e) {
      return Falha(
        TipoFalha.xmlInvalido,
        'Não foi possível extrair a chave de acesso.',
        detalhes: e,
      );
    }
  }

  // ============================================================
  // PROCESSAMENTO COMPLETO
  // ============================================================
  // Método de conveniência que combina validação e parse.
  // Retorna um NotaFiscal pronto para ser salvo no banco.
  Resultado<NotaFiscal> processarXml(
    String xmlContent,
    String empresaId,
  ) {
    // Passo 1: valida estrutura
    final validacao = validarNFe(xmlContent);
    if (validacao is Falha) {
      return Falha(
        (validacao as Falha).tipo,
        (validacao as Falha).mensagem,
      );
    }

    // Passo 2: parseia e cria o objeto NotaFiscal
    try {
      final nota = NotaFiscal.fromXml(xmlContent, empresaId);
      return Sucesso(nota);
    } on FormatException catch (e) {
      return Falha(
        TipoFalha.xmlInvalido,
        e.message,
        detalhes: e,
      );
    } catch (e) {
      return Falha(
        TipoFalha.desconhecido,
        'Erro inesperado ao processar o XML.',
        detalhes: e,
      );
    }
  }
}