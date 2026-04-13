# Guia Operacional Curto — ERP Modular

## Objetivo
Este guia funciona como checklist rapido para manter consistencia arquitetural, reduzir retrabalho e apoiar decisoes tecnicas no dia a dia.

## Fluxo obrigatorio por tarefa
1. Definir o fluxo: entrada -> processamento -> saida.
2. Confirmar a camada correta da alteracao:
   - `domain`: regras e modelos puros (sem Flutter, sem Supabase, sem Riverpod)
   - `application`: notifier, estados e orquestracao
   - `infrastructure`: integracao com Supabase e mapeamento de erros
   - `presentation`: widgets, telas e feedback visual
3. Em operacoes de banco:
   - repositarios retornam `Resultado<T>`
   - nao engolir excecao; mapear falha real
   - nao incluir `id` no `toMap()` quando UUID e gerado pelo banco
4. Em tabela nova:
   - `empresa_id` obrigatorio (multi-tenant)
   - `inativo_em` obrigatorio (soft delete)
   - RLS ativo e validado
5. Em estado (Riverpod v3):
   - usar `sealed class` para estados
   - UI reage ao estado; regra de negocio nao fica no widget
6. Em XML/NF-e:
   - tratar namespace/localName corretamente
   - simular parser e persistencia antes de consolidar mudanca
7. Em commit:
   - usar Conventional Commits
   - manter 1 commit por entrega pequena e rastreavel
8. Fechamento da tarefa:
   - validar caminho feliz e caminho de erro
   - registrar o que mudou e por que mudou

## Uso pratico no projeto
- Antes de codar: leia este guia em 2 minutos.
- Durante a implementacao: valide cada passo no checklist.
- Antes do commit: confirme se nenhuma regra foi quebrada.

## Importancia
Este guia protege o projeto contra atalho arquitetural, acelera revisoes, melhora depuracao e preserva o objetivo central do ERP Modular: aprender com consistencia tecnica em um sistema real.
