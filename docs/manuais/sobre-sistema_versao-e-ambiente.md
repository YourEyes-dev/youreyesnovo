# Manual do módulo — Sobre o Sistema

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e na mesma profundidade do piloto aprovado
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> É um **módulo pequeno** (uma tela só de leitura), então o manual é curto de
> propósito — mas cobre todas as seções do padrão.

- **Onde fica no menu:** seção **Sistema → Sobre o Sistema**.
- **Rota:** `/sobre-sistema`.
- **Para quem é:** qualquer usuário — RH, gestores, colaboradores e,
  principalmente, quem vai **abrir um chamado no Suporte**.
- **Em uma frase:** mostra, num cartão único, **qual versão** do YourEyes está
  rodando neste navegador, **em qual ambiente** (Produção ou Homologação),
  **quando foi publicada** e **qual base de dados** está atendendo.
- **Importante:** é uma tela de **consulta**. Não há nada para preencher,
  salvar ou configurar aqui — e por isso ela não tem "Guia Rápido" embutido
  como outros módulos.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Transparência total sobre o que está no ar.** Em dois segundos qualquer
  pessoa sabe a versão exata que está usando — sem depender do time técnico.
- **Suporte muito mais rápido.** Ao abrir um chamado, o usuário informa a
  **versão** e a **data da última publicação**. O suporte para de adivinhar e
  vai direto ao ponto — o próprio sistema registra a versão junto de cada erro.
- **Confiança de que você está no lugar certo.** O selo de **ambiente** deixa
  claro, na hora, se aquela tela é a **Produção** (dados reais) ou a
  **Homologação** (ambiente de testes) — evita mexer no lugar errado.
- **Prova de atualização.** A **data da última publicação** mostra que a
  plataforma está viva e recebendo melhorias com frequência.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Versão** | O "número da edição" do sistema no ar (ex.: **1.0.0**). Serve para o suporte saber exatamente o que você está usando. |
| **Sufixo de pré-lançamento** | Quando a versão não é a de produção, ela ganha uma marca no fim (ex.: **1.0.0-teste.20260928**). O "-teste" avisa que aquela tela é de ensaio, não a oficial. |
| **Ambiente** | Onde a tela está rodando. **Produção** = ambiente oficial, com dados reais. **Homologação** = ambiente de testes/ensaios. |
| **Última publicação** | Data e hora em que a versão que você está vendo foi colocada no ar (o "build"). Aparece no fuso de **Brasília**. |
| **Base de dados** | O identificador técnico do banco que está atendendo aquela tela. É a "etiqueta" que o suporte usa para confirmar de qual base os dados vêm. |

> 💡 O selo de ambiente responde a uma pergunta só: **"esta é a base real de
> produção?"**. Se sim, mostra **Produção**; qualquer outra base (teste,
> homologação, ensaio) aparece como **Homologação**.

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Estar logado no sistema.** O item aparece para qualquer usuário no menu
   **Sistema**.
2. Nada mais. Não há configuração, permissão especial nem opção a ligar — a
   tela é apenas de leitura.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Sobre o Sistema**, a tela mostra o título **"Sobre o Sistema"** com o
subtítulo *"Informações da versão em execução neste navegador"* e, logo abaixo,
**um único cartão**: **"YourEyes — Plataforma de Gestão de Pessoas e SST"**.

Dentro do cartão há **quatro linhas**, cada uma com um ícone à esquerda e o
valor à direita:

| Linha | O que mostra |
|---|---|
| **Versão** | O número da edição no ar (ex.: 1.0.0 ou 1.0.0-teste.20260928). |
| **Ambiente** | Um selo colorido: **Produção** ou **Homologação**. |
| **Última publicação** | Data e hora do build, no fuso de Brasília. |
| **Base de dados** | O identificador técnico da base que atende a tela. |

> 📸 **PRINT 01 — Onde fica no menu**
> **Onde:** menu lateral, seção **Sistema**.
> **O que precisa aparecer:** a seção **Sistema** aberta com os itens Meu Plano,
> Suporte, Configurações e **Sobre o Sistema** destacado.
> **Dados fictícios na tela:** logado como **Marina Alves** (Analista de RH),
> empresa **Empresa Staging LTDA**.
> **Ação filmada:** o cursor descendo até **Sobre o Sistema** e clicando.

> 📸 **PRINT 02 — Tela Sobre o Sistema (cartão completo)**
> **Onde:** **Sistema → Sobre o Sistema** (`/sobre-sistema`).
> **O que precisa aparecer:** o título, o subtítulo e o cartão com as quatro
> linhas (Versão, Ambiente, Última publicação, Base de dados).
> **Dados fictícios na tela:** versão **1.0.0-teste.20260928**; ambiente
> **Homologação**; última publicação **28 de setembro de 2026 às 14:30**; base
> de dados **bmehdgthciuvdbvutsdv**.
> **Ação filmada:** panorâmica lenta de cima para baixo, passando pelas quatro
> linhas.

---

## 5. Passo a passo por fluxo

### Fluxo 1 — Consultar a versão e a data de publicação

**Objetivo:** descobrir qual edição do sistema está rodando.
**Benefício:** informação pronta para colar num chamado de suporte.

1. No menu, abra **Sistema → Sobre o Sistema**.
2. Leia a linha **Versão** (ex.: 1.0.0-teste.20260928).
3. Leia a linha **Última publicação** — é a data/hora em que essa versão foi ao
   ar, no fuso de Brasília.

> 💡 Sempre que abrir um chamado no **Suporte**, informe a **versão** e a **data
> da última publicação**. O sistema já anexa a versão a cada erro registrado,
> mas essas duas informações aceleram muito a resposta.

---

### Fluxo 2 — Confirmar em qual ambiente você está

**Objetivo:** saber se a tela é a oficial (Produção) ou a de testes
(Homologação).
**Benefício:** evita mexer no ambiente errado — dados reais ficam separados dos
ensaios.

1. Abra **Sistema → Sobre o Sistema**.
2. Olhe o selo da linha **Ambiente**.
   - **Produção** → é o ambiente oficial, com dados reais.
   - **Homologação** → é ambiente de testes/ensaios (é o que aparece no site de
     teste).
3. Confira, se quiser, a linha **Base de dados** — o identificador técnico
   correspondente àquele ambiente.

> 📸 **PRINT 03 — Selo de ambiente (detalhe)**
> **Onde:** **Sobre o Sistema**, close-up na linha **Ambiente**.
> **O que precisa aparecer:** o selo colorido de ambiente bem legível.
> **Dados fictícios na tela:** selo **Homologação** (é o que o site de teste
> exibe; a versão ao lado traz o sufixo **-teste**).
> **Ação filmada:** aproximar o enquadramento no selo.

> 💡 No **site de teste** o selo aparece como **Homologação** e a versão vem com
> **-teste** — é o comportamento esperado. O selo **Produção** só surge quando a
> tela está rodando de fato na base oficial de produção.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (20–30s)

**Tom:** curto e tranquilizador — transparência e confiança.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–6s | *"Qual versão do sistema você está usando agora?"* Abre o menu Sistema. | **PRINT 01** |
| 6–18s | *"No YourEyes, é um clique: versão, ambiente e data da última atualização, sempre à vista."* | **PRINT 02** |
| 18–28s | *"Precisa de suporte? Você já sabe exatamente o que informar."* Logo. | **PRINT 03** + tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (1–2 min)

Narração em primeira pessoa ("vamos abrir…", "aqui eu vejo…").

1. **Abertura** — para que serve a tela e para quem (**PRINT 01**).
2. **Abrir Sobre o Sistema** e ler o cartão completo (**PRINT 02**).
3. **Ler a versão e a data de publicação** e explicar o uso no suporte
   (**PRINT 02**).
4. **Confirmar o ambiente** pelo selo e explicar Produção x Homologação
   (**PRINT 03**).
5. **Encerramento** — lembrar de informar versão e data ao abrir um chamado.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Onde fica no menu (Sistema → Sobre o Sistema)
- [ ] **PRINT 02** — Tela Sobre o Sistema (cartão completo com as 4 linhas)
- [ ] **PRINT 03** — Selo de ambiente (detalhe)

> Lembrete: no site de teste o selo lê **Homologação** e a versão traz o sufixo
> **-teste** — capture exatamente como aparece, sem editar para "Produção".

---

## 9. Erros comuns / dúvidas frequentes

- **"Não achei o Sobre o Sistema."** Ele fica no fim do menu, na seção
  **Sistema** (junto de Meu Plano, Suporte e Configurações).
- **"O selo diz Homologação, mas eu quero ver a Produção."** É esperado: o site
  de teste sempre mostra **Homologação**. O selo **Produção** só aparece na tela
  oficial de produção.
- **"A versão tem um '-teste' no fim."** É a marca de pré-lançamento: sinaliza
  que a tela é de ensaio, não a oficial. Na produção a versão vem "limpa" (ex.:
  1.0.0).
- **"A última publicação aparece como 'Não disponível'."** Significa que a data
  do build não veio preenchida naquele carregamento — recarregue a página; se
  persistir, relate ao suporte.
- **"Para que serve a Base de dados?"** É só um identificador técnico usado pelo
  suporte para confirmar de qual base seus dados vêm. Não precisa fazer nada com
  ele.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o site de teste
   (https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
   Alves**, e vá em **Sistema → Sobre o Sistema** para conferir que o cartão e as
   quatro linhas (Versão, Ambiente, Última publicação, Base de dados) batem com o
   que este manual descreve.
2. Abra o arquivo `docs/manuais/sobre-sistema_versao-e-ambiente.md` no projeto e
   confira se o passo a passo, os benefícios e os marcadores de print refletem
   como você quer conduzir os vídeos.
3. A **produção segue intacta** — nada foi publicado nem alterado por esta
   entrega.
