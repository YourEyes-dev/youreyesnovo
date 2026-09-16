-- ============================================================================
-- Motor de QA — Edge Functions: rotinas dos casos api com superfície de banco.
--
-- Dos 7 casos, a fatia verificável no motor SQL:
--   EDGE-001 — a rotina de disparo respeita app_config: sem supabase_url/anon_key
--              ela não chama ninguém (proteção de ambiente).
--   EDGE-006 — o segredo service_role não vive no app_config (fica só no servidor).
--   EDGE-007 — todo link público por token tem coluna de validade (expiração).
-- (EDGE-002/003/004/005 são de runtime da Edge Function — ref de projeto, token
--  QA_E2E_TOKEN, chave de IA, CORS/preflight — e ficam para cobertura edge/e2e.)
-- ============================================================================

-- ── EDGE-001: disparo respeita a config do ambiente ─────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_edge_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_ag uuid; v_antes timestamptz; v_depois timestamptz;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Sem supabase_url/anon_key no app_config, rodar a rotina de disparo';
  r.esperado := 'Nenhum agente é disparado (agenda intocada) — proteção de ambiente';

  -- Tira a config do ambiente (transação-local; o descarte devolve).
  DELETE FROM public.app_config WHERE chave IN ('supabase_url', 'supabase_anon_key');

  -- Agente ativo e vencido: se houvesse dispatch, a agenda avançaria.
  INSERT INTO public.youreyes_agentes (nome, ativo, periodicidade, proxima_execucao)
  VALUES ('[QA-EDGE1] Agente de teste', true, 'diaria', now() - interval '1 minute')
  RETURNING id, proxima_execucao INTO v_ag, v_antes;

  PERFORM public.youreyes_dispatch_agentes();

  SELECT proxima_execucao INTO v_depois FROM public.youreyes_agentes WHERE id = v_ag;

  IF v_depois IS NOT DISTINCT FROM v_antes THEN
    r.situacao := 'passou';
    r.obtido := 'Sem config de ambiente, o disparo não tocou o agente (não chamou ninguém). Proteção de ambiente OK.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'A rotina de disparo avançou a agenda mesmo sem supabase_url/anon_key — chamaria a Edge Function.';
  END IF;
  r.detalhe := jsonb_build_object('antes', v_antes, 'depois', v_depois);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── EDGE-006: service_role não vive no app_config ───────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_edge_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA: procurar segredo service_role no app_config';
  r.esperado := 'Nenhuma chave de service_role guardada no banco (fica só no servidor)';

  SELECT string_agg(chave, ', ' ORDER BY chave) INTO v_lista
  FROM public.app_config
  WHERE chave ILIKE '%service_role%' OR chave ILIKE '%service%key%' OR chave ILIKE '%role%secret%';

  IF v_lista IS NULL THEN
    r.situacao := 'passou';
    r.obtido := 'Nenhum segredo service_role no app_config — a chave que bypassa RLS fica só na Edge Function.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Chave(s) suspeita(s) de service_role no app_config (legível do cliente): ' || v_lista;
    r.detalhe := jsonb_build_object('chaves', v_lista);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── EDGE-007: todo link por token tem validade ─────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_edge_007()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA: toda tabela *_links de acesso por token tem coluna de validade';
  r.esperado := 'Nenhum link por token sem expiração (senão vira porta aberta)';

  SELECT string_agg(t.table_name, ', ' ORDER BY t.table_name) INTO v_lista
  FROM information_schema.tables t
  WHERE t.table_schema = 'public' AND t.table_type = 'BASE TABLE' AND t.table_name LIKE '%\_links'
    AND EXISTS (SELECT 1 FROM information_schema.columns c
                 WHERE c.table_schema = 'public' AND c.table_name = t.table_name AND c.column_name = 'token')
    AND NOT EXISTS (SELECT 1 FROM information_schema.columns c
                     WHERE c.table_schema = 'public' AND c.table_name = t.table_name
                       AND c.column_name IN ('expira_em', 'valido_ate', 'expires_at', 'data_expiracao'));

  IF v_lista IS NULL THEN
    r.situacao := 'passou';
    r.obtido := 'Todo link público por token tem coluna de validade (expiração).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Tabela(s) de link por token SEM coluna de validade: ' || v_lista;
    r.detalhe := jsonb_build_object('tabelas', v_lista);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── Ligar caso ↔ rotina ─────────────────────────────────────────────────────
INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
  ('EDGE-001', 'qa_caso_edge_001', true),
  ('EDGE-006', 'qa_caso_edge_006', true),
  ('EDGE-007', 'qa_caso_edge_007', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
