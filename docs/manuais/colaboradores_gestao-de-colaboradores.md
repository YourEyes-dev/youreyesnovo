# Manual do módulo — Gestão de Colaboradores

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e no mesmo tom do módulo-piloto [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial deste módulo.

- **Onde fica no menu:** seção **Estrutura Organizacional → Colaboradores**
  (rota `/colaboradores`).
- **Para quem é:** RH, Departamento Pessoal (DP) e Gestores.
- **Em uma frase:** é o **cadastro central de pessoas** da empresa — admite,
  edita, importa em massa, acompanha ativos e registra desligamentos, tudo em um
  só lugar, alimentando os demais módulos (Ponto, Documentos, Financeiro, Saúde).
- **Importante:** aqui vivem os **vínculos internos** (CLT, temporário,
  aprendiz, estagiário, intermitente). **Prestadores de serviço / PJ** têm tela
  própria — **Estrutura Organizacional → Prestadores de Serviços** — e não são
  cadastrados por aqui de propósito.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Uma única fonte da verdade sobre a equipe.** Quem cadastra o colaborador
  aqui já o disponibiliza para o Ponto, os Documentos, a Saúde Ocupacional e o
  Financeiro. Nada de recadastrar a mesma pessoa em cada módulo.
- **Admissão em minutos, não em dias.** O cadastro rápido pede só o essencial;
  a admissão completa (em 6 etapas) cobre dados pessoais, contato, profissional,
  bancário, exame admissional e documentos — com aprovação por etapas.
- **Importação em massa de planilha.** Chegou uma carteira nova ou está migrando
  de outro sistema? Suba um Excel/CSV e o sistema **cria colaboradores,
  departamentos e cargos de uma vez** — e ainda distribui cada pessoa para a
  empresa certa pelo CNPJ.
- **O próprio colaborador preenche o cadastro.** Um **link de cadastro** pode ser
  enviado para a pessoa completar os próprios dados e anexar documentos, tirando
  a digitação das costas do RH.
- **Desligamento com a lei do lado da empresa.** O fluxo de rescisão calcula
  aviso prévio, verbas e multa de FGTS, checa o **exame demissional (NR-7)**,
  avisa sobre **estabilidades** (acidentária, gestante, afastamento ativo) e
  gera o evento **eSocial S-2299** e as verbas no Financeiro.
- **Nada some, tudo é rastreável.** Colaborador com histórico não é apagado por
  acidente: o sistema oferece **Inativar** (preserva tudo) e só permite exclusão
  definitiva com dupla confirmação e perfil autorizado.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Colaborador ativo** | Pessoa com cadastro concluído e vínculo vigente — aparece na aba **Ativos**. |
| **Admissão** | O processo de entrada de um novo colaborador, com etapas e documentos, na aba **Admissões**. |
| **Cadastro rápido** | O botão **Novo Cadastro** — formulário enxuto que já cria a pessoa como ativa. |
| **Tipo de vínculo** | O regime de contratação: CLT, temporário, aprendiz, estagiário ou intermitente. |
| **Estabelecimento / Obra** | A unidade física onde a pessoa trabalha (sede, filial, canteiro). |
| **Bate ponto** | Se o colaborador aparece ou não no módulo de Ponto Eletrônico. |
| **Art. 62 da CLT** | Enquadramento que **dispensa** o controle de jornada (ex.: gestão, atividade externa). |
| **CBO** | Classificação Brasileira de Ocupações — o código oficial da ocupação. |
| **Link de cadastro** | Endereço que o RH envia para o colaborador **completar o próprio cadastro**. |
| **Inativar** | Tirar a pessoa das listas ativas **sem apagar** nada (reversível). |
| **Desligar** | Registrar a rescisão — calcula verbas e move a pessoa para **Desligados**. |
| **ASO / exame demissional** | Atestado de Saúde Ocupacional exigido pela **NR-7** no desligamento. |
| **Estabilidade** | Garantia legal de emprego (gestante, acidentária etc.) que pode **bloquear** o desligamento. |
| **S-2299** | Evento do eSocial de desligamento, gerado automaticamente na rescisão. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Empresa ativa selecionada** no cabeçalho — o cadastro e as listas sempre se
   referem à **empresa ativa**. Ao importar planilha com CNPJ, o sistema
   distribui cada pessoa para a empresa correta automaticamente.
2. **Estabelecimentos/Obras, Departamentos e Cargos cadastrados** (nas outras
   telas da seção Estrutura Organizacional). Não é obrigatório para o cadastro
   rápido, mas deixa os campos de seleção prontos — e a importação cria os que
   faltarem.
3. **Permissão de perfil.** Criar, editar, exportar e excluir colaboradores são
   ações controladas por perfil de acesso. Sem permissão, os botões
   correspondentes nem aparecem.

> 📸 **PRINT 01 — Tela inicial do módulo**
> **Onde:** menu **Estrutura Organizacional → Colaboradores**, aba **Ativos**.
> **O que precisa aparecer:** o título **"Colaboradores"** com o subtítulo
> "Gerencie sua equipe — admissão, ativos e desligados", os botões **Importar
> Colaboradores** e **Novo Cadastro**, as **três abas** (Ativos, Admissões,
> Desligados) e os cards de colaboradores.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; cards de
> **Marina Alves**, **Bruno Carvalho**, **Camila Duarte** e **Diego Freitas**.
> **Ação filmada:** panorâmica lenta mostrando as três abas e os botões do topo.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Colaboradores**, o topo traz o título, e à direita os botões
**Importar Colaboradores** e **Novo Cadastro** (quem tem permissão de criar).
Logo abaixo ficam as **três abas** do módulo:

| Aba | Para que serve |
|---|---|
| **Ativos** | A lista de quem está na ativa. Busca, filtros, cards ou lista, e o menu de ações de cada pessoa (perfil, editar, documentos, link, inativar, desligar, excluir). |
| **Admissões** | O processo de entrada: indicadores por situação e o formulário de admissão em 6 etapas com aprovação por documento e por etapa. |
| **Desligados** | O histórico de quem saiu — consulta e acesso aos documentos do colaborador. |

Dentro de **Ativos**, uma barra de filtros permite **buscar por nome, e-mail ou
função**, filtrar por **Departamento** e por **Estabelecimento / Obra**, e
**exportar** a lista filtrada para Excel. Um botão alterna a visualização entre
**cards** e **lista**.

> 📸 **PRINT 02 — Visualização em lista + filtros**
> **Onde:** Colaboradores → aba **Ativos**, com o botão de visualização em
> **lista** ativado.
> **O que precisa aparecer:** a barra de busca, os seletores **Departamento** e
> **Estabelecimento / Obra**, o contador "Mostrando X de Y colaboradores" e a
> tabela com colunas Colaborador, Cargo, Departamento, Contato, Admissão e
> Status.
> **Dados fictícios na tela:** linhas de **Marina Alves — Analista de RH**,
> **Bruno Carvalho — Coordenador de Operações**, **Camila Duarte — Operadora de
> Produção** (status **Ativo**), **Eduarda Lima — Analista Financeiro**.
> **Ação filmada:** alternar de cards para lista e aplicar o filtro
> "Departamento: Operações".

---

## 5. Passo a passo por fluxo

### Fluxo 1 — Cadastrar um colaborador (cadastro rápido)

**Objetivo:** colocar uma pessoa nova na ativa em poucos campos.
**Benefício:** a pessoa já nasce disponível para o Ponto, os Documentos e a
Saúde — e o sistema ainda cria a **pasta de documentos** dela com a lista de
documentos obrigatórios.

1. Clique em **Novo Cadastro** (topo da página).
2. (Opcional) **Adicione a foto** do colaborador.
3. Preencha **Nome Completo** e **CPF** (o sistema valida o dígito verificador),
   e opcionalmente **Celular** e **E-mail**.
4. Escolha o **Tipo de Vínculo** (CLT, temporário, aprendiz, estagiário,
   intermitente) e a **Data de Admissão**.
5. Defina se a pessoa **bate ponto eletrônico** e, se for o caso, o
   enquadramento no **art. 62 da CLT** (dispensa de jornada).
6. Selecione **Estabelecimento / Obra**, **Departamento**, **Cargo** e, se
   quiser, **Gestor Imediato**, **Centro de Custo**, **Matrícula eSocial** e
   **CBO**.
7. Clique em **Cadastrar**.

> 📸 **PRINT 03 — Modal "Novo Colaborador" (dados principais)**
> **Onde:** botão **Novo Cadastro**.
> **O que precisa aparecer:** a área da foto, os campos **Nome Completo**,
> **CPF**, **Celular**, **E-mail**, **Tipo de Vínculo** e **Data de Admissão**,
> e o banner da empresa ativa no topo do modal.
> **Dados fictícios na tela:** **Diego Freitas**, CPF **900.000.004-18**,
> vínculo **Empregado CLT**, data de admissão **01/09/2026**, e-mail
> **diego.freitas@staging.com.br**.
> **Ação filmada:** digitar o nome e o CPF e escolher o tipo de vínculo.

> 📸 **PRINT 04 — "Bate ponto" e dispensa do art. 62 da CLT**
> **Onde:** o mesmo modal, rolando um pouco para baixo.
> **O que precisa aparecer:** o switch **Bate ponto eletrônico** e o bloco
> **Dispensa de controle de jornada (art. 62 da CLT)** com os campos
> **Enquadramento** e **Teletrabalho**.
> **Dados fictícios na tela:** **Diego Freitas** com **Bate ponto** ativado,
> enquadramento **"Não se enquadra (marca ponto)"** e teletrabalho **"Por
> jornada"**.
> **Ação filmada:** alternar o switch de ponto e abrir o seletor de
> enquadramento.

> 💡 O campo **Bate ponto** é o que liga a pessoa ao módulo de **Ponto
> Eletrônico**. Vínculos PJ/terceiros normalmente ficam desligados; para teletrabalho
> **por jornada**, o ponto continua obrigatório mesmo com o art. 62 marcado (Lei
> 14.442/2022) — o sistema avisa isso na própria tela.

> 📸 **PRINT 05 — Cargo com condições especiais herdadas**
> **Onde:** o mesmo modal, campo **Cargo**.
> **O que precisa aparecer:** o seletor de **Cargo** e o aviso amarelo
> **"Condições Especiais (herdadas da função)"** com os selos de
> insalubridade/periculosidade/aposentadoria especial.
> **Dados fictícios na tela:** cargo **"Operadora de Produção"** com selo
> **Insalubridade 20%** (exemplo).
> **Ação filmada:** selecionar o cargo e mostrar o aviso surgindo.

> 💡 As condições especiais (insalubridade, periculosidade, aposentadoria
> especial) vêm **da função**, não do cadastro da pessoa — configure-as em
> **Cargos** e todas as pessoas daquela função herdam automaticamente.

---

### Fluxo 2 — Consultar, filtrar e exportar a equipe

**Objetivo:** encontrar rapidamente quem você procura e levar a lista para fora.
**Benefício:** uma tela responde "quem trabalha onde, em que função e com que
status", e exporta isso em um clique.

1. Na aba **Ativos**, use a **busca** (nome, e-mail ou função).
2. Refine por **Departamento** e por **Estabelecimento / Obra**.
3. Alterne entre **cards** e **lista** conforme a preferência.
4. Clique no ícone de **download** para **exportar** a lista filtrada em Excel.

> 📸 **PRINT 06 — Ver perfil (resumo do colaborador)**
> **Onde:** clicar sobre um card/linha, ou menu **⋯ → Ver perfil**.
> **O que precisa aparecer:** o modal de resumo com **CPF**, **e-mail**,
> **celular**, **departamento**, **estabelecimento/filial**, **data de
> admissão** e o selo de **status**.
> **Dados fictícios na tela:** **Camila Duarte**, CPF **900.000.003-37**,
> Operações, estabelecimento **"Sede — Empresa Staging LTDA"**, status
> **Ativo**.

> 💡 A exportação respeita os filtros: se você filtrou "Operações", a planilha
> sai só com Operações. O botão de exportar só aparece para perfis com
> permissão de exportação.

---

### Fluxo 3 — O menu de ações de cada colaborador

**Objetivo:** conhecer tudo o que dá para fazer com uma pessoa da lista.
**Benefício:** editar, ver documentos, compartilhar o link de cadastro,
inativar, desligar ou excluir — tudo a partir do mesmo menu **⋯**.

No card (ou na linha), clique no botão **⋯** para abrir o menu:

- **Ver perfil** — abre o resumo (PRINT 06).
- **Editar** — reabre o formulário completo do colaborador.
- **Documentos** — leva à pasta da pessoa no módulo **Documentos**.
- **Compartilhar Link / Copiar Link de Cadastro** — copia o link para a pessoa
  completar o próprio cadastro (Fluxo 4).
- **Inativar / Reativar** — tira ou devolve a pessoa às listas ativas.
- **Desligar** — abre o fluxo de rescisão (Fluxo 7).
- **Excluir** — remoção definitiva (só com permissão; Fluxo 6).

> 📸 **PRINT 07 — Menu de ações do colaborador**
> **Onde:** card de um colaborador → botão **⋯**.
> **O que precisa aparecer:** o menu aberto com as opções Ver perfil, Editar,
> Documentos, Compartilhar Link, Inativar, Desligar e Excluir.
> **Dados fictícios na tela:** menu aberto sobre o card de **Bruno Carvalho**.
> **Ação filmada:** abrir o menu e passar o mouse pelas opções.

---

### Fluxo 4 — Deixar o colaborador completar o próprio cadastro

**Objetivo:** enviar um link para a pessoa preencher os próprios dados e anexar
documentos.
**Benefício:** o RH não digita tudo sozinho — a pessoa entra com nome, contato e
documentos, e o RH só confere.

1. No menu **⋯** do colaborador, clique em **Compartilhar Link** (cards) ou
   **Copiar Link de Cadastro** (lista).
2. O link é copiado para a área de transferência (uma mensagem confirma).
3. Envie o link à pessoa por WhatsApp, e-mail etc.
4. Ao abrir, a pessoa vê a tela **Completar Cadastro** com os próprios dados e
   os documentos a enviar.

> 📸 **PRINT 08 — Tela "Completar Cadastro" (visão do colaborador)**
> **Onde:** o link de cadastro aberto no navegador (`/completar-cadastro/…`).
> **O que precisa aparecer:** a saudação com o nome, os campos que a pessoa
> preenche e a área de upload de documentos.
> **Dados fictícios na tela:** **Diego Freitas**, com a lista de documentos
> obrigatórios (RG, CPF, Comprovante de Residência, CTPS etc.).
> **Ação filmada:** ótimo momento para gravar a tela real de um celular
> abrindo o link.

> 💡 Ao cadastrar um colaborador, o sistema já cria a **pasta de documentos**
> dele e a lista de documentos obrigatórios (RG, CPF, comprovante de residência,
> CTPS, título de eleitor, certidão, foto 3x4, comprovante de escolaridade e
> exame admissional).

---

### Fluxo 5 — Inativar (e reativar) um colaborador

**Objetivo:** tirar alguém das listas ativas sem perder o histórico.
**Benefício:** afastamentos longos, licenças ou cadastros que não devem mais
aparecer somem da lista — e voltam quando você quiser, com um clique.

1. No menu **⋯**, clique em **Inativar**.
2. (Opcional) informe um **motivo**.
3. Confirme. A pessoa sai das listas ativas, mas **todos os registros e
   vínculos são preservados**.
4. Para reverter, use **Reativar** no mesmo menu.

> 📸 **PRINT 09 — Inativar colaborador**
> **Onde:** menu **⋯ → Inativar**.
> **O que precisa aparecer:** o diálogo de confirmação com o campo **Motivo
> (opcional)** e o texto explicando que os registros serão preservados.
> **Dados fictícios na tela:** **Eduarda Lima**, motivo **"Licença sem
> vencimento"**.

> 💡 **Inativar** é reversível e não perde nada. **Excluir** é definitivo. Para
> pessoas reais, prefira sempre **Inativar**.

---

### Fluxo 6 — Excluir um colaborador (com trava de segurança)

**Objetivo:** remover definitivamente um cadastro — normalmente de teste.
**Benefício:** o sistema **verifica antes** se a pessoa tem histórico em outros
módulos e exige confirmação por digitação, evitando exclusões por engano.

1. No menu **⋯**, clique em **Excluir** (aparece só para perfis autorizados).
2. O sistema **verifica vínculos** (Ponto, Documentos, Saúde, Financeiro…).
3. Se **não houver** vínculos: digite **EXCLUIR** para confirmar.
4. Se **houver** histórico: um aviso lista os módulos afetados e exige digitar
   **EXCLUIR TUDO** — a exclusão forçada apaga tudo permanentemente.

> 📸 **PRINT 10 — Excluir colaborador com histórico**
> **Onde:** menu **⋯ → Excluir** de uma pessoa com registros.
> **O que precisa aparecer:** o aviso vermelho "Colaborador com histórico no
> sistema", a lista de módulos vinculados e o campo para digitar **EXCLUIR
> TUDO**.
> **Dados fictícios na tela:** cadastro de teste **"Colaborador Teste QA"**
> (nunca uma persona/dado real), com módulos listados.

> 💡 Sem Point-in-Time Recovery no banco, exclusão é para sempre. Use exclusão
> forçada **apenas** para cadastros de teste; para o resto, **Inativar**.

---

### Fluxo 7 — Desligar um colaborador (rescisão)

**Objetivo:** registrar a saída de uma pessoa com todos os cálculos e checagens
legais.
**Benefício:** aviso prévio, verbas, multa de FGTS, exame demissional e
estabilidades tratados juntos — e a integração com Financeiro e eSocial feita
sozinha.

1. No menu **⋯**, clique em **Desligar**.
2. Informe **Data do Desligamento** e **Motivo** (dispensa sem/com justa causa,
   pedido de demissão, acordo mútuo, término de contrato, aposentadoria etc.).
3. Confira o **Aviso Prévio** — tipo (trabalhado/indenizado/dispensado) e os
   **dias calculados** (30 + 3 por ano, máx. 90; metade no acordo mútuo).
4. Trate o **Exame Demissional (NR-7)**: use um **ASO anterior válido** (135
   dias para GR 1–2, 90 para GR 3–4) ou informe o exame novo e anexe o ASO.
5. Preencha **Homologação e Verbas** (multa de FGTS e seguro-desemprego já
   aparecem calculados pelo motivo) e a **Chave de Conectividade Social (FGTS)**
   quando exigida.
6. Resolva os **alertas de estabilidade** (gestante, acidentária, afastamento
   ativo) — alguns **bloqueiam** o desligamento até serem tratados.
7. Clique em **Confirmar Desligamento**. O sistema gera as **verbas
   rescisórias** no Financeiro, o evento **eSocial S-2299** e envia ao Hub
   Contábil.

> 📸 **PRINT 11 — Desligamento (dados e aviso prévio)**
> **Onde:** menu **⋯ → Desligar**.
> **O que precisa aparecer:** os campos **Data do Desligamento** e **Motivo**, e
> o bloco **Aviso Prévio** com o total de dias calculado.
> **Dados fictícios na tela:** **Camila Duarte**, data **30/09/2026**, motivo
> **"Dispensa sem justa causa"**, aviso **Indenizado**, **33 dias**.
> **Ação filmada:** escolher o motivo e mostrar os dias de aviso mudando.

> 📸 **PRINT 12 — Exame demissional (NR-7) e verbas**
> **Onde:** o mesmo modal, rolando para baixo.
> **O que precisa aparecer:** o painel **NR-07** com a validade do ASO anterior,
> os campos do exame demissional e os cartões **Multa FGTS** e **Seguro
> Desemprego**.
> **Dados fictícios na tela:** GR da empresa **2 — validade 135 dias**, **Multa
> FGTS 40%**, **Seguro-desemprego: Sim**.

> 💡 Se houver **estabilidade ativa** (ex.: retorno de acidente há menos de 12
> meses), o botão de confirmar fica **bloqueado** — só justa causa ou
> falecimento passam. É a lei protegendo a empresa contra rescisão indevida.

---

### Fluxo 8 — Importar colaboradores em massa (planilha)

**Objetivo:** cadastrar muitas pessoas de uma vez a partir de um Excel/CSV.
**Benefício:** migração e admissões em lote em minutos — o sistema cria também
os **departamentos e cargos** que faltarem e distribui cada pessoa para a
**empresa certa** pelo CNPJ.

1. Clique em **Importar Colaboradores** (topo).
2. **Baixe o modelo** (CSV ou Excel) — o Excel vem com abas de instruções e de
   valores aceitos.
3. Preencha a planilha (obrigatórios: **CNPJ/CPF Empresa**, **Nome**, **CPF**,
   **Data de Nascimento**, **Cargo**, **Departamento**, **Data de Admissão**).
4. **Arraste o arquivo** para a área de upload (ou "Parametrizar Arquivo" para
   mapear colunas de um layout diferente).
5. Confira a **pré-visualização**: registros **válidos** e **com erros**.
6. Clique em **Importar N registros**.
7. Veja o **resultado**: novos, atualizados, departamentos/cargos criados e a
   distribuição por empresa.

> 📸 **PRINT 13 — Importar: upload e modelo**
> **Onde:** botão **Importar Colaboradores**, etapa de **upload**.
> **O que precisa aparecer:** a área de arrastar arquivo, os botões de download
> do modelo (CSV e Excel) e a lista de **colunas esperadas** com as
> obrigatórias destacadas.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; nenhum dado
> pessoal real — use o próprio modelo de exemplo.

> 📸 **PRINT 14 — Importar: pré-visualização (válidos x erros)**
> **Onde:** etapa de **preview** da importação.
> **O que precisa aparecer:** os cartões "X registros válidos" e "Y com erros",
> os filtros Todos/Com erros/Válidos e a tabela de linhas.
> **Dados fictícios na tela:** planilha fictícia com CPFs da faixa
> **900.000.0XX**; ex.: **8 válidos, 1 com erro** ("CPF inválido").

> 📸 **PRINT 15 — Importar: resultado**
> **Onde:** etapa de **resultado**.
> **O que precisa aparecer:** o "Importação Concluída!", as estatísticas
> (Departamentos criados, Cargos criados, Novos, Atualizados) e a distribuição
> por empresa.
> **Dados fictícios na tela:** **7 novos**, **1 atualizado**, **2 departamentos
> criados**, **3 cargos criados**, empresa **Empresa Staging LTDA**.

> 💡 **CPF duplicado não vira registro repetido** — ele atualiza a pessoa que já
> existe. E se a planilha trouxer várias empresas por CNPJ, troque a **empresa
> ativa** no cabeçalho para ver cada grupo.

---

### Fluxo 9 — Admissão completa (processo em etapas)

**Objetivo:** conduzir a entrada de um colaborador com documentos e aprovações.
**Benefício:** um processo formal e auditável — dados completos, documentos
anexados e aprovação etapa por etapa, com indicadores de andamento.

1. Abra a aba **Admissões** — no topo, os **indicadores** por situação (Total,
   Aguardando Docs, Em Análise, Aprovados, Reprovados, Rascunhos).
2. Clique em **Nova Admissão** e preencha as **6 etapas**: **Dados Pessoais →
   Contato → Profissional → Bancários → Exame Admissional → Documentos**.
3. **Anexe os documentos** exigidos em cada etapa (dá para salvar como rascunho e
   voltar depois).
4. Acompanhe pela **lista de admissões**; no **detalhe**, aprove/rejeite
   documentos e etapas do fluxo.
5. Ao concluir e aprovar, o colaborador passa a constar como **ativo**.

> 📸 **PRINT 16 — Aba Admissões (indicadores e lista)**
> **Onde:** Colaboradores → aba **Admissões**.
> **O que precisa aparecer:** os seis cartões de indicadores e a lista de
> admissões em andamento.
> **Dados fictícios na tela:** **Total 4**, **Aguardando Docs 1**, **Em Análise
> 1**, **Aprovados 2**; admissão de **Diego Freitas** em andamento.

> 📸 **PRINT 17 — Formulário de admissão em etapas**
> **Onde:** Admissões → **Nova Admissão**.
> **O que precisa aparecer:** a trilha das 6 etapas (Dados Pessoais, Contato,
> Profissional, Bancários, Exame Admissional, Documentos) com a etapa atual
> destacada.
> **Dados fictícios na tela:** etapa **Dados Pessoais** de **Diego Freitas**,
> CPF **900.000.004-18**.
> **Ação filmada:** avançar da etapa Dados Pessoais para Contato.

> 📸 **PRINT 18 — Detalhe da admissão (documentos e aprovação)**
> **Onde:** Admissões → clicar em uma admissão → **detalhe**.
> **O que precisa aparecer:** a lista de documentos com status (pendente/
> enviado/aprovado/rejeitado) e o histórico de etapas de aprovação.
> **Dados fictícios na tela:** admissão de **Diego Freitas** com **CTPS
> aprovada** e **Comprovante de Residência pendente**.

> 💡 O **cadastro rápido** (Fluxo 1) já cria a pessoa ativa; a **Admissão**
> (aqui) é para quando você quer o processo completo com documentos e
> aprovações. Os dois convivem — escolha conforme a formalidade que o caso pede.

---

### Fluxo 10 — Consultar os desligados

**Objetivo:** encontrar quem já saiu e acessar seus documentos.
**Benefício:** o histórico não some — consultas, auditorias e segunda via de
documentos continuam ao alcance.

1. Abra a aba **Desligados**.
2. Veja a lista de quem foi desligado (com cargo, departamento e contato).
3. Clique no ícone de **pasta** para abrir os **documentos** da pessoa.

> 📸 **PRINT 19 — Aba Desligados**
> **Onde:** Colaboradores → aba **Desligados**.
> **O que precisa aparecer:** a tabela de desligados com o selo **Desligado** e
> o botão de acesso aos documentos.
> **Dados fictícios na tela:** **Camila Duarte**, Operadora de Produção, selo
> **Desligado**.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, mostrando dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Sua equipe cadastrada em cinco sistemas diferentes? Um retrabalho sem fim."* Abre com telas desencontradas. | Imagem genérica |
| 8–22s | *"No YourEyes, cada pessoa é cadastrada uma vez — e já entra no Ponto, nos Documentos e na Saúde."* | **PRINT 01** (tela inicial) + **PRINT 03** (novo colaborador) |
| 22–38s | *"Carteira nova? Importe a planilha inteira — colaboradores, cargos e departamentos criados de uma vez."* | **PRINT 13** + **PRINT 15** (importação e resultado) |
| 38–52s | *"O próprio colaborador completa o cadastro pelo celular."* | **PRINT 08** (completar cadastro) |
| 52–68s | *"E o desligamento vem com a lei do lado da empresa: verbas, FGTS, exame demissional e eSocial."* | **PRINT 11** + **PRINT 12** (desligamento) |
| 68–80s | *"YourEyes. Sua equipe, sob controle."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 5–8 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("vamos cadastrar…", "agora eu importo…").

1. **Abertura** — o que o módulo faz e as três abas (**PRINT 01, 02**).
2. **Cadastrar um colaborador** — dados, ponto, art. 62 e cargo (**PRINT 03, 04,
   05**).
3. **Consultar e filtrar** — busca, filtros, ver perfil e exportar (**PRINT
   06**).
4. **O menu de ações** — visão geral das opções (**PRINT 07**).
5. **Compartilhar o link de cadastro** e mostrar a tela do colaborador (**PRINT
   08**).
6. **Inativar / reativar** (**PRINT 09**).
7. **Excluir com segurança** (**PRINT 10**).
8. **Desligar um colaborador** — dados, aviso, NR-7 e verbas (**PRINT 11, 12**).
9. **Importar em massa** — upload, preview e resultado (**PRINT 13, 14, 15**).
10. **Admissão completa** — indicadores, etapas e detalhe (**PRINT 16, 17, 18**).
11. **Consultar desligados** (**PRINT 19**).
12. **Encerramento** — reforçar que o cadastro alimenta os demais módulos.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Tela inicial / aba Ativos (cards)
- [ ] **PRINT 02** — Visualização em lista + filtros
- [ ] **PRINT 03** — Modal Novo Colaborador (dados principais)
- [ ] **PRINT 04** — Bate ponto + art. 62 da CLT
- [ ] **PRINT 05** — Cargo com condições especiais herdadas
- [ ] **PRINT 06** — Ver perfil (resumo)
- [ ] **PRINT 07** — Menu de ações do colaborador
- [ ] **PRINT 08** — Tela "Completar Cadastro" (colaborador)
- [ ] **PRINT 09** — Inativar colaborador
- [ ] **PRINT 10** — Excluir colaborador com histórico
- [ ] **PRINT 11** — Desligamento (dados e aviso prévio)
- [ ] **PRINT 12** — Exame demissional (NR-7) e verbas
- [ ] **PRINT 13** — Importar: upload e modelo
- [ ] **PRINT 14** — Importar: pré-visualização (válidos x erros)
- [ ] **PRINT 15** — Importar: resultado
- [ ] **PRINT 16** — Aba Admissões (indicadores e lista)
- [ ] **PRINT 17** — Formulário de admissão em etapas
- [ ] **PRINT 18** — Detalhe da admissão (documentos e aprovação)
- [ ] **PRINT 19** — Aba Desligados

---

## 9. Erros comuns / dúvidas frequentes

- **"Cadastrei a pessoa, mas ela não aparece na lista."** Confira a **empresa
  ativa** no cabeçalho — a lista mostra só a empresa selecionada. Verifique
  também os **filtros** (Departamento / Estabelecimento) e a busca.
- **"O colaborador não aparece no Ponto."** O campo **Bate ponto** dele está
  desligado, ou o vínculo é PJ/terceiro. Edite o cadastro e ative "Bate ponto".
- **"Um prestador PJ não deixa cadastrar aqui."** É proposital: PJ vai em
  **Estrutura Organizacional → Prestadores de Serviços**, não em Colaboradores.
- **"O CPF foi recusado."** O sistema valida o **dígito verificador**. Confira os
  números; nos testes, use a faixa fictícia **900.000.0XX**.
- **"A importação recusou linhas."** Faltou uma coluna obrigatória (Nome, CPF,
  Data de Nascimento, Cargo, Departamento, Data de Admissão) ou o CPF é
  inválido. A pré-visualização mostra o motivo em cada linha vermelha.
- **"Não consigo desligar a pessoa."** Pode haver **estabilidade ativa** ou o
  **exame demissional (NR-7)** ainda não preenchido — a tela lista o que está
  bloqueando.
- **"Excluí sem querer?"** A exclusão pede confirmação por digitação (EXCLUIR /
  EXCLUIR TUDO). Para não correr esse risco, use **Inativar**, que preserva
  tudo e é reversível.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/colaboradores_gestao-de-colaboradores.md` no
   projeto.
2. Confira se o passo a passo, os benefícios e os marcadores de print refletem
   como você quer conduzir os vídeos deste módulo.
3. Se quiser, cruze cada print com a tela real no **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
   Alves**, empresa **Empresa Staging LTDA**, em **Estrutura Organizacional →
   Colaboradores** — capturando sempre com dados fictícios (personas e CPFs da
   faixa 900.000.0XX).
