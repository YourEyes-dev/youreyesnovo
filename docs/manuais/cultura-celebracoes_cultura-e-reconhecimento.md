# Manual do módulo — Cultura & Celebrações

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e na mesma profundidade do piloto aprovado
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial.

- **Onde fica no menu:** seção **Pessoas & Cultura → Cultura & Celebrações**.
- **Para quem é:** RH, pessoas de Cultura/Employer Branding e líderes que querem
  celebrar a equipe sem depender da boa memória de ninguém.
- **Em uma frase:** transforma aniversários, tempo de casa, dias da profissão e
  datas comemorativas em **ações planejadas, executadas e medidas** — para que
  nenhuma data importante passe em branco.
- **Importante:** as celebrações de pessoas (aniversário e tempo de casa) saem
  automaticamente de quem já está **admitido e ativo** na empresa. Sem gente
  cadastrada com data de nascimento e de admissão, o painel de próximas
  celebrações fica vazio — é proposital.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Nenhuma data esquecida.** O sistema olha sozinho quem faz aniversário, quem
  completa mais um ano de casa e qual o **dia da profissão** de cada cargo nos
  **próximos 30 dias** — e coloca tudo num único painel.
- **Da intenção à ação, com um clique.** De cada celebração próxima o RH cria uma
  **ação** (planejar o bolo, o post, o presente) direto do painel, sem redigitar
  nada. A ação também aparece no **Mural Interno**, dando visibilidade ao time.
- **Cultura que se mede.** Taxa de celebrações realizadas, ações no prazo, ações
  atrasadas e tempo médio da criação à conclusão viram **indicadores** — cultura
  deixa de ser "achismo" e passa a ter número.
- **Celebrar do jeito que a pessoa gosta.** Cada colaborador tem
  **preferências** registradas (prefere experiência, presente ou folga? gosta de
  homenagem pública ou reservada?) — o reconhecimento acerta o tom.
- **Rituais que criam pertencimento.** Cafés mensais, reconhecimento trimestral,
  boas-vindas — **rituais recorrentes** ficam cadastrados e ativos, com
  responsável definido.
- **Regras da casa configuradas uma vez.** A empresa define se dá presente, se
  libera folga de aniversário, com quantos dias de antecedência a ação nasce e
  quem é o responsável padrão — e o módulo segue o combinado.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Ação (ação cultural)** | A tarefa de celebrar algo — um aniversário, um marco, uma data. Tem título, data, responsável e status. |
| **Data de referência** | A data que está sendo celebrada (ex.: o dia do aniversário). |
| **Data de execução** | O dia em que a celebração realmente aconteceu. Serve para medir se foi no prazo. |
| **Status da ação** | Onde a ação está: **Pendente**, **Em Andamento**, **Concluída** ou **Cancelada**. |
| **Tempo de casa** | Marco de aniversário de empresa do colaborador (1, 5, 10 anos…). |
| **Dia da Profissão** | A data comemorativa do cargo (ex.: Dia do Médico, Dia do Profissional de RH), reconhecida automaticamente pelo cargo. |
| **Ritual** | Uma celebração **recorrente** (semanal, quinzenal, mensal ou trimestral), como um café da equipe. |
| **Data configurável** | Uma data especial que a empresa cria (comemorativa, campanha, regional ou interna). |
| **Marco de tempo** | A regra de como celebrar cada aniversário de empresa (ex.: aos 5 anos, dar um certificado). |
| **Preferência** | Como cada colaborador gosta de ser celebrado (experiência/presente/folga; público/reservado). |
| **Responsável padrão** | Quem, por regra da empresa, toca as ações: **RH**, **Líder Direto** ou **Cultura**. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Empresa ativa selecionada.** O módulo mostra as celebrações da empresa em
   uso no momento (**Empresa Staging LTDA**, no ambiente de teste).
2. **Colaboradores admitidos e ativos**, com **data de nascimento** e **data de
   admissão** preenchidas — é daí que saem os aniversários e o tempo de casa em
   "Próximas Celebrações". Quem não tem admissão concluída não aparece.
3. **Cargos preenchidos** nas admissões — é o cargo que permite identificar o
   **Dia da Profissão** automaticamente.

> 💡 No primeiro acesso é normal o painel de próximas celebrações vir enxuto: ele
> só olha uma janela de **30 dias**. Para gravar, escolha um período com
> aniversários próximos no seed de staging.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Cultura & Celebrações**, o topo traz o título **PESSOAS** com a frase
*"Cultura não se improvisa. Se planeja, se executa e se acompanha."* Logo abaixo
vêm, em sequência, três blocos de painel que aparecem sempre:

| Bloco | Para que serve |
|---|---|
| **Cartões de resumo** | Quatro números do momento: **Datas Ativas**, **Ações Pendentes**, **Ações Concluídas** e **Rituais Ativos**. |
| **Próximas Celebrações (30 dias)** | A lista do que vem por aí — aniversários, tempo de casa, dias da profissão e ações — com botão **Criar Ação** / **Concluir**. |
| **Indicadores Culturais** | Os medidores: taxa de realização, ações no prazo, atrasadas e tempo médio, mais o resumo por status. |

Mais abaixo ficam as **3 abas** de trabalho do módulo:

| Aba | Para que serve |
|---|---|
| **Experiência do Colaborador** | A agenda de **ações culturais**: criar, filtrar, concluir e excluir. |
| **Preferências** | Como cada colaborador gosta de ser celebrado. |
| **Rituais e Reconhecimento** | Rituais recorrentes, datas configuráveis, marcos de tempo e a configuração do módulo. |

> 📸 **PRINT 01 — Tela inicial do módulo**
> **Onde:** menu **Pessoas & Cultura → Cultura & Celebrações**.
> **O que precisa aparecer:** o título **PESSOAS** com a frase de efeito, os
> quatro cartões de resumo e o começo do bloco "Próximas Celebrações".
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; cartões como
> **Datas Ativas 3**, **Ações Pendentes 4**, **Ações Concluídas 9**, **Rituais
> Ativos 2**.
> **Ação filmada:** panorâmica lenta de cima para baixo, mostrando os três blocos
> de painel e as três abas.

---

## 5. Passo a passo por fluxo

### Fluxo 1 — Ler o painel (o raio-X da cultura do mês)

**Objetivo:** entender, em segundos, o que vem por aí e como a empresa está indo.
**Benefício:** o RH abre o módulo e já sabe onde agir, sem cruzar planilhas.

1. Abra **Cultura & Celebrações**.
2. Leia os **quatro cartões de resumo** no topo (datas ativas, ações pendentes,
   concluídas e rituais ativos).
3. Desça até **Próximas Celebrações (30 dias)**: cada linha traz a pessoa (ou a
   data), o tipo (aniversário, tempo de casa, dia da profissão ou ação) e quanto
   falta — **Hoje!**, **Amanhã** ou **em X dias**. As linhas de hoje e dos
   próximos 3 dias vêm destacadas.
4. Confira os **Indicadores Culturais**: **Taxa de Realização**, **Ações no
   Prazo**, **Ações Atrasadas** e **Tempo Médio**, mais o resumo por status
   (Pendentes, Em Andamento, Concluídas, Canceladas).

> 📸 **PRINT 02 — Próximas Celebrações (30 dias)**
> **Onde:** bloco **Próximas Celebrações**, na visão inicial.
> **O que precisa aparecer:** a lista com tipos diferentes e os selos de prazo,
> além dos botões **Criar Ação** / **Concluir** à direita.
> **Dados fictícios na tela:**
> - **Camila Duarte** — Operadora de Produção — **Aniversário** — em 2 dias.
> - **Bruno Carvalho** — Coordenador de Operações — **3 anos de empresa** —
>   em 5 dias.
> - **Dia do Profissional de RH** — em 12 dias (dia da profissão).
> **Ação filmada:** passar o mouse por uma linha destacada de "Hoje!".

> 📸 **PRINT 03 — Indicadores Culturais**
> **Onde:** bloco **Indicadores Culturais**, logo abaixo das próximas
> celebrações.
> **O que precisa aparecer:** os quatro medidores no topo e a faixa de resumo por
> status embaixo.
> **Dados fictícios na tela:** **Taxa de Realização 82%**, **Ações no Prazo
> 90%**, **Ações Atrasadas 1**, **Tempo Médio 3d**; resumo **Pendentes 4 · Em
> Andamento 1 · Concluídas 9 · Canceladas 0**.

> 💡 A **Taxa de Realização** fica verde a partir de 80%, amarela entre 50% e 79%
> e vermelha abaixo disso — é o termômetro rápido da entrega.

---

### Fluxo 2 — Criar uma ação a partir de uma celebração próxima

**Objetivo:** transformar um aniversário ou tempo de casa em tarefa, sem digitar.
**Benefício:** o combo "vi que é aniversário → já planejei" acontece num clique.

1. No bloco **Próximas Celebrações (30 dias)**, ache a pessoa.
2. Clique em **Criar Ação** na linha dela.
3. Pronto: a ação nasce com o **título** já montado (ex.: *"Aniversário de Camila
   Duarte"* ou *"3 anos de empresa - Bruno Carvalho"*), a **data** e o status
   **Pendente**. Aparece a mensagem de confirmação e a ação também vai para o
   **Mural Interno**.

> 💡 Para as celebrações que **já são ações** (linhas com o tipo Ação), o botão
> muda para **Concluir** — encerra a ação ali mesmo, sem abrir a aba.

---

### Fluxo 3 — Planejar uma ação cultural manualmente

**Objetivo:** criar uma celebração que não veio automática (uma confraternização,
uma homenagem específica, uma data da empresa).
**Benefício:** toda ideia de celebração vira tarefa rastreável, com responsável.

1. Abra a aba **Experiência do Colaborador**.
2. Clique em **Nova Ação** (canto direito).
3. Preencha o **Tipo** (Aniversário, Tempo de Casa, Dia da Profissão, Data
   Configurada ou Ritual), o **Título** (obrigatório) e, se for de alguém, o
   **Colaborador**.
4. Informe a **Data de Referência** (obrigatória) e, se já souber, a **Data de
   Execução**.
5. Use o botão **Criar ação com antecedência** para que ela nasça alguns dias
   antes (ex.: **7 dias antes**), dando tempo de preparar.
6. Preencha **Responsável** e **Descrição** e clique em **Criar Ação**.

> 📸 **PRINT 04 — Aba Experiência do Colaborador (agenda de ações)**
> **Onde:** Cultura & Celebrações → aba **Experiência do Colaborador**.
> **O que precisa aparecer:** a barra de filtros (tipo, status, período, busca), o
> botão **Nova Ação** e a lista de ações em cartões com seus selos de tipo e
> status.
> **Dados fictícios na tela:** ação **"Aniversário de Camila Duarte"** —
> Aniversário — **Pendente**; ação **"Café da Cultura de Setembro"** — Ritual —
> **Concluída**.

> 📸 **PRINT 05 — Modal "Nova Ação Cultural"**
> **Onde:** aba Experiência do Colaborador → botão **Nova Ação**.
> **O que precisa aparecer:** os campos Tipo, Título, Colaborador, Data de
> Referência, Data de Execução, o interruptor **Criar ação com antecedência** e
> os campos Responsável e Descrição.
> **Dados fictícios na tela:** tipo **Tempo de Casa**, título **"5 anos de
> empresa - Eduarda Lima"**, colaboradora **Eduarda Lima**, data de referência
> **15/10/2026**, antecedência **7 dias**, responsável **Marina Alves**.
> **Ação filmada:** escolher o tipo, digitar o título, ligar a antecedência e
> clicar em **Criar Ação**.

> 💡 A ligação com o colaborador é opcional: deixe em **Nenhum (geral)** para
> ações que valem para a empresa toda (um mutirão, uma campanha).

---

### Fluxo 4 — Acompanhar, filtrar e concluir ações

**Objetivo:** manter a agenda em dia e não perder nada de vista.
**Benefício:** os filtros mostram exatamente o que interessa; concluir é um clique.

1. Na aba **Experiência do Colaborador**, use os filtros no topo: por **tipo**,
   por **status**, por **período** (Este mês, Trimestre, Este ano) e a busca por
   **colaborador**.
2. Em cada ação **Pendente**, o botão **Concluir** encerra a tarefa.
3. O ícone de lixeira **exclui** a ação, quando ela não é mais necessária.

> 💡 Combine o filtro **Status = Pendente** com **Período = Este mês** para a sua
> "lista do mês" — o que precisa sair até o fim de setembro.

---

### Fluxo 5 — Registrar as preferências de celebração

**Objetivo:** guardar como cada pessoa gosta (ou não gosta) de ser celebrada.
**Benefício:** acabam os presságios errados — nada de homenagem pública para quem
prefere reserva.

1. Abra a aba **Preferências**.
2. Clique em **Registrar Preferência**.
3. Escolha o **Colaborador**, a **Preferência para aniversários** (Experiência,
   Presente, Folga ou Indiferente) e o **Tipo de reconhecimento preferido**
   (Público, Reservado ou Tanto faz).
4. Anote as **Observações pessoais** (ex.: *"gosta de chocolate, prefere flores"*)
   e clique em **Salvar Preferência**.

> 📸 **PRINT 06 — Aba Preferências**
> **Onde:** Cultura & Celebrações → aba **Preferências**.
> **O que precisa aparecer:** a busca, o botão **Registrar Preferência** e os
> cartões com os selos 🎂 (aniversário) e 🏆 (reconhecimento).
> **Dados fictícios na tela:** **Diego Freitas** — 🎂 Folga · 🏆 Reservado;
> **Marina Alves** — 🎂 Experiência · 🏆 Público.

> 📸 **PRINT 07 — Modal "Como você gosta de ser celebrado?"**
> **Onde:** aba Preferências → botão **Registrar Preferência**.
> **O que precisa aparecer:** o seletor de colaborador, a preferência de
> aniversário, o tipo de reconhecimento e o campo de observações.
> **Dados fictícios na tela:** colaboradora **Camila Duarte**, preferência
> **Presente**, reconhecimento **Público**, observação **"prefere comemorar com a
> equipe"**.
> **Ação filmada:** escolher a Camila, marcar as opções e clicar em **Salvar
> Preferência**.

> 💡 O melhor momento para coletar essas preferências é no **onboarding** — a
> própria tela sugere isso quando ainda não há nenhuma registrada.

---

### Fluxo 6 — Rituais culturais recorrentes

**Objetivo:** cadastrar celebrações que se repetem (café, reconhecimento, etc.).
**Benefício:** o ritual fica registrado, com dono e frequência — não depende de
alguém lembrar toda vez.

1. Abra a aba **Rituais e Reconhecimento** → sub-aba **Rituais Culturais**.
2. Clique em **Novo Ritual**.
3. Preencha **Nome** (obrigatório), a **Frequência** (Semanal, Quinzenal, Mensal
   ou Trimestral), o **Responsável** e a **Descrição**; clique em **Criar
   Ritual**.
4. Use o **interruptor** de cada ritual para **ativar/inativar** e a lixeira para
   excluir.

> 📸 **PRINT 08 — Sub-aba Rituais Culturais**
> **Onde:** aba **Rituais e Reconhecimento** → **Rituais Culturais**.
> **O que precisa aparecer:** a lista de rituais em cartões, com selo de
> frequência, o selo **Ativo/Inativo** e os botões de ligar/desligar e excluir.
> **Dados fictícios na tela:** ritual **"Café da Cultura"** — Mensal — **Ativo**;
> ritual **"Reconhecimento do Trimestre"** — Trimestral — **Ativo**.

> 📸 **PRINT 09 — Modal "Novo Ritual Cultural"**
> **Onde:** sub-aba Rituais Culturais → botão **Novo Ritual**.
> **O que precisa aparecer:** os campos Nome, Frequência, Responsável e Descrição.
> **Dados fictícios na tela:** nome **"Café da Cultura"**, frequência **Mensal**,
> responsável **Marina Alves**.

> 💡 Inative um ritual em vez de excluí-lo quando ele estiver só em pausa — assim
> você preserva o histórico e reativa quando quiser.

---

### Fluxo 7 — Datas configuráveis da empresa

**Objetivo:** cadastrar datas especiais próprias (aniversário da empresa, campanha
interna, data regional).
**Benefício:** o calendário de cultura passa a incluir o que é da sua empresa, não
só as datas de pessoas.

1. Na aba **Rituais e Reconhecimento**, abra a sub-aba **Datas Configuráveis**.
2. Clique em **Nova Data**.
3. Preencha **Título** (obrigatório), o **Tipo** (Comemorativa, Campanha,
   Regional ou Interna) e o **Dia**/**Mês**; adicione uma **Descrição** e clique
   em **Criar Data**.

> 📸 **PRINT 10 — Sub-aba Datas Configuráveis**
> **Onde:** aba Rituais e Reconhecimento → **Datas Configuráveis**.
> **O que precisa aparecer:** a lista de datas com o selo de tipo e o dia/mês.
> **Dados fictícios na tela:** **"Aniversário da Empresa Staging LTDA"** —
> Interna — Dia 10/03; **"Setembro Amarelo"** — Campanha — Dia 10/09.

> 📸 **PRINT 11 — Modal "Nova Data Comemorativa"**
> **Onde:** sub-aba Datas Configuráveis → botão **Nova Data**.
> **O que precisa aparecer:** os campos Título, Tipo, Dia, Mês e Descrição.
> **Dados fictícios na tela:** título **"Setembro Amarelo"**, tipo **Campanha**,
> dia **10**, mês **9**.

---

### Fluxo 8 — Marcos de tempo de casa

**Objetivo:** definir como celebrar cada aniversário de empresa (1, 5, 10 anos…).
**Benefício:** o reconhecimento por tempo de casa fica padronizado e justo —
todos que chegam ao mesmo marco recebem o mesmo tratamento.

1. Na aba **Rituais e Reconhecimento**, abra a sub-aba **Marcos de Tempo**.
2. Clique em **Novo Marco**.
3. Informe os **Anos** (obrigatório), o **Tipo de Celebração** (Reconhecimento
   Público, Mimo / Presente, Certificado, Decoração da Mesa ou Homenagem Pública)
   e uma **Descrição**; clique em **Criar Marco**.

> 📸 **PRINT 12 — Sub-aba Marcos de Tempo**
> **Onde:** aba Rituais e Reconhecimento → **Marcos de Tempo**.
> **O que precisa aparecer:** os cartões de marcos, cada um com o número de anos e
> o selo do tipo de celebração.
> **Dados fictícios na tela:** **1 ano** — Certificado; **5 anos** — Mimo /
> Presente; **10 anos** — Homenagem Pública.

> 📸 **PRINT 13 — Modal "Novo Marco de Tempo"**
> **Onde:** sub-aba Marcos de Tempo → botão **Novo Marco**.
> **O que precisa aparecer:** os campos Anos, Tipo de Celebração e Descrição.
> **Dados fictícios na tela:** anos **5**, tipo **Mimo / Presente**, descrição
> **"Presente personalizado + cartão da equipe"**.

---

### Fluxo 9 — Configuração do módulo

**Objetivo:** definir as regras da casa para as celebrações.
**Benefício:** o módulo passa a agir do jeito da empresa — com ou sem presente,
com ou sem folga, com a antecedência e o responsável certos.

1. Na aba **Rituais e Reconhecimento**, abra a sub-aba **Configuração**.
2. Ligue/desligue os automáticos: **Aniversário do Colaborador**, **Tempo de
   Casa** e **Dia da Profissão**.
3. Defina os benefícios: **Presente Padrão**, **Folga Permitida** e o **Limite de
   valor do presente (R$)** (vazio = sem limite).
4. Ajuste os **Dias de antecedência para criar ação** e o **Responsável padrão**
   (RH, Líder Direto ou Cultura). As mudanças são salvas ao alterar cada campo.

> 📸 **PRINT 14 — Sub-aba Configuração**
> **Onde:** aba Rituais e Reconhecimento → **Configuração**.
> **O que precisa aparecer:** os interruptores dos automáticos e dos benefícios, o
> limite de valor, os dias de antecedência e o responsável padrão.
> **Dados fictícios na tela:** Aniversário **ligado**, Tempo de Casa **ligado**,
> Dia da Profissão **ligado**, Presente Padrão **ligado**, Folga Permitida
> **desligada**, limite **R$ 100**, antecedência **7**, responsável padrão **RH**.

> 💡 Se você desligar um automático (ex.: Dia da Profissão), o painel de próximas
> celebrações deixa de sugerir aquele tipo — útil quando a empresa não quer
> celebrar aquela categoria.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** emocional e leve — cultura, gente, pertencimento. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Quantos aniversários da sua equipe já passaram em branco?"* Abre com um post-it esquecido na geladeira. | Imagem genérica |
| 8–22s | *"O YourEyes avisa quem faz aniversário, quem completa mais um ano de casa e até o dia da profissão de cada um."* | **PRINT 02** (próximas celebrações) |
| 22–38s | *"De cada data, você cria uma ação com um clique — e ela ainda aparece no mural da empresa."* | **PRINT 02** (botão Criar Ação) + **PRINT 04** (agenda) |
| 38–52s | *"Celebre do jeito que cada pessoa gosta: presente, experiência ou folga."* | **PRINT 06** (preferências) |
| 52–68s | *"E acompanhe a cultura por números: quanto você realmente celebrou, e no prazo."* | **PRINT 03** (indicadores) |
| 68–82s | *"YourEyes. Cultura não se improvisa — se planeja, se executa e se acompanha."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 5–8 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("agora eu abro…", "vamos configurar…").

1. **Abertura** — o que o módulo faz e para quem, com a panorâmica da tela
   inicial (**PRINT 01**).
2. **Ler o painel** — cartões, próximas celebrações e indicadores (**PRINT 02,
   03**).
3. **Criar uma ação a partir de uma celebração próxima** — botão **Criar Ação**
   (**PRINT 02**).
4. **Planejar uma ação manual** na agenda (**PRINT 04, 05**).
5. **Filtrar e concluir** ações na aba Experiência do Colaborador (**PRINT 04**).
6. **Registrar uma preferência** de celebração (**PRINT 06, 07**).
7. **Criar um ritual** recorrente (**PRINT 08, 09**).
8. **Cadastrar uma data** da empresa (**PRINT 10, 11**).
9. **Definir um marco** de tempo de casa (**PRINT 12, 13**).
10. **Configurar as regras** do módulo (**PRINT 14**).
11. **Encerramento** — reforçar a frase da tela: cultura se planeja, se executa e
    se acompanha.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Tela inicial (título PESSOAS + cartões de resumo)
- [ ] **PRINT 02** — Próximas Celebrações (30 dias)
- [ ] **PRINT 03** — Indicadores Culturais
- [ ] **PRINT 04** — Aba Experiência do Colaborador (agenda de ações)
- [ ] **PRINT 05** — Modal Nova Ação Cultural
- [ ] **PRINT 06** — Aba Preferências
- [ ] **PRINT 07** — Modal "Como você gosta de ser celebrado?"
- [ ] **PRINT 08** — Sub-aba Rituais Culturais
- [ ] **PRINT 09** — Modal Novo Ritual Cultural
- [ ] **PRINT 10** — Sub-aba Datas Configuráveis
- [ ] **PRINT 11** — Modal Nova Data Comemorativa
- [ ] **PRINT 12** — Sub-aba Marcos de Tempo
- [ ] **PRINT 13** — Modal Novo Marco de Tempo
- [ ] **PRINT 14** — Sub-aba Configuração

---

## 9. Erros comuns / dúvidas frequentes

- **"O painel de próximas celebrações está vazio."** Provavelmente não há
  colaboradores **admitidos e ativos** com **data de nascimento**/**admissão** na
  empresa selecionada, ou não há nada nos próximos **30 dias**. Confira o cadastro
  das admissões.
- **"O aniversário de alguém não aparece."** Verifique se a **data de
  nascimento** está preenchida na admissão e se a pessoa está na **empresa ativa**
  em uso.
- **"O Dia da Profissão não apareceu."** Ele depende do **cargo** preenchido e de
  o cargo estar entre os reconhecidos. Se o automático **Dia da Profissão**
  estiver desligado na Configuração, ele também não sugere.
- **"Criei uma ação e não achei depois."** Ela está na aba **Experiência do
  Colaborador** — cheque os **filtros** (tipo, status, período); um filtro ativo
  pode estar escondendo-a.
- **"Preciso pausar um ritual sem perder o histórico."** Use o **interruptor**
  para **inativar** em vez de excluir.
- **"Mudei uma configuração e não vi botão de salvar."** Na aba **Configuração**,
  cada alteração é salva **na hora** em que você mexe no campo.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra, no ambiente de teste
   (https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
   Alves**, o menu **Pessoas & Cultura → Cultura & Celebrações** e confira, tela a
   tela, se cada marcador de print corresponde ao que aparece de verdade (cartões,
   Próximas Celebrações, Indicadores e as abas Experiência do Colaborador,
   Preferências e Rituais e Reconhecimento).
2. Verifique se o passo a passo, os benefícios e os dados fictícios refletem como
   você quer conduzir os vídeos.
3. Aprovado o **formato**, replico o mesmo padrão para os próximos módulos, nos
   lotes que você priorizar.
