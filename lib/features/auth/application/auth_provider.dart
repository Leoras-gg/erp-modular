// lib/features/auth/application/auth_provider.dart
//
// CAMADA: application
// RESPONSABILIDADE: gerenciar o estado de autenticação do ERP Modular.
//
// ============================================================
// ARQUITETURA DE SEGURANÇA — LEIA COM ATENÇÃO
// ============================================================
// O ERP Modular usa DUAS CAMADAS de autenticação independentes:
//
// CAMADA 1 — Supabase Auth (autenticação de rede):
//   Valida email e senha contra o banco de dados na nuvem.
//   Gera um token JWT com prazo de validade.
//   O supabase_flutter salva esse token localmente (criptografado)
//   para não precisar reautenticar na rede a cada abertura.
//   Esta camada é PERSISTENTE entre sessões por design do Supabase.
//
// CAMADA 2 — Login local (controle de acesso ao app):
//   O APP sempre exige que o usuário DIGITE A SENHA ao abrir,
//   mesmo que o token Supabase ainda seja válido.
//   Isso protege dispositivos COMPARTILHADOS — tablet no almoxarifado,
//   computador de uso coletivo, etc.
//   Se alguém pegar o dispositivo sem permissão, não entra sem senha.
//
// EXCEÇÃO — devMode (apenas desenvolvimento):
//   Quando ConfigDeploy.devMode = true, o app aceita o token Supabase
//   ativo sem pedir senha novamente.
//   Isso existe para que o desenvolvedor não precise logar a cada
//   hot restart durante o desenvolvimento.
//   NUNCA deve ser true em dispositivos de produção ou homologação.
//
// FLUXO AO ABRIR O APP:
//
//   App abre
//       ↓
//   Verifica sessão Supabase
//       ↓
//   Sem sessão ativa → AuthNaoAutenticado (email salvo se houver)
//   Com sessão ativa:
//     devMode = true  → AuthAutenticado (entra direto — só em dev)
//     devMode = false → AuthAguardandoConfirmacao (pede senha — produção)
//
// ESTADOS DA MÁQUINA:
//
//   AuthInicial ──────────────────────────────→ (carregando sessão)
//   AuthCarregando ───────────────────────────→ (operação em andamento)
//   AuthAutenticado ──────────────────────────→ (usuário dentro do app)
//   AuthAguardandoConfirmacao ────────────────→ (sessão ativa, senha necessária)
//   AuthNaoAutenticado ───────────────────────→ (sem sessão, tela de login)
//   AuthErro ─────────────────────────────────→ (erro, volta para NaoAutenticado)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/usuario.dart';
import '../domain/i_auth_repository.dart';
import '../infrastructure/supabase_auth_repository.dart';
import '../../../core/config_deploy.dart';
import '../../../core/services/preferencias_service.dart';

// ============================================================
// PROVIDER DO REPOSITÓRIO — ponto de injeção de dependência
// ============================================================
// Conceito SOLID — Dependency Inversion:
// AuthNotifier depende de IAuthRepository (abstração),
// não de SupabaseAuthRepository (implementação concreta).
// Para trocar Supabase por Firebase: muda só esta linha.
final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  return SupabaseAuthRepository();
});

// ============================================================
// PROVIDER DO SERVIÇO DE PREFERÊNCIAS LOCAIS
// ============================================================
// PreferenciasService gerencia dados salvos NO DISPOSITIVO,
// não no Supabase. Usado para o email "lembrar neste dispositivo".
// Ver lib/core/services/preferencias_service.dart para detalhes.
final preferenciasServiceProvider = Provider<PreferenciasService>((ref) {
  return PreferenciasService();
});

// ============================================================
// SEALED CLASS DE ESTADO — AuthState
// ============================================================
// CONCEITO: tipo soma (sum type)
// AuthState pode ser EXATAMENTE UM destes subtipos — nunca dois ao mesmo tempo.
// O compilador Dart exige que todo switch trate todos os casos.
// Se adicionarmos um estado novo e esquecermos de tratar na UI,
// o compilador avisa ANTES de compilar — erro em tempo de compilação,
// não em tempo de execução.
//
// Por que não usar bool isLogado + bool isCarregando + String? erro?
// Porque combinações inválidas seriam possíveis:
//   isLogado = true E erro = "senha errada" ao mesmo tempo ← impossível na realidade
// Com sealed class, isso é estruturalmente impossível.
sealed class AuthState {}

// App acabou de abrir — verificando sessão em andamento
// Estado transitório — dura milissegundos
class AuthInicial extends AuthState {}

// Operação de autenticação em andamento (login, logout, verificação)
// UI deve mostrar loading e bloquear interações
class AuthCarregando extends AuthState {}

// Usuário autenticado e dentro do app
// Carrega o objeto Usuario com todos os dados (nome, role, empresaId)
// A UI usa authState.usuario.nome, authState.usuario.role, etc.
class AuthAutenticado extends AuthState {
  final Usuario usuario;

  // Conceito POO: encapsulamento — usuario é final,
  // não pode ser reatribuído após a criação deste estado
  AuthAutenticado(this.usuario);
}

// Há sessão Supabase ativa mas o app exige confirmação de senha
// Ocorre APENAS quando ConfigDeploy.devMode = false
// (comportamento padrão de produção para dispositivos compartilhados)
//
// emailPreenchido: o email do usuário da sessão ativa OU o email
// salvo pelo "lembrar email" — preenchido automaticamente para
// facilitar (o usuário só precisa digitar a senha, não o email)
class AuthAguardandoConfirmacao extends AuthState {
  final String? emailPreenchido;
  AuthAguardandoConfirmacao({this.emailPreenchido});
}

// Sem sessão ativa — tela de login limpa (ou com email salvo)
// emailPreenchido: email salvo pelo "lembrar email" neste dispositivo
// Pode ser null se o usuário nunca marcou "lembrar email"
class AuthNaoAutenticado extends AuthState {
  final String? emailPreenchido;
  AuthNaoAutenticado({this.emailPreenchido});
}

// Erro de autenticação — credenciais inválidas ou erro de rede
// O AuthNotifier retorna automaticamente para AuthNaoAutenticado
// após 2 segundos para que o usuário veja a mensagem e tente novamente
class AuthErro extends AuthState {
  final String mensagem;
  AuthErro(this.mensagem);
}

// ============================================================
// NOTIFIER — gerencia as transições entre estados
// ============================================================
// CONCEITO: máquina de estados finita
// Cada método do Notifier é uma transição entre estados.
// Apenas os métodos públicos podem disparar transições —
// a UI nunca modifica o state diretamente.
//
// CONCEITO Riverpod v3: Notifier vs StateNotifier
// O Notifier da v3 substitui o StateNotifier da v2.
// Diferença principal: build() substitui o construtor.
// O ref está disponível diretamente sem injeção manual.
// Isso simplifica o código e evita erros de inicialização.
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    // build() é chamado automaticamente pelo Riverpod quando o provider
    // é acessado pela primeira vez. Equivale ao construtor do StateNotifier.
    //
    // Iniciamos a verificação da sessão imediatamente —
    // o usuário não precisa interagir para o app saber se está logado.
    // O estado inicial AuthInicial é transitório e logo muda.
    _verificarSessaoAtual();
    return AuthInicial();
  }

  // Acessores para as dependências — usando ref.read() pois são
  // chamadas pontuais, não observação contínua (que seria ref.watch)
  IAuthRepository get _repository => ref.read(authRepositoryProvider);
  PreferenciasService get _prefs => ref.read(preferenciasServiceProvider);

  // ============================================================
  // VERIFICAÇÃO DA SESSÃO AO ABRIR O APP
  // ============================================================
  // Método privado — só o próprio Notifier pode chamar.
  // Conceito POO: encapsulamento de comportamento interno.
  Future<void> _verificarSessaoAtual() async {
    state = AuthCarregando();

    try {
      // Consulta o Supabase Auth para ver se há token válido em cache
      // getUsuarioAtual() retorna null se não há sessão ou se expirou
      final usuario = await _repository.getUsuarioAtual();

      if (usuario == null) {
        // Sem sessão Supabase → vai para login
        // Recupera email salvo para preencher automaticamente
        final emailSalvo = await _prefs.recuperarEmail();
        state = AuthNaoAutenticado(emailPreenchido: emailSalvo);
        return;
      }

      // Há sessão Supabase ativa — comportamento depende do devMode
      if (ConfigDeploy.devMode) {
        // ---- MODO DESENVOLVIMENTO ----
        // Aceita a sessão ativa sem pedir senha novamente.
        // Conveniente para não logar a cada hot restart.
        // ATENÇÃO: nunca use devMode = true em produção!
        state = AuthAutenticado(usuario);
      } else {
        // ---- MODO PRODUÇÃO ----
        // Sessão Supabase existe mas o app EXIGE confirmação de senha.
        // O email é preenchido automaticamente (do "lembrar" ou da sessão)
        // para o usuário só precisar digitar a senha.
        // Isso protege dispositivos compartilhados de almoxarifado.
        final emailSalvo = await _prefs.recuperarEmail();
        state = AuthAguardandoConfirmacao(
          emailPreenchido: emailSalvo ?? usuario.email,
        );
      }
    } catch (_) {
      // Qualquer erro na verificação → trata como não autenticado
      // Não exibimos AuthErro aqui pois não é falha do usuário —
      // é apenas ausência ou falha de sessão
      final emailSalvo = await _prefs.recuperarEmail();
      state = AuthNaoAutenticado(emailPreenchido: emailSalvo);
    }
  }

  // ============================================================
  // LOGIN — chamado pela tela de login
  // ============================================================
  // INPUT:
  //   email:        email digitado pelo usuário
  //   password:     senha digitada (nunca salva localmente)
  //   lembrarEmail: se true, salva email no dispositivo
  //
  // OUTPUT (via state):
  //   AuthAutenticado    → login bem-sucedido, usuário dentro do app
  //   AuthNaoAutenticado → credenciais inválidas (após 2s de AuthErro)
  //
  // CONCEITO: parâmetro nomeado com valor padrão
  // {bool lembrarEmail = false} significa que o parâmetro é opcional
  // e seu valor padrão é false se não for passado
  Future<void> login(
    String email,
    String password, {
    bool lembrarEmail = false,
  }) async {
    state = AuthCarregando();

    try {
      // Salva ou limpa o email ANTES do login
      // Se o login falhar, o email ainda estará salvo para a próxima tentativa
      if (lembrarEmail) {
        await _prefs.salvarEmail(email);
      } else {
        // Se o usuário desmarcou "lembrar", limpa qualquer email salvo
        await _prefs.limparEmail();
      }

      // Delega a autenticação para o repositório — camada infrastructure
      // O repositório não sabe sobre estado, UI ou preferências locais
      // Conceito SOLID — Single Responsibility: cada camada tem uma responsabilidade
      final usuario = await _repository.login(
        email: email,
        password: password,
      );

      // Login bem-sucedido → usuário entra no app
      state = AuthAutenticado(usuario);
    } catch (e) {
      // Credenciais inválidas ou erro de rede
      // Exibe o erro por 2 segundos e volta para o formulário de login
      // com o email preenchido para o usuário tentar novamente facilmente
      state = AuthErro('Email ou senha incorretos. Verifique e tente novamente.');

      await Future.delayed(const Duration(seconds: 2));

      final emailSalvo = await _prefs.recuperarEmail();
      state = AuthNaoAutenticado(emailPreenchido: emailSalvo ?? email);
    }
  }

  // ============================================================
  // LOGOUT — chamado pelo botão Sair e por "Trocar usuário"
  // ============================================================
  // Encerra AMBAS as camadas de autenticação:
  // 1. Limpa o token Supabase em cache (logout da rede)
  // 2. Retorna para AuthNaoAutenticado (volta para tela de login)
  //
  // O email salvo pelo "lembrar" é MANTIDO após logout —
  // o usuário provavelmente vai querer logar novamente com o mesmo email.
  // Para limpar o email, o usuário deve desmarcar o checkbox.
  Future<void> logout() async {
    // signOut() do Supabase invalida o token e limpa o cache local
    await _repository.logout();

    // Recupera email salvo para manter preenchido na tela de login
    final emailSalvo = await _prefs.recuperarEmail();
    state = AuthNaoAutenticado(emailPreenchido: emailSalvo);
  }
}

// ============================================================
// PROVIDER EXPOSTO PARA A UI
// ============================================================
// NotifierProvider é o provider do Riverpod v3 para Notifiers.
//
// A UI acessa o estado via:
//   ref.watch(authProvider)          → observa e reconstrói ao mudar
//   ref.read(authProvider)           → lê uma vez sem observar
//   ref.read(authProvider.notifier)  → acessa o Notifier para chamar métodos
//
// Exemplo de uso em widget:
//   final authState = ref.watch(authProvider);
//   ref.read(authProvider.notifier).login(email, password);
final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});