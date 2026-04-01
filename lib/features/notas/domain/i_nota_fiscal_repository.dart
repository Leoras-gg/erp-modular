// lib/features/notas/domain/i_nota_fiscal_repository.dart
//
// CAMADA: domain
// Contrato do repositório de notas fiscais.
// Todos os métodos retornam Resultado<T> — nunca Exception.

import '../../../core/errors/resultado.dart';
import 'nota_fiscal.dart';

abstract class INotaFiscalRepository {
  // Retorna todas as notas ativas da empresa, ordenadas por data
  Future<Resultado<List<NotaFiscal>>> buscarTodas();

  // Busca nota por ID — inclui os itens
  Future<Resultado<NotaFiscal>> buscarPorId(String id);

  // Verifica se já existe nota com esta chave de acesso
  // Usado ANTES de processar o XML para evitar processamento desnecessário
  // Retorna Sucesso(true) se existe, Sucesso(false) se não existe
  Future<Resultado<bool>> verificarDuplicidade(String chaveAcesso);

  // Importa uma nota fiscal completa:
  // 1. Salva a nota em notas_fiscais
  // 2. Salva os itens em nota_itens
  // 3. Faz upload do XML para o Supabase Storage
  // Operação atômica — se qualquer passo falhar, nada é salvo
  Future<Resultado<NotaFiscal>> importar({
    required NotaFiscal nota,
    required String xmlContent,
  });

  // Atualiza apenas o status da nota
  // Status segue a máquina de estados definida na Sessão 4
  Future<Resultado<void>> atualizarStatus(String id, String novoStatus);

  // Soft delete
  Future<Resultado<void>> inativar(String id);
}