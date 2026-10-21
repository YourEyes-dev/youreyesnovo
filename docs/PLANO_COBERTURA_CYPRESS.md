# Plano de cobertura dos testes de tela (Cypress)

**Data da fotografia:** 21/10/2026.
**Missão:** nenhuma alteração ou recurso novo pode derrubar o que já funciona. O Cypress é a
última linha de defesa — a que clica nas telas como o usuário. Este plano diz onde estamos,
o que falta e em que ordem fechar, começando pelo que **nunca pode parar**.

> Fonte dos números: a guarda `npm run qa:cobertura-e2e`, lida do banco ao vivo no log da
> esteira do staging (corrida de 20/10/2026). Prioridade, módulo e classificação por caso vêm das
> migrations (aproximação; o banco manda). Lista completa dos pendentes:
> `docs/cobertura_e2e_pendente_20261021.csv`.

---

## 1. Onde estamos

| | |
|---|---|
| Casos documentados com nível `e2e` | **785** |
| Com teste de tela (ponte `qa_cobertura_e2e`) | **390** (≈ 50%) |
| **Sem teste de tela** | **395** — 81 críticos, 148 altos, 138 médios, 26 baixos |
| Suíte completa | 390 testes, ~45 min, 100% verde em 20/10 |

Os 390 `it()` passam, mas olhe **o que** eles provam:

- ~170 (≈ 45%) só provam que **a tela abre** ("abre…", "carrega…", "mostra…").
  Detectam tela quebrada, não regra quebrada.
- Só ~57 executam uma ação de verdade (criar, salvar, enviar, aprovar…).
- O login válido é exercitado implicitamente (44 specs fazem login no `beforeEach`), mas **não
  existe um teste explícito** dele (AUTH-002 está documentado e sem teste).

**Conclusão:** a cobertura *numérica* (50%) superestima a cobertura *de risco*. Os fluxos que
movimentam dinheiro, prazo legal, dado de saúde e acesso têm pouquíssimo teste de ação.

## 2. Três problemas estruturais (antes de escrever mais teste)

### 2.1 O Cypress não protege a produção
- Roda **depois** do merge (job `telas` do `staging.yml`). Vermelho não impede nada.
- O PR `main → producao` (o gesto que publica na Vercel) **não exige** Cypress verde.
- A Rede de Segurança (`rede-seguranca.yml`) trava regressão **de banco** antes do merge, mas
  não de tela. O elo de tela está desprotegido.

### 2.2 ~15% dos pendentes não são "tela"
Cerca de **60 dos 395** descrevem regra de cálculo ou comportamento de banco: fronteiras do aviso
prévio, 40%/20% do FGTS, porte da empresa, cota PcD, idempotência de rotina, quarentena de AFD…
Isso pertence ao **motor SQL** (nível `api`), que roda em segundos e **trava o PR** pela Rede de
Segurança. Implementar no Cypress seria mais lento, mais frágil e menos protetor. Ação:
reclassificar (`nivel` → `api`) e criar a rotina `qa_caso_<x>()`, caso a caso. A coluna
`sugestao_nivel` do CSV é só um filtro de partida.

### 2.3 Tempo de suíte
45 min já é longo. Somar ~300 testes sem estratégia leva a ~1h20 e ninguém espera isso.
Precisamos de **camadas**: fumaça rápida (a cada merge), completa (noturna — já agendada às 3h) e
por módulo (já possível pelo botão com seleção de módulos).

## 3. Rotas sem nenhum teste de tela

Telas que existem no app e não têm spec: `/admissao`, `/ponto-externo` (+ `/:token`),
`/ativar-conta`, `/forgot-password`, `/reset-password`, `/register`, `/completar-cadastro/:token`,
`/entrevista/:token`, `/meu-perfil`, `/meu-plano`, `/mapa-comportamental`, `/financeiro/beneficios`,
`/academia`, `/ouvidoria-externa/:token`, `/onboarding-cliente/:token`, todos os **links públicos de
assinatura** (`aceite-documento`, `assinar-contrato`, `contrato-assinatura`, `ferias-assinatura`,
`pdi-assinatura`, `experiencia-assinatura`, `manual-funcao`, `os`) e toda a área `/admin/*`
(SuperAdmin, tenants, controle de clientes).

São justamente as telas **sem login**, que o cliente final e o colaborador usam sozinhos — se
quebrarem, ninguém percebe até chegar reclamação.

## 4. O que "nunca pode parar" — Camada 0 (fumaça crítica)

Critério de entrada: **impacto** (dinheiro, prazo legal, dado sensível, acesso) × **frequência de
uso** × **dificuldade de reverter**. Cada item abaixo deve ter um teste que **executa a ação e
confere o resultado**, não só que a tela abre. Onde já existe caso `e2e`, o código vem indicado;
onde não existe, **documentar o caso antes** (regra da casa).

| # | Jornada | Casos documentados (pendentes) | Observação |
|---|---|---|---|
| 1 | **Login válido entra; logout; senha errada** | AUTH-002 | explícito, não só no `beforeEach` |
| 2 | **Recuperar senha / ativar conta** | (documentar) | `/forgot-password`, `/reset-password`, `/ativar-conta` |
| 3 | **Isolamento entre empresas**: trocar empresa troca o escopo e nada da anterior fica na tela | CTX-001, CTX-002, CTX-004 | vazamento entre clientes = risco LGPD |
| 4 | **Permissão negada de ponta a ponta**: usuário comum não vê/não acessa Configurações, Usuários, SuperAdmin | PER-003, CFG-002, CFG-012, AUTH-021, ACAD-030, OUV-030, PDI-032 | tela esconde **e** backend recusa |
| 5 | **Bater ponto** (colaborador marca; comprovante fica disponível; um colaborador não vê o do outro) | PONTO-005, PONTO-HOM-D2, PONTO-002 | `/ponto` e `/ponto-externo` |
| 6 | **Ajuste de ponto e fechamento do período** | PONTO-AJUSTE-FOLGA (já), fechamento | alimenta folha/DSR |
| 7 | **Admissão → colaborador ativo → documentos** | ADM-010, ADM-011, ADM-100, ADM-060/061/063 | cadastro rápido e completo equivalentes; ASO inapto barra |
| 8 | **Desligamento confirma, persiste e atualiza status** | DESL-100 (as regras de cálculo vão para `api`) | |
| 9 | **Atestado / declaração / afastamento** | cobertos em parte (AFAST-TELA) | manter; adicionar abono |
| 10 | **Férias: solicitar → aprovar → assinar (link público)** | (documentar assinatura) | `/ferias-assinatura/:token` |
| 11 | **Assinatura eletrônica pública** (contrato, aceite, PDI, experiência, manual) | (documentar um caso por link) | tela sem login, alto impacto jurídico |
| 12 | **Folha / Financeiro**: abrir período, calcular, tabelas, 13º | FOLHA-* (alta, 3) | 13º já coberto |
| 13 | **ASO / EPI / Ergonomia**: registrar ASO e status de vencimento; entregar EPI; risco crítico → ação | ASO-030, ERGO-014/015/020/024/030 | dado de saúde e NR |
| 14 | **Psicossocial**: questionário público responde e grava | (cobertura parcial) | `/questionario/:token` |
| 15 | **Ouvidoria**: enviar manifestação e responder | OUV-002, OUV-025 | canal legal, inclui `/ouvidoria-externa` |
| 16 | **Suporte: abrir ticket** | SUP-010 | |
| 17 | **Contrato de experiência: prorrogar, bloquear >90 dias, efetivar** | EXP-010, EXP-011, EXP-020 | prazo legal |
| 18 | **MarketYE**: cadastro do prestador, moderação, anúncio, conversa | MKY-030/040/050/070/140/141 | jornada de receita |

Meta da Camada 0: **~25 testes de ação, rodando em ≤ 10 min**, em toda publicação.

## 5. Plano em ondas

### Onda 0 — proteção (estrutura)  ·  ~1 semana  ·  **EM ANDAMENTO (21/10/2026)**
| Item | Estado |
|---|---|
| 1. Fumaça crítica rodando primeiro no job `telas` | **Feito** (a validar na 1ª corrida real). `cypress/smoke.txt` (17 specs, ~9,6 min pelas durações medidas); passo "Fumaça crítica" no `staging.yml`; a suíte completa roda em seguida mesmo se a fumaça falhar. Rodar sozinha: `npm run test:e2e:fumaca` ou `cypress.yml` com `fumaca=true`. |
| 2. Portão de publicação | **Feito, falta ligar.** `.github/workflows/gate-producao.yml` (check "Cypress verde no commit a publicar"). Só impede o merge quando o dono marcá-lo como *required* na regra da branch `producao`. Válvula: rótulo `liberar-sem-cypress`. |
| 3. Fatiar a suíte em 3 | **Ferramenta pronta, adoção pendente.** `scripts/cypress-specs.mjs --fatia N/M` + `cypress/duracoes.json` dividem os 46 specs em 3 fatias de ~14,5 min; o `cypress.yml` aceita `fatia=1/3`. **Não ativei no merge automático** porque as 3 fatias compartilhariam a mesma conta e o mesmo banco de teste; falta medir colisão de dados antes. |
| 3b. `cy.session` no login | **Não feito.** Cada um dos 44 specs tem seu próprio `login()`; trocar exige mexer em 44 arquivos e rodar o Cypress para validar. Entra como tarefa própria. |
| 4. Reclassificar ~60 casos de regra para `api` | **Não feito.** Exige decisão caso a caso (CSV `sugestao_nivel`) e criar a rotina `qa_caso_<x>()` de cada um. |

**Achado das durações (corrida de 20/10, 43 min no total):** 4 specs consomem 23 min —
`psicossocial` 8:47, `epi` 6:31, `swot` 5:11, `incidentes-acidentes` 2:46. Qualquer ganho de tempo
passa por enxugar esses quatro.

### Onda 1 — Camada 0 (jornadas críticas)  ·  ~2–3 semanas
Itens 1 a 8, 10 e 11 da seção 4 (acesso, isolamento, permissão, ponto, admissão, desligamento,
férias, assinaturas públicas). ≈ 20 testes de ação.


**Lote 1 — acesso crítico e links públicos (21/10/2026):** `cypress/e2e/acesso-critico.cy.ts` (7 testes) e
`cypress/e2e/links-publicos.cy.ts` (10 testes); casos AUTH-040, 041 e 050 a 059 documentados; pontes para
AUTH-002, 010, 011, 021 e 031. Validado na bancada (6 corridas, 17 de 17 verdes).

> **Achado de produto/ambiente — tela "Recuperar senha" não carrega na 1ª vez.** Em todas as 6
> corridas da bancada, a 1ª tentativa do teste de recuperar senha ficou em "Iniciando sistema…" (a
> tela é carregada sob demanda) por mais de 20 s — e por mais de 60 s quando o prazo foi ampliado —
> enquanto a repetição automática passa em ~2 s. Vale tanto para abertura direta de `/forgot-password`
> quanto para o clique em "Esqueceu a senha?" no login. As demais telas carregadas sob demanda
> (login, ativar conta, links públicos) não têm isso. Causa não encontrada; medido só no site de teste
> (GitHub Pages), não em produção (Vercel). Custo atual: ~21 s a mais por execução da suíte. A
> investigar com quem conhece o build: chunk da `ForgotPassword`, cache do Pages, Suspense.

### Onda 2 — regulatório e saúde  ·  ~2 semanas
Itens 9, 12 a 15, 17: Folha/Financeiro, ASO/EPI/Ergonomia, Psicossocial, Ouvidoria, Experiência.
Os 28 pendentes da Ergonomia e 40 do Desligamento são maioria `api` — só a jornada fica no tela.

### Onda 3 — receita e relacionamento  ·  ~2 semanas
MarketYE e Rede de Parceiros (34 pendentes, 10 críticos), Suporte, Academia, Onboarding.

### Onda 4 — o restante (médios/baixos)  ·  contínuo
Telas de apoio, estados vazios, filtros. Sem prazo fixo: **toda alteração nova entra com o
teste junto** (regra das três conferências) e a fila só diminui.

## 6. Regras para o teste valer

1. **Todo teste de Camada 0 confere resultado**, não só presença: após salvar, reabrir e ver o
   dado; após negar, tentar a ação direta e esperar recusa.
2. **Dado próprio e descartável** (fixtures com CPF 900.000.0XX, empresa de staging); nunca dado real.
3. **Sem `cy.wait(ms)`**; esperar elemento/rota. Flake derruba a confiança no portão.
4. **Um caso documentado ↔ um `it()`** (ponte `qa_cobertura_e2e`); título exato.
5. Teste que depende de bug de produto vai para `docs/BLOQUEIOS_PRODUTO_QA_E2E.md`, não vira
   teste vermelho nem teste que afirma menos que o caso.
6. Teste vermelho na Camada 0 **bloqueia a publicação**; nas demais, bloqueia o módulo afetado.

## 7. Como medir

| Indicador | Hoje | Meta |
|---|---|---|
| Casos críticos `e2e` com teste de ação | ~0% explícito | 100% |
| Cobertura total `e2e` | 50% (390/785) | 75% em 90 dias |
| Tempo da fumaça crítica | — | ≤ 10 min |
| Tempo da suíte completa | ~45 min | ≤ 20 min |
| Publicação em produção com Cypress verde | não exigido | sempre exigido |

Acompanhar pela própria guarda (`qa:cobertura-e2e`) e pela aba Testes Cypress do painel.

## 8. Limites desta análise

- Prioridade/módulo por caso foi lida das migrations; as contagens totais (785/390/395) vêm do
  banco ao vivo. Pode haver pequena divergência por módulo.
- "Camada 0" é uma proposta de risco; vale validar com quem opera o produto antes de fechar a lista.
- Não medi flakiness nem duração por spec; isso define o fatiamento da Onda 0.
