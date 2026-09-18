# Handoff de continuação — QA-motor & achados de produção (YourEyes)

> Escrito para uma **nova sessão do Claude Code** retomar exatamente daqui.
> Trate como se fosse a continuação da conversa. Leia primeiro o `CLAUDE.md`
> (regras da casa) e o `docs/RELATORIO_ACHADOS_PRODUCAO.md` (o mapa dos achados).
> Branch de trabalho: **`claude/laughing-newton-p9doqo`** (PR para `main`).

---

## 1. O que essa frente é

Levar o **motor de QA** (casos em `qa_casos_teste`, rotinas `qa_caso_*` que
devolvem `qa_retorno`) ao verde nos três ambientes e, além disso, **corrigir os
achados de compliance reais** que as rotinas denunciam — sempre validando na
réplica local → homologação → produção, **nunca** tocando produção a não ser
por script colado manualmente pelo usuário no SQL Editor.

## 2. Os três ambientes (decore)

| | PRODUÇÃO | HOMOLOGAÇÃO (= staging) | DEV / réplica |
|---|---|---|---|
| Supabase | `diayjpsrcerycycyaxst` | `bmehdgthciuvdbvutsdv` | réplica local |
| Como muda | **só** script colado pelo usuário no SQL Editor | idem (o usuário cola) | você aplica direto |
| Dados | reais (LGPD) | fictícios | fictícios |

- Os três **divergiram entre si** (decisão 09/2026: a homologação deixou de ser
  recriada). Então **cada entrega precisa ser idempotente e rodar nos três**.
- **O dev/réplica é a fonte da verdade** (é o que o repo/migrations produzem).
  O trabalho quase sempre é *drift*: o objeto existe no dev e não desceu para
  homolog/prod. Você **não implementa** — você **entrega** o que o dev já tem.

## 3. A réplica local (seu laboratório)

```bash
export PGHOST=/tmp/qa_pg/sock PGPORT=5599
# se estiver fora do ar (cai com frequência):
su postgres -c '/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/qa_pg/data -l /tmp/qa_pg/pg.log -o "-k /tmp/qa_pg/sock -p 5599" start'
psql -U postgres -d ye -tAc "SELECT 1"   # smoke test
```

Padrões úteis:
- Rodar um caso: `SELECT (public.qa_executar_descartavel('qa_caso_xxx')).situacao;`
  (roda em transação e **faz rollback** — não suja a base). Também expõe
  `.erro_tecnico`, `.obtido`, `.detalhe`.
- Dumpar um objeto para entregar: `pg_get_functiondef('public.fn(args)'::regprocedure)`
  ou via `pg_proc` + `pg_get_triggerdef`.
- Helpers de fixture: `qa_cpf(seed)` (CPF fictício com DV válido, prefixo 999),
  `qa_cpf_formatado`, `qa_sandbox_tenant_id()`, `qa_modo_ligar()`,
  `qa_nova_empresa_pf(razao,cpf,ativo)`.

## 4. Regras de ouro das entregas (aprendidas a caro preço nesta sessão)

1. **Toda mudança de banco = migration + script de entrega.** A migration
   (`supabase/migrations/`) o robô aplica no staging; o script de entrega
   (`docs/script_*.sql`) o usuário cola em homolog e depois prod. **Quando o
   objeto já existe numa migration do repo** (caso comum de drift), basta o
   **script de entrega** — não crie migration duplicada.
   - Carimbo de migration: `date -u +%Y%m%d%H%M%S`, **único e depois do último
     da pasta** (confira a ordem, não só a unicidade).
2. **DDL ⟂ conferência — NUNCA na mesma transação.** Juntar DDL (lock exclusivo)
   com a conferência pesada (rotinas que inserem/leem em muitas tabelas) numa
   base movimentada **deu deadlock** (Tema 4). Padrão: `script_*.sql` = só
   DDL/funções, curto; `conferencia_*.sql` = roda as rotinas, **execução
   separada**. Diga ao usuário para **não colar os dois juntos**.
3. **CHECK/FK novos em tabela com dado real → `NOT VALID`** (valem para
   gravações novas, não reprovam legado), depois um `DO` que tenta `VALIDATE` e
   cai em `NOTICE` se o legado violar. Índice único **não** aceita NOT VALID:
   guarde o `CREATE UNIQUE INDEX` num `DO ... EXCEPTION WHEN unique_violation`.
4. **Aspas-dólar:** cada marca (`$fn$`, `$do$`) em número **PAR** no arquivo
   inteiro; **nunca** uma marca dentro de comentário. Confira:
   `grep -oE '\$[a-zA-Z_]*\$' arquivo | sort | uniq -c`.
5. **Script termina com UMA conferência `SELECT`** (o editor só mostra o último
   resultado). Cuidado com tipos em `UNION` (ex.: `confdeltype::text`).
6. **Script que ALTERA/APAGA dado guarda backup antes** (`CREATE TABLE
   backup_... AS SELECT ...`). Produção **não tem PITR**. Script que só CRIA
   coisa nova dispensa.
7. **O controle E a rotina de QA sofrem drift** (lição do EMP): entregar só o
   controle não basta se a rotina de medição na produção está antiga — ela
   reporta falso-negativo. Ao entregar um controle, cheque se a rotina também
   precisa reentrega.
8. **Simule o drift na réplica antes de entregar:** derrube o objeto (drop/
   substitua por versão stale), confirme que o caso falha, rode o script,
   confirme que passa e que é **idempotente** (rode 2×). Para riscos de legado,
   plante uma linha violadora e prove que o script **não aborta**.
9. **Fechamento de entrega (obrigatório, CLAUDE.md):** ao terminar, PARE e
   espere o "aprovado" do usuário na homologação antes de liberar o passo de
   produção. Nunca antecipe produção.

## 5. O que foi entregue nesta sessão (tudo VERDE em produção salvo indicado)

| Frente | Casos | Script(s) de entrega | Prod |
|---|---|---|---|
| eSocial "sem relógio" | S-2200 (ADM-090), S-2299 (DESL-091), ADM-092/093, S-2230 (AFAST-060), S-2210/CAT (AFAST-030), S-2220 (SST-030), S-2240 (SST-031) + família SST 15/15 | `script_esocial_*.sql`, `script_fase4_sst_extracao_e_motores.sql`, `script_esocial_cat_prazo_s2210.sql` | ✅ |
| Menor de idade | ADM-030, ADM-031, DESL-083, FERIAS-016 | `script_menor_idade_adm030_031.sql`, `script_ferias016_estudante_menor.sql` | ✅ |
| Segregação de função | DESL-002, DESL-106, FERIAS-056, PONTO-252 | `script_t3_segregacao_funcao.sql`, `script_ponto252_controle_efetivo_e_medicao.sql` | ✅ |
| Duplicidade de empresa | EMP-020/021/070/071 | `script_emp_unicidade_documento_ativo.sql` (+ `conferencia_emp_unicidade.sql`, `script_fix_rotinas_emp020_021.sql`) | ✅ (legado 0) |
| Resíduos do motor | COLAB-011/023/033, HIER-002 | `script_residuos_prod.sql` (+ `conferencia_residuos.sql`) | ✅ |
| **Resíduo pendente** | **DESL-003** | ver §6 | ⏳ |

Notas de detalhe:
- **PONTO-252:** a CHECK `chk_ajuste_sem_autoaprovacao` é **cosmética** (compara
  auth_user_id com usuarios_base.id — espaços diferentes). O controle efetivo é
  o gatilho `trg_ponto_ajuste_autoaprovacao`. A rotina foi **remedida** (por
  decisão do dono): passa quando o controle efetivo existe; os ~76 autoaprovados
  históricos viram informação (grandfather), não falha.
- **A2/duplicidade de admissões** (limpeza de cópias exatas) já tinha sido feita
  em sessão anterior; a limpeza **A2 empresa-CPF(11)/vínculo(2)** segue pendente
  (Tema 4 do relatório).

## 6. DESL-003 — o único item aberto (plano preciso de continuação)

**O caso:** contrato suspenso por afastamento ativo/indeterminado impede dispensa
imotivada (CLT art. 476). A rotina `qa_caso_desl_003`: (1) cria admissão, (2)
**insere um afastamento indeterminado sem data_fim** (`prazo_indeterminado=true`),
(3) tenta dispensa sem justa causa e espera bloqueio.

**Sintoma em homolog e prod:** `erro` — a rotina quebra no **passo 2**: o
afastamento indeterminado é **recusado na escrita** com
`"Afastamento sem data de término. Informe a data de fim, ou marque como prazo
indeterminado / benefício do INSS..."`. Ou seja, há um **bug de produto real**:
nesses ambientes não dá para registrar afastamento de benefício INSS sem data de
fim. Na réplica (dev) o passo 2 é aceito e o caso passa.

**O que já foi descartado / entregue:**
- O gatilho `afastamento_valida_e_encerra` da homologação é **idêntico** ao do
  dev e chama `afastamento_sem_prazo_e_legitimo(NEW.prazo_indeterminado, NEW.status,
  NEW.status_geral_new, NEW.tipo_principal_new)`.
- Já entreguei à **homologação** (não à prod) o helper
  `afastamento_sem_prazo_e_legitimo` atual (retorna `true` para
  `prazo_indeterminado=true` — confirmado) **e** o gatilho de derivação
  `afastamento_campos_before` atual (deriva `status_geral_new='prazo_indeterminado'`)
  + coluna `data_fim_estabilidade`. **Mesmo assim, DESL-003 continua `erro`.**
- As colunas `prazo_indeterminado`, `status_geral_new`, `tipo_principal_new`,
  `data_fim` **existem** na homologação.

**A dedução:** como o helper checa `COALESCE(prazo_indeterminado,false)` PRIMEIRO
e retorna true, o caso só pode falhar se, no momento de `afastamento_valida_e_encerra`,
**`NEW.prazo_indeterminado` NÃO estiver true** — logo algum gatilho `BEFORE INSERT`
que roda **antes** dele está zerando/ignorando o prazo. Ordem alfabética dos
BEFORE INSERT em `afastamentos` (homolog): `afastamento_gera_s2230`,
`qa_guarda_cercado`, `tr_afastamento_sincroniza_ponto`, `trg_afastamento_campos_before`,
`trg_afastamento_valida_e_encerra`, ... O suspeito ainda **não confirmado** é
`afastamento_sincroniza_ponto` (ou uma versão stale de `afastamento_campos_before`
que persistiu, apesar da reentrega).

**PRÓXIMO PASSO EXATO (rodar na HOMOLOGAÇÃO):**
1. Peça ao usuário para colar **`docs/diag_desl003_instrumentado.sql`** na
   homologação. Ele insere o afastamento com `data_fim` **futura** (evita o
   RAISE) e lê de volta, **após os gatilhos BEFORE**:
   `prazo_indeterminado`, `status_geral_new`, `status`, e se o helper diz legítimo.
   - Na réplica dá: `prazo_indeterminado=t | status_geral_new=prazo_indeterminado | helper=t`.
   - Se em homolog vier `prazo_indeterminado=f` → um gatilho BEFORE zera o prazo;
     dumpe e diffie os corpos de `afastamento_sincroniza_ponto`,
     `afastamento_campos_before`, `processar_inteligencia_afastamento`,
     `atualizar_afastamento_dias` (homolog vs dev via `pg_get_functiondef`) e
     entregue o(s) stale.
   - Se vier `prazo_indeterminado=t` mas `status_geral_new` diferente e `helper=f`
     → o helper chamado não é o meu (ver overload/assinatura) — cheque
     `SELECT proname, pg_get_function_arguments(oid) FROM pg_proc WHERE proname='afastamento_sem_prazo_e_legitimo';`
2. Achado o objeto stale, entregue a versão do dev (CREATE OR REPLACE), valide na
   réplica **simulando o stale**, e feche o DESL-003 em homolog → prod.

**Cuidado:** são gatilhos de **dado real** em `afastamentos`. Entregue só o que o
diagnóstico apontar, valide simulando o drift, e não leve mudança incompleta à
produção (foi por isso que `script_residuos_prod.sql` deixou o DESL-003 de fora).

## 7. Backlog restante (do `RELATORIO_ACHADOS_PRODUCAO.md`)

- **DESL-003** (§6 acima).
- **Resíduos:** `AFAST-001` (sonda usa tenant real → cercar), `DADO-010 /
  HCAT-010 / HTPL-010` (enums abertos — fronteira resíduo/achado, decisão de
  modelagem).
- **PONTO-252 legado:** os ~76 ajustes autoaprovados históricos seguem na base
  (a trava protege o futuro; decisão do dono foi grandfather, não limpar).
- **Tema 4 pendente:** limpeza **A2 empresa-CPF(11)/vínculo(2)** (dado real,
  backup antes).
- **Tema 5** (travas legais por instituto — Férias, Afastamentos, SST,
  Benefícios, EPI, Desligamento, Folha, Cota) e **Tema 6** (LGPD/acesso a dado
  sensível): grandes, ainda não iniciados.

## 8. Git / fluxo

- Trabalhe na branch **`claude/laughing-newton-p9doqo`**; commite com mensagens
  descritivas; `git push -u origin` com retry/backoff em erro de rede.
- **Não** abra PR sem o usuário pedir. Merge na `main` dispara a esteira do
  staging (e deixa o Lovable pronto para o próximo Publicar).
- Antes de mexer em migrations: `git pull` (outras sessões e o Lovable também
  escrevem na `main`).
- Nas respostas ao usuário: português didático, sem jargão de git; fale em
  "registrar a mudança" e "ambiente de teste". Ao fechar entrega, mande o link
  do ambiente conferido, o que clicar, e o aviso de que a produção segue intacta.
