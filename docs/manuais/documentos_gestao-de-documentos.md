# Manual do módulo — Documentos (Gestão de Documentos & Governança)

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e do piloto aprovado [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial e de referência para os
> demais manuais.

- **Onde fica no menu:** seção **Documentos & Governança → Documentos**
  (rota `/documentos`).
- **Para quem é:** RH, Departamento Pessoal (DP), SST e Gestão da Qualidade.
- **Em uma frase:** organiza todos os arquivos da empresa e das pessoas em uma
  **árvore de pastas** com **upload, versões, movimentação e trilha de
  auditoria**, e ainda mostra **conformidade documental**, **maturidade de
  governança** e **alertas de vencimento** que viram plano de ação.
- **Importante:** a **estrutura de pastas é criada sozinha** quando a empresa
  abre o módulo pela primeira vez, e cada colaborador ativo ganha
  automaticamente a sua pasta pessoal. O RH não precisa montar a árvore do zero.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **O fim das pastas espalhadas e do "onde foi parar aquele arquivo?".** Tudo
  fica em um só lugar, numa árvore organizada por **áreas** (Governança, SST,
  Riscos, Pessoas, Auditorias…) e por **colaborador**.
- **Organização que nasce pronta.** Ao abrir o módulo, o sistema **gera a
  estrutura padrão** de governança e SST sozinho e **cria a pasta de cada
  pessoa** — sem trabalho manual. Documento de colaborador enviado já cai na
  subpasta certa (Admissão, Vida Funcional, Saúde Ocupacional, Desligamento).
- **Nada se perde, tudo tem histórico.** Cada arquivo guarda **versões**: subir
  uma nova versão **preserva a anterior**, e dá para **restaurar** uma versão
  antiga quando preciso. Toda ação (upload, mover, renomear, excluir, restaurar)
  fica registrada na **trilha de auditoria**, com autor e data.
- **Alerta antes de o documento vencer.** Documentos com data de validade (ASO,
  certidões, licenças, treinamentos) geram **avisos** — vencidos, críticos (até
  7 dias) e a vencer (prazo configurável). Cada aviso pode virar um **plano de
  ação** sugerido por IA no formato **5W2H**.
- **Visão de conformidade e de governança.** O **Mapa de Conformidade** compara
  os documentos esperados com os que existem por categoria (completude em %); o
  **Radar de Governança** mostra a maturidade documental por dimensão; e o painel
  **PDCA** consolida riscos, ações e vencimentos em um só lugar.
- **Segurança e LGPD.** Cada empresa vê só os seus documentos, e o download é
  feito por **link temporário e seguro** — o arquivo não fica exposto por uma URL
  pública.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Árvore de pastas / Estrutura** | A organização hierárquica: áreas → categorias → subpastas → pastas de colaborador. É a aba principal do módulo. |
| **Estrutura padrão** | O conjunto de pastas de governança e SST que o sistema cria sozinho na primeira vez (Governança, Sistema de Gestão, Riscos, SST, Cultura, Pessoas, Investigação, Auditorias). |
| **Pasta de colaborador** | A pasta pessoal de cada funcionário, criada automaticamente, com as subpastas Admissão, Vida Funcional, Saúde Ocupacional e Desligamento. |
| **Documento** | O arquivo enviado (PDF, imagem ou Word), com tipo, tamanho, validade e status. |
| **Tipo de documento** | A natureza do arquivo (ASO, Contrato, RG, Recibo de EPI, Certidão…). Pode ser escolhido da lista ou digitado livremente. |
| **Status** | A situação de validade: **Válido**, **Vencendo** (nos 30 dias antes da validade) ou **Vencido**. |
| **Versão** | Cada revisão do mesmo documento. A nova entra por cima e a anterior fica guardada no histórico. |
| **Trilha de auditoria** | O registro de tudo que aconteceu com os documentos (upload, mover, renomear, excluir, restaurar). |
| **Mapa de Conformidade** | Comparação entre documentos esperados e existentes, por categoria, com percentual de completude. |
| **Radar de Governança** | Gráfico da maturidade documental por dimensão (Governança, SST, Ambiental, Processos, Pessoas, Riscos, Auditorias). |
| **PDCA** | Ciclo de melhoria contínua (Planejar, Executar, Checar, Agir) — painel que junta ações, riscos e documentos vencidos. |
| **5W2H** | O formato do plano de ação (o quê, por quê, onde, quando, quem, como, quanto). |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Estar logado com um perfil de RH** (nas gravações, **Marina Alves**).
2. **Ter uma empresa ativa selecionada** — a árvore e os documentos são sempre
   os da empresa ativa (nas gravações, **Empresa Staging LTDA**).
3. **Nada mais.** A estrutura padrão de pastas é gerada automaticamente na
   primeira abertura, e as pastas dos colaboradores ativos aparecem sozinhas. Se
   a empresa foi recém-criada, ao abrir o módulo aparece por alguns segundos o
   aviso **"Gerando estrutura de pastas…"**.

> 📸 **PRINT 01 — Estado "gerando estrutura" (opcional, só tutorial)**
> **Onde:** módulo Documentos aberto pela primeira vez em uma empresa sem pastas.
> **O que precisa aparecer:** o cartão **"Gerando estrutura de pastas…"** com a
> mensagem de que a estrutura padrão está sendo criada automaticamente.
> **Uso:** só no tutorial, para explicar que o RH não monta nada à mão. Pode ser
> pulado no comercial.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Documentos**, o topo mostra o título **"Documentos"** com o subtítulo
**"Gestão hierárquica de arquivos e prontuários"** e, à direita, dois botões:
**Nova Pasta** e **Upload**.

Logo abaixo ficam **4 cartões de indicadores**: **Total** (de documentos),
**Pastas**, **Vencendo** e **Vencidos**.

Depois vêm as **6 abas** do módulo:

| Aba | Para que serve |
|---|---|
| **Estrutura** | A árvore de pastas (à esquerda) e os documentos da pasta selecionada (à direita). É o coração do módulo. |
| **Conformidade** | Mapa de documentos esperados x existentes por categoria, com % de completude. |
| **Governança** | Radar de maturidade documental por dimensão. |
| **PDCA** | Painel de melhoria contínua: ações, riscos e documentos vencidos. |
| **Notificações** | Alertas de vencimento (vencidos, críticos, a vencer) com botão para criar ação. Tem um selo com o número de pendências. |
| **Auditoria** | Trilha de tudo que foi feito com os documentos, com filtros. |

> 📸 **PRINT 02 — Tela inicial do módulo (aba Estrutura)**
> **Onde:** menu **Documentos & Governança → Documentos**, aba **Estrutura**.
> **O que precisa aparecer:** título, os botões **Nova Pasta** e **Upload**, os
> 4 cartões de indicadores e as 6 abas.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; indicadores
> como **Total 128**, **Pastas 42**, **Vencendo 3**, **Vencidos 1**.
> **Ação filmada:** panorâmica lenta mostrando os cartões e as abas.

---

## 5. Passo a passo por fluxo

### Fluxo 1 — Conhecer e navegar na árvore de pastas

**Objetivo:** entender como os arquivos estão organizados.
**Benefício:** o RH encontra qualquer documento em segundos, sem depender de
pastas soltas no computador de alguém.

1. Abra a aba **Estrutura**. A tela se divide em dois painéis: **árvore de
   pastas** (esquerda) e **documentos da pasta** (direita).
2. Clique nas setas **▶ / ▼** para abrir e fechar as pastas, ou use os botões
   **Expandir** e **Minimizar** no topo da árvore.
3. Use o campo **"Buscar pasta…"** para filtrar pelo nome.
4. Clique em uma pasta para ver seus documentos no painel da direita.

> 📸 **PRINT 03 — Árvore de pastas (painel esquerdo)**
> **Onde:** Documentos → **Estrutura**, painel da esquerda.
> **O que precisa aparecer:** a árvore com as áreas padrão — **Governança e
> Administração**, **Sistema de Gestão**, **Gestão de Riscos**, **SST**,
> **Cultura Organizacional**, **Gestão de Pessoas**, **Investigação de
> Incidentes**, **Auditorias e Melhoria Contínua** — com uma delas expandida
> mostrando as subcategorias. Mostre também o campo de busca e os botões
> **Expandir / Minimizar**.
> **Dados fictícios na tela:** área **SST** aberta com **Programas Legais (PGR,
> PCMSO, LTCAT)** e **Treinamentos**; selos de contagem nas pastas (ex.: **12**).
> **Ação filmada:** expandir a área SST e digitar "certidão" na busca.

> 💡 As pastas com documentos mostram **selos**: número total (cinza), a vencer
> (contorno amarelo) e vencidos (vermelho) — dá para ver o risco sem abrir a
> pasta.

---

### Fluxo 2 — Criar uma pasta ou subpasta

**Objetivo:** complementar a estrutura com pastas próprias (por ano, mês,
categoria ou personalizada).
**Benefício:** flexibilidade para adaptar a organização à realidade da empresa,
sem perder o padrão.

1. Clique em **Nova Pasta** (topo) para criar uma pasta raiz, **ou** passe o
   mouse sobre uma pasta na árvore e use o menu **⋮ → Nova Subpasta** (também há
   o botão **Nova Subpasta** no painel da direita).
2. Informe o **nome** (ex.: "2026", "Janeiro", "Treinamentos").
3. Escolha o **tipo**: **Pasta Personalizada**, **Ano**, **Mês** ou
   **Categoria**.
4. Clique em **Criar Pasta**.

> 📸 **PRINT 04 — Modal "Nova Pasta"**
> **Onde:** botão **Nova Pasta** (topo) ou **⋮ → Nova Subpasta** na árvore.
> **O que precisa aparecer:** o campo **Nome da Pasta**, o seletor **Tipo** e os
> botões **Cancelar / Criar Pasta**. Quando for subpasta, o texto "Criar subpasta
> em '...'".
> **Dados fictícios na tela:** nome **"2026"**, tipo **Ano**, criada dentro de
> **Auditorias e Melhoria Contínua**.

> 💡 Renomear e excluir também estão no menu **⋮** de cada pasta. Ao excluir uma
> pasta, as subpastas vão junto, mas **os documentos não são apagados** — eles
> apenas ficam sem pasta.

---

### Fluxo 3 — Enviar um documento (upload)

**Objetivo:** guardar um arquivo no sistema, na pasta certa e com validade.
**Benefício:** o documento passa a ter tipo, status de validade e histórico —
pronto para conferência e auditoria.

1. Selecione a pasta de destino na árvore e clique em **Upload** (topo) — ou use
   **Enviar Documento** dentro da pasta.
2. **Arraste o arquivo** para a área indicada ou **clique para selecionar**
   (PDF, imagem JPG/PNG/WebP ou Word — **máximo 50 MB**).
3. Confira/escolha a **Pasta / Subpasta** (campo com busca).
4. Escolha o **Tipo de Documento** — pode selecionar da lista (ASO, Contrato,
   RG, Recibo de EPI, Certidão…) **ou digitar um tipo livre**.
5. Se aplicável, informe a **Data de Validade** e as **Observações**.
6. Clique em **Enviar Documento**.

> 📸 **PRINT 05 — Modal "Upload de Documento"**
> **Onde:** botão **Upload** (topo).
> **O que precisa aparecer:** a área de arrastar arquivo (com um arquivo já
> selecionado), o seletor de **Pasta / Subpasta**, o campo **Tipo de Documento**,
> a **Data de Validade** e o campo **Observações**.
> **Dados fictícios na tela:** arquivo **"ASO_admissional.pdf"**, pasta
> **Gestão de Pessoas / Camila Duarte / Saúde Ocupacional**, tipo **ASO**,
> validade **30/09/2027**.
> **Ação filmada:** arrastar o arquivo, escolher o tipo e clicar em **Enviar
> Documento**.

> 📸 **PRINT 06 — Documento na lista da pasta**
> **Onde:** painel da direita, após o upload.
> **O que precisa aparecer:** a linha do documento com nome, tipo, tamanho, a
> validade e o **selo de status** (Válido / Vencendo / Vencido) e o menu **⋮**.
> **Dados fictícios na tela:** **ASO_admissional.pdf — ASO — 240 KB —
> Validade 30/09/2027 — Válido**.

> 💡 O tipo de documento influencia a organização: para pastas de colaborador, o
> sistema usa o tipo para escolher a subpasta certa (ver Fluxo 4).

---

### Fluxo 4 — Pastas de colaborador (organização automática)

**Objetivo:** manter o prontuário de cada pessoa organizado sem trabalho manual.
**Benefício:** cada colaborador ativo já tem pasta, e os documentos caem na
subpasta correta pelo tipo.

1. Na árvore, abra **Gestão de Pessoas** — cada colaborador ativo tem a sua
   pasta (quando há muitos, elas ficam agrupadas por letra, ex.: **"C • 4
   colaboradores"**).
2. Dentro da pasta de cada pessoa há as subpastas **Admissão**, **Vida
   Funcional**, **Saúde Ocupacional** e **Desligamento**.
3. Ao enviar um documento para a pasta de um colaborador, o **colaborador é
   pré-selecionado** e o sistema arquiva na subpasta certa pelo tipo:
   - **ASO, Atestado, Recibo de EPI, Ordem de Serviço, Treinamento NR** →
     **Saúde Ocupacional**;
   - **Ficha de Registro, Contrato, CTPS, RG, CPF, Comprovante de Residência,
     CNH, Certificado** → **Admissão**;
   - documentos de desligamento → **Desligamento**;
   - os demais → **Vida Funcional**.

> 📸 **PRINT 07 — Pasta de colaborador com subpastas**
> **Onde:** Documentos → **Estrutura** → **Gestão de Pessoas → Camila Duarte**.
> **O que precisa aparecer:** a pasta da colaboradora expandida, com as subpastas
> **Admissão / Vida Funcional / Saúde Ocupacional / Desligamento** e alguns
> documentos dentro.
> **Dados fictícios na tela:** **Camila Duarte** com um **Contrato** em Admissão
> e um **ASO** em Saúde Ocupacional.

> 💡 Colaboradores novos aparecem sozinhos: o módulo **sincroniza** as pastas das
> pessoas ativas que ainda não têm pasta assim que a tela carrega.

---

### Fluxo 5 — Mover, visualizar, baixar e excluir documentos

**Objetivo:** organizar e acessar os arquivos do dia a dia.
**Benefício:** cada ação fica registrada na auditoria — nada some sem rastro.

1. **Mover:** **arraste** o documento (pelo ícone de "pegar") de uma pasta e
   **solte** em outra pasta na árvore. O movimento é registrado na auditoria.
2. **Visualizar / Baixar:** no menu **⋮** do documento, use **Visualizar** (abre
   em nova aba por link seguro) ou **Download**.
3. **Excluir:** no menu **⋮**, use **Excluir** (pede confirmação).

> 📸 **PRINT 08 — Menu de ações do documento**
> **Onde:** painel da direita, menu **⋮** de uma linha de documento.
> **O que precisa aparecer:** as opções **Visualizar**, **Download**, **Versões**
> e **Excluir**.
> **Dados fictícios na tela:** documento **Contrato_Camila.pdf** com o menu
> aberto.
> **Ação filmada:** ótimo momento para gravar o **arrastar-e-soltar** de um
> documento entre duas pastas.

> 💡 Excluir um documento remove o arquivo; excluir uma **pasta** não apaga os
> documentos, só os desvincula. Prefira **mover** a excluir quando o objetivo é
> só reorganizar.

---

### Fluxo 6 — Versões: nova versão e restauração

**Objetivo:** atualizar um documento sem perder o anterior.
**Benefício:** rastreabilidade total — sempre dá para ver e voltar às versões
antigas.

1. No menu **⋮** do documento, clique em **Versões**.
2. Para atualizar, clique em **Nova Versão** e envie o novo arquivo — a versão
   atual passa a ser guardada no histórico.
3. No histórico, use **Download** para baixar uma versão antiga ou **Restaurar**
   (ícone de voltar) para torná-la a versão atual.

> 📸 **PRINT 09 — Modal "Histórico de Versões"**
> **Onde:** menu **⋮ → Versões** de um documento.
> **O que precisa aparecer:** o bloco da **versão atual** (com o botão **Nova
> Versão**) e a lista de **versões anteriores** com os botões de **Download** e
> **Restaurar**.
> **Dados fictícios na tela:** documento **PGR_2026.pdf**, **v3 — Atual**, e no
> histórico **v2** e **v1** com o motivo da revisão.

> 💡 O documento na lista mostra um selo **v2/v3…** quando tem mais de uma
> versão — dá para ver de relance o que já foi revisado.

---

### Fluxo 7 — Notificações de vencimento e criação de ação

**Objetivo:** não deixar documento vencer sem providência.
**Benefício:** o vencimento vira alerta e o alerta vira plano de ação — a
prevenção fica registrada.

1. Abra a aba **Notificações** (o selo na aba mostra o total de pendências).
2. No topo, ajuste em **Configurar** com quantos **dias de antecedência** quer
   ser avisado (padrão **30 dias**).
3. Veja os três blocos: **Vencidos**, **Vencimento Crítico (até 7 dias)** e
   **Vencimento Próximo**.
4. Em qualquer alerta, clique em **Criar Ação** — abre um assistente que
   **sugere um plano de ação 5W2H** (com apoio de IA) para a renovação.

> 📸 **PRINT 10 — Aba Notificações**
> **Onde:** Documentos → **Notificações**.
> **O que precisa aparecer:** o banner **Configuração de Alertas** (com os dias
> de antecedência), os cartões **Documentos vencidos / Críticos / Atenção** e a
> lista de documentos com o botão **Criar Ação**.
> **Dados fictícios na tela:** **1 vencido**, **2 críticos**, **3 em atenção**;
> alerta **"Certidão FGTS — vence em 5 dias"**.
> **Ação filmada:** clicar em **Criar Ação** em um alerta e mostrar o assistente
> de plano de ação.

> 💡 O selo com número na aba **Notificações** soma vencidos + a vencer — é o
> "sinal de atenção" do módulo.

---

### Fluxo 8 — Mapa de Conformidade

**Objetivo:** ver o que já existe e o que falta, por categoria.
**Benefício:** enxergar rapidamente as lacunas documentais antes de uma
auditoria ou fiscalização.

1. Abra a aba **Conformidade**.
2. Veja o resumo geral: **Completude (%)**, **Existentes**, **Faltantes**,
   **Vencidos**, **Não Aplicáveis**.
3. Expanda cada **seção** (Governança, Processos, Riscos, SST, Ambiental,
   Auditorias) para ver, por categoria, quais documentos estão presentes,
   faltando ou vencidos.
4. Use os **filtros** (Faltantes, Vencidos, Existentes, N/A) para focar.

> 📸 **PRINT 11 — Aba Conformidade**
> **Onde:** Documentos → **Conformidade**.
> **O que precisa aparecer:** os cartões de resumo (completude em %) e uma seção
> expandida com a lista de documentos esperados e seus ícones de status
> (existente / faltante / vencido).
> **Dados fictícios na tela:** **Completude 68%**; seção **Governança e
> Administração** com **Contrato Social (existente)** e **Certidão INSS
> (faltante)**.

> 💡 O Mapa cruza a árvore real de pastas com uma lista de documentos esperados —
> por isso vale nomear os arquivos de forma reconhecível (ex.: "Contrato
> Social").

---

### Fluxo 9 — Radar de Governança

**Objetivo:** medir a maturidade documental da empresa por dimensão.
**Benefício:** um indicador visual de evolução para apresentar à diretoria.

1. Abra a aba **Governança**.
2. Veja o **radar** com as dimensões (Governança, SST, Ambiental, Processos,
   Pessoas, Riscos, Auditorias) e a **média geral** com o rótulo de maturidade
   (**Inicial**, **Básico**, **Em Desenvolvimento** ou **Avançado**).
3. Abaixo, a legenda mostra o percentual e a quantidade de documentos por
   dimensão.

> 📸 **PRINT 12 — Aba Governança (radar)**
> **Onde:** Documentos → **Governança**.
> **O que precisa aparecer:** o gráfico de radar, a média geral com o rótulo de
> maturidade e a legenda com os percentuais por dimensão.
> **Dados fictícios na tela:** média **58% — Em Desenvolvimento**; **SST 75%**,
> **Ambiental 30%**.

---

### Fluxo 10 — Painel PDCA (melhoria contínua)

**Objetivo:** juntar ações, riscos e documentos vencidos em uma visão só.
**Benefício:** o RH/SST acompanha o ciclo de melhoria sem sair do módulo.

1. Abra a aba **PDCA**.
2. Veja os cartões do ciclo: **P — Planejar**, **D — Executar**, **C — Checar**,
   **A — Agir**.
3. Acompanhe o **radar de maturidade PDCA**, a **evolução de ações (6 meses)**,
   as **ações por origem** e os **alertas de melhoria contínua** (documentos
   vencidos, ações atrasadas, acidentes sem investigação).
4. Nos alertas, use **Criar Ação** para abrir um plano de ação.

> 📸 **PRINT 13 — Aba PDCA**
> **Onde:** Documentos → **PDCA**.
> **O que precisa aparecer:** os 4 cartões do ciclo, o radar de maturidade e o
> bloco **Alertas de Melhoria Contínua**.
> **Dados fictícios na tela:** **Planejar 4 / Executar 2 / Checar 3 / Agir 6**;
> alerta **"1 documento vencido — requer renovação imediata"**.

> 💡 O painel PDCA reúne dados de vários módulos (ações, eventos de SST,
> documentos) — é a visão de gestão que fecha o ciclo de governança.

---

### Fluxo 11 — Trilha de Auditoria

**Objetivo:** provar quem fez o quê com cada documento.
**Benefício:** rastreabilidade completa para auditorias internas e externas.

1. Abra a aba **Auditoria**.
2. Veja as últimas movimentações (upload, mover, renomear, excluir, restaurar),
   cada uma com autor e data.
3. **Filtre** por nome do documento/usuário, e pelo **tipo de ação**.

> 📸 **PRINT 14 — Aba Auditoria**
> **Onde:** Documentos → **Auditoria**.
> **O que precisa aparecer:** o contador de registros, o filtro por ação e a
> lista de eventos com ícones coloridos e o nome do responsável.
> **Dados fictícios na tela:** **Movimentação — Contrato_Camila.pdf — Admissão →
> Vida Funcional — Marina Alves**; **Upload — ASO_admissional.pdf — Marina
> Alves**.

> 💡 A movimentação (arrastar entre pastas) é a ação que mais aparece aqui — por
> isso o filtro **Movimentação** é útil para conferir reorganizações.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, mostrando dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Documentos da empresa espalhados em pastas, e-mails e pen drives? Na hora da auditoria, o desespero."* Abre com pastas bagunçadas. | Imagem genérica |
| 8–22s | *"O YourEyes organiza tudo em uma árvore que já nasce pronta — governança, SST, e a pasta de cada colaborador."* | **PRINT 02** (tela inicial) + **PRINT 03** (árvore) |
| 22–35s | *"Suba um documento e ele vai para o lugar certo, com validade e histórico de versões."* | **PRINT 05** (upload) + **PRINT 09** (versões) |
| 35–50s | *"O sistema avisa antes de vencer — e transforma o alerta em plano de ação."* | **PRINT 10** (notificações) |
| 50–65s | *"Veja a conformidade e a maturidade da governança em um clique."* | **PRINT 11** (conformidade) + **PRINT 12** (radar) |
| 65–80s | *"E tudo com trilha de auditoria: quem fez o quê, quando. YourEyes — governança documental sob controle."* Logo. | **PRINT 14** (auditoria) + tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 6–9 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("vamos abrir…", "agora eu envio…").

1. **Abertura** — o que o módulo faz e para quem (**PRINT 02**).
2. **Passear pela árvore** de pastas, expandir/minimizar e buscar (**PRINT 03**).
3. **Criar uma pasta/subpasta** (**PRINT 04**).
4. **Enviar um documento** com tipo e validade (**PRINT 05, 06**).
5. **Mostrar a pasta de colaborador** e a organização automática (**PRINT 07**).
6. **Mover, visualizar e baixar** um documento (**PRINT 08**).
7. **Nova versão e restauração** (**PRINT 09**).
8. **Configurar e usar as Notificações** de vencimento; **Criar Ação**
   (**PRINT 10**).
9. **Ler o Mapa de Conformidade** (**PRINT 11**).
10. **Mostrar o Radar de Governança** (**PRINT 12**) e o **PDCA** (**PRINT 13**).
11. **Conferir a Trilha de Auditoria** (**PRINT 14**).
12. **Encerramento** — reforçar organização automática, versões e auditoria.

> 💡 Dica de gravação: comece com uma empresa recém-criada para capturar o
> **PRINT 01** ("Gerando estrutura…") e mostrar que o RH não monta nada à mão.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Estado "Gerando estrutura…" (opcional, só tutorial)
- [ ] **PRINT 02** — Tela inicial / aba Estrutura (header, cartões, abas)
- [ ] **PRINT 03** — Árvore de pastas (painel esquerdo, com busca)
- [ ] **PRINT 04** — Modal Nova Pasta
- [ ] **PRINT 05** — Modal Upload de Documento
- [ ] **PRINT 06** — Documento na lista da pasta (selo de status)
- [ ] **PRINT 07** — Pasta de colaborador com subpastas
- [ ] **PRINT 08** — Menu de ações do documento (⋮)
- [ ] **PRINT 09** — Modal Histórico de Versões
- [ ] **PRINT 10** — Aba Notificações (config + alertas + Criar Ação)
- [ ] **PRINT 11** — Aba Conformidade (completude %)
- [ ] **PRINT 12** — Aba Governança (radar)
- [ ] **PRINT 13** — Aba PDCA
- [ ] **PRINT 14** — Aba Auditoria

---

## 9. Erros comuns / dúvidas frequentes

- **"A árvore de pastas está vazia / apareceu 'Gerando estrutura…'."** É normal
  na primeira abertura da empresa — a estrutura padrão está sendo criada
  automaticamente. Aguarde alguns segundos e atualize.
- **"O colaborador não tem pasta."** As pastas de colaboradores ativos são
  criadas sozinhas quando a tela carrega. Confira se a pessoa está **ativa** e
  vinculada à **empresa ativa** selecionada.
- **"Não consigo enviar o arquivo."** Verifique o **formato** (PDF, imagem
  JPG/PNG/WebP ou Word) e o **tamanho** (máximo **50 MB**). O sistema recusa
  outros tipos.
- **"O upload exige colaborador."** Isso acontece quando a pasta de destino é a
  de um colaborador — nesse caso a pessoa é obrigatória e já vem pré-selecionada.
  Para documentos da empresa, envie para uma pasta de área/categoria.
- **"Excluí uma pasta e sumiram os documentos?"** Não: excluir a pasta apaga as
  subpastas, mas os documentos apenas ficam **sem pasta** — não são apagados.
- **"Onde vejo quem mexeu no documento?"** Na aba **Auditoria** (upload, mover,
  renomear, excluir, restaurar), com autor e data.
- **"O documento está marcado como 'Vencendo'."** O status vira **Vencendo** nos
  **30 dias** antes da data de validade e **Vencido** depois dela. Ajuste o aviso
  de antecedência na aba **Notificações**.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/documentos_gestao-de-documentos.md` no projeto.
2. Se quiser conferir as telas descritas, acesse o **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
   Alves**, empresa **Empresa Staging LTDA**, e abra **Documentos & Governança →
   Documentos** — percorra as abas **Estrutura, Conformidade, Governança, PDCA,
   Notificações e Auditoria** conforme os marcadores de print.
3. Confira se o passo a passo, os benefícios e os marcadores de print refletem
   como você quer conduzir os vídeos. Aprovado o **formato**, replico o mesmo
   padrão para os demais módulos.
