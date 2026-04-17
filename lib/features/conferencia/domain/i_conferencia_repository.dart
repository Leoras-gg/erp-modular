// lib/features/conferencia/domain/i_conferencia_repository.dart
//
// CAMADA: domain
// RESPONSABILIDADE: contrato do repositório de conferências.
//
// CONCEITO SOLID — Dependency Inversion:
// O Notifier depende desta interface, nunca da implementação Supabase.
// Para testes: implementar FakeConferenciaRepository.
// Para trocar de banco: implementar SqliteConferenciaRepository.
// O Notifier não muda em nenhum dos casos.

import '../../../core/errors/resultado.dart';
import 'conferencia.dart';
import 'conferencia_item.dart';

abstract class IConferenciaRepository {
  // Busca todas as conferências ativas de uma nota específica
  // Inclui os itens de cada conferência
  Future<Resultado<List<Conferencia>>> buscarPorNota(String notaId);

  // Busca uma conferência completa por ID com todos os itens
  Future<Resultado<Conferencia>> buscarPorId(String id);

  // Inicia uma nova conferência para uma nota
  // Cria automaticamente um ConferenciaItem para cada ItemNota da nota
  // Retorna a conferência criada com todos os itens inicializados
  Future<Resultado<Conferencia>> iniciar({
    required String notaId,
    required String operadorId,
    required String empresaId,
    required List<Map<String, dynamic>> itensNota,
  });

  // Atualiza o status da conferência — valida a transição via domínio
  Future<Resultado<Conferencia>> atualizarStatus({
    required String id,
    required String novoStatus,
    String? motivo,
  });

  // Registra a quantidade conferida de um item específico
  // Atualiza conferido_em com timestamp atual
  Future<Resultado<ConferenciaItem>> registrarItem({
    required String conferenciaItemId,
    required double quantidadeConferida,
    String? observacao,
  });

  // Cancela a conferência com motivo obrigatório
  Future<Resultado<void>> cancelar({
    required String id,
    required String motivo,
  });
}