# Roteiro único de aplicação na PRODUÇÃO — Acesso, Salário, Documentos

> **Este roteiro é um plano. Nada foi aplicado na produção.** A produção só muda
> por dois gestos seus: (1) colar os scripts no SQL Editor de produção;
> (2) publicar as telas (Vercel, avançando a branch `producao`).
> Só comece depois de dizer **"aprovado"** e depois de conferir o ambiente de
> teste (Etapa 0).

Escrito para leitor de RH/operação: cada etapa diz **o que faz**, **o que
conferir antes**, **o resultado esperado** e **como desfazer**. Os arquivos
citados estão na pasta `docs/` do projeto.

---

## Regras de ouro (valem para todas as etapas)

1. **Uma etapa por vez, na ordem.** Cole o arquivo **inteiro**, espere terminar,
   leia o resultado da conferência (a tabelinha final) e só então siga.
2. **Se a conferência não bater, PARE.** Não aplique a próxima. Avise e me mande o
   resultado.
3. **Nunca reaplique uma etapa antiga depois de uma mais nova.** Em especial: se
   o script da fundação de subordinados (Etapa 2.1) rodar de novo **depois**
   das Etapas 4 e 6 (Fases 1a/2a), ele recoloca a versão antiga das funções
   centrais de acesso. Cada script é seguro de rodar duas vezes **em sequência
   correta**; a ordem é o que protege.
4. **Escolha um horário calmo** (fim do dia ou fim de semana) para as Etapas 5 e
   6: elas mudam quem pode gravar o quê, e o efeito é imediato.
5. **Não há restauração pontual (PITR) na produção.** O único resgate geral é o
   backup diário (restaurar custa o dia de todos os clientes). Por isso a Etapa 2a
   guarda as linhas que altera e cada etapa tem um "desfazer" cirúrgico.
6. Sem dado real em nenhum lugar fora da produção. Os resultados das consultas
   abaixo são **contagens**, sem nomes.

---

## Etapa 0 — Antes de tudo (só leitura, nada muda)

### 0.1 Conferir no TESTE
O robô já aplicou todas as mudanças no ambiente de teste ao serem mescladas.
Rode a consulta da **0.2** no SQL Editor do projeto de **TESTE**
(`bmehdgthciuvdbvutsdv`): **todas as colunas devem vir `true`**. Depois abra
https://youreyes-dev.github.io/youreyesnovo/teste/ e confira, com um usuário de
teste de cada tipo (Colaborador sem acesso, Gestor, Administrador):

| Conferir | O que deve acontecer |
|---|---|
| Perfil com Documentos = "Somente o próprio usuário" | vê só a própria pasta; abas administrativas somem |
| Perfil sem "Pode ver salário" | salários aparecem mascarados em Colaboradores, Cargos, Férias, Folha, Benefícios |
| Perfil só com módulo **EPIs** | abre a tela de EPIs, vê a lista e consegue registrar entrega |
| Perfil sem o verbo *Aprovar* em Férias | não consegue aprovar/recusar pedido pendente |
| Gestor/Administrador existente | continua vendo tudo (recebe perfil-modelo) |

> Aviso honesto: nesta sessão eu **não consegui abrir o site de teste** (o
> acesso à rede dele é bloqueado no meu ambiente). A conferência de tela acima
> precisa ser feita por você; as rotinas de QA e a réplica local passaram.

### 0.2 Descobrir o que a produção já tem (rode na PRODUÇÃO e no TESTE)

```sql
SELECT
  (SELECT count(*) FROM pg_proc WHERE proname='pode_ver_salario')                         AS e1_salario_fundacao,
  (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND policyname LIKE 'perfil_restringe_salario_folha_%') AS e1_salario_folha_qtd,
  (SELECT count(*) FROM information_schema.views WHERE table_schema='public' AND table_name='admissoes_segura')       AS e1_view_admissoes,
  (SELECT count(*) FROM information_schema.views WHERE table_schema='public' AND table_name IN ('cargos_segura','ferias_solicitacoes_segura')) AS e1_views_cargos_ferias_de_2,
  (SELECT count(*) FROM information_schema.views WHERE table_schema='public' AND table_name='beneficios_colaboradores_segura') AS e1_view_beneficios,
  (SELECT count(*) FROM information_schema.views WHERE table_schema='public' AND table_name='ferias_alertas_segura')  AS e1_view_alertas,
  (SELECT count(*) FROM pg_proc WHERE proname='ye_cpf_eh_subordinado_direto')             AS e2_subordinados_fundacao,
  (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND policyname LIKE 'perfil_restringe_leitura_ferias_%' AND qual LIKE '%ye_cpf_eh_subordinado_direto%') AS e2_ferias_subord_qtd,
  (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND policyname IN ('perfil_restringe_leitura_ponto_marcacoes','perfil_restringe_leitura_ponto_espelhos') AND qual LIKE '%ye_cpf_eh_subordinado_direto%') AS e2_ponto_subord_de_2,
  (SELECT count(*) FROM pg_proc WHERE proname='ye_pastas_do_usuario')                     AS e3_documentos,
  (SELECT count(*) FROM pg_proc WHERE proname='perfil_permite_modulo' AND pg_get_functiondef(oid) LIKE '%v_tem_perfil%') AS e4_fase1a,
  (SELECT count(*) FROM pg_proc WHERE proname='perfil_modelo_gestor')                     AS e5_fase1b,
  (SELECT count(*) FROM pg_proc WHERE proname='ye_eh_dono')                               AS e6_fase2a,
  (SELECT count(*) FROM pg_proc WHERE proname='qa_caso_perfil_008')                       AS e7_qa_casos,
  (SELECT count(*) FROM pg_proc WHERE proname='perfil_escreve')                           AS e8_fase2b,
  (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='epi_entregas' AND policyname='perfil_restringe_escrita_epi_entregas_ins') AS e9_fase2c,
  (SELECT count(*) FROM pg_proc WHERE proname='qa_caso_epi_070')                          AS e10_epi_modulo,
  (SELECT count(*) FROM pg_trigger WHERE tgname='trg_ferias_decisao_exige_aprovar' AND NOT tgisinternal) AS e11_fase2d,
  (SELECT count(*) FROM pg_trigger WHERE tgname='trg_decimo_terceiro_aprovacao_exige_aprovar' AND NOT tgisinternal) AS e12_fase2e,
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relkind='r' AND c.relname LIKE 'backup\_%' AND NOT c.relrowsecurity) AS backups_sem_rls_esperado_0;
```

Como ler: **`0` = ainda não está nesta base; `> 0` = já está**. (`e1_salario_folha_qtd`,
`e2_*_qtd` contam políticas.) Pule as etapas que já aparecem como aplicadas — mas
**a ordem das que faltam continua a mesma**. No TESTE tudo deve estar `> 0` (e
`backups_sem_rls_esperado_0` = 0).

### 0.3 Pré-checagem de impacto (só leitura) — rode na PRODUÇÃO
Responde "quem vai sentir diferença?". São **contagens por cliente**, sem nomes.

**(A) Antes das Etapas 4–6** — gestão que receberá o perfil-modelo:
```sql
SELECT ub.tenant_id, count(*) AS usuarios_de_gestao_sem_perfil_escolhido
  FROM public.usuarios_base ub
 WHERE ub.auth_user_id IS NOT NULL AND ub.status::text = 'ativo'
   AND ( ub.tipo_usuario::text IN ('administrador','gestor')
         OR EXISTS (SELECT 1 FROM public.user_roles ur
                     WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('manager','admin')) )
   AND NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text = 'owner')
   AND NOT public.is_superadmin(ub.auth_user_id)
   AND NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                     JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
                    WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true
                      AND (v.expira_em IS NULL OR v.expira_em > now())
                      AND COALESCE(pa.tipo::text, '') <> 'padrao_sistema')
 GROUP BY ub.tenant_id ORDER BY 2 DESC;
```
Esses usuários continuam vendo tudo (ganham o modelo "Administrador/Gestor
(padrão)", acesso amplo). Se o número for inesperado, me avise antes.

**(B) Antes da Etapa 4** — gestão com perfil **escolhido restritivo** (passará a ser restringida pelo perfil):
```sql
SELECT ub.tenant_id, count(DISTINCT ub.id) AS gestao_com_perfil_restritivo
  FROM public.usuarios_base ub
  JOIN public.usuario_perfil_vinculos v ON v.usuario_id = ub.id AND COALESCE(v.ativo, true)
  JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.tipo::text,'') <> 'padrao_sistema'
  JOIN public.perfil_permissoes pp ON pp.perfil_id = pa.id AND COALESCE(pp.escopo::text,'') = 'proprio_usuario'
 WHERE ( ub.tipo_usuario::text IN ('administrador','gestor')
         OR EXISTS (SELECT 1 FROM public.user_roles ur
                     WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('manager','admin')) )
 GROUP BY ub.tenant_id;
```
Se vier vazio: ninguém de gestão muda. Se vier linha: essa pessoa **passa a ver
só o que o perfil dela diz** (é a regra nova: "o perfil manda"). Confirme com o
cliente se é o desejado **antes** de seguir.

**(C) Antes das Etapas 8, 10 e 11** — perfis escolhidos a que falta algum verbo de escrita:
```sql
SELECT ub.tenant_id, pa.nome AS perfil, pp.modulo,
       string_agg(DISTINCT pp.acao::text, ',' ORDER BY pp.acao::text) AS verbos_que_tem,
       count(DISTINCT ub.id) AS usuarios
  FROM public.usuarios_base ub
  JOIN public.usuario_perfil_vinculos v ON v.usuario_id = ub.id AND COALESCE(v.ativo, true)
  JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.tipo::text, '') <> 'padrao_sistema'
  JOIN public.perfil_permissoes pp ON pp.perfil_id = pa.id AND COALESCE(pp.ativo, true)
       AND pp.modulo IN ('ferias','colaboradores','ponto','analise_jornada','psicossocial',
                         'sst','epi','financeiro','beneficios')
       AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario'
 GROUP BY ub.tenant_id, pa.nome, pp.modulo
HAVING NOT bool_or(pp.acao::text = 'administrar')
   AND NOT (bool_or(pp.acao::text = 'criar') AND bool_or(pp.acao::text = 'editar')
            AND bool_or(pp.acao::text = 'excluir'))
 ORDER BY 5 DESC;
```
Cada linha é um perfil com acesso amplo que **perderá** o verbo que falta (ex.:
perfil que "vê tudo de Férias" mas não tem "Excluir" deixa de excluir). Duas
variações que merecem atenção: **Editar sem Aprovar** (não decidirá mais
férias/13º) e **Criar sem Editar** (o 13º em lote falha). Corrija os **perfis**
na tela (Usuários → Perfis de acesso) *antes* ou *logo depois* da etapa — sem
precisar de script.

**Parada 0:** só prossiga com seu "aprovado" depois de ler (A), (B) e (C).

---

## Etapa 1 — "Pode ver salário" (6 scripts, nesta ordem)

Nada muda para ninguém até alguém desligar "Pode ver salário" num perfil
(padrão = liga; ninguém perde acesso hoje). Só cria colunas, funções, visões e
travas de leitura.

| # | Arquivo | Conferência esperada |
|---|---|---|
| 1.1 | `script_perfil_pode_ver_salario_fundacao.sql` | `coluna_ok=1, funcao_ok=1, perfis_que_nao_veem=0` |
| 1.2 | `script_perfil_salario_folha_rls.sql` | `tabelas_folha_com_trava_salario` ≥ 1 (conta as tabelas de folha cobertas) |
| 1.3 | `script_perfil_salario_admissoes_view.sql` | `view_ok=1, trigger_ok=1` |
| 1.4 | `script_perfil_salario_cargos_ferias_view.sql` | `views_ok_esperado_2=2, triggers_ok_esperado_2=2` |
| 1.5 | `script_perfil_salario_beneficios_view.sql` | `view_ok_esperado_1=1, trigger_ok_esperado_1=1` |
| 1.6 | `script_perfil_salario_ferias_alertas_view.sql` | `view_ok_esperado_1=1, trigger_ok_esperado_1=1` |

- **Importante:** as **telas novas leem pelas visões `*_segura`**. Por isso estes
  scripts vêm **antes** de publicar as telas (Etapa 14), nunca depois.
- **Desfazer:** as visões/gatilhos podem ser removidos (`DROP VIEW … / DROP
  TRIGGER …`) e a coluna fica inofensiva (padrão ligado). Como as telas antigas
  leem as tabelas direto, voltar atrás não quebra nada.

## Etapa 2 — Subordinados diretos (3 scripts)

Cria a âncora de chefia (`admissoes.gestor_cpf`, preenchida só onde o nome do
gestor é único), as funções "meus subordinados" e passa Férias e Ponto para o
escopo "subordinados diretos".

| # | Arquivo | Conferência esperada |
|---|---|---|
| 2.1 | `script_perfil_escopo_subordinados_fundacao.sql` | `coluna_gestor_cpf_ok=1, funcoes_criadas_esperado_4=4`, `vinculos_preenchidos` = nº de ligações achadas |
| 2.2 | `script_perfil_subordinados_ferias.sql` | `politicas_ferias_com_subordinados` ≥ 1 |
| 2.3 | `script_perfil_subordinados_ponto.sql` | `politicas_ponto_com_subordinados=2` |

- **Muda para os usuários:** só perfil de Férias/Ponto com escopo *subordinados
  diretos* (passa de "empresa inteira" para "os meus + dos meus subordinados").
  Quem tem acesso amplo continua igual.
- **Desfazer:** recriar as políticas `perfil_restringe_leitura_ferias_*` e
  `perfil_restringe_leitura_ponto_*` na versão anterior (eu extraio do histórico
  do projeto se precisar); a coluna `gestor_cpf` pode ficar.
- ⚠️ **Nunca rode 2.1 depois da Etapa 4 em diante** (regra de ouro 3).

## Etapa 3 — Documentos "somente o próprio usuário"

| # | Arquivo | Conferência esperada |
|---|---|---|
| 3.1 | `script_perfil_escopo_documentos_proprio.sql` | `pol_pastas_esperado_1=1, pol_docs_esperado_1=1, func_esperado_1=1` |

- **Muda:** perfil com Documentos = "Somente o próprio usuário" passa a ver só a
  própria pasta. Acesso amplo não muda.
- **Desfazer:** `DROP POLICY perfil_restringe_leitura_documento_pastas ON public.documento_pastas;`
  e `DROP POLICY perfil_restringe_leitura_documentos ON public.documentos;`.

---

## Etapa 4 — Acesso Fase 1a: **o perfil tem a palavra final** (leitura)

Arquivo: `script_acesso_fase1_perfil_tem_palavra_final.sql`
Pré-requisito: Etapa 2.1. **Rode antes a pré-checagem 0.3 (B).**

- **Muda:** quem **tem perfil vinculado** deixa de ganhar acesso amplo só por ser
  "gerente"/"administrador". O perfil decide. Super Admin e dono ficam acima.
  Quem **não** tem perfil: nada muda.
- **Conferência:** `funcoes_atualizadas_esperado_2 = 2`.
- **Desfazer:** não há desfazer de dados (nada é gravado). Para voltar ao
  comportamento anterior, reaplique as definições antigas das duas funções
  (`perfil_permite_modulo`, `perfil_amplo_sem_subordinados`) — peça a mim o script
  de retorno antes de aplicar, se quiser tê-lo à mão.

## Etapa 5 — Acesso Fase 1b: o **tipo vira modelo**

Arquivo: `script_acesso_fase1b_tipo_vira_modelo.sql`

- **Muda:** usuário **novo** nasce com um perfil-modelo do seu tipo
  (Administrador/Gestor = acesso amplo editável; Colaborador = próprio). **Usuários
  existentes não são tocados.**
- **Conferência:** `funcs_modelo_esperado_3=3, vincular_ok_esperado_1=1, substituir_ok_esperado_1=1`.
- **Desfazer:** `CREATE OR REPLACE` das duas funções de gatilho
  (`trg_vincular_perfil_padrao`, `trg_substituir_perfil_padrao`) com a versão
  anterior (eu extraio do histórico); usuários criados nesse
  intervalo mantêm o vínculo automático (inofensivo).

## Etapa 6 — Acesso Fase 2a: correções de segurança + **backfill** da gestão

Arquivo: `script_acesso_fase2a_correcoes_e_backfill.sql`
Pré-requisitos: Etapas 4 e 5. **Rode antes a pré-checagem 0.3 (A).**

- **Muda:** (1) só o papel **owner** do próprio cliente fica acima do perfil
  (antes, "admin" também passava); (2) o modelo acompanha os tipos de gestão
  (liderança, RH/DP, implantador, suporte, multiempresa); (3) **grava dados:**
  usuários de gestão ativos sem perfil escolhido recebem o modelo do tipo como
  perfil principal.
- **Guarda de segurança:** cria `backup_vinculos_fase2a_20261015` com as linhas
  antes de tocar (tabela com RLS ligada e fechada para a API).
- **Conferência:** `dono_estrito_esperado_2=2, modelo_por_tipo_esperado_1=1,
  gestao_sem_nenhum_perfil_esperado_0=0, casos_qa_esperado_2=2`,
  `qa_perfil_006` e `qa_perfil_007` = `passou`.
- **Desfazer (cirúrgico):** está comentado no fim do próprio script — devolve os
  vínculos a partir do backup (`UPDATE … FROM backup_vinculos_fase2a_20261015`),
  remove os vínculos `Sistema (Fase 2a)` e reaplica a Etapa 4 para restaurar as
  funções.

## Etapa 7 — QA: casos de Acesso, Salário e Documentos

Arquivo: `script_qa_acesso_salario_documentos_casos.sql`
Pré-requisitos: Etapas 1, 3, 4, 5, 6 (as rotinas auditam essas peças).

- Só cria rotinas de QA somente-leitura e documenta casos. Não altera dado.
- **Conferência:** `casos_esperado_8=8, rotinas_esperado_6=6`; `perfil_008..011`
  e `doc_050/051` = `passou` (ou `nao_implementado` se a produção não tiver massa
  de teste — nesse caso não é erro). **`falhou`/`erro` = parar e me avisar.**
- **Desfazer:** não é necessário (somente leitura).

---

## Etapa 7b — Administrador Master: acrescentar Excluir e Aprovar (antes das etapas de escrita)

Arquivo: `script_perfil_administrador_master_verbos_escrita.sql`. Rode **depois** das
pré-checagens (0.3 C e a consulta do Aprovar) e **antes** da Etapa 8.

- **Muda:** só acrescenta linhas em `perfil_permissoes` do perfil "Administrador Master" (não
  abre módulo novo, não mexe em outros perfis). Cópia de segurança em
  `backup_perfil_verbos_20261016`.
- **Conferência:** `faltando_excluir_esperado_0 = 0`, `faltando_aprovar_esperado_0 = 0`, `ok`.
- **Desfazer:** dois comandos comentados no fim do script.

---

## Etapa 8 — Acesso Fase 2b: o perfil manda na **escrita** (férias, ponto, psicossocial)

Arquivo: `script_acesso_fase2b_escrita_pelo_perfil.sql`
Pré-requisitos: Etapas 4–6. **Rode antes a pré-checagem 0.3 (C).**

- **Muda:** em 12 tabelas, quem tem perfil só grava com o verbo no módulo (Criar /
  Editar ou Aprovar / Excluir; "Administrar" vale por todos). Outras 5 tabelas
  passam a aceitar gravação direta só do Super Admin e do dono (rotinas
  internas seguem normais). **Sem perfil: nada muda.**
- **Conferência:** `tabelas_de_gestao_esperado_12=12, tabelas_endurecidas_esperado_5=5,
  funcao_esperado_1=1`, `qa_perfil_012` e `qa_perfil_013` = `passou`.
- **Desfazer:** consulta no fim do script que **gera** os `DROP POLICY` (um por
  política) — só remove as travas desta fase.

## Etapa 9 — Acesso Fase 2c: EPI, itens da folha e benefícios

Arquivo: `script_acesso_fase2c_escrita_epi_folha_beneficios.sql` · Pré-req.: Etapa 8.

- **Conferência:** `tabelas_de_gestao_esperado_15=15, tabelas_endurecidas_esperado_5=5`,
  `qa_perfil_012` / `qa_perfil_013` = `passou`.
- **Desfazer:** consulta geradora de `DROP POLICY` no fim (só `epi_entregas`,
  `folha_itens`, `beneficios_colaboradores`).

## Etapa 10 — EPI: o módulo "EPIs" basta para ler e gravar entregas

Arquivo: `script_acesso_epi_modulo_libera_entregas.sql` · Pré-req.: Etapa 9.

- **Muda:** quem tem só o módulo EPIs passa a ver a lista e a registrar entregas
  (regra do produto: "se tem EPI e não tem Compliance, o EPI aparece normal").
  O escopo do perfil continua valendo (próprio usuário vê o próprio CPF).
- **Conferência:** `leitura_inclui_epi_esperado_1=1, escrita_inclui_epi_esperado_1=1`,
  `qa_epi_070` e `qa_perfil_013` = `passou`.
- **Desfazer:** dois comandos comentados no fim do script (volta a leitura para
  SST e Colaboradores).

## Etapa 11 — Acesso Fase 2d: solicitação de férias

Arquivo: `script_acesso_fase2d_escrita_ferias_solicitacoes.sql` · Pré-req.: Etapa 8.

- **Muda:** além de Criar/Editar/Excluir, **aprovar ou recusar** um pedido
  pendente exige o verbo **Aprovar** (e, para gestor de subordinados, que o
  pedido seja de um subordinado). Só vale para quem está logado; rotinas
  automáticas não são barradas.
- **Conferência:** `politicas_esperado_3=3, gatilho_esperado_1=1`,
  `qa_fer_070` e `qa_perfil_012` = `passou`.
- **Desfazer:** 4 comandos `DROP` comentados no fim do script.

## Etapa 12 — Acesso Fase 2e: 13º salário e rescisões

Arquivo: `script_acesso_fase2e_escrita_13o_rescisoes.sql` · Pré-req.: Etapa 8.

- **Muda:** `folha_13_calculo` e `folha_rescisoes` exigem o verbo (Financeiro /
  Colaboradores); **aprovar o 13º** exige o verbo Aprovar. O 13º em lote exige
  Criar **e** Editar.
- **Conferência:** `tabelas_esperado_2=2, gatilho_esperado_1=1`,
  `qa_dec13_080` e `qa_perfil_012` = `passou`.
- **Desfazer:** 7 comandos `DROP` comentados no fim do script.

## Etapa 13 — Fechar as tabelas de backup (opcional, só se a 0.2 mostrar `backups_sem_rls_esperado_0 > 0`)

Arquivo: `script_backups_fechar_todos_sem_rls.sql` (substitui o `script_backups_sem_rls.sql`
de lista fixa) — liga RLS e fecha a API em **toda** tabela `backup_*` que esteja aberta. Não apaga nada. Desfazer: comentado no cabeçalho do arquivo.

---

## Etapa 14 — Publicar as telas (Vercel) — **só depois de todas as etapas de banco**

Por quê depois: as telas novas leem as visões `*_segura` e usam as funções novas.
Banco novo com tela antiga funciona; **tela nova com banco antigo, não.**

1. **Conferência final do banco** (consulta 0.2 na produção): todas as colunas
   `e*` das etapas aplicadas `> 0`.
2. **Revisar o que mais vai junto.** A `producao` está **~90 commits atrás da
   `main`** (último commit publicado: `60ace353`). Publicar leva **tudo** o que
   entrou na `main`, não só o Acesso. Além dos scripts deste roteiro, há **12
   scripts fora do escopo dele** que as telas/rotinas novas podem pressupor:
   `script_central_eventos_erro_rotinas`, `script_ponto_compfalta_guard_bypass_qa_modo`,
   `script_psicossocial_gro_severidade_catalogo_fonte_unica`,
   `script_psicossocial_tipo_instrumento_entrevista_coletiva`,
   `script_qa_cercas_compensacao_falta`, `script_qa_cobertura_e2e_*` (6) e
   `script_sec_001_security_definer_search_path`. **Confirme com você quais já
   estão na produção** antes de publicar (eu monto a consulta de conferência
   deles se você quiser).
3. **Gesto:** abrir o PR `main → producao` e mesclar (eu preparo o PR; a
   publicação é gesto seu). A Vercel publica em youreyes.com.br sozinha.
4. **Conferência de tela na produção** (com conta sua, sem expor dado de
   cliente): abrir Documentos, Colaboradores e Férias; criar um usuário de
   teste da casa só se necessário.
5. **Desfazer as telas:** na Vercel, promover o *deployment* anterior
   ("Instant Rollback"), ou voltar a branch `producao` para `60ace353`
   (detalhes em `docs/AMBIENTES.md`). O banco novo é compatível com a tela
   antiga **exceto** onde a tela antiga grava num perfil sem verbo (vai receber
   "sem permissão", comportamento esperado da regra nova).

---

## Resumo em uma tabela

| Etapa | Arquivo | Muda dado? | Efeito para o usuário | Desfazer |
|---|---|---|---|---|
| 0 | consultas 0.2 / 0.3 | não | nenhum | — |
| 1.1–1.6 | `script_perfil_*salario*` | não | nenhum até desligar "Pode ver salário" | `DROP VIEW/TRIGGER` |
| 2.1–2.3 | `script_perfil_*subordinados*` | coluna nova | só perfis "subordinados diretos" | recriar políticas antigas |
| 3.1 | `…documentos_proprio` | não | Documentos "próprio" vê só a própria pasta | `DROP POLICY` ×2 |
| 4 | `…fase1_perfil_tem_palavra_final` | não | perfil manda sobre papel/tipo (leitura) | reaplicar funções antigas |
| 5 | `…fase1b_tipo_vira_modelo` | não | usuário novo nasce com modelo | restaurar gatilhos antigos |
| 6 | `…fase2a_correcoes_e_backfill` | **sim** (com backup) | dono estrito; gestão ganha modelo | `UPDATE … FROM backup_…` |
| 7 | `script_qa_acesso_…` | não | nenhum | desnecessário |
| 8 | `…fase2b_escrita_pelo_perfil` | não | perfil manda na escrita (12+5 tabelas) | `DROP POLICY` gerado |
| 9 | `…fase2c_escrita_epi_folha_beneficios` | não | idem EPI/folha/benefícios | `DROP POLICY` gerado |
| 10 | `…epi_modulo_libera_entregas` | não | módulo EPIs basta | 2 comandos comentados |
| 11 | `…fase2d_escrita_ferias_solicitacoes` | não | aprovar férias exige "Aprovar" | 4 `DROP` |
| 12 | `…fase2e_escrita_13o_rescisoes` | não | aprovar 13º exige "Aprovar" | 7 `DROP` |
| 13 | `script_backups_sem_rls.sql` | não | nenhum | no cabeçalho |
| 14 | PR `main → producao` | — | telas novas | rollback Vercel |

## Limitações que continuam (decisões suas, não bloqueiam o roteiro)

- **Usuários sem nenhum perfil vinculado** continuam gravando como antes — a
  trava só vale para quem tem perfil. Fechar essa lacuna depende de decidir o
  *backfill dos colaboradores* (dar a cada um o perfil "Colaborador (padrão)").
- Tabelas ainda **sem** trava de escrita pelo perfil (deixadas de propósito por
  risco): documentos/pastas, atestados, alertas de saúde, marcações de ponto,
  ouvidoria, documentos de admissão.
- Casos de QA de tela DOC-052/053 ficam só documentados (precisam de uma segunda
  conta-robô restrita e do site de teste liberado na rede do ambiente).


---

## Situação final (16/10/2026)

**Aplicado na produção:** Etapas 1 a 12 (com a 7b), `consulta de status` conferida, QA (`21` a `28` na
homologação e produção, exceto `qa_cercas`), PR de telas #791 mesclado, 9 Edge Functions publicadas
(`ai-chat`, `ai-cultura-manual`, `ai-cultura-sugestao`, `ai-pgr-riscos`, `ai-pop-generator`,
`ai-sst-analise`, `ai-qa-scan`, `ai-qa-agent`, `invite-tenant-user`), `seed-test-user` apagada.

**Pendências para a próxima leva:**
- **Convite por e-mail nunca funcionou** (cadastro de usuário): ver logs de `invite-tenant-user` e o
  segredo `RESEND_API_KEY`/domínio no Resend.
- **Importação de documento de SST** não extrai (0 riscos, 0 ações) num documento que já funcionou:
  conferir no painel se `sst-pdf-extract` e `ai-sst-importacao` existem na produção e em que data
  foram publicadas (o repositório as traz desde 29/09); comparar com a homologação.
- **Conta `teste@seguramente.com`** (teste interno): trocar a senha (era `123456`; ficou pública
  enquanto `seed-test-user` esteve no ar) e encerrar as sessões; log de acessos não disponível.
- **`script_qa_cercas_compensacao_falta`** não aplicado na produção: rodar antes a consulta de
  tabelas sem gatilho `qa_guarda_cercado`.
- **Backfill dos colaboradores: APLICADO em 17/10/2026** (homologação e produção; 1 colaborador
  recebeu o "Colaborador (padrão)"; `candidatos_restantes = 0`, PERFIL-013 e PERFIL-014 `passou`).
  Ficam de fora, por decisão, os outros tipos sem perfil (ex.: 1 `tecnico_seguranca`), que operam
  por papel e pedem decisão caso a caso. Achado aberto: o cadastro de usuário novo dá o
  "Colaborador (padrão)" a qualquer tipo fora da gestão (`rh`, `proprietario`, `tecnico_seguranca`…),
  o que pode restringir um RH ou técnico recém-criado; revisar `perfil_modelo_para_tipo`.
- RH, Gerente de Operações e Gestor/Líder ficaram sem Excluir (decisão aceita em 16/10/2026).
- Opcional: `20_backups_fechar_todos_sem_rls` (varre o catálogo; o de lista fixa já foi aplicado).
