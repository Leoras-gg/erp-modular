// lib/features/conferencia/infrastructure/supabase_conferencia_repository.dart
//
// CAMADA: infrastructure
// RESPONSABILIDADE: implementar IConferenciaRepository usando Supabase.
//
// OPERAÇÃO MAIS COMPLEXA — iniciar():
// Ao iniciar uma conferência, o sistema:
// 1. Cria o registro em conferencias (status = 'criada')
// 2. Para cada ItemNota da nota, cria um ConferenciaItem com
//    quantidade_esperada = quantidade do ItemNota
//    quantidade_conferida = 0 (ainda não conferido)
// 3. Atualiza o status da nota para 'em_conferencia'
//
// Se qualquer passo falhar, aplica rollback manual (apaga a conferência
// criada) para evitar dado parcial no banco.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/resultado.dart';
import '../domain/conferencia.dart';
import '../domain/conferencia_item.dart';
import '../domain/i_conferencia_repository.dart';

class SupabaseConferenciaRepository implements IConferenciaRepository {
  final _client = Supabase.instance.client;

  static const _tabelaConferencias   = 'conferencias';
  static const _tabelaItens          = 'conferencia_itens';
  static const _tabelaNotas          = 'notas_fiscais';

  @override
  Future<Resultado<List<Conferencia>>> buscarPorNota(String notaId) async {
    try {
      final data = await _client
          .from(_tabelaConferencias)
          .select()
          .eq('nota_id', notaId)
          .isFilter('inativo_em', null)
          .order('criado_em', ascending: false);

      // Para cada conferência, busca seus itens em paralelo
      final conferencias = await Future.wait(
        (data as List).map((map) async {
          final itensData = await _client
              .from(_tabelaItens)
              .select()
              .eq('conferencia_id', map['id'] as String)
              .order('criado_em', ascending: true);

          final itens = (itensData as List)
              .map((i) => ConferenciaItem.fromMap(i))
              .toList();

          return Conferencia.fromMap(map, itens: itens);
        }),
      );

      return Sucesso(conferencias);
    } on PostgrestException catch (e) {
      return Falha(TipoFalha.servidor,
          'Erro ao buscar conferências: ${e.message}', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }

  @override
  Future<Resultado<Conferencia>> buscarPorId(String id) async {
    try {
      final confData = await _client
          .from(_tabelaConferencias)
          .select()
          .eq('id', id)
          .single();

      final itensData = await _client
          .from(_tabelaItens)
          .select()
          .eq('conferencia_id', id)
          .order('criado_em', ascending: true);

      final itens = (itensData as List)
          .map((i) => ConferenciaItem.fromMap(i))
          .toList();

      return Sucesso(Conferencia.fromMap(confData, itens: itens));
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') {
        return Falha(TipoFalha.naoEncontrado, 'Conferência não encontrada');
      }
      return Falha(TipoFalha.servidor,
          'Erro ao buscar conferência: ${e.message}', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }

// OPERAÇÃO iniciar():
// Ao iniciar uma conferência, o sistema:
// 1. Cria o registro em conferencias com status = 'em_andamento'
// 2. Cria um ConferenciaItem para cada ItemNota
// 3. Atualiza a nota para indicar que está em conferência
//
// IMPORTANTE:
// No fluxo atual da UI, "iniciar" não significa "pré-criar".
// Significa começar efetivamente o trabalho operacional.
// Por isso o status já nasce em_andamento.

// No método iniciar(), no INSERT em conferencias:

// ANTES — causava Bug 3: -> 'status': 'criada',

// DEPOIS — corrigido:
// O clique em "Iniciar conferência" já representa início imediato.
// Nasce em 'em_andamento' para que as transições
// para 'concluida' e 'aguardando_aprovacao' sejam válidas.

  @override
  Future<Resultado<Conferencia>> iniciar({
    required String notaId,
    required String operadorId,
    required String empresaId,
    required List<Map<String, dynamic>> itensNota,
  }) async {
    String? conferenciaId;
    try {
      // ---- Passo 1: cria a conferência ----
      final confData = await _client
          .from(_tabelaConferencias)
          .insert({
            'empresa_id': empresaId,
            'nota_id': notaId,
            'status': 'em_andamento',
            'operador_id': operadorId,
            'iniciado_em': DateTime.now().toIso8601String(),
            'criado_em': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      conferenciaId = confData['id'] as String;

      // ---- Passo 2: cria um ConferenciaItem para cada ItemNota ----
      // Cada item começa com quantidade_conferida = 0
      // quantidade_esperada = quantidade que a nota diz que deve chegar
      final itensParaSalvar = itensNota.map((item) => {
        'conferencia_id': conferenciaId,
        'nota_item_id': item['id'] as String,
        'quantidade_esperada': item['quantidade'],
        'quantidade_conferida': 0,
        'criado_em': DateTime.now().toIso8601String(),
      }).toList();

      await _client.from(_tabelaItens).insert(itensParaSalvar);

      // // ---- Passo 3: atualiza status da nota para em_conferencia ----
      // await _client
      //     .from(_tabelaNotas)
      //     .update({'status': 'em_conferencia'})
      //     .eq('id', notaId);

      // ---- Passo 4: retorna a conferência completa ----
      return buscarPorId(conferenciaId);
    } on PostgrestException catch (e) {
      // Rollback: apaga conferência parcialmente criada
      if (conferenciaId != null) {
        await _client
            .from(_tabelaConferencias)
            .delete()
            .eq('id', conferenciaId);
      }
      return Falha(TipoFalha.servidor,
          'Erro ao iniciar conferência: ${e.message} (${e.code})',
          detalhes: e);
    } catch (e) {
      if (conferenciaId != null) {
        await _client
            .from(_tabelaConferencias)
            .delete()
            .eq('id', conferenciaId);
      }
      return Falha(TipoFalha.desconhecido,
          'Erro inesperado ao iniciar conferência', detalhes: e);
    }
  }

  @override
  Future<Resultado<Conferencia>> atualizarStatus({
    required String id,
    required String novoStatus,
    String? motivo,
  }) async {
    try {
      // Busca a conferência atual para validar a transição no domínio
      final confAtualResult = await buscarPorId(id);
      if (confAtualResult is Falha) return confAtualResult;

      final confAtual = (confAtualResult as Sucesso<Conferencia>).dados;

      // Validação da transição pelo domínio — não pelo banco
      // Conceito: regras de negócio pertencem ao domínio, não ao banco
      if (!confAtual.podeTransicionar(novoStatus)) {
        return Falha(
          TipoFalha.dominio,
          'Transição inválida: ${confAtual.status} → $novoStatus',
        );
      }

      final updates = <String, dynamic>{'status': novoStatus};

      // Campos adicionais por tipo de transição
      if (novoStatus == 'concluida') {
        updates['concluido_em'] = DateTime.now().toIso8601String();
      }
      if (novoStatus == 'cancelada' && motivo != null) {
        updates['cancelado_em'] = DateTime.now().toIso8601String();
        updates['motivo_cancelamento'] = motivo;
      }
      if (novoStatus == 'reaberta' && motivo != null) {
        updates['reaberto_em'] = DateTime.now().toIso8601String();
        updates['motivo_reabertura'] = motivo;
      }

      await _client
          .from(_tabelaConferencias)
          .update(updates)
          .eq('id', id);

      return buscarPorId(id);
    } on PostgrestException catch (e) {
      return Falha(TipoFalha.servidor,
          'Erro ao atualizar status: ${e.message}', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }

  @override
  Future<Resultado<ConferenciaItem>> registrarItem({
    required String conferenciaItemId,
    required double quantidadeConferida,
    String? observacao,
  }) async {
    try {
      final data = await _client
          .from(_tabelaItens)
          .update({
            'quantidade_conferida': quantidadeConferida,
            'observacao': observacao,
            'conferido_em': DateTime.now().toIso8601String(),
          })
          .eq('id', conferenciaItemId)
          .select()
          .single();

      return Sucesso(ConferenciaItem.fromMap(data));
    } on PostgrestException catch (e) {
      return Falha(TipoFalha.servidor,
          'Erro ao registrar item: ${e.message}', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }

  @override
  Future<Resultado<void>> cancelar({
    required String id,
    required String motivo,
  }) async {
    return atualizarStatus(
      id: id,
      novoStatus: 'cancelada',
      motivo: motivo,
    ).then((r) => r is Sucesso ? Sucesso(null) : r as Resultado<void>);
  }
}