# Manual do módulo — Configurações (Usuários, Perfis de Acesso e Auditoria)

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e do módulo-piloto [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial e de referência para os
> próximos manuais.

- **Onde fica no menu:** seção **Sistema → Configurações** (rota `/configuracoes`).
- **Para quem é:** administradores da conta (RH/DP responsável pela gestão de
  acessos). **Só quem tem papel de administrador enxerga as abas** — os demais
  usuários não veem esta tela.
- **Em uma frase:** é o painel de controle da conta — cria e gerencia os
  **usuários**, define **quem pode ver e fazer o quê** através dos **perfis de
  acesso**, guarda o **certificado do eSocial**, aplica a **logo da empresa** nos
  documentos e mantém a **trilha de auditoria** de tudo o que acontece no sistema.
- **Importante:** duas coisas que parecem iguais e não são —
  **tipo de usuário** (a *natureza* da pessoa: Gestor, RH/DP, Auditor…) e
  **perfil de acesso** (as *permissões* que ela recebe). O manual volta nisso
  várias vezes porque é a maior fonte de dúvida do suporte.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Cada pessoa vê só o que precisa ver.** Dados de RH e saúde são sensíveis
  (LGPD). Com os perfis de acesso, o financeiro não abre a folha psicossocial e o
  gestor de uma unidade não enxerga outra. O acesso é desenhado, não improvisado.
- **Comece pronto, ajuste depois.** O sistema traz **templates de perfil**
  (Gestor de RH, Técnico de Segurança, Financeiro…) prontos para usar em um
  clique — e você personaliza o que quiser a partir deles.
- **Convite em segundos, sem planilha de senhas.** Cadastrou o usuário, o sistema
  **dispara o convite por e-mail** sozinho. Precisa liberar acesso na hora? Defina
  uma **senha provisória** e a pessoa já entra.
- **Uma pessoa, várias empresas.** Quem atende um grupo econômico é vinculado a
  **várias empresas de uma vez** (ou ao grupo inteiro), sem recadastro.
- **Enxerga o risco antes do problema.** Ao montar um perfil, o sistema **calcula
  o nível de risco** (normal, elevado, crítico) e avisa quando ele acumula
  permissões sensíveis demais — como financeiro + auditoria + administrar.
- **Nada acontece sem deixar rastro.** Toda criação, edição, vínculo e mudança de
  permissão vira registro na **auditoria** — a prova de "quem fez, o quê e quando".

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Usuário** | A identidade digital de uma pessoa no sistema (nome, e-mail, CPF). É o "crachá" de acesso. |
| **Tipo de usuário** | A *natureza* da pessoa (Gestor, RH/DP, Auditor, Colaborador…). Descreve o papel, não libera acesso sozinho. |
| **Perfil de acesso** | O *pacote de permissões*: o que a pessoa pode ver e fazer em cada módulo. É ele que abre e fecha portas. |
| **Colaborador (padrão)** | O perfil aplicado automaticamente quando nenhum outro é escolhido: **auto-serviço** — a pessoa vê o próprio ponto, atestados e holerites, e nada de outros colaboradores. |
| **Template** | Um modelo de perfil pronto ("de fábrica"). Ao **usar**, ele vira um perfil da sua conta, que você pode editar. |
| **Vínculo** | A ligação do usuário com uma **empresa** (e com que papel). Uma pessoa pode ter vários. |
| **Escopo** | Até onde a permissão alcança: só o próprio usuário, o setor, a empresa inteira, o grupo econômico… |
| **Permissão sensível** | Ação de maior impacto (Administrar, Dados Sensíveis, Dados Individualizados). Aparece marcada com um cadeado. |
| **Nível de risco** | Nota automática do perfil: **Normal**, **Elevado** ou **Crítico**, conforme as permissões acumuladas. |
| **Convite** | O e-mail que a pessoa recebe para ativar o acesso e criar a própria senha. |
| **Senha provisória** | Uma senha definida pelo admin para a pessoa entrar na hora e trocar depois. |
| **Auditoria** | O histórico imutável de ações no sistema — quem fez, o quê, quando. |
| **eSocial** | Aba onde ficam os **certificados digitais** usados para transmitir eventos ao governo. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Estar logado como administrador.** As abas de Configurações só aparecem para
   quem tem papel de administrador. No ambiente de teste, use **Marina Alves**.
2. **Ter uma empresa selecionada no topo do sistema.** Alguns recursos (como a
   **Logo**) dependem da empresa ativa; sem ela, a aba pede para selecionar uma.
3. **Ter ao menos um perfil ou template disponível** se for atribuir acesso no
   cadastro — o sistema já traz os templates de fábrica, então isso costuma estar
   pronto.

> 📸 **PRINT 01 — Tela inicial de Configurações**
> **Onde:** menu **Sistema → Configurações**.
> **O que precisa aparecer:** o título **"Configurações"** com o subtítulo
> "Gerencie sua empresa, equipe e níveis de acesso" e a fileira de abas:
> **Usuários**, **Perfis & Acessos**, **eSocial**, **Auditoria** e **Logo**.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA** selecionada no
> topo; aba **Usuários** aberta por padrão.
> **Ação filmada:** panorâmica lenta passando por cada aba.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Configurações**, o topo mostra o título e as **abas** do módulo. Só
administradores as veem. Se o cadastro inicial da conta ainda não foi concluído,
aparece um cartão **"Configuração inicial pendente"** com o botão **Finalizar
Configuração** (leva ao onboarding).

| Aba | Para que serve |
|---|---|
| **Usuários** | Cadastrar pessoas, enviar convites, definir senha, gerenciar vínculos e status. |
| **Perfis & Acessos** | Criar e editar perfis de permissão, usar templates, simular acesso e ver auditoria de perfis. |
| **eSocial** | Cadastrar os certificados digitais (próprios ou por procuração) usados no eSocial. |
| **Auditoria** | Consultar o histórico de ações do sistema, filtrando por módulo. |
| **Logo** | Enviar a logo da empresa, que aparece nos PDFs, relatórios e laudos. |

> 💡 As telas **Usuários** e **Perfis & Acessos** também existem como páginas
> próprias no sistema, mas o conteúdo é o mesmo das abas daqui — para o vídeo,
> grave tudo por dentro de **Configurações**, que é o caminho único e mais claro.

---

## 5. Passo a passo por fluxo

### Fluxo 1 — Conhecer a lista de usuários

**Objetivo:** entender de relance quem tem acesso e em que situação.
**Benefício:** um painel único mostra ativos, convites pendentes, quem atende
várias empresas e alertas de possível cadastro duplicado.

1. Abra a aba **Usuários**.
2. Veja os quatro **cartões de indicadores**: **Ativos**, **Com convite**,
   **Multiempresa** e **Alertas IA** (possíveis duplicidades).
3. Use os **filtros**: busca por **nome, e-mail, CPF ou telefone**, e os seletores
   de **empresa**, **status** e **tipo de usuário**. **Limpar** zera tudo.
4. Cada linha da lista traz: **usuário**, **empresa/e-mail**, **perfil de acesso**,
   **nº de vínculos**, **cadastro completo** (indicador de qualidade) e **status**.
5. Clique em qualquer linha para abrir o **detalhe** do usuário (Fluxo 3).

> 📸 **PRINT 02 — Aba Usuários (lista e indicadores)**
> **Onde:** Configurações → **Usuários**.
> **O que precisa aparecer:** os quatro cartões, a barra de filtros e a lista com
> várias pessoas e perfis coloridos.
> **Dados fictícios na tela:**
> - **Marina Alves** — Analista de RH — perfil **Gestor de RH** — **Ativo**.
> - **Bruno Carvalho** — Coordenador de Operações — perfil **Gestor** — **Ativo**.
> - **Camila Duarte** — Operadora de Produção — **Sem perfil** — **Convite Enviado**.
> - Indicadores: **Ativos 4**, **Com convite 1**, **Multiempresa 1**, **Alertas IA 0**.
> **Ação filmada:** digitar "Camila" na busca e depois filtrar por status
> **Convite Enviado**.

> 💡 A coluna **Perfil de Acesso** mostra "Sem perfil" quando ninguém definiu um.
> Isso não é erro: significa que a pessoa está no **Colaborador (padrão)** —
> auto-serviço apenas.

---

### Fluxo 2 — Cadastrar um novo usuário

**Objetivo:** dar acesso a uma nova pessoa, em três etapas guiadas.
**Benefício:** o sistema aproveita dados já existentes, avisa sobre duplicidade e
dispara o convite sozinho.

**Etapa 1 — Dados Básicos:**
1. Clique em **Novo Usuário**.
2. Comece pelo **CPF**. Se a pessoa já existir na base de admissões, aparece o
   aviso **"Colaborador encontrado na base!"** com o botão **Reaproveitar dados
   do colaborador** — um clique preenche nome, e-mail, telefone, cargo e empresa.
3. Confira **Nome Completo** e **E-mail** (obrigatórios). Preencha o que faltar:
   Nome Social, Matrícula, Data de Nascimento, Cargo/Função, Telefone/WhatsApp.
4. Escolha o **Perfil de acesso (permissões)**. Se deixar em branco, entra o
   **Colaborador (padrão)** (auto-serviço). Um aviso lembra disso.
5. Clique em **Próximo**. Se houver e-mail/CPF repetido, aparece o **alerta de
   duplicidade**.

**Etapa 2 — Vínculo & Revisão:**
6. Escolha o **Tipo de Vínculo**: **Uma empresa**, **Múltiplas** (busca por nome
   ou CNPJ, com seleção em lote) ou **Grupo** (vincula a todas as empresas do
   grupo econômico de uma vez).
7. Defina o **Papel nesta empresa** e, se quiser, o **Contexto Operacional**
   (ex.: SST, RH, Clínica).
8. Confira o **resumo** e clique em **Criar Usuário**.

**Etapa 3 — Confirmação:**
9. A tela de sucesso mostra os selos **Usuário criado**, **Vínculo ativo** e
   **Acesso no Auth criado**, e confirma que o **convite foi enviado por e-mail**.

> 📸 **PRINT 03 — Novo Usuário, Etapa 1 (Dados Básicos)**
> **Onde:** Usuários → **Novo Usuário**.
> **O que precisa aparecer:** os campos de identidade, o seletor **Perfil de
> acesso (permissões)** e a barra de progresso das 3 etapas.
> **Dados fictícios na tela:** CPF **900.000.003-37**, nome **Camila Duarte**,
> e-mail **camila.duarte@empresastaging.com.br**, cargo **Operadora de Produção**,
> perfil **Colaborador (padrão)**.

> 📸 **PRINT 04 — Novo Usuário, Etapa 2 (Vínculo & Revisão)**
> **Onde:** mesma janela, após **Próximo**.
> **O que precisa aparecer:** o resumo dos dados, o seletor de **Tipo de Vínculo**
> (Uma empresa / Múltiplas / Grupo), a empresa escolhida e o **Papel nesta Empresa**.
> **Dados fictícios na tela:** vínculo **Uma empresa** → **Empresa Staging LTDA**;
> papel **Colaborador**; contexto **Produção**.
> **Ação filmada:** alternar entre "Uma empresa" e "Grupo" para mostrar as opções.

> 📸 **PRINT 05 — Novo Usuário, Etapa 3 (Confirmação)**
> **Onde:** mesma janela, após **Criar Usuário**.
> **O que precisa aparecer:** o ícone de sucesso, o nome/e-mail e os selos
> "Usuário criado", "Vínculo ativo", "Acesso no Auth criado" e a mensagem de
> convite enviado.
> **Dados fictícios na tela:** **Camila Duarte** — convite enviado.

> 💡 O **tipo de usuário** e o **perfil de acesso** são coisas diferentes: o
> primeiro descreve *quem a pessoa é*; o segundo define *o que ela pode fazer*.
> Dá para ter um "Gestor" com perfil restrito, e vice-versa.

---

### Fluxo 3 — Gerenciar um usuário (detalhe)

**Objetivo:** ver e editar tudo de uma pessoa: dados, acesso, vínculos e histórico.
**Benefício:** convite, senha, bloqueio e vínculos em um só lugar, com trilha.

1. Na lista, **clique no usuário** para abrir o detalhe.
2. No topo, use as **ações**: **Enviar/Reenviar convite**, **Cancelar convite**,
   **Bloquear** (com justificativa) ou **Reativar**, e **Definir senha provisória**
   (dá para **Gerar senha** aleatória e **Copiar**).
3. **Aba Dados:** clique em **Editar** para alterar nome, e-mail, CPF, perfil de
   acesso e demais campos. O bloco **Cadastro Completo** mostra o que ainda falta.
4. **Aba Vínculos:** **Adicionar vínculo** (empresa + papel + contexto),
   **Vincular todas as empresas** de uma vez, ou **encerrar** um vínculo ativo.
5. **Aba Histórico:** a trilha de auditoria só daquele usuário.

> 📸 **PRINT 06 — Detalhe do usuário, aba Dados**
> **Onde:** Usuários → clicar em um usuário.
> **O que precisa aparecer:** cabeçalho com nome, status e perfil; as ações
> (**Definir senha provisória**, **Bloquear**) e o bloco **Cadastro Completo**.
> **Dados fictícios na tela:** **Marina Alves**, status **Ativo**, perfil
> **Gestor de RH**, cadastro completo alto.

> 📸 **PRINT 07 — Detalhe do usuário, aba Vínculos**
> **Onde:** mesma janela, aba **Vínculos**.
> **O que precisa aparecer:** a lista de empresas vinculadas por status e o botão
> **Adicionar vínculo**.
> **Dados fictícios na tela:** **Marina Alves** vinculada à **Empresa Staging
> LTDA** como **RH / DP**, status **Ativo**.
> **Ação filmada:** abrir **Adicionar vínculo** e mostrar o seletor de empresa.

> 📸 **PRINT 08 — Detalhe do usuário, aba Histórico**
> **Onde:** mesma janela, aba **Histórico**.
> **O que precisa aparecer:** a linha do tempo de ações do usuário (criação,
> edição, vínculo).
> **Dados fictícios na tela:** eventos "Criação — usuario" e "Vínculo criado".

> 💡 A **senha provisória** é o atalho para liberar acesso na hora, sem esperar o
> e-mail. Peça sempre para a pessoa trocá-la no primeiro login.

---

### Fluxo 4 — Conhecer os perfis de acesso

**Objetivo:** ver os perfis que existem e o risco de cada um.
**Benefício:** um painel de governança que sinaliza acúmulo de permissões perigosas.

1. Abra a aba **Perfis & Acessos**.
2. Veja os quatro números do topo: **Perfis ativos**, **Templates disponíveis**,
   **Usuários com perfil** e **Perfis personalizados**.
3. Se houver, aparecem os **alertas de risco** (crítico/elevado) em destaque.
4. Nas sub-abas **Meus Perfis**, os cards vêm separados em **Baseados em template**
   e **Personalizados**. Cada card mostra a **cor**, o **tipo** (Padrão / Clonado /
   Personalizado), o **nível de risco**, quantos **usuários** o usam e quantos
   **módulos** ele libera.
5. O menu **⋮** de cada card oferece: **Editar permissões**, **Duplicar**,
   **Gerenciar usuários**, **Simular acesso** e **Desativar/Ativar**.

> 📸 **PRINT 09 — Aba Perfis & Acessos (Meus Perfis)**
> **Onde:** Configurações → **Perfis & Acessos**.
> **O que precisa aparecer:** os quatro indicadores, os cards de perfil com cor e
> selo de risco, e as sub-abas **Meus Perfis / Templates / Auditoria**.
> **Dados fictícios na tela:** cards **Gestor de RH** (risco Normal), **Financeiro**
> (risco Elevado) e **Auditor** (risco Crítico); "Usuários com perfil: 4".
> **Ação filmada:** abrir o menu **⋮** de um card mostrando as opções.

---

### Fluxo 5 — Usar um template pronto

**Objetivo:** criar um perfil em um clique, a partir de um modelo de fábrica.
**Benefício:** começa com permissões coerentes já configuradas, sem montar do zero.

1. Na aba **Perfis & Acessos**, entre na sub-aba **Templates**.
2. Cada card de template mostra o nome, a descrição e quantos módulos ele traz.
3. Clique em **Usar template** — ele é **clonado** como um perfil da sua conta e
   já aparece em **Meus Perfis**, pronto para editar.

> 📸 **PRINT 10 — Templates do sistema**
> **Onde:** Perfis & Acessos → **Templates**.
> **O que precisa aparecer:** os cards tracejados de template com o botão **Usar
> template** (ou "Já adicionado" nos que já foram clonados).
> **Dados fictícios na tela:** templates **Gestor de RH**, **Técnico de
> Segurança** e **Financeiro**.

---

### Fluxo 6 — Criar ou editar um perfil (permissões)

**Objetivo:** desenhar exatamente o que o perfil pode ver e fazer.
**Benefício:** controle fino por módulo, ação e escopo, com aviso de risco em tempo real.

**Aba Informações gerais:**
1. Clique em **Novo Perfil** (ou **Editar permissões** em um card existente).
2. Preencha **Nome** e **Descrição**, escolha uma **Cor de identificação** e, se
   for temporário, uma **Data de expiração**.
3. Se for para colaborador que não acessa o sistema, ligue **Perfil assistido
   (sem login)**.

**Aba Permissões:**
4. Os módulos vêm agrupados (Estrutura Organizacional, Pessoas & Cultura, Jornada
   & Rotina, Saúde & Segurança, Financeiro, Sistema…). Abra um grupo.
5. Marque o **módulo** para ativá-lo e escolha o **escopo** (Próprio usuário,
   Setor, Empresa inteira, Grupo econômico…).
6. Ligue as **ações** desejadas (Visualizar, Criar, Editar, Excluir, Exportar,
   Aprovar…). As **sensíveis** — **Administrar**, **Dados Sensíveis**, **Dados
   Individualizados** — aparecem com **cadeado** e em vermelho.
7. O **nível de risco** é recalculado sozinho e um aviso surge se ficar Elevado ou
   Crítico. **Salve**.

> 📸 **PRINT 11 — Novo/Editar Perfil, aba Informações gerais**
> **Onde:** Perfis & Acessos → **Novo Perfil**.
> **O que precisa aparecer:** os campos Nome, Descrição, a paleta de cores, a data
> de expiração e o interruptor **Perfil assistido**.
> **Dados fictícios na tela:** nome **Gestor de RH — Staging**, cor violeta,
> descrição "Acesso de RH à Empresa Staging LTDA".

> 📸 **PRINT 12 — Novo/Editar Perfil, aba Permissões**
> **Onde:** mesma janela, aba **Permissões**.
> **O que precisa aparecer:** os grupos de módulos abertos, o seletor de **escopo**
> e os botões de **ação** — com as sensíveis marcadas por cadeado — e o aviso de
> risco.
> **Dados fictícios na tela:** módulo **Ponto** com escopo **Empresa inteira** e
> ações **Visualizar, Editar, Aprovar**; aviso "permissões sensíveis" ao ligar
> **Administrar**.
> **Ação filmada:** ligar a ação **Administrar** e mostrar o selo de risco mudar.

> 💡 Comece sempre pelo **menor** acesso necessário e aumente só quando faltar
> algo. É mais seguro (e mais fácil de auditar) do que liberar tudo e cortar depois.

---

### Fluxo 7 — Simular o acesso de um perfil

**Objetivo:** ver, antes de atribuir, exatamente o que aquele perfil enxerga.
**Benefício:** confere o desenho sem precisar entrar com a conta de outra pessoa.

1. No card do perfil, abra o menu **⋮** e clique em **Simular acesso**.
2. A janela lista **todos os módulos por grupo**: os liberados aparecem em verde,
   com o **escopo** e as **ações** (as sensíveis com cadeado); os bloqueados
   aparecem apagados, com "Sem acesso a este módulo".

> 📸 **PRINT 13 — Simulação de acesso**
> **Onde:** card do perfil → **⋮** → **Simular acesso**.
> **O que precisa aparecer:** a lista de módulos com os liberados (verde, com
> escopo e ações) e os bloqueados (cinza).
> **Dados fictícios na tela:** perfil **Gestor de RH — Staging** com **Ponto**,
> **Férias** e **Atestados** liberados (Empresa inteira) e **Financeiro**
> bloqueado.

---

### Fluxo 8 — Atribuir o perfil a usuários

**Objetivo:** ligar (ou desligar) pessoas de um perfil.
**Benefício:** gerência em lote a partir do próprio perfil, com validade opcional.

1. No card do perfil, **⋮ → Gerenciar usuários**.
2. Em **Adicionar usuário**, escolha a pessoa, defina se é o **Perfil principal**,
   uma **Expiração** opcional e uma **Observação**, e clique em **Vincular ao perfil**.
3. Abaixo, veja os **usuários vinculados** e remova quem precisar no **X**.

> 📸 **PRINT 14 — Gerenciar usuários do perfil**
> **Onde:** card do perfil → **⋮** → **Gerenciar usuários**.
> **O que precisa aparecer:** o formulário de adicionar (usuário, perfil principal,
> expiração, observação) e a lista de vinculados.
> **Dados fictícios na tela:** perfil **Gestor de RH — Staging**; vinculada
> **Marina Alves** (Principal).

> 💡 Também dá para trocar o perfil de alguém direto no **detalhe do usuário**
> (Fluxo 3, aba Dados). São dois caminhos para o mesmo resultado.

---

### Fluxo 9 — Auditoria dos perfis

**Objetivo:** acompanhar mudanças de perfis, permissões e vínculos.
**Benefício:** registro imutável de cada alteração crítica de acesso.

1. Na aba **Perfis & Acessos**, entre na sub-aba **Auditoria**.
2. A linha do tempo mostra cada ação (**Criação**, **Edição**, **Clonagem**,
   **Ativação/Inativação**, **Vínculo criado/removido**), com **quem fez** e **quando**.

> 📸 **PRINT 15 — Auditoria de Perfis & Acessos**
> **Onde:** Perfis & Acessos → **Auditoria**.
> **O que precisa aparecer:** a trilha com selos de ação, autor e data.
> **Dados fictícios na tela:** "Criação — Perfil Gestor de RH — Staging criado —
> por Marina Alves".

---

### Fluxo 10 — Auditoria do sistema

**Objetivo:** consultar tudo o que aconteceu, em todos os módulos.
**Benefício:** a prova central de "quem fez, o quê e quando" para conformidade.

1. Abra a aba **Auditoria**.
2. **Busque** por ação, usuário ou alvo, ou **filtre por módulo** (Equipe,
   Admissões, Atestados, Configurações, Ponto, Férias, Benefícios, SST, Trilhas,
   Avaliações).
3. Cada registro traz a descrição, o autor, a data/hora, um selo do módulo e o
   alvo. Use **Carregar mais** para ver o histórico completo.

> 📸 **PRINT 16 — Aba Auditoria (logs do sistema)**
> **Onde:** Configurações → **Auditoria**.
> **O que precisa aparecer:** a busca, o filtro de módulo e a lista de registros
> com selos coloridos por módulo.
> **Dados fictícios na tela:** eventos como "Convidou usuário Camila Duarte" (selo
> Configurações) e um registro do módulo Ponto.
> **Ação filmada:** aplicar o filtro **Configurações** e mostrar a lista reduzir.

---

### Fluxo 11 — eSocial: certificados digitais

**Objetivo:** cadastrar o certificado usado para transmitir eventos ao governo.
**Benefício:** deixa a empresa pronta para o eSocial dentro do próprio sistema.

1. Abra a aba **eSocial**.
2. Cadastre um certificado informando **CNPJ**, **nome da empresa**, o **tipo**
   (**próprio** ou **por procuração**), o **ambiente** (homologação ou produção),
   a **validade** e a **senha**, e anexe o arquivo do certificado.
3. Os certificados cadastrados ficam listados, com status e validade.

> 📸 **PRINT 17 — Aba eSocial (certificados)**
> **Onde:** Configurações → **eSocial**.
> **O que precisa aparecer:** a lista de certificados e o formulário de cadastro
> (tipo próprio/procuração, ambiente, validade).
> **Dados fictícios na tela:** certificado de **Empresa Staging LTDA**, tipo
> **próprio**, ambiente **homologação**.

> 💡 Para os vídeos, use sempre o ambiente **homologação** e um certificado
> fictício — nunca um certificado real.

---

### Fluxo 12 — Logo da empresa

**Objetivo:** aplicar a identidade visual da empresa nos documentos.
**Benefício:** PDFs, relatórios e laudos saem com a marca da empresa.

1. Confira a **empresa selecionada** no topo (a logo é por empresa).
2. Abra a aba **Logo** e clique em **Enviar Logo** (ou **Alterar Logo**).
3. Envie um arquivo **PNG, JPG, WebP ou SVG**, de até **2 MB** (o ideal é PNG com
   fundo transparente, cerca de 400×150 px).
4. Confira a **prévia**; use **Remover** para tirar.

> 📸 **PRINT 18 — Aba Logo**
> **Onde:** Configurações → **Logo**.
> **O que precisa aparecer:** a prévia da logo, o botão **Enviar/Alterar Logo** e
> as instruções de formato e tamanho.
> **Dados fictícios na tela:** logo fictícia da **Empresa Staging LTDA** na prévia.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, mostrando dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Quem vê a folha? Quem abre o psicossocial? Se você não sabe, é um problema."* Abre com uma planilha de senhas bagunçada. | Imagem genérica de planilha |
| 8–22s | *"No YourEyes, você desenha o acesso de cada pessoa — por módulo, por escopo, por ação."* | **PRINT 12** (permissões) + **PRINT 13** (simular acesso) |
| 22–36s | *"Comece com perfis prontos e ajuste em um clique."* | **PRINT 10** (templates) + **PRINT 09** (perfis) |
| 36–50s | *"Cadastrou, convidou — o acesso sai por e-mail na hora."* | **PRINT 03** (novo usuário) + **PRINT 05** (confirmação) |
| 50–65s | *"E tudo o que acontece fica registrado. Auditoria pronta para o dia da conferência."* | **PRINT 16** (auditoria) |
| 65–80s | *"YourEyes. Cada um vê só o que precisa ver."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 6–9 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("agora eu cadastro…", "vamos montar o perfil…").

1. **Abertura** — o que é Configurações e para quem (**PRINT 01**).
2. **A lista de usuários** e seus filtros (**PRINT 02**).
3. **Cadastrar um usuário** nas três etapas (**PRINT 03, 04, 05**).
4. **Abrir o detalhe**: senha provisória, vínculos e histórico (**PRINT 06, 07, 08**).
5. **Os perfis de acesso** e o painel de risco (**PRINT 09**).
6. **Usar um template** de fábrica (**PRINT 10**).
7. **Criar/editar um perfil**: geral e permissões (**PRINT 11, 12**).
8. **Simular o acesso** do perfil (**PRINT 13**).
9. **Atribuir o perfil** a um usuário (**PRINT 14**).
10. **Auditoria de perfis** e **auditoria do sistema** (**PRINT 15, 16**).
11. **eSocial** e **Logo** (**PRINT 17, 18**).
12. **Encerramento** — reforçar a diferença entre *tipo de usuário* e *perfil de
    acesso*, e o valor da auditoria.

> 💡 Dica de gravação: mostre logo no início a diferença entre **tipo de usuário**
> e **perfil de acesso** — é a dúvida nº 1 e ancora todo o resto do vídeo.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina Alves**
(administradora / Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Tela inicial de Configurações (abas)
- [ ] **PRINT 02** — Aba Usuários (lista e indicadores)
- [ ] **PRINT 03** — Novo Usuário, Etapa 1 (Dados Básicos)
- [ ] **PRINT 04** — Novo Usuário, Etapa 2 (Vínculo & Revisão)
- [ ] **PRINT 05** — Novo Usuário, Etapa 3 (Confirmação)
- [ ] **PRINT 06** — Detalhe do usuário, aba Dados
- [ ] **PRINT 07** — Detalhe do usuário, aba Vínculos
- [ ] **PRINT 08** — Detalhe do usuário, aba Histórico
- [ ] **PRINT 09** — Aba Perfis & Acessos (Meus Perfis)
- [ ] **PRINT 10** — Templates do sistema
- [ ] **PRINT 11** — Novo/Editar Perfil, Informações gerais
- [ ] **PRINT 12** — Novo/Editar Perfil, Permissões
- [ ] **PRINT 13** — Simulação de acesso
- [ ] **PRINT 14** — Gerenciar usuários do perfil
- [ ] **PRINT 15** — Auditoria de Perfis & Acessos
- [ ] **PRINT 16** — Aba Auditoria (logs do sistema)
- [ ] **PRINT 17** — Aba eSocial (certificados)
- [ ] **PRINT 18** — Aba Logo

---

## 9. Erros comuns / dúvidas frequentes

- **"Não vejo as abas de Configurações."** Elas só aparecem para
  **administradores**. Confira o papel do usuário logado.
- **"Qual a diferença entre tipo de usuário e perfil de acesso?"** O **tipo**
  descreve *quem a pessoa é* (Gestor, RH/DP…); o **perfil** define *o que ela pode
  fazer*. Quem libera acesso é o perfil.
- **"A coluna Perfil de Acesso mostra 'Sem perfil'."** Não é erro: a pessoa está
  no **Colaborador (padrão)** — auto-serviço (só os próprios dados). Atribua um
  perfil se ela precisar de mais.
- **"O convite não chegou."** Peça para conferir a caixa de spam. Se ainda assim
  não vier, use **Reenviar convite** ou **Definir senha provisória** no detalhe do
  usuário.
- **"Este e-mail já está vinculado a outra organização."** O e-mail é único no
  sistema inteiro. Use outro e-mail para a pessoa nesta conta.
- **"O perfil ficou com risco Crítico."** Ele acumula permissões sensíveis demais
  (ex.: financeiro + auditoria + administrar). Revise as permissões ou confirme que
  o acúmulo é mesmo necessário e justificado.
- **"A aba Logo pede para selecionar uma empresa."** A logo é por empresa —
  selecione uma no topo do sistema antes de enviar.
- **"Não consigo remover um perfil em uso."** Prefira **Desativar** (preserva o
  histórico e os vínculos) a apagar.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/configuracoes_usuarios-perfis-e-auditoria.md` no
   projeto.
2. Se quiser conferir as telas na prática, acesse o **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/) logado como **Marina
   Alves**, empresa **Empresa Staging LTDA**, e vá em **Sistema → Configurações**;
   percorra as abas **Usuários**, **Perfis & Acessos**, **eSocial**, **Auditoria**
   e **Logo** comparando com o passo a passo e os marcadores de print.
3. Confira se os benefícios, fluxos e prints refletem como você quer conduzir os
   vídeos. Aprovado o **formato**, replico o mesmo padrão para os demais módulos.
