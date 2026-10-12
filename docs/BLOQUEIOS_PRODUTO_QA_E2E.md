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
**Status:** ✅ RESOLVIDO em 12/10/2026 (opção 1 — religar a tela ao GRO unificado).

> **Resolução.** O `onSubmit` do "Novo Risco" (em `src/pages/Ergonomia.tsx`) passou
> a mapear o formulário para o modelo do GRO e gravar via `useGRORiscos.criarRisco`
> (tabela `gro_riscos`, subtipo `fisico`, fonte `manual`). O `nivel_risco`
> (criticidade) é calculado pelo trigger `calcular_nivel_gro_risco` no banco. O
> `RiscoForm` não mudou de UI; só o destino da escrita. Consequência: o risco
> cadastrado pela tela agora aparece no Inventário GRO e nos cards. Destravou de
> fato **ERGO-010**, **ERGO-014** (criticidade na linha do Inventário GRO) e
> **ERGO-061** (cards de estatística) — todos cobertos no Cypress. Os demais que
> eu havia listado como destravados (**ERGO-015/020/024**) têm, na verdade,
> descompasso de produto PRÓPRIO, documentado abaixo (Bloqueios 2, 3 e 4) — não
> foram resolvidos por esta correção. A tabela antiga `ergonomia_riscos` vira legado (o
> painel `ErgonomiaStats`, único leitor, não é renderizado em lugar nenhum). O
> **eixo** (físico/cognitivo/organizacional) e os **impactos potenciais** do
> formulário não têm campo no modelo GRO e ficam fora do registro unificado — por
> isso o **ERGO-012** ("eixo classifica o risco") segue sem suporte.

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

### BLOQUEIO 3 — a aba "Riscos Prioritários" não lê o inventário GRO

**Gravidade:** média. **Status:** aberto.
**Trava:** ERGO-015 ("Risco de alta criticidade aparece na aba Prioritários").

**O que acontece.** A aba "Riscos Prioritários" (`#tab-ergo-prioritarios`)
renderiza `<InventarioRiscos analises={analises} />`, que lista os riscos
extraídos das **análises AEP** (`useErgonomiaAnalises` → `analise.riscos_identificados`).
Um risco crítico cadastrado pelo "Novo Risco" (que agora vai para `gro_riscos`)
**não aparece** nessa aba — ela é alimentada só pela AEP. O card do topo "Riscos
Prioritários" conta de `gro_riscos`, mas a ABA não.

**Evidência:** `src/pages/Ergonomia.tsx` (TabsContent "prioritarios" →
`InventarioRiscos analises={analises}`); `src/components/ergonomia/InventarioRiscos.tsx`
(prop `analises: ErgonomiaAnalise[]`, expande `riscos_identificados`).

**Opções:** a aba Prioritários passar a listar os `gro_riscos` de nível
`alto`/`critico` (sozinha ou somada às análises AEP). Feito isso, ERGO-015 vira
teste que semeia (criar risco crítico → aparece em Prioritários).

---

### BLOQUEIO 4 — não dá para vincular uma ação a um risco do GRO pela tela

**Gravidade:** média. **Status:** aberto.
**Trava:** ERGO-020 ("Criar ação vinculada a um risco do inventário").

**O que acontece.** O `AcaoForm` tem um select "Vinculada ao Risco" que recebe
`riscos?: ErgonomiaRisco[]` (entidade antiga) — e o `Ergonomia.tsx` **não passa**
esse prop ao renderizar o form. Então a lista de riscos para vincular está
sempre vazia, e nem é da entidade do GRO. Não há como, pela tela, criar uma ação
vinculada a um risco do Inventário GRO.

**Evidência:** `src/components/ergonomia/AcaoForm.tsx` (prop `riscos?: ErgonomiaRisco[]`,
select "Vinculada ao Risco"); `src/pages/Ergonomia.tsx` (`<AcaoForm>` sem prop `riscos`).

**Opções:** passar `riscos={groRiscos}` ao `AcaoForm` e tipar o vínculo na
entidade GRO, gravando a ação com o `acao_id`/vínculo no `gro_risco` (casa com
`useGRORiscos.vincularAcao`). Feito isso, ERGO-020 vira teste que semeia.

---

### BLOQUEIO 5 — não há como encerrar/arquivar um risco do GRO pela tela

**Gravidade:** média. **Status:** aberto.
**Trava:** ERGO-024 ("Encerramento de risco crítico sem ação vinculada é impedido").

**O que acontece.** A regra existe no hook (`useGRORiscos.inativarRisco` bloqueia
arquivar risco `alto`/`critico` sem `acao_id`), mas **nenhuma UI a aciona**: o
`GROPainel` (que lista os `gro_riscos`) só tem o seletor de ciclo (`status_gro`) e
não oferece "encerrar/arquivar". O único "arquivar" da tela é o de **análises AEP**
(`RegistrosErgonomicos` → `arquivarAnalise`), outra entidade. Sem botão, o caso
não é exercitável pela tela.

**Evidência:** `src/components/ergonomia/GROPainel.tsx` (sem ação de arquivar);
`src/hooks/useGRORiscos.ts` (`inativarRisco` com a regra de bloqueio);
`src/pages/Ergonomia.tsx` (`onArquivar={arquivarAnalise}` é só para análises AEP).

**Opções:** expor no `GROPainel` um "Encerrar/Arquivar risco" que chame
`inativarRisco` — que já devolve o erro de bloqueio quando o risco é alto/crítico
sem ação. Feito isso, ERGO-024 vira teste (tentar arquivar crítico sem ação →
bloqueio; vincular ação → permite).

---

## O que NÃO está bloqueado (já entregue)

- **ERGO-001** — "inicializa a base NR-17 e abre as 7 abas do fluxo GRO":
  implementado semeando o inventário NR-17 pela própria tela (botão
  "Inicializar Itens NR-17", idempotente no backend). Prova que a abordagem de
  teste que semeia funciona; o que falta nos demais casos é a tela cumprir o
  caso — não a técnica de teste.
- **ERGO-010/014/061** — cobertos no Cypress após a resolução do Bloqueio 1
  (criar risco → aparece no Inventário GRO; criticidade composta na linha; cards
  de estatística refletem o inventário).

---

## Próximos módulos

O mesmo levantamento deve ser feito por módulo da fila de `qa_cobertura_e2e_lacunas()`.
Quando um caso `e2e` não puder ser coberto porque a tela não faz o que ele
descreve, acrescente uma seção aqui (módulo → bloqueio → evidência → casos
travados → opções) em vez de forçar um teste. Assim a fila de correção de
produto cresce junto com o diagnóstico, e os testes de tela voltam a andar assim
que cada bloqueio for resolvido.
