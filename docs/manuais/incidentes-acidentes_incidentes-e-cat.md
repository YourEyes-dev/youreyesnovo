# Manual do módulo — Incidentes & Acidentes (CAT, investigação e prevenção)

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e no mesmo nível de profundidade do piloto aprovado
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial: cada tela que aparece no
> vídeo tem um **marcador de print** dizendo o que capturar e com quais dados
> fictícios.

- **Onde fica no menu:** seção **Saúde & Segurança → Incidentes & Acidentes**
  (rota `/incidentes-acidentes`).
- **Para quem é:** SESMT (Técnico e Engenheiro de Segurança), RH, gestores de
  operação/produção e a CIPA.
- **Em uma frase:** registra incidentes e acidentes de trabalho, apoia a emissão
  da **CAT**, conduz a **investigação de causa raiz** e transforma cada
  ocorrência em **plano de ação** e inteligência de prevenção (FAP, Pirâmide de
  Bird, análise preditiva).
- **Frase-guia do módulo (aparece no topo da tela):** *"Cada incidente
  registrado é uma oportunidade de evitar o próximo acidente."*

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **CAT no prazo, sem multa.** O acidente é registrado com todos os campos que a
  **CAT** e o **eSocial S-2210** exigem. O painel do topo mostra um cartão
  **"CATs Pendentes"** que acende quando há acidente sem CAT — o prazo legal é o
  **1º dia útil** após o ocorrido (art. 22 da Lei 8.213/91).
- **Investigação que protege a empresa.** Cada evento reúne descrição, causa
  raiz, checklist legal (**NR-01 / ISO 45001**), anexos e ações num só lugar.
  Numa fiscalização ou ação trabalhista, essa trilha é a defesa.
- **Nada de subnotificação.** O sistema cruza incidentes x acidentes por setor e
  **avisa quando um setor tem muitos acidentes e poucos "quase-acidentes"** —
  sinal clássico de que ocorrências estão deixando de ser reportadas.
- **Prevenção com dados, não com achismo.** Indicadores de classe mundial
  (**LTIFR**, taxa de gravidade, Pirâmide de Bird), **análise preditiva** por
  setor e **cultura de segurança** gamificada mostram onde agir antes do
  próximo acidente.
- **Impacto financeiro visível.** O **Simulador de FAP** projeta quanto os
  acidentes custam (ou vão custar) na contribuição previdenciária — e quanto a
  empresa economiza reduzindo afastamentos.
- **Do registro à ação, em um clique.** Qualquer evento vira um **Plano de Ação**
  com responsável e prazo, sem sair da tela.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Incidente** | Evento **sem lesão** — o "quase-acidente" (near miss). Serve de aviso. |
| **Acidente** | Evento **com lesão, doença ou óbito**. Ativa campos legais e a CAT. |
| **Desvio de segurança** | A base da prevenção: uma condição ou ato inseguro observado **antes** de virar incidente. |
| **CAT** | Comunicação de Acidente de Trabalho — documento oficial exigido por lei quando há acidente. |
| **eSocial S-2210** | O leiaute do governo para comunicar o acidente. Os campos do sistema já seguem esse padrão. |
| **Causa raiz** | O motivo real por trás do evento (não só o sintoma). Investigada com 5-Porquês, Ishikawa etc. |
| **Plano de ação** | A correção com responsável e prazo, vinculada ao evento. |
| **NTEP / Nexo causal** | A ligação técnica entre o problema de saúde e o trabalho (usada pelo INSS). |
| **FAP / RAT** | Fatores que definem quanto a empresa paga de contribuição por risco de acidente. Menos acidentes = menos imposto. |
| **Pirâmide de Bird** | A ideia de que muitos desvios e quase-acidentes antecedem cada acidente grave. Uma base larga é sinal de cultura madura. |
| **LTIFR** | Taxa de acidentes com afastamento por milhão de horas trabalhadas (indicador internacional). |
| **Near Miss** | Outro nome para o quase-acidente (incidente sem lesão). |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Estar logado como quem opera SST** — no ambiente de teste, a persona
   **Marina Alves** (Analista de RH), empresa **Empresa Staging LTDA**.
2. **Ter colaboradores cadastrados** — o formulário sugere o colaborador
   envolvido a partir do cadastro (também é possível digitar o nome à mão).
3. **Ter estabelecimentos/obras e departamentos cadastrados** — assim os campos
   **Estabelecimento/Obra** e **Setor/Área** aparecem prontos para escolher (dá
   para digitar manualmente se não houver).
4. Não há nada a "ligar": ao abrir o módulo já é possível registrar o primeiro
   evento. Sem eventos, as abas de análise mostram "Sem dados" — é o ponto de
   partida normal.

> 💡 Para os vídeos ficarem críveis, deixe alguns eventos de exemplo já
> registrados (um incidente e um acidente) antes de gravar as abas de análise —
> elas só ganham vida com dados.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Incidentes & Acidentes**, o topo mostra o título com o ícone de
escudo, a frase-guia em itálico e dois botões: **Guia Rápido** e **Registrar
Evento**.

Logo abaixo vem a **faixa de indicadores** com 6 cartões: **Total de Eventos**,
**Incidentes**, **Acidentes**, **Em Aberto**, **Com Ações** e **CATs
Pendentes**.

Em seguida, as **8 abas** do módulo:

| Aba | Para que serve |
|---|---|
| **Ocorrências** | A lista de todos os eventos, com busca e filtros. É o ponto de partida do dia a dia. |
| **Análise** | Painel de leitura rápida: setores, tipos, turnos e fatores mais frequentes. |
| **Indicadores** | KPIs estratégicos (LTIFR, taxa de gravidade, Bird, % com causa raiz). |
| **Analytics** | Gráficos avançados: Pareto de causas, tendência mensal, heatmap setor × turno. |
| **Preditivo** | Score de risco por setor e probabilidade de acidente nos próximos 30 dias. |
| **Cultura** | Cultura de segurança gamificada: níveis, ranking por setor e top reportadores. |
| **FAP** | Simulador do impacto financeiro dos acidentes (FAP/RAT). |
| **Pirâmide** | Pirâmide de Bird e o registro de **desvios de segurança**. |

> 📸 **PRINT 01 — Tela inicial do módulo**
> **Onde:** menu **Saúde & Segurança → Incidentes & Acidentes**, aba
> **Ocorrências**.
> **O que precisa aparecer:** o título "Incidentes & Acidentes", a frase-guia em
> itálico, os botões **Guia Rápido** e **Registrar Evento**, a faixa dos 6
> cartões de indicadores e a barra das 8 abas.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; indicadores como
> **Total 14 · Incidentes 9 · Acidentes 5 · Em Aberto 3 · Com Ações 6 · CATs
> Pendentes 1**.
> **Ação filmada:** panorâmica lenta de cima para baixo, mostrando as abas.

> 💡 O cartão **CATs Pendentes** é o alarme legal da tela: se estiver aceso, há
> acidente sem CAT emitida — resolva primeiro.

---

## 5. Passo a passo por fluxo

O módulo traz um **Guia Rápido embutido** (botão no topo) com um passo a passo em
14 etapas e a opção de **baixar o manual em PDF**. Vale abri-lo no vídeo tutorial
como reforço.

> 📸 **PRINT 02 — Guia Rápido embutido**
> **Onde:** botão **Guia Rápido** (topo da tela).
> **O que precisa aparecer:** a janela do guia com a navegação lateral de etapas,
> a etapa "Bem-vindo ao Módulo de Incidentes & Acidentes" e a barra de progresso.
> **Ação filmada:** clicar em **Guia Rápido**, avançar uma ou duas etapas com
> **Próximo** e mostrar, na última etapa, o botão **Baixar Manual PDF**.

---

### Fluxo 1 — Registrar um incidente (quase-acidente)

**Objetivo:** registrar um evento **sem lesão** para que ele vire aprendizado.
**Benefício:** o incidente é a base da prevenção — registrá-lo hoje evita o
acidente de amanhã, e alimenta os indicadores de cultura.

O registro é um **assistente por etapas**. Para **incidente** são **5 etapas**:
**Tipo & Local → Envolvidos → Classificação → Descrição → Fatores**.

1. Clique em **Registrar Evento** no topo.
2. Na etapa **Tipo & Local**, escolha o cartão **Incidente** ("Quase-acidente,
   sem lesão"), informe **data** e **hora**, o **Estabelecimento/Obra**, o
   **Setor/Área**, o **Local específico** e o **Turno**.
3. Na etapa **Envolvidos**, selecione o **colaborador** do cadastro (ou digite o
   nome e a função) e registre **testemunhas/outros envolvidos**.
4. Na etapa **Classificação**, escolha a **Categoria principal** (ex.: "Quase
   queda"), a **Origem predominante** (comportamental, organizacional, técnica ou
   ambiental) e a **Gravidade potencial** (o que poderia ter acontecido).
5. Na etapa **Descrição**, conte **o que aconteceu** e a **percepção inicial da
   causa**.
6. Na etapa **Fatores**, marque os **fatores ergonômicos e psicossociais** que
   podem ter contribuído (ritmo acelerado, jornada longa, falta de pausa etc.).
7. Clique em **Registrar Evento** — o sistema gera um **código único** (ex.:
   `INC-2026-001`).

> 📸 **PRINT 03 — Registrar Evento: etapa Tipo & Local**
> **Onde:** botão **Registrar Evento** → primeira etapa.
> **O que precisa aparecer:** os dois cartões **Incidente / Acidente** (com o
> Incidente selecionado), os campos de data/hora e os campos de local (
> Estabelecimento, Setor, Local específico, Turno) e a trilha de etapas no topo.
> **Dados fictícios na tela:** tipo **Incidente**, data **22/09/2026**, hora
> **10:15**, Estabelecimento **Empresa Staging LTDA — Unidade Matriz**, Setor
> **Produção**, Local **"Linha 3, próximo ao refeitório"**, Turno **1º Turno**.

> 📸 **PRINT 04 — Registrar Evento: etapa Classificação**
> **Onde:** terceira etapa do assistente.
> **O que precisa aparecer:** a grade de **Categoria principal**, a lista de
> **Origem predominante** e os quatro botões de **Gravidade potencial** (Baixa/
> Média/Alta/Crítica).
> **Dados fictícios na tela:** Categoria **"Quase queda"**, Origem **"Técnica
> (máquina, ferramenta, EPI, layout)"**, Gravidade potencial **Alta**.

> 📸 **PRINT 05 — Registrar Evento: etapa Fatores**
> **Onde:** última etapa do assistente (incidente).
> **O que precisa aparecer:** a lista de fatores ergonômicos/psicossociais com
> alguns marcados e as etiquetas selecionadas no topo.
> **Dados fictícios na tela:** marcados **"Ritmo de trabalho acelerado / pressa"**
> e **"Falta de pausas adequadas"**.

> 💡 Quanto mais detalhada a descrição, mais fácil a investigação depois. Diga o
> que a pessoa fazia, onde exatamente e se havia alguma condição especial (piso
> molhado, correria, turno noturno).

---

### Fluxo 2 — Registrar um acidente e preparar a CAT

**Objetivo:** registrar um evento **com lesão** e reunir tudo o que a CAT exige.
**Benefício:** o acidente entra completo — gravidade, classificação legal e dados
da CAT — pronto para a comunicação no prazo e sem retrabalho.

Quando o tipo é **Acidente**, o assistente ganha etapas extras: **8 etapas** no
total — **Tipo & Local → Envolvidos → Classificação → Gravidade → Classificação
Legal → CAT → Descrição → Fatores**.

1. Clique em **Registrar Evento** e, na etapa **Tipo & Local**, escolha o cartão
   **Acidente** ("Com lesão ou dano").
2. Preencha **Envolvidos** e **Classificação** como no fluxo anterior.
3. Na etapa **Gravidade**, informe a **gravidade da lesão** (sem lesão, leve,
   moderada, grave), o **afastamento** (sem afastamento, até 15 dias, mais de 15
   dias), o **atendimento médico** (não necessário, ambulatorial, hospitalar) e,
   se for o caso, marque **Houve óbito**.
4. Na etapa **Classificação Legal**, informe o **tipo de acidente** (Típico, De
   Trajeto, Doença Ocupacional, NTEP), o **CID-10**, os **dias de afastamento**,
   o **nexo causal** (confirmado / suspeito / descartado) e o **agente causador
   (eSocial)**.
5. Na etapa **CAT**, marque **Houve emissão de CAT?** e, se sim, informe
   **número**, **data de emissão**, **tipo** (Inicial, Reabertura, Comunicação de
   Óbito) e **observações**.
6. Preencha **Descrição** e **Fatores** e clique em **Registrar Evento** — o
   código gerado sai como `ACD-2026-001`.

> 📸 **PRINT 06 — Registrar Evento: etapa Gravidade (acidente)**
> **Onde:** quarta etapa do assistente, com o tipo **Acidente** selecionado.
> **O que precisa aparecer:** os blocos de **Gravidade da lesão**, **Afastamento**
> e **Atendimento médico** e a caixa **Houve óbito**.
> **Dados fictícios na tela:** colaboradora **Camila Duarte** (Operadora de
> Produção), lesão **Leve**, afastamento **Até 15 dias**, atendimento
> **Ambulatorial**, óbito **desmarcado**.

> 📸 **PRINT 07 — Registrar Evento: etapa Classificação Legal**
> **Onde:** quinta etapa do assistente (acidente).
> **O que precisa aparecer:** os cartões de **Tipo de acidente legal**, o campo
> **CID-10**, **Dias de afastamento**, os botões de **Nexo causal** e o seletor de
> **Agente causador (eSocial)**.
> **Dados fictícios na tela:** tipo **Típico**, CID-10 **S60.0**, dias **7**, nexo
> **Confirmado**, agente **"07.04 — Corte por objeto"**.

> 📸 **PRINT 08 — Registrar Evento: etapa CAT**
> **Onde:** sexta etapa do assistente (acidente).
> **O que precisa aparecer:** a caixa **Houve emissão de CAT?** marcada e os
> campos número, data, tipo e observações.
> **Dados fictícios na tela:** CAT emitida, número **2026.000123-4**, data
> **23/09/2026**, tipo **Inicial**.

> 💡 O prazo da CAT é o **1º dia útil** após o acidente (imediato em caso de
> óbito). Enquanto ela não for marcada como emitida, o evento conta no cartão
> **CATs Pendentes** e nos alertas do Simulador de FAP.

---

### Fluxo 3 — Encontrar eventos: busca e filtros

**Objetivo:** localizar rapidamente um evento ou preparar um recorte para CIPA,
auditoria ou eSocial.
**Benefício:** a lista combina filtros para produzir exatamente o relatório que
você precisa.

1. Na aba **Ocorrências**, use a **busca** por código, nome do colaborador,
   setor ou descrição.
2. Combine os filtros: **Tipo** (Incidente/Acidente), **Status** (Em Aberto, Em
   Análise, Ações em Andamento, Concluído), **Unidade**, **Turno** e **período**
   (data início / data fim).
3. Cada linha mostra **Código, Data, Tipo, Gravidade, Unidade/Setor, Cargo,
   Turno, Status** e ícones de ação: **baixar relatório (impressora)**,
   **editar** e **ver detalhes (olho)**.

> 📸 **PRINT 09 — Lista de Ocorrências com filtros**
> **Onde:** aba **Ocorrências**.
> **O que precisa aparecer:** a barra de busca e filtros e a tabela com várias
> linhas e etiquetas de tipo/status/gravidade diferentes.
> **Dados fictícios na tela:**
> - `ACD-2026-001` — 22/09/2026 — **Acidente** — Leve — Produção — Operadora de
>   Produção — 1º Turno — **Em Análise**.
> - `INC-2026-004` — 22/09/2026 — **Incidente** — Alta (potencial) — Produção —
>   **Em Aberto**.
> - `ACD-2026-002` — 18/09/2026 — **Acidente** — Moderada — Logística —
>   **Ações em Andamento**.
> **Ação filmada:** aplicar o filtro **Tipo = Acidentes** e depois **Status = Em
> Aberto**.

> 💡 Para o relatório anual da CIPA, filtre **Tipo = Acidentes** e o **período**
> do ano. Para o eSocial, filtre **Acidentes** e confira quais ainda estão como
> **CATs Pendentes**.

---

### Fluxo 4 — Detalhar e investigar um evento

**Objetivo:** abrir o evento, conduzir a investigação e reunir a documentação.
**Benefício:** numa só tela ficam os dados, a CAT, a análise de causa raiz, o
checklist legal, os anexos e a transmissão ao eSocial.

1. Na lista, clique na linha do evento (ou no ícone do **olho**) para abrir o
   **detalhe**.
2. À **esquerda**: **Dados do Evento**, **Descrição**, **Detalhamento do
   Acidente**, o bloco **CAT** (com **anexar/atualizar o arquivo da CAT**), os
   **Fatores Ergonômicos** e as **Ações Vinculadas**.
3. À **direita**: o painel **Investigação Assistida** — **Score de Risco** do
   evento, o **Checklist de Investigação NR-01 / ISO 45001**, o campo **Análise
   de Causa Raiz / Notas** e o **Motor de Investigação por IA**; abaixo, o bloco
   de **transmissão ao eSocial (S-2210)** e a área de **Anexos** (arraste e
   solte fotos, laudos, depoimentos).
4. No topo do detalhe: **Baixar Relatório** (base para a CAT, em PDF), **Concluir
   Evento** e **Criar Ação Vinculada**.

> 📸 **PRINT 10 — Detalhe do evento (dados + CAT)**
> **Onde:** clique em um acidente na lista.
> **O que precisa aparecer:** o cabeçalho com o código e as etiquetas de tipo e
> status, o cartão **Dados do Evento**, o **Detalhamento do Acidente** e o bloco
> **CAT**.
> **Dados fictícios na tela:** `ACD-2026-001`, **Camila Duarte**, Produção, lesão
> **Leve**, afastamento **Até 15 dias**, CAT número **2026.000123-4**.

> 📸 **PRINT 11 — Painel de Investigação Assistida**
> **Onde:** coluna direita do detalhe do evento.
> **O que precisa aparecer:** o **Score de Risco** com a barra e os fatores, o
> **Checklist NR-01 / ISO 45001** com o percentual concluído, o campo de **Notas
> de causa raiz** e o botão **Analisar com IA**.
> **Dados fictícios na tela:** Score **48 — Alto Risco**; checklist **7/13
> (54%)**; nota de causa raiz preenchida com o método **"5-Porquês"**.
> **Ação filmada:** marcar dois itens do checklist e clicar em **Analisar com
> IA**.

> 💡 O **Score de Risco** e o **checklist** são a bússola da investigação: quanto
> mais alto o score e mais itens pendentes no checklist, maior a prioridade
> daquele evento.

---

### Fluxo 5 — Transformar o evento em ação (e concluir)

**Objetivo:** fechar o ciclo com uma correção rastreável.
**Benefício:** o evento vira **Plano de Ação** com responsável e prazo, e só é
concluído quando a ação está resolvida.

1. No detalhe, clique em **Criar Ação Vinculada** (ou **Nova Ação** no cartão de
   ações) — o sistema já preenche título, tipo (corretiva/preventiva),
   responsável e um prazo de referência de 30 dias.
2. A ação passa a aparecer no cartão **Ações Vinculadas** e o status do evento
   avança para **Ações em Andamento**.
3. Acompanhe o **ciclo de status**: **Em Aberto → Em Análise → Ações em Andamento
   → Concluído**.
4. Quando tudo estiver resolvido e com evidências anexadas, clique em **Concluir
   Evento**.

> 📸 **PRINT 12 — Ações vinculadas ao evento**
> **Onde:** cartão **Ações Vinculadas** no detalhe, após criar uma ação.
> **O que precisa aparecer:** o botão **Criar Ação Vinculada**, a ação criada com
> responsável e prazo e sua etiqueta de status.
> **Dados fictícios na tela:** ação **"Revisar proteção da Linha 3 e reforçar
> uso de EPI"**, responsável **Bruno Carvalho**, prazo **22/10/2026**, status
> **Em Andamento**.
> **Ação filmada:** clicar em **Criar Ação Vinculada** e mostrar o status do
> evento mudando para **Ações em Andamento**.

> 📸 **PRINT 13 — Relatório do evento em PDF**
> **Onde:** botão **Baixar Relatório** (topo do detalhe).
> **O que precisa aparecer:** o PDF gerado, com as seções Dados do Evento,
> Colaborador Envolvido, Natureza, Gravidade, Descrição e Dados da CAT.
> **Dados fictícios na tela:** cabeçalho **"Relatório de Acidente de Trabalho —
> base para preenchimento da CAT"**, código `ACD-2026-001`.

> 💡 O relatório é um **documento de apoio interno** para preencher a CAT nos
> sistemas oficiais — ele não substitui a responsabilidade técnica do
> profissional de SST.

---

### Fluxo 6 — Análise: leitura rápida do que está acontecendo

**Objetivo:** enxergar padrões sem montar planilha.
**Benefício:** em segundos você vê onde os eventos se concentram e qual fator se
repete.

Na aba **Análise** ficam quatro painéis — **Setores com maior concentração**,
**Tipos mais recorrentes**, **Distribuição por turno** e **Fatores ergonômicos
mais frequentes** — e um bloco de **Alertas e Insights** que sinaliza possível
**subnotificação** (setor com mais acidentes do que incidentes).

> 📸 **PRINT 14 — Aba Análise**
> **Onde:** Incidentes & Acidentes → **Análise**.
> **O que precisa aparecer:** os quatro painéis e, se houver, o cartão de alerta
> de subnotificação.
> **Dados fictícios na tela:** setor **Produção** no topo (**9 inc. / 5 acid.**);
> tipo mais recorrente **"Quase queda"**; concentração no **1º Turno**; fator
> mais frequente **"Ritmo de trabalho acelerado / pressa"**.

---

### Fluxo 7 — Indicadores estratégicos (KPIs)

**Objetivo:** medir o programa de segurança com indicadores reconhecidos.
**Benefício:** números prontos para reunião de CIPA, diretoria e auditoria.

A aba **Indicadores** calcula sozinha: **LTIFR** (acidentes com afastamento por
milhão de horas), **Taxa de Gravidade**, **Taxa de Incidência**, a relação
**Near Miss / Acidente** (meta da Pirâmide de Bird), **% de eventos com causa
raiz definida**, os **setores reincidentes** e a distribuição de **gravidade dos
acidentes**.

> 📸 **PRINT 15 — Aba Indicadores**
> **Onde:** Incidentes & Acidentes → **Indicadores**.
> **O que precisa aparecer:** os quatro cartões de frequência (LTIFR, Gravidade,
> Incidência, Near Miss/Acidente) e a linha de qualidade (% com causa raiz,
> setores reincidentes, gravidade).
> **Dados fictícios na tela:** LTIFR **1,80** (Atenção), Near Miss/Acidente
> **2** com selo **Crítico**, **% com causa raiz 64%**, **1 setor reincidente
> (Produção)**.

> 💡 A relação **Near Miss / Acidente** é o termômetro da cultura: quanto mais
> alto (a meta de Bird é 300:1), mais a empresa está enxergando os riscos antes
> do acidente.

---

### Fluxo 8 — Analytics avançado

**Objetivo:** aprofundar a análise com gráficos.
**Benefício:** identificar as poucas causas que respondem pela maioria dos
eventos e onde o risco se concentra.

A aba **Analytics** traz o **Pareto de causas** (as categorias que mais pesam), a
**Tendência mensal** (incidentes x acidentes ao longo do tempo), o **Heatmap
Setor × Turno** (onde o risco esquenta) e um alerta automático de
**subnotificação provável**.

> 📸 **PRINT 16 — Aba Analytics (Pareto + Heatmap)**
> **Onde:** Incidentes & Acidentes → **Analytics**.
> **O que precisa aparecer:** o **Pareto de Causas Principais** com o percentual
> acumulado e o **Heatmap Setor × Turno** colorido.
> **Dados fictícios na tela:** Pareto liderado por **"Quase queda"** e **"Corte /
> laceração"**; no heatmap, a célula **Produção × 1º Turno** em vermelho.

---

### Fluxo 9 — Preditivo: onde o próximo acidente é mais provável

**Objetivo:** antecipar o risco por setor.
**Benefício:** priorizar a prevenção com base em tendência, não em sorte.

A aba **Preditivo** calcula um **Score de Risco por setor** e uma
**probabilidade de acidente nos próximos 30 dias**, destaca os **setores que
exigem ação imediata** e mostra a **tendência** (crescente/estável/decrescente) e
o **turno crítico** de cada setor.

> 📸 **PRINT 17 — Aba Preditivo**
> **Onde:** Incidentes & Acidentes → **Preditivo**.
> **O que precisa aparecer:** o bloco de **setores que requerem ação prioritária**
> e a grade de cartões por setor com score, probabilidade/30 dias e tendência.
> **Dados fictícios na tela:** **Produção** com **Score 62 — Alto Risco**,
> **58% prob./30 dias**, tendência **Crescente ↑**, turno crítico **1º Turno**.

> 💡 O modelo é um apoio à decisão (baseado em frequência histórica) — não
> substitui a avaliação de risco formal da NR-01.

---

### Fluxo 10 — Cultura de segurança

**Objetivo:** medir e estimular o engajamento das equipes.
**Benefício:** reconhecer quem reporta transforma o registro de quase-acidentes
em hábito.

A aba **Cultura** dá um **nível global** (Bronze → Prata → Ouro → Diamante),
mostra quantos **near miss** foram reportados, a relação **Near Miss / Acidente**,
o **% com causa raiz**, o **ranking de cultura por setor** e o **Top Reportadores
de Near Miss** ("Heróis da Prevenção").

> 📸 **PRINT 18 — Aba Cultura**
> **Onde:** Incidentes & Acidentes → **Cultura**.
> **O que precisa aparecer:** o cartão de **Nível Global** com o emoji e a barra
> Bronze→Diamante, os indicadores de engajamento e o **Top Reportadores**.
> **Dados fictícios na tela:** nível **Prata — Em Desenvolvimento (Score 52)**;
> **9 near miss reportados**; no ranking, **Marina Alves** no topo.

---

### Fluxo 11 — Simulador de FAP (o custo dos acidentes)

**Objetivo:** mostrar quanto os acidentes pesam (ou vão pesar) na contribuição.
**Benefício:** um argumento financeiro para investir em prevenção.

Na aba **FAP**, informe a **folha mensal** e o **RAT base**; o simulador mostra o
**FAP atual** e a **contribuição anual estimada**, e permite simular cenários —
**reduzir afastamentos** (com um controle deslizante) e **eliminar acidentes
graves/óbitos** — projetando a **economia**. Abaixo, lista os **riscos
previdenciários** identificados (acidentes sem CAT, afastamentos > 15 dias,
óbitos).

> 📸 **PRINT 19 — Aba FAP (simulador)**
> **Onde:** Incidentes & Acidentes → **FAP**.
> **O que precisa aparecer:** os campos de folha e RAT, os cartões **Situação
> Atual** x **Cenário Simulado**, o cartão verde de **Economia Projetada** e o
> bloco de riscos previdenciários.
> **Dados fictícios na tela:** folha **R$ 500.000**, RAT **3%**, FAP atual
> **1,25**, cenário simulado **0,90**, economia projetada visível; alerta **"1
> acidente sem CAT emitida"**.
> **Ação filmada:** arrastar o controle **"Reduzir afastamentos"** e mostrar a
> economia mudando.

> 💡 É uma **estimativa** — o FAP real é calculado pelo INSS. Serve para
> dimensionar o impacto e defender o investimento em segurança.

---

### Fluxo 12 — Pirâmide de Bird e registro de desvios

**Objetivo:** ver a hierarquia completa dos eventos e registrar desvios na base.
**Benefício:** uma base larga de desvios e quase-acidentes, com topo pequeno de
acidentes graves, é o retrato de uma cultura de segurança madura.

1. Abra a aba **Pirâmide**. Ela mostra 5 níveis, da base ao topo: **Desvios de
   Segurança → Incidentes/Quase-acidentes → Acidentes s/ afastamento → Acidentes
   c/ afastamento → Óbitos/Graves**.
2. Use o seletor para ver a pirâmide por **Global, Unidade, Setor, Cargo ou
   Turno**. Clique em qualquer nível para abrir a **lista daquele nível** num
   painel lateral.
3. Para registrar um desvio, clique em **+ Desvio** (no topo do cartão da
   pirâmide). Informe **tipo** (Condição Insegura, Ato Inseguro, Desvio de
   Processo), **categoria técnica**, **potencial de risco** (Baixo/Médio/Alto/
   Crítico), **local/turno**, **data**, **descrição**, **causa provável** e a
   **ação imediata**; é possível registrar de forma **anônima**.

> 📸 **PRINT 20 — Aba Pirâmide (Bird)**
> **Onde:** Incidentes & Acidentes → **Pirâmide**.
> **O que precisa aparecer:** a pirâmide colorida de 5 níveis com as contagens, o
> seletor de dimensão, os três indicadores (desvios registrados, resolvidos,
> críticos abertos) e a relação incidentes/acidente.
> **Dados fictícios na tela:** base **Desvios 22**, **Incidentes 9**, **Acidentes
> s/ afast. 3**, **c/ afast. 2**, **Óbitos 0**; **Desvios resolvidos 15**.
> **Ação filmada:** clicar no nível **Incidentes** e mostrar o painel lateral com
> a lista.

> 📸 **PRINT 21 — Registrar Desvio de Segurança**
> **Onde:** botão **+ Desvio** na aba Pirâmide.
> **O que precisa aparecer:** a janela **Registrar Desvio de Segurança** com o
> tipo, a categoria técnica, os botões de potencial de risco e o interruptor
> **Anônimo**.
> **Dados fictícios na tela:** tipo **Condição Insegura**, categoria **EPI / EPR**,
> potencial **Alto**, setor **Produção**, descrição **"Proteção da Linha 3 solta"**.

> 💡 Desvios de potencial **Alto** ou **Crítico** mostram um aviso na tela
> sugerindo converter em incidente ou criar uma ação imediata — não deixe passar.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** dor → solução → prova. Personas fictícias, dados de exemplo.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Um acidente sem CAT no prazo já é multa. E sem investigação, é processo."* Abre em papel/planilha bagunçada. | Imagem genérica |
| 8–22s | *"O YourEyes registra incidentes e acidentes com tudo o que a CAT e o eSocial exigem — no passo a passo certo."* | **PRINT 03** + **PRINT 08** (CAT) |
| 22–38s | *"E não para no registro: investiga a causa raiz, cria o plano de ação e guarda a prova."* | **PRINT 11** (investigação) + **PRINT 12** (ação) |
| 38–55s | *"Transforma cada ocorrência em prevenção: indicadores, risco por setor e cultura de segurança."* | **PRINT 15** (indicadores) + **PRINT 17** (preditivo) |
| 55–70s | *"Até o bolso enxerga: simule quanto os acidentes custam no seu FAP."* | **PRINT 19** (FAP) |
| 70–85s | *"YourEyes. Cada incidente registrado evita o próximo acidente."* Logo. | **PRINT 20** (pirâmide) + tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 6–9 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("agora eu registro…", "vamos investigar…").

1. **Abertura** — o que o módulo faz e para quem (**PRINT 01**).
2. **Guia Rápido** embutido — mostrar rapidamente (**PRINT 02**).
3. **Registrar um incidente** (5 etapas) (**PRINT 03, 04, 05**).
4. **Registrar um acidente** e preparar a CAT (**PRINT 06, 07, 08**).
5. **Buscar e filtrar** na lista de ocorrências (**PRINT 09**).
6. **Abrir o detalhe** e **investigar** (score, checklist, IA) (**PRINT 10, 11**).
7. **Criar a ação vinculada** e **baixar o relatório** (**PRINT 12, 13**).
8. **Análise** e **Indicadores** (**PRINT 14, 15**).
9. **Analytics** e **Preditivo** (**PRINT 16, 17**).
10. **Cultura** e **FAP** (**PRINT 18, 19**).
11. **Pirâmide** e **registrar um desvio** (**PRINT 20, 21**).
12. **Encerramento** — lembrar do botão **Guia Rápido** e do **Manual em PDF**
    dentro do sistema.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Tela inicial do módulo (header + 6 cartões + 8 abas)
- [ ] **PRINT 02** — Guia Rápido embutido
- [ ] **PRINT 03** — Registrar Evento: etapa Tipo & Local (incidente)
- [ ] **PRINT 04** — Registrar Evento: etapa Classificação
- [ ] **PRINT 05** — Registrar Evento: etapa Fatores
- [ ] **PRINT 06** — Registrar Evento: etapa Gravidade (acidente)
- [ ] **PRINT 07** — Registrar Evento: etapa Classificação Legal
- [ ] **PRINT 08** — Registrar Evento: etapa CAT
- [ ] **PRINT 09** — Lista de Ocorrências com filtros
- [ ] **PRINT 10** — Detalhe do evento (dados + CAT)
- [ ] **PRINT 11** — Painel de Investigação Assistida
- [ ] **PRINT 12** — Ações vinculadas ao evento
- [ ] **PRINT 13** — Relatório do evento em PDF
- [ ] **PRINT 14** — Aba Análise
- [ ] **PRINT 15** — Aba Indicadores
- [ ] **PRINT 16** — Aba Analytics (Pareto + Heatmap)
- [ ] **PRINT 17** — Aba Preditivo
- [ ] **PRINT 18** — Aba Cultura
- [ ] **PRINT 19** — Aba FAP (simulador)
- [ ] **PRINT 20** — Aba Pirâmide (Bird)
- [ ] **PRINT 21** — Registrar Desvio de Segurança

---

## 9. Erros comuns / dúvidas frequentes

- **"O cartão CATs Pendentes está aceso."** Há acidente sem CAT marcada como
  emitida. Abra o evento, vá ao bloco **CAT** e informe número/data/tipo (e
  anexe o PDF, se tiver). Lembre do prazo do 1º dia útil.
- **"As abas de análise mostram 'Sem dados'."** Ainda não há eventos suficientes
  (ou faltou informar o **setor**). O **Preditivo**, por exemplo, só ativa
  quando os eventos têm setor preenchido.
- **"Não acho onde registrar um desvio."** O desvio não fica na lista de
  ocorrências: ele é registrado na aba **Pirâmide**, botão **+ Desvio**.
- **"O colaborador não aparece na lista do formulário."** Confira se ele está
  cadastrado; se preferir, use **"Digitar manualmente"** e informe nome e função.
- **"Registrei como incidente, mas houve lesão."** Edite o evento (ícone de
  lápis na lista) e mude o **Tipo** para **Acidente** — as etapas de gravidade,
  classificação legal e CAT passam a aparecer.
- **"O relatório em PDF substitui a CAT oficial?"** Não. Ele é documento de apoio
  interno para preencher a CAT nos sistemas oficiais.
- **"Os números do FAP são os do INSS?"** Não. O Simulador de FAP é uma
  **estimativa** para dimensionar impacto; o valor real é calculado pelo INSS.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução.

Para revisar o conteúdo e conferir cada print no ambiente correto:

1. Abra o **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
   Alves**, empresa **Empresa Staging LTDA**.
2. Vá em **Saúde & Segurança → Incidentes & Acidentes** e percorra as **8 abas**
   (Ocorrências, Análise, Indicadores, Analytics, Preditivo, Cultura, FAP,
   Pirâmide), o botão **Registrar Evento** (assistente por etapas) e o botão
   **Guia Rápido** — confirmando que cada marcador 📸 bate com a tela real.
3. Aprovado o **formato**, replico o mesmo padrão para os demais módulos, nos
   lotes que você priorizar.
