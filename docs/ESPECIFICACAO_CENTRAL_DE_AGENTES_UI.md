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
 ├─ Aba 5  Resultados    (/agentes/resultados) entregas medidas, horas estimadas, antes × depois (§11)
 ├─ Aba 6  Auditoria     (/agentes/auditoria)  trilha imutável, dossiê, integridade, exportação (§12; só Admin/Auditor)
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

### 2.8 Aba "Diário" (base da auditoria, ver §12)
Linha do tempo: hora · agente · ação em português · resultado (✔ enviado, ⏸ aguardando, ✖ falhou, ◌ simulado) · **Por quê?**. Filtros: agente, período, resultado, módulo. Exportar CSV (Documentos). Linhas simuladas (experiência) com selo "simulado".

### 2.9 Aba "Resultados" (detalhada em §11) e aba "Auditoria" (§12)
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

## 11. Resultados — como são medidos e apresentados

> Complementa §2.9. A aba "Resultados" deixa de ser só uma tela de números e vira um **contrato de medição**: cada número tem definição, fonte e rótulo de confiança.

### 11.1 Princípio: três camadas de resultado, rotuladas de formas diferentes
| Camada | O que é | Como se prova | Rótulo na tela |
|---|---|---|---|
| **Atividade** | O que o agente fez (lembretes enviados, minutas preparadas) | Linhas de `agente_acoes` (reais, nunca as simuladas) | "Feito" |
| **Entrega** | O **evento de sucesso** do agente, verificado no banco dentro de uma janela de atribuição após a ação dele | Evento no módulo de origem (ex.: assinatura registrada, contrato com decisão antes do D-0) | "Medido" |
| **Impacto** | Horas e R$ economizados | Cálculo: entregas × minutos por unidade × custo/hora (premissas visíveis e ajustáveis) | "Estimativa" |

Regras: só **Entrega** com evento verificável conta como resultado; Atividade sozinha nunca vira "sucesso" (evita inflar com lembretes que não mudam nada — risco de *gaming* do Discovery §7). Ação **simulada** (período de experiência) não entra em nenhuma camada; aparece à parte como "teria feito".

### 11.2 Definição por agente (ficha de medição, preenchida no catálogo `agentes_catalogo`)
| Agente | Unidade de valor | Evento de sucesso | Janela de atribuição |
|---|---|---|---|
| Bruno · Experiência | Contrato decidido no prazo | Decisão registrada antes do D-0 | Do 1º aviso até o D-0 |
| Clara · Assinaturas | Documento assinado | Assinatura registrada após lembrete | 7 dias após o lembrete **[VALIDAR]** |
| Aline · Admissão | Admissão concluída | Admissão `concluido` com checklist 100% | Da 1ª cobrança até a conclusão |
| Marta · Pessoas | Item concluído no prazo | Trilha/PDI/avaliação concluídos antes do vencimento | Do lembrete até o vencimento |
| Rui · Pendências | Pendência resolvida | Tarefa encerrada após o resumo diário | 3 dias após o resumo **[VALIDAR]** |
Os demais (Ponto, Folha, SST, Contábil) seguem o Discovery §3 e só ganham ficha quando passarem de "Em breve".

### 11.3 Indicadores da tela "Resultados"
| Indicador | Fórmula | Rótulo |
|---|---|---|
| Entregas no período | nº de eventos de sucesso atribuídos | Medido |
| Taxa de aceitação humana | aprovadas ÷ (aprovadas + recusadas), por tipo de ação | Medido |
| Tempo até a decisão | mediana entre aviso do agente e decisão humana | Medido |
| Vencimentos evitados | itens resolvidos antes do prazo após ação do agente | Medido |
| Falhas e reversões | ações com erro ou revertidas ÷ total | Medido |
| Horas economizadas | entregas × minutos/unidade ÷ 60 | **Estimativa** |
| Custo × benefício | preço do agente (+ excedente) ÷ economia estimada | **Estimativa** |
| **Antes × depois** | mesma entrega nos 30 dias **antes** da contratação (linha de base) | Medido (base) / comparação |
A **linha de base** é gravada no dia da contratação (`agentes_tenant.baseline_json`), porque só ela torna o "antes × depois" honesto.

### 11.4 Apresentação
1. **Visão geral**: 3 KPIs (entregas, aceitação humana, horas estimadas) com sparkline e comparação com o mês anterior.
2. **Resultados** (por agente e consolidado): seletor de período (mês atual, 3 meses, personalizado), barras de entregas por semana, tabela de detalhe, bloco "Antes × depois". Todo número é **clicável** e abre o Diário já filtrado nas linhas que o compõem (rastreabilidade número → evidência).
3. **Relatório mensal do agente**: gerado automaticamente no fechamento do mês (PDF em português para leitor de RH, sem dado pessoal), arquivado no módulo **Documentos** e enviado por e-mail ao decisor. Mesmo conteúdo da tela.
4. **Meu Plano**: linha "Equipe digital" ganha o resumo "X entregas este mês" ao lado do valor (liga custo a benefício no mesmo lugar).
5. **SuperAdmin**: adoção, taxa de aceitação média, custo de servir × preço, agentes com resultado fraco (insumo para promoção de nível, Discovery §6).

### 11.5 Honestidade dos números
- Período corrente rotulado "parcial"; sem dado = "—", nunca 0 enganoso; menos de 7 dias = estado vazio explicativo.
- Estimativas sempre com premissas expansíveis e botão "ajustar".
- Nenhuma correlação apresentada como causa; o texto diz "após ação do agente", não "por causa do agente".
- Sem dado individual: agregados; célula com menos de N pessoas é suprimida **[REGRA: N]** (psicossocial/ouvidoria só agregado, mínimo por GHE).
- Gráficos com tabela equivalente e cor nunca como única codificação (§4).

---

## 12. Auditoria

> A pergunta central: **"Posso provar, depois, o que o agente fez, por quê, com qual regra, quem autorizou e quanto custou?"** Sem isso o cliente não confia, o DPO não aprova e a cobrança não se sustenta. O Discovery já apontava a falta de "trilha única de ação de agente" (§1.6, §5.1); esta seção fecha a especificação.

### 12.1 Quem audita e o que cada um precisa
| Audiência | Pergunta | Acesso |
|---|---|---|
| Dono/RH-gestor | "O que o agente fez e por quê?" | Diário e Auditoria da própria empresa |
| **Auditor / DPO do cliente** (perfil novo, somente leitura) | "Há evidência, integridade e conformidade LGPD?" | Aba Auditoria + exportação assinada |
| Titular (colaborador), via RH | Informação sobre tratamento (LGPD art. 18) e **revisão de decisão automatizada** (art. 20) | RH consulta por colaborador; resposta registrada |
| SuperAdmin da casa | Suporte, incidente, cobrança contestada | Metadados cross-tenant; **conteúdo só com justificativa registrada** |

### 12.2 Três trilhas (todas append-only)
1. **Execução** — `agente_acoes`, uma linha por ação (inclusive **bloqueadas** e **simuladas**). Campos mínimos: `id`, `tenant_id` (derivado do registro do agente, nunca do input), `agente`, `agente_versao`, `regra_versao`, `nivel_vigente`, `gatilho` + `evento_origem_id`, `entidade_tipo/id`, `acao`, `resumo` (sem dado sensível; referência à entidade), `status` (feita, aguardando, recusada, falhou, **bloqueada_parada_dura**), `simulada`, `aprovador_id/aprovado_em/motivo_recusa`, `canal` + destinatário **mascarado**, `custo_tokens/custo_canal`, `sucesso_em` (evento de sucesso), `revertida_por`, `chave_idempotencia`, `criado_em` (relógio do servidor).
2. **Governança** — quem **contratou, efetivou, mudou nível, mudou regra (antes/depois), afastou, retomou, encerrou, aceitou o termo**; e, no SuperAdmin, quem **alterou preço** ou despublicou agente. Reaproveita o padrão de `entitlement_audit_log`.
3. **Acesso** — quem **consultou** o Diário/dossiê de uma entidade sensível e quem **exportou** (padrão do `log_acesso_clinico`). Consulta ao conteúdo por SuperAdmin entra aqui com a justificativa.
Cobrança tem um quarto vínculo: **conciliação diária** entre agentes ativos e o valor faturado (§12.6).

### 12.3 Integridade e imutabilidade
- Sem `UPDATE` nem `DELETE`: trigger bloqueia (como `ponto_audit_log`); correção = **nova linha** apontando a original; reversão idem (`revertida_por`).
- **Encadeamento por hash**: cada linha guarda `hash_anterior` e `hash` (SHA-256 sobre o conteúdo + hash anterior, por tenant), permitindo provar que nada foi apagado ou alterado. `digest` já tem atalho em `public` (CLAUDE.md). Função `agente_auditoria_verificar(tenant, de, ate)` devolve "cadeia íntegra" ou a primeira linha quebrada.
- Exportação **assinada** (CSV + arquivo de hashes + data/hora do servidor) guardada em Documentos. Carimbo de tempo com validade jurídica (ICP-Brasil) **[REGRA]**.
- Dados pessoais fora do `resumo`: guarda referência, não cópia; assim o expurgo de LGPD não destrói a cadeia.

### 12.4 Tela de Auditoria (nova aba "Auditoria", só perfis Administrador e Auditor)
```
┌ Auditoria ───────────────────────────────────────────────────────────────┐
│ Cadeia de registros:  ✔ Íntegra até 15/10 09:02   [Verificar agora]      │
│ Período [01/10–15/10]  Agente [Todos]  Tipo [Todos]  Status [Todos]      │
│ Buscar por colaborador/entidade: [ ................ ]  (acesso é registrado)│
├──────────┬────────┬──────────────────────────┬──────────┬───────────────┤
│ Quando   │ Agente │ Ação                     │ Status   │ Quem autorizou│
│ 15/10 08:00 │ Bruno │ Avisou gestora (7 dias)│ ✔ Feita  │ Regra v3 · auto│
│ 14/10 17:12 │ Bruno │ Minuta de prorrogação  │ ✔ Aprov. │ Ana (RH)      │
│ 14/10 09:30 │ Clara │ Reabrir link vencido   │ ⛔ Bloqueada (parada dura)│
└──────────┴────────┴──────────────────────────┴──────────┴───────────────┘
 [Exportar período (assinado)]   [Gerar relatório de auditoria]
```
**Dossiê da ação** (painel lateral ao clicar numa linha): linha do tempo *gatilho → regra aplicada (versão) → dados lidos (categorias) → decisão → quem aprovou/recusou → efeito → reversão*, mais custo e hash da linha. Botão "Ver no módulo" e "Criar ação no Plano de Ação" (regra global do YE).
**Visão por entidade**: "tudo que agentes fizeram sobre esta admissão/contrato" (resposta direta a pedido do titular).
**Reconstrução no tempo**: seletor "como estava em dd/mm" mostra o nível e a versão das regras vigentes naquela data.

### 12.5 Alertas de anomalia e "auditoria contínua"
Notificação ao administrador (e abertura no Plano de Ação) quando: pico de ações por hora acima do envelope; ação fora da janela de horário; **tentativa de parada dura bloqueada** (sempre registrada); custo acima do limite; taxa de recusa acima de meta; cadeia de hash quebrada (crítico, avisa também a casa). Esses mesmos indicadores alimentam os critérios de promoção de nível (Discovery §6).

### 12.6 Auditoria de cobrança
Tabela de conciliação diária (`agente_cobranca_dia`: tenant, agente, estado, preço vigente, motivo). Regras verificáveis: (a) nada é cobrado de agente "Em breve" ou em experiência sem decisão **[REGRA]**; (b) valor em `entitlement_my_plan` = soma dos agentes cobráveis do dia; (c) toda mudança de preço do SuperAdmin está no log e **não altera contratos vigentes**. Telas: Meu Plano mostra "histórico de cobrança dos agentes" por mês; SuperAdmin tem relatório de divergências.

### 12.7 Permissões (matriz)
| Ação | Admin | RH | Gestor | Auditor | SuperAdmin |
|---|---|---|---|---|---|
| Ver Diário da empresa | ✔ | ✔ (escopo do módulo) | só do seu time | ✔ | metadados |
| Ver aba Auditoria / dossiê | ✔ | — | — | ✔ | metadados (conteúdo com justificativa) |
| Exportar trilha assinada | ✔ | — | — | ✔ | ✔ (registrado) |
| Verificar cadeia | ✔ | — | — | ✔ | ✔ |
| Alterar/apagar registro | **ninguém** | | | | |
Consultas ao conteúdo geram linha na trilha de **Acesso**.

### 12.8 Estados da tela de Auditoria
| Estado | Mostra | Ação |
|---|---|---|
| carregando | skeleton da tabela e do selo de cadeia | — |
| vazio | "Nenhuma ação registrada neste período. Agentes em experiência aparecem como simulados." | alterar período |
| erro | "Não foi possível carregar a trilha." | tentar de novo |
| **cadeia quebrada** | faixa crítica "Inconsistência detectada na linha X" | contatar suporte, exportar evidência |
| exportando | progresso e `aria-live` | cancelar |
| sem permissão | "Você não tem acesso à auditoria" + a quem pedir | — |
| parcial | resultados paginados com aviso "mostrando 50 de N" | carregar mais |

### 12.9 Viabilidade e back **[BACK]**
- Tabelas: `agente_acoes`, `agente_governanca_log`, `agente_acesso_log`, `agente_cobranca_dia`, `agente_resultados_dia` (pré-agregado). Criar por `EXECUTE 'CREATE ' || 'TABLE'` no script de entrega (auto-RLS do SQL Editor, CLAUDE.md); RLS por `get_user_tenant_id()` + política `RESTRICTIVE perfil_restringe_leitura_*` (rotina PERFIL-003 cobra).
- RPCs: `agente_auditoria_listar`, `agente_dossie`, `agente_auditoria_verificar`, `agente_auditoria_exportar`, `agentes_resultados`, `agente_baseline_gravar`.
- Performance: índice `(tenant_id, criado_em desc)`; paginação por cursor; verificação de cadeia em lote por período (não ao vivo na tela inteira); `agente_resultados_dia` alimentada por job diário (padrão pg_cron + `app_config`).
- Retenção/expurgo: o job `central-expurgo-eventos` é precedente; política de prazo é **[REGRA]**. Expurgo nunca quebra a cadeia (guarda hash, remove referência pessoal).
- Depende da **Onda 0** do Discovery: sem `agente_acoes` não há Diário, Resultados nem Auditoria; a Vitrine pode sair antes, a cobrança de agente real não.

### 12.10 Critérios de aceite adicionais
- **CA-UX-027** Todo número da aba Resultados abre o Diário filtrado nas linhas que o compõem.
- **CA-UX-028** Cada indicador exibe o rótulo "Feito", "Medido" ou "Estimativa"; estimativa mostra premissas e permite ajustar.
- **CA-UX-029** Ação simulada nunca soma em Entregas nem em Horas economizadas.
- **CA-UX-030** A linha de base é gravada na contratação e o "antes × depois" a usa.
- **CA-UX-031** O relatório mensal é arquivado em Documentos, sem dado pessoal identificável.
- **CA-UX-032** Não existe edição nem exclusão de registro de auditoria em nenhuma tela ou RPC; correção cria nova linha.
- **CA-UX-033** O selo "Cadeia íntegra" reflete `agente_auditoria_verificar`; adulterar uma linha em teste muda o selo para "quebrada" e destaca a linha.
- **CA-UX-034** Ação bloqueada por parada dura aparece na Auditoria com status próprio.
- **CA-UX-035** O dossiê da ação mostra gatilho, versão da regra, categorias de dado, decisão, aprovador, efeito e custo.
- **CA-UX-036** A busca por colaborador gera registro na trilha de Acesso.
- **CA-UX-037** A exportação é assinada (arquivo + hashes) e fica em Documentos.
- **CA-UX-038** O perfil Auditor vê a trilha, mas não contrata, aprova nem altera regras.
- **CA-UX-039** SuperAdmin só vê metadados de outro tenant; abrir conteúdo exige justificativa registrada.
- **CA-UX-040** Anomalias (pico, fora do horário, bloqueio, custo, cadeia quebrada) notificam o administrador e oferecem "Criar ação no Plano de Ação".
- **CA-UX-041** O valor cobrado no mês = soma dos agentes cobráveis conciliados por dia; divergência aparece no relatório do SuperAdmin.
- **CA-UX-042** Alterar preço no SuperAdmin deixa linha na governança e não muda contratos vigentes.
- **CA-UX-043** Tenant A nunca enxerga trilha, resultados ou cobrança do tenant B (família `ISOL-*`).
- **CA-UX-044** Toda tabela e gráfico das abas Resultados e Auditoria tem equivalente textual e navegação por teclado.

**QA adicional (3 conferências):** casos `api` propostos `AGENTES-006` imutabilidade (UPDATE/DELETE falham), `-007` cadeia de hash detecta adulteração, `-008` simulada não conta como entrega, `-009` bloqueio de parada dura é registrado, `-010` conciliação de cobrança bate com `entitlement_my_plan`, `-011` isolamento da trilha entre tenants; `e2e` para Resultados → Diário → Dossiê e exportação. Rotinas `qa_caso_agentes_*()` e `it()` só depois dos casos documentados.

**Dúvidas novas [REGRA]:** prazo de retenção da trilha; se agentes de nível B/C configuram **decisão automatizada** (LGPD art. 20) e como o titular pede revisão; valor jurídico exigido da assinatura/carimbo; se existe hoje um perfil "Auditor" (o `perfis_acesso` é configurável, **[VERIFICAR]**); se o cliente pode pedir exportação completa ao encerrar o contrato; limite mínimo N de supressão de células.

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
10. **Falta algo?** Não especifiquei o **onboarding da primeira visita** (tour da Íris), o **e-mail da Reunião diária** nem a **versão do SuperAdmin para ver a Central "como cliente"** (suporte). O protótipo navegável cobre só Vitrine, Times e Ficha; Resultados e Auditoria estão apenas em texto e wireframe. Pergunta adicionada pelo dono: os resultados e a auditoria **não estavam** tratados como requisito próprio na primeira versão; as §11 e §12 corrigem isso, mas dependem de `agente_acoes`, que não existe.
