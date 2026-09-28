# Manual do módulo — Financeiro (Folha, Benefícios e Encargos)

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md),
> com a mesma profundidade do piloto aprovado
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial.

- **Onde fica no menu:** seção **Financeiro → Financeiro** (rota `/financeiro`).
- **Para quem é:** RH, Departamento Pessoal (DP), Analista Financeiro e
  Contabilidade.
- **Em uma frase:** calcula e fecha a folha de pagamento, férias, 13º, rescisões
  e provisões, aplicando INSS/IRRF/FGTS e a convenção coletiva sozinho, com
  holerite, memória de cálculo e os eventos do eSocial prontos para conferência.
- **Importante:** os cálculos usam os colaboradores e os salários já cadastrados;
  quando o módulo **Ponto** está fechado, as médias de horas extras e adicionais
  entram automaticamente (a folha e o ponto bebem da mesma fonte).
- **Módulos acoplados** (documentados só de passagem no fim deste manual):
  **Benefícios** (rota `/financeiro/beneficios`, é a aba Benefícios aberta
  direto) e **Hub Contábil** (rota `/hub-contabil`, a ponte com a contabilidade —
  guias, competências e certidões).

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **A folha inteira em um lugar só.** Salário, horas extras, adicional noturno,
  INSS, IRRF, FGTS, benefícios e descontos são calculados juntos, por
  competência — sem planilha paralela e sem digitar imposto na mão.
- **Cálculo que se explica.** Férias e 13º guardam a **memória de cálculo**: de
  onde saiu cada avo, quais competências entraram na média das variáveis, qual
  rubrica somou quanto. Numa auditoria ou numa dúvida do colaborador, o número
  tem origem rastreável (art. 142 da CLT para férias; Lei 4.090/1962 para o 13º).
- **A lei já vem embutida — e continua atualizável.** As tabelas de **INSS** e
  **IRRF** de 2025 vêm prontas, e podem ser **reparametrizadas sem depender de
  atualização do sistema** (aba Tabelas Fiscais). A **convenção coletiva (CCT)**
  entra com piso, adicionais e vigência.
- **Holerite pronto para entregar.** Cada colaborador tem o recibo em PDF, que
  pode ser **arquivado na pasta dele** em Documentos e **enviado para assinatura**
  em um clique.
- **13º sem susto no fim do ano.** O sistema **provisiona 1/12 por mês**, processa
  a 1ª e a 2ª parcela **em lote**, concilia o provisionado com o pago e avisa dos
  prazos legais (30/11 e 20/12).
- **Rescisão por tipo de desligamento.** Onze tipos de rescisão (pedido, sem
  justa causa, acordo 484-A, término de experiência…), cada um com as verbas e a
  multa de FGTS corretas, com fluxo de conferência → aprovação → pagamento.
- **eSocial e obrigações fiscais preparados.** Os eventos **S-1200** e **S-1210**,
  a **DCTFWeb** e o **FGTS Digital** são montados e conferidos a partir da folha;
  os **alertas de prazo** avisam antes de cada obrigação vencer.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Competência** | O mês de referência da folha (ex.: `2026-09` = Setembro/2026). Tudo é organizado por competência. |
| **Período de folha** | O "envelope" de uma competência: enquanto está **Aberto** aceita mudanças; depois vira **Prévia**, **Conferência** e **Fechado**. |
| **Prévia** | O primeiro rascunho da folha: o sistema cria um item por colaborador com o salário-base para você conferir. |
| **Provento** | Tudo que **soma** no holerite (salário, hora extra, adicional). |
| **Desconto** | Tudo que **subtrai** (INSS, IRRF, vale-transporte, plano de saúde). |
| **Rubrica** | O "código" de cada provento ou desconto, com as regras de **incidência** (se entra na base de INSS, IRRF, FGTS, férias, 13º, rescisão). |
| **Holerite** | O recibo de pagamento do colaborador, com proventos, descontos e líquido. |
| **INSS / IRRF / FGTS** | Os encargos: contribuição previdenciária, imposto de renda e fundo de garantia. |
| **1/3 constitucional** | O adicional de um terço pago sobre as férias (Constituição, art. 7º). |
| **Média das variáveis (art. 142)** | Horas extras, comissões e adicionais habituais entram nas férias e no 13º pela média do período. |
| **Avos** | As frações de 1/12 do 13º — um avo por mês trabalhado (fração de 15 dias conta como mês inteiro). |
| **Provisão** | O custo de férias e 13º reconhecido **1/12 por mês** (regime de competência), antes de o pagamento acontecer. |
| **CCT / ACT** | Convenção (ou Acordo) Coletiva de Trabalho — as regras do sindicato: piso, adicionais, benefícios. |
| **eSocial (S-1200 / S-1210)** | Os eventos oficiais de **Remuneração** (S-1200) e **Pagamento** (S-1210) enviados ao governo. |
| **DCTFWeb / FGTS Digital** | As declarações que consolidam os tributos da folha (INSS) e o recolhimento do FGTS. |
| **Memória de cálculo** | O detalhamento que mostra **de onde saiu** cada valor — o que torna o cálculo auditável. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Colaboradores cadastrados com salário.** A folha calcula a partir do
   salário-base de cada pessoa; sem ele, a prévia sai zerada.
2. **Tabelas de INSS/IRRF vigentes.** Já vêm as de **2025** embutidas — não
   precisa fazer nada para começar. Só crie uma tabela nova quando a legislação
   mudar (aba **Tab. Fiscais**).
3. **Convenção coletiva (opcional, mas recomendado).** Cadastre a **CCT** da
   categoria para o piso e os adicionais entrarem certos.
4. **Ponto fechado (opcional).** Se a empresa usa o módulo Ponto, feche o mês
   antes: assim as horas extras e adicionais habituais entram na média
   automaticamente.

> 💡 Para gravar, deixe pelo menos uma competência já com a **prévia gerada** —
> a tela fica muito mais rica do que no estado vazio.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Financeiro**, o topo mostra o título **"Módulo Financeiro"** e a
frase *"Folha de pagamento, benefícios e controle financeiro do RH"*. Abaixo
ficam as **13 abas** do módulo:

| Aba | Para que serve |
|---|---|
| **Painel** | Visão geral: última folha, custo de benefícios, períodos abertos, custos por categoria. |
| **Folha** | O coração do módulo: cria a competência, gera a prévia e abre o holerite de cada um. |
| **Rubricas** | Cadastro de proventos e descontos com as regras de incidência. |
| **Férias** | Cálculo de férias com 1/3, abono e média das variáveis (art. 142). |
| **13º** | 1ª e 2ª parcela, cálculo em lote, política do 13º e adiantamento nas férias. |
| **Rescisão** | Verbas rescisórias por tipo de desligamento, com fluxo de aprovação. |
| **Provisões** | Provisão mensal de férias e 13º e conciliação do ano. |
| **Benefícios** | Tipos de benefício (vale, plano de saúde…) e vínculo por colaborador. |
| **Tabelas** | Consulta às tabelas legais de INSS/IRRF e à matriz de encargos por vínculo. |
| **CCT** | Convenções coletivas: piso, adicionais e vigência por sindicato. |
| **eSocial** | Eventos S-1200/S-1210, DCTFWeb e FGTS Digital, montados a partir da folha. |
| **Alertas** | Prazos fiscais e trabalhistas da competência (fechamento, FGTS, eSocial…). |
| **Tab. Fiscais** | Cria versões novas de INSS/IRRF quando a lei muda, sem depender de atualização. |

> 📸 **PRINT 01 — Tela inicial do módulo (Painel)**
> **Onde:** menu **Financeiro → Financeiro**, aba **Painel**.
> **O que precisa aparecer:** o título "Módulo Financeiro", a fileira das 13
> abas e os quatro cartões de indicadores (Última Folha, Custo Benefícios/mês,
> Períodos Abertos, Tipos de Benefícios), mais o gráfico "Custos por Categoria
> de Benefício" e o "Histórico de Folha".
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; Última Folha
> **R$ 148.320,00** (Competência 2026-09); Custo Benefícios/mês **R$ 9.740,00**
> (18 vínculos ativos); Períodos Abertos **1**; barras de categoria
> (Saúde 52%, Alimentação 31%, Transporte 17%).
> **Ação filmada:** panorâmica lenta mostrando as abas e os cartões.

---

## 5. Passo a passo por fluxo

> A ordem abaixo é a ordem lógica de operação: primeiro as **bases de cálculo**
> (tabelas, CCT, rubricas), depois **rodar a folha**, e por fim os
> **eventos periódicos** (férias, 13º, rescisão, provisões) e as **obrigações**
> (eSocial, alertas).

### Fluxo 1 — Conferir as bases legais (INSS, IRRF e vínculos)

**Objetivo:** confirmar as tabelas que o motor de cálculo usa.
**Benefício:** transparência — o RH vê exatamente as faixas e alíquotas
aplicadas, sem "caixa-preta".

1. Abra a aba **Tabelas**.
2. Confira a **Tabela INSS** (faixas e teto) e a **Tabela IRRF** (faixas,
   alíquotas, dedução por dependente).
3. Role até a **Matriz de Encargos por Tipo de Vínculo** — ela mostra, por tipo
   (CLT, aprendiz, estágio, temporário, PJ…), o que incide: INSS, FGTS, alíquota
   e multa de FGTS, direito a 13º, férias e aviso prévio.

> 📸 **PRINT 02 — Aba Tabelas (INSS, IRRF e matriz de vínculos)**
> **Onde:** Financeiro → **Tabelas**.
> **O que precisa aparecer:** os dois cartões (Tabela INSS com o selo
> "Teto: R$ …" e Tabela IRRF com "Dedução/dep: R$ …") e, abaixo, a matriz de
> vínculos com os selos Sim/Não e os ✓.
> **Dados fictícios na tela:** vigência **2025**; teto INSS visível; linha
> "CLT Indeterminado" com INSS **Sim**, FGTS **Sim**, Alíq. FGTS **8%**,
> Multa **40%**, 13º/Férias/Aviso todos ✓.

> 💡 Estas tabelas são **só de consulta** aqui. Para trocar valores quando a lei
> mudar, use a aba **Tab. Fiscais** (Fluxo 2).

---

### Fluxo 2 — Atualizar as tabelas fiscais quando a lei muda

**Objetivo:** criar uma nova versão de INSS ou IRRF sem esperar atualização do
sistema.
**Benefício:** autonomia — assim que o governo publica a tabela nova, o DP
cadastra a vigência e o motor passa a usá-la.

1. Abra a aba **Tab. Fiscais**.
2. Clique em **Nova Tabela**.
3. Escolha o **tipo** (INSS ou IRRF) e a **vigência início**.
4. Clique em **Preencher com tabela 2025** para partir da base atual e ajustar,
   ou monte as **faixas** à mão (De / Até / Alíquota / Dedução).
5. **Salve.** Enquanto houver uma tabela **Ativa**, o motor usa ela; sem tabela
   ativa, cai no padrão 2025 embutido.

> 📸 **PRINT 03 — Tab. Fiscais (criar tabela)**
> **Onde:** Financeiro → **Tab. Fiscais** → **Nova Tabela**.
> **O que precisa aparecer:** o modal com o seletor de tipo, a vigência, o botão
> "Preencher com tabela 2025" e a tabela de faixas editáveis.
> **Dados fictícios na tela:** tipo **INSS**, vigência início **01/01/2026**,
> faixas preenchidas com a base 2025, teto preenchido.

> 💡 O rodapé da tela explica a regra: *tabela dinâmica ativa vence a constante
> embutida; sem nenhuma ativa, vale o padrão 2025 como reserva.*

---

### Fluxo 3 — Cadastrar as convenções coletivas (CCT)

**Objetivo:** registrar o sindicato, o piso e os adicionais da categoria.
**Benefício:** piso e adicionais entram no cálculo conforme a convenção vigente,
não no "chute".

1. Abra a aba **CCT**.
2. Clique em **Nova CCT**.
3. Preencha **sindicato**, **nº de registro no MTE**, **vigência** (início/fim),
   **piso salarial** e os adicionais (**HE 50%**, **HE 100%**, **noturno**).
4. Marque **Ativa** e **Salve**. A tela marca sozinha como **Vigente** ou
   **Expirada** conforme a data-fim.

> 📸 **PRINT 04 — Aba CCT (lista + nova convenção)**
> **Onde:** Financeiro → **CCT**.
> **O que precisa aparecer:** a tabela com uma CCT já cadastrada (selo
> **Vigente**) e o modal "Nova Convenção Coletiva" aberto ao lado.
> **Dados fictícios na tela:** sindicato **SINDICOM-SP**, registro
> **MR000123/2026**, vigência **01/05/2026 — 30/04/2027**, piso **R$ 2.500,00**,
> HE 50%/100% e noturno **20%**.

---

### Fluxo 4 — Cadastrar as rubricas da folha

**Objetivo:** definir os proventos e descontos e como cada um incide.
**Benefício:** o cálculo respeita as incidências certas — uma verba
indenizatória não vira base de INSS por engano.

1. Abra a aba **Rubricas**.
2. Clique em **Nova Rubrica**.
3. Informe **código**, **descrição**, **tipo** (Provento / Desconto /
   Informativa), **natureza** (Remuneratória / Indenizatória / Outra) e a
   **forma de cálculo** (valor fixo, % do salário, % de base específica,
   qtd × valor, importada).
4. Ligue as **incidências** que se aplicam: **INSS, IRRF, FGTS, Férias, 13º,
   Rescisão**.
5. **Salve.** Rubricas **protegidas** (as de sistema) aparecem bloqueadas para
   edição, para não quebrar o cálculo.

> 📸 **PRINT 05 — Aba Rubricas (lista + modal com incidências)**
> **Onde:** Financeiro → **Rubricas** → **Nova Rubrica**.
> **O que precisa aparecer:** a tabela com as colunas de incidência
> (INSS/IRRF/FGTS/Férias/13º/Resc.) e o modal com os seletores e os switches de
> incidência.
> **Dados fictícios na tela:** rubrica **003 — Hora Extra 50%**, tipo
> **Provento**, natureza **Remuneratória**, incidências INSS/IRRF/FGTS **ligadas**.

> 💡 A coluna de incidência mostra ✓ ou — para cada rubrica: é a leitura rápida
> de "o que entra em quê" sem abrir o cadastro.

---

### Fluxo 5 — Rodar a folha do mês

**Objetivo:** criar a competência e gerar a folha de todos.
**Benefício:** de zero a uma prévia com todo mundo em dois cliques.

1. Abra a aba **Folha**.
2. Clique em **Novo Período** e informe a **competência** (mês/ano). O período
   nasce com status **Aberto**.
3. No cartão do período, clique em **Gerar Prévia** — o sistema cria um item por
   colaborador com o salário-base. O status passa a **Prévia**.
4. **Clique no cartão** do período para expandir e ver a tabela: cada
   colaborador com salário-base, proventos, descontos, líquido e status.
5. **Clique na linha** de um colaborador para abrir o **holerite detalhado**
   (Fluxo 6).

> 📸 **PRINT 06 — Aba Folha (períodos + Novo Período)**
> **Onde:** Financeiro → **Folha**.
> **O que precisa aparecer:** os três cartões de resumo (Períodos / Em Aberto /
> Fechados), a lista de períodos com os selos de status e o modal "Novo Período
> de Folha".
> **Dados fictícios na tela:** competência **Setembro/2026**, **24 colaboradores**,
> líquido **R$ 148.320,00**, selo **Prévia**.

> 📸 **PRINT 07 — Período expandido (itens da folha)**
> **Onde:** Financeiro → **Folha**, com um período **selecionado**.
> **O que precisa aparecer:** a tabela interna com colaborador, cargo,
> salário-base, proventos, descontos, líquido e status; o nome do colaborador em
> destaque (é clicável).
> **Dados fictícios na tela:**
> - **Eduarda Lima** — Analista Financeiro — base **R$ 6.200,00** — líquido **R$ 5.310,00**.
> - **Camila Duarte** — Operadora de Produção — selo **Férias** ao lado do nome.
> - **Diego Freitas** — Desenvolvedor Full Stack — base **R$ 8.500,00**.
> **Ação filmada:** clicar no cartão para expandir e depois numa linha para abrir
> o holerite.

> 💡 A prévia parte do salário-base. Ajustes de horas extras, faltas e adicionais
> vêm do módulo **Ponto** quando ele está integrado e fechado.

---

### Fluxo 6 — Abrir, baixar e enviar o holerite

**Objetivo:** ver o recibo de pagamento de um colaborador e distribuí-lo.
**Benefício:** o holerite sai pronto — proventos, descontos, bases de cálculo e
líquido — e vai direto para a pasta do colaborador ou para assinatura.

1. Na aba **Folha**, com o período expandido, **clique no nome** do colaborador.
2. No modal do **Holerite**, confira os **proventos** (salário, horas extras,
   adicional noturno, DSR), os **descontos** (INSS, IRRF, vale-transporte, vale
   alimentação, plano de saúde/odontológico) e os totais.
3. Confira as **bases de cálculo** (Base INSS, Base IRRF, Base FGTS, FGTS do mês).
4. Use os botões do topo:
   - **Baixar PDF** — gera o recibo em PDF.
   - **Arquivar em Documentos** — guarda o PDF na pasta do colaborador.
   - **Enviar para Assinatura** — cria a solicitação de assinatura do holerite.

> 📸 **PRINT 08 — Holerite detalhado**
> **Onde:** Financeiro → **Folha** → clique no nome do colaborador.
> **O que precisa aparecer:** o cabeçalho "Holerite — Setembro de 2026", os três
> botões (Baixar PDF / Arquivar / Enviar para Assinatura), os dados do
> colaborador, a tabela de proventos e descontos e os três cartões de totais
> (Proventos, Descontos, Líquido) mais as bases de cálculo.
> **Dados fictícios na tela:** colaboradora **Eduarda Lima** (900.000.005-07),
> cargo **Analista Financeiro**, Total Proventos **R$ 6.930,00**, Total Descontos
> **R$ 1.620,00**, Líquido **R$ 5.310,00**.
> **Ação filmada:** clicar em **Baixar PDF** e depois em **Enviar para Assinatura**.

> 💡 Os dados de matrícula, PIS e CBO do recibo são de exemplo no ambiente de
> teste — em produção vêm do cadastro real do colaborador. **Nunca** capture o
> holerite de uma pessoa real (LGPD).

---

### Fluxo 7 — Cadastrar e vincular benefícios

**Objetivo:** manter os benefícios da empresa e ligá-los a cada colaborador.
**Benefício:** custo de benefícios e descontos consolidados, alimentando o
Painel e o holerite.

**Cadastrar o tipo de benefício:**
1. Abra a aba **Benefícios**.
2. Clique em **Novo Benefício**.
3. Informe **nome**, **categoria** (Alimentação, Saúde, Transporte, Seguro,
   Outros), **descrição**, **valor padrão** e **desconto fixo**.
4. **Salve.** O benefício aparece como cartão, com contador de colaboradores.

**Vincular a um colaborador:**
5. Clique em **Vincular Colaborador**.
6. Escolha o **benefício** e busque o **colaborador**; ajuste **valor**,
   **desconto** e **data de início**.
7. **Salve** — o vínculo entra na tabela "Colaboradores com Benefícios".

> 📸 **PRINT 09 — Aba Benefícios (tipos + indicadores)**
> **Onde:** Financeiro → **Benefícios**.
> **O que precisa aparecer:** os quatro cartões de topo (Tipos Cadastrados,
> Vínculos Ativos, Custo Mensal, Descontos Totais), os cartões de tipos de
> benefício com o ícone da categoria e a tabela "Colaboradores com Benefícios".
> **Dados fictícios na tela:** tipos **Vale Alimentação** (R$ 660,00),
> **Plano de Saúde** (R$ 420,00), **Vale Transporte** (R$ 220,00); Custo Mensal
> **R$ 9.740,00**; 18 vínculos ativos.

> 📸 **PRINT 10 — Vincular benefício a colaborador**
> **Onde:** Financeiro → **Benefícios** → **Vincular Colaborador**.
> **O que precisa aparecer:** o modal com o seletor de benefício, o buscador de
> colaborador, os campos valor/desconto/início.
> **Dados fictícios na tela:** benefício **Plano de Saúde**, colaborador
> **Diego Freitas** (900.000.004-18), valor **R$ 420,00**, início **01/09/2026**.

> 💡 A rota **Benefícios** no menu (Jornada & Rotina) abre exatamente esta aba —
> é um atalho para o mesmo lugar.

---

### Fluxo 8 — Calcular férias (com 1/3 e média das variáveis)

**Objetivo:** calcular as férias de um colaborador.
**Benefício:** o cálculo já traz 1/3, abono, INSS e IRRF, e guarda a **memória**
da média das variáveis para o valor se reproduzir depois.

1. Abra a aba **Férias** e clique em **Calcular Férias**.
2. Selecione o **colaborador** (o salário-base vem preenchido).
3. Informe o **período aquisitivo** (início/fim), o **período de gozo**, os
   **dias de gozo** e os **dias de abono**.
4. Na **média de variáveis (art. 142)**, clique em **Apurar da folha** — o
   sistema soma horas extras, comissões e adicionais habituais e mostra a
   memória (rubricas somadas, competência a competência). Você pode ajustar à
   mão, e o sistema registra que foi ajustado.
5. Marque **Férias em dobro** se o período concessivo venceu.
6. Clique em **Calcular.** Na lista, o botão do olho (**Detalhe**) abre o
   demonstrativo com Férias, 1/3, abono, INSS, IRRF, líquido e o **prazo legal**
   de pagamento.

> 📸 **PRINT 11 — Calcular férias (com apuração da média)**
> **Onde:** Financeiro → **Férias** → **Calcular Férias**.
> **O que precisa aparecer:** o modal com colaborador, períodos, dias, o bloco
> "Média de variáveis (art. 142)" com o botão **Apurar da folha** e o selo
> "Apurada da folha" + a memória.
> **Dados fictícios na tela:** colaboradora **Camila Duarte** (900.000.003-37),
> aquisitivo **01/09/2025–31/08/2026**, gozo **05/10/2026–03/11/2026**, 30 dias,
> média apurada **R$ 410,00**.

> 📸 **PRINT 12 — Detalhe do cálculo de férias**
> **Onde:** Financeiro → **Férias** → botão do olho na linha.
> **O que precisa aparecer:** o card com Férias Gozadas, 1/3 Constitucional,
> Total Bruto, INSS, IRRF, Líquido, o "Pagamento até" (prazo legal) e a memória
> da média (art. 142).
> **Dados fictícios na tela:** Total Bruto **R$ 4.140,00**, Líquido
> **R$ 3.690,00**, pagamento até **03/10/2026**.

> 💡 "Apurar da folha" é o que dá segurança jurídica: o valor da média nasce dos
> pagamentos reais do ano, com a memória guardada ao lado (art. 142 da CLT).

---

### Fluxo 9 — Calcular o 13º salário (parcelas, lote e política)

**Objetivo:** apurar e pagar o 13º de todos.
**Benefício:** roda a folha inteira de uma vez, respeita os avos e a média, e
deixa a política (as escolhas que a lei permite) nas mãos da empresa.

1. Abra a aba **13º** e confira o **ano** no campo do topo.
2. Para a empresa toda, use **Lote 1ª parcela** e depois **Lote 2ª parcela** —
   o cálculo roda no banco para todos, com o prazo legal de cada parcela.
3. Para um colaborador específico, clique em **Calcular 13º**, selecione a
   pessoa e clique em **Apurar**: o sistema conta os **avos** (a partir da
   admissão, faltas e afastamentos) e a **média das variáveis** do ano, com
   memória mês a mês.
4. Para quem pediu adiantamento junto das férias, use **Adiantamento nas férias**.
5. No ícone de engrenagem (**Política do 13º**), ajuste as opções que a lei
   admite: base do adiantamento, média de horas extras (física ou por valores),
   divisor de horas, dias de afastamento por conta da empresa e divisor da média.
6. Cada linha tem **Detalhe**, **Ver recibo** e **Arquivar recibo em Documentos**.

> 📸 **PRINT 13 — Aba 13º (lote, política e lista)**
> **Onde:** Financeiro → **13º**.
> **O que precisa aparecer:** o campo de ano, os botões **Lote 1ª parcela**,
> **Lote 2ª parcela**, **Adiantamento nas férias** e a engrenagem, e a tabela
> com Parcela, Avos, Situação, Prazo legal, 13º integral, INSS, IRRF e Líquido.
> **Dados fictícios na tela:** ano **2026**; linha **Bruno Carvalho** — 1ª
> parcela — **12/12** avos — prazo **30/11/2026** — líquido **R$ 3.900,00**.

> 📸 **PRINT 14 — Calcular 13º (apuração de avos e média)**
> **Onde:** Financeiro → **13º** → **Calcular 13º**.
> **O que precisa aparecer:** o modal com colaborador, parcela, ano-base, o
> bloco de apuração com **Avos** e **Média das variáveis** e o botão **Apurar**,
> mais os selos "Avos apurados"/"Média apurada" e a memória mês a mês.
> **Dados fictícios na tela:** colaborador **Bruno Carvalho** (900.000.002-56),
> 1ª parcela, ano **2026**, avos **12/12**, média **R$ 380,00**.

> 💡 A **Política do 13º** vale para os próximos cálculos; o que já foi apurado
> guarda a regra da época. Confirme as opções com a contabilidade antes de mudar.

---

### Fluxo 10 — Calcular uma rescisão

**Objetivo:** apurar as verbas de um desligamento.
**Benefício:** cada tipo de rescisão (são 11) traz as verbas e a multa de FGTS
certas, com fluxo de conferência → aprovação → pagamento.

1. Abra a aba **Rescisão** e clique em **Nova Rescisão**.
2. Selecione o **colaborador** (data de admissão e salário vêm preenchidos).
3. Escolha o **tipo de rescisão** (pedido de demissão, sem justa causa, acordo
   484-A, término de experiência, rescisão indireta…) e o **tipo de aviso**
   (indenizado, trabalhado, dispensado, não aplicável).
4. Confirme **data de desligamento** e o **motivo**, e clique em
   **Calcular Rescisão**.
5. Abra o **Detalhe** (olho): veja o saldo de salário, aviso prévio, férias
   vencidas e proporcionais, 1/3, 13º proporcional, os descontos (INSS/IRRF), o
   FGTS e a multa. Faça avançar o status: **Enviar para Conferência** →
   **Aprovar** → **Marcar como Paga**.

> 📸 **PRINT 15 — Nova rescisão**
> **Onde:** Financeiro → **Rescisão** → **Nova Rescisão**.
> **O que precisa aparecer:** o modal com colaborador, tipo de rescisão, aviso
> prévio, datas de admissão/desligamento, salário e motivo.
> **Dados fictícios na tela:** colaborador **Diego Freitas** (900.000.004-18),
> tipo **Dispensa sem Justa Causa**, aviso **Indenizado**, desligamento
> **30/09/2026**.

> 📸 **PRINT 16 — Detalhe da rescisão (verbas)**
> **Onde:** Financeiro → **Rescisão** → botão do olho.
> **O que precisa aparecer:** os cards "Verbas Rescisórias" e "Descontos e
> Encargos", o total líquido em destaque e os botões de fluxo de status.
> **Dados fictícios na tela:** Total Bruto **R$ 18.640,00**, Multa FGTS **40%**,
> Total Descontos **R$ 2.180,00**, Líquido a Receber **R$ 16.460,00**.

> 💡 O tipo de desligamento muda tudo: "Acordo (Art. 484-A)" paga metade do
> aviso e multa de 20%; "Culpa Recíproca" reduz as verbas pela metade. Escolha o
> tipo certo antes de calcular.

---

### Fluxo 11 — Provisionar férias e 13º e conciliar o ano

**Objetivo:** reconhecer o custo de férias e 13º mês a mês.
**Benefício:** o custo não "estoura" em novembro/dezembro — ele nasce 1/12 por
mês, e a conciliação mostra se o provisionado bate com o pago.

1. Abra a aba **Provisões** e escolha a **competência**.
2. Clique em **Provisionar 13º** — o sistema lança 1/12 do mês para cada
   colaborador (e reverte a provisão de quem foi desligado).
3. Clique em **Conciliar ano** para comparar o **provisionado** com o **pago** e
   ver a **diferença**.
4. Confira as tabelas de **Provisão de Férias** e **Provisão de 13º** (provisão,
   1/3, FGTS e total por colaborador).

> 📸 **PRINT 17 — Aba Provisões (cards + conciliação)**
> **Onde:** Financeiro → **Provisões**.
> **O que precisa aparecer:** o seletor de competência, os botões
> **Provisionar 13º** e **Conciliar ano**, os três cartões (Provisão Férias,
> Provisão 13º, Total) e a faixa de conciliação do ano.
> **Dados fictícios na tela:** competência **2026-09**; Provisão Férias
> **R$ 12.360,00**, Provisão 13º **R$ 11.980,00**; conciliação 2026 — situação
> **conciliado**.

> 💡 Diferença grande no fim do ano quase sempre é mês sem provisionar — rode a
> provisão das competências que faltam.

---

### Fluxo 12 — eSocial e integrações fiscais

**Objetivo:** montar e conferir os eventos que vão ao governo.
**Benefício:** S-1200, S-1210, DCTFWeb e FGTS Digital saem prontos da folha,
prontos para conferência antes da transmissão.

1. Abra a aba **eSocial** e escolha a **competência**.
2. Clique em **Gerar Eventos** — o sistema monta os **S-1200** (Remuneração) a
   partir dos itens da folha e mostra os resumos de **DCTFWeb** (INSS
   empregados, patronal, RAT, terceiros) e **FGTS Digital**.
3. Para o **13º** (apuração **anual**, separada da folha mensal), informe o
   **ano**, clique em **Validar 13º** (aponta pendências) e depois em
   **Gerar S-1200 / Gerar S-1210**.
4. Os eventos ficam **PENDENTES** — a transmissão de fato depende de certificado
   digital, procuração eletrônica e do ambiente do eSocial (é um passo à parte).

> 📸 **PRINT 18 — Aba eSocial (resumos + 13º anual)**
> **Onde:** Financeiro → **eSocial**.
> **O que precisa aparecer:** os três cartões (DCTFWeb, FGTS Digital, Eventos
> eSocial) e o bloco "13º salário — apuração anual" com **Validar 13º** e
> **Gerar S-1200 / S-1210**; o selo **Homologação** no ambiente.
> **Dados fictícios na tela:** competência **2026-09**; DCTFWeb total
> **R$ 41.200,00**; FGTS total **R$ 11.865,00**; 13º/2026 — **24 aptos**.

> 💡 O aviso da tela é importante para a narração: os eventos são **montados e
> conferidos, não enviados**. Leiaute desatualizado é a causa nº 1 de rejeição —
> confira a versão vigente na data do envio.

---

### Fluxo 13 — Alertas de prazo

**Objetivo:** não perder nenhuma obrigação da folha.
**Benefício:** os prazos de fechamento, pagamento, FGTS, eSocial, DCTFWeb e INSS
patronal ficam à vista, com contagem regressiva.

1. Abra a aba **Alertas** e escolha a **competência**.
2. Clique em **Gerar Alertas** — o sistema cria os prazos padrão do mês (com as
   datas-limite calculadas).
3. Clique em **Varrer 13º** para trazer os alertas anuais do 13º (parcelas, base
   de médias incompleta, afastamento a validar).
4. Acompanhe pelos selos (**Concluído**, **X dias restantes**, **Atrasado**) e
   clique em **Concluir** conforme cada obrigação é cumprida.

> 📸 **PRINT 19 — Aba Alertas de prazo**
> **Onde:** Financeiro → **Alertas**.
> **O que precisa aparecer:** os quatro cartões de resumo (Total, Concluídos,
> Pendentes, Atrasados) e a tabela de obrigações com ícone, descrição, prazo e
> selo de status.
> **Dados fictícios na tela:** competência **2026-09**; "FGTS Digital" com
> **5d restantes**; "eSocial S-1200" com **Atrasado (2d)**; "Fechamento da
> Folha" **Concluído**.

> 💡 A varredura do 13º roda sozinha todo dia; o botão **Varrer 13º** serve só
> para conferir na hora.

---

### De passagem — módulos acoplados

Estes dois não são o foco deste manual (cada um terá o seu), mas aparecem ligados
ao Financeiro:

- **Benefícios** (`/financeiro/beneficios`): é a **aba Benefícios** aberta
  direto, pelo atalho do menu **Jornada & Rotina → Benefícios**. Mesma tela do
  Fluxo 7.
- **Hub Contábil** (`/hub-contabil`, menu **Documentos & Governança**): a ponte
  entre DP/RH e a contabilidade. Centraliza os **processos** (admissão, demissão,
  férias, folha/ponto, atestados) em painel e kanban, com prazos (SLA), e é onde
  vivem **guias, competências e certidões** trocadas com o escritório contábil. O
  holerite e o 13º gerados no Financeiro podem ser **enviados para o Hub**.

> 📸 **PRINT 20 — Hub Contábil (visão de passagem)**
> **Onde:** menu **Documentos & Governança → Hub Contábil**.
> **O que precisa aparecer:** o título "Hub de Comunicação Contábil", a barra de
> abas (Painel, Admissão, Demissão, Férias, Folha/Ponto…) e o painel com os
> processos em andamento.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**, alguns
> processos abertos com contadores nas abas.
> **Uso:** só para a tomada de "módulos que conversam com o Financeiro"; o
> detalhamento fica no manual do Hub Contábil.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Folha de pagamento em planilha, imposto digitado na mão, 13º que assusta em dezembro?"* Abre com planilha confusa. | Imagem genérica de planilha |
| 8–22s | *"O YourEyes calcula a folha inteira por competência — salário, extras, INSS, IRRF, FGTS e benefícios, juntos."* | **PRINT 07** (folha) + **PRINT 08** (holerite) |
| 22–36s | *"Férias e 13º com a média das variáveis apurada da folha, e a memória de cálculo guardada."* | **PRINT 11** (férias) + **PRINT 14** (13º) |
| 36–50s | *"13º provisionado 1/12 por mês e processado em lote. Sem susto no fim do ano."* | **PRINT 13** (lote 13º) + **PRINT 17** (provisões) |
| 50–65s | *"eSocial, DCTFWeb e FGTS montados a partir da folha, com os prazos à vista."* | **PRINT 18** (eSocial) + **PRINT 19** (alertas) |
| 65–80s | *"YourEyes Financeiro. Sua folha, calculada e auditável."* Logo. | **PRINT 01** (Painel) / tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 6–9 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("vamos conferir as tabelas…", "agora eu gero a prévia…").

1. **Abertura** — o que o módulo faz e para quem (**PRINT 01**).
2. **Conferir as bases legais** — INSS, IRRF e matriz de vínculos (**PRINT 02**).
3. **Atualizar tabela fiscal** quando a lei muda (**PRINT 03**).
4. **Cadastrar a CCT** da categoria (**PRINT 04**).
5. **Criar rubricas** com incidências (**PRINT 05**).
6. **Rodar a folha** — novo período e prévia (**PRINT 06, 07**).
7. **Abrir o holerite**, baixar e enviar para assinatura (**PRINT 08**).
8. **Cadastrar e vincular benefícios** (**PRINT 09, 10**).
9. **Calcular férias** com apuração da média (**PRINT 11, 12**).
10. **Calcular o 13º** em lote e conferir a política (**PRINT 13, 14**).
11. **Calcular uma rescisão** e seguir o fluxo de status (**PRINT 15, 16**).
12. **Provisionar e conciliar** férias e 13º (**PRINT 17**).
13. **Montar os eventos do eSocial** e conferir (**PRINT 18**).
14. **Acompanhar os alertas de prazo** (**PRINT 19**).
15. **Encerramento** — citar os módulos acoplados (Benefícios e Hub Contábil,
    **PRINT 20**).

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Tela inicial / Painel
- [ ] **PRINT 02** — Aba Tabelas (INSS, IRRF e matriz de vínculos)
- [ ] **PRINT 03** — Tab. Fiscais (criar tabela)
- [ ] **PRINT 04** — Aba CCT (lista + nova convenção)
- [ ] **PRINT 05** — Aba Rubricas (lista + modal com incidências)
- [ ] **PRINT 06** — Aba Folha (períodos + Novo Período)
- [ ] **PRINT 07** — Período expandido (itens da folha)
- [ ] **PRINT 08** — Holerite detalhado
- [ ] **PRINT 09** — Aba Benefícios (tipos + indicadores)
- [ ] **PRINT 10** — Vincular benefício a colaborador
- [ ] **PRINT 11** — Calcular férias (com apuração da média)
- [ ] **PRINT 12** — Detalhe do cálculo de férias
- [ ] **PRINT 13** — Aba 13º (lote, política e lista)
- [ ] **PRINT 14** — Calcular 13º (apuração de avos e média)
- [ ] **PRINT 15** — Nova rescisão
- [ ] **PRINT 16** — Detalhe da rescisão (verbas)
- [ ] **PRINT 17** — Aba Provisões (cards + conciliação)
- [ ] **PRINT 18** — Aba eSocial (resumos + 13º anual)
- [ ] **PRINT 19** — Aba Alertas de prazo
- [ ] **PRINT 20** — Hub Contábil (visão de passagem)

---

## 9. Erros comuns / dúvidas frequentes

- **"A prévia saiu zerada."** Os colaboradores estão sem **salário-base** no
  cadastro, ou não há colaboradores ativos vinculados à empresa. Confira o
  cadastro antes de gerar a prévia.
- **"O cálculo não usou a tabela nova de INSS/IRRF."** A tabela precisa estar
  **Ativa** na aba **Tab. Fiscais** e com **vigência** cobrindo a competência.
  Sem tabela ativa, o sistema usa o padrão 2025 embutido.
- **"A média das férias/13º veio diferente do esperado."** Use **Apurar da
  folha** em vez de digitar: o valor nasce dos pagamentos reais do ano, com
  memória. Se ajustou à mão, o sistema marca como "ajustada" — confira.
- **"O 13º de um colaborador não aparece na lista."** O cálculo foi lançado em
  **ano** diferente do que está no filtro do topo. Ajuste o ano.
- **"Gerei os eventos do eSocial mas não foram enviados."** É proposital: o
  módulo **monta e confere** os eventos; a **transmissão** depende de certificado
  digital e do ambiente do eSocial, fora do sistema.
- **"A rescisão calculou verbas a mais/a menos."** Confira o **tipo de
  rescisão** e o **tipo de aviso** — cada combinação muda as verbas e a multa de
  FGTS.
- **"O custo do 13º disparou em dezembro."** Faltou **provisionar** nas
  competências anteriores. Rode **Provisionar 13º** nos meses que faltam e use
  **Conciliar ano** para conferir.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/financeiro_gestao-financeira.md` no projeto.
2. Confira se o passo a passo, os benefícios e os 20 marcadores de print
   refletem como você quer conduzir os vídeos do módulo Financeiro. Se quiser,
   percorra as abas no **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/ → menu **Financeiro →
   Financeiro**), logado como **Marina Alves**, para casar cada print com a tela
   real antes de gravar.
3. Aprovado o **conteúdo**, sigo com os próximos manuais de módulo nos lotes que
   você priorizar.
