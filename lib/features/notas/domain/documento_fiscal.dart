// lib/features/notas/domain/documento_fiscal.dart
//
// ============================================================
// CONTEXTO LEGAL — LEIA ANTES DE MODIFICAR
// ============================================================
// DocumentoFiscal é a abstração base para qualquer documento
// fiscal eletrônico no sistema. No Brasil, os principais são:
//
//   NF-e  (modelo 55) — Nota Fiscal Eletrônica de produto
//   NFC-e (modelo 65) — Nota Fiscal de Consumidor Eletrônica
//   CT-e  (modelo 57) — Conhecimento de Transporte Eletrônico
//   MDF-e (modelo 58) — Manifesto Eletrônico de Documentos Fiscais
//
// Este sistema implementa apenas NF-e (modelo 55) no Módulo 1.
// A classe abstrata existe para que futuros documentos fiscais
// possam ser adicionados sem alterar o código existente —
// aplicando o Open/Closed Principle do SOLID.
//
// CONCEITO POO APLICADO:
// Herança com classe abstrata — DocumentoFiscal declara os campos
// e comportamentos comuns a qualquer documento fiscal.
// NotaFiscal estende e especializa para NF-e.
//
// ATENÇÃO LEGISLATIVA:
// Os campos desta classe refletem a estrutura do leiaute
// da NF-e versão 4.0, definida pelo Manual de Orientação
// ao Contribuinte (MOC) disponível em www.nfe.fazenda.gov.br.
// Em caso de atualização do leiaute pela SEFAZ, este arquivo
// e seus descendentes devem ser revisados.

abstract class DocumentoFiscal {
  // Identificador único interno do sistema (gerado pelo banco)
  final String id;

  // Identificador da empresa no sistema (multi-tenant)
  final String empresaId;

  // ============================================================
  // CHAVE DE ACESSO — campo legal mais importante
  // ============================================================
  // 44 dígitos que identificam unicamente o documento no Brasil.
  // Composição da chave de acesso NF-e:
  //   2 dígitos  — código IBGE do estado do emitente
  //   4 dígitos  — AAMM (ano e mês de emissão)
  //  14 dígitos  — CNPJ do emitente
  //   2 dígitos  — modelo (55 = NF-e, 65 = NFC-e)
  //   3 dígitos  — série da nota (001 a 999)
  //   9 dígitos  — número da nota (000000001 a 999999999)
  //   1 dígito   — forma de emissão (1 = normal, 6 = contingência)
  //   8 dígitos  — código numérico aleatório
  //   1 dígito   — dígito verificador (módulo 11)
  //
  // Esta chave é a nossa UNIQUE constraint no banco —
  // impossível importar a mesma nota duas vezes acidentalmente.
  final String chaveAcesso;

  // Número do documento (ex: 000001234)
  // Junto com série e CNPJ, identifica o documento para o emitente
  final String numero;

  // Série do documento (001 a 999)
  // Permite que um emitente tenha múltiplas séries em operação
  final String serie;

  // Tipo da operação:
  // 'entrada'  — mercadoria entrando no estoque (compra, devolução de venda)
  // 'saida'    — mercadoria saindo do estoque (venda, devolução de compra)
  final String tipo;

  // ============================================================
  // STATUS — máquina de estados do documento
  // ============================================================
  // Estados possíveis (definidos na Sessão 4):
  //   'importada'        — XML lido, dados extraídos
  //   'em_conferencia'   — conferência iniciada
  //   'conferida'        — todos os itens conferidos
  //   'divergente'       — diferença entre nota e físico
  //   'finalizada'       — encerrada, estoque atualizado (terminal)
  //   'cancelada'        — cancelada antes de finalizar (terminal)
  final String status;

  // Data e hora de emissão do documento pelo emitente
  // Importante: esta é a data fiscal do documento, não a data de importação
  final DateTime dataEmissao;

  // Valor total do documento em reais
  // Tipo double por ora — idealmente seria Decimal em produção
  // para evitar erros de arredondamento em cálculos fiscais
  final double valorTotal;

  // URL do XML original armazenado no Supabase Storage
  // O XML original tem valor probatório legal — nunca deve ser alterado
  final String? xmlUrl;

  // Soft delete — padrão do sistema
  final DateTime? inativoEm;
  final DateTime criadoEm;

  const DocumentoFiscal({
    required this.id,
    required this.empresaId,
    required this.chaveAcesso,
    required this.numero,
    required this.serie,
    required this.tipo,
    required this.status,
    required this.dataEmissao,
    required this.valorTotal,
    this.xmlUrl,
    this.inativoEm,
    required this.criadoEm,
  });

  // Propriedades derivadas — lógica de negócio no domínio
  bool get ativo => inativoEm == null;
  bool get finalizado => status == 'finalizada' || status == 'cancelada';
  bool get podeConferir => status == 'importada' || status == 'em_conferencia';
}