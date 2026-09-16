# Planejamento — Portal do Parceiro e Gestão de Carteira

Documento de planejamento (não é implementação). Nasce da análise do mockup
`youreyes_portal_parceiro_mockup.html` cruzada com o sistema que já existe no
repositório. O desenvolvimento acontecerá no ambiente de desenvolvimento-teste
(projeto Supabase de staging + site https://ustudy123.github.io/youreyesnovo/teste/);
a produção não é tocada por nada deste plano até aprovação explícita.

---

## 1. O que o mockup pede

Uma tela **do parceiro** (clínica de SST, contador, consultor) que enxerga só a
própria carteira de clientes YourEyes e o que ganha com ela.

| Bloco do mockup | O que mostra | Dado necessário |
|---|---|---|
| Cabeçalho | Nome do parceiro, região, "parceiro desde", **Trilha** (ex.: Operador) e **Nível** (ex.: Visão), barra de evolução até o próximo nível (R$ MRR sob atendimento × meta) | cadastro do parceiro, trilha, nível, tabela de níveis/metas |
| 5 KPIs | MRR sob atendimento (com variação vs mês anterior), comissão do mês (% e data de fechamento), ganho acumulado, clientes ativos (+ em implantação), conversão lead → ativo | MRR por cliente, histórico mensal, comissões, funil |
| Link de afiliado | Link principal `?ref=CODIGO`, links por campanha `?ref=CODIGO-PGR`, cliques e leads por link, botão copiar e "gerar novo link" | tabela de links/campanhas, contagem de cliques, leads atribuídos |
| Funil 90 dias | Leads → Propostas → Contratos → Ativos, com taxas | estágio de cada conta originada, com datas |
| Gráfico 12 meses | Evolução do MRR sob atendimento, linha da meta do próximo nível | snapshot mensal do MRR por parceiro |
| Carteira | Empresa, Plano, MRR, Estágio (Lead, Proposta, Implantação, Go-live, Ativo, Churn), próximo passo/ciclo, comissão/mês, botão Exportar | ligação tenant ↔ parceiro, plano/assinatura, estágio derivado, ciclo contratual |
| Extrato de ganhos | Competência, base líquida, %, valor, status (Previsto, Pago, Retido); "fecha dia 25, paga até dia 10" | tabela de comissões por competência com fechamento mensal |
| Próximas renovações | Data de renovação do ciclo e bônus (2× a comissão) | fim do ciclo contratual por cliente, regra de bônus |

---

## 2. O que já existe no sistema e como se liga (elos e interferências)

### 2.1 Camada comercial — há DOIS conceitos de assinatura convivendo

| Estrutura | O que é | Uso no portal |
|---|---|---|
| `plans`, `plan_prices`, `plan_entitlements` (motor de entitlements, 09/2026) | Catálogo: starter R$ 197, essential R$ 397, performance R$ 797, governanca R$ 1.797, mais planos internos (`tester`). Preço mensal de tabela em `plan_prices.amount_cents` | **Fonte da verdade do plano e do preço de tabela** |
| `subscriptions` (1 por tenant) | `plan_id`, `status` (trialing, active, past_due, paused, canceled), período **mensal**, `payment_confirmed` (toggle manual, sem gateway). `superadmin_set_tenant_plan` troca o plano | **Fonte da verdade do estágio Ativo/Churn** e do MRR de tabela |
| `subscription_addons` | Módulos e vidas extras com preço congelado | Entra no MRR do cliente |
| `assinaturas` (Mercado Pago, 07/2026) | Pedido de checkout: `plano_id` texto, `ciclo` (mensal/trimestral/semestral/anual), `preco_mensal` **já com desconto**, `meses`, `payer_email`, `payment_id`. O webhook provisiona tenant + `programa_validador_clientes` e envia e-mail de ativação | Traz o **valor efetivamente pago** e o **ciclo contratado** — não existe em `subscriptions` |
| `tenants.plano` (enum legado `tenant_plan`: free, starter, professional, enterprise) | Coluna antiga, ainda gravada pelo onboarding e pelo webhook | **Não usar**: diverge do catálogo novo (não tem essential/performance/governanca) |
| `Site.tsx` (rota `/`, página pública) | Lista de planos e preços **hardcoded** (base 197/397/797/1797, descontos por ciclo: −10%, −50% lançamento, −40%) | Fonte do checkout; risco de divergir de `plan_prices` |

**Interferência 1 — "base líquida" da comissão.** O mockup calcula comissão sobre
o MRR (R$ 797 → R$ 199 a 25%). Mas o cliente que pagou o semestral de lançamento
paga metade disso. Precisa de decisão: comissão sobre preço de tabela
(`plan_prices` + add-ons) ou sobre valor pago (`assinaturas.preco_mensal`). O
plano prevê guardar os dois no fechamento e parametrizar qual vale.

**Interferência 2 — ciclo de renovação.** `subscriptions` só tem período mensal;
"renova ciclo em 12/03/2027" e "inicia ciclo 24m" não existem hoje. O ciclo vive
em `assinaturas.meses` (quando a conta veio do checkout) ou em lugar nenhum
(conta criada pelo SuperAdmin). Proposta: acrescentar `ciclo_meses`,
`ciclo_inicio` e `ciclo_fim` em `subscriptions`, preenchidos pelo webhook e
editáveis na tela `/admin/tenants/:id/assinatura`.

### 2.2 Leads e funil

| Estrutura | O que é | Uso no portal |
|---|---|---|
| `landing_leads` | Formulário público da landing (`/lp`), com diagnóstico. Insert liberado para `anon`. **Não guarda `ref`/UTM** | Precisa de coluna `ref_codigo` + captura do `?ref=` na página |
| `leads` (CRM do SuperAdmin, aba "Leads CRM" em Kanban) | `status` novo → contatado → qualificado → proposta → negociacao → convertido / perdido; `origem` já tem `'indicacao'`; `tenant_convertido_id`; `landing_lead_id` | Estágios **Lead** e **Proposta** da carteira vêm daqui. Falta `parceiro_id` e `parceiro_link_id` |
| `programa_validador_clientes` + `programa_validador_contratos` | Cadastro comercial do cliente (fase, `valor_mensal`, `tipo_cliente`, `dia_vencimento`, conta ativada, token de onboarding) e contrato assinado eletronicamente (pendente/enviado/assinado/recusado) | Estágios **Contrato** e **Implantação/Go-live**: contrato assinado + onboarding concluído |
| `profiles.onboarding_concluido` | Marca fim do onboarding do cliente | Critério de Go-live |

**Interferência 3 — o estágio da carteira é derivado de 4 tabelas.** Ninguém
guarda "estágio" hoje. Proposta: uma view/função `parceiro_estagio_tenant()`
com precedência clara (Churn > Ativo > Go-live > Implantação > Contrato >
Proposta > Lead) e critérios documentados nos casos de QA. Isso evita criar uma
segunda máquina de estados que brigue com o Kanban de leads.

### 2.3 Marketplace e Parceiros são a MESMA pessoa em dois papéis

O Marketplace (`/marketplace`) é a vitrine onde profissionais (médicos do
trabalho, técnicos de SST, psicólogos, contadores...) ofertam serviços para
todos os clientes YourEyes — modelo iFood/Mercado Livre de serviços. Hoje:

- `marketplace_profissionais` guarda o profissional (registro no conselho, UF,
  especialidades, cidade/estado, status pendente → ativo, `plano` base |
  profissional | **parceiro** — o valor já existe no enum) e já traz
  `codigo_afiliado`/`link_afiliado`, sem regra por trás.
- O cadastro (`ProfissionalFormModal`) aceita `user_id` nulo: o profissional
  pode se cadastrar **sem ser usuário de nenhum tenant**. Isso é exatamente a
  brecha de identidade que o parceiro precisa.
- A aba "Afiliados" e `marketplace_afiliados_comissoes` são um esboço: sem
  captura de `ref`, sem fechamento, sem níveis. A aba também mistura funções
  internas (Validação, Denúncias) com a vitrine.
- `usuario_tipo = 'clinica_parceira'` é outra coisa: usuário dentro de um
  tenant cliente. Não reaproveitar.

**Decisão de produto (03/09/2026):** o link de afiliado sai do Marketplace. No
lugar, um botão/convite "Quero ser parceiro YourEyes" leva o profissional para
a **Área do Parceiro**, fora do sistema. Todo profissional do Marketplace pode
virar parceiro (indicador, representante, implantador); e todo parceiro pode,
se quiser, ter vitrine no Marketplace. Uma identidade, dois papéis:

```
              pessoa (auth.users)  ── e-mail/senha ou link mágico, sem tenant
                     │
        ┌────────────┴─────────────┐
 marketplace_profissionais      parceiros  (via parceiro_usuarios.user_id)
 (vitrine: oferta de serviços)  (indicação: link, carteira, comissão)
        └────────────┬─────────────┘
              região de atuação compartilhada (cidade/UF)
```

Efeitos práticos: o parceiro que indica um cliente na própria região é também o
profissional que a casa pode sugerir para atender aquele cliente
(Marketplace); o profissional bem avaliado na vitrine ganha selo na Área do
Parceiro. Isso é o "fomentar o trabalho deles na região" pedido pelo dono.

### 2.4 Acesso — a Área do Parceiro fica FORA do sistema, entrando pelo site

Confirmado o caminho sugerido pelo dono do produto: o parceiro **não** entra no
YourEyes (menu, tenant, módulos). Ele entra por uma seção própria do site.

Por que isso encaixa bem no que existe:

- `profiles.tenant_id` é `NOT NULL` e `ProtectedRoute` expulsa quem não tem
  perfil de tenant. Parceiro sem tenant nunca passaria por ali — e não precisa.
- Já existe precedente de páginas do mesmo app fora do layout do sistema
  (`/site`, `/lp`, `/marketplace`, `/onboarding-cliente/:token`, assinaturas por
  token). A Área do Parceiro segue esse padrão: mesmo código, mesmo Supabase
  Auth, layout leve próprio, sem sidebar.
- Um único login (Supabase Auth) evita segunda base de senhas. Quem é parceiro
  E usuário de um tenant usa o mesmo e-mail: após o login, o app decide o
  destino — tem vínculo em `parceiro_usuarios` e não tem profile → `/parceiro`;
  tem os dois → entra no sistema com atalho "Área do Parceiro" no menu do
  usuário.

Estrutura proposta no site (`youreyes.com.br`):

| Rota | O que é | Quem acessa |
|---|---|---|
| `/parceiros` | Seção pública "Parceiros": proposta (trilhas, níveis, comissão), depoimentos, botão **Quero ser parceiro** | qualquer visitante; link no cabeçalho do site ao lado de Planos/Contato e no rodapé |
| `/parceiros/cadastro` | Formulário: pessoa/empresa, CPF/CNPJ, região de atuação (cidade/UF), tipo (indicador, representante, implantador, clínica, contabilidade), aceite dos termos do programa; cria a conta Auth e o `parceiros` em status `pendente` | visitante |
| `/parceiros/entrar` | Login do parceiro (e-mail/senha ou link mágico), reaproveitando `Login.tsx` com tema do site | parceiro |
| `/parceiro` | Portal (o mockup): cabeçalho, KPIs, link, funil, carteira, extrato, renovações | parceiro aprovado (`ParceiroRoute`) |
| `/parceiro/perfil` | Dados, região, dados bancários/PIX para pagamento, **"Também quero ofertar serviços no Marketplace"** (cria/liga `marketplace_profissionais`) | parceiro |
| `/marketplace` (existente) | Vitrine. A aba Afiliados sai; entra um cartão "Já é profissional? Vire parceiro YourEyes" → `/parceiros` | clientes e profissionais |

Aprovação: o SuperAdmin aprova o cadastro (status `pendente` → `ativo`) na aba
Parceiros; a Onda 1 pode nascer com aprovação automática para indicador e
manual para representante/implantador (decisão em aberto).

Alternativa descartada: criar um tenant "casca" por parceiro (poluiria a lista
de empresas, o motor de entitlements e as estatísticas). Também descartado
subdomínio separado (`parceiros.youreyes.com.br`) nesta fase: mesmo app e mesmo
build simplificam a esteira de staging; pode virar subdomínio depois só com
configuração de DNS.

### 2.5 SuperAdmin

`SuperAdminDashboard.tsx` já tem abas Visão Geral, Empresas, Usuários, Leads CRM,
Landing, Psicossocial, Situação, Preços. Entra a aba **Parceiros** (cadastro,
trilhas/níveis, vínculo manual tenant ↔ parceiro, fechamento e pagamento de
comissões). `TenantDetalhe`/`TenantAssinatura` ganham o campo "Parceiro de
origem" e o ciclo contratual. `LeadsCRMKanban` ganha o campo "Parceiro".

### 2.6 Pontos de captura da origem (`?ref=`)

1. `Site.tsx` (rota `/`) e `LandingPage.tsx` (`/lp`): ler `?ref=` na chegada e
   guardar em `localStorage` por 90 dias (janela de atribuição, a confirmar).
2. Insert em `landing_leads`: enviar `ref_codigo`.
3. `mercadopago-checkout`: enviar `ref_codigo` em `metadata`; gravar em
   `assinaturas.ref_codigo`.
4. `mercadopago-webhook` e `onboarding-signup`: ao criar o tenant, resolver
   `ref_codigo` → `parceiro_links` → gravar `tenants.parceiro_id`,
   `tenants.parceiro_link_id`, `tenants.originado_em`.
5. Conversão de lead no CRM (`tenant_convertido_id`): herdar o parceiro do lead.
6. Contagem de cliques: função pública `parceiro_registrar_clique(codigo)`
   chamada pela landing (sem dado pessoal: só código, data e hash do user-agent).

Observação de ambiente: o link do parceiro é montado com `VITE_APP_URL`, que no
site de teste é `https://ustudy123.github.io/youreyesnovo/teste/`. Em produção
será o domínio real. Nunca hardcode.

### 2.7 Segurança e LGPD

- O parceiro vê **apenas**: nome fantasia do cliente, plano, MRR, estágio, datas
  contratuais e a própria comissão. **Nunca** colaboradores, atestados,
  psicossocial ou qualquer dado de pessoa física. Isso se garante por RPCs
  `SECURITY DEFINER` que devolvem colunas fechadas, não por leitura direta das
  tabelas de tenant.
- Tabelas novas de parceiro têm RLS: leitura pelo próprio parceiro (via
  `parceiro_usuarios`) e superadmin; escrita só superadmin/robô.
- Não cadastrar as tabelas de parceiro em `entitlement_gated_tables` (elas não
  são módulos de tenant). Se a rotina de QA PERFIL-003 acusar "tabela sensível
  sem política de perfil", documentar a exceção dentro da rotina, como manda o
  CLAUDE.md, porque `perfil_permite_modulo` é por tenant e aqui não há tenant.
- `superadmin_delete_tenant` e `tenant_spinoffs`: chaves para parceiro em
  `tenants` com `ON DELETE SET NULL`; spin-off **não** herda parceiro
  automaticamente (decisão a confirmar).

---

## 3. Modelo de dados proposto

```
parceiros                 id, codigo (único, ex.: CLINICAVIDA), nome, tipo_pessoa, documento,
                          tipo_parceiro (indicador|representante|implantador|clinica|contabilidade),
                          cidade, uf, cep, lat, lng, raio_atuacao_km, trilha, nivel_id,
                          percentual_comissao (override opcional), status
                          (pendente|ativo|suspenso|encerrado), aprovacao (automatica|manual),
                          parceiro_desde, contato_*,
                          pix_chave (dado de pagamento, só superadmin lê),
                          marketplace_profissional_id (opcional, FK), aceite_termos_em, created_at
parceiro_niveis           id, trilha, nome (Visão, Diamante...), ordem, mrr_minimo_cents,
                          percentual_comissao, bonus_renovacao_multiplicador
parceiro_usuarios         parceiro_id, user_id, papel (dono|leitura), UNIQUE(user_id)
parceiro_links            id, parceiro_id, codigo (único, ex.: CLINICAVIDA-PGR),
                          campanha, ativo, created_at
parceiro_link_cliques     link_id, clicado_em, ua_hash          -- sem IP, sem pessoa
tenants                   + parceiro_id, parceiro_link_id, originado_em   (SET NULL)
leads                     + parceiro_id, parceiro_link_id, atribuicao (link|casa),
                          + implantador_parceiro_id (quem faz o setup, pode diferir do indicador)
tenants                   + implantador_parceiro_id
landing_leads             + ref_codigo
assinaturas               + ref_codigo
subscriptions             + ciclo_meses, ciclo_inicio, ciclo_fim
parceiro_mrr_snapshots    parceiro_id, competencia (date, dia 1), tenant_id,
                          mrr_tabela_cents, mrr_pago_cents, addons_cents   -- gráfico 12m
parceiro_eventos_remuneracao  id, trilha, tipo_parceiro, evento
                          (setup_concluido|go_live|renovacao), valor_fixo_cents,
                          percentual_primeira_mensalidade, ativo   -- editável pelo SuperAdmin
parceiro_comissoes        id, parceiro_id, tenant_id, competencia, tipo
                          (recorrente|bonus_renovacao|evento|ajuste), evento, base_cents, percentual,
                          valor_cents, status (previsto|fechado|pago|retido),
                          fechado_em, pago_em, observacao
```

Funções (todas `SECURITY DEFINER`, com checagem de vínculo/superadmin):

- `parceiro_meu_painel()` → cabeçalho + KPIs + progresso de nível.
- `parceiro_minha_carteira()` → linhas da tabela, com estágio derivado.
- `parceiro_meu_funil(dias)` e `parceiro_meu_extrato()` e
  `parceiro_minhas_renovacoes()`.
- `parceiro_registrar_clique(codigo)` (pública, `anon`, com limite por hora).
- `parceiro_fechar_competencia(competencia)` → gera `parceiro_comissoes`
  previsto → fechado no dia 25 (pg_cron; sem `app_config` preenchido não roda,
  seguindo a proteção de ambiente já existente).
- `superadmin_parceiros_*` (listar, criar, vincular tenant, marcar pago/retido).
- Recalcular nível: ao fechar a competência, se MRR ≥ `mrr_minimo` do próximo
  nível, promove (rebaixamento: decisão em aberto).

Estágio derivado (precedência):

| Estágio | Critério |
|---|---|
| Churn | `subscriptions.status = 'canceled'` ou tenant inativo |
| Ativo | `subscriptions.status = 'active'` e Go-live há mais de 30 dias |
| Go-live | contrato assinado **e** `profiles.onboarding_concluido` do owner, nos últimos 30 dias |
| Implantação | tenant existe, contrato assinado, onboarding não concluído (mostrar % de colaboradores cadastrados vs `quantidade_colaboradores`) |
| Contrato | `programa_validador_contratos.status = 'assinado'` sem tenant ativo ainda |
| Proposta | `leads.status IN ('proposta','negociacao')` ou contrato `enviado` |
| Lead | `leads` ou `landing_leads` com o parceiro e sem tenant |

Comissão só sobre planos `is_public = true`: tenant em `tester` ou plano interno
rende zero e aparece na carteira com aviso.

### 3.1 Sugestão de parceiro por proximidade (leads da casa)

Objetivo: fomentar o parceiro na região dele. Quando um lead entra **sem**
`ref` (landing, prospecção direta), o CRM sugere quem pode atender.

- Cadastro do parceiro guarda `cidade`, `uf`, `cep` e `raio_atuacao_km`; a
  migration geocodifica por **CEP → latitude/longitude** usando a tabela de
  municípios/CEPs já disponível (ou preenche `lat/lng` via Edge Function na
  aprovação; sem chave externa no código, config em `app_config`).
- Lead e `empresa_cadastro` também guardam CEP/cidade; distância calculada em
  SQL com a fórmula de Haversine (sem PostGIS, para não adicionar extensão).
- Função `parceiros_sugerir_para_lead(lead_id)` devolve até 5 parceiros ativos
  ordenados por: mesma cidade → dentro do raio → mesma UF; desempate por nível
  e nota no Marketplace. O SuperAdmin escolhe um no Kanban ("Encaminhar ao
  parceiro"), o que grava `leads.parceiro_id` com `atribuicao = 'casa'`
  (diferente de `'link'`) e notifica o parceiro (e-mail via `send-email-resend`).
- Aba Parceiros ganha um **mapa/lista por região** (parceiros por UF/cidade,
  leads sem parceiro na região) para orientar recrutamento onde falta cobertura.
- A comissão de um lead atribuído pela casa pode ter percentual distinto do
  lead originado por link (campo em `parceiro_niveis`: `percentual_link`,
  `percentual_casa`). Decisão de valores fica com o dono do produto.

---

### 3.2 Contrato de Parceria — onde se amarra

Decisão (03/09/2026): o contrato se amarra **no cadastro**. Ninguém vira
parceiro sem aceitar a versão vigente do Contrato de Parceria Comercial
(clickwrap), e o aceite fica registrado com versão, hash do texto, data,
usuário, IP e navegador (`parceiro_contratos_aceites`). O texto vive em
`parceiro_contratos_versoes` (só o SuperAdmin publica, via
`superadmin_parceiro_contrato_publicar`), é público em `/parceiros/contrato`
e consolida a Política de Parceiros: modalidades e aprovação, atribuição
(link 90 dias / casa), remuneração (níveis, base de tabela, fechamento 25 e
pagamento 10, bônus, setup), obrigações, **confidencialidade e segredos
comerciais** (5 anos; segredos enquanto durarem), **não concorrência e não
aliciamento** (12 meses após o fim, limitado ao uso de informações e
relacionamentos da parceria), marca, LGPD, vigência e rescisão. Versão nova
pede aceite de novo: o portal mostra o aviso, o SuperAdmin vê a pendência e,
após 60 dias, a parceria pode ser suspensa. Os Termos de Uso ganharam as
cláusulas 5.1 (confidencialidade e segredos) e 5.2 (Programa de Parceiros).
**Revisão jurídica recomendada** antes de aplicar em produção; o texto muda
sem nova publicação de tela, só publicando outra versão na tabela.

**Atualização (03/09/2026, pedido do dono do produto): o clickwrap deixou de
bastar.** O aceite marcado no cadastro só manifesta a intenção
(`parceiros.aceite_termos_em`). O contrato é **gerado por parceiro**
(`parceiro_contrato_render_abnt`): qualificação das duas partes (YourEyes de
`youreyes_empresa`, parceiro do cadastro), corpo v2 com a matriz vigente, fecho
e campos de assinatura, tudo no **padrão ABNT** (fonte serifada 12 pt,
entrelinha 1,5, justificado, recuo de parágrafo, margens 3 cm/2 cm em A4,
títulos numerados). Esse HTML fica em `contratos_assinaturas.html_assinado`
como registro **pendente** (token, 30 dias) do modelo categoria "parceria" da
tela SuperAdmin › Contratos, que agora exige CPF, telefone, endereço, selfie e
geolocalização. O parceiro assina em `/assinar-contrato/:token` — o MESMO fluxo
dos contratos existentes: assinatura manuscrita em tela, selfie ao vivo, IP,
navegador, coordenadas, data/hora e hash SHA-256 (Lei 14.063/2020, art. 4º, II;
MP 2.200-2/2001, art. 10, § 2º). Só quando `registrar_assinatura_contrato`
conclui é que `parceiro_contratos_aceites` ganha a versão e a pendência sai do
portal (`parceiro_contrato_situacao` devolve `assinatura_token` enquanto
pendente e `assinatura_id` depois). O cadastro (Edge Function e RPC) devolve o
token e a tela leva direto à assinatura. Caso QA: PGP-016 (api).

### 3.3 Aprovação em duas travas e portas de entrada (11/09/2026)

Decisão do dono do produto: Representante e Operador não podem operar antes
da aprovação. Implementado como duas travas em sequência: (1) **aprovação da
casa** (`parceiros.status` pendente → ativo, em SuperAdmin › Parceiros, com
Aprovar/Recusar e e-mail ao parceiro via `send-email-resend`, modelo
genérico); (2) **contrato assinado** (a assinatura pendente só é gerada por
`parceiro_contrato_iniciar_assinatura_para` quando o status é ativo, e a
aprovação em `superadmin_parceiro_status` já a gera). Enquanto pendente, o
portal mostra só a tela "Cadastro em análise"; enquanto o contrato não é
assinado, o bloco de links fica travado. Indicador continua automático.
`parceiro_meu_portal_com_contrato` passa a devolver `situacao` (status,
motivo, datas) e `contrato.aguardando_aprovacao`.

Indicação no site: `parceiro_ref_publico(codigo)` devolve nome/cidade do
parceiro ativo; o site mostra a faixa "Você foi indicado por X" e rola até os
planos quando o link traz `#planos`. O painel oferece dois links: apresentação
(`/?ref=`) e contratar (`/?ref=...#planos`).

Porta livre de cadastro de empresa (tela de login → /register, criava empresa
sem plano e sem pagamento) fechada por padrão pela chave
`app_config.cadastro_empresa_livre` ('nao'), lida por
`cadastro_empresa_livre_ativo()` na tela e pela Edge Function
`onboarding-signup` (recusa criar tenant, exceto chamada com chave de
serviço). `cadastro_empresa_trial_dias` fica reservada para o período de
teste (guardada, sem efeito no motor). SuperAdmin › Dados da YourEyes ›
Portas de entrada edita as duas. Caso QA: PGP-017 (api).

## 4. Decisões que precisam do dono do produto antes da Onda 1

1. **Trilhas e níveis**: quais trilhas existem (o mockup cita "Operador"), quais
   níveis (Visão, Diamante...), faixa de MRR e percentual de cada um (mockup:
   25% no nível Visão, 30% em Diamante a partir de R$ 12.000).
2. **Base da comissão**: preço de tabela ou valor efetivamente pago (com
   descontos de ciclo)? Add-ons entram? Inadimplência (`past_due`) vira
   "Retido"?
3. **Calendário**: fechamento dia 25 e pagamento até dia 10 — confirmar; e o que
   acontece com competência parcial (cliente que ativa dia 20).
4. **Bônus de renovação 2×**: sobre a comissão do mês da renovação; vale para
   renovação automática ou só para novo ciclo assinado?
5. **Atribuição**: primeiro clique vence? janela de 90 dias? conflito entre
   `ref` e prospecção direta da casa; lead já existente no CRM chega por link.
6. **Rebaixamento de nível** quando o MRR cai; spin-off herda parceiro?
7. **Parceiro-cliente**: a clínica que é cliente e parceira ganha comissão sobre
   a própria assinatura? (proposta: não).
8. ~~Marketplace~~ **Decidido (03/09/2026): sim.** Migrar os registros de
   `marketplace_afiliados_comissoes` para `parceiro_comissoes` (tipo `ajuste`,
   status conforme o original) e apagar a aba Afiliados na Onda 2.
9. ~~Aprovação~~ **Decidido: automática para indicador; manual (SuperAdmin) para
   representante, implantador, clínica e contabilidade.** Documentos exigidos
   ficam em aberto (proposta: CNPJ para pessoa jurídica; conselho só para quem
   também entra no Marketplace, onde já é obrigatório).
10. ~~Tipos~~ **Decidido: o implantador ganha também pelo setup, com valor
    configurável.** Modelo: tabela `parceiro_eventos_remuneracao` (por trilha e
    tipo de parceiro: evento `setup_concluido`, `go_live`, `renovacao`; valor
    fixo em centavos OU percentual da primeira mensalidade; ativo). O SuperAdmin
    edita na aba Parceiros. O fechamento gera `parceiro_comissoes.tipo =
    'evento'` quando o critério do evento ocorre (setup = onboarding concluído
    pelo cliente atendido por aquele implantador). O que representante pode
    fazer além de indicar segue em aberto.
11. ~~Região~~ **Decidido: leads que chegam pela casa (landing, prospecção)
    recebem sugestão de representante/parceiro por localidade e proximidade.**
    Ver seção 3.1.

Sem essas respostas, a Onda 1 entra com valores parametrizados em
`parceiro_niveis` (editáveis pelo SuperAdmin) e os do mockup como semente.

---

## 4.1 Política v2 (03/09/2026) — o que os anexos mudaram

Os documentos "Programa de Parceiros YourEyes" (jul/2026) e a apresentação aos
parceiros substituem várias decisões provisórias das Ondas 1-3:

- **Trilhas** Indicador / Representante / Operador; o "tipo" (clínica,
  contabilidade, consultoria…) vira perfil e sugere a trilha. Matriz de níveis
  Foco (até R$ 4 mil) / Visão (R$ 4-12 mil) / Diamante (> R$ 12 mil):
  6/8/10 %, 12/15/18 %, 20/25/30 %; participação no setup 20/25/30, 60/70/80,
  100 % (Operador fatura direto). Tudo em `parceiro_niveis`, pré-preenchido.
- **Base** = mensalidade efetivamente recebida (assinatura paga), líquida de
  impostos (parâmetro) e do desconto concedido (`subscriptions.desconto_pct`).
- **Ciclos de 24 meses** contados do go-live homologado, renovação automática
  com bônus 2×; compromisso da casa limitado ao ciclo em curso (o fechamento
  devolve `compromisso_ciclo_cents`).
- **Setup** pago pelo cliente e repassado em 3 parcelas (30/40/30) contra 1ª
  mensalidade, go-live homologado e 3ª mensalidade; bônus de retenção 90 dias
  (+15 %); Fast Start, volume e velocidade; retenção de qualidade do Operador
  (20 % por 3 meses); clawback 50 % entre o 4º e o 12º mês; inadimplência
  retém. Marcos registrados pelo SuperAdmin em Empresas › Assinatura.
- **43 parâmetros** em `parceiro_programa_config` (editáveis em Parceiros ›
  Níveis e remuneração); o motor e o contrato leem de lá.
- **Titularidade**: cláusula 2 do contrato v2 — a carteira é da YourEyes; o
  parceiro tem o registro de originação e a garantia de não abordagem direta.
  Não aliciamento e não concorrência por **24 meses**, confidencialidade 5 anos,
  cessão em mudança de controle, Prêmio de Liquidez (múltiplo até 6×, teto a
  fixar: sem teto, a cláusula não gera direito exigível), aviso de rescisão 90
  dias, mediação + foro, nota sobre a Lei 4.886/1965.
- **Contrato gerado por parceiro**: o texto v2 é preenchido com os dados das
  duas partes e da matriz (padrão ABNT) e vira um registro **pendente** na tela
  SuperAdmin › Contratos (modelo categoria "parceria" + `contratos_assinaturas`
  com `parceiro_id` e `html_assinado`); passa a **assinado** só pela assinatura
  eletrônica completa (selfie, IP, dispositivo, localização, hash) — seção 3.2.
- Ainda sem automação (lançar por ajuste): 13º da carteira, Master Regional
  (override calculado, mas elegibilidade manual), certificações.

## 5. Ondas de entrega (cada uma: migration + script de entrega + QA + teste no site de teste)

**Estado (03/09/2026):** Ondas 0 e 1 implementadas e registradas no projeto,
aguardando conferência no ambiente de teste. Entregáveis:
`supabase/migrations/20260904100000_parceiros_qa_casos.sql` (17 casos PGP),
`20260904110000_parceiros_fundacao.sql` (tabelas, RLS, 13 funções, sementes),
`20260904120000_parceiros_qa_rotinas.sql` (6 rotinas, todas passando na
réplica local), `docs/script_parceiros_onda1.sql` (script de entrega, rodado
duas vezes na réplica sem erro), aba **Parceiros** no SuperAdmin
(`ParceirosPanel.tsx`, `useParceiros.ts`), cartão "Parceiro de origem e
implantação" em `TenantDetalhe`, campo Parceiro no Kanban de leads. Prefixo dos
casos: **PGP** (PARC já pertence ao Marketplace).

**Onda 2 (03/09/2026):** implementada. `20260904130000_parceiros_portal.sql`
(estágio derivado como função pura + wrapper, `parceiro_meu_portal`,
`parceiro_cadastrar`, migração dos afiliados do Marketplace, rotina PGP-011,
pontes e2e), Edge Function `parceiro-cadastro` (autocadastro sem conta),
robô-parceiro semeado por `seed-e2e-user`, seção pública `/parceiros`,
`/parceiros/cadastro`, `/parceiros/entrar`, portal `/parceiro` e
`/parceiro/perfil`, guarda `ParceiroRoute`, redirecionamento pós-login,
atalho no menu do usuário, link "Parceiros" no site, aba Afiliados removida do
Marketplace (entra o convite). Cypress `portal-parceiro.cy.ts` cobre PGP-030 a
032. Script: `docs/script_parceiros_onda2.sql`.
Retoques (03/09/2026, após revisão do dono): menu do site mais espaçado e
sem o botão Diagnóstico na barra; logo local (o asset do Lovable não carrega
fora do domínio dele); cards de tipo de parceiro abrem detalhe (para quem é, o
que faz, como ganha, aprovação, requisitos); Fale conosco (WhatsApp e e-mail)
na seção pública; Termos de Uso com confidencialidade/segredos e programa de
parceiros; Contrato de Parceria com aceite eletrônico (seção 3.2),
`docs/script_parceiros_contrato.sql`.
**Onda 3 (03/09/2026):** implementada. `20260904150000_parceiros_motor_comissoes.sql`:
`parceiro_fechar_competencia` (snapshot de MRR por parceiro/cliente, comissão
recorrente pela tabela de níveis e atribuição link/casa, retenção automática em
inadimplência, comissão zero com rastro em plano interno, evento de setup do
implantador lido de `parceiro_eventos_remuneracao`, bônus de renovação pelo
multiplicador do nível, promoção de nível sem rebaixamento), agendamento pg_cron
`parceiros-fechamento-mensal` (dia 25, 06:30), funções do SuperAdmin (listar
por competência, marcar pago/retido/fechado, ajuste), sugestão por localidade
`parceiros_sugerir_para_lead` (mesma cidade › mesmo estado › distância; sem
extensão nova) e `superadmin_lead_encaminhar` (atribuição casa), `leads.cidade/uf`,
histórico de 12 meses no portal. Rotinas PGP-010/012/013/014 passam na réplica
(escrevem só no cercado qa-sandbox). Telas: sub-aba **Comissões** (prévia,
fechar, resumo por parceiro com PIX, marcar pago/reter, ajuste), botão "Sugerir
parceiro por localidade" no Kanban de leads, gráfico "Sua evolução" no portal.
Script: `docs/script_parceiros_onda3.sql`.
**Política v2 + Onda 4 (03/09/2026):** `20260904160000_parceiros_politica_v2.sql`
(matriz, config, marcos do cliente, motor v2, contrato v2 na tela de Contratos),
`20260904170000_parceiros_captura_ref.sql` (resolver ref, clique, trigger da
landing, origem no tenant via webhook/onboarding, PGP-015),
`20260904180000_leads_meta_ads_standby.sql` + Edge Function
`meta-leads-webhook` (porta para leads de tráfego pago da Meta, desligada até
preencher `meta_*` em `app_config`). Telas: cards por trilha com exemplos e
"o que não precisa fazer", cadastro por trilha + perfil, SuperAdmin com matriz
por trilha, parâmetros e bônus, cartão de marcos em Empresas › Assinatura,
origem Meta Ads no Kanban, captura do `?ref=` no site e na landing. Scripts:
`docs/script_parceiros_politica_v2.sql`, `docs/script_parceiros_onda4.sql`.
**Dados fiscais da YourEyes (03/09/2026):** `20260904190000_youreyes_dados_fiscais.sql`
cria o registro único `youreyes_empresa` (razão social, CNPJ, inscrições,
endereço, contato, representante legal, foro, regime), editável em
SuperAdmin › **Dados da YourEyes**; leitura pública sem CPF; o Contrato de
Parceria passa a identificar a contratante por esses dados (`{{YE_*}}`).
Script: `docs/script_youreyes_dados_fiscais.sql`.
Pendências anotadas: (a) PGP-020/021 (aba Parceiros do SuperAdmin) seguem sem
teste de tela porque a conta-robô não é superadmin e não deve virar; precisa de
um robô-superadmin próprio. (b) A data de go-live usa `profiles.updated_at` do
onboarding concluído como aproximação; a Onda 3 passa a gravar a data no
snapshot mensal. (c) Cliques no link e gráfico de 12 meses só nascem nas Ondas
3 e 4 (o portal já reserva o lugar). (d) **Bloqueio de ambiente**: o secret
`QA_E2E_TOKEN` não está cadastrado no repositório; sem ele a esteira pula a
semeadura das contas-robô e não envia o resultado do Cypress ao painel de QA.
O spec do portal pula (pendente, com aviso) enquanto o robô-parceiro não
existir. Cadastrar o secret é gesto do dono do repositório.

### Onda 0 — Documentação de testes (antes de qualquer código)
- `qa_modulos`: novo módulo `parceiros` (SuperAdmin) e `portal-parceiro`.
- `qa_casos_teste` `PARC-001…`: casos `api` (RLS: parceiro A não vê carteira do
  B; comissão zero em plano tester; estágio derivado por cenário; fechamento
  idempotente; captura de `ref` grava origem) e casos `e2e` (login de parceiro
  cai em `/parceiro`; copiar link; carteira lista clientes; exportar CSV).
- Só depois disso nascem os `it()` em `cypress/e2e/portal-parceiro.cy.ts` e as
  pontes em `qa_cobertura_e2e` (a guarda `npm run qa:cobertura-e2e` reprova
  teste inventado).

### Onda 1 — Fundação de dados + SuperAdmin
- Migration com as tabelas da seção 3, colunas novas (`IF NOT EXISTS`), RLS,
  RPCs de superadmin, semente de níveis/trilhas do mockup.
- Aba **Parceiros** no SuperAdmin: cadastro, links, vínculo manual de tenants e
  leads a um parceiro, campo "Parceiro de origem" em `TenantDetalhe`, ciclo
  contratual em `TenantAssinatura`, campo "Parceiro" no Kanban de leads.
- Aprovação automática para indicador, manual para os demais tipos.
- Tabela de remuneração por evento (setup, go-live, renovação) editável na aba.
- Seed de staging: 2 parceiros fictícios (Clínica Staging SST, Contábil
  Staging) ligados a tenants da Empresa Staging LTDA.
- Conferência: `SELECT` de parceiros, links e tenants vinculados.

### Onda 2 — Seção Parceiros no site + Portal do Parceiro (leitura)
- `/parceiros` (página pública), `/parceiros/cadastro`, `/parceiros/entrar`,
  link "Parceiros" no cabeçalho e rodapé de `Site.tsx`.
- Rota `/parceiro`, `ParceiroRoute`, redirecionamento pós-login, atalho no menu
  do usuário para quem também é usuário de tenant.
- Marketplace: remove a aba Afiliados; entra o cartão "Vire parceiro YourEyes";
  `/parceiro/perfil` ganha o botão "Também quero ofertar serviços" que cria ou
  liga o `marketplace_profissionais`.
- Cabeçalho, KPIs, carteira (com estágio derivado e Exportar CSV), link e
  campanhas (ainda sem clique automático), funil.
- Componentes shadcn/ui seguindo a paleta do sistema (o mockup tem paleta
  própria; a tela final segue o design system do app, tema claro/escuro).

### Onda 3 — Motor de comissões
- `parceiro_fechar_competencia`, snapshots mensais, extrato, "Próximas
  renovações" com bônus, gráfico 12 meses, promoção de nível.
- Comissão por evento: setup do implantador quando o onboarding do cliente é
  concluído; usa a tabela configurável da Onda 1.
- SuperAdmin: fechar competência manualmente, marcar Pago/Retido, ajuste.
- Sugestão de parceiro por proximidade no Kanban de leads e mapa por região
  (seção 3.1).
- pg_cron no dia 25 (só roda com `app_config` preenchido).
- Script de entrega **não altera dado existente** (só cria), então não exige
  tabela `backup_`; se a Onda 3 precisar reclassificar tenants já existentes,
  aí sim entra o `CREATE TABLE backup_parceiros_<data>`.

### Onda 4 — Captura automática e integrações
- `?ref=` na landing e no `/lp`, `localStorage` 90 dias, `landing_leads.ref_codigo`.
- `mercadopago-checkout` (metadata) → `assinaturas.ref_codigo` → webhook grava
  origem no tenant e preenche o ciclo em `subscriptions`.
- `onboarding-signup` recebe `refCodigo`.
- `parceiro_registrar_clique` e contadores por link.
- Opcional: migração dos afiliados do marketplace.

---

## 6. Riscos e pegadinhas a respeitar na execução

- **Carimbo de migration único**; `git pull` antes de criar (Lovable também
  escreve na `main`).
- Script de entrega: uma transação, blocos `DO` com `EXCEPTION`, idempotente,
  nenhuma marca `$$` em comentário, termina com um `SELECT` de conferência.
- `SET lock_timeout = '10s'` ao alterar `tenants`, `leads` e `subscriptions`
  (tabelas movimentadas); triggers, se houver, em scripts separados.
- Enum `lead_origem` já tem `'indicacao'` — reutilizar, não criar
  `'parceiro'`; comparar enums como texto quando houver dúvida.
- `tenants.plano` legado continua sendo gravado pelo onboarding e pelo webhook;
  o portal ignora essa coluna e lê `subscriptions`.
- `Site.tsx` tem preços hardcoded: qualquer mudança de preço precisa refletir em
  `plan_prices` ou a comissão calculada diverge do que o cliente vê.
- Cypress no staging usa a conta-robô semeada pela esteira; o teste de tela do
  portal precisa de um usuário-parceiro semeado (ajuste em `seed-e2e-user` ou
  seed SQL), sem dado real.
- Dados de exemplo do mockup (Clínica SST Vida, Metalúrgica Andrade...) são
  fictícios e podem virar semente do staging; jamais nomes reais de clientes.

## 7. Arquivos que serão tocados (previsão)

| Área | Arquivos |
|---|---|
| Banco | `supabase/migrations/<carimbo>_parceiros_*.sql` (uma por onda), `docs/script_parceiros_onda*.sql` |
| Edge Functions | `mercadopago-checkout`, `mercadopago-webhook`, `onboarding-signup`, `seed-e2e-user` |
| SuperAdmin | `src/pages/admin/SuperAdminDashboard.tsx`, `src/components/admin/superadmin/ParceirosPanel.tsx` (novo), `TenantDetalhe.tsx`, `TenantAssinatura.tsx`, `LeadsCRMKanban.tsx`, `src/hooks/useParceiros.ts` (novo) |
| Portal e site | `src/pages/parceiros/*` (Seção pública, Cadastro, Entrar — novos), `src/pages/parceiro/*` (portal — novo), `src/components/parceiro/*` (novo), `src/components/auth/ParceiroRoute.tsx` (novo), `src/App.tsx`, `src/hooks/useAuth.ts` (destino pós-login) |
| Marketplace | `src/pages/Marketplace.tsx` (sai a aba Afiliados, entra o convite), `AfiliadosDashboard.tsx` (removido na Onda 2) |
| Público | `src/pages/Site.tsx`, `src/pages/LandingPage.tsx` |
| QA | migration de casos `PARC-*`, `cypress/e2e/portal-parceiro.cy.ts`, pontes em `qa_cobertura_e2e` |
| Tipos | `src/integrations/supabase/types.ts` (regenerar após migration no staging) |
