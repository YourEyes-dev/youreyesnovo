# Levantamento main × produção — 20/10/2026

Método: um Postgres 16 efêmero recebeu as 1.189 migrations da `main` (nenhuma falhou) e dele saiu o
estado esperado (tabelas, colunas, RLS, políticas, gatilhos, views, cron, enums, índices, restrições,
funções). Consultas **somente leitura** (`scripts/levantamento/`) compararam esse estado com a
produção (`diayjpsrcerycycyaxst`). Limites: schema `public`; nada de dados; corpo de função
comparado por hash (na 2ª rodada, sem comentários e espaços).

## Resumo
- **Em dia:** camada de acesso por perfil (usa `ye_eh_dono`), 13º Salário (26/26), Cultura,
  Psicossocial, Feriados fases 1 e 2, Declaração de comparecimento / art. 473.
- **Funções:** 478 diferenças brutas caem para 32 sem o ruído de formatação, e várias dessas são
  **variantes de script por desenho** (o script de entrega troca `SELECT … INTO` por subconsulta
  escalar, regra do SQL Editor). Para dizer se uma variante é equivalente, a arbitragem é a bateria de
  QA do módulo na produção, não o texto.

## Esperado / sem ação
| Item | Por quê |
|---|---|
| Tabelas `backup_*_orfas_20260903`, `backup_ferias_autoaprovacao_20260913` e gatilhos `qa_guarda_cercado` nelas | Limpeza de dados de teste que não houve na produção |
| `backup_dossies_duplicados_20261020` | Nome com a data da montagem local; na produção é `…_20260901` (existe) |
| `backup_qa_cfg_*_20261020` | Do script opcional de documentação de testes ainda não colado |
| RLS ligada em `caepi_cache` e `entitlement_gated_tables` | A produção é mais restritiva que a `main` |
| Política pública do questionário psicossocial por token ausente | Endurecimento anônimo (ISOL-006); a produção usa políticas por vínculo |
| `digest`, `gen_random_bytes`, `uuid_larger/smaller`, `min/max(uuid)` | Atalhos de extensão da réplica |
| `marketye_semear_ilha_teste`, `qa_caso_ponto_478..486` | Semente de teste e rotinas de QA |
| `ye_minha_admissao_id` | Órfã: nenhuma função final a chama |
| Índices `uq_empresa_cnpj_ativa` / `uq_empresa_cpf_ativa` | A função/gatilho de unicidade existem; os índices só entram onde a base está limpa (legado com duplicatas) |
| Colunas `ponto_diario.feriado_trabalhado` e `ponto_escalas.comportamento_feriado` NOT NULL, `feriados.dia/mes` smallint, `ponto_retencao_config.id` extra | Diferenças históricas inofensivas da produção |
| Políticas de `feriados` antigas (4) em vez de `feriados_tenant` | Mesma cobertura por comando |

## Lacunas reais
| # | Lacuna | Impacto | Entrega |
|---|---|---|---|
| 1 | **APLICADA em 20/10/2026** (homologação e produção; `true, true, 2`). `cargo_perfil_ideal` (tabela, 2 políticas, 3 índices, 3 restrições, gatilho) e `cargo_perfil_ideal_por_mapa` | As telas Perfil ideal do cargo (Aprendizado) e aderência do Mapa Comportamental consultam a tabela | `docs/script_cargo_perfil_ideal.sql` (só cria) |
| 2 | **APLICADA em 20/10/2026** (homologação e produção; `true, true, 17 3 * * *`). Cron `ponto-links-vencidos` | Links externos de ponto vencidos não são desativados | `docs/script_ponto_links_vencidos_cron.sql` |
| 3 | Colunas `admissoes.regime_rural`, `admissoes.reversao_desligamento_aprovada_por`, `ferias_periodos_aquisitivos.interrompido_art133` e restrição `admissoes_regime_rural_chk` | Regras das migrations `fase4_avulsos…`, `fase4_desligamento_prazos_ritos`, `fase3_ferias_pontes…`; o front não lê as colunas | `docs/script_fases_3_4_parte1_ferias.sql` e `parte2_admissoes.sql` (+ `precheck_fases_3_4.sql`); `ferias_recalcular_periodo` já usa a coluna do art. 133 e falharia ao zerar o aquisitivo sem ela |
| 4 | Restrições `admissoes_dispensa_exame_justificada`, `chk_epis_estoque_nao_negativo`, `ponto_retencao_config_geolocalizacao_dias_check`, `psicossocial_entrevistas_tipo_sessao_chk` | Guardas de integridade; cada uma exige pré-check de dado existente | `docs/script_fases_3_4_parte2_admissoes.sql` e `parte3_restricoes.sql`: cada restrição só entra se nenhuma linha existente a violar |
| 5 | `admissao_normalizar_cpf`, `admissoes_cpf_duplicado` e gatilho `admissao_normaliza_cpf` | CPF único na admissão (QA ADM-002); já listado em `divergencia_producao_resultado.md` | `docs/script_divergencia_producao_parte2.sql` (conferir pré-check) |
| 6 | Funções Lovable-era sem script em `docs`: `finalizar_admissao_by_token`, `feriado_do_dia`, `reconciliar_donos_documentos`, `superadmin_delete_tenant` | Versões antigas na produção | Avaliar caso a caso (a de `superadmin_delete_tenant` protege só o tenant de QA) |
| 7 | Funções com corpo diferente sem explicação de `SELECT INTO`: `ferias_*`, `desligamento_*`/`admissao_guardar_desligamento`, `apurar_banco_horas_colaborador`, `ponto_espelho_resumo_empresa`, Mapa Comportamental (por_cpf, ficha/time, campanhas) | Podem ser versão anterior | Rodar a bateria de QA do módulo na produção |

## Bateria de QA na produção (20/10/2026)
Nenhum caso de negócio ficou pior que a `main`, exceto 6 por **rotina de teste em versão antiga** (gatilhos,
restrições e `cpf_valido` da produção são idênticos aos da `main`, conferido na `LEV_8`):
COLAB-011, 021, 023, 033 e DOC-030 (corrigidos por `docs/script_qa_colab_doc_rotinas_atualizar.sql`) e
PONTO-486 (rotina ainda não entregue). A bancada de testes na produção é parcial (Férias 1/57 casos,
Ponto 89/194, EPI com 48 sem rotina, RLS 1/8, módulos sem caso: Afastamentos, Folha, Benefícios,
Compliance SST, Central, Edge Functions); ver `docs/ROTEIRO_PRODUCAO_BANCADA_QA.md`.
