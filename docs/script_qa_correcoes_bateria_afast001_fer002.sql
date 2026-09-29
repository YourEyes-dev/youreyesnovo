-- ============================================================================
-- ENTREGA — Correções da bateria: AFAST-001 e FER-002 (bug real, vermelho nos DOIS)
--
-- Cole no SQL Editor da HOMOLOGAÇÃO primeiro; depois de conferido, na PRODUÇÃO.
-- Mesmo script nos dois (forward-only).
--
-- AFAST-001: qa_caso_afast_001 chamava afastamento_encerrar_vencidos() sem
--   escopo — rotina que encerra vencidos em TODOS os tenants (certo para o cron
--   das 03h). Num ambiente com afastamento legado ativo-e-vencido de cliente
--   real (a homologação tem), o UPDATE global cruza esse tenant e a cerca do
--   cercado — corretamente — aborta ("QA BLOQUEADO ... tentou tocar o tenant").
--   Correção: afastamento_encerrar_vencidos ganha filtro OPCIONAL de tenant
--   (NULL = global, cron intacto); a rotina de QA passa o cercado.
--
-- FER-002: qa_caso_fer_002 fazia min(tabela_id) com tabela_id uuid — o
--   PostgreSQL não tem min/max para uuid ("function min(uuid) does not exist").
--   Correção: (array_agg(tabela_id))[1], que existe para uuid; a contagem
--   esperada é 1, então a asserção é preservada.
--
-- Só troca funções (produção: comportamento default idêntico; QA: read-only).
-- Não cria tabela, não apaga dado. Idempotente. Roda numa transação.
-- ============================================================================

SET lock_timeout = '10s';

-- AFAST-001 · 1) filtro opcional de tenant (0 arg → 1 arg com default)
DROP FUNCTION IF EXISTS public.afastamento_encerrar_vencidos();

CREATE OR REPLACE FUNCTION public.afastamento_encerrar_vencidos(p_tenant uuid DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_encerrados integer := 0;
BEGIN
  WITH fim AS (
    UPDATE public.afastamentos a
       SET status = 'encerrado'
     WHERE a.status::text = 'ativo'
       AND a.data_fim IS NOT NULL
       AND a.data_fim < CURRENT_DATE
       AND (p_tenant IS NULL OR a.tenant_id = p_tenant)
       AND NOT public.afastamento_sem_prazo_e_legitimo(
             a.prazo_indeterminado, a.status::text,
             a.status_geral_new::text, a.tipo_principal_new::text)
    RETURNING a.id
  )
  SELECT count(*) INTO v_encerrados FROM fim;
  RETURN v_encerrados;
END;
$fn$;

COMMENT ON FUNCTION public.afastamento_encerrar_vencidos(uuid) IS
  'Encerra afastamentos vencidos. p_tenant NULL (default) = todos os tenants (cron diário); informado = só aquele tenant (rotinas de QA, que só escrevem no cercado).';

-- AFAST-001 · 2) a rotina de QA escopa a chamada ao cercado
CREATE OR REPLACE FUNCTION public.qa_caso_afast_001()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE
  r public.qa_retorno;
  v_id uuid;
  v_st text;
  v_n  int;
  v_cercado uuid := public.qa_sandbox_tenant_id();
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Registrar afastamento cujo período de término já passou';
  r.esperado    := 'Não permanece ativo — encerra pelo gatilho ou pela rotina';

  v_id := public.qa_afast_legado('QA Vencido', CURRENT_DATE - 40);
  UPDATE public.afastamentos SET data_fim = CURRENT_DATE - 10 WHERE id = v_id;

  SELECT public.afastamento_encerrar_vencidos(v_cercado) INTO v_n;
  SELECT status::text INTO v_st FROM public.afastamentos WHERE id = v_id;

  IF v_st <> 'encerrado' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: afastamento com término em %s continua como "%s". Enquanto '
             || 'contar como ativo, ele infla a régua dos 15 dias e o absenteísmo, e mantém o '
             || 'colaborador impedido de bater ponto — o RH só sai disso apagando o registro.',
             to_char(CURRENT_DATE - 10, 'DD/MM/YYYY'), v_st);
    RETURN r;
  END IF;

  r.passo_ordem := 2;
  r.passo_acao  := 'Rodar a rotina de encerramento de novo';
  r.esperado    := 'Nada muda — ela roda todo dia e precisa ser inócua quando não há o que fazer';
  SELECT public.afastamento_encerrar_vencidos(v_cercado) INTO v_n;

  IF v_n <> 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('A rotina não é idempotente: na segunda execução ainda encerrou %s '
                    || 'registro(s).', v_n);
    RETURN r;
  END IF;

  r.situacao := 'passou';
  r.obtido := 'Vencido não fica ativo, e rodar a rotina de novo não mexe em nada.';
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- FER-002 · min(uuid) → (array_agg(uuid))[1]
CREATE OR REPLACE FUNCTION public.qa_caso_fer_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_emp uuid; v_tab1 uuid; v_tab2 uuid; v_n int; v_qual uuid;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_emp  := public.qa_nova_empresa('[QA-FER] Unidade Troca', '11222333007202');
  v_tab1 := public.qa_nova_tabela_feriados('[QA-FER] Tabela Antiga');
  v_tab2 := public.qa_nova_tabela_feriados('[QA-FER] Tabela Nova');
  INSERT INTO public.feriado_tabela_empresas (tenant_id, tabela_id, empresa_id)
  VALUES (v_t, v_tab1, v_emp);

  r.passo_ordem := 1; r.passo_acao := 'Trocar a tabela (remover a antiga, gravar a nova)';
  r.esperado := 'Após a troca, exatamente um vínculo, apontando a tabela nova';
  DELETE FROM public.feriado_tabela_empresas WHERE empresa_id = v_emp;
  INSERT INTO public.feriado_tabela_empresas (tenant_id, tabela_id, empresa_id)
  VALUES (v_t, v_tab2, v_emp);

  SELECT count(*), (array_agg(tabela_id))[1] INTO v_n, v_qual
  FROM public.feriado_tabela_empresas WHERE empresa_id = v_emp;
  IF v_n <> 1 OR v_qual <> v_tab2 THEN
    r.situacao := 'falhou';
    r.obtido := format('Após a troca: %s vínculo(s), tabela %s.', v_n, v_qual);
    RETURN r;
  END IF;

  r.passo_ordem := 2; r.passo_acao := 'Selecionar a opção sem tabela';
  r.esperado := 'Unidade fica sem vínculo, sem erro';
  DELETE FROM public.feriado_tabela_empresas WHERE empresa_id = v_emp;
  SELECT count(*) INTO v_n FROM public.feriado_tabela_empresas WHERE empresa_id = v_emp;
  IF v_n = 0 THEN
    r.situacao := 'passou'; r.obtido := 'Troca substitui; desvincular zera sem erro.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('Sobraram %s vínculo(s) após desvincular.', v_n);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- Conferência (única): esperado 2 linhas 'ok'
WITH conf AS MATERIALIZED (
  SELECT 'AFAST-001: encerrar_vencidos aceita filtro de tenant'::text AS item,
         (SELECT pg_get_function_identity_arguments('public.afastamento_encerrar_vencidos(uuid)'::regprocedure) = 'p_tenant uuid') AS ok
  UNION ALL
  SELECT 'FER-002: qa_caso_fer_002 sem min(uuid)'::text,
         (SELECT pg_get_functiondef('public.qa_caso_fer_002()'::regprocedure) !~* 'min\s*\(\s*tabela_id')
)
SELECT item, CASE WHEN ok THEN 'ok' ELSE 'CONFERIR' END AS situacao FROM conf;
