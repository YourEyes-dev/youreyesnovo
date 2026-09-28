# Manual do módulo — Meu Bem-Estar

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e do módulo-piloto aprovado [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial e traz, em cada tela,
> um marcador de print com o que capturar e com quais dados fictícios.

- **Onde fica no menu:** seção **Pessoas & Cultura → Meu Bem-Estar**.
- **Para quem é:** o **próprio colaborador**. Cada pessoa vê e responde apenas o
  seu Meu Bem-Estar — não há visão de "colaborador X" para o RH aqui dentro.
- **Em uma frase:** um espaço pessoal de autopercepção onde o colaborador reflete
  sobre sete dimensões do seu bem-estar no trabalho, registra o humor do dia e
  guarda momentos de gratidão — tudo confidencial, sem nota, sem ranking e sem
  uso para cobrança.
- **Importante (LGPD / dado sensível):** o que se registra aqui é **percepção de
  saúde emocional** — dado sensível pela LGPD (art. 11). O sistema deixa isso
  explícito na própria tela: *"Nada que você registra aqui será usado para
  punição ou cobrança"* e *"Suas reflexões são pessoais e não são compartilhadas
  individualmente"*. Este manual reforça esse enquadramento o tempo todo, porque
  ele é o que dá segurança para a pessoa usar a ferramenta com honestidade.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Um espaço seguro para a pessoa se ouvir.** Não é avaliação de desempenho,
  não gera nota e não vira relatório com nome. É uma ferramenta de
  **autoconhecimento** — a própria tela avisa que as reflexões são pessoais.
- **Bem-estar em sete dimensões, num mapa só.** Um **radar** mostra, de forma
  visual, como a pessoa está vivendo o trabalho hoje em sete eixos:
  autoconhecimento, sentido, relações, autonomia, autorrealização, atenção plena
  e gratidão. Não é diagnóstico — é um retrato para refletir.
- **Check-in de humor rápido, no ritmo do dia.** Ao entrar no sistema, um popup
  discreto pergunta *"Como você está hoje?"* com carinhas. Leva segundos, é
  confidencial e monta um histórico de humor que a própria pessoa acompanha.
- **Reflexão que puxa para a ação — sem obrigar.** Quando um eixo aparece baixo,
  o sistema oferece **sugestões opcionais** (conversar com o líder, ver trilhas
  de desenvolvimento, reconhecer um colega) e atalhos para outros módulos, sempre
  como convite, nunca como cobrança.
- **Gratidão como cultura positiva.** Um espaço específico para registrar algo
  bom que aconteceu na semana — o "oxigênio emocional" que sustenta o time.
- **Privacidade que gera confiança.** Como nada é exposto individualmente, a
  pessoa responde com sinceridade. Só assim os sinais de bem-estar têm valor.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Eixo** | Uma das sete dimensões do bem-estar medidas no radar (ex.: "Relações & Conexão Humana"). |
| **Mapa de Bem-Estar** | O gráfico em forma de teia (radar) que junta os sete eixos numa imagem só. |
| **Reflexão / percepção** | A resposta que a pessoa registra num eixo — quase sempre um controle deslizante de 1 a 5. |
| **Status do eixo** | O rótulo que resume o eixo: **Forte**, **Em atenção**, **Pode melhorar** ou **Sem dados**. |
| **Check-in de humor** | O popup rápido com carinhas que pergunta como a pessoa está — de manhã e ao longo do dia. |
| **Gratidão** | O eixo/registro onde a pessoa anota, se quiser, algo positivo da semana (texto curto ou emoji). |
| **Micro-ação** | Uma sugestão pequena e opcional (ex.: "reconhecer alguém essa semana") que aparece dentro de um eixo. |
| **Espaço seguro** | O princípio da tela: nada aqui vira punição, cobrança ou avaliação com nome. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Estar logado como um colaborador.** Qualquer pessoa autenticada tem o seu
   Meu Bem-Estar. Para os prints, use **Marina Alves** (as reflexões capturadas
   serão as dela).
2. **O módulo precisa estar habilitado no plano da empresa.** Meu Bem-Estar é um
   módulo (`mod.bem_estar`); se o plano/perfil não o incluir, o item nem aparece
   no menu. Na Empresa Staging LTDA ele está ligado.
3. **Para o mapa aparecer preenchido, é preciso ter algumas reflexões
   registradas.** Em conta nova o radar aparece "vazio" (todos os eixos em **Sem
   dados**) — o que é normal. Registre uma ou duas reflexões em alguns eixos
   antes de gravar, para o radar mostrar formato.

> 💡 O radar calcula cada eixo pela **média das últimas 5 reflexões** daquele
> eixo. Então o mapa reflete o momento recente, não a vida inteira — quem
> respondeu há muito tempo verá o eixo mudar conforme registra de novo.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Meu Bem-Estar**, o topo mostra um coração e o título **"Meu Bem-Estar
no Trabalho"**, com a linha **"Autoconhecimento • Desenvolvimento • Equilíbrio"**.

Logo abaixo vem o **aviso de espaço seguro** (faixa verde com um cadeado/escudo)
— peça-chave do módulo. Depois, o cartão **"Meu Mapa de Bem-Estar"** com o
**radar dos sete eixos** e, embaixo, uma **legenda** com o status de cada eixo.
Ao clicar em qualquer ponto do radar (ou na legenda), abre-se o **painel do
eixo**, onde a pessoa registra a reflexão. Uma frase de rodapé fecha a tela:
*"Não é sobre medir pessoas. É sobre ajudar pessoas a se perceberem melhor no
trabalho."*

Fora desta tela, mas parte da mesma experiência, existe o **check-in de humor**:
um popup que aparece sozinho ao entrar no sistema e pode ser reaberto a qualquer
hora pela **carinha no topo** (cabeçalho).

Não há abas: é uma tela única, de uso individual. **Não existe botão de "Guia
Rápido" neste módulo** (ao contrário do Ponto) — a própria tela é autoexplicativa.

| Área da tela | Para que serve |
|---|---|
| **Aviso "Espaço seguro"** | Deixa claro que nada vira punição ou cobrança. |
| **Mapa de Bem-Estar (radar)** | Retrato visual dos sete eixos, com status por cor. |
| **Legenda de eixos** | Lista os eixos e o status (Forte / Em atenção / Pode melhorar / Sem dados). |
| **Painel do eixo** | Onde a pessoa lê o texto educativo e registra a reflexão. |
| **Check-in de humor (popup)** | Registro rápido do humor do dia, com carinhas. |

> 📸 **PRINT 01 — Tela inicial do módulo**
> **Onde:** menu **Pessoas & Cultura → Meu Bem-Estar**.
> **O que precisa aparecer:** o cabeçalho com o coração e "Meu Bem-Estar no
> Trabalho", a faixa verde de "Espaço seguro", o cartão "Meu Mapa de Bem-Estar"
> com o radar e a legenda abaixo.
> **Dados fictícios na tela:** sessão de **Marina Alves**, empresa **Empresa
> Staging LTDA**, radar com alguns eixos preenchidos.
> **Ação filmada:** panorâmica lenta de cima para baixo, terminando no radar.

> 📸 **PRINT 02 — Aviso de "Espaço seguro" (close-up)**
> **Onde:** a faixa verde logo abaixo do cabeçalho.
> **O que precisa aparecer:** o texto **"Espaço seguro: Nada que você registra
> aqui será usado para punição ou cobrança. Este é um espaço de autopercepção —
> suas reflexões são pessoais."**
> **Uso:** essencial no comercial e no tutorial — é a promessa de privacidade que
> sustenta o módulo.

---

## 5. Passo a passo por fluxo

### Fluxo 1 — Ler o Mapa de Bem-Estar (radar)

**Objetivo:** entender, num olhar, como se está vivendo o trabalho hoje.
**Benefício:** o mapa não julga nem diagnostica — ajuda a pessoa a **perceber**
onde está mais forte e onde vale a pena olhar com carinho.

1. Abra **Meu Bem-Estar**.
2. Observe o **radar**: cada ponta é um eixo; quanto mais para fora o ponto,
   melhor está aquele eixo (escala de 1 a 5).
3. Leia a **legenda** abaixo do radar — cada eixo mostra o status por cor:
   **Forte** (verde), **Em atenção** (âmbar), **Pode melhorar** (laranja) ou
   **Sem dados** (cinza, quando ainda não há reflexão).
4. A frase acima do radar reforça: *"Esse mapa não é um diagnóstico. Ele ajuda
   você a perceber como está vivendo o trabalho hoje."*

> 📸 **PRINT 03 — Mapa de Bem-Estar (radar + legenda)**
> **Onde:** cartão "Meu Mapa de Bem-Estar".
> **O que precisa aparecer:** o gráfico em teia com os sete eixos e a legenda
> com os status coloridos.
> **Dados fictícios na tela:** por exemplo — **Sentido & Propósito: Forte**,
> **Relações: Em atenção**, **Atenção Plena: Pode melhorar**, **Gratidão: Sem
> dados**.
> **Ação filmada:** aproximar (zoom) do radar e, em seguida, passar o cursor
> pela legenda.

> 💡 Não há "nota final" nem média geral que classifique a pessoa. Cada eixo é
> lido isoladamente, e sempre como convite à reflexão — nunca como avaliação.

---

### Fluxo 2 — Registrar uma reflexão num eixo

**Objetivo:** responder como a pessoa se sente em uma das dimensões.
**Benefício:** a resposta alimenta o radar e, principalmente, provoca uma pausa
de autopercepção. Ao final, o sistema agradece e lembra: *"Ela é só sua."*

1. No radar (ou na legenda), **clique no eixo** que quer registrar — por exemplo
   **Sentido & Propósito**.
2. Abre-se o **painel do eixo**, com o nome, uma breve descrição, um **texto
   educativo** (ex.: *"Pessoas tendem a se sentir melhor quando entendem por que
   fazem o que fazem."*) e, se já houver histórico, um **status** e "baseado nas
   últimas N reflexões".
3. Responda a pergunta do eixo no **controle deslizante de 1 a 5** (de "Muito
   pouco" a "Totalmente").
4. Clique em **Registrar percepção**.
5. Aparece a tela de agradecimento: *"💚 Obrigado pela reflexão. Ela é só sua."*

Os sete eixos e suas perguntas:

| Eixo | Pergunta que aparece |
|---|---|
| 🟡 **Autoconhecimento & Emoções** | "O que mais influenciou seu humor no trabalho nos últimos dias?" (+ escala) |
| 🟢 **Sentido & Propósito** | "Hoje, meu trabalho faz sentido para mim." |
| 🔵 **Relações & Conexão Humana** | "Sinto que posso contar com as pessoas do meu time." |
| 🟣 **Autonomia & Reconhecimento** | "Tenho autonomia suficiente para executar meu trabalho." |
| 🟠 **Autorrealização & Desenvolvimento** | "Sinto que estou evoluindo profissionalmente aqui." |
| 🔴 **Atenção Plena & Presença** | "Tenho conseguido manter um ritmo sustentável no trabalho." |
| 🟤 **Gratidão & Cultura Positiva** | "Algo positivo que aconteceu essa semana no trabalho?" |

> 📸 **PRINT 04 — Painel de eixo aberto (reflexão com escala)**
> **Onde:** clique no eixo **Sentido & Propósito** no radar.
> **O que precisa aparecer:** o cabeçalho do eixo, o texto educativo em itálico,
> a pergunta "Hoje, meu trabalho faz sentido para mim.", o controle deslizante
> de 1 a 5 e o botão **Registrar percepção**.
> **Dados fictícios na tela:** sessão de **Marina Alves**, deslizante posicionado
> em **"Bastante" (4)**.
> **Ação filmada:** arrastar o deslizante até 4 e clicar em Registrar percepção.

> 📸 **PRINT 05 — Tela de agradecimento**
> **Onde:** logo após clicar em Registrar percepção.
> **O que precisa aparecer:** o coração 💚 e a frase **"Obrigado pela reflexão.
> Ela é só sua."**
> **Uso:** ótimo para o comercial — resume o tom de cuidado e privacidade.

> 💡 No rodapé de todo painel de eixo há o lembrete **"🔒 Suas reflexões são
> pessoais e não são compartilhadas individualmente."** Vale enquadrar esse
> texto em um dos prints — ele é o coração da promessa de LGPD do módulo.

---

### Fluxo 3 — Eixo Autoconhecimento (humor recente + o que influenciou)

**Objetivo:** conectar o humor dos últimos dias com o que o influenciou.
**Benefício:** ao ver o próprio humor em sequência, a pessoa reconhece padrões —
"reconhecer o que influencia suas emoções é o primeiro passo para o equilíbrio".

1. Clique no eixo **Autoconhecimento & Emoções**.
2. No topo do painel aparece **"Seu humor nos últimos dias"** — uma faixa de
   carinhas com as datas (histórico de até 14 dias vindo do check-in de humor).
3. Use o deslizante para responder **"Como você avalia sua consciência emocional
   hoje?"**.
4. Escolha, entre os botões, **o que mais influenciou seu humor**: *Tarefas,
   Pessoas, Ritmo, Falta de clareza, Algo pessoal* ou *Prefiro não responder*.
5. Clique em **Registrar percepção**.

> 📸 **PRINT 06 — Eixo Autoconhecimento (histórico de humor + opções)**
> **Onde:** eixo **Autoconhecimento & Emoções**.
> **O que precisa aparecer:** a faixa "Seu humor nos últimos dias" com várias
> carinhas e datas, o deslizante e os botões de opção (Tarefas, Pessoas, Ritmo…).
> **Dados fictícios na tela:** sessão de **Marina Alves**; sequência de humor
> como 😊 😐 😴 😊 💪 nos últimos dias; opção **"Ritmo"** selecionada.
> **Ação filmada:** apontar a faixa de humor e selecionar a opção "Ritmo".

> 💡 A faixa de humor só aparece se a pessoa já tiver feito check-ins de humor
> (Fluxo 6). Em conta sem histórico, o painel abre sem essa faixa — é esperado.

---

### Fluxo 4 — Eixo Gratidão (registrar um momento positivo)

**Objetivo:** guardar algo bom da semana — o "oxigênio emocional".
**Benefício:** registrar o positivo é um hábito simples que fortalece a cultura
e o próprio ânimo. É totalmente opcional: pode ser texto, um emoji ou nada.

1. Clique no eixo **Gratidão & Cultura Positiva**.
2. Responda no deslizante **"Quanto você se sentiu grato no trabalho essa
   semana?"**.
3. No campo de texto, escreva algo positivo (até 280 caracteres) — ou use os
   atalhos de emoji **😊 🙏 🎉 💪 🌟**. O campo é claramente marcado como
   **"totalmente opcional"**.
4. Clique em **Registrar percepção**.

> 📸 **PRINT 07 — Eixo Gratidão (texto + emojis)**
> **Onde:** eixo **Gratidão & Cultura Positiva**.
> **O que precisa aparecer:** o deslizante, o campo de texto com contador
> "x/280 — totalmente opcional" e a fileira de emojis.
> **Dados fictícios na tela:** sessão de **Marina Alves**; texto
> **"O time me ajudou a fechar o relatório a tempo 🙏"**; deslizante em
> **"Bastante" (4)**.
> **Ação filmada:** digitar a frase, tocar num emoji e clicar em Registrar.

> 💡 O registro de gratidão é guardado à parte, junto com a reflexão do eixo — e
> segue a mesma regra de privacidade: é pessoal, não é exposto com o nome.

---

### Fluxo 5 — Sugestões, micro-ações e atalhos (o convite à ação)

**Objetivo:** oferecer um próximo passo quando faz sentido — sempre opcional.
**Benefício:** o módulo não fica só na reflexão: ele aponta caminhos concretos
(conversar com o líder, ver trilhas, reconhecer um colega), mas nunca obriga.

O que aparece depende do eixo e da resposta:

- **Nota baixa (1 ou 2) em alguns eixos** → surgem **Sugestões (opcionais)** como
  *"Conversa com líder"*, *"Criar item no PDI"*, *"Ajustar pausas"*,
  *"Reconhecer alguém essa semana"*.
- **Sentido & Propósito** → botão **"Quer ver como sua função se conecta com a
  empresa?"**, que expande objetivo e impacto da função.
- **Relações & Conexão Humana** → micro-ação **"Enviar feedback positivo"**
  (atalho para o módulo de Feedback).
- **Autonomia & Reconhecimento** → mostra **quantos feedbacks positivos** a
  pessoa recebeu.
- **Autorrealização & Desenvolvimento** → atalhos **"Ver trilhas disponíveis"** e
  **"Competências da função"** (módulo de Aprendizado).
- **Atenção Plena & Presença** → uma lista de **auto-observação** (jornadas
  longas? poucas pausas? trabalho fora do horário?) para refletir antes de
  responder.

> 📸 **PRINT 08 — Sugestões para nota baixa**
> **Onde:** um eixo com deslizante em 1 ou 2 (ex.: **Atenção Plena & Presença**).
> **O que precisa aparecer:** o bloco **"Sugestões (opcionais)"** com as
> etiquetas (ex.: "Ajustar pausas", "Conversar com líder").
> **Dados fictícios na tela:** sessão de **Marina Alves**, deslizante em
> **"Pouco" (2)**.
> **Ação filmada:** baixar o deslizante para 2 e mostrar as sugestões surgindo.

> 📸 **PRINT 09 — Conexão da função (eixo Sentido expandido)**
> **Onde:** eixo **Sentido & Propósito**, botão "Quer ver como sua função se
> conecta com a empresa?".
> **O que precisa aparecer:** o cartão expandido com **Sua função**, **Objetivo
> da função** e **Impacto no time e clientes**.
> **Dados fictícios na tela:** função **"Analista de RH"** (cargo de Marina
> Alves).

> 💡 Todas as sugestões são **opcionais**. Elas nunca disparam alerta para a
> gestão nem marcam a pessoa — são só atalhos para quem quiser agir.

---

### Fluxo 6 — Check-in de humor (o popup do dia a dia)

**Objetivo:** registrar, em segundos, como a pessoa está se sentindo.
**Benefício:** cria o histórico de humor que aparece no eixo Autoconhecimento e
mantém a pessoa em contato com o próprio estado — de forma leve e confidencial.

1. Ao **entrar no sistema pela primeira vez no dia**, aparece o popup **"Como
   você está hoje?"** com carinhas.
2. Ao longo do dia, o popup pode reaparecer para um **check-in de meio de
   jornada** (*"Como está agora?"*).
3. Escolha uma das carinhas: **Bem 😊, Animado 😄, Motivado 💪, Neutro 😐,
   Cansado 😴, Estressado 😰, Ansioso 😟, Desanimado 😞**.
4. Pronto — o humor é salvo (com a mensagem "Humor registrado! 💛"). Dá para
   **pular** se não quiser responder agora.
5. Para registrar ou trocar o humor a qualquer momento, clique na **carinha no
   topo** da tela (cabeçalho).

> 📸 **PRINT 10 — Popup de check-in de humor**
> **Onde:** aparece ao entrar no sistema, ou clicando na carinha do topo.
> **O que precisa aparecer:** o título **"Como você está hoje?"**, a nota
> **"Esse registro é pessoal e confidencial."** e as oito carinhas.
> **Dados fictícios na tela:** sessão de **Marina Alves**.
> **Ação filmada:** clicar na carinha do topo para abrir e escolher **"Bem 😊"**.

> 📸 **PRINT 11 — Carinha de humor no topo (cabeçalho)**
> **Onde:** barra superior do sistema.
> **O que precisa aparecer:** o ícone/emoji de humor no cabeçalho, com a dica
> **"Registrar humor do dia"** (ou, se já registrado, o emoji do humor atual).
> **Uso:** mostra que o check-in está sempre a um clique.

> 💡 O check-in de humor e as reflexões do radar são **coisas diferentes, mas se
> conversam**: o humor registrado aqui é o que aparece na faixa "Seu humor nos
> últimos dias" do eixo Autoconhecimento.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** acolhedor e humano. Foco em cuidado, privacidade e autopercepção —
nunca em "medir" ou "controlar" pessoas. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"E se, no meio do trabalho, você tivesse um lugar só seu para se ouvir?"* Abre na tela inicial. | **PRINT 01** (tela inicial) |
| 8–18s | *"Um espaço seguro: nada aqui vira nota, cobrança ou punição."* Destaque na faixa verde. | **PRINT 02** (espaço seguro) |
| 18–32s | *"Sete dimensões do seu bem-estar, num mapa só — para você perceber, não para ninguém te julgar."* | **PRINT 03** (radar) |
| 32–45s | *"Registre como se sente. E, quando fizer sentido, receba um próximo passo — sempre opcional."* | **PRINT 04** (reflexão) + **PRINT 08** (sugestões) |
| 45–55s | *"Um check-in de humor rápido, confidencial, no seu ritmo."* | **PRINT 10** (popup de humor) |
| 55–70s | *"Porque cuidar de quem faz a empresa acontecer começa por dar voz a cada um."* Fecha no agradecimento. | **PRINT 05** ("Ela é só sua.") |
| 70–80s | *"YourEyes — Meu Bem-Estar."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 4–6 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("agora eu registro…", "vou clicar aqui…"). Sessão logada como **Marina Alves**.

1. **Abertura** — o que é o módulo e para quem, reforçando que é pessoal e
   confidencial (**PRINT 01, PRINT 02**).
2. **Ler o Mapa de Bem-Estar** — explicar os eixos e os status da legenda
   (**PRINT 03**).
3. **Registrar uma reflexão** num eixo com escala e ver o agradecimento
   (**PRINT 04, PRINT 05**).
4. **Eixo Autoconhecimento** — mostrar o histórico de humor e as opções
   (**PRINT 06**).
5. **Eixo Gratidão** — registrar um momento positivo com texto e emoji
   (**PRINT 07**).
6. **Sugestões e atalhos** — baixar a nota de um eixo e mostrar as sugestões
   opcionais; abrir a conexão da função (**PRINT 08, PRINT 09**).
7. **Check-in de humor** — abrir o popup pela carinha do topo e registrar
   (**PRINT 10, PRINT 11**).
8. **Encerramento** — repetir a promessa de privacidade: as reflexões são só da
   pessoa, nunca expostas individualmente.

> 💡 Dica de gravação: este módulo **não tem "Guia Rápido" embutido** — a própria
> tela guia o uso. Aproveite as frases que já aparecem na interface (o aviso de
> espaço seguro, "Ela é só sua", "🔒 ...não são compartilhadas individualmente")
> como falas naturais da narração.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves**, empresa **Empresa Staging LTDA**. Antes de gravar, registre uma ou duas
reflexões e alguns check-ins de humor para o radar e a faixa de humor
aparecerem preenchidos.

- [ ] **PRINT 01** — Tela inicial do módulo
- [ ] **PRINT 02** — Aviso de "Espaço seguro" (close-up)
- [ ] **PRINT 03** — Mapa de Bem-Estar (radar + legenda)
- [ ] **PRINT 04** — Painel de eixo aberto (reflexão com escala)
- [ ] **PRINT 05** — Tela de agradecimento ("Ela é só sua.")
- [ ] **PRINT 06** — Eixo Autoconhecimento (histórico de humor + opções)
- [ ] **PRINT 07** — Eixo Gratidão (texto + emojis)
- [ ] **PRINT 08** — Sugestões para nota baixa
- [ ] **PRINT 09** — Conexão da função (eixo Sentido expandido)
- [ ] **PRINT 10** — Popup de check-in de humor
- [ ] **PRINT 11** — Carinha de humor no topo (cabeçalho)

---

## 9. Erros comuns / dúvidas frequentes

- **"O meu mapa está todo vazio / cinza."** Ainda não há reflexões registradas.
  O status **Sem dados** é normal em conta nova — clique num eixo e registre uma
  percepção para o radar ganhar formato.
- **"Não aparece o histórico de humor no eixo Autoconhecimento."** A faixa "Seu
  humor nos últimos dias" só aparece depois de fazer check-ins de humor (Fluxo 6).
- **"O popup de humor não abriu hoje."** Ele aparece no primeiro acesso do dia e
  volta após algumas horas. Se já respondeu, é normal não reaparecer — clique na
  **carinha no topo** para registrar ou alterar quando quiser.
- **"Isso vai para o meu chefe? Vou ser cobrado pelo que respondi?"** **Não.** A
  própria tela garante: as reflexões são **pessoais e não são compartilhadas
  individualmente**, e nada aqui é usado para punição ou cobrança. É um espaço de
  autopercepção.
- **"Preciso responder tudo?"** Não. Tudo é opcional — inclusive o texto de
  gratidão ("totalmente opcional") e o próprio check-in de humor, que pode ser
  pulado. Responda só o que quiser, quando quiser.
- **"O item 'Meu Bem-Estar' não aparece no meu menu."** O módulo pode não estar
  incluído no plano/perfil de acesso da empresa. Na Empresa Staging LTDA ele
  está habilitado.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/bem-estar_meu-bem-estar.md` no projeto.
2. Se quiser conferir as telas descritas, entre no **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/) logado como **Marina
   Alves** e navegue por **Pessoas & Cultura → Meu Bem-Estar**: confira o aviso
   de espaço seguro, o radar dos sete eixos, o painel de um eixo (com o
   agradecimento "Ela é só sua.") e o check-in de humor pela carinha no topo.
3. Verifique se o passo a passo, os benefícios e os marcadores de print refletem
   como você quer conduzir os vídeos — atenção especial às frases de privacidade
   (LGPD), que são o eixo do módulo.
4. Aprovado o **formato**, eu replico o mesmo padrão para os próximos módulos,
   nos lotes que você priorizar.
