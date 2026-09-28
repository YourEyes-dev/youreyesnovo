# Manual do módulo — Prestadores de Serviços (Terceiros & SST)

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e na profundidade do piloto aprovado
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial e traz os marcadores de
> print com os dados fictícios a usar na captura.

- **Onde fica no menu:** seção **Estrutura Organizacional → Prestadores de
  Serviços** (rota `/terceiros`).
- **Para quem é:** RH, SST (Segurança e Saúde no Trabalho) e Gestores que
  contratam empresas terceirizadas e prestadores de serviço.
- **Em uma frase:** controla todo o ciclo de compliance de terceiros — cadastro
  da empresa, trabalhadores, documentos (PGR, PCMSO, ASO…), treinamentos de NR,
  permissões de trabalho e vencimentos — para comprovar a **diligência da empresa
  contratante** (corresponsável pela segurança do terceirizado, CLT art. 455).
- **Importante:** este módulo é dos **prestadores de serviço / terceirizados**.
  Colaboradores CLT da própria empresa não entram aqui — eles vivem em
  **Colaboradores** e no **Ponto**. Aqui entram as empresas contratadas e os
  profissionais delas.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Prova de diligência que protege a empresa contratante.** A empresa que
  contrata é **corresponsável** pela segurança do terceirizado (CLT art. 455).
  Em caso de acidente ou fiscalização, a documentação completa (contrato, PGR,
  ASO, treinamentos de NR, permissão de trabalho, ficha de EPI) é a principal
  prova de que a empresa cumpriu o seu dever — tudo reunido e rastreável em um
  só lugar.
- **Bloqueio automático de quem está irregular.** Se qualquer documento ou
  treinamento obrigatório do trabalhador vence, o **status muda sozinho para
  "bloqueado"**. O sistema não deixa passar despercebido um eletricista com
  NR-10 vencida.
- **Cadastro em segundos pelo CNPJ.** Ao informar o CNPJ, o sistema consulta a
  base pública da Receita Federal e preenche razão social, nome fantasia, CNAE e
  atividade principal automaticamente.
- **Fim da planilha de vencimentos.** Documentos e treinamentos com validade
  próxima ou vencida aparecem consolidados em uma única tela, com semáforo
  (vermelho, amarelo, verde) e dias restantes.
- **Permissão de Trabalho (PT) digital.** Para atividades de risco (altura,
  espaço confinado, trabalho a quente), a PT é emitida no sistema e só libera
  quem tem documentos, treinamentos e ASO em dia — o próprio sistema confere.
- **Integração do terceiro por link.** O trabalhador terceirizado pode fazer a
  trilha de integração pelo próprio celular, por um link, sem precisar de login.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Terceiro / Prestador** | A empresa contratada (Pessoa Jurídica) ou o profissional autônomo (Pessoa Física) que presta serviço para a sua empresa. |
| **Trabalhador** | Cada profissional do terceiro que efetivamente atua na sua empresa (o eletricista, o pintor, o soldador). |
| **Status do terceiro/trabalhador** | Semáforo de liberação: **Liberado** (verde), **Restrito** (amarelo) ou **Bloqueado** (vermelho). É recalculado sozinho pela documentação. |
| **Atividade de risco** | Trabalho em altura, espaço confinado, eletricidade, soldagem etc. Quando marcada, ativa controles e documentos obrigatórios. |
| **PGR** | Programa de Gerenciamento de Riscos — documento obrigatório da empresa (substituiu o antigo PPRA). |
| **PCMSO** | Programa de Controle Médico de Saúde Ocupacional — define os exames obrigatórios por função. |
| **LTCAT** | Laudo Técnico das Condições Ambientais de Trabalho — documenta agentes nocivos do ambiente. |
| **ASO** | Atestado de Saúde Ocupacional — atesta que o trabalhador está apto para a função. |
| **NR-10 / NR-33 / NR-35** | Normas de segurança: eletricidade (NR-10), espaço confinado (NR-33), trabalho em altura (NR-35). |
| **PT (Permissão de Trabalho)** | Autorização formal, emitida no sistema, para iniciar uma atividade de risco. |
| **Vencimento** | Data de validade de um documento ou treinamento. Perto de vencer, vira alerta; vencido, bloqueia. |
| **Trilha de integração** | Conteúdo de onboarding/SST que o terceiro faz por um link, se identificando por nome e CPF. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Estar logado como quem opera o RH/SST** — nos vídeos, a persona
   **Marina Alves** (Analista de RH).
2. **Ter uma empresa contratante ativa** — a demonstração usa **Empresa Staging
   LTDA**. É a empresa que contrata os terceiros.
3. **Ter em mãos os dados de pelo menos um terceiro** (CNPJ ou CPF) para
   cadastrar ao vivo. Para o auto-preenchimento pelo CNPJ funcionar, use um CNPJ
   fictício válido.

> 📸 **PRINT 01 — Estado inicial (opcional, só para o tutorial)**
> **Onde:** módulo Prestadores de Serviços → aba **Terceiros**, sem nenhum
> cadastro.
> **O que precisa aparecer:** o aviso **"Nenhum terceiro cadastrado"** com a
> instrução *"Clique em 'Novo Terceiro' para começar."*
> **Dados fictícios na tela:** nenhum (tela vazia).
> **Ação filmada:** só mostrar o ponto de partida. Pode ser pulado no comercial.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Prestadores de Serviços**, o topo mostra o título **"Gestão de
Terceiros & SST"**, a frase *"Compliance, controle documental e prova jurídica
de prestadores de serviço"* e três botões à direita: **Guia Rápido**,
**Importar** e **Novo Terceiro**.

Abaixo ficam as **4 abas** do módulo:

| Aba | Para que serve |
|---|---|
| **Dashboard** | Painel gerencial: indicadores de conformidade, trabalhadores por status, documentos a vencer/vencidos e rankings de risco. |
| **Terceiros** | A lista das empresas/prestadores cadastrados, com busca. É a porta de entrada para a ficha de cada terceiro. |
| **Permissões de Trabalho** | Emissão e controle das PTs digitais para atividades de risco. |
| **Vencimentos** | Visão consolidada de tudo que está vencido ou perto de vencer (próximos 60 dias). |

> 📸 **PRINT 02 — Tela inicial do módulo (Dashboard)**
> **Onde:** menu **Estrutura Organizacional → Prestadores de Serviços**, aba
> **Dashboard**.
> **O que precisa aparecer:** o título "Gestão de Terceiros & SST", os botões
> Guia Rápido / Importar / Novo Terceiro, as 4 abas e a grade de indicadores.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; indicadores como
> **8 Terceiros Ativos**, **88% Conformes**, **2 Com Restrição**, **1 Bloqueado**,
> **19 Trabalhadores**, **4 Docs a Vencer**, **1 Doc Vencido**, **3 Atividade de
> Risco**.
> **Ação filmada:** panorâmica lenta mostrando os cartões e as abas.

---

## 5. Passo a passo por fluxo

A ordem abaixo é a mesma do **Guia Rápido** embutido no sistema (botão **Guia
Rápido** no topo) — vale abri-lo no vídeo tutorial como reforço (ver Fluxo 10).

### Fluxo 1 — Cadastrar o terceiro (auto-preenchimento pelo CNPJ)

**Objetivo:** registrar a empresa (ou prestador autônomo) contratada.
**Benefício:** a base do compliance nasce completa e correta, em segundos.

1. Clique em **Novo Terceiro** no topo.
2. Escolha o **Tipo de Pessoa**: **Pessoa Jurídica (CNPJ)** ou **Pessoa Física
   (CPF)**.
3. Para PJ, digite o **CNPJ** e clique na **lupa** ao lado — o sistema busca na
   Receita Federal e preenche **razão social, nome fantasia, CNAE, atividade
   principal, e-mail e telefone**.
4. Complete o **responsável técnico e cargo**, os **tipos de serviço**
   (Manutenção, Elétrica, Obras…), as **unidades e setores** onde vai atuar e o
   **tipo de acesso** (**Eventual**, **Recorrente** ou **Contínuo**).
5. Informe o **período do contrato** e, se for o caso, ligue a chave **"Este
   terceiro executa atividade com risco?"**. Anexe o **contrato** e **salve**.

> 📸 **PRINT 03 — Modal "Novo Terceiro"**
> **Onde:** botão **Novo Terceiro** (topo).
> **O que precisa aparecer:** o seletor Tipo de Pessoa, o campo CNPJ com a lupa
> de busca, os campos preenchidos automaticamente, os tipos de serviço, o tipo
> de acesso e a chave de atividade de risco.
> **Dados fictícios na tela:** Pessoa Jurídica, CNPJ fictício
> **40.111.222/0001-05**, razão social **Manutec Serviços Elétricos LTDA**, nome
> fantasia **Manutec**, tipos de serviço **Elétrica** e **Manutenção**, acesso
> **Recorrente**, atividade de risco **ativada**.
> **Ação filmada:** digitar o CNPJ, clicar na lupa e mostrar os campos se
> preenchendo sozinhos; ligar a chave de atividade de risco; clicar em Cadastrar.

> 💡 O **CNAE** preenchido automaticamente ajuda a validar se o serviço
> contratado é compatível com o objeto social da empresa terceirizada. Para
> autônomos, troque para **Pessoa Física (CPF)** — o campo passa a pedir CPF.

---

### Fluxo 2 — Abrir a ficha e cadastrar os trabalhadores

**Objetivo:** registrar cada profissional do terceiro que vai atuar na empresa.
**Benefício:** o controle passa a ser individual — cada trabalhador tem o seu
próprio status, documentos e treinamentos.

1. Na aba **Terceiros**, use a **busca** (por razão social ou CNPJ) e **clique no
   cartão** do terceiro para abrir a ficha.
2. Na ficha, veja os **cartões de resumo** (Trabalhadores, Documentos, A Vencer,
   Vencidos) e o **selo de status** ao lado do nome.
3. Na aba **Trabalhadores**, clique em **Novo Trabalhador**.
4. Informe **nome, CPF, cargo, unidade e setor** e marque as **atividades de
   risco** (altura, confinado, eletricidade…).
5. **Cadastre.** O status do trabalhador será recalculado automaticamente
   conforme a documentação for anexada.

> 📸 **PRINT 04 — Lista de terceiros (aba Terceiros)**
> **Onde:** módulo Prestadores de Serviços → aba **Terceiros**.
> **O que precisa aparecer:** a barra de busca e os cartões dos terceiros com o
> selo de status (Liberado/Restrito/Bloqueado) e o selo **Risco** quando houver.
> **Dados fictícios na tela:**
> - **Manutec Serviços Elétricos LTDA** — **Liberado** — selo **Risco** — Acesso
>   Recorrente.
> - **Pinturas Horizonte LTDA** — **Restrito** — Acesso Eventual.
> - **Rui Barreto (autônomo)** — **Bloqueado**.
> **Ação filmada:** buscar "Manutec" e clicar no cartão para abrir a ficha.

> 📸 **PRINT 05 — Ficha do terceiro (resumo + abas)**
> **Onde:** ficha aberta de um terceiro.
> **O que precisa aparecer:** o nome com o CNPJ, o selo de status, o selo
> **Atividade de Risco**, os 4 cartões de resumo e as abas **Trabalhadores** e
> **Documentos da Empresa**.
> **Dados fictícios na tela:** **Manutec Serviços Elétricos LTDA**,
> **4 Trabalhadores**, **6 Documentos**, **2 A Vencer**, **0 Vencidos**.

> 📸 **PRINT 06 — Modal "Novo Trabalhador"**
> **Onde:** ficha do terceiro → aba **Trabalhadores → Novo Trabalhador**.
> **O que precisa aparecer:** os campos nome, CPF, cargo, unidade, setor e os
> selos de **Atividades de Risco**.
> **Dados fictícios na tela:** nome **Rafael Pontes**, CPF **900.000.010-66**,
> cargo **Eletricista**, atividades de risco **Eletricidade** e **Trabalho em
> Altura**.

> 💡 Marcar as atividades de risco não é enfeite: elas definem quais
> treinamentos e documentos passam a ser exigidos daquele trabalhador.

---

### Fluxo 3 — Enviar documentos (da empresa e de cada trabalhador)

**Objetivo:** anexar e controlar a validade da documentação de compliance.
**Benefício:** o sistema vigia as validades e bloqueia sozinho quem vence.

**Documentos da empresa (terceiro):**
1. Na ficha, abra a aba **Documentos da Empresa** e clique em **Upload
   Documento**.
2. Escolha o **tipo** (PGR, PCMSO, LTCAT, Contrato, Certificado/Registro Legal,
   Seguro…), arraste o arquivo e informe **data de emissão e validade**.

**Documentos do trabalhador:**
3. Na aba **Trabalhadores**, **expanda** o card do trabalhador e clique em **Doc**.
4. Escolha o tipo (ASO, Certificado NR-10/12/18/33/35, Ficha de EPI…), anexe e
   informe as datas.

> 📸 **PRINT 07 — Card do trabalhador expandido (documentos e treinamentos)**
> **Onde:** ficha do terceiro → aba **Trabalhadores**, card do trabalhador
> aberto.
> **O que precisa aparecer:** os selos de atividade de risco, a tabela de
> **Documentos** e a de **Treinamentos**, cada linha com o **status** (válido /
> a vencer / vencido) e os botões **Doc** e **Treinamento**.
> **Dados fictícios na tela:** **Rafael Pontes** — status **Liberado**; documento
> **ASO** válido até **12/2026**; **Ficha de EPI** válida.
> **Ação filmada:** expandir o card e apontar os selos de status.

> 📸 **PRINT 08 — Modal "Upload de Documento"**
> **Onde:** botão **Upload Documento** (empresa) ou **Doc** (trabalhador).
> **O que precisa aparecer:** o seletor de tipo, a área de arrastar-e-soltar
> (PDF/DOC/DOCX/JPG/PNG) e os campos de data de emissão e validade.
> **Dados fictícios na tela:** tipo **PGR**, nome **PGR 2026**, emissão
> **01/2026**, validade **01/2027**.

> 💡 Documentos e treinamentos ganham status **A vencer** 30 dias antes da
> validade e **Vencido** na data — e documento/treinamento obrigatório vencido
> **bloqueia o trabalhador** automaticamente. Um documento **sem validade**
> informada fica como **Pendente**.

---

### Fluxo 4 — Registrar treinamentos (e conectar a uma trilha)

**Objetivo:** comprovar a capacitação técnica de cada trabalhador.
**Benefício:** habilitação vencida não passa — o status reflete a realidade.

1. No card do trabalhador expandido, clique em **Treinamento**.
2. Escolha o **tipo** (NR-10, NR-12, NR-18, NR-33, NR-35, NR-06 (EPI),
   Integração SST…).
3. Informe **data de realização, carga horária e validade**, e faça **upload do
   certificado**.
4. Se quiser, use **Conectar a uma Trilha** para vincular o treinamento a uma
   trilha de integração/capacitação já existente.
5. **Registre.**

> 📸 **PRINT 09 — Modal "Registrar Treinamento"**
> **Onde:** card do trabalhador → **Treinamento**.
> **O que precisa aparecer:** o seletor de tipo, os campos data/carga
> horária/validade, o seletor **Conectar a uma Trilha** e o anexo do certificado.
> **Dados fictícios na tela:** trabalhador **Rafael Pontes**, tipo **NR-10**,
> carga horária **40h**, validade **09/2028**, trilha **Integração de Terceiros —
> SST**.

> 💡 Um eletricista com **NR-10 vencida** é bloqueado automaticamente até a
> regularização. Exija certificados com a carga horária mínima exigida pela norma.

---

### Fluxo 5 — Emitir Permissão de Trabalho (PT)

**Objetivo:** autorizar formalmente uma atividade de risco.
**Benefício:** o sistema só libera quem tem documentos, treinamentos e ASO em
dia — a checagem de aptidão é automática.

1. Abra a aba **Permissões de Trabalho** e clique em **Nova PT**.
2. **Selecione o terceiro** responsável pela atividade.
3. Preencha **data de início e fim, local e atividade**, marque as **atividades
   de risco** e descreva as medidas de segurança.
4. Em **Trabalhadores Envolvidos**, marque quem vai executar — o sistema valida
   **Docs**, **Treinamentos** e **ASO** de cada um e mostra se está **apto**.
5. **Crie a PT.** Acompanhe o status na lista (Rascunho, Liberada, Bloqueada,
   Encerrada, Cancelada) e use **Encerrar** ao fim da atividade.

> 📸 **PRINT 10 — Modal "Nova Permissão de Trabalho"**
> **Onde:** aba **Permissões de Trabalho → Nova PT** (após escolher o terceiro).
> **O que precisa aparecer:** os campos data início/fim, local, atividade, os
> selos de atividades de risco e a lista de **Trabalhadores Envolvidos** com o
> status de cada um.
> **Dados fictícios na tela:** terceiro **Manutec Serviços Elétricos LTDA**,
> atividade **Manutenção elétrica preventiva**, local **Galpão 3**, risco
> **Eletricidade**; trabalhador **Rafael Pontes (Liberado)** marcado.
> **Ação filmada:** marcar o Rafael e clicar em **Criar PT**.

> 📸 **PRINT 11 — Painel de Permissões de Trabalho (linha expandida)**
> **Onde:** aba **Permissões de Trabalho**.
> **O que precisa aparecer:** os cartões de resumo (PTs Ativas / Liberadas /
> Bloqueadas), a tabela com código, terceiro, atividade, local, período e status,
> e uma **linha expandida** mostrando os trabalhadores com os selos **Docs ✓ /
> Trein ✓ / ASO ✓** e o resultado **apto**.
> **Dados fictícios na tela:** **1 PT Liberada**, código **PT-0007**, Manutec,
> Rafael Pontes com **Docs ✓ Trein ✓ ASO ✓** e ícone verde de apto.

> 💡 A PT é obrigatória para trabalho em altura (NR-35), espaço confinado (NR-33)
> e trabalho a quente. Se um trabalhador estiver com pendência, ele aparece como
> **não apto** (fundo vermelho) — não libere a atividade.

---

### Fluxo 6 — Monitorar vencimentos

**Objetivo:** agir antes de qualquer documento ou treinamento vencer.
**Benefício:** nenhuma surpresa em auditoria; renovação pedida com antecedência.

1. Abra a aba **Vencimentos**.
2. Veja os três cartões: **Vencidos**, **Vence em até 30 dias** e **Vence em
   31–60 dias**.
3. Na tabela, cada item mostra **tipo, terceiro, trabalhador (ou "Empresa"),
   validade, dias restantes e urgência**.
4. Priorize os **Vencidos** (vermelho) e **Urgentes** (amarelo) e cobre a
   renovação do terceiro.

> 📸 **PRINT 12 — Aba Vencimentos**
> **Onde:** módulo Prestadores de Serviços → aba **Vencimentos**.
> **O que precisa aparecer:** os três cartões de resumo e a tabela com o
> semáforo de urgência.
> **Dados fictícios na tela:** **1 Vencido**, **3 Vence em até 30 dias**, **2
> Vence em 31–60 dias**; linha **ASO — Pinturas Horizonte — João Vidal —
> 05/10/2026 — 7d — Urgente**.

> 💡 A tela lista o que vence nos próximos **60 dias** (e o que já venceu).
> Estabeleça uma rotina semanal de verificação — é o que evita bloqueios de
> última hora no dia do serviço.

---

### Fluxo 7 — Ler o Dashboard de compliance

**Objetivo:** ter a visão gerencial para reuniões e auditorias.
**Benefício:** a taxa de conformidade e os focos de risco em uma tela só.

1. Abra a aba **Dashboard**.
2. Leia os **8 indicadores** do topo (terceiros ativos, % conformes, restritos,
   bloqueados, trabalhadores, docs a vencer, docs vencidos, atividade de risco).
3. Use os painéis de baixo: **Atividades de Maior Risco** e **Terceiros Mais
   Recorrentes** (por número de trabalhadores).

> 📸 **PRINT 13 — Dashboard: rankings de risco e recorrência**
> **Onde:** aba **Dashboard**, parte de baixo.
> **O que precisa aparecer:** os dois painéis **Atividades de Maior Risco** e
> **Terceiros Mais Recorrentes**.
> **Dados fictícios na tela:** maior risco **Eletricidade (5 trab.)**, **Trabalho
> em Altura (3 trab.)**; mais recorrente **Manutec Serviços Elétricos LTDA (4
> trab.)**.

> 💡 Mantenha a conformidade acima de **95%**. Terceiros abaixo de **80%** devem
> ser notificados formalmente antes de qualquer nova atividade.

---

### Fluxo 8 — Importar terceiros em massa (planilha)

**Objetivo:** cadastrar muitos prestadores de uma vez.
**Benefício:** migração rápida de uma base existente, com relatório de erros.

1. Clique em **Importar** no topo.
2. Clique em **Baixar Modelo Excel**, preencha (obrigatórios: **razao_social** e
   **cnpj**) e salve.
3. **Suba o arquivo** (.xlsx, .xls ou .csv).
4. Veja o resultado: quantos foram importados e quais linhas deram erro — com
   **Baixar Relatório** dos erros.

> 📸 **PRINT 14 — Modal "Importar Prestadores de Serviço"**
> **Onde:** botão **Importar** (topo).
> **O que precisa aparecer:** o botão Baixar Modelo Excel, a área de upload e o
> aviso de campos obrigatórios (razao_social, cnpj, tipo_acesso, atividade_risco).
> **Dados fictícios na tela:** tela inicial do modal, sem arquivo enviado ainda.

> 📸 **PRINT 15 — Resultado da importação**
> **Onde:** modal Importar, após enviar a planilha.
> **O que precisa aparecer:** os cartões de **Importados com sucesso** e **Linhas
> com erro** e a lista de erros com o botão Baixar Relatório.
> **Dados fictícios na tela:** **5 importados com sucesso**, **1 linha com erro**
> (Linha 4 — "CNPJ já cadastrado no sistema").

> 💡 No modelo, **tipo_acesso** aceita `eventual`, `recorrente` ou `continuo`
> (sem acento) e **atividade_risco** aceita `sim` ou `nao`. O CNPJ é único no
> sistema — duplicados caem no relatório de erros.

---

### Fluxo 9 — Trilha de integração do terceiro (pelo link)

**Objetivo:** o trabalhador terceirizado faz a integração/SST pelo celular.
**Benefício:** onboarding padronizado, com registro de conclusão por CPF, sem
precisar dar login ao terceiro.

1. A trilha de integração é montada no módulo **Trilhas** (marcada como pública
   para terceiros) e conectada a treinamentos aqui no cadastro (ver **Fluxo 4**).
2. O terceiro recebe o **link** e abre no navegador do celular.
3. Ele **se identifica** com **nome e CPF** (empresa é opcional) e inicia.
4. Ele percorre os **módulos** (vídeo, PDF, texto, atividade), registra evidência
   quando pedido e acompanha o **progresso e a pontuação**; ao final, aparece a
   mensagem de trilha concluída.

> 📸 **PRINT 16 — Trilha do terceiro: identificação (celular)**
> **Onde:** o link da trilha pública aberto no navegador (`.../trilha-terceiro/
> ‹código›`).
> **O que precisa aparecer:** o nome da trilha, o número de módulos e o formulário
> de identificação (nome, CPF, empresa) com o botão **Iniciar Trilha**.
> **Dados fictícios na tela:** trilha **Integração de Terceiros — SST**, **5
> módulos**; nome **Rafael Pontes**, CPF **900.000.010-66**, empresa **Manutec**.
> **Ação filmada:** ótimo momento para gravar a tela real de um celular.

> 📸 **PRINT 17 — Trilha do terceiro: módulos e progresso**
> **Onde:** a mesma trilha, já identificado.
> **O que precisa aparecer:** a barra de progresso, a lista de módulos com os
> ícones de status (concluído/andamento) e a pontuação.
> **Dados fictícios na tela:** progresso **40%**, **2/5 módulos**, **20/50 pts**,
> módulo atual **"Regras de segurança na obra"**.

> 💡 A conclusão fica registrada pelo **CPF** do trabalhador — serve de prova de
> que a integração de SST foi feita antes do início do serviço.

---

### Fluxo 10 — Guia Rápido embutido e Manual em PDF

**Objetivo:** ter a ajuda passo a passo dentro do próprio sistema.
**Benefício:** onboarding do operador sem sair da tela; material offline.

1. Clique em **Guia Rápido** no topo.
2. Percorra os **passos** (visão geral, cadastro, trabalhadores, documentos,
   treinamentos, permissões, vencimentos, dashboard, recursos).
3. No último passo, clique em **Baixar Manual do Módulo (PDF)** para o guia
   offline.

> 📸 **PRINT 18 — Guia Rápido embutido**
> **Onde:** botão **Guia Rápido** (topo).
> **O que precisa aparecer:** o painel do guia com a lista de passos na lateral,
> o conteúdo do passo atual, o quadro de **Dica** e, no último passo, o botão
> **Baixar Manual do Módulo (PDF)**.
> **Dados fictícios na tela:** passo **"O que é esse módulo?"** aberto.
> **Ação filmada:** avançar 2–3 passos e mostrar o botão de baixar o PDF no fim.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Contratou um terceiro. E a documentação dele? Se der acidente, a conta é sua."* Abre com pasta de papéis bagunçada. | Imagem genérica de papelada |
| 8–22s | *"O YourEyes cadastra o prestador em segundos, só pelo CNPJ, e controla cada trabalhador."* | **PRINT 03** (cadastro) + **PRINT 05** (ficha) |
| 22–38s | *"Documento ou treinamento vencido? O sistema bloqueia sozinho e avisa antes."* | **PRINT 07** (status) + **PRINT 12** (vencimentos) |
| 38–52s | *"Atividade de risco só começa com Permissão de Trabalho — e só quem está em dia é liberado."* | **PRINT 11** (PT apto/bloqueado) |
| 52–66s | *"O terceiro faz a integração pelo próprio celular, com registro por CPF."* | **PRINT 16** (trilha no celular) |
| 66–80s | *"Tudo em um painel, pronto para a auditoria. YourEyes. Sua diligência, comprovada."* Logo. | **PRINT 02 / 13** (dashboard) |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 6–9 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("vamos cadastrar…", "agora eu envio o documento…").

1. **Abertura** — o que o módulo faz e para quem (**PRINT 02**).
2. **Cadastrar um terceiro** com auto-preenchimento pelo CNPJ (**PRINT 03**).
3. **Abrir a ficha** e **cadastrar um trabalhador** (**PRINT 04, 05, 06**).
4. **Enviar documentos** da empresa e do trabalhador (**PRINT 07, 08**).
5. **Registrar um treinamento** e conectar a uma trilha (**PRINT 09**).
6. **Emitir uma Permissão de Trabalho** e mostrar a checagem de aptidão
   (**PRINT 10, 11**).
7. **Monitorar vencimentos** (**PRINT 12**).
8. **Ler o Dashboard** de compliance (**PRINT 13**).
9. **Importar terceiros** por planilha (**PRINT 14, 15**).
10. **Mostrar a trilha de integração** no celular (**PRINT 16, 17**).
11. **Encerramento** — abrir o **Guia Rápido** e baixar o **Manual em PDF**
    (**PRINT 18**).

> 💡 Dica de gravação: abra o **Guia Rápido** (botão no topo) e siga os passos
> dele — este roteiro foi montado na mesma sequência.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Estado inicial / lista vazia (opcional, só tutorial)
- [ ] **PRINT 02** — Tela inicial / Dashboard
- [ ] **PRINT 03** — Modal Novo Terceiro (auto-CNPJ)
- [ ] **PRINT 04** — Lista de terceiros (busca + status)
- [ ] **PRINT 05** — Ficha do terceiro (resumo + abas)
- [ ] **PRINT 06** — Modal Novo Trabalhador
- [ ] **PRINT 07** — Card do trabalhador expandido (docs + treinamentos)
- [ ] **PRINT 08** — Modal Upload de Documento
- [ ] **PRINT 09** — Modal Registrar Treinamento (conectar a trilha)
- [ ] **PRINT 10** — Modal Nova Permissão de Trabalho
- [ ] **PRINT 11** — Painel de PTs (linha expandida, apto/bloqueado)
- [ ] **PRINT 12** — Aba Vencimentos
- [ ] **PRINT 13** — Dashboard: rankings de risco e recorrência
- [ ] **PRINT 14** — Modal Importar (baixar modelo + upload)
- [ ] **PRINT 15** — Resultado da importação
- [ ] **PRINT 16** — Trilha do terceiro: identificação (celular)
- [ ] **PRINT 17** — Trilha do terceiro: módulos e progresso
- [ ] **PRINT 18** — Guia Rápido embutido

---

## 9. Erros comuns / dúvidas frequentes

- **"O CNPJ não preencheu sozinho."** A busca depende da base pública da Receita
  Federal. Confira se o CNPJ tem 14 dígitos e é válido; para autônomo, troque
  para **Pessoa Física (CPF)** — aí não há busca automática.
- **"O trabalhador está bloqueado e não sei por quê."** Algum documento ou
  treinamento obrigatório venceu. Expanda o card dele e procure os selos
  **vencido** (vermelho); a aba **Vencimentos** também mostra o item.
- **"A Permissão de Trabalho não libera o trabalhador."** No modal da PT ele
  aparece como **não apto** (fundo vermelho) porque **Docs**, **Trein** ou
  **ASO** estão com pendência. Regularize e refaça a checagem.
- **"Um documento ficou como Pendente."** Ele foi cadastrado **sem data de
  validade**. Informe a validade para o sistema passar a controlar o vencimento.
- **"A importação recusou linhas."** Verifique **razao_social** e **cnpj**
  (obrigatórios), o CNPJ único e os valores de **tipo_acesso**/**atividade_risco**.
  Baixe o **relatório de erros** para ver a linha e o motivo.
- **"Não acho a trilha de integração aqui."** A trilha em si é criada no módulo
  **Trilhas** (marcada como pública para terceiros). Aqui você a **conecta** a um
  treinamento (Fluxo 4); o terceiro a acessa pelo **link**, sem login.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/terceiros_prestadores-de-servicos.md` no projeto.
2. Se quiser conferir cada print contra a tela real, entre no **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/) como **Marina Alves**,
   empresa **Empresa Staging LTDA**, e abra **Estrutura Organizacional →
   Prestadores de Serviços**; percorra as abas Dashboard, Terceiros, Permissões
   de Trabalho e Vencimentos e o botão **Guia Rápido**.
3. Aprovado o **formato**, replico o mesmo padrão para os próximos módulos, nos
   lotes que você priorizar.
