# Handoff QA — 29/09/2026

Fechamento da leva de saneamento da bateria de QA. Registra o que foi entregue,
o que fica em aberto (achados de dado, não de código) e as notas de processo.
Sem dado pessoal (referências por código de caso / id técnico).

## O que foi entregue (teste → homologação → produção, registrado na `main`)

Cada correção foi testada em réplica local, validada na homologação e só então
aplicada na produção por gesto manual do dono do produto (SQL Editor). Método:
diferencial (vermelho na homologação × verde no teste = porte; vermelho nos dois
= bug de origem), depois a bateria completa da produção.

- **Fila diferencial (12 famílias):** FÉRIAS, EPI, BEN, Integridade
  (Metas+Plano+Hub), Empresa (ENQ/TAC/DADO/REGRA/FER), SST, FOLHA, DESL, ADM
  (cotas aprendiz/PcD), DOC-030, VIN-008, ISOL-005.
- **PGP-010/012/013** — motor de comissões de parceiros. Padrão AFAST-001:
  `parceiro_fechar_competencia` ganhou `p_tenant` opcional (NULL = global, cron
  intacto); as rotinas de QA passam o cercado. Não é bug da lógica de comissão.
- **4 achados da bateria:** ADM-020 (teto de experiência), ISOL-005 (cercar
  backups sem RLS), ISOL-006 (revogar rotinas abertas ao anônimo), DESL-003
  (dispensa vedada com afastamento ativo).
- **7 pré-existentes:** AFAST-011/020/021/051, FER-003, MKY-063/123.

## Em aberto — achados de DADO (não de código; decisão humana)

### ADM-103 — 3 admissões concluídas sem usuário (produção)
Documentado em `docs/ADM-103_residual_conhecido.md`. O motor de reconciliação
está instalado; o passivo resolvível foi limpo. Restam 3 admissões marcadas
"concluído" cujas pessoas nunca viraram usuário (`usuarios_base`). A auditoria
ADM-103 continua contando (não foi mascarada). Fechar = provisionar esses
usuários (aí o backfill `docs/script_adm_reconciliacao_backfill.sql` resolve
sozinho) ou aceitar como legado. Diagnóstico privado:
`docs/diagnostico_adm103_residual.sql`.

### DESL-065 — 1 desligamento sem exame demissional e sem dispensa registrada
O motor (NR-07) está instalado. A auditoria acusa 1 desligamento que precisa de
ação de RH: lançar a data do exame demissional ou registrar a dispensa com
motivo. Não é código.

## Notas de processo (reincidência conhecida)

- **backup_* nascem sem RLS → ISOL-005.** Toda tabela `backup_*` que os scripts
  de entrega criam nasce sem RLS e dispara o ISOL-005 até a varredura rodar de
  novo (`docs/script_isol005_cercar_backups.sql`). Estrutural: cercar o backup
  na própria criação.
- **Funções novas nascem abertas ao anônimo → ISOL-006.** No PostgreSQL toda
  função nasce com EXECUTE para PUBLIC; rotina sensível nova reabre o flanco até
  a re-varredura (`docs/script_isol006_revogar_anon_homologacao.sql` /
  migration `20260928232519`). Estrutural: revogar de anon na própria migration
  que cria a função.
- **Constraints `NOT VALID` + dado legado.** Várias CHECK entraram `NOT VALID`
  (tipo_pessoa, FAP faixa, experiência, suspensão): linhas legadas passam até
  serem tocadas, quando qualquer UPDATE revalida a linha inteira e estoura
  (erro 23514). Ver abaixo.

## Legado de dado da HOMOLOGAÇÃO (só teste; produção limpa) — NÃO perseguir

A produção está **limpa** de `tipo_pessoa` inválido (0 linhas). A base **fictícia
da homologação** tem legado inválido espalhado em `empresa_cadastro`:
- `tipo_pessoa` fora de {pj,pf,NULL}: ~1397 linhas (2 valores).
- FAP fora da faixa legal (`chk_empresa_fap_faixa`): pelo menos 1 linha (FAP
  0.0002; a faixa legal é 0,5–2,0).

Como são constraints `NOT VALID`, tentar normalizar uma coluna revalida a linha
e tromba na próxima (whack-a-mole). **Recomendação: não limpar** — é dado
fictício, não afeta produção, e nenhum caso vermelho depende disso. Se um dia a
homologação precisar ficar impecável, o único caminho limpo é re-semear os dados
de staging (ou corrigir TODAS as colunas inválidas de cada linha de uma vez),
como tarefa própria.

## Rodada 2 (29/09, tarde) — bug de tela, crashes do motor e Cypress

Segunda leva do mesmo dia, sobre o relatório da manhã (762 passou · 5 falhou ·
3 erro) e um bug de tela reportado à parte. Tudo validado na homologação e
aplicado na produção por gesto manual; os 5 acionáveis fecham verdes nos dois
ambientes (conferido chamando as rotinas direto — ver timeout abaixo).

### Bug de tela — Novo Atestado sem colaboradores
Causa: a tela lê `admissoes` pedindo `cargo_id` (coluna nova da Onda 2, 28/09);
a coluna chega ao teste pela esteira mas **não** à homologação/produção sem o
script à mão. Sem ela, o PostgREST recusa o SELECT inteiro (400) e a lista vem
vazia — enquanto a lista de atestados (que não pede `cargo_id`) segue aparecendo.
Entrega: `docs/script_admissoes_cargo_id.sql`, com **suspensão dos gatilhos de
usuário durante o backfill** (`DISABLE TRIGGER USER`): o backfill acionava
`auto_criar_contrato_experiencia` e estourava `NOT NULL` em admissão sem
`data_admissao`. Aplicado e confirmado nos dois ambientes.

### Motor — crashes/regressões do próprio arnês de QA (corrigidos)
- **PONTO-402** (era `erro`): o UNIQUE do FER-003 (uma tabela de feriados por
  unidade) fazia `qa_feriado_da_unidade` estourar `duplicate key` na 2ª rodada.
  Helper passou a reaproveitar a tabela já vinculada.
  Migration `20260929183009` / `docs/script_qa_feriado_da_unidade_idempotente.sql`.
- **MKY-063 / MKY-123** (eram `erro`): as rotinas apagavam TODAS as empresas do
  cercado (para o `marketye_buscar` pegar a mais antiga), e o `DELETE` batia na
  FK `admissoes_empresa_id_fkey` das rotinas irmãs. Agora cada uma reaproveita a
  sua empresa QA e a torna a única mais antiga (`created_at=1970-01-01`),
  empurrando a irmã para frente — sem `DELETE`.
  Migration `20260929184150` / `docs/script_fix_mky_063_123_sem_delete_empresa.sql`.
- **ISOL-005 / ISOL-006** (`falhou`): reincidência estrutural conhecida (backups
  nascem sem RLS; funções novas nascem abertas ao anônimo). Re-rodadas as
  varreduras `docs/script_isol005_cercar_backups.sql` e
  `docs/script_isol006_revogar_anon_homologacao.sql`.

### Cypress — era config, não código
Disparo dava HTTP 403/401. O botão usa o secret `GITHUB_DISPATCH_TOKEN` (Edge
Function `qa-disparar-cypress`, workflow `cypress-homologacao.yml`). O token não
tinha `Actions: write` / estava inválido. Resolvido gerando token com permissão
de Actions e salvando o secret no projeto Supabase + redeploy da função. Sem
mudança de código.

### AFAST-021 — passou a achado documentado
Ver `docs/AFAST-021_recaida_responsabilidade_conhecido.md`: a acumulação por CID
existe; falta materializar "sem novos 15 dias do empregador" na recaída. Mudança
de recurso (3 conferências) — fica como conhecido, junto de ADM-103/DESL-065.

### Em aberto (não urgente) — timeout da bateria "todos os módulos"
A suíte cresceu para 784 casos e a execução única "todos os módulos" estoura o
teto de tempo (SQL Editor: "upstream timeout"; provavelmente também o botão da
tela, que parou de gravar execução nova). Não é regressão. Contornos usados:
rodar por módulo no seletor, ou chamar rotinas direto
(`docs/diagnostico_conferir_5_casos_direto.sql`). Conserto de vez (tarefa
própria): rodar por módulo/em lotes, ou tornar a bateria assíncrona / subir o
`statement_timeout`.

## Estado final

Bateria de QA (produção e homologação): **limpa dos vermelhos acionáveis**.
Restam apenas os achados que dependem de decisão humana — ADM-103, DESL-065 e
AFAST-021 — mais o legado fictício da homologação. Produção nunca foi alterada
por esteira — só por script colado à mão, com backup antes de qualquer alteração
de dado. Bug de tela do Novo Atestado corrigido; Cypress disparando; único item
técnico pendente é o timeout da bateria completa (acima).
