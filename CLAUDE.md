# YourEyes — regras da casa para sessões do Claude Code

Plataforma SaaS de RH/SST (ponto eletrônico, saúde ocupacional, psicossocial,
admissões, financeiro). Stack: Vite + React 18 + TypeScript + shadcn/ui +
TanStack Query; Supabase (PostgreSQL com RLS, Edge Functions); as telas de
produção são publicadas pela **Vercel** (a partir da branch `producao`; o
Lovable está dormente — ver `docs/AMBIENTES.md`).

## Os dois ambientes — decore isto antes de qualquer coisa

| | PRODUÇÃO | STAGING (testes) |
|---|---|---|
| Projeto Supabase | `diayjpsrcerycycyaxst` | `bmehdgthciuvdbvutsdv` |
| Telas | youreyes.com.br (Vercel, via branch `producao`) | https://youreyes-dev.github.io/youreyesnovo/teste/ |
| Dados | reais, protegidos por LGPD | fictícios (Empresa Staging LTDA, CPFs 900000xxx) |

**Fluxo obrigatório:** desenvolver → mesclar na `main` → o workflow
`.github/workflows/staging.yml` aplica sozinho no STAGING (migrations +
functions + site de teste) → humano valida no staging → só então produção.

**A produção NUNCA é alterada por esta esteira.** Ela só muda por dois gestos
manuais do usuário: (1) colar um script de entrega no SQL Editor de produção;
(2) publicar as telas na **Vercel**. Nunca peça nem simule outros caminhos.
A Vercel serve as telas de produção a partir da branch **`producao`** (NÃO da
`main`): merges na `main` geram só pré-visualização. **Publicar** = avançar a
`producao` para o commit desejado da `main`, via PR `main → producao` (a Vercel
então publica em `youreyes.com.br` sozinha). O Lovable está dormente — não
republique por ele. Detalhes e rollback (DNS/branch) em `docs/AMBIENTES.md`.

**Nunca** coloque dados reais (CPFs, nomes, atestados) no staging, em seeds,
em PDFs de devolutiva ou em documentos que circulam. Dados de saúde são
sensíveis (LGPD art. 11). CPFs fictícios da casa: faixa 900.000.0XX com
dígito verificador válido (o sistema valida DV).

**Decisão 09/2026 — a homologação deixou de ser recriada.** O fluxo passou a ser
`desenvolvimento → homologação → produção`, forward-only: tudo entra por script
de entrega (o MESMO em homologação e depois em produção), nunca mais por cópia da
produção para baixo. Motivo: recriar apagava a estrutura de testes já montada na
tela do SuperAdmin (casos documentados, cobertura, mobiliário de QA). Consequência
a ter em mente: a homologação **deixa de ser espelho fiel da produção** e passa a
divergir dela — some a garantia que ela dava de "o script aplica na estrutura REAL
da produção?". O que protege a produção do drift vira a disciplina do próprio
script (idempotente, `IF NOT EXISTS`, blocos `DO` com `EXCEPTION` por item). O
RECRIAR abaixo NÃO foi apagado, mas está **suspenso**: só voltar a usar depois de
resolver a preservação dos casos (opções anotadas em `docs/AMBIENTES.md`).

**Exceção única, e só na homologação (quando o RECRIAR estava em uso):** o botão RECRIAR tem os campos
`mascarar` e `cliente_real`. Em `um_cliente`, só o cliente informado vem com
dado real e todos os outros seguem embaralhados (decisão do dono do produto,
08/2026, para a própria operação da casa — SUDOMED ITAPEJARA); em `nao`, a
cópia inteira sai crua. Prefira sempre `um_cliente`: cobre o mesmo caso de
uso com uma fração da exposição. A esteira recusa os dois modos sem o secret
`HOMOLOGACAO_TESTADORES`, e no modo cru também recusa a senha compartilhada
`123456`; superadmins nunca ficam com senha compartilhada quando há dado real
na base. Detalhes em `docs/AMBIENTES.md`. **Isso não afrouxa nada fora dali**:
staging, seeds, PDFs e qualquer documento que circule seguem sem dado real,
sem exceção.

## Mudanças de banco: migration + script de entrega

Toda mudança de banco vira DUAS entregas:
1. **Migration** em `supabase/migrations/` — é o que o robô aplica no staging;
2. **Script de entrega** em `docs/script_*.sql` — versão para o usuário colar
   no SQL Editor de produção (nem a Vercel nem a esteira rodam migrations em
   produção — o banco de produção só muda por script colado à mão).

Regras dos scripts de entrega (aprendidas a caro preço):
- O SQL Editor roda o arquivo inteiro em UMA transação e NÃO mantém sessão
  entre execuções: nada de tabelas temporárias entre statements — use CTEs
  `WITH x AS MATERIALIZED (...)` autossuficientes em cada statement.
- Nunca `RAISE EXCEPTION` solto (aborta tudo): blocos `DO` com
  `EXCEPTION WHEN OTHERS THEN RAISE NOTICE` por item.
- Idempotente sempre (rodar duas vezes não pode quebrar nem duplicar).
- **Nunca escreva uma marca de aspas-dólar (`$function$`, `$$`, `$nome$`) dentro
  de um comentário.** O SQL Editor divide os comandos no navegador e conta essas
  marcas no texto cru: uma marca solta num comentário desbalanceia a contagem, o
  divisor passa a ler o corpo da função como SQL solto e o erro sai longe da
  causa (já aconteceu: `relation "v_apuracao_preenche" does not exist`, onde
  aquilo era uma variável PL/pgSQL). No `psql` passa — o servidor ignora
  comentário —, então a réplica local NÃO pega isso. Confira que cada marca
  aparece em número PAR no arquivo inteiro, comentários incluídos.
- **Script que CRIA TABELA nova aciona o "auto-RLS" do SQL Editor — e ele
  corrompe as funções do mesmo arquivo.** O editor tem um auxiliar "enable RLS
  on newly created tables" que só LIGA quando o script cria tabela (`CREATE
  TABLE`, ou `SELECT ... INTO`, que também cria tabela). Uma vez ligado, ele
  varre o texto inteiro e INJETA `ALTER TABLE <x> ENABLE ROW LEVEL SECURITY` —
  inclusive DENTRO do corpo das funções, tratando cada variável de `SELECT ...
  INTO v_x` como se fosse tabela nova. Isso parte a string com aspas-dólar e o
  erro sai deslocado (`unterminated dollar-quoted string`, `no function body
  specified`) numa função QUALQUER, longe da causa. No `db push`/`psql` não
  existe esse auxiliar — o staging NÃO pega (aconteceu com o script da Ouvidoria,
  set/2026: injetou `ALTER TABLE v_link/v_colab/v_rot ...` dentro de uma RPC).
  Por isso os scripts que só criam FUNÇÃO nunca sofrem, e só o que cria TABELA
  quebra. Num script de entrega que precisa criar tabela:
  1) Crie a tabela por `EXECUTE` dentro de um bloco `DO`, montando a string como
     `'CREATE ' || 'TABLE public.x (...)'` — assim a sequência contígua
     `CREATE TABLE` NÃO existe no texto e o auxiliar não detecta tabela nova.
  2) Nas funções, NUNCA use `SELECT ... INTO var`; atribua por subconsulta
     escalar (`v := (SELECT ... LIMIT 1)`) e monte objetos com `to_json(...)`.
  A migration equivalente (que roda por `db push`) pode manter `CREATE TABLE` e
  `SELECT INTO` normais — a pegadinha é só do editor.
- Termina com UMA conferência `SELECT` — o editor só mostra o último
  resultado. Inclua colunas de erro (ex.: `erro_tecnico`) quando houver.
- Existe statement timeout: updates linha a linha com função por registro
  estouram tempo em tabelas grandes — prefira UPDATE com JOIN/CTE.
- **Script que ALTERA ou APAGA dado existente guarda as linhas antes.** A
  produção NÃO tem Point-in-Time Recovery (conferido no painel em 08/2026: o
  PITR aparece como add-on não contratado); o único resgate é o backup diário,
  e restaurá-lo custa o dia inteiro de todos os clientes. Como o SQL Editor
  roda em UMA transação, script que dá erro se desfaz sozinho — o risco real é
  o script que roda com SUCESSO e faz a coisa errada. Então, antes do
  `UPDATE`/`DELETE`, copie o que será tocado:
  `CREATE TABLE IF NOT EXISTS backup_<assunto>_<aaaammdd> AS SELECT * FROM <tabela> WHERE <mesmo filtro do update>;`
  e deixe no comentário final o `UPDATE ... FROM backup_...` que desfaz. Isso
  é mais cirúrgico que PITR (devolve só as linhas afetadas, sem descartar o
  trabalho legítimo dos outros clientes no período) e não depende de add-on.
  Não vale para script que só CRIA coisa nova (tabela, função, política).
- DDL em tabela movimentada: `SET lock_timeout = '10s'`; nunca crie triggers
  em DUAS tabelas movimentadas na mesma transação (deadlock real já ocorrido)
  — divida em scripts parte1/parte2.
- `auth.uid()` é NULL no SQL Editor; simule usuário com
  `set_config('request.jwt.claims', json_build_object('sub', uid, 'role','authenticated')::text, true)`
  (transação-local).

Regras das migrations:
- Carimbo (timestamp do nome) ÚNICO — carimbos duplicados quebram o registro
  do CLI. **Gere o carimbo com `date -u +%Y%m%d%H%M%S`; não escolha um número
  redondo.** Em 16/09/2026 a esteira quebrou QUATRO vezes no mesmo dia porque
  sessões diferentes, trabalhando em paralelo, escolheram `20260916180000`,
  depois `20260916181000` — cada uma sem saber da outra. O `db push` indexa
  pelo carimbo: a primeira a mesclar registra a versão e TODAS as entregas
  seguintes, de todo mundo, ficam vermelhas até alguém investigar. O segundo
  de um carimbo real quase nunca colide; um número redondo colide sempre.
  `npm run qa:carimbos` (e a esteira, antes do `db push`) confere e nomeia os
  arquivos em colisão. **E confira a ORDEM, não só a unicidade:** se uma
  migration anterior do mesmo dia usou um carimbo à frente do relógio (é
  comum), o `date -u` devolve um número MENOR e a sua roda ANTES da que ela
  depende — em banco novo, quebra. Ordem manda mais que relógio: olhe o último
  carimbo da pasta antes de escolher. (Aconteceu em 16/09/2026: uma Etapa 2
  carimbada às 19:14 rodava antes da Etapa 1 carimbada às 23:00, e só a
  réplica em banco vazio pegou.)
- NUNCA URL/chave de projeto no código (nem produção nem staging). Config por
  ambiente vive na tabela `app_config` (`supabase_url`, `supabase_anon_key`);
  sem valores, rotinas de disparo não chamam ninguém (proteção de ambiente).
- Seed/reparo com dados específicos de produção: embrulhe em bloco
  `DO $prodseed$` com `EXCEPTION WHEN foreign_key_violation OR not_null_violation
  OR raise_exception THEN RAISE NOTICE ... $prodseed$` — em banco novo pula,
  em produção roda igual (padrão já usado em 33 migrations).
- Objeto criado fora das migrations em produção: traga para o repositório com
  `IF NOT EXISTS` (precedentes: `feriados`, `ponto_diario.tipo_dia`).
- Extensões base (pgcrypto, pg_trgm, pg_cron, pg_net) já garantidas em
  `20260118212300_extensoes_base.sql` — não recriar. `digest`/`gen_random_bytes`
  têm atalhos em `public` porque o db push não enxerga o schema `extensions`.

## Pegadinhas conhecidas do schema (não redescobrir do jeito difícil)

- `perfil_permissoes.escopo` é ENUM `perfil_escopo_tipo` SEM o valor
  `'empresa'` (tem `empresa_inteira`, `proprio_usuario`, ...). Compare sempre
  como texto: `COALESCE(pp.escopo::text,'') <> 'proprio_usuario'`. Um literal
  inválido contra enum quebra em EXECUÇÃO, não na criação da função.
- `admissoes.status` (enum `admissao_status`): colaborador ativo =
  `'concluido'` (não existe `'ativo'`). Painéis filtram também por
  `empresa_id` — registros sem vínculo ficam invisíveis.
- Papéis: `user_roles` + `has_minimum_role(uid, role)`; tipos de usuário
  (`usuarios_base.tipo_usuario`) mapeiam via `src/lib/userRoleMap.ts`
  (colaborador → 'user').
- Camada de acesso por perfil: função `perfil_permite_modulo(tenant, VARIADIC
  modulos)` + políticas RESTRICTIVE `perfil_restringe_leitura_*` em 11 tabelas
  sensíveis. Tabela sensível nova PRECISA da política (a rotina de QA
  PERFIL-003 acusa) ou de exceção documentada dentro da própria rotina.

## QA

Motor em `qa_*`: casos em `qa_casos_teste` (código único, ex.: PERFIL-004),
rotinas `qa_caso_<x>()` que devolvem `qa_retorno` (situacao ∈ passou | falhou |
nao_implementado | erro + `erro_tecnico`), executadas por
`qa_rodar_bateria('manual', '<path do módulo>')`. Rotinas são somente leitura
(simulação por claims em transação). Ao mexer em área coberta, rode a bateria
da família no staging e inclua-a na conferência do script de entrega.

### Testes de tela (Cypress) — documentação vem antes do teste

Regra da casa: **todo teste de tela nasce de um caso documentado**. A
Documentação de testes (`qa_casos_teste`) é a fonte da verdade; cada caso tem
`nivel` `'api'` (roda no motor SQL) ou `'e2e'` (roda no browser, via Cypress).
O Cypress só implementa casos de nível `e2e` **já documentados** — nunca o
contrário. Consequências práticas:
- **Não invente teste de tela** sem um caso `e2e` documentado. Módulo sem
  documentação `e2e` fica sem teste de tela (e sem problema).
- Ao **documentar** casos `e2e` novos para um módulo, aí sim adicione os `it()`
  correspondentes em `cypress/e2e/<modulo>.cy.ts`.
- A ligação caso ↔ `it()` vive em `qa_cobertura_e2e (codigo, spec, teste)`, onde
  `teste` é o **título exato** do `it()`. Renomear um `it()` sem atualizar a
  ponte quebra a ligação.
- **Guarda automática** (reprova a esteira): o passo `npm run qa:cobertura-e2e`
  (`scripts/verificar-cobertura-e2e.mjs`) lê os casos `e2e` da função read-only
  `qa-cobertura-e2e` (fechada por `QA_E2E_TOKEN`) e cruza com os `it()` reais.
  Falha a corrida se houver `it()` sem caso documentado (inventado); avisa (sem
  reprovar) sobre casos `e2e` documentados ainda sem teste e pontes quebradas.

## Como fechar uma entrega (obrigatório)

Ao terminar qualquer implementação, encerre a resposta com:
1. o link do ambiente onde a mudança foi de fato validada — o site de teste
   (https://youreyes-dev.github.io/youreyesnovo/teste/) quando o ciclo passou pelo
   staging, ou o da homologação
   (https://youreyes-dev.github.io/youreyesnovo/homologacao/) quando a validação foi
   lá. Não repita o link de teste no automático: mandar o usuário conferir num
   ambiente onde a mudança não foi aplicada não prova nada;
2. o que exatamente o usuário deve abrir/clicar lá para conferir (tela, caminho
   no menu, o que deve aparecer) e, se for banco, a conferência SQL para o
   SQL Editor do projeto de TESTE;
3. o aviso de que a produção segue intacta.

Então PARE e espere. Só depois de um "aprovado" explícito entregue o passo de
produção (script para o SQL Editor de produção e/ou publicar as telas na Vercel
avançando a branch `producao` — PR `main → producao`). Nunca antecipe o passo de
produção sem aprovação, e nunca sugira que o usuário aplique algo na produção sem
ter conferido no teste antes.

## Convenções de trabalho

- Branch própria por sessão (`claude/...`), PR para `main`, merge após testar.
  O merge dispara a esteira do staging automaticamente. (Nas respostas ao
  usuário, evite o jargão: fale em "registrar a mudança no projeto" e
  "ambiente de teste", não em branch/PR/merge/staging.)
- Antes de mexer em migrations, `git pull` — outras sessões também escrevem
  na `main`.
- Respostas e PDFs de devolutiva para o usuário: didáticos, em português,
  para leitor de RH não-técnico; nunca transcrever dados pessoais reais.
- `docs/AMBIENTES.md` documenta a infraestrutura dos ambientes; o manual da
  equipe está em PDF fora do repositório.
- Teste de mudanças de banco antes do merge: monte réplica local (PostgreSQL,
  stubs de `auth`/`storage`/`cron`/`net`) e rode as migrations — as 744
  atravessam um banco vazio sem erro; mantenha assim.
