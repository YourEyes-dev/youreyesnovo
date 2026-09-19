# YourEyes — Orientação completa do projeto

Documento único de entrada para uma nova sessão Claude assumir trabalho neste
repositório sem redescobrir nada do zero. Consolida `CLAUDE.md`,
`docs/AMBIENTES.md` e o aprendizado acumulado até 09/2026. Leia inteiro antes
de tocar em código, migration ou script de entrega.

---

## 1. O que é o YourEyes

Plataforma SaaS de **RH e SST** (Saúde e Segurança do Trabalho) usada por
clientes reais em produção. Cobre:

- **Ponto eletrônico** (jornada, apuração, espelho, conformidade Portaria 671).
- **Saúde ocupacional** (ASO, exames, atestados, PCMSO).
- **Riscos psicossociais** (NR-1, avaliações, devolutivas).
- **Admissões** (processo admissional e documental).
- **Financeiro / Benefícios** (13º, folha auxiliar, benefícios).
- **Portal do parceiro** e **central de controle de clientes** (multi-tenant).
- **Motor de QA interno** (casos documentados, execução em banco, cobertura
  cruzada com Cypress).

O produto é multi-tenant (uma base, várias empresas cliente), com dados de
saúde sensíveis sob LGPD art. 11. Dono do produto: **contato@ustudy.com.br**
(operação "SUDOMED ITAPEJARA" aparece como cliente âncora nos exemplos).

---

## 2. Stack técnica

- **Frontend:** Vite + React 18 + TypeScript + shadcn/ui + TanStack Query.
- **Backend:** Supabase (PostgreSQL com RLS + Edge Functions em Deno).
- **Publicação das telas de produção:** **Lovable** (publica a partir da
  `main` — merge na `main` já deixa o código pronto para o próximo "Publicar
  no Lovable").
- **Testes:** Vitest (unitário), Cypress (E2E), motor SQL próprio (`qa_*`).
- **Esteira:** GitHub Actions (`.github/workflows/staging.yml`) — aplica no
  STAGING automaticamente após merge na `main`.

Scripts principais (`package.json`):
- `npm run dev` / `dev:staging` / `dev:homologacao`
- `npm run build[:staging|:homologacao|:production]`
- `npm run test` (Vitest), `test:e2e` (Cypress)
- `npm run qa:cobertura-e2e` — guarda que casos `e2e` documentados casem com
  `it()` reais.
- `npm run qa:carimbos` — confere unicidade de carimbos de migration.

---

## 3. Ambientes — os TRÊS mundos

| | PRODUÇÃO | HOMOLOGAÇÃO | STAGING (testes) |
|---|---|---|---|
| Projeto Supabase | `diayjpsrcerycycyaxst` | (projeto próprio, ver `docs/AMBIENTES.md`) | `bmehdgthciuvdbvutsdv` |
| Tela | seguramente.lovable.app (via Publicar no Lovable) | https://ustudy123.github.io/youreyesnovo/homologacao/ | https://ustudy123.github.io/youreyesnovo/teste/ |
| Dados | reais (LGPD) | forward-only, script de entrega, pode ter dado real controlado | fictícios (Empresa Staging LTDA, CPFs 900000xxx) |

### Fluxo obrigatório

```
desenvolvimento → merge na main → esteira aplica no STAGING automaticamente
                                (migrations + edge functions + site de teste)
                → humano valida no staging
                → só então: script para SQL Editor de PRODUÇÃO + Publicar no Lovable
```

Também: `desenvolvimento → homologação → produção` como fluxo forward-only
oficial desde 09/2026 (ver §4).

### Regras invioláveis dos ambientes

- **A produção NUNCA é alterada por esta esteira.** Só muda por dois gestos
  manuais do usuário: (1) colar um script de entrega no SQL Editor de
  produção; (2) clicar Publicar no Lovable. Nunca peça nem simule outros
  caminhos.
- **Nunca** colocar dados reais (CPFs, nomes, atestados, saúde) em staging,
  seeds, PDFs de devolutiva ou qualquer documento que circule.
- CPFs fictícios da casa: faixa **900.000.0XX com DV válido** (o sistema valida).

---

## 4. Decisão 09/2026 — homologação forward-only

A homologação **deixou de ser recriada por cópia da produção**. Motivo:
recriar apagava a estrutura de testes já montada na tela do SuperAdmin
(casos, cobertura, mobiliário de QA).

**Consequência:** homologação **não é mais espelho fiel da produção** — pode
divergir. O que antes protegia contra drift (a garantia de que o script
aplicava na estrutura REAL da produção) agora depende inteiramente da
**disciplina do script**: idempotente, `IF NOT EXISTS`, blocos `DO` com
`EXCEPTION` por item, backups antes de UPDATE/DELETE.

O botão RECRIAR (com `mascarar` e `cliente_real`) **NÃO foi apagado, está
suspenso**. Só voltará quando resolvido o problema de preservar casos de
teste. Opções em `docs/AMBIENTES.md`.

Enquanto suspenso, a exceção antiga do RECRIAR (permitir `um_cliente` sem
mascaramento para SUDOMED ITAPEJARA, exigir secret `HOMOLOGACAO_TESTADORES`,
recusar senha `123456` no modo cru) **não se aplica a nada fora dali**:
staging, seeds, PDFs e documentos circulantes seguem sem dado real, sem
exceção.

---

## 5. Mudanças de banco — DUAS entregas sempre

Toda alteração de banco gera:

1. **Migration** em `supabase/migrations/` — o robô aplica no STAGING.
2. **Script de entrega** em `docs/script_*.sql` — para o usuário colar no
   SQL Editor de PRODUÇÃO (o Lovable NÃO roda migrations em produção).

### Regras do script de entrega (aprendidas a caro preço)

- **Uma única transação, sem sessão entre execuções.** Nada de tabelas
  temporárias entre statements — use `WITH x AS MATERIALIZED (...)`
  autossuficientes em cada statement.
- **Nunca `RAISE EXCEPTION` solto** (aborta tudo). Use blocos `DO` com
  `EXCEPTION WHEN OTHERS THEN RAISE NOTICE` por item.
- **Idempotente sempre** — rodar duas vezes não pode quebrar nem duplicar.
- **NUNCA escrever marca de aspas-dólar (`$function$`, `$$`, `$nome$`)
  dentro de comentário.** O SQL Editor divide comandos no navegador contando
  essas marcas no texto cru; uma marca solta em comentário desbalanceia e o
  erro sai longe da causa (caso real: `relation "v_apuracao_preenche" does
  not exist` para uma variável PL/pgSQL). No `psql` passa — a réplica local
  NÃO pega isso. Cada marca precisa aparecer em número **PAR** no arquivo
  inteiro, comentários incluídos.
- **Termina com UMA conferência `SELECT`** — o editor só mostra o último
  resultado. Inclua colunas de erro (`erro_tecnico`) quando houver.
- **Statement timeout existe** — updates linha a linha com função por
  registro estouram em tabelas grandes. Prefira `UPDATE ... FROM` com
  JOIN/CTE.
- **Script que ALTERA/APAGA dado guarda antes.** A produção **NÃO tem PITR**
  (Point-in-Time Recovery — conferido em 08/2026 como add-on não contratado).
  Único resgate é o backup diário — restaurar custa o dia inteiro de todos os
  clientes. Como o SQL Editor roda em uma transação, script com erro se
  desfaz sozinho — o risco real é o que **roda com sucesso e faz a coisa
  errada**. Antes do `UPDATE`/`DELETE`:

  ```sql
  CREATE TABLE IF NOT EXISTS backup_<assunto>_<aaaammdd> AS
    SELECT * FROM <tabela> WHERE <mesmo filtro do update>;
  ```

  E deixe no comentário final o `UPDATE ... FROM backup_...` que desfaz. Mais
  cirúrgico que PITR e não depende de add-on. Não vale para script que só
  CRIA coisa nova (tabela, função, política).
- **DDL em tabela movimentada:** `SET lock_timeout = '10s'`. Nunca criar
  triggers em DUAS tabelas movimentadas na mesma transação (deadlock real já
  ocorrido) — divida em `parte1`/`parte2`.
- **`auth.uid()` é NULL no SQL Editor.** Simule usuário com:
  ```sql
  select set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role','authenticated')::text, true);
  ```
  (transação-local).

### Regras das migrations

- **Carimbo (timestamp do nome) ÚNICO** — carimbos duplicados quebram o
  registro do CLI. **Gere com `date -u +%Y%m%d%H%M%S`, nunca número redondo.**
  Em 16/09/2026 a esteira quebrou 4× no mesmo dia porque sessões escolheram
  `20260916180000` e `20260916181000` em paralelo. Números redondos colidem
  sempre; segundo real quase nunca colide.
- **Confira a ORDEM, não só a unicidade.** Se uma migration anterior do
  mesmo dia usou carimbo à frente do relógio (comum), `date -u` devolve
  número MENOR e sua migration roda ANTES da que ela depende. Olhe o último
  carimbo da pasta antes de escolher. Aconteceu 16/09/2026 (Etapa 2 às 19:14
  rodava antes da Etapa 1 às 23:00).
- `npm run qa:carimbos` confere e nomeia colisões antes do `db push`.
- **NUNCA URL/chave de projeto no código** (nem produção nem staging).
  Config vive em `app_config` (`supabase_url`, `supabase_anon_key`). Sem
  valores, rotinas de disparo não chamam ninguém (proteção de ambiente).
- **Seed/reparo com dados de produção:** embrulhe em `DO $prodseed$ ...
  EXCEPTION WHEN foreign_key_violation OR not_null_violation OR
  raise_exception THEN RAISE NOTICE ... $prodseed$` — em banco novo pula,
  em produção roda igual. Padrão já em 33+ migrations.
- **Objeto criado fora das migrations em produção:** traga para o repositório
  com `IF NOT EXISTS` (precedentes: `feriados`, `ponto_diario.tipo_dia`).
- Extensões base (`pgcrypto`, `pg_trgm`, `pg_cron`, `pg_net`) já garantidas
  em `20260118212300_extensoes_base.sql` — não recriar. `digest` /
  `gen_random_bytes` têm atalhos em `public` porque `db push` não enxerga
  schema `extensions`.

Total atual: **~1079 migrations** no repositório. Elas atravessam um banco
vazio sem erro — mantenha assim (réplica local: PostgreSQL + stubs de
`auth`/`storage`/`cron`/`net`).

---

## 6. Pegadinhas de schema — não redescobrir

- **`perfil_permissoes.escopo`** é ENUM `perfil_escopo_tipo` **SEM** o valor
  `'empresa'`. Tem `empresa_inteira`, `proprio_usuario`, etc. Compare **como
  texto**: `COALESCE(pp.escopo::text,'') <> 'proprio_usuario'`. Literal
  inválido contra enum quebra em EXECUÇÃO, não na criação da função.
- **`admissoes.status`** (enum `admissao_status`): colaborador ativo =
  `'concluido'` (NÃO existe `'ativo'`). Painéis filtram também por
  `empresa_id` — registros sem vínculo ficam invisíveis.
- **Papéis:** `user_roles` + `has_minimum_role(uid, role)`. Tipos de usuário
  (`usuarios_base.tipo_usuario`) mapeiam via `src/lib/userRoleMap.ts`
  (colaborador → `'user'`).
- **Acesso por perfil:** função `perfil_permite_modulo(tenant, VARIADIC
  modulos)` + políticas RESTRICTIVE `perfil_restringe_leitura_*` em 11
  tabelas sensíveis. Tabela sensível NOVA precisa dessa política (rotina
  PERFIL-003 acusa) ou de exceção documentada dentro da própria rotina.

---

## 7. Motor de QA

Casos documentados em `qa_casos_teste` (código único, ex.: `PERFIL-004`),
com `nivel ∈ 'api' | 'e2e'`.

- **`api`:** roda no motor SQL. Rotinas `qa_caso_<x>()` devolvem
  `qa_retorno` (`situacao ∈ passou | falhou | nao_implementado | erro`
  com `erro_tecnico`). Executadas por `qa_rodar_bateria('manual', '<path
  do módulo>')`. Rotinas são **somente leitura** (simulação por claims em
  transação).
- **`e2e`:** roda no browser via Cypress.

### Regra da casa: **documentação vem antes do teste**

- Todo teste de tela nasce de um caso `e2e` **documentado**. Cypress só
  implementa `e2e` já documentados. **Nunca invente teste sem caso.**
- Módulo sem documentação `e2e` fica sem teste de tela (sem problema).
- Ligação caso ↔ `it()`: `qa_cobertura_e2e (codigo, spec, teste)`, onde
  `teste` é o **título exato** do `it()`. Renomear `it()` sem atualizar a
  ponte quebra a ligação.
- **Guarda automática:** `npm run qa:cobertura-e2e`
  (`scripts/verificar-cobertura-e2e.mjs`) lê da função read-only
  `qa-cobertura-e2e` (fechada por `QA_E2E_TOKEN`) e cruza com `it()` reais.
  Reprova a esteira se houver `it()` sem caso (inventado); avisa (sem
  reprovar) sobre casos `e2e` sem teste e pontes quebradas.

Ao mexer em área coberta: rode a bateria da família no staging E inclua-a
na conferência do script de entrega.

---

## 8. Como fechar uma entrega (obrigatório)

Ao terminar QUALQUER implementação, encerre a resposta com:

1. **O link do ambiente onde a mudança foi de fato validada** — teste
   (https://ustudy123.github.io/youreyesnovo/teste/) quando passou pelo
   staging, ou homologação
   (https://ustudy123.github.io/youreyesnovo/homologacao/) quando foi lá.
   NÃO repita o link do teste no automático se a mudança não passou por lá
   — não prova nada.
2. **O que o usuário abre/clica lá** para conferir (tela, caminho no menu,
   o que deve aparecer). Se for banco: a **conferência SQL** para o SQL
   Editor do projeto de TESTE.
3. **Aviso de que a produção segue intacta.**

Então **PARE e espere**. Só depois de "aprovado" explícito, entregue o
passo de produção (script para SQL Editor de produção e/ou "requer
Publicar no Lovable"). **Nunca antecipe produção sem aprovação**, e
**nunca sugira aplicar em produção sem ter conferido no teste antes**.

---

## 9. Convenções de trabalho

- **Branch própria por sessão** (`claude/...`), PR para `main`, merge após
  testar. Merge dispara a esteira do staging.
- **Nas respostas ao usuário, evite jargão:** fale em "registrar a mudança
  no projeto" e "ambiente de teste", não em branch/PR/merge/staging.
- **Antes de mexer em migrations, `git pull`** — outras sessões e o
  Lovable também escrevem na `main`.
- **Respostas e PDFs de devolutiva:** didáticos, em português, para leitor
  de RH não-técnico. **Nunca** transcrever dados pessoais reais.
- `docs/AMBIENTES.md` documenta infraestrutura dos ambientes. Manual da
  equipe está em PDF fora do repositório.
- **Teste mudanças de banco antes do merge:** réplica local (PostgreSQL +
  stubs de `auth`/`storage`/`cron`/`net`), rode as migrations. As ~1079
  atravessam banco vazio sem erro — mantenha assim.

---

## 10. Documentos de referência dentro do repo

Em `docs/`:

- `AMBIENTES.md` — infraestrutura dos ambientes (produção, homologação,
  staging), secrets, RECRIAR suspenso, opções de preservação.
- `CENTRAL_CONTROLE_CLIENTES.md` — multi-tenant / central.
- `MANUAL_PONTO.md` — regras de ponto eletrônico.
- `PLANO_CORRECAO_MOTOR_QA.md` — QA.
- `ROTEIRO_PRODUCAO_*.md` — roteiros por módulo (ponto, benefícios,
  bancada QA).
- `YourEyes_Conformidade_Portaria_671*.pdf` — conformidade regulatória.
- `YourEyes_Resposta_*.pdf` — respostas a chamados por tema.
- `HANDOFF_CONTINUACAO.md`, `RESUMO_SESSAO_*` — passagem de bastão entre
  sessões.
- `PROMPT_INICIAL_DEV.md` — prompt de arranque histórico.

---

## 11. Checklist mental antes de cada mudança

1. Isto é banco? Então: migration + script de entrega, ambos idempotentes.
2. O carimbo é único E na ordem certa? (`npm run qa:carimbos`).
3. Vai ALTERAR/APAGAR dado em produção? Fiz `CREATE TABLE backup_...`?
4. Tem `$$` em comentário? (Precisa ser par no arquivo inteiro.)
5. Cobre área com QA? Rodei a bateria? Incluí no `SELECT` final?
6. Toquei tabela sensível nova? Tem política `perfil_restringe_leitura_*`?
7. Testei em staging? Meu fechamento aponta para o ambiente CERTO?
8. Estou tentando sugerir passo de produção sem aprovação? PARE.

---

_Documento gerado em 2026-09-19 para orientar novas sessões Claude
trabalhando no projeto YourEyes. Fontes: `CLAUDE.md`, `docs/AMBIENTES.md`,
estrutura viva do repositório._
