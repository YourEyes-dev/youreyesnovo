# Manual do módulo — Ergonomia (Gestão de Risco Ergonômico)

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e do piloto aprovado [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial: cada tela que aparece
> tem um **marcador de print** com o que capturar e quais dados fictícios usar.

- **Onde fica no menu:** seção **Saúde & Segurança → Ergonomia** (rota `/ergonomia`).
- **Para quem é:** RH, Saúde e Segurança do Trabalho (SST), técnicos e
  engenheiros de segurança, e gestores responsáveis pelo programa de riscos.
- **Em uma frase:** conduz o ciclo completo de **Gestão de Riscos Ocupacionais
  (GRO)** para a ergonomia — da avaliação preliminar ao documento de
  conformidade —, atendendo à **NR-01**, à **NR-17** e à **ISO 45003**.
- **Importante:** o módulo trabalha o risco por **Situação de Trabalho** (o par
  **Setor + Função**), não "por empresa" genérica. Cada função é uma realidade
  distinta — é assim que a NR-17 e o auditor fiscal enxergam o trabalho.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Conformidade legal pronta para fiscalização.** O módulo cobre a NR-17
  (ergonomia) dentro do fluxo do GRO da NR-01. Gera os documentos técnicos que o
  auditor pede — a **AEP** (Análise Ergonômica Preliminar), o **Documento de
  Metodologia** e a **Comunicação aos Trabalhadores** — sem depender de planilha
  ou consultoria externa para cada laudo.
- **Um fluxo guiado em 5 etapas, sem precisar ser especialista.** O sistema leva
  o RH do risco ao documento: **Avaliar (AEP) → Inventário GRO → Riscos
  Prioritários → Plano de Ação → Monitoramento**. Cada nível de risco é calculado
  sozinho (Baixo, Médio, Alto, Crítico).
- **Diagnóstico por foto, em segundos.** A **Análise por IA** recebe uma foto do
  posto de trabalho e devolve os riscos identificados, o percentual de
  conformidade com a NR-17 e recomendações — que viram ações com um clique.
- **Nada de risco solto sem tratamento.** Risco Alto ou Crítico exige Plano de
  Ação vinculado; o sistema destaca em vermelho os que estão "sem ação" e alerta
  os prazos (30 dias para Crítico, 60 para Alto).
- **Checklist do auditor embutido.** A síntese da AEP tem os **12 itens que o
  auditor fiscal verifica** (Manual de Aplicação da NR-17, MTE/2002) e calcula o
  percentual de conformidade na hora.
- **Score de maturidade do programa.** O painel mostra em que estágio está a
  gestão ergonômica (de **Reativo** a **Cultura Saudável**), com o percentual de
  conformidade NR-17 — uma métrica que a diretoria entende.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **GRO** | Gerenciamento de Riscos Ocupacionais (NR-01). O ciclo completo: identificar → avaliar → controlar → monitorar o risco. |
| **NR-17** | A Norma Regulamentadora da **ergonomia** — postura, mobiliário, cargas, ruído, temperatura, ritmo e pausas. |
| **AEP** | **Análise Ergonômica Preliminar** — o documento de entrada que descreve as condições reais de uma função e classifica o risco. |
| **AET** | **Análise Ergonômica do Trabalho** — o estudo aprofundado, indicado quando a AEP aponta necessidade. |
| **Situação de Trabalho** | O par **Setor + Função** (ex.: "Produção + Operador"). Cada combinação é uma realidade distinta a avaliar. |
| **GHE** | Grupo de Exposição Homogênea (NR-01) — funções semelhantes que compartilham a mesma exposição; no sistema, o botão **Duplicar** representa isso. |
| **Inventário GRO** | A lista central de todos os riscos ergonômicos da empresa, com nível calculado. |
| **Nível de risco** | Resultado de **probabilidade × severidade**: Baixo, Médio, Alto ou Crítico. |
| **Eixo ergonômico** | A natureza do risco: **Físico**, **Cognitivo** ou **Organizacional**. |
| **Ciclo GRO** | O estágio de cada risco no fluxo (identificado, em tratamento, revisado…), ajustável na tabela do inventário. |
| **5W2H** | Modelo de plano de ação: o quê, por quê, quem, quando, onde, como e quanto custa. |
| **Maturidade** | O estágio do programa: Reativo → Corretivo → Preventivo → Estratégico → Cultura Saudável. |
| **RQ-26 / RQ-19 / RQ-20** | Registros da NR-01: metodologia do programa (RQ-26) e comunicação/participação dos trabalhadores (RQ-19/20). |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Empresa ativa selecionada.** O módulo puxa CNPJ e razão social da empresa
   ativa (aqui, **Empresa Staging LTDA**) automaticamente para a AEP.
2. **Itens da NR-17 inicializados.** Na primeira vez, o módulo abre com um convite
   para **Inicializar Itens NR-17** — cria os 23 itens normativos padrão que
   alimentam o Status GRO e o checklist. Sem isso, o painel fica vazio.
3. **Setores e funções cadastrados** (departamentos e cargos da empresa) — a AEP
   sugere setor e função a partir desses cadastros.
4. **(Opcional) Fotos dos postos de trabalho** para a Análise por IA e para as
   evidências da AEP Multi-Setor.

> 📸 **PRINT 01 — Estado inicial (Inicializar Itens NR-17)**
> **Onde:** módulo **Ergonomia** numa empresa que ainda não inicializou os itens.
> **O que precisa aparecer:** o cartão "Módulo de Ergonomia" com o botão
> **Inicializar Itens NR-17** e o texto "Serão criados os itens padrão da NR-17".
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**.
> **Uso:** só no tutorial, para mostrar o ponto de partida. Pode ser pulado no
> comercial.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Ergonomia**, o topo mostra o título **"Gestão de Risco Ergonômico"**,
a linha **"Fluxo GRO · NR-1 · NR-17 · ISO 45003"** e quatro botões: **Guia
Rápido**, **Atualizar**, **Novo Risco** e **Nova Ação**.

Logo abaixo ficam os **cartões de indicadores (KPIs)**:

| Cartão | O que mostra |
|---|---|
| **Status GRO Ergonômico** | Nível de maturidade + barra de **% de conformidade NR-17**; atendidos / parciais / pendentes. Clicável — abre os itens NR-17. |
| **Riscos Prioritários** | Quantos riscos estão **Críticos + Altos**. |
| **Ações Pendentes** | Quantas ações do plano ainda estão em aberto. |
| **Base Ergonômica** (aparece com análises feitas) | Análises Realizadas, Postos Avaliados, Riscos Identificados, Conformidade Média. |

Depois vêm as abas do **Fluxo GRO — Ciclo de Gestão de Risco**:

| Aba | Para que serve |
|---|---|
| **1. Avaliar Riscos (AEP)** | Ponto de entrada: cria a Análise Ergonômica Preliminar (modos **Função Única** e **Multi-Setor**). |
| **2. Inventário GRO** | Lista central de todos os riscos, com nível e ciclo GRO. |
| **3. Riscos Prioritários** | Só os riscos Altos e Críticos, que exigem ação. |
| **4. Plano de Ação** | As ações corretivas/preventivas e seu andamento. |
| **5. Monitoramento** | Mapa de risco + documentos de conformidade (Metodologia e Comunicação). |
| **Análise por IA** | Diagnóstico rápido por foto do posto (suporte). |
| **Base Ergonômica** | Histórico de todas as análises realizadas (suporte). |

> 📸 **PRINT 02 — Tela inicial do módulo**
> **Onde:** menu **Saúde & Segurança → Ergonomia**.
> **O que precisa aparecer:** título "Gestão de Risco Ergonômico", os quatro
> botões do topo, os cartões de KPI e a barra de abas do Fluxo GRO.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; Status GRO
> **Preventivo — 68% conformidade NR-17**; **2** riscos prioritários; **3** ações
> pendentes.
> **Ação filmada:** panorâmica lenta mostrando os KPIs e as 5 etapas numeradas.

---

## 5. Passo a passo por fluxo

Os fluxos seguem a ordem do **Guia Rápido** embutido no sistema (botão **Guia
Rápido**, no topo). Vale abri-lo no vídeo tutorial: ele tem os mesmos passos.

### Fluxo 0 — Abrir o Guia Rápido embutido

**Objetivo:** conhecer o módulo em 8 telas, sem sair da tela.
**Benefício:** o próprio sistema ensina o fluxo GRO em 5 etapas.

1. Clique em **Guia Rápido** no topo da página.
2. Navegue pelos passos: **visão geral**, as **5 etapas** do GRO, mais os extras
   **Análise por IA** e **Base Ergonômica**.
3. No último passo há o atalho para o **Manual completo** (PDF de referência).

> 📸 **PRINT 03 — Guia Rápido embutido**
> **Onde:** botão **Guia Rápido** (topo).
> **O que precisa aparecer:** a janela do guia com a barra de progresso, a
> navegação lateral (etapas 1 a 5 + extras) e o conteúdo de uma etapa.
> **Dados fictícios na tela:** passo **"Etapa 1 — Avaliar Riscos (AEP)"** aberto.
> **Ação filmada:** clicar em **Próximo** algumas vezes para mostrar a navegação.

> 💡 O guia é o mesmo roteiro deste manual — os prints de PRINT 05 em diante
> seguem a sequência dele.

---

### Fluxo 1 — Conferir o Status GRO (itens da NR-17)

**Objetivo:** ver, item a item, onde a empresa está conforme e onde não está.
**Benefício:** um raio-x da conformidade NR-17 por eixo (Físico, Cognitivo,
Organizacional), com o percentual calculado sozinho.

1. Clique no cartão **Status GRO Ergonômico** (ou no botão **Ver**).
2. Abre um painel lateral com os itens NR-17 agrupados por categoria.
3. Filtre por eixo nas abas **Todos / Físico / Cognitivo / Organizacional**.
4. Em cada item, ajuste o status: **Atendido**, **Parcial**, **Não Atendido** ou
   **Não Aplicável** — o percentual do topo se recalcula.
5. Clique num item para abrir o detalhe e registrar observações.

> 📸 **PRINT 04 — Status GRO Ergonômico (itens NR-17)**
> **Onde:** clique no cartão **Status GRO Ergonômico**.
> **O que precisa aparecer:** o painel lateral com as abas de eixo, os itens
> normativos (ex.: 17.3 Mobiliário, 17.5 Condições Ambientais) e o % de
> conformidade no cabeçalho.
> **Dados fictícios na tela:** aba **Físico**; item **"17.3.3 Características do
> assento" — Parcial**; item **"17.5.4 Temperatura efetiva" — Atendido**;
> **68% de conformidade**.
> **Ação filmada:** trocar a aba para **Físico** e mudar um item para
> **Atendido**, mostrando o % subir.

---

### Fluxo 2 — Etapa 1: Avaliar Riscos com a AEP (Função Única)

**Objetivo:** produzir a Análise Ergonômica Preliminar de uma função.
**Benefício:** o documento de entrada do GRO, com checklist do auditor e cálculo
de conformidade — e que já alimenta o Inventário GRO.

1. Abra a aba **1. Avaliar Riscos (AEP)** e deixe selecionado **Função Única**.
2. Percorra as **6 etapas** do formulário (com o **Assistente de IA** disponível
   em cada uma):
   - **Identificação** — empresa e CNPJ vêm preenchidos; escolha **Setor** e
     **Função**.
   - **Descrição** — descreva a atividade real e o ambiente.
   - **Riscos** — riscos físicos e cognitivos.
   - **Síntese** — classificação geral, pontos críticos e o **Checklist NR-17**
     (12 itens do auditor); marque a **necessidade de AET**.
   - **Ações** — recomendações de melhoria.
   - **Assinaturas** — responsável pela avaliação.
3. Clique em **Visualizar** para conferir o documento e, se estiver certo, em
   **Exportar PDF**.

> 📸 **PRINT 05 — AEP Função Única (formulário guiado)**
> **Onde:** Ergonomia → aba **1. Avaliar Riscos (AEP)** → **Função Única**.
> **O que precisa aparecer:** a trilha das 6 etapas no topo, o card do
> **Assistente de IA** e os campos da etapa **Identificação**.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; setor
> **Tecnologia**; função **Desenvolvedor Full Stack**.
> **Ação filmada:** avançar da etapa Identificação para a Descrição.

> 📸 **PRINT 06 — AEP: Síntese com Checklist NR-17**
> **Onde:** AEP → etapa **Síntese**.
> **O que precisa aparecer:** a classificação geral do risco, os pontos críticos
> e o **Checklist de Conformidade NR-17** com os 12 itens e o % no canto.
> **Dados fictícios na tela:** classificação **Médio**; **9/12 itens** marcados —
> **75%**; item pendente destacado (ex.: "Pausas de recuperação previstas").
> **Ação filmada:** marcar um item do checklist e mostrar o % recalcular.

> 📸 **PRINT 07 — Pré-visualização e exportação do PDF da AEP**
> **Onde:** AEP → botão **Visualizar** → **Exportar PDF**.
> **O que precisa aparecer:** o documento AEP montado (identificação, riscos,
> síntese, ações, assinaturas) e o botão **Exportar PDF**.
> **Dados fictícios na tela:** cabeçalho **AEP — Empresa Staging LTDA —
> Desenvolvedor Full Stack**.
> **Ação filmada:** rolar o preview e clicar em **Exportar PDF**.

> 💡 O PDF gerado é **arquivado automaticamente** no módulo **Documentos**, na
> pasta **Ergonomia** — não é preciso salvar à parte.

---

### Fluxo 3 — Etapa 1 (variante): AEP Multi-Setor

**Objetivo:** avaliar várias situações de trabalho de uma vez, a partir de fotos.
**Benefício:** cobre a empresa inteira por **Setor + Função**, com a IA
analisando as evidências e gerando uma avaliação por função.

1. Na aba **1. Avaliar Riscos (AEP)**, escolha **Multi-Setor**.
2. **Configuração inicial** — confira a empresa e o responsável pelo levantamento;
   adicione cada **Situação de Trabalho** (Setor + Função). Use **Duplicar** para
   funções parecidas no mesmo setor (o tal do GHE).
3. **Evidências** — envie fotos de cada situação.
4. **Análise por IA** — clique em **Analisar com IA**; o sistema processa todas as
   evidências.
5. **Revisão por Função** — revise e ajuste a avaliação de cada função.
6. **Síntese** e **Assinaturas** — feche e exporte, como na Função Única.

> 📸 **PRINT 08 — AEP Multi-Setor (situações de trabalho)**
> **Onde:** Ergonomia → aba **1. Avaliar Riscos (AEP)** → **Multi-Setor** →
> etapa **Configuração inicial**.
> **O que precisa aparecer:** a trilha de 6 etapas (ícones), a barra com
> "situações de trabalho" e a lista de situações Setor + Função.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; situações
> **Operações + Operadora de Produção**, **Tecnologia + Desenvolvedor**,
> **Administrativo + Analista Financeiro**.
> **Ação filmada:** adicionar uma situação e clicar em **Duplicar**.

> 💡 Não faça uma AEP "genérica da empresa". Faça **por função** — o auditor
> compara o trabalho **prescrito** com o **real** de cada posto.

---

### Fluxo 4 — Etapa 2: Inventário GRO

**Objetivo:** ter todos os riscos ergonômicos num só lugar, com nível calculado.
**Benefício:** a visão consolidada de onde estão os riscos — os que vêm da AEP e
os cadastrados à mão — para priorizar e agir.

1. Abra a aba **2. Inventário GRO**.
2. Veja os cartões do topo: **Total de Riscos**, **Risco Crítico**, **Sem Ação**
   e **Reavaliação**.
3. Na tabela, cada linha traz o risco, o tipo (**Físico** ou **Psicossocial**),
   a **fonte**, o **nível** e o **Ciclo GRO** (ajustável ali mesmo).
4. Filtre por **subtipo** e por **nível**.
5. Para incluir um risco manualmente, clique em **Novo Risco**.

**Cadastrar um risco (Novo Risco):**
- Informe **título**, **eixo** (Físico/Cognitivo/Organizacional), **severidade** e
  **probabilidade** (o nível sai do cruzamento).
- Opcional: vincule a um **item NR-17**, informe **setor/departamento**, os
  **impactos potenciais** e as **medidas** existentes e recomendadas.

> 📸 **PRINT 09 — Inventário GRO (tabela consolidada)**
> **Onde:** Ergonomia → aba **2. Inventário GRO**.
> **O que precisa aparecer:** os cartões (Total, Crítico, Sem Ação, Reavaliação),
> os filtros e a tabela com níveis coloridos e a coluna **Ciclo GRO**.
> **Dados fictícios na tela:** **Total 8**; **1 Crítico**; **2 Sem Ação**; linha
> **"Postura inadequada — Tecnologia · Desenvolvedor" — Alto**; linha **"Ruído
> acima do conforto — Operações" — Médio**.
> **Ação filmada:** filtrar por nível **Alto** e mudar o Ciclo GRO de um risco.

> 📸 **PRINT 10 — Cadastrar Risco (Novo Risco)**
> **Onde:** botão **Novo Risco** (topo ou dentro do Inventário).
> **O que precisa aparecer:** o formulário com título, eixo, severidade,
> probabilidade, setor e as listas de impactos e medidas.
> **Dados fictícios na tela:** título **"Postura inadequada em estação de
> trabalho"**; eixo **Físico**; severidade **Alto**; probabilidade **Médio**;
> setor **Tecnologia**; impacto **"LER/DORT"**.
> **Ação filmada:** preencher o título, escolher o eixo e clicar em **Cadastrar
> Risco**.

> 💡 Risco **Alto** ou **Crítico** sem ação vinculada fica marcado como
> **Sem Ação** — é o sinal de que falta um Plano de Ação.

---

### Fluxo 5 — Etapa 3: Riscos Prioritários

**Objetivo:** focar no que exige ação imediata.
**Benefício:** o sistema separa automaticamente os riscos Altos e Críticos, para
o RH não perder tempo garimpando a lista inteira.

1. Abra a aba **3. Riscos Prioritários**.
2. Veja só os riscos **Alto** e **Crítico**.
3. Para cada um, clique em **Criar Ação** para vincular um Plano de Ação.
4. Riscos sem ação vinculada ficam destacados como pendência.

> 📸 **PRINT 11 — Riscos Prioritários**
> **Onde:** Ergonomia → aba **3. Riscos Prioritários**.
> **O que precisa aparecer:** a lista filtrada de riscos Altos/Críticos e o botão
> **Criar Ação** / **Exportar**.
> **Dados fictícios na tela:** risco **"Postura inadequada — Tecnologia" — Alto**
> destacado como pendência; risco **"Levantamento manual de cargas — Operações" —
> Crítico**.
> **Ação filmada:** clicar em **Criar Ação** num risco crítico.

> 💡 Prazos sugeridos: **Crítico = 30 dias**, **Alto = 60 dias**. O sistema
> acompanha o vencimento.

---

### Fluxo 6 — Etapa 4: Plano de Ação

**Objetivo:** transformar risco em tarefa com responsável e prazo.
**Benefício:** cada risco vira uma ação 5W2H acompanhável — e ação atrasada
derruba o score de maturidade, sinalizando risco de não conformidade.

1. Abra a aba **4. Plano de Ação**.
2. Clique em **Nova Ação** (ou use o botão no topo da página).
3. Preencha: **título**, **tipo** (Corretiva/Preventiva/Melhoria), **prioridade**,
   **responsável**, **prazo** e **custo estimado**; vincule ao **risco** e/ou ao
   **item NR-17**.
4. Acompanhe o andamento das ações (Pendente → Em Andamento → Concluída).

> 📸 **PRINT 12 — Plano de Ação (lista)**
> **Onde:** Ergonomia → aba **4. Plano de Ação**.
> **O que precisa aparecer:** a lista de ações com prioridade, responsável, prazo
> e status.
> **Dados fictícios na tela:** ação **"Substituir cadeiras por modelo com
> regulagem"** — prioridade **Alta** — responsável **Bruno Carvalho** — prazo
> **30/11/2026** — **Em Andamento**.

> 📸 **PRINT 13 — Nova Ação (modelo 5W2H)**
> **Onde:** botão **Nova Ação** (topo) ou dentro do Plano de Ação.
> **O que precisa aparecer:** o formulário com tipo, prioridade, risco vinculado,
> responsável, prazo e custo estimado.
> **Dados fictícios na tela:** título **"Implementar pausas ativas"**; tipo
> **Corretiva**; prioridade **Alta**; responsável **Bruno Carvalho**; prazo
> **30/11/2026**; custo **R$ 0,00**.
> **Ação filmada:** preencher e clicar em **Cadastrar Ação**.

> 💡 Ao concluir uma ação vinculada a um risco Alto/Crítico, o risco fica marcado
> como **Reavaliar** no inventário — para confirmar se o nível caiu.

---

### Fluxo 7 — Etapa 5: Monitoramento (mapa + documentos)

**Objetivo:** enxergar a distribuição dos riscos e emitir os documentos da NR-01.
**Benefício:** o mapa mostra onde o risco se concentra e os dois documentos
técnicos ficam prontos para auditoria com um clique.

1. Abra a aba **5. Monitoramento**.
2. Veja o **Mapa de Risco Ergonômico** — distribuição por setor/posto; clique num
   setor para o detalhe.
3. No card **Documento de Metodologia (RQ-26)**, clique em **Gerar PDF** para a
   documentação técnica do programa (critérios, matriz, metodologia, limitações).
4. No card **Comunicação aos Trabalhadores (RQ-19/20)**, gere o comunicado formal
   de riscos e a participação dos trabalhadores.
5. Arquive os documentos — comprovam conformidade em fiscalização e ações
   trabalhistas.

> 📸 **PRINT 14 — Monitoramento: Mapa de Risco**
> **Onde:** Ergonomia → aba **5. Monitoramento**.
> **O que precisa aparecer:** o mapa de riscos por setor, com os setores
> coloridos por nível e um setor expandido.
> **Dados fictícios na tela:** setores **Operações (Alto)**, **Tecnologia
> (Médio)**, **Administrativo (Baixo)**; cargos analisados listados.
> **Ação filmada:** clicar no setor **Operações** para abrir o detalhe.

> 📸 **PRINT 15 — Documentos de conformidade (Metodologia + Comunicação)**
> **Onde:** aba **5. Monitoramento**, cards **Documento de Metodologia (RQ-26)**
> e **Comunicação aos Trabalhadores (RQ-19/20)**.
> **O que precisa aparecer:** os dois cards com o botão **Gerar PDF** e a
> referência normativa (RQ-26 · NR-1 §1.4.6 / RQ-19-20).
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; versão e data de
> geração visíveis.
> **Ação filmada:** clicar em **Gerar PDF** no Documento de Metodologia.

> 💡 Gere Metodologia e Comunicação sempre que o inventário mudar de forma
> relevante — a recomendação da casa é revisão **anual**, no mínimo.

---

### Fluxo 8 — Extra: Análise por IA (diagnóstico por foto)

**Objetivo:** um diagnóstico ergonômico rápido a partir de uma foto do posto.
**Benefício:** identifica riscos, estima a conformidade NR-17 e sugere ações em
segundos — ótimo ponto de partida antes da AEP formal.

1. Abra a aba **Análise por IA**.
2. Informe **Setor** e **Cargo** (obrigatórios) e, se quiser, a **Atividade**.
3. Arraste ou selecione **fotos** do posto de trabalho.
4. Clique em **Analisar com IA**.
5. Veja o resultado: **resumo**, **% de conformidade NR-17**, **riscos
   identificados** (por eixo e severidade) e **recomendações**.
6. Clique em **Criar Ação** numa recomendação (ou **Criar todas as ações**) e em
   **Salvar na Base Ergonômica**.

> 📸 **PRINT 16 — Análise por IA (foto → resultado)**
> **Onde:** Ergonomia → aba **Análise por IA**.
> **O que precisa aparecer:** os campos Setor/Cargo/Atividade, a área de upload de
> foto e, abaixo, o resultado com o % de conformidade, os riscos e as
> recomendações.
> **Dados fictícios na tela:** setor **Administrativo**; cargo **Analista
> Financeiro**; conformidade estimada **62%**; risco **"Monitor abaixo da linha
> dos olhos — Físico — Médio"**; recomendação **"Elevar o monitor com suporte"**.
> **Ação filmada:** soltar uma foto, clicar em **Analisar com IA** e depois em
> **Criar Ação** numa recomendação.

> 💡 A Análise por IA é **preliminar** e não substitui a AEP formal nem o parecer
> de um profissional habilitado (Ergonomista/CREFITO). O próprio resultado avisa
> isso.

---

### Fluxo 9 — Extra: Base Ergonômica (histórico)

**Objetivo:** consultar todas as análises já feitas.
**Benefício:** o arquivo histórico do programa — demonstra evolução em auditorias.

1. Abra a aba **Base Ergonômica**.
2. Veja as análises registradas, com data, setor e resultado.
3. Filtre por setor/função; **arquive** as que não forem mais relevantes.

> 📸 **PRINT 17 — Base Ergonômica**
> **Onde:** Ergonomia → aba **Base Ergonômica**.
> **O que precisa aparecer:** a lista de análises com data, setor/cargo e
> classificação de risco.
> **Dados fictícios na tela:** análise **Administrativo · Analista Financeiro —
> 28/09/2026 — Moderado**; análise **Operações · Operadora de Produção —
> Alto**.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, mostrando dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Fiscalização da NR-17 batendo à porta — e a ergonomia ainda em planilha?"* Abre com uma planilha bagunçada. | Imagem genérica de planilha |
| 8–22s | *"O YourEyes conduz o ciclo do GRO em 5 etapas: do risco ao documento pronto para o auditor."* | **PRINT 02** (tela inicial) + **PRINT 03** (guia) |
| 22–38s | *"Tire uma foto do posto e a IA aponta os riscos e a conformidade com a NR-17."* | **PRINT 16** (Análise por IA) |
| 38–54s | *"Cada risco vira uma AEP com o checklist do auditor e um plano de ação com responsável e prazo."* | **PRINT 06** (checklist) + **PRINT 13** (nova ação) |
| 54–70s | *"E os documentos da NR-01 — metodologia e comunicação aos trabalhadores — saem com um clique."* | **PRINT 14** (mapa) + **PRINT 15** (documentos) |
| 70–85s | *"YourEyes. Ergonomia sob controle, do risco à prova."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 6–9 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("vamos avaliar…", "agora eu crio a ação…").

1. **Abertura** — o que o módulo faz e para quem (**PRINT 02**).
2. **Abrir o Guia Rápido** e mostrar as 5 etapas (**PRINT 03**).
3. **(Opcional) Estado inicial** — inicializar itens NR-17 (**PRINT 01**).
4. **Conferir o Status GRO** por eixo (**PRINT 04**).
5. **Criar uma AEP Função Única** — formulário e checklist (**PRINT 05, 06**).
6. **Visualizar e exportar o PDF** da AEP (**PRINT 07**).
7. **Mostrar a AEP Multi-Setor** por situação de trabalho (**PRINT 08**).
8. **Abrir o Inventário GRO** e **cadastrar um risco** (**PRINT 09, 10**).
9. **Ver os Riscos Prioritários** e criar ação a partir de um crítico
   (**PRINT 11**).
10. **Abrir o Plano de Ação** e **criar uma nova ação** 5W2H (**PRINT 12, 13**).
11. **Monitoramento** — mapa e geração dos documentos (**PRINT 14, 15**).
12. **Análise por IA** por foto (**PRINT 16**).
13. **Base Ergonômica** — histórico (**PRINT 17**).
14. **Encerramento** — lembrar do botão **Guia Rápido** dentro do sistema.

> 💡 Dica de gravação: abra o **Guia Rápido** e siga a mesma ordem — o roteiro do
> tutorial foi montado na sequência das etapas dele.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Estado inicial / Inicializar Itens NR-17 (opcional, tutorial)
- [ ] **PRINT 02** — Tela inicial (KPIs + abas do Fluxo GRO)
- [ ] **PRINT 03** — Guia Rápido embutido
- [ ] **PRINT 04** — Status GRO Ergonômico (itens NR-17 por eixo)
- [ ] **PRINT 05** — AEP Função Única (formulário guiado)
- [ ] **PRINT 06** — AEP: Síntese com Checklist NR-17
- [ ] **PRINT 07** — Pré-visualização e exportação do PDF da AEP
- [ ] **PRINT 08** — AEP Multi-Setor (situações de trabalho)
- [ ] **PRINT 09** — Inventário GRO (tabela consolidada)
- [ ] **PRINT 10** — Cadastrar Risco (Novo Risco)
- [ ] **PRINT 11** — Riscos Prioritários
- [ ] **PRINT 12** — Plano de Ação (lista)
- [ ] **PRINT 13** — Nova Ação (5W2H)
- [ ] **PRINT 14** — Monitoramento: Mapa de Risco
- [ ] **PRINT 15** — Documentos de conformidade (Metodologia + Comunicação)
- [ ] **PRINT 16** — Análise por IA (foto → resultado)
- [ ] **PRINT 17** — Base Ergonômica

---

## 9. Erros comuns / dúvidas frequentes

- **"O módulo abriu vazio / só tem um botão."** Os itens da NR-17 ainda não foram
  inicializados. Clique em **Inicializar Itens NR-17** (Fluxo do PRINT 01).
- **"A AEP não puxou a empresa e o CNPJ."** Confira a **empresa ativa** no topo
  do sistema — a AEP preenche a partir dela.
- **"Não consigo escolher a função na AEP."** A função vem dos **cargos**
  cadastrados; se o setor não tiver cargos, cadastre-os antes (ou selecione
  "Todas as funções").
- **"Um risco Alto ficou marcado como Sem Ação."** É proposital: risco Alto ou
  Crítico precisa de **Plano de Ação vinculado** (Fluxos 5 e 6).
- **"A Análise por IA não roda."** É preciso **pelo menos uma foto** e informar
  **Setor** e **Cargo** para salvar na base. Fotos até 20 MB (JPG/PNG/WebP).
- **"O PDF da AEP sumiu."** Ele é **arquivado automaticamente** no módulo
  **Documentos → pasta Ergonomia**, além do download.
- **"Aparece um selo 'Reavaliar' no inventário."** A ação vinculada ao risco foi
  concluída — reavalie se o nível caiu e atualize o Ciclo GRO.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução.

Para conferir o conteúdo com o módulo aberto, use o **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves**, empresa **Empresa Staging LTDA**:

1. Abra **Saúde & Segurança → Ergonomia** e confira se a tela inicial, os KPIs e
   as 5 etapas do Fluxo GRO batem com o **PRINT 02** e o **mapa da tela** (seção 4).
2. Clique em **Guia Rápido** (PRINT 03) e confira se os passos deste manual
   seguem a mesma sequência.
3. Percorra as abas **1 a 5** e os extras **Análise por IA** e **Base
   Ergonômica**, conferindo cada fluxo e marcador de print.
4. Aprovado o **formato**, replico o mesmo padrão para os próximos módulos, nos
   lotes que você priorizar.
