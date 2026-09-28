# Manual do módulo — Gestão de EPIs

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e na mesma profundidade do piloto aprovado
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial e traz os marcadores de
> print para captura no ambiente de teste.

- **Onde fica no menu:** seção **Saúde & Segurança → EPIs** (rota `/epis`).
- **Para quem é:** RH, SST (Segurança e Saúde no Trabalho) e Gestores.
- **Em uma frase:** controla todo o ciclo de vida dos Equipamentos de Proteção
  Individual — cadastro, estoque, entrega com **ficha assinada digitalmente**,
  devolução, alertas de CA/validade e auditoria — em conformidade com a
  **NR-06** e com a **Lei 14.063/2020** (assinatura eletrônica).
- **Importante:** a entrega de EPI depende de **colaboradores com admissão
  concluída** e de **tipos de EPI cadastrados**. Sem isso, o assistente de
  entrega avisa e não deixa prosseguir (é proposital — evita ficha sem lastro).

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Fim da ficha de EPI em papel.** A entrega é registrada com **verificação de
  presença** (a pessoa pisca e vira o rosto na câmera), **foto** e **assinatura
  digital na tela**. O recibo em PDF é gerado na hora e **arquivado sozinho** na
  pasta do colaborador (módulo Documentos), com validade jurídica pela Lei
  14.063/2020.
- **Nada de entregar EPI irregular.** Se o **CA (Certificado de Aprovação)
  estiver vencido**, ou se o EPI **não tiver CA cadastrado**, o sistema
  **bloqueia a entrega** — como manda a NR-06. O erro não chega ao chão de
  fábrica.
- **Estoque que não deixa faltar.** Cada entrada, saída, transferência e entrega
  movimenta o saldo automaticamente. Quando um item fica **abaixo do mínimo** ou
  **zera**, vira alerta antes de faltar EPI para quem precisa.
- **Alertas antes do problema.** CA vencendo, EPI perto da validade, colaborador
  usando equipamento vencido, troca periódica atrasada — tudo é sinalizado por
  nível (**Crítico / Urgente / Atenção**) e pode virar um **Plano de Ação**.
- **Prova de conformidade por função.** A **Matriz de Proteção** diz quais EPIs
  cada cargo precisa (NR-06 / PGR) e cruza com o que foi entregue, mostrando
  quem está **conforme** e quem tem **lacuna**.
- **Auditoria com IA.** Um clique gera um relatório que aponta padrões suspeitos
  (extravios em excesso, consumo anormal), CAs vencidos e riscos jurídicos —
  pronto para exportar em PDF antes de uma fiscalização.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **EPI** | Equipamento de Proteção Individual — capacete, luva, bota, óculos, protetor auricular etc. |
| **CA** | Certificado de Aprovação — número emitido pelo Ministério do Trabalho que valida o EPI para uso legal. Tem data de validade. |
| **Categoria** | O agrupamento do EPI (ex.: Proteção da Cabeça, Proteção das Mãos). Define, entre outras coisas, se aquele item **exige CA**. |
| **Tipo de EPI** | O modelo cadastrado (ex.: "Protetor Auricular 3M"), com CA, marca, validade e periodicidade de troca. |
| **Ficha de EPI** | O comprovante de entrega assinado pelo colaborador. Aqui é **digital** (recibo em PDF). |
| **Entrega** | O evento central: dar um EPI a um colaborador, com verificação, foto e assinatura. Baixa o estoque. |
| **Devolução** | Registro de retorno do EPI, com destino **Estoque**, **Manutenção** ou **Descarte**. |
| **Verificação de presença (liveness)** | Prova, pela câmera, que é uma pessoa real assinando (pisca / vira a cabeça), não uma foto. |
| **Local de estoque** | Onde o EPI fica guardado (almoxarifado central, estoque de obra, filial). |
| **Matriz de Proteção** | A regra "cada função precisa destes EPIs", exigida pela NR-06 e pelo PGR. |
| **Estoque mínimo** | O nível abaixo do qual o item vira alerta de reposição. |
| **Periodicidade de troca** | De quantos em quantos dias aquele EPI deve ser substituído. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Colaboradores com admissão concluída** — a entrega busca a pessoa pelo nome
   ou CPF; sem admissões concluídas, o assistente avisa "Nenhum colaborador
   cadastrado".
2. **Pelo menos um tipo de EPI cadastrado** (com CA, quando a categoria exigir).
3. **Locais de estoque criados** — obrigatório quando o **controle de estoque**
   estiver ligado (ver Fluxo 1). Sem local, a entrega não tem de onde baixar.
4. **Câmera liberada no navegador** — a entrega usa a câmera para a verificação
   de presença e a foto. Grave num dispositivo com webcam.

> 💡 O módulo tem um **Guia Rápido** embutido (botão no topo) com 10 passos e um
> **Manual em PDF** para download na última etapa. Vale abri-lo no vídeo tutorial
> como reforço — o roteiro deste manual segue a mesma ordem.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **EPIs**, o topo mostra o título **"Gestão de EPIs"** (com o capacete),
o subtítulo "Controle de equipamentos de proteção individual" e os botões de
ação: **Guia Rápido**, **Categoria**, **Novo EPI** e **Entrega** (os botões
aparecem conforme a permissão do usuário).

Logo abaixo ficam **6 cartões de indicadores clicáveis** (cada um leva à aba
correspondente): **Total de EPIs**, **Itens em Estoque**, **Entregas Ativas**,
**Estoque Baixo**, **EPIs Vencidos** e **Tipos Cadastrados**.

Depois, as abas do módulo (algumas dependem de permissão):

| Aba | Para que serve |
|---|---|
| **Entregas** | Lista de entregas e o registro de **devolução**. É a aba que abre por padrão. |
| **Estoque** | Os EPIs cadastrados, com CA, validade, saldo e status. |
| **Local** | Dashboard do saldo por local (almoxarifado, obra, filial). |
| **Mov.** | Entradas, saídas, transferências e importação de nota fiscal. |
| **Alertas** | CA vencido, validade, estoque baixo, troca atrasada — por nível. |
| **Matriz** | EPIs obrigatórios por função e a conformidade de cada colaborador. |
| **Auditoria** | Relatório de padrões e riscos gerado por IA. |
| **Histórico** | Todas as movimentações (entrada, saída, ajuste, descarte). |
| **Config** | Controle de estoque, exigência de CA por categoria e locais. |

> 📸 **PRINT 01 — Tela inicial do módulo**
> **Onde:** menu **Saúde & Segurança → EPIs**, aba **Entregas** (padrão).
> **O que precisa aparecer:** título "Gestão de EPIs", os botões do topo, os 6
> cartões de indicadores e a fileira de abas.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; cartões como
> "Total de EPIs 8", "Itens em Estoque 640", "Entregas Ativas 5", "Estoque Baixo
> 2", "EPIs Vencidos 1", "Tipos Cadastrados 8".
> **Ação filmada:** panorâmica lenta mostrando os cartões e as abas.

> 📸 **PRINT 02 — Guia Rápido embutido**
> **Onde:** botão **Guia Rápido** no topo.
> **O que precisa aparecer:** a janela "Guia do Módulo de EPIs" com a barra de
> passos à esquerda (O que é, Passo 1 a 8, Documentos) e o conteúdo do passo
> atual.
> **Ação filmada:** abrir o guia e passar por 2 ou 3 passos com "Próximo".

---

## 5. Passo a passo por fluxo

### Fluxo 1 — Configurar o módulo

**Objetivo:** definir como o EPI vai funcionar na empresa antes de operar.
**Benefício:** o sistema passa a exigir (ou dispensar) CA e saldo do jeito certo
para cada tipo de item, sem travar uniformes nem liberar EPI irregular.

1. Abra a aba **Config**.
2. Em **Configuração Geral do Módulo**, decida **"Usar controle de estoque de
   EPI?"**:
   - **Ativado:** cada entrega baixa o saldo; é preciso manter estoque por
     compras/movimentações e os alertas de estoque ficam ligados.
   - **Desativado:** a entrega continua (registro + ficha + verificação facial),
     mas **sem exigir saldo** e sem os dashboards de estoque — ideal para quem
     está começando.
3. Em **Exigência de CA por Categoria**, deixe **ligado** para o que é EPI de
   verdade (capacete, luva, bota) e **desligue** para o que não tem CA (uniforme,
   crachá) — assim esses itens entram sem número e sem validade.
4. Em **Locais de Estoque**, clique em **Novo Local** e cadastre almoxarifados,
   estoques de obra e filiais (nome, tipo, estabelecimento e responsável).

> 📸 **PRINT 03 — Config: controle de estoque e CA por categoria**
> **Onde:** EPIs → **Config**.
> **O que precisa aparecer:** o cartão "Usar controle de estoque de EPI?" com o
> interruptor e, abaixo, "Exigência de CA por Categoria" com a lista de
> categorias e seus interruptores.
> **Dados fictícios na tela:** controle de estoque **Ativado**; "Proteção da
> Cabeça" e "Proteção das Mãos" exigindo CA; "Sinalização e Visibilidade" (colete)
> marcada como isenta.

> 📸 **PRINT 04 — Config: locais de estoque**
> **Onde:** EPIs → **Config → Locais de Estoque**.
> **O que precisa aparecer:** a tabela de locais e o formulário "Novo Local de
> Estoque" aberto.
> **Dados fictícios na tela:** local **"Almoxarifado Central"** (Matriz),
> responsável **Marina Alves**; um segundo local **"Estoque Obra Norte"**.

> 💡 Com o controle de estoque **desativado**, você ainda registra entregas e
> gera a ficha assinada — só não controla saldo. Dá para começar simples e ligar
> o estoque depois.

---

### Fluxo 2 — Cadastrar categorias

**Objetivo:** organizar os EPIs em grupos.
**Benefício:** a categoria define a exigência de CA (Fluxo 1) e facilita a busca
no estoque e nos filtros.

1. Clique em **Categoria** no topo.
2. O sistema já traz as categorias padrão (Proteção da Cabeça, Auditiva,
   Respiratória, Visual, Facial, das Mãos, dos Pés, contra Quedas, do Tronco,
   Sinalização e Visibilidade, Outros).
3. Para criar uma nova, digite o nome em **Nova Categoria** e clique em
   **Adicionar**.

> 📸 **PRINT 05 — Gerenciar categorias**
> **Onde:** botão **Categoria** (topo).
> **O que precisa aparecer:** o campo "Nova Categoria" e a lista de categorias
> cadastradas com o contador.
> **Dados fictícios na tela:** categoria nova sendo digitada, ex.: **"Proteção
> Térmica"**; contador "Categorias cadastradas (12)".

---

### Fluxo 3 — Cadastrar um tipo de EPI

**Objetivo:** registrar o modelo de EPI que a empresa usa.
**Benefício:** só o que está cadastrado (com CA válido, quando exigido) pode ser
entregue — a base de toda a conformidade.

1. Clique em **Novo EPI** no topo.
2. Escolha a **Categoria** e informe o **Nome do EPI** (ex.: "Protetor Auricular
   3M").
3. Preencha **CA** e **Data de Validade** — obrigatórios quando a categoria exige
   (NR-06). O sistema **avisa se o CA já estiver cadastrado** em outro item.
4. Complete marca, modelo, fabricante, unidade de medida, tipo de durabilidade e
   a **periodicidade de troca (dias)**.
5. Informe **Quantidade em Estoque**, **Quantidade Mínima (alerta)** e, se for o
   caso, o **local** e o custo unitário.
6. Se o item tem numeração (calçado, luva), ligue **Controlar por Tamanho** e
   monte a **grade** (tamanho × local × quantidade).
7. Clique em **Cadastrar**.

> 📸 **PRINT 06 — Cadastro de novo EPI**
> **Onde:** botão **Novo EPI** (topo).
> **O que precisa aparecer:** o formulário com Categoria, Nome, CA, Validade,
> marca/modelo, quantidade, quantidade mínima e a chave "Controlar por Tamanho".
> **Dados fictícios na tela:** categoria **Proteção das Mãos**, nome **"Luva de
> Segurança Nitrílica"**, CA **12345**, validade **31/12/2027**, fabricante
> **3M do Brasil**, quantidade **200**, mínima **20**.

> 💡 Cadastrou um uniforme e o sistema exigiu CA? Marque a categoria como isenta
> em **Config → Exigência de CA por Categoria** (Fluxo 1) — aí ela passa a
> aceitar item sem número e sem validade.

---

### Fluxo 4 — Registrar entrada no estoque

**Objetivo:** creditar EPIs recebidos no local certo.
**Benefício:** o saldo por local fica correto e rastreável, com fornecedor e
motivo — a base para o controle não deixar faltar.

1. Abra a aba **Mov.**
2. Escolha a operação:
   - **Nova Entrada** — inventário inicial, ajuste, doação ou compra sem nota.
   - **Importar NF** — lançar a partir de uma nota fiscal.
   - **Saída** — baixa manual (descarte, perda, dano, vencimento).
   - **Transferir** — mover saldo de um local para outro.
3. Na **Nova Entrada**, informe o EPI, a **quantidade recebida**, o **local de
   destino** e o motivo/fornecedor.
4. O saldo é creditado automaticamente e a operação aparece na lista de entradas.

> 📸 **PRINT 07 — Aba Estoque (lista de EPIs)**
> **Onde:** EPIs → **Estoque**.
> **O que precisa aparecer:** a busca "por nome, categoria, CA, marca ou modelo"
> e a tabela com Categoria, Nome, CA, Marca/Modelo, Tamanho, Estoque, Validade e
> Status.
> **Dados fictícios na tela:** linhas de **Capacete de Segurança**, **Luva de
> Segurança Nitrílica (CA 12345)**, **Protetor Auricular** com estoque baixo em
> laranja.

> 📸 **PRINT 08 — Movimentar: nova entrada de estoque**
> **Onde:** EPIs → **Mov. → Nova Entrada**.
> **O que precisa aparecer:** os cartões de subtipo (Inventário Inicial, Ajuste,
> Doação, Compra), o formulário de entrada e a tabela de entradas abaixo.
> **Dados fictícios na tela:** entrada de **100** un. de **Luva de Segurança
> Nitrílica**, local **Almoxarifado Central**, tipo **Compra**, responsável
> **Marina Alves**.

---

### Fluxo 5 — Registrar a entrega ao colaborador (o coração do módulo)

**Objetivo:** entregar o EPI com ficha assinada e à prova de contestação.
**Benefício:** a entrega nasce auditável — presença verificada, foto, assinatura
com validade legal e recibo arquivado sozinho na pasta do colaborador.

O assistente tem **5 passos** (Formulário → Verificação → Foto → Assinatura →
Concluído).

**Passo A — Formulário**
1. Clique em **Entrega** no topo.
2. Busque o **colaborador** por nome ou CPF. Aparecem os dados dele e, se a
   função tiver Matriz configurada, as **sugestões de EPI** para o cargo (clique
   numa sugestão para preencher o tipo).
3. Escolha o **Tipo de EPI**, o **Local de Estoque** (quando o controle está
   ligado), o **tamanho** (se o item tiver grade), a **quantidade** e as datas.
4. Clique em **Próximo**.

O sistema **bloqueia o avanço** se: o **CA estiver vencido**, o **EPI não tiver
CA**, ou o **saldo for insuficiente**. Se o colaborador já tem uma entrega ativa
do mesmo tipo, aparece o aviso de **substituição** (a anterior será marcada como
devolvida ao confirmar). Há também o botão **Colaborador Recusou**, que registra
a recusa como advertência.

**Passo B — Verificação de presença**
5. Libere a câmera. O sistema pede **3 ações aleatórias** (piscar, virar à
   esquerda, virar à direita). A cada ação, clique em **Ação Realizada**.

**Passo C — Foto**
6. Capture a **foto** do colaborador recebendo o EPI.

**Passo D — Assinatura**
7. O colaborador **assina na tela** (dedo ou mouse) e confirma. A tela lembra a
   validade jurídica pela **Lei 14.063/2020**.

**Passo E — Concluído**
8. O **recibo** é exibido; baixe o **PDF** se quiser. Ele é **arquivado
   automaticamente** na pasta do colaborador (módulo Documentos).

> 📸 **PRINT 09 — Entrega: passo 1 (formulário)**
> **Onde:** botão **Entrega** → passo **Formulário**.
> **O que precisa aparecer:** a barra de progresso (Formulário/Verificação/Foto/
> Assinatura/Concluído), a busca de colaborador, os dados dele, as sugestões da
> Matriz, o seletor de EPI, o local e a quantidade.
> **Dados fictícios na tela:** colaborador **Camila Duarte** (900.000.003-37),
> cargo **Operadora de Produção**; EPI **Luva de Segurança Nitrílica (CA 12345)**;
> local **Almoxarifado Central**; quantidade **1**; nota "Saldo em estoque: 300".
> **Ação filmada:** buscar a Camila, escolher a luva, clicar em Próximo.

> 📸 **PRINT 10 — Entrega bloqueada por CA vencido**
> **Onde:** passo Formulário, ao escolher um EPI com CA vencido.
> **O que precisa aparecer:** o alerta vermelho **"CA Vencido — Entrega
> Bloqueada"** e o botão Próximo desabilitado.
> **Dados fictícios na tela:** EPI com CA vencido em **30/06/2026**, texto citando
> a NR-06.
> **Uso:** ótimo para o comercial mostrar a proteção contra EPI irregular.

> 📸 **PRINT 11 — Entrega: verificação de presença**
> **Onde:** passo **Verificação**.
> **O que precisa aparecer:** a imagem da câmera, o selo "Rosto detectado", a
> instrução (ex.: "Vire a cabeça para a esquerda") e o botão "Ação Realizada".
> **Dados fictícios na tela:** —(imagem de pessoa da equipe de gravação, não de
> pessoa real do cliente).
> **Ação filmada:** cumprir uma das ações e ver o indicador ficar verde.

> 📸 **PRINT 12 — Entrega: foto**
> **Onde:** passo **Foto**.
> **O que precisa aparecer:** a captura da foto do recebimento.

> 📸 **PRINT 13 — Entrega: assinatura digital**
> **Onde:** passo **Assinatura**.
> **O que precisa aparecer:** a área "Assinatura do colaborador", os botões
> Limpar/Confirmar e o aviso da **Lei 14.063/2020**.
> **Dados fictícios na tela:** "Camila Duarte, assine no campo abaixo".
> **Ação filmada:** assinar com o mouse/dedo e clicar em Confirmar Assinatura.

> 📸 **PRINT 14 — Entrega concluída (recibo)**
> **Onde:** passo **Concluído**.
> **O que precisa aparecer:** o recibo com nome, CPF, cargo, EPI, CA, quantidade,
> data e a assinatura; o botão **Baixar PDF**.
> **Dados fictícios na tela:** recibo da entrega de **1x Luva de Segurança
> Nitrílica (CA 12345)** para **Camila Duarte**, entregue por **Marina Alves**.

> 💡 O recibo vai sozinho para a pasta do colaborador em **Documentos** — não
> precisa salvar à mão. Se o colaborador se recusar a assinar, use **Colaborador
> Recusou**: fica registrado como advertência, sem ficha "em branco".

---

### Fluxo 6 — Conferir o saldo por local

**Objetivo:** ver quanto de cada EPI existe em cada local.
**Benefício:** identifica na hora onde o estoque está crítico e onde sobra, para
planejar transferências.

1. Abra a aba **Local**.
2. Veja os indicadores (Total de Itens, Locais com Estoque, Abaixo do Mínimo,
   Zerados) e os **cartões por local**.
3. Clique num cartão para filtrar a **tabela detalhada** (EPI × tamanho × CA ×
   local × quantidade × mínimo × status).

> 📸 **PRINT 15 — Saldo por local**
> **Onde:** EPIs → **Local**.
> **O que precisa aparecer:** os indicadores no topo, os cartões por local e a
> tabela de saldo detalhado com selos "Baixo"/"Zerado".
> **Dados fictícios na tela:** **Almoxarifado Central** com 480 itens; **Estoque
> Obra Norte** com um item **Zerado**; Protetor Auricular com selo **Baixo**.

---

### Fluxo 7 — Registrar a devolução

**Objetivo:** dar baixa correta quando o EPI volta.
**Benefício:** cada EPI tem destino rastreável e o saldo só volta a subir quando
o item realmente pode ser reutilizado.

1. Na aba **Entregas**, use os filtros (colaborador, tipo de EPI, status,
   período) para achar a entrega **ativa**.
2. Clique em **Devolver**.
3. Escolha o **destino**: **Estoque** (credita saldo de volta), **Manutenção**
   (vai para o local "Em Manutenção") ou **Descarte** (não retorna ao estoque).
4. Preencha as **Observações** (obrigatórias) descrevendo o estado do EPI.
5. Confirme.

> 📸 **PRINT 16 — Devolução de EPI**
> **Onde:** EPIs → **Entregas** → botão **Devolver** → modal "Registrar
> Devolução".
> **O que precisa aparecer:** os três botões de destino (Estoque / Manutenção /
> Descarte) e o campo de observações obrigatório.
> **Dados fictícios na tela:** devolução do EPI de **Diego Freitas**, destino
> **Manutenção**, observação "Luva com desgaste, enviar para inspeção".

---

### Fluxo 8 — Acompanhar os alertas

**Objetivo:** agir antes de a validade ou o estoque virarem problema.
**Benefício:** conformidade contínua — cada risco vira um item priorizado e pode
virar Plano de Ação.

1. Abra a aba **Alertas** (ou clique nos cartões **Estoque Baixo** / **EPIs
   Vencidos** da tela inicial).
2. Veja o resumo por nível: **Críticos**, **Urgentes**, **Atenção**.
3. Na tabela, cada linha traz o tipo de alerta (CA vencido, EPI vencido, entrega
   vencida em uso, vida útil, troca atrasada, estoque baixo), o item e o
   colaborador.
4. Clique no **+** de uma linha para criar um **Plano de Ação** a partir do
   alerta.

> 📸 **PRINT 17 — Aba Alertas**
> **Onde:** EPIs → **Alertas**.
> **O que precisa aparecer:** os cartões Críticos/Urgentes/Atenção e a tabela com
> níveis coloridos e o botão **+** de ação.
> **Dados fictícios na tela:** crítico **"CA 12345 vencido"**; urgente **"Protetor
> Auricular — estoque baixo"**; atenção **"EPI de Camila Duarte vence em 20 dias"**.

---

### Fluxo 9 — Matriz de Proteção (conformidade por função)

**Objetivo:** definir os EPIs obrigatórios de cada cargo e medir a cobertura.
**Benefício:** mostra, colaborador a colaborador, quem está protegido conforme a
NR-06/PGR e quem tem lacuna — e ainda alimenta as sugestões da entrega.

1. Abra a aba **Matriz**.
2. Veja os indicadores (Colaboradores, Conformes, Com Alertas, Sem Função).
3. Clique em **Configurar Matriz** (ou numa matriz já configurada) e monte as
   linhas **Função × EPI × quantidade mínima**, marcando os obrigatórios.
4. Na tabela, acompanhe o **percentual de proteção** de cada colaborador e os
   alertas de EPI obrigatório não entregue ou vencido; use **Ação** para abrir um
   Plano de Ação.

> 📸 **PRINT 18 — Matriz de Proteção**
> **Onde:** EPIs → **Matriz**.
> **O que precisa aparecer:** os indicadores, os selos das matrizes configuradas
> e a tabela colaborador × cargo × proteção (%) × status.
> **Dados fictícios na tela:** **Camila Duarte — Operadora de Produção — 100%
> Conforme**; um colaborador com **1 alerta** (EPI obrigatório não entregue).

---

### Fluxo 10 — Auditoria inteligente e Histórico

**Objetivo:** revisar padrões e ter o registro completo de tudo.
**Benefício:** um relatório pronto para fiscalização e a trilha de cada
movimentação, com autor e data.

- **Auditoria** (aba **Auditoria**): clique em **Executar Análise**. A IA aponta
  padrões suspeitos (extravios, consumo anormal), CAs vencidos e recomendações;
  exporte em **PDF** (também arquivado em Documentos → SST).
- **Histórico** (aba **Histórico**): toda entrada, saída, ajuste e descarte, com
  saldo anterior/atual, motivo e responsável; filtre por colaborador, EPI, tipo
  e período.

> 📸 **PRINT 19 — Auditoria inteligente (IA)**
> **Onde:** EPIs → **Auditoria**.
> **O que precisa aparecer:** o botão **Executar Análise** e, depois, o relatório
> formatado com o botão **Baixar PDF**.
> **Dados fictícios na tela:** relatório da **Empresa Staging LTDA** com seções de
> Padrões, Conformidade e Anomalias.

> 📸 **PRINT 20 — Histórico de movimentações**
> **Onde:** EPIs → **Histórico**.
> **O que precisa aparecer:** os filtros e a tabela Data/Hora, Tipo, EPI,
> Quantidade, Anterior, Atual, Motivo, Realizado por.
> **Dados fictícios na tela:** entrada **+100** de Luva por Marina Alves; saída
> **-1** (entrega para Camila Duarte).

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Ficha de EPI em papel, CA vencido, estoque que some… e o processo trabalhista chega."* Abre com uma pilha de fichas de papel. | Imagem genérica de papelada |
| 8–22s | *"No YourEyes, a entrega é assinada na tela, com verificação facial e foto — validade jurídica pela Lei 14.063."* | **PRINT 11** (verificação) + **PRINT 13** (assinatura) |
| 22–35s | *"E o sistema não deixa entregar EPI com CA vencido. A NR-06 aplicada sozinha."* | **PRINT 10** (bloqueio CA) |
| 35–50s | *"Estoque por local, alertas antes de faltar e conformidade por função."* | **PRINT 15** (saldo) + **PRINT 17** (alertas) + **PRINT 18** (matriz) |
| 50–65s | *"Antes da fiscalização, a auditoria por IA aponta os riscos."* | **PRINT 19** (auditoria IA) |
| 65–80s | *"YourEyes. Proteção que se prova."* Logo. | **PRINT 14** (recibo) + tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 6–9 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("vamos configurar…", "agora eu registro a entrega…").

1. **Abertura** — o que o módulo faz e para quem (**PRINT 01**); abrir o **Guia
   Rápido** (**PRINT 02**).
2. **Configurar o módulo** — controle de estoque, CA por categoria e locais
   (**PRINT 03, 04**).
3. **Cadastrar categorias** (**PRINT 05**).
4. **Cadastrar um tipo de EPI** com CA (**PRINT 06**).
5. **Ver o estoque** e **registrar uma entrada** (**PRINT 07, 08**).
6. **Registrar a entrega completa** — formulário, verificação, foto, assinatura,
   recibo (**PRINT 09, 11, 12, 13, 14**); mostrar o **bloqueio de CA vencido**
   (**PRINT 10**).
7. **Conferir o saldo por local** (**PRINT 15**).
8. **Registrar uma devolução** (**PRINT 16**).
9. **Tratar alertas** (**PRINT 17**).
10. **Configurar e ler a Matriz de Proteção** (**PRINT 18**).
11. **Rodar a auditoria por IA** e ver o **histórico** (**PRINT 19, 20**).
12. **Encerramento** — lembrar do **Guia Rápido** e do **Manual em PDF** dentro
    do sistema.

> 💡 Dica de gravação: abra o **Guia Rápido** (botão no topo) e siga os passos —
> o roteiro do tutorial foi montado na mesma sequência, e o guia tem o **Manual
> em PDF** para download na última etapa.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Tela inicial (Entregas + cartões + abas)
- [ ] **PRINT 02** — Guia Rápido embutido
- [ ] **PRINT 03** — Config: controle de estoque e CA por categoria
- [ ] **PRINT 04** — Config: locais de estoque
- [ ] **PRINT 05** — Gerenciar categorias
- [ ] **PRINT 06** — Cadastro de novo EPI
- [ ] **PRINT 07** — Aba Estoque (lista)
- [ ] **PRINT 08** — Movimentar: nova entrada
- [ ] **PRINT 09** — Entrega: passo 1 (formulário)
- [ ] **PRINT 10** — Entrega bloqueada por CA vencido
- [ ] **PRINT 11** — Entrega: verificação de presença
- [ ] **PRINT 12** — Entrega: foto
- [ ] **PRINT 13** — Entrega: assinatura digital
- [ ] **PRINT 14** — Entrega concluída (recibo)
- [ ] **PRINT 15** — Saldo por local
- [ ] **PRINT 16** — Devolução de EPI
- [ ] **PRINT 17** — Aba Alertas
- [ ] **PRINT 18** — Matriz de Proteção
- [ ] **PRINT 19** — Auditoria inteligente (IA)
- [ ] **PRINT 20** — Histórico de movimentações

---

## 9. Erros comuns / dúvidas frequentes

- **"Não consigo iniciar a entrega — não aparece colaborador."** É preciso ter
  **colaboradores com admissão concluída**. Cadastre-os no módulo de Admissão.
- **"O botão Próximo da entrega está travado."** Provavelmente o EPI está com
  **CA vencido**, **sem CA cadastrado** ou o **saldo é insuficiente**. Os três
  bloqueiam o avanço; resolva o CA/estoque antes.
- **"O sistema exigiu CA para um uniforme."** Marque a categoria como isenta em
  **Config → Exigência de CA por Categoria**; ela passa a aceitar item sem número
  e sem validade.
- **"A câmera não abre na entrega."** A verificação de presença e a foto usam a
  câmera — libere a permissão no navegador e use um dispositivo com webcam.
- **"O CA não foi aceito no cadastro."** Cada **CA é único**; se já existe em
  outro item, o sistema avisa. Confira o número.
- **"Registrei devolução para Manutenção/Descarte e o saldo não voltou."** Só o
  destino **Estoque** credita o saldo de volta; Manutenção e Descarte, não.
- **"O saldo não baixa na entrega."** O **controle de estoque** pode estar
  desativado em **Config** — nesse modo a entrega funciona, mas sem mexer no
  saldo.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo e conferir
que os prints batem com a tela real:

1. Abra o **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
   Alves**, empresa **Empresa Staging LTDA**.
2. Vá em **Saúde & Segurança → EPIs** e percorra as abas na ordem dos fluxos
   deste manual (Entregas, Estoque, Local, Mov., Alertas, Matriz, Auditoria,
   Histórico, Config) e o botão **Entrega** (assistente de 5 passos).
3. Confira se o passo a passo, os benefícios e os marcadores de print refletem
   como você quer conduzir os vídeos.
4. Aprovado o **formato**, replico o mesmo padrão para os próximos módulos, nos
   lotes que você priorizar.
