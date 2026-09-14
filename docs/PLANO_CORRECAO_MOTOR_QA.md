# Plano de correção — Motor de QA (relatório 13/09/2026)

> Base: `relatorio_qa_todos_13-09-2026_11-00-13` — execução "Todos os módulos".
> Resultado: **528 passou · 167 falhou · 3 erro · 709 sem rotina** (total 1407).
> **170 falhas para correção.**
>
> Fluxo: corrigir primeiro em **desenvolvimento** (migrations no repositório → esteira
> aplica no STAGING a cada merge) e depois transferir o **mesmo** conteúdo para
> **homologação** como script de entrega colado à mão (decisão 09/2026, forward-only).
> A produção segue intacta até aprovação explícita.

---

## 0. Progresso (atualizado 13/09/2026)

Ambiente de desenvolvimento (migrations no repositório, validadas em réplica local
com as 1009 migrations e cada caso isolado como o motor real faz — `qa_executar_descartavel`
— com diff caso a caso contra o "antes" para provar que não há regressão):

- **Fase 0 — concluída (4):** AFAST-020, AFAST-031 (regressão de 24/07), FERIAS-056, DESL-003.
- **Fase 1 — concluída (46 casos + 1 ganho colateral):**
  - Batch 1 (Metas/Plano/Hub): MCHK-010/011, MPAR-011, MEVD-010, PLTP-010, PLTM-010,
    PLTF-010/011, PLEV-010, PDOC-010, PCHK-010, PROC-010/011, HTPL-010, HCAT-010, HCAL-012.
  - Batch 2 (Empresa/Enq/Feriados/TAC/Cert): EMP-020/021/070/071, DADO-010, HIER-002,
    FER-002/003/004, ENQ-010/011/013, TAC-003, CERT-010/011.
  - Batch 3 (Adm/Afast/EPI/Férias): ADM-020, AFAST-011, AFAST-051, EPI-020, EPI-030,
    FERIAS-013/014/052.
  - Batch 4 (Colab/Idade): COLAB-025/027/029/033, ADM-030, DESL-083 (+ EMP-060, ganho colateral).
- **Pendente da Fase 1:** **ADM-031** (idade × risco da função/turno) foi remetido à
  fase de SST, porque depende do modelo de riscos por função (ainda a estruturar).
- **Fase 2 — concluída (perfil/LGPD/log clínico):** DESL-110, FOLHA-090, EPI-041, SST-041
  (políticas RESTRICTIVE `perfil_restringe_leitura_*`) + `log_acesso_clinico` e
  `ler_cid_clinico()` (AFAST-080, SST-080).
- **Fase 3 — concluída em lotes:**
  - Férias lote 1 (estrutura e prazos): FERIAS-091/008/016/010/040/031/042.
  - Férias lote 2 (pontes): FERIAS-003 (art. 133), FERIAS-024 (afastamento suspende),
    FERIAS-053 (ponto barrado em gozo).
  - EPI/SST vencimentos: EPI-011/022/050/052, SST-001/011/020/021.
  - **Admissão/Cota + Benefícios (11):** ADM-040 (motor da cota de aprendiz),
    ADM-041 (enquadramento PcD/reabilitado alimentando o realizado), BEN-001/010/011/012/
    020/050/051/060 (elegibilidade, termo, VT, teto PAT, ponte Folha, proporcional Ponto,
    CCT) + EMP-053 (categoria reabilitado do INSS, ganho colateral legítimo).

**Estado confirmado no ambiente de teste (relatório 13/09 19:16): 614 passou · 84 falhou
· 0 erro.** As 170 falhas originais caíram para 84, sem nenhuma rotina quebrando (erro=0).
As 5 falhas BEN restantes (030/040/042/070/071) são exatamente os subsistemas adiados de
propósito — confirmando que o lote Admissão/Cota + Benefícios entrou verde.

**Artefato de heurística ainda em aberto:**
- **AFAST-060** marca verde porque a auditoria casa a palavra "prazo" em qualquer função,
  e a guarda de status passou a citar `prazo_indeterminado`. O **motor de prazos do
  S-2230 continua pendente (Fase 4).** (ADM-040 deixou de ser artefato: agora tem motor
  real da cota de aprendiz.)

**As 84 falhas restantes, por família:** ADM (11: 021/022/031/050/051/052/070/071/072/073/
107), AFAST (7), BEN (5 estruturais adiados), DESL (5), EPI (7), FERIAS (7), FOLHA (6),
MKY/Marketplace (16), SST (9), REGRA (6: obrigações automáticas), + MCHK-002, MWKF-011,
PERFIL-003, PGP-014, PONTO-113.

Nada foi aplicado em homologação ou produção. As migrations só chegam ao ambiente de
teste quando a mudança for registrada na `main`.

---

## 1. Como ler este plano (método)

Cada caso do Motor é uma rotina `qa_caso_<código>()` que **simula** uma operação e
compara o comportamento do banco com a regra (legal ou de negócio). Quando o sistema
não impede o que deveria, a rotina devolve `falhou` e — este é o ouro — o próprio campo
`obtido` traz **o ACHADO** (o que está errado) **e a Correção sugerida**. A fonte da
verdade técnica de cada item, portanto, é a rotina na migration, não o PDF (o PDF traz o
"porquê importa" e os passos de reprodução).

Consequência importante: **muitas falhas não são bugs, são ausências de estrutura**. O
Motor está cobrando regras que o sistema ainda não implementa. Por isso o trabalho vai de
`CHECK` de uma linha a subsistemas inteiros — e é isso que o plano organiza.

---

## 2. Panorama por natureza do conserto

As 170 falhas se agrupam em **seis naturezas**, que definem esforço, risco e ordem:

| Natureza | O que é | Esforço | Risco | Nº aprox. |
|---|---|---|---|---|
| **A. Guarda de integridade** | `CHECK`/`UNIQUE`/`EXCLUDE`/FK/trigger de recusa: o banco passa a não aceitar dado impossível | baixo | baixo | ~45 |
| **B. Regressão conhecida (24/07)** | bug real: a reescrita do gatilho de afastamento moveu lógica para `AFTER` e perdeu escritas na própria linha | baixo | baixo | 2 |
| **C. Camada de perfil / LGPD** | política `perfil_restringe_leitura_*` + log de acesso a dado sensível — padrão maduro (23 tabelas já cobertas) | médio | baixo | ~6 |
| **D. Motor sobre parâmetro existente** | o parâmetro já está cadastrado e ninguém o consome: falta o gatilho/rotina de cálculo ou alerta (pg_cron) | médio | médio | ~15 |
| **E. Motor de prazos do eSocial** | data-limite + alerta + geração de evento na fila, compartilhado por vários módulos | médio-alto | médio | ~6 |
| **F. Subsistema estrutural novo** | tabelas/modalidades que não existem (dependentes, planos/faturas, intermitente, PPP, folha complementar…) | alto | alto | ~55 |
| **MarketYE** | módulo novo (set/2026): isolamento entre empresas, moderação, ciclo do anúncio, LGPD | médio-alto | médio | 16 |

> Os números somam mais que 170 porque alguns casos têm "metade boa, metade faltando" e
> aparecem em duas naturezas (ex.: um dado que existe mas sem trava + sem motor).

---

## 3. Mapa de vínculos entre módulos (ler antes de sequenciar)

O relatório expõe **dependências reais** que precisam guiar a ordem. As principais:

- **Cadeia SST de extração** (a mais crítica de sequência):
  `SST-002` (tabela estruturada de dados extraídos do documento, revisão humana) é a
  **fundação**. Sem ela não saem: `SST-003` (medidas do PGR → Plano de Ação),
  `SST-010` (OS por função), `SST-031` (exposição/S-2240), `SST-050` (enquadramento →
  adicional na Folha), `SST-060` (PPP), `SST-070` (coerência documental). **Fazer SST-002
  primeiro; o resto pende dele.**

- **Cadeia previdenciária de exposição:** `SST-031` (S-2240) → `SST-060` (PPP no
  desligamento). "Exposição não registrada em 2026 é benefício negado em 2046."

- **Motor de prazos do eSocial (um motor, vários clientes):** `AFAST-060` (S-2230),
  `SST-030` (S-2220), `DESL-093` (S-2299), `ADM-071` (S-2200 retroativo) e as referências
  a `FOLHA-060`/`DESL-091`. Todos pedem **data-limite calculada + alerta + marcação de
  "fora do prazo"**. Construir **uma vez** o motor de prazos e ligar cada evento a ele.

- **Idade × modalidade/risco (fonte única `data_nascimento`):** `ADM-030` (menor de 16),
  `ADM-031` (menor de 18 × risco/turno), `DESL-083` (quitação de menor com assistente).
  Mesmo dado, três travas — fazer juntas.

- **Cota (mesmo desenho):** `ADM-041` (PcD, motor JÁ existe: `recalcular_cota_pcd`) é o
  **modelo** para `ADM-040` (aprendiz, sem motor) e para as obrigações `REGRA-001` (déficit
  PcD). Espelhar o gatilho existente.

- **Benefícios ↔ Folha ↔ Ponto:** `BEN-020` (adesão → rubrica na folha) e `BEN-050`
  (proporcional aos dias do Ponto) dependem da ponte para `folha_rubricas`/`folha_itens` e
  de `ponto_saldo_dias_competencia_bruto` (que Férias já consome). `BEN-030` (dependentes)
  é pré-requisito de `BEN-042` (conciliação de fatura por vida) e do IRRF.

- **Férias ↔ Afastamentos ↔ Ponto:** `FERIAS-003` (afastamento longo reinicia aquisitivo),
  `FERIAS-024` (afastamento sobre férias suspende), `FERIAS-053` (em gozo bloqueia ponto).
  A ponte férias→afastamentos não existe e é citada nos três.

- **Estabilidade (Afastamentos → Rescisão):** `AFAST-031` (acidente, `data_fim_estabilidade`)
  e `AFAST-040` (gestante, "parto + 5 meses") alimentam as travas de dispensa do módulo
  Desligamento (`DESL-070/071/077`). A regressão do AFAST-031 hoje deixa a estabilidade
  "sem vencimento".

- **Assinatura/Documentos (infra madura, reaproveitar):** o fluxo de assinatura com trilha
  da experiência (`experiencia_assinatura_links`) e a guarda no módulo Documentos servem a
  `ADM-070`, `BEN-060`, `EPI-042/044`, `SST-040` (atas). Estender, não reinventar.

- **Disciplina "período fechado / reversão com dupla aprovação"** (mesmo desenho em 4
  módulos): `FOLHA-071`, `DESL-106`, `FERIAS-051/052`, `DEC13-070`. Padrão único de
  reabertura com motivo + dupla aprovação + trilha.

- **Folha complementar / dissídio retroativo** (mesmo vazio em 3 módulos):
  `FOLHA-070`, `DESL-105`, `DEC13-033`. Tipo de período + referência à competência-mãe.

- **EPI ciclo físico:** `EPI-020` (saldo ≥ 0) ⟶ `EPI-021` (FEFO) ⟶ `EPI-040` (vencido não
  sai) ⟶ `EPI-043` (baixa só após assinatura). Encadeados; fazer na ordem do saldo.

---

## 4. Plano em fases

Norte: **"fazer o sistema funcionar por completo nas operações básicas"**. Traduzido em
prioridade: primeiro o que **impede dado impossível e corrige bug real** (barato, protege
a base), depois **LGPD/acesso** (exposição legal alta), depois **motores sobre o que já
existe**, e por fim **subsistemas novos** (maiores, alguns dependem de decisão jurídica).

Cada fase é uma ou mais **entregas** = `migration` (vai ao staging) **+** `docs/script_*.sql`
(homologação/produção), e termina com a **bateria do Motor** da família rodada no staging.

### Fase 0 — Regressões e travas de auto-aprovação (rápida, alto valor)
Bug real e travas de uma linha que protegem operação diária.
- **AFAST-020, AFAST-031** — devolver a mudança de status (`aguardando_inss`) e a gravação
  de `data_fim_estabilidade` ao gatilho `BEFORE` (`afastamento_campos_before`). É a
  regressão da reescrita de 24/07 (a inteligência foi para `AFTER`, que não altera a
  própria linha). Reabilita a tela de INSS e a leitura de estabilidade pela Rescisão.
- **FERIAS-056** — `CHECK (aprovado_por IS NULL OR aprovado_por <> colaborador_id)` em
  `ferias_solicitacoes` (espelha `chk_ajuste_sem_autoaprovacao` do Ponto).
- **DESL-003** — trigger que recusa dispensa imotivada com afastamento ativo.

### Fase 1 — Guardas de integridade (natureza A, em lote por módulo)
`CHECK`/`UNIQUE`/`EXCLUDE`/FK que fazem o banco recusar o impossível. Baixo risco, alto
volume. Uma migration por família:
- **Admissão:** ADM-020 (experiência ≤90 e soma ≤90).
- **Afastamentos:** AFAST-011 (`EXCLUDE USING gist` de período por colaborador),
  AFAST-051 (suspensão disciplinar ≤30 dias).
- **Empresas/Cadastro:** EMP-020/021/070/071 (CNPJ/CPF ativo único; inativa duplicada ok),
  DADO-010 (`tipo_pessoa` só PJ/PF), HIER-002 (apagar grupo preserva empresa — conferir se
  já `SET NULL`), FER-002/003/004 (tabela de feriados: troca substitui, sem ambiguidade,
  sem vincular tabela de outro cliente).
- **Enquadramento/SST cadastro:** ENQ-010 (FAP ≤2,0), ENQ-011 (grau de risco ajustado exige
  justificativa), ENQ-013 (mandato CIPA fim≥início), TAC-003 (vigência TAC fim≥início),
  CERT-010/011 (emissão antes da validade; irregular não vira válida sozinho).
- **EPI estoque:** EPI-020 (`CHECK quantidade_estoque >= 0` + conferência no gatilho),
  EPI-030 (`UNIQUE (tenant, chave_acesso)` + `CHECK` 44 dígitos).
- **Férias:** FERIAS-013 (saldo), FERIAS-014 (início 2 dias antes de feriado/repouso),
  FERIAS-052 (data confirmada só muda com justificativa).
- **Hub/Processos/Metas/Plano de Ação:** HCAT-010 (retenção ≥0), HCAL-012/MCHK-011/PROC-011
  (não apontar para outro cliente), MCHK-010 (progresso 0–100), MPAR-011 (peso positivo),
  PROC-010 (prazo ≥ referência), HTPL-010 (tipo casa com enum), PLTF-010 (dependência
  circular), PLTF-011 (tarefa não depende de tarefa de outra ação), PLTM-010 (apontamento
  fim≥início), PLTP-010 (template com estrutura de ação), PDOC-010 (versão do mesmo
  processo), PLEV-010 (evidência de tarefa da própria ação), MEVD-010 (evidência não vazia),
  PCHK-010 (concluir com item obrigatório aberto — trigger de recusa),
  MWKF-011/MCHK-002 (conferir se já passam; podem ser efeito de outra correção).
- **Colaborador/vínculo:** COLAB-025 (2º vínculo ativo na mesma empresa recusado),
  COLAB-027 (vínculo suspenso ocupa vaga), COLAB-029 (papel duplo permitido — conferir),
  COLAB-033 (CPF com formatação diferente = mesma pessoa).
- **Idade (fonte única):** ADM-030, ADM-031, DESL-083 — travas idade × modalidade/risco/turno
  e assistente do menor na quitação.

### Fase 2 — Camada de perfil e log de acesso (LGPD, exposição alta)
Padrão `perfil_restringe_leitura_*` (modelo: `beneficios_onda0_lgpd_rls.sql`) + log
append-only via `SECURITY DEFINER`.
- **DESL-110** — `folha_rescisoes` (verbas, motivo, justa causa) fora da camada.
- **FOLHA-090** — `folha_itens` legível por qualquer autenticado → por papel (manager+) ou
  próprio holerite.
- **EPI-041** — `epi_entregas` (biometria facial) sem restrição nem log.
- **SST-041** — canal de assédio (Lei 14.457): restrição própria de fluxo + prazo de
  tratativa vigiado.
- **AFAST-080 + SST-080** — RLS do CID/clínico já existe; falta o **log de acesso**
  (leitor, titular, registro, hora) em tabela append-only. Uma função de leitura serve aos
  dois (CID e exames).

### Fase 3 — Motores sobre parâmetro que já existe (natureza D)
O parâmetro está cadastrado e ninguém consome. Ligar o consumo:
- **ADM-040** — cota de aprendiz: espelhar `recalcular_cota_pcd` (gatilho por faixa +
  realizado das admissões de aprendiz).
- **ADM-041** — enquadramento PcD/reabilitado na admissão alimentando o realizado.
- **FERIAS-070** — encargos por enquadramento (Simples Anexo III × IV) lendo
  `ferias_config.simples_dispensa_patronal`.
- **FERIAS-071** — alerta de cobertura (% máx. simultâneo por depto — alerta, nunca bloqueio).
- **EPI-011** — pg_cron marca CA vencido no catálogo + alerta de renovação.
- **EPI-022** — mínimo atingido → ação de reposição no Plano de Ação.
- **EPI-050** — data de troca = entrega + periodicidade + rotina de vencimento.
- **EPI-051** — kit de admissão em função de risco vira pendência.
- **EPI-052** — checklist de devolução no desligamento (rescisão segue de qualquer forma).
- **SST-001** — pg_cron marca PGR/PCMSO/laudo vencido + janela 60/30.
- **SST-020** — próxima data do periódico = último ASO + periodicidade + alertas.
- **SST-011** — trava de CA vigente na entrega (par do EPI-040).
- **FERIAS-003, FERIAS-024, FERIAS-053** — ponte Férias↔Afastamentos↔Ponto.
- **FERIAS-004, FERIAS-040, FERIAS-008, FERIAS-010, FERIAS-016, FERIAS-030, FERIAS-031,
  FERIAS-042, FERIAS-051, FERIAS-015** — vínculo formal programação→período aquisitivo,
  carimbo do requerimento de abono, prescrição, concordância do fracionamento, aviso 30
  dias, cancelamento que devolve dias. (Muitos são campo + trava; alguns tocam natureza A.)

### Fase 4 — Motor de prazos do eSocial (compartilhado)
Construir **uma vez**: data-limite por evento/motivo, alerta de aproximação, marcação
explícita de "FORA DO PRAZO", geração na fila `esocial_transmissoes` com anti-duplicidade.
Ligar: **AFAST-060** (S-2230), **SST-030** (S-2220), **DESL-093** (S-2299),
**ADM-071** (S-2200 retroativo + justificativa em trilha), **AFAST-030** (prazo da CAT =
1º dia útil, usa `feriados`).

### Fase 5 — EPI: ciclo físico e prova de entrega
Encadeado (saldo → FEFO → vencido → assinatura):
- **EPI-021** (FEFO na saída), **EPI-040** (vencido não sai), **EPI-043** (baixa só após
  assinatura; INSERT reserva), **EPI-042** (hash de integridade do recibo — `extensions.digest`),
  **EPI-044** (arquivar recibo no módulo Documentos), **EPI-010** (consulta CAEPI — edge
  function; pode ficar por último por depender de base externa).

### Fase 6 — Folha: versionamento, fechamento e complementar
- **FOLHA-001** (rubrica sem classificação = "incompleta", trava o cálculo),
  **FOLHA-002** (vigência/versão da rubrica, como `folha_tabelas_inss/irrf`),
  **FOLHA-030** (desconto exige rubrica classificada + teto por tipo),
  **FOLHA-071** (defender competência fechada + reabertura com dupla aprovação),
  **FOLHA-081** (comparativo de variação atípica antes do fechamento),
  **FOLHA-070 + DESL-105** (folha/rescisão complementar: tipo + competência-mãe).

### Fase 7 — Benefícios: motor e estrutura
- **BEN-001** (elegibilidade lida na adesão), **BEN-010/011/012** (VT/VR: termo, teto 6%,
  teto PAT), **BEN-020** (adesão → rubrica), **BEN-050** (proporcional ao Ponto),
  **BEN-051** (CCT × vigência), **BEN-060** (termo assinado no Documentos).
- **Estrutural:** **BEN-030** (dependentes) → **BEN-042** (operadoras/planos/faturas/
  conciliação) e **BEN-040** (arts. 30/31, prazo de 30 dias). **BEN-070** (PLR) e
  **BEN-071** (consignado) só quando houver programa/convênio.

### Fase 8 — Afastamentos: matriz de efeitos e espécies
- **AFAST-010** (tabela tipo→efeito: interrupção/suspensão, FGTS/tempo, código Tabela 18,
  vigência) — base para **AFAST-032** (FGTS por tipo) e o reflexo na folha (AFAST-022).
- **AFAST-040** (maternidade: adesão Empresa Cidadã + estabilidade gestante "parto+5m").
- **AFAST-050** (catálogo do art. 473 com incisos/dias/frequência).
- **AFAST-021** (recaída: prazo do S-2230 no 1º dia), **AFAST-070** (encerramento retido
  sem ASO de retorno).

### Fase 9 — Admissão: modalidades e ciclo de conclusão
- **ADM-070** (conclusão condicionada a contrato assinado — estender assinatura da
  experiência), **ADM-072** (conclusão condicionada a ASO apto),
  **ADM-050** (VT: opção/renúncia estruturada), **ADM-051** (salário × piso da CCT),
  **ADM-052** (checklist parametrizável), **ADM-073** (retenção/descarte de candidato —
  LGPD), **ADM-107** (ASO admissional como documento de saúde), **ADM-021** (prazo
  determinado estruturado), **ADM-022** (intermitente).

### Fase 10 — SST: cadeia de extração e conformidade documental
Ordem obrigatória: **SST-002** (extração estruturada + revisão humana) →
**SST-003** (medidas → Plano de Ação), **SST-010** (OS por função),
**SST-031** (exposição/S-2240) → **SST-060** (PPP no desligamento),
**SST-050** (enquadramento → adicional; neutralização por EPI/CA),
**SST-070** (coerência PGR/PCMSO/LTCAT/ASO), **SST-021** (ASO de mudança de função),
**SST-040** (dimensionamento CIPA Quadro I + atas). Conecta com REGRA-002/003/004/006 e
DESL (dossiê/PPP).

### Fase 11 — Desligamento (completar)
- **DESL-015** (pagamento × prazo art. 477 + multa §8º + antecipação por dia não útil),
  **DESL-025** (justa causa/indireta com validação de perfil competente),
  **DESL-106** (reversão com dupla aprovação e estorno rastreado),
  **FERIAS-090/091** (rescisão liquida férias vencidas+proporcionais+1/3; dois vínculos
  segregados).

### Fase 12 — MarketYE (trilha própria, módulo novo)
16 casos, em blocos:
- **Isolamento (RLS):** MKY-071 (terceiro não lê/escreve conversa/lead), MKY-082
  (autocompra), MKY-121 (ação com origem marketplace visível só ao dono).
- **Ciclo do anúncio:** MKY-052 (preço >0 ou sob orçamento), MKY-053 (pausar/retomar/
  remover), MKY-054 (promoção só na vigência), MKY-068 (vitrine só ativo×publicado, sem PII).
- **Moderação/devido processo:** MKY-042 (denúncia→remoção pelo superadmin), MKY-046 (IA só
  sinaliza; nada automático), MKY-087 (avaliação moderada sai da vitrine e da média),
  MKY-072 (recusa "não vou atender" encerra sem ocorrência).
- **LGPD:** MKY-037 (mascarar contato na bio), MKY-090 (exportar só o que é meu),
  MKY-092 (exclusão com conversa aberta anonimiza), MKY-093 (nova versão de termos exige
  novo aceite).
- **Config:** MKY-101 (pesos normalizados a 100%). E **PGP-014** (sugestão de parceiro por
  proximidade) na trilha de Parceiros.

---

## 5. Itens que dependem de decisão jurídica/negócio ([VAL] / [RCC] / [BPR])

As rotinas marcam onde o número/regra é decisão do dono do produto ou jurídico — **não
inventar**. Levantar antes de implementar a fase correspondente:
- Prazos/valores: retenção de candidato (ADM-073), antecedência de alertas EPI/SST
  (EPI-011/050, SST-001/020), teto PAT do VR (BEN-012), margem consignável (BEN-071),
  guarda da ficha de EPI (EPI-044).
- Matrizes: efeito por tipo de afastamento e FGTS (AFAST-010/032), regra exata da recaída
  (AFAST-021), hipóteses/dias do art. 473 ampliadas por CCT (AFAST-050 [RCC]).
- Cláusulas: contrato intermitente (ADM-022), neutralização de insalubridade por EPI
  (SST-050).
- [BPR] (boa prática, não obrigação): variação atípica da folha (FOLHA-081), coerência
  documental (SST-070), cobertura de férias (FERIAS-071).

---

## 6. Mecânica de entrega e verificação (por lote)

Para **cada** entrega, seguindo as regras da casa:
1. **Migration** em `supabase/migrations/` (carimbo único) — vai ao staging no merge.
2. **Script de entrega** `docs/script_*.sql` — idempotente, `IF NOT EXISTS`, blocos `DO`
   com `EXCEPTION` por item, sem aspas-dólar em comentário, uma conferência `SELECT` no
   fim. Script que ALTERA/APAGA dado guarda `backup_<assunto>_<aaaammdd>` antes.
3. **Réplica local** (PostgreSQL + stubs) roda todas as migrations sem erro.
4. **Bateria do Motor** da família no staging (`qa_rodar_bateria('manual','<módulo>')`) —
   os casos daquele lote precisam virar `passou`.
5. **Fechar a entrega** com o link do staging, o que conferir na tela e a conferência SQL
   do projeto de TESTE; **produção intacta**; esperar "aprovado".
6. Depois de aprovado no teste, o **mesmo** script vai para **homologação** e, só então,
   para produção.

> Antes de implementar cada fase, **rerodar a bateria da família** no staging: o relatório é
> de 13/09 e há commits recentes (MarketYE); alguns casos podem já ter mudado de estado.
> Confirmar o "antes" evita corrigir o que já passou.

---

## 7. Ordem recomendada de execução

Fase 0 → Fase 1 → Fase 2 → (3,4,5 em paralelo por serem famílias independentes) →
6 → 7 → 8 → 9 → 10 → 11 → 12.

Racional: 0–2 são baratas, de baixo risco e protegem a base e a LGPD imediatamente
(operação básica confiável). 3–5 ativam o que já está cadastrado (ganho grande, esforço
médio). 6–11 são os subsistemas por módulo, na ordem em que se destravam. 12 (MarketYE)
corre em paralelo por ser módulo isolado.
