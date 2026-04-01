// lib/features/estoque/domain/i_produto_repository.dart
//
// CAMADA: domain
// RESPONSABILIDADE: declarar o contrato do repositório de produtos.
// Esta interface não sabe se os dados vêm do Supabase, SQLite
// ou de qualquer outra fonte — define apenas O QUE é possível fazer.
//
// CONCEITO SOLID — Dependency Inversion:
// Quem usa o repositório (ProdutoNotifier) depende desta abstração,
// nunca da implementação concreta (SupabaseProdutoRepository).
// Isso permite trocar o backend sem tocar em nenhuma tela ou provider.

import '../../../core/errors/resultado.dart';
import 'produto.dart';

abstract class IProdutoRepository {
  // Retorna todos os produtos ativos da empresa
  // Soft delete aplicado automaticamente — inativo_em IS NULL
  Future<Resultado<List<Produto>>> buscarTodos();

  // Busca produto por ID
  // Retorna Falha(TipoFalha.naoEncontrado) se não existir
  Future<Resultado<Produto>> buscarPorId(String id);

  // Busca produto por código de barras
  // Consulta na tabela produto_barcodes — pode retornar múltiplos
  Future<Resultado<List<Produto>>> buscarPorBarcode(String barcode);

  // Busca por termo — filtra por nome ou código interno
  // Usado pela barra de busca da tela de listagem
  Future<Resultado<List<Produto>>> buscarPorTermo(String termo);

  // Salva produto novo — retorna o produto com id gerado pelo banco
  Future<Resultado<Produto>> salvar(Produto produto);

  // Atualiza produto existente
  Future<Resultado<Produto>> atualizar(Produto produto);

  // Soft delete — preenche inativo_em, não remove do banco
  // Conceito: registros com histórico nunca são deletados fisicamente
  Future<Resultado<void>> inativar(String id);
}