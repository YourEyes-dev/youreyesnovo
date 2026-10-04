-- =====================================================================
-- ENTREGA — QA SEC-001: SECURITY DEFINER sem search_path travado
-- (colar no SQL Editor; rodar em producao SO apos aprovado no teste)
--
-- O que faz:
--   1) trava o search_path das 5 funcoes SECURITY DEFINER que faltavam
--      (padrao da casa: SET search_path = public);
--   2) cria a varredura qa_caso_sec_001() que passa a ACUSAR qualquer
--      funcao nova SECURITY DEFINER sem a trava;
--   3) documenta e liga o caso SEC-001 no motor de QA.
--
-- Seguro: so cria/altera FUNCAO e insere metadado de QA. NAO cria TABELA
-- (nao aciona o auto-RLS do editor) e NAO altera/apaga dado de negocio
-- (dispensa backup). Idempotente: rodar duas vezes nao quebra nem duplica.
-- =====================================================================

-- 1) Endurecer as 5 conhecidas (busca por nome, trava por identidade).
DO $harden$
DECLARE f record; v_n int := 0;
BEGIN
  FOR f IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND p.proname IN (
        'gaf_tem_acesso_sensivel', 'obter_contrato_publico',
        'registrar_assinatura_contrato', 'superadmin_set_principal_empresa',
        'trg_gaf_auditoria_afastamentos')
      AND NOT EXISTS (
        SELECT 1 FROM unnest(COALESCE(p.proconfig,'{}')) c WHERE c LIKE 'search_path=%')
  LOOP
    BEGIN
      EXECUTE format('ALTER FUNCTION public.%I(%s) SET search_path = public', f.proname, f.args);
      v_n := v_n + 1;
      RAISE NOTICE 'search_path travado em %(%)', f.proname, f.args;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Nao consegui travar %(%): %', f.proname, f.args, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE 'SEC-001: % funcao(oes) endurecida(s).', v_n;
END $harden$;

-- 2) A varredura (somente leitura).
CREATE OR REPLACE FUNCTION public.qa_caso_sec_001()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE r public.qa_retorno; v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): funcoes SECURITY DEFINER em public sem search_path travado';
  r.esperado    := 'Nenhuma funcao SECURITY DEFINER sem SET search_path';

  SELECT string_agg(sig, ', ' ORDER BY sig) INTO v_lista
  FROM (
    SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND NOT EXISTS (
        SELECT 1 FROM unnest(COALESCE(p.proconfig,'{}')) c WHERE c LIKE 'search_path=%')
      AND NOT EXISTS (
        SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
  ) x;

  IF v_lista IS NULL THEN
    r.situacao := 'passou';
    r.obtido   := 'Nenhuma funcao SECURITY DEFINER em public sem search_path travado.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := 'Funcao(oes) SECURITY DEFINER SEM search_path travado: ' || v_lista
      || '. Corrigir com ALTER FUNCTION ... SET search_path = public (padrao da casa). '
      || 'Sem a trava, quem controla o search_path da sessao desvia chamadas nao '
      || 'qualificadas para funcoes maliciosas, executadas com os poderes do dono.';
    r.detalhe := jsonb_build_object('funcoes', v_lista);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $fn$;

-- 3) Documentar e ligar o caso (idempotente).
INSERT INTO public.qa_casos_teste
  (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, resultado_esperado, base_legal)
SELECT m.id, 'SEC-001',
  'Funcao SECURITY DEFINER sem search_path travado e acusada',
  'negativo', 'critica', 'aprovado', 'api',
  'Garantir que toda funcao com poderes elevados (SECURITY DEFINER) fixe o '
   || 'search_path, fechando o vetor classico de escalonamento de privilegio. '
   || 'A varredura se estende sozinha: funcao nova sem a trava e acusada.',
  'Nenhuma funcao SECURITY DEFINER em public sem SET search_path.',
  'Boa pratica de seguranca PostgreSQL (CVE-2018-1058); LGPD art. 46 (medidas de seguranca).'
FROM public.qa_modulos m
WHERE m.path = 'infraestrutura-auth/rls'
ON CONFLICT (codigo) DO UPDATE SET
  titulo = EXCLUDED.titulo, tipo = EXCLUDED.tipo, prioridade = EXCLUDED.prioridade,
  status = EXCLUDED.status, nivel = EXCLUDED.nivel, objetivo = EXCLUDED.objetivo,
  resultado_esperado = EXCLUDED.resultado_esperado, base_legal = EXCLUDED.base_legal;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo, criado_em)
VALUES ('SEC-001', 'qa_caso_sec_001', true, now())
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- 4) CONFERENCIA FINAL (o editor mostra so o ultimo resultado).
--    Deve vir situacao = passou e restantes = 0.
SELECT s.situacao,
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.prosecdef
           AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(p.proconfig,'{}')) c WHERE c LIKE 'search_path=%')
           AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
       ) AS funcoes_ainda_sem_trava,
       s.obtido
FROM public.qa_caso_sec_001() s;
