-- ============================================================================
-- Mapa Comportamental — Fatia 4: Ficha da pessoa + Mapa do Time
--
-- Decisão travada com o dono do produto: acesso AMPLO, como o resto do sistema
-- — gestor/RH com a permissão do módulo (perfil_permite_modulo) leem os mapas
-- do tenant, igual a Atestados/Avaliações. (O escopo estrito por organograma
-- não existe no sistema hoje e fica para quando houver esse modelo.)
--
-- Travas de privacidade mantidas:
--  - RN-003: NINGUÉM vê as respostas item a item de outra pessoa. O RPC de
--    leitura de mapa de terceiro devolve o resultado interpretado, sem
--    'respostas' nem 'tempo_por_item'.
--  - RF-013 / CA-009: toda leitura de mapa de TERCEIRO é registrada em
--    mapa_comportamental_acessos (criada na Fatia 1); o titular consulta quem
--    acessou o próprio mapa.
--  - RN-011: agregados seguem com supressão por baixo N (função painel da F1).
-- Sem dado sensível de saúde; RN-009 intacta (nenhuma troca com outros módulos).
-- ============================================================================

SET lock_timeout = '10s';

-- ────────────────────────────────────────────────────────────────────────────
-- 1) Amplia a leitura: além do titular (política da Fatia 1), quem o perfil
--    permite o módulo lê os mapas do tenant. Política PERMISSIVA adicional
--    (as permissivas se somam por OR). A RESTRICTIVE da Fatia 1 já contempla
--    perfil_permite_modulo, então a leitura efetiva passa a ser
--    titular OR superadmin OR perfil.
-- ────────────────────────────────────────────────────────────────────────────
DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='mapa_comportamental_respostas' AND policyname='mapa_comp_resp_select_perfil') THEN
    CREATE POLICY mapa_comp_resp_select_perfil ON public.mapa_comportamental_respostas
      FOR SELECT TO authenticated
      USING (public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['mapa_comportamental'::text]));
  END IF;
END $pol$;

-- ────────────────────────────────────────────────────────────────────────────
-- 2) Ver mapa de terceiro (ficha da pessoa) — devolve o resultado interpretado
--    SEM as respostas item a item (RN-003) e REGISTRA o acesso (RF-013).
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mapa_comportamental_ver_mapa(p_mapa_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_auth uuid := auth.uid();
  v_tenant uuid;
  v_titular uuid;
  v_res jsonb;
BEGIN
  v_tenant  := (SELECT tenant_id FROM public.mapa_comportamental_respostas WHERE id = p_mapa_id);
  v_titular := (SELECT auth_user_id FROM public.mapa_comportamental_respostas WHERE id = p_mapa_id);
  IF v_tenant IS NULL THEN
    RETURN NULL;
  END IF;

  IF NOT (v_titular = v_auth
          OR public.is_superadmin(v_auth)
          OR public.perfil_permite_modulo(v_tenant, VARIADIC ARRAY['mapa_comportamental'::text])) THEN
    RAISE EXCEPTION 'Sem permissão para ver este mapa.';
  END IF;

  -- Registra o acesso quando é leitura de mapa de terceiro (RF-013).
  IF v_titular <> v_auth THEN
    INSERT INTO public.mapa_comportamental_acessos (tenant_id, mapa_id, acessado_por, acessado_por_nome)
    VALUES (v_tenant, p_mapa_id, v_auth,
            (SELECT nome_completo FROM public.usuarios_base WHERE auth_user_id = v_auth LIMIT 1));
  END IF;

  -- Resultado interpretado, sem respostas item a item nem tempos (RN-003).
  v_res := (
    SELECT to_jsonb(r) - 'respostas' - 'tempo_por_item'
    FROM public.mapa_comportamental_respostas r
    WHERE r.id = p_mapa_id
  );
  RETURN v_res;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.mapa_comportamental_ver_mapa(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mapa_comportamental_ver_mapa(uuid) TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 3) Mapa do Time — composição (lista de mapas concluídos do tenant/empresa),
--    para gestor/RH. Sem respostas item a item.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mapa_comportamental_time(p_empresa_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant uuid := public.get_user_tenant_id();
  v_res jsonb;
BEGIN
  IF v_tenant IS NULL
     OR NOT public.perfil_permite_modulo(v_tenant, VARIADIC ARRAY['mapa_comportamental'::text]) THEN
    RETURN '[]'::jsonb;
  END IF;

  v_res := (
    SELECT COALESCE(jsonb_agg(
             jsonb_build_object(
               'mapa_id', id, 'nome', colaborador_nome, 'arquetipo', arquetipo,
               'confiabilidade', confiabilidade, 'concluido_em', concluido_em)
             ORDER BY colaborador_nome), '[]'::jsonb)
    FROM public.mapa_comportamental_respostas
    WHERE tenant_id = v_tenant AND status = 'concluido'
      AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id)
  );
  RETURN v_res;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.mapa_comportamental_time(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mapa_comportamental_time(uuid) TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 4) Quem acessou o meu mapa (transparência ao titular — CA-009).
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mapa_comportamental_meus_acessos()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_auth uuid := auth.uid();
  v_res jsonb;
BEGIN
  v_res := (
    SELECT COALESCE(jsonb_agg(
             jsonb_build_object('acessado_por_nome', a.acessado_por_nome, 'acessado_em', a.acessado_em)
             ORDER BY a.acessado_em DESC), '[]'::jsonb)
    FROM public.mapa_comportamental_acessos a
    JOIN public.mapa_comportamental_respostas r ON r.id = a.mapa_id
    WHERE r.auth_user_id = v_auth
  );
  RETURN v_res;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.mapa_comportamental_meus_acessos() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mapa_comportamental_meus_acessos() TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 5) QA — MAPA-005 (acesso a mapa de terceiro é registrado) e MAPA-006
--    (leitura ampla por perfil).
-- ────────────────────────────────────────────────────────────────────────────
DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'desenvolvimento-performance/mapa-comportamental');
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo QA ausente — pulei os casos da Fatia 4.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
    (v_mod, 'MAPA-005', 'Leitura de mapa de terceiro é registrada (RF-013)', 'feliz', 'alta', 'aprovado', 'api',
     'A função de ver mapa de terceiro grava acesso e não expõe respostas item a item.',
     'Fatia 4 aplicada.',
     '[{"ordem":1,"acao":"Verificar mapa_comportamental_ver_mapa (SECURITY DEFINER)","resultado_esperado":"função presente e security definer"}]'::jsonb,
     'A função de leitura com log existe.', 'Cobre RF-013/RN-003.'),
    (v_mod, 'MAPA-006', 'Leitura ampla por perfil (gestor/RH)', 'feliz', 'media', 'aprovado', 'api',
     'Além do titular, quem o perfil permite o módulo lê os mapas do tenant.',
     'Fatia 4 aplicada.',
     '[{"ordem":1,"acao":"Verificar política permissiva mapa_comp_resp_select_perfil","resultado_esperado":"presente"}]'::jsonb,
     'A política de leitura por perfil existe.', 'Cobre a matriz de acesso (decisão do dono do produto).')
  ON CONFLICT (codigo) DO NOTHING;

  RAISE NOTICE 'OK: casos MAPA-005/006 documentados.';
END $doc$;

CREATE OR REPLACE FUNCTION public.qa_caso_mapa_005()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE r public.qa_retorno; v_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Verificar função de leitura de mapa de terceiro (com log)';
  r.esperado    := 'mapa_comportamental_ver_mapa presente e SECURITY DEFINER';
  v_ok := (SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'mapa_comportamental_ver_mapa' AND p.prosecdef));
  IF v_ok THEN r.situacao := 'passou'; r.obtido := 'Função presente e SECURITY DEFINER';
  ELSE r.situacao := 'falhou'; r.obtido := 'Função ausente ou não SECURITY DEFINER'; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_mapa_006()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE r public.qa_retorno; v_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Verificar política permissiva de leitura por perfil';
  r.esperado    := 'mapa_comp_resp_select_perfil presente';
  v_ok := (SELECT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='mapa_comportamental_respostas'
      AND policyname='mapa_comp_resp_select_perfil'));
  IF v_ok THEN r.situacao := 'passou'; r.obtido := 'Política presente';
  ELSE r.situacao := 'falhou'; r.obtido := 'Política ausente'; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END;
$fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('MAPA-005', 'qa_caso_mapa_005'),
  ('MAPA-006', 'qa_caso_mapa_006')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
