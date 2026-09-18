# Handoff — MarketYE: promoção para produção (para continuar em outra sessão)

**Data:** 2026-09-17/18 · **Branch da sessão:** `claude/quirky-sagan-p127hg`
**Tip:** `d7915850` (sobre `fbf68a69`, sobre `main` `7b453e2e`).

Este arquivo é o resumo desta sessão para uma **próxima sessão do Claude Code
continuar** de onde parou, sem perder contexto. Leia junto com `CLAUDE.md`,
`docs/ENTREGA_MARKETYE.md`, `docs/QA_MARKETYE.md` e `docs/AMBIENTES.md`.

---

## 1. TL;DR — em uma tela

O **MarketYE** (marketplace de serviços que substitui a antiga "Rede de
Parceiros") foi promovido:

- **Produção (banco):** APLICADO pelo usuário (colou `docs/script_marketye_fundacao.sql`
  no SQL Editor de produção). Conferência final = **`OK` · 83/83 rotinas · 0 falhas · 0 erros**.
  O achado crítico **D-18** e os outros 15 achados estão **fechados** em produção.
- **Homologação (banco):** APLICADO, mesma conferência **`OK` 83/83 0/0**.
- **Ambiente de teste / staging (`.../teste/`, projeto `bmehdgthciuvdbvutsdv`):**
  ⚠️ **AINDA NÃO tem a correção desta sessão** (a migração `20260917005941`),
  porque o fix está só na branch `claude/quirky-sagan-p127hg`, **não na `main`**.

### O que FALTA (pendências abertas)

1. **Telas de produção:** falta o usuário clicar **Publicar no Lovable** (publica
   a `main` inteira; as telas do MarketYE já estão na `main`). Ordem certa: banco
   (feito) → telas. Aviso dado: o Publicar leva TODA a `main`, não só o MarketYE.
2. **Registrar na `main`:** a correção (`migração 20260917005941` + script
   regerado) está só na branch. Produção/homologação estão **à frente da `main`**
   e do ambiente de teste. Recomendado mesclar para alinhar (a esteira aplica no
   staging sozinha; **não toca produção**). **Aguardando ok do usuário.**
3. (Decisão pendente antiga, provavelmente já resolvida na prática) fix dos 16
   achados vs. promover — os 16 já foram corrigidos pela Fase 4; nada a decidir.

---

## 2. Os ambientes e o fluxo (decore — vem do CLAUDE.md)

| | PRODUÇÃO | STAGING/TESTE | HOMOLOGAÇÃO |
|---|---|---|---|
| Supabase | `diayjpsrcerycycyaxst` | `bmehdgthciuvdbvutsdv` | projeto próprio (id não anotado) |
| Telas | seguramente.lovable.app (via Publicar no Lovable) | `https://ustudy123.github.io/youreyesnovo/teste/` | `https://ustudy123.github.io/youreyesnovo/homologacao/` |
| Como muda | 2 gestos MANUAIS do usuário: (1) colar script no SQL Editor; (2) Publicar no Lovable | esteira `.github/workflows/staging.yml` aplica sozinha ao mesclar na `main` | colar o MESMO script de entrega (forward-only) |

Fluxo forward-only (decisão 09/2026): `desenvolvimento → homologação → produção`.
O **MESMO script de entrega** é colado em homologação e depois em produção. A
esteira **nunca** toca a produção. Toda mudança de banco = **migração** (staging)
**+ script de entrega** em `docs/script_*.sql` (produção/homologação).

Regras críticas de script de entrega: 1 transação; idempotente; **marcas de
aspas-dólar (`$...$`) em número PAR no arquivo inteiro, comentários incluídos**;
nada de `RAISE EXCEPTION` solto (use `DO ... EXCEPTION`); termina com UM `SELECT`
de conferência; **produção não tem PITR** — script que ALTERA/APAGA dado guarda
backup antes (o nosso só CRIA/CREATE OR REPLACE, então não precisa).

---

## 3. O que esta sessão entregou

### 3.1 Script de entrega ÚNICO e COMPLETO
`docs/script_marketye_fundacao.sql` (8936 linhas) foi **regerado** para ser o
veículo único de produção. Antes ele estava no estado **anterior** às correções
da Fase 4 (colá-lo reabriria os 16 achados, inclusive o D-18 via `<> 'cliente'`
em vez de `IS DISTINCT FROM 'cliente'`). Agora inclui, em ordem de carimbo
(CREATE OR REPLACE mais novo vence), a fundação + as correções da Fase 4 do
MarketYE que só existiam como migração aplicada no teste, **sem veículo de
produção**:
- `20260915190000_fase4_marketplace_logica_anuncio_perfil` (MKY-037/052/054)
- `20260915211500_fase4_marketplace_pesos_autocompra` (MKY-082/101)
- `20260915213000_fase4_marketplace_ciclo_anuncio_export` (MKY-053/090)
- `20260915220000_fase4_marketplace_recusa_termos` (MKY-093)
- `20260915223000_fase4_marketplace_rls_vitrine_avaliacao` (MKY-068/087)
- `20260916130000_fase4_marketplace_rls_moderacao_final` (D-18, MKY-121) — já vinha
  no `docs/script_fase4_marketye_rls_ponto_e_motor.sql`, mantido aqui também.
- `20260916200000_qa_rotinas_marketye_sql` (MKY-091/117/131).

A **conferência final** do script foi reescrita para rodar TODAS as rotinas MKY
ativas de `qa_implementacoes` (não uma lista fixa) — autoadaptável.

### 3.2 Reparo de robustez ao BANCO REAL (o que quebrou na 1ª tentativa)
A 1ª aplicação na **homologação** deu `REVISAR` com 3 rotinas em `erro`
(MKY-058, 063, 123) — que **não apareciam** na réplica local nem no prodsim.
Correção: **migração `20260917005941_marketye_qa_058_063_123_banco_real.sql`**
(+ regeneração do script). Causas e correções:

- **MKY-058** `insert on "objects" violates FK "objects_bucketId_fkey"`: o bucket
  privado `marketplace-docs` só era criado por uma migração ANTIGA alheia ao
  módulo (`20260212181003`), que **não entra** no script do MarketYE; no fluxo
  forward-only da homologação ele não existe. **Fix:** o script passou a garantir
  `INSERT INTO storage.buckets ('marketplace-docs',...,false) ON CONFLICT DO NOTHING`
  E a rotina 058 garante os buckets dentro dela mesma (transação descartável).
- **MKY-063/123** `update/delete on "empresa_cadastro" violates FK "admissoes_..."`:
  as rotinas faziam `DELETE FROM empresa_cadastro` para deixar a busca
  determinística; no banco real o cercado tem filhos (`empresa_cadastro` tem
  ~25 FKs NO ACTION: admissoes, ponto, metas...). **Fix:** trocaram o DELETE por
  `UPDATE` de todas as linhas do tenant (com INSERT só se não houver nenhuma) —
  determinístico e **sem apagar**.

**Por que a réplica não pegou:** (a) a réplica local não tinha a FK
`storage.objects.bucket_id -> buckets` que o Supabase real tem, e tinha o bucket
`marketplace-docs` (criado pela migração antiga que a réplica roda); (b) o cercado
da réplica não tinha filhos em `empresa_cadastro`. **Lição:** validar rotinas de
QA reproduzindo as condições do banco REAL (FK do Storage + filhos no cercado),
não só a réplica "limpa". (Mesma lição do caso dos 24 "erro" por `SET ROLE` em
função SECURITY DEFINER — ver `qa_rls.*`.)

### 3.3 Commits desta sessão (na branch `claude/quirky-sagan-p127hg`)
- `fbf68a69` — script único e completo (fundação + correções Fase 4).
- `d7915850` — rotinas 058/063/123 robustas ao banco real (migração + script + doc).

Também atualizados: `docs/ENTREGA_MARKETYE.md` (bloco "Atualização 17/09" + nota
do reparo do banco real).

---

## 4. Arquivos-chave

- `docs/script_marketye_fundacao.sql` — **veículo único de produção** do MarketYE
  (fundação + todas as correções + QA motor + qa_rls). Colar SÓ este; **nunca**
  reaplicar versão antiga depois (reabre o D-18).
- `supabase/migrations/20260917005941_marketye_qa_058_063_123_banco_real.sql` —
  correção de robustez (bucket + rotinas 058/063/123). Carimbo único e ordenado.
- `docs/script_fase4_marketye_rls_ponto_e_motor.sql` — entrega consolidada da
  Fase 4 de OUTRAS sessões (MarketYE moderação + EPI/Metas/Ponto/RLS/Edge). USA
  os ajudantes `qa_rls.*` (criados pelo nosso script). Domínio de outra sessão.
- `docs/ENTREGA_MARKETYE.md`, `docs/QA_MARKETYE.md` — documentação da entrega e
  dos achados D-01..D-31.
- `src/components/marketplace/*`, `src/components/admin/superadmin/MarketYEAdminPanel.tsx`
  — front-end do MarketYE (já na `main`; publica via Lovable).

---

## 5. Como validar (recriar a bancada — o scratchpad NÃO sobrevive à sessão)

Os scripts de validação viviam no scratchpad da sessão (sumiram). Recriar assim:

**Réplica local (PostgreSQL 16):** subir um cluster com stubs de
`auth`/`storage`/`cron`/`net`, criar DB `replica`, aplicar TODAS as migrations em
ordem (as ~1067 atravessam banco vazio sem erro — mantenha assim). Para simular
**produção** (sem MarketYE): criar DB `prodsim` e aplicar todas as migrations
**exceto** as que casam `*marketye_*`, `*fase4_*`, `*qa_rotinas_marketye*`; depois
colar o script de entrega em UMA transação (`psql -1`) e conferir.

**Rodar a bateria MarketYE (motor)** como superadmin (a tela chama
`qa_disparar_bateria`, que exige superadmin):
```sql
INSERT INTO auth.users(id) VALUES ('00000000-0000-4000-8000-0000000000aa') ON CONFLICT DO NOTHING;
INSERT INTO public.superadmins(user_id, ativo, email)
  VALUES ('00000000-0000-4000-8000-0000000000aa', true, 'qa-runner@teste.local')
  ON CONFLICT (user_id) DO UPDATE SET ativo=true;
SELECT set_config('request.jwt.claims',
  json_build_object('sub','00000000-0000-4000-8000-0000000000aa','role','authenticated')::text, false);
SELECT public.qa_disparar_bateria('rede-parceiros');  -- id da execução
-- depois:
SELECT situacao, count(*) FROM public.qa_resultados WHERE execucao_id='<id>' GROUP BY situacao;
```
Esperado no MarketYE: **82 passou / 0 falhou / 0 erro / 43 nao_implementado**
(os nao_implementado são casos `e2e` — Cypress — + 6 casos api sem rotina:
MKY-069/104/130/132/133/134). O módulo QA é `path='rede-parceiros'`, label MarketYE.

**Reproduzir as condições do banco real** (para não regredir 058/063/123):
```sql
-- FK do Storage que o Supabase real tem (a réplica não cria sozinha):
ALTER TABLE storage.objects ADD CONSTRAINT "objects_bucketId_fkey"
  FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);
-- bucket privado ausente (simula a homologação forward-only):
DELETE FROM storage.objects WHERE bucket_id='marketplace-docs';
DELETE FROM storage.buckets  WHERE id='marketplace-docs';
-- filho que trava o DELETE em empresa_cadastro do cercado:
--   inserir 1 empresa_cadastro para public.qa_sandbox_tenant_id() e 1 admissoes
--   filha (status 'concluido', CPF fictício com DV válido, ex.: 90000003433).
```
Conferir `date -u +%Y%m%d%H%M%S` para carimbo e `npm run qa:carimbos` (aviso
pré-existente sobre `qa_rotinas_isolamento_rls.sql` com 2 carimbos NÃO é nosso).

---

## 6. Pegadinhas de esquema/QA relevantes aqui

- `empresa_cadastro` tem ~25 FKs NO ACTION (admissoes, ponto, metas, ...): **não
  faça DELETE** em cercado com dados; normalize por UPDATE.
- `storage.objects.path_tokens` é coluna GERADA (não aceita valor no INSERT).
- `storage.objects.bucket_id` tem FK para `storage.buckets` no Supabase real.
- Rotinas de QA rodam via `qa_executar_descartavel(funcao)` (rollback). Exercem
  RLS **sem `SET ROLE`** (proibido dentro de SECURITY DEFINER) usando os
  ajudantes `qa_rls.conta_auth/exec_auth/conta_anon/exec_anon` (schema `qa_rls`,
  fechado para PUBLIC/API; só motor os chama).
- `postgres` na Supabase **não é superusuário**; `ALTER FUNCTION ... OWNER TO`
  exige CREATE no schema (por isso o bloco temporário GRANT/REVOKE em `qa_rls`).
- Conferência OK exige: `erros=0 AND falhas_inesperadas=0 AND rotinas_registradas>=80`.
  Falha em caso com `disposicao` (bug_confirmado/aguardando_construcao) sai em
  `achados_conhecidos` (hoje: vazio, tudo corrigido).

---

## 7. Próximos passos sugeridos (para a próxima sessão)

1. Se o usuário aprovar, **registrar na `main`** a branch `claude/quirky-sagan-p127hg`
   (traz `migração 20260917005941` + script corrigido) para alinhar `main` e o
   ambiente de teste com produção/homologação. Não toca produção. (A branch só
   tem histórico já mesclado + estes 2 commits; se precisar rebasear na `main`
   nova, preserve `fbf68a69` e `d7915850`.)
2. Confirmar com o usuário o **Publicar no Lovable** (telas de produção) — lembrar
   que publica a `main` inteira; oferecer levantar o que mais entraria antes.
3. Se pedirem novas rotinas de QA MarketYE que mexam em Storage ou em cercado com
   filhos, aplicar os mesmos padrões da seção 5 (garantir buckets; normalizar por
   UPDATE) e validar reproduzindo o banco real.
4. Fechamento de entrega SEMPRE: link do ambiente validado + o que clicar +
   "produção intacta"; PARE e espere "aprovado" antes de qualquer passo de produção.

---

## 8. Estado de verificação (evidência desta sessão)

- Cadeia completa: **1067 migrations** aplicam em banco vazio sem erro.
- Migração `20260917005941`: idempotente (2x), full chain OK.
- Script de entrega: aspas-dólar PARES; aplica limpo em base prod-like (com a FK
  real do bucket); `OK` 83/83, 0 falhas, 0 erros; idempotente (2x).
- Reproduzidas as condições reais (FK do Storage + filho admissões no cercado +
  bucket ausente): bateria pela tela **82 passou / 0 falhou / 0 erro**.
- **Homologação (banco real, pelo usuário):** `OK` 83/83 0/0. ✅
- **Produção (banco real, pelo usuário):** `OK` 83/83 0/0. ✅
