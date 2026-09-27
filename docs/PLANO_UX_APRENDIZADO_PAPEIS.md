# Plano de desenvolvimento — evolução de UX do módulo Aprendizado & Papéis

> Documento técnico de desenvolvimento. Escrito para a equipe que vai implementar.
> Base: varredura do módulo em 27/09/2026. Nada foi alterado no sistema ao escrever este plano.
> Fluxo obrigatório da casa: desenvolver → registrar na `main` → esteira aplica no **staging** →
> validação humana no staging/homologação → **só então** produção (script no SQL Editor + publicar
> telas na Vercel avançando `producao`). A produção nunca é tocada por esta esteira.

---

## 1. Objetivo

Elevar a usabilidade do módulo **Aprendizado & Papéis** sem remover nenhum recurso atual, e
adicionar a integração com o **Mapa Comportamental** (perfil ideal por cargo + aderência do
colaborador que ocupa a função).

Meta de produto (palavras do dono): o módulo deve ser **fácil, confiável e criar dependência** —
o RH precisa voltar a ele para "fechar pendências" e enxergar valor a cada visita.

Diagnóstico-resumo: o módulo **já entrega o resultado final** (manual de função com/sem POPs,
assinado). O gargalo de UX não é falta de recurso — é **excesso de recursos mal orquestrados**:
muitas portas de entrada e nenhuma que diga "comece por aqui"; valor enterrado em camadas de abas.

---

## 2. Mapa do estado atual (para quem nunca abriu o módulo)

### 2.1 Rota e navegação
- Rota: `/aprendizado-papeis` → `src/pages/AprendizadoPapeis.tsx`.
- Item de menu: `src/components/layout/AppSidebar.tsx:190`, seção "Desenvolvimento & Performance".
- **Divergência de nome já existente:** menu diz **"Aprendizado & Competências"**, página diz
  **"Aprendizado & Papéis"**.

### 2.2 Estrutura de telas
Abas de topo (`AprendizadoPapeis.tsx`): **Funções · Assinaturas · Indicadores · Configurações**.

- **Funções** → `FuncaoList.tsx` (lista) → ao selecionar, `FuncaoDetail.tsx` (detalhe).
  - `FuncaoDetail` tem um **segundo nível de 6 abas**: Atividades · Competências · Indicadores ·
    EPIs & Treinamento · Gerar Vaga · Gerar Proposta.
- **Assinaturas** → `AssinaturasManualTab.tsx` (acompanhamento de envios).
- **Indicadores** → `AprendizadoStats.tsx` (estatísticas globais).
- **Configurações** → `AprendizadoConfig.tsx`.

### 2.3 Componentes por área (`src/components/aprendizado/`)
- Lista/detalhe: `FuncaoList.tsx`, `FuncaoDetail.tsx`.
- Construção da função: `AtividadesSection.tsx`, `CompetenciasSection.tsx`, `IndicadoresSection.tsx`,
  `EpisSection.tsx`, `TreinamentosSection.tsx`, `ResponsabilidadeField.tsx`.
- Entradas por IA/áudio/texto: `GerarFuncaoIAModal.tsx`, `AudioAtividadesImport.tsx`,
  `TextoAtividadesImport.tsx`, `AudioCompetenciasImport.tsx`, `TextoCompetenciasImport.tsx`.
- POPs: `PopSection.tsx`, `PopGerarModal.tsx`, `PopEditorModal.tsx`, `PopDiffModal.tsx`,
  `GerarPopsEmLoteModal.tsx`, `ExportarTodosPopsPdf.tsx`.
- Saídas: `GerarVagaSection.tsx`, `GerarPropostaSection.tsx`, `ManualFuncaoModal.tsx`,
  `EnviarManualAssinaturaDialog.tsx`, `AssinaturasManualTab.tsx`.
- Métricas/config: `AprendizadoStats.tsx`, `IndicadorDetailModal.tsx`, `AprendizadoConfig.tsx`.

### 2.4 Dados (hook `src/hooks/useAprendizado.ts`, `usePopAtividade.ts`)
- `cargos` — registro do cargo (id, nome, tenant_id, empresa_id, departamento_id, descricao, nivel,
  `objetivo_funcao`, `escopo_geral`, `subordinacao`, `interfaces_cargo`, `padroes_execucao`,
  `cultura_esperada`, `criterios_sucesso`, `erros_riscos`, `ferramentas_cargo`, `responsabilidade`,
  `requisitos_formacao`, `requisitos_experiencia`, faixa salarial).
- Filhas por `cargo_id`: `funcao_atividades`, `funcao_competencias` (`tipo` ∈ tecnica |
  comportamental | cognitiva), `funcao_indicadores`, `funcao_ferramentas`, `funcao_conteudos`,
  `funcao_responsabilidades`, `funcao_epi_vinculacoes`, `funcao_pops`, `funcao_config`.
- Manuais e assinatura: `manuais_gerados`, `manual_funcao_assinaturas`, `manual_funcao_links`.
- **Edge Functions de IA** usadas: `ai-gerar-funcao-completa`, `ai-manual-funcao`,
  `ai-texto-atividades`, `ai-audio-atividades`, `ai-responsabilidade-funcao`, `ai-gerar-vaga`,
  `ai-gerar-proposta`, `ai-gerar-trilha-manual`, e a de POP em `usePopAtividade`.

### 2.5 Vínculo colaborador ↔ cargo (ponto sensível)
- **Não existe FK** ligando colaborador a `cargos`. Os colaboradores vivem em `admissoes` (o campo
  `admissoes.cargo` é **texto livre**) e em `usuarios_base` (`cargo_funcao` **texto livre**).
- O envio para assinatura casa colaborador ao cargo por **comparação de string**
  (`EnviarManualAssinaturaDialog.tsx:51-55`: `c.cargo.trim().toLowerCase() === cargoNome...`).
  Qualquer divergência de digitação → colaborador não aparece.

### 2.6 Mapa Comportamental (para a integração)
- Página `src/pages/MapaComportamental.tsx`; ficha individual `FichaPessoa.tsx`; resultado
  `ResultadoMapa.tsx`; permissões `useMapaComportamentalPermissoes.ts`.
- Motor determinístico e auditável (não é IA/caixa-preta): `src/data/instrumentos/mapaComportamental.ts`
  (`calcularMapa`). Dimensões: **Arquétipo** (Pioneiro/Conector/Guardião/Estrategista), **Motor**
  (Racional/Relacional/Pragmático), **Modo** (Constante/Cadenciado), e **Confiabilidade** (alta/baixa).
- Resultados em `mapa_comportamental_respostas` (uma linha por aplicação; `auth_user_id`,
  `usuario_id`, `colaborador_cpf`, `arquetipo`, `resultado` jsonb, `confiabilidade`, `status`).
  **Não há `cargo_id` nessa tabela.**
- **Não existe hoje** nenhum conceito de perfil ideal / aderência / match (greenfield).
- Restrição de produto do Mapa (obrigatória de respeitar): **"não existe perfil melhor nem pior"**,
  linguagem de *tendência* (não capacidade), e o próprio código diz **"não é sobre movimentação,
  promoção ou desligamento"** (`FichaPessoa.tsx:48-52`, RN-010).

---

## 3. Princípios de design que guiam este plano

1. **Não remover recursos.** Reorganizar e revelar, nunca amputar.
2. **Conduzir, não expor.** Toda tela vazia deve dizer o próximo passo.
3. **Determinístico e explicável** onde já é (o match reaproveita o motor do Mapa, sem IA opaca).
4. **Consistência de padrões** (edição, cores por token, feedback de progresso).
5. **Respeitar o enquadramento ético do Mapa** ao introduzir aderência.
6. **Seguir as regras da casa** de migration + script de entrega, RLS por perfil e QA.

---

## 4. Backlog priorizado

| # | Item | Prioridade | Esforço | Onda |
|---|------|-----------|---------|------|
| QW1 | Unificar o nome do módulo (menu × página) | P2 | Trivial | Quick win |
| QW2 | Corrigir contagem do toast no lote de POPs (`sucessos + 1`) | P2 | Trivial | Quick win |
| QW3 | Criar função direto no estado vazio (sem sair para Cadastros) | P1 | Baixo | Quick win |
| QW4 | Renomear aba global "Indicadores" → "Visão geral" | P1 | Baixo | Quick win |
| O1-A | Checklist de completude por função | P1 | Baixo-médio | Onda 1 |
| O1-B | Estado inicial guiado (3 caminhos) na função vazia | P0 | Médio | Onda 1 |
| O1-C | Unificar entradas (IA/áudio/texto/arquivo) num ponto só | P0 | Médio | Onda 1 |
| O1-D | Agrupar as 6 abas internas em "Construir" × "Usar" | P1 | Baixo | Onda 1 |
| O2-A | `cargo_id` canônico no colaborador (conserta assinatura) | P0 | Médio-alto | Onda 2 |
| O2-B | Central de POPs por função | P1 | Médio | Onda 2 |
| O2-C | Padronizar edição inline e cores por token; progresso no manual | P2 | Médio | Onda 2 |
| O3-A | Perfil comportamental ideal por cargo | P1 | Médio | Onda 3 |
| O3-B | Aderência (match) na ficha do Mapa, gated e enquadrado | P1 | Médio-alto | Onda 3 |

Legenda de prioridade: **P0** crítico (bloqueia o valor), **P1** alto impacto, **P2** polimento.

---

## 5. Especificação detalhada

### QW1 — Nome único do módulo
- Decidir o nome canônico (recomendado: **"Aprendizado & Papéis"**, que é o que a página já usa e
  o que o dono chama).
- Alterar `AppSidebar.tsx:190` (`title`) e o `<h1>` de `AprendizadoPapeis.tsx:30` para bater.
- Conferir também `GlobalSearch.tsx` e quaisquer breadcrumbs.
- **Aceite:** menu, título e busca exibem exatamente o mesmo nome.

### QW2 — Bug de contagem no lote de POPs
- Arquivo: `GerarPopsEmLoteModal.tsx:110`.
- Hoje: `toast.success(\`POPs gerados: ${sucessos + 1} de ${total}\`)` — o `+1` é herança de um cálculo
  antes do `setState` assíncrono e **reporta um a mais**.
- Corrigir contando a partir do array de resultados após o loop (usar uma variável local incrementada
  no `try`, não o `sucessos` derivado de estado defasado). Ex.: acumular `okLocal++` dentro do sucesso
  e usar `okLocal` no toast.
- **Aceite:** com N atividades e K falhas, o toast diz exatamente `N-K de N`.

### QW3 — Criar função no estado vazio
- Arquivo: `FuncaoList.tsx:456-461` (bloco "Nenhuma função cadastrada" que hoje manda ir a
  Cadastros → Funções).
- Trocar o texto por um botão **"Criar primeira função"** que abre um mini-form (nome, nível,
  departamento) e insere em `cargos`, reaproveitando a mutação de `useCadastros`/`usePapeisEmpresa`.
- Manter o atalho textual para Cadastros como link secundário.
- **Aceite:** é possível criar um cargo sem sair do módulo; ele aparece na lista imediatamente.

### QW4 — Renomear aba global "Indicadores"
- Há **dois** "Indicadores": aba de topo (estatísticas globais) e aba interna da função (KPIs do
  cargo). Renomear a de topo para **"Visão geral"** (`AprendizadoPapeis.tsx:46-48`, manter o valor
  `value="indicadores"` para não quebrar estado, mudar só o rótulo e o ícone se quiser).
- **Aceite:** nenhum usuário confunde as duas; a interna continua "Indicadores".

### O1-A — Checklist de completude por função
Cria a sensação de "o que falta" (motor da dependência).

- **Onde:** no card de cada função em `FuncaoList.tsx` (linha de contadores, ~509-521) e no topo de
  `FuncaoDetail.tsx`.
- **Itens do checklist (derivados de dados já existentes):** Objetivo definido · Atividades ≥ 1 ·
  Competências ≥ 1 · POPs (X de N atividades) · EPIs revisados · Perfil ideal definido (Onda 3) ·
  Manual gerado.
- **Cálculo:** reaproveitar as queries de contagem que já existem em `FuncaoList` (`atividadeCounts`,
  `competenciaCounts`, `epiCounts`) + presença de `manuais_gerados` (já carregado como
  `cachedManuais`). Adicionar contagem de `funcao_pops` por cargo.
- **UI:** um `Progress` fino + um popover/checklist com os itens marcados. Percentual = itens
  concluídos / total aplicável.
- **Aceite:** o card mostra % de completude; clicar revela o que falta e leva à aba correspondente.

### O1-B — Estado inicial guiado (a função vazia conduz)
- **Onde:** `FuncaoDetail.tsx`, quando `!hasEnrichedData` e sem atividades/competências.
- **UI:** substituir o layout de abas por um "primeiro passo" com 3 cartões grandes:
  1. **Gerar com IA** (abre `GerarFuncaoIAModal`).
  2. **Gravar/enviar entrevista (áudio)** (ver O1-C — precisa gerar a função inteira).
  3. **Colar / subir descrição** (ver O1-C).
- Depois de qualquer caminho preencher a função, o layout guiado some e vira o atual.
- **Aceite:** ao abrir um cargo vazio, o usuário vê 3 caminhos claros; não vê 6 abas vazias.

### O1-C — Unificar entradas (coerência das portas)
Problema: hoje `GerarFuncaoIAModal` gera a função inteira (atividades+competências+indicadores),
mas os importadores por **áudio/texto** só trazem *atividades* OU *competências* isoladas
(`AtividadesSection.tsx:100-127`, `CompetenciasSection.tsx:116-117`). Incoerente.

- **Meta:** um único ponto **"Adicionar conteúdo"** no `FuncaoDetail` com 4 modos (IA / Áudio /
  Texto / Arquivo), todos capazes de alimentar a **função inteira**.
- **Backend:** avaliar estender `ai-gerar-funcao-completa` para aceitar `origem: 'audio'|'texto'`
  recebendo a transcrição/《texto》 como `descricao_livre` (a de áudio primeiro transcreve via a
  função de áudio existente e depois passa o texto ao gerador completo). Reusar o pipeline de
  `ai-audio-atividades`/`ai-texto-atividades` só para a parte de transcrição/leitura de arquivo.
- **Compatibilidade:** manter os importadores por-seção como "atalho avançado" dentro de Atividades
  e Competências — não remover.
- **Aceite:** subir um áudio de entrevista gera atividades **e** competências **e** indicadores numa
  única prévia editável (mesmo componente de revisão do `GerarFuncaoIAModal`).

### O1-D — Reagrupar as 6 abas internas
- Em `FuncaoDetail.tsx:247-267`, agrupar visualmente em dois blocos:
  - **Construir a função:** Atividades · Competências · Indicadores · EPIs & Treinamento.
  - **Usar a função:** Gerar Vaga · Gerar Proposta · (Onda 3) Perfil comportamental.
- Pode ser um separador/label dentro da `TabsList`, sem trocar as rotas de aba.
- **Aceite:** o usuário distingue "montar o cargo" de "usar o cargo".

### O2-A — `cargo_id` canônico no colaborador (estrutural)
Sem isto, a assinatura falha por digitação e o match (O3) não tem chave de junção.

- **Migration:** adicionar `cargo_id uuid` (FK → `cargos(id)`, `ON DELETE SET NULL`) em
  `admissoes` (e/ou `usuarios_base`, avaliar qual é a fonte canônica de "colaborador"). `IF NOT
  EXISTS`.
- **Backfill idempotente:** resolver `cargo_id` a partir do texto atual por nome case-insensitive,
  dentro do mesmo `tenant_id`/`empresa_id` (há precedente:
  `20260509213258_*.sql`). Onde houver ambiguidade/sem match, deixar `NULL` e listar num relatório.
- **UI de cadastro:** no cadastro/edição de colaborador, trocar o campo texto por um **select de
  cargos** (com opção de manter texto livre legado para casos não resolvidos, exibindo aviso).
- **Ajustar** `EnviarManualAssinaturaDialog.tsx:51-55` para filtrar por `cargo_id` quando disponível,
  com fallback ao nome-texto atual (transição suave).
- **RLS:** a coluna não é dado sensível novo por si; manter as políticas da tabela.
- **Aceite:** colaboradores aparecem no envio de assinatura mesmo com variação de digitação no texto
  legado; relatório mostra quantos ficaram sem `cargo_id`.

### O2-B — Central de POPs por função
- **Problema:** POPs ficam a 3 cliques (Função → Atividades → expandir → POP). Sem visão única.
- **UI:** nova sub-aba/painel **"POPs"** no `FuncaoDetail` listando todos os POPs do cargo
  (`funcao_pops` por `cargo_id`, já consultado em `usePopAtividade`) com: código, título, status
  (rascunho/em revisão/publicado/desatualizado), versão, e ações (editar → `PopEditorModal`, ver
  diff → `PopDiffModal`, exportar → `ExportarTodosPopsPdf`).
- Reaproveitar os componentes existentes; é agregação de UI, não novo backend.
- **Aceite:** numa tela só, o RH vê todos os POPs da função e seus status.

### O2-C — Padronização visual
- **Edição inline:** unificar num padrão (recomendado: o de "lápis → salvar/cancelar" já usado em
  Atividades) para descrição, conteúdos, ferramentas, responsabilidade e competências.
- **Cores:** substituir classes hardcoded (`bg-blue-100 text-blue-800`, etc. em `FuncaoList`,
  `AtividadesSection`, `CompetenciasSection`) por tokens do tema, garantindo dark mode. Alinhar com o
  guia de `dataviz`/design tokens do projeto.
- **Progresso:** dar ao "Gerar Manual (global)" o mesmo feedback de progresso do lote de POPs, ou ao
  menos etapas ("montando estrutura → escrevendo seções → finalizando").
- **Aceite:** um único padrão de edição; badges/cores corretos em claro e escuro.

### O3-A — Perfil comportamental ideal por cargo
Define o "alvo" comportamental da função, reusando as dimensões determinísticas do Mapa.

**Modelo de dados (migration):**
```sql
-- Nova tabela: perfil comportamental ALVO do cargo (nível cargo, NÃO é dado pessoal)
CREATE TABLE IF NOT EXISTS public.cargo_perfil_ideal (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL,
  empresa_id   uuid,
  cargo_id     uuid NOT NULL REFERENCES public.cargos(id) ON DELETE CASCADE,
  arquetipo_ideal   text,        -- 'pioneiro'|'conector'|'guardiao'|'estrategista'
  motor_ideal       text[],      -- subconjunto de 'racional'|'relacional'|'pragmatico'
  modo_ideal        text,        -- 'constante'|'cadenciado'|'misto'
  observacoes       text,
  definido_por      uuid,
  definido_por_nome text,
  algoritmo_versao  text NOT NULL DEFAULT 'v1',  -- casar com mapaComportamental.ts
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, cargo_id)
);
```
- **Enums como texto validado** (não criar enum novo no banco): validar contra os valores de
  `Arquetipo`/`Motor`/`Modo` de `src/data/instrumentos/mapaComportamental.ts` no front e numa
  função de guarda. Assim o front e o banco não divergem quando o instrumento evoluir de versão.
- **RLS:** definir = admin/RH (`has_minimum_role(uid,'admin')`); leitura = quem o sistema de perfil
  permitir o módulo `mapa_comportamental` **ou** `aprendizado` (`perfil_permite_modulo(...)`). Como
  a tabela guarda alvo do cargo (não dado pessoal de saúde), **não** é "tabela sensível" no sentido
  LGPD — documentar essa avaliação na própria migration para a rotina QA PERFIL-003 não acusar
  (ou adicionar a política RESTRICTIVE se o time preferir uniformidade).
- **UI:** nova aba **"Perfil comportamental"** em `FuncaoDetail` (bloco "Usar a função"), onde
  RH/gestor define arquétipo/motor/modo alvo. Botão **"Sugerir com IA"** que propõe o alvo a partir
  de `objetivo_funcao` + atividades + competências comportamentais já cadastradas (nova ação numa
  edge function, ex.: `ai-responsabilidade-funcao` com `acao: 'sugerir_perfil_ideal'`), sempre como
  prévia editável.
- **Aceite:** cada cargo pode ter um perfil ideal salvo e editável; a sugestão por IA é opcional e
  revisável.

### O3-B — Aderência (match) na ficha do Mapa
Mostra, para gestão/liderança, o quanto o mapa da pessoa "flui" com o perfil ideal do cargo que ela
ocupa. **Determinístico**, sem armazenar nota pessoal.

- **Cálculo (função pura, espelhando o estilo de `calcularMapa`):** comparar
  arquétipo/motor/modo da pessoa (de `mapa_comportamental_respostas.resultado`) com o
  `cargo_perfil_ideal`. Resultado **qualitativo**, não uma nota fria:
  - arquétipo igual → "flui naturalmente"; vizinho → "adapta-se"; oposto → "exige mais energia";
  - idem para motor e modo.
  - Colocar a função em `src/data/instrumentos/` ou `src/lib/` como pura e testável (Vitest).
- **Junção de dados:** pessoa (`auth_user_id`/`colaborador_cpf`) → colaborador → `cargo_id`
  (depende de **O2-A**) → `cargo_perfil_ideal`. **Pré-requisito duro: O2-A.**
- **Exposição via RPC SECURITY DEFINER** (padrão do Mapa): expor só o resultado agregado da
  aderência, **sem** vazar respostas item a item (segue RN-003). Reusar/estender as permissões de
  `mapa_comportamental_ver_mapa`.
- **UI:** seção "Aderência ao estilo da função" em `FichaPessoa.tsx` (e opcionalmente uma nova aba
  "Aderência" no Mapa), **visível só a manager+** (`podeVerPainel`/`podeVerMapaTime` já existem em
  `useMapaComportamentalPermissoes`). **Nunca** exibir ao próprio colaborador como julgamento.
- **Enquadramento ético (obrigatório):**
  - Rotular como **"aderência ao estilo esperado da função"**, linguagem de desenvolvimento
    ("onde a pessoa tende a fluir e onde pode precisar de mais apoio/energia"), **não** score de
    "aptidão".
  - **Aviso fixo** de que não serve para movimentação/promoção/desligamento (coerente com RN-010 e
    `FichaPessoa.tsx:48-52`).
  - **Suprimir** a aderência quando `confiabilidade = 'baixa'` no mapa da pessoa.
- **Decisão de produto a confirmar com o dono ANTES de codar:** o enquadramento é
  "aderência de desenvolvimento" (recomendado) ou algo mais avaliativo? Isto muda copy, permissões
  e onde aparece.
- **Aceite:** gestor vê a aderência com linguagem de tendência + aviso; colaborador não vê
  julgamento; mapas de baixa confiabilidade não geram aderência.

---

## 6. Regras da casa para as mudanças de banco (O2-A e O3-A)

Toda mudança de banco = **duas entregas** (ver `CLAUDE.md`):
1. **Migration** em `supabase/migrations/` — o que a esteira aplica no staging.
2. **Script de entrega** em `docs/script_*.sql` — para o usuário colar no SQL Editor de produção.

Pontos de atenção específicos deste plano:
- **Carimbo único e em ordem:** gerar com `date -u +%Y%m%d%H%M%S`; conferir o último carimbo da
  pasta antes (não escolher número redondo). Rodar `npm run qa:carimbos`.
- **`cargo_perfil_ideal` cria TABELA nova** → no **script de entrega** (não na migration) evitar a
  pegadinha do "auto-RLS" do SQL Editor:
  - criar a tabela por `EXECUTE` dentro de um bloco `DO`, montando a string como
    `'CREATE ' || 'TABLE public.cargo_perfil_ideal (...)'` (a sequência contígua `CREATE TABLE` não
    pode existir no texto cru);
  - nas funções do script, **não** usar `SELECT ... INTO var` — atribuir por subconsulta escalar.
  - A **migration** equivalente pode manter `CREATE TABLE` normal.
- **Nunca** escrever marca de aspas-dólar (`$$`, `$function$`) dentro de comentário; conferir número
  PAR de marcas no arquivo inteiro.
- **Idempotência** sempre (`IF NOT EXISTS`, blocos `DO` com `EXCEPTION WHEN OTHERS THEN RAISE
  NOTICE`).
- **O2-A faz backfill/UPDATE em dado existente** (`admissoes.cargo_id`): antes do UPDATE, no script
  de entrega, guardar as linhas afetadas em `backup_admissoes_cargoid_<aaaammdd>` e deixar no
  comentário final o UPDATE de reversão (produção não tem PITR).
- Terminar o script com **um** `SELECT` de conferência (incluir coluna de erro quando houver).
- RLS: se marcar `cargo_perfil_ideal` como sensível, adicionar `perfil_restringe_leitura_*`; senão,
  documentar a exceção dentro da rotina QA PERFIL-003.

---

## 7. QA (regras da casa)

- **Motor SQL (`qa_*`):** ao mexer em área coberta, rodar a bateria da família no staging
  (`qa_rodar_bateria('manual', '<path do módulo>')`) e incluir na conferência do script de entrega.
- **Documentação antes do teste:** todo teste de tela nasce de um caso `e2e` documentado em
  `qa_casos_teste`; só então adicionar o `it()` em `cypress/e2e/aprendizado-papeis.cy.ts` e a ponte
  em `qa_cobertura_e2e (codigo, spec, teste)`. A guarda `npm run qa:cobertura-e2e` reprova `it()`
  inventado.
- **Testes unitários (Vitest):** a função pura de aderência (O3-B) e a de completude (O1-A) devem ter
  testes de tabela-verdade (arquétipos iguais/vizinhos/opostos; confiabilidade baixa → sem match).
- **Regressão:** garantir que os importadores por-seção e os fluxos de POP/assinatura seguem
  funcionando após a reorganização (O1-D, O2-B).

---

## 8. Sequência de entrega recomendada

1. **Quick wins** (QW1–QW4): sem banco, baixo risco, ganho imediato de coerência.
2. **Onda 1** (O1-A…O1-D): clareza e condução — é onde nasce a "dependência". Sem banco (exceto
   contagem de POPs para o checklist, que é leitura).
3. **Onda 2** (O2-A…O2-C): O2-A é banco (migration + script + backfill com backup); conserta a
   assinatura e destrava o match. O2-B/O2-C são front.
4. **Onda 3** (O3-A, O3-B): depende de O2-A. **Confirmar o enquadramento ético com o dono antes de
   codar O3-B.** Banco em O3-A (migration + script). O3-B é RPC + front.

Cada onda: desenvolver na branch da sessião → registrar na `main` → validar no **staging**
(https://youreyes-dev.github.io/youreyesnovo/teste/) → só após "aprovado" seguir para produção
(script no SQL Editor de produção + publicar telas na Vercel avançando `producao` via PR
`main → producao`). **A produção nunca é tocada pela esteira.**

---

## 9. Riscos e decisões abertas

| Tema | Risco/decisão | Encaminhamento |
|------|---------------|----------------|
| Vínculo colaborador↔cargo | Texto legado ambíguo pode não resolver no backfill | Relatório de não-resolvidos + UI para corrigir manualmente |
| Enquadramento do match | Colidir com "não existe perfil melhor/pior" (RN-010) | **Decisão do dono** antes de O3-B; default = aderência de desenvolvimento |
| Sensibilidade de `cargo_perfil_ideal` | Classificar como sensível ou não (QA PERFIL-003) | Documentar avaliação na migration; default: não sensível (alvo do cargo, não dado pessoal) |
| Extensão das edge functions de IA | Custo/latência ao gerar função inteira a partir de áudio | Transcrever → reusar `ai-gerar-funcao-completa`; medir tempo |
| Versão do instrumento | Perfil ideal salvo com `algoritmo_versao` pode divergir de mapas futuros | Guardar versão; recomparar/avisar quando a versão do mapa da pessoa diferir |

---

## 10. Resumo de arquivos que serão tocados (referência rápida)

- **Front (existentes):** `AppSidebar.tsx`, `AprendizadoPapeis.tsx`, `FuncaoList.tsx`,
  `FuncaoDetail.tsx`, `AtividadesSection.tsx`, `CompetenciasSection.tsx`,
  `GerarPopsEmLoteModal.tsx`, `EnviarManualAssinaturaDialog.tsx`, `ManualFuncaoModal.tsx`,
  `FichaPessoa.tsx`, `useMapaComportamentalPermissoes.ts`.
- **Front (novos):** componente de checklist de completude; componente de estado inicial guiado;
  ponto unificado "Adicionar conteúdo"; central de POPs; aba "Perfil comportamental"; seção de
  aderência; função pura de aderência + testes.
- **Banco (novos):** migration + `docs/script_*.sql` para `admissoes.cargo_id` (O2-A) e
  `cargo_perfil_ideal` (O3-A); RPC de aderência (O3-B).
- **Edge functions:** extensão de `ai-gerar-funcao-completa` (origem áudio/texto) e nova ação de
  sugestão de perfil ideal.
- **QA:** casos `qa_casos_teste` + `it()` em `cypress/e2e/aprendizado-papeis.cy.ts` + testes Vitest.

---

*Fim do plano. Próximo passo sugerido: aprovar o escopo das ondas e a decisão de enquadramento do
match; então iniciar pelos Quick wins no ambiente de teste.*
