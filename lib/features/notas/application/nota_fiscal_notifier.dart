// lib/features/notas/application/nota_fiscal_notifier.dart
//
// CAMADA: application
// RESPONSABILIDADE: orquestrar o fluxo completo de importação
// de uma NF-e, desde a seleção do arquivo até o salvamento no banco.
//
// FLUXO COMPLETO:
//   1. Usuário clica em "Importar XML"
//   2. XmlService abre o seletor de arquivo
//   3. XmlService valida o XML estruturalmente
//   4. XmlService extrai a chave de acesso
//   5. Repositório verifica duplicidade pela chave
//   6. Se duplicada → estado NotaDuplicada (usuário decide)
//   7. XmlService parseia o XML completo → NotaFiscal
//   8. Repositório salva nota + itens + XML no Storage
//   9. Estado → NotaImportada com sucesso

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/resultado.dart';
import '../../../core/services/xml_service.dart';
import '../domain/i_nota_fiscal_repository.dart';
import '../domain/nota_fiscal.dart';
import '../infrastructure/supabase_nota_fiscal_repository.dart';
import '../../auth/application/auth_provider.dart';

// ============================================================
// PROVIDERS
// ============================================================
final xmlServiceProvider = Provider<XmlService>((ref) => XmlService());

final notaFiscalRepositoryProvider =
    Provider<INotaFiscalRepository>((ref) {
  return SupabaseNotaFiscalRepository();
});

// ============================================================
// SEALED CLASS DE ESTADO
// ============================================================
sealed class NotaFiscalState {}

class NotaFiscalInicial extends NotaFiscalState {}
class NotaFiscalCarregando extends NotaFiscalState {}

class NotaFiscalListaCarregada extends NotaFiscalState {
  final List<NotaFiscal> notas;
  NotaFiscalListaCarregada(this.notas);
}

// ============================================================
// ESTADO NotaFiscalImportada — agora carrega lista completa
// ============================================================
// Mudança: em vez de carregar só a nota nova, agora carrega
// todas as notas (incluindo a nova) para exibir a lista completa.
// O feedback de sucesso (snackbar) é disparado via ref.listen
// na NotasScreen ao detectar este estado.
class NotaFiscalImportada extends NotaFiscalState {
  final NotaFiscal nota;        // nota recém-importada (para o snackbar)
  final List<NotaFiscal> notas; // lista completa incluindo a nova
  final String mensagem;
  NotaFiscalImportada(this.nota, this.notas, this.mensagem);
}

// Estado especial: nota duplicada detectada
// A UI usa este estado para perguntar ao usuário o que fazer
class NotaDuplicada extends NotaFiscalState {
  final String chaveAcesso;
  final String mensagem;
  NotaDuplicada(this.chaveAcesso, this.mensagem);
}

class NotaFiscalErro extends NotaFiscalState {
  final String mensagem;
  NotaFiscalErro(this.mensagem);
}

class NotaFiscalVazio extends NotaFiscalState {}

// ============================================================
// NOTIFIER
// ============================================================
class NotaFiscalNotifier extends Notifier<NotaFiscalState> {
  @override
  NotaFiscalState build() {
    _carregarNotas();
    return NotaFiscalInicial();
  }

  XmlService get _xmlService => ref.read(xmlServiceProvider);
  INotaFiscalRepository get _repository =>
      ref.read(notaFiscalRepositoryProvider);

  // Obtém o empresaId do usuário autenticado
  // Necessário para associar a nota à empresa correta
  String get _empresaId {
    final authState = ref.read(authProvider);
    if (authState is AuthAutenticado) {
      return authState.usuario.empresaId;
    }
    throw Exception('Usuário não autenticado');
  }

  Future<void> _carregarNotas() async {
    state = NotaFiscalCarregando();
    final resultado = await _repository.buscarTodas();
    state = switch (resultado) {
      Sucesso(:final dados) => dados.isEmpty
          ? NotaFiscalVazio()
          : NotaFiscalListaCarregada(dados),
      Falha(:final mensagem) => NotaFiscalErro(mensagem),
    };
  }

  // ============================================================
  // MÉTODO PRINCIPAL — fluxo de importação
  // ============================================================
  Future<void> importarXml() async {
    state = NotaFiscalCarregando();

    // ---- Passo 1: seleciona arquivo ----
    final arquivoResultado = await _xmlService.selecionarArquivo();
    if (arquivoResultado is Falha) {
      await _carregarNotas();
      return;
    }
    final xmlContent = (arquivoResultado as Sucesso<String>).dados;

    // ---- Passo 2: valida XML ----
    final validacao = _xmlService.validarNFe(xmlContent);
    if (validacao is Falha) {
      state = NotaFiscalErro((validacao as Falha).mensagem);
      return;
    }

    // ---- Passo 3: extrai chave ----
    final chaveResultado = _xmlService.extrairChaveAcesso(xmlContent);
    if (chaveResultado is Falha) {
      state = NotaFiscalErro((chaveResultado as Falha).mensagem);
      return;
    }
    final chaveAcesso = (chaveResultado as Sucesso<String>).dados;

    // ---- Passo 4: verifica duplicidade ----
    final duplicidadeResultado =
        await _repository.verificarDuplicidade(chaveAcesso);
    if (duplicidadeResultado is Sucesso<bool>) {
      if ((duplicidadeResultado).dados) {
        state = NotaDuplicada(
          chaveAcesso,
          'Esta nota fiscal já foi importada anteriormente.\n'
          'Chave: $chaveAcesso\n\n'
          'Deseja navegar para a nota existente?',
        );
        return;
      }
    }

    // ---- Passo 5: parseia XML ----
    final parseResultado = _xmlService.processarXml(xmlContent, _empresaId);
    if (parseResultado is Falha) {
      state = NotaFiscalErro((parseResultado as Falha).mensagem);
      return;
    }
    final nota = (parseResultado as Sucesso<NotaFiscal>).dados;

    // ---- Passo 6: salva no banco ----
    final importacaoResultado = await _repository.importar(
      nota: nota,
      xmlContent: xmlContent,
    );

    if (importacaoResultado is Falha) {
      final f = importacaoResultado as Falha;
      state = switch (f.tipo) {
        TipoFalha.duplicidade => NotaDuplicada(chaveAcesso, f.mensagem),
        TipoFalha.rede => NotaFiscalErro('Sem conexão. Verifique sua internet.'),
        _ => NotaFiscalErro(f.mensagem),
      };
      return;
    }

    final notaImportada = (importacaoResultado as Sucesso<NotaFiscal>).dados;

    // ---- Passo 7: busca lista completa atualizada ----
    // CORREÇÃO BUG 2: em vez de emitir só a nota nova,
    // buscamos todas as notas para exibir a lista completa
    // imediatamente, sem que o usuário precise dar refresh manual.
    final listaResultado = await _repository.buscarTodas();
    final todasNotas = listaResultado is Sucesso<List<NotaFiscal>>
        ? (listaResultado).dados
        : [notaImportada];

    state = NotaFiscalImportada(
      notaImportada,
      todasNotas,
      'Nota fiscal importada com sucesso!\n'
      '${notaImportada.emitenteNome} — ${notaImportada.itens.length} item(ns)',
    );
  }

  Future<void> recarregar() => _carregarNotas();
}

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
// Provider de detalhe de nota específica por ID
// Parametrizado com .family — cada nota ID tem cache independente
// Movido para application/ porque providers pertencem a esta camada,
// não a presentation/. Isso permite que outros widgets e telas
// acessem o detalhe de uma nota sem depender de uma tela específica.

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

final notaFiscalProvider =
    NotifierProvider<NotaFiscalNotifier, NotaFiscalState>(() {
  return NotaFiscalNotifier();
});