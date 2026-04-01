// lib/core/errors/resultado.dart
//
// Conceito: tipo soma para representar sucesso ou falha
// de forma explícita e type-safe.
//
// Por que não só lançar Exception?
// Exception obriga try/catch em todo lugar — e o compilador
// não garante que você tratou. Com Resultado<T>, o switch
// no provider/UI é obrigatório — o compilador avisa se
// você esqueceu de tratar algum caso.

sealed class Resultado<T> {}

// Operação bem-sucedida — carrega o dado de retorno
class Sucesso<T> extends Resultado<T> {
  final T dados;
  Sucesso(this.dados);
}

// Operação falhou — carrega o tipo de falha e mensagem
class Falha<T> extends Resultado<T> {
  final TipoFalha tipo;
  final String mensagem;
  final Object? detalhes; // stack trace ou erro original para debug
  Falha(this.tipo, this.mensagem, {this.detalhes});
}

// Tipos de falha padronizados — cobre todos os cenários do ERP
enum TipoFalha {
  validacao,      // dado inválido antes de chegar ao banco
  dominio,        // regra de negócio violada (ex: nota já finalizada)
  permissao,      // usuário sem permissão para a operação
  naoEncontrado,  // registro buscado não existe
  duplicidade,    // tentativa de criar registro já existente
  xmlInvalido,    // XML de NF-e malformado ou inválido
  rede,           // sem conexão ou timeout
  servidor,       // erro inesperado no Supabase
  desconhecido,   // fallback para erros não mapeados
}