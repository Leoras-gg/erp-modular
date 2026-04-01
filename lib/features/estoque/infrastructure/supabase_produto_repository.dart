// lib/features/estoque/infrastructure/supabase_produto_repository.dart
//
// CAMADA: infrastructure
// RESPONSABILIDADE: implementar IProdutoRepository usando Supabase.
// Esta é a ÚNICA classe do módulo de estoque que conhece o Supabase.
//
// CONCEITOS APLICADOS:
// - Resultado<T>: toda operação retorna Sucesso ou Falha — nunca Exception
// - Soft delete: todas as queries filtram inativo_em IS NULL
// - RLS: o Supabase aplica automaticamente o filtro de empresa_id
//   baseado no token JWT do usuário autenticado

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/resultado.dart';
import '../domain/i_produto_repository.dart';
import '../domain/produto.dart';

class SupabaseProdutoRepository implements IProdutoRepository {
  // Cliente Supabase inicializado no main.dart
  // Singleton — mesma instância em toda a aplicação
  final _client = Supabase.instance.client;

  // Nome da tabela — constante para evitar string mágica repetida
  static const _tabela = 'produtos';
  static const _tabelaBarcodes = 'produto_barcodes';

  @override
  Future<Resultado<List<Produto>>> buscarTodos() async {
    try {
      // SELECT produtos.*, array_agg(produto_barcodes.barcode) as barcodes
      // WHERE inativo_em IS NULL
      // ORDER BY nome ASC
      //
      // O RLS do Supabase adiciona automaticamente:
      // AND empresa_id = auth.uid() (ou empresa do usuário)
      final data = await _client
          .from(_tabela)
          .select('*, $_tabelaBarcodes(barcode)')
          .isFilter('inativo_em', null) // soft delete filter
          .order('nome', ascending: true);

      // Mapeia cada registro para um objeto Produto
      // Conceito: transformação de dado externo em objeto de domínio
      final produtos = (data as List)
          .map((map) => _mapearComBarcodes(map))
          .toList();

      return Sucesso(produtos);
    } on PostgrestException catch (e) {
      // Erro específico do Supabase — classificamos por código
      return Falha(
        TipoFalha.servidor,
        'Erro ao buscar produtos',
        detalhes: e,
      );
    } catch (e) {
      return Falha(
        TipoFalha.desconhecido,
        'Erro inesperado ao buscar produtos',
        detalhes: e,
      );
    }
  }

  @override
  Future<Resultado<Produto>> buscarPorId(String id) async {
    try {
      final data = await _client
          .from(_tabela)
          .select('*, $_tabelaBarcodes(barcode)')
          .eq('id', id)
          .isFilter('inativo_em', null)
          .single(); // lança erro se não encontrar

      return Sucesso(_mapearComBarcodes(data));
    } on PostgrestException catch (e) {
      // Código PGRST116 = nenhuma linha retornada pelo .single()
      if (e.code == 'PGRST116') {
        return Falha(TipoFalha.naoEncontrado, 'Produto não encontrado');
      }
      return Falha(TipoFalha.servidor, 'Erro ao buscar produto', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }

  @override
  Future<Resultado<List<Produto>>> buscarPorBarcode(String barcode) async {
    try {
      // Busca na tabela de barcodes e faz join com produtos
      final data = await _client
          .from(_tabelaBarcodes)
          .select('produto_id, $_tabela(*, $_tabelaBarcodes(barcode))')
          .eq('barcode', barcode);

      final produtos = (data as List)
          .map((map) => _mapearComBarcodes(map[_tabela] as Map<String, dynamic>))
          .toList();

      return Sucesso(produtos);
    } on PostgrestException catch (e) {
      return Falha(TipoFalha.servidor, 'Erro ao buscar por barcode', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }

  @override
  Future<Resultado<List<Produto>>> buscarPorTermo(String termo) async {
    try {
      // ilike = case insensitive LIKE no PostgreSQL
      // % no início e fim = contém o termo em qualquer posição
      final data = await _client
          .from(_tabela)
          .select('*, $_tabelaBarcodes(barcode)')
          .isFilter('inativo_em', null)
          .or('nome.ilike.%$termo%,codigo_interno.ilike.%$termo%')
          .order('nome', ascending: true);

      final produtos = (data as List)
          .map((map) => _mapearComBarcodes(map))
          .toList();

      return Sucesso(produtos);
    } on PostgrestException catch (e) {
      return Falha(TipoFalha.servidor, 'Erro na busca', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }

  @override
  Future<Resultado<Produto>> salvar(Produto produto) async {
    try {
      final data = await _client
          .from(_tabela)
          .insert(produto.toMap())
          .select('*, $_tabelaBarcodes(barcode)')
          .single();

      return Sucesso(_mapearComBarcodes(data));
    } on PostgrestException catch (e) {
      // Código 23505 = violação de unique constraint (duplicidade)
      if (e.code == '23505') {
        return Falha(
          TipoFalha.duplicidade,
          'Já existe um produto com este código interno',
        );
      }
      return Falha(TipoFalha.servidor, 'Erro ao salvar produto', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }

  @override
  Future<Resultado<Produto>> atualizar(Produto produto) async {
    try {
      final data = await _client
          .from(_tabela)
          .update(produto.toMap())
          .eq('id', produto.id)
          .select('*, $_tabelaBarcodes(barcode)')
          .single();

      return Sucesso(_mapearComBarcodes(data));
    } on PostgrestException catch (e) {
      return Falha(TipoFalha.servidor, 'Erro ao atualizar produto', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }

  @override
  Future<Resultado<void>> inativar(String id) async {
    try {
      // Soft delete: preenche inativo_em com timestamp atual
      // O produto continua no banco — só some das listagens normais
      await _client
          .from(_tabela)
          .update({'inativo_em': DateTime.now().toIso8601String()})
          .eq('id', id);

      return Sucesso(null);
    } on PostgrestException catch (e) {
      return Falha(TipoFalha.servidor, 'Erro ao inativar produto', detalhes: e);
    } catch (e) {
      return Falha(TipoFalha.desconhecido, 'Erro inesperado', detalhes: e);
    }
  }

  // ============================================================
  // MÉTODO PRIVADO — mapeamento com barcodes
  // ============================================================
  // Conceito: método auxiliar privado (underscore = privado em Dart)
  // Centraliza a lógica de transformar o resultado do JOIN
  // em um objeto Produto com a lista de barcodes preenchida
  Produto _mapearComBarcodes(Map<String, dynamic> map) {
    // O Supabase retorna os barcodes como lista de objetos
    // Exemplo: [{"barcode": "7891234567890"}, {"barcode": "123456"}]
    // Precisamos extrair só o valor do campo "barcode"
    final barcodesRaw = map[_tabelaBarcodes] as List<dynamic>? ?? [];
    final barcodes = barcodesRaw
        .map((b) => (b as Map<String, dynamic>)['barcode'] as String)
        .toList();

    // Cria um Map novo com a lista de barcodes já processada
    return Produto.fromMap({...map, 'barcodes': barcodes});
  }
}