-- =====================================================================
-- PROGRAMA DE PARCEIROS · ONDAS 0 e 1 · SCRIPT DE ENTREGA
-- Cole no SQL Editor de cada ambiente (Teste → Homologação → Produção),
-- avançando só depois que o anterior devolver OK e o ambiente de teste
-- tiver sido conferido na tela.
--
-- O que faz: documenta os casos de teste PGP-*, cria a entidade "parceiro
-- comercial" (tabelas, RLS, funções do SuperAdmin, níveis e remuneração por
-- evento) e liga a origem do cliente em tenants/leads. SÓ CRIA — não altera
-- nem apaga dado existente, por isso não gera tabela backup_. Idempotente:
-- rodar duas vezes não quebra nem duplica.
--
-- Corresponde às migrations:
--   20260904100000_parceiros_qa_casos.sql
--   20260904110000_parceiros_fundacao.sql
--   20260904120000_parceiros_qa_rotinas.sql
-- =====================================================================

-- ───────────────────────── 20260904100000_parceiros_qa_casos ─────────────────────────
-- =========================================================
-- QA — Programa de Parceiros (Onda 0): documentação dos casos.
--
-- Contexto: o Portal do Parceiro e a gestão de carteira nascem fora do
-- sistema (acesso pelo site), com uma identidade que pode ser também
-- profissional do Marketplace (família PARC, já documentada em
-- rede-parceiros). Para não colidir com PARC-*, esta família usa o
-- prefixo PGP (Programa de Parceiros) e vive no submódulo
-- rede-parceiros/programa-parceiros.
--
-- Regra da casa: documentação antes do teste. Casos 'api' ganham rotina
-- na migration de rotinas da mesma entrega quando a estrutura que testam
-- já existe (Onda 1); os demais ficam documentados e aparecem como
-- "nao_implementado" na bateria até a onda correspondente. Casos 'e2e'
-- só ganham it() no Cypress depois de documentados aqui.
--
-- Decisões do dono do produto (03/09/2026) refletidas nos casos:
--   * indicador é aprovado automaticamente; demais tipos, manualmente;
--   * implantador ganha pelo setup, com valor configurável por evento;
--   * lead da casa recebe sugestão de parceiro por proximidade;
--   * a aba Afiliados do Marketplace migra para este programa.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_pai uuid; v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_pai FROM public.qa_modulos WHERE path = 'rede-parceiros';
  IF v_pai IS NULL THEN
    INSERT INTO public.qa_modulos (label, path, icone, ordem)
    VALUES ('Rede de Parceiros', 'rede-parceiros', '🤝', 90)
    RETURNING id INTO v_pai;
  END IF;

  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'rede-parceiros/programa-parceiros';
  IF v_mod IS NULL THEN
    INSERT INTO public.qa_modulos (parent_id, label, path, icone, ordem)
    VALUES (v_pai, 'Programa de Parceiros', 'rede-parceiros/programa-parceiros', '🔗', 2)
    RETURNING id INTO v_mod;
  END IF;

  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  -- ══════════ A) CADASTRO, APROVAÇÃO E IDENTIDADE (Onda 1) ══════════

  (v_mod, 'PGP-001', 'Indicador nasce ativo; representante, implantador, clínica e contabilidade nascem pendentes',
   'feliz', 'alta', 'aprovado', 'api',
   'Decisão do dono do produto (03/09/2026): aprovação automática só para indicador',
   'O indicador só gera link e não fala em nome da casa: pode entrar sozinho. Quem representa, implanta ou atende o cliente precisa de aprovação humana antes de aparecer como parceiro ativo.',
   'Tabela parceiros com regra de status inicial por tipo.',
   '[{"ordem":1,"acao":"Cadastrar parceiro do tipo indicador sem informar status","resultado_esperado":"Status ativo e aprovacao = automatica"},
     {"ordem":2,"acao":"Cadastrar parceiro do tipo implantador sem informar status","resultado_esperado":"Status pendente e aprovacao = manual"}]'::jsonb,
   'Só o indicador entra sem aprovação.',
   'Sonda de escrita: insere dois parceiros sintéticos (código QA-*) e apaga ao final.'),

  (v_mod, 'PGP-002', 'Código do parceiro é único e o link principal nasce junto com o cadastro',
   'feliz', 'alta', 'aprovado', 'api',
   'Mockup do Portal do Parceiro (link principal ?ref=CODIGO)',
   'Todo parceiro tem um código único que vira o link principal de indicação. Sem o link automático, o parceiro aprovado fica sem o que compartilhar.',
   'Tabela parceiros e parceiro_links.',
   '[{"ordem":1,"acao":"Cadastrar parceiro com código QA-PGP-002","resultado_esperado":"Existe um parceiro_links com o mesmo código, campanha principal, ativo"},
     {"ordem":2,"acao":"Tentar cadastrar outro parceiro com o mesmo código","resultado_esperado":"Recusado por unicidade"}]'::jsonb,
   'Um código, um parceiro, um link principal automático.',
   NULL),

  (v_mod, 'PGP-003', 'Isolamento: parceiro só lê a própria carteira e comissões; leitura direta das tabelas não vaza',
   'negativo', 'critica', 'aprovado', 'api',
   'LGPD art. 46 (segurança) e política de acesso da casa (RLS em toda tabela com dado de terceiro)',
   'Carteira e comissão são dados comerciais de cada parceiro. A leitura precisa ser restrita ao próprio vínculo (parceiro_usuarios) e ao superadmin; nenhuma política pode abrir SELECT para qualquer autenticado.',
   'RLS ligada em parceiros, parceiro_usuarios, parceiro_links, parceiro_link_cliques e parceiro_comissoes.',
   '[{"ordem":1,"acao":"AUDITORIA: RLS ligada nas 5 tabelas","resultado_esperado":"relrowsecurity = true em todas"},
     {"ordem":2,"acao":"AUDITORIA: nenhuma política permissiva de SELECT com USING (true) para authenticated","resultado_esperado":"Só políticas que citam parceiro_usuarios ou is_superadmin"}]'::jsonb,
   'Sem RLS ou com política aberta = falha.',
   'Tabelas de parceiro não são por tenant: não entram em entitlement_gated_tables nem em perfil_permite_modulo. Se PERFIL-003 acusar, a exceção é documentada aqui.'),

  (v_mod, 'PGP-004', 'Origem do cliente fica no tenant e apagar o parceiro não apaga o cliente',
   'excecao', 'alta', 'aprovado', 'api',
   'Planejamento do Portal do Parceiro, seção 2.7 (FK ON DELETE SET NULL)',
   'O tenant guarda quem o originou (parceiro, link, data) e quem o implantou. Encerrar um parceiro não pode arrastar o cliente: as chaves apontam para o parceiro com SET NULL.',
   'Colunas parceiro_id, parceiro_link_id, originado_em e implantador_parceiro_id em tenants; parceiro_id e atribuicao em leads.',
   '[{"ordem":1,"acao":"AUDITORIA: colunas existem em tenants e leads","resultado_esperado":"Todas presentes"},
     {"ordem":2,"acao":"AUDITORIA: regra de exclusão das FKs tenants→parceiros e leads→parceiros","resultado_esperado":"SET NULL, nunca CASCADE"}]'::jsonb,
   'Cliente sobrevive ao parceiro.',
   NULL),

  (v_mod, 'PGP-005', 'Remuneração por evento (setup, go-live, renovação) é configurável, não fixa no código',
   'feliz', 'alta', 'aprovado', 'api',
   'Decisão do dono do produto (03/09/2026): o implantador ganha pelo setup e o valor é configurável',
   'O ganho por evento vive em tabela editável pelo SuperAdmin (por trilha e tipo de parceiro), com valor fixo ou percentual da primeira mensalidade. Nenhuma função pode ter o valor do setup escrito à mão.',
   'Tabela parceiro_eventos_remuneracao semeada.',
   '[{"ordem":1,"acao":"AUDITORIA: tabela existe com evento setup_concluido para implantador","resultado_esperado":"Linha semeada, ativa"},
     {"ordem":2,"acao":"AUDITORIA: função de fechamento (quando existir) lê a tabela e não um literal","resultado_esperado":"Corpo referencia parceiro_eventos_remuneracao"}]'::jsonb,
   'Valor de setup editável na tela, lido pelo motor.',
   'Na Onda 1 só a tabela e a semente existem; a leitura pelo motor entra na Onda 3 e a sonda passa a exigir.'),

  (v_mod, 'PGP-006', 'Níveis por trilha: faixa de MRR e percentual vêm de tabela e o próximo nível é calculável',
   'feliz', 'media', 'aprovado', 'api',
   'Mockup (Trilha Operador · Nível Visão → Diamante, 25% → 30%)',
   'A barra "faltam R$ X para Diamante" depende de níveis ordenados por trilha com mrr_minimo e percentual. Sem tabela, a promoção vira código.',
   'parceiro_niveis semeada com a trilha operador.',
   '[{"ordem":1,"acao":"AUDITORIA: trilha operador tem ao menos 2 níveis ordenados com mrr_minimo crescente","resultado_esperado":"Visão (0) e Diamante (> 0)"}]'::jsonb,
   'Níveis em tabela, ordenados, com percentual.',
   NULL),

  -- ══════════ B) MOTOR (Ondas 3 e 4 — documentados, sem rotina ainda) ══════════

  (v_mod, 'PGP-010', 'Comissão zero em plano interno ou não público (tester)',
   'negativo', 'alta', 'aprovado', 'api',
   'plans.is_public = false não gera receita',
   'Tenant em plano interno aparece na carteira com aviso e comissão zero; o fechamento não pode gerar valor sobre plano de teste.',
   'Motor de fechamento (Onda 3).',
   '[{"ordem":1,"acao":"Fechar competência com tenant em plano tester vinculado a parceiro","resultado_esperado":"Comissão gerada com valor 0 e observação"}]'::jsonb,
   'Plano interno não remunera.', 'Rotina na Onda 3.'),

  (v_mod, 'PGP-011', 'Estágio da carteira derivado com precedência (Churn > Ativo > Go-live > Implantação > Contrato > Proposta > Lead)',
   'feliz', 'alta', 'aprovado', 'api',
   'Planejamento, seção 3 (tabela de estágio derivado)',
   'O estágio não é gravado: é calculado de subscriptions, contratos, onboarding e leads. A precedência precisa ser estável para o funil não mudar sozinho.',
   'Função parceiro_estagio_tenant (Onda 2).',
   '[{"ordem":1,"acao":"Tenant cancelado que também tem contrato assinado","resultado_esperado":"Churn"},
     {"ordem":2,"acao":"Tenant ativo há mais de 30 dias após go-live","resultado_esperado":"Ativo"},
     {"ordem":3,"acao":"Lead em negociação sem tenant","resultado_esperado":"Proposta"}]'::jsonb,
   'Um estágio por conta, pela precedência documentada.', 'Rotina na Onda 2.'),

  (v_mod, 'PGP-012', 'Fechamento de competência é idempotente e respeita 25/10',
   'excecao', 'critica', 'aprovado', 'api',
   'Mockup (fecha dia 25, paga até dia 10)',
   'Rodar o fechamento duas vezes na mesma competência não duplica comissão; o status segue previsto → fechado → pago/retido.',
   'Função parceiro_fechar_competencia (Onda 3).',
   '[{"ordem":1,"acao":"Fechar a mesma competência duas vezes","resultado_esperado":"Mesmo número de linhas, mesmos valores"}]'::jsonb,
   'Fechar duas vezes = fechar uma vez.', 'Rotina na Onda 3.'),

  (v_mod, 'PGP-013', 'Setup do implantador gera comissão por evento quando o onboarding do cliente conclui',
   'feliz', 'alta', 'aprovado', 'api',
   'Decisão do dono do produto (03/09/2026)',
   'Quando o cliente atendido por um implantador conclui o onboarding, o fechamento gera uma comissão do tipo evento com o valor configurado em parceiro_eventos_remuneracao.',
   'Onda 3.',
   '[{"ordem":1,"acao":"Tenant com implantador_parceiro_id conclui onboarding","resultado_esperado":"Uma comissão tipo evento/setup_concluido, valor da tabela"}]'::jsonb,
   'Setup pago pela tabela, uma vez por cliente.', 'Rotina na Onda 3.'),

  (v_mod, 'PGP-014', 'Lead da casa recebe sugestão de parceiro por proximidade e a atribuição fica marcada como casa',
   'feliz', 'media', 'aprovado', 'api',
   'Decisão do dono do produto (03/09/2026); planejamento seção 3.1',
   'Lead sem link de origem recebe até 5 parceiros ativos sugeridos (mesma cidade → raio → UF). Ao encaminhar, leads.atribuicao = casa, distinto de link.',
   'Função parceiros_sugerir_para_lead (Onda 3).',
   '[{"ordem":1,"acao":"Sugerir para lead em cidade com parceiro ativo","resultado_esperado":"Parceiro da cidade em primeiro"},
     {"ordem":2,"acao":"Encaminhar lead ao parceiro","resultado_esperado":"atribuicao = casa"}]'::jsonb,
   'Proximidade ordena; atribuição registra a origem.', 'Rotina na Onda 3.'),

  (v_mod, 'PGP-015', 'Link ?ref= grava a origem no lead da landing, no checkout e no tenant provisionado',
   'feliz', 'alta', 'aprovado', 'api',
   'Planejamento, seção 2.6',
   'O código do link viaja da landing (ref_codigo) ao checkout (metadata) e ao webhook, que grava parceiro_id no tenant. Sem isso, a carteira do parceiro fica vazia.',
   'Onda 4.',
   '[{"ordem":1,"acao":"Inserir landing_lead com ref_codigo de link válido","resultado_esperado":"Lead atribuído ao parceiro do link"}]'::jsonb,
   'Origem preservada de ponta a ponta.', 'Rotina na Onda 4.'),

  -- ══════════ C) TELA (e2e) ══════════

  (v_mod, 'PGP-020', 'SuperAdmin: aba Parceiros lista, cadastra e mostra o status inicial pelo tipo',
   'feliz', 'alta', 'aprovado', 'e2e',
   NULL,
   'O SuperAdmin cadastra um parceiro pela aba Parceiros e vê o status correto (indicador ativo; implantador pendente).',
   'Login de superadmin no site de teste.',
   '[{"ordem":1,"acao":"Abrir /admin e clicar na aba Parceiros","resultado_esperado":"Lista de parceiros e botão Novo parceiro"},
     {"ordem":2,"acao":"Cadastrar parceiro tipo implantador","resultado_esperado":"Aparece na lista com selo Pendente"}]'::jsonb,
   'Cadastro pela tela reflete a regra de aprovação.', 'Cypress: cypress/e2e/parceiros-admin.cy.ts'),

  (v_mod, 'PGP-021', 'SuperAdmin: aprovar parceiro pendente e vincular uma empresa à carteira',
   'feliz', 'alta', 'aprovado', 'e2e',
   NULL,
   'Aprovar muda o selo para Ativo; vincular uma empresa faz o parceiro aparecer como origem no detalhe da empresa.',
   'Parceiro pendente existente.',
   '[{"ordem":1,"acao":"Clicar Aprovar no parceiro pendente","resultado_esperado":"Selo Ativo"},
     {"ordem":2,"acao":"Vincular empresa ao parceiro","resultado_esperado":"Empresa listada na carteira; detalhe da empresa mostra Parceiro de origem"}]'::jsonb,
   'Aprovação e vínculo visíveis nas duas telas.', 'Cypress: cypress/e2e/parceiros-admin.cy.ts'),

  (v_mod, 'PGP-030', 'Parceiro sem empresa loga pelo site e cai na Área do Parceiro, não no sistema',
   'feliz', 'critica', 'aprovado', 'e2e',
   'Planejamento, seção 2.4',
   'Usuário vinculado a um parceiro e sem profile de tenant entra em /parceiros/entrar e é levado a /parceiro; nunca vê o menu do sistema.',
   'Usuário-parceiro semeado no staging (Onda 2).',
   '[{"ordem":1,"acao":"Login em /parceiros/entrar","resultado_esperado":"Redireciona para /parceiro com cabeçalho do parceiro"}]'::jsonb,
   'Portal próprio, fora do sistema.', 'Onda 2.'),

  (v_mod, 'PGP-031', 'Portal: copiar o link de indicação',
   'feliz', 'media', 'aprovado', 'e2e',
   NULL, 'O botão Copiar coloca o link completo (com o código do parceiro) na área de transferência e confirma.',
   'Parceiro ativo logado.',
   '[{"ordem":1,"acao":"Clicar Copiar","resultado_esperado":"Texto Copiado e link contém ?ref=CODIGO"}]'::jsonb,
   'Link copiado com o código.', 'Onda 2.'),

  (v_mod, 'PGP-032', 'Portal: carteira lista as empresas originadas com estágio e exporta CSV',
   'feliz', 'media', 'aprovado', 'e2e',
   NULL, 'A carteira mostra só as empresas do parceiro, com plano, MRR, estágio e comissão, e o botão Exportar gera CSV.',
   'Parceiro com ao menos uma empresa vinculada.',
   '[{"ordem":1,"acao":"Abrir /parceiro","resultado_esperado":"Tabela com as empresas do parceiro"},
     {"ordem":2,"acao":"Clicar Exportar","resultado_esperado":"CSV com as mesmas linhas"}]'::jsonb,
   'Só a própria carteira, exportável.', 'Onda 2.')

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'PGP: % casos antes, % depois.', v_antes, v_depois;
END $doc$;

-- ───────────────────────── 20260904110000_parceiros_fundacao ─────────────────────────
-- =====================================================================
-- PROGRAMA DE PARCEIROS · ONDA 1 · fundação de dados + gestão no SuperAdmin
--
-- Cria a entidade "parceiro comercial" (indicador, representante,
-- implantador, clínica, contabilidade), seus usuários, links de indicação,
-- níveis por trilha, remuneração por evento e a tabela de comissões
-- (o motor de fechamento entra na Onda 3). Liga a origem do cliente ao
-- parceiro em tenants e leads. Nada aqui altera dado existente: só cria.
--
-- Decisões do dono do produto (03/09/2026):
--   * indicador aprovado automaticamente; demais tipos, manualmente;
--   * implantador ganha pelo setup, valor configurável (tabela de eventos);
--   * leads da casa recebem sugestão por proximidade (Onda 3; aqui só as
--     colunas de localização do parceiro);
--   * a aba Afiliados do Marketplace migra para este programa (Onda 2).
-- Planejamento: docs/PLANEJAMENTO_PORTAL_PARCEIRO.md
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) Níveis por trilha
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.parceiro_niveis (
  id                            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trilha                        text NOT NULL,
  nome                          text NOT NULL,
  ordem                         int  NOT NULL DEFAULT 1,
  mrr_minimo_cents              bigint NOT NULL DEFAULT 0,
  percentual_link               numeric(5,2) NOT NULL DEFAULT 25.00,
  percentual_casa               numeric(5,2) NOT NULL DEFAULT 25.00,
  bonus_renovacao_multiplicador numeric(4,2) NOT NULL DEFAULT 2.00,
  ativo                         boolean NOT NULL DEFAULT true,
  created_at                    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (trilha, nome)
);
COMMENT ON TABLE public.parceiro_niveis IS
  'Níveis do programa de parceiros por trilha: faixa de MRR sob atendimento e percentuais. Editável pelo SuperAdmin.';

-- ---------------------------------------------------------------------
-- 2) Parceiros
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.parceiros (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo                      text NOT NULL UNIQUE,
  nome                        text NOT NULL,
  tipo_pessoa                 text NOT NULL DEFAULT 'pj'
                              CHECK (tipo_pessoa IN ('pf','pj')),
  documento                   text,
  tipo_parceiro               text NOT NULL DEFAULT 'indicador'
                              CHECK (tipo_parceiro IN ('indicador','representante','implantador','clinica','contabilidade')),
  email                       text,
  telefone                    text,
  cidade                      text,
  uf                          text,
  cep                         text,
  lat                         numeric(9,6),
  lng                         numeric(9,6),
  raio_atuacao_km             int  NOT NULL DEFAULT 50,
  trilha                      text NOT NULL DEFAULT 'operador',
  nivel_id                    uuid REFERENCES public.parceiro_niveis(id) ON DELETE SET NULL,
  percentual_comissao         numeric(5,2),          -- override opcional do nível
  status                      text NOT NULL DEFAULT 'pendente'
                              CHECK (status IN ('pendente','ativo','suspenso','encerrado')),
  aprovacao                   text NOT NULL DEFAULT 'manual'
                              CHECK (aprovacao IN ('automatica','manual')),
  aprovado_em                 timestamptz,
  aprovado_por                uuid,
  motivo_recusa               text,
  parceiro_desde              date NOT NULL DEFAULT CURRENT_DATE,
  pix_chave                   text,
  marketplace_profissional_id uuid REFERENCES public.marketplace_profissionais(id) ON DELETE SET NULL,
  aceite_termos_em            timestamptz,
  observacoes                 text,
  created_by                  uuid,
  created_at                  timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.parceiros IS
  'Parceiro comercial YourEyes (indicador, representante, implantador, clínica, contabilidade). Não é tenant nem usuário de tenant; pode ser também profissional do Marketplace.';
CREATE INDEX IF NOT EXISTS idx_parceiros_status ON public.parceiros(status);
CREATE INDEX IF NOT EXISTS idx_parceiros_uf_cidade ON public.parceiros(uf, cidade);

CREATE TABLE IF NOT EXISTS public.parceiro_usuarios (
  parceiro_id uuid NOT NULL REFERENCES public.parceiros(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL,
  papel       text NOT NULL DEFAULT 'dono' CHECK (papel IN ('dono','leitura')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (parceiro_id, user_id),
  UNIQUE (user_id)
);
COMMENT ON TABLE public.parceiro_usuarios IS
  'Vínculo entre um usuário (auth.users) e um parceiro. Um usuário pertence a no máximo um parceiro.';

CREATE TABLE IF NOT EXISTS public.parceiro_links (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parceiro_id uuid NOT NULL REFERENCES public.parceiros(id) ON DELETE CASCADE,
  codigo      text NOT NULL UNIQUE,
  campanha    text NOT NULL DEFAULT 'principal',
  ativo       boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_parceiro_links_parceiro ON public.parceiro_links(parceiro_id);

CREATE TABLE IF NOT EXISTS public.parceiro_link_cliques (
  id          bigserial PRIMARY KEY,
  link_id     uuid NOT NULL REFERENCES public.parceiro_links(id) ON DELETE CASCADE,
  clicado_em  timestamptz NOT NULL DEFAULT now(),
  ua_hash     text
);
COMMENT ON TABLE public.parceiro_link_cliques IS
  'Cliques no link de indicação. Sem IP e sem dado de pessoa: só o link, a hora e um hash do navegador.';
CREATE INDEX IF NOT EXISTS idx_parceiro_link_cliques_link ON public.parceiro_link_cliques(link_id, clicado_em);

CREATE TABLE IF NOT EXISTS public.parceiro_eventos_remuneracao (
  id                               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trilha                           text NOT NULL DEFAULT 'operador',
  tipo_parceiro                    text NOT NULL
                                   CHECK (tipo_parceiro IN ('indicador','representante','implantador','clinica','contabilidade')),
  evento                           text NOT NULL
                                   CHECK (evento IN ('setup_concluido','go_live','renovacao')),
  valor_fixo_cents                 bigint NOT NULL DEFAULT 0,
  percentual_primeira_mensalidade  numeric(5,2) NOT NULL DEFAULT 0,
  ativo                            boolean NOT NULL DEFAULT true,
  created_at                       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (trilha, tipo_parceiro, evento)
);
COMMENT ON TABLE public.parceiro_eventos_remuneracao IS
  'Remuneração por evento (setup, go-live, renovação) por trilha e tipo de parceiro. Editável pelo SuperAdmin; o motor de fechamento lê daqui, nunca de literal.';

CREATE TABLE IF NOT EXISTS public.parceiro_comissoes (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parceiro_id  uuid NOT NULL REFERENCES public.parceiros(id) ON DELETE CASCADE,
  tenant_id    uuid REFERENCES public.tenants(id) ON DELETE SET NULL,
  competencia  date NOT NULL,                         -- dia 1 do mês
  tipo         text NOT NULL DEFAULT 'recorrente'
               CHECK (tipo IN ('recorrente','bonus_renovacao','evento','ajuste')),
  evento       text,
  base_cents   bigint NOT NULL DEFAULT 0,
  percentual   numeric(5,2),
  valor_cents  bigint NOT NULL DEFAULT 0,
  status       text NOT NULL DEFAULT 'previsto'
               CHECK (status IN ('previsto','fechado','pago','retido')),
  fechado_em   timestamptz,
  pago_em      timestamptz,
  observacao   text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_parceiro_comissoes_parceiro_comp
  ON public.parceiro_comissoes(parceiro_id, competencia);
CREATE UNIQUE INDEX IF NOT EXISTS uq_parceiro_comissoes_recorrente
  ON public.parceiro_comissoes(parceiro_id, tenant_id, competencia, tipo, coalesce(evento,''));

-- ---------------------------------------------------------------------
-- 3) Origem nas tabelas existentes (tudo IF NOT EXISTS, SET NULL)
-- ---------------------------------------------------------------------
ALTER TABLE public.tenants
  ADD COLUMN IF NOT EXISTS parceiro_id             uuid REFERENCES public.parceiros(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS parceiro_link_id        uuid REFERENCES public.parceiro_links(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS originado_em            timestamptz,
  ADD COLUMN IF NOT EXISTS implantador_parceiro_id uuid REFERENCES public.parceiros(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_tenants_parceiro ON public.tenants(parceiro_id);

ALTER TABLE public.leads
  ADD COLUMN IF NOT EXISTS parceiro_id             uuid REFERENCES public.parceiros(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS parceiro_link_id        uuid REFERENCES public.parceiro_links(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS atribuicao              text CHECK (atribuicao IN ('link','casa')),
  ADD COLUMN IF NOT EXISTS implantador_parceiro_id uuid REFERENCES public.parceiros(id) ON DELETE SET NULL;

ALTER TABLE public.landing_leads ADD COLUMN IF NOT EXISTS ref_codigo text;
ALTER TABLE public.assinaturas   ADD COLUMN IF NOT EXISTS ref_codigo text;
ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS ciclo_meses  int,
  ADD COLUMN IF NOT EXISTS ciclo_inicio date,
  ADD COLUMN IF NOT EXISTS ciclo_fim    date;

-- ---------------------------------------------------------------------
-- 4) Regras automáticas: código, status inicial por tipo, link principal
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.parceiro_gerar_codigo(p_nome text)
RETURNS text
LANGUAGE plpgsql
SET search_path = public
AS $parceiro_gerar_codigo$
DECLARE v_base text; v_cod text; v_n int := 0;
BEGIN
  v_base := upper(regexp_replace(translate(coalesce(p_nome,'PARCEIRO'),
             'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
             'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'), '[^A-Za-z0-9]', '', 'g'));
  v_base := left(coalesce(nullif(v_base,''),'PARCEIRO'), 14);
  v_cod := v_base;
  WHILE EXISTS (SELECT 1 FROM public.parceiros WHERE codigo = v_cod)
     OR EXISTS (SELECT 1 FROM public.parceiro_links WHERE codigo = v_cod) LOOP
    v_n := v_n + 1; v_cod := v_base || v_n::text;
  END LOOP;
  RETURN v_cod;
END $parceiro_gerar_codigo$;

CREATE OR REPLACE FUNCTION public.parceiros_antes_inserir()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $parceiros_antes_inserir$
BEGIN
  IF NEW.codigo IS NULL OR btrim(NEW.codigo) = '' THEN
    NEW.codigo := public.parceiro_gerar_codigo(NEW.nome);
  ELSE
    NEW.codigo := upper(regexp_replace(NEW.codigo, '[^A-Za-z0-9-]', '', 'g'));
  END IF;
  -- Decisão 03/09/2026: indicador entra sozinho; os demais esperam aprovação.
  IF NEW.tipo_parceiro = 'indicador' THEN
    NEW.aprovacao := 'automatica';
    IF NEW.status = 'pendente' THEN
      NEW.status := 'ativo'; NEW.aprovado_em := now();
    END IF;
  ELSE
    NEW.aprovacao := 'manual';
  END IF;
  IF NEW.nivel_id IS NULL THEN
    SELECT id INTO NEW.nivel_id FROM public.parceiro_niveis
    WHERE trilha = NEW.trilha AND ativo ORDER BY ordem LIMIT 1;
  END IF;
  RETURN NEW;
END $parceiros_antes_inserir$;

DROP TRIGGER IF EXISTS trg_parceiros_antes_inserir ON public.parceiros;
CREATE TRIGGER trg_parceiros_antes_inserir
  BEFORE INSERT ON public.parceiros
  FOR EACH ROW EXECUTE FUNCTION public.parceiros_antes_inserir();

CREATE OR REPLACE FUNCTION public.parceiros_depois_inserir()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $parceiros_depois_inserir$
BEGIN
  INSERT INTO public.parceiro_links (parceiro_id, codigo, campanha)
  VALUES (NEW.id, NEW.codigo, 'principal')
  ON CONFLICT (codigo) DO NOTHING;
  RETURN NEW;
END $parceiros_depois_inserir$;

DROP TRIGGER IF EXISTS trg_parceiros_depois_inserir ON public.parceiros;
CREATE TRIGGER trg_parceiros_depois_inserir
  AFTER INSERT ON public.parceiros
  FOR EACH ROW EXECUTE FUNCTION public.parceiros_depois_inserir();

CREATE OR REPLACE FUNCTION public.parceiros_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $parceiros_updated_at$
BEGIN NEW.updated_at := now(); RETURN NEW; END $parceiros_updated_at$;
DROP TRIGGER IF EXISTS trg_parceiros_updated_at ON public.parceiros;
CREATE TRIGGER trg_parceiros_updated_at BEFORE UPDATE ON public.parceiros
  FOR EACH ROW EXECUTE FUNCTION public.parceiros_updated_at();

-- ---------------------------------------------------------------------
-- 5) Quem é o parceiro do usuário logado
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.parceiro_meu_id()
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $parceiro_meu_id$
  SELECT pu.parceiro_id FROM public.parceiro_usuarios pu WHERE pu.user_id = auth.uid() LIMIT 1
$parceiro_meu_id$;
GRANT EXECUTE ON FUNCTION public.parceiro_meu_id() TO authenticated;

-- ---------------------------------------------------------------------
-- 6) RLS — parceiro lê o que é seu; superadmin tudo; escrita só por função
-- ---------------------------------------------------------------------
ALTER TABLE public.parceiro_niveis              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parceiros                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parceiro_usuarios            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parceiro_links               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parceiro_link_cliques        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parceiro_eventos_remuneracao ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parceiro_comissoes           ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS parceiro_niveis_leitura ON public.parceiro_niveis;
CREATE POLICY parceiro_niveis_leitura ON public.parceiro_niveis
  FOR SELECT TO authenticated USING (ativo OR public.is_superadmin(auth.uid()));
DROP POLICY IF EXISTS parceiro_niveis_superadmin ON public.parceiro_niveis;
CREATE POLICY parceiro_niveis_superadmin ON public.parceiro_niveis
  FOR ALL TO authenticated USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS parceiro_eventos_leitura ON public.parceiro_eventos_remuneracao;
CREATE POLICY parceiro_eventos_leitura ON public.parceiro_eventos_remuneracao
  FOR SELECT TO authenticated USING (public.parceiro_meu_id() IS NOT NULL OR public.is_superadmin(auth.uid()));
DROP POLICY IF EXISTS parceiro_eventos_superadmin ON public.parceiro_eventos_remuneracao;
CREATE POLICY parceiro_eventos_superadmin ON public.parceiro_eventos_remuneracao
  FOR ALL TO authenticated USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS parceiros_proprio ON public.parceiros;
CREATE POLICY parceiros_proprio ON public.parceiros
  FOR SELECT TO authenticated
  USING (id = public.parceiro_meu_id() OR public.is_superadmin(auth.uid()));
DROP POLICY IF EXISTS parceiros_superadmin ON public.parceiros;
CREATE POLICY parceiros_superadmin ON public.parceiros
  FOR ALL TO authenticated USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS parceiro_usuarios_proprio ON public.parceiro_usuarios;
CREATE POLICY parceiro_usuarios_proprio ON public.parceiro_usuarios
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR parceiro_id = public.parceiro_meu_id() OR public.is_superadmin(auth.uid()));
DROP POLICY IF EXISTS parceiro_usuarios_superadmin ON public.parceiro_usuarios;
CREATE POLICY parceiro_usuarios_superadmin ON public.parceiro_usuarios
  FOR ALL TO authenticated USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS parceiro_links_proprio ON public.parceiro_links;
CREATE POLICY parceiro_links_proprio ON public.parceiro_links
  FOR SELECT TO authenticated
  USING (parceiro_id = public.parceiro_meu_id() OR public.is_superadmin(auth.uid()));
DROP POLICY IF EXISTS parceiro_links_superadmin ON public.parceiro_links;
CREATE POLICY parceiro_links_superadmin ON public.parceiro_links
  FOR ALL TO authenticated USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS parceiro_link_cliques_proprio ON public.parceiro_link_cliques;
CREATE POLICY parceiro_link_cliques_proprio ON public.parceiro_link_cliques
  FOR SELECT TO authenticated
  USING (public.is_superadmin(auth.uid())
         OR EXISTS (SELECT 1 FROM public.parceiro_links l
                    WHERE l.id = link_id AND l.parceiro_id = public.parceiro_meu_id()));

DROP POLICY IF EXISTS parceiro_comissoes_proprio ON public.parceiro_comissoes;
CREATE POLICY parceiro_comissoes_proprio ON public.parceiro_comissoes
  FOR SELECT TO authenticated
  USING (parceiro_id = public.parceiro_meu_id() OR public.is_superadmin(auth.uid()));
DROP POLICY IF EXISTS parceiro_comissoes_superadmin ON public.parceiro_comissoes;
CREATE POLICY parceiro_comissoes_superadmin ON public.parceiro_comissoes
  FOR ALL TO authenticated USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()));

-- Leitura pelo app passa pela RLS acima; a escrita é só por função.
GRANT SELECT ON public.parceiros, public.parceiro_usuarios, public.parceiro_links,
  public.parceiro_link_cliques, public.parceiro_niveis, public.parceiro_eventos_remuneracao,
  public.parceiro_comissoes TO authenticated;
GRANT ALL ON public.parceiros, public.parceiro_usuarios, public.parceiro_links,
  public.parceiro_link_cliques, public.parceiro_niveis, public.parceiro_eventos_remuneracao,
  public.parceiro_comissoes TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.parceiro_link_cliques_id_seq TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- 7) Funções do SuperAdmin
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.superadmin_parceiros_list()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiros_list$
DECLARE result jsonb;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  SELECT jsonb_agg(row_to_json(x) ORDER BY x.status = 'pendente' DESC, x.created_at DESC) INTO result
  FROM (
    SELECT p.id, p.codigo, p.nome, p.tipo_pessoa, p.documento, p.tipo_parceiro, p.email, p.telefone,
           p.cidade, p.uf, p.cep, p.raio_atuacao_km, p.trilha, p.nivel_id, n.nome AS nivel_nome,
           p.percentual_comissao, p.status, p.aprovacao, p.aprovado_em, p.motivo_recusa,
           p.parceiro_desde, p.pix_chave, p.marketplace_profissional_id, p.observacoes, p.created_at,
           (SELECT count(*) FROM public.tenants t WHERE t.parceiro_id = p.id)            AS total_clientes,
           (SELECT count(*) FROM public.tenants t WHERE t.implantador_parceiro_id = p.id) AS total_implantacoes,
           (SELECT count(*) FROM public.leads l WHERE l.parceiro_id = p.id AND l.deleted_at IS NULL) AS total_leads,
           (SELECT count(*) FROM public.parceiro_links k WHERE k.parceiro_id = p.id AND k.ativo) AS total_links,
           (SELECT string_agg(u.email, ', ') FROM public.parceiro_usuarios pu
              JOIN auth.users u ON u.id = pu.user_id WHERE pu.parceiro_id = p.id) AS usuarios
    FROM public.parceiros p
    LEFT JOIN public.parceiro_niveis n ON n.id = p.nivel_id
  ) x;
  RETURN coalesce(result, '[]'::jsonb);
END $superadmin_parceiros_list$;
GRANT EXECUTE ON FUNCTION public.superadmin_parceiros_list() TO authenticated;

CREATE OR REPLACE FUNCTION public.superadmin_parceiro_salvar(_dados jsonb)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiro_salvar$
DECLARE v_id uuid;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF coalesce(btrim(_dados->>'nome'),'') = '' THEN RAISE EXCEPTION 'Nome é obrigatório'; END IF;
  v_id := nullif(_dados->>'id','')::uuid;

  IF v_id IS NULL THEN
    INSERT INTO public.parceiros
      (codigo, nome, tipo_pessoa, documento, tipo_parceiro, email, telefone, cidade, uf, cep,
       raio_atuacao_km, trilha, percentual_comissao, pix_chave, observacoes, created_by)
    VALUES
      (nullif(_dados->>'codigo',''), _dados->>'nome', coalesce(_dados->>'tipo_pessoa','pj'),
       nullif(_dados->>'documento',''), coalesce(_dados->>'tipo_parceiro','indicador'),
       nullif(_dados->>'email',''), nullif(_dados->>'telefone',''), nullif(_dados->>'cidade',''),
       nullif(upper(_dados->>'uf'),''), nullif(_dados->>'cep',''),
       coalesce((_dados->>'raio_atuacao_km')::int, 50), coalesce(_dados->>'trilha','operador'),
       nullif(_dados->>'percentual_comissao','')::numeric, nullif(_dados->>'pix_chave',''),
       nullif(_dados->>'observacoes',''), auth.uid())
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.parceiros SET
      nome = _dados->>'nome',
      tipo_pessoa = coalesce(_dados->>'tipo_pessoa', tipo_pessoa),
      documento = nullif(_dados->>'documento',''),
      tipo_parceiro = coalesce(_dados->>'tipo_parceiro', tipo_parceiro),
      email = nullif(_dados->>'email',''), telefone = nullif(_dados->>'telefone',''),
      cidade = nullif(_dados->>'cidade',''), uf = nullif(upper(_dados->>'uf'),''),
      cep = nullif(_dados->>'cep',''),
      raio_atuacao_km = coalesce((_dados->>'raio_atuacao_km')::int, raio_atuacao_km),
      trilha = coalesce(_dados->>'trilha', trilha),
      nivel_id = coalesce(nullif(_dados->>'nivel_id','')::uuid, nivel_id),
      percentual_comissao = nullif(_dados->>'percentual_comissao','')::numeric,
      pix_chave = nullif(_dados->>'pix_chave',''),
      observacoes = nullif(_dados->>'observacoes','')
    WHERE id = v_id;
  END IF;
  RETURN v_id;
END $superadmin_parceiro_salvar$;
GRANT EXECUTE ON FUNCTION public.superadmin_parceiro_salvar(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.superadmin_parceiro_status(_parceiro_id uuid, _status text, _motivo text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiro_status$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF _status NOT IN ('pendente','ativo','suspenso','encerrado') THEN RAISE EXCEPTION 'Status inválido: %', _status; END IF;
  UPDATE public.parceiros SET
    status = _status,
    aprovado_em = CASE WHEN _status = 'ativo' THEN coalesce(aprovado_em, now()) ELSE aprovado_em END,
    aprovado_por = CASE WHEN _status = 'ativo' THEN coalesce(aprovado_por, auth.uid()) ELSE aprovado_por END,
    motivo_recusa = CASE WHEN _status IN ('suspenso','encerrado') THEN _motivo ELSE NULL END
  WHERE id = _parceiro_id;
END $superadmin_parceiro_status$;
GRANT EXECUTE ON FUNCTION public.superadmin_parceiro_status(uuid, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.superadmin_parceiro_vincular_usuario(_parceiro_id uuid, _email text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiro_vincular_usuario$
DECLARE v_user uuid;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  SELECT id INTO v_user FROM auth.users WHERE lower(email) = lower(btrim(_email)) LIMIT 1;
  IF v_user IS NULL THEN
    RETURN 'Nenhum usuário com esse e-mail. Crie a conta primeiro (Área do Parceiro, Onda 2) ou convide pelo painel de usuários.';
  END IF;
  INSERT INTO public.parceiro_usuarios (parceiro_id, user_id)
  VALUES (_parceiro_id, v_user)
  ON CONFLICT (user_id) DO UPDATE SET parceiro_id = EXCLUDED.parceiro_id;
  RETURN 'ok';
END $superadmin_parceiro_vincular_usuario$;
GRANT EXECUTE ON FUNCTION public.superadmin_parceiro_vincular_usuario(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.superadmin_parceiro_desvincular_usuario(_user_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiro_desvincular_usuario$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  DELETE FROM public.parceiro_usuarios WHERE user_id = _user_id;
END $superadmin_parceiro_desvincular_usuario$;
GRANT EXECUTE ON FUNCTION public.superadmin_parceiro_desvincular_usuario(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.superadmin_parceiro_vincular_tenant(
  _tenant_id uuid, _parceiro_id uuid DEFAULT NULL, _implantador_id uuid DEFAULT NULL, _manter_ausente boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiro_vincular_tenant$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  -- _manter_ausente = true: só altera o campo que veio preenchido
  UPDATE public.tenants SET
    parceiro_id = CASE WHEN _manter_ausente AND _parceiro_id IS NULL THEN parceiro_id ELSE _parceiro_id END,
    implantador_parceiro_id = CASE WHEN _manter_ausente AND _implantador_id IS NULL THEN implantador_parceiro_id ELSE _implantador_id END,
    originado_em = CASE WHEN _parceiro_id IS NOT NULL THEN coalesce(originado_em, now()) ELSE originado_em END
  WHERE id = _tenant_id;
END $superadmin_parceiro_vincular_tenant$;
GRANT EXECUTE ON FUNCTION public.superadmin_parceiro_vincular_tenant(uuid, uuid, uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.superadmin_parceiro_link_criar(_parceiro_id uuid, _campanha text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiro_link_criar$
DECLARE v_cod text; v_suf text;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  v_suf := upper(regexp_replace(coalesce(_campanha,''), '[^A-Za-z0-9]', '', 'g'));
  IF v_suf = '' THEN RAISE EXCEPTION 'Informe o nome da campanha'; END IF;
  SELECT p.codigo || '-' || left(v_suf, 12) INTO v_cod FROM public.parceiros p WHERE p.id = _parceiro_id;
  IF v_cod IS NULL THEN RAISE EXCEPTION 'Parceiro não encontrado'; END IF;
  INSERT INTO public.parceiro_links (parceiro_id, codigo, campanha) VALUES (_parceiro_id, v_cod, _campanha)
  ON CONFLICT (codigo) DO UPDATE SET ativo = true, campanha = EXCLUDED.campanha;
  RETURN v_cod;
END $superadmin_parceiro_link_criar$;
GRANT EXECUTE ON FUNCTION public.superadmin_parceiro_link_criar(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.superadmin_parceiro_link_ativo(_link_id uuid, _ativo boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiro_link_ativo$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  UPDATE public.parceiro_links SET ativo = _ativo WHERE id = _link_id AND campanha <> 'principal';
END $superadmin_parceiro_link_ativo$;
GRANT EXECUTE ON FUNCTION public.superadmin_parceiro_link_ativo(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.superadmin_parceiro_detalhe(_parceiro_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiro_detalhe$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  RETURN jsonb_build_object(
    'links', coalesce((SELECT jsonb_agg(jsonb_build_object(
                'id', k.id, 'codigo', k.codigo, 'campanha', k.campanha, 'ativo', k.ativo,
                'cliques', (SELECT count(*) FROM public.parceiro_link_cliques c WHERE c.link_id = k.id),
                'leads', (SELECT count(*) FROM public.leads l WHERE l.parceiro_link_id = k.id AND l.deleted_at IS NULL))
              ORDER BY k.campanha = 'principal' DESC, k.created_at)
              FROM public.parceiro_links k WHERE k.parceiro_id = _parceiro_id), '[]'::jsonb),
    'clientes', coalesce((SELECT jsonb_agg(jsonb_build_object(
                'id', t.id, 'nome', t.nome, 'slug', t.slug, 'ativo', t.ativo, 'originado_em', t.originado_em,
                'papel', CASE WHEN t.parceiro_id = _parceiro_id AND t.implantador_parceiro_id = _parceiro_id THEN 'origem+implantacao'
                              WHEN t.parceiro_id = _parceiro_id THEN 'origem' ELSE 'implantacao' END,
                'plano', (SELECT pl.name FROM public.subscriptions s JOIN public.plans pl ON pl.id = s.plan_id WHERE s.tenant_id = t.id),
                'status_assinatura', (SELECT s.status FROM public.subscriptions s WHERE s.tenant_id = t.id))
              ORDER BY t.nome)
              FROM public.tenants t
              WHERE t.parceiro_id = _parceiro_id OR t.implantador_parceiro_id = _parceiro_id), '[]'::jsonb),
    'leads', coalesce((SELECT jsonb_agg(jsonb_build_object(
                'id', l.id, 'nome', l.nome, 'empresa', l.empresa, 'status', l.status, 'atribuicao', l.atribuicao, 'created_at', l.created_at)
              ORDER BY l.created_at DESC)
              FROM public.leads l WHERE l.parceiro_id = _parceiro_id AND l.deleted_at IS NULL), '[]'::jsonb),
    'usuarios', coalesce((SELECT jsonb_agg(jsonb_build_object('user_id', pu.user_id, 'email', u.email, 'papel', pu.papel))
              FROM public.parceiro_usuarios pu JOIN auth.users u ON u.id = pu.user_id
              WHERE pu.parceiro_id = _parceiro_id), '[]'::jsonb)
  );
END $superadmin_parceiro_detalhe$;
GRANT EXECUTE ON FUNCTION public.superadmin_parceiro_detalhe(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.superadmin_parceiros_tenants_list()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiros_tenants_list$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object(
      'id', t.id, 'nome', t.nome, 'slug', t.slug, 'ativo', t.ativo,
      'parceiro_id', t.parceiro_id, 'parceiro_nome', p.nome,
      'implantador_parceiro_id', t.implantador_parceiro_id, 'implantador_nome', i.nome,
      'originado_em', t.originado_em) ORDER BY t.nome)
    FROM public.tenants t
    LEFT JOIN public.parceiros p ON p.id = t.parceiro_id
    LEFT JOIN public.parceiros i ON i.id = t.implantador_parceiro_id), '[]'::jsonb);
END $superadmin_parceiros_tenants_list$;
GRANT EXECUTE ON FUNCTION public.superadmin_parceiros_tenants_list() TO authenticated;

CREATE OR REPLACE FUNCTION public.superadmin_parceiro_eventos_salvar(_itens jsonb)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiro_eventos_salvar$
DECLARE r jsonb; v_n int := 0;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  FOR r IN SELECT * FROM jsonb_array_elements(coalesce(_itens,'[]'::jsonb)) LOOP
    INSERT INTO public.parceiro_eventos_remuneracao
      (trilha, tipo_parceiro, evento, valor_fixo_cents, percentual_primeira_mensalidade, ativo)
    VALUES (coalesce(r->>'trilha','operador'), r->>'tipo_parceiro', r->>'evento',
            coalesce((r->>'valor_fixo_cents')::bigint, 0),
            coalesce((r->>'percentual_primeira_mensalidade')::numeric, 0),
            coalesce((r->>'ativo')::boolean, true))
    ON CONFLICT (trilha, tipo_parceiro, evento) DO UPDATE SET
      valor_fixo_cents = EXCLUDED.valor_fixo_cents,
      percentual_primeira_mensalidade = EXCLUDED.percentual_primeira_mensalidade,
      ativo = EXCLUDED.ativo;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $superadmin_parceiro_eventos_salvar$;
GRANT EXECUTE ON FUNCTION public.superadmin_parceiro_eventos_salvar(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.superadmin_parceiro_niveis_salvar(_itens jsonb)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiro_niveis_salvar$
DECLARE r jsonb; v_n int := 0;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  FOR r IN SELECT * FROM jsonb_array_elements(coalesce(_itens,'[]'::jsonb)) LOOP
    INSERT INTO public.parceiro_niveis
      (trilha, nome, ordem, mrr_minimo_cents, percentual_link, percentual_casa, bonus_renovacao_multiplicador, ativo)
    VALUES (coalesce(r->>'trilha','operador'), r->>'nome', coalesce((r->>'ordem')::int, 1),
            coalesce((r->>'mrr_minimo_cents')::bigint, 0),
            coalesce((r->>'percentual_link')::numeric, 25), coalesce((r->>'percentual_casa')::numeric, 25),
            coalesce((r->>'bonus_renovacao_multiplicador')::numeric, 2), coalesce((r->>'ativo')::boolean, true))
    ON CONFLICT (trilha, nome) DO UPDATE SET
      ordem = EXCLUDED.ordem, mrr_minimo_cents = EXCLUDED.mrr_minimo_cents,
      percentual_link = EXCLUDED.percentual_link, percentual_casa = EXCLUDED.percentual_casa,
      bonus_renovacao_multiplicador = EXCLUDED.bonus_renovacao_multiplicador, ativo = EXCLUDED.ativo;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $superadmin_parceiro_niveis_salvar$;
GRANT EXECUTE ON FUNCTION public.superadmin_parceiro_niveis_salvar(jsonb) TO authenticated;

-- ---------------------------------------------------------------------
-- 8) Sementes de configuração (valores do mockup; o SuperAdmin edita)
-- ---------------------------------------------------------------------
INSERT INTO public.parceiro_niveis (trilha, nome, ordem, mrr_minimo_cents, percentual_link, percentual_casa)
VALUES ('operador', 'Visão',    1,       0, 25.00, 25.00),
       ('operador', 'Diamante', 2, 1200000, 30.00, 30.00)
ON CONFLICT (trilha, nome) DO NOTHING;

INSERT INTO public.parceiro_eventos_remuneracao (trilha, tipo_parceiro, evento, valor_fixo_cents, percentual_primeira_mensalidade)
VALUES ('operador', 'implantador',   'setup_concluido', 0, 100.00),
       ('operador', 'implantador',   'go_live',         0,   0.00),
       ('operador', 'representante', 'go_live',         0,   0.00)
ON CONFLICT (trilha, tipo_parceiro, evento) DO NOTHING;

-- ---------------------------------------------------------------------
-- 9) Semente de teste — SÓ onde existe a Empresa Staging LTDA (fictícia).
--    Em produção e em banco vazio, não faz nada.
-- ---------------------------------------------------------------------
DO $seed$
DECLARE v_staging uuid; v_p1 uuid; v_p2 uuid;
BEGIN
  SELECT id INTO v_staging FROM public.tenants WHERE nome = 'Empresa Staging LTDA' LIMIT 1;
  IF v_staging IS NULL THEN
    RAISE NOTICE 'Parceiros: sem Empresa Staging neste ambiente — semente de parceiros pulada.';
    RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.parceiros WHERE codigo = 'CLINICASTAGING') THEN
    INSERT INTO public.parceiros (codigo, nome, tipo_pessoa, documento, tipo_parceiro, email, cidade, uf, cep, status)
    VALUES ('CLINICASTAGING', 'Clínica Staging SST', 'pj', '00.000.000/0001-91', 'clinica',
            'clinica.staging@exemplo.test', 'Pato Branco', 'PR', '85501-000', 'ativo')
    RETURNING id INTO v_p1;
    UPDATE public.parceiros SET aprovado_em = now() WHERE id = v_p1;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.parceiros WHERE codigo = 'CONTABILSTAGING') THEN
    INSERT INTO public.parceiros (codigo, nome, tipo_pessoa, documento, tipo_parceiro, email, cidade, uf, cep)
    VALUES ('CONTABILSTAGING', 'Contábil Staging', 'pj', '00.000.000/0002-72', 'implantador',
            'contabil.staging@exemplo.test', 'Francisco Beltrão', 'PR', '85601-000')
    RETURNING id INTO v_p2;
  END IF;

  SELECT id INTO v_p1 FROM public.parceiros WHERE codigo = 'CLINICASTAGING';
  UPDATE public.tenants SET parceiro_id = v_p1, originado_em = coalesce(originado_em, now())
  WHERE id = v_staging AND parceiro_id IS NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Parceiros: semente de teste não aplicada (%).', SQLERRM;
END $seed$;

-- ───────────────────────── 20260904120000_parceiros_qa_rotinas ─────────────────────────
-- ============================================================================
-- QA PGP — rotinas dos casos do Programa de Parceiros que a Onda 1 já torna
-- testáveis (PGP-001..006). Os demais (010-015) seguem documentados e
-- aparecem como nao_implementado até as Ondas 2-4; os e2e ficam no Cypress.
--
-- Padrão da casa: sondas de escrita com linhas sintéticas (código QA-*)
-- apagadas ao final + auditorias somente leitura em pg_class/pg_policies/
-- information_schema. Nenhuma funcionalidade é alterada.
-- ============================================================================

-- PGP-001 — status inicial por tipo
CREATE OR REPLACE FUNCTION public.qa_caso_pgp_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_a uuid; v_b uuid; sa text; aa text; sb text; ab text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Inserir indicador e implantador sem status';
  r.esperado := 'Indicador ativo/automatica; implantador pendente/manual';
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro) VALUES ('QA-PGP001-A', 'QA Indicador', 'indicador') RETURNING id INTO v_a;
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro) VALUES ('QA-PGP001-B', 'QA Implantador', 'implantador') RETURNING id INTO v_b;
  SELECT status, aprovacao INTO sa, aa FROM public.parceiros WHERE id = v_a;
  SELECT status, aprovacao INTO sb, ab FROM public.parceiros WHERE id = v_b;
  DELETE FROM public.parceiros WHERE id IN (v_a, v_b);
  IF sa = 'ativo' AND aa = 'automatica' AND sb = 'pendente' AND ab = 'manual' THEN
    r.situacao := 'passou'; r.obtido := format('indicador %s/%s; implantador %s/%s', sa, aa, sb, ab);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('indicador %s/%s; implantador %s/%s — a regra de aprovação por tipo não foi aplicada.', sa, aa, sb, ab);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PGP-002 — código único + link principal automático
CREATE OR REPLACE FUNCTION public.qa_caso_pgp_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_id uuid; v_links int; v_dup boolean := false;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Cadastrar parceiro QA-PGP-002 e conferir o link principal';
  r.esperado := 'Um parceiro_links com o mesmo código, campanha principal, ativo';
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro) VALUES ('QA-PGP-002', 'QA Link', 'indicador') RETURNING id INTO v_id;
  SELECT count(*) INTO v_links FROM public.parceiro_links
  WHERE parceiro_id = v_id AND codigo = 'QA-PGP-002' AND campanha = 'principal' AND ativo;

  r.passo_ordem := 2;
  r.passo_acao := 'Tentar um segundo parceiro com o mesmo código';
  r.esperado := 'Recusado por unicidade';
  BEGIN
    INSERT INTO public.parceiros (codigo, nome, tipo_parceiro) VALUES ('QA-PGP-002', 'QA Dup', 'indicador');
    v_dup := true;
    DELETE FROM public.parceiros WHERE codigo = 'QA-PGP-002' AND nome = 'QA Dup';
  EXCEPTION WHEN unique_violation THEN v_dup := false;
  END;
  DELETE FROM public.parceiros WHERE id = v_id;

  IF v_links = 1 AND NOT v_dup THEN
    r.situacao := 'passou'; r.obtido := 'Link principal criado junto; código duplicado recusado.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('links principais: %s (esperado 1); duplicado aceito: %s', v_links, v_dup);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PGP-003 — RLS ligada e sem política aberta
CREATE OR REPLACE FUNCTION public.qa_caso_pgp_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_sem_rls text; v_abertas text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA: RLS ligada em parceiros, parceiro_usuarios, parceiro_links, parceiro_link_cliques, parceiro_comissoes';
  r.esperado := 'relrowsecurity = true nas 5';
  SELECT string_agg(t, ', ') INTO v_sem_rls
  FROM unnest(ARRAY['parceiros','parceiro_usuarios','parceiro_links','parceiro_link_cliques','parceiro_comissoes']) t
  WHERE NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = 'public' AND c.relname = t AND c.relrowsecurity);

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: nenhuma política de SELECT permissiva com USING (true) para authenticated/anon';
  r.esperado := 'Só políticas que citam parceiro_meu_id/parceiro_usuarios ou is_superadmin';
  SELECT string_agg(tablename || '.' || policyname, ', ') INTO v_abertas
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename IN ('parceiros','parceiro_usuarios','parceiro_links','parceiro_link_cliques','parceiro_comissoes')
    AND permissive = 'PERMISSIVE'
    AND cmd IN ('SELECT','ALL')
    AND coalesce(qual,'') NOT ILIKE '%parceiro_meu_id%'
    AND coalesce(qual,'') NOT ILIKE '%parceiro_usuarios%'
    AND coalesce(qual,'') NOT ILIKE '%is_superadmin%';

  IF v_sem_rls IS NULL AND v_abertas IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'RLS ligada nas 5 tabelas; toda leitura passa por vínculo ou superadmin.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: ' || coalesce('sem RLS: ' || v_sem_rls || '. ', '')
             || coalesce('políticas abertas: ' || v_abertas || '.', '')
             || ' Carteira e comissão são dados comerciais de cada parceiro — ligue RLS e restrinja a leitura ao vínculo.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PGP-004 — origem no tenant e FKs SET NULL
CREATE OR REPLACE FUNCTION public.qa_caso_pgp_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_faltam text; v_ruins text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA: colunas de origem em tenants e leads';
  r.esperado := 'tenants.parceiro_id, parceiro_link_id, originado_em, implantador_parceiro_id; leads.parceiro_id, atribuicao';
  SELECT string_agg(x, ', ') INTO v_faltam FROM (VALUES
    ('tenants.parceiro_id'),('tenants.parceiro_link_id'),('tenants.originado_em'),('tenants.implantador_parceiro_id'),
    ('leads.parceiro_id'),('leads.atribuicao')) v(x)
  WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = split_part(x,'.',1) AND column_name = split_part(x,'.',2));

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: regra de exclusão das FKs tenants/leads → parceiros';
  r.esperado := 'SET NULL';
  SELECT string_agg(tc.table_name || '.' || tc.constraint_name || '=' || rc.delete_rule, ', ') INTO v_ruins
  FROM information_schema.table_constraints tc
  JOIN information_schema.referential_constraints rc ON rc.constraint_name = tc.constraint_name AND rc.constraint_schema = tc.table_schema
  JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = rc.unique_constraint_name AND ccu.constraint_schema = rc.unique_constraint_schema
  WHERE tc.table_schema = 'public' AND tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_name IN ('tenants','leads') AND ccu.table_name IN ('parceiros','parceiro_links')
    AND rc.delete_rule <> 'SET NULL';

  IF v_faltam IS NULL AND v_ruins IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'Colunas presentes; FKs com SET NULL — encerrar parceiro não arrasta cliente.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: ' || coalesce('faltam colunas: ' || v_faltam || '. ', '')
             || coalesce('FKs sem SET NULL: ' || v_ruins || '.', '');
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PGP-005 — remuneração por evento em tabela
CREATE OR REPLACE FUNCTION public.qa_caso_pgp_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_linha int; v_motor boolean; v_le boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA: evento setup_concluido semeado para implantador';
  r.esperado := 'Linha ativa em parceiro_eventos_remuneracao';
  SELECT count(*) INTO v_linha FROM public.parceiro_eventos_remuneracao
  WHERE tipo_parceiro = 'implantador' AND evento = 'setup_concluido' AND ativo;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: se o motor de fechamento existir, ele lê a tabela';
  r.esperado := 'parceiro_fechar_competencia referencia parceiro_eventos_remuneracao (ou ainda não existe — Onda 3)';
  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'public' AND p.proname = 'parceiro_fechar_competencia') INTO v_motor;
  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'public' AND p.proname = 'parceiro_fechar_competencia'
                   AND p.prosrc ILIKE '%parceiro_eventos_remuneracao%') INTO v_le;

  IF v_linha >= 1 AND (NOT v_motor OR v_le) THEN
    r.situacao := 'passou';
    r.obtido := CASE WHEN v_motor THEN 'Tabela semeada e lida pelo motor.'
                     ELSE 'Tabela semeada; motor de fechamento ainda não existe (Onda 3) — sonda passa a exigir a leitura quando ele nascer.' END;
  ELSE
    r.situacao := 'falhou';
    r.obtido := CASE WHEN v_linha = 0 THEN 'ACHADO: sem linha de setup_concluido para implantador — o setup do implantador ficou sem valor configurável.'
                     ELSE 'ACHADO: o motor de fechamento existe e NÃO lê parceiro_eventos_remuneracao — o valor do setup está fixo no código.' END;
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PGP-006 — níveis por trilha
CREATE OR REPLACE FUNCTION public.qa_caso_pgp_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_n int; v_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA: trilha operador com ≥ 2 níveis ativos e mrr_minimo crescente com a ordem';
  r.esperado := 'Visão (0) antes de Diamante (> 0)';
  SELECT count(*) INTO v_n FROM public.parceiro_niveis WHERE trilha = 'operador' AND ativo;
  SELECT coalesce(bool_and(ok), false) INTO v_ok FROM (
    SELECT mrr_minimo_cents >= coalesce(lag(mrr_minimo_cents) OVER (ORDER BY ordem), -1) AS ok
    FROM public.parceiro_niveis WHERE trilha = 'operador' AND ativo) s;
  IF v_n >= 2 AND v_ok THEN
    r.situacao := 'passou'; r.obtido := format('%s níveis, faixas crescentes.', v_n);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: %s níveis; faixas crescentes: %s — a barra "faltam R$ X para o próximo nível" não tem base.', v_n, v_ok);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── Registro no motor ──
INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('PGP-001', 'qa_caso_pgp_001'),
  ('PGP-002', 'qa_caso_pgp_002'),
  ('PGP-003', 'qa_caso_pgp_003'),
  ('PGP-004', 'qa_caso_pgp_004'),
  ('PGP-005', 'qa_caso_pgp_005'),
  ('PGP-006', 'qa_caso_pgp_006')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- =====================================================================
-- CONFERÊNCIA FINAL (o editor mostra só este resultado)
-- =====================================================================
WITH tabelas AS MATERIALIZED (
  SELECT count(*) AS n FROM information_schema.tables
  WHERE table_schema = 'public'
    AND table_name IN ('parceiros','parceiro_usuarios','parceiro_links','parceiro_link_cliques',
                       'parceiro_niveis','parceiro_eventos_remuneracao','parceiro_comissoes')
), rls AS MATERIALIZED (
  SELECT count(*) AS n FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
  WHERE ns.nspname = 'public' AND c.relrowsecurity
    AND c.relname IN ('parceiros','parceiro_usuarios','parceiro_links','parceiro_link_cliques',
                      'parceiro_niveis','parceiro_eventos_remuneracao','parceiro_comissoes')
), funcoes AS MATERIALIZED (
  SELECT count(*) AS n FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
  WHERE ns.nspname = 'public' AND p.proname IN (
    'superadmin_parceiros_list','superadmin_parceiro_salvar','superadmin_parceiro_status',
    'superadmin_parceiro_vincular_usuario','superadmin_parceiro_desvincular_usuario',
    'superadmin_parceiro_vincular_tenant','superadmin_parceiro_link_criar','superadmin_parceiro_link_ativo',
    'superadmin_parceiro_detalhe','superadmin_parceiros_tenants_list',
    'superadmin_parceiro_eventos_salvar','superadmin_parceiro_niveis_salvar','parceiro_meu_id')
), colunas AS MATERIALIZED (
  SELECT count(*) AS n FROM information_schema.columns
  WHERE table_schema = 'public' AND (
    (table_name = 'tenants' AND column_name IN ('parceiro_id','parceiro_link_id','originado_em','implantador_parceiro_id')) OR
    (table_name = 'leads' AND column_name IN ('parceiro_id','parceiro_link_id','atribuicao','implantador_parceiro_id')) OR
    (table_name = 'landing_leads' AND column_name = 'ref_codigo') OR
    (table_name = 'assinaturas' AND column_name = 'ref_codigo') OR
    (table_name = 'subscriptions' AND column_name IN ('ciclo_meses','ciclo_inicio','ciclo_fim')))
), casos AS MATERIALIZED (
  SELECT count(*) FILTER (WHERE nivel = 'api') AS api, count(*) FILTER (WHERE nivel = 'e2e') AS e2e
  FROM public.qa_casos_teste WHERE codigo LIKE 'PGP-%'
), rotinas AS MATERIALIZED (
  SELECT count(*) AS n FROM public.qa_implementacoes WHERE codigo LIKE 'PGP-%' AND ativo
), sementes AS MATERIALIZED (
  SELECT (SELECT count(*) FROM public.parceiro_niveis WHERE trilha = 'operador') AS niveis,
         (SELECT count(*) FROM public.parceiro_eventos_remuneracao) AS eventos,
         (SELECT count(*) FROM public.parceiros) AS parceiros
)
SELECT
  CASE WHEN t.n = 7 AND r.n = 7 AND f.n = 13 AND c.n = 13 AND k.api = 12 AND k.e2e = 5 AND q.n = 6
       THEN 'OK — Programa de Parceiros (Ondas 0 e 1) aplicado'
       ELSE 'ATENÇÃO — confira as colunas ao lado' END AS resultado,
  t.n || '/7'  AS tabelas,
  r.n || '/7'  AS tabelas_com_rls,
  f.n || '/13' AS funcoes,
  c.n || '/13' AS colunas_novas,
  k.api || ' api + ' || k.e2e || ' e2e' AS casos_qa,
  q.n || '/6'  AS rotinas_qa,
  s.niveis AS niveis_operador,
  s.eventos AS eventos_remuneracao,
  s.parceiros AS parceiros_cadastrados,
  NULL::text AS erro_tecnico
FROM tabelas t, rls r, funcoes f, colunas c, casos k, rotinas q, sementes s;
