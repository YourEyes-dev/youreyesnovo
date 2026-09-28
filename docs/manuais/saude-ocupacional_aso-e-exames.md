# Manual do módulo — Saúde Ocupacional (ASO)

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e na mesma profundidade do módulo-piloto
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial deste módulo.

- **Onde fica no menu:** seção **Jornada & Rotina → Saúde Ocupacional (ASO)**
  (rota `/saude-ocupacional`).
- **Para quem é:** RH, Departamento Pessoal (DP), SESMT / Medicina do Trabalho e
  Gestores responsáveis pelo PCMSO.
- **Em uma frase:** registra e controla os **exames ocupacionais (ASO)** —
  admissional, periódico, de retorno ao trabalho, de mudança de risco e
  demissional — e avisa **quando cada exame vence**, dando ao RH a foto do
  cumprimento do **PCMSO (NR-7)**.
- **Importante — dado sensível (LGPD art. 11):** ASO é documento de saúde. Toda
  captura de tela para vídeo usa **exclusivamente dados fictícios** (ver a seção
  de regras no final). Nunca filme um ASO real.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **O PCMSO deixa de ser controlado na planilha.** Cada exame entra com o tipo,
  a data de realização e o próximo vencimento calculado sozinho — o RH vê num
  relance quem está **em dia**, quem **vence nos próximos 30 dias** e quem já
  está **vencido**.
- **Ninguém trabalha com exame vencido sem que alguém saiba.** O painel destaca
  os exames fora do prazo, que são justamente o que uma fiscalização da NR-7
  cobra e o que gera passivo em ação trabalhista.
- **Admissional, periódico e demissional no mesmo lugar.** Cada finalidade de
  exame do PCMSO tem seu tipo próprio, e o registro guarda qual é — do primeiro
  dia do colaborador ao desligamento.
- **A aptidão fica registrada.** Apto, apto com restrições, inapto temporário ou
  inapto — com o campo de restrições, o RH sabe se pode alocar a pessoa naquela
  função.
- **Menos digitação: a IA lê o ASO.** Ao anexar o PDF ou a foto do exame, o
  sistema **extrai os dados** (colaborador, médico, CRM, datas) para você só
  conferir e salvar.
- **O documento não se perde.** O arquivo do ASO é guardado também na **pasta de
  documentos do próprio colaborador** — some a pilha de papel e o "onde foi parar
  aquele exame?".

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **ASO** | Atestado de Saúde Ocupacional — o documento que o médico do trabalho emite dizendo se a pessoa está apta para a função. |
| **PCMSO** | Programa de Controle Médico de Saúde Ocupacional (NR-7) — o programa que obriga a empresa a fazer os exames. Este módulo é a execução dele. |
| **Exame admissional** | Feito **antes** de o colaborador começar a trabalhar. |
| **Exame periódico** | Repetido de tempos em tempos (em regra, **anual**) enquanto a pessoa trabalha. |
| **Retorno ao trabalho** | Exame após afastamento longo, antes de a pessoa voltar. |
| **Mudança de risco ocupacional** | Exame quando o colaborador muda de função/risco. |
| **Exame demissional** | Feito no **desligamento** do colaborador. |
| **Aptidão** | O resultado do exame: **Apto**, **Apto com Restrições**, **Inapto Temporário** ou **Inapto**. |
| **Próximo vencimento** | A data em que o próximo exame passa a ser necessário — o sistema calcula a partir da data de realização. |
| **Status de vencimento** | O selo colorido de cada ASO: **Regular** (verde), **Próximo ao Vencimento** (âmbar) ou **Vencido** (vermelho). |
| **CRM / CRO** | O registro do profissional que emitiu o exame (médico / dentista). |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Colaboradores cadastrados.** O ASO é sempre vinculado a um colaborador — o
   formulário exige **selecionar um colaborador cadastrado** antes de salvar.
2. **Empresa ativa selecionada.** O painel mostra os ASOs da empresa em que você
   está posicionado (**Empresa Staging LTDA** no ambiente de teste).
3. **O documento do exame em mãos** (opcional, mas recomendado): o PDF ou a foto
   do ASO, para anexar e deixar a IA preencher os campos.

> 💡 Este módulo **não tem abas**: é uma única tela com os cartões de resumo em
> cima e a lista de exames embaixo. Todo o cadastro acontece no formulário que o
> botão **Novo ASO** abre.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Saúde Ocupacional (ASO)**, o topo mostra o título **"Saúde
Ocupacional (ASO)"** com a linha **"Gestão de exames ocupacionais e controle de
periodicidade"**, e dois botões à direita: **Relatório** e **Novo ASO**.

Logo abaixo ficam **três cartões de resumo**:

| Cartão | O que mostra |
|---|---|
| **Total de ASOs** (azul) | Quantos exames ocupacionais estão registrados. |
| **ASOs Vencidos** (vermelho) | Quantos exames estão fora do prazo. |
| **A Vencer (30 dias)** (âmbar) | Quantos exames vencem no próximo mês. |

Embaixo, o **quadro da lista**: uma **busca** ("Buscar por colaborador ou
médico…"), um botão **Filtros** e a **tabela de exames** com as colunas
**Colaborador · Tipo de Exame · Realizado em · Próximo Vencimento · Status ·
Ações**.

> 📸 **PRINT 01 — Tela inicial do módulo**
> **Onde:** menu **Jornada & Rotina → Saúde Ocupacional (ASO)**.
> **O que precisa aparecer:** o título, a linha de subtítulo, os botões
> **Relatório** e **Novo ASO** e os três cartões de resumo.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; cartões como
> **Total de ASOs 8**, **ASOs Vencidos 1**, **A Vencer (30 dias) 2**.
> **Ação filmada:** panorâmica lenta de cima para baixo, dos cartões até a lista.

> 📸 **PRINT 02 — Lista de ASOs**
> **Onde:** Saúde Ocupacional, quadro da lista (parte de baixo da tela).
> **O que precisa aparecer:** a tabela com várias linhas e as seis colunas, com
> selos de status **diferentes** entre as linhas (verde, âmbar e vermelho).
> **Dados fictícios na tela:**
> - **Camila Duarte** — Periódico — realizado **10/09/2026** — próximo
>   **10/09/2027** — **Regular** (verde).
> - **Diego Freitas** — Admissional — realizado **02/10/2025** — próximo
>   **02/10/2026** — **Próximo ao Vencimento** (âmbar).
> - **Eduarda Lima** — Periódico — realizado **05/08/2025** — próximo
>   **05/08/2026** — **Vencido** (vermelho).
> **Ação filmada:** deslizar o olhar pela coluna **Status**, mostrando os três
> selos.

---

## 5. Passo a passo por fluxo

### Fluxo 1 — Registrar um novo ASO

**Objetivo:** trazer um exame ocupacional para o controle.
**Benefício:** a partir daí o exame passa a contar nos cartões e a ter o próximo
vencimento acompanhado sozinho.

1. Clique em **Novo ASO** (canto superior direito). Abre o formulário **"Novo
   Afastamento"** já no modo **ocupacional**.
2. Em **Selecionar Colaborador**, busque e escolha a pessoa. Os **dados do
   colaborador** (nome, CPF, cargo, departamento) são preenchidos sozinhos e
   ficam somente leitura.
3. Em **Tipo de Exame/Documento**, escolha a finalidade: **Admissional**,
   **Periódico**, **Retorno ao trabalho**, **Mudança de risco ocupacional** ou
   **Demissional**.
4. Preencha o **Profissional Emissor**: **Nome do Médico**, **Data de Emissão** e
   **CRM / CRO** (obrigatórios), mais UF, RQE, telefone, e-mail e endereço se
   houver. O ícone de **lupa** ao lado do CRM tenta recuperar os dados do médico
   do histórico.
5. Em **Resultado do Exame**, informe a **Aptidão** (Apto / Apto com Restrições /
   Inapto Temporário / Inapto), as **Restrições** (se houver) e **Observações do
   Exame**.
6. Clique em **Salvar Atestado**. O ASO passa a constar na lista.

> 📸 **PRINT 03 — Novo ASO: seleção do colaborador**
> **Onde:** botão **Novo ASO** → formulário aberto.
> **O que precisa aparecer:** o título do formulário, a caixa **Selecionar
> Colaborador** com um colaborador já escolhido e o quadro **Dados do
> Colaborador (preenchidos automaticamente)**.
> **Dados fictícios na tela:** colaboradora **Camila Duarte**, CPF
> **900.000.003-37**, cargo **Operadora de Produção**, departamento **Operações**.
> **Ação filmada:** abrir a busca, digitar "Camila" e selecionar.

> 📸 **PRINT 04 — Tipo de Exame/Documento**
> **Onde:** dentro do formulário de ASO, seção **Tipo de Afastamento**.
> **O que precisa aparecer:** o seletor **Tipo de Exame/Documento** aberto,
> mostrando as opções **Admissional, Periódico, Retorno ao trabalho, Mudança de
> risco ocupacional, Demissional**.
> **Dados fictícios na tela:** opção **Periódico** destacada.

> 📸 **PRINT 05 — Profissional Emissor**
> **Onde:** dentro do formulário de ASO, seção **Profissional Emissor**.
> **O que precisa aparecer:** os campos Nome do Médico, Data de Emissão, CRM/CRO
> (com o botão de lupa), UF e RQE.
> **Dados fictícios na tela:** médico **Dr. Ricardo Nunes**, data de emissão
> **10/09/2026**, CRM **123456**, UF **SP**.

> 📸 **PRINT 06 — Resultado do Exame (aptidão)**
> **Onde:** dentro do formulário de ASO, seção **Resultado do Exame**.
> **O que precisa aparecer:** o seletor **Aptidão** aberto (Apto / Apto com
> Restrições / Inapto Temporário / Inapto) e os campos **Restrições** e
> **Observações do Exame**.
> **Dados fictícios na tela:** aptidão **Apto**, restrições em branco,
> observações **"Sem alterações relevantes"**.
> **Ação filmada:** escolher **Apto** e clicar em **Salvar Atestado**.

> 💡 O botão de salvar mostra **"Salvar Atestado"** (o formulário de ASO é o
> mesmo motor dos atestados, ajustado para o modo ocupacional) — é o botão certo
> para gravar o exame.

---

### Fluxo 2 — Anexar o documento e deixar a IA preencher

**Objetivo:** evitar digitação e guardar o arquivo do exame.
**Benefício:** o ASO em PDF/foto vira registro estruturado em segundos, e o
arquivo fica arquivado junto ao colaborador.

1. Ainda no formulário de ASO, vá até **Documento** e **arraste** o arquivo (ou
   clique para selecionar). Aceita **imagem (JPG/PNG)** ou **PDF**, até **20 MB**.
2. Clique em **Extrair dados com IA**. O sistema lê o documento e preenche os
   campos que reconhecer (colaborador, médico, CRM, datas).
3. **Confira** tudo o que foi preenchido — a IA é um ajudante, a conferência é
   sua — e ajuste o que precisar.
4. **Salve.** O arquivo é guardado no exame **e** na **pasta de documentos do
   colaborador** (módulo Documentos).

> 📸 **PRINT 07 — Upload do documento + Extrair dados com IA**
> **Onde:** formulário de ASO, seção **Documento**.
> **O que precisa aparecer:** a área de arrastar arquivo com um documento já
> anexado e o botão **Extrair dados com IA** (ou o aviso "Dados extraídos
> automaticamente. Revise as informações abaixo antes de salvar.").
> **Dados fictícios na tela:** arquivo **aso_camila_periodico_ficticio.pdf**.
> **Ação filmada:** soltar o arquivo na área e clicar em **Extrair dados com IA**.

> 💡 O documento anexado é **sensível (LGPD art. 11)**. No ambiente de teste use
> só um PDF/foto **fictício** — nunca um ASO real de pessoa verdadeira.

---

### Fluxo 3 — Acompanhar vencimentos e status

**Objetivo:** saber, sem abrir cada registro, quem está em dia e quem não está.
**Benefício:** o RH age antes de o exame vencer, que é o que a NR-7 cobra.

1. Leia os **três cartões** do topo: **Total de ASOs**, **ASOs Vencidos** e
   **A Vencer (30 dias)**.
2. Na tabela, olhe a coluna **Status**, que classifica cada exame:
   - **Regular** (verde) — dentro do prazo.
   - **Próximo ao Vencimento** (âmbar) — vence em até 30 dias.
   - **Vencido** (vermelho) — já passou do prazo.
3. A coluna **Próximo Vencimento** mostra a data-alvo do próximo exame, calculada
   a partir da **data de realização** (para o periódico, cerca de **um ano**).

> 📸 **PRINT 08 — Cartões e selos de status**
> **Onde:** topo da tela (cartões) + coluna **Status** da tabela.
> **O que precisa aparecer:** os cartões com números e, na tabela, os três tipos
> de selo lado a lado.
> **Dados fictícios na tela:** **ASOs Vencidos 1** batendo com a linha da
> **Eduarda Lima (Vencido)**; **A Vencer (30 dias) 2** batendo com a linha do
> **Diego Freitas (Próximo ao Vencimento)**.
> **Ação filmada:** apontar o cartão **ASOs Vencidos** e depois a linha vermelha
> correspondente na tabela.

> 💡 O número dos cartões e os selos da lista vêm da **mesma conta** (data de
> realização → próximo vencimento) — por isso batem entre si.

---

### Fluxo 4 — Localizar um exame

**Objetivo:** achar rapidamente o ASO de uma pessoa ou de um médico.
**Benefício:** numa base grande, é a diferença entre achar em segundos e rolar
página por página.

1. No campo **"Buscar por colaborador ou médico…"**, digite parte do **nome do
   colaborador**, do **nome do médico** ou do **código do CID**.
2. A lista **filtra na hora** conforme você digita.
3. Se nada for encontrado, aparece a mensagem **"Nenhum registro de ASO
   encontrado."** — é o vazio orientativo, não um erro.

> 📸 **PRINT 09 — Busca por colaborador ou médico**
> **Onde:** campo de busca acima da tabela.
> **O que precisa aparecer:** o texto digitado e a lista já filtrada.
> **Dados fictícios na tela:** busca **"Camila"** mostrando só a linha da
> **Camila Duarte**.
> **Ação filmada:** digitar "Camila" e ver a lista encolher para uma linha.

> 📸 **PRINT 10 — Busca sem resultado**
> **Onde:** campo de busca com um termo inexistente.
> **O que precisa aparecer:** a mensagem **"Nenhum registro de ASO encontrado."**
> no corpo da tabela, sem erro.
> **Dados fictícios na tela:** busca **"xyz"**.

---

### Fluxo 5 — O que o sistema não deixa passar (validação)

**Objetivo:** garantir que todo ASO nasce com o mínimo para servir ao controle.
**Benefício:** não existe exame "solto" sem titular, sem data ou sem médico — o
que serve ao eSocial e à fiscalização.

1. Ao tentar **Salvar Atestado** sem escolher colaborador, o sistema avisa
   **"Selecione um colaborador cadastrado antes de continuar."** e mantém o
   formulário aberto.
2. Faltando **Data de Emissão**, **Nome do Médico** ou **CRM/CRO**, o sistema
   aponta os campos obrigatórios e não salva.

> 📸 **PRINT 11 — Bloqueio ao salvar sem os obrigatórios**
> **Onde:** formulário de ASO, ao clicar em **Salvar Atestado** com campos
> essenciais em branco.
> **O que precisa aparecer:** a mensagem de obrigatoriedade (aviso de
> colaborador e/ou campos destacados em vermelho) e o formulário **ainda aberto**.
> **Dados fictícios na tela:** formulário sem colaborador selecionado.
> **Ação filmada:** clicar em **Salvar Atestado** e mostrar o aviso surgindo.

---

### Fluxo 6 — Onde o exame fica guardado (privacidade)

**Objetivo:** mostrar que o ASO e seu arquivo têm um lar organizado e protegido.
**Benefício:** rastreabilidade e conformidade com a LGPD para dado de saúde.

- O registro do ASO aparece na **lista deste módulo** (só exames do tipo
  ocupacional — atestados clínicos comuns **não** aparecem aqui).
- O **arquivo anexado** é guardado também na **pasta do colaborador** dentro do
  módulo **Documentos**, junto aos demais documentos daquela pessoa.
- A coluna **Ações** de cada linha traz o atalho de **documento** do exame.

> 💡 Como este módulo lida com **dado de saúde (LGPD art. 11)**, o acesso é
> restrito por perfil: quem não tem permissão não alcança a tela nem os exames.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Quantos exames ocupacionais da sua equipe estão vencidos agora? Se a resposta está numa planilha, você não sabe."* Abre com uma planilha bagunçada. | Imagem genérica de planilha |
| 8–22s | *"O YourEyes coloca todo o PCMSO numa tela: admissional, periódico, demissional — e avisa quem está em dia, quem vence em 30 dias e quem já venceu."* | **PRINT 01** (painel) + **PRINT 08** (cartões e selos) |
| 22–38s | *"Anexe o ASO em PDF ou foto e deixe a inteligência artificial preencher os dados. Você só confere e salva."* | **PRINT 07** (upload + IA) |
| 38–52s | *"Registre a aptidão, as restrições e o médico responsável — tudo no lugar certo, com a busca que acha qualquer exame na hora."* | **PRINT 06** (resultado) + **PRINT 09** (busca) |
| 52–68s | *"Exame de saúde é dado sensível. Aqui ele fica protegido, na pasta do colaborador, com acesso por perfil."* | **PRINT 02** (lista) |
| 68–80s | *"YourEyes. Seu PCMSO sempre em dia."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 5–7 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("agora eu registro…", "vamos conferir os vencimentos…").

1. **Abertura** — o que o módulo faz e para quem; a tela e os cartões
   (**PRINT 01**).
2. **Ler a lista** e entender as colunas (**PRINT 02**).
3. **Registrar um novo ASO** — colaborador (**PRINT 03**), tipo de exame
   (**PRINT 04**), médico e CRM (**PRINT 05**), aptidão (**PRINT 06**).
4. **Anexar o documento** e usar a **extração com IA** (**PRINT 07**).
5. **Acompanhar vencimentos** — cartões e selos de status (**PRINT 08**).
6. **Buscar** um exame por colaborador/médico (**PRINT 09**) e mostrar o vazio
   orientativo (**PRINT 10**).
7. **Mostrar a validação** que bloqueia salvar sem os obrigatórios
   (**PRINT 11**).
8. **Encerramento** — reforçar a privacidade (dado de saúde, LGPD) e onde o
   arquivo fica guardado.

> 💡 Este módulo **não tem um "Guia Rápido" embutido** como o Ponto — não procure
> por esse botão na tela. O roteiro acima já cobre a operação de ponta a ponta.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Tela inicial do módulo (painel + cartões)
- [ ] **PRINT 02** — Lista de ASOs (colunas e selos de status)
- [ ] **PRINT 03** — Novo ASO: seleção do colaborador
- [ ] **PRINT 04** — Tipo de Exame/Documento (admissional/periódico/demissional…)
- [ ] **PRINT 05** — Profissional Emissor (médico + CRM + data)
- [ ] **PRINT 06** — Resultado do Exame (aptidão / restrições)
- [ ] **PRINT 07** — Upload do documento + Extrair dados com IA
- [ ] **PRINT 08** — Cartões e selos de status (vencimento)
- [ ] **PRINT 09** — Busca por colaborador ou médico
- [ ] **PRINT 10** — Busca sem resultado (mensagem de vazio)
- [ ] **PRINT 11** — Bloqueio ao salvar sem os obrigatórios

---

## 9. Erros comuns / dúvidas frequentes

- **"O colaborador não aparece para selecionar."** Ele precisa estar
  **cadastrado** e vinculado à **empresa ativa**. Confira a empresa selecionada
  no topo.
- **"Cliquei em salvar e nada aconteceu."** Provavelmente falta um campo
  obrigatório (colaborador, **Data de Emissão**, **Nome do Médico** ou
  **CRM/CRO**). O aviso aparece como mensagem no campo e como notificação.
- **"Um atestado de doença comum não está aparecendo aqui."** É proposital: esta
  tela mostra **só exames ocupacionais (ASO)**. Atestados clínicos e
  afastamentos ficam no módulo de Atestados/Afastamentos.
- **"A IA não preencheu tudo."** A extração é um ponto de partida — reveja e
  complete os campos manualmente antes de salvar.
- **"O status está diferente do que eu esperava."** O status vem da **data de
  realização** do exame e do **próximo vencimento** calculado a partir dela
  (periódico ≈ 1 ano). Confira a data informada no registro.
- **"Não encontro o botão Guia Rápido."** Este módulo não tem guia embutido —
  use este manual.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução.

Para revisar o conteúdo contra a tela real, abra o **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves**, e vá em **Jornada & Rotina → Saúde Ocupacional (ASO)**:

1. Confira o **painel** (título, cartões **Total de ASOs / ASOs Vencidos /
   A Vencer (30 dias)**) e a **lista** com as colunas descritas no Mapa da tela.
2. Clique em **Novo ASO** e percorra o formulário (colaborador → tipo de exame →
   médico/CRM → resultado/aptidão → documento com IA), comparando com os fluxos.
3. Teste a **busca** e o **vazio orientativo**, e o **bloqueio** ao salvar sem os
   campos obrigatórios.

Aprovado o **formato**, replico o mesmo padrão para os demais módulos nos lotes
que você priorizar.
