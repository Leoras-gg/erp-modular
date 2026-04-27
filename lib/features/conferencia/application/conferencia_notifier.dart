// lib/features/conferencia/application/conferencia_notifier.dart
//
// CAMADA: application
//
// ============================================================
// REFATORAÇÃO: DOIS PROVIDERS SEPARADOS
// ============================================================
// PROBLEMA original: um único conferenciaProvider global era usado
// tanto pela lista quanto pela tela ativa. Isso causava:
//   - Pushes duplicados (listener reagia a estado persistido)
//   - Tela ativa carregando infinitamente ao voltar (estado da lista
//     sobrescrevia estado da conferência)
//   - Loop de navegação ao reabrir conferência
//
// SOLUÇÃO: dois providers com responsabilidades distintas:
//
//   conferenciaListaProvider  → gerencia a lista de conferências de uma nota
//                               usado exclusivamente por ConferenciaListaScreen
//
//   conferenciaAtivaProvider  → gerencia UMA conferência específica aberta
//                               usado exclusivamente por ConferenciaAtivaScreen
//
// CONCEITO: Single Responsibility aplicado a providers.
// Cada provider tem um único motivo para mudar de estado.
// Mudanças na lista não afetam a tela ativa e vice-versa.

import '../../estoque/domain/i_movimentacao_repository.dart';
import '../../estoque/infrastructure/supabase_movimentacao_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/resultado.dart';
import '../../../features/auth/application/auth_provider.dart';
import '../domain/conferencia.dart';
import '../domain/i_conferencia_repository.dart';
import '../infrastructure/supabase_conferencia_repository.dart';
import '../../notas/application/nota_fiscal_notifier.dart';

// Provider do repositório — compartilhado pelos dois notifiers
final conferenciaRepositoryProvider =
    Provider<IConferenciaRepository>((ref) {
  return SupabaseConferenciaRepository();
});

final movimentacaoRepositoryProvider =
    Provider<IMovimentacaoRepository>((ref) {
  return SupabaseMovimentacaoRepository();
});

// ============================================================
// SEALED CLASSES DE ESTADO — LISTA
// ============================================================
sealed class ConferenciaListaState {}

class ConferenciaListaInicial   extends ConferenciaListaState {}
class ConferenciaListaCarregando extends ConferenciaListaState {}

class ConferenciaListaCarregada extends ConferenciaListaState {
  final List<Conferencia> conferencias;
  final String notaId;
  ConferenciaListaCarregada(this.conferencias, {required this.notaId});
}

class ConferenciaListaVazio extends ConferenciaListaState {
  final String notaId;
  ConferenciaListaVazio(this.notaId);
}

class ConferenciaListaErro extends ConferenciaListaState {
  final String mensagem;
  ConferenciaListaErro(this.mensagem);
}

// ============================================================
// SEALED CLASSES DE ESTADO — ATIVA
// ============================================================
sealed class ConferenciaAtivaState {}

class ConferenciaAtivaInicial   extends ConferenciaAtivaState {}
class ConferenciaAtivaCarregando extends ConferenciaAtivaState {}

class ConferenciaAtivaCarregada extends ConferenciaAtivaState {
  final Conferencia conferencia;
  ConferenciaAtivaCarregada(this.conferencia);
}

class ConferenciaAtivaErro extends ConferenciaAtivaState {
  final String mensagem;
  ConferenciaAtivaErro(this.mensagem);
}

// ============================================================
// NOTIFIER DA LISTA
// ============================================================
// Responsabilidade: listar e iniciar conferências de uma nota.
// NÃO gerencia o estado da conferência aberta.
class ConferenciaListaNotifier
    extends Notifier<ConferenciaListaState> {
  @override
  ConferenciaListaState build() => ConferenciaListaInicial();

  IConferenciaRepository get _repo =>
      ref.read(conferenciaRepositoryProvider);

  String get _operadorId {
    final auth = ref.read(authProvider);
    if (auth is AuthAutenticado) return auth.usuario.id;
    throw Exception('Usuário não autenticado');
  }

  String get _empresaId {
    final auth = ref.read(authProvider);
    if (auth is AuthAutenticado) return auth.usuario.empresaId;
    throw Exception('Usuário não autenticado');
  }

  Future<void> carregar(String notaId) async {
    state = ConferenciaListaCarregando();
    final resultado = await _repo.buscarPorNota(notaId);
    state = switch (resultado) {
      Sucesso(:final dados) => dados.isEmpty
          ? ConferenciaListaVazio(notaId)
          : ConferenciaListaCarregada(dados, notaId: notaId),
      Falha(:final mensagem) => ConferenciaListaErro(mensagem),
    };
  }

  // Inicia conferência e retorna o ID para navegação
  // Não muda o estado para ConferenciaAtiva — isso é responsabilidade
  // do conferenciaAtivaProvider. Aqui apenas criamos no banco.
  Future<String?> iniciar(
      String notaId, List<Map<String, dynamic>> itensNota) async {
    state = ConferenciaListaCarregando();
    final resultado = await _repo.iniciar(
      notaId: notaId,
      operadorId: _operadorId,
      empresaId: _empresaId,
      itensNota: itensNota,
    );
    return switch (resultado) {
      Sucesso(:final dados) => dados.id,
      Falha(:final mensagem) => () {
          state = ConferenciaListaErro(mensagem);
          return null;
        }(),
    };
  }
}

final conferenciaListaProvider =
    NotifierProvider<ConferenciaListaNotifier, ConferenciaListaState>(
        () => ConferenciaListaNotifier());

// ============================================================
// NOTIFIER DA CONFERÊNCIA ATIVA
// ============================================================
// Responsabilidade: carregar e operar uma conferência específica.
// NÃO sabe nada sobre a lista de conferências.
class ConferenciaAtivaNotifier
    extends Notifier<ConferenciaAtivaState> {
  @override
  ConferenciaAtivaState build() => ConferenciaAtivaInicial();

  IConferenciaRepository get _repo =>
      ref.read(conferenciaRepositoryProvider);

      String get _operadorId {
    final auth = ref.read(authProvider);
    if (auth is AuthAutenticado) return auth.usuario.id;
    throw Exception('Usuário não autenticado');
  }

  String get _empresaId {
    final auth = ref.read(authProvider);
    if (auth is AuthAutenticado) return auth.usuario.empresaId;
    throw Exception('Usuário não autenticado');
  }

  Future<void> carregar(String conferenciaId) async {
    state = ConferenciaAtivaCarregando();
    final resultado = await _repo.buscarPorId(conferenciaId);
    state = switch (resultado) {
      Sucesso(:final dados) => ConferenciaAtivaCarregada(dados),
      Falha(:final mensagem) => ConferenciaAtivaErro(mensagem),
    };
  }

  Future<void> pausar(String id) async {
    final resultado =
        await _repo.atualizarStatus(id: id, novoStatus: 'pausada');
    _aplicarResultado(resultado);
  }

  Future<void> retomar(String id) async {
    final resultado =
        await _repo.atualizarStatus(id: id, novoStatus: 'em_andamento');
    _aplicarResultado(resultado);
  }

  Future<void> registrarItem({
    required String conferenciaId,
    required String conferenciaItemId,
    required double quantidadeConferida,
    String? observacao,
  }) async {
    final resultado = await _repo.registrarItem(
      conferenciaItemId: conferenciaItemId,
      quantidadeConferida: quantidadeConferida,
      observacao: observacao,
    );
    if (resultado is Falha) {
      state = ConferenciaAtivaErro((resultado as Falha).mensagem);
      return;
    }
    // Recarrega para atualizar progresso
    await carregar(conferenciaId);
  }

  Future<void> tentarFinalizar(String conferenciaId) async {
    final confResult = await _repo.buscarPorId(conferenciaId);
    if (confResult is Falha) {
      state = ConferenciaAtivaErro((confResult as Falha).mensagem);
      return;
    }
    final conf = (confResult as Sucesso<Conferencia>).dados;

    if (!conf.todosItensVerificados) {
      state = ConferenciaAtivaErro(
        'Ainda existem ${conf.totalItensPendentes} item(ns) não conferidos.',
      );
      return;
    }

    if (conf.temDivergencia) {
      // Com divergência → supervisor aprova antes de finalizar
      // Não registra movimentações ainda
      final resultado = await _repo.atualizarStatus(
        id: conferenciaId,
        novoStatus: 'aguardando_aprovacao',
      );
      _aplicarResultado(resultado);
      return;
    }

    // ============================================================
    // Sem divergência → registra movimentações e finaliza
    // ============================================================
    state = ConferenciaAtivaCarregando();

    final itensConferencia = conf.itens
        .where((i) => i.quantidadeConferida > 0)
        .map((i) => {
              'nota_item_id': i.notaItemId,
              'quantidade_conferida': i.quantidadeConferida,
              'lote': null, // lote resolvido via nota_itens no repositório
            })
        .toList();

    // Passo 1: registra movimentações de entrada no estoque
    final movResult = await ref
        .read(movimentacaoRepositoryProvider)
        .registrarEntradaConferencia(
          conferenciaId: conferenciaId,
          notaId: conf.notaId,
          operadorId: _operadorId,
          empresaId: _empresaId,
          itensConferencia: itensConferencia,
        );

    if (movResult is Falha) {
      state = ConferenciaAtivaErro((movResult as Falha).mensagem);
      return;
    }

    // Passo 2: atualiza status da conferência para 'concluida'
    // Via conferenciaRepository — separação correta de responsabilidades
    // O repositório de movimentações não deve atualizar a conferência
    final finalizarResult = await _repo.atualizarStatus(
      id: conferenciaId,
      novoStatus: 'concluida',
    );

    if (finalizarResult is Falha) {
      state = ConferenciaAtivaErro((finalizarResult as Falha).mensagem);
      return;
    }

    // Passo 3: recarrega a conferência ativa com status atualizado
    await carregar(conferenciaId);

    // Passo 4: propaga atualização para a lista de notas fiscais
    //
    // IMPORTANTE — por que NÃO usar ref.invalidate(conferenciaListaProvider):
    // A ConferenciaListaScreen já tem um .then() no context.push() que chama
    // carregar() ao voltar. Se invalidarmos o provider aqui, o notifier é
    // recriado enquanto a tela ainda está tentando usá-lo via .then(),
    // causando loop de carregamento infinito.
    //
    // Por que usar .recarregar() em vez de ref.invalidate(notaFiscalProvider):
    // notaFiscalProvider é NotifierProvider — invalidate() recria o notifier
    // inteiro, que pode ter side effects. .recarregar() chama o método correto
    // no notifier existente, forçando busca do banco com o status atualizado.
    try {
      ref.read(notaFiscalProvider.notifier).recarregar();
    } catch (_) {
      // notaFiscalProvider pode não estar ativo se o usuário não passou
      // pela tela de notas — ignorar silenciosamente
    }
  }

  Future<void> cancelar(String id, String motivo) async {
    final resultado =
        await _repo.cancelar(id: id, motivo: motivo);
    if (resultado is Falha) {
      state = ConferenciaAtivaErro((resultado).mensagem);
    }
    // Se sucesso, a tela vai fechar via Navigator.pop()
  }

  void _aplicarResultado(Resultado<Conferencia> resultado) {
    state = switch (resultado) {
      Sucesso(:final dados) => ConferenciaAtivaCarregada(dados),
      Falha(:final mensagem) => ConferenciaAtivaErro(mensagem),
    };
  }
}

final conferenciaAtivaProvider =
    NotifierProvider<ConferenciaAtivaNotifier, ConferenciaAtivaState>(
        () => ConferenciaAtivaNotifier());