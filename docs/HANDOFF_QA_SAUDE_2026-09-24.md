# Handoff — saúde do QA (bateria completa) · 24/09/2026

Resumo para uma **nova sessão** retomar o conserto dos casos vermelhos do QA.
Contexto pescado ao rodar a bateria inteira ("Todos os módulos") no SuperAdmin.

## Placar da bateria (execução 24/09/2026 15:54)

- **646 passou · 98 falhou · 9 erro** (~107 casos vermelhos, espalhados por
  muitos módulos: FÉRIAS, EPI, BEN, FOLHA, SST, DESL, ADM, REGRA, AFAST…).
- Contagem de casos difere por ambiente: **teste ≈ 773**, **homologação ≈ 767**.

## A chave: método DIFERENCIAL teste ↔ homologação

A homologação é **forward-only** e **diverge** do teste: o teste recebe tudo
pela esteira (migrations); a homologação só recebe o que é **colado** (scripts
de entrega). Logo, **muitos vermelhos da homologação são correções que já
existem no teste e não foram repassadas**.

Não sair consertando no escuro. Para cada módulo:

1. Rodar a bateria **por módulo** nos **dois** ambientes.
2. Cruzar os vermelhos:
   - **Verde no teste + vermelho na homologação** → a correção já existe; é só
     **repassar** (script de entrega) para a homologação e, depois, produção.
     (Provável maioria.)
   - **Vermelho nos dois** → bug real; corrigir na origem (teste) primeiro,
     depois seguir o fluxo teste → homologação → produção.

## Exceções para não confundir

### 1. Regressão desta sessão — REVERTER (não é "homologação atrasada")
Ao corrigir o PONTO-270 rodou-se o `qa_instalar_cercas()` genérico, que cercou
36 tabelas (não só as 2 de ponto). Duas delas **nunca tinham cerca** e a cerca
nova quebrou testes que estavam verdes — está vermelho **nos dois** ambientes
porque foram cercadas nos dois:

| Caso(s) | Tabela | Ação |
|---|---|---|
| MKY-005, MKY-065 | `marketplace_demanda_latente` | `DROP TRIGGER qa_guarda_cercado` |
| PGP-010, PGP-012, PGP-013 | `parceiro_mrr_snapshots` | `DROP TRIGGER qa_guarda_cercado` |

- Fazer via **migration corretiva** (carimbo > `20260924184510`, para rodar
  DEPOIS do `qa_reinstala_cercas_ponto`) + os mesmos `DROP` na homologação.
- **Manter** as 2 tabelas de ponto cercadas (`ponto_expurgo_eventos`,
  `ponto_retrato_pre`) — o PONTO-270 depende disso.
- Conserto durável de verdade (opcional): ensinar essas rotinas de QA do
  marketye/parceiros a **registrar o tenant sintético** que criam, aí as
  tabelas ficam protegidas E os testes passam (não precisa do DROP).

### 2. AFAST-001 — pré-existente (NÃO reverter cerca)
`afastamentos` já era cercada desde 15/08 (migration antiga). O AFAST-001
escreve num tenant não registrado nessa tabela → é **bug da rotina**, não
regressão desta sessão. Corrigir a rotina (registrar o tenant), não tirar a
cerca de uma tabela sensível.

### 3. ISOL-006 e ISOL-008 — segurança pré-existente (módulo admissão)
- **ISOL-006:** 4 rotinas sensíveis executáveis por **anônimo**:
  `admissao_esocial_gerar_s2200`, `admissao_qualificacao_cadastral`,
  `admissoes_contrato_duplicado`, `desligamento_esocial_gerar_s2299`.
  → revogar EXECUTE do anônimo.
- **ISOL-008:** `admissao_qualificacao_cadastral` roda com privilégio do dono
  **sem reamarrar o cliente** (contorna a política de linha).
  → reamarrar o tenant/usuário dentro da função.
- Sugestão: começar a frente de saúde do QA por estes (são de segurança).

## Como as cercas funcionam (para não repetir o erro)

- `qa_instalar_cercas()` instala o gatilho `qa_guarda_cercado` em **toda**
  tabela de `public` com `tenant_id` (menos `qa_%`). É **genérico** — cerca
  tudo. Rodar de novo re-cerca (o DROP corretivo precisa vir depois dele).
- O gatilho (`qa_bloqueia_fora_do_cercado`) é **no-op fora do modo de teste**
  (`app.qa_modo <> 'on'` → retorna sem checar). Só bloqueia durante rotinas de
  QA, escrita em tenant que não seja um "cercado" registrado. **Seguro em
  produção** (não afeta operação normal).
- Uma rotina de QA é "limpa" quando só escreve nos tenants que **registra** como
  cercado. As que quebram (MKY/PGP/AFAST) escrevem tenant sintético **sem
  registrar** — só passavam porque a tabela não tinha cerca.

## O que JÁ ficou entregue e íntegro em produção (nesta sessão)

- **Item 2** — selfie do link respeita `ponto_configuracao.exigir_selfie_link`.
- **Item 3** — geolocalização capturada no momento do Registrar.
- **Item A** — batida externa grava `empresa_id` do colaborador (forward).
  - Backfill das antigas: **fora** — colide com `ponto_marcacoes_nsr_unico`
    (mover empresa duplica NSR). Só com re-sequenciamento de NSR (fiscal).
- **PONTO-270** — cercas reinstaladas (migration `20260924184510`).
- **Item B** (link por empresa vs por conta) — pendente, para outra sessão.

Telas de produção agora pela **Vercel** (branch `producao`), não mais Lovable
(ver `docs/AMBIENTES.md`). Banco de produção continua só por script no SQL
Editor.
