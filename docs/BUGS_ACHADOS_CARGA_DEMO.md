# Bugs do app achados durante a carga de demonstração (out/2026)

Origem: os agentes que escreveram `docs/homologacao/demo/parte_*.sql` leram o código
das telas e rodaram os scripts numa réplica local (migrations + parte 00). **Nenhum
destes itens foi corrigido nem reproduzido pela sessão principal**: são relatos dos
agentes, a confirmar antes de mexer. Onde o script de demo contornou o problema,
isso está dito — a correção real tira a necessidade do contorno.

Premissa da casa: toda correção passa pelas três conferências do CLAUDE.md
(onde afeta, caso em `qa_casos_teste`, execução no motor/Cypress). Correção de banco =
migration + script de entrega.

Prioridade sugerida: **A** aparece em demonstração/uso comum · **B** afeta cenário
específico · **C** limitação ou dívida.

## Psicossocial / clima / cultura

| # | Prio | Problema | Onde | Contorno na demo |
|---|---|---|---|---|
| 1 | A | `gerar_alertas_psicossociais` falha: `psicossocial_alertas.tipo` é NOT NULL e o gatilho não preenche; o erro é engolido, então nenhum alerta/ação automática nasce. Também aparece `record "new" has no field "campanha_id"` em alguns disparos. | gatilho/função `gerar_alertas_psicossociais` | alertas e ações gravados explicitamente (04a) |
| 2 | A | Escala do IPS invertida: o gatilho grava `ips_score` como média do IPS (proteção), mas as telas leem como IRP-S e mostram `100 − valor`. | gatilho do SIPRO + telas de resultado | gravada a média do IRP-S (igual à seed TS); novo envio real pela tela reinverte |
| 3 | B | Painel de alertas só exibe classificações `critico` e `elevado`; o gatilho gera `alto`. | painel de alertas psicossociais | — |
| 4 | A | Humor positivo no Painel compara com minúsculas (`feliz`, `motivado`), mas o app grava capitalizado (`Motivado`); o indicador sai 0. | `useDashboardData` | — |
| 5 | B | `EixoPanel` consulta `feedbacks.destinatario_id`, coluna inexistente: o contador de reconhecimento da aba Autonomia dá erro. | `EixoPanel` | — |

## Dashboard / Pendências

| # | Prio | Problema | Onde | Contorno |
|---|---|---|---|---|
| 6 | A | `useDashboardData` lê `.count` em consultas sem `{ count: 'exact' }`: `riscosAtivos`, `feedPostsHoje` e `evidenciasEnviadas` ficam sempre 0. | `useDashboardData` | — |
| 7 | B | Política de leitura de `empresa_import_pendencias` compara `profiles.id = auth.uid()`; o correto é `profiles.user_id`. As pendências de importação nunca aparecem para ninguém. | RLS de `empresa_import_pendencias` | — |

## Financeiro / benefícios / plano de ação

| # | Prio | Problema | Onde | Contorno |
|---|---|---|---|---|
| 8 | B | Gatilho que recalcula o status da ação grava `'pausada'` quando há tarefa `bloqueada`, mas o enum `acao_status` não tem esse valor: qualquer tarefa bloqueada derruba a gravação. | gatilho de `plano_acoes`/`plano_tarefas` | nenhuma tarefa `bloqueada` na demo |
| 9 | B | Aba eSocial do Financeiro consulta `folha_itens.competencia`, coluna inexistente: o bloco "Eventos S-1200" mensal nunca monta. | aba eSocial do Financeiro | — |
| 10 | B | Índice único de `folha_alertas_prazo` `(tenant, tipo, ano, faixa, colaborador, empresa)` não inclui a competência: só um alerta mensal por tipo. | índice de `folha_alertas_prazo` | `faixa` = competência |
| 11 | B | `beneficio_valida_elegibilidade` referencia `admissoes.colaborador_cpf` (a coluna é `cpf`): erro assim que um tipo de benefício tem regras de elegibilidade. | função `beneficio_valida_elegibilidade` | tipos de benefício sem regras |
| 12 | C | `plano_acoes`, `plano_comentarios`, `plano_participantes` têm FK para `auth.users`: responsáveis/participantes só podem ser logins reais. | schema | responsáveis por nome em texto; só o login demo participa |

## Avaliações / metas / mapa comportamental / trilhas

| # | Prio | Problema | Onde | Contorno |
|---|---|---|---|---|
| 13 | B | `useResultadosAvaliacao` cruza `avaliado_id` (id da admissão) com `profiles.user_id` e seleciona `profiles.departamento`, coluna inexistente: "Média por setor" e filtros de setor/função ficam vazios ou "Não informado". | `useResultadosAvaliacao` | — |
| 14 | B | Gatilho `meta_checkin_aplica_na_meta` devolve meta "atrasada" para "em andamento" a cada check-in. | gatilho de check-in de meta | UPDATE no tenant demo reaplicando "atrasada" |
| 15 | C | `metas.unidade_id` tem FK para `empresa_cadastro`, não para `filiais`; metas de filial só guardam o nome da unidade. | schema de `metas` | — |
| 16 | B | `mapa_comportamental_gerar_convites` convida só quem está em `usuarios_base` (na demo, só o login). | RPC | `participacoes.usuario_id` com id da admissão (sem FK) |
| 17 | B | Gatilho de cota do mapa comportamental aborta o INSERT se o plano tiver limite menor que a quantidade de mapas. | gatilho de cota | inserts em bloco `DO` com `EXCEPTION` |
| 18 | B | "Minhas Trilhas" casa o e-mail do login com `admissoes.email` em vez do usuário autenticado. | tela Minhas Trilhas | progresso do login demo gravado com o id do auth |

## Férias / ponto

| # | Prio | Problema | Onde | Contorno |
|---|---|---|---|---|
| 19 | A | Solicitação de férias **não aprovada** (pendente, recusada, cancelada) faz `trg_consolida_ferias` / `consolidar_ponto_diario_manual` gravarem "falta" e alertas nos dias futuros do pedido. | gatilhos de férias → ponto | no fim do 02b: linhas do ponto para `pendente` e alertas apagados, só no tenant demo, só após hoje |
| 20 | B | Marcar o link de férias como `assinado` dispara `registrar_ferias_no_ponto`, que grava linhas duplicadas e sem empresa no ponto. | `registrar_ferias_no_ponto` | links só `pendente` |
| 21 | A | `classificar_marcacao_clt` marca vermelho ("interjornada") a volta do almoço, comparando com a saída do almoço do mesmo dia: metade das entradas fica vermelha. | `classificar_marcacao_clt` | UPDATE de `classificacao_clt` só nos registros da demo |
| 22 | C | `gerar_alertas_ponto` e o gatilho de supressão de intervalo criam alertas `intervalo_suprimido` transitórios quando o almoço é batido em tempo real. | gatilhos de ponto | batidas do dia num INSERT único + limpeza |

## Atestados / saúde / SST / Hub Contábil

| # | Prio | Problema | Onde | Contorno |
|---|---|---|---|---|
| 23 | B | `/atestados`: abas Absenteísmo, Saúde Mental e FAP/RAT usam números fixos em zero (`useGafDashboards`); aba Pendências mostra só o selo, com texto fixo no código. | `useGafDashboards` | — |
| 24 | C | `colaborador_id` aponta para `auth.users` (férias) ou `profiles` (atestados, afastamentos, eventos, benefícios); telas casam por CPF/nome. | schema | colunas NULL |
| 25 | C | Não existe tabela de dependentes (só `admissoes.dependentes_irrf`, quantidade). | schema | — |
| 26 | C | `SSTAlertasTab` trata todo marcador "- " do relatório como achado, inclusive itens que não são alertas. | `SSTAlertasTab` | lista numerada "1." nas ações |
| 27 | C | Componentes do Hub Contábil (competências, guias, certidões, calendário) existem mas não estão ligados a nenhuma rota. | Hub Contábil | dados semeados, sem tela |

## Observações para quem for corrigir
- Cada item acima pode ter mais de uma causa; confirme lendo o código/função antes.
- Os scripts `docs/homologacao/demo/parte_*.sql` têm contornos (UPDATEs/limpezas) que
  ficam desnecessários após a correção; não precisam ser desfeitos, mas vale revisar.
- Telas que identificam pessoa por **nome** (celebrações, cobertura da Cultura,
  preferências, férias) misturam homônimos — a parte 00 já gera nomes únicos, mas isso
  é um risco real em cliente com homônimos.
