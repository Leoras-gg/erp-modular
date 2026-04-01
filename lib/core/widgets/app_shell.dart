// lib/core/widgets/app_shell.dart
//
// RESPONSABILIDADE: layout base de todas as telas autenticadas.
// O AppShell é o "esqueleto" visual do ERP — ele sempre está
// presente nas telas autenticadas e adapta sua navegação
// conforme o tamanho da tela.
//
// CONCEITOS APLICADOS:
// - LayoutBuilder: widget que fornece as constraints da tela pai
//   para que o filho possa adaptar seu layout
// - Responsividade: mesmo widget, comportamento diferente por tamanho
// - NavigationRail: componente Material 3 para sidebar de navegação
// - NavigationBar: componente Material 3 para barra inferior mobile
// - ConsumerWidget: acessa providers Riverpod (para logout e dados do usuário)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_provider.dart';
import '../router.dart';

// Breakpoints de layout — definidos uma vez, usados em todo o app
// Conceito: constantes centralizadas evitam valores mágicos espalhados
class AppBreakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;

  AppBreakpoints._();
}

// ConsumerWidget porque precisa do authProvider (para logout e nome do usuário)
class AppShell extends ConsumerWidget {
  // child: a tela filha atual — fornecida pelo ShellRoute do GoRouter
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // LayoutBuilder fornece o tamanho disponível para este widget
    // Conceito: design responsivo declarativo — sem MediaQuery direto
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < AppBreakpoints.mobile;
        final isTablet = constraints.maxWidth < AppBreakpoints.tablet;

        if (isMobile) {
          // Layout mobile: conteúdo em cima, NavigationBar embaixo
          return _MobileShell(child: child);
        } else if (isTablet) {
          // Layout tablet: NavigationRail compacta (só ícones) + conteúdo
          return _DesktopShell(extended: false, child: child);
        } else {
          // Layout desktop: NavigationRail expandida (ícones + labels) + conteúdo
          return _DesktopShell(extended: true, child: child);
        }
      },
    );
  }
}

// ============================================================
// LAYOUT DESKTOP / TABLET — NavigationRail lateral
// ============================================================
class _DesktopShell extends ConsumerWidget {
  final Widget child;

  // extended: true = sidebar com ícone + label
  // extended: false = sidebar só com ícone (tablet)
  final bool extended;

  const _DesktopShell({required this.child, required this.extended});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    // Obtém o nome do usuário se autenticado
    // O operador 'as' faz type casting — seguro porque verificamos o tipo
    final nomeUsuario = authState is AuthAutenticado
        ? authState.usuario.nome
        : 'Usuário';

    return Scaffold(
      body: Row(
        children: [
          // ---- SIDEBAR (NavigationRail) ----
          // NavigationRail é o componente Material 3 para navegação lateral
          NavigationRail(
            extended: extended,

            // leading: widget no topo da rail (logo + nome do usuário)
            leading: _RailHeader(nomeUsuario: nomeUsuario, extended: extended),

            // trailing: widget no rodapé da rail (botão de logout)
            trailing: _RailFooter(
              extended: extended,
              onLogout: () => ref.read(authProvider.notifier).logout(),
            ),

            // selectedIndex: qual item está ativo baseado na rota atual
            selectedIndex: _selectedIndex(context),

            onDestinationSelected: (index) =>
                _onDestinationSelected(context, index),

            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: Text('Início'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Dashboard'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2),
                label: Text('Estoque'),
              ),
              // No NavigationRail destinations, adiciona após estoque:
              NavigationRailDestination(
                icon: Icon(Icons.description_outlined),
                selectedIcon: Icon(Icons.description),
                label: Text('Notas'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Configurações'),
              ),
            ],
          ),

          // Divisor visual entre sidebar e conteúdo
          const VerticalDivider(thickness: 1, width: 1),

          // ---- CONTEÚDO PRINCIPAL ----
          // Expanded faz o conteúdo ocupar todo o espaço restante
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ============================================================
// LAYOUT MOBILE — NavigationBar inferior
// ============================================================
class _MobileShell extends ConsumerWidget {
  final Widget child;

  const _MobileShell({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // AppBar com nome do app e botão de logout
      appBar: AppBar(
        title: const Text('ERP Modular'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),

      // body: o conteúdo da tela atual
      body: child,

      // NavigationBar fica na parte inferior no mobile
      // É o substituto moderno do BottomNavigationBar no Material 3
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex(context),
        onDestinationSelected: (index) =>
            _onDestinationSelected(context, index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Estoque',
          ),
          // No NavigationBar destinations, adiciona após estoque:
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description),
            label: 'Notas',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Config.',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// FUNÇÕES COMPARTILHADAS DE NAVEGAÇÃO
// ============================================================
// Retorna o índice do item de navegação ativo baseado na rota atual
// Conceito: estado da navegação derivado da URL — não de uma variável local
int _selectedIndex(BuildContext context) {
  final location = GoRouterState.of(context).matchedLocation;

  if (location.startsWith(AppRoutes.dashboard)) return 1;
  if (location.startsWith(AppRoutes.estoque)) return 2;
  // No _selectedIndex, adiciona:
  if (location.startsWith(AppRoutes.notas)) return 3;
  if (location.startsWith(AppRoutes.configuracoes)) return 4;
  return 0; // home é o padrão
}

// Navega para a rota correspondente ao índice selecionado
void _onDestinationSelected(BuildContext context, int index) {
  switch (index) {
    case 0:
      context.go(AppRoutes.home);
    case 1:
      context.go(AppRoutes.dashboard);
    case 2:
      context.go(AppRoutes.estoque);
    case 3:
      context.go(AppRoutes.notas);
    case 4:
      context.go(AppRoutes.configuracoes);
  }
}

// ============================================================
// WIDGETS AUXILIARES DA SIDEBAR
// ============================================================

// Cabeçalho da sidebar: logo + nome do usuário
class _RailHeader extends StatelessWidget {
  final String nomeUsuario;
  final bool extended;

  const _RailHeader({required this.nomeUsuario, required this.extended});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          // Círculo com inicial do usuário — avatar simples
          CircleAvatar(
            radius: 20,
            backgroundColor: colorScheme.primaryContainer,
            child: Text(
              nomeUsuario.isNotEmpty ? nomeUsuario[0].toUpperCase() : 'U',
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Nome do usuário — só aparece quando a sidebar está expandida
          if (extended) ...[
            const SizedBox(height: 8),
            Text(
              nomeUsuario,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// Rodapé da sidebar: botão de logout
class _RailFooter extends StatelessWidget {
  final bool extended;
  final VoidCallback onLogout;

  const _RailFooter({required this.extended, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: extended
          ? TextButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout),
              label: const Text('Sair'),
            )
          : IconButton(
              onPressed: onLogout,
              icon: const Icon(Icons.logout),
              tooltip: 'Sair',
            ),
    );
  }
}
