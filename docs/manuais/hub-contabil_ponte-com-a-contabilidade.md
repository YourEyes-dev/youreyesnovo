# Manual do módulo — Hub Contábil (ponte com a contabilidade)

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e na mesma profundidade do piloto aprovado
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial.

- **Onde fica no menu:** seção **Documentos & Governança → Hub Contábil**.
- **Rota:** `/hub-contabil`.
- **Para quem é:** RH, Departamento Pessoal (DP) e Gestores que conversam com a
  contabilidade (interna ou terceirizada).
- **Em uma frase:** é a **ponte organizada entre o RH/DP e a contabilidade** —
  cada demanda (admissão, demissão, férias, folha, atestado, guia, certidão…)
  vira um **processo** rastreável, com documentos, checklist, conversa e prazo
  (SLA), do rascunho até a conclusão.
- **Como o sistema chama a tela por dentro:** o título no topo é **"Hub de
  Comunicação Contábil"**, com o subtítulo *"Centralização e automação da
  comunicação entre DP, RH e Contabilidade"*.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Fim do e-mail solto e do WhatsApp perdido.** Toda solicitação para a
  contabilidade vira um **processo com código**, com histórico, documentos e
  conversa no mesmo lugar. Nada mais se perde em caixa de entrada.
- **Cada demanda com prazo (SLA).** Cada tipo de processo tem um **prazo em
  horas** configurável. O sistema calcula o vencimento e **acende alerta** para
  o que está vencido ou a vencer nas próximas 48h — antes de virar problema.
- **Padronização por checklist.** Cada tipo de processo já traz um **checklist**
  do que precisa ser entregue (contrato assinado, documentos pessoais, etc.).
  O RH marca item a item e vê a barra de progresso — ninguém esquece um papel.
- **Dossiê digital por processo.** Documentos (ficha de registro, TRCT, holerite,
  espelho de ponto, guias, ASO…) ficam **anexados ao processo**, versionados e
  com marcação de "requer assinatura".
- **Automação a partir dos outros módulos.** Quando as **férias são aprovadas**,
  por exemplo, o Hub **cria o processo sozinho** e já o coloca como "Pronto para
  envio", com o selo **Auto**. Menos digitação, menos esquecimento.
- **Visão de gestão pronta.** Kanban por etapa, linha do tempo por colaborador e
  relatórios com taxa de conclusão, taxa de automação e SLAs críticos — para o
  gestor enxergar o gargalo num relance.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Processo** | Uma solicitação à contabilidade (ex.: "Admissão — Camila Duarte"). É a unidade central do módulo, com código próprio. |
| **Código** | O "número do protocolo" do processo, gerado automaticamente. |
| **Tipo** | A natureza da demanda: Admissão, Demissão, Férias, Advertência, Folha/Ponto, Atestado, Guia, etc. |
| **Status** | Em que etapa o processo está (Rascunho, Aguardando Documentos, Enviado, Em Análise, Concluído…). |
| **Prioridade** | Baixa, Normal, Alta ou **Urgente** — a urgente aparece em vermelho. |
| **Competência** | O mês/ano de referência da demanda (ex.: 09/2026). |
| **SLA** | O prazo (em horas) para resolver o processo. O sistema calcula quando vence. |
| **Contabilidade** | O escritório/parceiro contábil destinatário do processo (cadastrado nas Configurações). |
| **Checklist** | A lista de itens/documentos que aquele tipo de processo exige. |
| **Dossiê** | O conjunto de documentos anexados ao processo. |
| **Auto** | Selo dos processos que o sistema criou sozinho a partir de outro módulo (ex.: férias aprovadas). |
| **Pendência** | Um comentário marcado como algo que precisa ser resolvido. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Estar logado com um perfil de RH/DP** que enxerga o menu **Documentos &
   Governança → Hub Contábil** (nas gravações, use **Marina Alves**).
2. **Colaboradores cadastrados** — o campo "Colaborador" do novo processo busca
   direto no cadastro (por nome, CPF ou cargo) e preenche o CPF sozinho.
3. **(Recomendado) Pelo menos uma contabilidade parceira cadastrada** — feito em
   **Config. → Contabilidades Parceiras** (Fluxo 8). Sem ela, o processo é criado
   normalmente, mas fica sem destinatário selecionável.
4. **(Opcional) SLAs revisados** por tipo de processo (Fluxo 8) — o sistema já
   traz prazos-padrão, mas cada empresa pode ajustar.

> 💡 Diferente do Ponto, o Hub **não exige uma "chave de liga/desliga"** no
> cadastro da empresa: basta abrir o módulo e criar a primeira solicitação. Numa
> base nova, o Painel aparece zerado com o convite **"Criar primeira
> solicitação"** — bom ponto de partida para o tutorial.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Hub Contábil**, o topo mostra o título **"Hub de Comunicação
Contábil"** e o subtítulo explicativo. Logo abaixo há uma **barra de abas
roláveis** (deslize na horizontal para ver todas). As abas por **tipo** trazem um
**contador** com quantos processos daquele tipo estão em aberto.

| Aba | Para que serve |
|---|---|
| **Painel** | Visão operacional: indicadores (KPIs), alertas de SLA, processos ativos e volume por tipo. |
| **Admissão** | Processos do tipo Admissão (com filtros e busca). |
| **Demissão** | Processos de Demissão / Rescisão. |
| **Férias** | Processos de Férias (é onde caem os gerados automaticamente). |
| **Advertência** | Processos de Advertência. |
| **Folha/Ponto** | Processos de Ponto / Folha. |
| **Atestados** | Processos de Atestado / Afastamento. |
| **Geral** | Solicitações gerais (o que não se encaixa nos demais). |
| **Todos** | Lista completa de processos ativos, de qualquer tipo. |
| **Kanban** | Quadro por etapa; arraste os cards para mudar o status. |
| **Colaboradores** | Linha do tempo consolidada por pessoa. |
| **Relatórios** | Indicadores gerenciais e gráficos. |
| **Config.** | SLAs, contabilidades parceiras, integrações e templates de checklist. |

> 📸 **PRINT 01 — Tela inicial (Painel)**
> **Onde:** menu **Documentos & Governança → Hub Contábil**, aba **Painel**.
> **O que precisa aparecer:** o título "Hub de Comunicação Contábil", a barra de
> abas com contadores e os cinco cartões de indicadores (Em Andamento, Pend.
> Documentos, Pronto p/ Envio, Assinaturas, SLA Vencido), além da lista
> "Processos Ativos" e do painel "Volume por Tipo".
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; indicadores como
> **8 em andamento**, **2 pend. documentos**, **1 SLA vencido**; processos como
> "Admissão — Camila Duarte" e "Férias — Diego Freitas".
> **Ação filmada:** panorâmica lenta mostrando as abas e os cartões.

---

## 5. Passo a passo por fluxo

> Este módulo **não tem** um botão "Guia Rápido" embutido (diferente do Ponto).
> Portanto, no vídeo, conduza pelos fluxos abaixo — não procure um guia na tela.

### Fluxo 1 — Abrir uma nova solicitação

**Objetivo:** registrar uma demanda para a contabilidade.
**Benefício:** a partir daqui a demanda tem código, prazo, dossiê e conversa —
tudo rastreável.

1. No **Painel** (ou em qualquer aba de tipo), clique em **Nova Solicitação**
   (ou **Novo Processo**).
2. Escolha o **Tipo de Processo** (Admissão, Demissão/Rescisão, Férias,
   Advertência, Atestado/Afastamento, Ponto/Folha, Eventos Variáveis, Alteração
   Contratual, Mudança Salarial, CAT, PPP/LTCAT, Pró-Labore ou Solicitação Geral).
3. Defina a **Prioridade** (Baixa, Normal, Alta ou Urgente).
4. No campo **Colaborador**, busque a pessoa por **nome, CPF ou cargo** — ao
   selecionar, o **CPF é preenchido sozinho** e o **Título** é sugerido no
   formato "Tipo — Nome".
5. Ajuste o **Título** se quiser, informe a **Competência** (mês/ano) e escolha a
   **Contabilidade** de destino (se houver cadastrada).
6. Escreva a **Descrição / Observações** e clique em **Criar Processo**. Ele
   nasce com status **Rascunho**.

> 📸 **PRINT 02 — Modal "Nova Solicitação"**
> **Onde:** botão **Nova Solicitação** (Painel).
> **O que precisa aparecer:** os campos Tipo, Prioridade, Título, o seletor de
> Colaborador com busca, CPF, Competência, Contabilidade e Descrição.
> **Dados fictícios na tela:** Tipo **Admissão**, Prioridade **Normal**,
> colaboradora **Camila Duarte** (900.000.003-37), Título auto-sugerido
> **"Admissão — Camila Duarte"**, Competência **09/2026**, Contabilidade
> **"Contábil Exemplo ME"**.
> **Ação filmada:** digitar "Camila" na busca, selecionar, mostrar o CPF e o
> título se preenchendo sozinhos, clicar em **Criar Processo**.

> 💡 O campo Colaborador puxa direto do cadastro da empresa — não precisa digitar
> o CPF na mão nem correr risco de erro de digitação.

---

### Fluxo 2 — Localizar processos (abas por tipo, "Todos" e busca)

**Objetivo:** achar rapidamente o processo certo.
**Benefício:** filtros por tipo, status e texto evitam rolar listas enormes.

1. Clique na aba do **tipo** desejado (ex.: **Admissão**) ou em **Todos**.
2. Use a **busca** para filtrar por **nome, código ou CPF**.
3. Use o seletor de **Status** para ver só um estágio (ex.: "Aguard. Docs").
4. Cada card mostra código, título, colaborador, competência, data e o **selo de
   status**; processos com **SLA vencido** ficam com a borda vermelha e o
   automáticos trazem o selo **Auto**.
5. Clique no card para abrir o **detalhe** (Fluxo 3).

> 📸 **PRINT 03 — Lista de processos por tipo (com filtros)**
> **Onde:** Hub Contábil → aba **Admissão** (ou **Todos**).
> **O que precisa aparecer:** o campo de busca, o filtro de status, o botão
> **Novo Processo** e vários cards de processos com selos de status diferentes.
> **Dados fictícios na tela:** cards "Admissão — Camila Duarte" (Aguard. Docs),
> "Admissão — Diego Freitas" (Pronto p/ Envio), um card com borda vermelha e
> etiqueta **SLA vencido**.
> **Ação filmada:** digitar "Camila" na busca e aplicar o filtro de status.

---

### Fluxo 3 — Trabalhar o processo (documentos, checklist, chat, histórico)

**Objetivo:** conduzir o processo até a conclusão.
**Benefício:** tudo do processo — papéis, tarefas, conversa e trilha — numa única
gaveta lateral.

Ao clicar num processo, abre um **painel lateral** com o cabeçalho (código, selo
de status, colaborador, competência, data e **SLA**), um seletor para **mudar o
status** e **quatro abas**:

**a) Documentos** — o dossiê do processo.
1. Clique em **Anexar Documento**.
2. Escolha o **Tipo do Documento** (Ficha de Registro, Contrato/Aditivo, Aviso e
   Recibo de Férias, TRCT/Rescisão, Espelho de Ponto, Relatório de Folha,
   Holerite, Guia/Comprovante, ASO, Documento Pessoal, etc.).
3. Dê um **nome/descrição**, arraste ou selecione o arquivo (**PDF, Word, Excel
   ou imagem, até 50 MB**) e, se for o caso, marque **"requer assinatura"**.
4. Clique em **Anexar**. O documento entra na lista com **status**, **versão** e
   botão de **download**.

**b) Checklist** — o que falta entregar.
5. Marque cada item concluído; itens **obrigatórios** ficam sinalizados e a
   **barra de progresso** mostra o avanço.

**c) Chat** — a conversa do processo.
6. Escreva um comentário; marque **"Pendência"** (fica destacado em amarelo) e/ou
   **"Visível à contabilidade"** quando a mensagem não for interna. Clique em
   **Enviar**.

**d) Histórico** — a trilha de auditoria.
7. Veja a linha do tempo das ações e as mudanças de status (etapa anterior →
   nova).

Para avançar o processo, use o seletor **Status** no cabeçalho (Rascunho →
Aguardando Documentos → Pronto para Envio → Enviado → Recebido → Em Análise →
Processado → Aguardando Assinatura → Concluído, entre outros).

> 📸 **PRINT 04 — Detalhe do processo (aba Documentos)**
> **Onde:** clicar em um processo → aba **Documentos**.
> **O que precisa aparecer:** o cabeçalho com código, selo de status, colaborador,
> competência e SLA; o seletor de status; e a lista de documentos com botão de
> download.
> **Dados fictícios na tela:** processo "Admissão — Camila Duarte", status
> **Aguardando Documentos**, SLA para **30/09 18:00**, documentos "Ficha de
> Registro" e "Documento Pessoal".

> 📸 **PRINT 05 — Modal "Anexar Documento ao Dossiê"**
> **Onde:** aba Documentos → botão **Anexar Documento**.
> **O que precisa aparecer:** o seletor de Tipo do Documento, o campo de nome, a
> área de arrastar arquivo (com o aviso "até 50MB") e a opção "requer assinatura".
> **Dados fictícios na tela:** Tipo **Contrato / Aditivo**, nome **"Contrato —
> Camila Duarte"**, opção "requer assinatura" marcada.

> 📸 **PRINT 06 — Aba Checklist (com barra de progresso)**
> **Onde:** detalhe do processo → aba **Checklist**.
> **O que precisa aparecer:** a barra de progresso, itens marcados e itens
> obrigatórios sinalizados.
> **Dados fictícios na tela:** checklist de Admissão com **4/6** concluídos; item
> "Contrato assinado" ainda pendente e marcado como *obrigatório*.

> 📸 **PRINT 07 — Aba Chat (comentário / pendência)**
> **Onde:** detalhe do processo → aba **Chat**.
> **O que precisa aparecer:** mensagens com autor e horário, um comentário
> marcado como **Pendência** (amarelo) e outro **Visível à Contabilidade**, além
> da caixa de escrita com as duas opções.
> **Dados fictícios na tela:** mensagem de **Marina Alves** "Falta o comprovante
> de residência" marcada como pendência.
> **Ação filmada:** digitar um comentário, marcar "Visível à contabilidade" e
> clicar em **Enviar**.

> 📸 **PRINT 08 — Aba Histórico (trilha de auditoria)**
> **Onde:** detalhe do processo → aba **Histórico**.
> **O que precisa aparecer:** a linha do tempo das ações com a transição de
> status (ex.: "aguardando documentos → pronto para envio").
> **Dados fictícios na tela:** eventos assinados por **Marina Alves** com datas
> de Setembro/2026.

> 💡 O **Chat** distingue mensagem **interna** (só o RH vê) de mensagem **visível
> à contabilidade** — use isso para separar conversa de bastidor da comunicação
> oficial.

---

### Fluxo 4 — Reabrir um processo concluído ou cancelado

**Objetivo:** voltar a mexer num processo já encerrado.
**Benefício:** reabertura controlada — exige um **motivo**, que fica registrado no
histórico; nada é alterado silenciosamente.

1. Abra um processo com status **Concluído** ou **Cancelado**.
2. Clique em **Reabrir** (canto superior do painel).
3. Informe o **motivo da reabertura** (obrigatório) e confirme.
4. O processo volta para **Rascunho** e o motivo entra no histórico/conversa.

> 📸 **PRINT 09 — Reabrir processo**
> **Onde:** processo concluído → botão **Reabrir**.
> **O que precisa aparecer:** o modal "Reabrir Processo" com a caixa de motivo e
> o aviso de que voltará para **Rascunho**.
> **Dados fictícios na tela:** motivo **"Contabilidade pediu documento
> complementar"**.

---

### Fluxo 5 — Kanban: mover processos pelas etapas

**Objetivo:** gerir o fluxo de forma visual.
**Benefício:** enxergar todos os processos por etapa e mudar o status arrastando.

1. Abra a aba **Kanban**.
2. Veja as colunas por etapa (Rascunho, Aguard. Docs, Pronto p/ Envio, Enviado,
   Em Análise, Pend. Complementação, Docs Devolvidos, Aguard. Assinatura,
   Concluído).
3. **Arraste** um card de uma coluna para outra para **mudar o status**.
4. Cada card mostra código, prioridade (🔴 urgente / 🟠 alta), aviso de **SLA
   vencido**, colaborador, competência e o selo **Auto** quando aplicável.

> 📸 **PRINT 10 — Kanban por status**
> **Onde:** Hub Contábil → aba **Kanban**.
> **O que precisa aparecer:** as colunas por etapa com contadores e vários cards
> distribuídos; um card sendo arrastado, se possível.
> **Dados fictícios na tela:** "Admissão — Camila Duarte" em Aguard. Docs;
> "Férias — Diego Freitas" (selo Auto) em Pronto p/ Envio.
> **Ação filmada:** arrastar um card de "Pronto p/ Envio" para "Enviado".

---

### Fluxo 6 — Linha do tempo por colaborador

**Objetivo:** ver tudo o que já passou pela contabilidade sobre uma pessoa.
**Benefício:** histórico consolidado por colaborador, útil em auditoria e em
conversas com o gestor.

1. Abra a aba **Colaboradores**.
2. **Busque** a pessoa por nome ou CPF na lista à esquerda (cada uma mostra
   quantos processos tem).
3. Selecione o colaborador e veja, à direita, a **linha do tempo** de processos,
   com ícone por tipo, competência, data e status.
4. Clique em qualquer item para abrir o detalhe.

> 📸 **PRINT 11 — Linha do tempo por colaborador**
> **Onde:** Hub Contábil → aba **Colaboradores**.
> **O que precisa aparecer:** a lista de colaboradores com contador à esquerda e
> a linha do tempo com ícones por tipo à direita.
> **Dados fictícios na tela:** **Camila Duarte** selecionada, com Admissão
> (09/2026) e Atestado (09/2026) na trilha.

---

### Fluxo 7 — Relatórios gerenciais

**Objetivo:** medir volume, prazos e automação.
**Benefício:** o gestor vê o gargalo num relance e mostra resultado.

1. Abra a aba **Relatórios**.
2. Confira os **KPIs**: Total de Processos, **Taxa de Conclusão**, **Automação
   %** e **SLA Vencido** (com quantos a vencer em 48h).
3. Analise os gráficos: **Volume por Mês** (6 meses), **Distribuição por Status**
   (pizza) e **Volume por Tipo de Processo** (barras).
4. Veja a lista de **Processos com SLA Crítico** (vencidos e a vencer).

> 📸 **PRINT 12 — Relatórios gerenciais**
> **Onde:** Hub Contábil → aba **Relatórios**.
> **O que precisa aparecer:** os quatro KPIs no topo e os gráficos de volume por
> mês, pizza por status e barras por tipo.
> **Dados fictícios na tela:** Total **24**, Taxa de Conclusão **62%**, Automação
> **17%**, SLA Vencido **1**.

---

### Fluxo 8 — Configurar o Hub (SLA, contabilidades, integrações, checklists)

**Objetivo:** deixar o módulo com a cara da empresa.
**Benefício:** prazos, parceiros e listas de conferência sob medida — e as
automações à vista.

1. Abra a aba **Config.**.
2. **SLA por Tipo de Processo:** ajuste o **prazo em horas** de cada tipo (padrões
   de fábrica: Admissão 48h, Demissão 72h, Férias 24h, Advertência 24h, Atestado
   48h, Folha/Ponto 72h, Eventos 48h, Geral 96h) e clique em **Salvar SLAs**.
3. **Contabilidades Parceiras:** cadastre nome, e-mail e responsável em
   **Adicionar Contabilidade**; ative/desative as existentes.
4. **Integrações Automáticas Ativas:** confira quais eventos de outros módulos
   geram processos sozinhos (Admissão, Demissão, Férias, Contratos de
   Experiência e Holerites aparecem como **Ativo**; Advertências como **Em
   desenvolvimento**).
5. **Templates de Checklist:** por tipo de processo, veja os itens **globais**
   (padrão do sistema, com o ícone de globo, não editáveis) e crie itens
   **customizados** da sua empresa (obrigatório/opcional e ordem). Os
   customizados têm prioridade sobre os globais de mesmo nome.

> 📸 **PRINT 13 — Config.: SLA por tipo de processo**
> **Onde:** Hub Contábil → **Config.** → cartão **SLA por Tipo de Processo**.
> **O que precisa aparecer:** a grade de tipos com os campos de horas e o botão
> **Salvar SLAs**.
> **Dados fictícios na tela:** Admissão **48h**, Férias **24h**, Demissão **72h**.

> 📸 **PRINT 14 — Config.: Contabilidades Parceiras**
> **Onde:** **Config.** → cartão **Contabilidades Parceiras**.
> **O que precisa aparecer:** a lista de contabilidades com selo Ativo/Inativo e o
> formulário "Adicionar Contabilidade".
> **Dados fictícios na tela:** contabilidade **"Contábil Exemplo ME"**,
> responsável **"João Contador"**, e-mail **contato@contabilexemplo.com.br**.

> 📸 **PRINT 15 — Config.: Integrações Automáticas Ativas**
> **Onde:** **Config.** → cartão **Integrações Automáticas Ativas**.
> **O que precisa aparecer:** a lista de módulos que geram processos sozinhos, com
> os selos **Ativo** / **Em desenvolvimento**.
> **Dados fictícios na tela:** Férias, Admissão, Demissão, Holerites como
> **Ativo**; Advertências como **Em desenvolvimento**.

> 📸 **PRINT 16 — Config.: Templates de Checklist**
> **Onde:** **Config.** → cartão **Templates de Checklist**.
> **O que precisa aparecer:** os tipos de processo expansíveis, itens globais (com
> o ícone de globo) e itens customizados, com marcação de obrigatório/opcional.
> **Dados fictícios na tela:** grupo **Admissão** aberto, item global "Documentos
> pessoais (RG/CPF)" e um item customizado "Termo de teletrabalho" (opcional).

> 💡 Os itens **globais** são padrões do sistema e não podem ser editados nem
> apagados — para adaptar, crie um item customizado da empresa; ele prevalece.

---

### Fluxo 9 — Processo gerado automaticamente (integração de Férias)

**Objetivo:** entender de onde vêm os processos com o selo **Auto**.
**Benefício:** o RH não precisa recriar no Hub o que já foi aprovado em outro
módulo — o sistema faz a ponte sozinho.

1. No módulo de **Férias**, quando um pedido é **aprovado**, o Hub detecta o
   evento e **cria um processo do tipo Férias** automaticamente.
2. Esse processo nasce já em **Pronto para Envio**, com o selo **Auto**, o
   colaborador, a competência (mês do início das férias) e uma descrição com o
   período — sem digitação manual.
3. Ele aparece na aba **Férias** e no **Painel**, pronto para o RH conferir os
   documentos e enviar à contabilidade.

> 📸 **PRINT 17 — Processo automático de Férias (selo "Auto")**
> **Onde:** Hub Contábil → aba **Férias** (ou Painel).
> **O que precisa aparecer:** um card com o selo **Auto** e status **Pronto p/
> Envio**.
> **Dados fictícios na tela:** "Férias — Diego Freitas", competência **09/2026**,
> descrição com o período aquisitivo.

> 💡 A automação só dispara uma vez por pedido de férias — se o processo já
> existir, o sistema **não duplica**.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, mostrando dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Quantos e-mails vão e voltam entre o RH e a contabilidade todo mês? E quando um se perde?"* Abre com uma caixa de e-mail lotada. | Imagem genérica de caixa de entrada |
| 8–22s | *"O Hub Contábil transforma cada demanda em um processo rastreável, com documentos, checklist e conversa no mesmo lugar."* | **PRINT 01** (painel) + **PRINT 04** (detalhe/dossiê) |
| 22–38s | *"Cada tipo tem um prazo. O sistema avisa o que está vencendo antes de virar problema."* | **PRINT 12** (relatórios/SLA) + **PRINT 10** (kanban) |
| 38–52s | *"Aprovou as férias? O processo já nasce pronto na contabilidade, sozinho."* | **PRINT 17** (processo Auto) |
| 52–68s | *"Todo o histórico por colaborador, pronto para auditoria."* | **PRINT 11** (linha do tempo) |
| 68–82s | *"YourEyes. A ponte organizada entre o RH e a contabilidade."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 5–8 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("vamos abrir uma solicitação…", "agora eu anexo o documento…").

1. **Abertura** — o que o módulo faz e para quem (**PRINT 01**).
2. **Abrir uma nova solicitação** com busca de colaborador (**PRINT 02**).
3. **Localizar o processo** na aba de tipo e nos filtros (**PRINT 03**).
4. **Trabalhar o processo**: anexar documento (**PRINT 04, 05**), fechar o
   checklist (**PRINT 06**), conversar no chat (**PRINT 07**) e mostrar o
   histórico (**PRINT 08**).
5. **Mudar o status** pelo seletor e depois **pelo Kanban** arrastando
   (**PRINT 10**).
6. **Reabrir** um processo concluído, com motivo (**PRINT 09**).
7. **Linha do tempo por colaborador** (**PRINT 11**).
8. **Relatórios** e SLAs críticos (**PRINT 12**).
9. **Configurar** SLA, contabilidade, integrações e checklists
   (**PRINT 13, 14, 15, 16**).
10. **Mostrar um processo automático de Férias** e explicar a integração
    (**PRINT 17**).
11. **Encerramento** — reforçar que tudo fica rastreável e auditável.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Tela inicial (Painel)
- [ ] **PRINT 02** — Modal Nova Solicitação
- [ ] **PRINT 03** — Lista de processos por tipo (com filtros)
- [ ] **PRINT 04** — Detalhe do processo (aba Documentos)
- [ ] **PRINT 05** — Modal Anexar Documento
- [ ] **PRINT 06** — Aba Checklist (barra de progresso)
- [ ] **PRINT 07** — Aba Chat (comentário / pendência)
- [ ] **PRINT 08** — Aba Histórico
- [ ] **PRINT 09** — Reabrir processo
- [ ] **PRINT 10** — Kanban por status
- [ ] **PRINT 11** — Linha do tempo por colaborador
- [ ] **PRINT 12** — Relatórios gerenciais
- [ ] **PRINT 13** — Config.: SLA por tipo
- [ ] **PRINT 14** — Config.: Contabilidades Parceiras
- [ ] **PRINT 15** — Config.: Integrações Automáticas Ativas
- [ ] **PRINT 16** — Config.: Templates de Checklist
- [ ] **PRINT 17** — Processo automático de Férias (selo Auto)

---

## 9. Erros comuns / dúvidas frequentes

- **"Onde fica o Guia Rápido?"** Este módulo **não tem** guia embutido (diferente
  do Ponto). Use este manual como roteiro.
- **"O colaborador não aparece na busca do novo processo."** Confira se ele está
  **cadastrado** e vinculado à empresa ativa — o campo puxa direto do cadastro.
- **"Não consigo escolher a contabilidade ao criar o processo."** É preciso
  **cadastrar uma contabilidade parceira** antes, em **Config. → Contabilidades
  Parceiras** (Fluxo 8).
- **"Um processo apareceu sozinho, com o selo Auto."** Foi criado por integração
  (ex.: **férias aprovadas**). É esperado — confira e siga o fluxo normal.
- **"Não consigo editar/excluir um item do checklist."** Itens **globais** (ícone
  de globo) são padrão do sistema. Crie um item **customizado** para adaptar.
- **"O card ficou com a borda vermelha / diz SLA vencido."** O prazo daquele tipo
  de processo passou. Priorize-o; revise os prazos em **Config. → SLA por Tipo**
  se estiverem apertados demais.
- **"Preciso mexer num processo já concluído."** Use **Reabrir** e informe o
  motivo — ele volta para Rascunho e a reabertura fica registrada (Fluxo 4).

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/hub-contabil_ponte-com-a-contabilidade.md` no
   projeto.
2. Se quiser conferir cada print contra a tela real, acesse o **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/), faça login como **Marina
   Alves** (empresa **Empresa Staging LTDA**) e abra **Documentos & Governança →
   Hub Contábil**; percorra as abas Painel, Kanban, Colaboradores, Relatórios e
   Config. seguindo o checklist da seção 8.
3. Confira se o passo a passo, os benefícios e os marcadores de print refletem
   como você quer conduzir os vídeos. Aprovado o **formato/conteúdo**, replico o
   padrão para os próximos módulos.
