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

class NotaFiscalImportada extends NotaFiscalState {
  final NotaFiscal nota;
  // Mensagem de sucesso para exibir na UI
  final String mensagem;
  NotaFiscalImportada(this.nota, this.mensagem);
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
      // Usuário cancelou — volta ao estado anterior sem erro
      await _carregarNotas();
      return;
    }

    final xmlContent = (arquivoResultado as Sucesso<String>).dados;

    // ---- Passo 2: valida estrutura do XML ----
    final validacao = _xmlService.validarNFe(xmlContent);
    if (validacao is Falha) {
      state = NotaFiscalErro((validacao as Falha).mensagem);
      return;
    }

    // ---- Passo 3: extrai chave para verificar duplicidade ----
    final chaveResultado = _xmlService.extrairChaveAcesso(xmlContent);
    if (chaveResultado is Falha) {
      state = NotaFiscalErro((chaveResultado as Falha).mensagem);
      return;
    }

    final chaveAcesso = (chaveResultado as Sucesso<String>).dados;

    // ---- Passo 4: verifica duplicidade ----
    final duplicidadeResultado =
        await _repository.verificarDuplicidade(chaveAcesso);

    if (duplicidadeResultado is Sucesso) {
      final jaCadastrada =
          (duplicidadeResultado as Sucesso<bool>).dados;

      if (jaCadastrada) {
        // Nota duplicada — informa a UI para decidir o que fazer
        state = NotaDuplicada(
          chaveAcesso,
          'Esta nota fiscal já foi importada anteriormente.\n'
          'Chave: $chaveAcesso\n\n'
          'Deseja navegar para a nota existente?',
        );
        return;
      }
    }

    // ---- Passo 5: parseia o XML ----
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

    state = switch (importacaoResultado) {
      Sucesso(:final dados) => NotaFiscalImportada(
          dados,
          'Nota fiscal importada com sucesso!\n'
          '${dados.emitenteNome} — ${dados.itens.length} item(ns)',
        ),
      Falha(:final tipo, :final mensagem) => switch (tipo) {
          TipoFalha.duplicidade => NotaDuplicada(chaveAcesso, mensagem),
          TipoFalha.rede => NotaFiscalErro('Sem conexão. Verifique sua internet.'),
          _ => NotaFiscalErro(mensagem),
        },
    };
  }

  Future<void> recarregar() => _carregarNotas();
}

final notaFiscalProvider =
    NotifierProvider<NotaFiscalNotifier, NotaFiscalState>(() {
  return NotaFiscalNotifier();
});