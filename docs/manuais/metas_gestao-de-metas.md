# Manual do módulo — Gestão de Metas

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e do módulo-piloto aprovado
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial.

- **Onde fica no menu:** seção **Planejamento & Gestão → Metas** (rota `/metas`).
- **Para quem é:** Diretoria, Gestores e RH — quem planeja a estratégia e quem
  acompanha a execução no dia a dia.
- **Em uma frase:** transforma a estratégia da empresa em metas claras (estilo
  **OKR**), desdobradas em quatro níveis — da diretoria até a pessoa — com
  acompanhamento por check-in, evidências, governança de aprovação e apoio de
  **Inteligência Artificial** em cada etapa.
- **Importante:** o módulo é **IA First**. A IA sugere metas, indicadores,
  títulos, descrições, desdobramentos, análises de risco e resumos executivos —
  mas **nunca decide sozinha**: todo conteúdo gerado sai marcado como "sujeito a
  revisão humana" e depende de aprovação de uma pessoa para valer.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Da estratégia à pessoa, sem perder o fio.** Uma meta da diretoria pode ser
  **desdobrada** em metas de unidade, de setor e, no fim, individuais — cada
  camada herdando o objetivo da camada de cima. O alinhamento deixa de morar num
  slide e passa a viver no sistema.
- **Todo mundo fala a mesma língua de resultado.** Cada meta tem **indicador**,
  **valor alvo** e **progresso calculado automaticamente** a partir dos
  check-ins. Some a discussão de "achismo" sobre quem entregou o quê.
- **Governança de verdade.** As metas passam por um **fluxo de aprovação**
  (Rascunho → Em Aprovação → Ativa) e toda mudança fica registrada num
  **histórico automático** — quem criou, quem aprovou, quando mudou de status.
- **Acompanhamento contínuo, não só no fim do ciclo.** Os **check-ins**
  registram a evolução real, com **evidências** anexadas (fotos, planilhas,
  certificados, links). No fechamento não há surpresa — e há prova.
- **Avaliação justa e explicável.** A **consolidação** calcula o atingimento
  **ponderado pelo peso** de cada meta e mostra a **memória de cálculo**
  aberta — o resultado final é defensável linha a linha.
- **IA que faz o trabalho pesado.** Sugestão de metas **SMART**, desdobramento
  automático, detecção de **duplicidades e conflitos**, análise de **risco** de
  não atingimento e **resumo executivo** do ciclo — tudo com um clique, sempre
  para revisão humana.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Meta** | Um objetivo com dono, prazo e forma de medir. É a unidade básica do módulo. |
| **Nível** | A camada da meta: **Estratégica**, **Unidade**, **Setor** ou **Individual**. Define a que altura da organização ela pertence. |
| **Desdobramento** | Quebrar uma meta de nível superior em submetas coerentes nos níveis abaixo (ex.: uma meta estratégica vira várias metas de setor). |
| **Indicador** | A régua da meta: o que se mede (ex.: "Taxa de acidentes"), com **tipo**, **unidade** e **direção**. |
| **Valor alvo** | Onde se quer chegar. O **progresso** é calculado comparando o valor atual com o alvo. |
| **Direção** | Como o indicador "melhora": **maior é melhor**, **menor é melhor**, **igual ao alvo** ou **dentro da faixa**. |
| **Peso** | A importância da meta na consolidação. Metas mais importantes pesam mais no resultado final. |
| **Check-in** | O registro periódico de "quanto já alcancei". Atualiza o progresso e monta a linha do tempo da meta. |
| **Evidência** | O comprovante do que foi declarado no check-in (arquivo, link ou descrição). |
| **Workflow** | O ciclo de vida da meta: Rascunho, Em Aprovação, Ativa, Em Revisão, Suspensa, Encerrada, Cancelada. |
| **Atingimento ponderado** | O resultado do ciclo: Σ (Progresso × Peso) ÷ Σ Peso. Mais justo que uma média simples. |
| **Meta compartilhada** | Meta com co-responsáveis além do responsável principal, cada um com seu papel e peso. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Estar logado em um perfil com acesso ao módulo.** As abas **Indicadores** e
   **Configurações** só aparecem para quem tem permissão de configuração; um
   operador comum vê Visão Geral, Minhas Metas, Consolidação e Assistente IA.
2. **Ter a estrutura organizacional cadastrada** (empresas/unidades, setores/
   departamentos e colaboradores) — é dela que o formulário puxa as opções de
   **Unidade**, **Setor** e **Colaborador** ao definir a responsabilidade da meta.
3. **Decidir as regras do ciclo** (na aba Configurações): se toda meta exige
   indicador, quais níveis exigem aprovação, com que frequência se faz check-in.
   Dá para começar com os padrões e ajustar depois.

> 💡 Para gravar com a tela "cheia", cadastre algumas metas de exemplo em cada
> nível antes de filmar (ver **Dados fictícios** dos prints). Módulo vazio mostra
> só o cartão "Nenhuma meta cadastrada — clique em Nova Meta para começar".

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Metas**, o topo mostra o título **"Metas"** com o subtítulo *"Planeje,
acompanhe e desdobre metas em todos os níveis da organização"* e dois botões:
**Guia** (abre o guia embutido, passo a passo) e **Nova Meta**.

Logo abaixo ficam as abas principais:

| Aba | Para que serve |
|---|---|
| **Visão Geral** | Painel do ciclo: 4 cartões por nível, indicadores (total, ativas, atrasadas…), gráficos e a validação de consistência por IA. |
| **Minhas Metas** | A lista de todas as metas, com filtro por nível, busca e filtro por status. É onde se opera meta a meta. |
| **Consolidação** | O resultado ponderado do ciclo, por nível, com memória de cálculo e resumo executivo por IA. |
| **Assistente IA** | Um chat que responde sobre suas metas (o que está atrasado, onde focar). |
| **Indicadores** *(só config.)* | Cadastro de indicadores reutilizáveis entre metas e áreas. |
| **Configurações** *(só config.)* | Regras do ciclo: exigências, aprovações por nível, frequência de check-in. |

> 📸 **PRINT 01 — Tela inicial do módulo (Visão Geral)**
> **Onde:** menu **Planejamento & Gestão → Metas**, aba **Visão Geral**.
> **O que precisa aparecer:** título "Metas", os botões **Guia** e **Nova Meta**,
> as abas e os **4 cartões coloridos por nível** (Estratégicas roxo, Unidade
> azul, Setor âmbar, Individual verde) com as contagens.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; cartões com
> **2 Estratégicas, 3 Unidade, 4 Setor, 6 Individual**.
> **Ação filmada:** panorâmica lenta do topo para os cartões e as abas.

---

## 5. Passo a passo por fluxo

A ordem abaixo segue a mesma lógica do **Guia** embutido (botão **Guia** no topo,
9 passos) — vale abri-lo no vídeo tutorial como reforço.

> 📸 **PRINT 02 — Guia do Módulo (embutido)**
> **Onde:** botão **Guia** no topo da página.
> **O que precisa aparecer:** o guia em tela cheia, com a barra lateral "Passo a
> Passo" (O que é este módulo, Níveis Hierárquicos, Crie uma Nova Meta,
> Indicadores, Workflow, Check-ins, IA, Consolidação, Boas Práticas) e a barra de
> progresso no topo.
> **Ação filmada:** clicar em **Guia**, avançar 2 ou 3 passos com **Próximo**.

---

### Fluxo 1 — Configurar as regras do ciclo

**Objetivo:** definir como as metas se comportam na empresa.
**Benefício:** todas as metas passam a seguir a mesma política (exigências,
aprovações, ritmo de check-in) sem depender da lembrança de cada gestor.

1. Abra a aba **Configurações** (visível para perfis com permissão).
2. Em **Configurações Gerais**, ligue/desligue: **exigir vínculo com objetivo
   estratégico**, **exigir indicador em todas as metas**, **permitir
   desdobramento**, **permitir metas compartilhadas** e **integrar com Avaliação
   de Desempenho**.
3. Em **Aprovações por Nível**, escolha quais níveis exigem aprovação formal
   (Estratégicas, Unidade, Setor, Individuais).
4. Em **Parâmetros**, defina a **frequência de check-in** (semanal, quinzenal,
   mensal, trimestral) e os **dias de alerta antes do prazo**.
5. Clique em **Salvar Configurações**.

> 📸 **PRINT 03 — Aba Configurações**
> **Onde:** Metas → **Configurações**.
> **O que precisa aparecer:** os três blocos (Gerais, Aprovações por Nível,
> Parâmetros) com as chaves e o botão **Salvar Configurações**.
> **Dados fictícios na tela:** "Exigir indicador" **ligado**; aprovação
> **Estratégica ligada**, demais desligadas; frequência **Mensal**; alerta **7 dias**.

> 💡 Comece pelos padrões (indicador exigido, só metas estratégicas exigindo
> aprovação, check-in mensal) e ajuste conforme a maturidade da empresa.

---

### Fluxo 2 — Padronizar indicadores reutilizáveis

**Objetivo:** criar um catálogo de indicadores que várias metas podem usar.
**Benefício:** áreas diferentes medem a mesma coisa do mesmo jeito — o que dá
comparabilidade e leitura executiva consistente.

1. Abra a aba **Indicadores**.
2. Clique em **Novo Indicador**.
3. Preencha **nome**, **descrição**, **tipo** (quantitativo, qualitativo,
   financeiro), **direção** (maior/menor/igual/faixa), **unidade de medida**,
   **origem dos dados** (manual, integrado, híbrido), **frequência de
   atualização** e, se houver, a **fórmula**.
4. Deixe **Ativo** ligado e clique em **Criar**.

> 📸 **PRINT 04 — Lista de indicadores reutilizáveis**
> **Onde:** Metas → **Indicadores**.
> **O que precisa aparecer:** a lista com alguns indicadores, cada um com badges
> de tipo, direção e unidade, o campo de busca e o botão **Novo Indicador**.
> **Dados fictícios na tela:** **"Taxa de Frequência de Acidentes"** (Quantitativo,
> Menor é melhor, un) e **"Índice de Satisfação Interna"** (Qualitativo).

> 📸 **PRINT 05 — Cadastro de novo indicador**
> **Onde:** Indicadores → **Novo Indicador**.
> **O que precisa aparecer:** o formulário com tipo, direção, unidade, origem,
> frequência e fórmula.
> **Dados fictícios na tela:** nome **"Taxa de Frequência de Acidentes"**, tipo
> **Quantitativo**, direção **Menor é melhor**, fórmula **"(acidentes / HHT) ×
> 1.000.000"**, frequência **Mensal**.

> 💡 O campo **Fórmula** é livre e serve de documentação — quem lê a meta entende
> exatamente como o número é obtido.

---

### Fluxo 3 — Criar uma nova meta (com apoio de IA)

**Objetivo:** cadastrar uma meta clara, mensurável e no nível certo.
**Benefício:** meta nasce com dono, prazo e indicador — pronta para ser
acompanhada — e a IA ajuda a escrever cada parte.

1. Clique em **Nova Meta** no topo.
2. Em **Informações Gerais**, escolha o **Nível** (Estratégica, Unidade, Setor ou
   Individual) e escreva um **Título** claro. Use **Sugerir com IA** ao lado do
   título ou da descrição se quiser um rascunho automático.
3. Em **Período**, informe **Ano** e as **datas de início e fim**. O **trimestre**
   é preenchido automaticamente pela data fim.
4. Em **Indicador de Medição**, defina **nome do indicador**, **tipo**, **unidade
   de medida** e **valor alvo** (há também **Sugerir com IA** para o indicador).
5. Em **Responsabilidades**, selecione **Unidade**, **Setor** e/ou **Colaborador**
   conforme o nível (metas individuais pedem colaborador; estratégicas pedem o
   nome do responsável).
6. Se for uma meta com mais de um dono, ligue **Meta compartilhada** e adicione
   **participantes** com **papel** (co-responsável, apoio, consultado) e **peso**.
7. Clique em **Criar Meta** — ela nasce como **Rascunho**.

> 📸 **PRINT 06 — Formulário "Nova Meta"**
> **Onde:** botão **Nova Meta** (topo).
> **O que precisa aparecer:** as seções Informações Gerais, Período, Indicador de
> Medição e Responsabilidades, com os botões **Sugerir com IA**.
> **Dados fictícios na tela:** nível **Estratégica**, título **"Reduzir a taxa de
> acidentes em 30%"**, indicador **"Taxa de Frequência de Acidentes"**, valor alvo
> **8**, responsável **Bruno Carvalho**, ano **2026**.
> **Ação filmada:** digitar o título e clicar em **Sugerir com IA** na descrição.

> 📸 **PRINT 07 — Sugestões de meta geradas por IA**
> **Onde:** dentro do formulário, após clicar em **Sugerir com IA** (topo).
> **O que precisa aparecer:** os cartões de sugestão com selo **IA** (título,
> descrição, justificativa 💡) e o clique aplicando uma sugestão ao formulário.
> **Dados fictícios na tela:** sugestão **"Reduzir em 30% a taxa de frequência de
> acidentes até dez/2026"**.

> 💡 A IA usa o que já está preenchido como contexto. Preencha o título antes de
> pedir a descrição ou o indicador — a sugestão fica muito mais precisa. E
> **sempre revise** o texto antes de aprovar.

---

### Fluxo 4 — Ler a Visão Geral do ciclo

**Objetivo:** enxergar a saúde de todas as metas numa tela.
**Benefício:** o gestor vê num relance quantas metas existem, quantas estão
atrasadas, o progresso médio e a distribuição por nível e status.

1. Abra a aba **Visão Geral**.
2. No topo, os **4 cartões por nível** mostram a contagem e servem de atalho —
   clicar em um leva à lista já filtrada por aquele nível.
3. Abaixo, os **indicadores** (Total, Ativas, Em Andamento, Concluídas,
   Atrasadas, Aguardando Aprovação), o **Progresso Médio Geral**, o gráfico
   **Distribuição por Status** e o quadro **Metas por Nível**.
4. Ao final, **Atividade Recente** lista as últimas metas movimentadas.

> 📸 **PRINT 08 — Painel Visão Geral (indicadores e gráficos)**
> **Onde:** Metas → **Visão Geral** (rolando abaixo dos cartões).
> **O que precisa aparecer:** a linha de indicadores, a barra de Progresso Médio,
> o gráfico de pizza por status e o quadro Metas por Nível.
> **Dados fictícios na tela:** Total **15**, Ativas **9**, Atrasadas **2**,
> Progresso Médio **58%**.

---

### Fluxo 5 — Operar a lista (Minhas Metas)

**Objetivo:** encontrar e agir sobre uma meta específica.
**Benefício:** filtros por nível, status e busca por texto colocam a meta certa à
mão em segundos; cada cartão já traz progresso, indicador e ações.

1. Abra a aba **Minhas Metas**.
2. Use o **filtro segmentado por nível** (Todas, Estratégicas, Unidade, Setor,
   Individual), a **busca por título** e o **filtro por status**.
3. Cada cartão mostra: **badges** (nível, status do workflow, situação, período,
   risco, compartilhada, nº de participantes), **indicador**, **barra de
   progresso** e o botão **Atualizar progresso**.
4. No menu **⋮** de cada cartão: **Detalhar**, **Atualizar progresso**,
   **Editar**, **Desdobrar com IA** (metas não individuais), ações de **workflow**
   e **Excluir**.

> 📸 **PRINT 09 — Lista de metas com filtro por nível**
> **Onde:** Metas → **Minhas Metas**.
> **O que precisa aparecer:** o filtro segmentado de nível no topo, a busca e o
> filtro de status, e vários cartões com badges e barra de progresso.
> **Dados fictícios na tela:**
> - **"Reduzir a taxa de acidentes em 30%"** — Estratégica — **Ativa** — 40%.
> - **"Concluir 100% dos exames periódicos da unidade"** — Unidade — Ativa — 72%.
> - **"Treinar equipe de produção em NR-12"** — Setor — Em Aprovação — 0%.
> - Uma meta com badge **Risco alto** e outra **👥 Compartilhada**.
> **Ação filmada:** clicar no filtro **Setor** e depois abrir o menu **⋮** de um cartão.

> 💡 A barra de progresso **não é editável direto** — para avançar a meta é preciso
> registrar um **check-in** (próximo fluxo). Isso garante que todo avanço tenha
> data, autor e, de preferência, evidência.

---

### Fluxo 6 — Registrar check-in de progresso

**Objetivo:** atualizar quanto já foi alcançado.
**Benefício:** o progresso é **calculado automaticamente** a partir do valor
informado e do valor alvo (respeitando a direção do indicador) e monta a linha do
tempo da meta.

1. No cartão da meta, clique em **Atualizar progresso** (ou **⋮ → Detalhar**).
2. Na aba **Check-in**, informe **quanto você já alcançou** (o número total até
   hoje, não a diferença). Para indicadores qualitativos, escolha o estado numa
   lista (ex.: Não Iniciado / Em Andamento / Concluído).
3. Veja o **progresso calculado** aparecer na hora, com o quanto falta para o alvo.
4. Escreva uma **observação** (o que foi feito, dificuldades, próximos passos).
5. Clique em **Salvar Check-in**. O histórico de check-ins fica logo abaixo.

> 📸 **PRINT 10 — Detalhe da meta: aba Check-in**
> **Onde:** cartão da meta → **Atualizar progresso** → aba **Check-in**.
> **O que precisa aparecer:** o indicador com valor atual/alvo, o campo de valor
> alcançado, o bloco **Progresso calculado** e o campo de observação.
> **Dados fictícios na tela:** indicador **Taxa de acidentes**, valor alcançado
> **12**, alvo **8**, progresso calculado **~67%**, observação *"Concluímos o
> treinamento da equipe A; equipe B começa na próxima semana."*
> **Ação filmada:** digitar o valor, ver o progresso recalcular e salvar.

---

### Fluxo 7 — Anexar evidências

**Objetivo:** comprovar o que foi declarado nos check-ins.
**Benefício:** dá segurança jurídica e credibilidade à avaliação — na auditoria,
a evidência é a prova de diligência da gestão.

1. No detalhe da meta, abra a aba **Evidências**.
2. Clique em **Adicionar Evidência**.
3. Escolha o **tipo** (documento, relatório, planilha, imagem, link, texto),
   informe **título**, **descrição** e o **período de referência**.
4. **Anexe o arquivo** (upload) ou informe uma **URL** de link externo.
5. Salve — a evidência entra na lista com data e autor.

> 📸 **PRINT 11 — Detalhe da meta: aba Evidências**
> **Onde:** detalhe da meta → aba **Evidências**.
> **O que precisa aparecer:** o aviso "O que anexar aqui?", o formulário de nova
> evidência e uma evidência já anexada com botão de download.
> **Dados fictícios na tela:** evidência **"Lista de presença — Treinamento
> NR-12"**, tipo **Documento**, período **Set/2026**, autor **Marina Alves**.

> 💡 Recomende anexar **uma evidência a cada check-in**. É o que separa uma meta
> "declarada" de uma meta "comprovada".

---

### Fluxo 8 — Governança: mover a meta pelo workflow

**Objetivo:** controlar maturidade e aprovação da meta.
**Benefício:** nada entra em execução sem passar pelo caminho definido, e cada
mudança fica registrada.

1. No menu **⋮** do cartão, use as ações de **workflow** conforme o estado atual:
   - **Rascunho** → *Enviar para Aprovação* ou *Ativar Diretamente*.
   - **Em Aprovação** → *Aprovar e Ativar* ou *Devolver (Rascunho)*.
   - **Ativa** → *Suspender*, *Enviar para Revisão* ou *Encerrar*.
   - **Suspensa** → *Reativar* ou *Cancelar*.
2. Acompanhe tudo na aba **Histórico** do detalhe da meta — criação, mudanças de
   status e quem fez cada ação (somente leitura, preenchido pelo sistema).

> 📸 **PRINT 12 — Menu de ações e workflow do cartão**
> **Onde:** Minhas Metas → menu **⋮** de um cartão em **Em Aprovação**.
> **O que precisa aparecer:** as opções Detalhar, Atualizar progresso, Editar,
> Desdobrar com IA, e as ações de workflow **Aprovar e Ativar / Devolver**.
> **Dados fictícios na tela:** meta **"Treinar equipe de produção em NR-12"**,
> ação destacada **Aprovar e Ativar**.

> 📸 **PRINT 13 — Detalhe da meta: aba Histórico**
> **Onde:** detalhe da meta → aba **Histórico**.
> **O que precisa aparecer:** a linha do tempo com criação e mudanças de status,
> com nome do responsável e data.
> **Dados fictícios na tela:** "Meta criada — Marina Alves"; "Rascunho → Em
> Aprovação"; "Em Aprovação → Ativa — Bruno Carvalho".

> 💡 As aprovações exigidas por nível vêm da aba **Configurações** (Fluxo 1).
> Metas de níveis que não exigem aprovação podem ir direto para **Ativa**.

---

### Fluxo 9 — Desdobrar uma meta com IA

**Objetivo:** transformar uma meta superior em submetas nos níveis abaixo.
**Benefício:** o alinhamento vertical vira alguns cliques — a IA propõe as
submetas e você escolhe quais criar.

1. No menu **⋮** de uma meta **não individual**, clique em **Desdobrar com IA**.
2. Escolha o **nível de destino** (uma estratégica desdobra em unidade ou setor;
   unidade em setor ou individual; setor em individual).
3. Clique em **Gerar Sugestões com IA**.
4. **Selecione** as submetas desejadas nos cartões e confirme **Criar Meta(s)** —
   elas nascem como **Rascunho**, já vinculadas à meta superior.

> 📸 **PRINT 14 — Desdobramento Inteligente (IA)**
> **Onde:** cartão → **⋮ → Desdobrar com IA**.
> **O que precisa aparecer:** o seletor de nível de destino e os cartões de
> submetas sugeridas, com as caixas de seleção marcadas.
> **Dados fictícios na tela:** desdobrar **"Reduzir a taxa de acidentes em 30%"**
> para o nível **Setor**, com sugestões **"Zerar acidentes na linha de produção"**
> e **"100% dos EPIs inspecionados mensalmente"**.

> 💡 As submetas entram como **rascunho** de propósito — você revisa, ajusta
> responsável e prazo, e só então as ativa.

---

### Fluxo 10 — Consolidar o resultado do ciclo

**Objetivo:** ver o atingimento geral e por nível, de forma ponderada.
**Benefício:** um resultado justo (metas mais importantes pesam mais) e
**explicável** — a memória de cálculo mostra cada linha.

1. Abra a aba **Consolidação** e escolha o **ano**.
2. Veja o **Atingimento Geral Ponderado** com o **conceito** (Excelente, Bom,
   Regular, Insuficiente) e o detalhamento **por nível**.
3. Confira a **Memória de Cálculo** — a fórmula **Σ (Progresso × Peso) ÷ Σ Peso**
   e a conta de cada meta.
4. Clique em **Resumo Executivo IA** para uma leitura em texto do ciclo
   (destaques positivos, pontos de atenção, recomendações).

> 📸 **PRINT 15 — Consolidação (atingimento ponderado)**
> **Onde:** Metas → **Consolidação**.
> **O que precisa aparecer:** o cartão de Atingimento Geral com conceito, os
> cartões por nível e o bloco **Memória de Cálculo**.
> **Dados fictícios na tela:** Atingimento Geral **64% — Bom**; nível Estratégica
> **58%**, Unidade **72%**; memória mostrando "45% × 2 = 90".

> 💡 Não deixe a consolidação só para o fim do ciclo. Consulte-a antes das
> reuniões executivas — junto com a validação de consistência.

---

### Fluxo 11 — IA de análise: consistência, risco e chat

**Objetivo:** usar a IA para revisar o conjunto de metas e antecipar problemas.
**Benefício:** detecta duplicidades e conflitos, mede o risco de não atingir e
responde perguntas em linguagem natural.

- **Validação de Consistência** (aba **Visão Geral**, ao final): clique em
  **Validar Metas** e a IA aponta **duplicidades, conflitos, desalinhamentos e
  sobreposições**, com sugestão para cada caso (precisa de ao menos 2 metas).
- **Análise de Risco** (detalhe da meta → aba **Análise IA**): clique em
  **Analisar Risco com IA** para um diagnóstico cruzando progresso × tempo
  restante × histórico, com **probabilidade de atingimento**, fatores de risco e
  recomendações.
- **Assistente de Metas** (aba **Assistente IA**): um chat que responde sobre suas
  metas — use os atalhos "Quais metas estão atrasadas?", "Onde focar?" etc.

> 📸 **PRINT 16 — Validação de Consistência (IA)**
> **Onde:** Metas → **Visão Geral**, painel ao final da página.
> **O que precisa aparecer:** o botão **Validar Metas** e a lista de alertas com
> badges de tipo (duplicidade, conflito…) e sugestões.
> **Dados fictícios na tela:** alerta **"duplicidade"** entre duas metas de
> redução de acidentes em setores diferentes, com sugestão de desdobrar em vez de
> duplicar.

> 📸 **PRINT 17 — Assistente de Metas (chat IA)**
> **Onde:** Metas → **Assistente IA**.
> **O que precisa aparecer:** a área de conversa com os atalhos de pergunta e uma
> resposta da IA já na tela.
> **Dados fictícios na tela:** pergunta **"Quais metas estão atrasadas?"** e a
> resposta listando as 2 metas com status Atrasada.

> 💡 Todo texto da IA sai marcado como **"sujeito a revisão humana"**. Trate como
> um primeiro rascunho de um analista — ótimo ponto de partida, decisão sempre sua.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, mostrando dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"A estratégia da sua empresa vive num slide que ninguém abre?"* Abre com um organograma parado. | Imagem genérica |
| 8–22s | *"O YourEyes transforma a estratégia em metas — da diretoria até cada pessoa."* | **PRINT 01** (cartões por nível) + **PRINT 14** (desdobramento) |
| 22–38s | *"Cada meta tem indicador, dono e progresso que se atualiza a cada check-in."* | **PRINT 06** (nova meta) + **PRINT 10** (check-in) |
| 38–52s | *"E uma IA que sugere, analisa risco e aponta metas duplicadas — sempre para você aprovar."* | **PRINT 07** (sugestão IA) + **PRINT 16** (consistência) |
| 52–68s | *"No fim do ciclo, um resultado ponderado e explicável, com memória de cálculo aberta."* | **PRINT 15** (consolidação) |
| 68–80s | *"YourEyes. Da estratégia ao resultado, com governança."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 6–9 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("vamos configurar…", "agora eu crio a meta…").

1. **Abertura** — o que o módulo faz e para quem (**PRINT 01**); abrir o **Guia**
   embutido (**PRINT 02**).
2. **Configurar o ciclo** — exigências, aprovações, check-in (**PRINT 03**).
3. **Padronizar indicadores** reutilizáveis (**PRINT 04, 05**).
4. **Criar uma meta** com apoio de IA (**PRINT 06, 07**).
5. **Ler a Visão Geral** e seus gráficos (**PRINT 08**).
6. **Operar a lista** com filtros por nível (**PRINT 09**).
7. **Registrar um check-in** e ver o progresso recalcular (**PRINT 10**).
8. **Anexar uma evidência** (**PRINT 11**).
9. **Aprovar a meta** pelo workflow e ver o histórico (**PRINT 12, 13**).
10. **Desdobrar** uma meta com IA (**PRINT 14**).
11. **Consolidar** o ciclo e gerar o resumo executivo (**PRINT 15**).
12. **Validar consistência** e conversar com o **Assistente IA** (**PRINT 16, 17**).
13. **Encerramento** — lembrar do botão **Guia** dentro do sistema.

> 💡 Dica de gravação: abra o **Guia** (botão no topo) e siga os 9 passos dele — o
> roteiro do tutorial foi montado na mesma sequência.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina Alves**
(Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Tela inicial / Visão Geral (cartões por nível)
- [ ] **PRINT 02** — Guia do Módulo (embutido)
- [ ] **PRINT 03** — Aba Configurações
- [ ] **PRINT 04** — Lista de indicadores reutilizáveis
- [ ] **PRINT 05** — Cadastro de novo indicador
- [ ] **PRINT 06** — Formulário Nova Meta
- [ ] **PRINT 07** — Sugestões de meta por IA
- [ ] **PRINT 08** — Painel Visão Geral (indicadores e gráficos)
- [ ] **PRINT 09** — Lista de metas com filtro por nível
- [ ] **PRINT 10** — Detalhe: aba Check-in
- [ ] **PRINT 11** — Detalhe: aba Evidências
- [ ] **PRINT 12** — Menu de ações e workflow do cartão
- [ ] **PRINT 13** — Detalhe: aba Histórico
- [ ] **PRINT 14** — Desdobramento Inteligente (IA)
- [ ] **PRINT 15** — Consolidação (atingimento ponderado)
- [ ] **PRINT 16** — Validação de Consistência (IA)
- [ ] **PRINT 17** — Assistente de Metas (chat IA)

---

## 9. Erros comuns / dúvidas frequentes

- **"Não vejo as abas Indicadores e Configurações."** Elas só aparecem para
  perfis com permissão de configuração. Um operador comum vê Visão Geral, Minhas
  Metas, Consolidação e Assistente IA.
- **"A barra de progresso não deixa eu digitar o percentual."** É de propósito. O
  progresso vem do **check-in**: informe o valor alcançado e o sistema calcula
  (Fluxo 6). Isso garante data, autor e histórico em cada avanço.
- **"Criei a meta mas ela não está valendo."** Toda meta nasce como **Rascunho**.
  Mova-a pelo workflow até **Ativa** (Fluxo 8) — direto ou via aprovação, conforme
  as Configurações.
- **"A opção Desdobrar com IA não aparece."** Metas **individuais** não desdobram
  (são o último nível). Desdobre a partir de estratégica, unidade ou setor.
- **"O progresso de uma meta 'menor é melhor' parece invertido."** Não está: para
  indicadores de **menor é melhor** (ex.: acidentes), o sistema calcula o
  progresso pela aproximação de zero. Confira a **direção** do indicador na meta.
- **"A validação de consistência não roda."** É preciso ter **pelo menos 2 metas**
  cadastradas para a IA comparar.
- **"Posso confiar no texto da IA?"** Trate como rascunho: tudo sai marcado como
  **"sujeito a revisão humana"** e depende da sua aprovação para valer.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/metas_gestao-de-metas.md` no projeto.
2. Se quiser conferir cada tela citada, acesse o **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
   Alves**, e vá em **Planejamento & Gestão → Metas**: confira as abas Visão
   Geral, Minhas Metas, Consolidação e Assistente IA, o botão **Guia** e o
   formulário **Nova Meta**, comparando com os fluxos e marcadores de print acima.
3. Aprovado o conteúdo, os prints podem ser capturados no ambiente de teste
   seguindo o checklist da seção 8.
