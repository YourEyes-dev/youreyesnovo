# Roteiro de produção — módulo Ponto

Este documento é a **lista mestra** dos pacotes SQL que precisam ser colados,
**em ordem**, no SQL Editor do banco de **produção** (projeto
`diayjpsrcerycycyaxst`) quando a implantação do módulo Ponto for aprovada.

Ele existe para que, ao final de tudo, **nenhum passo se perca e nenhuma
sequência se inverta**. É um documento vivo: cada onda nova entra aqui assim
que é entregue no ambiente de teste.

---

## O princípio (não esquecer nunca)

1. **Nada vai para produção antes de ser validado no ambiente de teste.**
   Toda mudança nasce no teste (pela automação), é conferida por uma pessoa, e
   **só então** o pacote correspondente é colado em produção.
2. **A produção só muda por gesto manual seu.** A automação nunca toca o banco
   real. Você cola o script no SQL Editor de produção — nada mais faz isso.
3. **Ordem importa.** Rode os pacotes na numeração abaixo. Alguns dependem de
   outro ter rodado antes (a coluna "Depende de" avisa).
4. **Antes de colar qualquer coisa, confira o nome do projeto no topo da tela
   do Supabase.** Ele abre sempre no último projeto usado. Tem que estar escrito
   o projeto de **produção**.
5. Todos os pacotes são **idempotentes**: rodar duas vezes não quebra nem
   duplica. Se ficar na dúvida se rodou, rode de novo e olhe a conferência.

---

## Antes da produção: o ensaio na homologação

A fila abaixo **não vai direto para a produção**. Ela passa antes por um ensaio
na **homologação** — a cópia fiel da estrutura da produção (com o drift real).
A homologação responde à pergunta que o teste não responde: *"o script aplica na
estrutura real?"*. Já aconteceu duas vezes de um script passar no teste e abortar
na produção (uma coluna que só existia no teste; funções auxiliares que nunca
chegaram lá) — o ensaio existe para isso não se repetir.

O ensaio usa **os mesmos scripts, na mesma ordem** desta fila; muda só onde se
cola e um passo de preparo antes. Três gestos:

1. **Recriar a homologação** a partir da produção: GitHub → Actions →
   `homologacao` → **Run workflow** → digitar `RECRIAR`. A esteira copia a
   estrutura da produção com um usuário **somente leitura** (a produção nunca é
   tocada) e recria o schema da homologação com ela. Começar a colar só depois de
   a corrida fechar verde. (Requer, uma vez, os secrets `PRODUCAO_DB_PASSWORD` e
   `HOMOLOGACAO_DB_PASSWORD` e o usuário leitor —
   `docs/script_homologacao_leitor_producao.sql`.)
2. **Colar os pacotes em ordem** no SQL Editor da **HOMOLOGAÇÃO** (não da
   produção), lote a lote, lendo a conferência de cada um.
3. **Ensaio aprovado** quando todos os pacotes rodam **sem erro** contra a
   estrutura real, cada conferência dando `OK`. Depois de colados, a homologação
   passa a diferir da produção — de propósito, pelos pacotes desta fila. Só então
   os mesmos scripts, na mesma ordem, vão para o SQL Editor da **produção**.

> Detalhe operacional do ensaio (lotes e checklist): artefato **"Ensaio na
> Homologação — Ponto"**. A conferência da fidelidade da cópia (produção ×
> homologação) é `docs/script_conferencia_homologacao.sql`, e roda **antes** de
> colar os pacotes (o próprio botão já a executa ao final da corrida).

---

## Estado atual

**Nenhum pacote foi aplicado em produção ainda.** Todos estão validados (ou em
validação) apenas no ambiente de teste. Esta é a fila para quando você decidir
implantar.

Legenda de status: ⬜ a fazer · ✅ feito · ⏳ aguardando validação no teste

| # | Pacote | Arquivo | Depende de | Teste | Produção |
|---|--------|---------|-----------|:-----:|:--------:|
| 1 | PONTO-004 — marcação imutável + remove e-mail hardcoded | `docs/script_ponto004_imutabilidade.sql` | — | ⏳ | ⬜ |
| 2 | Onda 0 — travas legais de risco aberto | `docs/script_ponto_onda0_travas_legais.sql` | — | ⏳ | ⬜ |
| 3 | Onda 1 (parte 1) — NSR e histórico de lotação | `docs/script_ponto_onda1_nsr_e_lotacao.sql` | — | ⏳ | ⬜ |
| 4 | Onda 1 (parte 1) — preenchimento histórico do NSR | `docs/script_ponto210_backfill_nsr.sql` | **#3** | ⏳ | ⬜ |
| 5 | Onda 1 (parte 2) — vínculo/empresa na chave | `docs/script_ponto_onda1_vinculo_na_chave.sql` | **#3** | ⏳ | ⬜ |
| 6 | Onda 1 (parte 3) — versionamento + memória de cálculo | `docs/script_ponto_onda1_versionamento_e_memoria.sql` | — | ⏳ | ⬜ |
| 7 | Onda 3 (parte 1) — tolerância cumulativa dos dois tetos legais | `docs/script_ponto_onda3_tolerancia.sql` | — | ⏳ | ⬜ |
| 8 | Onda 3 (parte 2) — jornada da escala + hora extra sem truncar | `docs/script_ponto_onda3_jornada_escala_he.sql` | — | ⏳ | ⬜ |
| 9 | Onda 3 (parte 3) — adicional noturno prorrogado (Súmula 60, II) | `docs/script_ponto_onda3_adicional_noturno_prorrogado.sql` | inclui #8 | ⏳ | ⬜ |
| 10 | Onda 3 (parte 4) — turno da virada pertence ao dia de início | `docs/script_ponto_onda3_turno_da_virada.sql` | — | ⏳ | ⬜ |
| 11 | Onda 2 (parte 1) — cadeia de hash encadeado + verificação | `docs/script_ponto_onda2_cadeia_hash.sql` | **#3, #4** (NSR) | ⏳ | ⬜ |
| 12 | Onda 2 (parte 2) — relógio confiável + origem da batida | `docs/script_ponto_onda2_relogio_e_origem.sql` | — | ⏳ | ⬜ |
| 13 | Onda 2 (parte 3) — detecção de marcações uniformes ("britânico") | `docs/script_ponto_onda2_marcacoes_uniformes.sql` | — | ⏳ | ⬜ |
| 14 | Onda 2 (parte 4) — reabertura formal de competência + versão do espelho | `docs/script_ponto_onda2_reabertura_competencia.sql` | — | ⏳ | ⬜ |
| 15 | Onda 2 (parte 5) — correção por acréscimo (desconsiderar) — banco | `docs/script_ponto_onda2_desconsiderar_marcacao.sql` | — | ⏳ | ⬜ |
| 15-tela | Onda 2 (parte 5) — botão "Desconsiderar" | **Publicar no Lovable** (não é script) | #15 | ⏳ | ⬜ |
| 16 | Onda 4 (parte 1) — faixas de intervalo (art. 71) | `docs/script_ponto_onda4_faixas_intervalo.sql` | — | ⏳ | ⬜ |
| 17 | Onda 4 (parte 2) — supressão de intervalo (indenização 50%) | `docs/script_ponto_onda4_supressao_intervalo.sql` | **#16** | ⏳ | ⬜ |
| 18 | Onda 4 (parte 3) — pré-assinalação formal do intervalo (Súm. 338) | `docs/script_ponto_onda4_pre_assinalacao.sql` | **#16 #17** | ⏳ | ⬜ |
| 19 | Onda 4 (parte 4) — domingo trabalhado em dobro (Lei 605/49, Súm. 146) | `docs/script_ponto_onda4_domingo_em_dobro.sql` | — | ⏳ | ⬜ |
| 20 | Onda 4 (parte 5) — DSR e repouso semanal de 24h (Lei 605/49, CLT art. 67) | `docs/script_ponto_onda4_dsr.sql` | — | ⏳ | ⬜ |
| 21 | Onda 5 (parte 1) — banco de horas só com instrumento vigente (CLT art. 59) | `docs/script_ponto_onda5_banco_instrumento_vigente.sql` | — | ⏳ | ⬜ |
| 22 | Onda 5 (parte 2) — prazo de vencimento em cada crédito (CLT art. 59, §§5º/6º) | `docs/script_ponto_onda5_prazo_vencimento_saldo.sql` | **#21** | ⏳ | ⬜ |
| 23 | Onda 5 (parte 3) — alertas de vencimento e teto de acúmulo do banco | `docs/script_ponto_onda5_alertas_banco.sql` | **#21** | ⏳ | ⬜ |
| 24 | Onda 5 (parte 4) — limite de 10h diárias no regime de compensação (CLT art. 59, §2º) | `docs/script_ponto_onda5_limite_diario_compensacao.sql` | **#21** | ⏳ | ⬜ |
| 25 | Onda 5 (parte 5) — liquidação do saldo de banco na rescisão (CLT art. 59, §3º) | `docs/script_ponto_onda5_liquidar_banco_rescisao.sql` | **#21** | ⏳ | ⬜ |
| 26 | Onda 5 (parte 6) — escala 12x36 por ciclo (CLT art. 59-A) | `docs/script_ponto_onda5_escala_12x36.sql` | — | ⏳ | ⬜ |
| 27 | Onda 6 (parte 1) — geração transacional dos espelhos (tudo-ou-nada) | `docs/script_ponto_onda6_gerar_espelhos.sql` | — | ⏳ | ⬜ |
| 28 | Onda 6 (parte 2) — pendência crítica bloqueia o fechamento | `docs/script_ponto_onda6_fechamento_pendencias.sql` | — | ⏳ | ⬜ |
| 29 | Onda 6 (parte 3) — espelho sem ciência bloqueia o fechamento (Súm. 338) | `docs/script_ponto_onda6_fechamento_ciencia_espelho.sql` | **#28** | ⏳ | ⬜ |
| 30 | Onda 6 (parte 4) — pacote da folha com naturezas corretas (vencimento/desconto/indenizatória) | `docs/script_ponto_onda6_pacote_folha.sql` | — | ⏳ | ⬜ |
| 31 | Onda 6 (parte 5) — fila da folha com estados e reenvio idempotente | `docs/script_ponto_onda6_fila_folha_reenvio.sql` | **#30** | ⏳ | ⬜ |
| 32 | Onda 7 (parte 1) — comprovante como documento (Portaria 671/REP-P) | `docs/script_ponto_onda7_comprovantes.sql` | — | ⏳ | ⬜ |
| 33 | Onda 7 (parte 2) — AEJ (Arquivo Eletrônico de Jornada, Portaria 671) | `docs/script_ponto_onda7_aej.sql` | — | ⏳ | ⬜ |
| 34 | Onda 7 (parte 3) — importação de AFD que confere (CRC, cadeia, lacuna, quarentena) | `docs/script_ponto_onda7_afd_importacao.sql` | — | ⏳ | ⬜ |
| 35 | Onda 7 (parte 4) — gestão do certificado digital (ICP-Brasil) | `docs/script_ponto_onda7_certificado_digital.sql` | — | ⏳ | ⬜ |
| 36 | Onda 7 (parte 5) — dossiê de fiscalização + arquivamento no módulo Documentos | `docs/script_ponto_onda7_dossie_fiscalizacao.sql` | #33 #34 #35 | ⏳ | ⬜ |
| 37 | Onda 8 (parte 1) — enquadramento do art. 62 (dispensa) + teletrabalho por jornada | `docs/script_ponto_onda8_enquadramento_art62.sql` | — | ⏳ | ⬜ |
| 38 | Onda 8 (parte 2) — controle de fato descaracteriza a dispensa (art. 62) | `docs/script_ponto_onda8_descaracterizacao_art62.sql` | **#37** | ⏳ | ⬜ |
| 39 | Onda 8 (parte 3) — obrigatoriedade do controle por estabelecimento (>20) | `docs/script_ponto_onda8_obrigatoriedade_estabelecimento.sql` | — | ⏳ | ⬜ |
| 40 | Onda 8 (parte 4) — sistema alternativo (REP-A) só com instrumento coletivo | `docs/script_ponto_onda8_rep_alternativo_instrumento.sql` | — | ⏳ | ⬜ |
| 41 | Onda 8 (parte 5) — LGPD: trilha de acesso a dado sensível + contenção de enumeração | `docs/script_ponto_onda8_lgpd_trilha_e_enumeracao.sql` | — | ⏳ | ⬜ |
| 42 | Onda 8 (parte 6) — Plano de Ação: alerta→ação 5W2H + eficácia + IA sugere/humano decide | `docs/script_ponto_onda8_plano_de_acao.sql` | — | ⏳ | ⬜ |
| 43 | Onda 8 (correção) — competência fechada bloqueia até para gestão (remove a válvula) | `docs/script_ponto_onda8_competencia_fechada.sql` | **#14** (reabertura) | ⏳ | ⬜ |
| 44 | Onda 9 — instrumento coletivo vigente na competência (vigilância de vigência) | `docs/script_ponto_onda9_cct_vigencia.sql` | — | ⏳ | ⬜ |
| 45 | QA (metadado) — atualiza a disposição dos 6 casos de tela conforme auditoria as-built | `docs/script_qa_disposicao_ponto_telas.sql` | — | ⏳ | ⬜ (opcional) |
| 46 | Onda 10 (parte 1) — escala 12x36 só vale com acordo formal (art. 59-A) | `docs/script_ponto_onda10_escala_12x36_formalizacao.sql` | — | ⏳ | ⬜ |
| 47 | Onda 10 (parte 2) — revezamento: jornada de 6h, salvo coletivo (CF art. 7º, XIV) | `docs/script_ponto_onda10_escala_revezamento.sql` | **#46** | ⏳ | ⬜ |
| 48 | Onda 10 (parte 3) — radar de cobertura de turno (turno descoberto avisado antes) | `docs/script_ponto_onda10_cobertura_turno.sql` | — | ⏳ | ⬜ |
| 49 | Onda 10 (parte 4) — troca de turno com aprovação e recálculo (fecha a onda 10) | `docs/script_ponto_onda10_troca_turno.sql` | — | ⏳ | ⬜ |
| 50 | Onda 11 (parte 1) — atestado acima de 15 dias encaminha ao INSS (Lei 8.213) | `docs/script_ponto_onda11_atestado_encaminha_inss.sql` | — | ⏳ | ⬜ |
| 51 | Onda 11 (parte 2) — atestados sobrepostos detectados, não abonados em dobro | `docs/script_ponto_onda11_atestados_sobrepostos.sql` | — | ⏳ | ⬜ |
| 52 | Onda 11 (parte 3) — ausência do art. 473 sem documento fica pendente (não abona por fé) | `docs/script_ponto_onda11_comprovacao_art473.sql` | — | ⏳ | ⬜ |
| 53 | Vigilâncias do ponto — rotina diária que faz as monitorias rodarem | `docs/script_ponto_vigilancias_diarias.sql` | **#23 #38 #39 #44 #46 #47 #48** | ⏳ | ⬜ |
| 54 | Comprovantes — extração restrita ao dono do CPF (correção de segurança) | `docs/script_ponto_comprovantes_extrair_dono.sql` | **#32** | ⏳ | ⬜ |
| 57 | Jornada prevista desconta o intervalo pré-assinalado | `docs/script_ponto_jornada_desconta_pre_assinalacao.sql` | **#18** | ⏳ | ⬜ |
| 58 | Regrava a jornada gravada nas escalas com intervalo declarado | `docs/script_ponto_escalas_regrava_jornada_declarada.sql` | **#18** | ⏳ | ⬜ |
| 57/58-tela | Tela de escalas e cartão-ponto enxergam a declaração | **Publicar no Lovable** (não é script) | — | ✅ | ⬜ |

> Os pacotes **53 a 56** nasceram depois desta tabela, durante o ensaio na
> homologação, e estão descritos nas seções do fim deste roteiro — os números 53
> e 54 das duas linhas acima são de outra contagem, anterior. Vale a numeração
> das seções.

> Quando eu validar cada onda com você no teste e você aprovar, marque a coluna
> **Teste** como ✅. A coluna **Produção** só vira ✅ depois que você colar o
> pacote no banco real e a conferência der `OK`.

---

## Detalhe de cada pacote

### 1 · PONTO-004 — marcação imutável + remoção do e-mail hardcoded
- **Arquivo:** `docs/script_ponto004_imutabilidade.sql`
- **O que faz:** impede que a marcação de ponto original seja apagada
  diretamente por papel de gestão (a correção passa a ser por acréscimo) e
  remove um e-mail real que estava fixo no código como exceção (backdoor + LGPD).
- **Não altera cálculo de jornada.**
- **Conferência esperada (última linha do resultado):** `true | true | true | 3 | OK`
  — e-mail removido, marcação blindada, exclusão de ajustes preservada, 3
  gatilhos de proteção, situação OK.

### 2 · Onda 0 — travas legais de risco aberto
- **Arquivo:** `docs/script_ponto_onda0_travas_legais.sql`
- **O que faz:** seis travas de cadastro/acesso — colaborador comum passa a ler
  só o próprio ponto (LGPD); marcação no futuro é recusada; tolerância acima do
  teto legal, CCT abaixo do piso de intervalo e "registro por exceção" sem
  acordo passam a ser recusados no cadastro; instala a trava de teste na tabela
  que faltava.
- **Não altera cálculo de jornada.**
- **Conferência esperada:** `2 | 4 | 0 | 0 | 0 | OK` — 2 políticas de leitura, 4
  gatilhos de validação, e **três zeros** de cadastros legados fora da faixa.
- **Atenção:** se os três zeros **não** vierem zero, existem cadastros antigos
  fora da faixa legal (tolerância/intervalo/exceção). Eles continuam
  funcionando, mas produzem apuração irregular — me avise os números que eu
  ajudo a tratar um a um.

### 3 · Onda 1 (parte 1) — NSR e histórico de lotação
- **Arquivo:** `docs/script_ponto_onda1_nsr_e_lotacao.sql`
- **O que faz:** cria o NSR (numeração sequencial e imutável de cada marcação,
  exigida pela Portaria 671) e o histórico de lotação por estabelecimento.
  Estruturas novas ao lado do que já existe; **não altera cálculo.**
- **Conferência esperada:** `t | t | t | t | t | t | OK`. A coluna
  `marcacoes_sem_nsr` dá o tamanho do preenchimento histórico do passo 4.
- **Depois deste, rode o passo 4.**

### 4 · Onda 1 (parte 1) — preenchimento histórico do NSR
- **Arquivo:** `docs/script_ponto210_backfill_nsr.sql`
- **Rodar SOMENTE depois do #3.**
- **O que faz:** dá NSR às marcações **antigas** (as novas já nascem com NSR).
  É separado de propósito: cada atualização gera uma linha de auditoria, então
  o preenchimento é feito **em lotes** de 20 mil, no seu ritmo.
- **Como rodar:** cole e rode. A cada execução ele numera um lote e avisa quanto
  falta (`Faltam: N`). **Repita até `Faltam: 0`.** É seguro parar e retomar.
- **Conferência esperada ao terminar:** `faltam_nsr = 0` e situação `OK` (ou
  `OK, com ressalva` se houver `orfas_sem_tenant` — ver abaixo).
- **Atenção:** a coluna `orfas_sem_tenant` conta marcações que apontam para um
  empregador que não existe mais. Elas ficam de fora de propósito e merecem
  investigação à parte — me avise se vier acima de zero.

### 5 · Onda 1 (parte 2) — vínculo/empresa na chave da apuração
- **Arquivo:** `docs/script_ponto_onda1_vinculo_na_chave.sql`
- **Depende do #3** (usa a mesma base estrutural).
- **O que faz:** inclui a empresa na chave da apuração diária, para que dois
  vínculos do mesmo trabalhador (duas empresas do grupo) tenham cada um a sua
  linha. Para quem tem um vínculo só, o dia continua uma linha — **não altera
  cálculo.** Um gatilho de reconciliação garante que nenhum dia de vínculo
  único se parta.
- **Conferência esperada:** `t | t | t | 5 | OK` — chave por vínculo, gatilho de
  reconciliação, escritores sem o arbiter antigo, 5 escritores migrados, OK.
- **Sem backfill** — o gatilho de reconciliação dispensa.

### 6 · Onda 1 (parte 3) — versionamento de parâmetros + memória de cálculo
- **Arquivo:** `docs/script_ponto_onda1_versionamento_e_memoria.sql`
- **O que faz:** os parâmetros da escala passam a ser versionados por vigência
  (editar a escala hoje deixa de reescrever a apuração de um mês passado) e cria
  a memória de cálculo por competência (fonte + resultado). **A mudança é inerte
  até alguém editar uma escala** — sem edição, a apuração sai idêntica à de hoje.
- **Conferência esperada:** `t | t | 4 | t | OK` — tabela de versões, gatilho de
  arquivamento, 4 leitores com o overlay, tabela de memória, OK.
- **Sem backfill** — a tabela de versões nasce vazia.

---

### 7 · Onda 3 (parte 1) — tolerância cumulativa dos dois tetos legais
- **Arquivo:** `docs/script_ponto_onda3_tolerancia.sql`
- **O que faz:** a apuração passa a aplicar os dois tetos de tolerância do
  art. 58, §1º da CLT (Súmula 366 do TST) de forma cumulativa: o
  atraso/antecipação é absorvido só até **5 minutos por marcação**; a sobra no
  dia mantém o teto de **10 minutos diários**. Estourou qualquer um, computa-se
  a totalidade que excede a jornada — não só o que passou da tolerância. Corrige
  também o padrão de encaixe de batida (era 10 por marcação, o dobro do legal).
- **Muda o cálculo de saldo** (é a onda do dinheiro) — mas de forma provada:
  na bateria do teste, só PONTO-041, PONTO-042 e PONTO-352 passaram a passar, e
  **nenhum outro caso mudou** (regressão zero).
- **Este script é cirúrgico, não cola o corpo inteiro.** O corpo desta função,
  em produção, foi remendado à mão no passado e não bate com o repositório. O
  script lê o corpo vivo em produção e troca **apenas** os trechos de
  tolerância. Se o corpo tiver sido remendado também nessas linhas, ele **não
  altera nada e avisa** — aí me mande o corpo atual que eu reconcilio antes.
- **Conferência esperada:** `t | t | t | OK` — marcador aplicado, padrão de 5
  por marcação no lugar, e o padrão antigo de 10 removido.
- **Atenção:** se a conferência vier `PENDENTE`, o corpo divergiu e **nada foi
  aplicado** — é o comportamento seguro, me avise para reconciliarmos.
- **Sem backfill** — muda só a leitura/apuração, não grava nada em massa.

### 8 · Onda 3 (parte 2) — jornada da escala + hora extra sem truncar
- **Arquivo:** `docs/script_ponto_onda3_jornada_escala_he.sql`
- **O que faz:** na função de cálculo de hora extra e adicional noturno,
  (a) a jornada esperada do dia passa a vir da **escala vigente do vínculo**
  (respeitando o versionamento da onda 1), em vez das 8h fixas — assim a hora
  extra de quem tem jornada contratual menor deixa de ser apagada (CLT art. 58;
  CF art. 7º, XIII); (b) remove o corte que truncava a hora extra em 2h — apura
  **todo** o tempo trabalhado além da jornada (continua devido, art. 59) e
  **sinaliza** o excesso ao RH com um alerta (um por colaborador/dia).
- **Muda o cálculo de HE** (na bateria só PONTO-091 e PONTO-092 passaram a
  passar; PONTO-110/111 do adicional noturno seguem idênticos — regressão zero).
- **`CREATE OR REPLACE` limpo** (esta função tem definição única, sem remendos
  próprios de produção) — seguro e idempotente.
- **Conferência esperada:** `t | t | t | OK` — lê a jornada da escala, não trunca
  mais em 2h, e sinaliza o excesso.
- **Observação:** esta função de cálculo **ainda não é consumida pelo fluxo vivo
  de apuração** (nenhuma tela/gatilho a chama hoje). A correção deixa o cálculo
  certo para quando ele for ligado — por si só não muda os números que já
  aparecem hoje. Ligar o cálculo ao fluxo é passo à parte, de uma onda adiante.
- **Sem backfill.**

### 9 · Onda 3 (parte 3) — adicional noturno prorrogado (Súmula 60, II do TST)
- **Arquivo:** `docs/script_ponto_onda3_adicional_noturno_prorrogado.sql`
- **O que faz:** quando a jornada é cumprida integralmente no período noturno
  (entrada até as 22h, cobrindo toda a janela 22h–05h) e **prorrogada** além das
  05h, o adicional noturno acompanha as horas prorrogadas — em vez de cessar em
  05:00 fixo (Súmula 60, II do TST). A parte noturna mantém a hora ficta; as
  horas prorrogadas entram pelo tempo real (critério conservador, porque aplicar
  a ficta à prorrogação é controvertido — registrado no comentário da função).
- **Este pacote INCLUI o #8.** É a mesma função da parte 2: o corpo aqui já traz
  a jornada da escala e a hora extra sem truncar. Rodar o #8 antes é inofensivo
  (o #9 o substitui com o corpo final); rodar só o #9 também fica completo.
- **`CREATE OR REPLACE` limpo** (definição única, sem remendos) — idempotente.
- **Conferência esperada:** `t | t | t | t | OK` — jornada da escala, sem corte
  em 2h, alerta do art. 59 e prorrogação do adicional, todos presentes.
- **Na bateria** só PONTO-112 passou a passar; PONTO-110/111 (janela e ficta)
  seguem idênticos — regressão zero.
- **Mesma observação de escopo:** a função ainda não é consumida pelo fluxo vivo
  de apuração. **Sem backfill.**

### 10 · Onda 3 (parte 4) — turno da virada pertence ao dia de início
- **Arquivo:** `docs/script_ponto_onda3_turno_da_virada.sql`
- **O que faz:** a jornada que cruza a meia-noite (ex.: entrada 22:00, saída
  06:00 do dia seguinte, lançadas no dia de início) passa a pertencer inteira ao
  dia em que começou — 8h no dia de início, **sem falta fictícia** no dia
  seguinte. A reordenação de rótulos e a consolidação diária passam a ler as
  batidas em ordem **cíclica** (o turno começa logo após o maior vão do dia),
  reconhecendo a virada. **Nenhum horário é alterado** — muda só a ordem de
  leitura das batidas.
- **Cria uma função nova** (`ponto_corte_virada`) usada pelas duas.
- **`CREATE OR REPLACE` limpo** (sem remendos próprios de produção) — idempotente.
- **Conferência esperada:** `t | t | t | OK` — corte criado, reordenação e
  consolidação lendo em ordem cíclica.
- **Na bateria** só PONTO-022 passou a passar; dias comuns não mudaram
  (regressão zero em 120 casos).
- **Sem backfill.**

### 11 · Onda 2 (parte 1) — cadeia de hash encadeado + verificação
- **Arquivo:** `docs/script_ponto_onda2_cadeia_hash.sql`
- **Depende do NSR (#3 e #4).** O encadeamento usa a numeração sequencial das
  marcações — rode os pacotes do NSR antes deste.
- **O que faz:** o hash de cada marcação nova passa a **incorporar o hash da
  anterior** (por NSR/estabelecimento) — remover uma linha passa a quebrar a
  cadeia. Uma rotina recomputa cada hash (detecta alteração de conteúdo) e
  confere o encadeamento e a continuidade da NSR (detecta remoção), com alerta
  ao RH. É o que transforma "não editamos" em prova (registro tipo 7 do AFD).
- **Retrocompatível.** O append do hash anterior é vazio para as marcações
  antigas, e append de vazio não muda o hash — as marcações já gravadas
  continuam com o **mesmo hash** e verificam limpas. **Sem backfill.**
- **`ADD COLUMN IF NOT EXISTS` + `CREATE OR REPLACE`** — idempotente. A geração
  do hash é defensiva: nunca deixa de gravar a marcação.
- **Conferência esperada:** `t | t | t | 0 | OK` — coluna criada, hash encadeado,
  rotina de verificação, e **zero quebras** na base atual (sem falso positivo).
- **Atenção:** se `quebras_hoje` vier acima de zero, há marcação adulterada ou
  removida em produção — me avise para investigar.
- **Na bateria** só PONTO-191 passou a passar; regressão zero. Além da régua,
  provei o mecanismo de verdade: base legada limpa, novas marcações encadeiam, e
  a remoção de uma marcação do meio é detectada.

### 12 · Onda 2 (parte 2) — relógio confiável + origem da batida
- **Arquivo:** `docs/script_ponto_onda2_relogio_e_origem.sql`
- **O que faz (requisitos do REP-P):** (378) a marcação passa a registrar se
  nasceu **on-line ou off-line** (`origem_offline`) e o momento da sincronização
  (`sincronizado_em`), preservando a hora da batida como a oficial; (379) uma
  rotina monitora o **relógio do servidor contra a Hora Legal Brasileira**
  (Observatório Nacional), com trilha das checagens (`ponto_relogio_checagens`)
  e alerta quando o desvio passa da tolerância. A hora oficial é fornecida por
  quem chama (uma Edge Function que consulta a fonte).
- **Puramente aditivo** — colunas novas com padrão neutro e mecanismos ao lado
  do que já existe; nada do fluxo atual muda.
- **`ADD COLUMN IF NOT EXISTS` + `CREATE TABLE IF NOT EXISTS` + `CREATE OR
  REPLACE`** — idempotente. **Sem backfill.**
- **Conferência esperada:** `t | t | t | OK` — colunas de origem, trilha do
  relógio e rotina de monitoração presentes.
- **Na bateria** só PONTO-378 e PONTO-379 passaram a passar; regressão zero.
  Provado de verdade: desvio dentro da tolerância não alerta, desvio acima
  alerta (uma vez por dia), e a trilha registra cada checagem.

### 13 · Onda 2 (parte 3) — detecção de marcações uniformes ("britânico")
- **Arquivo:** `docs/script_ponto_onda2_marcacoes_uniformes.sql`
- **O que faz:** por colaborador na competência, mede o desvio-padrão dos
  horários de entrada e saída ao longo dos dias. Desvio quase nulo por muitos
  dias = espelho **uniforme** ("britânico"), que a Súmula 338, III, do TST
  considera **inválido como prova**. Uma rotina companheira alerta o RH,
  idempotente por competência.
- **Somente leitura** sobre `ponto_diario`; aditivo e idempotente
  (`CREATE OR REPLACE`). **Sem backfill.**
- **Conferência esperada:** `t | t | OK` — rotina de verificação e companheira
  de alerta presentes.
- **Na bateria** só PONTO-377 passou a passar; regressão zero. Provado de
  verdade: um colaborador com horários idênticos por 14 dias é sinalizado como
  uniforme (e alertado); um com variação de minutos, não.

### 14 · Onda 2 (parte 4) — reabertura formal de competência + versão do espelho
- **Arquivo:** `docs/script_ponto_onda2_reabertura_competencia.sql`
- **O que faz:** cria a saída **formal** para o erro legítimo descoberto após o
  fechamento. `ponto_reabrir_competencia` valida que a competência está fechada,
  **exige motivo**, confere a **alçada** (papéis de gestão), **arquiva** a versão
  corrente dos espelhos (a que o colaborador recebeu) num histórico recuperável,
  marca o fechamento como `reaberto` e registra a **trilha**. O re-fechamento
  seguinte gera a próxima versão, sem regravar a anterior.
- **A tabela nova (`ponto_espelhos_historico`) recebe a trava do cercado** do QA,
  como toda tabela de ponto — sem isso a rotina PONTO-270 acusaria.
- **Aditivo e idempotente** (`ADD COLUMN IF NOT EXISTS`, `CREATE TABLE IF NOT
  EXISTS`, `CREATE OR REPLACE`). **Sem backfill.**
- **Conferência esperada:** `t | t | t | t | OK` — colunas de reabertura,
  histórico do espelho, trava do cercado na tabela nova, e a função de
  reabertura.
- **Na bateria** PONTO-358 passou a passar; regressão zero. Provado de verdade:
  reabertura sem motivo é recusada; com motivo, arquiva a versão e marca
  `reaberto`; e reabrir uma competência já reaberta é recusado.
- **Nota honesta:** o PONTO-194 (geração transacional dos espelhos) também
  aparece verde na bateria depois desta parte, mas por **coincidência** — a
  régua dele só procura uma função que toque `ponto_espelhos` com `INSERT`, e a
  reabertura casa esse padrão. A geração transacional dos espelhos de verdade
  (hoje o frontend grava linha a linha) segue como item próprio, a fazer.

### 15 · Onda 2 (parte 5) — correção por acréscimo: desconsiderar, nunca apagar
- **Arquivo (banco):** `docs/script_ponto_onda2_desconsiderar_marcacao.sql`
- **O que faz:** a batida original **nunca é apagada**. Passa a ser
  **desconsiderada**: fica no acervo e na cadeia de hash, marcada com motivo e
  responsável, e sai do cálculo do dia. Fecha o buraco dos RPCs
  (`excluir_marcacao_ponto`, `processar_ajuste_ponto` tipo correção) que ainda
  apagavam pelo flag de sessão. Portaria 671 veda apagar; CLT art. 74; Súmula
  338 do TST.
- **`ADD COLUMN IF NOT EXISTS` + `CREATE OR REPLACE`** — idempotente. **Sem
  backfill.**
- **Conferência esperada:** `t | t | t | t | t | OK` — coluna de desconsideração,
  RPC próprio, o antigo "excluir" delegando (não apaga), o cálculo ignorando
  desconsideradas, e o ajuste sem apagar.
- **Na bateria:** PONTO-004 segue passando; **regressão zero**. Provado de
  verdade: desconsiderar tira a batida do cálculo, mas ela **continua no acervo**
  e a **cadeia de hash segue intacta** (a prova fica).

#### 15-tela · o botão "Desconsiderar" (Publicar no Lovable)
- **Não é um script.** A tela (o botão "Excluir" do espelho vira "Desconsiderar",
  com o motivo obrigatório) está no código do frontend e entra em produção pelo
  **Publicar no Lovable**, depois que o pacote #15 (banco) estiver em produção.
- **Enquanto a tela não é publicada:** o banco já protege — o botão "Excluir"
  antigo já **desconsidera** (não apaga), só com o rótulo antigo. Publicar o
  Lovable troca o rótulo e passa a pedir o motivo.

### 16 · Onda 4 (parte 1) — faixas de intervalo (art. 71)
- **Arquivo:** `docs/script_ponto_onda4_faixas_intervalo.sql`
- **O que faz:** cria a função canônica do mínimo de intervalo intrajornada por
  **faixa de jornada** (CLT art. 71): até 4h nenhum; 4-6h 15 min; acima de 6h
  60 min. É a base do cálculo de supressão (parte 2) — sem as faixas, aplicar
  "1 hora para todos" criaria supressão fictícia nas jornadas curtas.
- **Função pura (`IMMUTABLE`), aditiva e idempotente** (`CREATE OR REPLACE`).
  **Sem backfill.**
- **Conferência esperada:** `t | 0 | 15 | 15 | 60 | OK`.
- **Na bateria** só PONTO-062 passou a passar; regressão zero.

### 17 · Onda 4 (parte 2) — supressão de intervalo (indenização de 50%)
- **Arquivo:** `docs/script_ponto_onda4_supressao_intervalo.sql`
- **Depende da parte 1 (#16).** Usa as faixas de intervalo.
- **O que faz (CLT art. 71, §4º pós-2017):** jornada acima de 6h com pausa menor
  que a devida gera **supressão** — indenização de **50% sobre apenas os minutos
  suprimidos**, natureza **indenizatória** (sem reflexos em DSR/férias/13º/FGTS;
  a regra antiga da hora cheia salarial foi revogada em 2017). A função calcula;
  um gatilho na consolidação grava os minutos suprimidos em
  `ponto_diario.he_intervalo_suprimido_minutos` e **alerta o RH** (parcial ou
  total), idempotente por colaborador/dia. A supressão total (jornada corrida
  sem nenhuma pausa) deixa de passar invisível.
- **Aditivo e idempotente** (`CREATE OR REPLACE`, `DROP TRIGGER IF EXISTS` +
  `CREATE TRIGGER`). **Sem backfill.**
- **Conferência esperada:** `t | t | 60 | 0 | OK`.
- **Na bateria** só PONTO-060 e PONTO-061 passaram a passar; regressão zero.
  Provado: 8h30 sem pausa → 60 min suprimidos e alerta; 8h com 60min de pausa →
  nada; jornada de 4h sem pausa → nada (≤4h não exige intervalo).

### 18 · Onda 4 (parte 3) — pré-assinalação formal do intervalo (Súmula 338)
- **Arquivo:** `docs/script_ponto_onda4_pre_assinalacao.sql`
- **Depende das partes 1 e 2 (#16/#17).**
- **O que faz (Súmula 338, III do TST; Portaria MTP 671/2021):** a jornada de
  **duas batidas** (entra e sai, sem marcar o almoço) só é válida quando o
  intervalo é **expressamente pré-assinalado**. Passa a existir a **declaração
  formal** — tabela `ponto_pre_assinalacao`, por escala (ampla) ou por
  colaborador (específica, que prevalece), com **vigência** e **lastro**
  (CCT/acordo). O espelho ganha duas colunas em `ponto_diario`
  (`intervalo_origem` = `marcado`/`pre_assinalado` e
  `intervalo_pre_assinalado_minutos`) que **mostram** de onde veio o intervalo
  do dia. E a supressão (parte 2) deixa de acusar **falsa "supressão total"**
  num dia legitimamente pré-assinalado.
- **Desligado por padrão.** Sem declaração cadastrada, nada muda: a origem fica
  `marcado` (dia com almoço batido) ou `NULL`, e a supressão fica idêntica à
  parte 2. **Não altera** `ponto_marcacoes`, `horas_trabalhadas` nem o motor de
  saldo — a dedução do intervalo na apuração segue exatamente como já era.
- **Batida real sempre vence o declarado.**
- **Aditivo e idempotente** (`ADD COLUMN IF NOT EXISTS`, `CREATE TABLE IF NOT
  EXISTS`, `CREATE OR REPLACE`, `DROP TRIGGER IF EXISTS` + `CREATE TRIGGER`).
  **Sem backfill.** Um único gatilho de `ponto_diario` é (re)criado; a tabela
  nova nasce vazia (sem contenção) — sem risco de deadlock entre tabelas.
- **Conferência esperada:** `t | t | t | t | t | t | OK`.
- **Na bateria** só PONTO-064 passou a passar; regressão zero (270 da cerca
  segue verde, 060/061/062 seguem verdes). Provado em transação: dia de 2
  batidas sem declaração → nada muda (`60` min de supressão, igual à parte 2);
  almoço batido → `marcado`, sem supressão; 2 batidas + declaração de 60 min →
  `pre_assinalado`, **sem supressão**, `horas_trabalhadas` intactas; declaração
  existente mas com almoço batido → `marcado` (real vence); declaração de 30 min
  (abaixo do mínimo) → supressão **parcial** de 30 min mantida.
- **Tela (Publicar no Lovable) — quando o RH for usar:** a exibição de "intervalo
  pré-assinalado" no espelho e o cadastro da declaração são de tela; entram por
  Publicar no Lovable quando forem construídos. O banco já guarda tudo.

### 19 · Onda 4 (parte 4) — domingo trabalhado em dobro (Lei 605/49, Súmula 146)
- **Arquivo:** `docs/script_ponto_onda4_domingo_em_dobro.sql`
- **O que faz:** o trabalho em **domingo** (descanso semanal) sem folga
  compensatória é pago **em dobro por inteiro** — a jornada normal inclusive —,
  não apenas o que excede a jornada (Lei 605/1949, art. 9º; Súmula 146 do TST).
  Até aqui o cálculo tratava o domingo como mera hora extra 100%, dobrando só o
  excedente. Agora, na `calcular_he_adicional_noturno_dia`, quando o domingo
  **não é dia de trabalho previsto na escala** (é o repouso da semana), a
  jornada trabalhada inteira vira 100%.
- **Só muda o domingo de repouso trabalhado.** Domingo **previsto na escala**
  (6x1 e afins) já carrega o repouso noutro dia → cai no cálculo normal, sem
  dobra. Dia útil e sábado ficam idênticos. **Não toca no motor de saldo** (ele
  lê `horas_extras`/`horas_faltantes`, não `horas_extras_100_minutos`); o alerta
  do art. 59 segue igual.
- **Substitui a função inteira** (mantém as partes 2 e 3 da onda 3: jornada pela
  escala, HE sem truncar, adicional noturno prorrogado — a conferência confirma).
- **Aditivo e idempotente** (`CREATE OR REPLACE`). **Sem backfill.**
- **Conferência esperada:** `t | t | t | t | t | OK`.
- **Na bateria** só PONTO-130 passou a passar; regressão zero. Provado em
  transação: domingo-repouso de 8h → 480 min a 100% (dobra da jornada inteira);
  domingo-repouso de 11h corridas → 660 min a 100%; **domingo previsto na escala
  → sem dobra** (0); dia útil de 11h → 180 min a 50%; sábado de 11h → 180 min a
  50%. *Obs.: PONTO-132 (reflexo do DSR) segue pendente — é a parte 5; não foi
  tocado por esta parte.*
- **Limitação conhecida:** escala legada sem `dias_config` reporta o domingo como
  dia útil e não dobra (critério conservador, não cobra a mais). Compensação
  ad-hoc de domingo, se necessária, é evolução à parte (espelhando o mecanismo
  de `feriado_folga_compensatoria`).

### 20 · Onda 4 (parte 5) — DSR e repouso semanal de 24h (Lei 605/49, CLT art. 67)
- **Arquivo:** `docs/script_ponto_onda4_dsr.sql`
- **O que faz:** fecha a onda 4 com o repouso semanal, até aqui ausente do
  cálculo. Três funções novas:
  - `ponto_dsr_competencia` (**132**) — apuração semanal que alimenta a folha
    com o **reflexo das horas extras sobre o repouso** (Súmula 172 do TST: a
    média das HE da semana entra no valor do DSR) e a **perda do DSR por falta
    injustificada** na semana (Lei 605/49, art. 6º);
  - `ponto_repouso_semanal_verificar` (**133**) — detecta **sete dias seguidos
    de trabalho sem 24 horas consecutivas de repouso** (CLT art. 67);
  - `ponto_repouso_semanal_monitorar` (**133**) — varre a competência e alerta o
    gestor sobre a violação, idempotente por colaborador/sequência.
- **Baixo risco:** duas funções somente-leitura e um monitor que só insere
  alertas. Nada é chamado automaticamente, **sem gatilho em tabela quente, sem
  tocar no motor de saldo e sem tabela nova** (sem cerca a instalar). A folha e o
  espelho consomem estas funções quando forem ligados.
- **Aditivo e idempotente** (`CREATE OR REPLACE`). **Sem backfill.**
- **Conferência esperada:** `t | t | t | OK`.
- **Na bateria** só PONTO-132 e PONTO-133 passaram a passar; regressão zero.
  Provado em transação: semana com 120 min de HE em 5 dias úteis → reflexo de 24
  min no DSR; semana com falta injustificada → `dsr_perdido = true`; sequência de
  7 dias trabalhados → violação do art. 67 sinalizada; o monitor cria o alerta na
  1ª execução e devolve 0 na 2ª (idempotente).
- **Tela (Publicar no Lovable) — quando o RH for usar:** o evento de DSR na folha
  e a coluna do espelho (`total_dsr`) passam a ter fonte; ligá-los na exportação
  e no espelho é de tela, por Publicar no Lovable. O banco já apura.

### 21 · Onda 5 (parte 1) — banco de horas só com instrumento vigente (CLT art. 59)
- **Arquivo:** `docs/script_ponto_onda5_banco_instrumento_vigente.sql`
- **O que faz:** o banco de horas creditava para **todo mundo**, sem regime nem
  acordo. Sem instrumento válido e vigente (CLT art. 59, §§2º e 5º), a hora extra
  é devida em **dinheiro** na competência — mandá-la para o banco é postergar
  pagamento devido. Agora a apuração só **credita/debita** o banco quando existe
  regime de compensação **vigente** para o vínculo (`ponto_banco_horas_config`
  ativo, dentro da vigência, e com o acordo/CCT anexado quando o regime o exige).
  Sem regime, o excedente **segue apurado no dia** e vai para a folha — não some.
- **Duas peças:** a função nova `ponto_banco_regime_vigente` (resolve o regime do
  vínculo, específico da escala > empresa > tenant) e o portão dentro de
  `apurar_banco_horas_colaborador`. A rotina de empresa `apurar_banco_horas` só
  repassa para essa função — o comportamento propaga sozinho.
- **Só muda quem NÃO tem regime.** Vínculo com regime vigente segue idêntico.
  **Não apaga nada** — a hora extra continua apurada (`horas_extras_*` do dia).
- **Aditivo e idempotente** (`CREATE OR REPLACE`). **Sem backfill.**
- **Conferência esperada:** `t | t | OK`.
- **Na bateria** só PONTO-170 passou a passar; regressão zero. Provado em
  transação: sem config → sem crédito; config ativa e vigente → regime presente;
  config inativa, com início futuro, ou que exige acordo sem anexo → regime nulo
  (não credita); com o acordo anexado → regime presente.

### 22 · Onda 5 (parte 2) — prazo de vencimento em cada crédito (CLT art. 59, §§5º/6º)
- **Arquivo:** `docs/script_ponto_onda5_prazo_vencimento_saldo.sql`
- **Depende da parte 1 (#21).** Usa o `ponto_banco_regime_vigente`.
- **O que faz:** a conversão de saldo vencido em hora extra **já existe e
  funciona** (`converter_banco_horas_vencido`), mas **nunca dispara** porque a
  apuração jamais gravava `prazo_compensacao` — nenhum saldo tinha vencimento.
  Agora `apurar_banco_horas_colaborador` grava `prazo_compensacao = fim da
  competência + prazo_compensacao_dias do regime` (6 meses no acordo individual,
  até 12 no coletivo). Com o prazo na linha, o saldo que passa do limite vira
  hora extra a pagar, em vez de ficar pendurado para sempre.
- **Só acrescenta o prazo.** Sem regime, não há crédito nem prazo (segue a parte
  1); e um prazo já existente na linha é preservado (não apaga vencimento de
  saldo acumulado sob regime anterior). Não altera a conversão nem o motor de
  saldo.
- **Aditivo e idempotente** (`CREATE OR REPLACE`). **Sem backfill.**
- **Conferência esperada:** `t | t | OK`.
- **Na bateria** PONTO-171 e PONTO-354 passaram a passar; regressão zero. Provado
  em transação: regime de 180 dias na competência 03/2026 → prazo gravado
  27/09/2026 (31/03 + 180); sem regime → prazo nulo e crédito zero; saldo com
  prazo vencido ontem → convertido em HE com a movimentação de conversão.

### 23 · Onda 5 (parte 3) — alertas de vencimento e teto de acúmulo do banco
- **Arquivo:** `docs/script_ponto_onda5_alertas_banco.sql`
- **Depende da parte 1 (#21).** Usa o `ponto_banco_regime_vigente`.
- **O que faz:** cria o monitor `ponto_banco_alertas_monitorar(dias_aviso)`, que
  gera dois avisos no `ponto_alertas`:
  - **(355) vencimento próximo** — X dias antes do `prazo_compensacao` (parte 2),
    com a ação sugerida (programar compensação ou pagar). Sem isso, o RH só
    descobria o saldo vencido quando já era passivo (CLT art. 59, §5º);
  - **(356) teto de acúmulo** — o `limite_acumulo_horas` da configuração, antes
    decorativo, passa a ser comparado com o saldo e a sinalizar o excedente.
- **Baixo risco:** só insere alertas, idempotente por colaborador/prazo e por
  colaborador/competência. Nada roda sozinho — sem gatilho em tabela quente, sem
  tocar no motor de saldo. Pode ser agendado (pg_cron) para rodar diariamente.
- **Aditivo e idempotente** (`CREATE OR REPLACE`). **Sem backfill.**
- **Conferência esperada:** `t | t | t | OK`.
- **Na bateria** PONTO-355 e PONTO-356 passaram a passar; regressão zero. Provado
  em transação: saldo vencendo em 10 dias → alerta de vencimento; saldo acima do
  teto (90/100 min contra teto de 60) → alerta de teto; a 2ª execução não duplica
  (devolve 0).

### 24 · Onda 5 (parte 4) — limite de 10h diárias no regime de compensação (CLT art. 59, §2º)
- **Arquivo:** `docs/script_ponto_onda5_limite_diario_compensacao.sql`
- **Depende da parte 1 (#21).** Usa o `ponto_banco_regime_vigente`.
- **O que faz:** em regime de compensação (banco de horas), a jornada do dia não
  pode passar de **10 horas** (CLT art. 59, §2º) — limite **do regime**, que
  independe do teto de 2h extras: um dia de 11h com banco é irregular mesmo que o
  saldo compense depois. Cria o monitor `ponto_banco_limite_diario_monitorar`,
  que sinaliza os dias acima de **600 minutos** para quem está em regime de
  compensação vigente.
- **Baixo risco:** só insere alertas, idempotente por colaborador/dia. Nada roda
  sozinho — sem gatilho em tabela quente, sem tocar no motor de saldo. Pode ser
  agendado (pg_cron) junto do monitor da parte 3.
- **Aditivo e idempotente** (`CREATE OR REPLACE`). **Sem backfill.**
- **Conferência esperada:** `t | t | OK`.
- **Na bateria** só PONTO-172 passou a passar; regressão zero. Provado em
  transação: sem regime, dia de 11h → nenhum alerta (é hora extra normal); com
  regime, dia de 11h (660 min) → alerta; dias de 10h (600) e de 9h → nenhum; a 2ª
  execução não duplica.

### 25 · Onda 5 (parte 5) — liquidação do saldo de banco na rescisão (CLT art. 59, §3º)
- **Arquivo:** `docs/script_ponto_onda5_liquidar_banco_rescisao.sql`
- **O que faz:** o desligamento não conversava com o banco de horas — o
  colaborador desligado com saldo positivo perdia o registro. A CLT art. 59, §3º
  manda pagar as horas não compensadas na rescisão, sobre a **remuneração da data
  da rescisão**. Passa a existir `ponto_banco_liquidar_rescisao` (apura o saldo
  final e registra a liquidação — movimentação `liquidacao_rescisao` com os
  minutos a pagar) e um **gatilho no desligamento** (`admissoes`) que a dispara.
- **Blindado:** qualquer falha na liquidação **não quebra o desligamento**
  (`EXCEPTION → NOTICE`). Idempotente (não liquida duas vezes); saldo
  zero/negativo não gera crédito. Não altera o motor de saldo nem a apuração —
  só lê o banco e registra a liquidação; nada é apagado.
- **`admissoes` já tem vários gatilhos de desligamento** — este é mais um, no
  mesmo padrão. `SET lock_timeout` curto na criação do gatilho.
- **Aditivo e idempotente** (`CREATE OR REPLACE`; `DROP TRIGGER IF EXISTS` +
  `CREATE TRIGGER`). **Sem backfill.**
- **Conferência esperada:** `t | t | OK`.
- **Na bateria** só PONTO-173 passou a passar; regressão zero. Provado em
  transação: saldo +240 → liquida 240; 2ª chamada → 0 (idempotente); saldo −60 →
  0 (sem crédito); e o desligamento (status → `desligado`) disparou a liquidação
  ponta a ponta.
- **Tela (Publicar no Lovable):** a folha lê a movimentação `liquidacao_rescisao`
  e calcula o valor sobre a remuneração da rescisão — ligar isso na
  `folha_rescisoes` é de tela, por Publicar no Lovable. O banco já registra.

### 26 · Onda 5 (parte 6) — escala 12x36 por ciclo (CLT art. 59-A)
- **Arquivo:** `docs/script_ponto_onda5_escala_12x36.sql`
- **O que faz:** os campos de ciclo existiam na escala (`tipo '12x36'`,
  `ciclo_horas_trabalho/descanso`, `ciclo_inicio_data`) e **nenhuma apuração os
  lia** — o plantonista 12x36 teria 4h de "extra" em todo plantão e "falta" em
  toda folga, e o feriado trabalhado geraria dobra indevida (a 12x36 já compensa
  por lei — CLT art. 59-A e §2º). Passa a existir a função
  `ponto_apurar_ciclo_plantao_do_dia` (diz se o dia é plantão ou folga e a
  jornada do plantão), e três apurações passam a lê-la: `ponto_jornada_do_dia`
  (jornada do ciclo no plantão, 0 na folga), o motor de saldo
  (`ponto_saldo_dias_competencia_bruto` — plantão sem HE, folga **sem falta**) e
  `ponto_feriados_trabalhados` (**pula a dobra** de feriado na 12x36).
- **Injeções guardadas (mesmo padrão da onda 3):** as três apurações são
  patcheadas pelo corpo vivo, de forma **idempotente e guardada por âncora** —
  se o corpo em produção divergir, **nada é alterado** e a conferência acusa o
  que faltou (aí me envie o `pg_get_functiondef` da função para reconciliar).
- **Só muda quem é 12x36.** Para todo o resto, a função devolve `eh_ciclo=false`
  e nada muda. Sem âncora (`ciclo_inicio_data`) a apuração diária fica como está.
- **Aditivo e idempotente.** **Sem backfill.**
- **Conferência esperada:** `t | t | t | t | OK`.
- **Na bateria** PONTO-150 e PONTO-151 passaram a passar; regressão zero. Provado
  em transação (12x36 com âncora numa segunda): a função alterna plantão (720
  min) / folga (0); no saldo, o plantão de 12h dá **saldo 0** (sem HE) e a folga
  dá **saldo 0** (sem falta).

### 27 · Onda 6 (parte 1) — geração transacional dos espelhos (tudo-ou-nada)
- **Arquivo:** `docs/script_ponto_onda6_gerar_espelhos.sql`
- **O que faz:** os espelhos nasciam **linha a linha** por um caminho de tela —
  uma falha no meio deixava metade dos colaboradores com documento e metade sem
  (pior que ausente, porque parece completo). Passa a existir
  `ponto_gerar_espelhos_competencia`, uma função **única e transacional**
  (tudo-ou-nada): para cada colaborador com ponto na competência, compõe os
  totais (a partir da apuração canônica `ponto_espelho_resumo`) e faz UPSERT em
  `ponto_espelhos`. **Regenerar preserva a ciência já dada** (status, confirmação,
  assinatura, ressalva) — só atualiza os números; invalidar ciência é o fluxo de
  reabertura (onda 2).
- **Nota:** a rotina PONTO-194 já vinha passando **por acaso** (casava com
  `ponto_reabrir_competencia`, que só arquiva espelhos ao reabrir). Agora há a
  função **de verdade** — a bateria continua verde, mas legitimamente.
- **Baixo risco:** não altera o motor de saldo; só compõe e grava o espelho. Não
  roda por gatilho — o fechamento (parte 2) a chama. Idempotente.
- **Conferência esperada:** `t | t | OK`.
- **Na bateria** sem mudança de contagem (194 já estava verde); regressão zero.
  Provado em transação: dois colaboradores → dois espelhos gerados numa chamada;
  confirmar um e regerar → números atualizados, **status `confirmado` preservado**.

### 28 · Onda 6 (parte 2) — pendência crítica bloqueia o fechamento
- **Arquivo:** `docs/script_ponto_onda6_fechamento_pendencias.sql`
- **O que faz:** o fechamento não verificava pendências — com ajuste pendente de
  aprovação ou dia incompleto sem tratamento, a competência fechava por cima e
  mandava o dado errado para a folha (e depois de fechada não se mexe). Passam a
  existir `ponto_fechamento_pendencias_criticas` (lista as pendências
  bloqueantes: ajustes pendentes e dias incompletos) e
  `ponto_fechar_competencia_verificar` (o **portão**: aborta com a lista se
  houver pendência; devolve 0 quando pode fechar). A tela chama o portão antes de
  concluir o fechamento.
- **Baixo risco:** só leitura + um guardião que aborta quando não pode fechar.
  Não altera o motor de saldo, o espelho nem a transição de banco. Não roda por
  gatilho.
- **Aditivo e idempotente** (`CREATE OR REPLACE`). **Sem backfill.**
- **Conferência esperada:** `t | t | t | OK`.
- **Na bateria** só PONTO-388 passou a passar; regressão zero. Provado em
  transação: competência limpa → portão devolve 0 (pode fechar); com um ajuste
  pendente e um dia incompleto → a lista traz os dois e o portão **aborta** com a
  contagem ("2 pendências críticas — 1 ajuste pendente e 1 dia incompleto").
- **Tela (Publicar no Lovable):** ligar o botão de fechar para chamar o portão e
  exibir a lista de pendências é de tela, por Publicar no Lovable. O banco já
  guarda e bloqueia.

### 29 · Onda 6 (parte 3) — espelho sem ciência bloqueia o fechamento (Súmula 338)
- **Arquivo:** `docs/script_ponto_onda6_fechamento_ciencia_espelho.sql`
- **Depende da parte 2 (#28).** Estende as duas funções (`CREATE OR REPLACE`).
- **O que faz:** a tabela `ponto_espelhos` tem `status`, `data_confirmacao` e
  `assinatura_hash`, mas o fechamento não os consultava — fechava com espelho
  ainda pendente de confirmação. Espelho sem ciência enfraquece a prova (Súmula
  338 do TST). A lista de pendências e o portão passam a considerar também o
  **espelho sem ciência** (status não confirmado/assinado, sem confirmação e sem
  assinatura). Espelho com **ressalva formal** registrada **não bloqueia** (a
  recusa está formalizada).
- **Baixo risco:** só leitura + o guardião que aborta. Não altera o motor de
  saldo, o espelho nem a transição de banco.
- **Aditivo e idempotente** (`CREATE OR REPLACE`). **Sem backfill.**
- **Conferência esperada:** `t | t | OK`.
- **Na bateria** só PONTO-387 passou a passar; regressão zero. Provado em
  transação: espelho `gerado` sem confirmação → bloqueia; espelho `confirmado` →
  não; espelho `gerado` **com ressalva** → não (recusa formalizada); dada a
  ciência a todos → o portão libera (0).

### 30 · Onda 6 (parte 4) — pacote da folha com naturezas corretas
- **Arquivo:** `docs/script_ponto_onda6_pacote_folha.sql`
- **O que faz:** a exportação para a folha era um jsonb montado pela tela, sem
  regra verificável. É onde o ponto vira dinheiro. Passa a existir
  `ponto_compor_pacote_folha`, que monta o pacote a partir da **apuração fechada**
  (`ponto_espelhos`) com **memória** e **naturezas distintas**:
  - **vencimento** — hora extra 50%/100%, adicional noturno, reflexo do DSR;
  - **desconto** — faltas, atrasos, perda de DSR;
  - **indenizatória** — supressão de intervalo (CLT art. 71, §4º), que **não é
    hora extra** e não pode entrar como tal.
  Grava em `ponto_exportacoes_folha` (marcador `sistema_destino='folha_auto'`),
  idempotente por competência.
- **Nota:** os casos PONTO-361 **e** PONTO-398 passaram a passar juntos — ambas
  as rotinas checam a mesma condição frouxa (existir função que referencie
  `ponto_exportacoes_folha`), e a composição a satisfaz. A **fila com estados e
  reenvio idempotente** (o conteúdo real do 398) é a **parte 5**, ainda a fazer —
  ela deixa o 398 legítimo.
- **Baixo risco:** só compõe (não envia). Não altera o motor de saldo nem o
  espelho. **Aditivo e idempotente.** **Sem backfill.**
- **Conferência esperada:** `t | t | t | OK`.
- **Na bateria** PONTO-361 e PONTO-398 passaram a passar; regressão zero. Provado
  em transação: HE 50% e adicional noturno → **vencimento**; supressão de
  intervalo → **indenizatória** (não HE); faltas e atrasos → **desconto**; refazer
  não duplica (um pacote por competência).
- **Tela (Publicar no Lovable):** gerar o arquivo (CSV/TXT/XML) a partir do
  pacote e disparar o envio é de tela/edge, por Publicar no Lovable. O banco já
  compõe o conteúdo com as naturezas certas.

### 31 · Onda 6 (parte 5) — fila da folha com estados e reenvio idempotente
- **Arquivo:** `docs/script_ponto_onda6_fila_folha_reenvio.sql`
- **Depende da parte 4 (#30).**
- **O que faz:** a exportação era um registro passivo — sem fila, sem reenvio,
  sem confirmação. A coluna `status` já tinha os quatro estados (gerado/enviado/
  processado/erro ≈ pendente/enviado/confirmado/falha), mas nada os movimentava.
  Passam a existir `ponto_folha_marcar_status` (transição de estado **validada** —
  só as transições legítimas: gerado→enviado→processado; →erro na falha;
  erro→gerado no reenvio — com trilha no próprio pacote) e `ponto_folha_reenviar`
  (**reenvio idempotente**: reencaminha só os pacotes ainda em erro, incrementando
  as tentativas, **sem duplicar nem perder** — atualiza o registro existente).
- **É o conteúdo real do PONTO-398**, que já vinha verde desde a parte 4 (as duas
  rotinas checam a mesma condição frouxa). Agora está legítimo.
- **Baixo risco:** não cria exportação nova; não altera o motor de saldo, o
  espelho nem o fechamento. **Aditivo e idempotente.** **Sem backfill.**
- **Conferência esperada:** `t | t | t | OK`.
- **Na bateria** sem mudança de contagem (398 já estava verde); regressão zero.
  Provado em transação: gerado→enviado→processado (válidas); gerado→processado
  **abortada** (inválida); um pacote em erro → reenvia 1 e depois 0 (idempotente),
  `tentativas=1`, sem duplicar (continua um pacote na competência).
- **Tela (Publicar no Lovable):** o disparo do envio e a confirmação de
  recebimento chamam essas transições; a fila e o reenvio já estão no banco.

### 32 · Onda 7 (parte 1) — comprovante como documento (Portaria 671/REP-P)
- **Arquivo:** `docs/script_ponto_onda7_comprovantes.sql`
- **O que faz:** hoje o comprovante é só um booleano
  (`ponto_marcacoes.comprovante_gerado`). A Portaria MTP 671/2021 (REP-P) trata o
  comprovante como o **recibo legal do trabalhador**: um artefato com
  identificação do empregador e do trabalhador, data/hora e **NSR**, arquivado e
  vinculado à marcação, disponibilizado em até 48h e extraível por período pelo
  próprio trabalhador. O NSR já existe na marcação (desde a onda 1); faltava o
  documento. Passam a existir: a tabela **`ponto_comprovantes`** (o documento, com
  empregador, trabalhador, data/hora, NSR, conteúdo mínimo, hash de integridade e
  vínculo à marcação — com a trava do cercado e RLS por tenant);
  **`ponto_gerar_comprovante`** (emite o comprovante da marcação, **idempotente** —
  um por marcação —, atribuindo o NSR quando falta e disponibilizando na hora);
  **`ponto_comprovante_vigiar_48h`** (vigia o prazo de 48h — marcação sem
  comprovante perto de estourar vira alerta **preventivo**, estourada vira
  **crítico**); e **`ponto_comprovantes_extrair`** (extração por período,
  **restrita ao próprio CPF** — direito do trabalhador).
- **Baixo risco:** não altera o motor de saldo, o espelho nem o fechamento. Só
  cria o documento, a emissão, a vigilância e a extração. **Aditivo e
  idempotente** (roda duas vezes sem quebrar nem duplicar). **Sem backfill** —
  comprovantes nascem sob demanda pela emissão.
- **Conferência esperada:** `t | t | t | t | t | OK`.
- **Na bateria** três casos passaram a passar na parte (380, 381, 359),
  regressão zero (91→94). Provado em transação: emissão atribui o NSR quando
  falta (0→1), monta o conteúdo com empregador/trabalhador/data/hora/NSR, grava o
  hash sha256 e marca `comprovante_gerado=true`; 2ª chamada devolve **o mesmo**
  comprovante (não duplica); a vigilância gera 1 alerta crítico numa marcação
  vencida e 0 na 2ª rodada (idempotente); a extração devolve 1 para o próprio CPF
  (mesmo com máscara) e 0 para outro CPF.
- **Tela — FEITO (28/08/2026):** registrar ponto passou a chamar
  `ponto_gerar_comprovante` logo após gravar a marcação (falha ali não desfaz a
  batida — a vigilância de 48h cobra o comprovante que faltar), e o cartão "Meus
  comprovantes de ponto" no Meu Perfil extrai por período pelo
  `ponto_comprovantes_extrair`, com download. Entra em produção por Publicar no
  Lovable.
- **Correção de segurança junto (item 54):** `ponto_comprovantes_extrair` é
  SECURITY DEFINER e recebia o CPF por parâmetro sem conferir quem chamava —
  qualquer usuário autenticado lia os comprovantes de um colega (LGPD arts. 6º,
  46 e 47). Ver o item 54: sem ele, **não publique a tela**.

### 33 · Onda 7 (parte 2) — AEJ (Arquivo Eletrônico de Jornada, Portaria 671)
- **Arquivo:** `docs/script_ponto_onda7_aej.sql`
- **O que faz:** o AEJ é a saída **obrigatória** do "programa de tratamento" na
  Portaria 671 (ele substituiu o AFDT/ACJEF da 1510/2009) e a peça que a
  fiscalização pede **junto com o AFD**. Não existia em lugar nenhum do banco —
  nem função, nem coluna, nem tabela. Passam a existir: a tabela
  **`ponto_arquivos_aej`** (o arquivo gerado e **arquivado** — empregador,
  período, conteúdo em registros tipados, versão estruturada, **assinatura por
  hash** e contagens, com a trava do cercado e RLS por tenant); o gerador
  **`ponto_gerar_aej(tenant, empresa, competência)`** (monta o AEJ **a partir da
  apuração fechada** — `ponto_espelhos` — mais o contrato (`admissoes`) e as
  marcações **tratadas** (`ponto_marcacoes` não desconsideradas, com origem e
  NSR), em registros tipados: 1 cabeçalho, 2 contrato, 3 marcação, 4 apuração,
  9 trailer; **idempotente**, refaz o arquivo da competência); e
  **`ponto_aej_extrair(tenant, empresa, competência)`** (devolve o arquivo
  arquivado + assinatura para download/fiscalização).
- **Baixo risco:** não altera o motor de saldo, o espelho, o fechamento nem as
  marcações. Só **lê** a apuração e grava o arquivo. **Aditivo e idempotente.**
  **Sem backfill** — o AEJ nasce sob demanda pela geração.
- **Conferência esperada:** `t | t | t | OK`.
- **Na bateria** um caso passou a passar na parte (211), regressão zero (94→95).
  Provado em transação (dados fictícios): o gerador monta o cabeçalho com o
  empregador e o período, um registro de contrato por trabalhador, um registro
  por marcação **tratada** (a desconsiderada fica de fora, e some da contagem),
  o registro de apuração da competência e o trailer com as contagens; assina com
  hash sha256; regerar **não duplica** (um arquivo por competência); a extração
  devolve o arquivo assinado.
- **Tela — FEITO (28/08/2026):** o botão "gerar AEJ" passou a chamar
  `ponto_gerar_aej` (arquiva e assina a versão tratada) antes de baixar o arquivo
  no leiaute oficial, e a aba mostra o cartão "Cópia arquivada e assinada desta
  competência" (data, contagens, hash e download da cópia tratada), lendo
  `ponto_aej_extrair`. Se o arquivamento falhar, o arquivo oficial sai mesmo
  assim e a tela avisa. Entra em produção por Publicar no Lovable.

### 34 · Onda 7 (parte 3) — importação de AFD que confere
- **Arquivo:** `docs/script_ponto_onda7_afd_importacao.sql`
- **O que faz:** a importação de AFD (o arquivo-fonte do relógio de terceiro) só
  conferia, quando conferia, **na tela**. Importação por API entrava **sem
  conferência**: arquivo corrompido, com a sequência de números de registro (NSR)
  quebrada, reimportado depois de uma falha no meio, ou com os registros que não
  são batida (ajuste do relógio, eventos do equipamento) simplesmente jogados
  fora. Passa a existir a conferência **no banco**:
  - **`ponto_afd_crc16`** — o dígito verificador (CRC-16) de cada registro, para
    pegar corrupção byte a byte (confere o valor-padrão: `123456789` → `10673`).
  - **`ponto_afd_validar_importacao`** — confere o CRC de cada registro, a cadeia
    (SHA-256 do fecho do arquivo), o veredito da assinatura e a **lacuna** na
    sequência de NSR; **arquivo com buraco na sequência é recusado por inteiro**
    (registro removido não entra como prova), com **quarentena** do reprovado e
    relatório. Só guarda os eventos do equipamento quando o arquivo é aprovado.
  - **`ponto_repc_importacoes`** ganha a **unicidade do arquivo** (a mesma remessa
    não entra duas vezes) e o veredito (CRC/cadeia/assinatura/quarentena).
  - **`ponto_marcacoes`** ganha a **chave natural de origem** (`nsr_origem` +
    `equipamento`) — o NSR que veio no arquivo e o relógio que o emitiu, para
    reimportação **idempotente** (o NSR próprio, gerado aqui, não deduplica
    arquivo de terceiro).
  - **`ponto_afd_eventos_equipamento`** — a casa dos registros não-batida (ajuste
    do relógio, evento sensível), visíveis na trilha; um relógio ajustado perto de
    uma marcação suspeita é o que a fiscalização procura.
- **Baixo risco:** não altera o motor de saldo, o espelho, o fechamento nem grava
  batida — a persistência das batidas validadas segue pelo fluxo existente, agora
  com este veredito como porteiro. **Aditivo e idempotente.** **Sem backfill.**
- **Conferência esperada:** `t | t | t | t | t | OK`.
- **Na bateria** quatro casos passaram a passar na parte (382, 383, 384, 212),
  regressão zero (95→99). Provado em transação (dados fictícios): arquivo válido
  guarda os eventos do equipamento; **lacuna** de NSR (falta o 101 entre 100 e
  102) manda o arquivo **inteiro** para a quarentena e **nenhum evento** entra;
  registro com CRC errado também vai para a quarentena, com o rejeitado contado.
- **Tela — FEITO (28/08/2026):** a importação de AFD passa por
  `ponto_afd_validar_importacao` ANTES de gravar qualquer marcação. A tela lê o
  arquivo (leiaute 671 ou 1510, detectado pelo cabeçalho) em registros tipados
  com a linha crua, calcula o hash da remessa (trava de reimportação), chama o
  validador e só grava se o arquivo for aprovado — com `nsr_origem` e
  `equipamento`, que impedem entrada em dobro. Reprovado, aparece o painel de
  quarentena explicando o que falhou (CRC, assinatura, lacuna de NSR,
  reimportação) e nada entra. O histórico ganhou a coluna "Conferência".
  Leitura coberta por `src/test/afdImportacao.test.ts`. Entra em produção por
  Publicar no Lovable.

### 35 · Onda 7 (parte 4) — gestão do certificado digital (ICP-Brasil)
- **Arquivo:** `docs/script_ponto_onda7_certificado_digital.sql`
- **O que faz:** não existia gestão de certificado digital — nem cadastro, nem
  vigência, nem alerta. Sem isso, o AFD e o AEJ **não têm com que ser assinados**
  (a assinatura `.p7s`/ICP-Brasil exigida pela Portaria 671 depende de um
  certificado), e um certificado **vencido** paralisaria a emissão assinada
  exatamente na hora da auditoria. Passam a existir:
  - **`ponto_certificados_digitais`** — o cadastro do certificado por empresa
    (tipo A1/A3, titular, número de série, emissor, vigência e a antecedência do
    alerta), com trava do cercado e RLS. **A chave privada não fica no banco** —
    só os metadados de vigência.
  - **`ponto_certificado_vigente`** — o certificado ICP-Brasil válido **hoje** (o
    que assina o `.p7s`); um certificado vencido não é devolvido.
  - **`ponto_certificado_vigiar_vencimento`** — vigia o vencimento: alerta
    **preventivo** com a antecedência parametrizada e **crítico** quando já
    vencido.
- **Baixo risco:** não altera o motor de saldo, o espelho, o fechamento nem a
  emissão de AFD/AEJ. Só cadastra e vigia. **Aditivo e idempotente.**
- **Conferência esperada:** `t | t | t | OK`.
- **Na bateria** um caso passou a passar na parte (360), regressão zero (99→100).
  Provado em transação (dados fictícios): o "vigente" escolhe o certificado válido
  e ignora o vencido; a vigilância gera **alta** para o que está perto de vencer e
  **crítica** para o vencido, e **nada** para o de validade longa; rodar de novo
  não duplica.
- **Tela — FEITO (28/08/2026):** nova aba **Ponto › Configurações › Certificado
  digital**: cadastro (tipo A1/A3, ICP-Brasil, titular, emissor, nº de série,
  vigência e antecedência do aviso), cartão "Certificado em uso hoje" — que
  avisa quando NÃO há vigente, porque sem ele o AFD/AEJ não têm com que ser
  assinados — e situação por linha (Vigente / Vence em N dias / VENCIDO). A tela
  guarda só metadados: **a chave privada não entra no sistema**. O alerta de
  vencimento passou a rodar sozinho (item 53, agora com oito rotinas). Entra em
  produção por Publicar no Lovable.

### 36 · Onda 7 (parte 5) — dossiê de fiscalização + arquivamento (fecha a onda 7)
- **Arquivo:** `docs/script_ponto_onda7_dossie_fiscalizacao.sql`
- **Depende das partes 2, 3 e 4 (#33, #34, #35)** — reúne as peças que elas criam.
- **O que faz:** faltavam as duas pontas do acervo de provas. **(1)** Diante do
  Auditor-Fiscal, o DP teria de caçar peça por peça — não havia um empacotador que
  reunisse AFD, AEJ, comprovantes, espelhos e a trilha num pacote com **índice e
  verificação de assinaturas (hashes)**. **(2)** As peças ficavam soltas nas
  tabelas do ponto, sem a **classificação por pasta e o vínculo** do módulo
  Documentos, dependendo de upload manual. Passam a existir:
  - **`ponto_dossies_fiscalizacao`** — o pacote da competência: o **índice** das
    peças com contagens e hashes, e o **hash do pacote** (integridade do conjunto),
    com trava do cercado e RLS.
  - **`ponto_arquivar_documento`** — grava a referência de uma peça no **módulo
    Documentos** (`public.documentos`) com pasta/classificação e vínculo
    (empresa/colaborador), conferindo o objeto no repositório de arquivos, **sem
    upload manual**; idempotente por caminho de arquivo.
  - **`ponto_gerar_dossie_fiscalizacao`** — monta o dossiê da competência a partir
    das peças (AEJ, comprovantes, espelhos, AFD importado) e o **arquiva** no
    módulo Documentos.
- **Baixo risco:** não altera o motor de saldo, o espelho, o fechamento nem as
  peças. Só **lê** as peças, monta o pacote e registra a referência. **Aditivo e
  idempotente.**
- **Conferência esperada:** `t | t | t | OK`.
- **Na bateria** dois casos passaram a passar na parte (392, 393), regressão zero
  (100→102). Provado em transação (dados fictícios): o dossiê soma as 5 peças da
  competência (1 AEJ, 2 comprovantes, 1 espelho, 1 AFD), monta o índice com um
  hash por tipo e o hash do pacote, e **arquiva** o dossiê no módulo Documentos
  (tipo, classificação, vínculo à empresa, "Ponto (automático)"); regerar **não
  duplica** nem o dossiê nem o documento.
- **Tela — FEITO (28/08/2026):** nova aba **Ponto › Compliance › Dossiê fiscal**:
  escolhe a competência, monta o dossiê (`ponto_gerar_dossie_fiscalizacao`), mostra
  o índice peça a peça (AEJ, comprovantes, espelhos, AFD importado) com contagem e
  hash, a assinatura do pacote, e permite baixar o índice para conferência. Peça
  com quantidade zero fica visível de propósito — é o que falta reunir antes da
  fiscalização. Remontar a mesma competência não duplica o dossiê (provado em
  réplica: 3 comprovantes → `comprovantes: 3`; segunda montagem mantém 1 dossiê).
  Entra em produção por Publicar no Lovable.
- **Onda 7 fechada nas telas (28/08/2026):** partes 1 a 5 agora têm ponto de
  acesso — comprovante, AEJ, importação de AFD conferida, certificado digital e
  dossiê. Em produção, o item 54 (correção de segurança dos comprovantes) entra
  ANTES do Publicar no Lovable.

### 37 · Onda 8 (parte 1) — enquadramento do art. 62 (dispensa) + teletrabalho
- **Arquivo:** `docs/script_ponto_onda8_enquadramento_art62.sql`
- **O que faz:** o cadastro não tinha enquadramento do art. 62. Gestor, trabalhador
  externo e teletrabalhista por produção/tarefa eram tratados como controlados — e
  a materialização de faltas gerava **falta para quem a lei dispensa de marcar**. E
  o teletrabalho não distinguia **jornada** de **produção** (Lei 14.442/2022): só
  produção dispensa; teletrabalhista por jornada continua sujeito a controle.
  Passam a existir, no vínculo (`admissoes`): `art62_inciso` (I/II/III),
  `art62_documento`, `teletrabalho_modalidade` (jornada/produção) e
  `dispensado_ponto` (a dispensa resolvida); a **regra** `ponto_art62_dispensa`
  (dispensa só quando há inciso **e** a modalidade não é teletrabalho por jornada);
  e um **gatilho** que resolve `dispensado_ponto` e, quando dispensa, **zera
  `bate_ponto`** — assim a materialização de faltas (que já pula `bate_ponto=false`)
  respeita a dispensa **sem tocar no motor**.
- **Baixo risco:** não altera o cálculo de saldo, o espelho nem o fechamento; o
  gatilho só recompõe a dispensa e a coerência de `bate_ponto`. **Aditivo e
  idempotente.**
- **Conferência esperada:** `t | t | t | t | t | OK`.
- **Na bateria** dois casos passaram a passar na parte (373, 374), regressão zero
  (102→104). Provado em transação (dados fictícios): gestor (II) e teletrabalho por
  **produção** (III) ficam **dispensados** e sem bater ponto; teletrabalho por
  **jornada** (III) **continua controlado** (não é dispensado); enquadrar um
  controlado depois já zera o `bate_ponto`.
- **Tela — FEITO (28/08/2026):** a ficha do colaborador ganhou o bloco **"Dispensa
  de controle de jornada (art. 62 da CLT)"**: enquadramento (não se enquadra / I
  externa / II gestão / III teletrabalho por produção), modalidade de teletrabalho
  e o documento que sustenta o enquadramento. Quando alguém marca um inciso com
  teletrabalho **por jornada**, a tela avisa que a dispensa não se aplica — a
  regra do banco mantém o colaborador marcando ponto. A lista de colaboradores
  passou a carregar esses campos para a edição. Provado em réplica: gestor
  (inciso II) grava `dispensado_ponto = true` e `bate_ponto = false`;
  teletrabalhista por jornada com inciso III fica `dispensado_ponto = false` e
  segue batendo ponto. Entra em produção por Publicar no Lovable.

### 38 · Onda 8 (parte 2) — controle de fato descaracteriza a dispensa (art. 62)
- **Arquivo:** `docs/script_ponto_onda8_descaracterizacao_art62.sql`
- **Depende da parte 1 (#37)** — usa o enquadramento (`dispensado_ponto`).
- **O que faz:** a dispensa do art. 62 cai na Justiça quando há **controle de
  fato** — um vínculo marcado como dispensado que, na prática, acumula marcações
  reais. Aí a exclusão é descaracterizada e as **horas extras do período inteiro**
  voltam. Passa a existir **`ponto_detectar_descaracterizacao_art62`**, que cruza o
  enquadramento com as marcações reais recentes (marcações desconsideradas não
  contam) e gera um **alerta crítico** por colaborador para RH/Jurídico revisar.
- **Baixo risco:** só leitura das marcações + gravação de alerta; não altera o
  motor de saldo, o espelho, o fechamento nem o enquadramento. **Aditivo e
  idempotente** (um alerta por colaborador/dia de varredura).
- **Conferência esperada:** `t | t | OK`.
- **Na bateria** um caso passou a passar na parte (375), regressão zero (104→105).
  Provado em transação (dados fictícios): um dispensado com marcações reais em três
  dias gera **um alerta crítico**; um dispensado com marcação em um só dia **não**
  gera; rodar de novo não duplica.
- **Tela (Publicar no Lovable):** o alerta aparece no painel do ponto; a detecção já
  está no banco (pode ser agendada periodicamente).

### 39 · Onda 8 (parte 3) — obrigatoriedade do controle por estabelecimento (>20)
- **Arquivo:** `docs/script_ponto_onda8_obrigatoriedade_estabelecimento.sql`
- **O que faz:** o controle de jornada é obrigatório quando o **estabelecimento**
  passa de 20 trabalhadores — e a contagem é **por estabelecimento**, não pela
  empresa inteira (CLT art. 74, §2º, Lei 13.874/2019). O sistema não tinha essa
  noção: tratava todo cliente igual, e um obrigado sem controle ativo não recebia
  aviso — enquanto a Súmula 338 do TST joga a jornada alegada pelo empregado contra
  quem não controla. Passam a existir: a sinalização no cadastro
  (`empresa_cadastro.controle_ponto_obrigatorio`), a **contagem por
  estabelecimento** (`ponto_estabelecimento_trabalhadores`) e o **monitor**
  (`ponto_estabelecimento_obrigatoriedade_monitorar`) que resolve a obrigatoriedade
  e **alerta** o estabelecimento obrigado que ainda não usa controle de ponto.
- **Baixo risco:** não altera o motor de saldo, o espelho nem o fechamento. Só
  conta, sinaliza e alerta. **Aditivo e idempotente.**
- **Conferência esperada:** `t | t | t | OK`.
- **Na bateria** um caso passou a passar na parte (370), regressão zero (105→106).
  Provado em transação (dados fictícios): um estabelecimento com 21 trabalhadores
  ativos vira **obrigado** e, por não usar controle, recebe um alerta; um com 5
  trabalhadores **não**; rodar de novo não duplica.
- **Tela — FEITO (28/08/2026):** a lista de empresas mostra o selo **"ponto
  obrigatório"** ao lado da contagem de colaboradores quando
  `controle_ponto_obrigatorio` está marcado, com a explicação legal no título.
  Quem marca é a rotina do banco (que agora roda sozinha, item 53). Provado em
  réplica: 26 vínculos ativos → contagem 26, monitor gera 1 alerta e a empresa
  fica sinalizada. Entra em produção por Publicar no Lovable.
- **Restante (Publicar no Lovable):** o alerta aparece no cadastro do
  estabelecimento; a contagem e a regra já estão no banco.

### 40 · Onda 8 (parte 4) — sistema alternativo (REP-A) só com instrumento coletivo
- **Arquivo:** `docs/script_ponto_onda8_rep_alternativo_instrumento.sql`
- **O que faz:** o sistema alternativo de controle de jornada (REP-A: registro por
  link/app) só é admitido quando **autorizado por convenção ou acordo coletivo**
  (Portaria 671; CLT art. 74, §4º). O modo `link_externo` podia ser ativado **sem
  nenhum lastro documental** — e registro alternativo sem autorização invalida o
  controle perante a fiscalização. Passa a ser **recusado** sem autorização:
  espelhando a trava que já existe para o registro por exceção, ativar
  `modo_registro='link_externo'` exige o documento do instrumento coletivo anexado
  (`link_externo_acordo_url`) **ou** um acordo **coletivo** (act/cct) vigente em
  `ponto_acordos`. Um acordo **individual** não autoriza.
- **Baixo risco:** não altera o motor de saldo, o espelho nem o fechamento; só
  valida a ativação do modo alternativo. Os modos `interno` e `ambos` não são
  afetados, e o gatilho só dispara quando se mexe no modo ou na autorização.
  **Aditivo e idempotente.**
- **Conferência esperada:** `t | t | t | OK`.
- **Na bateria** um caso passou a passar na parte (213), regressão zero (106→107).
  Provado em transação (dados fictícios): `link_externo` **sem** autorização é
  recusado; **com** o documento anexado é aceito; **com** um acordo coletivo
  vigente é aceito; um acordo **individual** é recusado (exige coletivo); e o modo
  `interno` passa normalmente.
- **Tela — FEITO (28/08/2026):** ao escolher "link externo" (ou "ambos") em
  Ponto › Configurações › Geral, aparece o campo **"Instrumento que autoriza o
  registro por link (REP-A)"**, com a explicação legal — junto da escolha, não
  escondido em outra tela. Se o banco recusar, a mensagem técnica vira uma frase
  que o RH resolve ("informe o instrumento ou cadastre um acordo vigente em
  Compliance › Acordos"). Provado em réplica: ativar `link_externo` sem
  instrumento é recusado pelo gatilho; com o instrumento informado, grava.
  Entra em produção por Publicar no Lovable.

### 41 · Onda 8 (parte 5) — LGPD: trilha de acesso a dado sensível + enumeração
- **Arquivo:** `docs/script_ponto_onda8_lgpd_trilha_e_enumeracao.sql`
- **O que faz:** duas frentes de LGPD. **(397)** A trilha de auditoria só
  registrava **escrita** — visualizar a selfie ou a geolocalização de uma marcação
  e **exportar** relatórios (AFD/AEJ) não deixavam rastro; a LGPD (arts. 11 e 46)
  pede registro do tratamento de dado sensível. Passam a existir um **log imutável**
  (`ponto_acesso_sensivel_log`, append-only) e as funções que registram **quem viu**
  dado sensível (`ponto_log_acesso_sensivel`) e **quem exportou**, com escopo e
  destinatário (`ponto_log_exportacao`). **(362)** O link compartilhado identifica o
  trabalhador por CPF; tentativas em sequência com CPFs diferentes (**enumeração**)
  passavam sem contenção. `ponto_links` ganha `tentativas_frustradas` e
  `bloqueado_ate`, e **`ponto_link_registrar_tentativa`** conta as tentativas por
  link, **bloqueia temporariamente** ao estourar o limite e registra o evento na
  trilha (LGPD arts. 46-49).
- **Baixo risco:** não altera o motor de saldo, o espelho, o fechamento nem as
  marcações. Só registra acesso e contém enumeração. **Aditivo e idempotente.**
- **Conferência esperada:** `t | t | t | t | t | OK`.
- **Na bateria** dois casos passaram a passar na parte (397, 362), regressão zero
  (107→109). Provado em transação (dados fictícios): a visualização de selfie e a
  exportação de AFD gravam no log; o log **recusa** UPDATE e DELETE (imutável); no
  link, cinco tentativas frustradas **bloqueiam** o link e geram um evento de
  enumeração na trilha, e um acesso bem-sucedido **zera** o contador.
- **Tela — FEITO (28/08/2026):** três frentes.
  (1) **Selfie**: deixou de ser servida a quem apenas abre o espelho — vem coberta
  por um botão de câmera, e revelar chama `ponto_log_acesso_sensivel`
  (`visualizou_selfie`, com a marcação e o CPF). O gesto deliberado é o que a
  trilha registra.
  (2) **Exportações**: AFD, AEJ (inclusive a cópia arquivada), PDFs e planilhas do
  módulo passam a chamar `ponto_log_exportacao` com competência, empresa e tipo de
  relatório no escopo. Falha no registro **não** impede a exportação.
  (3) **Link compartilhado**: cada identificação por CPF chama
  `ponto_link_registrar_tentativa`; ao estourar o limite o link fica bloqueado por
  alguns minutos, com mensagem em português e o evento na trilha. Acerto zera o
  contador. Provado em réplica: 5 tentativas frustradas → `bloqueado: true` e uma
  linha `enumeracao_cpf_link` na trilha; acerto seguinte zera `tentativas_frustradas`
  e libera o link. Entra em produção por Publicar no Lovable.

### 42 · Onda 8 (parte 6) — Plano de Ação (fecha a onda 8 no banco)
- **Arquivo:** `docs/script_ponto_onda8_plano_de_acao.sql`
- **O que faz:** três frentes que ligam o ponto ao Plano de Ação. **(389)** O
  alerta do ponto (lacuna, HE habitual, intervalo, banco a vencer, integridade,
  instrumento vencido, obrigatoriedade, descaracterização) passa a **virar ação
  5W2H** no Plano de Ação, com a origem navegável (`ponto_alerta_gerar_acao`; o
  alerta ganha `plano_acao_id`). **(390)** Concluir a ação **valida a eficácia**
  (`ponto_acao_concluir_com_eficacia`): reavalia a ocorrência de origem e, se ela
  persiste (recorrência), **não dá baixa cega** — gera um alerta de eficácia; senão,
  encerra o alerta. **(391)** A **IA de análise** nasce com o limite embutido: ela
  **sugere** causa/impacto/ação (`ponto_ia_analisar_alerta`, status *sugerido*) e só
  avança por **decisão humana registrada** (`ponto_ia_registrar_decisao`, exige o
  responsável humano). Nada automatizado afeta direito do trabalhador (LGPD art. 20).
- **Nota sobre o caso 391:** o próprio caso PONTO-391 previa "reclassificar como
  passou quando a IA existir com o controle implantado". Este pacote implanta a IA
  de sugestão com o controle de decisão humana **e** atualiza a regra para
  reconhecê-lo — **se houver decisão automática sobre direito, continua reprovando.**
- **Baixo risco:** não altera o motor de saldo, o espelho, o fechamento nem as
  marcações. **Aditivo e idempotente.**
- **Conferência esperada:** `t | t | t | t | t | OK`.
- **Na bateria** três casos passaram a passar na parte (389, 390, 391), regressão
  zero (109→112). Provado em transação (dados fictícios): o alerta vira ação 5W2H
  (ACO-… com por quê/onde/como/prazo, prioridade pela severidade) e fica vinculado;
  concluir sem recorrência **encerra** o alerta, com recorrência **gera** alerta de
  eficácia; a IA sugere, a decisão **sem humano é recusada** e **com humano** fica
  registrada.
- **Tela — FEITO (28/08/2026):** no painel de Alertas CLT, cada alerta ganhou
  **"Gerar ação"** (chama `ponto_alerta_gerar_acao`, que cria a 5W2H com a origem
  e deixa o alerta vinculado — alerta já convertido mostra o selo "Ação criada")
  e **"Analisar com IA"**, que abre a sugestão (causa provável, impacto, ação) com
  os botões *Aceitar e criar ação* / *Recusar sugestão*: a decisão humana fica
  registrada por `ponto_ia_registrar_decisao` nos dois casos, e só o aceite gera a
  ação. O diálogo diz na abertura que a análise **sugere** e quem decide é a
  pessoa (LGPD art. 20).
  Concluir uma ação de origem `ponto` passa por `ponto_acao_concluir_com_eficacia`:
  se a ocorrência persiste, a tela avisa que um alerta de eficácia foi aberto em
  vez de dar baixa cega. A falha na reavaliação não impede a conclusão.
  Provado em réplica: gerar ação vincula o alerta e cria a ação com
  `origem_modulo = ponto`; a análise nasce `sugerido` e só vira `decidido_aceito`
  depois da decisão humana, com o nome de quem decidiu e a observação. Entra em
  produção por Publicar no Lovable.
- **Onda 8 fechada nas telas (28/08/2026):** partes 1 a 6 com ponto de acesso.

### 43 · Onda 8 (correção) — competência fechada bloqueia até para gestão
- **Arquivo:** `docs/script_ponto_onda8_competencia_fechada.sql`
- **Por que existe:** ao rodar a bateria do ponto no ambiente de teste **por um
  usuário de gestão**, o caso PONTO-193 reprovou: uma competência **fechada**
  aceitou marcação nova sem reabertura. O guard de período (`validar_periodo_aberto_ponto`)
  abria uma **exceção para papéis de gestão** — a "válvula" já apontada como
  risco. Sem sessão (a réplica local roda sem usuário) o caso passava; **como
  gestão** — o cenário real do teste — a válvula deixava a marcação entrar por
  baixo dos panos, alterando um espelho já entregue e assinado.
- **O que faz:** **remove a válvula.** Competência **fechada** passa a bloquear
  marcação nova para **todos**. O único caminho para mexer continua sendo a
  **reabertura formal** (pacote #14, PONTO-358), que muda o status para
  *reaberto* — e aí o guard naturalmente libera (ele só bloqueia *fechado*). O
  gatilho é *BEFORE INSERT*, então só afeta marcação **nova**; a correção por
  acréscimo (desconsiderar) não é tocada.
- **Baixo risco:** não altera o motor de saldo, o espelho nem o fechamento. Só
  fecha a válvula do guard de período. **Aditivo (substitui a função) e idempotente.**
- **Conferência esperada:** `t | t | f | f | OK` — a função existe, ainda bloqueia
  competência fechada, e **não** contém mais `has_role` nem a lógica `pode_burlar`.
- **Na bateria:** rodando **como gestão** (o cenário que reprovava), o PONTO-193
  passou a **passar**; sem sessão, a bateria segue em 112 casos passando, com os
  mesmos dois em vermelho (113 rural e 386 vigência de CCT, itens de onda futura),
  regressão zero.

### 44 · Onda 9 — instrumento coletivo vigente na competência (vigilância)
- **Arquivo:** `docs/script_ponto_onda9_cct_vigencia.sql`
- **O que faz:** a apuração de horas **já escolhia** o instrumento coletivo
  (CCT/ACT em `ponto_cct_config`) cuja vigência cobre a **data apurada** —
  reapurar uma competência antiga aplica a convenção da época, não a atual
  (CF/88 art. 7º, XXVI). O que faltava era a **vigilância**: cria
  `ponto_cct_vigiar_vigencia(tenant, empresa)`, que gera alerta quando um
  instrumento está **a vencer** (60 dias → média, 30 dias → alta) ou **vencido**
  (crítica), e quando **duas vigências se sobrepõem** no mesmo escopo
  (empresa + categoria) — situação que deixaria a apuração ambígua.
- **Baixo risco:** não altera o motor de saldo, o espelho, o fechamento nem a
  apuração — só lê `ponto_cct_config` e escreve alertas. **Aditivo e idempotente.**
- **Conferência esperada:** `t | t | OK` — a função de vigilância existe e a
  apuração continua filtrando por vigência.
- **Na bateria:** o PONTO-386 passou a **passar** (a apuração respeita a vigência
  **e** a vigilância existe), regressão zero (112→113). Provado em transação
  (dados fictícios): instrumento a vencer gera alerta *alta*, vencido gera
  *crítica*, par sobreposto gera *alta* nos dois; segunda chamada não duplica.
- **Sobra em vermelho** só o **PONTO-113** (trabalhador rural), que é evolução
  condicional a cliente do agronegócio — fora do escopo de conformidade geral.

### 45 · QA (metadado) — disposição dos 6 casos de tela conforme auditoria as-built
- **Arquivo:** `docs/script_qa_disposicao_ponto_telas.sql`
- **Por que existe:** a disposição desses 6 casos `e2e` (tela) foi gravada em
  05/08/2026, **antes das ondas**, com o motivo genérico *"o motor de apuração
  ainda não existe"* aplicado a todos os `PONTO-%` de uma vez. Hoje o motor
  existe e o apoio de banco de vários já está pronto — o texto ficou mentindo no
  relatório. Este pacote corrige a disposição **caso a caso**, a partir de uma
  auditoria as-built do código React (PontoExterno, comprovante, geofence,
  selfie):
  - **PONTO-002** → `comportamento_correto` (não restringe horário: já atendido);
  - **PONTO-005** → `aguardando_construcao` (banco pronto na onda 7; falta expor
    o comprovante na tela do trabalhador);
  - **PONTO-006** → `aguardando_construcao` (nunca bloqueia e registra: ok; falta
    só o "sinaliza" ao trabalhador);
  - **PONTO-195** → `aguardando_construcao` (banco tem `ressalva_texto`; falta a
    tela de ciência/ressalva por inteiro);
  - **PONTO-254** → `decisao_de_produto` (selfie é dado comum hoje; falta decidir
    classificação/aviso e o gatilho de reclassificação);
  - **PONTO-363** → `decisao_de_produto` (aviso mínimo existe; falta decidir o
    conteúdo e construir o aviso LGPD completo).
- **Baixo risco:** **não muda nenhuma rotina de teste nem o resultado da
  bateria** — só o texto de disposição mostrado no relatório. **Idempotente.**
- **Conferência esperada:** 6 linhas, uma por caso, `erro_tecnico = OK` nas 6.
- **Opcional em produção:** o placar da bateria não muda com ou sem este pacote;
  ele só deixa o relatório honesto. Aplique quando quiser o relatório alinhado.

### 46 · Onda 10 (parte 1) — escala 12x36 só vale com acordo formal (ESC-001)
- **Arquivo:** `docs/script_ponto_onda10_escala_12x36_formalizacao.sql`
- **Contexto:** a bateria ganhou 8 casos novos de escala/atestado (`ESC-*`, análise
  de requisitos YE-DP-ESC-001). Esta é a parte 1 da **onda 10** (escalas).
- **O que faz:** o art. 59-A da CLT condiciona a **12x36** a acordo individual
  ESCRITO, ACT ou CCT. Hoje a 12x36 nasce ativa e é atribuída **sem que nada cobre
  o acordo** — as colunas existem (`acordo_individual_url`, `cct_act_url`) e nenhuma
  função as lê. Cria `ponto_escala_formalizacao_status` (verificador que lê o acordo
  anexado e o coletivo vigente) e `ponto_escala_formalizacao_monitorar` (gera
  **pendência/alerta** para toda 12x36 ativa sem acordo formal). **Não bloqueia o
  cadastro** — sinaliza a pendência; anexado o acordo, a pendência deixa de nascer.
- **Baixo risco:** não altera o motor de saldo, a apuração do ciclo (PONTO-150/151),
  o espelho nem o fechamento. Só verifica e alerta. **Aditivo e idempotente.**
- **Conferência esperada:** `t | t | OK` — verificador e monitor presentes, lendo o
  acordo.
- **Na bateria** só o **ESC-001** passou a passar (falhou→passou); regressão zero
  (113→114 verdes). Provado em transação (dados fictícios): 12x36 sem acordo →
  status `pendente` e 1 pendência; 12x36 com acordo anexado → `regular`, 0
  pendência; segunda rodada do monitor não duplica.
- **Tela — FEITO (28/08/2026):** a lista de escalas ganhou a coluna
  **Formalização** ("Falta acordo" / "Em ordem"), lida de
  `ponto_escala_formalizacao_status`, e um cartão de aviso no topo reúne as
  escalas pendentes com a explicação legal e o caminho para regularizar. Entra em
  produção por Publicar no Lovable.

### 47 · Onda 10 (parte 2) — revezamento: jornada de 6h, salvo coletivo (ESC-031)
- **Arquivo:** `docs/script_ponto_onda10_escala_revezamento.sql`
- **Depende do #46** (estende as mesmas funções de formalização).
- **O que faz:** o turno ininterrupto de **revezamento** tem jornada
  constitucional de **6 horas** (CF art. 7º, XIV); só a negociação coletiva amplia
  (o STF admite até 8h por CCT/ACT). Hoje o revezamento **não existe** como
  conceito — a modalidade só conhece `fixa`/`movel` e nada valida as 6h. O pacote
  (1) **tipifica `revezamento`** na modalidade da escala e (2) estende a
  formalização: revezamento **acima de 6h** sem instrumento **coletivo** (CCT/ACT
  anexado ou coletivo vigente) gera **pendência/alerta**. Revezamento de até 6h é
  regular (piso constitucional); acordo **individual** não autoriza ampliar.
- **Baixo risco:** não altera o motor de saldo, a apuração, o espelho nem o
  fechamento. A troca do CHECK só **amplia** o conjunto (superset) — nenhuma linha
  atual deixa de passar. **Aditivo e idempotente.** `SET lock_timeout='10s'` na DDL.
- **Conferência esperada:** `t | t | t | OK` — modalidade aceita revezamento,
  verificador o menciona, monitor presente.
- **Na bateria** só o **ESC-031** passou a passar (falhou→passou); regressão zero
  (114→115 verdes). Provado em transação (dados fictícios): revezamento de 8h sem
  coletivo → `pendente` e 1 alerta; de 6h → `regular`; de 8h com CCT anexada →
  `regular`; segunda rodada do monitor não duplica.
- **Tela — FEITO (28/08/2026):** o cadastro da escala ganhou a modalidade
  **"Turno ininterrupto de revezamento"** (que usa o formulário de dias da semana,
  não o de ciclo móvel) e um aviso explicando que acima de 6h só com instrumento
  coletivo. A pendência aparece na coluna Formalização. Provado em réplica:
  revezamento de 8h fica "pendente", **continua pendente com acordo individual**
  (só o coletivo autoriza) e vira "regular" com CCT anexada; revezamento de 6h já
  nasce regular. Entra em produção por Publicar no Lovable.
- **Restante (Publicar no Lovable):** a tipificação, a
  verificação e a pendência já estão no banco.

### 48 · Onda 10 (parte 3) — radar de cobertura de turno (ESC-021)
- **Arquivo:** `docs/script_ponto_onda10_cobertura_turno.sql`
- **O que faz:** operação por turnos vive de cobertura. Um turno previsto **sem
  colaborador disponível** (quem estava atribuído entrou de férias, se afastou ou
  foi desligado) precisa aparecer **antes do dia** — não ser descoberto com o
  posto vazio. Cria `ponto_escala_cobertura_listar` (read-only, para a tela) e
  `ponto_escala_cobertura_monitorar` (gera **alerta ao gestor**), que projetam os
  próximos dias de cada escala com atribuição vigente e acusam o dia em que
  **todos** os colaboradores atribuídos estão indisponíveis (cruzando
  `afastamentos`, `ferias_solicitacoes` e desligamento em `admissoes`).
- **Baixo risco:** somente leitura + alerta; não altera o motor de saldo, a
  apuração, o espelho nem o fechamento. **Aditivo e idempotente.** Monitor
  agendável (sem gatilho em tabela quente).
- **Conferência esperada:** `t | t | OK` — listador e monitor presentes, falando
  de turno/cobertura.
- **Na bateria** só o **ESC-021** passou a passar (falhou→passou); regressão zero
  (115→116 verdes). Provado em transação (dados fictícios): escala cujo único
  colaborador está afastado nos próximos dias → 7 dias descobertos e 7 alertas;
  escala com colaborador disponível → 0; segunda rodada do monitor não duplica.
- **Tela — FEITO (28/08/2026):** cartão **"Turnos a descoberto nos próximos 14
  dias"** no topo da aba Escalas, lendo `ponto_escala_cobertura_listar` (escala,
  dia e o porquê). Só aparece quando há algo a mostrar. A ação de cobertura no
  Plano de Ação segue pendente. Entra em produção por Publicar no Lovable.

### 49 · Onda 10 (parte 4) — troca de turno com aprovação e recálculo (ESC-020)
- **Arquivo:** `docs/script_ponto_onda10_troca_turno.sql` — **fecha a onda 10.**
- **O que faz:** trocar o turno de dois colaboradores **não** é editar duas linhas:
  precisa de **aprovação** (gestor), **registro** (quem trocou com quem, quando) e
  **recálculo** — a interjornada de 11h (CLT art. 66) pode mudar para os dois. Cria
  a tabela `ponto_troca_turno` (com **trava do cercado** e **RLS por tenant**) e o
  fluxo `ponto_troca_turno_solicitar` → `aprovar`/`recusar` → `efetivar`. O
  **solicitar** simula a interjornada dos dois **antes** de consumar (marca risco
  quando a virada fica abaixo de 11h); o **efetivar** troca as atribuições em
  `ponto_escala_atribuicoes` de forma transacional, **preservando o histórico de
  vigência** (encerra as antigas, cria as cruzadas; se a troca tem fim, restaura
  depois).
- **Baixo risco:** não altera o motor de saldo, a apuração, o espelho nem o
  fechamento. A efetivação só mexe nas atribuições (append, sem apagar história).
  **Aditivo e idempotente.** `SET lock_timeout='10s'` na DDL.
- **Conferência esperada:** `t | t | t | 4 | OK` — tabela, RLS ativa (PONTO-250),
  política por tenant e as 4 funções do fluxo.
- **Na bateria** só o **ESC-020** passou a passar (falhou→passou); regressão zero
  (116→117 verdes) — PONTO-250 (RLS) e PONTO-270 (cercado) seguem verdes com a
  tabela nova. Provado em transação (dados fictícios): solicitação de troca com
  virada de 8h marca **risco de interjornada**; efetivar **antes** de aprovar é
  recusado; após aprovar, a efetivação cruza as escalas dos dois a partir da data
  e **mantém as atribuições antigas** encerradas na véspera (história preservada).
- **Tela — FEITO (28/08/2026):** nova sub-aba **Ponto › Escalas › Troca de turno**
  com o fluxo inteiro: solicitar (escolhendo as duas atribuições vigentes, período
  e motivo), aprovar/recusar e efetivar. O aviso de interjornada aparece por linha
  ("abaixo de 11h", com o detalhe da simulação) e aprovar uma troca com risco pede
  confirmação por palavra-chave — o gestor pode assumir, mas não sem ver. Só
  aparece "Efetivar" depois de aprovada, e a efetivação avisa que o histórico
  anterior é preservado. Provado em réplica: escala 15–23 trocando com 07–15
  acusa "interjornada de 8.0h"; efetivar sem aprovar é recusado pelo banco; após
  efetivar, cada colaborador fica com a atribuição antiga encerrada na véspera e a
  nova a partir do dia da troca. Entra em produção por Publicar no Lovable.
- **Restante (Publicar no Lovable):** o fluxo, a simulação e a efetivação já estão
  no banco.

### 50 · Onda 11 (parte 1) — atestado acima de 15 dias encaminha ao INSS (ESC-010)
- **Arquivo:** `docs/script_ponto_onda11_atestado_encaminha_inss.sql`
- **Abre a onda 11** (atestados/afastamentos — área de saúde, LGPD sensível).
- **O que faz:** o atestado longo muda de natureza no **16º dia** — até 15 dias a
  empresa abona; do 16º em diante é **benefício previdenciário do INSS** (Lei 8.213,
  arts. 59-60). Hoje um atestado de 20 dias entra e **nenhum afastamento nasce**.
  Um gatilho `BEFORE INSERT` em `atestados` passa a, quando o período **passa de 15
  dias** e o atestado ainda não tem afastamento vinculado, **criar** o afastamento
  previdenciário (status `beneficio_inss`, tipo B31, começando no 16º dia),
  **vincular** em `atestados.afastamento_id` e **alertar o DP** — uma única vez.
- **Baixo risco:** a criação do afastamento é **defensiva** (`EXCEPTION → NOTICE`):
  qualquer falha na cadeia de gatilhos de `afastamentos` **não quebra** o registro
  do atestado. Não altera o motor de saldo, a apuração, o espelho nem o fechamento.
  **Aditivo e idempotente** (só age quando `afastamento_id` é nulo).
- **Conferência esperada:** `t | t | OK` — a função da ponte existe e o gatilho está
  em `atestados`.
- **Na bateria** só o **ESC-010** passou a passar (falhou→passou); regressão zero
  (117→118 verdes). Provado em transação (dados fictícios): atestado de 20 dias →
  afastamento `beneficio_inss` criado a partir do 16º dia, vinculado, com alerta ao
  DP; atestado de 10 dias → **nada** (abono da empresa, não encaminha).
- **Tela (Publicar no Lovable):** o aviso de encaminhamento e a conferência do
  benefício aparecem no painel; a ponte já está no banco.

### 51 · Onda 11 (parte 2) — atestados sobrepostos detectados, não abonados em dobro (ESC-011)
- **Arquivo:** `docs/script_ponto_onda11_atestados_sobrepostos.sql`
- **O que faz:** dois atestados que cobrem o **mesmo período** (documento reenviado,
  ou dois médicos para os mesmos dias) não podem **abonar em dobro** nem confundir a
  contagem dos 15 dias. Hoje entram como registros independentes, **sem detecção**, e
  tudo que soma por atestado dobra (dias acumulados, a régua dos 15 dias do INSS,
  absenteísmo). Um gatilho `BEFORE INSERT` em `atestados` passa a **detectar a
  sobreposição** de período (mesmo CPF/tenant) na entrada e **sinalizar** — um alerta
  ao DP (`tipo = 'atestado_sobreposto'`, severidade `media`) decidir qual vale,
  mantendo o tratamento mais favorável e a **contagem de dias única** (cada dia doente
  conta uma vez).
- **Baixo risco:** **não bloqueia** o registro (pode ser dois atendimentos legítimos);
  só detecta e alerta. O alerta é **defensivo** (`EXCEPTION → NOTICE`): nunca quebra o
  registro do atestado. Não altera o motor de saldo, a apuração, o espelho nem o
  fechamento. **Aditivo e idempotente.**
- **Conferência esperada:** `t | t | OK` — a função de detecção existe e o gatilho está
  em `atestados`.
- **Na bateria** só o **ESC-011** passou a passar (falhou→passou); regressão zero
  (118→119 verdes). Provado em transação (dados fictícios): dois atestados com períodos
  sobrepostos do mesmo CPF → **1 alerta** de sobreposição; dois atestados sem
  sobreposição → **nenhum** alerta.
- **Tela (Publicar no Lovable):** o aviso de sobreposição aparece no painel de alertas
  do DP; a detecção já está no banco.

### 52 · Onda 11 (parte 3) — ausência do art. 473 sem documento fica pendente (ESC-012)
- **Arquivo:** `docs/script_ponto_onda11_comprovacao_art473.sql`
- **Fecha a onda 11 e a fila legal do Ponto no banco.**
- **O que faz:** o rol do art. 473 da CLT abona a falta, mas **mediante comprovação**
  (certidão de óbito/casamento, declaração de comparecimento, comprovante de doação
  de sangue). O catálogo `ponto_justificativas` já marcava os tipos que exigem
  documento (`requer_anexo`) e a tela recebia a flag — mas **nada impedia** o abono
  sem documento. Agora `processar_ajuste_ponto` olha `requer_anexo`: um abono que
  exige documento e entra **sem anexo não se consuma** — o ajuste fica
  `pendente_comprovacao`, com **prazo**, e um alerta avisa o colaborador e o DP.
  Anexado o documento e reprocessado, o abono se **efetiva**. Uma nova rotina
  `ponto_comprovacao_monitorar` varre as pendências com prazo vencido e alerta o DP
  **antes** de o dia virar desconto.
- **Estrutura:** nova coluna `ponto_ajustes.comprovacao_prazo` (data-limite) e o
  `CHECK` de status ganha o valor `pendente_comprovacao`. Reproduz
  `processar_ajuste_ponto` na íntegra e apenas acrescenta o portão do art. 473 —
  todo o resto (segregação de funções, correção por acréscimo, marcações) é idêntico.
- **Baixo risco:** **aditivo e idempotente**. Não altera o motor de saldo, a apuração,
  o espelho nem o fechamento — só condiciona a **consumação do abono à prova**. Não
  desconta às cegas: o dia fica falta pendente até a decisão. `SET lock_timeout` na DDL.
- **Conferência esperada:** `t | t | t | t | OK` — coluna, estado no `CHECK`, o portão
  em `processar_ajuste_ponto` e a rotina de monitoramento existem.
- **Na bateria** só o **ESC-012** passou a passar (falhou→passou); regressão zero
  (119→120 verdes). Provado em transação (dados fictícios): abono `requer_anexo` sem
  documento → `pendente_comprovacao`, prazo, alerta ao colaborador+DP e o dia **fica
  falta** (não abona); prazo vencido → alerta ao DP (idempotente); documento anexado
  e reaprovado → **abono efetivado**.
- **Tela (Publicar no Lovable):** o novo estado "pendente de comprovação", o prazo e
  os avisos aparecem no fluxo de ajustes/justificativas; a regra já está no banco.
- **Encerramento:** com este pacote, a fila legal do Ponto fica **inteira verde** —
  restam apenas o **rural (PONTO-113)**, parado por decisão, e os **casos de tela**
  (e2e, cobertos pelo Cypress).

### 53 · Vigilâncias do ponto — rotina diária que faz as monitorias rodarem
- **Arquivo:** `docs/script_ponto_vigilancias_diarias.sql`
- **Depende de:** #23 (alertas do banco), #38 (art. 62), #39 (estabelecimento),
  #44 (CCT), #46/#47 (formalização de escala), #48 (cobertura de turno).
- **O que faz:** as ondas 5, 7, 8, 9 e 10 criaram rotinas de vigilância que geram
  alerta no painel de Alertas CLT. **Nenhuma tem gatilho nem agendamento** — são
  funções que alguém precisa chamar, e nenhuma tela chama. Na prática, **oito**
  famílias de alerta nunca foram emitidas (as seis primeiras mais, desde
  28/08, o **vencimento do certificado digital** e o **prazo de 48h do
  comprovante**, encontrados ao ligar as telas da onda 7; a migration
  `20260828150000` acrescentou as duas, e o script de entrega já sai completo). Este pacote cria
  `ponto_vigilancias_diarias()`, que percorre os tenants ativos e executa cada
  monitoria **isolando erro por tenant/rotina** (uma falha não impede as demais),
  e a agenda no `pg_cron` para rodar 1x/dia às **03:37 UTC** (minuto livre entre
  as rotinas já existentes do módulo: 03:17 links, 04:41 expurgo, 05:23 faltas).
- **Não altera dado existente:** só cria a função e o agendamento. As rotinas
  chamadas apenas INSEREM alerta e todas já se protegem contra duplicidade
  (`NOT EXISTS` por tipo/escopo/data) — rodar todo dia não repete alerta. Nenhuma
  toca marcação, apuração, saldo ou espelho. Por isso **não há cópia de segurança
  a fazer**.
- **Conferência esperada:** `t | t | t | 37 3 * * * | <n> | OK`.
- **Provado em réplica local** (868 migrations aplicadas): com uma CCT vencendo em
  10 dias, a 1ª execução gera **1 alerta** (`cct_vigencia_vencimento`, severidade
  alta) e a 2ª execução gera **0** — idempotente. Mesmo resultado com um
  certificado digital vencendo em 10 dias (`certificado_digital_vencimento`,
  alta): 1 na primeira execução, 0 na segunda. O reagendamento rodado duas
  vezes deixa **um único** job. Sem `pg_cron` (réplica), a função é criada e a
  conferência avisa que nada foi agendado, em vez de falhar.
- **Tela (Publicar no Lovable):** nenhuma. Os alertas aparecem no painel de
  Alertas CLT que já existe, porque ele lista a tabela inteira.

### 54 · Comprovantes — extração restrita ao dono do CPF (correção de segurança)
- **Arquivo:** `docs/script_ponto_comprovantes_extrair_dono.sql`
- **Depende de:** #32 (comprovante como documento).
- **O que corrige:** `ponto_comprovantes_extrair()` é `SECURITY DEFINER` e recebe
  o CPF por parâmetro. O comentário dizia "restrita ao proprio CPF", mas a
  restrição **não estava escrita**: qualquer usuário autenticado podia chamar a
  função com o CPF de um colega e receber os comprovantes dele — data, hora e NSR
  de cada batida. O RLS não protege: `SECURITY DEFINER` passa por cima. Dado
  pessoal de terceiro (LGPD arts. 6º, 46 e 47).
- **O que passa a valer:** mesma assinatura e mesmo retorno; antes de devolver
  qualquer linha, confere quem chama — o **dono** do CPF
  (`usuarios_base.auth_user_id = auth.uid()`), quem tem **papel de gestão**
  (`has_minimum_role >= manager`) ou execução **sem sessão** (rotina/SQL Editor).
  Fora disso devolve **vazio**, sem erro, para não virar oráculo de "este CPF
  existe".
- **Não altera dado:** função de leitura, `CREATE OR REPLACE`, idempotente. Sem
  cópia de segurança a fazer.
- **Conferência esperada:** `t | t | t | OK`.
- **Provado em réplica local:** com a versão antiga, um colaborador lia os
  comprovantes de outro (**1 linha**); com esta, lê **0**. O dono continua lendo
  os seus, o gestor continua lendo os de terceiros, e a execução sem sessão segue
  funcionando. Script rodado duas vezes seguidas: `OK` nas duas.
- **Ordem:** este item entra **antes** de publicar a tela "Meus comprovantes".

### Item condicional — trabalhador rural (PONTO-113), parado por decisão

Não implementado **de propósito**: só compensa quando houver cliente do agro —
antes disso seria código mantido sem uso. Fica **parado e documentado**. Enquanto
nenhum vínculo for marcado como rural, todo o cálculo continua urbano como hoje
(risco zero para quem não é do agro). Escopo já medido, para não redescobrir:

- **Regra legal (Lei 5.889/73, três eixos ao mesmo tempo):** janela noturna
  **lavoura 21h–5h / pecuária 20h–4h** (urbano 22h–5h); adicional **25%** (urbano
  20%); **hora cheia de 60 min, sem hora ficta** (urbano usa a ficta de 52min30s).
- **Banco (uma onda pequena):** (1) campo de **regime** no vínculo/admissão
  (`urbano` [padrão] / `rural_lavoura` / `rural_pecuaria`), irmão do enquadramento
  do art. 62 que já vive em `admissoes` — fica no trabalhador, não na empresa
  (o mesmo empregador tem gente de campo e de escritório); (2) `calcular_he_adicional_noturno_dia`
  passa a aplicar os três eixos quando o vínculo é rural — a função **já sabe**
  usar janela/percentual/ficta parametrizados (hoje lê de `ponto_cct_config`),
  falta só ligar a fonte "rural" e o padrão legal; (3) caso funcional provando os
  três eixos juntos (lavoura e pecuária) com regressão zero no urbano.
- **Tela (Publicar no Lovable):** campo de enquadramento rural no cadastro do
  vínculo, para o RH marcar quem é rural. Sem ele, o banco funciona mas ninguém
  marca pela tela.
- **Decisões de produto pendentes:** confirmar as janelas legais lavoura/pecuária;
  default urbano para quem não tem enquadramento; e se a convenção coletiva pode
  sobrepor o piso rural (em regra só para melhorar) — este último é mais código.

## Regras gerais dos pacotes

- **Um pacote por vez, na ordem.** Cole o arquivo inteiro no SQL Editor, rode, e
  **olhe a última linha do resultado** (o editor só mostra o último) — ela é a
  conferência. Só passe ao próximo quando ela der `OK`.
- **Se a conferência não der `OK`,** pare e me mostre o resultado. Não siga
  adiante.
- **Nenhum destes pacotes exige "Publicar no Lovable".** Nenhum mexe em tela —
  são todos de banco. O passo do Lovable só aparece quando uma onda mexer em
  tela (a partir da onda 2, "desconsiderar em vez de apagar", e outras).

---

## O que NÃO faz parte deste roteiro

Existem em `docs/` dois scripts de ponto de **trabalhos anteriores**, fora deste
plano das ondas:

- `docs/script_ponto_controle_por_empresa.sql`
- `docs/script_ponto_correcoes_bateria_12ago.sql`

**Não sei o estado de produção deles** (podem já ter sido aplicados por outra
pessoa). Não os inclua nesta sequência sem confirmar com quem os escreveu — eles
não pertencem à jornada das ondas 0/1.

---

## Playbooks operacionais (não são pacotes de produção)

Notas de "se acontecer X, faça Y" — não entram na fila de produção; ficam
registradas para não se perderem.

### Corretor de RLS do QA — destrave do seed (hoje NÃO aplicável)

Existe um prompt-corretor (arquivo `CORRETOR-QA-DESTRAVE.md`, fora do repo) para
o caso de a RLS apertada (correção do vazamento de salários/admissões) voltar a
**bloquear as rotinas de *seed* do QA** — o sintoma seria uma **onda de "erro"**
na bateria com a mensagem *"new row violates row-level security policy"* ao
semear fixtures (não "falhou"). A correção proposta é tornar as funções de seed
`qa_*` **`SECURITY DEFINER` com trava obrigatória de sandbox**
(`IF tenant <> public.qa_sandbox_tenant_id() THEN RAISE`), **sem tocar na RLS
real** e re-provando que o colaborador comum não vê salário de colega.

- **Estado em 20/08/2026:** **não aplicável.** A bateria roda com **0 erros**
  (113 passou · 1 falhou · 6 sem rotina) e `admissoes` tem só políticas de INSERT
  **permissivas** — o seed não está travado. O corretor mira um estado que o
  sistema já superou.
- **Não rodar por prevenção:** converter ~50 funções para `SECURITY DEFINER` sem
  o bloqueio existir **eleva privilégio à toa** (aumenta a superfície de
  segurança). Só usar se o sintoma (onda de "erro" de RLS no seed) reaparecer.
- **Se um dia for usado:** a trava de sandbox precisa cobrir **todo alvo de
  escrita** dentro de cada função de seed (algumas gravam em várias tabelas), e é
  mudança de banco → migration + `docs/script_*.sql`, como as demais.

---

## Próximas ondas (ainda não entregues)

Conforme cada uma for entregue e validada no teste, ela entra na tabela acima
com seu pacote. A ordem prevista:

- **Onda 2** — registro imutável de verdade (correção por acréscimo, cadeia de
  hash, competência fechada). **Concluída no teste**, em cinco partes: cadeia de
  hash (#11), relógio/origem da batida (#12), marcações uniformes (#13),
  reabertura formal de competência (#14) e correção por acréscimo/desconsiderar
  (#15 banco + #15-tela). *A parte 5 tem componente de tela — o botão
  "Desconsiderar" entra por Publicar no Lovable.* A geração transacional dos
  espelhos (PONTO-194) fica como item próprio, a fazer.
- **Onda 3** — cálculo (hora extra, jornada da escala, tolerância, turno da
  virada, adicional noturno). *Onde está o dinheiro; agora segura, com o
  versionamento da onda 1 no lugar.* **Concluída no teste**, entregue em quatro
  partes: 1 (tolerância, #7), 2 (jornada da escala + hora extra sem truncar,
  #8), 3 (adicional noturno prorrogado, #9) e 4 (turno da virada, #10). Sete
  casos da bateria passaram a passar, regressão zero. O regime rural
  (PONTO-113) fica como evolução condicional a cliente do agro.
- **Onda 4** — intervalo, descanso e DSR. **Concluída no teste**, em cinco
  partes: parte 1 (faixas de intervalo, #16), parte 2 (supressão de intervalo,
  #17), parte 3 (pré-assinalação formal, #18), parte 4 (domingo em dobro, #19) e
  parte 5 (DSR + repouso semanal de 24h, #20). Sete casos da bateria passaram a
  passar na onda (062, 060, 061, 064, 130, 132, 133), regressão zero.
- **Onda 5** — banco de horas e escalas especiais. **Concluída no teste**, em
  seis partes: banco só com instrumento vigente (#21), prazo de vencimento do
  saldo (#22), alertas de vencimento e teto (#23), limite de 10h no regime (#24),
  liquidação na rescisão (#25) e a escala 12x36 por ciclo (#26). Oito casos da
  bateria passaram a passar na onda (170, 354, 171, 355, 356, 172, 173, 150,
  151), regressão zero.
- **Onda 6** — fechamento e folha. **Concluída no teste**, em cinco partes:
  geração transacional dos espelhos (#27), pendência crítica bloqueia o
  fechamento (#28), espelho sem ciência bloqueia (#29), pacote da folha com
  naturezas corretas (#30) e a fila com estados e reenvio idempotente (#31).
  Cinco casos passaram a passar na onda (194, 388, 387, 361, 398), regressão
  zero.
- **Onda 7** — arquivos legais e prova documental (REP-P/AFD/AEJ, certificado
  digital, dossiê de fiscalização). **Concluída no teste**, em cinco partes:
  comprovante como documento (#32) — a tabela `ponto_comprovantes`, a emissão
  idempotente com NSR e hash, a vigilância do prazo de 48h e a extração por
  período pelo próprio trabalhador (380, 381, 359); o AEJ — Arquivo Eletrônico de
  Jornada (#33) — a tabela `ponto_arquivos_aej`, o gerador a partir da apuração
  fechada em registros tipados e assinado, e a extração (211); a importação de AFD
  que confere (#34) — CRC-16, cadeia SHA-256, recusa por lacuna de NSR e
  quarentena, a chave natural de origem na marcação e a trilha dos eventos do
  equipamento (382, 383, 384, 212); a gestão do certificado digital (#35) — o
  cadastro ICP-Brasil por empresa, o certificado vigente que assina o `.p7s` e o
  alerta de vencimento (360); e o dossiê de fiscalização + arquivamento (#36) — o
  empacotador com índice e hashes e o arquivamento automático no módulo Documentos
  (392, 393). Onze casos passaram a passar na onda (380, 381, 359, 211, 382, 383,
  384, 212, 360, 392, 393), regressão zero.
- **Onda 8** — enquadramento (art. 62, teletrabalho) e prevenção (LGPD, plano de
  ação). **Concluída no teste (banco)**, em seis partes: o enquadramento do art. 62
  no vínculo (#37; casos 373, 374); o controle de fato que descaracteriza a
  dispensa (#38; caso 375); a obrigatoriedade do controle por estabelecimento acima
  de 20 (#39; caso 370); o sistema alternativo (REP-A) só com instrumento coletivo
  (#40; caso 213); a LGPD — trilha de auditoria de acesso a dado sensível e
  exportação, e a contenção de enumeração de CPF no link (#41; casos 397, 362); e a
  integração do Plano de Ação — alerta vira ação 5W2H, verificação de eficácia na
  conclusão, e a IA que sugere mas nunca decide (#42; casos 389, 390, 391). Dez
  casos passaram a passar na onda, regressão zero. **Correção pós-bateria (#43):**
  a bateria rodada no teste por um usuário de gestão pegou o PONTO-193 — uma
  competência fechada aceitava marcação de gestão sem reabertura (a "válvula" do
  guard de período); o pacote #43 remove a válvula e a competência fechada passa a
  bloquear todos, até a reabertura formal (#14, PONTO-358). *Cinco casos desta onda são de
  **tela** (comprovante após a batida, cerca que sinaliza sem bloquear, aviso de
  tratamento de dados, selfie como dado comum, e não restringir horário de
  marcação — 002, 005, 006, 254, 363): não têm rotina de banco e entram por
  Publicar no Lovable, fora desta esteira.*
- **Onda 9** — instrumento coletivo vigente na competência. **Concluída no teste
  (banco)**, em uma parte: a vigilância de vigência de CCT/ACT (#44; caso 386) —
  a apuração já escolhia o instrumento vigente na data apurada, e agora existe o
  alerta de vencimento (60/30 dias/vencido) e de sobreposição de vigências. Um
  caso passou a passar (386), regressão zero (112→113). **Com isso, o único caso
  de banco ainda em vermelho é o PONTO-113 (trabalhador rural)**, evolução
  condicional a cliente do agronegócio — os demais pendentes são casos de **tela**
  (Publicar no Lovable), fora desta esteira.

O plano completo, com o detalhe de cada onda, está no documento de planejamento
(artefato "Ponto Redondo").

---

## Pacote 53 — RN23: adicional de feriado (achado da bancada)

`docs/script_ponto_rn23_feriado_adicional.sql` — **entra no fim desta fila**, depois
do 52.

Não veio do planejamento: veio da **bancada de QA rodando na homologação** em
27/08/2026. Quatro casos (PONTO-131, 320, 321, 322) reprovaram com a mesma causa
— `function public.ponto_feriado_adicional_competencia(uuid, uuid, text) does not
exist`. A RN23 inteira (Lei 605/1949 art. 9º; Súmula 146 do TST) nasceu em duas
migrations e **nenhum script de entrega**, então nunca existiu na produção.

Efeito prático na produção hoje: feriado trabalhado sem folga compensatória é
tratado como jornada comum, **sem a dobra, em silêncio** — nenhum erro aparece, a
apuração apenas não encontra a função e o dia segue normal.

O pacote traz a tabela da folga compensatória, a tabela de exceção de feriado, a
coluna `ponto_escalas.comportamento_feriado` e a cadeia de apuração completa.

**Detalhe que a conferência salvou:** a primeira montagem copiava as duas
migrations na ordem cronológica, e a de 13/08 carrega uma versão de
`ponto_feriados_trabalhados` **anterior** à que a Onda 5 (12x36) instalou depois —
teria regredido o 12x36 que já está na produção. A prova em réplica pegou (o caso
PONTO-151 caiu). Por isso o pacote leva o **estado atual do projeto**, não o texto
das migrations.

Conferência esperada: `t | t | t | t | t | t | t | OK`. Depois dele, a bateria do
Ponto na homologação vai de 112 para **120 de 128** — sobrando apenas o PONTO-113
(regime rural), que é evolução de produto e falha no projeto também.

---

## Pacote 54 — link de marcação com prazo obrigatório (achado da bancada)

`docs/script_ponto_links_prazo_obrigatorio.sql` — entra depois do 53.

Segundo achado da bancada na homologação: **"De 248 link(s): data_expiracao
aceita NULO no schema"** (PONTO-251).

O link de marcação é uma credencial distribuída por mensagem — o colaborador
recebe a URL e bate ponto por ela. Sem prazo obrigatório na estrutura, um link
pode nascer sem validade e virar **acesso permanente ao ponto daquela pessoa**,
inclusive depois do desligamento. Proteção não pode depender de a consulta
lembrar de filtrar por data.

Os 248 links da produção estão todos preenchidos hoje — a auditoria não achou
nenhum ativo sem prazo, nenhum vencido ainda ativo, nenhum token curto e nenhuma
colisão. **Falta só a trava.**

O pacote preenche defensivamente quem estiver sem prazo, torna `data_expiracao`
obrigatória (DEFAULT 180 dias + NOT NULL), e traz quatro peças que só existiam
no ambiente de teste: o gatilho `trg_ponto_links_validade`, que preenche o prazo
na gravação, e as rotinas `ponto_links_desativar_vencidos`,
`ponto_links_revogar_desligados` e `ponto_link_renovar`. Sem elas o vencimento é
só um campo — ninguém age sobre ele.

Não revoga nem desativa nenhum link existente: fecha a porta para os próximos e
entrega as ferramentas de manutenção.

Conferência esperada: `t | t | 0 | 0 | t | t | OK`. (`vencidos_ativos` é
informativo — se vier maior que zero, é a fila de trabalho da rotina nova, não
reprovação.)

---

## Pacote 55 — as duas últimas da bateria (PONTO-191 e PONTO-354)

`docs/script_ponto_correcoes_bateria_homologacao.sql` — entra depois do 54.

Nenhum dos dois era defeito de comportamento. Os dois eram defeito de **entrega**
e de **ferramenta**, e só apareceram porque a bancada passou a rodar contra a
estrutura real, com dado de cliente por perto.

**PONTO-191.** A verificação da cadeia de hash existe na produção e está correta
(encadeada) — mas o caso reprovava. A sonda procura uma função cujo *corpo*
contenha "hash_marcacao" e "verific". A produção ficou com uma versão antiga da
função, cujo corpo não tem a segunda palavra. O pacote instala a versão atual do
projeto. É só a função de verificação, que apenas lê: não toca hash gravado, não
altera marcação, não mexe no gatilho de gravação.

**PONTO-354.** O caso quebrava com *"QA BLOQUEADO: ... tentou tocar o tenant
83f1b040-..."*. A trava do cercado funcionou — o problema é do teste: ele chama
`converter_banco_horas_vencido()`, que é global e varre todos os tenants. Numa
base sem dado de cliente isso nunca aparece; numa base com dado de cliente o
teste tenta tocar linha de terceiro e a trava aborta, como deve. O caso era
**inexecutável justamente onde a bancada mais precisa rodar**. A rotina ganha um
tenant opcional: sem argumento o comportamento é idêntico ao de hoje, com
argumento só aquele — e o caso escopa a conversão no cercado.

Provado em réplica: a conversão escopada converteu a linha do cercado e deixou a
do tenant real **intacta**; sem argumento continua varrendo todos.

**Observação de produto, fora deste pacote:** `converter_banco_horas_vencido` não
está agendada em lugar nenhum — nem cron, nem tela, nem outra função. Na prática,
saldo de banco de horas vencido **não está sendo convertido sozinho** na produção.

Conferência esperada: `t | t | t | t | OK`. Depois dele o Ponto fica em **119 de
128** — restando o PONTO-113 (regime rural, evolução de produto) e o PONTO-301
(refatoramento `_bruto`, decisão pendente).

---

## Pacote 56 — apuração em duas peças: núcleo + invólucro (PONTO-300/301)

`docs/script_ponto_apuracao_nucleo_e_involucro.sql` — entra depois do 55.

Encerra a divergência que mais custou caro nesta esteira. O projeto dividiu o
motor de apuração em duas peças há meses; a produção ficou com a peça única. Isso
já derrubou dois pacotes no ensaio: o **#7** teria falhado em voz alta
(`function ... does not exist`) e o **#26** teria falhado **em silêncio** — ele
procura um trecho para alterar, não acha, e segue sem mudar nada; na prática o
plantonista de 12x36 continuaria acumulando falta no dia de folga. Enquanto os
dois ambientes divergirem, todo pacote futuro que tocar a apuração corre o mesmo
risco.

**O núcleo é o mesmo motor que já roda na produção.** Comparado linha a linha com
o monolito remendado pelos pacotes #7 e #26, as únicas **11 linhas diferentes são
comentários** — nenhuma linha de código executável muda.

**O invólucro é fino e explícito:** dia que sai uma vez só passa intocado
(`linhas = 1 → saldo_unico`), sem nem arredondamento; dia duplicado vira uma
linha, com a mesma tolerância de 10 minutos da apuração.

A assinatura pública não muda — mesmos parâmetros, mesma tabela de retorno. Os
seis chamadores de banco e as telas continuam chamando a mesma função do mesmo
jeito. O núcleo entra antes do invólucro de propósito: o invólucro é `LANGUAGE
sql` e o banco valida o corpo na criação, então recusaria se o núcleo faltasse.

### Como foi conferido

Montou-se a homologação fiel numa réplica — o monolito da produção mais os
pacotes #7 e #26 — e ela reproduziu o retrato de lá exatamente (119 passou, 1
falhou, 1 erro, 7 sem rotina). Então:

1. **Os números da apuração não mudaram.** Fotografou-se a saída da função
   pública para **toda** combinação (tenant, CPF, competência) do banco — 602
   linhas — antes e depois da troca: **mesma impressão digital**.
2. **A bateria melhorou sem regredir:** 119 → **120 passou**, 0 erro. O PONTO-301
   passou (*"Sem duplicata, a saída pública é idêntica à bruta"*) e o PONTO-300
   (uma linha por dia civil) continuou de pé.
3. Segunda passada sem divergência, e as duas funções ficam com a mesma soma de
   verificação do projeto.

Conferência esperada: `t | t | t | t | t | t | OK`. Depois dele o Ponto fica em
**120 de 128** — sobrando apenas o PONTO-113 (regime rural), evolução de produto.

---

## Pacote 57 — a jornada prevista desconta o intervalo pré-assinalado

`docs/script_ponto_jornada_desconta_pre_assinalacao.sql` — **depende do pacote
18** (Onda 4 parte 3, que instala a pré-assinalação) e do pacote da Onda 1
(`ponto_escala_com_versao`).

Achado no cartão-ponto de agosto/2026 de um cliente real. A escala tem o
intervalo **declarado** por pré-assinalação — existe, mas não é batido. O cartão
saía assim, quase todo dia:

```
Marcações 08:00 18:00 | H.D. 9:00 | H.N. 10:00 | H.A. 1:00
Ocorrência: "Atraso / saída antecipada"
```

O trabalhado estava certo; a jornada **prevista** vinha com a janela crua, sem
descontar o intervalo. A diferença virava uma hora de ausência por dia, e um dia
integralmente cumprido era rotulado como atraso. No mês: **16:50 de ausência que
nunca existiu**.

A causa: `ponto_jornada_do_dia` só descontava o intervalo quando o próprio dia da
escala trazia o trio `tem_almoco` + `inicio_almoco` + `fim_almoco`. A tabela de
pré-assinalação nasceu marcada como "metadado de exibição; o motor de saldo não
lê" — o cartão imprimia o "(P)" e a apuração ignorava a declaração. E foi por
isso que as sextas saíam certas e o resto da semana não: naquele dia a escala
tinha a janela de almoço preenchida.

A jornada passa a descontar por precedência: janela de almoço do dia, minutos de
intervalo do dia, pré-assinalação vigente. **Não** há um quarto passo caindo para
`ponto_escalas.intervalo_intrajornada_minutos`: a tela cria toda escala com esse
campo em 60 por padrão, então uma escala cuja janela já exclui o almoço
(08:00–16:00) passaria a perder mais uma hora.

**Este arquivo se recusa a aplicar sem os pré-requisitos.** O PostgreSQL não
valida o corpo de uma função plpgsql na criação: sem a guarda, ele instalaria com
sucesso uma função que quebraria na primeira apuração, derrubando o ponto de
todos os clientes. Provado em réplica: onde a rotina de pré-assinalação não
existe, a função **antiga fica intacta** e a conferência sai
`f | t | f | PRE-REQUISITO FALTANDO`.

Não altera dado nenhum: troca uma função de leitura. O relatório lê a apuração ao
vivo, então não é preciso reprocessar competência — basta gerar o cartão de novo.

Provado em réplica com a escala do relatório (seg–qui 08:00–18:00, sexta
08:00–17:00, 60 min declarados): **antes** 600/540 minutos, **depois** 540/480 —
as 44h da semana. Não-regressão: escala 08:00–16:00 sem declaração continua em
480, não perde hora nenhuma.

Conferência esperada: `t | t | t | OK`.

---

## Pacote 58 — regrava a jornada gravada nas escalas com intervalo declarado

`docs/script_ponto_escalas_regrava_jornada_declarada.sql` — **depende do pacote
18**. Independe do 57, mas faz sentido logo depois dele.

Companheiro do 57. Aquele corrige o **motor**; este corrige o **número gravado**
na escala. O motor não usa esse número quando há configuração por dia, mas ele
vaza para dois lugares que importam:

1. **O AEJ** (Arquivo Eletrônico de Jornada, Portaria MTP 671/2021): o registro
   Tipo 4 "Horários contratuais" carrega a carga diária. Declarar 9h48 onde o
   contrato é 9h é erro de conformidade, não detalhe de tela.
2. A base da **cobertura por atestado** e do **teto diário (RN17)**, quando os
   blocos previstos do dia não estão disponíveis.

Só é tocada a escala que (a) tem configuração por dia, (b) tem declaração
**vigente hoje** e (c) cujo número gravado difere da conta correta. Escala sem
declaração **não** é tocada: ali a janela crua é mesmo a jornada, e mexer seria
inventar um intervalo que ninguém declarou.

**O gatilho de versão é suspenso durante a regravação.** `ponto_escalas` tem um
gatilho que arquiva os parâmetros antigos quando a jornada muda, com vigência até
ontem — e a apuração de datas passadas passa a ler esse arquivo. Isso existe para
edição de verdade. Aqui **não houve mudança de contrato**: o contrato sempre foi
9h, o sistema é que guardava a conta errada. Arquivar "9h48 vigorou até ontem"
afirmaria sobre o passado uma coisa que nunca foi verdade, num arquivo que
alimenta a apuração. O gatilho é religado no mesmo bloco; se algo falhar, a
transação inteira volta atrás e o gatilho volta junto.

Guarda as linhas antes em `backup_ponto_escalas_20260916` (cópia integral — a
tabela é pequena), e o comando que desfaz está no rodapé do próprio arquivo.

Provado em réplica, com três escalas lado a lado: a que tem declaração e almoço
não batido foi de **588/2940 para 528/2640**; a **sem declaração** ficou intacta
em 600/3000; a **com almoço batido** ficou intacta em 480/2400 (a declaração não
desconta em dobro). Nenhuma linha de versão foi criada. Segunda execução não
mexe em nada, e o comando de desfazer devolveu os 588/2940 originais. Em ambiente
sem a tabela de pré-assinalação o arquivo pula com aviso legível, sem erro.

Conferência esperada: `t | t | t | 1 (ou mais) | OK`.

---

## Depois desta fila: a bancada de QA

Esta fila leva **o comportamento corrigido** para a produção — mas não leva **a
bancada que comprova o comportamento**. Dos 51 scripts de entrega do Ponto, só 4
criam alguma rotina de teste e nenhum registra a ponte caso→rotina; as 114
rotinas do Ponto nasceram em migrations, que nunca alcançam a produção. Medido na
homologação: o projeto tem 121 casos do Ponto com rotina ligada, a produção tem
**15**.

Por isso existe uma segunda trilha, em `ROTEIRO_PRODUCAO_BANCADA_QA.md`, com 15
pacotes que levam catálogo, rotinas e pontes de todos os módulos.

**Ela vem depois desta.** Se a bancada do Ponto entrar antes dos 52, a bateria na
produção acende vermelho em dezenas de casos — corretamente, porque o
comportamento ainda não foi corrigido lá. Comportamento primeiro, bancada depois:
aí a bateria nasce verde e vale como prova do que foi entregue.
