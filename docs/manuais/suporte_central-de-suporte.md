# Manual do módulo — Central de Suporte

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e no mesmo nível de profundidade do módulo-piloto
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial.

- **Onde fica no menu:** seção **Sistema → Suporte**.
- **Para quem é:** qualquer usuário da empresa que precise pedir ajuda, relatar
  um problema ou sugerir uma melhoria — e o RH/administradores que acompanham e
  respondem os chamados.
- **Em uma frase:** é o canal oficial para **abrir chamados** (bug, falha,
  reclamação, sugestão ou dúvida), **acompanhar o andamento** e **conversar**
  com quem está tratando o assunto, tudo dentro do próprio sistema.
- **Importante:** cada chamado é um **ticket**. Quem abre acompanha o status e
  os comentários; quem administra (perfil **admin**) muda o status e registra a
  resolução. Nada some — o histórico do ticket fica registrado.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Um único lugar para pedir ajuda.** Acabou o pedido de socorro por WhatsApp,
  e-mail solto ou "me liga que eu explico". Bug, dúvida, reclamação ou ideia de
  melhoria entram todos pelo mesmo canal, organizados por tipo e prioridade.
- **Nada se perde.** Cada chamado vira um **ticket** com autor, data, módulo
  relacionado e histórico de comentários. O que foi pedido, por quem e como foi
  resolvido fica registrado.
- **Acompanhamento transparente.** Quem abriu vê o **status** mudar (Aberto →
  Em Análise → Em Andamento → Resolvido) e recebe a **resolução** por escrito,
  sem precisar cobrar.
- **Conversa dentro do ticket.** A troca de mensagens fica **junto do chamado** —
  não espalhada em vários e-mails. Qualquer pessoa que abrir o ticket entende o
  contexto na hora.
- **Prioridade explícita.** Marcar um chamado como **Crítico** ou **Alto** ajuda
  quem atende a saber o que tratar primeiro.
- **Visão consolidada para o RH e a administração.** Os cartões do topo mostram,
  em números, quantos chamados estão **abertos**, **em andamento** e
  **resolvidos** — um termômetro rápido da operação.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Ticket / Chamado** | Cada pedido registrado no suporte. Tem título, descrição, tipo, prioridade e status. |
| **Tipo** | A natureza do chamado: **Bug**, **Falha**, **Reclamação**, **Sugestão** ou **Dúvida**. |
| **Status** | Em que ponto o chamado está: **Aberto**, **Em Análise**, **Em Andamento**, **Resolvido**, **Fechado** ou **Cancelado**. |
| **Prioridade** | Urgência do chamado: **Baixa**, **Média**, **Alta** ou **Crítica**. |
| **Módulo relacionado** | A parte do sistema a que o chamado se refere (Ponto, Férias, Financeiro…). Ajuda a direcionar. É opcional. |
| **Resolução** | O texto que descreve como o chamado foi solucionado. Aparece destacado (em verde) quando preenchido. |
| **Comentário** | Cada mensagem trocada dentro do ticket, com autor e data. |
| **Reportado por** | Quem abriu o chamado. |
| **Atribuído a** | Quem ficou responsável por tratar o chamado (quando definido). |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Estar logado no sistema.** O suporte usa o nome e a empresa do usuário
   logado para preencher o autor do chamado automaticamente.
2. **Saber a que módulo o problema se refere** (opcional, mas recomendado) —
   deixa o chamado mais fácil de direcionar.
3. **Para responder chamados** (mudar status, registrar resolução) é preciso ter
   perfil **administrador**. Usuários comuns abrem chamados e comentam.

> 💡 Não existe configuração prévia para começar a usar: qualquer pessoa da
> empresa já consegue abrir um ticket assim que entra na tela.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Suporte**, o topo mostra o ícone de boia salva-vidas com o título
**"Central de Suporte"** e a frase *"Reporte bugs, falhas, sugestões e acompanhe
os tickets"*.

Logo abaixo ficam **quatro cartões de números**:

| Cartão | O que conta |
|---|---|
| **Total** | Todos os chamados. |
| **Abertos** | Chamados ainda no status "Aberto". |
| **Em Andamento** | Chamados "Em Análise" + "Em Andamento". |
| **Resolvidos** | Chamados "Resolvido" + "Fechado". |

Em seguida vem a **barra de ferramentas**: um campo de **busca**
("Buscar tickets…"), um **filtro por tipo** e o botão **Novo Ticket**. Abaixo,
as **abas de status** (Todos, Abertos, Em Análise, Em Andamento, Resolvidos,
Fechados) e, por fim, a **lista de chamados** — cada linha é um ticket que se
abre com um clique.

> 📸 **PRINT 01 — Tela inicial do módulo**
> **Onde:** menu **Sistema → Suporte**.
> **O que precisa aparecer:** título "Central de Suporte", os quatro cartões de
> números, a busca, o filtro de tipo, o botão **Novo Ticket**, as abas de status
> e a lista de tickets.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; cartões como
> "Total 8, Abertos 3, Em Andamento 2, Resolvidos 3"; a lista com alguns
> chamados de exemplo (ver PRINT 05).
> **Ação filmada:** panorâmica lenta de cima para baixo, mostrando os cartões, a
> barra de ferramentas e a lista.

> 📸 **PRINT 02 — Estado vazio (opcional, só para o tutorial)**
> **Onde:** Suporte, quando ainda não há nenhum chamado.
> **O que precisa aparecer:** o ícone de boia esmaecido com a mensagem
> "Nenhum ticket encontrado" e o botão **Novo Ticket** no centro.
> **Uso:** só no tutorial, para mostrar o ponto de partida. Pode ser pulado no
> comercial.

---

## 5. Passo a passo por fluxo

### Fluxo 1 — Abrir um novo chamado

**Objetivo:** registrar um bug, falha, reclamação, sugestão ou dúvida.
**Benefício:** o pedido entra organizado, com tipo e prioridade, e passa a ser
acompanhável — nada mais fica "perdido no e-mail".

1. Clique em **Novo Ticket** (botão no canto direito da barra de ferramentas).
2. Preencha o **Título** — um resumo curto do problema (obrigatório).
3. Preencha a **Descrição** — o que aconteceu, os passos para reproduzir e o que
   você esperava que acontecesse (obrigatório).
4. Escolha o **Tipo**: Bug, Falha, Reclamação, Sugestão ou Dúvida.
5. Escolha a **Prioridade**: Baixa, Média, Alta ou Crítica.
6. (Opcional) Selecione o **Módulo relacionado** (ex.: Ponto, Férias,
   Financeiro).
7. Clique em **Enviar Ticket**. O chamado aparece no topo da lista e um aviso de
   sucesso confirma o envio.

> 📸 **PRINT 03 — Modal "Novo Ticket" (em branco)**
> **Onde:** botão **Novo Ticket** (barra de ferramentas).
> **O que precisa aparecer:** os campos Título, Descrição, Tipo, Prioridade e
> Módulo relacionado, com os botões **Cancelar** e **Enviar Ticket**.
> **Dados fictícios na tela:** campos ainda vazios, com os textos de ajuda
> ("Resumo do problema…", "Descreva o problema em detalhes…").

> 📸 **PRINT 04 — Modal "Novo Ticket" (preenchido)**
> **Onde:** o mesmo modal, já preenchido.
> **O que precisa aparecer:** os campos completos, prontos para enviar.
> **Dados fictícios na tela:** Título **"Relatório de ponto não abre em PDF"**;
> Descrição **"Ao clicar em Exportar espelho, a tela fica carregando e o PDF não
> baixa. Acontece no Chrome."**; Tipo **Bug**; Prioridade **Alta**; Módulo
> **Ponto**.
> **Ação filmada:** digitar título e descrição, escolher Tipo/Prioridade/Módulo
> e clicar em **Enviar Ticket**.

> 💡 Quanto mais claro o **Título** e a **Descrição** (o que aconteceu, em que
> tela, como reproduzir), mais rápido o chamado é resolvido. Use a **Prioridade
> Crítica** só para o que realmente trava o trabalho — assim ela continua tendo
> peso.

---

### Fluxo 2 — Encontrar um chamado (busca, filtro e abas)

**Objetivo:** localizar rapidamente um chamado específico ou um grupo de
chamados.
**Benefício:** mesmo com muitos tickets, você chega ao que interessa em segundos.

1. Use a **busca** ("Buscar tickets…") para procurar por **título**, **descrição**
   ou **nome de quem abriu**.
2. Use o **filtro por tipo** para ver só **Bug**, **Falha**, **Reclamação**,
   **Sugestão** ou **Dúvida** (ou "Todos tipos").
3. Use as **abas de status** para alternar entre **Todos**, **Abertos**, **Em
   Análise**, **Em Andamento**, **Resolvidos** e **Fechados**.
4. Os filtros se combinam: dá para ver, por exemplo, só os **Bugs** que estão
   **Abertos**.

> 📸 **PRINT 05 — Lista de chamados com vários tipos**
> **Onde:** Suporte, aba **Todos**.
> **O que precisa aparecer:** a lista com chamados de tipos diferentes, cada um
> com seu ícone/cor, o selo de status, a prioridade, o módulo, o autor e a data.
> **Dados fictícios na tela:**
> - **"Relatório de ponto não abre em PDF"** — Bug — **Aberto** — Alta — Ponto —
>   *Marina Alves* — 28/09/2026.
> - **"Sugestão: lembrete de férias vencendo"** — Sugestão — **Em Andamento** —
>   Média — Férias — *Bruno Carvalho*.
> - **"Dúvida sobre fechamento do mês"** — Dúvida — **Resolvido** — Baixa —
>   Financeiro — *Eduarda Lima*.

> 📸 **PRINT 06 — Busca e filtro por tipo**
> **Onde:** barra de ferramentas.
> **O que precisa aparecer:** o campo de busca com um termo digitado e o filtro
> de tipo aberto, mostrando as opções (Todos tipos, Bug, Falha, Reclamação,
> Sugestão, Dúvida).
> **Dados fictícios na tela:** busca por **"ponto"**; filtro em **Bug**.
> **Ação filmada:** digitar "ponto" na busca e depois escolher **Bug** no filtro,
> mostrando a lista se estreitar.

> 📸 **PRINT 07 — Abas de status**
> **Onde:** faixa de abas logo acima da lista.
> **O que precisa aparecer:** as abas Todos / Abertos / Em Análise / Em
> Andamento / Resolvidos / Fechados, com uma selecionada.
> **Dados fictícios na tela:** aba **Abertos** ativa, listando só os chamados
> nesse status.
> **Ação filmada:** clicar em **Abertos** e depois em **Resolvidos**, mostrando a
> lista mudar.

> 💡 A busca também encontra pelo **nome de quem abriu** — útil quando alguém
> pede "cadê aquele chamado que a Marina abriu semana passada?".

---

### Fluxo 3 — Acompanhar um chamado e conversar (comentários)

**Objetivo:** ver os detalhes de um chamado e trocar mensagens sobre ele.
**Benefício:** todo o histórico da conversa fica junto do chamado — nada de
procurar em e-mails soltos.

1. Clique em qualquer **linha da lista** para abrir os **detalhes** do chamado.
2. No detalhe, veja o **cabeçalho** (título, tipo, status e prioridade) e o bloco
   de informações: **Reportado por**, **Data**, **Módulo** e, quando houver,
   **Atribuído a**.
3. Leia a **Descrição** completa. Se o chamado já tiver **Resolução**, ela
   aparece destacada em verde.
4. Role até **Comentários** para ver as mensagens já trocadas.
5. Escreva no campo **"Adicionar comentário…"** e clique no botão de **enviar**
   (ícone de avião de papel) — ou tecle **Enter**.

> 📸 **PRINT 08 — Detalhe do chamado**
> **Onde:** clicar em um chamado da lista.
> **O que precisa aparecer:** o cabeçalho com título e selos (tipo, status,
> prioridade), o bloco de informações (Reportado por, Data, Módulo), a descrição
> e a seção de comentários.
> **Dados fictícios na tela:** chamado **"Relatório de ponto não abre em PDF"**;
> Reportado por **Marina Alves**; Data **28/09/2026 09:14**; Módulo **Ponto**;
> Tipo **Bug**, Status **Em Análise**, Prioridade **Alta**.

> 📸 **PRINT 09 — Adicionar comentário**
> **Onde:** parte de baixo do detalhe do chamado.
> **O que precisa aparecer:** a lista de comentários (com avatar e nome do autor)
> e o campo para escrever um novo comentário.
> **Dados fictícios na tela:** comentário de **Bruno Carvalho**: *"Conseguimos
> reproduzir aqui, já estamos verificando."*; e um novo texto sendo digitado por
> **Marina Alves**: *"Obrigada! Acontece também no relatório mensal."*
> **Ação filmada:** digitar o comentário e clicar em enviar, mostrando a mensagem
> entrar na conversa.

> 💡 Os comentários aparecem em ordem, com nome e data, montando a linha do tempo
> do chamado. É a forma de manter todo mundo no mesmo contexto.

---

### Fluxo 4 — Responder e resolver um chamado (perfil administrador)

**Objetivo:** conduzir o chamado até a solução, mudando o status conforme o
tratamento avança.
**Benefício:** quem abriu acompanha a evolução em tempo real, sem precisar
cobrar.

> Este fluxo só aparece para quem tem perfil **administrador**. Usuários comuns
> não veem os botões de mudar status.

1. Abra o chamado pela lista.
2. Na linha **"Alterar status:"**, escolha o novo estado: **Em Análise**,
   **Em Andamento**, **Resolvido**, **Fechado** ou **Cancelado**.
3. Ao marcar como **Resolvido**, o sistema registra a data da resolução; use os
   comentários (ou o campo de resolução, quando disponível) para explicar o que
   foi feito.
4. O novo status passa a valer na hora — aparece no selo do chamado e é contado
   nos cartões do topo.

> 📸 **PRINT 10 — Alterar status (administrador)**
> **Onde:** detalhe do chamado, logado como um usuário **administrador**
> (ex.: Bruno Carvalho).
> **O que precisa aparecer:** a linha "Alterar status:" com os botões dos estados
> possíveis e, se já resolvido, o bloco verde de **Resolução**.
> **Dados fictícios na tela:** chamado **"Relatório de ponto não abre em PDF"**;
> botões **Em Andamento / Resolvido / Fechado / Cancelado**; bloco de Resolução
> com o texto *"Corrigido o gerador de PDF; disponível na próxima publicação."*
> **Ação filmada:** clicar em **Resolvido** e mostrar o selo do chamado mudar.

> 💡 Só quem administra muda o status. Assim, o andamento é controlado por quem
> de fato trata os chamados, e quem abriu apenas acompanha.

---

### Fluxo 5 — Visão de todos os clientes (Superadmin)

**Objetivo:** para a equipe interna da YourEyes, acompanhar os chamados de
**todas as empresas** de uma vez.
**Benefício:** a operação enxerga tudo num só painel, sem trocar de empresa.

- Um usuário **superadmin** vê os tickets de **todos os tenants** (empresas), e
  não apenas os da própria empresa.
- Nesse modo, cada linha da lista mostra também uma etiqueta com o **identificador
  do tenant** (empresa) a que o chamado pertence.

> 📸 **PRINT 11 — Lista no modo Superadmin (opcional)**
> **Onde:** Suporte, logado como **superadmin**.
> **O que precisa aparecer:** a lista com a etiqueta de **Tenant** em cada linha,
> indicando a empresa de origem do chamado.
> **Dados fictícios na tela:** chamados de mais de uma empresa, com etiquetas de
> tenant diferentes (mantendo **Empresa Staging LTDA** como uma delas).
> **Uso:** só faz sentido no material voltado à equipe interna — pode ser pulado
> no comercial para o cliente final.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (45–70s)

**Tom:** direto, dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Precisou de ajuda no sistema? Chega de pedido perdido no WhatsApp e no e-mail."* Abre com uma caixa de e-mails bagunçada. | Imagem genérica de e-mails |
| 8–22s | *"Na Central de Suporte, você abre um chamado em segundos — bug, dúvida ou sugestão."* | **PRINT 04** (novo ticket preenchido) |
| 22–36s | *"Acompanhe o andamento e converse com quem está resolvendo, tudo no mesmo lugar."* | **PRINT 08** + **PRINT 09** (detalhe e comentários) |
| 36–50s | *"O time vê o status mudar até a solução — nada se perde."* | **PRINT 10** (resolver) + **PRINT 01** (cartões de números) |
| 50–65s | *"YourEyes. Suporte que você acompanha do começo ao fim."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 4–6 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("agora eu abro um chamado…", "vamos acompanhar…").

1. **Abertura** — o que a Central de Suporte faz e para quem (**PRINT 01**).
2. **Abrir um novo chamado** — título, descrição, tipo, prioridade e módulo
   (**PRINT 03, 04**).
3. **Ver o chamado na lista** com seu tipo, status e prioridade (**PRINT 05**).
4. **Encontrar um chamado** com a busca, o filtro de tipo e as abas de status
   (**PRINT 06, 07**).
5. **Abrir os detalhes** e ler as informações do chamado (**PRINT 08**).
6. **Comentar** no chamado e acompanhar a conversa (**PRINT 09**).
7. **Responder e resolver** (mostrando o perfil administrador) (**PRINT 10**).
8. **(Opcional, material interno)** a visão de todos os clientes no modo
   superadmin (**PRINT 11**).
9. **Encerramento** — lembrar que qualquer pessoa da empresa pode abrir um
   chamado por aqui.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**. Para o PRINT 10
(alterar status) use um login com perfil **administrador** (ex.: Bruno
Carvalho); o PRINT 11 exige login **superadmin**.

- [ ] **PRINT 01** — Tela inicial (cartões, busca, abas, lista)
- [ ] **PRINT 02** — Estado vazio (opcional, só tutorial)
- [ ] **PRINT 03** — Modal Novo Ticket (em branco)
- [ ] **PRINT 04** — Modal Novo Ticket (preenchido)
- [ ] **PRINT 05** — Lista de chamados com vários tipos
- [ ] **PRINT 06** — Busca e filtro por tipo
- [ ] **PRINT 07** — Abas de status
- [ ] **PRINT 08** — Detalhe do chamado
- [ ] **PRINT 09** — Adicionar comentário
- [ ] **PRINT 10** — Alterar status (administrador)
- [ ] **PRINT 11** — Lista no modo Superadmin (opcional, material interno)

---

## 9. Erros comuns / dúvidas frequentes

- **"O botão Enviar Ticket está desabilitado."** Faltou preencher o **Título** ou
  a **Descrição** — os dois são obrigatórios.
- **"Não consigo mudar o status do chamado."** Mudar status é exclusivo do perfil
  **administrador**. Usuários comuns abrem chamados e comentam, mas não alteram o
  status.
- **"Abri o chamado no módulo errado."** O **módulo relacionado** é só uma
  referência para direcionar; ele não impede o atendimento. Se precisar, informe
  o módulo correto em um comentário.
- **"Não encontro meu chamado na lista."** Verifique a **aba de status** ativa
  (ex.: você está em "Resolvidos" e o chamado está "Aberto") e limpe a **busca**
  e o **filtro de tipo**.
- **"Que prioridade eu escolho?"** Use **Crítica** só para o que trava o trabalho,
  **Alta** para o que atrapalha bastante, e **Média/Baixa** para o restante —
  assim a fila de atendimento faz sentido.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/suporte_central-de-suporte.md` no projeto.
2. Se quiser conferir a tela descrita, entre no **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/) logado como **Marina
   Alves** e vá em **Sistema → Suporte** — confira que os cartões, a busca, o
   filtro de tipo, as abas de status, o botão **Novo Ticket** e o detalhe do
   chamado (com comentários) batem com o passo a passo e os marcadores de print.
3. Aprovado o **formato e o conteúdo**, replico o mesmo padrão para os próximos
   módulos, nos lotes que você priorizar.
