# Manual do módulo — Mural Interno

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e no mesmo nível de profundidade do módulo-piloto
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial.

- **Onde fica no menu:** seção **Pessoas & Cultura → Mural Interno**
  (endereço `/feed`).
- **Para quem é:** todos os colaboradores da empresa. RH e Gestores usam para
  comunicar; qualquer pessoa publica, reage e comenta.
- **Em uma frase:** é o **mural de comunicação interna** da empresa — um feed
  onde a equipe compartilha recados, o RH publica **anúncios oficiais** e todos
  celebram aniversários e tempo de casa, com **reações**, **comentários** e
  **menções** a colegas.
- **Importante:** o mural é **por empresa (tenant)** — cada colaborador vê o
  mural da própria empresa. Publicar um **Anúncio** e **fixar** uma publicação
  são ações reservadas a **gestores** (papel *manager* ou acima).

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Comunicação interna num só lugar.** Em vez de recado espalhado por grupo de
  WhatsApp, e-mail e cartaz na parede, a empresa tem **um feed oficial** — o que
  o RH publica ali fica registrado, visível para todos e no histórico.
- **Anúncio oficial se destaca do bate-papo.** Quando o RH ou um gestor marca a
  publicação como **Anúncio**, ela ganha selo próprio; e uma publicação
  importante pode ser **fixada no topo** para ninguém perder.
- **Cultura que acontece sozinha.** O painel **Lembretes** puxa
  automaticamente os **aniversários** e o **tempo de casa** de quem está na base
  de admissões — e oferece um atalho para **deixar uma mensagem de parabéns** no
  mural com um clique.
- **Engajamento com reações e comentários.** Cada publicação aceita **5 reações**
  (👍 Curtir, ❤️ Amei, 🎉 Parabéns, 💪 Apoio, 🚀 Inspirador) e uma conversa de
  comentários, com **menção a colegas** usando `@`.
- **Simples como uma rede social.** A tela é familiar: uma caixa "No que você
  está pensando?", foto opcional e o botão Publicar. Não precisa de treinamento.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Publicação (post)** | Uma mensagem no mural. Pode ter só texto, ou texto + uma imagem. |
| **Anúncio** | Uma publicação marcada como comunicado oficial. Ganha selo laranja com um megafone. Só **gestor** cria. |
| **Fixar** | Prender uma publicação no **topo** do mural, com selo "Fixado", para que ela apareça primeiro. Só **gestor**. |
| **Reação** | O "curtir" do mural — 5 opções (👍 ❤️ 🎉 💪 🚀). Cada pessoa deixa **uma** reação por publicação (clicar de novo remove). |
| **Comentário** | Uma resposta abaixo da publicação. Aparece ao clicar em "Comentar". |
| **Menção (@)** | Citar um colega no comentário digitando `@` e o nome — o sistema sugere a lista de pessoas. |
| **Lembretes** | O painel lateral que junta **aniversários**, **tempo de casa** e ações de cultura pendentes dos próximos 30 dias. |
| **Deixar uma mensagem** | Atalho do painel Lembretes que já escreve "Parabéns, Fulano!" na caixa de publicar, pronto para você completar e postar. |
| **Dispensar** | O "x" que tira um lembrete do painel (some só para você, e volta no próximo ciclo). |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Estar logado numa empresa.** O mural mostra as publicações da **empresa
   ativa** do usuário. Se nenhuma empresa estiver selecionada, o feed vem vazio.
2. **Para o painel Lembretes aparecer:** precisa haver **colaboradores admitidos**
   (admissões com status **concluído**) com **data de nascimento** e/ou **data de
   admissão** preenchidas, com evento nos próximos **30 dias** — ou **ações de
   cultura** pendentes. Sem nada disso, o painel simplesmente **não aparece** (é
   proposital, não é erro).
3. **Para criar Anúncio e fixar publicação:** o usuário precisa ter papel de
   **gestor** (*manager*) ou acima. Um colaborador comum publica, reage e
   comenta, mas não vê o botão de Anúncio nem o de Fixar.

> 💡 Não há botão de "Guia Rápido" dentro do Mural (diferente do módulo de
> Ponto). A tela é autoexplicativa — este manual faz o papel do guia.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Mural Interno**, o topo mostra o título **"Mural Interno"**, a frase
**"Conecte-se e compartilhe com sua equipe"** e, à direita, o botão
**Atualizar** (recarrega o feed).

Abaixo, a tela se divide em **duas colunas** (em telas largas):

| Área | Para que serve |
|---|---|
| **Coluna principal (esquerda)** | A **caixa de publicar** ("No que você está pensando?") no topo e, abaixo, o **feed** — as publicações em ordem: fixadas primeiro, depois da mais recente para a mais antiga. |
| **Coluna lateral (direita)** | O painel **Lembretes** — aniversários, tempo de casa e ações de cultura dos próximos 30 dias, cada um com o atalho **Deixar uma mensagem**. |

Em celular, as duas colunas viram uma só, empilhadas.

> 📸 **PRINT 01 — Tela inicial do módulo**
> **Onde:** menu **Pessoas & Cultura → Mural Interno**.
> **O que precisa aparecer:** título "Mural Interno", a caixa de publicar, duas
> ou três publicações no feed (uma delas fixada, uma marcada como Anúncio) e o
> painel **Lembretes** à direita.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; publicação
> fixada de **Marina Alves** ("Reunião geral na sexta às 16h"); painel Lembretes
> com **aniversário de Camila Duarte** em breve.
> **Ação filmada:** panorâmica lenta de cima para baixo, mostrando as duas
> colunas.

---

## 5. Passo a passo por fluxo

### Fluxo 1 — Publicar no mural (recado comum)

**Objetivo:** compartilhar uma mensagem com a equipe.
**Benefício:** comunicação rápida, visível para todos, guardada no histórico.

1. Na coluna principal, clique na caixa **"No que você está pensando?"** — ela
   **expande** e mostra as opções.
2. Escreva o texto.
3. (Opcional) Clique em **Foto** para anexar uma imagem — o limite é **5 MB**;
   a prévia aparece com um "x" para remover.
4. Clique em **Publicar**. A publicação sobe imediatamente para o topo do feed
   (abaixo das fixadas) e aparece a confirmação **"Post publicado!"**.

> 📸 **PRINT 02 — Caixa de publicar (expandida)**
> **Onde:** Mural → caixa **"No que você está pensando?"** já clicada.
> **O que precisa aparecer:** o campo de texto grande, o botão **Foto**, o selo
> **Anúncio** (se o usuário for gestor) e os botões **Cancelar** e **Publicar**.
> **Dados fictícios na tela:** autor **Marina Alves**; texto **"Bom dia, time!
> O café novo chegou na copa ☕"**.
> **Ação filmada:** digitar o texto e clicar em **Publicar**.

> 📸 **PRINT 03 — Publicação com imagem no feed**
> **Onde:** o feed, logo após publicar com foto.
> **O que precisa aparecer:** o cartão da publicação com avatar, nome, "há
> instantes", texto e a imagem anexada.
> **Dados fictícios na tela:** **Marina Alves** — **"Confraternização de setembro
> foi um sucesso! 🎉"** + foto ilustrativa do evento.

> 💡 A imagem é opcional: dá para publicar **só texto** ou **só imagem**. O botão
> Publicar fica desativado enquanto não houver nem texto nem imagem.

---

### Fluxo 2 — Publicar um Anúncio oficial (gestor)

**Objetivo:** destacar um comunicado importante do bate-papo comum.
**Benefício:** o anúncio ganha selo próprio (megafone laranja) e chama atenção.

1. Comece uma publicação normalmente (Fluxo 1).
2. Com a caixa expandida, clique no selo **Anúncio** (megafone) — ele fica
   destacado, indicando que aquela publicação será um anúncio.
3. Escreva o comunicado e clique em **Publicar**.

> 📸 **PRINT 04 — Marcar como Anúncio**
> **Onde:** caixa de publicar expandida, com o selo **Anúncio** ativado.
> **O que precisa aparecer:** o selo **Anúncio** destacado e, no feed já
> publicado, o cartão com o selo laranja de megafone ao lado do nome.
> **Dados fictícios na tela:** **Bruno Carvalho** (Coordenador de Operações),
> anúncio **"Nova política de home office entra em vigor em outubro. Detalhes no
> RH."**
> **Ação filmada:** ativar o selo Anúncio, publicar e apontar para o selo laranja
> no feed.

> 💡 O selo **Anúncio só aparece para gestores** (papel *manager* ou acima). Um
> colaborador comum não vê essa opção — publica como recado normal.

---

### Fluxo 3 — Reagir a uma publicação

**Objetivo:** demonstrar apoio/reconhecimento sem precisar comentar.
**Benefício:** engajamento com um clique; a publicação mostra quantas reações
recebeu.

1. Na barra de ações do cartão, escolha uma das **5 reações**:
   **👍 Curtir**, **❤️ Amei**, **🎉 Parabéns**, **💪 Apoio** ou **🚀 Inspirador**.
2. Sua reação fica **destacada**. Clicar de novo na mesma reação **remove**;
   clicar em outra **troca** (cada pessoa mantém uma reação por publicação).
3. Acima da barra, um **resumo** mostra os emojis mais usados e o total de
   reações da publicação.

> 📸 **PRINT 05 — Reações**
> **Onde:** um cartão de publicação no feed.
> **O que precisa aparecer:** a barra com as 5 reações, uma delas destacada
> (escolhida pelo usuário), e o resumo de reações acima (emojis + total).
> **Dados fictícios na tela:** publicação da **Camila Duarte**; reações
> **🎉 3 · ❤️ 2 · 👍 1**, total **6**.
> **Ação filmada:** passar o mouse (mostra o rótulo "Parabéns") e clicar na
> reação **🎉**.

> 💡 Passar o mouse sobre cada reação mostra o **nome** dela (Curtir, Amei,
> Parabéns, Apoio, Inspirador) — útil para quem está começando.

---

### Fluxo 4 — Comentar e mencionar colegas (@)

**Objetivo:** conversar sobre a publicação e chamar alguém pelo nome.
**Benefício:** a discussão fica organizada abaixo de cada publicação; a menção
avisa a pessoa citada.

1. No cartão, clique em **Comentar** (ou no contador "N comentários") — a área
   de comentários abre.
2. Escreva no campo **"Escreva um comentário... Use @ para mencionar"**.
3. Para citar um colega, digite **`@`** e comece o nome — aparece uma lista de
   pessoas. Escolha com as **setas** e **Enter/Tab**, ou clique no nome.
4. Pressione **Enter** (ou o botão de enviar) para publicar o comentário.

> 📸 **PRINT 06 — Comentários com menção**
> **Onde:** um cartão com a área de comentários aberta.
> **O que precisa aparecer:** um ou dois comentários já existentes (avatar, nome,
> texto, "há instantes") e o campo de novo comentário com a **lista de sugestões
> do `@`** aberta.
> **Dados fictícios na tela:** comentário de **Diego Freitas** — "Ótima
> iniciativa!"; no campo, digitando **"@Cami"** com **Camila Duarte** sugerida na
> lista.
> **Ação filmada:** digitar `@`, escolher **Camila Duarte** na lista e enviar o
> comentário.

> 💡 Cada pessoa pode **apagar os próprios comentários** (o ícone de lixeira
> aparece ao passar o mouse). Administradores podem apagar qualquer comentário.

---

### Fluxo 5 — Fixar e desfixar uma publicação (gestor)

**Objetivo:** manter um recado importante sempre no topo.
**Benefício:** informação crítica não "desce" no feed conforme chegam novas
publicações.

1. No cartão da publicação, clique no menu **⋯** (três pontinhos), no canto.
2. Escolha **Fixar** — o cartão ganha o selo **"Fixado"** e sobe para o topo do
   mural (fica com uma borda destacada).
3. Para soltar, abra o mesmo menu e clique em **Desfixar**.

> 📸 **PRINT 07 — Fixar publicação**
> **Onde:** o menu **⋯** de um cartão, aberto.
> **O que precisa aparecer:** o menu com a opção **Fixar** (e, num cartão já
> fixado, o selo **"Fixado"** com o ícone de alfinete e a borda destacada).
> **Dados fictícios na tela:** publicação de **Bruno Carvalho** — "Reunião geral
> na sexta às 16h" — fixada no topo.
> **Ação filmada:** abrir o menu ⋯, clicar em **Fixar** e mostrar o cartão
> subindo para o topo.

> 💡 Fixar/Desfixar aparece **só para gestores**. As publicações fixadas sempre
> vêm **antes** das demais, independentemente da data.

---

### Fluxo 6 — Excluir uma publicação ou comentário

**Objetivo:** remover conteúdo publicado por engano ou desatualizado.
**Benefício:** o mural fica limpo, sem depender do suporte.

1. **Publicação:** abra o menu **⋯** do cartão e clique em **Excluir** (em
   vermelho). Aparece a confirmação **"Post excluído"**.
2. **Comentário:** passe o mouse sobre o comentário e clique no ícone de
   **lixeira**.

**Quem pode excluir:**
- O **autor** pode excluir a própria publicação/comentário.
- **Administradores** podem excluir qualquer publicação ou comentário.

> 📸 **PRINT 08 — Excluir publicação**
> **Onde:** o menu **⋯** de um cartão, com a opção **Excluir** destacada em
> vermelho.
> **O que precisa aparecer:** o menu aberto mostrando **Fixar/Desfixar** e
> **Excluir**.
> **Dados fictícios na tela:** publicação de teste **"Rascunho — apagar"** da
> **Marina Alves**.
> **Ação filmada:** abrir o menu e clicar em **Excluir** (opcional mostrar o
> toast "Post excluído").

> 💡 A exclusão é definitiva e não pede uma segunda confirmação — só exclua
> quando tiver certeza.

---

### Fluxo 7 — Lembretes de cultura e "Deixar uma mensagem"

**Objetivo:** não esquecer aniversários e tempo de casa, e celebrar no mural.
**Benefício:** a cultura de reconhecimento roda sozinha — o painel avisa e o
atalho já monta a mensagem de parabéns.

1. Na coluna lateral, veja o painel **Lembretes**. Ele junta automaticamente:
   - **Aniversários** dos próximos 30 dias (ícone de bolo 🎂);
   - **Tempo de casa** — aniversários de admissão com 1 ano ou mais (ícone de
     troféu 🏆);
   - **Ações de cultura** pendentes ou em andamento (ícone de brilho ✨).
2. Cada item mostra o **nome**, a **data**, e um selo dizendo **"Hoje! 🎉"** ou
   **"em N dias"**.
3. Clique em **Deixar uma mensagem** — a caixa de publicar, no topo, já vem
   preenchida com **"Parabéns, Fulano! "** e a tela rola para cima. Complete o
   texto e clique em **Publicar**.
4. Se não quiser um lembrete, clique no **"x"** para **dispensá-lo** (some só
   para você).

> 📸 **PRINT 09 — Painel Lembretes**
> **Onde:** coluna lateral direita do Mural.
> **O que precisa aparecer:** o cartão **Lembretes** com dois ou três itens de
> tipos diferentes (aniversário, tempo de casa) e o botão **Deixar uma
> mensagem** em cada um.
> **Dados fictícios na tela:** **🎂 Aniversário de Camila Duarte — 30/09 — em 2
> dias**; **🏆 3 anos de empresa — Bruno Carvalho — 05/10**.
> **Ação filmada:** clicar em **Deixar uma mensagem** no aniversário da Camila.

> 📸 **PRINT 10 — Mensagem de parabéns pré-preenchida**
> **Onde:** a caixa de publicar, logo após clicar em "Deixar uma mensagem".
> **O que precisa aparecer:** a caixa já expandida com o texto inicial
> **"Parabéns, Camila Duarte! "**, pronta para completar.
> **Dados fictícios na tela:** texto completado — **"Parabéns, Camila Duarte!
> Muitas felicidades e um ótimo ano novo de vida! 🎂"**.
> **Ação filmada:** completar a frase e clicar em **Publicar**.

> 💡 O painel Lembretes usa a base de **admissões concluídas** com data de
> nascimento/admissão. Se ele não aparece, é porque não há eventos nos próximos
> 30 dias — não é erro.

---

### Fluxo 8 — Ler o mural e atualizar

**Objetivo:** acompanhar o que a equipe publicou.
**Benefício:** um lugar único e sempre atualizado para a comunicação interna.

1. Role a coluna principal para ler as publicações — **fixadas primeiro**, depois
   das mais recentes para as mais antigas (o mural traz as **50 publicações**
   mais recentes).
2. Clique na **imagem** de uma publicação para abri-la ampliada (lightbox).
3. Clique em **Atualizar** (topo direito) para buscar as publicações novas na
   hora.

> 📸 **PRINT 11 — Imagem ampliada (lightbox) [opcional]**
> **Onde:** clicar na imagem de uma publicação.
> **O que precisa aparecer:** a imagem em tela cheia sobre um fundo escurecido,
> com o "x" para fechar.
> **Dados fictícios na tela:** foto da confraternização da **Empresa Staging
> LTDA**.

> 💡 Se o feed estiver vazio, aparece a mensagem **"Nenhuma publicação ainda —
> seja o primeiro a compartilhar algo com a equipe!"** — bom quadro para o
> tutorial mostrar o ponto de partida.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** leve e humano — comunicação e cultura. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Recado da empresa perdido em cinco grupos de WhatsApp?"* Abre com telas de chat bagunçadas. | Imagem genérica de grupos de mensagem |
| 8–22s | *"O YourEyes tem um mural interno oficial — publique, anexe uma foto e todo mundo vê."* | **PRINT 02** (publicar) + **PRINT 03** (post com foto) |
| 22–35s | *"Comunicado importante vira Anúncio e fica fixado no topo."* | **PRINT 04** (anúncio) + **PRINT 07** (fixado) |
| 35–50s | *"A equipe reage e comenta — e ainda menciona colegas."* | **PRINT 05** (reações) + **PRINT 06** (comentário/@)|
| 50–65s | *"E a cultura acontece sozinha: aniversários e tempo de casa entram no mural com um clique."* | **PRINT 09** + **PRINT 10** (Lembretes → parabéns) |
| 65–80s | *"YourEyes. A voz da sua empresa, num só lugar."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 4–6 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("agora eu publico…", "vou marcar como anúncio…").

1. **Abertura** — o que o mural faz e para quem (**PRINT 01**).
2. **Publicar um recado** com foto (**PRINT 02, 03**).
3. **Marcar uma publicação como Anúncio** (gestor) (**PRINT 04**).
4. **Reagir** a uma publicação (**PRINT 05**).
5. **Comentar e mencionar** um colega com `@` (**PRINT 06**).
6. **Fixar** um comunicado no topo (gestor) (**PRINT 07**).
7. **Excluir** uma publicação de teste (**PRINT 08**).
8. **Usar os Lembretes** e **deixar uma mensagem** de parabéns (**PRINT 09, 10**).
9. **Ampliar uma imagem** e **atualizar** o feed (**PRINT 11**).
10. **Encerramento** — reforçar que o mural é por empresa e que Anúncio/Fixar são
    de gestores.

> 💡 Dica de gravação: grave os passos de gestor (Anúncio, Fixar) logado como
> **Bruno Carvalho** (Coordenador) e os demais como **Marina Alves** — assim o
> vídeo mostra a diferença de permissão de forma natural.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**. Para os prints de
gestor (Anúncio, Fixar), logar como **Bruno Carvalho** (Coordenador).

- [ ] **PRINT 01** — Tela inicial (feed + Lembretes)
- [ ] **PRINT 02** — Caixa de publicar expandida
- [ ] **PRINT 03** — Publicação com imagem no feed
- [ ] **PRINT 04** — Marcar como Anúncio
- [ ] **PRINT 05** — Reações (barra + resumo)
- [ ] **PRINT 06** — Comentários com menção (@)
- [ ] **PRINT 07** — Fixar publicação
- [ ] **PRINT 08** — Excluir publicação
- [ ] **PRINT 09** — Painel Lembretes
- [ ] **PRINT 10** — Mensagem de parabéns pré-preenchida
- [ ] **PRINT 11** — Imagem ampliada (lightbox) [opcional]

---

## 9. Erros comuns / dúvidas frequentes

- **"Não vejo o selo Anúncio nem a opção Fixar."** São ações de **gestor**
  (*manager* ou acima). Colaborador comum publica, reage e comenta, mas não
  cria anúncio nem fixa.
- **"O painel Lembretes não aparece."** É normal quando não há aniversários,
  tempo de casa ou ações de cultura nos próximos **30 dias**. Confira também se
  as **admissões** têm data de nascimento/admissão preenchidas e status
  **concluído**.
- **"Minha imagem não subiu."** O limite é **5 MB**; imagens maiores são
  recusadas com o aviso "Imagem muito grande".
- **"Reagi e sumiu."** Clicar na **mesma** reação de novo a **remove**; clicar em
  outra **troca**. Cada pessoa mantém **uma** reação por publicação.
- **"Não consigo excluir a publicação de um colega."** Só o **autor** ou um
  **administrador** exclui. O mesmo vale para comentários.
- **"Publiquei e não aparece para o outro time."** O mural é **por empresa** —
  cada colaborador vê o mural da própria empresa ativa.
- **"O feed não mostra o post novo de um colega."** Clique em **Atualizar** (topo
  direito) para recarregar.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/mural-interno_comunicacao-interna.md` no projeto.
2. Se quiser conferir as telas junto, entre no **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/) logado como **Marina
   Alves**, vá em **Pessoas & Cultura → Mural Interno** e siga os fluxos deste
   manual — o passo a passo e os marcadores de print seguem exatamente a tela.
3. Confira se os benefícios, o passo a passo e os prints refletem como você quer
   conduzir os vídeos. Aprovado o **formato**, replico o mesmo padrão para os
   demais módulos nos lotes que você priorizar.
