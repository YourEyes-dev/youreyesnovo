# Manual do módulo — Cadastros de Estrutura (Estabelecimentos/Obras, Departamentos e Cargos)

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e na profundidade do piloto aprovado
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial.

- **Onde fica no menu:** seção **Estrutura Organizacional**. Este manual cobre os
  **três** itens dessa seção, cada um com tela própria:
  - **Estabelecimentos / Obras** — `/cadastros/filiais`
  - **Departamentos** — `/cadastros/departamentos`
  - **Cargos** — `/cadastros/cargos`
- **Para quem é:** RH, Departamento Pessoal (DP) e gestores que montam a
  estrutura da empresa antes de admitir pessoas.
- **Em uma frase:** desenha o "esqueleto" da organização — **onde** as pessoas
  trabalham (estabelecimentos e obras), **em que área** (departamentos, com
  gestor responsável) e **em que função** (cargos, com nível, faixa salarial e
  condições especiais de SST) — para que todos os outros módulos (ponto, saúde
  ocupacional, admissões, financeiro) tenham em que se apoiar.
- **Importante:** este é um módulo de **fundação**. Sem estabelecimento,
  departamento e cargo cadastrados, a admissão de um colaborador fica sem onde
  encaixá-lo. Recomenda-se cadastrar nesta ordem: **1) Estabelecimento/Obra →
  2) Departamento → 3) Cargo**.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Uma estrutura, todos os módulos.** O estabelecimento, o departamento e o
  cargo cadastrados aqui reaparecem prontos na admissão, no ponto, na saúde
  ocupacional e no financeiro — cadastra-se **uma vez** e a informação circula
  por todo o sistema.
- **Endereço sem digitação.** No estabelecimento ou obra, basta digitar o **CEP**
  e o sistema preenche cidade, estado e logradouro sozinho — menos erro, mais
  rapidez.
- **Obra é diferente de escritório — e o sistema sabe disso.** Locais fixos
  (sede, unidade, depósito) e locais temporários (canteiros, reformas) são
  tratados como tipos distintos; a obra ganha o campo **CNO** (Cadastro Nacional
  de Obras) que a fiscalização exige.
- **Cada departamento com dono.** Ao indicar o **gestor responsável**, o sistema
  **cria o acesso dele automaticamente** (login e senha inicial), sem o RH ter de
  abrir chamado — e ainda prevê o **substituto** para licenças e férias.
- **Cargo que já nasce em conformidade com a SST.** Insalubridade,
  periculosidade e aposentadoria especial ficam registradas no cargo, com base
  técnica (NR-15/NR-16), e os adicionais são **herdados automaticamente** por
  quem for admitido naquele cargo.
- **Regra legal aplicada sozinha.** Quando um cargo tem insalubridade **e**
  periculosidade ao mesmo tempo, o sistema aplica a **regra de prevalência**
  (art. 193, §2º da CLT) — paga o mais vantajoso, sem cumular.
- **Montagem em lote.** Cargos, departamentos e colaboradores podem entrar de uma
  vez por **importação de planilha**, acelerando a implantação de empresas
  inteiras.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Matriz** | A empresa "mãe" (com CNPJ). É dela que penduramos os estabelecimentos e obras. |
| **Estabelecimento** | Local **fixo** da empresa: sede, unidade, escritório, depósito/galpão. |
| **Obra** | Local **temporário** de prestação de serviço: canteiro, reforma. Tem campo **CNO**. |
| **CNO** | Cadastro Nacional de Obras — o "CNPJ da obra" exigido pela Receita/fiscalização. |
| **Departamento** | A área/setor onde as pessoas trabalham (RH, Operações, Financeiro…). Pode ser vinculado a um estabelecimento/obra ou à empresa como um todo. |
| **Gestor responsável** | O colaborador que responde pelo departamento (aprova, acompanha). Ao ser indicado, ganha acesso ao sistema automaticamente. |
| **Substituto** | Quem assume o departamento quando o gestor titular está afastado. Só "vale" enquanto o RH marca que ele **está atuando agora**. |
| **Cargo** | A função exercida (ex.: Analista de RH, Operador de Produção). Guarda nível, faixa salarial e condições de SST. |
| **Nível** | A senioridade do cargo: estagiário, júnior, pleno, sênior, especialista, coordenador, gerente, diretor. |
| **Insalubridade** | Exposição a agente nocivo (NR-15). Gera adicional de 10% / 20% / 40% (grau mínimo/médio/máximo). |
| **Periculosidade** | Exposição a risco (NR-16: inflamáveis, eletricidade, explosivos…). Adicional fixo de 30% (art. 193 CLT). |
| **Aposentadoria especial** | Enquadramento previdenciário (15/20/25 anos) informado ao eSocial (evento S-2240). |
| **CBO** | Classificação Brasileira de Ocupações — o código oficial da ocupação (ex.: `2524-05`). No YourEyes ele é escolhido na **ficha do colaborador / na admissão** (busca por código ou título), para o eSocial. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Uma empresa (Matriz) cadastrada**, com CNPJ. Os estabelecimentos e obras são
   sempre pendurados numa empresa.
2. **Estar logado como quem opera o RH** — nas gravações, **Marina Alves**
   (Analista de RH).
3. Para provisionar gestor de departamento e para resetar senha, é preciso ter
   permissão de **gestor/administrador** (papel *manager* ou acima).
4. **Ordem recomendada de cadastro:** estabelecimento/obra → departamento →
   cargo. Assim, quando você for criar o departamento, já existirá o
   estabelecimento para vincular; e quando for criar o cargo, já existirá o
   departamento.

> 💡 Antes de gravar, confirme que a empresa em uso é a **Empresa Staging LTDA** —
> ela aparece no seletor de empresa e no topo das telas.

---

## 4. Mapa da tela (visão de 30 segundos)

A seção **Estrutura Organizacional** no menu lateral tem três entradas. Todas
seguem o mesmo desenho: um **título**, um **campo de busca**, uma **tabela** com a
lista e um botão para **criar um novo registro** (no canto superior direito). As
edições acontecem em **janelas (formulários)** que abrem por cima da tela.

| Tela | Abre em | Para que serve |
|---|---|---|
| **Estabelecimentos / Obras** | `/cadastros/filiais` | Primeiro você escolhe a empresa; depois gerencia os locais (fixos e temporários) dela. |
| **Departamentos** | `/cadastros/departamentos` | Cadastra as áreas, define o gestor e o substituto de cada uma. |
| **Cargos** | `/cadastros/cargos` | Cadastra as funções, com nível, faixa salarial e condições especiais de SST. |

> **Observação para quem for gravar:** estas telas **não têm** botão de "Guia
> Rápido" embutido (diferente do módulo Ponto). O passo a passo abaixo é o
> roteiro completo.

---

## 5. Passo a passo por fluxo

O manual está dividido em **três blocos**, um por tela. A numeração dos prints é
**única e sequencial** cobrindo os três blocos.

---

## BLOCO A — Estabelecimentos / Obras (`/cadastros/filiais`)

### Fluxo A1 — Escolher a empresa

**Objetivo:** dizer ao sistema de qual empresa você vai gerenciar os locais.
**Benefício:** cada empresa (Matriz) tem sua própria lista de estabelecimentos e
obras, sem misturar.

1. Abra **Estrutura Organizacional → Estabelecimentos / Obras**.
2. Leia o cartão azul que explica a diferença entre **Estabelecimento** (locais
   fixos) e **Obra** (locais temporários).
3. Se houver várias empresas, use o campo **"Buscar por CNPJ da empresa…"**.
4. Clique no **cartão da empresa** desejada — ele mostra o CNPJ, a cidade e
   quantos registros já existem.

> 📸 **PRINT 01 — Seleção de empresa**
> **Onde:** Estrutura Organizacional → **Estabelecimentos / Obras** (primeira
> tela).
> **O que precisa aparecer:** o cartão explicativo "O que é Estabelecimento ou
> Obra?", o campo de busca por CNPJ e o cartão da empresa com o contador de
> registros.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**, CNPJ fictício,
> selo **"3 registros"**.
> **Ação filmada:** clicar no cartão da Empresa Staging LTDA para entrar.

> 💡 Se a empresa já estiver **ativa/selecionada** no topo do sistema, o passo de
> escolha é pulado e você já cai direto na lista de locais dela.

---

### Fluxo A2 — Ver e cadastrar um estabelecimento

**Objetivo:** registrar um local **fixo** (sede, unidade, depósito).
**Benefício:** o endereço fica pronto para ser reaproveitado nas admissões e no
ponto, e o CEP preenche o resto sozinho.

1. Na lista da empresa, clique em **Novo Registro**.
2. Em **Tipo**, mantenha **Estabelecimento**.
3. Preencha o **Nome** (ex.: "Escritório Central").
4. Digite o **CEP** — cidade, estado e endereço são preenchidos
   automaticamente; ajuste o número/complemento se quiser.
5. Preencha **Telefone** e **E-mail** (opcionais) e deixe o **Ativo** ligado.
6. Clique em **Criar**.

> 📸 **PRINT 02 — Lista de estabelecimentos e obras**
> **Onde:** Estabelecimentos / Obras, já dentro da empresa.
> **O que precisa aparecer:** o cartão "Entenda os tipos de registro", o campo de
> busca e a tabela com as colunas **Nome, Tipo, Localização, Contato, Status,
> Ações**.
> **Dados fictícios na tela:**
> - **Escritório Central** — *Estabelecimento* — São Paulo - SP — Ativo.
> - **Galpão Logístico** — *Estabelecimento* — Guarulhos - SP — Ativo.
> - **Canteiro Obra Vila Nova** — *Obra* — São Paulo - SP — Ativo.
> **Ação filmada:** clicar em **Novo Registro**.

> 📸 **PRINT 03 — Formulário de novo estabelecimento**
> **Onde:** botão **Novo Registro** → Tipo **Estabelecimento**.
> **O que precisa aparecer:** o seletor de Tipo, os campos Nome, CEP, Cidade,
> Estado, Endereço, Telefone, E-mail e a chave **Ativo**.
> **Dados fictícios na tela:** Nome **"Escritório Central"**, CEP **01310-100**,
> Cidade **São Paulo**, Estado **SP**, Telefone **(11) 4000-0000**, E-mail
> **contato@empresastaging.com.br**.
> **Ação filmada:** digitar o CEP e mostrar cidade/estado sendo preenchidos
> sozinhos; clicar em **Criar**.

> 💡 O CEP puxa o endereço automaticamente. Se não puxar, digite manualmente —
> nenhum campo de endereço é obrigatório; só o **Nome** e o **Tipo** são.

---

### Fluxo A3 — Cadastrar uma obra (com CNO)

**Objetivo:** registrar um local **temporário** de prestação de serviço.
**Benefício:** a obra guarda o **CNO**, que a matriz não tem, deixando a estrutura
pronta para a parte fiscal.

1. Clique em **Novo Registro**.
2. Em **Tipo**, escolha **Obra** — o campo **CNO** aparece ao lado.
3. Informe o **Nome** da obra e o **CNO**.
4. Preencha o endereço (via CEP) e **Criar**.

> 📸 **PRINT 04 — Formulário de nova obra (campo CNO)**
> **Onde:** Novo Registro → Tipo **Obra**.
> **O que precisa aparecer:** o Tipo em "Obra" e o campo **CNO** visível ao lado.
> **Dados fictícios na tela:** Nome **"Canteiro Obra Vila Nova"**, CNO
> **12.345.67890/12**, Cidade **São Paulo - SP**.
> **Ação filmada:** trocar o Tipo para "Obra" e mostrar o campo CNO surgindo.

> 💡 Trocar o tipo de **Obra** para **Estabelecimento** limpa o CNO — coerente,
> já que estabelecimento não tem esse cadastro.

> **Editar / excluir:** cada linha da tabela tem o lápis (**editar**) e a lixeira
> (**excluir**). A exclusão pede confirmação e **não pode ser desfeita** — use
> preferencialmente a chave **Ativo/Inativo** quando quiser apenas "aposentar" um
> local sem perder o histórico.

---

## BLOCO B — Departamentos (`/cadastros/departamentos`)

### Fluxo B1 — Cadastrar um departamento e definir o gestor

**Objetivo:** criar a área e dizer quem responde por ela.
**Benefício:** ao indicar o gestor, o sistema **cria o acesso dele
automaticamente** — sem depender de outro cadastro.

1. Abra **Estrutura Organizacional → Departamentos**.
2. Clique em **Novo Departamento**.
3. Informe o **Nome** (ex.: "Recursos Humanos").
4. Em **Estabelecimento/Obra**, escolha o local ao qual o departamento pertence
   ou deixe **"Nenhum (vinculado à empresa)"**.
5. No bloco **Gestão do Departamento**, escolha o **Gestor responsável** (busca
   por nome ou CPF).
6. (Opcional) Preencha a **Descrição** e deixe **Ativo** ligado.
7. Clique em **Criar** — ao salvar, o sistema **provisiona o login do gestor**:
   `primeiro.ultimo@youreyes.com.br`, com **senha inicial igual ao CPF** dele.

> 📸 **PRINT 05 — Lista de departamentos**
> **Onde:** Estrutura Organizacional → **Departamentos**.
> **O que precisa aparecer:** o campo de busca e a tabela com **Nome,
> Estabelecimento/Obra, Gestor, Substituto, Status, Ações**.
> **Dados fictícios na tela:**
> - **Recursos Humanos** — Escritório Central — **Marina Alves** — sem substituto
>   — Ativo.
> - **Operações** — Canteiro Obra Vila Nova — **Bruno Carvalho** — substituto com
>   selo **Atuando** — Ativo.
> - **Financeiro** — Escritório Central — **Eduarda Lima** — Ativo.
> **Ação filmada:** clicar em **Novo Departamento**.

> 📸 **PRINT 06 — Formulário de novo departamento**
> **Onde:** botão **Novo Departamento**.
> **O que precisa aparecer:** o campo Nome, o seletor Estabelecimento/Obra e o
> bloco **Gestão do Departamento** com **Gestor responsável** e **Substituto**.
> **Dados fictícios na tela:** Nome **"Operações"**, Estabelecimento **"Canteiro
> Obra Vila Nova"**, Gestor **Bruno Carvalho** (900.000.002-56).
> **Ação filmada:** escolher o gestor Bruno Carvalho no seletor de busca.

> 💡 A lista de gestores mostra apenas colaboradores (não traz PJ). O aviso no
> formulário lembra que será gerado o login `primeiro.ultimo@youreyes.com.br` com
> senha inicial = CPF.

---

### Fluxo B2 — Definir e ativar o substituto

**Objetivo:** garantir cobertura quando o gestor titular se afasta.
**Benefício:** o substituto só "assume" quando o RH liga a chave — controle
explícito, sem surpresa.

1. No formulário do departamento, escolha o **Substituto do gestor** (não pode
   ser a mesma pessoa do titular).
2. Quando o titular entrar de licença/férias, ligue a chave **"Substituto está
   atuando agora"**.
3. Salve. Na tabela, o substituto aparece com o selo **Atuando**.

> 📸 **PRINT 07 — Substituto atuando + acesso do gestor**
> **Onde:** formulário de Departamento (chave do substituto) e, ao salvar, o aviso
> de login criado.
> **O que precisa aparecer:** a chave **"Substituto está atuando agora"** ligada
> e/ou a mensagem de confirmação **"Login criado: … — senha inicial: CPF do
> gestor"**.
> **Dados fictícios na tela:** substituto **Diego Freitas** atuando pelo gestor
> **Bruno Carvalho**; login **bruno.carvalho@youreyes.com.br**.
> **Ação filmada:** ligar a chave do substituto e mostrar o selo **Atuando** na
> lista.

> 💡 Precisou reenviar a senha do gestor? Na lista, o botão da **chave** (ao lado
> de editar/excluir) dispara um **link de redefinição** para o e-mail do gestor.
> Esse botão só aparece para quem é gestor/administrador e quando o departamento
> já tem gestor definido.

---

## BLOCO C — Cargos (`/cadastros/cargos`)

### Fluxo C1 — Cadastrar um cargo (dados gerais)

**Objetivo:** criar a função com nível, departamentos e faixa salarial.
**Benefício:** o cargo vira a "etiqueta" reaproveitada na admissão e nos demais
módulos.

1. Abra **Estrutura Organizacional → Cargos**.
2. Clique em **Novo Cargo**.
3. Na aba **Dados Gerais**, informe o **Nome** (ex.: "Analista de RH").
4. Em **Departamentos**, marque um ou mais — **o primeiro selecionado é o
   departamento principal**.
5. Escolha o **Nível** (estagiário → diretor) e a **faixa salarial** (mínimo e
   máximo).
6. (Opcional) escreva a **Descrição** das responsabilidades e deixe **Ativo**
   ligado.

> 📸 **PRINT 08 — Lista de cargos**
> **Onde:** Estrutura Organizacional → **Cargos**.
> **O que precisa aparecer:** os botões **Importar Planilha** e **Novo Cargo**, o
> campo de busca e a tabela com **Nome, Departamentos, Nível, Faixa Salarial,
> Condições Especiais, Status**.
> **Dados fictícios na tela:**
> - **Analista de RH** — *Recursos Humanos* — Pleno — R$ 3.500 a R$ 5.000 — sem
>   condições especiais — Ativo.
> - **Operador de Produção** — *Operações* — Júnior — selos **Insalubre** e
>   **Periculoso**.
> - **Analista Financeiro** — *Financeiro* — Pleno — Ativo.
> **Ação filmada:** clicar em **Novo Cargo**.

> 📸 **PRINT 09 — Novo cargo, aba Dados Gerais**
> **Onde:** Novo Cargo → aba **Dados Gerais**.
> **O que precisa aparecer:** o campo Nome, o seletor de **Departamentos** (com
> vários marcados em forma de etiquetas), o **Nível** e a faixa salarial.
> **Dados fictícios na tela:** Nome **"Analista de RH"**, Departamento
> **Recursos Humanos**, Nível **Pleno**, salário **R$ 3.500 – R$ 5.000**.
> **Ação filmada:** marcar dois departamentos e mostrar a etiqueta do principal.

> 💡 Um cargo pode pertencer a **vários departamentos** — útil para funções
> transversais (ex.: "Auxiliar Administrativo"). O primeiro da lista é o
> principal.

---

### Fluxo C2 — Condições especiais de SST no cargo

**Objetivo:** registrar insalubridade, periculosidade e aposentadoria especial.
**Benefício:** os adicionais são **herdados automaticamente** por quem for
admitido no cargo, com base técnica e regra legal aplicada sozinha.

1. Ainda no cargo, abra a aba **Condições Especiais (SST)**.
2. Ligue **Insalubridade** se houver — escolha o **grau** (10%/20%/40%) e
   descreva o **agente nocivo** (NR-15).
3. Ligue **Periculosidade** se houver — escolha o **tipo** (inflamáveis,
   eletricidade…); o adicional é fixo de **30%** (art. 193 CLT).
4. Ligue **Aposentadoria especial** se houver — escolha o **enquadramento**
   (15/20/25 anos), informado ao eSocial (S-2240).
5. Clique em **Criar** / **Salvar**.

> 📸 **PRINT 10 — Novo cargo, aba Condições Especiais (SST)**
> **Onde:** Novo Cargo → aba **Condições Especiais (SST)**.
> **O que precisa aparecer:** o aviso "Base Técnica SST", as chaves de
> Insalubridade, Periculosidade e Aposentadoria Especial, com um exemplo aberto.
> **Dados fictícios na tela:** cargo **"Operador de Produção"**, Insalubridade
> **grau Médio (20%)**, agente **"Ruído contínuo acima de 85dB"**; Periculosidade
> **Eletricidade**.
> **Ação filmada:** ligar Insalubridade e mostrar os campos de grau e agente
> surgindo.

> 💡 Se um cargo tiver **insalubridade e periculosidade juntas**, aparece o aviso
> da **Regra de Prevalência (art. 193, §2º CLT)**: o sistema calcula os dois e
> aplica o mais vantajoso, sem cumular. Bom momento comercial para filmar.

---

### Fluxo C3 — Importar cargos por planilha

**Objetivo:** cadastrar muitos cargos (e departamentos/colaboradores) de uma vez.
**Benefício:** implantação rápida — em vez de digitar um a um, sobe-se uma
planilha.

1. Na tela de Cargos, clique em **Importar Planilha**.
2. **Arraste** o arquivo Excel/CSV ou selecione-o.
3. Confira o **mapeamento das colunas** e a **prévia** (o sistema separa linhas
   válidas das com erro).
4. Confirme o processamento.

> 📸 **PRINT 11 — Importar planilha de cargos**
> **Onde:** Cargos → botão **Importar Planilha**.
> **O que precisa aparecer:** a área de upload do arquivo e o título "Importar
> Cargos e Colaboradores".
> **Dados fictícios na tela:** arquivo de exemplo **"cargos_empresa_staging.xlsx"**.
> **Ação filmada:** arrastar o arquivo e avançar até a prévia.

---

### Sobre o CBO (onde ele entra)

O **CBO — Classificação Brasileira de Ocupações** é o código oficial da ocupação
(ex.: `2524-05 — Analista de recursos humanos`). No YourEyes, o CBO **não é um
campo da tela de Cargos**: ele é escolhido na **ficha do colaborador** e no
**processo de admissão**, num buscador que aceita **código ou título** e formata
como `0000-00`. Assim, o "cargo" descreve a função interna da empresa, e o **CBO**
faz a ponte com a classificação oficial exigida pelo eSocial.

> 📸 **PRINT 12 — Busca de CBO (ficha do colaborador / admissão)**
> **Onde:** cadastro do colaborador ou fluxo de admissão, campo **Ocupação / CBO**.
> **O que precisa aparecer:** o buscador de CBO com resultados por código e
> título.
> **Dados fictícios na tela:** busca por **"analista"**, resultado **2524-05 —
> Analista de recursos humanos** selecionado para **Marina Alves**.
> **Ação filmada:** digitar "analista", escolher o CBO na lista.

> 💡 Este print é opcional no vídeo de estrutura — use-o só para explicar a
> diferença entre **cargo** (interno) e **CBO** (oficial). O detalhe de admissão
> tem manual próprio.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, mostrando dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Antes de admitir a primeira pessoa, sua empresa precisa de estrutura."* Abre com um organograma em branco. | Imagem genérica |
| 8–22s | *"Cadastre sedes, unidades e obras — o CEP preenche o endereço sozinho, e a obra já nasce com CNO."* | **PRINT 03** (estabelecimento) + **PRINT 04** (obra/CNO) |
| 22–38s | *"Monte os departamentos e, ao indicar o gestor, o acesso dele é criado na hora."* | **PRINT 06** (departamento) + **PRINT 07** (login do gestor) |
| 38–55s | *"Defina os cargos com nível, faixa salarial e as condições de SST — os adicionais são herdados por quem você admitir."* | **PRINT 09** (dados gerais) + **PRINT 10** (SST) |
| 55–70s | *"Empresa inteira? Importe por planilha e ganhe dias de implantação."* | **PRINT 11** (importação) |
| 70–85s | *"YourEyes. Sua estrutura pronta antes da primeira admissão."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 5–8 min)

Ordem de gravação = ordem lógica de uso (estabelecimento → departamento → cargo).
Narração em primeira pessoa ("vamos cadastrar…", "agora eu indico o gestor…").

1. **Abertura** — o que é o módulo de estrutura e por que vem antes de tudo.
2. **Escolher a empresa** na tela de Estabelecimentos/Obras (**PRINT 01**).
3. **Ver a lista** e **criar um estabelecimento**, mostrando o CEP automático
   (**PRINT 02, 03**).
4. **Criar uma obra** e mostrar o campo CNO (**PRINT 04**).
5. Ir para **Departamentos**, ver a lista e **criar um departamento** com gestor
   (**PRINT 05, 06**).
6. **Definir o substituto** e mostrar o login do gestor criado (**PRINT 07**).
7. Ir para **Cargos**, ver a lista e **criar um cargo** (dados gerais)
   (**PRINT 08, 09**).
8. Preencher as **Condições Especiais (SST)** e mostrar a regra de prevalência
   (**PRINT 10**).
9. **Importar uma planilha** de cargos (**PRINT 11**).
10. **Encerramento** — explicar rapidamente onde o **CBO** entra (ficha do
    colaborador/admissão) (**PRINT 12**) e lembrar a ordem recomendada:
    estabelecimento → departamento → cargo.

> 💡 Dica de gravação: mantenha a mesma empresa (**Empresa Staging LTDA**) e as
> mesmas personas do começo ao fim, para os três blocos parecerem um só sistema.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Seleção de empresa (Estabelecimentos/Obras)
- [ ] **PRINT 02** — Lista de estabelecimentos e obras
- [ ] **PRINT 03** — Formulário de novo estabelecimento (CEP automático)
- [ ] **PRINT 04** — Formulário de nova obra (campo CNO)
- [ ] **PRINT 05** — Lista de departamentos
- [ ] **PRINT 06** — Formulário de novo departamento (gestão)
- [ ] **PRINT 07** — Substituto atuando + login do gestor criado
- [ ] **PRINT 08** — Lista de cargos (com selos de condições especiais)
- [ ] **PRINT 09** — Novo cargo, aba Dados Gerais
- [ ] **PRINT 10** — Novo cargo, aba Condições Especiais (SST)
- [ ] **PRINT 11** — Importar planilha de cargos
- [ ] **PRINT 12** — Busca de CBO (ficha do colaborador / admissão) — opcional

---

## 9. Erros comuns / dúvidas frequentes

- **"Não aparece nenhuma empresa para escolher."** Só empresas do tipo **Matriz**
  aparecem aqui. Cadastre/ative a empresa antes, ou confira o CNPJ na busca.
- **"O CEP não preencheu o endereço."** Digite os 8 dígitos completos; se o CEP
  não for encontrado, preencha cidade/estado/endereço manualmente (não são
  obrigatórios).
- **"Não vejo o campo CNO."** O CNO só existe quando o **Tipo** é **Obra** —
  troque o tipo no topo do formulário.
- **"No departamento, o dropdown de estabelecimento está vazio."** Ele lista
  apenas locais **ativos da empresa em uso**. Cadastre/ative o estabelecimento
  antes, ou use **"Nenhum (vinculado à empresa)"**.
- **"Indiquei o gestor mas o login não foi criado."** O provisionamento roda ao
  **salvar**; se falhar, o formulário fica aberto para tentar de novo. Confira se
  o colaborador tem CPF válido (a senha inicial é o CPF).
- **"O substituto não está valendo."** Além de escolher o substituto, é preciso
  ligar a chave **"Substituto está atuando agora"**.
- **"Não consigo resetar a senha do gestor."** O botão da chave só aparece para
  usuários **gestor/administrador** e quando o departamento tem gestor definido.
- **"Onde coloco o CBO do cargo?"** O CBO não fica no cadastro de Cargos — ele é
  escolhido na **ficha do colaborador / admissão**. O cargo guarda a função
  interna; o CBO, a classificação oficial.
- **"Excluí sem querer."** A exclusão pede confirmação e **não pode ser
  desfeita**. Para "aposentar" sem perder histórico, use a chave
  **Ativo/Inativo** em vez de excluir.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução.

Para revisar o conteúdo comparando com as telas reais, abra o **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves**, empresa **Empresa Staging LTDA**, e percorra:

1. **Estrutura Organizacional → Estabelecimentos / Obras** — escolha a empresa,
   veja a lista e abra **Novo Registro** (confira o CEP automático e o campo CNO
   ao trocar para "Obra").
2. **Estrutura Organizacional → Departamentos** — abra **Novo Departamento** e
   confira o bloco de gestão (gestor, substituto).
3. **Estrutura Organizacional → Cargos** — abra **Novo Cargo** e confira as abas
   **Dados Gerais** e **Condições Especiais (SST)**, além do botão **Importar
   Planilha**.

Confirme que o passo a passo, os benefícios e os marcadores de print refletem
como você quer conduzir os vídeos. Aprovado o **formato**, replico o mesmo padrão
para os demais módulos, nos lotes que você priorizar.
