-- ============================================================================
-- ENTREGA — a massa da bancada de testes passa a ser REAPROVEITADA
--
-- Vale para o ambiente que RODA a bateria (teste e homologacao). Nao toca em
-- regra de negocio nenhuma: mexe so nas duas ferramentas que a propria bancada
-- usa para montar empresa e admissao de mentira.
--
-- POR QUE
-- Elas sempre INSERIAM. Se uma sonda e interrompida no meio — tipico de
-- ambiente onde a peca que ela exercita ainda nao chegou —, sobra a empresa
-- criada e o resto nao. Na execucao seguinte, recriar a MESMA empresa/admissao
-- bate nas travas do proprio sistema ("Ja existe outra empresa ATIVA com o
-- CNPJ ...", uq_admissoes_cpf_ativa) e a sonda passa a devolver ERRO para
-- sempre, num ambiente que ja pode estar correto — com o achado verdadeiro
-- sumindo atras de "a rotina quebrou".
--
-- Depois desta entrega, as ferramentas procuram antes de criar. Em ambiente
-- limpo nada muda: a primeira execucao cria igual.
--
-- Somente CREATE OR REPLACE de duas funcoes de teste. Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_nova_empresa(
  p_razao text, p_cnpj text, p_ativo boolean DEFAULT true)
RETURNS uuid
LANGUAGE plpgsql
AS $function$
DECLARE
  v_t  uuid := public.qa_sandbox_tenant_id();
  v_id uuid;
BEGIN
  -- Reaproveita a empresa do cercado com o mesmo CNPJ, se ela ja existe.
  SELECT e.id INTO v_id
  FROM public.empresa_cadastro e
  WHERE e.tenant_id = v_t AND e.cnpj = p_cnpj
  ORDER BY (e.ativo IS TRUE) DESC, e.created_at NULLS LAST
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    UPDATE public.empresa_cadastro
       SET razao_social = p_razao, nome_fantasia = p_razao, ativo = p_ativo
     WHERE id = v_id;
    RETURN v_id;
  END IF;

  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
  VALUES (v_t, p_razao, p_razao, p_cnpj, p_ativo)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.qa_ponto_admissao(
  p_nome text, p_cpf_semente integer, p_empresa_id uuid DEFAULT NULL::uuid,
  p_data_admissao date DEFAULT (CURRENT_DATE - 60))
RETURNS text
LANGUAGE plpgsql
AS $function$
DECLARE
  v_t   uuid := public.qa_sandbox_tenant_id();
  v_cpf text := public.qa_cpf(p_cpf_semente);
  v_id  uuid;
BEGIN
  -- Reaproveita a admissao do cercado com o mesmo CPF, se ela ja existe.
  SELECT a.id INTO v_id
  FROM public.admissoes a
  WHERE a.tenant_id = v_t AND a.cpf = v_cpf
  ORDER BY (a.status = 'concluido') DESC, a.created_at NULLS LAST
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    UPDATE public.admissoes
       SET nome_completo = p_nome,
           status        = 'concluido',
           data_admissao = p_data_admissao,
           empresa_id    = COALESCE(p_empresa_id, empresa_id)
     WHERE id = v_id;
    RETURN v_cpf;
  END IF;

  INSERT INTO public.admissoes
    (tenant_id, nome_completo, cpf, email, cargo, status, data_admissao, empresa_id)
  VALUES (v_t, p_nome, v_cpf,
          public.qa_fixture_email('PONTO-AGO', p_cpf_semente),
          'Operador', 'concluido', p_data_admissao, p_empresa_id);
  RETURN v_cpf;
END $function$;

DO $fim$
BEGIN
  RAISE NOTICE 'Massa de teste reaproveitavel: qa_nova_empresa e qa_ponto_admissao procuram antes de criar.';
END $fim$;

-- ============================================================================
-- CONFERENCIA
-- ============================================================================
SELECT
  (SELECT position('Reaproveita a empresa' in p.prosrc) > 0
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'qa_nova_empresa')    AS empresa_reaproveita,
  (SELECT position('Reaproveita a admissao' in p.prosrc) > 0
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'qa_ponto_admissao')  AS admissao_reaproveita,
  CASE WHEN (SELECT position('Reaproveita a empresa' in p.prosrc) > 0
               FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'qa_nova_empresa')
        AND (SELECT position('Reaproveita a admissao' in p.prosrc) > 0
               FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'qa_ponto_admissao')
       THEN 'OK' ELSE 'CONFERIR' END                                 AS erro_tecnico;
