# Discovery — Camada de Agentes Autônomos no YourEyes

Data: 15/10/2026. Método: varredura somente-leitura do repositório (rotas em `src/App.tsx`, 1159 migrations, ~80 edge functions, `docs/`). Nenhum código foi alterado.
Legenda: **[LACUNA]** = não existe, precisa construir · **[VERIFICAR]** = ambíguo no código, exige conferência/decisão humana. Corpos de RPCs não foram lidos um a um; onde só o nome foi visto, está dito.

---

## 1. Mapa do sistema (as-built)

### 1.1 Plataforma
- Vite + React + TS; Supabase (Postgres + RLS + Edge Functions). Produção `diayjpsrcerycycyaxst`, staging `bmehdgthciuvdbvutsdv` (`CLAUDE.md`). 438 `ENABLE ROW LEVEL SECURITY`, 423 triggers.
- Lógica mora no banco (RPCs `ponto_*`, `ferias_*`, `decimo_terceiro_*`, `afastamento_*`, `folha_*`, `sst_*`, `epi_*`). Edge functions são só IA, integrações e links públicos.

### 1.2 Módulos e rotas (principais)
| Domínio | Rotas / páginas | Tabelas-chave |
|---|---|---|
| Ponto/Jornada | `/ponto`, `/analise-jornada`, `/ponto-externo/:token` | `ponto_marcacoes`, `ponto_diario`, `ponto_alertas`, `ponto_ajustes`, `ponto_espelhos`, `ponto_fechamentos`, `ponto_banco_horas*`, `ponto_ia_analises`, `ponto_audit_log` |
| Férias / 13º | `/ferias`, `/ferias-assinatura/:token`; 13º é aba do `/financeiro` | `ferias_*`, `folha_ferias_calculo`, `folha_13_calculo` |
| Folha/Financeiro/Benefícios | `/financeiro`, `/financeiro/beneficios` | `folha_*`, `beneficios_*` |
| Afastamentos/Atestados | `/atestados` (CentralGaf) | `atestados`, `afastamentos*`, `alertas_saude`, `gaf_auditoria` |
| SST | `/saude-ocupacional`, `/epis`, `/ergonomia`, `/compliance-sst`, `/incidentes-acidentes`, `/terceiros` | `sst_*`, `epi_*`, `eventos_sst`, `terceiro_*`, `ergonomia_*` |
| Psicossocial / Ouvidoria / Bem-estar | `/psicossocial`, `/questionario/:token`, `/ouvidoria`, `/ouvidoria-externa/:token`, `/felicidade` | `psicossocial_*`, `ouvidoria*`, `bem_estar_*` |
| Admissão/Colaboradores | `/colaboradores`, `/completar-cadastro/:token`, `/onboarding-rh` | `admissoes`, `admissao_documentos`, `onboarding_*` |
| Documentos/Assinaturas | `/documentos` + 8 rotas públicas por token | `*_assinatura_links`, `contratos_*`, `documentos` |
| Experiência | `/contratos-experiencia` | `contratos_experiencia` |
| Gestão de pessoas | `/trilhas`, `/pdi`, `/avaliacoes`, `/metas`, `/mapa-comportamental`, `/estrategia`, `/cultura-celebracoes`, `/feed` | respectivas tabelas |
| Plano de Ação / Pendências | `/plano-acao`, `/pendencias` | `plano_acoes`, `plano_tarefas` |
| Contábil | `/hub-contabil` | `hub_*` |
| Marketplace/Parceiros | `/marketplace`, `/marketye/*`, `/parceiro*` | `marketplace_*`, `parceiro_*` |
| Comercial | `/lp`, site | `landing_leads`, `leads`, `lead_interacoes` |
| Plano/Cobrança | `/meu-plano` | `plans`, `subscriptions`, `usage_counters`, `assinaturas` |
| SuperAdmin | `/admin/*` (QA, central de clientes) | `qa_*`, `evento_erro`, `evento_incidente`, `youreyes_agentes` |

### 1.3 Jobs pg_cron existentes (todos em migrations; se estão ativos em produção depende dos scripts colados — [VERIFICAR])
`ponto-materializar-faltas`, `ponto-vigilancias-diarias` (7 vigilâncias), `ponto-links-vencidos`, `ponto-expurgo-geo`, `ferias-alertas-diario`, `decimo_terceiro_alertas_diario`, `afastamento-encerrar-vencidos`, `gerar-alertas-estabilidade-30-dias`, `reavaliar-validade-documentos`, `epi-ca-vigiar-diario`, `epi-estoque-minimo-diario`, `sst-vigiar-documentos-diario`, `auto-abrir-competencia-mensal`, `bloquear-profissionais-expirados`, `parceiros-fechamento-mensal`, `central-expurgo-eventos`, `qa-*`.
**Não existe cron para**: fechamento/espelho/folha, eSocial, Hub Contábil, admissão e documentos, experiência, assinaturas pendentes, trilhas, suporte, leads, cultura, ASO/exames, CAT, terceiros, psicossocial, ouvidoria. O padrão de disparo `net.http_post` com URL/chave em `app_config` está provado (`20260810100000_app_config_e_dispatch_por_ambiente.sql`).

### 1.4 Integrações
eSocial (`esocial-transmissao`: S-2210/2220/2240; geradores SQL de S-2200/2230/2299/férias/13º), Resend (e-mail), WhatsApp via WhatsAPI (`superadmin-whatsapp-send`, `psicossocial-whatsapp-otp`; envio síncrono, sem fila), Mercado Pago, Meta CAPI/leadgen, HubSpot, GitHub Actions (Cypress), OpenAI (43 funções). **Faciliti: nenhuma ocorrência no repositório** [VERIFICAR com o dono do produto].

### 1.5 IA existente
- ~36 funções `ai-*` chamando OpenAI direto (gpt-4o / gpt-4o-mini), disparadas pelo front; **sem camada única, sem log de tokens/custo/tenant** [LACUNA].
- Único padrão "IA propõe, humano decide" persistido: `ponto_ia_analises` + `ponto_ia_analisar_alerta` / `ponto_ia_registrar_decisao`.
- `youreyes-run-agent` é **agente de QA** (lê findings do `ai-qa-scan`, gera relatório). Não age em dados de cliente, sem ferramentas/loop. O cron `youreyes-dispatch-agentes` foi **desligado** em `20260916185000_central_testes_aposentada.sql`. Tabelas `youreyes_*` seguem, RLS só superadmin.

### 1.6 Permissões e auditoria
- Tenant: `get_user_tenant_id()` (via `profiles`, 1 tenant por usuário). Papéis: `user_roles`/`has_minimum_role`; perfis: `perfis_acesso`, `perfil_permissoes`, `perfil_permite_modulo`, 11 políticas RESTRICTIVE `perfil_restringe_leitura_*`. Superadmin: `is_superadmin`.
- Entitlements/planos: `plans`, `features` (boolean/limit/metered), `plan_entitlements`, `subscriptions`, `subscription_overrides`, `usage_counters`, `entitlement_can_use()`. **Não achei features metered de IA** [VERIFICAR seed].
- Auditoria fragmentada por domínio: `audit_logs` (só ações de usuário), `ponto_audit_log` (imutável), `gaf_auditoria`, `documento_audit_log`, `terceiro_audit_log`, `marketplace_audit_log`, `entitlement_audit_log`, etc. **Não existe trilha única de "ação de agente".**
- 46 edge functions usam service role: isolamento de tenant depende do código de cada uma.

### 1.7 Pontos de partida reaproveitáveis
1. **Plano de Ação como fila de trabalho**: `plano_acao_abrir()` (idempotente por origem), `ponto_alerta_gerar_acao`, `ferias_alerta_gerar_acao`, `decimo_terceiro_alerta_gerar_acao`.
2. **Tabelas-inbox de eventos**: `ponto_alertas`, `ferias_alertas`, `folha_alertas_prazo`, `psicossocial_alertas`, `alertas_saude`, `trilha_notificacoes`, `leads_integracoes_eventos` (idempotente), `esocial_transmissoes`.
3. Padrão de link por token (`*_assinatura_links` + RPCs `*_por_token`).
4. `entitlement_can_use` + `usage_counters` para medir/limitar.
5. Realtime só em `ponto_marcacoes`/`ponto_diario`; **sem outbox nem `pg_notify`** [LACUNA].

### 1.8 Achados de segurança que bloqueiam agentes (corrigir antes)
Conferidos por mim no código:
- `ai-pgr-riscos`: `verify_jwt=false`, usa service role e **`tenant_id`/`empresa_id` vindos do body** → leitura/escrita cross-tenant possível (`supabase/config.toml:55`, `supabase/functions/ai-pgr-riscos/index.ts:19-55`).
Relatados pela exploração, não conferidos um a um [VERIFICAR]: 33 das ~36 `ai-*` não validam usuário; `ai-qa-agent` tem e-mail/senha de teste fixos no código; autorização "agendada" do `youreyes-run-agent` compara com a anon key (pública); `mercadopago-webhook` valida por consulta à API, não por HMAC.

---

## 2. Catálogo de atividades automatizáveis

**Score** = soma 0–5 de: volume · clareza de regra · dado/gatilho disponível · baixo risco legal/financeiro · reversibilidade (máx 25). Notas são minhas, baseadas nos relatórios; calibrar com o dono do produto.
**Nível**: A = Assistir · B = Agir com aprovação · C = Autônomo em limites.
**Preço**: U = por ação · O = por resultado · S = assinatura · H = híbrido.

### 2.1 Onda 1 — o sistema já tem o dado; falta o gatilho/lembrete
| # | Módulo | Atividade | Score | Nível | Gatilho | Paradas duras / checkpoints | Lacunas | Unidade de valor | Preço | Economia humana (estim.) |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Experiência | Vigiar vencimento (45/90d), alertar 15/7/2d e preparar decisão efetivar/prorrogar/encerrar | 22 | C (alerta) / B (minuta do aditivo) | Agenda diária | Nunca encerrar/efetivar sozinho | Colunas `alerta_*_enviado` existem e **ninguém as consome**; falta cron e canal | Contrato acompanhado até decisão | O | ~15 min/contrato |
| 2 | Admissão | Cobrar documentos pendentes do candidato | 21 | C | Agenda + evento (admissão criada) | Não aprovar documento; não concluir admissão | Cron, canal (e-mail/WhatsApp), log de envio | Admissão com checklist 100% | O | ~30–60 min/admissão |
| 3 | Assinaturas | Cobrar assinatura pendente (férias, PDI, contrato, OS, manual, experiência) | 21 | C | Agenda sobre `*_assinatura_links` | Não assinar por ninguém; respeitar expiração do token | Visão unificada de pendências; lembrete; expiração de link [VERIFICAR] | Documento assinado | O | ~10 min/documento |
| 4 | Ponto | Triar alertas de inconsistência e sugerir tratamento | 20 | A→B | Evento (`ponto_alertas`) | Não aprovar ajuste/abono | Já existe `ponto_ia_analises`; falta lote e métrica de acerto | Alerta triado | U | ~3 min/alerta, alto volume |
| 5 | Ponto | Lembrar ciência do espelho; resumo pré-fechamento (`ponto_fechamento_pendencias_criticas`) | 20 | C (lembrete) | Agenda mensal | Nunca fechar competência | Lembrete de espelho inexistente; canal | Competência pronta p/ fechar | O | horas/mês/empresa |
| 6 | Férias | Cobrar aviso/ciência 30 dias; lembrar vencimento do concessivo | 19 | C | Agenda (já há `ferias-alertas-diario`) | Não programar/pagar sozinho | Lembrete de assinatura [VERIFICAR `ferias_aviso_tem_ciencia`] | Aviso com ciência | O | ~10 min/solicitação |
| 7 | SST | ASO periódico: vigiar vencimento e alertar RH | 18 | C (alerta ao RH) | Agenda | Convocar colaborador só com aprovação; nunca decidir aptidão | `sst_proximo_exame_periodico` existe **sem chamador**; sem tabela de exames/PCMSO estruturado | ASO em dia / vencido evitado | O | alto |
| 8 | SST | EPI: cobrar assinatura de entrega e troca vencida | 19 | C | Agenda (`data_prevista_troca`) | Não bloquear nem entregar | Cron de troca/assinatura | Entrega regularizada | U | médio |
| 9 | Trilhas | Disparar `trilha-notificacoes` por agenda | 19 | C | Agenda | — | Edge pronta, **sem scheduler**; canal | Trilha concluída no prazo | U | médio |
| 10 | Plano de Ação/Pendências | Digest diário de pendências por gestor; cobrança de prazo 5W2H | 19 | C | Agenda | — | `usePendencias` só lê; falta envio | Pendência resolvida | S | alto |
| 11 | Hub Contábil | Cobrar SLA e envio de competência ao contador | 17 | B | Agenda | Não enviar guia/certidão sem conferência | `hub_notificacao_config` sem consumidor [VERIFICAR] | Competência entregue | O | ~1 h/empresa/mês |
| 12 | Cultura | Gerar aniversários/marcos e rascunho de felicitação | 18 | B | Agenda | Humano publica | Gerador (hoje manual no front) | Ação cultural publicada | U | baixo |
| 13 | Psicossocial | Lembrete de convites não respondidos | 15 | B | Agenda | Nunca identificar respondente; mínimo por GHE | Cron; canal | Taxa de resposta | O | médio |

### 2.2 Onda 2 — rotina de alto volume, decisão com aprovação
| # | Módulo | Atividade | Score | Nível | Paradas duras | Lacunas | Preço |
|---|---|---|---|---|---|---|---|
| 14 | Atestados | OCR/extração + pré-validação (CRM, datas, sobreposição) e rascunho de afastamento | 14 | A→B | **Nunca aprovar/glosar**; CID/saúde mental só com acesso restrito; DPA com provedor de IA | `consultar-crm` é stub; log de IA; base legal para enviar saúde à OpenAI [VERIFICAR] | U |
| 15 | Ponto | Pré-análise de ajustes e abonos (recomenda aprovar/negar com base na regra) | 14 | B | Autoaprovação já bloqueada por trigger; decisão humana | Métrica de acurácia por tipo | H |
| 16 | Folha | Conferência de variação mês a mês e de descontos (art. 462) | 15 | A→B | Não fechar folha | `folha_conferencia_variacao` existe; falta agenda e relatório | U |
| 17 | Benefícios/NF | Conciliar fatura × NF × rubricas | 14 | B | Não pagar | IA de NF existe (`ai-nf-match`) | U |
| 18 | Admissão | Conferir cadastro/documentos e pré-validar (OCR) | 13 | A→B | Humano aprova; LGPD | OCR de documento pessoal não existe | U |
| 19 | Colaboradores | Importação de planilha e resolução de pendências; dedup | 14 | B | Não mesclar sem aprovação | Log de decisão | U |
| 20 | Suporte | Triagem/classificação de tickets | 14 | A | — | Sem SLA/notificação | U |
| 21 | Leads | Cadência de follow-up | 13 | B | — | Sem cadência; canal | H |
| 22 | SST | CAT: lembrar prazo (1º dia útil) em `eventos_sst` | 13 | C (lembrete) | **Nunca emitir/transmitir CAT** | Prazo só existe em `afastamentos_pendencias` | O |
| 23 | Ouvidoria | Triagem e roteamento; SLA | 10 | A | **Nunca desanonimizar**; denúncia grave vai a humano | Sem SLA/prazo; IA não persiste | U |
| 24 | Terceiros | Vencimento de documentos/treinamentos | 17 | C (alerta) | Bloqueio de acesso é humano | Cron de passagem do tempo (trigger só dispara na escrita) | U |

### 2.3 Onda 3 — alto risco/valor; só sobre telemetria e auditoria provadas
| Atividade | Por que é risco | Máximo de autonomia |
|---|---|---|
| Fechamento de competência (ponto) e de folha | Reabertura exige rito formal | B (checklist pronto; humano executa) |
| Cálculo/pagamento de 13º e férias | Financeiro; prazos 30/11 e 20/12 | A (conferir cálculo, apontar divergência) |
| Transmissão eSocial (S-2200/2230/2299/2210/2220/2240) | Irreversível/multa | A (gerar, validar, traduzir rejeição) |
| Acerto semestral do banco de horas | Pagamento | A |
| Desligamento/rescisão | Parada dura | A |
| Comissão de parceiros | Financeiro | B |
| Moderação/contestação/denúncia Marketye | Reputacional/jurídico | A |
| Alertas psicossociais, recaída de afastamento | Saúde mental; ambíguo | A |

---

## 3. Agentes vendáveis (um agente = um resultado ponta a ponta)

| Agente | Resultado que possui | Atividades (#) | Evento de sucesso | Unidade de valor |
|---|---|---|---|---|
| **Agente de Admissão** | Admissão completa e documentada no prazo | 2, 18, 19 (+ S-2200 só proposto) | Admissão `concluido` com checklist 100% | Admissão concluída |
| **Agente de Experiência & Ciclo do Contrato** | Nenhum contrato de experiência vence sem decisão | 1 | Decisão registrada antes do D-0 | Contrato decidido no prazo |
| **Agente de Assinaturas** | Todo documento enviado volta assinado | 3, 6 (parcial) | Assinatura registrada | Documento assinado |
| **Agente de Fechamento de Ponto** | Competência pronta p/ fechar sem pendência crítica | 4, 5, 15 | Pendências críticas = 0 no D-X | Competência pré-fechada |
| **Agente de Conferência de Folha** | Folha conferida antes do fechamento | 16, 17 | Divergências listadas e tratadas | Folha conferida |
| **Agente de Saúde Ocupacional (vigilância)** | ASO/exames/EPI/documentos SST em dia | 7, 8, 22, 24 + renovação de PGR/PCMSO via Plano de Ação | Vencimento evitado (ação aberta e concluída antes do prazo) | Vencimento evitado |
| **Agente de Pessoas & Engajamento** | Ciclos de trilha, PDI, metas, avaliações e cultura cumpridos | 9, 10, 12, 13 | Item concluído no prazo | Item concluído |
| **Agente de Pendências (maestro)** | Gestor recebe 1 digest/dia e pendências caem | 10 | Pendência encerrada após digest | Pendência resolvida |
| **Agente Contábil** | Competência entregue ao contador no SLA | 11 | Entrega confirmada | Competência entregue |
| **Agente SuperAdmin (operação da casa)** | Suporte/leads/saúde dos clientes triados | 20, 21 + central de incidentes | Ticket triado/lead contatado | Ticket/lead tratado |

---

## 4. Camada de venda / empacotamento

- **Bundles sugeridos**: *Admissão & Contrato* (Admissão + Experiência + Assinaturas) · *Ponto & Folha* (Fechamento + Conferência) · *SST Vigilante* (Saúde Ocupacional) · *Pessoas* (Engajamento + Pendências) · *Contábil*.
- **Preço**: híbrido (base por agente ativo + resultado) para os de rotina com evento claro (Admissão, Experiência, Assinaturas, SST); por ação para os de triagem/IA (Ponto, Atestados, NF, Suporte). Outcome-based só onde a atribuição é limpa: "assinatura recebida após lembrete" é atribuível; "folha sem erro" não é — evitar.
- **Custo de servir**: lembretes por regra (sem LLM) têm custo marginal ~zero (e-mail/WhatsApp); LLM entra só em triagem/extração/minuta. Hoje tudo é gpt-4o/4o-mini sem medição → **a margem não é calculável hoje** [LACUNA]. WhatsApp usa WhatsAPI não oficial, risco de banimento/escala [VERIFICAR antes de vender volume].
- **Telemetria mínima por execução (desde o dia um)**: `tenant_id`, `agente`, `versão da regra`, `gatilho`, `entidade alvo`, `ação`, `nível de autonomia`, `status`, `aprovador`, `tokens/custo`, `canal e custo`, `resultado (evento de sucesso sim/não, quando)`, `reversão`.
- **Entitlement**: cadastrar cada agente como `feature` em `features`/`plan_entitlements` e contar consumo em `usage_counters` (a infraestrutura já existe).

---

## 5. Fundação técnica (construir antes de qualquer agente)

1. **Trilha única de ações de agente** (`agente_acoes`: quem/o quê/quando/base/resultado/aprovador/reversão) + **telemetria de uso e custo** — mesma tabela serve auditoria, segurança e cobrança. Imutável como `ponto_audit_log`. [LACUNA]
2. **Registro de agentes por tenant**: ativo/inativo, nível de autonomia, envelope (limites, horários, canais), vínculo ao entitlement. O `youreyes_agentes` é só de superadmin e de QA — reaproveitar o desenho, não a tabela. [LACUNA]
3. **Identidade do agente**: execução com papel/perfil próprio de menor privilégio (hoje funções usam service role e confiam em `tenant_id` do body). Padrão: o agente roda com `tenant_id` derivado do registro, nunca do input; RPCs `SECURITY DEFINER` estreitas para cada ação permitida.
4. **Barramento de eventos/agenda**: outbox (`agente_eventos`) alimentado por triggers nas tabelas-inbox existentes + despachante pg_cron com `net.http_post` (padrão `app_config`). Idempotência por chave (modelo `leads_integracoes_eventos`). [LACUNA]
5. **Camada de comunicação**: fila de envio com log, templates, opt-out, janela de horário, limites; substituir chamadas diretas do navegador (`sendEmail.ts`) e avaliar WhatsApp oficial. [LACUNA]
6. **Gateway de IA**: função única que valida JWT/tenant, checa `entitlement_can_use`, registra tokens/custo, aplica minimização de dados e escolhe o modelo. Migrar as `ai-*` gradualmente. [LACUNA]
7. **Regras parametrizáveis e versionadas** (prazos de alerta 15/7/2d, periodicidade de lembrete, tolerâncias): hoje estão em código/colunas fixas; criar tabela de parâmetros por tenant com versão.
8. **Correções de segurança da §1.8** (primeiro item: `ai-pgr-riscos`).
9. **Kill switch** por agente e por tenant, e modo "sombra" (agente propõe, não age) como estado inicial obrigatório.
10. **QA**: cada agente nasce com casos em `qa_casos_teste` + rotina `qa_caso_*` / `it()` (regra da casa); migrations + `docs/script_*.sql` conforme `CLAUDE.md`. Atenção ao auto-RLS do SQL Editor ao criar tabelas nos scripts de entrega.

---

## 6. Roadmap em ondas

- **Onda 0 — Fundação (pré-requisito)**: itens 1–4, 6 (mínimo), 8, 9 da §5. Piloto em modo sombra em staging com dados fictícios. Nada de agente em produção antes disto.
- **Onda 1 — Quick wins sem LLM (lembretes por regra)**: Experiência (#1), Assinaturas (#3), Admissão-cobrança (#2), Trilhas (#9), Digest de Pendências (#10), SST-vigilância (#7, #8, #24), lembretes do ponto (#5). Nível C só em lembrete; zero decisão.
- **Onda 2 — Triagem com IA + aprovação**: Ponto (#4, #15), Atestados (#14, com parecer jurídico/DPO antes), Folha (#16, #17), Admissão-OCR (#18), Suporte/Leads. Autonomia sobe por tipo conforme acurácia medida.
- **Onda 3 — Alto risco**: fechamentos, 13º/férias, eSocial, banco de horas — somente nível A/B; reavaliar após 2 ciclos de dados reais de acurácia.

Critério de promoção de nível: taxa de aceitação humana ≥ meta definida por tipo de ação, por N ciclos, sem incidente — **meta numérica a decidir** [VERIFICAR].

---

## 7. Riscos e governança

| Risco | Detalhe | Mitigação |
|---|---|---|
| LGPD art. 11 | `extract-atestado` e IA SST enviam documento de saúde à OpenAI (transferência internacional) | DPA/base legal, minimização, não enviar CID a LLM por padrão, log de acesso clínico (`log_acesso_clinico`) |
| Multi-tenant | Service role + `tenant_id` do body (ex.: `ai-pgr-riscos`) | Identidade de agente (§5.3), teste de isolamento no QA (`ISOL-*`) |
| Anonimato psicossocial/ouvidoria | Agente pode vazar identidade por cruzamento | Agentes só veem agregados; respeitar mínimo por GHE; sem acesso a denúncia identificada |
| Legal/folha/eSocial | Irreversível ou multa | Paradas duras da §2.3; agente nunca transmite/fecha/paga |
| Comunicação | WhatsApp não oficial, spam, horário, opt-out | Fila com limites e janela; canal oficial antes de escalar |
| Gaming / atribuição | Outcome-based pode ser inflado (lembrete que cria sucesso artificial) | Só cobrar por evento verificável no banco; janela de atribuição; auditoria |
| Erro em escala | Mesmo erro em todos os tenants | Rollout por tenant, kill switch, modo sombra, limite de ações/hora |
| Regra legal desatualizada | Prazos fixos em código | Parâmetros versionados + vigilância de mudança (padrão `ponto_cct_vigiar_vencimento`) |
| Produção | Banco só muda por script colado | Cada entrega: migration + script idempotente; fluxo staging → aprovação → produção (`CLAUDE.md`) |

---

## 8. Autoavaliação crítica (10 perguntas)

1. Inventariei a partir do código? **Sim, via 4 varreduras paralelas + conferência direta de 3 fatos** (cron desligado, `ai-pgr-riscos`, `sst_proximo_exame_periodico` sem chamador). Corpos de RPCs não foram lidos todos; scores são estimativa minha.
2. Lacunas marcadas honestamente? Sim; as de maior peso: sem trilha/telemetria de agente, sem outbox, sem log de IA, sem cron em ~12 módulos.
3. Paradas duras respeitadas? Sim: nenhum agente fecha, paga, transmite, desliga, decide contratação ou trata caso sensível sozinho.
4. Multi-tenant/RLS respeitados? Proposta exige identidade própria do agente; mas o estado atual **viola** isso em funções `ai-*` — tratado como pré-requisito.
5. Cada agente tem unidade de valor e evento de sucesso mensuráveis? Sim na §3; alguns eventos dependem de colunas ainda inexistentes.
6. A telemetria mede uso **e** resultado? Sim (§4), mas ainda é desenho, não existe.
7. Priorizei segurança antes de valor? Onda 0 precede tudo; porém a Onda 1 foi escolhida por baixo risco, não por maior receita.
8. Os preços fazem sentido com o custo de servir? **Não dá para afirmar**: sem medição de custo de IA/canal hoje.
9. O que depende de decisão humana/jurídica? DPA e base legal para IA em dado de saúde; WhatsApp oficial; metas de acurácia para promover autonomia; quais crons estão realmente ativos em produção; existência da integração Faciliti; relação `assinaturas` × `subscriptions`; permitir agentes em produção sem passar por shadow.
10. O que pode estar errado? Relatórios de exploração podem ter falsos negativos ("não achei cron") — vale rodar `SELECT * FROM cron.job` em produção e em staging antes de planejar a Onda 1, para não duplicar automações já existentes.

---

### Pendências [VERIFICAR] consolidadas
`cron.job` real em produção · se há consumidor de `hub_notificacao_config` e de `folha_alertas_prazo` · canal de envio do link de assinatura de férias · existência de holerite em lote · S-1200 emitido? · features metered de IA em `features` · Faciliti · quem chama `ai-pdi-from-avaliacao`, `ai-gerar-vaga`, `ai-psicossocial-entrevista`, `ai-pgr-riscos` · rota de `PerfisAcesso` · página que hospeda afastamentos · origem exata do `plano_acao_abrir` para psicossocial.
