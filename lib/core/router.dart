// lib/core/router.dart
//
// RESPONSABILIDADE: configuração central de navegação do ERP Modular.
// Todas as rotas do sistema são definidas aqui — nenhuma tela conhece
// outra tela diretamente. A navegação é declarativa: você declara
// o que deve aparecer em cada rota, não como chegar lá.
//
// CONCEITOS APLICADOS:
// - GoRouter: biblioteca de navegação declarativa para Flutter
// - ShellRoute: rota pai que mantém o AppShell (menu/sidebar) fixo
//   enquanto apenas o conteúdo interno troca entre rotas
// - Redirect: redirecionamento automático baseado em estado de auth
// - Provider Pattern: o router observa o authProvider para decidir
//   se o usuário pode acessar cada rota

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_provider.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/estoque/presentation/estoque_screen.dart';
import '../features/configuracoes/presentation/configuracoes_screen.dart';
import 'widgets/app_shell.dart';

// Adiciona este import no topo do router.dart:
import '../features/notas/presentation/notas_screen.dart';

// ============================================================
// NOMES DAS ROTAS — constantes para evitar strings mágicas
// ============================================================
// Conceito: nunca escrever '/home' ou '/login' espalhado pelo código.
// Se a rota mudar, muda só aqui — em um lugar.
class AppRoutes {
  static const login = '/login';
  static const home = '/home';
  static const dashboard = '/dashboard';
  static const estoque = '/estoque';
  static const configuracoes = '/configuracoes';

  // Adiciona esta constante em AppRoutes:
  static const notas = '/notas';

  // Construtor privado — esta classe não deve ser instanciada
  // Conceito POO: utility class com apenas membros estáticos
  AppRoutes._();
}

// ============================================================
// PROVIDER DO ROUTER
// ============================================================
// Conceito: o router é um provider Riverpod para que possa
// observar o authProvider e reagir a mudanças de autenticação.
// O refreshListenable conecta o GoRouter ao estado de auth —
// quando o auth muda, o router reavalia os redirects.
final routerProvider = Provider<GoRouter>((ref) {
  // RouterNotifier gerencia a lógica de redirect e notifica o router
  final notifier = RouterNotifier(ref);

  return GoRouter(
    // Rota inicial — o redirect vai redirecionar conforme o estado
    initialLocation: AppRoutes.login,

    // debugLogDiagnostics: imprime cada navegação no console durante dev
    // Útil para entender o fluxo de redirect
    debugLogDiagnostics: true,

    // refreshListenable: o GoRouter observa este objeto.
    // Quando ele notifica, o router reavalia TODOS os redirects.
    // Conceito: reatividade — mudança no auth = router reage automaticamente
    refreshListenable: notifier,

    // redirect global: executado antes de cada navegação
    // Se retornar uma string, redireciona para ela
    // Se retornar null, permite a navegação normalmente
    redirect: notifier.redirect,

    routes: [
      // --------------------------------------------------------
      // ROTA PÚBLICA — Login
      // --------------------------------------------------------
      // Rota simples sem ShellRoute — não tem menu/sidebar
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),

      // --------------------------------------------------------
      // SHELL ROUTE — Rotas autenticadas com AppShell
      // --------------------------------------------------------
      // ShellRoute envolve as rotas filhas com o AppShell.
      // O AppShell (menu + sidebar) fica fixo na tela.
      // Apenas o conteúdo dentro do shell muda ao navegar.
      //
      // Analogia: uma janela com moldura fixa (AppShell) e
      // um quadro que troca (as telas filhas).
      ShellRoute(
        builder: (context, state, child) {
          // child = a tela filha atual sendo exibida
          // AppShell é responsável por renderizar child
          // dentro do layout correto (sidebar + content)
          return AppShell(child: child);
        },
        routes: [
          GoRoute(
            path: AppRoutes.home,
            name: 'home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: AppRoutes.dashboard,
            name: 'dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: AppRoutes.estoque,
            name: 'estoque',
            builder: (context, state) => const EstoqueScreen(),
          ),
          GoRoute(
            path: AppRoutes.configuracoes,
            name: 'configuracoes',
            builder: (context, state) => const ConfiguracoesScreen(),
          ),
          // Adiciona esta rota dentro do ShellRoute (junto com estoque, dashboard...):
          GoRoute(
            path: AppRoutes.notas,
            name: 'notas',
            builder: (context, state) => const NotasScreen(),
          ),
        ],
      ),
    ],
  );
});

// ============================================================
// ROUTER NOTIFIER — lógica de redirect e notificação
// ============================================================
// Conceito: ChangeNotifier é a interface do Flutter para objetos
// observáveis. O GoRouter usa isso para saber quando reavaliar
// os redirects. Quando o authProvider muda, este notifier
// chama notifyListeners() e o router reavalia tudo.
class RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  RouterNotifier(this._ref) {
    // Observa o authProvider — quando o estado de auth mudar,
    // notifyListeners() é chamado e o GoRouter reavalia os redirects
    _ref.listen(authProvider, (previous, next) {
      // Só notifica se o estado realmente mudou de categoria
      // ex: de NaoAutenticado para Autenticado (e vice-versa)
      if (previous.runtimeType != next.runtimeType) {
        notifyListeners();
      }
    });
  }

  // ============================================================
  // FUNÇÃO DE REDIRECT
  // ============================================================
  // Chamada pelo GoRouter antes de cada navegação.
  // Retorna String para redirecionar, null para permitir.
  //
  // Conceito: guard de rota — centraliza a lógica de acesso
  // em um único lugar, não espalhada por cada tela.
  String? redirect(BuildContext context, GoRouterState state) {
    final authState = _ref.read(authProvider);
    final isLoggedIn = authState is AuthAutenticado;
    final isLoggingIn = state.matchedLocation == AppRoutes.login;

    // Carregando — não redireciona
    if (authState is AuthInicial || authState is AuthCarregando) {
      return null;
    }

    // Aguardando confirmação de senha (devMode = false com sessão ativa)
    // → vai para login com email preenchido
    if (authState is AuthAguardandoConfirmacao && !isLoggingIn) {
      return AppRoutes.login;
    }

    // Não autenticado tentando acessar rota protegida → login
    if (!isLoggedIn && !isLoggingIn) {
      return AppRoutes.login;
    }

    // Autenticado tentando acessar login → home
    if (isLoggedIn && isLoggingIn) {
      return AppRoutes.home;
    }

    return null;
  }
}
