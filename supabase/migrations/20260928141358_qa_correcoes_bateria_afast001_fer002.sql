-- ============================================================================
-- QA · Correções da bateria — AFAST-001 e FER-002 (vermelhos nos DOIS ambientes)
--
-- Diferente das demais correções desta leva, estes dois são bug de código real
-- (não "homologação atrasada"): reproduzem em teste e em homologação. Por isso
-- entram pela esteira (migration) e também vão em script de entrega.
--
-- ── AFAST-001 — a rotina de QA arrastava a cerca para dados reais ───────────
-- erro_tecnico na homologação:
--   "QA BLOQUEADO: modo de teste ligado. Operacao UPDATE em public.afastamentos
--    tentou tocar o tenant 83f1b040-... Permitido apenas os cercados."
-- Causa: qa_caso_afast_001 chamava afastamento_encerrar_vencidos() SEM escopo.
-- Essa rotina encerra vencidos em TODOS os tenants (é o certo para o cron das
-- 03h). Mas num ambiente com afastamento legado ativo-e-vencido de cliente
-- (a homologação tem; um banco só-migrations não, porque o gatilho de 13/08
-- impede o registro de nascer assim) o UPDATE global tenta tocar esse tenant
-- real e a cerca — corretamente — aborta. O cercado é o certo; quem estava
-- errado era a rotina de teste, que só deve escrever no cercado.
-- Correção: afastamento_encerrar_vencidos ganha um filtro OPCIONAL de tenant
-- (p_tenant); NULL = global (cron intacto). A rotina de QA passa o cercado, e
-- assim exercita a mesma lógica sem tocar dado real.
--
-- ── FER-002 — min(uuid) não existe ──────────────────────────────────────────
-- erro_tecnico: "function min(uuid) does not exist".
-- qa_caso_fer_002 fazia SELECT ..., min(tabela_id) — e tabela_id é uuid, tipo
-- para o qual o PostgreSQL não tem agregado min/max. Erra em qualquer base.
-- Correção: como a contagem esperada é 1, troca min(tabela_id) por
-- (array_agg(tabela_id))[1], que existe para uuid e preserva a asserção.
--
-- Só troca funções (uma de produção, com comportamento default idêntico; duas
-- rotinas de QA read-only). Não cria tabela nem apaga dado. Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- ── AFAST-001, parte 1: encerrar_vencidos com filtro opcional de tenant ─────
-- Muda a assinatura (0 → 1 arg com default), então DROP + CREATE. O cron chama
-- por nome sem argumento e continua resolvendo para o default (NULL = global).
DROP FUNCTION IF EXISTS public.afastamento_encerrar_vencidos();

CREATE OR REPLACE FUNCTION public.afastamento_encerrar_vencidos(p_tenant uuid DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_encerrados integer := 0;
BEGIN
  WITH fim AS (
    UPDATE public.afastamentos a
       SET status = 'encerrado'
     WHERE a.status::text = 'ativo'
       AND a.data_fim IS NOT NULL
       AND a.data_fim < CURRENT_DATE
       AND (p_tenant IS NULL OR a.tenant_id = p_tenant)   -- NULL = global (cron)
       AND NOT public.afastamento_sem_prazo_e_legitimo(
             a.prazo_indeterminado, a.status::text,
             a.status_geral_new::text, a.tipo_principal_new::text)
    RETURNING a.id
  )
  SELECT count(*) INTO v_encerrados FROM fim;

  RETURN v_encerrados;
END;
$$;

COMMENT ON FUNCTION public.afastamento_encerrar_vencidos(uuid) IS
  'Encerra afastamentos cujo período de término já passou. p_tenant NULL (default) = todos os tenants (uso do cron diário); informado = só aquele tenant (uso das rotinas de QA, que escrevem apenas no cercado).';

-- ── AFAST-001, parte 2: a rotina de QA escopa a chamada ao cercado ──────────
CREATE OR REPLACE FUNCTION public.qa_caso_afast_001()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $$
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

  -- Escopo no cercado: a rotina de encerramento roda global no cron, mas a
  -- prova de QA só pode tocar o cercado (senão a cerca aborta ao cruzar um
  -- afastamento legado de cliente real, como acontece na homologação).
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
END $$;

-- ── FER-002: min(uuid) → (array_agg(uuid))[1] ───────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_fer_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
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

  -- min(uuid) não existe no PostgreSQL; como a contagem esperada é 1, o primeiro
  -- (e único) elemento de array_agg resolve e preserva a asserção.
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
END $$;

-- ── Conferência ─────────────────────────────────────────────────────────────
DO $confere$
DECLARE v_arg text; v_fer_ok boolean;
BEGIN
  SELECT pg_get_function_identity_arguments('public.afastamento_encerrar_vencidos(uuid)'::regprocedure) INTO v_arg;
  v_fer_ok := pg_get_functiondef('public.qa_caso_fer_002()'::regprocedure) !~* 'min\s*\(\s*tabela_id';
  RAISE NOTICE 'Conferência: encerrar_vencidos assinatura = (%) [esperado "p_tenant uuid"]; FER-002 sem min(uuid) = %.',
    v_arg, v_fer_ok;
END $confere$;
