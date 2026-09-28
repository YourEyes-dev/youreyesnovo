# Manual do módulo — Afastamentos (Atestados e Afastamentos)

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e na mesma profundidade do piloto aprovado
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial.

- **Onde fica no menu:** seção **Jornada & Rotina → Afastamentos**.
- **Para quem é:** RH, Departamento Pessoal (DP), Medicina do Trabalho e Gestores.
- **Em uma frase:** centraliza o lançamento de **atestados médicos, licenças,
  acidentes de trabalho (CAT) e afastamentos previdenciários (INSS)**, cuida
  sozinho da **régua dos 15 dias**, do **ASO de retorno**, da **estabilidade** e
  do **absenteísmo** — e **abona o dia direto no espelho do ponto**.
- **Importante (LGPD):** este módulo lida com **dado de saúde**, que é
  **sensível** (art. 11 da LGPD). O **CID** só é registrado com autorização e
  nunca deve aparecer em tela de captura, vídeo ou documento com valor real —
  use sempre CIDs de exemplo fictícios (ver box logo abaixo).

> ⚠️ **Aviso de LGPD para TODA captura deste módulo.** Atestado, CID, nome de
> médico e diagnóstico são dados sensíveis. Grave **exclusivamente** no
> ambiente de teste, com as personas fictícias e **CIDs de exemplo**
> (ex.: **F32.0**, **M54.5**, **J11**). Nenhum atestado, CID, nome ou CPF real
> pode entrar em print, vídeo ou PDF. Na dúvida, não grave.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Nunca mais perder o prazo dos 15 dias.** Pela CLT, a empresa paga os
  **primeiros 15 dias** de afastamento; a partir do 16º, o benefício é do
  **INSS**. O sistema acompanha a contagem por colaborador e **avisa antes** de
  o prazo estourar — protegendo a empresa de pagar o que era do INSS.
- **CAT e FAP/RAT sob controle.** Todo acidente de trabalho pede **CAT**; sem
  ela, há risco de multa no **eSocial** e impacto no **FAP** (o multiplicador
  que encarece a contribuição). O módulo abre uma **pendência automática** de
  CAT e mostra o impacto tributário em um painel próprio.
- **ASO de retorno na hora certa.** Afastamento de **30 dias ou mais** exige,
  pela **NR-7**, o **ASO de retorno ao trabalho** antes de o colaborador
  reassumir. O sistema sinaliza os casos pendentes para o RH não deixar passar.
- **Estabilidade rastreada.** Benefício **B91 (acidentário)** gera
  **estabilidade de 12 meses** no retorno. O módulo marca até quando ela vale,
  evitando uma demissão indevida que viraria processo.
- **Saúde mental visível.** Os afastamentos por **CID do grupo F** (transtornos
  mentais) são destacados, e o sistema alerta quando um mesmo setor concentra
  vários casos em pouco tempo — sinal de risco psicossocial.
- **Lançamento em segundos, com IA.** Basta anexar a foto do atestado: a
  extração automática preenche nome, médico, CRM, datas e CID para o RH só
  conferir e salvar.
- **Integração de verdade.** O atestado **abona o dia no espelho do ponto**
  sozinho, o arquivo vai para a **pasta de documentos** do colaborador, e os
  alertas viram **Plano de Ação 5W2H** com um clique.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Atestado** | O documento médico em si (com médico, CRM, datas e, se houver, CID). É o que se lança. |
| **Afastamento** | O período de ausência que o atestado gera. **É criado automaticamente** quando o atestado tem período (dias). |
| **CID** | Código internacional da doença (ex.: F32.0). Dado sensível — só entra com autorização. |
| **Grupo clínico** | A "família" do CID (mental, osteomuscular, respiratório…). O sistema deduz a partir do código. |
| **Regra dos 15 dias** | Até o 15º dia quem paga é a empresa; do 16º em diante é o INSS. A barra de progresso mostra a contagem. |
| **CAT** | Comunicação de Acidente de Trabalho. Obrigatória em acidente; falta dela gera pendência e risco no eSocial. |
| **Nexo com o trabalho** | Se a doença/acidente tem relação com o trabalho (Sim / Em análise / Não). Muda o enquadramento. |
| **B31 / B91** | Benefícios do INSS: **B31** = auxílio-doença comum; **B91** = auxílio-doença **acidentário** (gera estabilidade). |
| **Estabilidade** | Período (12 meses) em que o colaborador não pode ser demitido sem justa causa após alta de B91. |
| **ASO de retorno** | Exame ocupacional obrigatório (NR-7) antes de reassumir, quando o afastamento passa de 30 dias. |
| **Absenteísmo** | O total de ausências e "dias perdidos" — o indicador que mede o impacto na produtividade. |
| **FAP / RAT** | Fatores que definem quanto a empresa paga de contribuição por risco de acidente. Acidentes encarecem. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Colaboradores cadastrados.** O lançamento exige **selecionar um
   colaborador da lista** — o atestado é sempre vinculado a alguém. Sem
   cadastro, não há como salvar.
2. **O documento do atestado em mãos** (foto ou PDF), se for usar a extração
   por IA. É opcional, mas é o que deixa o lançamento rápido no vídeo.
3. **Permissão de acesso.** Alguns painéis (Absenteísmo, Saúde Mental) só
   aparecem para quem tem permissão de **dashboards gerais** — o operador de RH
   padrão (Marina Alves) enxerga as abas de lançamento; os painéis gerenciais
   dependem do perfil.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Afastamentos**, o topo mostra o título **"MOD-GAF"** e o subtítulo
**"Gestão Inteligente de Atestados e Afastamentos"**, com os botões
**Exportar** e **Novo Atestado / Novo Afastamento** (o rótulo muda conforme a
aba). Logo abaixo ficam as **abas** do módulo:

| Aba | Para que serve |
|---|---|
| **Atestados** | A lista de atestados lançados, com busca e filtros. É onde se cria um novo. |
| **Afastamentos** | Os períodos de ausência gerados pelos atestados, com a régua dos 15 dias e os alertas de ASO. |
| **Absenteísmo** | Painel com total de afastamentos e dias perdidos (requer permissão). |
| **Saúde Mental** | Concentração de CID do grupo F e alertas de padrão coletivo (requer permissão). |
| **FAP/RAT** | CAT pendente e impacto tributário dos acidentes (risco eSocial). |
| **Pendências** | O que ainda precisa de ação (CAT sem número, documentos faltando). |

> 📸 **PRINT 01 — Tela inicial do módulo (aba Atestados)**
> **Onde:** menu **Jornada & Rotina → Afastamentos**.
> **O que precisa aparecer:** o título **"MOD-GAF"**, o subtítulo, os botões
> **Exportar** e **Novo Atestado**, e a fileira de abas (Atestados,
> Afastamentos, Absenteísmo, Saúde Mental, FAP/RAT, Pendências).
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; a lista já com
> alguns atestados das personas.
> **Ação filmada:** panorâmica lenta mostrando as abas, terminando na aba
> **Atestados**.

---

## 5. Passo a passo por fluxo

### Fluxo 1 — Lançar um atestado médico (o caso mais comum)

**Objetivo:** registrar o atestado de um colaborador que faltou por doença.
**Benefício:** em um lançamento, o sistema guarda o documento, abona o dia no
ponto e começa a contar a régua dos 15 dias — tudo sozinho.

1. Na aba **Atestados**, clique em **Novo Atestado** (canto superior direito).
2. Em **Tipo de Lançamento**, escolha **Atestado Médico** e, no **Subtipo**,
   **Doença comum** (ou **Odontológico**).
3. Em **Selecionar Colaborador**, busque pelo nome e escolha a pessoa — o
   sistema mostra CPF e cargo, e um **selo** avisa se ela já está afastada.
4. (Opcional) Arraste a **foto ou PDF** do atestado e clique em **Extrair
   dados com IA** — os campos se preenchem sozinhos para você conferir.
5. Em **Profissional Emissor**, informe **Nome do Médico**, **Data de
   Emissão** e **CRM/CRO** (a lupa busca o médico no histórico/base).
6. Em **Período de Afastamento**, deixe a unidade em **Dias**, digite os dias e
   a **Data Início** — a **data de término é calculada automaticamente**.
7. **Salve** — o atestado entra na lista e o afastamento é criado.

> 📸 **PRINT 02 — Aba Atestados (lista com busca e filtros)**
> **Onde:** Afastamentos → aba **Atestados**.
> **O que precisa aparecer:** o campo de busca, os filtros **Tipo** (Atestados
> Médicos / Licenças / Ocupacional) e **Grupo Clínico**, e a lista de cards.
> **Dados fictícios na tela:**
> - **Camila Duarte** — Atestado Médico — grupo **Respiratório** —
>   **3 dias de afastamento** — Dra. Helena Prado (CRM 12345).
> - **Diego Freitas** — Atestado Médico — grupo **Osteomuscular** — 2 dias.
> **Ação filmada:** aplicar o filtro **Grupo Clínico → Osteomuscular**.

> 📸 **PRINT 03 — Modal "Novo Atestado": topo (tipo + colaborador)**
> **Onde:** botão **Novo Atestado**.
> **O que precisa aparecer:** os campos **Tipo de Lançamento** e **Subtipo**, e
> a busca **Selecionar Colaborador** com o cartão do colaborador escolhido.
> **Dados fictícios na tela:** Tipo **Atestado Médico**, Subtipo **Doença
> comum**; colaboradora **Camila Duarte** (CPF **900.000.003-37**, Operadora de
> Produção, Operações).
> **Ação filmada:** abrir a lista de colaboradores, buscar "Camila" e selecioná-la.

> 💡 O colaborador é **obrigatório** — o atestado é sempre vinculado a alguém e
> vai direto para a **pasta de documentos** daquela pessoa.

---

### Fluxo 2 — Anexar o documento e extrair com IA

**Objetivo:** transformar a foto do atestado em campos preenchidos.
**Benefício:** o RH deixa de digitar; só confere e salva.

1. No modal, na seção **Documento**, arraste o arquivo ou clique para
   selecionar (**JPG, PNG ou PDF, até 20 MB**).
2. Clique em **Extrair dados com IA**.
3. Confira o aviso **"Dados extraídos automaticamente. Revise as informações
   antes de salvar."** e revise cada campo preenchido.

> 📸 **PRINT 04 — Upload do documento + extração por IA**
> **Onde:** modal Novo Atestado, seção **Documento**.
> **O que precisa aparecer:** a área de upload com um arquivo carregado, o botão
> **Extrair dados com IA** e o aviso verde de sucesso da extração.
> **Dados fictícios na tela:** arquivo **atestado_exemplo.jpg** (documento
> fictício, sem dado real); aviso de dados extraídos.
> **Ação filmada:** soltar o arquivo, clicar em **Extrair dados com IA** e
> mostrar os campos se preenchendo.

> 💡 A IA é uma **ajuda**, não a palavra final: a responsabilidade é da revisão
> do RH. Sempre confira datas e CID antes de salvar.

---

### Fluxo 3 — Informar o período (dias, horas ou comparecimento)

**Objetivo:** dizer quanto tempo dura a ausência.
**Benefício:** é o período que aciona a régua dos 15 dias e o abono no ponto —
ou que registra apenas horas, quando é só um comparecimento.

1. Na seção **Período de Afastamento**, escolha a **Unidade**: **Dias** ou
   **Horas**.
2. Em **Dias**, digite a quantidade e a **Data Início**; a **Data de término**
   aparece calculada. Use **0 dias** para **prazo indeterminado**.
3. Em **Horas**, informe **horas e minutos** — é o caso do **comparecimento
   médico**: abona só aquele intervalo e o colaborador **segue batendo ponto**.

> 📸 **PRINT 05 — Período de Afastamento (dias e data calculada)**
> **Onde:** modal Novo Atestado, seção **Período de Afastamento**.
> **O que precisa aparecer:** a **Unidade** (Dias), o campo **Dias**, a **Data
> Início** e o box **"Data de término calculada"**.
> **Dados fictícios na tela:** **3 dias**, início **24/09/2026**, término
> calculado **26/09/2026**.
> **Ação filmada:** digitar 3 dias, escolher a data de início e mostrar o
> término aparecendo sozinho.

> 💡 Regra da casa: **comparecimento médico** (em horas, ou **0 dias**) **não
> abre afastamento** — abona só as horas. **Atestado com período (dias)** abre o
> afastamento e entra na régua dos 15 dias. Se você digitar dias, a **Data
> Início vira obrigatória**: sem ela, os dias não contariam para o absenteísmo.

---

### Fluxo 4 — Registrar o CID (dado sensível, com autorização)

**Objetivo:** registrar o diagnóstico quando o atestado o traz.
**Benefício:** habilita a leitura de saúde mental, grupo clínico e nexo — sempre
respeitando a LGPD.

1. Ligue a chave **Contém CID?**.
2. Digite o **Código CID** (ex.: **F32.0**) — o sistema busca e sugere o
   **grupo clínico** automaticamente.
3. Informe o **Nexo com o Trabalho** (Não / Em análise / Sim).

> 📸 **PRINT 06 — Bloco CID (com aviso de LGPD)**
> **Onde:** modal Novo Atestado, chave **Contém CID?** ligada.
> **O que precisa aparecer:** a chave ligada, o texto **"Ao enviar ao RH, o
> colaborador autoriza o uso do CID (LGPD/CFM)"**, o campo **Código CID** e o
> **Nexo com o Trabalho**.
> **Dados fictícios na tela:** CID **F32.0** (exemplo fictício), grupo clínico
> sugerido **Saúde Mental**, nexo **Não**.
> **Ação filmada:** ligar a chave, digitar F32.0 e mostrar o grupo clínico
> preenchendo sozinho.

> 💡 **LGPD.** O CID só entra com autorização — por isso o texto do CFM aparece
> ao lado da chave. Na captura, use **sempre um CID de exemplo**; nunca um real.

---

### Fluxo 5 — Afastamento longo: o Benefício INSS aparece sozinho

**Objetivo:** registrar o benefício quando a ausência passa de 15 dias.
**Benefício:** o RH não precisa abrir um lançamento separado — a seção do INSS
surge no mesmo formulário.

1. Ao digitar **mais de 15 dias** (ou escolher o tipo **Afastamento INSS**), a
   seção **Benefício INSS** aparece automaticamente.
2. Escolha a **Espécie**: **B31** (auxílio-doença comum) ou **B91**
   (acidentário).
3. Informe **número do benefício**, **data de início** e, quando houver,
   **data da alta**.

> 📸 **PRINT 07 — Bloco Benefício INSS (auto ao passar de 15 dias)**
> **Onde:** modal Novo Atestado, com o período acima de 15 dias.
> **O que precisa aparecer:** a seção **Benefício INSS** com o aviso de que foi
> habilitada automaticamente, e os campos Espécie, Número, Data de início e
> Data da alta.
> **Dados fictícios na tela:** **20 dias** de afastamento; espécie **B91**,
> número **900.000.111-2** (fictício), início **24/09/2026**.
> **Ação filmada:** subir o número de dias para 20 e mostrar a seção do INSS
> aparecendo.

> 💡 O **B91** (acidentário) gera **estabilidade de 12 meses** no retorno — o
> módulo passa a mostrar até quando ela vale, e isso vira alerta na lista.

---

### Fluxo 6 — Acidente de trabalho: dados da CAT

**Objetivo:** registrar o acidente e garantir a CAT.
**Benefício:** evita multa no eSocial e alimenta o painel de FAP/RAT.

1. Em **Tipo de Lançamento**, escolha **Acidente de Trabalho** e o subtipo
   (**típico**, **trajeto** ou **doença ocupacional**) — o **nexo** já entra
   como **Sim**.
2. Preencha o bloco **Dados do Acidente (CAT)**: número da CAT, data, hora,
   local, parte do corpo, agente causador e descrição.
3. Se você **não** tiver o número da CAT ainda, pode salvar mesmo assim — o
   sistema abre uma **pendência de CAT** no RH para não esquecer.

> 📸 **PRINT 08 — Bloco Dados do Acidente (CAT)**
> **Onde:** modal Novo Atestado, tipo **Acidente de Trabalho**.
> **O que precisa aparecer:** o bloco destacado **"Dados do Acidente (CAT)"**
> com os campos número/data/hora/local/parte do corpo/agente/descrição e o aviso
> **"Se vazio, será gerada uma pendência no RH."**
> **Dados fictícios na tela:** colaborador **Diego Freitas**; parte do corpo
> **Mão direita**, agente **Máquina**, data **22/09/2026**; número da CAT em
> branco (para mostrar a pendência).
> **Ação filmada:** escolher Acidente de Trabalho e mostrar o bloco da CAT
> surgindo abaixo.

> 💡 CAT sem número **não trava** o lançamento — vira **pendência crítica** na
> aba **Pendências** e no painel **FAP/RAT**, para o RH resolver depois.

---

### Fluxo 7 — Ler a aba Afastamentos (régua 15 dias e ASO)

**Objetivo:** acompanhar quem está afastado e por quanto tempo.
**Benefício:** numa lista o RH vê a contagem dos 15 dias, quem precisa de
encaminhamento ao INSS e quem precisa do ASO de retorno.

1. Abra a aba **Afastamentos** — os registros foram criados **automaticamente**
   pelos atestados.
2. Cada card mostra **colaborador**, **status** (Ativo / Encerrado / Benefício
   INSS), **motivo**, **período**, **dias totais** e a barra **"Regra 15 dias
   (empresa x INSS)"**.
3. Fique de olho nos avisos: **próximo de 15 dias** (amarelo) e **ASO de
   Retorno pendente** para afastamento **≥30 dias** (vermelho).

> 📸 **PRINT 09 — Aba Afastamentos (régua 15 dias e alertas)**
> **Onde:** Afastamentos → aba **Afastamentos**.
> **O que precisa aparecer:** um card com o status, os dias totais, a **barra de
> progresso dos 15 dias** e um card com o alerta **"ASO de Retorno Pendente"**.
> **Dados fictícios na tela:**
> - **Camila Duarte** — Ativo — Respiratório — **3/15** na barra.
> - **Diego Freitas** — Benefício INSS — **32 dias** — alerta vermelho de **ASO
>   de Retorno pendente**.
> **Ação filmada:** rolar a lista mostrando a barra e o alerta vermelho.

> 💡 A barra dos 15 dias é a "conta da empresa": ao chegar perto do 15º dia, é
> hora de preparar o **encaminhamento ao INSS**.

---

### Fluxo 8 — Tratar alertas e criar Plano de Ação (5W2H)

**Objetivo:** transformar um alerta em tarefa.
**Benefício:** o encaminhamento ao INSS ou o ASO de retorno viram ação com
responsável e prazo, sem sair do sistema.

1. Quando um afastamento passa de **15 dias** (num único atestado ou acumulado
   em 90 dias pelo mesmo grupo clínico), o sistema **sugere o encaminhamento ao
   INSS** automaticamente.
2. No alerta, clique em **Criar ação** — o sistema abre sugestões prontas
   (encaminhar ao INSS, agendar ASO de retorno, notificar o gestor).
3. Escolha uma sugestão e confirme, ou clique em **Criar manualmente** para ir
   ao módulo **Plano de Ação**.

> 📸 **PRINT 10 — Sugestões de ação (Criar ação a partir do alerta)**
> **Onde:** clique em **Criar ação** num alerta de encaminhamento INSS ou ASO.
> **O que precisa aparecer:** o modal **"Sugestões de Ação — IA"** com as
> sugestões (o quê, por quê, onde, como) e os botões **Criar manualmente** e
> **Criar ação selecionada**.
> **Dados fictícios na tela:** alerta **"Encaminhamento ao INSS sugerido —
> Diego Freitas"**; sugestão **"Encaminhar Colaborador ao INSS"** selecionada.
> **Ação filmada:** abrir o modal, selecionar a sugestão e criar a ação.

> 💡 A ação criada vai para o módulo **Plano de Ação** com prazo padrão de
> **7 dias** — de lá o RH acompanha até concluir.

---

### Fluxo 9 — A integração com o ponto (o dia abonado sozinho)

**Objetivo:** mostrar que o atestado abona o dia no espelho do ponto.
**Benefício:** o RH lança o atestado uma vez e o ponto já reflete — sem lançar
falta indevida nem digitar duas vezes.

1. Lance um atestado **com período** (Fluxo 1) para uma colaboradora CLT.
2. Abra o módulo **Ponto → Espelho** no dia do atestado.
3. O dia aparece com o **selo Atestado/Afastamento**, sem gerar falta.

> 📸 **PRINT 11 — Integração: o dia abonado no espelho do ponto**
> **Onde:** módulo **Ponto → Espelho**, no dia do atestado lançado.
> **O que precisa aparecer:** a linha da colaboradora com o **selo Atestado**
> (violeta) no dia, sem marcação de falta.
> **Dados fictícios na tela:** **Camila Duarte**, dia **24/09/2026** com selo
> **Atestado**.
> **Ação filmada:** ir do módulo Afastamentos ao módulo Ponto e mostrar o mesmo
> dia já abonado.

> 💡 Se o atestado for **excluído**, o ponto é **revertido automaticamente** —
> o dia volta ao que era, sem intervenção manual.

---

### Fluxo 10 — Os painéis gerenciais (Absenteísmo, Saúde Mental, FAP/RAT)

**Objetivo:** enxergar o quadro geral, não só caso a caso.
**Benefício:** os números que a diretoria pede — dias perdidos, saúde mental,
risco tributário — já saem calculados.

- **Absenteísmo:** total de afastamentos e **dias perdidos** no período — o
  impacto direto na produtividade.
- **Saúde Mental:** total de afastamentos com **CID do grupo F** e **alertas de
  padrão coletivo** (setores com concentração de casos em 90 dias).
- **FAP/RAT:** **CAT pendente** (risco de multa eSocial) e **impacto FAP
  confirmado** (custo tributário).
- **Pendências:** o que ainda precisa de ação (CAT sem número, documentos).

> 📸 **PRINT 12 — Painel Absenteísmo**
> **Onde:** Afastamentos → aba **Absenteísmo**.
> **O que precisa aparecer:** os cartões **Total de Afastamentos** e **Dias
> Perdidos**.
> **Dados fictícios na tela:** **8 afastamentos**, **41 dias perdidos**.

> 📸 **PRINT 13 — Painel Saúde Mental**
> **Onde:** Afastamentos → aba **Saúde Mental**.
> **O que precisa aparecer:** o cartão **Total Saúde Mental (CID F)** e o de
> **Alertas de Padrão Coletivo**.
> **Dados fictícios na tela:** **2 registros CID F**, **1 setor** em alerta.

> 📸 **PRINT 14 — Painel FAP/RAT**
> **Onde:** Afastamentos → aba **FAP/RAT**.
> **O que precisa aparecer:** os cartões **CAT Pendente** e **Impacto FAP
> Confirmado**.
> **Dados fictícios na tela:** **1 CAT pendente**, **1 impacto FAP confirmado**.

> 💡 Os painéis **Absenteísmo** e **Saúde Mental** só aparecem para quem tem
> permissão de dashboards gerais — se a sua Marina Alves de teste não os vê, é o
> perfil de acesso, não um erro.

---

### Fluxo 11 — Exportar a base

**Objetivo:** levar os dados para uma planilha.
**Benefício:** relatório rápido para reunião ou conferência, sem sair da tela.

1. No topo, clique em **Exportar**.
2. O sistema baixa um **CSV** com atestados e afastamentos (tipo, colaborador,
   CID, datas, dias, motivo, status).

> 📸 **PRINT 15 — Botão Exportar (CSV)**
> **Onde:** topo do módulo Afastamentos, botão **Exportar**.
> **O que precisa aparecer:** o botão **Exportar** e, se possível, o arquivo
> **mod-gaf-AAAA-MM-DD.csv** sendo baixado.
> **Dados fictícios na tela:** apenas dados das personas fictícias.

> 💡 O CSV **também carrega CID**: trate o arquivo como **documento sensível** —
> nada de compartilhar fora do RH nem anexar em vídeo com dado real.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, mostrando dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Atestado empilhado em gaveta? Prazo do INSS perdido vira prejuízo."* Abre com papéis bagunçados. | Imagem genérica de papelada |
| 8–22s | *"No YourEyes, você anexa a foto do atestado e a IA preenche tudo."* | **PRINT 04** (extração IA) + **PRINT 03** (colaborador) |
| 22–36s | *"O sistema conta os 15 dias sozinho e avisa antes de a conta virar do INSS."* | **PRINT 09** (régua 15 dias) |
| 36–50s | *"Acidente de trabalho? CAT controlada, sem risco de multa no eSocial."* | **PRINT 08** (CAT) + **PRINT 14** (FAP/RAT) |
| 50–64s | *"E o dia já cai abonado no ponto, sem lançar nada duas vezes."* | **PRINT 11** (espelho do ponto) |
| 64–80s | *"Afastamentos sob controle. Saúde da equipe, protegida por lei."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 5–8 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("agora eu lanço…", "veja como o sistema avisa…").

1. **Abertura** — o que o módulo faz e para quem (**PRINT 01**).
2. **Lançar um atestado médico** — tipo, colaborador (**PRINT 03**).
3. **Anexar e extrair com IA** (**PRINT 04**).
4. **Informar o período** e ver a data de término calculada (**PRINT 05**).
5. **Registrar o CID** com o aviso de LGPD (**PRINT 06**).
6. **Salvar e ver na lista** (**PRINT 02**).
7. **Afastamento longo** — mostrar a seção do INSS aparecendo (**PRINT 07**).
8. **Acidente de trabalho** — dados da CAT (**PRINT 08**).
9. **Aba Afastamentos** — régua dos 15 dias e ASO de retorno (**PRINT 09**).
10. **Criar ação** a partir de um alerta (**PRINT 10**).
11. **Integração com o ponto** — o dia abonado (**PRINT 11**).
12. **Painéis** — Absenteísmo, Saúde Mental, FAP/RAT (**PRINT 12, 13, 14**).
13. **Exportar** a base (**PRINT 15**).
14. **Encerramento** — reforçar o cuidado com LGPD ao gravar e circular dados.

> 💡 Dica de gravação: grave o **caso completo da Camila** (atestado curto) e o
> **caso do Diego** (afastamento longo com INSS e ASO) — assim os prints das
> abas Afastamentos e dos painéis ficam com dados coerentes entre si.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**. **Somente dados
fictícios e CIDs de exemplo.**

- [ ] **PRINT 01** — Tela inicial (MOD-GAF, aba Atestados)
- [ ] **PRINT 02** — Aba Atestados (lista, busca e filtros)
- [ ] **PRINT 03** — Modal Novo Atestado: tipo + colaborador
- [ ] **PRINT 04** — Upload do documento + extração por IA
- [ ] **PRINT 05** — Período de Afastamento (dias + data calculada)
- [ ] **PRINT 06** — Bloco CID (com aviso de LGPD)
- [ ] **PRINT 07** — Bloco Benefício INSS (auto > 15 dias)
- [ ] **PRINT 08** — Bloco Dados do Acidente (CAT)
- [ ] **PRINT 09** — Aba Afastamentos (régua 15 dias e ASO)
- [ ] **PRINT 10** — Sugestões de ação (Criar ação)
- [ ] **PRINT 11** — Integração: dia abonado no espelho do ponto
- [ ] **PRINT 12** — Painel Absenteísmo
- [ ] **PRINT 13** — Painel Saúde Mental
- [ ] **PRINT 14** — Painel FAP/RAT
- [ ] **PRINT 15** — Botão Exportar (CSV)

---

## 9. Erros comuns / dúvidas frequentes

- **"Não consigo salvar — pede a data de início."** Você informou dias (ou
  horas) mas não a **Data Início**. Com período informado, a data de início é
  obrigatória; sem ela os dias não entrariam no absenteísmo.
- **"Lancei o atestado mas não apareceu afastamento."** Foi um
  **comparecimento** (em horas, ou **0 dias**): esse caso **abona só as horas** e
  **não** abre afastamento, de propósito. Afastamento só nasce de atestado com
  **período em dias**.
- **"O colaborador não aparece para selecionar."** O atestado exige
  **colaborador cadastrado**; confira o cadastro e se ele está vinculado à
  empresa ativa.
- **"A seção de Benefício INSS não apareceu."** Ela surge sozinha ao passar de
  **15 dias** ou no tipo **Afastamento INSS**. Abaixo disso, não é necessária.
- **"Salvei o acidente sem o número da CAT."** É permitido — o sistema abre uma
  **pendência crítica de CAT** (abas **Pendências** e **FAP/RAT**). Informe o
  número depois e a pendência é resolvida.
- **"Não vejo os painéis Absenteísmo/Saúde Mental."** Eles dependem de
  **permissão de dashboards gerais**; é o perfil de acesso, não um erro.
- **"O dia continua como falta no ponto."** Confira se o atestado foi lançado
  **com período** e para a **colaboradora CLT correta** — o abono do ponto vem
  do atestado com dias; comparecimento em horas não zera o dia inteiro.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/afastamentos_atestados-e-afastamentos.md` no
   projeto.
2. Se quiser conferir cada tela citada, acesse o **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
   Alves**, e navegue em **Jornada & Rotina → Afastamentos** — confira que os
   passos, os benefícios e os marcadores de print refletem o que você quer nos
   vídeos (lembrando: **só dados fictícios e CIDs de exemplo**).
3. Aprovado o **formato**, replico o mesmo padrão para os próximos módulos, nos
   lotes que você priorizar.
