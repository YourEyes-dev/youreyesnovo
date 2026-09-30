# Correções do Banco de Horas — set/2026

Registro, para a equipe, das correções do módulo de Ponto (apuração e banco de
horas) que entraram em **produção** em setembro/2026. Linguagem de RH; os
detalhes técnicos de cada entrega estão nos scripts citados, dentro de `docs/`.

> **Regra que valeu para todas:** testar (réplica local e/ou ambiente de teste)
> → o dono do produto validar → só então aplicar em produção, colando o script
> no SQL Editor de produção à mão. Nenhuma foi aplicada pela esteira. Cada
> correção é idempotente (rodar de novo não quebra) e termina com uma
> conferência.

## O tema central

O banco de horas debitava horas de quem **não estava trabalhando** e, em alguns
casos, cobrava a mesma hora **duas vezes** (no banco e na folha). Corrigimos em
camadas, da raiz até a limpeza.

## O que entrou em produção

### 1. Apuração respeita vínculo e afastamento (Fase 1)
- **Problema:** o sistema gerava "dias de trabalho esperado" para quem já estava
  **desligado** (após a rescisão) ou **afastado**, e debitava esses dias como
  falta — saldo negativo indevido.
- **Correção:** a apuração só conta dias dentro do vínculo ativo e não debita
  dias protegidos por afastamento.
- **Entrega:** `script_apuracao_vinculo_afastamento_parte1_motor.sql` e
  `_parte2_escala.sql`. Migration:
  `20260929233840_ponto_apuracao_respeita_vinculo_e_afastamento.sql`.

### 2. Reapuração dos afetados + zeragem do grupo (Fase 3)
- **Problema:** dez colaboradores tiveram agosto zerado, mas as horas "voltaram
  a contar" — setembro havia sido apurado com o motor antigo e o número errado
  escorreu de volta.
- **Correção:** reapuramos agosto e setembro dos afetados com o motor já
  corrigido e zeramos agosto de novo só desse grupo (credores e devedores),
  preservando os demais. Agosto voltou a zero para os dez.
- **Entrega:** `script_fase3_reapuracao_e_zeragem.sql` (com backup e desfazer).
  Apoiada pelos diagnósticos só-leitura `script_diag_zeragem_voltou_itapejara.sql`
  e `script_diag_fase2_folha_esocial.sql`.

### 3. Não debita dia que ainda não fechou (corte de dia)
- **Problema:** à noite, o saldo já debitava **amanhã** (e o próprio dia de hoje
  antes de acabar) como falta de jornada inteira. Causa: uso da data em fuso UTC
  — depois das ~21h de Brasília, o "amanhã" já tinha virado.
- **Correção:** o dia sem marcação só vira falta depois de fechar no fuso de
  Brasília.
- **Entrega:** `script_apuracao_nao_debita_dia_futuro.sql`. Migration:
  `20260930015040_ponto_apuracao_nao_debita_dia_futuro.sql`.

### 4. Sábado de equalização não é falta
- **Problema:** nas escalas de equalização mensal (o sábado que fecha a carga do
  mês), quando o sábado não era trabalhado ele entrava como **débito no banco E
  como falta** no espelho — a mesma hora cobrada duas vezes, com risco ao
  descanso semanal (DSR). Caso da Kailaine (19/09).
- **Correção:** o sábado de equalização segue como **débito de banco**, mas não
  conta como **falta de folha**.
- **Entrega:** `script_espelho_equalizacao_nao_e_falta.sql`. Migration:
  `20260930182041_ponto_espelho_equalizacao_nao_e_falta.sql`.

### 5. Limpeza das cópias de segurança
- Removemos de produção as três tabelas de backup criadas como rede de segurança
  (`backup_fase3_banco_20260930`, `backup_fase3_movs_20260930`,
  `backup_fechamento_banco_20260929`).
- **Entrega:** `script_limpeza_backups_banco_horas.sql`.

## Guardas automáticas deixadas

Testes de QA que reprovam se o problema voltar, entre eles:
- **PONTO-475 / PONTO-476** — vínculo e afastamento na apuração (Fase 1);
- **PONTO-478** — sábado de equalização é débito, não falta;
- além de PONTO-421 / 474 / 330 / 472 / 402 / 023 / 024, que seguem verdes.

## Fora de produção de propósito

- **Ajuste de dado de teste do QA (PONTO-001/024):** corrige só a bateria de
  testes rodada de madrugada (fuso). Não muda o produto — não vai para produção.
- **Configuração antiga "Compensações Mensais (Último Sábado)":** removida
  apenas da **Escala Padrão**. As demais escalas (Horário Diferenciado, Escala
  36h, etc.) ainda a têm — padronizar quando for oportuno.

## Pendências conhecidas

- Padronizar a remoção da config antiga de compensações mensais nas demais
  escalas.
- *Gaps* do documento de requisitos de Falta/Banco de Horas e de Abono/Zeragem
  (em análise) — ver o backlog levantado na sessão.
