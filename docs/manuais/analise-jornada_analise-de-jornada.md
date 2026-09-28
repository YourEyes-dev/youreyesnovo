# Manual do módulo — Análise de Jornada

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e no mesmo tom e profundidade do piloto aprovado
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial.

- **Onde fica no menu:** seção **Jornada & Rotina → Análise de Jornada**
  (rota `/analise-jornada`). Na tela, o título completo é **"Análise de Carga de
  Trabalho & Jornada"**.
- **Para quem é:** RH, Departamento Pessoal (DP), Gestores e a equipe de
  **SST/SESMT** (saúde e segurança do trabalho, NR-1 e riscos psicossociais).
- **Em uma frase:** transforma a jornada já registrada (ou planilhas de ponto de
  outros sistemas) em **indicadores de carga de trabalho, conformidade legal
  (CLT) e risco** — por pessoa, por setor e para a empresa toda.
- **Importante:** este módulo **não registra ponto** — ele **analisa**. É o
  complemento do módulo **Ponto**: enquanto o Ponto marca e fecha a jornada, a
  Análise de Jornada lê esses dados (ou importa planilhas externas) e aponta
  excesso de horas extras, jornadas longas, intervalos e descansos fora da lei e
  quem está sob maior risco.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Enxergar o risco antes que ele vire passivo.** O sistema cruza a jornada de
  cada pessoa com os limites da CLT e devolve um **nível de risco** (baixo,
  moderado, alto) e um **status de conformidade** (conforme, em atenção, não
  conforme). O que estava escondido em milhares de linhas de ponto vira um painel
  de uma tela.
- **Conformidade legal calculada sozinha.** Jornada diária, jornada semanal,
  **intervalo intrajornada** (almoço), **descanso interjornada (11h)** e
  **descanso semanal (DSR)** são conferidos automaticamente contra os
  parâmetros configurados. Cada violação é contada e classificada.
- **Prova para NR-1 e riscos psicossociais.** Jornadas excessivas e falta de
  descanso são **fatores de risco psicossocial**. O relatório integrado do módulo
  foi pensado para instruir o **PGR / NR-1** e auditorias.
- **Funciona mesmo com dados de fora.** Quem ainda usa outro relógio de ponto
  pode **importar a planilha** (CSV ou Excel) — o sistema mapeia as colunas
  sozinho, valida e traz tudo para dentro. Não é preciso trocar de sistema para
  começar a medir.
- **Alertas inteligentes que sugerem a ação.** Excesso de hora extra, intervalo
  curto, descanso insuficiente e jornada longa viram **alertas** com severidade
  e uma **ação sugerida** — do "redistribuir tarefas" ao "ação imediata: ajustar
  escalas".
- **Da pessoa ao setor, sem planilha.** A mesma análise mostra o **individual**
  (a jornada dia a dia de cada um) e o **coletivo** (comparativo por
  departamento, com insights automáticos de subdimensionamento).

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Análise** | O processamento que lê a jornada do período e calcula, por pessoa, as médias, as violações, o risco e a conformidade. É acionada pelo botão **Executar Análise**. |
| **Carga de trabalho** | Quanto cada pessoa (ou setor) trabalha de fato: média de horas por dia, por semana e total de horas extras. |
| **Nível de risco** | Um selo por colaborador — **Baixo**, **Moderado** ou **Alto** — calculado a partir das violações e do volume de horas extras. |
| **Score de risco** | A nota de 0 a 100 por trás do nível de risco (quanto maior, pior). Alto ≥ 60, Moderado ≥ 30. |
| **Conformidade** | O veredito legal do período: **Conforme**, **Em Atenção** ou **Não Conforme**, conforme o número de violações. |
| **Violação** | Um dia em que um limite legal foi estourado. O sistema conta cinco tipos (ver abaixo). |
| **Intervalo intrajornada** | O intervalo de almoço/descanso dentro do dia (mínimo padrão de **1h**). |
| **Descanso interjornada** | O descanso **entre um dia e outro** (mínimo padrão de **11h**). |
| **DSR** | Descanso Semanal Remunerado — o sistema sinaliza quando há **7 dias consecutivos** trabalhados sem folga. |
| **Parâmetros de conformidade** | Os limites usados no cálculo (jornada diária/semanal máx., HE diária máx., intervalos e descansos mínimos). Vêm no padrão CLT e podem ser ajustados à CCT. |
| **Importação** | O assistente que traz jornada de uma planilha externa (CSV/Excel) para dentro do sistema. |
| **Template de mapeamento** | O "de-para" de colunas salvo, para reaproveitar a cada nova importação do mesmo sistema de origem. |
| **Alerta** | Um sinal automático (com severidade e ação sugerida) gerado quando um padrão de risco aparece. |
| **NR-1 / PGR** | A norma e o programa de gestão de riscos que o **Relatório Integrado** ajuda a instruir. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Ter jornada no período para analisar.** A análise lê os registros de ponto
   diário da empresa. Há dois caminhos para ter dados:
   - já usar o módulo **Ponto** (a jornada registrada por lá é lida direto); ou
   - **importar uma planilha** (CSV/Excel) de outro sistema, pela aba
     **Importação** (Fluxo 2).
2. **Colaboradores identificados por CPF/matrícula e data.** São os dois campos
   obrigatórios da importação — sem eles o sistema não consegue montar a jornada.
3. **(Opcional, recomendado) Parâmetros de conformidade revisados.** Vêm no
   padrão CLT; ajuste-os à **CCT** da categoria na aba **Conformidade →
   Parâmetros** antes de rodar a análise para o resultado sair fiel.

> 📸 **PRINT 01 — Tela inicial do módulo (Dashboard)**
> **Onde:** menu **Jornada & Rotina → Análise de Jornada**, aba **Dashboard**.
> **O que precisa aparecer:** o título **"Análise de Carga de Trabalho &
> Jornada"**, as **8 abas** (Dashboard, Importação, Individual, Coletiva,
> Conformidade, Alertas, Documentos, Relatórios), a faixa de período, o botão
> **Executar Análise** e os seis cartões de indicadores.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; período
> **01/09/2026 a 30/09/2026**.
> **Ação filmada:** panorâmica lenta mostrando as 8 abas.

> 💡 Este módulo **não tem "Guia Rápido" embutido** — a orientação é este manual.
> A primeira coisa a fazer em uma empresa nova é rodar a análise (Fluxo 1); antes
> disso os painéis mostram "Sem dados. Execute a análise primeiro".

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Análise de Jornada**, o topo mostra o título **"Análise de Carga de
Trabalho & Jornada"** e o subtítulo *"Monitoramento analítico de jornada,
conformidade legal e riscos organizacionais"*. Abaixo ficam as **8 abas**:

| Aba | Para que serve |
|---|---|
| **Dashboard** | Painel geral: indicadores, distribuição de risco, top de horas extras e alertas recentes. É onde se **executa a análise**. |
| **Importação** | Assistente em 4 etapas para trazer jornada de planilhas (CSV/Excel) de outros sistemas. |
| **Individual** | A jornada de **uma pessoa**: métricas, violações e o gráfico dia a dia. |
| **Coletiva** | Comparativo **por departamento/setor**, com insights automáticos. |
| **Conformidade** | Veredito legal (CLT), detalhamento das violações e os **parâmetros** de cálculo. |
| **Alertas** | Sinais automáticos de risco, com filtro e botão para **resolver**. |
| **Documentos** | Guarda de **PDFs de evidência** (espelhos, acordos, CCT, auditorias). |
| **Relatórios** | Exportação em **PDF ou Excel** (inclui o modelo integrado NR-1 / PGR). |

> 📸 **PRINT 02 — Dashboard após executar a análise**
> **Onde:** Análise de Jornada → **Dashboard**, depois de clicar em **Executar
> Análise**.
> **O que precisa aparecer:** os seis cartões preenchidos (Colaboradores, Média
> h/dia, Total HE, Alertas, Risco Alto, Não Conforme), o gráfico de pizza
> **Distribuição de Risco** e o gráfico **Top Horas Extras por Colaborador**.
> **Dados fictícios na tela:** **Colaboradores 24**, **Média h/dia 8,3**,
> **Total HE 96h**, **Alertas 5**, **Risco Alto 3**, **Não Conforme 2**; no top de
> extras, **Diego Freitas** liderando.
> **Ação filmada:** clicar em **Executar Análise** e mostrar os cartões se
> preenchendo.

---

## 5. Passo a passo por fluxo

### Fluxo 1 — Executar a análise (Dashboard)

**Objetivo:** processar a jornada do período e gerar os indicadores.
**Benefício:** em um clique, milhares de marcações viram risco, conformidade e
alertas — tudo o que as outras abas mostram nasce daqui.

1. Abra a aba **Dashboard**.
2. Confira a faixa de **período** (o sistema já usa o **mês atual** — início ao
   fim do mês).
3. Clique em **Executar Análise**.
4. Aguarde a mensagem *"Análise concluída: N colaboradores avaliados"*.
5. Os seis **cartões** e os dois **gráficos** se preenchem; os **Alertas
   Recentes** aparecem no rodapé.

> 📸 **PRINT 03 — Cartões e gráficos do Dashboard**
> **Onde:** Análise de Jornada → **Dashboard**.
> **O que precisa aparecer:** os seis cartões, a pizza de risco e a barra de top
> de horas extras; se houver, o bloco **Alertas Recentes**.
> **Dados fictícios na tela:** pizza com **Baixo 19 / Moderado 2 / Alto 3**;
> alerta recente *"Excesso de horas extras — Diego Freitas"*.

> 💡 Cada vez que a análise roda para o mesmo período, ela **substitui** o
> resultado anterior daquele período — não duplica. Pode rodar quantas vezes
> quiser depois de importar dados novos ou ajustar parâmetros.

---

### Fluxo 2 — Importar jornada de uma planilha (CSV / Excel)

**Objetivo:** trazer a jornada de um sistema de ponto externo.
**Benefício:** começa a medir sem trocar de relógio — o assistente mapeia as
colunas sozinho, valida e importa em quatro etapas.

1. Abra a aba **Importação**. O topo mostra o trilho **1. Upload → 2. Mapeamento
   → 3. Preview → 4. Resultado**.
2. **Upload:** arraste um arquivo **.csv, .xlsx ou .xls** (máx. 20 MB) para a área
   pontilhada, ou clique para selecionar.
3. **Mapeamento:** o sistema **tenta associar as colunas automaticamente**.
   Confira e ajuste o "de-para". Só **Nome do Colaborador** e **Data** são
   obrigatórios (marcados com *). Se já usa o mesmo sistema de origem, use
   **Carregar template**; ou **Salvar Template** para reaproveitar depois.
4. Clique em **Pré-visualizar**.
5. **Preview:** confira os contadores **registros / válidos / com erros** e a
   prévia das primeiras linhas (linhas com erro ficam destacadas).
6. Clique em **Importar para Base de Dados** e acompanhe a barra de progresso.
7. **Resultado:** veja **novos registros**, **atualizados** e **erros**. Se quiser,
   **Nova Importação**.

> 📸 **PRINT 04 — Importação, etapa Upload**
> **Onde:** Análise de Jornada → **Importação**.
> **O que precisa aparecer:** o trilho de 4 etapas e a área pontilhada de
> arrastar arquivo, com os selos **.csv / .xlsx / .xls** e o limite de 20 MB.
> **Dados fictícios na tela:** nome de arquivo sugerido **"ponto_setembro_2026.xlsx"**.

> 📸 **PRINT 05 — Importação, Mapeamento de colunas**
> **Onde:** Importação, após soltar o arquivo.
> **O que precisa aparecer:** os campos do sistema à esquerda e os seletores de
> coluna à direita, com **Nome** e **Data** marcados com *; os botões **Carregar
> template** e **Salvar Template**.
> **Dados fictícios na tela:** arquivo **"ponto_setembro_2026.xlsx"**, colunas
> reconhecidas automaticamente (Nome → "Funcionário", Data → "Dia", Entrada →
> "Hora Entrada").

> 📸 **PRINT 06 — Importação, Preview e Resultado**
> **Onde:** Importação, etapas **Preview** e **Resultado**.
> **O que precisa aparecer:** os selos **N registros / N válidos / N com erros** e
> a tabela de prévia; e, na conclusão, os três blocos **Novos registros /
> Atualizados / Erros**.
> **Dados fictícios na tela:** **480 registros**, **472 válidos**, **8 com
> erros**; resultado **464 novos, 8 atualizados, 8 erros**.
> **Ação filmada:** clicar em **Importar para Base de Dados** e mostrar a tela de
> conclusão.

> 💡 Depois de importar, volte ao **Dashboard** e clique em **Executar Análise**
> para que os dados novos entrem nos indicadores.

---

### Fluxo 3 — Analisar um colaborador (Individual)

**Objetivo:** olhar a jornada de uma pessoa em detalhe.
**Benefício:** numa tela, o RH vê médias, violações por tipo e a jornada dia a
dia — inclusive um selo quando a pessoa está **afastada**.

1. Abra a aba **Individual**.
2. **Busque** por nome ou CPF no campo de busca.
3. Clique no colaborador na lista (cada cartão traz o selo de **risco** e um
   resumo: h/dia, HE, atrasos).
4. No painel à direita veja as **métricas** (média diária, HE total, atrasos,
   violações) e o detalhamento das violações por tipo.
5. Confira o gráfico **Jornada Diária** (horas trabalhadas x extras por dia).

> 📸 **PRINT 07 — Individual, lista e busca**
> **Onde:** Análise de Jornada → **Individual**.
> **O que precisa aparecer:** o campo de busca e a lista de colaboradores com os
> selos de risco.
> **Dados fictícios na tela:** **Camila Duarte** (900.000.003-37) — Risco Baixo;
> **Diego Freitas** (900.000.004-18) — Risco Alto.
> **Ação filmada:** digitar "Diego" na busca e clicar no cartão dele.

> 📸 **PRINT 08 — Individual, detalhe do colaborador**
> **Onde:** Individual, com um colaborador selecionado.
> **O que precisa aparecer:** os selos de risco e conformidade, as quatro
> métricas, o detalhamento de violações e o gráfico **Jornada Diária**.
> **Dados fictícios na tela:** **Diego Freitas**, Risco **Alto**, **Não
> Conforme**; média **9,4h/dia**, **HE 22h**, **3 atrasos**; violações de
> interjornada em destaque.

> 💡 Se a pessoa estiver de férias/atestado no período, aparece o selo
> **Afastado** ao lado do nome — evita interpretar como falta o que é ausência
> legal.

---

### Fluxo 4 — Analisar por setor (Coletiva)

**Objetivo:** comparar departamentos e achar gargalos.
**Benefício:** revela onde a carga está concentrada e onde pode haver
subdimensionamento — com **insights automáticos**.

1. Abra a aba **Coletiva**.
2. Leia os **Insights Automáticos** no topo (ex.: setor com média acima de 9h/dia
   ou com muitos colaboradores em risco alto).
3. Confira o **gráfico comparativo** (média h/dia x total de HE por setor).
4. Use a **tabela por departamento**: colaboradores, média h/dia, total HE,
   risco alto e não conformes.

> 📸 **PRINT 09 — Coletiva, comparativo por departamento**
> **Onde:** Análise de Jornada → **Coletiva**.
> **O que precisa aparecer:** o bloco **Insights Automáticos**, o gráfico de
> barras por setor e a tabela por departamento.
> **Dados fictícios na tela:** insight *"Operações: média de 9,4h/dia indica
> possível subdimensionamento"*; tabela com **Operações**, **Tecnologia** e
> **Administrativo**.

> 💡 Os insights só aparecem quando um limiar é ultrapassado — sem alerta na
> Coletiva significa que nenhum setor cruzou os gatilhos de atenção.

---

### Fluxo 5 — Conformidade legal e parâmetros

**Objetivo:** ver o veredito legal do período e ajustar os limites de cálculo.
**Benefício:** o mesmo cálculo que classifica cada pessoa fica transparente — e
adaptável à CCT da categoria.

1. Abra a aba **Conformidade**.
2. Veja os três cartões **Conforme / Em Atenção / Não Conforme** e a pizza de
   distribuição.
3. Confira o **Detalhamento de Violações** (intervalo, interjornada, jornada
   diária, horas extras e DSR).
4. Para ajustar os limites, clique em **Parâmetros** e edite: jornada diária máx.,
   jornada semanal máx., HE diária máx., intervalo intrajornada (min), descanso
   interjornada (h) e descanso semanal (h).
5. Clique em **Salvar Parâmetros** — a próxima análise usa os novos limites.

> 📸 **PRINT 10 — Conformidade, panorama e violações**
> **Onde:** Análise de Jornada → **Conformidade**.
> **O que precisa aparecer:** os três cartões de status, a pizza de distribuição e
> o **Detalhamento de Violações** com os cinco tipos.
> **Dados fictícios na tela:** **Conforme 20 / Em Atenção 2 / Não Conforme 2**;
> violações de interjornada e de intervalo com contagem maior que zero.

> 📸 **PRINT 11 — Conformidade, Parâmetros (limites CLT)**
> **Onde:** Conformidade → botão **Parâmetros**.
> **O que precisa aparecer:** os seis campos de limite preenchidos e o botão
> **Salvar Parâmetros**.
> **Dados fictícios na tela:** jornada diária **8h**, semanal **44h**, HE diária
> **2h**, intervalo **60 min**, interjornada **11h**, descanso semanal **24h**.

> 💡 Alterou parâmetro? Volte ao **Dashboard** e **execute a análise de novo** —
> os vereditos são recalculados com os novos limites.

---

### Fluxo 6 — Tratar alertas

**Objetivo:** agir sobre os sinais de risco.
**Benefício:** cada alerta já vem com severidade e uma ação sugerida — e pode ser
marcado como **resolvido** para manter a lista limpa.

1. Abra a aba **Alertas**.
2. Filtre por **tipo** (excesso de HE, falta de intervalo, descanso insuficiente,
   jornada excessiva…) e por **status** (Pendentes, Resolvidos, Todos).
3. Leia o alerta: título, severidade (baixa/média/alta/crítica), descrição e a
   **ação sugerida** (💡).
4. Ao providenciar a ação, clique em **Resolver** — o alerta passa a
   "✓ Resolvido".

> 📸 **PRINT 12 — Alertas Inteligentes**
> **Onde:** Análise de Jornada → **Alertas**.
> **O que precisa aparecer:** os dois filtros (tipo e status), a lista de alertas
> com selos de severidade e o botão **Resolver**.
> **Dados fictícios na tela:** alerta **crítico** *"Descanso interjornada
> insuficiente — Diego Freitas"* com ação sugerida *"Ação imediata: ajustar
> escalas para garantir 11h de descanso"*.
> **Ação filmada:** clicar em **Resolver** em um alerta e mostrá-lo esmaecer.

> 💡 Os alertas são **gerados junto com a análise**. Se a lista estiver vazia,
> rode a análise no Dashboard primeiro.

---

### Fluxo 7 — Documentos de apoio

**Objetivo:** guardar PDFs de evidência ligados ao período/empresa.
**Benefício:** centraliza espelhos, acordos e convenções para instruir auditoria
e NR-1, tudo no mesmo módulo.

1. Abra a aba **Documentos**.
2. Clique em **Enviar Documento** e arraste um **PDF** (máx. 20 MB).
3. Preencha **nome**, **tipo** (espelho de ponto, relatório de jornada, acordo de
   compensação, convenção coletiva, auditoria, outro), o **vínculo** (empresa,
   unidade, setor ou período) e, se quiser, **período** e **observações**.
4. Clique em **Enviar Documento**.
5. Depois, use os botões de **baixar** e **excluir** em cada documento.

> 📸 **PRINT 13 — Documentos de Apoio**
> **Onde:** Análise de Jornada → **Documentos**.
> **O que precisa aparecer:** a lista de documentos com os selos de tipo/vínculo e
> o modal **Enviar Documento de Apoio (PDF)**.
> **Dados fictícios na tela:** documento **"Acordo de Compensação — Operações"**,
> vínculo **Empresa Staging LTDA**, período **01/09/2026 — 30/09/2026**.

> 💡 São aceitos apenas **PDFs** aqui — é o formato pensado para evidência que
> circula em auditoria.

---

### Fluxo 8 — Exportar relatórios

**Objetivo:** gerar o documento para gestores, auditoria ou NR-1/PGR.
**Benefício:** o mesmo dado sai pronto em **Excel** (para análise) ou **PDF**
(para arquivar), inclusive no modelo **integrado**.

1. Abra a aba **Relatórios**.
2. Escolha o **tipo**: Individual, Carga por Setor, Conformidade Legal, Alertas ou
   **Integrado (NR-1 / PGR)**.
3. Escolha o **formato**: **Excel (.xlsx)** ou **PDF**.
4. Confira o quadro *"O que será incluído"*.
5. Clique em **Exportar** — o arquivo é baixado.

> 📸 **PRINT 14 — Relatórios**
> **Onde:** Análise de Jornada → **Relatórios**.
> **O que precisa aparecer:** os seletores de **tipo** e **formato**, o quadro
> "O que será incluído" e o botão **Exportar**.
> **Dados fictícios na tela:** tipo **Relatório Integrado (NR-1 / PGR)**, formato
> **Excel (.xlsx)**.

> 💡 A exportação respeita o **perfil de acesso**: quem não tem permissão de
> exportar vê o botão desabilitado, com o aviso do motivo — é a mesma camada de
> segurança do resto do sistema.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, mostrando dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Sua empresa sabe quem está no limite da jornada — antes de virar processo?"* Abre com planilha de ponto interminável. | Imagem genérica de planilha |
| 8–22s | *"A Análise de Jornada lê o ponto e devolve risco, conformidade e alertas em uma tela."* | **PRINT 02** (Dashboard) + **PRINT 03** (gráficos) |
| 22–36s | *"Ainda usa outro relógio? Importe a planilha — o sistema mapeia as colunas sozinho."* | **PRINT 05** (mapeamento) + **PRINT 06** (resultado) |
| 36–50s | *"Veja a pessoa e o setor: quem faz hora extra demais, onde falta gente."* | **PRINT 08** (individual) + **PRINT 09** (coletiva) |
| 50–65s | *"Intervalo, descanso de 11h, DSR: conferidos pela CLT, com alerta e ação sugerida."* | **PRINT 10** (conformidade) + **PRINT 12** (alertas) |
| 65–80s | *"E o relatório de NR-1 / PGR sai pronto para a auditoria."* | **PRINT 14** (relatórios) |
| 80–90s | *"YourEyes. Jornada sob controle, risco sob os olhos."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 5–8 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("agora eu importo…", "vamos executar a análise…").

1. **Abertura** — o que o módulo faz, e que ele **complementa o Ponto**
   (**PRINT 01**).
2. **Importar uma planilha** de ponto externo, do upload ao resultado
   (**PRINT 04, 05, 06**).
3. **Executar a análise** no Dashboard e ler os indicadores (**PRINT 02, 03**).
4. **Analisar um colaborador** na aba Individual (**PRINT 07, 08**).
5. **Comparar setores** na aba Coletiva (**PRINT 09**).
6. **Conferir a conformidade** e ajustar os **parâmetros** (**PRINT 10, 11**).
7. **Tratar um alerta** e marcá-lo como resolvido (**PRINT 12**).
8. **Anexar um documento** de apoio (**PRINT 13**).
9. **Exportar o relatório integrado** NR-1 / PGR (**PRINT 14**).
10. **Encerramento** — lembrar que, ao mudar dados ou parâmetros, basta
    **executar a análise de novo**.

> 💡 Dica de gravação: importe a planilha **antes** de executar a análise, para
> mostrar o ciclo completo (dado entra → análise roda → indicadores aparecem).

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Tela inicial / Dashboard (8 abas)
- [ ] **PRINT 02** — Dashboard após executar a análise
- [ ] **PRINT 03** — Cartões e gráficos do Dashboard
- [ ] **PRINT 04** — Importação, etapa Upload
- [ ] **PRINT 05** — Importação, Mapeamento de colunas
- [ ] **PRINT 06** — Importação, Preview e Resultado
- [ ] **PRINT 07** — Individual, lista e busca
- [ ] **PRINT 08** — Individual, detalhe do colaborador
- [ ] **PRINT 09** — Coletiva, comparativo por departamento
- [ ] **PRINT 10** — Conformidade, panorama e violações
- [ ] **PRINT 11** — Conformidade, Parâmetros (limites CLT)
- [ ] **PRINT 12** — Alertas Inteligentes
- [ ] **PRINT 13** — Documentos de Apoio
- [ ] **PRINT 14** — Relatórios

---

## 9. Erros comuns / dúvidas frequentes

- **"Os painéis mostram 'Sem dados. Execute a análise primeiro'."** Você ainda não
  rodou a análise. Vá ao **Dashboard** e clique em **Executar Análise** (Fluxo 1).
- **"A análise diz '0 colaboradores avaliados'."** Não há jornada no período.
  Confira o **período** no Dashboard e, se for o caso, **importe** a planilha
  (Fluxo 2) ou verifique se o módulo **Ponto** tem registros no mês.
- **"A importação não deixa avançar do mapeamento."** Faltou mapear os campos
  obrigatórios **Nome do Colaborador** e **Data** (marcados com *).
- **"O colaborador não tem setor/cargo na análise."** O departamento e o cargo
  vêm do cadastro de **admissões** (pelo CPF). Sem admissão vinculada, a pessoa
  aparece como "Sem departamento".
- **"Mudei os parâmetros mas nada mudou."** Os parâmetros só valem na **próxima
  análise** — rode **Executar Análise** de novo (Fluxo 5).
- **"O botão Exportar está desabilitado."** Seu **perfil de acesso** não permite
  exportar relatórios de jornada — peça a liberação a um administrador.
- **"É o mesmo que o módulo Ponto?"** Não. O **Ponto** registra e fecha a jornada;
  a **Análise de Jornada** lê esses dados (ou importa de fora) e mede risco e
  conformidade. Um alimenta o outro.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/analise-jornada_analise-de-jornada.md` (este
   arquivo) no projeto.
2. Se quiser conferir as telas descritas, acesse o **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
   Alves**, e abra **Jornada & Rotina → Análise de Jornada**: percorra as 8 abas
   (Dashboard, Importação, Individual, Coletiva, Conformidade, Alertas,
   Documentos, Relatórios) e confira se o passo a passo e os marcadores de print
   refletem como você quer conduzir os vídeos.
3. Aprovado o **formato**, replico o mesmo padrão para os demais módulos, nos
   lotes que você priorizar.
