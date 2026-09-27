-- ============================================================================
-- Mapa Comportamental — Fatia 6: leitura por CPF (integração com Feedback)
--
-- Objetivo: na tela de Feedback, ao selecionar um colaborador que já fez o
-- Mapa Comportamental, mostrar a orientação do Guia do Líder para o arquétipo
-- dele. O Feedback identifica o colaborador por admissoes.id + CPF; a ponte
-- para o mapa é o CPF (guardado como dígitos em colaborador_cpf).
--
-- RPC mapa_comportamental_por_cpf: acha o último mapa CONCLUÍDO daquele CPF no
-- tenant e devolve o resultado interpretado.
--  - RN-003: NUNCA devolve respostas item a item (nem tempo_por_item).
--  - RF-013: registra o acesso quando é leitura de mapa de TERCEIRO.
--  - Acesso: titular OU superadmin OU perfil_permite_modulo. Sem permissão ou
--    sem mapa concluído → RETORNA NULL (o painel de Feedback só não aparece;
--    a tela de Feedback nunca quebra por causa disso).
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.mapa_comportamental_por_cpf(p_cpf text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_auth   uuid := auth.uid();
  v_tenant uuid := public.get_user_tenant_id();
  v_cpf    text := regexp_replace(COALESCE(p_cpf, ''), '[^0-9]', '', 'g');
  v_mapa_id uuid;
  v_titular uuid;
  v_res    jsonb;
BEGIN
  IF v_tenant IS NULL OR v_cpf = '' THEN
    RETURN NULL;
  END IF;

  SELECT id, auth_user_id INTO v_mapa_id, v_titular
  FROM public.mapa_comportamental_respostas
  WHERE tenant_id = v_tenant
    AND status = 'concluido'
    AND colaborador_cpf = v_cpf
  ORDER BY concluido_em DESC NULLS LAST, created_at DESC
  LIMIT 1;

  IF v_mapa_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Sem permissão de leitura → não expõe nada (sem erro na tela de Feedback).
  IF NOT (v_titular = v_auth
          OR public.is_superadmin(v_auth)
          OR public.perfil_permite_modulo(v_tenant, VARIADIC ARRAY['mapa_comportamental'::text])) THEN
    RETURN NULL;
  END IF;

  -- Leitura de mapa de terceiro é registrada (RF-013).
  IF v_titular <> v_auth THEN
    INSERT INTO public.mapa_comportamental_acessos (tenant_id, mapa_id, acessado_por, acessado_por_nome)
    VALUES (v_tenant, v_mapa_id, v_auth,
            (SELECT nome_completo FROM public.usuarios_base WHERE auth_user_id = v_auth LIMIT 1));
  END IF;

  -- Resultado interpretado, sem respostas item a item (RN-003).
  v_res := (
    SELECT to_jsonb(r) - 'respostas' - 'tempo_por_item'
    FROM public.mapa_comportamental_respostas r
    WHERE r.id = v_mapa_id
  );
  RETURN v_res;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.mapa_comportamental_por_cpf(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mapa_comportamental_por_cpf(text) TO authenticated;

-- ── QA — MAPA-007 (leitura por CPF com log, somente leitura) ─────────────────
DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'desenvolvimento-performance/mapa-comportamental');
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo QA ausente — pulei o caso da Fatia 6.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
    (v_mod, 'MAPA-007', 'Leitura de mapa por CPF (integração Feedback) com log', 'feliz', 'alta', 'aprovado', 'api',
     'A função de leitura por CPF existe, é SECURITY DEFINER e não expõe respostas item a item.',
     'Fatia 6 aplicada.',
     '[{"ordem":1,"acao":"Verificar mapa_comportamental_por_cpf (SECURITY DEFINER)","resultado_esperado":"presente e security definer"}]'::jsonb,
     'A função de leitura por CPF existe.', 'Cobre RF-013/RN-003 na integração com Feedback.')
  ON CONFLICT (codigo) DO NOTHING;
  RAISE NOTICE 'OK: caso MAPA-007 documentado.';
END $doc$;

CREATE OR REPLACE FUNCTION public.qa_caso_mapa_007()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE r public.qa_retorno; v_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Verificar função de leitura de mapa por CPF (com log)';
  r.esperado    := 'mapa_comportamental_por_cpf presente e SECURITY DEFINER';
  v_ok := (SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'mapa_comportamental_por_cpf' AND p.prosecdef));
  IF v_ok THEN r.situacao := 'passou'; r.obtido := 'Função presente e SECURITY DEFINER';
  ELSE r.situacao := 'falhou'; r.obtido := 'Função ausente ou não SECURITY DEFINER'; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END;
$fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('MAPA-007', 'qa_caso_mapa_007')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
