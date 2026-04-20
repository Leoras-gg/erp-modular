# ERP Modular

> Sistema ERP open source para micro e pequenas empresas — em desenvolvimento ativo.

[![Flutter](https://img.shields.io/badge/Flutter-stable-blue?logo=flutter)](https://flutter.dev)
[![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL-green?logo=supabase)](https://supabase.com)
[![Riverpod](https://img.shields.io/badge/Riverpod-v3-purple)](https://riverpod.dev)
[![License](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)

---

## O que é este projeto

O ERP Modular é um sistema de gestão empresarial construído do zero como projeto de portfólio e aprendizado prático. O objetivo é duplo: criar uma aplicação funcional e real para micro e pequenas empresas, e aprender na prática os conceitos de arquitetura de software, design patterns e boas práticas de desenvolvimento profissional.

O projeto é desenvolvido de forma incremental, com sessões documentadas, decisões arquiteturais registradas e processo de debugging transparente — incluindo os erros e o que foi aprendido com eles.

**Status atual:** Módulo 1 (Almoxarifado e Estoque) em desenvolvimento — Sessões 1 a 10 concluídas ou em progresso.

---

## Stack tecnológica

| Tecnologia | Versão | Uso |
|---|---|---|
| Flutter | stable | Frontend — web, desktop e mobile (único codebase) |
| Dart | oficial | Linguagem — padrões oficiais da linguagem |
| Supabase | ^2.12.2 | Backend — PostgreSQL + Auth + Storage + RLS |
| Riverpod | ^3.3.1 | Gerenciamento de estado — Notifier/NotifierProvider |
| GoRouter | ^17.1.0 | Navegação declarativa com ShellRoute |
| xml | ^6.6.1 | Parse de XML de NF-e (Nota Fiscal eletrônica) |
| file_picker | ^10.3.10 | Seleção de arquivo no sistema operacional |
| shared_preferences | ^2.5.5 | Preferências locais do dispositivo |

---

## Arquitetura

O projeto segue arquitetura em camadas com separação estrita de responsabilidades:

```
lib/
├── features/
│   ├── auth/
│   │   ├── domain/          → entidades e interfaces (Dart puro, zero dependências)
│   │   ├── application/     → Notifier + sealed class de estado
│   │   ├── infrastructure/  → implementação Supabase
│   │   └── presentation/    → widgets e telas
│   ├── estoque/             → módulo de produtos e movimentações
│   ├── notas/               → módulo de notas fiscais (NF-e)
│   └── conferencia/         → módulo de conferência física de mercadorias
├── core/
│   ├── errors/              → Resultado<T>, TipoFalha
│   ├── router.dart          → GoRouter + rotas + redirect de autenticação
│   ├── widgets/             → AppShell responsivo, AppBreakpoints
│   └── services/            → XmlService, PreferenciasService
```

### Regras arquiteturais invioláveis

1. **Widgets nunca acessam Supabase diretamente**
2. **Notifiers nunca sabem se a fonte é Supabase, SQLite ou Firebase**
3. **Repositórios sempre retornam `Resultado<T>` — nunca lançam Exception**
4. **Soft delete obrigatório** — campo `inativo_em timestamptz` em todas as tabelas
5. **RLS ativo em todas as tabelas** com `empresa_id` para isolamento multi-tenant
6. **`toMap()` nunca inclui `id`** quando o UUID é gerado pelo banco

---

## Padrões técnicos

### Resultado\<T\> — retorno padronizado de operações

```dart
sealed class Resultado<T> {}

class Sucesso<T> extends Resultado<T> {
  final T dados;
  Sucesso(this.dados);
}

class Falha<T> extends Resultado<T> {
  final TipoFalha tipo;
  final String mensagem;
  final Object? detalhes;
  Falha(this.tipo, this.mensagem, {this.detalhes});
}

enum TipoFalha {
  validacao, dominio, permissao, naoEncontrado,
  duplicidade, xmlInvalido, rede, servidor, desconhecido
}
```

Toda operação que pode falhar retorna `Resultado<T>`. Nenhum `catch` silencioso — erros são classificados, propagados e exibidos com contexto real.

### Sealed class de estado — máquina de estados por tela

```dart
sealed class XState {}
class XInicial    extends XState {}
class XCarregando extends XState {}
class XCarregado  extends XState { final List<X> dados; }
class XVazio      extends XState { final String mensagem; }
class XErro       extends XState { final String mensagem; }
```

O compilador Dart garante que todos os estados são tratados explicitamente — impossível esquecer um caso sem erro de compilação.

### Isolamento multi-tenant com RLS

Cada empresa vê exclusivamente seus próprios dados — por design de banco, não por lógica de aplicação:

```sql
create policy "dados da empresa"
  on public.produtos for all
  using (
    empresa_id = (
      select empresa_id from public.usuarios where id = auth.uid()
    )
  );
```

Validado em produção: inserção com `empresa_id` incorreto resulta em dados completamente invisíveis para o usuário autenticado — sem nenhuma verificação na camada de aplicação.

---

## Funcionalidades implementadas

### ✅ Autenticação

- Login com email e senha via Supabase Auth
- Sessão persistente com token JWT
- Login obrigatório a cada abertura (segurança para dispositivos compartilhados)
- Modo de desenvolvimento configurável via `config_deploy.dart`
- Lembrar email no dispositivo (opt-in, senha nunca salva localmente)

### ✅ Navegação responsiva

- GoRouter com ShellRoute
- AppShell adaptativo: sidebar no desktop, NavigationBar no mobile
- Redirecionamento automático baseado em estado de autenticação
- Rotas dinâmicas com parâmetros (`/notas/:id`, `/conferencia/:id`)

### ✅ Módulo de Estoque — Produtos

- Cadastro com múltiplos campos fiscais (NCM, CEST, unidade)
- Múltiplos códigos de barras por produto
- Indicador visual de estoque baixo baseado em regra de domínio
- Soft delete com confirmação
- Busca por nome e código interno
- Pull-to-refresh

### ✅ Módulo de Notas Fiscais (NF-e)

- Importação de XML via seleção de arquivo no sistema operacional
- Parser completo do leiaute NF-e 4.0 com tratamento de namespace XML
- Detecção de duplicidade pela chave de acesso (44 dígitos)
- Validação estrutural do XML antes do processamento
- Listagem com count de itens por nota
- Tela de detalhes com dados fiscais completos (NCM, CFOP, EAN, lote, validade)
- Upload do XML original para Supabase Storage (auditoria)

**Decisão técnica relevante:** o namespace padrão do XML da NF-e (`xmlns="http://www.portalfiscal.inf.br/nfe"`) faz com que `findAllElements('det')` retorne zero resultados. A solução foi usar `localName` para busca agnóstica de namespace — compatível com qualquer variação de XML da SEFAZ.

### ✅ Módulo de Conferência

- Fluxo de conferência física de mercadorias vinculado à nota importada
- Máquina de estados com 8 estados e transições validadas no domínio:
  `em_andamento → pausada → em_andamento → concluida`
- Registro de quantidade conferida por item
- Detecção automática de divergência (quantidade física ≠ nota)
- Fluxo de aprovação supervisor para divergências
- Cancelamento com motivo obrigatório
- Barra de progresso em tempo real

### 🔄 Em desenvolvimento

- Movimentações de estoque vinculadas à finalização da conferência
- Histórico de movimentações por produto
- Ajuste manual de estoque

---

## Banco de dados

```sql
-- Tabelas em produção
usuarios         -- usuários com empresa_id para isolamento
produtos         -- catálogo com NCM, preços, estoque
produto_barcodes -- múltiplos códigos de barras por produto
notas_fiscais    -- NF-e importadas (chave_acesso UNIQUE)
nota_itens       -- itens de cada nota com dados fiscais
conferencias     -- processo de conferência física (8 estados)
conferencia_itens -- itens conferidos com quantidade_esperada vs conferida
movimentacoes    -- trilha de auditoria imutável de entradas e saídas
```

Todas as tabelas têm:

- `empresa_id` para RLS e isolamento multi-tenant
- `inativo_em timestamptz nullable` para soft delete
- `criado_em timestamptz default now()`
- UUID gerado pelo banco via `gen_random_uuid()`

---

## Processo de desenvolvimento

O projeto é desenvolvido em sessões documentadas. Cada sessão tem:

- Objetivo definido antes de escrever código
- Simulação do fluxo (Python quando necessário) antes de implementar
- Commits incrementais com mensagens semânticas (Conventional Commits)
- Diário de bordo documentando o que foi construído, o que falhou e o que foi aprendido

### Exemplo de debugging estruturado (Sessão 7)

Um bug consumiu mais de 50 horas de diagnóstico: itens de nota fiscal não eram salvos no banco, mas a nota aparecia corretamente na listagem.

**Processo aplicado:**

1. Mapeamento do fluxo completo: note → repository → Supabase
2. Hipótese: o `toMap()` dos itens enviava `'id': ''` ao banco
3. Simulação em Python reproduzindo o comportamento do Dart
4. Confirmação: PostgreSQL rejeita string vazia como UUID com erro silenciado pelo catch
5. Correção cirúrgica: remover `'id'` do `toMap()` — banco gera via `gen_random_uuid()`
6. Regra consolidada e documentada para todos os módulos futuros

**Lição:** catch silencioso em operações de banco é tão perigoso quanto ausência de tratamento de erro. Todo `PostgrestException` agora expõe `e.message` e `e.code` no estado de erro.

---

## Rodando o projeto

### Pré-requisitos

- Flutter SDK (canal stable)
- Conta no Supabase (gratuita)
- VS Code ou Android Studio

### Configuração

1. Clone o repositório:

```bash
git clone https://github.com/seu-usuario/erp-modular.git
cd erp-modular
```

1. Instale as dependências:

```bash
flutter pub get
```

1. Crie os arquivos de configuração (não estão no repositório por segurança):

```dart
// lib/core/supabase_config.dart
abstract class SupabaseConfig {
  static const String url = 'SUA_URL_SUPABASE';
  static const String anonKey = 'SUA_ANON_KEY';
}
```

```dart
// lib/core/config_deploy.dart
abstract class ConfigDeploy {
  static const bool devMode = true; // false em produção
  static const int sessionTimeoutMinutes = 0;
  ConfigDeploy._();
}
```

1. Execute as migrations SQL disponíveis em `docs/migrations/` no seu projeto Supabase.

2. Rode o projeto:

```bash
flutter run -d linux    # Linux desktop
flutter run -d chrome   # Web
flutter run             # Android/iOS
```

---

## Estrutura de commits

O projeto usa [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(escopo): descrição
fix(escopo): descrição
refactor(escopo): descrição
chore(escopo): descrição
docs(escopo): descrição
```

---

## Documentação adicional

A pasta `docs/` contém:

- **Decisões arquiteturais** (v1.0 e v1.1) — decisões tomadas antes de implementar
- **Diários de bordo por sessão** — o que foi construído, o que falhou e o que foi aprendido
- **Guia Universal de Módulos** — checklist e ciclo de vida para cada módulo
- **CLAUDE.md** — contexto para uso com Claude Code no terminal

---

## Módulos planejados

| Módulo | Status |
|---|---|
| Módulo 1 — Almoxarifado e Estoque | 🔄 Em desenvolvimento |
| Módulo 2 — Vendas | 📋 Planejado |
| Módulo 3 — Assistência Técnica | 📋 Planejado |
| Módulo 4 — Dashboard e Relatórios | 📋 Planejado |

---

## Autor

**Leandro Horas Pereira**
Estudante de Engenharia da Computação

- GitHub: [@leoras](https://github.com/leoras)
- LinkedIn: [linkedin.com/in/leandro-horas](https://linkedin.com/in/leandro-horas)

---

## Licença

MIT — veja [LICENSE](LICENSE) para detalhes.

---

> Este projeto é desenvolvido com objetivo de aprendizado e portfólio.
> Toda a arquitetura, decisões e bugs documentados refletem o processo real de desenvolvimento —
> incluindo os erros e o que foi aprendido com eles.
