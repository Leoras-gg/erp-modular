// lib/features/auth/application/auth_provider.dart
//
// CAMADA: application
// RESPONSABILIDADE: gerenciar o estado de autenticação e orquestrar
// as chamadas ao repositório. Esta camada não sabe como os dados
// são persistidos — só sabe o que precisa acontecer.
//
// CONCEITOS APLICADOS:
// - Dependency Injection via Riverpod (authRepositoryProvider)
// - Sealed class para modelagem de estados (tipo soma)
// - Notifier v3 para máquina de estados finita
// - SOLID: Dependency Inversion — depende de IAuthRepository, não de Supabase

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/usuario.dart';
import '../domain/i_auth_repository.dart';
import '../infrastructure/supabase_auth_repository.dart';

// ============================================================
// INJEÇÃO DE DEPENDÊNCIA — Provider do repositório
// ============================================================
// Este provider é o ponto de injeção da implementação concreta.
// O AuthNotifier nunca instancia SupabaseAuthRepository diretamente —
// ele recebe via ref.read(authRepositoryProvider).
//
// Conceito SOLID — Dependency Inversion:
// AuthNotifier depende de IAuthRepository (abstração),
// não de SupabaseAuthRepository (implementação concreta).
// Se trocar Supabase por Firebase, só muda esta linha.
final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  return SupabaseAuthRepository();
});

// ============================================================
// MODELAGEM DE ESTADOS — Sealed class
// ============================================================
// Sealed class em Dart representa um "tipo soma": o estado da
// autenticação É exatamente um destes tipos, nunca dois ao mesmo tempo.
//
// Por que não usar bool isLogado?
// Com bool, combinações inválidas são possíveis em código:
//   isLogado = true E erro = "senha errada" ao mesmo tempo
// Com sealed class, isso é impossível — cada estado é exclusivo.
//
// O Dart exige que todo switch sobre sealed class trate TODOS os casos.
// Se você adicionar um estado novo e esquecer de tratar na UI,
// o compilador avisa antes de você rodar o app.
sealed class AuthState {}

// Estado inicial — app acabou de abrir, ainda não sabe se há sessão
class AuthInicial extends AuthState {}

// Operação em andamento — UI deve mostrar loading e bloquear interação
class AuthCarregando extends AuthState {}

// Usuário autenticado — carrega o objeto Usuario com todos os dados
// A UI acessa usuario.nome, usuario.role, etc. diretamente
class AuthAutenticado extends AuthState {
  final Usuario usuario;

  // Conceito POO: encapsulamento — usuario é final,
  // não pode ser trocado após a criação do estado
  AuthAutenticado(this.usuario);
}

// Nenhuma sessão ativa — UI deve exibir tela de login
class AuthNaoAutenticado extends AuthState {}

// Erro ocorreu — UI deve exibir mensagem ao usuário
// A mensagem é tratada aqui na camada application,
// não na UI — a UI só exibe o que recebe
class AuthErro extends AuthState {
  final String mensagem;
  AuthErro(this.mensagem);
}

// ============================================================
// NOTIFIER — Máquina de estados da autenticação
// ============================================================
// Notifier é o padrão do Riverpod v3 para gerenciar estado mutável.
// Substitui o StateNotifier da v2 com uma API mais limpa.
//
// Conceito: máquina de estados finita — o estado só muda através
// dos métodos definidos aqui. A UI nunca modifica o estado diretamente.
// Isso garante que todas as transições são rastreáveis e controladas.
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    // build() é chamado automaticamente quando o provider é criado.
    // Conceito Riverpod v3: build() substitui o construtor do StateNotifier.
    // Aqui iniciamos a verificação de sessão imediatamente —
    // o app não espera interação do usuário para saber se há sessão ativa.
    _verificarSessaoAtual();
    return AuthInicial(); // estado enquanto _verificarSessaoAtual() roda
  }

  // Método privado — só o próprio Notifier pode chamar
  // Conceito POO: encapsulamento de comportamento interno
  Future<void> _verificarSessaoAtual() async {
    state = AuthCarregando();
    try {
      // ref.read() acessa o repositório sem criar dependência reativa.
      // Usamos read (não watch) porque só precisamos do valor uma vez.
      // Conceito: Dependency Injection — recebemos a dependência,
      // não a criamos aqui dentro
      final repository = ref.read(authRepositoryProvider);
      final usuario = await repository.getUsuarioAtual();

      // Operador ternário — se há usuário, autenticado; senão, não autenticado
      // Conceito: transição de estado explícita e rastreável
      state = usuario != null
          ? AuthAutenticado(usuario)
          : AuthNaoAutenticado();
    } catch (_) {
      // Qualquer erro na verificação de sessão = tratar como não autenticado
      // Não exibimos AuthErro aqui pois não é falha do usuário —
      // é apenas ausência de sessão
      state = AuthNaoAutenticado();
    }
  }

  // Método público — chamado pela tela de login via ref.read(authProvider.notifier)
  // Conceito: a UI chama métodos do Notifier, nunca modifica state diretamente
  Future<void> login(String email, String password) async {
    state = AuthCarregando(); // feedback imediato para a UI
    try {
      final repository = ref.read(authRepositoryProvider);
      final usuario = await repository.login(
        email: email,
        password: password,
      );
      state = AuthAutenticado(usuario); // transição para autenticado
    } catch (e) {
      // Conceito: a mensagem de erro é definida na camada application,
      // não na UI. A UI só exibe — não decide o texto.
      // Isso centraliza as mensagens e facilita tradução futura.
      state = AuthErro('Email ou senha incorretos');
    }
  }

  // Logout — encerra a sessão e volta para não autenticado
  Future<void> logout() async {
    final repository = ref.read(authRepositoryProvider);
    await repository.logout();
    state = AuthNaoAutenticado(); // transição explícita de volta
  }
}

// ============================================================
// PROVIDER EXPOSTO — ponto de acesso para a UI
// ============================================================
// NotifierProvider é o provider do Riverpod v3 para Notifiers.
// A UI acessa o estado via: ref.watch(authProvider)
// A UI chama métodos via: ref.read(authProvider.notifier).login(...)
//
// Conceito: a UI nunca instancia AuthNotifier diretamente —
// o Riverpod gerencia o ciclo de vida, o cache e o rebuild automático
final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});