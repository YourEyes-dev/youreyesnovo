# Bloqueios de produto que travam a cobertura de tela (e2e)

**Para quê este documento.** Registrar os pontos em que um caso de teste `e2e`
documentado **não pode ser implementado no Cypress de forma honesta** porque a
tela, hoje, não faz o que o caso descreve — não por falta de teste, mas por um
bug/descompasso de produto. É a **fila de correção** que precisa andar *antes*
de os testes correspondentes existirem. Cada bloqueio diz: o que trava, a
evidência (arquivo:linha), quais casos ficam parados e as opções de correção.

**Como foi levantado.** Durante o piloto de testes de tela que semeiam dado
(decisão de 08/10/2026 — ver histórico do `cypress/e2e/ergonomia.cy.ts`), ao
tentar cobrir os casos da Ergonomia caso a caso, lendo a tela e as descrições
reais de `qa_casos_teste`. O método vale para os demais módulos: antes de
escrever o `it()`, confira se a tela realmente produz o resultado esperado do
caso; quando não produz, o item entra aqui em vez de virar teste vermelho ou
cobertura falsa.

**Regra da casa respeitada:** não se mascara achado com teste. Um caso que a
tela não cumpre fica **pendente e documentado aqui**, nunca "coberto" por um
`it()` que afirma menos do que o caso pede.

---

## Ergonomia (/ergonomia)

### BLOQUEIO 1 — "Novo Risco" grava em `ergonomia_riscos`, mas o Inventário GRO lê de `gro_riscos`

**Gravidade:** alta (trava o coração do módulo: inventário, priorização, PGR).
**Status:** aberto — decisão do dono do produto.

**O que acontece.** O botão **"Novo Risco"** da tela (e também o "Novo" de
dentro da aba Inventário GRO) abre o mesmo formulário `RiscoForm`, cujo submit
chama `useErgonomia.createRisco`, que **insere em `ergonomia_riscos`**. Só que a
aba **Inventário GRO**, os **cards de prioridade** e a aba **Riscos
Prioritários** leem de **`gro_riscos`** (`useGRORiscos`). As duas tabelas são
entidades diferentes. Resultado: o risco cadastrado pela tela **não aparece no
Inventário GRO** nem nos cards — exatamente o que os casos mandam conferir.

**Evidência (código):**

- `src/pages/Ergonomia.tsx`
  - o `RiscoForm` (modal "Novo Risco") tem `onSubmit` → `createRisco` (de
    `useErgonomia`);
  - a aba Inventário GRO renderiza `<GROPainel onNovo={() => setShowRiscoForm(true)} />`
    — ou seja, o "Novo" de dentro do painel abre o MESMO form que grava na
    tabela errada;
  - os cards "Riscos Prioritários" e a lista do painel usam `groRiscos`
    (`riscosCriticosAltos = groRiscos.filter(...)`).
- `src/hooks/useErgonomia.ts` (linhas ~200-221): `createRisco` →
  `insert` em **`ergonomia_riscos`**.
- `src/hooks/useGRORiscos.ts`: a query lê **`gro_riscos`** (linhas ~25-29);
  `criarRisco` insere em `gro_riscos` (linhas ~58-64). O **único** caminho de UI
  que escreve `gro_riscos` é `importarDaCampanha` (importação do módulo
  Psicossocial) — **não há** caminho, pela tela de Ergonomia, que crie um risco
  no inventário unificado do GRO.

**Casos e2e travados por isto** (seguem documentados em `qa_casos_teste`,
pendentes de ponte até a correção):

| código | título | por que depende do GRO |
|---|---|---|
| ERGO-010 | Cadastrar risco com os campos obrigatórios | passo 3 pede "aparece no Inventário GRO" |
| ERGO-014 | Severidade e probabilidade compõem a criticidade | criticidade é `gro_riscos.nivel_risco` |
| ERGO-015 | Risco de alta criticidade aparece em Prioritários | aba lê `gro_riscos` |
| ERGO-020 | Criar ação vinculada a um risco do inventário | precisa de um risco no `gro_riscos` |
| ERGO-024 | Encerrar risco crítico sem ação é impedido | regra vive em `useGRORiscos.inativarRisco` |
| ERGO-061 | Cards de estatísticas refletem o inventário | cards leem `gro_riscos` |

(ERGO-013 e ERGO-016 também tocam o cadastro de risco e provavelmente herdam o
mesmo bloqueio; reavaliar junto.)

**Opções de correção (decisão do produto):**

1. **Religar a tela ao GRO unificado** — o `RiscoForm`/"Novo Risco" (e o
   `GROPainel.onNovo`) passam a chamar `useGRORiscos.criarRisco` (grava em
   `gro_riscos`), mapeando eixo/severidade/probabilidade para o modelo do GRO.
   É a correção que faz a tela cumprir os casos como estão escritos.
2. **Unificar as tabelas** — migrar `ergonomia_riscos` para `gro_riscos` (ou
   fazer `ergonomia_riscos` virar uma visão sobre `gro_riscos`). Maior, mas tira
   a duplicidade de entidade de vez.

Feita a correção (qualquer uma), os 6+ casos acima viram testes que semeiam
(criar risco pela tela → conferir no Inventário GRO), no mesmo padrão do
ERGO-001 já entregue.

---

### BLOQUEIO 2 — AcaoForm não exige "Responsável" (descompasso doc × código)

**Gravidade:** baixa (um campo; decisão rápida).
**Status:** aberto — decisão do dono do produto (corrigir a tela OU o caso).

**O que acontece.** O caso **ERGO-021 — "Responsável é exigido na ação"**
espera que o salvar seja barrado sem responsável. Na tela, o `AcaoForm` só trava
o salvar por falta de **título**; o campo Responsável é **opcional** (sem
asterisco, sem validação).

**Evidência (código):** `src/components/ergonomia/AcaoForm.tsx`
- `<Label htmlFor="responsavel">Responsável</Label>` — sem `*`, input sem
  `required` (linhas ~237-243);
- botão: `disabled={isLoading || !formData.titulo}` (linha ~273) — só o título;
- `handleSubmit` (linhas ~79-101) não valida responsável.

**Opções (uma das duas):**

1. **Alinhar a tela ao caso** — tornar Responsável obrigatório no `AcaoForm`
   (asterisco + trava no submit). Aí ERGO-021 vira teste read-only simples
   (abre "Nova Ação", preenche título sem responsável, confere salvar
   bloqueado), no padrão do ERGO-011.
2. **Alinhar o caso à tela** — se responsável é opcional por decisão de produto,
   atualizar a descrição de ERGO-021 em `qa_casos_teste` para refletir isso (ex.:
   "responsável é opcional"), e então documentar/implementar o caso certo.

Enquanto não houver decisão, ERGO-021 fica pendente (não implementado).

---

## O que NÃO está bloqueado (já entregue)

- **ERGO-001** — "inicializa a base NR-17 e abre as 7 abas do fluxo GRO":
  implementado semeando o inventário NR-17 pela própria tela (botão
  "Inicializar Itens NR-17", idempotente no backend). Prova que a abordagem de
  teste que semeia funciona; o que falta nos demais casos é a tela cumprir o
  caso (Bloqueio 1) — não a técnica de teste.

---

## Próximos módulos

O mesmo levantamento deve ser feito por módulo da fila de `qa_cobertura_e2e_lacunas()`.
Quando um caso `e2e` não puder ser coberto porque a tela não faz o que ele
descreve, acrescente uma seção aqui (módulo → bloqueio → evidência → casos
travados → opções) em vez de forçar um teste. Assim a fila de correção de
produto cresce junto com o diagnóstico, e os testes de tela voltam a andar assim
que cada bloqueio for resolvido.
