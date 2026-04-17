// lib/features/conferencia/application/conferencia_notifier.dart
//
// CAMADA: application
// RESPONSABILIDADE: orquestrar o fluxo de conferência — iniciar,
// pausar, retomar, registrar itens e finalizar.
//
// SEALED CLASS DE ESTADO — cobre todos os momentos possíveis da UI:
//
//   ConferenciaInicial      → tela ainda não carregou
//   ConferenciaCarregando   → operação em andamento
//   ConferenciaListaCarregada → lista de conferências da nota
//   ConferenciaAtiva        → conferência em progresso (tela ativa)
//   ConferenciaVazio        → nota sem conferências
//   ConferenciaErro         → falha na operação

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/resultado.dart';
import '../../../features/auth/application/auth_provider.dart';
import '../domain/conferencia.dart';
import '../domain/conferencia_item.dart';
import '../domain/i_conferencia_repository.dart';
import '../infrastructure/supabase_conferencia_repository.dart';

// ============================================================
// PROVIDERS
// ============================================================
final conferenciaRepositoryProvider =
    Provider<IConferenciaRepository>((ref) {
  return SupabaseConferenciaRepository();
});

// ============================================================
// SEALED CLASS DE ESTADO
// ============================================================
sealed class ConferenciaState {}

class ConferenciaInicial extends ConferenciaState {}
class ConferenciaCarregando extends ConferenciaState {}

class ConferenciaListaCarregada extends ConferenciaState {
  final List<Conferencia> conferencias;
  // notaId para contexto — saber a qual nota pertencem as conferências
  final String notaId;
  ConferenciaListaCarregada(this.conferencias, {required this.notaId});
}

// Estado especial: conferência aberta e em andamento
// A tela de conferência ativa usa este estado para exibir
// o progresso em tempo real e permitir ações
class ConferenciaAtiva extends ConferenciaState {
  final Conferencia conferencia;
  ConferenciaAtiva(this.conferencia);
}

class ConferenciaVazio extends ConferenciaState {
  final String notaId;
  ConferenciaVazio(this.notaId);
}

class ConferenciaErro extends ConferenciaState {
  final String mensagem;
  ConferenciaErro(this.mensagem);
}

// ============================================================
// NOTIFIER
// ============================================================
class ConferenciaNotifier extends Notifier<ConferenciaState> {
  @override
  ConferenciaState build() => ConferenciaInicial();

  IConferenciaRepository get _repository =>
      ref.read(conferenciaRepositoryProvider);

  // Obtém dados do usuário autenticado
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

  // ---- Carrega lista de conferências de uma nota ----
  Future<void> carregarPorNota(String notaId) async {
    state = ConferenciaCarregando();
    final resultado = await _repository.buscarPorNota(notaId);
    state = switch (resultado) {
      Sucesso(:final dados) => dados.isEmpty
          ? ConferenciaVazio(notaId)
          : ConferenciaListaCarregada(dados, notaId: notaId),
      Falha(:final mensagem) => ConferenciaErro(mensagem),
    };
  }

  // ---- Inicia nova conferência ----
  // itensNota: lista de maps com 'id' e 'quantidade' dos ItemNota
  Future<void> iniciar(
      String notaId, List<Map<String, dynamic>> itensNota) async {
    state = ConferenciaCarregando();
    final resultado = await _repository.iniciar(
      notaId: notaId,
      operadorId: _operadorId,
      empresaId: _empresaId,
      itensNota: itensNota,
    );
    state = switch (resultado) {
      Sucesso(:final dados) => ConferenciaAtiva(dados),
      Falha(:final mensagem) => ConferenciaErro(mensagem),
    };
  }

  // ---- Abre conferência existente para continuar ----
  Future<void> abrirConferencia(String conferenciaId) async {
    state = ConferenciaCarregando();
    final resultado = await _repository.buscarPorId(conferenciaId);
    state = switch (resultado) {
      Sucesso(:final dados) => ConferenciaAtiva(dados),
      Falha(:final mensagem) => ConferenciaErro(mensagem),
    };
  }

  // ---- Pausa a conferência em andamento ----
  Future<void> pausar(String conferenciaId) async {
    final resultado = await _repository.atualizarStatus(
      id: conferenciaId,
      novoStatus: 'pausada',
    );
    if (resultado is Sucesso<Conferencia>) {
      state = ConferenciaAtiva((resultado).dados);
    } else if (resultado is Falha) {
      state = ConferenciaErro((resultado as Falha).mensagem);
    }
  }

  // ---- Retoma conferência pausada ----
  Future<void> retomar(String conferenciaId) async {
    final resultado = await _repository.atualizarStatus(
      id: conferenciaId,
      novoStatus: 'em_andamento',
    );
    if (resultado is Sucesso<Conferencia>) {
      state = ConferenciaAtiva((resultado).dados);
    } else if (resultado is Falha) {
      state = ConferenciaErro((resultado as Falha).mensagem);
    }
  }

  // ---- Registra quantidade conferida de um item ----
  Future<void> registrarItem({
    required String conferenciaId,
    required String conferenciaItemId,
    required double quantidadeConferida,
    String? observacao,
  }) async {
    final resultado = await _repository.registrarItem(
      conferenciaItemId: conferenciaItemId,
      quantidadeConferida: quantidadeConferida,
      observacao: observacao,
    );

    if (resultado is Falha) {
      state = ConferenciaErro((resultado as Falha).mensagem);
      return;
    }

    // Recarrega a conferência completa para atualizar o progresso
    final confResult = await _repository.buscarPorId(conferenciaId);
    state = switch (confResult) {
      Sucesso(:final dados) => ConferenciaAtiva(dados),
      Falha(:final mensagem) => ConferenciaErro(mensagem),
    };
  }

  // ---- Tenta finalizar — verifica divergências antes ----
  Future<void> tentarFinalizar(String conferenciaId) async {
    // Busca estado atual para verificar divergências
    final confResult = await _repository.buscarPorId(conferenciaId);
    if (confResult is Falha) {
      state = ConferenciaErro((confResult as Falha).mensagem);
      return;
    }

    final conf = (confResult as Sucesso<Conferencia>).dados;

    if (conf.temDivergencia) {
      // Há divergência — vai para aguardando_aprovacao
      final resultado = await _repository.atualizarStatus(
        id: conferenciaId,
        novoStatus: 'aguardando_aprovacao',
      );
      state = switch (resultado) {
        Sucesso(:final dados) => ConferenciaAtiva(dados),
        Falha(:final mensagem) => ConferenciaErro(mensagem),
      };
    } else if (conf.todosItensVerificados) {
      // Sem divergência e todos conferidos — finaliza diretamente
      final resultado = await _repository.atualizarStatus(
        id: conferenciaId,
        novoStatus: 'concluida',
      );
      state = switch (resultado) {
        Sucesso(:final dados) => ConferenciaAtiva(dados),
        Falha(:final mensagem) => ConferenciaErro(mensagem),
      };
    } else {
      state = ConferenciaErro(
        'Ainda existem itens não conferidos. '
        'Confira todos os itens antes de finalizar.',
      );
    }
  }

  // ---- Cancela a conferência com motivo ----
  Future<void> cancelar(String conferenciaId, String motivo) async {
    state = ConferenciaCarregando();
    final resultado = await _repository.cancelar(
      id: conferenciaId,
      motivo: motivo,
    );
    if (resultado is Falha) {
      state = ConferenciaErro((resultado).mensagem);
    }
    // Após cancelar, volta para a lista da nota
  }
}

final conferenciaProvider =
    NotifierProvider<ConferenciaNotifier, ConferenciaState>(() {
  return ConferenciaNotifier();
});