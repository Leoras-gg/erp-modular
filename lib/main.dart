// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/supabase_config.dart';
import 'features/auth/presentation/login_screen.dart';

Future<void> main() async {
  // Garante que os bindings do Flutter estejam prontos
  // antes de inicializar serviços externos
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa o Supabase com as credenciais do projeto
  // Conceito: configuração centralizada — um único ponto
  // onde a conexão com o backend é estabelecida
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  // ProviderScope é obrigatório no Riverpod —
  // ele envolve todo o app e permite que qualquer
  // widget acesse os providers definidos no projeto
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ERP Modular',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A56A0),
        ),
      ),
      // LoginScreen por enquanto — GoRouter entra na próxima sessão
      home: const LoginScreen(),
    );
  }
}