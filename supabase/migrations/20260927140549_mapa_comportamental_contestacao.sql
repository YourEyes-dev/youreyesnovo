-- ============================================================================
-- Mapa Comportamental — Contestação do resultado (RF-014 / RF-029).
--
-- Direito de revisão do titular (LGPD art. 20): "Não me reconheço neste
-- resultado". Abre uma contestação com texto livre e opção de solicitar nova
-- aplicação. Gestor/RH (perfil do módulo) analisa e resolve. O titular
-- acompanha o status do próprio pedido.
--
-- Identidade (tenant/auth_user_id/cpf/nome) é carimbada pelo servidor a partir
-- do usuário logado — o cliente não escolhe de quem é a contestação.
-- ============================================================================

SET lock_timeout = '10s';

CREATE TABLE IF NOT EXISTS public.mapa_comportamental_contestacoes (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  mapa_id              uuid REFERENCES public.mapa_comportamental_respostas(id) ON DELETE SET NULL,
  auth_user_id         uuid,
  colaborador_cpf      text,
  colaborador_nome     text,
  texto                text NOT NULL,
  solicitou_reaplicacao boolean NOT NULL DEFAULT false,
  status               text NOT NULL DEFAULT 'aberta',
  resposta             text,
  resolvido_por        uuid,
  resolvido_por_nome   text,
  resolvido_em         timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT mapa_contest_status_chk CHECK (status IN ('aberta','em_analise','resolvida'))
);

CREATE INDEX IF NOT EXISTS idx_mapa_contest_tenant_status
  ON public.mapa_comportamental_contestacoes(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_mapa_contest_mapa
  ON public.mapa_comportamental_contestacoes(mapa_id);

-- Trigger de identidade/resolução:
--  - INSERT: carimba tenant/auth_user_id/cpf/nome do usuário logado.
--  - UPDATE p/ 'resolvida': carimba quem resolveu e quando (a partir do logado).
CREATE OR REPLACE FUNCTION public.mapa_comportamental_contestacao_carimbar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_uid uuid := auth.uid(); v_ub record;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.auth_user_id := v_uid;
    NEW.tenant_id := COALESCE(public.get_user_tenant_id(), NEW.tenant_id);
    SELECT ub.nome_completo,
           regexp_replace(COALESCE(ub.cpf, ''), '[^0-9]', '', 'g') AS cpf_num
      INTO v_ub
      FROM public.usuarios_base ub
     WHERE ub.auth_user_id = v_uid
     LIMIT 1;
    IF FOUND THEN
      NEW.colaborador_nome := v_ub.nome_completo;
      NEW.colaborador_cpf  := NULLIF(v_ub.cpf_num, '');
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE: ao marcar como resolvida, registra o autor da resolução.
  IF NEW.status = 'resolvida' AND (OLD.status IS DISTINCT FROM 'resolvida') THEN
    NEW.resolvido_por := v_uid;
    NEW.resolvido_por_nome := (SELECT ub.nome_completo FROM public.usuarios_base ub WHERE ub.auth_user_id = v_uid LIMIT 1);
    NEW.resolvido_em := now();
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_mapa_contest_carimbar ON public.mapa_comportamental_contestacoes;
CREATE TRIGGER trg_mapa_contest_carimbar
  BEFORE INSERT OR UPDATE ON public.mapa_comportamental_contestacoes
  FOR EACH ROW EXECUTE FUNCTION public.mapa_comportamental_contestacao_carimbar();

ALTER TABLE public.mapa_comportamental_contestacoes ENABLE ROW LEVEL SECURITY;

DO $pol$
BEGIN
  -- Leitura: titular (por auth_user_id OU CPF), superadmin, ou quem tem o módulo.
  DROP POLICY IF EXISTS mapa_contest_select ON public.mapa_comportamental_contestacoes;
  CREATE POLICY mapa_contest_select ON public.mapa_comportamental_contestacoes
    FOR SELECT TO authenticated
    USING (
      auth_user_id = auth.uid()
      OR public.is_superadmin(auth.uid())
      OR (public.cpf_do_usuario_logado() <> '' AND colaborador_cpf = public.cpf_do_usuario_logado())
      OR public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['mapa_comportamental'::text])
    );

  -- Restritiva por perfil (tabela com dado pessoal — padrão PERFIL-003).
  DROP POLICY IF EXISTS perfil_restringe_leitura_mapa_comportamental_contestacoes ON public.mapa_comportamental_contestacoes;
  CREATE POLICY perfil_restringe_leitura_mapa_comportamental_contestacoes ON public.mapa_comportamental_contestacoes
    AS RESTRICTIVE FOR SELECT TO authenticated
    USING (
      auth_user_id = auth.uid()
      OR public.is_superadmin(auth.uid())
      OR (public.cpf_do_usuario_logado() <> '' AND colaborador_cpf = public.cpf_do_usuario_logado())
      OR public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['mapa_comportamental'::text])
    );

  -- Abertura: o próprio titular cria a sua contestação.
  DROP POLICY IF EXISTS mapa_contest_insert ON public.mapa_comportamental_contestacoes;
  CREATE POLICY mapa_contest_insert ON public.mapa_comportamental_contestacoes
    FOR INSERT TO authenticated
    WITH CHECK (auth_user_id = auth.uid() AND tenant_id = public.get_user_tenant_id());

  -- Resolução: gestor/RH com o módulo (ou superadmin).
  DROP POLICY IF EXISTS mapa_contest_update ON public.mapa_comportamental_contestacoes;
  CREATE POLICY mapa_contest_update ON public.mapa_comportamental_contestacoes
    FOR UPDATE TO authenticated
    USING (public.is_superadmin(auth.uid()) OR public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['mapa_comportamental'::text]))
    WITH CHECK (public.is_superadmin(auth.uid()) OR public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['mapa_comportamental'::text]));
END $pol$;

-- ── QA — MAPA-010 (contestação) ──────────────────────────────────────────────
DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'desenvolvimento-performance/mapa-comportamental');
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo QA ausente — pulei o caso da contestação.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
    (v_mod, 'MAPA-010', 'Contestação do resultado (direito de revisão)', 'feliz', 'alta', 'aprovado', 'api',
     'A tabela de contestações existe com RLS e trigger de identidade/resolução.',
     'Migration da contestação aplicada.',
     '[{"ordem":1,"acao":"Verificar tabela e trigger de contestação","resultado_esperado":"tabela + trigger presentes"}]'::jsonb,
     'Objetos da contestação presentes.', 'RF-014/RF-029; LGPD art. 20 (revisão humana).')
  ON CONFLICT (codigo) DO NOTHING;
  RAISE NOTICE 'OK: caso MAPA-010 documentado.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'MAPA-010 doc: %', SQLERRM;
END $doc$;

CREATE OR REPLACE FUNCTION public.qa_caso_mapa_010()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE r public.qa_retorno; v_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Verificar tabela de contestações e o trigger de carimbo';
  r.esperado    := 'mapa_comportamental_contestacoes + trigger presentes';
  v_ok := (to_regclass('public.mapa_comportamental_contestacoes') IS NOT NULL)
      AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_mapa_contest_carimbar');
  IF v_ok THEN r.situacao := 'passou'; r.obtido := 'Objetos presentes';
  ELSE r.situacao := 'falhou'; r.obtido := 'Objeto(s) da contestação ausente(s)'; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END;
$fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('MAPA-010', 'qa_caso_mapa_010')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
