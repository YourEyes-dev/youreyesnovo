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

## Estado final

Bateria de QA da produção: **limpa dos vermelhos acionáveis**. Restam apenas os
dois achados de dado acima (ADM-103, DESL-065) e o legado fictício da homologação.
Produção nunca foi alterada por esteira — só por script colado à mão, com backup
antes de qualquer alteração de dado.
