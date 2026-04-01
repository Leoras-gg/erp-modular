// lib/features/home/presentation/home_screen.dart
//
// RESPONSABILIDADE: tela inicial do ERP após o login.
// Exibe os módulos disponíveis como cards navegáveis.
//
// Por enquanto todos os módulos são exibidos — quando o sistema
// de permissões estiver implementado, apenas os módulos que
// a empresa tem ativos e o usuário tem permissão aparecerão.
//
// CONCEITOS APLICADOS:
// - ConsumerWidget: acessa o authProvider para saudação personalizada
// - GridView: layout de grade responsiva para os cards de módulo
// - Composição: tela composta por widgets menores e reutilizáveis

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/auth/application/auth_provider.dart';
import '../../../core/router.dart';
import '../../../core/widgets/app_shell.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    // Extrai o nome do usuário do estado de autenticação
    final nomeUsuario = authState is AuthAutenticado
        ? authState.usuario.nome
        : 'Usuário';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- SAUDAÇÃO ----
              Text(
                'Olá, $nomeUsuario',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Selecione um módulo para começar',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
              ),
              const SizedBox(height: 32),

              // ---- GRID DE MÓDULOS ----
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Número de colunas baseado na largura disponível
                    // Conceito: layout responsivo sem MediaQuery — usa constraints
                    final crossAxisCount =
                        constraints.maxWidth < AppBreakpoints.mobile
                            ? 2   // mobile: 2 colunas
                            : constraints.maxWidth < AppBreakpoints.desktop
                                ? 3 // tablet: 3 colunas
                                : 4; // desktop: 4 colunas

                    return GridView.count(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1.1,
                      children: [
                        _ModuloCard(
                          titulo: 'Estoque',
                          subtitulo: 'Almoxarifado e movimentações',
                          icone: Icons.inventory_2_outlined,
                          cor: Colors.blue,
                          // Conceito: navegação declarativa com GoRouter
                          // context.go() não empilha — substitui a rota atual
                          onTap: () => context.go(AppRoutes.estoque),
                        ),
                        _ModuloCard(
                          titulo: 'Dashboard',
                          subtitulo: 'Métricas e relatórios',
                          icone: Icons.dashboard_outlined,
                          cor: Colors.purple,
                          onTap: () => context.go(AppRoutes.dashboard),
                        ),
                        // Módulos futuros — desabilitados visualmente
                        _ModuloCard(
                          titulo: 'Vendas',
                          subtitulo: 'PDV e pedidos',
                          icone: Icons.point_of_sale_outlined,
                          cor: Colors.green,
                          desabilitado: true,
                          onTap: null,
                        ),
                        _ModuloCard(
                          titulo: 'Assistência',
                          subtitulo: 'Ordens de serviço',
                          icone: Icons.build_outlined,
                          cor: Colors.orange,
                          desabilitado: true,
                          onTap: null,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CARD DE MÓDULO — widget privado e reutilizável
// ============================================================
// Conceito POO: encapsulamento — o card conhece seus próprios dados
// e comportamento, sem expor detalhes de implementação
class _ModuloCard extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final IconData icone;
  final Color cor;
  final VoidCallback? onTap;

  // desabilitado: módulo futuro — exibido mas não navegável
  final bool desabilitado;

  const _ModuloCard({
    required this.titulo,
    required this.subtitulo,
    required this.icone,
    required this.cor,
    this.onTap,
    this.desabilitado = false,
  });

  @override
  Widget build(BuildContext context) {
    // Opacidade reduzida para módulos desabilitados
    // Conceito: feedback visual claro sobre o estado do elemento
    return Opacity(
      opacity: desabilitado ? 0.4 : 1.0,
      child: Card(
        elevation: desabilitado ? 0 : 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Ícone do módulo com cor de fundo
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icone, color: cor, size: 28),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      desabilitado ? 'Em breve' : subtitulo,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}