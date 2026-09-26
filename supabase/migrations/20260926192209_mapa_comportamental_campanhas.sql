-- ============================================================================
-- Mapa Comportamental — Fatia 2: Governança + Campanhas + Convites
--
-- Constrói sobre a Fatia 1 (fundação + Meu Mapa). Entrega:
--  - Política de uso + aviso de tratamento versionados e publicáveis (RF-001):
--    sem política publicada, campanha não pode ser ATIVADA (trava por trigger).
--  - Campanhas (RH): público, prazo, status rascunho/ativa/encerrada.
--  - Convites (participações) por colaborador, com token; cobertura acompanhável.
--  - Vínculo da resposta à campanha: ao concluir um mapa com campanha, a
--    participação correspondente é marcada como respondida.
--
-- Mantém as travas da casa: RN-009 (sem troca com Psicossocial/Saúde),
-- RN-011 (supressão por baixo N nos agregados), RN-012 (recusa/omissão sem
-- consequência — a não-resposta só aparece como cobertura não atingida).
-- Nada de dado sensível de saúde.
-- ============================================================================

SET lock_timeout = '10s';

-- ────────────────────────────────────────────────────────────────────────────
-- 1) Política de uso + aviso de tratamento (versionados). RF-001.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.mapa_comportamental_politicas (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  versao             int  NOT NULL,
  titulo             text NOT NULL DEFAULT 'Política de Uso — Mapa Comportamental',
  texto_politica     text NOT NULL,
  texto_aviso        text NOT NULL,
  publicada          boolean NOT NULL DEFAULT false,
  publicada_em       timestamptz,
  publicada_por      uuid,
  publicada_por_nome text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_mapa_comp_politica_versao UNIQUE (tenant_id, versao)
);
CREATE INDEX IF NOT EXISTS idx_mapa_comp_politicas_tenant
  ON public.mapa_comportamental_politicas(tenant_id, publicada);

-- ────────────────────────────────────────────────────────────────────────────
-- 2) Campanhas.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.mapa_comportamental_campanhas (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  empresa_id         uuid,
  nome               text NOT NULL,
  descricao          text,
  publico            jsonb NOT NULL DEFAULT '{"tipo":"empresa_inteira"}'::jsonb,
  status             text NOT NULL DEFAULT 'rascunho',
  data_inicio        date,
  data_fim           date,
  instrumento_versao int NOT NULL DEFAULT 1,
  politica_id        uuid REFERENCES public.mapa_comportamental_politicas(id),
  criado_por         uuid,
  criado_por_nome    text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT mapa_comp_camp_status_chk CHECK (status IN ('rascunho','ativa','encerrada'))
);
CREATE INDEX IF NOT EXISTS idx_mapa_comp_campanhas_tenant_status
  ON public.mapa_comportamental_campanhas(tenant_id, status);

-- ────────────────────────────────────────────────────────────────────────────
-- 3) Participações (convites) por colaborador.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.mapa_comportamental_participacoes (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  campanha_id      uuid NOT NULL REFERENCES public.mapa_comportamental_campanhas(id) ON DELETE CASCADE,
  usuario_id       uuid NOT NULL,
  colaborador_nome text,
  colaborador_cpf  text,
  token            text NOT NULL DEFAULT encode(gen_random_bytes(16), 'hex'),
  status           text NOT NULL DEFAULT 'pendente',
  respondido_em    timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_mapa_comp_participacao UNIQUE (campanha_id, usuario_id),
  CONSTRAINT uq_mapa_comp_participacao_token UNIQUE (token),
  CONSTRAINT mapa_comp_part_status_chk CHECK (status IN ('pendente','respondido'))
);
CREATE INDEX IF NOT EXISTS idx_mapa_comp_part_campanha ON public.mapa_comportamental_participacoes(campanha_id);
CREATE INDEX IF NOT EXISTS idx_mapa_comp_part_usuario  ON public.mapa_comportamental_participacoes(tenant_id, usuario_id, status);

-- ────────────────────────────────────────────────────────────────────────────
-- 4) Trigger RF-001: campanha só ATIVA com política publicada.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mapa_comportamental_exige_politica()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.status = 'ativa' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.mapa_comportamental_politicas p
      WHERE p.tenant_id = NEW.tenant_id AND p.publicada = true
    ) THEN
      RAISE EXCEPTION 'Publique a política de uso antes de ativar uma campanha do Mapa Comportamental (RF-001).';
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_mapa_comp_exige_politica ON public.mapa_comportamental_campanhas;
CREATE TRIGGER trg_mapa_comp_exige_politica
  BEFORE INSERT OR UPDATE ON public.mapa_comportamental_campanhas
  FOR EACH ROW EXECUTE FUNCTION public.mapa_comportamental_exige_politica();

DROP TRIGGER IF EXISTS trg_mapa_comp_camp_updated_at ON public.mapa_comportamental_campanhas;
CREATE TRIGGER trg_mapa_comp_camp_updated_at
  BEFORE UPDATE ON public.mapa_comportamental_campanhas
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_mapa_comp_pol_updated_at ON public.mapa_comportamental_politicas;
CREATE TRIGGER trg_mapa_comp_pol_updated_at
  BEFORE UPDATE ON public.mapa_comportamental_politicas
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ────────────────────────────────────────────────────────────────────────────
-- 5) Trigger: ao concluir um mapa vinculado a campanha, marca a participação.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mapa_comportamental_marcar_participacao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.status = 'concluido' AND NEW.campanha_id IS NOT NULL AND NEW.usuario_id IS NOT NULL THEN
    UPDATE public.mapa_comportamental_participacoes
       SET status = 'respondido', respondido_em = COALESCE(NEW.concluido_em, now())
     WHERE campanha_id = NEW.campanha_id
       AND usuario_id = NEW.usuario_id
       AND status <> 'respondido';
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_mapa_comp_marcar_participacao ON public.mapa_comportamental_respostas;
CREATE TRIGGER trg_mapa_comp_marcar_participacao
  AFTER INSERT OR UPDATE ON public.mapa_comportamental_respostas
  FOR EACH ROW EXECUTE FUNCTION public.mapa_comportamental_marcar_participacao();

-- ────────────────────────────────────────────────────────────────────────────
-- 6) RLS
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.mapa_comportamental_politicas      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mapa_comportamental_campanhas      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mapa_comportamental_participacoes  ENABLE ROW LEVEL SECURITY;

DO $pol$
BEGIN
  -- Políticas: leitura no tenant; gestão por manager+.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='mapa_comportamental_politicas' AND policyname='mapa_comp_pol_select') THEN
    CREATE POLICY mapa_comp_pol_select ON public.mapa_comportamental_politicas
      FOR SELECT TO authenticated USING (tenant_id = public.get_user_tenant_id());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='mapa_comportamental_politicas' AND policyname='mapa_comp_pol_manage') THEN
    CREATE POLICY mapa_comp_pol_manage ON public.mapa_comportamental_politicas
      FOR ALL TO authenticated
      USING (tenant_id = public.get_user_tenant_id() AND public.has_minimum_role(auth.uid(),'manager'::public.app_role))
      WITH CHECK (tenant_id = public.get_user_tenant_id() AND public.has_minimum_role(auth.uid(),'manager'::public.app_role));
  END IF;

  -- Campanhas: leitura no tenant; gestão por manager+.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='mapa_comportamental_campanhas' AND policyname='mapa_comp_camp_select') THEN
    CREATE POLICY mapa_comp_camp_select ON public.mapa_comportamental_campanhas
      FOR SELECT TO authenticated USING (tenant_id = public.get_user_tenant_id());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='mapa_comportamental_campanhas' AND policyname='mapa_comp_camp_manage') THEN
    CREATE POLICY mapa_comp_camp_manage ON public.mapa_comportamental_campanhas
      FOR ALL TO authenticated
      USING (tenant_id = public.get_user_tenant_id() AND public.has_minimum_role(auth.uid(),'manager'::public.app_role))
      WITH CHECK (tenant_id = public.get_user_tenant_id() AND public.has_minimum_role(auth.uid(),'manager'::public.app_role));
  END IF;

  -- Participações: o titular vê a própria; RH/perfil vê todas; gestão por manager+.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='mapa_comportamental_participacoes' AND policyname='mapa_comp_part_select') THEN
    CREATE POLICY mapa_comp_part_select ON public.mapa_comportamental_participacoes
      FOR SELECT TO authenticated
      USING (
        public.is_superadmin(auth.uid())
        OR public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['mapa_comportamental'::text])
        OR EXISTS (SELECT 1 FROM public.usuarios_base ub
                   WHERE ub.auth_user_id = auth.uid() AND ub.id = usuario_id)
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='mapa_comportamental_participacoes' AND policyname='mapa_comp_part_manage') THEN
    CREATE POLICY mapa_comp_part_manage ON public.mapa_comportamental_participacoes
      FOR ALL TO authenticated
      USING (tenant_id = public.get_user_tenant_id() AND public.has_minimum_role(auth.uid(),'manager'::public.app_role))
      WITH CHECK (tenant_id = public.get_user_tenant_id() AND public.has_minimum_role(auth.uid(),'manager'::public.app_role));
  END IF;

  -- RESTRICTIVE (PERFIL-003): participações carregam nome/cpf. Só o titular, o
  -- perfil que permite o módulo, ou superadmin leem.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='mapa_comportamental_participacoes' AND policyname='perfil_restringe_leitura_mapa_comportamental_participacoes') THEN
    CREATE POLICY perfil_restringe_leitura_mapa_comportamental_participacoes
      ON public.mapa_comportamental_participacoes
      AS RESTRICTIVE FOR SELECT TO authenticated
      USING (
        public.is_superadmin(auth.uid())
        OR public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['mapa_comportamental'::text])
        OR EXISTS (SELECT 1 FROM public.usuarios_base ub
                   WHERE ub.auth_user_id = auth.uid() AND ub.id = usuario_id)
      );
  END IF;
END $pol$;

-- ────────────────────────────────────────────────────────────────────────────
-- 7) RPCs (SECURITY DEFINER)
-- ────────────────────────────────────────────────────────────────────────────

-- 7.1) Gera convites para o público da campanha. Retorna o total de convidados.
CREATE OR REPLACE FUNCTION public.mapa_comportamental_gerar_convites(p_campanha_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant  uuid;
  v_publico jsonb;
  v_tipo    text;
  v_total   int;
BEGIN
  SELECT tenant_id, publico INTO v_tenant, v_publico
  FROM public.mapa_comportamental_campanhas WHERE id = p_campanha_id;

  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Campanha não encontrada.';
  END IF;
  IF NOT public.perfil_permite_modulo(v_tenant, VARIADIC ARRAY['mapa_comportamental'::text]) THEN
    RAISE EXCEPTION 'Sem permissão para gerar convites.';
  END IF;

  v_tipo := COALESCE(v_publico->>'tipo', 'empresa_inteira');

  IF v_tipo = 'lista' THEN
    INSERT INTO public.mapa_comportamental_participacoes (tenant_id, campanha_id, usuario_id, colaborador_nome, colaborador_cpf)
    SELECT v_tenant, p_campanha_id, ub.id, ub.nome_completo,
           NULLIF(regexp_replace(COALESCE(ub.cpf,''),'[^0-9]','','g'),'')
    FROM public.usuarios_base ub
    WHERE ub.tenant_id = v_tenant
      AND ub.id::text IN (SELECT jsonb_array_elements_text(COALESCE(v_publico->'usuario_ids','[]'::jsonb)))
    ON CONFLICT (campanha_id, usuario_id) DO NOTHING;
  ELSE
    -- empresa_inteira: todos os usuários ativos do tenant.
    INSERT INTO public.mapa_comportamental_participacoes (tenant_id, campanha_id, usuario_id, colaborador_nome, colaborador_cpf)
    SELECT v_tenant, p_campanha_id, ub.id, ub.nome_completo,
           NULLIF(regexp_replace(COALESCE(ub.cpf,''),'[^0-9]','','g'),'')
    FROM public.usuarios_base ub
    WHERE ub.tenant_id = v_tenant
      AND ub.status::text = 'ativo'
    ON CONFLICT (campanha_id, usuario_id) DO NOTHING;
  END IF;

  v_total := (SELECT count(*) FROM public.mapa_comportamental_participacoes WHERE campanha_id = p_campanha_id);
  RETURN v_total;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.mapa_comportamental_gerar_convites(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mapa_comportamental_gerar_convites(uuid) TO authenticated;

-- 7.2) Cobertura de uma campanha.
CREATE OR REPLACE FUNCTION public.mapa_comportamental_cobertura(p_campanha_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant uuid;
  v_conv int;
  v_resp int;
BEGIN
  SELECT tenant_id INTO v_tenant FROM public.mapa_comportamental_campanhas WHERE id = p_campanha_id;
  IF v_tenant IS NULL
     OR NOT public.perfil_permite_modulo(v_tenant, VARIADIC ARRAY['mapa_comportamental'::text]) THEN
    RETURN jsonb_build_object('convidados', 0, 'respondidos', 0, 'pct', 0);
  END IF;

  v_conv := (SELECT count(*) FROM public.mapa_comportamental_participacoes WHERE campanha_id = p_campanha_id);
  v_resp := (SELECT count(*) FROM public.mapa_comportamental_participacoes WHERE campanha_id = p_campanha_id AND status = 'respondido');

  RETURN jsonb_build_object(
    'convidados', v_conv,
    'respondidos', v_resp,
    'pct', CASE WHEN v_conv > 0 THEN round((v_resp::numeric / v_conv) * 100, 1) ELSE 0 END
  );
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.mapa_comportamental_cobertura(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mapa_comportamental_cobertura(uuid) TO authenticated;

-- 7.3) Minha campanha pendente (para o banner no Meu Mapa).
CREATE OR REPLACE FUNCTION public.mapa_comportamental_minha_campanha_pendente()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_res jsonb;
BEGIN
  v_res := (
    SELECT jsonb_build_object(
             'campanha_id', c.id, 'nome', c.nome, 'data_fim', c.data_fim,
             'participacao_id', pa.id)
    FROM public.mapa_comportamental_participacoes pa
    JOIN public.mapa_comportamental_campanhas c ON c.id = pa.campanha_id
    JOIN public.usuarios_base ub ON ub.id = pa.usuario_id
    WHERE ub.auth_user_id = v_uid
      AND pa.status = 'pendente'
      AND c.status = 'ativa'
    ORDER BY c.data_fim NULLS LAST, c.created_at
    LIMIT 1
  );
  RETURN v_res;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.mapa_comportamental_minha_campanha_pendente() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mapa_comportamental_minha_campanha_pendente() TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 8) QA — casos MAPA-003/004 (nível api, somente leitura).
-- ────────────────────────────────────────────────────────────────────────────
DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'desenvolvimento-performance/mapa-comportamental');
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo QA mapa-comportamental ausente — pulei os casos da Fatia 2.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
    (v_mod, 'MAPA-003', 'Trava RF-001: ativar campanha exige política publicada', 'negativo', 'alta', 'aprovado', 'api',
     'Sem política publicada, a campanha não pode ser ativada.',
     'Fatia 2 aplicada.',
     '[{"ordem":1,"acao":"Verificar o trigger que exige política publicada ao ativar campanha","resultado_esperado":"trigger trg_mapa_comp_exige_politica presente"}]'::jsonb,
     'A trava RF-001 existe.', 'Cobre RF-001.'),
    (v_mod, 'MAPA-004', 'Participações protegidas por política RESTRICTIVE de perfil', 'feliz', 'critica', 'aprovado', 'api',
     'PERFIL-003: participações carregam nome/cpf e precisam da trava RESTRICTIVE.',
     'Fatia 2 aplicada.',
     '[{"ordem":1,"acao":"Verificar pg_policies em mapa_comportamental_participacoes","resultado_esperado":"perfil_restringe_leitura_mapa_comportamental_participacoes RESTRICTIVE"}]'::jsonb,
     'A política RESTRICTIVE de perfil existe nas participações.', 'Cobre RN-002/RN-003.')
  ON CONFLICT (codigo) DO NOTHING;

  RAISE NOTICE 'OK: casos MAPA-003/004 documentados.';
END $doc$;

CREATE OR REPLACE FUNCTION public.qa_caso_mapa_003()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE r public.qa_retorno; v_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Verificar trigger de exigência de política (RF-001)';
  r.esperado    := 'trg_mapa_comp_exige_politica em mapa_comportamental_campanhas';
  v_ok := (SELECT EXISTS (
    SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relname = 'mapa_comportamental_campanhas'
      AND t.tgname = 'trg_mapa_comp_exige_politica' AND NOT t.tgisinternal));
  IF v_ok THEN r.situacao := 'passou'; r.obtido := 'Trigger RF-001 presente';
  ELSE r.situacao := 'falhou'; r.obtido := 'Trigger RF-001 ausente'; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_mapa_004()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE r public.qa_retorno; v_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Verificar política RESTRICTIVE de perfil nas participações';
  r.esperado    := 'perfil_restringe_leitura_mapa_comportamental_participacoes RESTRICTIVE';
  v_ok := (SELECT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='mapa_comportamental_participacoes'
      AND policyname='perfil_restringe_leitura_mapa_comportamental_participacoes'
      AND permissive='RESTRICTIVE'));
  IF v_ok THEN r.situacao := 'passou'; r.obtido := 'Política RESTRICTIVE presente';
  ELSE r.situacao := 'falhou'; r.obtido := 'Política RESTRICTIVE ausente'; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END;
$fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('MAPA-003', 'qa_caso_mapa_003'),
  ('MAPA-004', 'qa_caso_mapa_004')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
