// lib/features/estoque/application/produto_notifier.dart
//
// CAMADA: application
// RESPONSABILIDADE: gerenciar o estado da listagem de produtos
// e orquestrar as operações via repositório.
//
// CONCEITOS APLICADOS:
// - Sealed class ProdutoState: todos os estados possíveis da tela
// - Notifier Riverpod v3: substituto moderno do StateNotifier
// - Dependency Injection: recebe IProdutoRepository via ref
// - Resultado<T>: processa Sucesso e Falha de forma explícita

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/resultado.dart';
import '../domain/produto.dart';
import '../domain/i_produto_repository.dart';
import '../infrastructure/supabase_produto_repository.dart';

// ============================================================
// PROVIDER DO REPOSITÓRIO
// ============================================================
// Ponto de injeção da implementação concreta.
// Para trocar Supabase por outro backend: muda só esta linha.
final produtoRepositoryProvider = Provider<IProdutoRepository>((ref) {
  return SupabaseProdutoRepository();
});

// ============================================================
// SEALED CLASS — estados da tela de produtos
// ============================================================
sealed class ProdutoState {}

// Tela acabou de abrir — carregamento ainda não iniciou
class ProdutoInicial extends ProdutoState {}

// Buscando dados no banco — exibir loading
class ProdutoCarregando extends ProdutoState {}

// Dados carregados com sucesso — exibir lista
class ProdutoCarregado extends ProdutoState {
  final List<Produto> produtos;
  // termo: busca atual ativa (vazio = sem filtro)
  final String termo;
  ProdutoCarregado(this.produtos, {this.termo = ''});
}

// Lista carregada mas sem resultados
class ProdutoVazio extends ProdutoState {
  final String mensagem;
  ProdutoVazio(this.mensagem);
}

// Erro ao carregar ou operar
class ProdutoErro extends ProdutoState {
  final String mensagem;
  ProdutoErro(this.mensagem);
}

// ============================================================
// NOTIFIER
// ============================================================
class ProdutoNotifier extends Notifier<ProdutoState> {
  @override
  ProdutoState build() {
    // Carrega os produtos imediatamente ao criar o provider
    // Conceito: efeito colateral no build() do Notifier v3
    _carregarProdutos();
    return ProdutoInicial();
  }

  // Acesso ao repositório via ref — Dependency Injection
  IProdutoRepository get _repository =>
      ref.read(produtoRepositoryProvider);

  Future<void> _carregarProdutos() async {
    state = ProdutoCarregando();

    final resultado = await _repository.buscarTodos();

    state = switch (resultado) {
      Sucesso(:final dados) => dados.isEmpty
          ? ProdutoVazio('Nenhum produto cadastrado')
          : ProdutoCarregado(dados),
      Falha(:final tipo, :final mensagem) => switch (tipo) {
          TipoFalha.permissao =>
            ProdutoErro('Sem permissão para acessar produtos'),
          TipoFalha.rede =>
            ProdutoErro('Verifique sua conexão com a internet'),
          _ => ProdutoErro(mensagem),
        },
    };
  }

  // Busca por termo — chamada ao digitar na barra de busca
  // Conceito: debounce deve ser aplicado na UI antes de chamar este método
  Future<void> buscarPorTermo(String termo) async {
    if (termo.trim().isEmpty) {
      // Termo vazio = volta para a lista completa
      await _carregarProdutos();
      return;
    }

    state = ProdutoCarregando();

    final resultado = await _repository.buscarPorTermo(termo.trim());

    state = switch (resultado) {
      Sucesso(:final dados) => dados.isEmpty
          ? ProdutoVazio('Nenhum produto encontrado para "$termo"')
          : ProdutoCarregado(dados, termo: termo),
      Falha(:final tipo, :final mensagem) => switch (tipo) {
          TipoFalha.rede => ProdutoErro('Verifique sua conexão'),
          _ => ProdutoErro(mensagem),
        },
    };
  }

  // Inativa produto — soft delete
  Future<void> inativar(String id) async {
    final resultado = await _repository.inativar(id);

    switch (resultado) {
      case Sucesso():
        // Recarrega a lista após inativar
        await _carregarProdutos();
      case Falha(:final mensagem):
        state = ProdutoErro(mensagem);
    }
  }

  // Recarrega manualmente — pull to refresh
  Future<void> recarregar() => _carregarProdutos();
}

// Provider exposto para a UI
final produtoProvider = NotifierProvider<ProdutoNotifier, ProdutoState>(() {
  return ProdutoNotifier();
});