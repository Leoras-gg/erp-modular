// lib/features/auth/infrastructure/supabase_auth_repository.dart

// Conceito: Implementação concreta da interface IAuthRepository
// Esta classe SABE que o backend é Supabase — e só ela sabe.
// O resto do projeto enxerga apenas IAuthRepository.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/i_auth_repository.dart';
import '../domain/usuario.dart';

class SupabaseAuthRepository implements IAuthRepository {
  // Acessa o cliente Supabase já inicializado no main.dart
  // Conceito: reutilização da instância única (Singleton do Supabase)
  final _client = Supabase.instance.client;

  @override
  Future<Usuario?> getUsuarioAtual() async {
    final session = _client.auth.currentSession;

    // Se não há sessão ativa, retorna null
    if (session == null) return null;

    // Busca os dados do usuário na tabela 'usuarios'
    // usando o id do usuário autenticado
    final data = await _client
        .from('usuarios')
        .select()
        .eq('id', session.user.id)
        .single();

    return Usuario.fromMap(data);
  }

  @override
  Future<Usuario> login({
    required String email,
    required String password,
  }) async {
    // Autentica com Supabase Auth
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.user == null) {
      throw Exception('Falha na autenticação — usuário não encontrado');
    }

    // Busca os dados completos do usuário no banco
    // O Supabase Auth guarda só email e id — nome, role e empresa_id
    // ficam na nossa tabela 'usuarios'
    final data = await _client
        .from('usuarios')
        .select()
        .eq('id', response.user!.id)
        .single();

    return Usuario.fromMap(data);
  }

  @override
  Future<void> logout() async {
    await _client.auth.signOut();
  }

  @override
  Stream<Usuario?> onAuthStateChange() {
    // Converte o stream do Supabase para o nosso tipo Usuario
    // Conceito: adaptação — traduz o formato externo para o domínio
    return _client.auth.onAuthStateChange.asyncMap((event) async {
      if (event.session == null) return null;

      try {
        final data = await _client
            .from('usuarios')
            .select()
            .eq('id', event.session!.user.id)
            .single();

        return Usuario.fromMap(data);
      } catch (_) {
        return null;
      }
    });
  }
}