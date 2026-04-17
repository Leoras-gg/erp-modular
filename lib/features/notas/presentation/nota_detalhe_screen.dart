// lib/features/notas/presentation/nota_detalhe_screen.dart
//
// CAMADA: presentation
// RESPONSABILIDADE: exibir os detalhes completos de uma nota fiscal,
// incluindo a lista de todos os itens com seus dados fiscais.
//
// CONCEITO DE NAVEGAÇÃO — por que tela separada?
// A listagem de notas exibe cards simplificados (número, emitente, valor, count).
// O detalhe exibe tudo: itens, NCM, CFOP, quantidades, valores individuais.
// Separar em telas diferentes segue o princípio de Single Responsibility —
// cada tela tem um propósito claro.
//
// FLUXO:
//   NotasScreen (lista de cards)
//     → toca no card
//     → GoRouter navega para /notas/:id
//     → NotaDetalheScreen carrega nota completa por ID
//
// INPUT esperado: notaId via parâmetro de rota (GoRouter state.pathParameters)
// OUTPUT: tela com dados da nota e lista de ItemNota completos

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/nota_fiscal_notifier.dart';
import '../domain/item_nota.dart';
import '../domain/nota_fiscal.dart';
// Adiciona estas duas linhas no início do arquivo, junto com os outros imports:
import '../../../core/errors/resultado.dart';
// ignore: unused_import
import 'package:go_router/go_router.dart';

// ============================================================
// PROVIDER DE DETALHE — carrega nota específica por ID
// ============================================================
// Conceito Riverpod: Family providers permitem criar um provider
// parametrizado. notaDetalheProvider(id) cria um provider único
// para cada nota ID — cada ID tem seu próprio cache e estado.
//
// Por que não reusar o notaFiscalProvider?
// O notaFiscalProvider gerencia o estado da LISTAGEM.
// O notaDetalheProvider gerencia o estado de UMA NOTA ESPECÍFICA.
// São responsabilidades diferentes — providers diferentes.
final notaDetalheProvider = FutureProvider.family<NotaFiscal, String>(
  (ref, notaId) async {
    // Acessa o repositório diretamente via provider
    // Para carregar uma nota por ID com todos os itens
    final repository = ref.read(notaFiscalRepositoryProvider);
    final resultado = await repository.buscarPorId(notaId);

    return switch (resultado) {
      Sucesso(:final dados) => dados,
      Falha(:final mensagem) => throw Exception(mensagem),
    };
  },
);

class NotaDetalheScreen extends ConsumerWidget {
  // notaId: UUID da nota a ser exibida, vem do parâmetro de rota
  final String notaId;

  const NotaDetalheScreen({super.key, required this.notaId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // AsyncValue é o tipo retornado por FutureProvider
    // Tem três estados: loading, data, error
    // Conceito: o Riverpod gerencia o ciclo de vida do Future automaticamente
    final asyncNota = ref.watch(notaDetalheProvider(notaId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes da Nota'),
        // leading: botão voltar automático do GoRouter
      ),
      body: switch (asyncNota) {
        // Estado de carregamento — nota sendo buscada no banco
        AsyncLoading() => const Center(child: CircularProgressIndicator()),

        // Erro ao carregar — mensagem com botão de tentar novamente
        AsyncError(:final error) => _ErroDetalhe(
            mensagem: error.toString(),
            onRetentar: () => ref.invalidate(notaDetalheProvider(notaId)),
          ),

        // Nota carregada com sucesso
        AsyncData(:final value) => _ConteudoDetalhe(nota: value),
      },
    );
  }
}

// ============================================================
// CONTEÚDO PRINCIPAL DA TELA
// ============================================================
class _ConteudoDetalhe extends StatelessWidget {
  final NotaFiscal nota;

  const _ConteudoDetalhe({required this.nota});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- CABEÇALHO DA NOTA ----
          _CabecalhoNota(nota: nota),
          const SizedBox(height: 24),

          // ---- DADOS DO EMITENTE ----
          _SecaoEmitente(nota: nota),
          const SizedBox(height: 24),

          // ---- LISTA DE ITENS ----
          _SecaoItens(itens: nota.itens),
          const SizedBox(height: 24),

          // ---- TOTAIS ----
          _SecaoTotais(nota: nota),
        ],
      ),
    );
  }
}

// ============================================================
// CABEÇALHO — dados de identificação da nota
// ============================================================
class _CabecalhoNota extends StatelessWidget {
  final NotaFiscal nota;

  const _CabecalhoNota({required this.nota});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título com número e série
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'NF-e ${nota.numero} / Série ${nota.serie}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                // Badge de status colorido
                _StatusBadge(status: nota.status),
              ],
            ),
            const SizedBox(height: 12),

            // Chave de acesso — dado legal mais importante
            Text(
              'Chave de acesso:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            // SelectableText permite o usuário copiar a chave
            SelectableText(
              nota.chaveAcesso,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const Divider(height: 24),

            // Dados gerais
            _LinhaDado(
              label: 'Tipo',
              valor: nota.tipo == 'entrada' ? 'Entrada (compra)' : 'Saída (venda)',
            ),
            _LinhaDado(
              label: 'Data de emissão',
              valor: _formatarData(nota.dataEmissao),
            ),
            _LinhaDado(
              label: 'Total de itens',
              valor: '${nota.totalItens} item(ns)',
            ),
            // Após os _LinhaDado existentes, adiciona:
const SizedBox(height: 12),
SizedBox(
  width: double.infinity,
  child: FilledButton.icon(
    onPressed: () =>
        context.push('/notas/${nota.id}/conferencias'),
    icon: const Icon(Icons.assignment_outlined),
    label: const Text('Ver conferências'),
  ),
),
          ],
        ),
      ),
    );
  }

  String _formatarData(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/'
        '${data.year}';
  }
}

// ============================================================
// SEÇÃO EMITENTE — dados do fornecedor/remetente
// ============================================================
class _SecaoEmitente extends StatelessWidget {
  final NotaFiscal nota;

  const _SecaoEmitente({required this.nota});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Emitente',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _LinhaDado(label: 'Razão Social', valor: nota.emitenteNome),
                _LinhaDado(
                  label: 'CNPJ',
                  valor: _formatarCnpj(nota.emitenteCnpj),
                ),
                _LinhaDado(label: 'UF', valor: nota.emitenteUf),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Formata CNPJ: 00.000.000/0000-00
  String _formatarCnpj(String cnpj) {
    if (cnpj.length != 14) return cnpj;
    return '${cnpj.substring(0, 2)}.${cnpj.substring(2, 5)}'
        '.${cnpj.substring(5, 8)}/${cnpj.substring(8, 12)}'
        '-${cnpj.substring(12)}';
  }
}

// ============================================================
// SEÇÃO ITENS — lista completa dos produtos da nota
// ============================================================
class _SecaoItens extends StatelessWidget {
  final List<ItemNota> itens;

  const _SecaoItens({required this.itens});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Itens da nota (${itens.length})',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),

        // Lista de itens — um card por item
        ...itens.map((item) => _ItemCard(item: item)),
      ],
    );
  }
}

// ============================================================
// CARD DE ITEM — exibe dados completos de um produto da nota
// ============================================================
class _ItemCard extends StatelessWidget {
  final ItemNota item;

  const _ItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Linha: número do item + descrição
            Row(
              children: [
                // Número do item em destaque
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${item.numeroItem}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.descricaoProduto,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Dados fiscais — NCM e CFOP são campos legais importantes
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _ChipInfo(label: 'NCM', valor: item.ncm),
                _ChipInfo(label: 'CFOP', valor: item.cfop),
                if (item.codigoBarras != null)
                  _ChipInfo(label: 'EAN', valor: item.codigoBarras!),
              ],
            ),
            const SizedBox(height: 8),

            // Quantidade e valores
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_formatarQtd(item.quantidade)} ${item.unidadeMedida}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  'R\$ ${item.valorTotal.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Unitário: R\$ ${item.valorUnitario.toStringAsFixed(4)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),

            // Dados de lote — quando disponível
            if (item.lote != null) ...[
              const Divider(height: 16),
              Row(
                children: [
                  Icon(Icons.qr_code_outlined,
                      size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    'Lote: ${item.lote!}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (item.dataValidade != null) ...[
                    const SizedBox(width: 16),
                    Icon(Icons.event_outlined,
                        size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      'Val: ${_formatarDataCurta(item.dataValidade!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ],

            // Código do produto no emitente (para conferência futura)
            const SizedBox(height: 4),
            Text(
              'Cód. emitente: ${item.codigoProdutoEmitente}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // Formata quantidade: remove zeros desnecessários
  String _formatarQtd(double qtd) {
    if (qtd == qtd.truncateToDouble()) return qtd.toInt().toString();
    return qtd.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '');
  }

  String _formatarDataCurta(DateTime data) {
    return '${data.month.toString().padLeft(2, '0')}/${data.year}';
  }
}

// ============================================================
// SEÇÃO TOTAIS
// ============================================================
class _SecaoTotais extends StatelessWidget {
  final NotaFiscal nota;

  const _SecaoTotais({required this.nota});

  @override
  Widget build(BuildContext context) {
    // Soma dos itens para conferência visual
    final somaItens = nota.itens.fold(0.0, (acc, i) => acc + i.valorTotal);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _LinhaDado(
              label: 'Soma dos itens',
              valor: 'R\$ ${somaItens.toStringAsFixed(2)}',
            ),
            const Divider(),
            _LinhaDado(
              label: 'Valor total da nota',
              valor: 'R\$ ${nota.valorTotal.toStringAsFixed(2)}',
              destaque: true,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// WIDGETS AUXILIARES
// ============================================================

// Badge de status — mesmo padrão da NotasScreen
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (cor, label) = switch (status) {
      'importada'        => (Colors.blue, 'Importada'),
      'em_conferencia'   => (Colors.orange, 'Em conferência'),
      'conferida'        => (Colors.teal, 'Conferida'),
      'divergente'       => (Colors.red, 'Divergente'),
      'finalizada'       => (Colors.green, 'Finalizada'),
      'cancelada'        => (Colors.grey, 'Cancelada'),
      _                  => (Colors.grey, status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: cor, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

// Chip de informação fiscal — NCM, CFOP, EAN
class _ChipInfo extends StatelessWidget {
  final String label;
  final String valor;
  const _ChipInfo({required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $valor',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

// Linha de dado label: valor
class _LinhaDado extends StatelessWidget {
  final String label;
  final String valor;
  final bool destaque;
  const _LinhaDado({
    required this.label,
    required this.valor,
    this.destaque = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
          Text(
            valor,
            style: destaque
                ? Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    )
                : Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
          ),
        ],
      ),
    );
  }
}

// Estado de erro
class _ErroDetalhe extends StatelessWidget {
  final String mensagem;
  final VoidCallback onRetentar;
  const _ErroDetalhe({required this.mensagem, required this.onRetentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(mensagem, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetentar,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}