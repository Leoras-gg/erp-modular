// lib/core/services/preferencias_service.dart
//
// RESPONSABILIDADE: gerenciar preferências locais do dispositivo.
// Dados salvos aqui ficam NO DISPOSITIVO — não vão para o Supabase.
//
// CONCEITO: separação entre dados de negócio (banco) e preferências
// de interface/dispositivo (local). O email salvo é uma preferência
// do dispositivo — não é dado da empresa.
//
// DADOS SALVOS LOCALMENTE (via shared_preferences):
// - email do último usuário (opt-in via checkbox)
// - flag "lembrar email" (bool)
//
// DADOS NÃO SALVOS AQUI:
// - senha (nunca salva localmente)
// - token de autenticação (gerenciado pelo Supabase automaticamente)
// - dados de negócio (produtos, notas, etc.)

import 'package:shared_preferences/shared_preferences.dart';

class PreferenciasService {
  // Chaves para o SharedPreferences
  // Prefixo 'erp_' evita colisão com outros apps no mesmo dispositivo
  static const _keyEmail = 'erp_ultimo_email';
  static const _keyLembrarEmail = 'erp_lembrar_email';

  // ============================================================
  // EMAIL DO ÚLTIMO USUÁRIO
  // ============================================================

  // Salva o email localmente — só chamado se o usuário marcou
  // "Lembrar meu email"
  Future<void> salvarEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, email);
    await prefs.setBool(_keyLembrarEmail, true);
  }

  // Recupera o email salvo — retorna null se não houver
  Future<String?> recuperarEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final lembrar = prefs.getBool(_keyLembrarEmail) ?? false;
    if (!lembrar) return null;
    return prefs.getString(_keyEmail);
  }

  // Verifica se "lembrar email" está ativado
  Future<bool> lembrarEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyLembrarEmail) ?? false;
  }

  // Limpa o email salvo — chamado quando usuário desmarca o checkbox
  Future<void> limparEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEmail);
    await prefs.setBool(_keyLembrarEmail, false);
  }
}