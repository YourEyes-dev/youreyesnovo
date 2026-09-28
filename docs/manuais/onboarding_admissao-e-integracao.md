# Manual do módulo — Onboarding (Admissão Digital e Integração)

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e na mesma profundidade do piloto [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial.

- **Onde fica no menu:** seção **Pessoas & Cultura → Onboarding** (rota `/onboarding-rh`).
- **Para quem é:** RH, Departamento Pessoal (DP) e Gestores — e, na ponta, o
  **próprio novo colaborador**, que recebe um link e finaliza o cadastro sozinho.
- **Em uma frase:** conduz a chegada de um novo colaborador do começo ao fim —
  da **admissão digital** (dados, documentos e exame admissional) à **integração
  gamificada** (trilha de boas-vindas com etapas, pontos e certificado) — sem
  papel e com trilha de aprovação auditável.
- **Importante:** o módulo tem **duas frentes que trabalham juntas**:
  1. a **Admissão** (o cadastro do novo colaborador e a coleta de documentos),
     que hoje é operada dentro de **Colaboradores** (o antigo caminho `/admissao`
     leva direto para lá);
  2. o **Onboarding gamificado** propriamente dito (a tela `/onboarding-rh`, com
     as trilhas, os processos e os indicadores de integração).
  Este manual cobre as duas, na ordem em que acontecem na vida real.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Admissão 100% digital, sem pilha de papel.** O RH abre a admissão, e o
  próprio colaborador finaliza o cadastro pelo **celular** — envia foto, RG, CPF,
  CTPS e os demais documentos de onde estiver, por um **link seguro**.
- **Checklist de documentos que se envia sozinho.** Um clique gera a lista de
  documentos e manda por **WhatsApp** ou **e-mail** para o novo colaborador —
  com marcação do que já foi entregue e do que falta.
- **Homologação com trilha de auditoria.** Cada documento passa por
  **aprovar / rejeitar / substituir**, e a admissão avança por um **fluxo de
  aprovação** com responsável, data e observação registrados. Nada se perde.
- **Tudo conversa com o resto do sistema.** Concluída a admissão, o registro
  vira **colaborador ativo** (aparece em Colaboradores, no Ponto, etc.). Vínculo
  de **contrato de experiência** já sai com o contrato criado no módulo próprio;
  o processo também entra no **Hub Contábil**.
- **Integração que engaja de verdade.** A trilha de onboarding é **gamificada**:
  etapas com **pontos**, **certificado** ao concluir e conexão com o **PDI**. O
  novo colaborador conhece a cultura, os valores e o time de forma interativa.
- **Indicadores de integração.** Taxa de conclusão, tempo médio de integração e
  a **percepção cultural** coletada dos recém-chegados — dados que mostram se a
  chegada das pessoas está funcionando.
- **Feito para a LGPD.** Documentos sensíveis ficam sob acesso controlado e os
  aceites legais (Termos, Privacidade, DPA) são registrados na ativação.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Admissão digital** | O cadastro do novo colaborador preenchido em etapas (dados, contato, profissional, bancários, exame, documentos). |
| **Link de cadastro** | Endereço único (`/completar-cadastro/…`) que o RH envia ao colaborador para ele finalizar o próprio cadastro. |
| **Completar cadastro** | A tela que o colaborador abre pelo link para enviar a foto e os documentos. Não precisa ter senha/login. |
| **Homologação** | A conferência do RH: aprovar, rejeitar ou pedir novo envio de cada documento. |
| **Fluxo de aprovação (workflow)** | A sequência de etapas que a admissão percorre até ser aprovada, cada uma com responsável e observação. |
| **Status da admissão** | Em que ponto está: Rascunho, Aguardando Documentos, Em Análise, Aprovado, Reprovado, Concluído. |
| **Template de onboarding** | O “molde” da trilha de integração: define as etapas, o prazo, e a quem se aplica (função, departamento, vínculo). |
| **Etapa (da trilha)** | Cada passo da integração: apresentação, cultura & valores, checklist, quiz, reflexão, etc. |
| **Processo de onboarding** | A trilha em andamento de um colaborador específico — com progresso (%) e pontos. |
| **Trilha gamificada / pontos** | Cada etapa concluída vale pontos; o colaborador vê o próprio avanço. |
| **Certificado** | Documento emitido automaticamente quando o colaborador conclui a trilha (se o template ligar essa opção). |
| **Conexão com PDI** | Ao concluir a trilha, o Plano de Desenvolvimento Individual pode ser alimentado automaticamente. |
| **Percepção cultural** | Respostas que o colaborador dá durante a trilha sobre cultura e integração — viram indicador agregado no RH. |
| **Contrato de experiência** | Vínculo CLT por prazo determinado (CLT art. 445); quando escolhido, o contrato é criado sozinho no módulo próprio. |
| **Exame admissional** | Dados do ASO de admissão (data, validade, resultado, clínica, médico, CRM). |

> 💡 **Ativação de conta** é coisa diferente de link de cadastro. O
> **link de cadastro** é para o novo colaborador enviar documentos. A **ativação
> de conta** (`/ativar-conta`) é a porta de entrada do **responsável da empresa**
> na implantação do sistema (Portal de Implantação), com aceite de Termos,
> Privacidade e DPA. Não confunda os dois no vídeo.

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Empresa cadastrada e ativa** (Estrutura Organizacional → Empresa).
2. **Cargos e Departamentos criados** — a admissão pede cargo e departamento, e
   os templates de onboarding podem ser filtrados por eles.
3. **Pelo menos um template de onboarding ativo** — sem template aplicável, a
   admissão até se conclui, mas não há trilha gamificada para o novo colaborador
   percorrer.
4. **Contato do colaborador** (e-mail/celular) para enviar o link de cadastro e o
   checklist de documentos.

> 📸 **PRINT 01 — Tela inicial do Onboarding (aba Processos)**
> **Onde:** menu **Pessoas & Cultura → Onboarding**, aba **Processos**.
> **O que precisa aparecer:** o título **“Onboarding Gamificado”**, as três abas
> (**Processos**, **Indicadores**, **Templates**) e os cartões de contagem
> (Total, Pendentes, Em andamento, Concluídos) com a lista de processos abaixo.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; um processo de
> **Felipe Nunes** com barra de progresso e pontuação (ex.: 60% • 120pts),
> status **Em Andamento**.
> **Ação filmada:** panorâmica lenta mostrando as três abas e os cartões.

---

## 4. Mapa da tela (visão de 30 segundos)

O módulo tem **duas telas** que você vai alternar no vídeo:

**A) Onboarding gamificado** (`/onboarding-rh`) — três abas:

| Aba | Para que serve |
|---|---|
| **Processos** | Acompanha a trilha de cada novo colaborador: status, progresso e pontos. |
| **Indicadores** | Painel de KPIs (taxa de conclusão, tempo médio) e a percepção cultural agregada. |
| **Templates** | Cria e edita os “moldes” de trilha (as etapas, o prazo e a quem se aplicam). |

**B) Admissão** (dentro de **Colaboradores** — o antigo `/admissao` redireciona
para lá) — onde nasce a admissão digital, com a **lista de admissões**, o
**formulário em 6 etapas** e a tela de **detalhe/homologação**.

> 💡 Regra de ouro da ordem: **primeiro a admissão** (cadastro + documentos +
> homologação), **depois a trilha** (a integração gamificada). O processo de
> onboarding de cada pessoa nasce a partir da admissão dela.

---

## 5. Passo a passo por fluxo

### Fluxo 1 — Montar o template da trilha de onboarding

**Objetivo:** definir uma vez o roteiro de boas-vindas que valerá para os novos
colaboradores.
**Benefício:** padroniza a integração — todo mundo do mesmo grupo recebe a mesma
acolhida, sem depender da memória de quem está de plantão.

1. Abra **Onboarding → aba Templates**.
2. Clique em **Novo Template**.
3. Preencha **Nome** (ex.: “Onboarding CLT — Operações”), **Descrição** e o
   **Prazo (dias)** para concluir a trilha.
4. Defina **a quem se aplica**: **Funções**, **Departamentos** e **Tipos de
   vínculo** (deixar vazio = vale para todos).
5. Ligue, se quiser, **Emitir certificado ao concluir** e **Conectar ao PDI**.
6. **Salve** e depois abra o template para **adicionar as etapas**.

> 📸 **PRINT 02 — Aba Templates (lista)**
> **Onde:** Onboarding → **Templates**.
> **O que precisa aparecer:** os cartões de template com selos **Ativo**,
> **prazo em dias** e **Certificado**, e os botões **Novo Template** e
> **Importar Planilha**.
> **Dados fictícios na tela:** template **“Onboarding CLT — Operações”**,
> **15 dias**, **Ativo**, selo **Certificado**.

> 📸 **PRINT 03 — Novo Template (formulário)**
> **Onde:** Templates → **Novo Template**.
> **O que precisa aparecer:** os campos Nome, Descrição, Prazo, os seletores de
> **Funções / Departamentos / Tipos de vínculo** e os interruptores **Emitir
> certificado** e **Conectar ao PDI**.
> **Dados fictícios na tela:** nome **“Onboarding CLT — Operações”**, prazo
> **15**, vínculo **CLT**, certificado **ligado**.

> 💡 Cada template é filtrado por função, departamento e vínculo. Assim, um
> operador de produção e um analista de TI podem receber trilhas diferentes,
> automaticamente.

---

### Fluxo 2 — Adicionar as etapas da trilha

**Objetivo:** montar o roteiro que o colaborador vai percorrer.
**Benefício:** cada etapa vira uma experiência guiada, com pontos e tempo
estimado — dá ritmo e engajamento à chegada.

1. No template, clique em **Adicionar Etapa**.
2. Escolha o **Tipo** da etapa. Os tipos disponíveis são:
   **Apresentação Institucional**, **Cultura & Valores**, **Mural de
   Boas-vindas**, **Checklist de Integração**, **Conteúdo Livre**, **Quiz** e
   **Reflexão**.
3. Dê um **Título**, uma **Descrição** e o **Formato** (Texto, Vídeo,
   Apresentação ou Híbrido). Para vídeo/apresentação, informe a **URL**.
4. Defina **Pontuação**, **Tempo estimado (min)**, **Ordem** e se é
   **Obrigatória**.
5. **Salve** — a etapa entra na sequência da trilha.

> 📸 **PRINT 04 — Detalhe do template com as etapas**
> **Onde:** Templates → clique em um template.
> **O que precisa aparecer:** a lista de etapas numeradas, cada uma com ícone
> colorido do tipo, selo do tipo, **tempo** e **pontos**, e o selo
> **Obrigatória**; o botão **Adicionar Etapa**.
> **Dados fictícios na tela:** etapas como **“Bem-vindo à Empresa Staging”**
> (Apresentação Institucional), **“Nossos Valores”** (Cultura & Valores),
> **“Checklist do 1º dia”** (Checklist de Integração).

> 📸 **PRINT 05 — Nova Etapa (formulário)**
> **Onde:** dentro do template → **Adicionar Etapa**.
> **O que precisa aparecer:** o seletor de **Tipo** aberto mostrando os 7 tipos,
> o **Formato**, e os campos Pontuação / Tempo / Ordem / Obrigatória.
> **Dados fictícios na tela:** tipo **Cultura & Valores**, título
> **“Nossos Valores”**, pontuação **10**, tempo **5 min**, obrigatória **sim**.

> 💡 A etapa **Cultura & Valores** puxa sozinha a Missão, Visão, Valores e
> Comportamentos cadastrados em **Estratégia & Governança → Cultura** — o texto
> que você digita entra como complemento.

---

### Fluxo 3 — Abrir uma admissão digital (RH)

**Objetivo:** cadastrar o novo colaborador em etapas.
**Benefício:** um roteiro guiado garante que nenhum dado essencial fica de fora,
e o formulário salva sozinho enquanto você preenche.

1. Vá em **Colaboradores** e clique em **Nova Admissão** (o caminho antigo
   `/admissao` também leva a Colaboradores).
2. Preencha as **6 etapas** do formulário, na ordem:
   **1) Dados Pessoais**, **2) Contato**, **3) Profissional**,
   **4) Bancários**, **5) Exame Admissional**, **6) Documentos**.
3. Na etapa **Profissional**, escolha o **Tipo de Vínculo**. Se marcar **CLT –
   Contrato de Experiência**, o sistema avisa que criará o contrato
   automaticamente no módulo de Contratos de Experiência.
4. Na etapa **Documentos**, você já pode anexar o que tiver em mãos — ou deixar
   o próprio colaborador enviar depois pelo link (Fluxo 5).
5. **Salve** — a admissão é criada e aparece na lista.

> 📸 **PRINT 06 — Lista de Admissões (com indicadores e filtros)**
> **Onde:** Colaboradores → área de **Admissão**.
> **O que precisa aparecer:** os indicadores no topo, a busca por nome/função/
> CPF, os filtros de **status** e **departamento**, e os cartões de admissão com
> as barras de **Documentos** e **Aprovação**; o botão **Nova Admissão**.
> **Dados fictícios na tela:** cartão de **Felipe Nunes** — **Assistente
> Administrativo**, **Administrativo** — status **Aguardando Documentos**,
> Documentos **2/12**.

> 📸 **PRINT 07 — Nova Admissão: etapa Dados Pessoais (com o passo a passo)**
> **Onde:** **Nova Admissão** (etapa 1).
> **O que precisa aparecer:** a régua de **6 etapas** no topo (Dados Pessoais,
> Contato, Profissional, Bancários, Exame Admissional, Documentos) e os campos
> da etapa atual.
> **Dados fictícios na tela:** **Felipe Nunes**, CPF **900.000.006-80**, RG
> fictício, data de nascimento e nome da mãe fictícios.

> 📸 **PRINT 08 — Nova Admissão: etapa Profissional (vínculo)**
> **Onde:** **Nova Admissão** (etapa 3).
> **O que precisa aparecer:** o seletor **Tipo de Vínculo** aberto (CLT prazo
> indeterminado, CLT contrato de experiência, Pró-labore, Estagiário,
> Temporário, Autônomo) e, ao escolher **Contrato de Experiência**, o quadro
> explicando a criação automática do contrato (CLT art. 445).
> **Dados fictícios na tela:** cargo **Assistente Administrativo**, departamento
> **Administrativo**, vínculo **CLT – Contrato de Experiência**, jornada
> **44h semanais**.

> 💡 Felipe Nunes (CPF 900.000.006-80) é uma **persona fictícia** criada para
> este manual, na faixa de CPFs da casa (900.000.0XX). **Nunca** use dados reais
> nas capturas.

---

### Fluxo 4 — Montar e enviar o checklist de documentos

**Objetivo:** dizer ao colaborador exatamente o que ele precisa providenciar.
**Benefício:** menos idas e vindas — a lista sai formatada e vai direto pelo
WhatsApp ou e-mail, com o que já foi entregue marcado.

1. Na lista, abra o menu **⋮** do cartão do colaborador (ou o botão
   **Checklist** no detalhe) e escolha **Checklist de Docs**.
2. Veja o **progresso** (quantos documentos já foram aprovados) e a lista de
   **documentos obrigatórios e opcionais**.
3. Envie por **WhatsApp** ou **E-mail**, ou use **Copiar Texto** / **Baixar
   Documento**.

> 📸 **PRINT 09 — Modal “Checklist de Documentos”**
> **Onde:** menu **⋮** do cartão → **Checklist de Docs**.
> **O que precisa aparecer:** a barra de progresso (ex.: **2/12 documentos**),
> a lista com selos Obrigatório/Opcional e os quatro botões **Copiar Texto**,
> **Baixar Documento**, **WhatsApp** e **E-mail**.
> **Dados fictícios na tela:** colaborador **Felipe Nunes**, cargo **Assistente
> Administrativo**; documentos como RG, CPF, Comprovante de Residência, CTPS,
> Exame Admissional.

> 💡 A lista padrão inclui RG, CPF, Comprovante de Residência, Título de Eleitor,
> CTPS, Certidão de Nascimento/Casamento, Foto 3x4, Comprovante de Escolaridade
> e Exame Admissional (obrigatórios), além de Reservista e Certificados de Cursos
> (opcionais).

---

### Fluxo 5 — Enviar o link para o colaborador finalizar o cadastro

**Objetivo:** deixar o próprio colaborador enviar foto e documentos.
**Benefício:** o RH não digita nada por ele nem recebe pilhas de PDF por e-mail —
o colaborador resolve pelo celular, em minutos.

1. No menu **⋮** do cartão (na Admissão **ou** em Colaboradores), clique em
   **Compartilhar Link**.
2. O sistema **copia o link** `.../completar-cadastro/<token>` para a área de
   transferência (aparece o aviso “Link copiado!”).
3. **Cole** esse link no WhatsApp/e-mail do colaborador.

> 📸 **PRINT 10 — Compartilhar Link**
> **Onde:** menu **⋮** do cartão → **Compartilhar Link**.
> **O que precisa aparecer:** o item **Compartilhar Link** no menu e o aviso
> (toast) **“Link copiado! Envie para o colaborador finalizar o cadastro.”**
> **Dados fictícios na tela:** cartão de **Felipe Nunes**.

> 💡 Se aparecer “Esta admissão não possui link de cadastro gerado”, é porque a
> admissão ainda não gerou o token — salve a admissão primeiro.

---

### Fluxo 6 — O colaborador finaliza o cadastro (visão do colaborador)

**Objetivo:** o novo colaborador envia a foto e os documentos.
**Benefício:** experiência simples, pelo celular, sem precisar criar senha.

1. O colaborador **abre o link** que recebeu.
2. Na tela **Finalizar Cadastro**, ele **envia a foto** (clicando ou arrastando).
3. **Envia cada documento** solicitado (foto ou PDF) na área correspondente.
4. Clica em **Finalizar e Enviar para RH** — só é liberado quando todos os
   **documentos obrigatórios** foram enviados.
5. Aparece a confirmação **“Cadastro Enviado!”** — os dados vão para homologação.

> 📸 **PRINT 11 — Colaborador: tela “Finalizar Cadastro”**
> **Onde:** o link `/completar-cadastro/…` aberto (ótimo para gravar no celular).
> **O que precisa aparecer:** a saudação com o nome, o círculo de **foto**, a
> lista de **Documentos Necessários** com botões **Enviar**, e o botão
> **Finalizar e Enviar para RH**.
> **Dados fictícios na tela:** **“Olá, Felipe Nunes”**, documentos em envio.
> **Ação filmada:** enviar a foto e um documento, depois finalizar.

> 📸 **PRINT 12 — Colaborador: confirmação “Cadastro Enviado!”**
> **Onde:** após finalizar.
> **O que precisa aparecer:** o cartão verde de sucesso com a mensagem de que os
> dados foram **enviados para homologação pelo RH**.
> **Dados fictícios na tela:** tela de confirmação (sem dados sensíveis).

> 💡 O link não pede login: é de uso único do colaborador. Se estiver
> **inválido ou expirado**, gere e envie um novo pelo **Compartilhar Link**.

---

### Fluxo 7 — Homologar documentos e aprovar a admissão (RH)

**Objetivo:** conferir o que o colaborador enviou e aprovar (ou pedir correção).
**Benefício:** cada decisão fica registrada — quem aprovou, quando e por quê —,
protegendo a empresa e dando rastreabilidade total.

1. Abra a admissão de **Felipe Nunes** e vá na aba **Documentos**.
2. Para cada documento enviado: **Aprovar**, **Rejeitar** (com motivo) ou
   **Substituir** (reabrir para novo envio).
3. Vá na aba **Aprovação** e conduza o **fluxo de aprovação**: clique em
   **Analisar Etapa** e **Aprove** ou **Rejeite** (rejeição exige observação).
4. Concluída a aprovação, a admissão avança de status até **Concluído** — e o
   registro passa a existir como **colaborador ativo**.

> 📸 **PRINT 13 — Detalhe da Admissão (abas)**
> **Onde:** lista de Admissões → **Visualizar** o cartão.
> **O que precisa aparecer:** o cabeçalho com foto, nome e **selo de status**, e
> as abas **Dados**, **Documentos**, **Aprovação** e **Histórico**; o botão
> **Checklist**.
> **Dados fictícios na tela:** **Felipe Nunes**, **Assistente Administrativo •
> Administrativo**, status **Em Análise**.

> 📸 **PRINT 14 — Aba Documentos (homologação)**
> **Onde:** detalhe da Admissão → aba **Documentos**.
> **O que precisa aparecer:** a lista de documentos enviados com os botões
> **Aprovar / Rejeitar / Substituir** e o status de cada um.
> **Dados fictícios na tela:** RG e CPF **Aprovados**, Comprovante de Residência
> **Enviado (aguardando)**.
> **Ação filmada:** aprovar um documento e mostrar o status mudar.

> 📸 **PRINT 15 — Aba Aprovação (fluxo de aprovação)**
> **Onde:** detalhe da Admissão → aba **Aprovação**.
> **O que precisa aparecer:** a linha do tempo de etapas com o selo **Atual** na
> etapa pendente e os botões **Analisar Etapa → Aprovar / Rejeitar**.
> **Dados fictícios na tela:** etapa atual sob responsabilidade de **Bruno
> Carvalho**; contador **“1/3 etapas”**.

> 💡 O sistema **não apaga** documentos rejeitados nem etapas: tudo fica na aba
> **Histórico**, com autor, data e observação.

---

### Fluxo 8 — Acompanhar a trilha de integração (Processos)

**Objetivo:** ver como anda a integração de cada novo colaborador.
**Benefício:** o RH enxerga num relance quem já começou, quem travou e quem
concluiu — e cobra no tempo certo.

1. Abra **Onboarding → aba Processos**.
2. Veja os cartões de contagem (**Total, Pendentes, Em andamento, Concluídos**).
3. Em cada processo, acompanhe o **progresso (%)** e os **pontos** obtidos.
4. Ao concluir, o processo mostra **Concluído** e, se o template pedir, o
   **certificado é emitido** e o **PDI é alimentado**.

> 📸 **PRINT 16 — Aba Processos com um processo em andamento**
> **Onde:** Onboarding → **Processos**.
> **O que precisa aparecer:** os cartões de contagem e a lista com o processo de
> **Felipe Nunes**, barra de progresso e pontos, com o selo de status.
> **Dados fictícios na tela:** **Felipe Nunes** — **Em Andamento** — **60% •
> 120pts**; contadores no topo (ex.: Total 4, Concluídos 2).

---

### Fluxo 9 — Ler os indicadores de integração

**Objetivo:** medir se a chegada das pessoas está funcionando.
**Benefício:** taxa de conclusão, tempo médio e a percepção cultural viram
argumento e melhoria contínua — não achismo.

1. Abra **Onboarding → aba Indicadores**.
2. Leia os **KPIs**: Total de Processos, Taxa de Conclusão, Tempo Médio, Em
   Andamento e Respostas Culturais.
3. Veja os gráficos de **Distribuição de Status** e **Progresso Geral**.
4. Role até **Percepção Cultural** para ver as respostas agregadas (com filtro
   por categoria) e as **Observações dos Colaboradores**.

> 📸 **PRINT 17 — Aba Indicadores**
> **Onde:** Onboarding → **Indicadores**.
> **O que precisa aparecer:** a fileira de KPIs, o gráfico de pizza de status, o
> painel de **Progresso Geral** e o bloco **Percepção Cultural — Respostas
> Agregadas**.
> **Dados fictícios na tela:** Taxa de Conclusão **75%**, Tempo Médio **8d**,
> respostas de percepção cultural fictícias.

> 💡 A percepção cultural só aparece conforme os colaboradores concluem as
> etapas — em uma base recém-criada, o bloco pode aparecer vazio (é esperado).

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, mostrando dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Contratou? Agora vem a papelada, o vaivém de documentos, o primeiro dia perdido."* Abre com uma mesa cheia de papéis. | Imagem genérica de papelada |
| 8–22s | *"No YourEyes, a admissão é digital. O RH abre, e o novo colaborador finaliza tudo pelo celular."* | **PRINT 07** (nova admissão) + **PRINT 11** (colaborador no celular) |
| 22–35s | *"A lista de documentos vai por WhatsApp. O RH só confere e aprova."* | **PRINT 09** (checklist) + **PRINT 14** (homologação) |
| 35–50s | *"Aprovou? Vira colaborador na hora — e começa a integração."* | **PRINT 15** (aprovação) + **PRINT 16** (trilha) |
| 50–65s | *"Uma trilha de boas-vindas com pontos, certificado e a cultura da empresa."* | **PRINT 04** (etapas) + **PRINT 16** (processo) |
| 65–80s | *"E indicadores que mostram se a chegada das pessoas está funcionando."* | **PRINT 17** (indicadores) |
| 80–90s | *"YourEyes. Da contratação à integração, sem papel."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 6–9 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("vamos montar a trilha…", "agora eu abro a admissão…").

1. **Abertura** — o que o módulo faz e as duas frentes (**PRINT 01**).
2. **Montar um template** de onboarding (**PRINT 02, 03**).
3. **Adicionar etapas** à trilha (**PRINT 04, 05**).
4. **Abrir uma admissão** e percorrer as 6 etapas (**PRINT 06, 07, 08**).
5. **Enviar o checklist** de documentos por WhatsApp (**PRINT 09**).
6. **Compartilhar o link** com o colaborador (**PRINT 10**).
7. **Trocar de lugar:** mostrar a tela que o colaborador vê e finalizar o
   cadastro (**PRINT 11, 12**).
8. **Voltar ao RH:** homologar documentos e aprovar a admissão (**PRINT 13, 14,
   15**).
9. **Acompanhar a trilha** de integração (**PRINT 16**).
10. **Ler os indicadores** de onboarding (**PRINT 17**).
11. **Encerramento** — reforçar a ordem: admissão → homologação → integração.

> 💡 Dica de gravação: grave o **Fluxo 6** (a tela do colaborador) num celular
> de verdade — é o momento mais convincente do vídeo.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**. Novo colaborador
fictício: **Felipe Nunes** (CPF **900.000.006-80**).

- [ ] **PRINT 01** — Onboarding: aba Processos (tela inicial)
- [ ] **PRINT 02** — Aba Templates (lista)
- [ ] **PRINT 03** — Novo Template (formulário)
- [ ] **PRINT 04** — Detalhe do template com etapas
- [ ] **PRINT 05** — Nova Etapa (formulário, tipos)
- [ ] **PRINT 06** — Lista de Admissões (indicadores + filtros)
- [ ] **PRINT 07** — Nova Admissão: etapa Dados Pessoais (régua de 6 etapas)
- [ ] **PRINT 08** — Nova Admissão: etapa Profissional (vínculo / contrato de experiência)
- [ ] **PRINT 09** — Modal Checklist de Documentos (WhatsApp/e-mail)
- [ ] **PRINT 10** — Compartilhar Link (menu + aviso)
- [ ] **PRINT 11** — Colaborador: tela Finalizar Cadastro (foto + documentos)
- [ ] **PRINT 12** — Colaborador: confirmação Cadastro Enviado
- [ ] **PRINT 13** — Detalhe da Admissão (abas)
- [ ] **PRINT 14** — Aba Documentos (homologação: aprovar/rejeitar)
- [ ] **PRINT 15** — Aba Aprovação (fluxo de aprovação)
- [ ] **PRINT 16** — Aba Processos (trilha em andamento)
- [ ] **PRINT 17** — Aba Indicadores

---

## 9. Erros comuns / dúvidas frequentes

- **"O menu não tem ‘Admissão’ separado."** Correto: a admissão vive dentro de
  **Colaboradores** (o antigo `/admissao` redireciona para lá). Use **Nova
  Admissão**.
- **"O botão Compartilhar Link deu erro."** A admissão ainda não gerou o link de
  cadastro — **salve** a admissão primeiro e tente de novo.
- **"O colaborador diz que o link está inválido/expirado."** Gere e envie um novo
  pelo **Compartilhar Link**.
- **"O colaborador não consegue finalizar."** Falta algum **documento
  obrigatório** — o botão de finalizar só libera quando todos os obrigatórios
  foram enviados.
- **"A admissão não vira colaborador ativo."** Ela precisa passar pela
  **homologação** e pelo **fluxo de aprovação** até o status **Concluído**.
- **"Criei a admissão, mas não apareceu trilha de onboarding."** Confira se há um
  **template ativo** cujos critérios (função, departamento, vínculo) batem com o
  colaborador. Sem template aplicável, não há trilha.
- **"A etapa Cultura & Valores está ‘vazia’."** Ela puxa os dados de
  **Estratégia & Governança → Cultura**; preencha a identidade estratégica lá.
- **"O bloco de percepção cultural está vazio."** Normal enquanto ninguém
  concluiu etapas — as respostas aparecem conforme a trilha é percorrida.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/onboarding_admissao-e-integracao.md` no projeto.
2. Confira se os fluxos (admissão → link → cadastro do colaborador → homologação
   → trilha), os benefícios e os 17 marcadores de print refletem como você quer
   conduzir os vídeos.
3. Se quiser conferir as telas de referência, abra o **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/) logado como **Marina
   Alves** e navegue por **Pessoas & Cultura → Onboarding** e por
   **Colaboradores → Nova Admissão** — apenas para comparar com os prints
   descritos (nenhuma alteração é necessária lá).
