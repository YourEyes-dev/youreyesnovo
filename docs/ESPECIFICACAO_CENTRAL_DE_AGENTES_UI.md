# Especificação de interface — Central de Agentes Autônomos (menu "Equipe Digital")

Data: 15/10/2026 · Autor: agente Analista de Requisitos (Front-end, UX e Desenvolvimento) · Status: **proposta para aprovação humana (Leiri)** · Insumos: `docs/DISCOVERY_CAMADA_AGENTES.md` + leitura do código atual (`MeuPlano.tsx`, `PrecosAddonsPanel.tsx`, `AppSidebar.tsx`, migrations `20260902220000_entitlements_motor`, `20260903140000_addon_prices`, `20260903150000_addon_contratacao`).

Legenda: **[VALIDAR]** suposição minha · **[BACK]** exige trabalho de banco/RPC que não existe · **[REGRA]** devolvido ao analista/jurídico/dono do produto.

---

## 0. Entendimento inicial

**Requisito.** Uma tela que apresenta os agentes autônomos como **funcionários digitais contratáveis**. Contratar = **add-on** somado ao valor mensal da empresa. Preço visível em três lugares: Central de Agentes, **SuperAdmin → Preços** (edição) e **Meu Plano** (resumo + contratação). A tela vira **item de menu**.

**Usuários.**
| Perfil | Quer |
|---|---|
| Dono/Diretor/RH-gestor (decide a compra) | Entender o que ganha, quanto custa, ter segurança de que nada irreversível acontece |
| RH operacional (convive com o agente) | Ver o que o agente fez, aprovar o que ele propõe, ajustar regras |
| Superadmin da casa | Precificar, publicar/despublicar agentes, ver adoção |

**Outcome (JTBD).** "Quando tenho tarefas repetitivas de RH/SST que sempre atrasam, quero contratar um colega digital que cuide delas sem me fazer perder o controle, para eu só decidir o que importa."

**Descoberta que muda o desenho (achado no código).** Já existe motor de add-on: `addon_prices` (preço por `feature_key`), `subscription_addons` (`kind in ('module','life')`), RPCs `my_contratar_addon` / `my_cancelar_addon` / `entitlement_my_plan`, painel `PrecosAddonsPanel` em `/admin/precos` e bloco "Contratar (R$/mês)" em `/meu-plano`. **Agente entra como um novo `kind = 'agent'` no mesmo motor** — nada de cobrança paralela. É a escolha de menor risco (premissa 1 do CLAUDE.md: não quebrar o que funciona).

**Premissas.**
1. Fixo mensal por agente na 1ª entrega (cabe no motor atual); cobrança por resultado/ação só depois da trilha `agente_acoes` existir (Discovery §4/§5.1) **[REGRA]**.
2. Todo agente nasce em **modo sombra** (propõe, não age) — Discovery §5.9. A UI transforma isso em metáfora de **período de experiência** (ver §1.3).
3. Os 9 agentes do Discovery §3 são o catálogo inicial; nomes de persona são sugestão **[VALIDAR]**.

**Dúvidas que voltam ao analista/jurídico/dono do produto → ver §10.**

---

## 1. Fluxo e arquitetura da informação

### 1.1 Ideia-mestra (UX simples sobre regra complexa)
A complexidade (níveis A/B/C, paradas duras, envelope, outbox, custo de IA) fica no motor. A pessoa só vê **uma metáfora RH que ela já domina**:

| Conceito técnico | Metáfora na tela |
|---|---|
| Catálogo de agentes | **Vitrine de talentos** |
| `add-on` + entitlement | **Contratar** (valor mensal sobe) |
| Modo sombra (nível A) | **Período de experiência** — "o Bruno observa por 14 dias e mostra o que *teria* feito" |
| Nível B (age com aprovação) | **"Faz e pede seu OK"** |
| Nível C (autônomo em limites) | **"Cuida sozinho dentro das regras"** |
| Paradas duras | **"O que ele nunca faz"** (lista fixa, não editável, sempre visível) |
| Kill switch | **Afastar** (pausa imediata, 1 clique, reversível) |
| `agente_acoes` | **Diário de bordo** (feed legível, com "por quê?") |
| Evento de sucesso | **Entregas** ("12 contratos decididos no prazo") |

### 1.2 Mapa de telas
```
Menu lateral ▸ "Equipe Digital" (/agentes)                  ← NOVO
 ├─ Aba 1  Visão geral   (/agentes)            Íris + equipe + o que precisa de você + economia
 ├─ Aba 2  Vitrine       (/agentes/vitrine)    contratar: cards dos agentes + "Times" (bundles)
 │    └─ Ficha do agente (Sheet lateral)       atribuições, nunca faz, preço, simulador, [Contratar]
 │         └─ Confirmar contratação (Dialog)   impacto no valor mensal antes → depois
 ├─ Aba 3  Aprovações    (/agentes/aprovacoes) caixa de entrada "aguardando seu OK" (nível B)
 ├─ Aba 4  Diário        (/agentes/diario)     trilha de ações, filtro por agente/empresa/resultado
 ├─ Aba 5  Resultados    (/agentes/resultados) entregas, horas economizadas, custo × benefício
 └─ Perfil do agente     (/agentes/:codigo)    cabeçalho + Regras (envelope) + Diário + Resultados daquele agente

Meu Plano (/meu-plano)        ← ALTERADO: card "Equipe digital" (contratados + valor) → link p/ Central; contratar via MESMA Ficha
SuperAdmin ▸ Preços (/admin/precos) ← ALTERADO: nova seção "Agentes" (preço, publicação, times)
SuperAdmin ▸ Agentes (/admin/agentes) ← NOVO: catálogo (persona, textos, nível máx., status Em breve/Disponível/Oculto) + adoção
```

### 1.3 Jornada principal (compra → confiança → autonomia)
1. **Descoberta** — Íris, no topo, diz algo baseado nos dados da empresa: *"Você tem 7 contratos de experiência vencendo em 30 dias. O Bruno cuida disso."* → [Ver o Bruno].
2. **Avaliação** — Ficha: o que faz, **o que nunca faz**, canais que usa, preço, **simulador de economia** com os números da própria empresa.
3. **Contratação** — Diálogo de confirmação mostra **valor mensal antes → depois**, aceite do termo e início em **período de experiência (14 dias [VALIDAR])**, sem ação real.
4. **Experiência** — Aba Visão geral mostra o agente "em experiência" e o painel **"O que ele teria feito"** (ações simuladas). Nada sai para colaborador.
5. **Efetivação** — Ao fim, Íris pergunta: *"Efetivar o Bruno?"* → escolhe nível (*Sugere / Faz e pede OK / Cuida sozinho*). Subir de nível exige confirmação explícita; descer é imediato.
6. **Rotina** — Aprovações, Diário, Resultados. **Afastar** a qualquer momento.

Cancelar: Ficha → "Encerrar contrato" → mostra quando o valor deixa de ser cobrado (fim do ciclo vigente **[REGRA]**).

### 1.4 Onde a inovação (IA-first) entra
| Recurso | O que é | Custo de construção |
|---|---|---|
| **Íris recomenda** | Faixa no topo com 1–3 recomendações ancoradas em dados reais do tenant (contagens por RPC, sem LLM) | Baixo ([BACK] RPC de contagens) |
| **Pergunte à Íris** | Campo de comando (⌘K reaproveitando `command.tsx`): "quem cuida dos ASOs?", "o que o Bruno fez ontem?" — responde com card/link, não texto livre longo | Médio (depende do gateway de IA, Discovery §5.6) — **fase 2** |
| **Simulador de economia** | Slider "admissões/mês" pré-preenchido com o dado real da empresa × minutos economizados × custo/hora → "≈ 14 h/mês" | Baixo; premissas de minutos vêm do Discovery §2 e são **[VALIDAR]** |
| **Período de experiência com "teria feito"** | Prova de valor *antes* de agir de verdade | Médio ([BACK] modo sombra grava ação simulada) |
| **Por quê?** em toda ação | Painel: gatilho → regra aplicada (versão) → dado usado → resultado | Médio ([BACK] campos da trilha) |
| **Organograma da equipe** | Íris no topo, agentes abaixo, ligados aos módulos que atendem; clicar filtra o Diário | Baixo |
| **Reunião diária** | Resumo de 1 minuto (o que fizeram, o que precisa de você) no topo da Visão geral e opcional por e-mail | Médio |
| **Times (bundles)** | "Admissão & Contrato", "Ponto & Folha", "SST Vigilante", "Pessoas", "Contábil" (Discovery §4) com preço fechado | Baixo na UI; preço **[REGRA]** |

---

## 2. Especificação por tela

### 2.1 Item de menu (AppSidebar)
- Título **"Equipe Digital"**, ícone `Bot` (lucide) com selo `Sparkles`; posição: logo abaixo de "Plano de Ação/Pendências" **[VALIDAR]**.
- **Selo numérico** = nº de aprovações pendentes (some se 0). Selo `Lock` se o plano não incluir `mod.agentes` (padrão `usePlanLock`) — clicar leva à Vitrine em modo vitrine pública (permitido ver e contratar).
- Rota registrada em `moduleAccess.ts` com módulo `agentes` (controle por perfil, igual aos demais).

### 2.2 Aba "Visão geral" (`/agentes`)
```
┌───────────────────────────────────────────────────────────────────────────────┐
│ Equipe Digital                                   [ 🔍 Pergunte à Íris… ⌘K ]   │
├───────────────────────────────────────────────────────────────────────────────┤
│ (Íris)  "Bom dia, Ana. 3 coisas esperam seu OK e o Bruno viu 7 contratos      │
│          vencendo em 30 dias."                       [Ver aprovações] [Vitrine]│
├──────────────────────────────┬────────────────────────────────────────────────┤
│ SUA EQUIPE (3)               │ ESTE MÊS                                       │
│ ┌──────────┐ ┌──────────┐    │  38 entregas · ≈ 21 h economizadas             │
│ │ Bruno    │ │ Clara    │    │  Custo da equipe digital: R$ xxx/mês           │
│ │ Experiên.│ │ Assinat. │    │  ▁▂▃▅▆ (sparkline entregas/semana)             │
│ │ ● Ativo  │ │ ◐ Experi.│    ├────────────────────────────────────────────────┤
│ │ 2 p/ OK  │ │ dia 6/14 │    │ AGUARDANDO VOCÊ (3)                            │
│ └──────────┘ └──────────┘    │  • Bruno: prorrogar contrato de J.S.? [Abrir]  │
│ ┌ + Contratar novo agente ┐  │  • …                                           │
│ └─────────────────────────┘  │                                                │
├──────────────────────────────┴────────────────────────────────────────────────┤
│ ÚLTIMAS ATIVIDADES  (Diário — 5 linhas)                      [Ver diário →]   │
└───────────────────────────────────────────────────────────────────────────────┘
```
Componentes: `IrisBriefing` (novo), `AgenteCardEquipe` (novo), `KpiTile` (novo, sobre `Card`), `ListaAprovacoesResumo` (novo), `DiarioLinha` (novo).

### 2.3 Aba "Vitrine" (`/agentes/vitrine`)
- Topo: filtro por **necessidade** (Pessoas · Ponto & Folha · SST · Documentos · Contábil) + busca; alternância **Agentes | Times**.
- Grade de `AgenteCardVitrine` (3 col desktop · 2 tablet · 1 mobile):
```
┌─────────────────────────────────────┐
│  [avatar ilustrado]    ⓘ Agente de IA│  ← selo fixo "Agente de IA" (transparência)
│  Bruno                              │
│  Agente de Experiência              │
│  "Nenhum contrato vence sem decisão"│  ← resultado que possui (Discovery §3)
│  ✔ Vigia 45/90 dias  ✔ Prepara a    │
│    decisão  ✔ Cobra o gestor        │
│  Nível máx.: Faz e pede seu OK      │
│  ─────────────────────────────────  │
│  R$ XX/mês            [ Conhecer ]  │  ← preço sempre visível no card
│  Estado: Disponível│Em breve│Contratado│
└─────────────────────────────────────┘
```
- **Times**: card maior com os agentes componentes, preço de pacote e **"economize R$ X"** vs. soma avulsa **[REGRA: desconto]**.

### 2.4 Ficha do agente (Sheet lateral direita, 560 px; tela cheia no mobile)
Seções em acordeão (revelação progressiva; só "O que faz" e "Preço" abertas):
1. **Cabeçalho** — avatar, nome, cargo, selo "Agente de IA", estado.
2. **O que faz** — 3–5 atribuições em linguagem de RH (não técnica).
3. **O que ele NUNCA faz** — bloco destacado (ícone `ShieldCheck`), lista fixa vinda do catálogo (paradas duras). *Ex.: "Nunca encerra ou efetiva contrato sozinho."*
4. **Como trabalha** — nível de autonomia disponível (3 degraus visuais), canais (e-mail/WhatsApp), horário padrão.
5. **Dados que usa** — módulos e categorias de dado (transparência LGPD); para saúde: aviso reforçado **[REGRA/jurídico]**.
6. **Quanto você ganha** — `SimuladorEconomia`: 1 slider pré-preenchido com dado real; resultado em horas e em R$; rótulo "estimativa" com premissa expansível.
7. **Preço** — valor mensal, o que está incluso (franquia, se houver) e o excedente **[REGRA]**.
8. **Rodapé fixo** — `[Contratar por R$ XX/mês]` · "14 dias de experiência, sem ações reais".

### 2.5 Diálogo de confirmação ("Contrato de trabalho")
- Linha de **antes → depois**: `Plano Essential R$ 1.200 + add-ons R$ 150 = R$ 1.350` → `+ Bruno R$ XX = R$ 1.4xx /mês` (usa `valores` já devolvido por `entitlement_my_plan`).
- Quando a cobrança começa (início do período de experiência ou da efetivação **[REGRA]**) e quando renova.
- Checkbox de aceite do termo de uso de agentes (reutilizar fluxo `ContratosAceite` **[VALIDAR]**).
- `[Confirmar contratação]` / `[Voltar]`. Sucesso → toast + redireciona ao **Perfil do agente** com a faixa "Em experiência".

### 2.6 Perfil do agente (`/agentes/:codigo`)
Cabeçalho (avatar, status, ações `Afastar` / `Efetivar` / `Encerrar contrato`) + abas internas: **Regras** (envelope: prazos de alerta 15/7/2 dias, janela de horário, canais, quem recebe — controles com padrão sensato; "Restaurar padrão"), **Diário** e **Entregas** (filtrados). Mudanças de regra mostram prévia "isto altera X" e ficam versionadas (Discovery §5.7).

### 2.7 Aba "Aprovações"
Lista priorizada por prazo. Cada item: agente, ação proposta em uma frase, **por quê?** (expansível), entidade alvo (link), prazo. Ações: `Aprovar`, `Recusar` (com motivo opcional), `Abrir detalhe`. Aprovação em lote só para itens do mesmo tipo e **risco baixo**. Itens que exigem parada dura nunca aparecem como "aprovar", só como "Abrir no módulo" (humano executa).

### 2.8 Aba "Diário"
Linha do tempo: hora · agente · ação em português · resultado (✔ enviado, ⏸ aguardando, ✖ falhou, ◌ simulado) · **Por quê?**. Filtros: agente, período, resultado, módulo. Exportar CSV (Documentos). Linhas simuladas (experiência) com selo "simulado".

### 2.9 Aba "Resultados"
KPIs por agente com a **unidade de valor** do Discovery §3 (ex.: "Contratos decididos no prazo"), comparativo mês a mês, horas economizadas (estimativa rotulada), custo × benefício. Sem ranking entre pessoas; nada que identifique colaborador.

### 2.10 Meu Plano (`/meu-plano`) — alteração
Novo card **"Equipe digital"** entre "Módulos" e o rodapé:
- Lista de agentes contratados: nome, estado, valor/mês, `Encerrar`.
- Linha **"Equipe digital: R$ XX/mês"** somada em `valores.addons_cents` e no **total** (o breakdown atual já existe — acrescentar a linha).
- Seção "Disponíveis para contratar" com cards compactos (nome + preço + `Conhecer`) — **abre a mesma Ficha** (componente `AgenteFichaSheet` compartilhado; não duplicar fluxo).
- Texto do rodapé atual ("Módulos e vidas extras…") passa a citar agentes.

### 2.11 SuperAdmin → Preços (`/admin/precos`) — alteração
Nova seção **"Agentes"** no `PrecosAddonsPanel` (mesmo padrão `PrecoInput` por linha, mesmo botão Salvar):
| Coluna | Controle |
|---|---|
| Agente (nome + persona) | texto |
| Preço mensal (R$) | `PrecoInput` |
| Franquia incluída / excedente | **[REGRA]** colunas ocultas na 1ª entrega |
| Visibilidade na Vitrine | switch (publicado/oculto) |
| Estado | select Em breve / Disponível |
Seção **"Times"**: preço de pacote e agentes componentes. Aviso fixo: "Alterar preço não muda contratos vigentes" **[REGRA: política de reajuste]**.

### 2.12 SuperAdmin → Agentes (`/admin/agentes`) — novo
Catálogo editável (persona, avatar, textos, atribuições, **paradas duras**, nível máx., estado), **adoção por empresa** (quem contratou, em experiência × efetivado, kill switch global) e custo de IA/canal por agente quando a telemetria existir. Despublicar um agente exige confirmação digitando o nome.

---

## 3. Matriz de estados

### 3.1 Cartão de agente (Vitrine e Meu Plano)
| Estado | Mostra | Usuário pode | Mensagem |
|---|---|---|---|
| default | avatar, resultado, preço | Conhecer | — |
| hover/foco | elevação + anel de foco 2 px | Enter/clique abre Ficha | — |
| carregando | `Skeleton` do card | — | — |
| **Em breve** | selo "Em breve", sem preço firme | **Avisar-me** (registra interesse) | "Avisamos quando o Bruno estiver disponível." |
| **Disponível** | preço + Conhecer | Conhecer / Contratar | — |
| **Em experiência** | selo "Dia X/14" | Ver "teria feito", Efetivar, Encerrar | "Ele só observa; nada é enviado a ninguém." |
| **Contratado/ativo** | selo ● Ativo + nível | Abrir perfil, Afastar | — |
| **Afastado (pausado)** | selo ⏸, esmaecido | Retomar | "Pausado por você em dd/mm. Nenhuma ação está sendo feita." |
| **Falha** | selo ⚠ | Ver detalhe, Falar com suporte | "Houve um problema e ele parou por segurança." |
| **Sem permissão** | botões desabilitados + tooltip | Ver apenas | "Só administradores podem contratar." |
| **Plano suspenso** (`past_due/paused/canceled`) | contratar desabilitado | Ir a Meu Plano | "Regularize o plano para contratar." |
| offline | último dado + banner | Reler | "Sem conexão." |

### 3.2 Telas
| Tela | carregando | vazio | erro | sucesso | sem permissão | parcial |
|---|---|---|---|---|---|---|
| Visão geral | Skeletons por bloco (não bloqueia a página) | **Sem equipe:** Íris convida + 3 recomendações + [Vitrine] | Bloco com "Tentar de novo" (não derruba os outros) | — | Somente leitura se perfil sem `agentes` de escrita | KPIs sem dado de custo → "—" com tooltip |
| Vitrine | 6 skeletons | "Nenhum agente nesta categoria" + limpar filtro | "Não foi possível carregar a vitrine" + retry | — | Visível; Contratar desabilitado | Alguns "Em breve" |
| Ficha | Skeleton das seções | — | "Não foi possível carregar" | — | Contratar oculto | Simulador sem dado real → campos manuais |
| Confirmação | Botão com spinner | — | Erro do RPC em texto claro (ex.: "Plano já inclui este agente") e botão reativado | Toast + redireciona | Bloqueado antes de abrir | — |
| Aprovações | Skeleton linhas | "Nada esperando você 🎉" | Retry | Toast "Registrado" + item sai com `aria-live` | Sem botões de decidir | — |
| Diário | Skeleton | "Sem atividade ainda. Em experiência, as ações aparecem como simuladas." | Retry | — | Filtrado por perfil/escopo | Linhas sem "por quê" → "—" |
| Resultados | Skeleton | "Ainda sem dados (precisa de 7 dias)" | Retry | — | Oculta custo se perfil sem financeiro | Mês corrente rotulado "parcial" |
| SuperAdmin Preços | Skeleton | "Nenhum agente cadastrado" | Erro por linha | Toast "Preço salvo" | Redireciona (não superadmin) | Linha com preço 0 = "sob consulta" |

---

## 4. Acessibilidade (WCAG 2.2 AA) — critérios de aceite
- Contraste texto ≥ 4,5:1 e componentes/ícones ≥ 3:1, **verificado por par de token** nos temas claro/escuro; selos de estado **nunca só por cor** (ícone + texto).
- Alvos ≥ 24×24 px (meta 44 px em mobile); foco visível ≥ 2 px e **não obscurecido** pelo Sheet fixo/rodapé de contratação (`scroll-padding`).
- Teclado: grade de cards navegável por Tab; Enter/Espaço abre a Ficha; `Esc` fecha Sheet/Dialog devolvendo o foco ao cartão de origem; ⌘K abre "Pergunte à Íris".
- ARIA: Sheet/Dialog com `role` e título; abas com `tablist/tab/tabpanel`; selo de aprovações com `aria-label="3 aprovações pendentes"`; resultado de aprovar/contratar em `aria-live="polite"`; erros ligados ao campo por `aria-describedby`.
- Avatares ilustrados com `alt` descritivo; decorativos `alt=""`. Gráficos (sparkline) com tabela/resumo textual equivalente.
- Animações (entrada de cards, Íris) respeitam `prefers-reduced-motion`.
- Preço lido por leitor de tela como "R$ 150,00 por mês".
- Nenhuma ação depende de arrastar ou de gesto complexo (WCAG 2.5.7).

---

## 5. Responsividade e tokens
**Breakpoints (Tailwind do projeto):** `<640` 1 coluna, Ficha em tela cheia, abas viram `Select`; `640–1023` 2 colunas; `≥1024` 3 colunas + painel lateral "Aguardando você" fixo na Visão geral; `≥1536` até 4 colunas.

**Tokens (3 camadas).** Primitivos existentes (Tailwind/shadcn) → semânticos novos → componente:
| Semântico (novo) | Uso |
|---|---|
| `--agente-surface`, `--agente-border` | fundo/borda do cartão |
| `--agente-estado-ativo / experiencia / pausado / falha / embreve` | selos (cada um com variante claro/escuro/alto contraste) |
| `--agente-economia` | destaque positivo (horas/R$ economizados) |
| `--agente-nunca` | bloco "O que ele nunca faz" (tom de segurança, não de erro) |
| Espaçamento 4/8/16/24; raio `--radius`; sombra `elevation-1/2` | todos |
Cada agente tem **matiz de acento** próprio (só decoração; informação nunca depende dela).

**Componentes shadcn reaproveitados:** `Card`, `Badge`, `Button`, `Sheet`, `Dialog/AlertDialog` (`confirm-dialog`), `Tabs`, `Accordion`, `Progress`, `Skeleton`, `Tooltip`, `Switch`, `Slider`, `Select`, `Command` (⌘K), `Table`, `sonner`. **Novos:** `IrisBriefing`, `AgenteCardVitrine`, `AgenteCardEquipe`, `AgenteFichaSheet`, `NivelAutonomiaSelector` (3 degraus), `SimuladorEconomia`, `DiarioLinha`, `PorQuePopover`, `AprovacaoItem`, `KpiTile`, `OrganogramaEquipe`.

---

## 6. Viabilidade técnica

### 6.1 O que reaproveita (existe hoje)
- Preço/contratação/valor mensal: `addon_prices`, `subscription_addons`, `my_contratar_addon`, `my_cancelar_addon`, `entitlement_my_plan` (já devolve `precos`, `addons`, `valores`), `superadmin_set_addon_price`, `usePrecosAddons`, `useMeuPlano`.
- Entitlement por módulo: `features`/`plan_entitlements`, `usePlanLock`, `useTenantFeatures`.
- Fila de trabalho: `plano_acao_abrir()` (idempotente) para o que o humano deve executar.

### 6.2 O que NÃO existe e precisa de back **[BACK]**
| Necessidade | Proposta | Fase |
|---|---|---|
| Agente como item de add-on | Ampliar `CHECK (kind in ('module','life'))` para incluir `'agent'`; `features` com `key = 'agente.<codigo>'`, `kind='boolean'`, `category='agentes'`; `addon_prices` já serve | 1 |
| `my_contratar_addon` hoje deduz `kind` só por `limit.vidas` | Ajustar `v_kind` para reconhecer `agente.%`; exigir papel de administrador do tenant (**[VERIFICAR]** se a RPC atual já valida papel) | 1 |
| Catálogo (persona, atribuições, paradas duras, nível máx., estado) | Tabela `agentes_catalogo` (global) — criação por `EXECUTE 'CREATE ' \|\| 'TABLE'` no script de entrega (pegadinha do auto-RLS, CLAUDE.md) | 1 |
| Registro por tenant (estado, nível, envelope, experiência até, kill switch) | `agentes_tenant` + RLS por `get_user_tenant_id()` | 1 |
| Aprovações, Diário, Resultados | `agente_acoes` (imutável) + `agente_eventos` (outbox) — Discovery §5.1/§5.4; RPCs `agentes_aprovacoes_listar`, `agente_decidir`, `agentes_diario_listar`, `agentes_resultados` | 2 |
| Recomendações da Íris | RPC `agentes_recomendacoes()` com contagens (contratos vencendo, documentos pendentes…) respeitando RLS/perfil | 1 |
| Cobrança por resultado/excedente | Depende de telemetria e `usage_counters` | 3 |
| "Pergunte à Íris" | Gateway de IA com `entitlement_can_use` e log de custo — Discovery §5.6 | 3 |

### 6.3 Ponto crítico de honestidade comercial
**A Central pode ser construída antes dos agentes, mas não deve cobrar por um agente que ainda não age.** Recomendação: Fase 1 publica a Vitrine com estado **"Em breve" + Avisar-me**; `Contratar` só habilita por agente quando o estado do catálogo for **Disponível** (feature flag por agente em `agentes_catalogo.estado`). Os agentes reais dependem da Onda 0 do Discovery (trilha, registro, identidade, kill switch, correções de segurança §1.8).

### 6.4 Performance
Visão geral = 1 RPC agregada (`agentes_visao_geral`) + cache TanStack Query (`staleTime` 60 s, como `useMeuPlano`); Diário paginado por cursor (50/linha-de-tempo); Resultados pré-agregados por dia (não somar `agente_acoes` ao vivo); contagem do selo do menu via `useQuery` leve com `refetchInterval` de 5 min (sem Realtime na 1ª fase).

### 6.5 Permissões e multi-tenant
Tenant sempre derivado de `get_user_tenant_id()`, nunca do parâmetro. Ver a Central: módulo `agentes` por perfil (`perfil_permite_modulo`). **Contratar/Encerrar/Efetivar/Afastar:** administrador do tenant **[VALIDAR papel]**. **Aprovar:** quem tem permissão no módulo de origem (agente de ASO → só quem vê SST). Nas tabelas novas sensíveis (`agente_acoes`, `agentes_tenant`) criar política RESTRICTIVE `perfil_restringe_leitura_*` (a rotina PERFIL-003 cobra). Agentes **não aparecem** com dado identificável de psicossocial/ouvidoria (só agregados).

---

## 7. Contrato de handoff (resumo executável)
- **Rotas:** `/agentes`, `/agentes/vitrine`, `/agentes/aprovacoes`, `/agentes/diario`, `/agentes/resultados`, `/agentes/:codigo`, `/admin/agentes`; alteração em `/meu-plano` e `/admin/precos` (rota existente `PrecosAddonsPanel`).
- **Arquivos prováveis:** `src/pages/agentes/*`, `src/components/agentes/*`, `src/hooks/useAgentes.ts`, ajuste em `AppSidebar.tsx`, `lib/moduleAccess.ts`, `MeuPlano.tsx`, `PrecosAddonsPanel.tsx`, `usePrecosAddons.ts`, `useMeuPlano.ts` (tipo `kind: 'module'|'life'|'quota'|'agent'`).
- **Feature flags:** `mod.agentes` (menu) e `agentes_catalogo.estado` por agente (Em breve/Disponível/Oculto).
- **Validações/mensagens:** contratar agente já incluído → "Este agente já faz parte do seu plano."; plano `past_due/paused/canceled` → bloquear; valor sempre em centavos no banco, `centsToReais` na tela (padrão existente); confirmação obrigatória antes de contratar/encerrar; subir nível exige confirmação, descer não.
- **Latência:** ações de contratar < 2 s com spinner; listas com skeleton; erro de rede = banner + retry, nunca tela branca.
- **Entrega de banco:** migration + `docs/script_*.sql` conforme CLAUDE.md (idempotente, uma conferência `SELECT` final, tabelas por `EXECUTE`, sem `SELECT INTO`).
- **QA (3 conferências, antes de fechar a entrega):** (1) mapa de impacto: `MeuPlano`, `PrecosAddonsPanel`, `entitlement_my_plan` (soma de valores), `AppSidebar`, `moduleAccess`; (2) casos propostos em `qa_casos_teste`: `AGENTES-001` (preço do agente igual na Vitrine, Meu Plano e SuperAdmin), `-002` (contratar soma exatamente `unit_price` em `valores.addons_cents`), `-003` (isolamento: tenant A não vê agentes/ações do B — família `ISOL-*`), `-004` (agente "Em breve" não contrata), `-005` (perfil sem permissão não contrata) — nível `api`; `-101…` e2e para fluxo Vitrine → Ficha → Confirmar; (3) rotinas `qa_caso_agentes_*()` e `cypress/e2e/agentes.cy.ts` + ponte `qa_cobertura_e2e`, **só após os casos e2e estarem documentados**.

---

## 8. Automação / redução de trabalho
- Dado cadastrado **uma vez**: a Ficha puxa contagens reais do tenant (nada de digitar "quantas admissões você faz").
- Contratar em **1 fluxo** (Ficha → Confirmar), igual em Central e Meu Plano; sem formulário comercial nem contato com suporte.
- Aprovação em lote para itens de risco baixo; regras com padrões sensatos (zero configuração obrigatória).
- Regras globais do YE: todo alerta/ação de agente tem **"Analisar com IA"** e **"Criar ação no Plano de Ação"**; documentos gerados vão ao módulo Documentos.
- Estimativa: elimina a etapa "ligar para vender/ativar add-on" e a conferência manual de preço entre telas (fonte única `addon_prices`).

---

## 9. Critérios de aceite de UX (testáveis)
- **CA-UX-001** O item "Equipe Digital" aparece no menu para perfis com o módulo; some para quem não tem.
- **CA-UX-002** O selo do menu mostra o nº de aprovações pendentes e desaparece com 0.
- **CA-UX-003** Cada card exibe nome, cargo, resultado, selo "Agente de IA" e preço **sem abrir a Ficha**.
- **CA-UX-004** Agente "Em breve" não possui botão Contratar; possui "Avisar-me".
- **CA-UX-005** A Ficha mostra, sem rolagem horizontal, "O que faz", "O que NUNCA faz" e Preço.
- **CA-UX-006** "O que NUNCA faz" é idêntico ao do catálogo e não é editável pelo cliente.
- **CA-UX-007** O preço do mesmo agente é **idêntico** na Vitrine, na Ficha, em Meu Plano e no SuperAdmin.
- **CA-UX-008** A confirmação mostra valor mensal antes e depois; o "depois" = "antes" + preço do agente.
- **CA-UX-009** Após contratar, `/meu-plano` lista o agente e o total mensal já atualizado, sem recarregar a página.
- **CA-UX-010** Contratar duas vezes o mesmo agente é impedido com mensagem clara.
- **CA-UX-011** Usuário sem permissão vê tudo, mas Contratar/Afastar/Efetivar ficam desabilitados com tooltip explicativo.
- **CA-UX-012** Plano `past_due/paused/canceled` bloqueia contratação e indica o caminho.
- **CA-UX-013** Em experiência, nenhuma ação sai para colaborador; o Diário marca tudo como "simulado".
- **CA-UX-014** "Afastar" pausa em ≤ 1 clique + confirmação, e o Diário registra quem e quando.
- **CA-UX-015** Subir nível de autonomia exige confirmação; descer é imediato.
- **CA-UX-016** Toda linha do Diário e toda aprovação tem "Por quê?" abrindo gatilho, regra e dado usado.
- **CA-UX-017** Aprovar/Recusar atualiza a lista e anuncia o resultado a leitor de tela (`aria-live`).
- **CA-UX-018** Toda tela tem estados carregando, vazio, erro e sem permissão conforme §3.
- **CA-UX-019** Contraste ≥ 4,5:1 (texto) / 3:1 (UI) nos temas claro e escuro; estados não dependem só de cor.
- **CA-UX-020** Fluxo completo Vitrine → Contratar executável só por teclado; foco devolvido ao cartão ao fechar Sheet/Dialog.
- **CA-UX-021** Em 360 px de largura: sem rolagem horizontal; Ficha em tela cheia; alvos ≥ 44 px.
- **CA-UX-022** SuperAdmin altera preço, salva, e a mudança aparece nas telas do cliente na próxima leitura; contratos vigentes **não** mudam de valor.
- **CA-UX-023** Usuário não-superadmin não acessa `/admin/precos` nem `/admin/agentes`.
- **CA-UX-024** Tenant A nunca vê agentes, ações ou valores do tenant B (teste de isolamento).
- **CA-UX-025** Nenhuma tela de agente exibe nome/CPF/atestado reais de colaborador em texto de exemplo, KPI ou export de psicossocial/ouvidoria (só agregados).
- **CA-UX-026** `prefers-reduced-motion` desliga as animações da Íris e dos cards.

---

## 10. Dúvidas e riscos

### Voltam ao analista / jurídico / dono do produto **[REGRA]**
1. **Modelo de cobrança da Fase 1:** fixo mensal por agente (cabe no motor) vs. híbrido/resultado (exige telemetria). Recomendo fixo + franquia agora.
2. **Quando começa a cobrança:** na contratação, no fim da experiência ou na efetivação? E o **pró-rata** e o **ciclo de cancelamento**.
3. **Duração e cobrança do período de experiência** (14 dias sem custo? só cobrança do plano?).
4. **Descontos de Times** e política de **reajuste** de preço sobre contratos vigentes.
5. **Termo de uso/aceite** específico de agentes (responsabilidade, limites, subprocessadores de IA) e **DPA/base legal** para agente que toque dado de saúde (Discovery §7) — bloqueia o Agente de SST/Atestados na vitrine.
6. **Quem pode contratar** (papel mínimo) e se o contratante precisa ser distinto de quem aprova.
7. **Antropomorfização:** nomes próprios e avatares ajudam a venda, mas pode induzir a crer que são pessoas. Mitigação adotada: selo fixo "Agente de IA". Confirmar com o dono do produto/jurídico.
8. **WhatsApp não oficial** (WhatsAPI): vender agente que depende dele cria risco de banimento (Discovery §7). A Ficha deve informar o canal real.
9. Existe integração **Faciliti**? (Discovery pendência) — afeta o texto da Ficha.

### Riscos de usabilidade / implementação
- **Vender antes de entregar** (§6.3) — o maior risco; mitigado por estado "Em breve" por agente.
- **Preço dessincronizado** entre três telas — mitigado por fonte única `addon_prices` e CA-UX-007 (teste QA).
- **Excesso de metáfora** pode esconder o que é de fato (software). Mitigação: selo "Agente de IA" + "O que ele nunca faz" + Diário auditável.
- **Fadiga de aprovação** (nível B): se o agente pedir demais, o cliente aprova no automático; medir taxa de aprovação e usar lote só para baixo risco.
- **Estimativas de economia** são premissas minhas **[VALIDAR]**; rotular como estimativa e permitir ajustar.
- Homologação não exercita vigilâncias (Discovery §1.3) — QA do agente deve rodar no **teste**, não na homologação.
- Mudança de `CHECK (kind …)` em tabela com dados: fazer por `DROP CONSTRAINT IF EXISTS` + `ADD CONSTRAINT` em bloco `DO` com `EXCEPTION`, com `lock_timeout`.

---

## Avaliação crítica do agente (10 perguntas)
1. **Especifiquei todos os estados?** Cartão e as 8 telas têm carregando/vazio/erro/sucesso/sem permissão; falta detalhar offline por tela e o estado "plano sem o módulo `agentes`" na navegação — deixei como regra única, não por tela.
2. **Acessibilidade nos tokens e nos critérios?** Sim (§4, §5, CA-UX-019/020/021/026), mas não calculei os pares de contraste reais dos tokens novos — isso é tarefa de implementação com validador.
3. **A tela reflete permissões/RLS?** Sim em §6.5, porém **não conferi** o código de `my_contratar_addon` para saber se ele já valida papel de administrador — está como [VERIFICAR].
4. **Escondi a complexidade?** Níveis A/B/C viraram 3 degraus em linguagem de RH; risco: a palavra "efetivar" pode confundir com efetivar *colaborador* — testar com usuários.
5. **Construível na stack como especifiquei?** Fase 1 sim (reutiliza o motor de add-on). Diário, Aprovações, "Pergunte à Íris" e cobrança por resultado **dependem de back inexistente** e estão marcados por fase.
6. **Decidi regra de negócio?** Evitei: preços, desconto, pró-rata, termo e papéis ficaram em §10. Escolhi 14 dias de experiência e o fixo mensal como *sugestões* [VALIDAR].
7. **O que assumi sem validar?** Nomes das personas, posição no menu, minutos economizados por tarefa, 14 dias, que `Bot` do lucide combina com a identidade, que a identidade Íris/tokens permite os acentos por agente.
8. **A inovação é real ou enfeite?** Os diferenciais com valor comprovável são: experiência com "teria feito", "por quê?" e simulador com dado real. "Pergunte à Íris" e organograma são desejáveis, mas não essenciais à 1ª entrega.
9. **Reaproveitei antes de criar?** Sim (add-on, `PrecosAddonsPanel`, `Meu Plano`, `Command`, `Sheet`), mas li só os trechos citados; pode haver componentes de card/KPI já existentes que não vi.
10. **Falta algo?** Não especifiquei o **onboarding da primeira visita** (tour da Íris), o **e-mail da Reunião diária** nem a **versão do SuperAdmin para ver a Central "como cliente"** (suporte). Também não há protótipo navegável — apenas wireframes.
