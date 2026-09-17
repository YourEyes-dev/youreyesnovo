# Relatório de achados — motor de QA (auditoria de conformidade)

**Data:** 17/09/2026 · **Origem:** bateria completa do motor de QA rodada em
**produção** e **homologação** (só leitura, por simulação com descarte). Cada
achado tem um **código** rastreável e, quase sempre, a **base legal**.
**Sem dado pessoal** — só contagens e a natureza do gap.

Como ler: **homologação** tem massa de teste rica e exercita mais casos, então
lista mais achados; **produção** confirma um subconjunto contra **dados reais**
(marcados com 🟢 **confirmado em produção**, alguns com números). Um gap que só
aparece em homologação é igualmente real — só não teve dado que o disparasse na
produção ainda.

> Severidade é sugestão minha para triar. Ao todo, ~90 achados.
>
> **Progresso (17/09/2026):** ✅ **4 resolvidos em produção** — o eSocial das duas
> pontas do vínculo (S-2200 admissão `ADM-090`, S-2299 desligamento `DESL-091`),
> a qualificação cadastral (`ADM-092`) e a tradução de rejeição (`ADM-093`), com
> os gatilhos blindados. Correções aplicadas com validação prévia e sem tocar em
> dado existente (só colunas novas + eventos).

---

## 🔴 TEMA 1 — eSocial não sai (compliance, o mais grave)

O sistema não gerava os eventos do eSocial na linha da vida do vínculo.

### ✅ RESOLVIDOS (17/09/2026 — em produção)

| Evento | Código | O que entrou |
|---|---|---|
| **S-2200** admissão | `ADM-090` | ✅ gerador + gatilho (novas admissões geram S-2200; 10.541 históricas registradas sem transmitir) |
| **Qualificação cadastral** | `ADM-092` | ✅ `admissao_qualificacao_cadastral` (CPF×nome×nascimento antes do envio) |
| **Tradução de rejeição** | `ADM-093` | ✅ `esocial_rejeicao_traduzir` (código → instrução; conduz retificação) |
| **S-2299** desligamento | `DESL-091` | ✅ gerador + gatilho (novos desligamentos geram S-2299; históricos registrados sem transmitir) |
| **S-2230** afastamento | `AFAST-060` | ✅ prazo por duração + gerador + gatilho blindado + backfill `historico` |
| **S-2210** CAT (acidente) | `AFAST-030` | ✅ gatilho preenche o prazo = 1º dia útil seguinte (art. 22, Lei 8.213); função de calendário entregue junto (drift) |
| **S-2220** monitoramento saúde | `SST-030` | ✅ prazo do S-2220 (dia 15 do mês seguinte ao ASO) — camada fase-4 SST entregue |
| **S-2240** cond. ambientais | `SST-031` | ✅ histórico de exposição estruturado + geração do S-2240; coerência documental `SST-070` (PGR×PCMSO×LTCAT×S-2240) |
| Gatilhos de eSocial | — | ✅ **blindados** (nunca travam a operação) |

> Decisão de compliance aplicada: os eventos **históricos** entram como `historico`
> (contam, mas **não transmitem** ao governo); só os **novos** transmitem.

### ✅ Frente eSocial "sem relógio" — fechada

Todos os eventos da linha da vida do vínculo agora carregam relógio (prazo/
data-limite), gerador e gatilho blindado. A entrega da **camada fase-4 de SST**
(`script_fase4_sst_extracao_e_motores.sql`) fechou de quebra a família SST
inteira (15/15 casos verdes): extração estruturada, PGR→plano de ação, OS por
função, CIPA pelo Quadro I, enquadramento×adicional, PPP e coerência documental.

---

## 🔴 TEMA 2 — Proteção do menor de idade (jurídico grave)

### ✅ RESOLVIDOS (17/09/2026 — em produção)

- `ADM-030` — ✅ **trava idade × modalidade na gravação**: menor de 14 barrado; 14–15 só aprendiz (gatilho `trg_admissao_idade_modalidade`, CF art. 7º XXXIII).
- `ADM-031` — ✅ **trava idade × risco/turno**: menor de 18 barrado em jornada noturna e em função insalubre/perigosa (gatilho `trg_admissao_valida_menor_risco`, CLT arts. 404/405).
- `DESL-083` — ✅ **quitação de menor exige assistente legal** (nome + CPF do responsável) na rescisão (gatilho `trg_admissao_menor_assistente_quitacao`, CLT art. 439).
- `FERIAS-016` — ✅ **flag de estudante** no cadastro da admissão (`admissoes.estudante`): a programação de férias pode sinalizar o direito do menor estudante de coincidir com as escolares (CLT art. 136, §2º). Entrega `script_ferias016_estudante_menor.sql`.

> Entrega `script_menor_idade_adm030_031.sql` — só cria colunas/funções/gatilhos,
> não toca dado existente, gatilhos agem só em gravações futuras. Camada estava
> no desenvolvimento (migrations fase-1/fase-4) mas nunca fora entregue à produção.
>
> **Tema 2 fechado por inteiro.**

---

## 🟠 TEMA 3 — Segregação de função / aprovação sem rito (controle interno)

### ✅ RESOLVIDOS (17/09/2026) — entrega `script_t3_segregacao_funcao.sql`

- `DESL-002` — ✅ **desligamento vira trilha de eventos**: regravar por cima de desligamento já registrado é barrado (`unique_violation`); correção só por `desligamento_retificar` (com justificativa, gestor/RH), tudo em `desligamento_eventos`.
- `DESL-106` — ✅ **reversão exige rito**: sair de `desligado` por UPDATE cru sem `reversao_desligamento_justificativa` é bloqueado (gatilho `trg_admissao_bloqueia_reversao_desligamento`).
- `FERIAS-056` — ✅ **trava de autoaprovação** em `ferias_solicitacoes` (CHECK `aprovado_por <> colaborador_id`, entregue `NOT VALID` para não reprovar legado).
- `PONTO-252` — ⚠️ **trava instalada** (`chk_ajuste_sem_autoaprovacao`, `NOT VALID`) barra novas autoaprovações. **Continua vermelho na produção** enquanto existirem os ~76 ajustes históricos autoaprovados — esses exigem **decisão de produto à parte** (o que fazer com o passado; a trava não reescreve histórico).

### ⏳ Pendentes

- `DESL-025` — justa causa (art. 482) entra **sem rito** (sem quem aprovou).
- `FOLHA-071` — fechamento de folha **decorativo**: lançamento em competência fechada é aceito; reabertura sem trilha.
- `FOLHA-030` — desconto em folha **sem amparo** (texto livre, sem rubrica/teto).

---

## 🟠 TEMA 4 — Duplicidade / unicidade que ainda passa

Parte liga-se ao **A2** (a limpeza de empresa-CPF e vínculo ficou pendente):

- `EMP-020` / `EMP-021` — 🟢 **duas empresas ativas com o mesmo CNPJ**; a trava `prevent_duplicate_active_cnpj` **não pega o UPDATE** de reativação.
- `EMP-070` / `EMP-071` — 🟢 **duas empresas PF ativas com o mesmo CPF**: a trava só olha `cnpj`, e o índice de CPF ficou **adiado** (duplicatas não limpas).
- `COLAB-033` — CPF duplicado separado só pela **pontuação** (índice sobre a coluna crua).
- `COLAB-021` — 🟢 **CPF inválido aceito** (validação só no front).
- `FERIAS-091` / `PONTO-394` — período/constraint chaveado por `(tenant, CPF)` **ignora a empresa** (mesma raiz que corrigimos na admissão).

> Ação ligada: falta a **limpeza A2 de empresa-CPF (11 grupos) e vínculo (2)** +
> estender a trava de CNPJ para o UPDATE e para o CPF de empresa PF.

---

## 🟡 TEMA 5 — Travas legais ausentes, por instituto

### Férias (CLT 129–149) — ~24 achados
Fracionamento sem piso/concordância (`FERIAS-010/011/012`), abono acima de 1/3 e
fora de prazo (`FERIAS-041/042/040`), saldo×solicitado não conferidos
(`FERIAS-013`), faltas→dias não travado (`FERIAS-001`), início na véspera de
feriado (`FERIAS-014`), aviso de 30 dias sem relógio (`FERIAS-030/031`), troca
silenciosa de data confirmada (`FERIAS-052`), colaborador em férias marca ponto
(`FERIAS-053`), afastamento sobre férias (`FERIAS-024`), cancelamento não devolve
saldo (`FERIAS-051`), dobra não priorizada (`FERIAS-004`), rescisão não apura
férias (`FERIAS-090`), art. 133 não cruza afastamento (`FERIAS-003`), prescrição
inexistente (`FERIAS-008`), encargos Simples (`FERIAS-070`), cobertura de equipe
(`FERIAS-071`). **FERIAS-015** = trava etária **legada** (a remover na produção).

### Afastamentos (CLT / NR-7 / INSS) — ~13
Sobreposição de dois afastamentos ativos (`AFAST-011`), efeito legal do tipo não
parametrizado (`AFAST-010`), acumulação/INSS parcial (`AFAST-021`), CAT sem
relógio (`AFAST-030`), doença única sem pendência (`AFAST-020` — *regressão da
reescrita de 24/07*), estabilidade do acidente perdida (`AFAST-031` — *regressão*),
maternidade só como tipo (`AFAST-040`), art. 474 suspensão >30d (`AFAST-051`),
art. 473 genérico sem prazos (`AFAST-050`), FGTS do afastado (`AFAST-032`), ASO de
retorno sem trava (`AFAST-070`).

### SST (NR-4/5/6/7, PGR/PCMSO/LTCAT/PPP) — ~15
**PPP não existe** (`SST-060`), PGR vigência decorativa (`SST-001`), plano de ação
não vira tarefa (`SST-003`), ASO de mudança de risco (`SST-021`), periodicidade de
exame sem relógio (`SST-020`), exposição não estruturada (`SST-031`), laudo×adicional
desligados (`SST-050`), OS manual (`SST-010`), CA sem trava (`SST-011`), documentos
não se cruzam (`SST-070`), IA sem revisão (`SST-002`), CIPA mandato sem régua
(`SST-040`), ouvidoria sigilo/prazo (`SST-041`), acervo clínico sem trilha de acesso
(`SST-080`).

### Benefícios (VT/VR/PAT/planos/PLR) — ~13
Teto VT 6% ignorado (`BEN-011`), VR sem limite (`BEN-012`), termo de opção VT
inexistente (`BEN-010/060`), elegibilidade não lida (`BEN-001`), sem ponte com
Folha (`BEN-020`) nem com Ponto (`BEN-050`), CCT não chega (`BEN-051`),
**dependentes não existem** (`BEN-030`), operadoras/planos inexistentes (`BEN-042`),
**PLR inexistente** (`BEN-070`), consignado/margem inexistentes (`BEN-071`), plano
do demitido art. 30/31 Lei 9.656 (`BEN-040`).

### EPI (NR-6) — ~14
CA validade decorativa (`EPI-011`), sem consulta CAEPI (`EPI-010`), lote vencido sai
(`EPI-040`), sem FEFO na saída (`EPI-021`), estoque mínimo sem alerta (`EPI-022`),
troca sem relógio (`EPI-050`), nota fiscal sem chave única (`EPI-030`), **biometria
(liveness) aberta a qualquer usuário** (`EPI-041` — LGPD), assinatura sem carimbo do
tempo (`EPI-042`), devolução solta (`EPI-052`), kit de admissão não gerado
(`EPI-051`), arquivamento manual (`EPI-044`).

### Desligamento — ~10
Sobrescrita sem trilha (`DESL-002`), reversão sem aprovação (`DESL-106`), justa
causa sem rito (`DESL-025`), rescisão complementar sem lar (`DESL-105`), estabilidade
de CCT (`DESL-074`), "desligamento programado" inexistente (`DESL-013`), S-2299 sem
relógio (`DESL-093`), exame demissional fora de 10 dias (`DESL-065` — 🟢 1 de 24 sem
exame), prazo de pagamento não conferido (`DESL-015`).

### Enquadramento & Regras (NR-4/5, FAP, obrigações) — ~11
SESMT/CIPA por interruptor manual (`ENQ-050/051`), FAP fora da faixa 0,5–2,0
(`ENQ-010`), grau de risco reduzido sem justificativa (`ENQ-011`), mandato CIPA
invertido (`ENQ-013`). Obrigações não registradas automaticamente: TAC (`REGRA-005`),
déficit de PcD (`REGRA-001`), CIPA (`REGRA-002`), SESMT (`REGRA-003`), FAP alto
(`REGRA-004`), grau elevado (`REGRA-006`).

### Folha — ~7
Rubrica sem natureza eSocial/incidências (`FOLHA-001`), rubrica sem vigência/versão
(`FOLHA-002`), fechamento decorativo (`FOLHA-071`), desconto sem amparo (`FOLHA-030`),
folha complementar sem lar (`FOLHA-070`), sem alerta de variação (`FOLHA-081`),
leitura de folha aberta (`FOLHA-090` — LGPD).

### Cota PcD/Aprendiz (Lei 8.213 art. 93) — ~6
Total de empregados por digitação (`EMP-050`), não conta de admissões (`EMP-051`),
sem laudo ligado a pessoas (`EMP-052`), não agrupa matriz+filiais por raiz do CNPJ
(`EMP-054`), ignora reabilitado do INSS (`EMP-053`).

---

## 🟡 TEMA 6 — LGPD / acesso a dado sensível

- `EPI-041` — biometria (rosto/liveness) legível por qualquer usuário do tenant.
- `FOLHA-090` — leitura da folha aberta (escrita é protegida).
- `AFAST-080` / `SST-080` — CID/atestados com política de perfil, mas **sem trilha de quem acessou**.

---

## 🔧 Resíduos de QA (eu corrijo — não são achados de produto)

Pequenos, do próprio motor:
- `AFAST-001` — sonda usa **tenant real** (mesmo caso das Férias); corrijo para o cercado.
- `COLAB-011/023/033` — fixtures de CPF (a sonda esbarra na validação/constraint).
- `DESL-003` — depende de afastamento com data-fim.
- `HIER-002` — limpeza de FK do cercado.
- `DADO-010` / `HCAT-010` / `HTPL-010` — enums abertos (`tipo_pessoa='mei'`, obrigatoriedade/tipo livres) — **na fronteira** entre resíduo e achado; anoto os dois.

---

## Como usar

1. **Prioridade nº 1: eSocial (Tema 1).** É compliance com números reais.
2. **Temas 2, 3 e 4** (controle interno, duplicidade, menor) — risco alto e correções em geral pequenas.
3. **Tema 5** é o roadmap de conformidade por módulo — grande, para planejar por trimestre.
4. Os **resíduos de QA** eu fecho com segurança quando você quiser (começando pela sonda do AFAST, igual às Férias).
5. Cada correção é **feature real na produção** → disciplina de sempre (dev → teste → seu aprovado → produção), item a item.

> **A produção segue intacta.** Todo o backfill do motor foi rotina de teste; a
> única mudança de dado que você aprovou foi a limpeza de duplicidade (A2).
