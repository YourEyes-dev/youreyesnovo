# Manual do módulo — Contratos de Experiência

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e do módulo-piloto [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial e diz exatamente o que
> capturar em cada print, sempre com dados fictícios (LGPD).

- **Onde fica no menu:** seção **Pessoas & Cultura → Contratos de Experiência**
  (rota `/contratos-experiencia`).
- **Para quem é:** RH, Departamento Pessoal (DP) e Gestores imediatos.
- **Em uma frase:** acompanha o **período de experiência** de cada novo
  colaborador CLT — prazos de **45/90 dias**, alertas de vencimento, e as três
  saídas legais (**prorrogar**, **efetivar** ou **encerrar**), com **geração e
  assinatura digital** dos documentos, tudo fundamentado na **CLT art. 445**.
- **Importante:** os contratos **não são cadastrados aqui**. Eles aparecem
  **sozinhos** nesta tela quando um colaborador é admitido com o tipo
  **"CLT – Contrato de Experiência"** no módulo de **Admissão / Pessoas**. Esta
  tela é o **painel de gestão e decisão** do que já foi admitido.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Nenhum prazo passa despercebido.** O período de experiência tem data para
  acabar — e deixar vencer sem decisão **converte o vínculo em prazo
  indeterminado automaticamente** (perde-se a chance de encerrar sem custo). O
  sistema avisa com **15, 7 e 2 dias** de antecedência, para a decisão sair no
  tempo certo.
- **As três saídas legais em um clique.** Da própria linha do colaborador o RH
  **Prorroga** (quando ainda é permitido), **Efetiva** (converte para prazo
  indeterminado) ou **Encerra** (término normal ou rescisão antecipada) — com a
  regra da **CLT art. 445** aplicada sozinha.
- **Regra dos 90 dias garantida pelo sistema.** A experiência é de **no máximo
  90 dias**, com **uma única prorrogação**. O sistema **não deixa** ultrapassar
  esse limite nem prorrogar duas vezes — o erro que mais gera passivo
  trabalhista simplesmente não acontece.
- **Documento pronto e assinado digitalmente.** Contrato, termo de prorrogação,
  de efetivação e de rescisão são **gerados pelo sistema** e enviados para
  **assinatura digital** por link — colaborador, empregador e testemunhas
  assinam do próprio celular.
- **Contabilidade avisada na hora.** Efetivação e encerramento disparam um aviso
  automático ao **Hub Contábil**, sem o RH precisar redigitar nada.
- **Trilha de auditoria completa.** Cada ação (criação, prorrogação, efetivação,
  encerramento) fica registrada com **data, responsável e fundamentação legal** —
  nada se altera sem deixar rastro.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Período de experiência** | O "teste" inicial do vínculo CLT — no máximo **90 dias** (CLT art. 445). Nele, tanto empresa quanto colaborador podem encerrar com custo reduzido. |
| **1º Período / 2º Período** | A experiência pode ser dividida em duas etapas (ex.: **45 + 45**). O 1º Período é o contrato inicial; o 2º Período é o que passa a valer **depois de prorrogado**. |
| **Prorrogação** | Estender a experiência **uma única vez**, sem estourar os 90 dias no total. Depois de prorrogado, não dá para prorrogar de novo. |
| **Efetivação** | Aprovar o colaborador: o vínculo vira **CLT por prazo indeterminado** e o contrato de experiência é encerrado como concluído. |
| **Encerramento** | Finalizar a experiência: por **término normal** (chegou ao fim) ou por **rescisão antecipada** (antes do prazo), pelo empregador ou pelo empregado. |
| **Cláusula assecuratória** | Cláusula que, se existir no contrato, faz a rescisão antecipada seguir as regras de **aviso prévio** de contrato indeterminado. Sem ela, aplica-se **indenização de metade dos dias restantes** (CLT art. 479/480). |
| **Dias restantes** | Quantos dias faltam para o término atual do contrato. É o número que vira alerta (15/7/2 dias). |
| **Hub Contábil** | O canal por onde o RH manda eventos para a contabilidade. Efetivar/encerrar avisa o Hub sozinho. |
| **Assinatura digital** | O documento gerado é enviado por **link**; o signatário lê, confirma e **desenha a assinatura** na tela. O link vale por **7 dias**. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Existir admissão do tipo experiência.** O contrato só aparece nesta tela se
   houver uma admissão cadastrada com tipo **"CLT – Contrato de Experiência"** no
   módulo de **Admissão / Pessoas**. Sem isso, a lista fica vazia (é proposital —
   não se inventa contrato aqui).
2. **Uma empresa selecionada no seletor global.** A aba **Configuração da
   Empresa** só abre com uma empresa ativa selecionada.
3. **Configuração da empresa revisada** (recomendado): modelo de períodos
   (1 ou 2), duração padrão e alertas — feito na aba **Configuração da Empresa**
   (Fluxo 6).

> 💡 Se a lista abrir vazia, a causa quase sempre é o item 1: **não há admissão
> do tipo experiência**. A própria tela avisa isso no rodapé do card de
> explicação.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Contratos de Experiência**, o topo mostra o título **"Contratos de
Experiência"** e a linha **"Gestão de contratos com prazos, alertas e ações
legais integradas"**. Logo abaixo ficam **duas abas**:

| Aba | Para que serve |
|---|---|
| **Painel** | O dia a dia: card explicativo, indicadores, filtros e a tabela de todos os contratos com as ações (prorrogar, efetivar, encerrar, gerar documento). |
| **Configuração da Empresa** | As regras padrão da empresa: modelo de períodos, cláusula assecuratória, alertas de vencimento e política interna. |

Dentro do **Painel**, de cima para baixo: um **card azul "Como funciona esta
tela?"** (a explicação embutida — este módulo **não tem** botão de "Guia
Rápido"), uma faixa de **5 cartões indicadores**, a barra de **filtros** e a
**tabela** de contratos.

Os 5 indicadores são: **Em Experiência**, **Vencendo em 7 dias** (vermelho),
**Vencendo em 15 dias** (âmbar), **Vencendo em 30 dias** e **Total de
Contratos**.

> 📸 **PRINT 01 — Tela inicial do módulo (aba Painel)**
> **Onde:** menu **Pessoas & Cultura → Contratos de Experiência**, aba
> **Painel**.
> **O que precisa aparecer:** o título, o card azul **"Como funciona esta
> tela?"** e a faixa dos **5 cartões indicadores**.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; indicadores
> **Em Experiência 3**, **Vencendo em 7 dias 1**, **Vencendo em 15 dias 2**,
> **Vencendo em 30 dias 3**, **Total de Contratos 6**.
> **Ação filmada:** panorâmica lenta de cima para baixo, mostrando o card de
> explicação e os indicadores.

---

## 5. Passo a passo por fluxo

> Este módulo **não possui** um "Guia Rápido" em botão (como o do Ponto). A
> orientação embutida é o **card azul "Como funciona esta tela?"** no topo do
> Painel — vale mostrá-lo no vídeo como reforço.

### Fluxo 1 — Ler o painel e encontrar quem precisa de decisão

**Objetivo:** enxergar, em segundos, quais contratos estão perto do vencimento.
**Benefício:** o RH ataca primeiro o que é urgente, sem varrer planilha.

1. Abra a aba **Painel**.
2. Leia os **cartões indicadores** — o número em vermelho (**Vencendo em 7
   dias**) é a fila de urgência.
3. Na **tabela**, cada linha traz **Colaborador (nome + CPF)**, **Cargo**,
   **Unidade**, **Admissão**, **Término**, **Dias Restantes** (com barra de
   progresso), **Período** (1º/2º) e **Status**.
4. Linhas que vencem em **7 dias ou menos** ficam **destacadas** e mostram
   "**X dias**", "**Vence hoje!**" ou "**Vencido!**" em vermelho.
5. Use a busca e os filtros para focar: **buscar** por nome/CPF/cargo, filtrar
   por **Status**, **Prazo** (7/15/30 dias), **Unidade** e **Gestor**.

> 📸 **PRINT 02 — Tabela de contratos e filtros**
> **Onde:** Painel, área da tabela.
> **O que precisa aparecer:** a barra de filtros (busca, Status, Prazo, Unidade,
> Gestor) e a tabela com várias linhas e status diferentes.
> **Dados fictícios na tela:**
> - **Camila Duarte** (900.000.003-37) — Operadora de Produção — admissão
>   **20/08/2026** — término **03/10/2026** — **5 dias** (vermelho) — **1º
>   Período**.
> - **Diego Freitas** (900.000.004-18) — Desenvolvedor Full Stack — **2º
>   Período** — término **29/10/2026** — **31 dias**.
> - **Eduarda Lima** (900.000.005-07) — status **Efetivado**.
> **Ação filmada:** aplicar o filtro **Prazo → "Vencendo em 7 dias"** e mostrar a
> lista reduzir para a Camila.

> 📸 **PRINT 03 — Linha urgente em destaque**
> **Onde:** Painel, tabela filtrada por "Vencendo em 7 dias".
> **O que precisa aparecer:** a linha da **Camila Duarte** em fundo avermelhado,
> com a coluna **Dias Restantes** mostrando **"5 dias"** e a barra de progresso, e
> os botões de ação à direita.
> **Dados fictícios na tela:** Camila Duarte, **1º Período**, término
> **03/10/2026**.

> 💡 A barra de progresso enche conforme o contrato "gasta" o prazo — bate os
> **dias já passados** contra a **duração total**. É o termômetro visual de cada
> experiência.

---

### Fluxo 2 — Prorrogar um contrato

**Objetivo:** estender a experiência quando ainda não houve decisão de
efetivar/encerrar.
**Benefício:** ganha-se mais tempo de avaliação **sem estourar** o limite legal —
o sistema barra qualquer tentativa de passar de 90 dias ou prorrogar duas vezes.

1. Na linha do colaborador (em experiência), clique no ícone **Prorrogar**
   (↔ setas). Ele **só aparece** quando a prorrogação é permitida (contrato ainda
   **não prorrogado**, no **1º Período**, e com dias disponíveis dentro dos 90).
2. O sistema mostra o **1º Período** (duração e data-fim) e os **dias
   disponíveis** até o teto de 90.
3. Informe a **duração da prorrogação (dias)**. O sistema calcula o **total após
   prorrogação** em tempo real.
4. Se a soma passar de 90, aparece o aviso **"Total excede 90 dias! Reduza a
   duração"** e o botão fica bloqueado.
5. Clique em **Prorrogar** — o contrato passa a **2º Período**, ganha nova
   data-fim e os alertas são rearmados.

> 📸 **PRINT 04 — Modal "Prorrogar Contrato"**
> **Onde:** Painel → linha da Camila → ícone **Prorrogar**.
> **O que precisa aparecer:** o resumo do 1º período, os **dias disponíveis**, o
> campo de duração e o texto **"Total após prorrogação"**.
> **Dados fictícios na tela:** colaboradora **Camila Duarte**; **1º Período: 45
> dias**; **Dias disponíveis: 45**; duração digitada **45**; **Total após
> prorrogação: 90 dias**; nota **"CLT art. 445: máximo 90 dias, uma única
> prorrogação."**
> **Ação filmada:** digitar **45**, mostrar o total virar **90**, clicar em
> **Prorrogar**.

> 💡 Não existe o botão **Prorrogar** na linha? Então esse contrato **já foi
> prorrogado** ou já atingiu 90 dias — é o próprio sistema evitando a
> irregularidade.

---

### Fluxo 3 — Efetivar o colaborador

**Objetivo:** aprovar a experiência e tornar o vínculo permanente.
**Benefício:** um clique converte para **CLT prazo indeterminado**, atualiza o
cadastro e avisa a contabilidade.

1. Na linha do colaborador, clique no ícone **Efetivar** (✓ verde).
2. Leia o quadro **"O que acontece ao efetivar"**: vínculo passa a **CLT – prazo
   indeterminado**, contrato de experiência marcado como **concluído**, **Módulo
   Financeiro atualizado** e **registro permanente no histórico**.
3. Confira o resumo (colaborador, cargo, período total).
4. Clique em **Efetivar**. O sistema atualiza a admissão para prazo
   indeterminado e **envia o evento ao Hub Contábil** automaticamente.

> 📸 **PRINT 05 — Modal "Efetivar Colaborador"**
> **Onde:** Painel → linha do colaborador → ícone **Efetivar** (verde).
> **O que precisa aparecer:** o quadro verde "O que acontece ao efetivar" e o
> resumo do colaborador.
> **Dados fictícios na tela:** colaborador **Diego Freitas**, cargo
> **Desenvolvedor Full Stack**, **período total: 90 dias**.
> **Ação filmada:** clicar em **Efetivar** e mostrar o status da linha virar
> **Efetivado**.

> 💡 Efetivar é **definitivo** e alimenta a folha e a contabilidade — confirme a
> avaliação de desempenho **antes** (a empresa pode registrar essa exigência no
> campo **Política interna**, na aba Configuração).

---

### Fluxo 4 — Encerrar o contrato

**Objetivo:** finalizar a experiência (no prazo ou antes dele).
**Benefício:** o encerramento sai com o **enquadramento legal correto** e a
contabilidade é avisada na hora.

1. Na linha do colaborador, clique no ícone **Encerrar** (✕ vermelho).
2. Escolha o **Tipo de Encerramento**:
   - **Término normal do contrato** (chegou ao fim do prazo);
   - **Rescisão antecipada (empregador)**;
   - **Rescisão antecipada (empregado)**.
3. Informe a **Data de Encerramento** e, se quiser, o **Motivo**.
4. Em rescisão antecipada, aparece o aviso **"Atenção Legal"**:
   - **com cláusula assecuratória** → aplicam-se regras de **aviso prévio** como
     contrato indeterminado;
   - **sem cláusula** → **indenização de metade dos dias restantes** (art. **479**
     empregador / **480** empregado).
5. Clique em **Encerrar Contrato**. O evento é **enviado ao Hub Contábil**.

> 📸 **PRINT 06 — Modal "Encerrar Contrato" (aviso legal)**
> **Onde:** Painel → linha do colaborador → ícone **Encerrar** (vermelho).
> **O que precisa aparecer:** o seletor de tipo, a data, o campo de motivo e o
> quadro âmbar **"Atenção Legal"**.
> **Dados fictícios na tela:** colaboradora **Camila Duarte**; tipo **Rescisão
> antecipada (empregador)**; data **30/09/2026**; motivo **"Não adaptação à
> função durante o período de experiência"**; aviso mostrando a indenização
> calculada (metade dos dias restantes, art. 479 CLT).
> **Ação filmada:** trocar o tipo para "Rescisão antecipada (empregador)" e o
> quadro âmbar aparecer.

> 💡 O texto do aviso muda conforme o contrato **tiver ou não** cláusula
> assecuratória — é o sistema aplicando o art. 479/480 da CLT por você.

---

### Fluxo 5 — Gerar e assinar os documentos

**Objetivo:** emitir o documento certo e coletar as assinaturas digitalmente.
**Benefício:** contrato, prorrogação, efetivação e rescisão **prontos**, com
assinatura por link — sem papel, sem digitar de novo.

**Gerar o documento:**
1. Na linha do colaborador, clique no ícone **Gerar Documento** (📄).
2. Escolha o tipo. Cada um só habilita quando faz sentido:
   - **Contrato de Experiência** — sempre disponível;
   - **Termo de Prorrogação** — só se o contrato **foi prorrogado**;
   - **Termo de Efetivação** — só se **efetivado**;
   - **Termo de Rescisão** — só se **encerrado**.
3. O sistema **gera o documento** com os dados do colaborador e da empresa e o
   exibe em uma prévia.
4. Use **Imprimir**, **Baixar HTML** ou **Enviar p/ Assinatura**.

**Enviar para assinatura:**
5. Clique em **Enviar p/ Assinatura**, informe **nome do signatário**, o
   **papel** (Colaborador, Empregador, Testemunha 1 ou 2) e o **e-mail
   (opcional)**.
6. Clique em **Gerar Link de Assinatura** — o sistema devolve um **link** (válido
   por **7 dias**) para **copiar** e enviar. Use **"+ Gerar outro link (outra
   parte)"** para cada assinante.

**O signatário assina (no celular ou navegador):**
7. Ao abrir o link, ele vê o documento (etapa **Leitura**), confirma **"Li e
   compreendi o documento"**, **desenha a assinatura** (etapa **Assinatura**) e
   clica em **Confirmar Assinatura**.
8. A tela mostra **"Documento Assinado!"** e a assinatura fica registrada.

> 📸 **PRINT 07 — Modal "Gerar Documento" (tipos)**
> **Onde:** Painel → linha do colaborador → ícone **Gerar Documento**.
> **O que precisa aparecer:** a lista dos 4 tipos, com os indisponíveis
> explicando o motivo (ex.: "Contrato não foi prorrogado").
> **Dados fictícios na tela:** colaboradora **Camila Duarte**; **Contrato de
> Experiência** com o selo **"Gerar"**; **Termo de Prorrogação** desabilitado
> ("Contrato não foi prorrogado").

> 📸 **PRINT 08 — Documento gerado (prévia)**
> **Onde:** dentro do modal, após gerar.
> **O que precisa aparecer:** a **prévia do documento** e os botões **Imprimir**,
> **Baixar HTML** e **Enviar p/ Assinatura**.
> **Dados fictícios na tela:** título **"Contrato de Experiência"**, nome
> **Camila Duarte**, empresa **Empresa Staging LTDA**.

> 📸 **PRINT 09 — Formulário "Enviar p/ Assinatura"**
> **Onde:** modal do documento → botão **Enviar p/ Assinatura**.
> **O que precisa aparecer:** os campos **nome do signatário**, **papel** e
> **e-mail**.
> **Dados fictícios na tela:** signatário **Camila Duarte**, papel
> **Colaborador**, e-mail **camila.duarte@exemplo.com**.

> 📸 **PRINT 10 — Link de assinatura gerado**
> **Onde:** mesmo modal, após **Gerar Link de Assinatura**.
> **O que precisa aparecer:** a confirmação com o **link**, o botão **Copiar** e a
> nota **"O link expira em 7 dias"**, além de **"+ Gerar outro link (outra
> parte)"**.
> **Dados fictícios na tela:** link para **Camila Duarte (colaborador)**.
> **Ação filmada:** clicar em **Copiar** e mostrar o "Copiado".

> 📸 **PRINT 11 — Página de assinatura: Leitura (tela do signatário)**
> **Onde:** o link aberto no navegador/celular do colaborador
> (`/experiencia-assinatura/<token>`).
> **O que precisa aparecer:** o cabeçalho **YourEyes**, o passo **1 Leitura**, o
> card com Colaborador/Cargo/Admissão, o documento na tela e o botão **"Li e
> compreendi o documento"**.
> **Dados fictícios na tela:** **Camila Duarte**, Operadora de Produção,
> admissão **20/08/2026**.
> **Ação filmada:** ótimo momento para gravar a **tela real de um celular**.

> 📸 **PRINT 12 — Página de assinatura: Assinatura (desenho)**
> **Onde:** mesma página, passo **2 Assinatura**.
> **O que precisa aparecer:** a área de **desenho da assinatura** (com **Limpar**)
> e o botão **Confirmar Assinatura**.
> **Dados fictícios na tela:** "Assine abaixo — **Camila Duarte**".
> **Ação filmada:** desenhar a assinatura e clicar em **Confirmar Assinatura**.

> 📸 **PRINT 13 — Confirmação "Documento Assinado!"**
> **Onde:** a mesma página após confirmar.
> **O que precisa aparecer:** o ✓ verde, **"Documento Assinado!"** e o selo
> **"Assinatura concluída"**.
> **Dados fictícios na tela:** "Assinatura registrada com sucesso para **Camila
> Duarte**".

> 💡 Precisa de várias assinaturas (colaborador + empregador + testemunhas)?
> Gere **um link por parte** com **"+ Gerar outro link"** — cada pessoa assina do
> seu próprio dispositivo.

---

### Fluxo 6 — Configurar as regras da empresa

**Objetivo:** definir o padrão de experiência que a empresa aplica.
**Benefício:** contratos novos já nascem com o modelo, os alertas e a política
certos — sem ajuste manual caso a caso.

1. Abra a aba **Configuração da Empresa** (com uma empresa selecionada no seletor
   global).
2. Em **Modelo de Períodos**, escolha **1 único período** (ex.: 90 dias) ou **2
   períodos** (ex.: 45 + 45) e informe as durações. O selo **"Total: X dias"**
   avisa se passar de 90.
3. Em **Cláusula Assecuratória**, ligue/desligue **"Incluir cláusula
   assecuratória por padrão"**.
4. Em **Alertas e Política Interna**, ative os alertas de **15/7/2 dias**, defina
   os **dias de antecedência para ação** e escreva a **política interna** (ex.:
   avaliação de desempenho obrigatória antes de efetivar).
5. Clique em **Salvar Configuração**.

> 📸 **PRINT 14 — Configuração: Modelo de Períodos**
> **Onde:** aba **Configuração da Empresa**.
> **O que precisa aparecer:** o seletor de modelo, as durações do 1º/2º período e
> o selo **"Total: 90 dias"**.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; modelo **2
> períodos (ex.: 45 + 45)**; 1º período **45**, 2º período **45**; **Total: 90
> dias**.

> 📸 **PRINT 15 — Configuração: Cláusula, Alertas e Política**
> **Onde:** mesma aba, mais abaixo.
> **O que precisa aparecer:** o interruptor da cláusula assecuratória, os três
> alertas (15/7/2 dias), o campo de dias de antecedência e a caixa de política
> interna.
> **Dados fictícios na tela:** cláusula **desligada**; alertas **15/7/2 dias
> ligados**; antecedência **5 dias**; política interna **"Avaliação de desempenho
> obrigatória antes da efetivação."**
> **Ação filmada:** clicar em **Salvar Configuração**.

> 💡 A configuração é **por empresa**. Se a plataforma tiver mais de uma empresa,
> troque no seletor global e configure cada uma.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Deixou o período de experiência vencer? O vínculo virou permanente — e você nem percebeu."* Abre com um calendário estourando o prazo. | Imagem genérica de calendário |
| 8–22s | *"O YourEyes acompanha cada experiência e avisa com 15, 7 e 2 dias de antecedência."* | **PRINT 01** (indicadores) + **PRINT 03** (linha urgente) |
| 22–38s | *"Prorrogar, efetivar ou encerrar: um clique, com a CLT aplicada sozinha — nunca mais de 90 dias, nunca duas prorrogações."* | **PRINT 04** (prorrogar) + **PRINT 05** (efetivar) |
| 38–52s | *"Rescisão antecipada? O sistema já calcula a indenização certa, com ou sem cláusula assecuratória."* | **PRINT 06** (encerrar, aviso legal) |
| 52–68s | *"Contrato gerado e assinado digitalmente — colaborador e empresa assinam do celular."* | **PRINT 08** (documento) + **PRINT 12** (assinatura no celular) |
| 68–80s | *"YourEyes. O período de experiência sob controle, do primeiro ao último dia."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 5–8 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("agora eu prorrogo…", "vamos efetivar…").

1. **Abertura** — o que o módulo faz, de onde vêm os contratos (do módulo de
   Admissão) e o card "Como funciona esta tela?" (**PRINT 01**).
2. **Ler o painel** e filtrar por vencimento (**PRINT 02, 03**).
3. **Prorrogar** um contrato e mostrar o teto de 90 dias (**PRINT 04**).
4. **Efetivar** um colaborador (**PRINT 05**).
5. **Encerrar** por rescisão antecipada e mostrar o aviso legal (**PRINT 06**).
6. **Gerar o documento** e escolher o tipo (**PRINT 07, 08**).
7. **Enviar para assinatura** e copiar o link (**PRINT 09, 10**).
8. **Assinar** pelo celular: leitura, desenho e confirmação (**PRINT 11, 12,
   13**).
9. **Configurar a empresa**: períodos, cláusula, alertas e política (**PRINT 14,
   15**).
10. **Encerramento** — lembrar que efetivação/encerramento avisam o **Hub
    Contábil** sozinhos.

> 💡 Dica de gravação: este módulo **não tem** botão de Guia Rápido — use o card
> azul **"Como funciona esta tela?"** no topo do Painel como apoio da narração.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Tela inicial / Painel (card explicativo + indicadores)
- [ ] **PRINT 02** — Tabela de contratos e filtros
- [ ] **PRINT 03** — Linha urgente em destaque (vencendo em 7 dias)
- [ ] **PRINT 04** — Modal Prorrogar Contrato
- [ ] **PRINT 05** — Modal Efetivar Colaborador
- [ ] **PRINT 06** — Modal Encerrar Contrato (aviso legal)
- [ ] **PRINT 07** — Modal Gerar Documento (tipos)
- [ ] **PRINT 08** — Documento gerado (prévia)
- [ ] **PRINT 09** — Formulário Enviar p/ Assinatura
- [ ] **PRINT 10** — Link de assinatura gerado
- [ ] **PRINT 11** — Página de assinatura: Leitura (celular)
- [ ] **PRINT 12** — Página de assinatura: Assinatura (desenho)
- [ ] **PRINT 13** — Confirmação "Documento Assinado!"
- [ ] **PRINT 14** — Configuração: Modelo de Períodos
- [ ] **PRINT 15** — Configuração: Cláusula, Alertas e Política

---

## 9. Erros comuns / dúvidas frequentes

- **"A lista está vazia."** Não há admissão do tipo **"CLT – Contrato de
  Experiência"**. Cadastre a admissão nesse tipo no módulo de **Admissão /
  Pessoas** — o contrato aparece aqui sozinho.
- **"Não aparece o botão Prorrogar na linha."** O contrato **já foi prorrogado
  uma vez** ou já atingiu **90 dias**. A CLT permite **uma única** prorrogação, e
  o sistema respeita isso.
- **"O botão Prorrogar ficou bloqueado."** A duração digitada faz o **total
  passar de 90 dias**. Reduza a duração até o total ficar dentro do limite.
- **"Efetivei sem querer."** A efetivação é **definitiva** (converte o vínculo e
  avisa a contabilidade). Confira o colaborador no modal **antes** de confirmar.
- **"Qual encerramento escolher?"** **Término normal** = o prazo chegou ao fim;
  **rescisão antecipada** = encerrar antes do prazo (pelo empregador ou pelo
  empregado). O sistema mostra o enquadramento legal (art. 479/480) conforme a
  **cláusula assecuratória**.
- **"O link de assinatura não abre."** O link **expira em 7 dias**. Gere um novo
  em **Gerar Documento → Enviar p/ Assinatura**.
- **"A aba Configuração pede empresa."** Selecione uma empresa no **seletor
  global** — a configuração é **por empresa**.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/contratos-experiencia_periodo-de-experiencia.md`
   no projeto.
2. Se quiser conferir as telas descritas, acesse o **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/) logado como **Marina
   Alves**, empresa **Empresa Staging LTDA**, e abra **Pessoas & Cultura →
   Contratos de Experiência** — confira o **Painel** (indicadores, tabela e os
   modais de prorrogar/efetivar/encerrar/gerar documento) e a aba **Configuração
   da Empresa**.
3. Confira se o passo a passo, os benefícios e os marcadores de print refletem
   como você quer conduzir os vídeos. Aprovado o **formato**, replico o mesmo
   padrão para os demais módulos, nos lotes que você priorizar.
</content>
</invoke>
