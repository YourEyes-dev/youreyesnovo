# Manual do módulo — Ouvidoria (Canal de Ética)

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e na mesma profundidade do módulo-piloto
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial.

- **Onde fica no menu:** seção **Pessoas & Cultura → Ouvidoria** (rota `/ouvidoria`).
- **Para quem é:** RH, gestores e a alta liderança (comitê de ética); e, do outro
  lado do balcão, **qualquer colaborador** — inclusive quem quer falar **sem se
  identificar**.
- **Em uma frase:** um canal único para **sugestões, reclamações, denúncias,
  elogios e dúvidas**, com opção **anônima**, **link público** que dispensa
  login, **roteamento automático** por tipo, resposta rastreável e
  acompanhamento por **protocolo** — tudo sob a proteção da **LGPD**.
- **Importante:** a Ouvidoria tem **dois lados**. O **lado interno** (a tela
  `/ouvidoria`, dentro do sistema) é onde o RH recebe, tria e responde. O **lado
  externo** (o link público `ouvidoria-externa/…`, aberto no navegador de
  qualquer pessoa) é onde o colaborador registra sua manifestação sem precisar de
  usuário nem senha. Este manual cobre os dois.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Um canal de ética que as pessoas realmente usam.** Denúncia de assédio,
  fraude ou desvio raramente chega quando o único caminho é "falar com o chefe".
  O modo **anônimo** derruba a barreira do medo: quem envia anônimo **não tem
  nome, e-mail nem departamento registrados** — nem os gestores conseguem ver.
- **Sem login, direto do celular.** Um **link público único** vale para toda a
  empresa. O colaborador abre, escolhe o tipo, escreve e envia — sem app, sem
  cadastro, sem senha. Perfeito para colar no mural, no crachá ou mandar no grupo
  de WhatsApp.
- **Cada manifestação cai na mesa certa.** O **roteamento** define, por tipo
  (denúncia vai para o comitê, elogio vai para o gestor da área, etc.), qual
  **departamento** ou **pessoa** recebe. Nada se perde, nada fica "com todo mundo
  e com ninguém".
- **Acompanhamento por protocolo, mesmo anônimo.** Quem envia recebe um
  **protocolo** (ex.: `OUV-00000000-XXXXXX`). Com ele consulta o andamento e lê a
  resposta da empresa **sem se identificar** — a ponte que faltava entre sigilo e
  transparência.
- **Da denúncia à ação, sem retrabalho.** Com um clique, a manifestação vira
  **ações no Plano de Ação** (5W2H + priorização **GUT**), com **sugestões geradas
  por IA**. O problema relatado deixa de ser um desabafo e vira plano com dono e
  prazo.
- **Triagem inteligente.** A **pré-análise por IA** classifica sentimento,
  categoria, prioridade sugerida e sinaliza **risco** de segurança, saúde ou
  compliance — ajudando o RH a priorizar o que é grave.
- **Conformidade LGPD por padrão.** Dados de identificação só existem quando a
  pessoa escolhe se identificar, e ficam visíveis **apenas aos responsáveis**. O
  anônimo é anônimo de verdade.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Manifestação** | Qualquer mensagem enviada ao canal: sugestão, reclamação, denúncia, elogio ou dúvida. |
| **Tipo** | A natureza da manifestação. São cinco: 💡 Sugestão, ⚠️ Reclamação, 🚨 Denúncia, ⭐ Elogio, ❓ Dúvida. |
| **Anônimo** | Modo em que nenhum dado de identificação é registrado — nem nome, nem e-mail, nem departamento. |
| **Link público** | O endereço externo (`ouvidoria-externa/…`) que qualquer pessoa abre para registrar, **sem login**. É único por empresa. |
| **Protocolo** | O código de acompanhamento entregue a quem registra pelo link (ex.: `OUV-00000000-XXXXXX`). Serve para consultar o andamento e ler a resposta. |
| **Roteamento** | A regra que define qual **departamento** ou **pessoa** recebe cada **tipo** de manifestação. |
| **Status** | Em que ponto está a manifestação: **Pendente**, **Em análise**, **Respondido** ou **Arquivado**. |
| **Prioridade** | O grau de urgência definido pelo RH: **Baixa**, **Normal**, **Alta** ou **Urgente**. |
| **Pré-análise por IA** | Uma leitura automática que sugere sentimento, categoria, prioridade e alerta de risco antes do envio/triagem. |
| **Plano de Ação (5W2H / GUT)** | O módulo onde a manifestação vira ação com responsável e prazo; **GUT** = Gravidade × Urgência × Tendência, a nota que prioriza. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Estar logado com um perfil de gestão** para ver o lado interno completo. A
   tela distingue três níveis:
   - **Colaborador** — vê só a aba **Nova Manifestação** e **Minhas
     Manifestações**.
   - **Gestor (manager)** — vê também os **indicadores** (cartões do topo) e a aba
     **Todas Manifestações**, podendo responder e mudar status/prioridade.
   - **Administrador (admin)** — vê ainda a aba **Configurações** (link público e
     roteamento) e pode **excluir** manifestações.
2. **Um link público gerado** (Fluxo 1) — sem ele, o canal externo não abre.
3. **Roteamento configurado** (Fluxo 2) — opcional, mas recomendado: sem
   roteamento, as manifestações ficam visíveis a todos os gestores.
4. **Departamentos e responsáveis cadastrados** — para poder escolhê-los no
   roteamento.

> 💡 Para gravar, use a persona **Marina Alves** (Analista de RH) com perfil de
> **administrador** no ambiente de teste — assim as três abas aparecem e é
> possível filmar tanto a configuração quanto a triagem.

---

## 4. Mapa da tela (visão de 30 segundos)

**Lado interno (`/ouvidoria`).** No topo, o título **Ouvidoria** com o ícone de
coração-balão e o subtítulo *"Canal de comunicação para sugestões, reclamações,
denúncias e elogios"*. Logo abaixo (só para gestores) aparecem **5 cartões de
indicadores**: **Total, Pendentes, Em Análise, Respondidas, Anônimas**. Depois,
as abas:

| Aba | Para que serve | Quem vê |
|---|---|---|
| **Nova Manifestação** | Formulário para enviar uma manifestação pelo sistema. | Todos |
| **Todas Manifestações** / **Minhas Manifestações** | A lista para triagem (gestor) ou o histórico próprio (colaborador). | Todos (conteúdo muda pelo perfil) |
| **Configurações** | Link público da ouvidoria + roteamento por tipo. | Só administrador |

**Lado externo (link público).** Uma página enxuta, fora do sistema, com o nome
da empresa, um alternador **Registrar / Acompanhar** e o rodapé *"Canal de
Ouvidoria • Registro via link externo • Dados protegidos (LGPD)"*.

> 📸 **PRINT 01 — Tela inicial da Ouvidoria (lado interno)**
> **Onde:** menu **Pessoas & Cultura → Ouvidoria**.
> **O que precisa aparecer:** título **Ouvidoria**, os 5 cartões de indicadores e
> as 3 abas (Nova Manifestação / Todas Manifestações / Configurações).
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; indicadores como
> **Total 14, Pendentes 3, Em Análise 2, Respondidas 8, Anônimas 5**.
> **Ação filmada:** panorâmica lenta mostrando os cartões e as abas.

---

## 5. Passo a passo por fluxo

### Fluxo 1 — Gerar e distribuir o link público

**Objetivo:** criar o endereço externo que os colaboradores usarão para se
manifestar sem login.
**Benefício:** um único link para toda a empresa, pronto para o mural, o crachá
ou o WhatsApp.

1. Abra a aba **Configurações** (visível só para administrador).
2. No bloco **Link público da Ouvidoria**, clique em **Gerar link da ouvidoria**.
3. O link aparece pronto. Use os botões:
   - **Copiar** — copia o endereço.
   - **WhatsApp** — abre uma mensagem já escrita com o link.
   - **Abrir** — abre o canal externo numa nova aba (ótimo para conferir).
   - **Desativar / Ativar** — liga e desliga o canal sem apagar o link.
   - **Gerar novo link** — troca o endereço; **o link anterior deixa de
     funcionar** (use se o link vazou).

> 📸 **PRINT 02 — Link público gerado**
> **Onde:** Ouvidoria → **Configurações → Link público da Ouvidoria**.
> **O que precisa aparecer:** o endereço do link, o selo **Ativo** e os botões
> Copiar / WhatsApp / Abrir / Desativar / Gerar novo link.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; link terminando
> em `.../ouvidoria-externa/a1b2c3d4e5f6a7b8`; status **Ativo**.
> **Ação filmada:** clicar em **Copiar** e mostrar o aviso "Link copiado!".

> 💡 O mesmo link serve para sempre e para todos — não é preciso gerar um por
> pessoa. Só troque o link (**Gerar novo link**) se ele tiver vazado.

---

### Fluxo 2 — Configurar o roteamento por tipo

**Objetivo:** dizer para onde vai cada tipo de manifestação.
**Benefício:** a denúncia chega ao comitê de ética, o elogio ao gestor da área —
cada coisa na mesa certa, automaticamente.

1. Ainda em **Configurações**, vá ao bloco **Roteamento de Manifestações**.
2. Para cada um dos cinco tipos, escolha:
   - **Departamento Responsável** (ou *"Nenhum (todos os gestores)"*).
   - **Pessoa Responsável** (ou *"Nenhum (qualquer gestor)"*).
3. Clique em **Salvar Configurações**. Os tipos já configurados ganham o selo
   **Configurado**.

> 📸 **PRINT 03 — Roteamento por tipo**
> **Onde:** Ouvidoria → **Configurações → Roteamento de Manifestações**.
> **O que precisa aparecer:** os cinco blocos de tipo com os seletores de
> departamento e de responsável, e o botão **Salvar Configurações**.
> **Dados fictícios na tela:** 🚨 **Denúncia** → departamento **Recursos
> Humanos**, responsável **Marina Alves — Analista de RH**; ⭐ **Elogio** →
> responsável **Bruno Carvalho — Coordenador de Operações**; selo **Configurado**
> nos dois.
> **Ação filmada:** abrir o seletor de responsável da Denúncia e escolher Marina
> Alves, depois clicar em Salvar.

> 💡 Deixar em *"Nenhum"* não é erro: a manifestação simplesmente fica visível a
> todos os gestores. Use o roteamento quando quiser **sigilo** (ex.: denúncia só
> para o comitê) ou responsabilidade clara.

---

### Fluxo 3 — Registrar uma manifestação pelo sistema (colaborador logado)

**Objetivo:** enviar uma manifestação por dentro da plataforma.
**Benefício:** quem já está logado registra em segundos, ainda podendo escolher o
**modo anônimo**.

1. Abra a aba **Nova Manifestação**.
2. Escolha o **tipo** entre os cinco cartões (Sugestão, Reclamação, Denúncia,
   Elogio, Dúvida).
3. Decida a identificação no botão **Enviar de forma anônima**:
   - **Desligado** — seu nome fica visível aos gestores.
   - **Ligado** — aparece o aviso de que **nome, e-mail e departamento não serão
     registrados**.
4. Preencha **Assunto** (até 200 caracteres) e **Mensagem** (até 5.000).
5. (Opcional) Clique em **Pré-analisar com IA** para uma leitura automática antes
   de enviar (Fluxo 3a).
6. (Opcional) Anexe até **5 arquivos** de até **10 MB** cada como evidência.
7. Clique em **Enviar Manifestação**.

> 📸 **PRINT 04 — Nova Manifestação (tipos + modo anônimo)**
> **Onde:** Ouvidoria → aba **Nova Manifestação**.
> **O que precisa aparecer:** os cinco cartões de tipo, o botão **Enviar de forma
> anônima** e os campos Assunto e Mensagem.
> **Dados fictícios na tela:** tipo **Sugestão** selecionado; assunto **"Café da
> copa do 2º andar acabando cedo"**; mensagem curta de exemplo; contador
> **"36/200"**.
> **Ação filmada:** selecionar o cartão **Sugestão** e digitar o assunto.

> 📸 **PRINT 05 — Aviso do modo anônimo**
> **Onde:** aba **Nova Manifestação**, com o botão **Enviar de forma anônima**
> ligado.
> **O que precisa aparecer:** o alerta *"Manifestação Anônima: sua identidade
> será completamente protegida. Os gestores não terão acesso ao seu nome, email
> ou departamento."*
> **Dados fictícios na tela:** tipo **Denúncia** selecionado; toggle **ligado**.
> **Ação filmada:** ligar o botão e deixar o alerta em destaque na tela.

> 💡 O anexo é opcional, mas fortalece uma denúncia (foto, print, documento).
> Guarde sempre evidências fora do calor do momento.

---

### Fluxo 3a — Pré-analisar com IA (opcional, antes de enviar/triar)

**Objetivo:** ler a manifestação com apoio de IA.
**Benefício:** sentimento, categoria e prioridade sugeridos, além de alerta de
risco — priorização mais rápida e justa.

1. Com **tipo, assunto e mensagem** preenchidos (assunto com ao menos 5 e
   mensagem com ao menos 20 caracteres), clique em **Pré-analisar com IA**.
2. O painel mostra: **Sentimento** (positivo/neutro/negativo/urgente),
   **Prioridade Sugerida**, **Resumo**, **Categoria** e subcategorias,
   **Encaminhamento**, **Palavras-chave**, **Ação Sugerida** e o **% de
   confiança**.
3. Se a IA identificar **risco de segurança, saúde ou compliance**, aparece uma
   faixa vermelha de alerta.

> 📸 **PRINT 06 — Pré-análise por IA**
> **Onde:** aba **Nova Manifestação**, após clicar em **Pré-analisar com IA**.
> **O que precisa aparecer:** o painel **Análise por IA** com sentimento,
> prioridade sugerida, resumo, categoria, palavras-chave e a barra de confiança.
> **Dados fictícios na tela:** sentimento **Negativo 😟**, prioridade sugerida
> **ALTA**, categoria **"Infraestrutura / Copa"**, confiança **88%**.
> **Ação filmada:** clicar em **Pré-analisar com IA** e mostrar o painel surgindo.

> 💡 A IA **sugere**, não decide. A palavra final sobre prioridade e
> encaminhamento é sempre do RH.

---

### Fluxo 4 — Registrar pelo canal externo (link público, anônimo ou identificado)

**Objetivo:** deixar qualquer colaborador se manifestar **sem login**, do próprio
celular.
**Benefício:** o canal chega a quem não usa o sistema no dia a dia, com anonimato
real e proteção LGPD.

1. Abra o **link público** (o mesmo do Fluxo 1). A página mostra o nome da
   empresa e o alternador **Registrar / Acompanhar** — comece em **Registrar**.
2. Escolha o **tipo** de manifestação.
3. Em **Como deseja registrar?**, escolha:
   - **Anônimo** — nada de identificação é pedido nem gravado.
   - **Identificar-me** — abre os campos **CPF**, **Nome** e **E-mail
     (opcional)**. Ao digitar um CPF completo já cadastrado, o **nome é
     preenchido sozinho**.
4. Preencha **Assunto** e **Mensagem**.
5. Clique em **Enviar manifestação**. Aparece a faixa azul lembrando que, no modo
   anônimo, **nenhum dado de identificação é registrado**.

> 📸 **PRINT 07 — Canal externo, modo anônimo**
> **Onde:** o link público aberto no navegador (idealmente um celular).
> **O que precisa aparecer:** o cabeçalho **Canal de Ouvidoria** com o nome da
> empresa, o seletor de tipo, os botões **Anônimo / Identificar-me** (com
> **Anônimo** selecionado) e a faixa azul de proteção.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; tipo
> **Denúncia**; assunto **"Horas extras não registradas na equipe da noite"**.
> **Ação filmada:** escolher **Denúncia**, manter **Anônimo**, digitar o assunto.

> 📸 **PRINT 08 — Canal externo, identificando-se por CPF**
> **Onde:** o link público, com **Identificar-me** selecionado.
> **O que precisa aparecer:** os campos **CPF, Nome e E-mail** e o nome
> preenchido automaticamente após o CPF.
> **Dados fictícios na tela:** CPF **900.000.003-37**, nome **Camila Duarte**
> (preenchido sozinho), e-mail em branco.
> **Ação filmada:** digitar o CPF e mostrar o nome aparecendo no campo abaixo.

> 💡 O modo **anônimo** apaga a barreira do medo, mas o modo **identificado** é
> útil para elogios e sugestões, em que a pessoa quer aparecer. Deixe a escolha
> sempre com quem envia.

---

### Fluxo 5 — Receber o protocolo e acompanhar o andamento (canal externo)

**Objetivo:** dar a quem enviou uma forma de acompanhar, mesmo anônimo.
**Benefício:** transparência sem quebrar o sigilo — o protocolo é a "chave" da
manifestação.

1. Ao enviar (Fluxo 4), a tela de confirmação mostra **"Manifestação enviada!"** e
   o **protocolo** (ex.: `OUV-00000000-XXXXXX`), com um botão de **copiar**.
2. A pessoa **guarda o protocolo**.
3. Para acompanhar, volta ao link e clica em **Acompanhar pelo protocolo** (ou no
   alternador **Acompanhar** no topo).
4. Cola o protocolo e clica em **Consultar**.
5. A tela mostra **tipo, assunto, status, data de envio** e, quando houver, a
   **resposta da empresa**. Sem resposta ainda, aparece *"Ainda sem resposta.
   Volte a consultar mais tarde com o mesmo protocolo."*.

> 📸 **PRINT 09 — Protocolo entregue**
> **Onde:** canal externo, tela de confirmação após enviar.
> **O que precisa aparecer:** o ícone verde de sucesso, o texto **"Manifestação
> enviada!"**, o **protocolo** em destaque com o botão de copiar e o botão
> **Acompanhar pelo protocolo**.
> **Dados fictícios na tela:** protocolo **OUV-00000000-9F3K2A**.
> **Ação filmada:** clicar em copiar o protocolo e mostrar "Protocolo copiado!".

> 📸 **PRINT 10 — Acompanhamento por protocolo**
> **Onde:** canal externo, aba **Acompanhar**.
> **O que precisa aparecer:** o campo de protocolo, o botão **Consultar** e o
> cartão de resultado com status e a resposta da empresa.
> **Dados fictícios na tela:** protocolo **OUV-00000000-9F3K2A**; status
> **Respondido**; assunto **"Horas extras não registradas na equipe da noite"**;
> resposta curta da empresa (fictícia).
> **Ação filmada:** colar o protocolo, clicar em **Consultar** e mostrar a
> resposta aparecendo.

> 💡 Reforce nos comunicados internos: **"guarde seu protocolo"**. É a única forma
> de quem enviou anônimo voltar a ver o andamento.

---

### Fluxo 6 — Triar as manifestações (gestor)

**Objetivo:** organizar o que chega e priorizar o que importa.
**Benefício:** numa tela, o RH vê tudo, filtra e enxerga os indicadores do canal.

1. Abra a aba **Todas Manifestações**.
2. Use a **busca** (assunto, mensagem ou autor) e os filtros de **Tipo** e
   **Status**.
3. Cada cartão mostra o **tipo**, o **status**, a **prioridade**, se é **anônimo**
   ou o **autor**, a **data**, o **departamento/responsável** do roteamento e a
   contagem de **anexos**.
4. Os **cartões de indicadores** no topo resumem o canal: Total, Pendentes, Em
   Análise, Respondidas e Anônimas.

> 📸 **PRINT 11 — Lista de manifestações (triagem)**
> **Onde:** Ouvidoria → aba **Todas Manifestações**.
> **O que precisa aparecer:** a barra de busca, os filtros de Tipo e Status e
> vários cartões com selos diferentes.
> **Dados fictícios na tela:**
> - 🚨 **Denúncia** — **Anônimo** — status **Pendente** — prioridade **Alta**.
> - ⭐ **Elogio** — **Bruno Carvalho** — status **Respondido**.
> - 💡 **Sugestão** — **Camila Duarte** — **1 anexo** — status **Em Análise**.
> **Ação filmada:** aplicar o filtro **Tipo → Denúncia** e mostrar a lista
> reduzir.

> 💡 A manifestação **anônima nunca revela o autor**, mesmo na triagem — o selo
> mostra apenas "Anônimo". Isso é proposital.

---

### Fluxo 7 — Responder e atualizar status/prioridade (gestor)

**Objetivo:** dar retorno a quem se manifestou e manter o andamento em dia.
**Benefício:** resposta rastreável (com autor e data) e status sempre atualizado —
inclusive para quem consulta por protocolo.

1. No cartão da manifestação, ajuste o **Status** (Pendente, Em Análise,
   Respondido, Arquivado) e a **Prioridade** (Baixa, Normal, Alta, Urgente) pelos
   seletores.
2. Clique em **Responder**, escreva a resposta e clique em **Enviar Resposta**. O
   status vira **Respondido** e a resposta passa a mostrar **quem respondeu e
   quando**.
3. Se preciso, use **Ver mais / Ver menos** para ler mensagens longas.

> 📸 **PRINT 12 — Responder manifestação**
> **Onde:** aba **Todas Manifestações**, cartão expandido com o campo de resposta.
> **O que precisa aparecer:** os seletores de **Status** e **Prioridade**, o botão
> **Responder** e a caixa de texto da resposta.
> **Dados fictícios na tela:** manifestação de **Camila Duarte** (Sugestão);
> status alterado para **Respondido**; resposta fictícia curta.
> **Ação filmada:** mudar o status para **Em Análise**, clicar em **Responder**,
> digitar e enviar.

> 💡 A resposta enviada aqui é a **mesma** que a pessoa lê ao consultar pelo
> protocolo no canal externo (Fluxo 5). Uma resposta, dois lados.

---

### Fluxo 8 — Transformar a manifestação em ações (Plano de Ação)

**Objetivo:** converter o que foi relatado em ações com dono e prazo.
**Benefício:** o problema não morre na resposta — vira plano concreto, com
priorização **GUT** e apoio de IA.

1. No cartão, clique em **Criar Ações**.
2. No modal, clique em **Gerar Sugestões com IA** — a IA propõe até **5 ações**
   (5W2H: título, por quê, onde, como; tipo corretiva/preventiva/melhoria; e nota
   **GUT**).
3. **Selecione** as ações desejadas (ou use **Criar** em uma só) e clique em
   **Criar selecionadas**. Elas nascem no **Plano de Ação**, vinculadas à
   manifestação.
4. De volta ao cartão, aparece o bloco **"N ação(ões) no Plano de Ação"** com os
   códigos.

> 📸 **PRINT 13 — Sugestões de ação por IA (GUT)**
> **Onde:** cartão da manifestação → botão **Criar Ações** → **Gerar Sugestões
> com IA**.
> **O que precisa aparecer:** a lista de sugestões com título, tipo (Corretiva/
> Preventiva/Melhoria), a etiqueta **GUT** e as caixas de seleção.
> **Dados fictícios na tela:** ação **"Auditar registros de hora extra da equipe
> noturna"**, tipo **Corretiva**, **GUT: 45**.
> **Ação filmada:** marcar duas sugestões e clicar em **Criar selecionadas**.

> 📸 **PRINT 14 — Ações vinculadas no cartão**
> **Onde:** aba **Todas Manifestações**, cartão após criar as ações.
> **O que precisa aparecer:** o bloco **"2 ação(ões) no Plano de Ação"** com os
> códigos das ações.
> **Dados fictícios na tela:** códigos como **PA-0007** e **PA-0008**.

> 💡 O **GUT** (Gravidade × Urgência × Tendência) prioriza sozinho: quanto maior
> a nota, mais no topo do Plano de Ação a ação entra.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, dor → solução → prova. Personas fictícias, empresa Staging.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Nem toda verdade chega ao RH. Medo de represália cala muita gente."* Abre com uma caixa de sugestões empoeirada. | Imagem genérica |
| 8–22s | *"A Ouvidoria do YourEyes dá voz — inclusive anônima. Sem login, direto do celular."* | **PRINT 07** (canal externo anônimo) |
| 22–36s | *"Denúncia, reclamação, elogio: cada tipo vai para a pessoa certa, automaticamente."* | **PRINT 03** (roteamento) |
| 36–50s | *"Quem envia acompanha por protocolo — sigilo e transparência juntos."* | **PRINT 09** (protocolo) + **PRINT 10** (acompanhar) |
| 50–66s | *"E o RH prioriza com apoio de IA, transformando o relato em plano de ação."* | **PRINT 06** (IA) + **PRINT 13** (ações) |
| 66–80s | *"YourEyes Ouvidoria. Um canal de ética que as pessoas usam."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 5–8 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa.

1. **Abertura** — o que a Ouvidoria faz e seus dois lados (**PRINT 01**).
2. **Gerar o link público** e mostrar os botões (**PRINT 02**).
3. **Configurar o roteamento** por tipo (**PRINT 03**).
4. **Registrar pelo sistema** escolhendo o tipo e o modo anônimo (**PRINT 04,
   05**).
5. **Pré-analisar com IA** (**PRINT 06**).
6. **Abrir o canal externo** e registrar anônimo, depois identificado (**PRINT 07,
   08**).
7. **Mostrar o protocolo** e **acompanhar** por ele (**PRINT 09, 10**).
8. **Triar** na aba Todas Manifestações, com filtros (**PRINT 11**).
9. **Responder** e mudar status/prioridade (**PRINT 12**).
10. **Criar ações** com IA e ver o vínculo no cartão (**PRINT 13, 14**).
11. **Encerramento** — reforçar anonimato, protocolo e LGPD.

> 💡 Dica de gravação: para o canal externo, filme a tela **de um celular real** —
> reforça a mensagem de "sem login, de qualquer lugar".

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina Alves**
(Analista de RH, com perfil de administrador), empresa **Empresa Staging LTDA**.
Para os prints do canal externo, use o **link público** gerado no Fluxo 1 (abra-o,
de preferência, em um celular).

- [ ] **PRINT 01** — Tela inicial da Ouvidoria (indicadores + abas)
- [ ] **PRINT 02** — Link público gerado (Configurações)
- [ ] **PRINT 03** — Roteamento por tipo
- [ ] **PRINT 04** — Nova Manifestação (tipos + modo anônimo)
- [ ] **PRINT 05** — Aviso do modo anônimo
- [ ] **PRINT 06** — Pré-análise por IA
- [ ] **PRINT 07** — Canal externo, modo anônimo
- [ ] **PRINT 08** — Canal externo, identificando-se por CPF
- [ ] **PRINT 09** — Protocolo entregue
- [ ] **PRINT 10** — Acompanhamento por protocolo
- [ ] **PRINT 11** — Lista de manifestações (triagem)
- [ ] **PRINT 12** — Responder manifestação
- [ ] **PRINT 13** — Sugestões de ação por IA (GUT)
- [ ] **PRINT 14** — Ações vinculadas no cartão

---

## 9. Erros comuns / dúvidas frequentes

- **"O link externo abre com erro / diz que é inválido."** O link não foi gerado,
  foi **desativado** ou foi **trocado** ("Gerar novo link" invalida o anterior).
  Confira em **Configurações → Link público** (Fluxo 1).
- **"Não vejo a aba Configurações."** Ela é **só para administrador**. Gestores
  veem a triagem, mas não a configuração; colaboradores veem apenas as próprias
  manifestações.
- **"Não aparecem os indicadores nem a aba Todas Manifestações."** Isso é visão de
  **gestor/administrador**. Um colaborador comum vê só **Nova Manifestação** e
  **Minhas Manifestações** — proposital.
- **"Quero saber quem enviou a denúncia anônima."** Não é possível, por
  segurança: no modo anônimo **nenhum dado de identificação é registrado**. É o
  que garante a confiança no canal.
- **"A pessoa perdeu o protocolo."** Sem o protocolo não há como consultar o
  andamento pelo canal externo — ele é a chave da manifestação. Oriente a
  **guardar/copiar** o protocolo no momento do envio.
- **"O nome não preencheu sozinho ao digitar o CPF."** O preenchimento automático
  só ocorre quando o **CPF está completo e cadastrado** na empresa daquele link.
  CPF fora do cadastro é aceito, mas o nome deve ser digitado à mão.
- **"A manifestação não caiu na pessoa certa."** Revise o **roteamento** do tipo
  (Fluxo 2). Sem roteamento, ela fica visível a **todos os gestores**.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/ouvidoria_canal-de-etica.md` no projeto.
2. Se quiser conferir as telas descritas, acesse o **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
   Alves**, empresa **Empresa Staging LTDA**, e percorra
   **Pessoas & Cultura → Ouvidoria** (lado interno) e o **link público** gerado
   na aba Configurações (canal externo).
3. Confira se o passo a passo, os benefícios e os marcadores de print refletem
   como você quer conduzir os vídeos. Aprovado o formato, replico o mesmo padrão
   nos próximos módulos.
</content>
</invoke>
