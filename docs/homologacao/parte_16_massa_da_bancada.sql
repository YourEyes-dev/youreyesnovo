-- ============================================================================
-- HOMOLOGACAO — PONTO, PARTE 16 de 16: A massa da bancada passa a ser reaproveitada
--
-- Ajuste so da bancada de testes: as ferramentas que montam empresa e
-- admissao de mentira procuram antes de criar, para que uma sonda
-- interrompida no meio nao deixe a proxima execucao presa em ERRO por massa
-- pela metade.
--
-- ONDE COLAR
-- No SQL Editor do projeto de HOMOLOGACAO. Nao e para a producao: a producao
-- so muda por gesto manual seu, depois de conferida aqui.
--
-- COMO USAR
-- Cole o arquivo INTEIRO e execute uma vez. Pode rodar de novo sem risco
-- (idempotente). As partes tem ordem: rode da 01 para a 16, conferindo o
-- resultado de cada uma antes de passar para a seguinte.
--
-- O QUE ESTE ARQUIVO REUNE
--   * script_qa_massa_reaproveitavel.sql
--
-- Ao final sai UMA conferencia, dizendo o que chegou e o que faltou.
-- ============================================================================



-- ############################################################
-- BLOCO: script_qa_massa_reaproveitavel.sql
-- ############################################################

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


-- ============================================================================
-- CONFERENCIA DESTA PARTE
-- Lista o que a parte deveria deixar no ambiente e diz o que chegou. A ultima
-- linha resume: OK quando nada faltou.
-- ============================================================================
WITH esperado (tipo, nome, marcador) AS MATERIALIZED (
  VALUES
    ('funcao', 'qa_nova_empresa', NULL),
    ('funcao', 'qa_ponto_admissao', NULL)
), estado AS MATERIALIZED (
  SELECT e.tipo, e.nome, e.marcador,
         CASE e.tipo
           WHEN 'funcao'  THEN EXISTS (SELECT 1 FROM pg_proc p
                                        JOIN pg_namespace n ON n.oid = p.pronamespace
                                       WHERE n.nspname = 'public' AND p.proname = e.nome
                                         AND (e.marcador IS NULL
                                              OR p.prosrc LIKE '%' || e.marcador || '%'))
           WHEN 'tabela'  THEN to_regclass('public.' || e.nome) IS NOT NULL
           WHEN 'indice'  THEN EXISTS (SELECT 1 FROM pg_indexes
                                       WHERE schemaname = 'public' AND indexname = e.nome)
           WHEN 'gatilho' THEN EXISTS (SELECT 1 FROM pg_trigger
                                       WHERE NOT tgisinternal AND tgname = e.nome)
           WHEN 'coluna'  THEN EXISTS (SELECT 1 FROM information_schema.columns
                                       WHERE table_schema = 'public'
                                         AND table_name  = split_part(e.nome, '.', 1)
                                         AND column_name = split_part(e.nome, '.', 2))
         END AS presente
  FROM esperado e
)
SELECT tipo, nome, CASE WHEN presente THEN 'chegou' ELSE 'FALTOU' END AS situacao
FROM estado
WHERE NOT presente
UNION ALL
SELECT 'RESUMO',
       (SELECT count(*) FROM estado WHERE presente)::text || ' de '
         || (SELECT count(*) FROM estado)::text || ' pecas no lugar',
       CASE WHEN (SELECT count(*) FROM estado WHERE NOT presente) = 0
            THEN 'OK' ELSE 'CONFERIR as linhas acima' END
ORDER BY 1 DESC, 2;
