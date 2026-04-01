// lib/main.dart
//
// RESPONSABILIDADE: ponto de entrada do aplicativo.
// Inicializa serviços externos e configura o app raiz.
//
// MUDANÇA EM RELAÇÃO À SESSÃO 3:
// - Removido: home: LoginScreen (navegação hardcoded)
// - Adicionado: GoRouter via routerProvider (navegação declarativa)
// O GoRouter agora controla toda a navegação — inclusive
// o redirecionamento para login ou home baseado no estado de auth.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase_config.dart';
import 'core/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

// ConsumerWidget porque precisa do routerProvider
// Conceito: MyApp agora é reativo — o router vem de um provider
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ref.watch: reconstrói MyApp se o router mudar
    // Na prática o router não muda — mas é a forma correta
    // de acessar providers em ConsumerWidget
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'ERP Modular',
      debugShowCheckedModeBanner: false,

      // MaterialApp.router em vez de MaterialApp
      // Conceito: integra o GoRouter com o sistema de navegação do Flutter
      routerConfig: router,

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A56A0),
        ),
      ),
    );
  }
}