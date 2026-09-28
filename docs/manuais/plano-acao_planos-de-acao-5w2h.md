# Manual do módulo — Plano de Ação (5W2H)

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e no mesmo nível de profundidade do piloto aprovado
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial deste módulo.

- **Onde fica no menu:** seção **Planejamento & Gestão → Plano de Ação**
  (rota `/plano-acao`).
- **Para quem é:** RH, SST, gestores e coordenadores — qualquer pessoa que
  precise transformar um problema ou um alerta em algo com **responsável, prazo
  e acompanhamento**.
- **Em uma frase:** organiza as ações da empresa com a metodologia **5W2H**
  (o quê, por quê, onde, quando, quem, como e quanto), prioriza cada uma pela
  **Matriz GUT** e liga tudo aos **alertas dos outros módulos** (Ponto,
  Ergonomia, Ouvidoria, EPIs, SST, Psicossocial e mais).
- **Importante:** este é o **destino comum** dos alertas do sistema. Quando um
  módulo aponta um risco (ex.: "atrasos recorrentes" no Ponto), ele oferece o
  botão **Criar Ação** — e a ação nasce aqui, já marcada com a origem, para não
  se perder.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Nada mais se perde no e-mail ou na cabeça de alguém.** Todo problema vira
  uma **ação com dono e prazo**. Cada uma recebe um **código único**
  (ex.: `ACO-00012`) e fica visível para todo mundo que precisa acompanhar.
- **Prioridade sem "achismo".** A **Matriz GUT** (Gravidade × Urgência ×
  Tendência) dá uma nota de 1 a 125 a cada ação e a classifica sozinha em
  **Imediato, Urgente, Médio ou Baixo** — o que é mais grave sobe para o topo
  da lista automaticamente.
- **Plano completo em uma tela.** A metodologia **5W2H** obriga a responder as
  sete perguntas que fazem uma ação sair do papel: *o quê, por quê, onde,
  quando, quem, como e quanto*. Sem campo esquecido.
- **Alertas viram ação com um clique.** Um atraso no Ponto, um risco na
  Ergonomia, uma reclamação na Ouvidoria ou uma não conformidade na SST podem
  virar uma ação 5W2H **direto de dentro daquele módulo** — e a ação já chega
  aqui com a origem registrada.
- **Assistente de IA que escreve o plano com você.** A IA sugere ações a partir
  de um problema descrito em texto, preenche cada campo do 5W2H e propõe a nota
  GUT — você só revisa e confirma.
- **Acompanhamento de verdade.** Cada ação tem **tarefas**, **comentários**,
  **histórico** completo (quem fez o quê e quando) e uma **barra de progresso**
  que sobe sozinha conforme as tarefas são concluídas.
- **Visão de gestão em segundos.** Cartões no topo mostram quantas ações estão
  **pendentes, em andamento, atrasadas e concluídas**, além de um **Índice de
  Execução** (o percentual do que já foi concluído).

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Ação** | Uma iniciativa para resolver um problema ou aproveitar uma oportunidade. É a unidade central do módulo. |
| **5W2H** | O método por trás de cada ação: **W**hat (o quê), **W**hy (por quê), **W**here (onde), **W**hen (quando), **W**ho (quem), **H**ow (como) e **H**ow much (quanto custa). |
| **Matriz GUT** | A forma de priorizar: dá notas de 1 a 5 para **G**ravidade, **U**rgência e **T**endência. O **Score** é a multiplicação das três (G × U × T). |
| **Score GUT** | O número de 1 a 125 que resume a prioridade. Quanto maior, mais urgente. |
| **Prioridade** | A "etiqueta" que o Score gera sozinho: **Imediato** (64–125), **Urgente** (27–63), **Médio** (8–26) e **Baixo** (1–7). |
| **Origem** | De onde a ação nasceu: criada à mão (**Manual**) ou a partir de um alerta de outro módulo (Ponto, Ergonomia, Ouvidoria, EPIs, SST…). |
| **Tipo** | A natureza da ação: **Corretiva** (conserta algo que deu errado), **Preventiva** (evita que aconteça) ou **Melhoria** (aperfeiçoa o que já funciona). |
| **Tarefa** | Um passo operacional dentro de uma ação. Marcar tarefas como concluídas faz o **progresso** da ação subir. |
| **Progresso** | A barra que mostra o quanto da ação já foi feito (0% a 100%). |
| **Minha Caixa** | A visão pessoal: as ações em que **você é o responsável** e as que **você criou**. |
| **Assistente IA** | O ajudante que sugere ações, escreve o 5W2H e propõe a nota GUT a partir de um texto. |
| **Código da ação** | O identificador único, gerado automaticamente no padrão `ACO-00001`. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Estar logado com uma empresa selecionada.** As ações pertencem à empresa
   ativa no topo do sistema (nos vídeos, **Empresa Staging LTDA**).
2. **Saber quem serão os responsáveis.** O campo **Quem** puxa os
   colaboradores/usuários cadastrados — tenha pelo menos as personas de
   demonstração no ambiente.
3. **(Opcional, mas ótimo para o vídeo) Ter um alerta em outro módulo.** Para
   filmar a ligação "alerta → ação", deixe preparado um alerta no **Ponto**,
   **Ergonomia** ou **Ouvidoria** — é ali que aparece o botão **Criar Ação**.

> 📸 **PRINT 01 — Estado vazio (opcional, só para o tutorial)**
> **Onde:** módulo **Plano de Ação** sem nenhuma ação cadastrada.
> **O que precisa aparecer:** os cartões de indicadores zerados e o cartão
> pontilhado **"Nenhuma ação encontrada"** com o ícone de alvo.
> **Uso:** só no tutorial, para mostrar o ponto de partida. Pode ser pulado no
> comercial.

> 💡 Este módulo **não tem um botão "Guia Rápido"** embutido (diferente do
> Ponto). O passo a passo abaixo é o próprio guia — siga a ordem dos fluxos.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Plano de Ação**, o topo mostra o título **"Plano de Ação"** com o
ícone de alvo e a linha **"Gestão estratégica de ações com metodologia 5W2H e
Matriz GUT"**. À direita ficam dois botões: **Filtros** e **Nova Ação**.

Logo abaixo aparecem, em ordem:

| Área | Para que serve |
|---|---|
| **5 cartões de indicadores** | Total de Ações, Pendentes, Em Andamento, Atrasadas e Concluídas. **São clicáveis** — clicar filtra a lista. |
| **Índice de Execução** | A barra que mostra o percentual de ações já concluídas. |
| **Assistente IA** | O painel escuro onde você descreve um problema e recebe sugestões de ação prontas. |
| **Busca + chips rápidos** | Campo de busca e etiquetas de atalho para Status (Pendentes, Em andamento, Concluídas) e Prioridade (🔴 Imediato, 🟠 Urgente). |
| **3 abas** | **Todas**, **Minha Caixa** e **Críticas** (ver tabela abaixo). |

As três abas do módulo:

| Aba | O que mostra |
|---|---|
| **Todas** | Todas as ações da empresa, ordenadas pela prioridade (maior Score GUT primeiro). |
| **Minha Caixa** | Só as suas: as que **você é responsável** e as que **você criou** (com um contador no título). |
| **Críticas** | Só as ações **Imediato**, **Urgente** ou **atrasadas** (com o prazo vencido). |

> 📸 **PRINT 02 — Tela inicial do módulo**
> **Onde:** menu **Planejamento & Gestão → Plano de Ação**.
> **O que precisa aparecer:** título, os 5 cartões de indicadores, a barra
> **Índice de Execução**, o painel **Assistente IA** e as 3 abas.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; indicadores
> como **Total 14**, **Pendentes 5**, **Em Andamento 4**, **Atrasadas 2**,
> **Concluídas 3**; Índice de Execução **21%**.
> **Ação filmada:** panorâmica lenta de cima para baixo, terminando nas abas.

> 💡 Os cartões de indicadores funcionam como **filtro**: clicar em
> **"Atrasadas"** já leva para a aba **Críticas**; clicar em **"Pendentes"**
> filtra a lista por esse status. Clicar de novo no mesmo cartão limpa o filtro.

---

## 5. Passo a passo por fluxo

### Fluxo 1 — Criar uma ação manualmente (5W2H + GUT)

**Objetivo:** registrar uma ação preenchendo as sete perguntas do 5W2H e
priorizá-la pela Matriz GUT.
**Benefício:** o plano nasce completo — com dono, prazo, custo e prioridade — e
recebe um código único para acompanhamento.

1. Clique em **Nova Ação** (canto superior direito).
2. Preencha **O QUÊ** (título — obrigatório), escolha o **Tipo** (Corretiva,
   Preventiva ou Melhoria) e a **Origem** (deixe **Manual** se você está
   criando do zero).
3. Escreva a **Descrição** e o **POR QUÊ** (a justificativa).
4. Preencha **ONDE** (setor/processo), **QUANDO** (prazo), **QUEM**
   (responsável) e **QUANTO** (custo estimado em R$).
5. Descreva **COMO** a ação será executada.
6. Ajuste a **Matriz GUT** com os três controles deslizantes (**Gravidade**,
   **Urgência** e **Tendência**, de 1 a 5). O **Score** e a **Prioridade**
   aparecem sozinhos no canto.
7. Clique em **Criar Ação**.

> 📸 **PRINT 03 — Modal "Nova Ação 5W2H"**
> **Onde:** botão **Nova Ação** (topo).
> **O que precisa aparecer:** o cabeçalho roxo **"Nova Ação 5W2H"** com o selo
> **"IA disponível em cada campo"**, e os campos O QUÊ, Tipo, Origem, Descrição,
> POR QUÊ, ONDE, QUANDO, QUEM, QUANTO e COMO.
> **Dados fictícios na tela:** título **"Implementar pausas ativas na Produção"**,
> tipo **Preventiva**, origem **Manual**, ONDE **"Setor de Produção"**, QUANDO
> **31/10/2026**, QUEM **Bruno Carvalho**, QUANTO **R$ 1.500,00**.
> **Ação filmada:** preencher o título e, em seguida, clicar no ícone ✨ ao lado
> de um campo para a IA sugerir o texto.

> 📸 **PRINT 04 — Matriz GUT dentro do modal**
> **Onde:** parte de baixo do modal **Nova Ação**.
> **O que precisa aparecer:** os três controles deslizantes (Gravidade, Urgência,
> Tendência) e, no canto, o **Score** e a etiqueta de **Prioridade** coloridos.
> **Dados fictícios na tela:** Gravidade **4**, Urgência **4**, Tendência **3**,
> **Score 48**, prioridade **Urgente** (laranja).
> **Ação filmada:** arrastar um controle e mostrar o Score e a Prioridade
> mudando na hora.

> 💡 Ao lado de vários campos há o ícone **✨ (IA)** — ele sugere o texto daquele
> campo com base no título e na descrição. Preencha o **título primeiro** para a
> IA ter contexto.

---

### Fluxo 2 — Deixar a IA sugerir as ações

**Objetivo:** partir de um problema descrito em texto e receber ações prontas.
**Benefício:** transforma uma preocupação solta ("temos muitos atrasos") em uma
ou várias ações estruturadas, criadas em lote.

1. No painel **Assistente IA**, escreva o problema, risco ou situação no campo
   de texto.
2. Clique em **Gerar Sugestões**.
3. A IA devolve uma lista de **ações sugeridas**, cada uma com tipo e
   prioridade. Marque as caixas das que interessam (ou **Selecionar todas**).
4. Clique em **Criar N Ação(ões) no Plano** — elas entram na lista já como
   ações reais, marcadas como geradas pela IA.

> 📸 **PRINT 05 — Assistente IA com sugestões**
> **Onde:** painel escuro **Assistente IA**, na tela inicial.
> **O que precisa aparecer:** o texto do problema no campo, o botão **Gerar
> Sugestões** e, abaixo, a lista de sugestões com caixas de seleção e a barra
> **"Criar N Ação(ões) no Plano"**.
> **Dados fictícios na tela:** contexto digitado **"Aumento de atrasos no turno
> da tarde da Produção"**; sugestões como **"Revisar a escala do turno da tarde"**
> e **"Criar rotina de conferência de ponto às 14h"**, com 2 selecionadas.
> **Ação filmada:** digitar o problema, clicar em Gerar Sugestões, marcar duas e
> clicar em Criar.

> 💡 A IA é um ponto de partida, não a palavra final. Depois de criada, toda ação
> pode ser aberta e ajustada normalmente (inclusive a nota GUT).

---

### Fluxo 3 — Ler e filtrar a lista de ações

**Objetivo:** encontrar rapidamente a ação certa e enxergar as prioridades.
**Benefício:** a lista já vem ordenada pela urgência (maior Score GUT no topo) e
os filtros isolam exatamente o que você procura.

1. Na aba **Todas**, veja os cartões de ação: cada um mostra o **Score GUT** à
   esquerda, o **código**, as etiquetas de **prioridade** e **status**, o
   **título**, o **responsável**, o **prazo**, a **origem** e a **barra de
   progresso**.
2. Use a **busca** para procurar por código, título, descrição ou responsável.
3. Use os **chips rápidos** para filtrar por status ou prioridade, ou abra
   **Filtros** para o painel completo (Período/Prazo, Responsável, Status,
   Prioridade e Origem).
4. Clique em qualquer cartão para abrir o **detalhe** da ação.

> 📸 **PRINT 06 — Lista de ações (aba Todas)**
> **Onde:** Plano de Ação → aba **Todas**.
> **O que precisa aparecer:** vários cartões de ação com Score GUT, códigos,
> etiquetas de prioridade/status coloridas, e pelo menos um com a etiqueta
> vermelha **"Atrasada"**.
> **Dados fictícios na tela:**
> - **ACO-00012** — "Implementar pausas ativas na Produção" — GUT **48** —
>   **Urgente** — Em Andamento — responsável **Bruno Carvalho** — 60%.
> - **ACO-00009** — "Substituir EPIs vencidos do almoxarifado" — GUT **75** —
>   **Imediato** — Pendente — origem **EPIs** — etiqueta **Atrasada**.
> - **ACO-00007** — "Rever escala do turno da tarde" — GUT **27** — **Médio** —
>   origem **Ponto**.
> **Ação filmada:** digitar "produção" na busca e depois clicar no chip
> **🔴 Imediato**.

> 📸 **PRINT 07 — Busca e painel de Filtros aberto**
> **Onde:** topo da lista, com o botão **Filtros** acionado.
> **O que precisa aparecer:** o campo de busca, os chips de Status e Prioridade e
> o painel de Filtros com Período (Prazo), Responsável, Status, Prioridade e
> Origem.
> **Dados fictícios na tela:** filtro de **Origem = Ponto** selecionado e
> prioridade **Urgente** marcada.

> 💡 As ações são ordenadas automaticamente pelo **Score GUT** (maior primeiro).
> Você não precisa ordenar à mão — o que é mais crítico já aparece no topo.

---

### Fluxo 4 — Minha Caixa (o que é meu)

**Objetivo:** ver rapidamente só as suas ações.
**Benefício:** cada pessoa foca no que precisa executar ou acompanhar, sem se
perder na lista geral.

1. Abra a aba **Minha Caixa** (o número ao lado mostra quantas ações são suas).
2. Alterne entre **Sou Responsável** (ações atribuídas a você) e **Criadas por
   mim** (ações que você abriu).
3. Clique em qualquer item para abrir o detalhe.

> 📸 **PRINT 08 — Aba Minha Caixa**
> **Onde:** Plano de Ação → aba **Minha Caixa**.
> **O que precisa aparecer:** os dois sub-botões **Sou Responsável** e **Criadas
> por mim** (com contadores) e a lista de itens.
> **Dados fictícios na tela:** logada como **Marina Alves**; em "Criadas por mim",
> a ação **ACO-00012**; em "Sou Responsável", uma ação com prazo próximo.

---

### Fluxo 5 — Ações Críticas

**Objetivo:** focar no que não pode esperar.
**Benefício:** reúne, numa aba só, tudo que é **Imediato**, **Urgente** ou já
está **atrasado**.

1. Abra a aba **Críticas** (ou clique no cartão **Atrasadas** no topo).
2. Trate primeiro as ações com etiqueta **Atrasada** e prioridade mais alta.

> 📸 **PRINT 09 — Aba Críticas**
> **Onde:** Plano de Ação → aba **Críticas**.
> **O que precisa aparecer:** só as ações urgentes/imediatas/atrasadas, com as
> etiquetas vermelhas e laranja em destaque.
> **Dados fictícios na tela:** **ACO-00009** (Imediato, Atrasada) e **ACO-00012**
> (Urgente) no topo.

---

### Fluxo 6 — Abrir uma ação e navegar pelo 5W2H

**Objetivo:** ver e editar todos os detalhes de uma ação.
**Benefício:** o 5W2H inteiro fica visível em cartões; clicar em qualquer um
abre a edição.

1. Clique em uma ação na lista — abre a tela de **detalhe**.
2. No topo, veja o **código**, o **status**, a **prioridade** e a **origem**,
   além da **barra de progresso** com o número de tarefas concluídas.
3. Abaixo ficam os **cartões 5W2H**: **Quem**, **Onde**, **Por quê**, **Como**,
   **Quanto**, **Matriz GUT** e **Origem**. Clique em qualquer cartão para
   **editar** aquele campo.
4. Para editar a nota GUT sem sair da tela, use o botão **Editar** dentro do
   cartão **Matriz GUT**.

> 📸 **PRINT 10 — Detalhe da ação (cartões 5W2H)**
> **Onde:** Plano de Ação → clicar em uma ação.
> **O que precisa aparecer:** o cabeçalho com código, etiquetas e os botões
> **Concluir Ação / Editar / Arquivar / Excluir**; a barra de progresso; e os
> cartões Quem, Onde, Por quê, Como, Quanto, Matriz GUT e Origem.
> **Dados fictícios na tela:** **ACO-00012** — "Implementar pausas ativas na
> Produção" — Em Andamento — Urgente — **Quem: Bruno Carvalho** — **Onde: Setor
> de Produção** — **Quanto: R$ 1.500,00** — progresso **60%** — **2 de 3
> tarefas**.
> **Ação filmada:** clicar no cartão **Quem** para abrir a edição.

> 💡 O **progresso** não se digita: ele sobe sozinho conforme as **tarefas** são
> marcadas como concluídas (ver Fluxo 7).

---

### Fluxo 7 — Tarefas operacionais dentro da ação

**Objetivo:** quebrar a ação em passos e acompanhar a execução.
**Benefício:** cada tarefa também é um mini-5W2H; concluir tarefas move a barra
de progresso da ação.

1. No detalhe da ação, abra a aba **Tarefas**.
2. Clique em **Adicionar** e preencha a nova tarefa no formato **5W2H**
   (O quê, Por quê, Onde, Quando, Quem, Como, Quanto e Prioridade).
3. Marque a **caixa** ao lado de uma tarefa para concluí-la — a barra de
   progresso da ação se atualiza.
4. Tarefas com prazo vencido ganham a etiqueta **Atrasada**.

> 📸 **PRINT 11 — Aba Tarefas**
> **Onde:** detalhe da ação → aba **Tarefas**.
> **O que precisa aparecer:** a lista de tarefas com caixas de seleção,
> prioridades e, ao menos uma, concluída (riscada) e uma **Atrasada**.
> **Dados fictícios na tela:** tarefas **"Levantar horários de pico"** (concluída),
> **"Definir roteiro das pausas"** (em andamento) e **"Treinar os líderes"**
> (Atrasada).

> 📸 **PRINT 12 — Modal "Nova Tarefa (5W2H)"**
> **Onde:** aba Tarefas → botão **Adicionar**.
> **O que precisa aparecer:** o formulário com os campos O quê, Por quê, Onde,
> Quando, Quem, Como, Quanto e Prioridade.
> **Dados fictícios na tela:** O quê **"Treinar os líderes de turno"**, Quem
> **Camila Duarte**, Quando **20/10/2026**, Prioridade **Urgente**.

> 💡 Concluir todas as tarefas leva o progresso a 100%, mas quem encerra a ação é
> o botão **Concluir Ação** (Fluxo 9) — assim ninguém fecha um plano por engano.

---

### Fluxo 8 — Comentários e histórico

**Objetivo:** conversar sobre a ação e ter a trilha completa do que aconteceu.
**Benefício:** o contexto fica junto da ação (não some no chat) e o histórico
guarda cada mudança, com autor e data.

1. Na aba **Comentários**, escreva uma mensagem e envie (também dá para enviar
   com **Ctrl/Cmd + Enter**).
2. Na aba **Histórico**, acompanhe a linha do tempo: criação, edições, mudança
   de status, tarefas concluídas, comentários e trocas de responsável.

> 📸 **PRINT 13 — Aba Comentários**
> **Onde:** detalhe da ação → aba **Comentários**.
> **O que precisa aparecer:** o campo de novo comentário e a lista de mensagens
> com autor e data.
> **Dados fictícios na tela:** comentário de **Marina Alves** — *"Pausas
> alinhadas com a liderança; começamos na semana que vem."*

> 📸 **PRINT 14 — Aba Histórico**
> **Onde:** detalhe da ação → aba **Histórico**.
> **O que precisa aparecer:** a linha do tempo com ícones coloridos por tipo de
> evento (criação, edição, tarefa concluída…).
> **Dados fictícios na tela:** *"Ação criada"* por **Marina Alves**;
> *"Tarefa concluída"*; *"Status alterado para Em Andamento"*.

> 💡 O histórico é automático — ninguém precisa preencher. Ele é a prova de quem
> fez o quê, útil em auditorias e prestação de contas.

---

### Fluxo 9 — Concluir, arquivar ou excluir uma ação

**Objetivo:** encerrar o ciclo de vida da ação com segurança.
**Benefício:** concluir e arquivar mantêm o registro; excluir só acontece com
uma confirmação explícita, para nada sumir por acidente.

1. **Concluir:** clique em **Concluir Ação** (verde) — a ação vai para 100% e
   status **Concluída**. Se houver tarefas em aberto, o sistema avisa e as
   mantém como estão.
2. **Arquivar:** clique em **Arquivar** — a ação sai das listagens ativas mas
   continua disponível nos filtros de arquivadas; dá para **Desarquivar** depois.
3. **Excluir:** clique em **Excluir** (vermelho). Como é **irreversível** (apaga
   ação, tarefas, comentários e histórico), o sistema pede que você **digite a
   palavra EXCLUIR** para confirmar.

> 📸 **PRINT 15 — Ações de encerramento (Concluir / Arquivar / Excluir)**
> **Onde:** cabeçalho do detalhe da ação.
> **O que precisa aparecer:** os botões **Concluir Ação**, **Editar**,
> **Arquivar** e **Excluir**; e, sobreposta, a caixa de confirmação de exclusão
> pedindo para digitar **EXCLUIR**.
> **Dados fictícios na tela:** confirmação sobre a ação **ACO-00007**.
> **Ação filmada:** clicar em **Concluir Ação** e mostrar o progresso ir a 100%.

> 💡 Prefira **Arquivar** a **Excluir**. Arquivar limpa a lista sem perder a
> história da ação; excluir é definitivo.

---

### Fluxo 10 — Entender a Matriz GUT

**Objetivo:** saber por que uma ação recebeu determinada prioridade.
**Benefício:** a priorização deixa de ser opinião — vira um cálculo transparente
que todos entendem.

1. No detalhe da ação, clique no título **Matriz GUT** do cartão.
2. Veja o **Score** central, a fórmula **G × U × T**, a explicação de cada nota
   (Gravidade, Urgência, Tendência) e a **escala de prioridades**.

> 📸 **PRINT 16 — Modal Matriz GUT**
> **Onde:** detalhe da ação → clicar em **Matriz GUT**.
> **O que precisa aparecer:** o Score no círculo colorido, a fórmula
> **G × U × T**, os cartões de cada critério e a legenda (64–125 Imediato /
> 27–63 Urgente / 8–26 Médio / 1–7 Baixo).
> **Dados fictícios na tela:** Gravidade **4**, Urgência **4**, Tendência **3**,
> **Score 48**, prioridade **Urgente**.

> 💡 Regra de bolso: **Gravidade** = tamanho do dano; **Urgência** = pressão do
> tempo; **Tendência** = o quanto piora se ninguém agir.

---

### Fluxo 11 — Criar uma ação a partir de um alerta de outro módulo

**Objetivo:** transformar um alerta (Ponto, Ergonomia, Ouvidoria, EPIs, SST,
Psicossocial, Atestados, Documentos, Estratégia…) em uma ação 5W2H.
**Benefício:** o problema detectado por outro módulo vira ação sem retrabalho —
e já chega ao Plano de Ação **etiquetado com a origem**, para se saber de onde
veio.

1. No módulo de origem (ex.: **Ponto → Compliance → Alertas**), localize o
   alerta e clique em **Criar Ação**.
2. Abre o **Assistente IA**: clique em **Gerar Sugestões de Ação com IA** — a IA
   lê o alerta e propõe até 3 ações já com 5W2H (Por quê, Onde, Como).
3. Selecione a melhor sugestão e clique em **Criar Ação Selecionada**.
4. Use **Ver no Plano de Ação** para ir direto para a ação recém-criada — ela
   aparece com a etiqueta da **origem** (ex.: ⏰ Ponto).

> 📸 **PRINT 17 — Criar ação a partir de um alerta**
> **Onde:** dentro de outro módulo (ex.: **Ponto → Alertas**), botão **Criar
> Ação** → modal **"Criar Ação — Assistente IA"**.
> **O que precisa aparecer:** o bloco cinza com o alerta de origem, o botão
> **Gerar Sugestões de Ação com IA** e as sugestões 5W2H para selecionar.
> **Dados fictícios na tela:** alerta **"Atrasos recorrentes — turno da tarde"**,
> origem **ponto**; sugestão selecionada **"Rever escala do turno da tarde"**.
> **Ação filmada:** clicar em Gerar Sugestões, escolher uma e clicar em **Criar
> Ação Selecionada**, depois **Ver no Plano de Ação**.

> 💡 No Plano de Ação, filtre por **Origem** (ex.: Ponto, Ergonomia) para ver
> tudo que nasceu de cada módulo — ótimo para relatórios por área.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, mostrando dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Quantos problemas na sua empresa morrem num e-mail sem dono e sem prazo?"* Abre com uma caixa de entrada lotada. | Imagem genérica de e-mails |
| 8–22s | *"No YourEyes, todo problema vira uma ação 5W2H — com responsável, prazo e prioridade calculada sozinha."* | **PRINT 03** (Nova Ação) + **PRINT 04** (Matriz GUT) |
| 22–36s | *"O que é mais grave sobe para o topo. E você acompanha tudo numa tela só."* | **PRINT 02** (indicadores) + **PRINT 06** (lista priorizada) |
| 36–50s | *"Um alerta no Ponto, na Ergonomia ou na Ouvidoria? Vira ação com um clique."* | **PRINT 17** (alerta → ação) |
| 50–64s | *"E uma IA escreve o plano com você, do problema à priorização."* | **PRINT 05** (Assistente IA) |
| 64–80s | *"Do problema ao resultado, com dono e prazo. YourEyes Plano de Ação."* Logo. | **PRINT 10** (detalhe com progresso) |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 5–8 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("agora eu crio uma ação…", "vamos priorizar…").

1. **Abertura** — o que o módulo faz e para quem (**PRINT 02**).
2. **Criar uma ação manual** com 5W2H e usar o ✨ da IA num campo (**PRINT 03**).
3. **Priorizar pela Matriz GUT** e ver o Score/Prioridade mudarem (**PRINT 04**).
4. **Deixar a IA sugerir ações** a partir de um problema (**PRINT 05**).
5. **Ler e filtrar a lista**: busca, chips e painel de Filtros (**PRINT 06, 07**).
6. **Minha Caixa** e **Críticas** (**PRINT 08, 09**).
7. **Abrir o detalhe** e navegar pelos cartões 5W2H (**PRINT 10**).
8. **Adicionar tarefas** e ver o progresso subir (**PRINT 11, 12**).
9. **Comentar** e conferir o **histórico** (**PRINT 13, 14**).
10. **Concluir / arquivar / excluir** com a confirmação (**PRINT 15**).
11. **Entender a Matriz GUT** no modal (**PRINT 16**).
12. **Criar uma ação a partir de um alerta** de outro módulo (**PRINT 17**).
13. **Encerramento** — reforçar o filtro por **Origem** para relatórios por área.

> 💡 Dica de gravação: mantenha **Marina Alves** logada e a **Empresa Staging
> LTDA** ativa em todos os prints, para dar continuidade com os demais vídeos.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Estado vazio (opcional, só tutorial)
- [ ] **PRINT 02** — Tela inicial (indicadores + Índice + abas)
- [ ] **PRINT 03** — Modal Nova Ação 5W2H
- [ ] **PRINT 04** — Matriz GUT dentro do modal
- [ ] **PRINT 05** — Assistente IA com sugestões
- [ ] **PRINT 06** — Lista de ações (aba Todas)
- [ ] **PRINT 07** — Busca + painel de Filtros
- [ ] **PRINT 08** — Aba Minha Caixa
- [ ] **PRINT 09** — Aba Críticas
- [ ] **PRINT 10** — Detalhe da ação (cartões 5W2H)
- [ ] **PRINT 11** — Aba Tarefas
- [ ] **PRINT 12** — Modal Nova Tarefa (5W2H)
- [ ] **PRINT 13** — Aba Comentários
- [ ] **PRINT 14** — Aba Histórico
- [ ] **PRINT 15** — Concluir / Arquivar / Excluir
- [ ] **PRINT 16** — Modal Matriz GUT
- [ ] **PRINT 17** — Criar ação a partir de um alerta

---

## 9. Erros comuns / dúvidas frequentes

- **"Minha ação sumiu da lista."** Provavelmente foi **arquivada**. Use os
  filtros para ver as arquivadas, ou confira se a **empresa ativa** no topo é a
  certa (as ações pertencem à empresa selecionada).
- **"Não consigo excluir a ação."** A exclusão é irreversível, então o sistema
  exige que você **digite EXCLUIR** no campo de confirmação. Sem isso, o botão
  fica bloqueado.
- **"A prioridade mudou sozinha."** A prioridade é calculada pela **Matriz GUT**
  (Gravidade × Urgência × Tendência). Se você alterar uma dessas notas, o Score
  e a etiqueta de prioridade se recalculam.
- **"O progresso não sobe."** O progresso vem das **tarefas concluídas**. Abra a
  aba **Tarefas**, cadastre os passos e marque as caixas conforme forem sendo
  feitos.
- **"A IA não gerou sugestões."** No modal de campo, preencha o **título antes** —
  a IA precisa de contexto. No painel Assistente, descreva o problema no campo de
  texto antes de clicar em **Gerar Sugestões**.
- **"Como sei de onde a ação veio?"** Pela etiqueta de **Origem** no cartão e no
  cartão **Origem** do detalhe. Para ver todas de um módulo, filtre por
  **Origem** (ex.: Ponto, Ergonomia, Ouvidoria).
- **"Concluí a ação mas havia tarefas em aberto."** O sistema avisa e **mantém**
  as tarefas como estavam — concluir a ação não apaga nem força as tarefas.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/plano-acao_planos-de-acao-5w2h.md` no projeto.
2. Se quiser conferir cada print antes de gravar, entre no **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/) logado como **Marina
   Alves**, empresa **Empresa Staging LTDA**, e siga o menu **Planejamento &
   Gestão → Plano de Ação** comparando cada tela com os marcadores 📸 deste
   manual.
3. Confira se o passo a passo, os benefícios e os prints refletem como você quer
   conduzir os vídeos. Aprovado o **formato**, replico o mesmo padrão para os
   próximos módulos.
