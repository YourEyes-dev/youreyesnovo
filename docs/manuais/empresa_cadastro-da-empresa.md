# Manual do módulo — Cadastro da Empresa

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e no mesmo nível de profundidade do piloto aprovado
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial.

- **Onde fica no menu:** seção **Estrutura Organizacional → Empresa** (rota `/empresa`).
- **Para quem é:** RH, Departamento Pessoal (DP), SST e gestores que cuidam do
  cadastro legal das empresas atendidas.
- **Em uma frase:** é o **cadastro central** de cada empresa (matriz ou filial) —
  dados e CNPJ, enquadramento legal (CNAE, grau de risco, SESMT, CIPA), cotas de
  inclusão, indicadores previdenciários, **jornada e turnos** (inclusive o
  interruptor "utiliza controle de ponto") e o contexto que alimenta a I.A.
- **Importante:** o YourEyes é **multiempresa**. Tudo o que os outros módulos
  fazem (ponto, saúde, obrigações, financeiro) depende de a empresa estar
  cadastrada aqui primeiro. Este é o ponto de partida da plataforma.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Uma base só para todo o grupo.** Cadastre matrizes, filiais e
  estabelecimentos e organize-os em **grupos econômicos** — o sistema entende a
  hierarquia e o restante da plataforma passa a respeitá-la.
- **Cadastro que se preenche sozinho.** Digite o **CNPJ** e clique na lupa: razão
  social, nome fantasia, endereço, CNAE e contatos vêm da **Receita Federal**. O
  **CEP** completa o endereço automaticamente. Menos digitação, menos erro.
- **Conformidade calculada, não adivinhada.** A partir do CNAE, o sistema já
  sugere o **grau de risco (NR-04)**; a partir do total de colaboradores, calcula
  a **cota de PCD (Lei 8.213/91)**; e aponta quando **SESMT** e **CIPA** são
  obrigatórios. As regras legais deixam de depender da memória de alguém.
- **Obrigações viram plano de ação.** O que o cadastro detecta (SESMT ausente,
  CIPA não constituída, déficit de PCD, TAC ativo…) pode virar, com um clique, um
  **Plano de Ação 5W2H** com responsável, prazo e evidências.
- **A chave que liga o Ponto.** É aqui, na aba **Jornada e Turnos**, que se liga
  o **"utiliza controle de ponto"** — o interruptor que coloca a empresa no
  módulo de ponto eletrônico. Empresas com mais de 20 empregados são sinalizadas
  como **obrigadas** ao controle de jornada (CLT art. 74, §2º).
- **I.A. que conhece a empresa.** O campo de **contexto para I.A.** faz todas as
  ferramentas inteligentes do sistema darem respostas sob medida, e não
  genéricas.
- **Checklist que não deixa buraco.** Uma aba mostra, campo a campo, o que ainda
  falta preencher — separando obrigatório de opcional.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Multiempresa** | O sistema guarda várias empresas ao mesmo tempo; você alterna entre elas pelo seletor no cabeçalho. |
| **Matriz / Filial** | Matriz é a empresa detentora do CNPJ base; filial é a unidade vinculada a uma matriz. |
| **Grupo econômico** | Um "guarda-chuva" que junta empresas do mesmo dono/holding. |
| **CNAE** | O código da atividade econômica da empresa (o que ela faz). |
| **Grau de risco (NR-04)** | Escala de 1 a 4 que mede o risco da atividade; puxa obrigações de SST. Sai automaticamente do CNAE. |
| **SESMT (NR-04)** | Serviço especializado de segurança e medicina do trabalho; obrigatório conforme risco e nº de empregados. |
| **CIPA (NR-05)** | Comissão Interna de Prevenção de Acidentes. |
| **Cota PCD (Lei 8.213/91)** | Percentual de vagas para pessoas com deficiência, exigido de empresas com 100+ empregados. |
| **Jovem Aprendiz (CLT art. 429)** | Cota de aprendizes para empresas com 7+ empregados. |
| **FAP** | Fator Acidentário de Prevenção: multiplicador (0,5 a 2,0) que aumenta ou reduz a contribuição do RAT. |
| **TAC** | Termo de Ajustamento de Conduta firmado com órgãos como o Ministério Público. |
| **Utiliza controle de ponto** | O interruptor que coloca a empresa no módulo de Ponto Eletrônico. |
| **Tabela de feriados** | Calendário de feriados vinculado à unidade; prevalece na apuração do ponto. |
| **Contexto para I.A.** | Texto livre sobre a empresa que orienta todas as ferramentas de inteligência artificial. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Estar logado com um perfil que gerencia empresas** (no ambiente de teste,
   **Marina Alves**, Analista de RH).
2. **Ter o CNPJ (ou CPF, para empregador pessoa física) em mãos** — a busca
   automática na Receita Federal parte dele.
3. Para vincular **filial a matriz**: a **matriz precisa já estar cadastrada e
   ativa**.
4. Para ligar o **"utiliza controle de ponto"**: o **módulo de Ponto precisa
   estar incluído no plano** do cliente — caso contrário o interruptor aparece
   bloqueado com o selo "não incluído no plano".

---

## 4. Mapa da tela (visão de 30 segundos)

O módulo tem **duas telas**:

**A) Lista de empresas** (tela inicial). Título **"Empresas"**, um aviso
**"Sistema Multiempresa"**, quatro cartões de indicadores (**Total, Ativas,
Inativas, GR ≥ 3**), uma barra de busca com filtros (**Status, UF, Grau de
Risco, Grupo**) e os botões **Exportar**, **Importar** e **Nova Empresa**. Abaixo,
a tabela com uma linha por empresa.

**B) Cadastro da empresa** (ao clicar em uma linha ou em "Nova Empresa"). No topo,
a seta **Voltar**, o título e o botão **Salvar** (o salvamento é **manual** — uma
faixa avisa quando há alterações não gravadas). O cadastro é dividido em **8
abas**:

| Aba | Para que serve |
|---|---|
| **Dados** | Identificação: hierarquia/grupo, tipo de empregador, CNPJ, endereço, contatos, total de colaboradores. |
| **Enquadramento** | CNAE, grau de risco, SESMT e CIPA. |
| **Inclusão** | Cotas de PCD e de Jovem Aprendiz. |
| **Indicadores** | FAP e TAC. |
| **Jornada** | Jornada, turnos, "utiliza controle de ponto", condições especiais e tabela de feriados. |
| **Obrigações** | Obrigações legais detectadas automaticamente a partir do cadastro. |
| **Contexto I.A.** | Texto que orienta as ferramentas de inteligência artificial. |
| **Checklist** | O que ainda falta preencher, campo a campo. |

No rodapé do cadastro há a navegação **← Anterior / Próxima aba → / Salvar**.

> 📸 **PRINT 01 — Lista de empresas (tela inicial)**
> **Onde:** menu **Estrutura Organizacional → Empresa**.
> **O que precisa aparecer:** título "Empresas", o aviso "Sistema Multiempresa",
> os quatro cartões de indicadores, a barra de filtros e a tabela com as colunas
> (Razão Social, CNPJ/CPF, Tipo, Grupo, CNAE, Colaboradores, GR, Status, Ações).
> **Dados fictícios na tela:** linha da **Empresa Staging LTDA**, CNPJ fictício
> **90.000.000/0001-91**, tipo **Matriz**, GR **3**, status **Ativa**.
> **Ação filmada:** panorâmica lenta da tela, terminando no botão **Nova Empresa**.

---

## 5. Passo a passo por fluxo

> Observação de gravação: este módulo **não tem** botão de "Guia Rápido" embutido
> (diferente do módulo de Ponto). A sequência abaixo é a ordem natural das 8 abas,
> de cima para baixo — grave nessa ordem.

### Fluxo 1 — Conhecer a lista e criar uma nova empresa

**Objetivo:** entrar no cadastro de uma empresa nova.
**Benefício:** em um clique começa o cadastro, e a lista dá o panorama de todo o
grupo.

1. Abra **Estrutura Organizacional → Empresa**.
2. Observe os cartões (Total, Ativas, Inativas, GR ≥ 3) e use os **filtros** e a
   **busca** para localizar uma empresa (a busca aceita razão social, nome
   fantasia, cidade ou CNPJ/CPF).
3. Para editar, **clique na linha** da empresa. Para começar do zero, clique em
   **Nova Empresa**.

> 💡 Cada linha traz atalhos à direita: **Editar**, **Ativar/Inativar** e (para
> quem tem alçada) **Excluir**. Empresas com mais de 20 colaboradores exibem o
> selo **"ponto obrigatório"** na coluna Colaboradores.

---

### Fluxo 2 — Dados básicos e busca automática pelo CNPJ

**Objetivo:** preencher a identificação da empresa.
**Benefício:** com o CNPJ, o grosso do cadastro se completa sozinho pela Receita
Federal; o CEP completa o endereço.

1. Na aba **Dados**, escolha o **Tipo de Empregador**: **Pessoa Jurídica (CNPJ)**
   ou **Pessoa Física (CPF)**.
2. Digite o **CNPJ** e clique na **lupa** ("Buscar dados na Receita Federal") —
   razão social, nome fantasia, endereço, CNAE, e-mail e telefone são preenchidos
   automaticamente.
3. Confira/complete **Razão Social**, **Nome Fantasia**, **Inscrição Estadual** e
   **Municipal**.
4. Preencha **Telefone**, **E-mail** e **Website**.
5. No bloco **Endereço**, digite o **CEP**: logradouro, bairro, cidade e estado
   vêm preenchidos. Ajuste **Número** e **Complemento**.
6. Informe o **Total de Colaboradores** — esse número alimenta os cálculos de
   **CIPA, PCD e Jovem Aprendiz**.

> 📸 **PRINT 02 — Aba Dados com busca de CNPJ**
> **Onde:** Cadastro da empresa → aba **Dados**.
> **O que precisa aparecer:** o seletor de tipo de empregador, o campo CNPJ com a
> lupa, os campos de razão social/endereço já preenchidos e o campo Total de
> Colaboradores.
> **Dados fictícios na tela:** **Empresa Staging LTDA**, CNPJ
> **90.000.000/0001-91**, cidade **São Paulo/SP**, total de colaboradores **150**.
> **Ação filmada:** digitar o CNPJ e clicar na lupa; mostrar os campos se
> preenchendo sozinhos.

> 💡 Para empregador **Pessoa Física** aparecem os campos **CPF**, **CEI** e
> **CAEPF** no lugar do CNPJ. Use sempre CPF fictício da casa (faixa
> **900.000.0XX**).

---

### Fluxo 3 — Hierarquia e grupo econômico (matriz e filial)

**Objetivo:** posicionar a empresa na estrutura do grupo.
**Benefício:** o sistema passa a tratar matrizes e filiais corretamente e reúne
empresas do mesmo dono sob um grupo.

1. Ainda na aba **Dados**, no bloco **Hierarquia e Grupo Econômico**, escolha o
   **Grupo Econômico** (ou clique em **Incluir novo grupo** para criar um na
   hora, informando nome e descrição).
2. Defina o **Tipo de Unidade**: **Matriz** ou **Filial**.
3. Se for **Filial**, selecione a **Matriz de Referência** (a empresa detentora
   do CNPJ base). Ao escolher a matriz, o grupo econômico dela é herdado
   automaticamente.

> 📸 **PRINT 03 — Hierarquia e grupo econômico**
> **Onde:** aba **Dados**, bloco **Hierarquia e Grupo Econômico** (com o diálogo
> "Novo Grupo Econômico" aberto).
> **O que precisa aparecer:** os campos Grupo Econômico, Tipo de Unidade e Matriz
> de Referência, e o diálogo de criação de grupo.
> **Dados fictícios na tela:** grupo **"Grupo Staging"**, tipo **Filial**, matriz
> de referência **Empresa Staging LTDA**.
> **Ação filmada:** abrir o seletor de grupo, clicar em "Incluir novo grupo",
> digitar o nome e criar.

---

### Fluxo 4 — Enquadramento legal (CNAE, grau de risco, SESMT, CIPA)

**Objetivo:** registrar o enquadramento de SST da empresa.
**Benefício:** o grau de risco sai automático do CNAE e o sistema aponta quando
SESMT e CIPA são obrigatórios, com alertas visuais.

1. Na aba **Enquadramento**, confira o **CNAE Principal** e a **descrição** (já
   vêm da busca do CNPJ).
2. Veja o **Grau de Risco** — preenchido automaticamente pelo CNAE (NR-04). Grau
   3 ou 4 mostra o alerta **"Risco elevado – obrigações adicionais"**.
3. No bloco **SESMT**, ligue **SESMT Obrigatório** quando for o caso e defina a
   **Situação** (Próprio / Terceirizado / Inexistente). Obrigatório e inexistente
   dispara um **Alerta Crítico**.
4. No bloco **CIPA**, ligue **CIPA Obrigatória**, defina a **Situação**
   (Não Constituída / Em Implantação / Ativa) e, se ativa, as **datas do mandato**.

> 📸 **PRINT 04 — Aba Enquadramento**
> **Onde:** Cadastro da empresa → aba **Enquadramento**.
> **O que precisa aparecer:** CNAE e descrição, o Grau de Risco selecionado, e os
> blocos SESMT e CIPA com seus interruptores e situações.
> **Dados fictícios na tela:** CNAE **4120-4/00 — Construção de edifícios**, grau
> de risco **3** (com o selo de risco elevado), SESMT **Terceirizado**, CIPA
> **Ativa**.

> 💡 O selo vermelho de alerta (SESMT/CIPA obrigatório e não constituído) é um
> ótimo gancho de comercial: mostra o sistema **apontando o risco** antes da
> fiscalização.

---

### Fluxo 5 — Obrigações de inclusão (PCD e Jovem Aprendiz)

**Objetivo:** acompanhar as cotas legais de inclusão.
**Benefício:** a cota de PCD é calculada sozinha pela faixa de colaboradores, e o
sistema mostra o déficit em barra de progresso.

1. Na aba **Inclusão**, ligue **Cota PCD Obrigatória** (empresas com 100+
   empregados já entram como obrigatórias).
2. Confira o **% Exigido** e a **Qtd. Exigida** — calculados automaticamente pelo
   total de colaboradores (Lei 8.213/91: de 2% a 5%).
3. Informe a **Qtd. Atual** de PCDs contratados; a barra mostra o **progresso** e
   o **déficit**, se houver.
4. No bloco **Jovem Aprendiz** (CLT art. 429), ligue **Obrigatória** e informe as
   quantidades **mínima**, **máxima** e **atual** (aqui o preenchimento é manual).

> 📸 **PRINT 05 — Aba Inclusão (Cota PCD)**
> **Onde:** Cadastro da empresa → aba **Inclusão**.
> **O que precisa aparecer:** o cálculo automático da cota PCD (%, qtd exigida,
> qtd atual), a barra de progresso e o bloco de Jovem Aprendiz.
> **Dados fictícios na tela:** 150 colaboradores → **2%** → **3 PCD exigidos**,
> **1 atual**, barra em déficit; Jovem Aprendiz mínima **8**, atual **5**.

> 💡 O cálculo depende do **Total de Colaboradores** preenchido na aba **Dados**.
> Se estiver zerado, o sistema avisa e pede para completar lá primeiro.

---

### Fluxo 6 — Indicadores previdenciários (FAP e TAC)

**Objetivo:** registrar o FAP e eventuais Termos de Ajustamento de Conduta.
**Benefício:** o FAP é classificado automaticamente (Bônus/Neutro/Malus) e os
TACs ficam organizados, com histórico de arquivamento.

1. Na aba **Indicadores**, informe o **FAP Atual** (faixa legal 0,5000 a 2,0000).
   O sistema classifica: **Bônus** (< 1), **Neutro** (= 1) ou **Malus** (> 1,
   com alerta de RAT majorado).
2. Ligue **Possui TAC ativo?** para habilitar a lista de TACs.
3. Clique em **Adicionar TAC** e preencha **Nº/Identificador**, **Órgão
   Emissor**, **Data de Assinatura**, **Obrigações/Cláusulas**, **Prazo**,
   **Status** e **Penalidades**.
4. Use as abas **Ativos** e **Arquivados** para organizar; um TAC pode ser
   **arquivado** (preserva histórico) ou excluído.

> 📸 **PRINT 06 — Aba Indicadores (FAP e TAC)**
> **Onde:** Cadastro da empresa → aba **Indicadores**.
> **O que precisa aparecer:** o campo FAP com o selo de classificação e a lista
> de TACs (abas Ativos/Arquivados) com o botão Adicionar TAC.
> **Dados fictícios na tela:** FAP **1,3500** (selo **Malus – RAT majorado**);
> um TAC ativo **"TAC 123/2026"**.

> 📸 **PRINT 07 — Modal "Adicionar TAC"**
> **Onde:** aba **Indicadores** → botão **Adicionar TAC**.
> **O que precisa aparecer:** o formulário do TAC (identificador, órgão emissor,
> data, obrigações, prazo, status, penalidades).
> **Dados fictícios na tela:** nº **TAC 123/2026**, órgão **Ministério Público do
> Trabalho (MPT)**, status **Em cumprimento**, prazo **12 meses**.

> 💡 As cláusulas de cada TAC podem virar ações de cumprimento pela aba
> **Obrigações** (próximo fluxo).

---

### Fluxo 7 — Jornada e turnos (o interruptor do Ponto) e condições especiais

**Objetivo:** definir a jornada, ligar o controle de ponto e sinalizar condições
especiais de trabalho.
**Benefício:** é aqui que a empresa entra (ou não) no módulo de Ponto — e onde se
sinalizam riscos que geram obrigações de saúde e treinamento.

1. Na aba **Jornada**, ligue **Utiliza controle de ponto** para colocar a empresa
   no módulo de Ponto (ela passa a aparecer no seletor do Ponto e a gerar falta
   nos dias úteis sem marcação). Desligado, fica de fora — sem lançar falta
   indevida.
2. Escolha a **Jornada Padrão** na lista (44h, 40h, 12x36, 6x1, tempo parcial…)
   ou descreva uma **personalizada**.
3. Ligue **Possui 3º Turno (Noturno)** e/ou **Escalas Especiais** se houver (o 3º
   turno exibe o aviso de avaliações de saúde e ergonomia — NR-17).
4. No bloco **Condições Especiais de Trabalho**, ligue o que se aplica:
   **Trabalho em Altura (NR-35)**, **Espaço Confinado (NR-33)**, **Insalubridade
   (NR-15)**, **Periculosidade (NR-16)**, **Aposentadoria Especial**.
5. Em **Tabela de feriados vinculada** (aparece após salvar a unidade), escolha a
   tabela ou clique em **Aplicar sugestão** quando o sistema sugerir uma pelo
   município.

> 📸 **PRINT 08 — Aba Jornada com "Utiliza controle de ponto"**
> **Onde:** Cadastro da empresa → aba **Jornada**.
> **O que precisa aparecer:** o interruptor **Utiliza controle de ponto** ligado
> (destacado), a Jornada Padrão selecionada e os cartões de Condições Especiais.
> **Dados fictícios na tela:** ponto **ligado** (com o selo **obrigatório** por
> ter mais de 20 empregados), jornada **44h semanais — 8h diárias (seg a sex) +
> 4h sábado**, condição **Trabalho em Altura (NR-35)** ativa.
> **Ação filmada:** ligar o interruptor "Utiliza controle de ponto" e mostrar o
> cartão mudando de cor.

> 📸 **PRINT 09 — Tabela de feriados vinculada**
> **Onde:** aba **Jornada**, bloco **Tabela de feriados vinculada** (empresa já
> salva).
> **O que precisa aparecer:** o seletor de tabela e a sugestão automática pelo
> município, com o botão **Aplicar sugestão**.
> **Dados fictícios na tela:** sugestão **"São Paulo/SP"**, botão Aplicar
> sugestão visível.

> 💡 O selo **"não incluído no plano"** aparece quando o cliente não contratou o
> módulo de Ponto — nesse caso o interruptor fica bloqueado (é proposital).

---

### Fluxo 8 — Obrigações detectadas viram plano de ação

**Objetivo:** transformar o que o cadastro apontou em tarefas com responsável e
prazo.
**Benefício:** nada de obrigação legal esquecida numa planilha — cada item vira
um Plano de Ação 5W2H acompanhável.

1. Na aba **Obrigações**, veja quantas obrigações foram **detectadas** a partir
   do cadastro.
2. Clique em **Gerar Obrigações** para registrar as que ainda não estão na lista.
3. Em cada obrigação, clique em **Criar Ação** para gerar um plano no módulo
   **Planejamento e Cultura → Plano de Ação** (ou **Abrir Ação**, se já existir).
4. Ajuste o **status** (Pendente / Conforme / Não Conforme / Em Adequação) e
   ative/inative itens conforme o caso.

> 📸 **PRINT 10 — Aba Obrigações detectadas**
> **Onde:** Cadastro da empresa → aba **Obrigações**.
> **O que precisa aparecer:** a barra "X obrigação(ões) detectada(s)" com o botão
> **Gerar Obrigações**, e os cartões de obrigações com **Criar Ação** e o selo de
> criticidade/status.
> **Dados fictícios na tela:** obrigação **"CIPA obrigatória — constituir
> comissão"**, criticidade **Alta**, status **Pendente**.

> 💡 A criticidade aparece como uma barra colorida à esquerda do cartão (do
> cinza ao vermelho) — bom recurso visual para o vídeo.

---

### Fluxo 9 — Contexto para a Inteligência Artificial

**Objetivo:** ensinar a I.A. sobre a empresa.
**Benefício:** todas as ferramentas de I.A. do sistema passam a dar respostas sob
medida, e não genéricas.

1. Na aba **Contexto I.A.**, clique em **Adicionar Contexto** (ou **Editar**).
2. Descreva setor, porte, cultura, objetivos estratégicos e referências internas
   (até 3.000 caracteres).
3. Clique em **Salvar Contexto**.

> 📸 **PRINT 11 — Aba Contexto I.A.**
> **Onde:** Cadastro da empresa → aba **Contexto I.A.**.
> **O que precisa aparecer:** o cartão explicativo e o editor de contexto (ou o
> contexto já salvo, com o contador de caracteres).
> **Dados fictícios na tela:** texto exemplo "Empresa de construção civil de
> médio porte, forte cultura de segurança…", contador **~180/3.000**.

---

### Fluxo 10 — Checklist e salvar o cadastro

**Objetivo:** conferir o que falta e gravar tudo.
**Benefício:** o checklist não deixa passar campo obrigatório, e o salvamento
manual evita gravações acidentais.

1. Abra a aba **Checklist** e veja o percentual de **obrigatórios preenchidos** e
   a **completude geral**.
2. Clique em qualquer **pendência** para ir direto ao campo correspondente.
3. Clique em **Salvar** (no topo ou no rodapé). A faixa de aviso confirma
   **"Tudo salvo no banco de dados"**.

> 📸 **PRINT 12 — Aba Checklist do cadastro**
> **Onde:** Cadastro da empresa → aba **Checklist**.
> **O que precisa aparecer:** as barras de progresso (obrigatórios e completude
> geral), os cartões por aba e a lista de campos pendentes clicáveis.
> **Dados fictícios na tela:** obrigatórios **12/14**, completude geral **78%**,
> duas pendências destacadas.

> 💡 O salvamento é **manual**. Enquanto houver mudança não gravada, a faixa fica
> âmbar com "⚠️ Você tem alterações não salvas". Lembre de clicar em **Salvar**.

---

### Fluxo 11 — Alternar a empresa ativa (seletor no cabeçalho)

**Objetivo:** trocar qual empresa está em foco no resto do sistema.
**Benefício:** com um clique, todos os módulos passam a operar sobre a empresa
escolhida — a essência do multiempresa.

1. No **cabeçalho** (topo da página), abra o **seletor de empresa**.
2. Escolha a empresa desejada na lista.

> 📸 **PRINT 13 — Seletor de empresa (cabeçalho)**
> **Onde:** topo da tela, ao lado do título (componente de seleção de empresa).
> **O que precisa aparecer:** o seletor aberto com a lista de empresas.
> **Dados fictícios na tela:** **Empresa Staging LTDA** selecionada e uma filial
> na lista.
> **Ação filmada:** abrir o seletor e trocar de empresa.

---

### Fluxo 12 — Importar e exportar empresas

**Objetivo:** cadastrar muitas empresas de uma vez ou levar os dados para fora.
**Benefício:** carga em lote via planilha e relatórios prontos em Excel ou PDF.

1. Na **lista de empresas**, clique em **Importar** para abrir o assistente
   (baixe o modelo, preencha e envie o Excel/CSV).
2. Para exportar, clique em **Exportar** e escolha **Planilha (.xlsx)** ou
   **PDF** — o arquivo respeita os filtros aplicados na lista.

> 📸 **PRINT 14 — Importar / Exportar empresas**
> **Onde:** lista de empresas → botões **Importar** e **Exportar**.
> **O que precisa aparecer:** o menu de exportação (Planilha/PDF) e/ou o diálogo
> "Importar Empresas" com a opção de baixar o modelo.
> **Dados fictícios na tela:** exportação de **3 empresas** filtradas.

> 💡 Empresas com colaboradores ou terceiros vinculados **não** são excluídas —
> a validação do banco bloqueia, protegendo o histórico.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, mostrando dor → solução → prova. Empresa e dados fictícios.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Cadastrar empresa ainda é copiar CNPJ de um lado para o outro?"* Abre com uma planilha confusa. | Imagem genérica de planilha |
| 8–22s | *"No YourEyes você digita o CNPJ e o cadastro se completa sozinho — direto da Receita Federal."* | **PRINT 02** (busca de CNPJ) |
| 22–38s | *"E ele já entende a lei: grau de risco, SESMT, CIPA e a cota de PCD, calculados automaticamente."* | **PRINT 04** (enquadramento) + **PRINT 05** (cota PCD) |
| 38–52s | *"Precisa de ponto eletrônico? É um clique para ligar o controle de jornada."* | **PRINT 08** (utiliza controle de ponto) |
| 52–66s | *"Cada obrigação vira um plano de ação com responsável e prazo."* | **PRINT 10** (obrigações → ação) |
| 66–80s | *"Matrizes, filiais e grupos, tudo numa base só. YourEyes: sua estrutura, organizada."* Logo. | **PRINT 01** (lista) + tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 5–8 min)

Ordem de gravação = ordem das abas, de cima para baixo. Narração em primeira
pessoa ("vamos cadastrar…", "agora eu ligo o ponto…").

1. **Abertura** — a lista de empresas e o conceito multiempresa (**PRINT 01**).
2. **Nova empresa: dados e busca de CNPJ** (**PRINT 02**).
3. **Hierarquia e grupo econômico** — matriz, filial, grupo (**PRINT 03**).
4. **Enquadramento legal** — CNAE, grau de risco, SESMT, CIPA (**PRINT 04**).
5. **Obrigações de inclusão** — PCD e Jovem Aprendiz (**PRINT 05**).
6. **Indicadores** — FAP e cadastro de um TAC (**PRINT 06, 07**).
7. **Jornada e turnos** — ligar o ponto, condições especiais e feriados
   (**PRINT 08, 09**).
8. **Obrigações detectadas** — gerar e criar ação (**PRINT 10**).
9. **Contexto para I.A.** (**PRINT 11**).
10. **Checklist e salvar** (**PRINT 12**).
11. **Trocar a empresa ativa** pelo seletor do cabeçalho (**PRINT 13**).
12. **Importar/exportar** empresas (**PRINT 14**).
13. **Encerramento** — reforçar que este cadastro é a base de todos os módulos.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Lista de empresas (tela inicial)
- [ ] **PRINT 02** — Aba Dados com busca de CNPJ
- [ ] **PRINT 03** — Hierarquia e grupo econômico
- [ ] **PRINT 04** — Aba Enquadramento (CNAE, SESMT, CIPA)
- [ ] **PRINT 05** — Aba Inclusão (Cota PCD)
- [ ] **PRINT 06** — Aba Indicadores (FAP e TAC)
- [ ] **PRINT 07** — Modal Adicionar TAC
- [ ] **PRINT 08** — Aba Jornada (Utiliza controle de ponto)
- [ ] **PRINT 09** — Tabela de feriados vinculada
- [ ] **PRINT 10** — Aba Obrigações detectadas
- [ ] **PRINT 11** — Aba Contexto I.A.
- [ ] **PRINT 12** — Aba Checklist do cadastro
- [ ] **PRINT 13** — Seletor de empresa (cabeçalho)
- [ ] **PRINT 14** — Importar / Exportar empresas

---

## 9. Erros comuns / dúvidas frequentes

- **"Cliquei na lupa e não veio nada."** O CNPJ precisa ter 14 dígitos e ser
  válido; confira a digitação. Se persistir, o CNPJ pode não constar na base da
  Receita — preencha manualmente.
- **"A cota de PCD está zerada."** Falta o **Total de Colaboradores** na aba
  **Dados** — é ele que dispara o cálculo automático.
- **"O interruptor 'utiliza controle de ponto' está bloqueado."** O módulo de
  Ponto não faz parte do plano do cliente (selo "não incluído no plano").
- **"O botão Salvar está desabilitado."** Faltam campos mínimos: **Razão
  Social/Nome** e **CNPJ** (PJ) ou **CPF** (PF). Preencha-os para liberar.
- **"Não consigo vincular a filial."** A **matriz precisa estar cadastrada e
  ativa** antes; só então ela aparece na lista de "Matriz de Referência".
- **"Não consigo excluir a empresa."** Empresas com colaboradores ou terceiros
  vinculados são bloqueadas na exclusão, de propósito, para preservar o
  histórico. Considere **inativar** em vez de excluir.
- **"Perdi o que estava digitando?"** O cadastro guarda um **rascunho** local
  automaticamente enquanto você preenche; ao voltar, ele oferece restaurar. Ainda
  assim, clique em **Salvar** para gravar de fato no banco.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/empresa_cadastro-da-empresa.md` no projeto.
2. Se quiser conferir cada tela citada, acesse o **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
   Alves**, e navegue em **Estrutura Organizacional → Empresa** seguindo os
   fluxos e os marcadores de print.
3. Confirme se o passo a passo, os benefícios e os prints refletem como você quer
   conduzir os vídeos. Aprovado o formato, sigo o mesmo padrão para os próximos
   módulos.
