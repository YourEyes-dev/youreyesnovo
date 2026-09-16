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
