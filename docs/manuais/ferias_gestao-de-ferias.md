# Manual do módulo — Gestão de Férias

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e na mesma profundidade do piloto [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial do módulo de Férias.

- **Onde fica no menu:** seção **Jornada & Rotina → Férias**.
- **Para quem é:** RH, Departamento Pessoal (DP), Gestores e Diretoria.
- **Em uma frase:** planeja, aprova, documenta e paga as férias dos
  colaboradores CLT em conformidade com a CLT (arts. 129 a 145), tratando
  férias como **organização do trabalho e recuperação humana** — não como mera
  ausência.
- **Importante:** férias são direito **exclusivo de vínculos CLT**. PJ,
  pró-labore e terceiros são propositalmente excluídos das listas do módulo.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Fim do passivo em dobro.** Férias não concedidas dentro do período
  concessivo custam **em dobro** (art. 137 da CLT). O módulo vigia cada
  vencimento (**D-90 / D-60 / D-30**), calcula o custo da dobra antes de ela
  acontecer e transforma o risco em uma ação no Plano de Ação.
- **Planejamento anual de verdade.** A aba **Programação** monta o plano de 12
  meses de toda a equipe, com saldo e valor reais, validando cada data contra a
  CLT (fracionamento, limite concessivo, abono) na hora em que o RH digita.
- **Conformidade CLT automática.** Fracionamento em até 3 períodos (um ≥ 14
  dias, nenhum < 5 dias), abono de até 1/3, aviso com 30 dias de antecedência e
  ciência do colaborador — tudo verificado pelo sistema, com base legal citada.
- **Documento certo, assinado e arquivado.** Aviso e recibo de férias são
  gerados em PDF/HTML, enviados para **assinatura digital** por link (WhatsApp)
  e arquivados sozinhos no módulo **Documentos**, na pasta do colaborador.
- **Provisão financeira confiável.** O módulo estima a provisão de férias com
  terço e encargos parametrizáveis por regime tributário e projeta o
  **desembolso mês a mês** — número que fala a mesma língua da folha.
- **Saúde antes do burnout.** O **INR™** (Indicador de Necessidade de
  Recuperação) cruza humor, ponto, afastamentos e vencimentos para apontar quem
  precisa descansar já — e gera a **evidência NR-1** que a Portaria MTE
  1.419/2024 passou a exigir.
- **Férias coletivas sem dor de cabeça.** Programa por setor, marca os novatos
  proporcionais (art. 140) e gera os comunicados obrigatórios ao MTE, ao
  sindicato e aos empregados dentro do prazo de 15 dias.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Período aquisitivo** | Os 12 meses de trabalho que dão direito às férias. |
| **Período concessivo** | Os 12 meses **seguintes**, prazo em que a empresa tem de conceder as férias. Estourou → paga em dobro. |
| **Limite concessivo** | A data-limite do concessivo. É o "relógio" que o módulo vigia. |
| **Fracionamento** | Dividir as férias em até **3 períodos** (um ≥ 14 dias; nenhum < 5 dias) — art. 134, §1º. |
| **Abono pecuniário** | "Vender" até **1/3** das férias (no máximo 10 dias) e receber em dinheiro — art. 143. |
| **Aviso de férias** | Comunicação formal ao colaborador com **30 dias** de antecedência (art. 135). |
| **Ciência** | A confirmação (assinatura) de que o colaborador **recebeu o aviso**. Sem ela, o gozo não inicia. |
| **Recibo de férias** | Comprovante do pagamento das férias, também assinável. |
| **Provisão** | O passivo contábil acumulado de férias (base + 1/3 + encargos). |
| **Passivo em dobro** | O custo extra das férias já vencidas (art. 137). |
| **INR™** | Indicador de Necessidade de Recuperação — score de 0 a 100 do quanto cada pessoa precisa descansar. |
| **Férias coletivas** | Férias concedidas ao setor inteiro de uma vez (arts. 139-141). |
| **Art. 140** | Novatos (menos de 12 meses) entram na coletiva com férias **proporcionais** e reiniciam o aquisitivo. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Colaboradores CLT ativos cadastrados**, com **data de admissão** e
   **CPF** — é o CPF que liga cada pessoa aos seus períodos e saldos.
2. **Salário base** preenchido (vem das admissões) — sem ele, a simulação
   financeira, a provisão e o recibo saem zerados.
3. **Saldos de férias importados** (aba **Saldos → Importar saldos**) para quem
   já tinha períodos antes de entrar no sistema. Sem saldo importado, a aba
   **Programação** fica indisponível e o saldo aparece apenas como **estimado**
   (30 dias fixos).

> 💡 A ordem natural de uso é: **cadastrar/admitir → importar saldos →
> programar o ano → solicitar/aprovar → gerar e assinar documentos → pagar**.
> Os fluxos abaixo seguem essa mesma ordem.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Férias**, o topo mostra o título **"Gestão de Férias"** com o
subtítulo *"Ferramenta de organização do trabalho e recuperação humana"* e o
botão **Nova Solicitação**. Abaixo, uma faixa de **7 indicadores**: Pendentes,
Aprovadas, Em Gozo, Concluídas, Com Abono, Preventivas e **Provisão** (em R$).

Depois vêm as **11 abas** do módulo e um **filtro de status** à direita:

| Aba | Para que serve |
|---|---|
| **Programação** | Plano anual de férias de toda a equipe, validado contra a CLT. |
| **Solicitações** | As solicitações em cartões: aprovar, recusar e gerar documentos. |
| **Calendário** | Visão de calendário de quem está/estará de férias. |
| **Saldos** | Saldo, período aquisitivo e vencimento por colaborador; importação. |
| **Financeiro** | Provisão, desembolso projetado e passivo em dobro. |
| **INR™** | Inteligência de recuperação e evidência NR-1. |
| **Vencimentos** | Alertas de férias a vencer e vencidas (risco de dobro). |
| **Coletivas** | Programação de férias coletivas por setor. |
| **Cultura** | Mensagens de pré-férias e check-in de retorno. |
| **Relatórios** | Indicadores estratégicos (efetividade, custo, risco). |
| **Governança** | Selo de maturidade, checklist de diligência e vínculo familiar. |

> 📸 **PRINT 01 — Tela inicial do módulo**
> **Onde:** menu **Jornada & Rotina → Férias**.
> **O que precisa aparecer:** título "Gestão de Férias", o botão **Nova
> Solicitação**, a faixa de 7 indicadores e a linha das 11 abas.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; indicadores
> como "3 Pendentes, 5 Aprovadas, 1 Em Gozo, Provisão R$ 48k".
> **Ação filmada:** panorâmica lenta mostrando os indicadores e as abas.

---

## 5. Passo a passo por fluxo

### Fluxo 1 — Importar os saldos de férias

**Objetivo:** trazer os períodos aquisitivos e os dias já gozados de quem já
tinha histórico antes do sistema.
**Benefício:** o saldo passa a ser o **real** (calculado por avos e faltas —
art. 130), e não o "30 fixo" estimado; só assim a Programação libera.

1. Abra a aba **Saldos**.
2. Clique em **Importar saldos**.
3. **Baixe o modelo (.xlsx)** — uma linha por período aquisitivo; **CPF é
   obrigatório**.
4. Preencha faltas e dias já gozados por período e **envie a planilha**.
5. Confira a prévia (o que será criado, atualizado ou tem problema) e clique em
   **Importar**. Nada é gravado antes dessa conferência.

> 📸 **PRINT 02 — Aba Saldos**
> **Onde:** Férias → **Saldos**.
> **O que precisa aparecer:** os 3 cartões de resumo (Colaboradores; Vencem em
> até 90 dias; Férias vencidas), a busca, o botão **Importar saldos** e a tabela
> com saldo, usados, progresso, período aquisitivo e vencimento.
> **Dados fictícios na tela:**
> - **Camila Duarte** — saldo **30d de 30d**, vencimento verde (no prazo).
> - **Bruno Carvalho** — vencimento **âmbar** ("faltam 45 dias").
> - **Diego Freitas** — linha destacada em vermelho, vencimento **Vencida**.

> 📸 **PRINT 03 — Modal "Importar saldos"**
> **Onde:** Saldos → **Importar saldos**.
> **O que precisa aparecer:** a trilha de 3 passos (Modelo → Conferência →
> Concluído), o botão **Baixar modelo** e a tabela de prévia com selos "novo" /
> "atualizar" / "não encontrado".
> **Dados fictícios na tela:** "Serão importadas **12**", "Novos **9**",
> "Atualizados **3**", "Com problema **0**".

> 💡 Se um colaborador teve muitas faltas no período, a zeragem entra numa
> **fila de validação** (art. 130) e só zera o saldo após a conferência do RH.

---

### Fluxo 2 — Programar as férias do ano

**Objetivo:** montar o plano de 12 meses de toda a equipe.
**Benefício:** as datas nascem já checadas contra a CLT; nada é aprovado no
susto e o RH enxerga a cobertura e os vencimentos num painel só.

1. Abra a aba **Programação** (precisa de saldos importados).
2. Use a busca e o filtro de prazo (**Vencidas / Vencendo 90d / No prazo**).
3. Clique no lápis de um colaborador para abrir a edição.
4. Preencha **Período 1** (≥ 14 dias), e, se fracionar, **Períodos 2 e 3**
   (≥ 5 dias cada). Ative **abono** (vender até 1/3) e **adiantar 13º** se for
   o caso.
5. O sistema valida em tempo real e mostra **bloqueios** (vermelho),
   **alertas** (âmbar) e **avisos** (azul) com a base legal. **Salve**.
6. Depois, **confirme** a programação e, quando quiser, **converta em
   solicitação** (a seta) — o que leva o registro para a aba Solicitações.

> 📸 **PRINT 04 — Aba Programação (grade)**
> **Onde:** Férias → **Programação**.
> **O que precisa aparecer:** os 4 mini-cartões (Colaboradores, Com programação,
> Cobertura %, Vencendo/vencidas), a faixa azul explicativa e a grade com
> colunas Aquisitivo, Saldo, Limite, Programação, Não prog., Valor est. e Status.
> **Dados fictícios na tela:** **Marina Alves** com "P1 20d · P2 10d",
> cobertura **72%**, status **Planejado**; **Diego Freitas** com limite em
> vermelho (**Vencida**).
> **Ação filmada:** aplicar o filtro "Vencendo (90d)".

> 📸 **PRINT 05 — Edição da programação (validação CLT)**
> **Onde:** Programação → lápis de um colaborador.
> **O que precisa aparecer:** os blocos Período 1/2/3, o abono, o "adiantar 13º"
> e um aviso do motor de regras com a base legal citada; o rodapé "Total
> programado Xd de Yd".
> **Dados fictícios na tela:** **Bruno Carvalho** — P1 **14d** (01/12 a 14/12),
> P2 **10d**, abono **6 dias**; aviso azul "Fracionamento — art. 134".

> 📸 **PRINT 06 — Programação além do limite concessivo**
> **Onde:** Programação → edição de um colaborador com período vencido.
> **O que precisa aparecer:** o alerta vermelho "Programação além do limite
> concessivo (art. 134)" com o custo estimado da dobra e a chave de **Autorizar
> a exceção (alçada de diretoria)**.
> **Dados fictícios na tela:** **Diego Freitas** — "devia ser concedida até
> 30/06/2026", custo estimado da dobra **R$ 3.200,00**.

> 📸 **PRINT 07 — Linha do tempo da programação**
> **Onde:** Programação → botão **Linha do tempo**.
> **O que precisa aparecer:** as barras de férias de cada colaborador ao longo
> dos 12 meses, permitindo enxergar sobreposições de setor.
> **Ação filmada:** alternar entre **Grade** e **Linha do tempo**.

> 💡 Programação já **confirmada ou solicitada** trava a edição pela grade — a
> partir daí a alteração é feita pela aba **Solicitações**, para as duas telas
> nunca divergirem.

---

### Fluxo 3 — Criar uma solicitação de férias

**Objetivo:** registrar um pedido de férias com validação CLT.
**Benefício:** o sistema recusa fracionamento inválido e abono acima de 1/3
antes de gravar, e já calcula os valores brutos (férias + 1/3 + abono).

1. Clique em **Nova Solicitação** no topo.
2. **Selecione o colaborador** — departamento, CPF e salário base são
   preenchidos sozinhos.
3. Informe o **Período de Gozo** (início e fim) — o total de dias aparece na
   hora.
4. Preencha o **Período Aquisitivo** de referência.
5. Se houver **abono pecuniário**, ligue a chave e informe os dias (máx. 10) —
   a **simulação** mostra Férias, 1/3 constitucional, Abono e Total bruto.
6. Clique em **Criar Solicitação**.

> 📸 **PRINT 08 — Modal "Nova Solicitação de Férias"**
> **Onde:** botão **Nova Solicitação** (topo).
> **O que precisa aparecer:** o seletor de colaborador, o período de gozo com o
> total calculado, o período aquisitivo e o bloco de abono com a **Simulação**.
> **Dados fictícios na tela:** colaboradora **Camila Duarte** (900.000.003-37),
> gozo **05/01/2026 a 24/01/2026** (**20 dias**), abono **10 dias**, salário
> base **R$ 2.400,00**; simulação com Total bruto **R$ 4.000,00**.
> **Ação filmada:** selecionar a Camila, ligar o abono e mostrar a simulação
> mudando.

> 💡 O sistema aplica o art. 134 na hora: no máximo 3 períodos, um ≥ 14 dias,
> nenhum < 5 dias. O abono é limitado a 1/3 (10 dias) pelo art. 143.

---

### Fluxo 4 — Aprovar (ou recusar) e acompanhar o status

**Objetivo:** decidir sobre as solicitações e acompanhar o ciclo.
**Benefício:** cada aprovação/recusa fica com **autor e data** registrados —
trilha auditável, exigência de segurança do sistema (não é texto livre).

1. Abra a aba **Solicitações**.
2. Filtre por status pelo seletor à direita (Pendente, Aprovado, Em Gozo,
   Concluído, Recusado).
3. No cartão **pendente**, clique em **Aprovar** ou **Recusar**. Ao aprovar, o
   sistema **avisa se há sobreposição** de férias no mesmo setor.

> 📸 **PRINT 09 — Aba Solicitações (cartões)**
> **Onde:** Férias → **Solicitações**.
> **O que precisa aparecer:** vários cartões com avatar, status colorido,
> período, dias, e um cartão pendente com os botões **Aprovar / Recusar**.
> **Dados fictícios na tela:**
> - **Camila Duarte** — 05/01 a 24/01, **20 dias**, **Pendente**, selo abono.
> - **Eduarda Lima** — **Aprovado**.
> - **Bruno Carvalho** — **Em Gozo**; selo **INR™** (férias preventiva).
> **Ação filmada:** clicar em **Aprovar** no cartão da Camila.

> 💡 O selo **INR™** num cartão indica que aquelas férias nasceram como **ação
> preventiva** sugerida pela inteligência do módulo.

---

### Fluxo 5 — Gerar o aviso, colher a ciência e iniciar o gozo

**Objetivo:** cumprir o art. 135 (aviso e ciência) antes das férias começarem.
**Benefício:** o gozo só inicia com a ciência registrada — trava do próprio
banco que protege a empresa de conceder férias "sem avisar".

Depois de **aprovada**, o cartão mostra as **Ações pós-aprovação**:

1. **Gerar Aviso** — cria o PDF do aviso de férias e o arquiva em Documentos.
2. **Aviso p/ Assinar** — gera um **link de assinatura** do aviso (Fluxo 7).
3. Alternativa sem assinatura digital: **Registrar ciência (papel)** — grava
   quem e quando colheu a ciência fora do sistema.
4. Com a ciência registrada, clique em **Iniciar Gozo** — o status vira **Em
   Gozo**. (Sem ciência, o sistema recusa e explica o porquê.)

> 📸 **PRINT 10 — Ações pós-aprovação no cartão**
> **Onde:** Solicitações → cartão de uma solicitação **Aprovada**.
> **O que precisa aparecer:** os botões **Gerar Aviso**, **Gerar Recibo**,
> **Reg. Financeiro**, **Aviso p/ Assinar**, **Enviar Recibo p/ Assinatura**,
> **Registrar ciência (papel)**, **Iniciar Gozo** e **Publicar no Feed**.
> **Dados fictícios na tela:** cartão da **Eduarda Lima** (Aprovado); "Aviso"
> já com o ✓.
> **Ação filmada:** clicar em **Gerar Aviso** e mostrar o aviso arquivado.

> 💡 **Publicar no Feed** posta um recado simpático de "boas férias" no mural da
> empresa — cuidado que aparece no vídeo comercial.

---

### Fluxo 6 — Gerar o recibo e o registro financeiro

**Objetivo:** produzir o comprovante de pagamento e lançar o valor na folha.
**Benefício:** o recibo sai pronto e arquivado, e o valor bruto já vira um item
de folha com o vencimento certo (até 2 dias úteis antes — art. 145).

1. No cartão aprovado, clique em **Gerar Recibo** (PDF arquivado em Documentos).
2. Clique em **Reg. Financeiro** — o sistema cria/usa o período de folha da
   competência e lança o valor com a data de vencimento calculada.

> 📸 **PRINT 11 — Aba Financeiro**
> **Onde:** Férias → **Financeiro**.
> **O que precisa aparecer:** a faixa azul de "estimativa gerencial", os 3
> cartões (**Provisão de férias**, **Desembolso projetado**, **Passivo em
> dobro**), o gráfico de **fluxo de desembolso** de 12 meses e a **memória de
> cálculo** recolhível.
> **Dados fictícios na tela:** Provisão **R$ 48.200,00**; Passivo em dobro
> **R$ 3.200,00** ("1 período vencido — art. 137"); taxa de encargos **~36,8%**.
> **Ação filmada:** abrir **Parâmetros de encargos** e mostrar INSS/RAT×FAP/
> Terceiros/FGTS e a chave do **Simples Nacional**.

> 💡 A provisão do módulo é **estimativa gerencial** — concilie com a folha
> antes de usar como provisão contábil oficial. A taxa de encargos muda por
> regime tributário (o Simples dispensa a parte patronal em vários anexos).

---

### Fluxo 7 — Assinatura digital do aviso e do recibo

**Objetivo:** colher a assinatura do colaborador à distância.
**Benefício:** ciência e recibo assinados com **IP e data/hora** registrados;
o documento assinado é arquivado sozinho e libera o início do gozo.

1. No cartão, clique em **Aviso p/ Assinar** (ou **Enviar Recibo p/
   Assinatura**).
2. O sistema mostra o **link**; copie ou clique em **Enviar via WhatsApp**.
3. O colaborador abre o link, confere os dados, **desenha a assinatura** e
   confirma.
4. Depois, o RH pode clicar em **Ver Recibo Assinado** para abrir a versão
   assinada.

> 📸 **PRINT 12 — Link de assinatura gerado**
> **Onde:** cartão → **Aviso p/ Assinar**.
> **O que precisa aparecer:** o campo com o link, o botão **Copiar** e o botão
> verde **Enviar via WhatsApp**.
> **Dados fictícios na tela:** "Link gerado para **Camila Duarte**".

> 📸 **PRINT 13 — Tela de assinatura do colaborador**
> **Onde:** o link `/ferias-assinatura/<token>` aberto (idealmente no celular).
> **O que precisa aparecer:** o cabeçalho (Aviso ou Recibo de Férias), os dados
> do período, a prévia do documento e o campo de **assinatura** (desenho) com o
> botão **Confirmar Assinatura**.
> **Dados fictícios na tela:** **Camila Duarte**, departamento **Operações**,
> período **05/01/2026 a 24/01/2026**, **20 dias**.
> **Ação filmada:** ótimo momento para gravar a tela real de um celular
> assinando com o dedo.

> 💡 A tela de assinatura avisa: *"Ao assinar, você confirma ciência do aviso.
> Seu IP e data/hora serão registrados para auditoria."*

---

### Fluxo 8 — Vencimentos: agir antes da dobra

**Objetivo:** não deixar nenhuma férias vencer.
**Benefício:** os alertas nascem sozinhos (varredura diária) com o custo
estimado da dobra e o atalho para o Plano de Ação.

1. Abra a aba **Vencimentos**.
2. Veja os alertas por faixa: **Vence em ≤ 90/60/30 dias** e **Vencido —
   dobro**.
3. Clique em **Gerar ação** para criar a ação no Plano de Ação (os críticos já
   nascem com ação).
4. Use **Atualizar agora** para forçar uma nova varredura.

> 📸 **PRINT 14 — Aba Vencimentos**
> **Onde:** Férias → **Vencimentos**.
> **O que precisa aparecer:** o cartão de alerta vermelho com o passivo total em
> dobro e a lista de alertas com faixa, data-limite e o botão **Gerar ação**.
> **Dados fictícios na tela:** **Diego Freitas** — "Vencido — dobro", conceder
> até **30/06/2026**, dobro estimado **R$ 3.200,00**; **Marina Alves** — "Vence
> em ≤ 60 dias".

> 💡 Este é o número que sensibiliza a diretoria: cada quadrado vermelho aqui é
> dinheiro que pode virar passivo. Vale destaque no vídeo comercial.

---

### Fluxo 9 — Férias coletivas por setor

**Objetivo:** conceder férias ao setor inteiro de uma vez.
**Benefício:** o sistema marca os novatos proporcionais (art. 140) e gera os
comunicados obrigatórios dentro do prazo de 15 dias.

1. Abra a aba **Coletivas** e clique em **Programar coletiva**.
2. Escolha o **setor**, o **ano** e o **Período 1** (obrigatório, ≥ 10 dias); o
   **Período 2** é opcional.
3. Abra a coletiva criada para ver os **colaboradores abrangidos** (com o selo
   **Art. 140** nos novatos) e **gerar os comunicados** (MTE, sindicato,
   empregados), que ficam arquivados em Documentos.

> 📸 **PRINT 15 — Aba Coletivas (detalhe de uma coletiva)**
> **Onde:** Férias → **Coletivas** → clicar numa coletiva programada.
> **O que precisa aparecer:** as comunicações obrigatórias com prazo e botão
> **Gerar**, e a lista de colaboradores abrangidos com o selo **Art. 140 —
> Xd proporcionais**.
> **Dados fictícios na tela:** setor **Produção**, ano **2026**, período **02/02
> a 16/02**; comunicado ao **Sindicato** "até 18/01/2026"; **Camila Duarte** com
> selo Art. 140 (8 meses de casa).

> 💡 Quem tem menos de 12 meses entra na coletiva com férias **proporcionais** e
> **reinicia** o período aquisitivo (art. 140).

---

### Fluxo 10 — Inteligência (INR™) e evidência NR-1

**Objetivo:** enxergar quem precisa descansar e documentar o monitoramento.
**Benefício:** férias viram instrumento de saúde; a evidência NR-1 prova o
monitoramento de fatores psicossociais exigido pela Portaria MTE 1.419/2024.

1. Abra a aba **INR™**.
2. Leia o **ranking**: score de 0 a 100 por pessoa, com os **fatores** (humor,
   férias vencidas, ações atrasadas, sobrecarga) no tooltip.
3. Nos casos crítico/alto, clique no alvo para **criar uma ação preventiva**.
4. Role até **Evidência NR-1** e clique em **Exportar para o inventário** (PDF).

> 📸 **PRINT 16 — Ranking INR™**
> **Onde:** Férias → **INR™**.
> **O que precisa aparecer:** o cabeçalho "Inteligência de Férias — INR™", os
> cartões de crítico/alto, o ranking com barras de score e o painel lateral
> "Férias por Setor" e "Risco Trabalhista".
> **Dados fictícios na tela:** **Diego Freitas** — score **82**, nível
> **Crítico**, fatores ⚠️⏰; risco trabalhista **35% de exposição**.

> 📸 **PRINT 17 — Evidência NR-1**
> **Onde:** Férias → **INR™** (abaixo do ranking).
> **O que precisa aparecer:** o cartão "Evidência NR-1 — fatores
> organizacionais", os resumos (Índice de descanso, Monitorados, Críticos,
> Férias vencidas), o risco por departamento e o botão **Exportar para o
> inventário**.
> **Dados fictícios na tela:** Índice de descanso **68%**, Monitorados **12**,
> Críticos **1**.

> 💡 O INR™ é **capturado no momento da solicitação** e fica guardado, o que
> permite a análise histórica na aba Relatórios.

---

### Fluxo 11 — Cultura, Relatórios e Governança

**Objetivo:** fechar o ciclo com cuidado humano, dados e evidência de
diligência.
**Benefício:** a empresa demonstra que **avalia, ajusta, registra e previne**.

- **Cultura:** 7 dias antes, sugere uma **mensagem de pré-férias**; no retorno
  (±3 dias), envia um **check-in de bem-estar** que alimenta o INR™.
- **Relatórios:** efetividade, tempo médio, sobrecarga oculta, preventivas vs
  regulares, risco por setor e correlação INR™ × férias.
- **Governança:** um **Selo de Maturidade** (0-100), o **checklist de
  diligência** e o **vínculo familiar** (art. 136, §1º — familiares no mesmo
  estabelecimento podem sair juntos).

> 📸 **PRINT 18 — Aba Cultura**
> **Onde:** Férias → **Cultura**.
> **O que precisa aparecer:** os painéis "Mensagens Pré-Férias" e "Check-in de
> Retorno" com os cartões dos colaboradores.
> **Dados fictícios na tela:** **Camila Duarte** "Férias em 3 dias" com a
> sugestão de mensagem; **Bruno Carvalho** "Retornou há 1 dia" com o check-in.

> 📸 **PRINT 19 — Aba Relatórios**
> **Onde:** Férias → **Relatórios**.
> **O que precisa aparecer:** os 6 cartões (Efetividade, Tempo, Sobrecarga
> Oculta, Preventivas vs Regulares, Risco por Setor, Correlação INR™).
> **Dados fictícios na tela:** Efetividade **80%**, Tempo médio **18 dias**,
> Sobrecarga oculta **1 vencida**.

> 📸 **PRINT 20 — Aba Governança (selo + vínculo familiar)**
> **Onde:** Férias → **Governança**.
> **O que precisa aparecer:** o **Selo de Maturidade** (círculo com o score), o
> **checklist de diligência** e o cartão **Vínculo familiar** com um par
> cadastrado.
> **Dados fictícios na tela:** Selo **74 — Bom**; vínculo **Marina Alves e
> Bruno Carvalho — Cônjuge**.

> 💡 O vínculo familiar cadastrado faz o sistema **sugerir períodos
> coincidentes** na Programação, atendendo ao art. 136, §1º.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, mostrando dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Férias esquecidas viram passivo em dobro. E ninguém percebe até a conta chegar."* Abre com um calendário lotado. | Imagem genérica de calendário |
| 8–22s | *"O YourEyes vigia cada vencimento e mostra, em reais, o risco antes de ele acontecer."* | **PRINT 14** (vencimentos) + **PRINT 11** (financeiro) |
| 22–38s | *"Planeje o ano inteiro da equipe — com a CLT conferida enquanto você digita."* | **PRINT 04** (programação) + **PRINT 05** (validação) |
| 38–52s | *"Aviso e recibo assinados pelo celular, arquivados sozinhos."* | **PRINT 13** (assinatura no celular) |
| 52–68s | *"E mais: uma inteligência que aponta quem precisa descansar — com a evidência que a NR-1 exige."* | **PRINT 16** (INR™) + **PRINT 17** (evidência NR-1) |
| 68–82s | *"YourEyes. Férias que descansam a equipe e protegem a empresa."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 6–9 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("vamos importar…", "agora eu aprovo…").

1. **Abertura** — o que o módulo faz e para quem (**PRINT 01**).
2. **Importar os saldos** e conferir a prévia (**PRINT 02, 03**).
3. **Programar o ano** e ver a validação CLT (**PRINT 04, 05, 06, 07**).
4. **Criar uma solicitação** com abono e simulação (**PRINT 08**).
5. **Aprovar** e acompanhar o status (**PRINT 09**).
6. **Gerar o aviso**, ver as ações pós-aprovação (**PRINT 10**).
7. **Gerar o recibo e o registro financeiro** (**PRINT 11**).
8. **Enviar para assinatura** e assinar no celular (**PRINT 12, 13**).
9. **Tratar um vencimento** e gerar ação (**PRINT 14**).
10. **Programar uma coletiva** (**PRINT 15**).
11. **Ler o INR™** e exportar a evidência NR-1 (**PRINT 16, 17**).
12. **Cultura, Relatórios e Governança** (**PRINT 18, 19, 20**).
13. **Encerramento** — férias como organização do trabalho e recuperação.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Tela inicial / indicadores e abas
- [ ] **PRINT 02** — Aba Saldos (tabela)
- [ ] **PRINT 03** — Modal Importar saldos (prévia)
- [ ] **PRINT 04** — Aba Programação (grade)
- [ ] **PRINT 05** — Edição da programação (validação CLT)
- [ ] **PRINT 06** — Programação além do limite concessivo (dobra)
- [ ] **PRINT 07** — Linha do tempo da programação
- [ ] **PRINT 08** — Modal Nova Solicitação (abono + simulação)
- [ ] **PRINT 09** — Aba Solicitações (cartões)
- [ ] **PRINT 10** — Ações pós-aprovação no cartão
- [ ] **PRINT 11** — Aba Financeiro (provisão / dobro / fluxo)
- [ ] **PRINT 12** — Link de assinatura gerado
- [ ] **PRINT 13** — Tela de assinatura do colaborador (celular)
- [ ] **PRINT 14** — Aba Vencimentos (alertas)
- [ ] **PRINT 15** — Aba Coletivas (detalhe)
- [ ] **PRINT 16** — Ranking INR™
- [ ] **PRINT 17** — Evidência NR-1
- [ ] **PRINT 18** — Aba Cultura
- [ ] **PRINT 19** — Aba Relatórios
- [ ] **PRINT 20** — Aba Governança (selo + vínculo familiar)

---

## 9. Erros comuns / dúvidas frequentes

- **"A aba Programação está indisponível."** Faltam **saldos importados**.
  Importe pela aba **Saldos → Importar saldos** (Fluxo 1).
- **"O colaborador não aparece na lista."** Férias é só **CLT** — PJ, pró-labore
  e terceiros são excluídos de propósito. Confira também se está **ativo** e com
  **CPF** cadastrado.
- **"O saldo aparece como 'estimado'."** Aquele colaborador ainda não tem
  período importado; o sistema mostra 30 dias fixos até a importação (Fluxo 1).
- **"Não consigo iniciar o gozo."** Falta a **ciência do aviso** (art. 135).
  Colha a assinatura do aviso (Fluxo 7) ou use **Registrar ciência (papel)**.
- **"O sistema recusou a solicitação."** Provavelmente é o **fracionamento**
  (máx. 3 períodos, um ≥ 14 dias, nenhum < 5 dias) ou o **abono acima de 1/3**
  (máx. 10 dias).
- **"A provisão não bate com a folha."** É uma **estimativa gerencial** com
  encargos parametrizados; ajuste os **Parâmetros de encargos** conforme o
  regime tributário e concilie com a folha.
- **"Aparece 'programação além do limite concessivo'."** As férias já
  passaram do prazo e implicam **pagamento em dobro** (art. 137); só a diretoria
  (admin ou acima) pode autorizar a exceção.
- **"O recibo abre como código em vez de documento."** É um arquivo HTML antigo;
  use o botão **Ver Recibo Assinado** — o sistema já reabre o conteúdo
  renderizado corretamente.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/ferias_gestao-de-ferias.md` no projeto.
2. Confira se o passo a passo, os benefícios e os 20 marcadores de print
   refletem como você quer conduzir os vídeos do módulo de Férias.
3. Se quiser validar os prints na prática, abra o site de teste
   (https://youreyes-dev.github.io/youreyesnovo/teste/) logado como **Marina
   Alves**, na empresa **Empresa Staging LTDA**, e percorra **Jornada & Rotina →
   Férias** seguindo o checklist da seção 8.
4. Aprovado o **formato**, replico o mesmo padrão para os próximos módulos, nos
   lotes que você priorizar.
