# Manual do módulo — Estratégia (Planejamento, Identidade e Organograma)

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e do módulo-piloto [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial.

- **Este manual atende TRÊS itens de menu que são a MESMA página** (`/estrategia`),
  abertos em abas diferentes:

| Item de menu | Onde fica no menu | Abre em | O que faz |
|---|---|---|---|
| **Planejamento Estratégico** | **Planejamento & Gestão** | `/estrategia` (aba padrão) | Diagnóstico e inovação: **SWOT** e **Oceano Azul**. |
| **Identidade Estratégica** | **Planejamento & Gestão** | `/estrategia?tab=cultura` | **Cultura**: missão, visão, valores, comportamentos e Manual de Cultura. |
| **Organograma** | **Estrutura Organizacional** | `/estrategia?tab=organograma` | **Estrutura hierárquica** da empresa (quem responde a quem). |

- **Para quem é:** RH, gestão, diretoria e sócios — quem cuida do planejamento, da
  cultura e da estrutura da empresa (não exige perfil técnico).
- **Em uma frase:** transforma o planejamento em ação — do diagnóstico (SWOT) à
  inovação (Oceano Azul), da identidade cultural ao desenho da hierarquia — tudo
  no mesmo lugar e com **escopo por empresa ou por grupo econômico**.
- **Importante:** apesar de serem três nomes no menu, é **uma única tela** com
  abas. O que muda é a aba que abre. Ao longo do dia é comum alternar entre elas
  pelas próprias abas, sem voltar ao menu.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Planejamento que vira ação, não gaveta.** A análise SWOT e a matriz Oceano
  Azul não param no diagnóstico: cada item pode virar uma **ação no Plano de
  Ação**, com responsável, prazo e acompanhamento. O papel deixa de ser enfeite
  de parede.
- **Diagnóstico estratégico estruturado.** A **SWOT** organiza Forças, Fraquezas,
  Oportunidades e Ameaças com **classificação** (estratégico, operacional,
  cultural, pessoas, mercado) e **grau de impacto** — separando o que é crítico
  do que é secundário.
- **Inovação com método.** O **Oceano Azul** força quatro perguntas certeiras —
  o que **Eliminar, Reduzir, Elevar e Criar** — e ainda **puxa sugestões da
  própria SWOT** para dentro dos quadrantes.
- **Cultura escrita e viva.** Missão, visão, valores, princípios e
  comportamentos ficam **formalizados** e viram um **Manual de Cultura** (gerado
  com apoio de IA ou enviado pronto pela empresa), pronto para onboarding,
  treinamento e auditorias.
- **Organograma automático.** O sistema **monta a hierarquia sozinho** a partir
  do campo "Gestor Imediato" dos colaboradores — e esse desenho **alimenta
  avaliações, aprovações (férias, ponto), Plano de Ação e alertas** em outros
  módulos.
- **Uma empresa ou o grupo inteiro.** O **seletor de escopo** alterna entre a
  visão de uma empresa e a visão consolidada do **grupo econômico** — ideal para
  holdings e reuniões de diretoria.
- **Apoio de IA em cada etapa.** Sugestão de missão/visão/valores, geração do
  Manual de Cultura e sugestão de ações a partir do Oceano Azul — sempre como
  ponto de partida editável, nunca como decisão automática.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **SWOT** | Diagnóstico em 4 quadrantes: **Forças** e **Fraquezas** (internas), **Oportunidades** e **Ameaças** (externas). |
| **Classificação (SWOT)** | A "natureza" do item: **estratégico, operacional, cultural, pessoas ou mercado**. Ajuda a agrupar e priorizar. |
| **Grau de impacto** | O peso do item: **baixo, médio ou alto**. Separa o que decide a estratégia do que é detalhe. |
| **Oceano Azul** | Método de inovação em 4 movimentos: **Eliminar, Reduzir, Elevar, Criar** — sair da guerra de preços criando valor novo. |
| **Matriz** | Cada estudo de Oceano Azul salvo (pode ser vinculado a uma SWOT). |
| **Identidade Estratégica / Cultura** | O "quem somos": missão, visão, valores, princípios e comportamentos esperados e não tolerados. |
| **Manual de Cultura** | Documento que reúne a identidade da empresa — gerado com IA a partir do que foi preenchido, ou enviado pronto pela empresa. |
| **Organograma** | O desenho de quem responde a quem — a hierarquia da empresa. |
| **Gestor Imediato** | O campo no cadastro do colaborador que diz quem é o chefe direto. É a base do organograma automático. |
| **Posição / Nó** | Cada "caixinha" do organograma (uma função e seu ocupante). |
| **Escopo** | A abrangência do que você está vendo/editando: **uma empresa** ou o **grupo econômico** inteiro. |
| **Plano de Ação** | Módulo onde as iniciativas ganham responsável, prazo e acompanhamento (as ações do Oceano Azul caem lá). |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Empresa selecionada** no topo do sistema (**Empresa Staging LTDA** no
   ambiente de teste). Todas as três abas respeitam a empresa/escopo ativo.
2. **Para o Organograma automático:** colaboradores cadastrados com o campo
   **"Gestor Imediato"** preenchido. Sem isso, o botão **Sugerir Organograma**
   não aparece e a árvore fica vazia (é proposital).
3. **Para a Identidade Estratégica:** nada é obrigatório de antemão — você
   preenche missão/visão/valores na própria tela. Documentos como Código de
   Ética podem ser anexados para enriquecer o Manual de Cultura.
4. **Para vincular ações do Oceano Azul:** o módulo **Plano de Ação** disponível
   (as ações criadas a partir de itens caem lá).

> 💡 As três abas funcionam de forma independente: você pode usar só o
> Organograma sem nunca preencher a SWOT, ou só a Cultura. Nada trava nada.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Planejamento Estratégico** (aba padrão), o topo mostra:

- O **título e o ícone da aba atual** (que mudam conforme a aba: bússola para
  Planejamento, coração para Cultura, pessoas para Organograma).
- O botão **Guia Rápido** (abre um passo a passo embutido, que se **adapta à aba
  aberta**).
- O **seletor de Escopo** (Empresa ou Grupo Econômico), com um selo indicando
  qual está ativo.

O corpo da tela muda conforme o item de menu:

| Aba (item de menu) | O que aparece |
|---|---|
| **Planejamento Estratégico** | Duas sub-abas: **SWOT** e **Oceano Azul**. |
| **Identidade Estratégica** | Duas sub-abas: **Editor de Cultura** e **Painel de Gestão**. |
| **Organograma** | O quadro (canvas) da hierarquia, com **Sugerir Organograma** e **Nova Posição**. |

> 📸 **PRINT 01 — Tela inicial (Planejamento Estratégico)**
> **Onde:** menu **Planejamento & Gestão → Planejamento Estratégico**.
> **O que precisa aparecer:** o título **"Planejamento Estratégico"** com o ícone
> de bússola, o botão **Guia Rápido**, o **seletor de Escopo** e as duas sub-abas
> **SWOT** e **Oceano Azul**.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; selo de escopo
> **"Por empresa"**.
> **Ação filmada:** panorâmica lenta do topo, mostrando o seletor de escopo e as
> sub-abas.

> 📸 **PRINT 02 — Guia Rápido embutido**
> **Onde:** botão **Guia Rápido** (topo), com a aba **Planejamento Estratégico**
> aberta.
> **O que precisa aparecer:** o passo a passo lateral (SWOT, Oceano Azul,
> Cultura, Organograma, Escopo, Recursos) e a área de conteúdo com a barra de
> progresso.
> **Dados fictícios na tela:** primeiro passo **"O que é esse módulo?"**.
> **Ação filmada:** abrir o Guia, avançar um ou dois passos e fechar.

> 💡 O **Guia Rápido é contextual**: abra-o dentro de cada aba. Em Identidade
> Estratégica ele mostra o guia da cultura; em Organograma, o guia do
> organograma. Vale abrir os três no tutorial.

---

## 5. Passo a passo por fluxo

### BLOCO A — Planejamento Estratégico (aba padrão)

Esta aba tem duas ferramentas em sub-abas: **SWOT** (diagnóstico) e **Oceano
Azul** (inovação).

#### Fluxo 1 — Criar uma análise SWOT

**Objetivo:** montar o diagnóstico estratégico da empresa.
**Benefício:** enxergar, em um quadro só, o que a empresa tem de forte, o que
precisa melhorar e o que o mercado oferece ou ameaça.

1. Na aba **SWOT**, clique em **Nova SWOT**.
2. Preencha **Título**, **Descrição**, o **Escopo** (Empresa, Unidade ou
   Projeto) e o **período** (datas de início e fim).
3. Clique em **Criar Análise** — o card aparece na lista.
4. Clique no card para **abrir o detalhe** com os quatro quadrantes.

> 📸 **PRINT 03 — Lista de Análises SWOT**
> **Onde:** Planejamento Estratégico → sub-aba **SWOT**.
> **O que precisa aparecer:** o botão **Nova SWOT** e ao menos um card de
> análise já criada.
> **Dados fictícios na tela:** card **"SWOT Estratégica 2026"**, escopo
> **Empresa**, período **01/01/2026 a 31/12/2026**, autor **Marina Alves**.

> 📸 **PRINT 04 — Modal "Nova Análise SWOT"**
> **Onde:** botão **Nova SWOT**.
> **O que precisa aparecer:** os campos Título, Descrição, Escopo e as datas de
> início/fim.
> **Dados fictícios na tela:** título **"SWOT Estratégica 2026"**, escopo
> **Empresa**, início **01/01/2026**, fim **31/12/2026**.

#### Fluxo 2 — Preencher os quadrantes da SWOT

**Objetivo:** cadastrar os itens de cada quadrante, com classificação e impacto.
**Benefício:** um diagnóstico priorizado — dá para separar o crítico do
secundário e conversar sobre o que importa.

1. No detalhe da SWOT, use a **barra de adição** no topo: escolha o **tipo**
   (Força, Fraqueza, Oportunidade ou Ameaça), escreva a **descrição**, escolha a
   **classificação** e o **impacto**, e clique em **+**.
2. O item cai no **quadrante correspondente** (cada um com cor própria:
   Força/verde, Fraqueza/vermelho, Oportunidade/azul, Ameaça/âmbar).
3. Passe o mouse no **ícone de ajuda (?)** de cada quadrante para ver descrição e
   exemplos.
4. Para remover, use a **lixeira** do item (pede confirmação).

> 📸 **PRINT 05 — Detalhe da SWOT (4 quadrantes)**
> **Onde:** SWOT → clique em um card.
> **O que precisa aparecer:** a legenda de **Classificações** e **Grau de
> Impacto**, a barra de adição e os quatro quadrantes coloridos com itens.
> **Dados fictícios na tela:**
> - **Força:** "Equipe de RH certificada" — classificação **Pessoas**, impacto
>   **Alto**.
> - **Fraqueza:** "Alta rotatividade na produção" — **Operacional**, **Alto**.
> - **Oportunidade:** "Nova legislação de saúde ocupacional" — **Mercado**,
>   **Médio**.
> - **Ameaça:** "Concorrente com preço agressivo" — **Mercado**, **Alto**.
> **Ação filmada:** adicionar um item novo e mostrá-lo caindo no quadrante.

> 💡 A SWOT não precisa ficar pronta de uma vez. Revise-a **trimestralmente** —
> o mundo muda, o diagnóstico também.

#### Fluxo 3 — Criar uma matriz Oceano Azul

**Objetivo:** transformar o diagnóstico em movimento de inovação.
**Benefício:** sair da comparação com o concorrente e desenhar valor novo, com
método.

1. Vá na sub-aba **Oceano Azul** e clique em **Nova Matriz**.
2. Preencha **Título** e **Descrição**. Se quiser, **vincule a uma SWOT** já
   criada (assim a matriz puxa sugestões dela).
3. Clique em **Criar Matriz** e depois **abra o card**.
4. No detalhe, cadastre itens escolhendo o **quadrante** (Eliminar, Reduzir,
   Elevar, Criar) e a **descrição**. Cada quadrante traz uma pergunta-guia:
   *"O que devemos parar de fazer?"*, *"…fazer menos?"*, *"…fazer mais?"*,
   *"…começar a fazer?"*.
5. Quando a matriz estiver vinculada a uma SWOT, aparecem **"Sugestões da
   SWOT"** dentro dos quadrantes — clique em **Usar** para importá-las.

> 📸 **PRINT 06 — Lista / Nova Matriz Oceano Azul**
> **Onde:** Planejamento Estratégico → sub-aba **Oceano Azul**.
> **O que precisa aparecer:** o botão **Nova Matriz** e o modal de criação com
> Título, Descrição e o seletor **Vincular à SWOT**.
> **Dados fictícios na tela:** título **"Oceano Azul 2026"**, vinculada à
> **"SWOT Estratégica 2026"**.

> 📸 **PRINT 07 — Detalhe do Oceano Azul (4 quadrantes + sugestões)**
> **Onde:** Oceano Azul → clique em uma matriz.
> **O que precisa aparecer:** os quatro quadrantes (Eliminar/Reduzir/Elevar/
> Criar) com suas perguntas-guia e o bloco **"Sugestões da SWOT"** com o botão
> **Usar**.
> **Dados fictícios na tela:**
> - **Eliminar:** "Relatórios em papel".
> - **Reduzir:** "Reuniões sem pauta".
> - **Elevar:** "Atendimento consultivo ao cliente".
> - **Criar:** "Portal de autoatendimento do colaborador".
> **Ação filmada:** clicar em **Usar** numa sugestão da SWOT e vê-la entrar no
> quadrante.

#### Fluxo 4 — Transformar um item do Oceano Azul em ação

**Objetivo:** levar a iniciativa para o Plano de Ação, com responsável e prazo.
**Benefício:** a estratégia deixa de ser conversa e ganha dono e data.

1. No item do quadrante, clique no botão **robô (Sugerir ações com IA)**.
2. No modal **"Criar Ação no Plano de Ação"**, clique em **Sugerir ações com
   IA** para receber propostas, **selecione** as que fizerem sentido e clique em
   **Criar ação(ões) no Plano** — ou preencha o **formulário manual** (título,
   por quê, como, onde, prazo, responsável, tipo).
3. A ação passa a existir no módulo **Plano de Ação**, marcada com a origem
   (Oceano Azul → quadrante).

> 📸 **PRINT 08 — Modal "Criar Ação no Plano de Ação"**
> **Onde:** item do Oceano Azul → botão **robô**.
> **O que precisa aparecer:** o botão de IA, a lista de sugestões selecionáveis e
> o formulário manual (título, por quê, como, onde, prazo, responsável, tipo).
> **Dados fictícios na tela:** item de origem **"Portal de autoatendimento do
> colaborador"**, ação **"Implantar portal do colaborador"**, responsável
> **Bruno Carvalho**, prazo **30/11/2026**, tipo **Melhoria**.

> 💡 A IA é sempre um **ponto de partida editável**: revise título, prazo e
> responsável antes de criar. Nada vai para o Plano de Ação sem a sua
> confirmação.

---

### BLOCO B — Identidade Estratégica (aba `cultura`)

Aberta pelo item de menu **Identidade Estratégica**. Tem duas sub-abas: **Editor
de Cultura** (onde você preenche) e **Painel de Gestão** (onde tudo aparece
consolidado, pronto para consulta).

#### Fluxo 5 — Preencher a identidade (missão, visão, valores)

**Objetivo:** formalizar quem a empresa é.
**Benefício:** cultura escrita orienta contratação, avaliação e comunicação — e
é defensável em auditorias.

1. Na sub-aba **Editor de Cultura**, escreva a **Missão** e a **Visão**. Se
   quiser um rascunho, use **Sugerir com IA** em cada campo.
2. Adicione itens às listas: **Valores**, **Princípios Culturais**,
   **Comportamentos Esperados** e **Comportamentos Não Tolerados** (digite e
   clique em **+**, ou peça **Sugerir com IA**).
3. Clique em **Salvar** — o histórico é mantido.

> 📸 **PRINT 09 — Editor de Cultura (Missão, Visão e Valores)**
> **Onde:** Identidade Estratégica → sub-aba **Editor de Cultura**.
> **O que precisa aparecer:** os cartões **Missão** e **Visão** com o botão
> **Sugerir com IA**, e as listas de **Valores** e **Princípios** com itens em
> forma de etiqueta.
> **Dados fictícios na tela:**
> - **Missão:** "Cuidar da saúde e da segurança de quem faz a empresa acontecer."
> - **Visão:** "Ser referência em gestão de pessoas e SST até 2030."
> - **Valores:** Respeito, Transparência, Cuidado, Excelência.

#### Fluxo 6 — Enriquecer com o "jeito de ser" e documentos

**Objetivo:** descrever propósito, tom de voz, conduta, dress code e modelo de
trabalho, e anexar documentos da cultura.
**Benefício:** um Manual de Cultura completo e coerente para o onboarding.

1. Ainda no Editor, preencha os campos de texto livre: **Propósito**, **Carta /
   Manifesto de boas-vindas**, **Tom de voz e comunicação**, **Conduta e
   diversidade**, **Dress code** e **Modelo de trabalho**.
2. Em **Documentos da cultura**, clique em **Adicionar documento** e anexe
   arquivos como **Código de Ética/Conduta** ou **Regulamento Interno** (PDF ou
   Word). Eles ficam salvos no módulo **Documentos** e servem de insumo para o
   manual gerado por IA.
3. Clique em **Salvar**.

> 📸 **PRINT 10 — Jeito de ser + Documentos da cultura**
> **Onde:** Editor de Cultura (rolar até os campos de texto e a seção de
> documentos).
> **O que precisa aparecer:** os campos de texto (Propósito, Tom de voz, Dress
> code, Modelo de trabalho…) e a lista de **Documentos da cultura** com o botão
> **Adicionar documento**.
> **Dados fictícios na tela:** **Modelo de trabalho:** "Híbrido — 3 dias
> presenciais"; documento anexado **"Código de Conduta 2026.pdf"**.

#### Fluxo 7 — Ver o Painel de Gestão e gerar o Manual de Cultura

**Objetivo:** consultar tudo consolidado e gerar/baixar o Manual.
**Benefício:** um material pronto para reuniões, integração e treinamentos.

1. Abra a sub-aba **Painel de Gestão**: propósito, destino, valores, princípios,
   **o que incentivamos**, **o que não é tolerado** e o "jeito de ser" aparecem
   organizados, com um contador de campos preenchidos.
2. Para o documento, volte ao **Editor** e clique em **Gerar Manual com IA** (ou
   **Regerar Manual**). O manual abre em uma janela, é **arquivado no módulo
   Documentos** e pode ser exportado em **PDF**.
3. Se a empresa já tem um manual pronto, use **Enviar manual pronto** para
   anexá-lo, e **Baixar enviado** para recuperá-lo.

> 📸 **PRINT 11 — Painel de Gestão**
> **Onde:** Identidade Estratégica → sub-aba **Painel de Gestão**.
> **O que precisa aparecer:** os blocos **Propósito (Missão)**, **Destino
> (Visão)**, **Valores Base**, **Princípios**, **O que incentivamos**, **Não
> tolerado** e **Identidade e Jeito de Ser** com o contador "X de 6 preenchidos".
> **Dados fictícios na tela:** os valores da Empresa Staging LTDA já preenchidos
> nos fluxos 5 e 6.

> 📸 **PRINT 12 — Manual de Cultura gerado com IA**
> **Onde:** Editor de Cultura → botão **Gerar Manual com IA**.
> **O que precisa aparecer:** a janela do manual gerado e o botão de exportar em
> **PDF**.
> **Dados fictícios na tela:** manual da **Empresa Staging LTDA** com missão,
> visão, valores e comportamentos.
> **Ação filmada:** clicar em **Gerar Manual com IA** e mostrar o resultado.

> 💡 O Manual gerado é **rascunho inteligente**: ele reúne o que você preencheu e
> os documentos anexados. Revise antes de distribuir.

---

### BLOCO C — Organograma (aba `organograma`)

Aberto pelo item de menu **Organograma** (seção **Estrutura Organizacional**).

#### Fluxo 8 — Gerar o organograma automaticamente

**Objetivo:** montar a hierarquia sem desenhar caixa por caixa.
**Benefício:** o organograma nasce dos dados já cadastrados e passa a alimentar
outros módulos.

1. Garanta que os colaboradores tenham o **"Gestor Imediato"** preenchido (no
   cadastro de Colaboradores). O botão **Sugerir Organograma** mostra, no selo, a
   quantidade de colaboradores com gestor.
2. Clique em **Sugerir Organograma**: o sistema exibe a hierarquia proposta
   (quem reporta a quem; quem é **Raiz**).
3. Clique em **Gerar Organograma** para criar a árvore. Se já houver posições,
   escolha **Gerar** (adiciona) ou **Limpar e Gerar** (apaga tudo e recria — use
   após grandes movimentações).

> 📸 **PRINT 13 — Organograma (quadro da hierarquia)**
> **Onde:** menu **Estrutura Organizacional → Organograma**.
> **O que precisa aparecer:** o quadro com os cards em árvore, os botões
> **Sugerir Organograma** e **Nova Posição**, e a dica "Arraste para mover ·
> Scroll para zoom".
> **Dados fictícios na tela:** raiz **Bruno Carvalho — Coordenador de
> Operações**; subordinados **Camila Duarte — Operadora de Produção** e **Diego
> Freitas — Desenvolvedor Full Stack**.
> **Ação filmada:** dar zoom com o scroll e arrastar um card para outro nível.

> 📸 **PRINT 14 — Sugerir Organograma**
> **Onde:** Organograma → botão **Sugerir Organograma**.
> **O que precisa aparecer:** a lista da hierarquia proposta (nome, cargo,
> "Reporta a…" e o selo **Raiz**), e os botões **Gerar Organograma** / **Limpar
> e Gerar**.
> **Dados fictícios na tela:** **Bruno Carvalho** como Raiz; **Camila Duarte** e
> **Diego Freitas** reportando a Bruno.

#### Fluxo 9 — Ajustar posições manualmente

**Objetivo:** incluir, mover ou corrigir caixinhas à mão.
**Benefício:** a estrutura fica fiel à realidade, mesmo quando falta um "Gestor
Imediato" no cadastro.

1. Clique em **Nova Posição**. Escolha uma **função cadastrada** ou digite o
   **nome da função**; selecione o(s) **ocupante(s)** (colaboradores) ou digite
   um nome livre; defina a **posição** (superior na hierarquia, ou **Tornar Raiz
   Principal**).
2. Se digitar uma função que ainda não existe, o sistema pergunta se quer
   **cadastrá-la** nos registros gerais ou apenas usá-la aqui.
3. No quadro, cada card tem atalhos ao passar o mouse: **editar** (lápis),
   **excluir** (lixeira), **inserir acima** (seta para cima), **adicionar
   abaixo** (+) e **adicionar ao lado** (seta lateral). Também dá para **arrastar
   e soltar** para virar subordinado ou mudar de nível.

> 📸 **PRINT 15 — Nova Posição no Organograma**
> **Onde:** Organograma → botão **Nova Posição**.
> **O que precisa aparecer:** os campos Função cadastrada, Nome da função,
> Ocupante e o seletor de Posição (com a opção **Tornar Raiz Principal**).
> **Dados fictícios na tela:** função **"Analista de RH"**, ocupante **Marina
> Alves**, posição **subordinada a Bruno Carvalho**.

> 💡 O organograma é **fonte de verdade** para outros módulos (avaliações,
> aprovações de férias e ponto, Plano de Ação, alertas SST). Mantenha-o
> atualizado — hierarquia errada gera fluxo errado lá na frente.

---

### Fluxo transversal — Escopo: empresa ou grupo econômico

**Objetivo:** alternar entre a visão de uma empresa e a do grupo.
**Benefício:** a mesma ferramenta serve para a filial e para a diretoria do
grupo.

1. No topo, use o **seletor de Escopo**.
2. Escolha **a empresa ativa** (visão individual) ou um **grupo econômico**
   (visão consolidada). O selo ao lado indica **"Por empresa"** ou **"Grupo
   econômico"**.
3. Todas as ferramentas (SWOT, Oceano Azul, Cultura, Organograma) passam a
   respeitar o escopo escolhido. Ao trocar de empresa ativa, o escopo **volta
   sozinho para "Empresa"** se o grupo não valer mais.

> 📸 **PRINT 16 — Seletor de Escopo (empresa / grupo)**
> **Onde:** topo de qualquer aba do módulo.
> **O que precisa aparecer:** o seletor aberto mostrando a **Empresa Staging
> LTDA** e a seção **Grupos Econômicos**, com o selo de escopo.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; grupo
> (se houver no seed) exibido na lista.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, mostrando dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Planejamento estratégico que morre na gaveta? Cultura que ninguém conhece?"* Abre com um quadro branco esquecido. | Imagem genérica |
| 8–22s | *"O YourEyes transforma diagnóstico em ação: SWOT e Oceano Azul num só lugar."* | **PRINT 05** (SWOT) + **PRINT 07** (Oceano Azul) |
| 22–35s | *"E cada ideia vira ação, com responsável e prazo."* | **PRINT 08** (Criar Ação) |
| 35–50s | *"Sua cultura escrita, viva e pronta pro onboarding — com apoio de IA."* | **PRINT 11** (Painel) + **PRINT 12** (Manual) |
| 50–65s | *"O organograma se monta sozinho e alimenta avaliações, férias e alertas."* | **PRINT 13** (Organograma) |
| 65–80s | *"Uma empresa ou o grupo inteiro. YourEyes: estratégia que anda."* Logo. | **PRINT 16** (Escopo) + tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 6–9 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("vamos diagnosticar…", "agora eu monto a hierarquia…").

1. **Abertura** — os três itens de menu que abrem a mesma tela (**PRINT 01**) e o
   **Guia Rápido** contextual (**PRINT 02**).
2. **Criar uma SWOT** e preencher os quadrantes (**PRINT 03, 04, 05**).
3. **Criar uma matriz Oceano Azul** vinculada à SWOT e usar sugestões
   (**PRINT 06, 07**).
4. **Transformar um item em ação** no Plano de Ação (**PRINT 08**).
5. **Preencher a Identidade Estratégica** — missão, visão, valores (**PRINT 09**)
   e o "jeito de ser" + documentos (**PRINT 10**).
6. **Ver o Painel de Gestão** e **gerar o Manual de Cultura** (**PRINT 11, 12**).
7. **Gerar o Organograma automaticamente** (**PRINT 13, 14**) e **ajustar uma
   posição** à mão (**PRINT 15**).
8. **Alternar o escopo** entre empresa e grupo (**PRINT 16**).
9. **Encerramento** — lembrar do botão **Guia Rápido** dentro de cada aba.

> 💡 Dica de gravação: abra o **Guia Rápido** em cada aba antes de gravar o
> respectivo bloco — ele resume exatamente os passos que você vai executar.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Tela inicial (Planejamento Estratégico)
- [ ] **PRINT 02** — Guia Rápido embutido
- [ ] **PRINT 03** — Lista de Análises SWOT
- [ ] **PRINT 04** — Modal Nova Análise SWOT
- [ ] **PRINT 05** — Detalhe da SWOT (4 quadrantes)
- [ ] **PRINT 06** — Lista / Nova Matriz Oceano Azul
- [ ] **PRINT 07** — Detalhe do Oceano Azul (quadrantes + sugestões)
- [ ] **PRINT 08** — Modal Criar Ação no Plano de Ação
- [ ] **PRINT 09** — Editor de Cultura (Missão/Visão/Valores)
- [ ] **PRINT 10** — Jeito de ser + Documentos da cultura
- [ ] **PRINT 11** — Painel de Gestão
- [ ] **PRINT 12** — Manual de Cultura gerado com IA
- [ ] **PRINT 13** — Organograma (quadro da hierarquia)
- [ ] **PRINT 14** — Sugerir Organograma
- [ ] **PRINT 15** — Nova Posição no Organograma
- [ ] **PRINT 16** — Seletor de Escopo (empresa / grupo)

---

## 9. Erros comuns / dúvidas frequentes

- **"São três nomes no menu, mas cai tudo na mesma tela."** É proposital:
  **Planejamento Estratégico**, **Identidade Estratégica** e **Organograma** são
  a mesma página (`/estrategia`) abrindo em abas diferentes.
- **"Não aparece o botão Sugerir Organograma."** Nenhum colaborador tem o campo
  **"Gestor Imediato"** preenchido. Ajuste no cadastro de Colaboradores e volte.
- **"Gerei o organograma e ficou errado."** O desenho segue o **"Gestor
  Imediato"** dos colaboradores — gestor errado, organograma errado. Corrija o
  cadastro e use **Limpar e Gerar**.
- **"As sugestões da SWOT não aparecem no Oceano Azul."** A matriz precisa estar
  **vinculada a uma SWOT** (campo "Vincular à SWOT" na criação da matriz).
- **"Preenchi a cultura numa empresa e sumiu na outra."** A identidade é **por
  escopo**. Confira o **seletor de Escopo** e a **empresa ativa** — ao trocar de
  empresa, o conteúdo é o daquela empresa/grupo.
- **"A ação do Oceano Azul não apareceu."** Ela é criada no módulo **Plano de
  Ação** (com a origem marcada como Oceano Azul), não dentro da Estratégia.
- **"O Manual de Cultura saiu incompleto."** A IA usa o que foi preenchido e os
  documentos anexados — quanto mais campos e documentos, mais completo. Preencha
  ao menos missão, visão ou valores antes de gerar.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo
   `docs/manuais/estrategia_planejamento-identidade-organograma.md` no projeto.
2. Se quiser conferir a tela enquanto lê, use o **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
   Alves** (empresa **Empresa Staging LTDA**), e abra os três itens de menu —
   **Planejamento Estratégico**, **Identidade Estratégica** (Planejamento &
   Gestão) e **Organograma** (Estrutura Organizacional) — confirmando que os três
   levam à mesma página em abas diferentes.
3. Confira se o passo a passo, os benefícios e os marcadores de print refletem
   como você quer conduzir os vídeos.
4. Aprovado o **formato**, replico o mesmo padrão para os demais módulos, nos
   lotes que você priorizar.
