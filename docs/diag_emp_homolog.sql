-- ============================================================================
-- DIAGNOSTICO EMP-020 (somente leitura) — rodar na HOMOLOGACAO.
-- Descobre por que o gatilho barra CPF mas nao CNPJ. Uma consulta, varias linhas.
-- ============================================================================
WITH
trigs AS (
  SELECT string_agg(tg.tgname || ' -> ' || p.proname
           || ' [' || CASE WHEN (tg.tgtype & 4)=4 THEN 'INS ' ELSE '' END
           || CASE WHEN (tg.tgtype & 16)=16 THEN 'UPD' ELSE '' END || ']', ' ; ') AS v
  FROM pg_trigger tg JOIN pg_proc p ON p.oid = tg.tgfoid
  WHERE tg.tgrelid = 'public.empresa_cadastro'::regclass AND NOT tg.tgisinternal
),
fn AS (
  SELECT (prosrc ILIKE '%cnpj_norm%')::text AS checa_cnpj,
         (prosrc ILIKE '%cpf_norm%')::text  AS checa_cpf
  FROM pg_proc WHERE proname = 'prevent_duplicate_active_cnpj'
    AND pronamespace = 'public'::regnamespace
)
SELECT '1. gatilhos em empresa_cadastro' AS item, COALESCE((SELECT v FROM trigs), '(nenhum)') AS valor
UNION ALL
SELECT '2. funcao prevent_duplicate_active_cnpj checa CNPJ',
       COALESCE((SELECT checa_cnpj FROM fn), '(funcao ausente)')
UNION ALL
SELECT '3. funcao prevent_duplicate_active_cnpj checa CPF',
       COALESCE((SELECT checa_cpf FROM fn), '(funcao ausente)')
UNION ALL
SELECT '4. EMP-020 obtido', left((public.qa_executar_descartavel('qa_caso_emp_020')).obtido, 240)
ORDER BY item;
