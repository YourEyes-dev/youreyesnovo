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

> Severidade é sugestão minha para triar. Ao todo, ~90 achados. **Nada aqui
> alterou a produção** — tudo foi leitura.

---

## 🔴 TEMA 1 — eSocial não sai (compliance, o mais grave)

O sistema **não gera os eventos do eSocial**, em toda a linha da vida do vínculo:

| Evento | Código | Evidência |
|---|---|---|
| **S-2200** admissão | `ADM-092` | 🟢 **10.541 admissões, 0 eventos na fila, 0 log** |
| **S-2190** admissão preliminar | `ADM-093` | decorrência do S-2200 |
| **S-2299** desligamento | `DESL-091` | 🟢 **24 desligamentos, 9 logs "gerado", 0 eventos na fila** |
| **S-2230** afastamento | `AFAST-060` | pendência criada, mas sem data-limite e sem evento |
| **S-2210** CAT (acidente) | `AFAST-030` | pendência disparada, sem relógio nem evento |
| **S-2220** monitoramento saúde | `SST-030` | fila aceita quando a tela monta, sem projetar prazo (dia 15) |
| **S-2240** cond. ambientais | `SST-070` | documentos não se cruzam (PGR×PCMSO×LTCAT×S-2240) |

**É o item nº 1.** O padrão é sempre o mesmo: a inteligência cria a *pendência/log*,
mas **o evento não é enfileirado** e **não há relógio** (prazo/data-limite).

---

## 🔴 TEMA 2 — Proteção do menor de idade (jurídico grave)

- `ADM-030` — admissão **comum aceita candidato de 15 anos** (CF art. 7º XXXIII).
- `ADM-031` — **menor de 17 pode entrar em escala noturna/insalubre**.
- `DESL-083` — **menor desligado sem assistente/responsável legal** (não há campo).
- `FERIAS-016` — **estudante menor** não tem como coincidir férias com as escolares (art. 136 §2º).

---

## 🟠 TEMA 3 — Segregação de função / aprovação sem rito (controle interno)

- `PONTO-252` — 🟢 **76 de 1.709 ajustes de ponto aprovados pelo próprio colaborador**.
- `FERIAS-056` — 🟢 férias **aprovadas pelo próprio solicitante** (sem segregação).
- `DESL-002` — 🟢 **desligamento sobrescrito sem trilha** (pedido→sem justa causa, sem histórico/aprovação).
- `DESL-106` — reversão de desligamento por UPDATE simples, sem aprovação/motivo.
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
