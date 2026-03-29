// lib/features/auth/domain/i_auth_repository.dart

// Conceito: Interface (contrato)
// Esta classe abstrata declara O QUE o repositório de auth faz.
// Ela não sabe se os dados vêm do Supabase, Firebase ou qualquer outro.
// Quem depende desta interface nunca precisa mudar se o backend mudar.

// Conceito SOLID — Dependency Inversion:
// Módulos de alto nível (providers) dependem desta abstração,
// não da implementação concreta (SupabaseAuthRepository).

import 'usuario.dart';

abstract class IAuthRepository {
  // Retorna o usuário logado ou null se não há sessão ativa
  Future<Usuario?> getUsuarioAtual();

  // Realiza login com email e senha
  // Retorna o Usuario em caso de sucesso
  // Lança exceção em caso de erro — o provider decide o que fazer
  Future<Usuario> login({
    required String email,
    required String password,
  });

  // Encerra a sessão do usuário atual
  Future<void> logout();

  // Stream que emite o usuário atual sempre que o estado de auth muda
  // Conceito: reatividade — a UI se atualiza automaticamente
  Stream<Usuario?> onAuthStateChange();
}