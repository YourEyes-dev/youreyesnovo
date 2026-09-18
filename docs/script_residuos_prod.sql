-- ============================================================================
-- Residuos do motor — ENTREGA producao (os 4 confirmados verdes na homologacao).
-- COLAB-011/023/033 (CPF) + HIER-002 (FK). SO funcoes/indice/FK.
--
-- NAO inclui as mudancas de afastamento (DESL-003): ainda ha uma peca stale na
-- cadeia de gatilhos de afastamentos que nao fechou o caso na homologacao —
-- fica como item a parte, para nao levar mudanca incompleta de dado real a
-- producao.
--
-- Causas cobertas aqui:
--  - COLAB-011/023/033: qa_cpf stale gerava CPF com DV invalido; o validador
--    real recusava. Reentrega qa_cpf/qa_cpf_formatado (helpers de QA).
--  - COLAB-033: indice unico de CPF normalizado (guardado contra legado).
--  - HIER-002: FK grupo_economico recriada com ON DELETE SET NULL.
--
-- So cria/atualiza; nao altera dado. Idempotente. A conferencia esta em
-- docs/conferencia_residuos.sql (rodar depois, em transacao propria).
-- ============================================================================

SET lock_timeout = '10s';

-- Helper de QA: gerador de CPF com digito verificador valido ------------------
CREATE OR REPLACE FUNCTION public.qa_cpf(p_semente integer)
RETURNS text LANGUAGE plpgsql IMMUTABLE
AS $fn$
DECLARE
  v_base text; v_d int[]; v_soma int; v_dv1 int; v_dv2 int; i int;
BEGIN
  v_base := '999' || lpad((abs(p_semente) % 1000000)::text, 6, '0');
  SELECT array_agg(substring(v_base FROM g FOR 1)::int ORDER BY g)
    INTO v_d FROM generate_series(1, 9) g;
  v_soma := 0;
  FOR i IN 1..9 LOOP v_soma := v_soma + v_d[i] * (11 - i); END LOOP;
  v_dv1 := 11 - (v_soma % 11);
  IF v_dv1 >= 10 THEN v_dv1 := 0; END IF;
  v_soma := 0;
  FOR i IN 1..9 LOOP v_soma := v_soma + v_d[i] * (12 - i); END LOOP;
  v_soma := v_soma + v_dv1 * 2;
  v_dv2 := 11 - (v_soma % 11);
  IF v_dv2 >= 10 THEN v_dv2 := 0; END IF;
  RETURN v_base || v_dv1::text || v_dv2::text;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_cpf_formatado(p_cpf text)
RETURNS text LANGUAGE sql IMMUTABLE
AS $fn$
  SELECT format('%s.%s.%s-%s',
                substr(p_cpf,1,3), substr(p_cpf,4,3), substr(p_cpf,7,3), substr(p_cpf,10,2))
$fn$;

-- COLAB-033: indice unico de CPF normalizado (so onde a base esta limpa) ------
DO $do$
BEGIN
  IF to_regclass('public.usuarios_base_cpf_norm_tenant_uidx') IS NULL THEN
    CREATE UNIQUE INDEX usuarios_base_cpf_norm_tenant_uidx
      ON public.usuarios_base (tenant_id, regexp_replace(cpf, '[^0-9]', '', 'g'))
      WHERE cpf IS NOT NULL AND regexp_replace(cpf, '[^0-9]', '', 'g') <> '';
  END IF;
EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'usuarios_base_cpf_norm_tenant_uidx nao criado: ha CPF normalizado duplicado no legado. COLAB-033 segue vermelho ate a limpeza a parte.';
END $do$;

-- HIER-002: FK grupo_economico com ON DELETE SET NULL ------------------------
DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname='empresa_cadastro_grupo_economico_id_fkey'
                    AND conrelid='public.empresa_cadastro'::regclass
                    AND confdeltype='n') THEN
    ALTER TABLE public.empresa_cadastro
      DROP CONSTRAINT IF EXISTS empresa_cadastro_grupo_economico_id_fkey;
    ALTER TABLE public.empresa_cadastro
      ADD CONSTRAINT empresa_cadastro_grupo_economico_id_fkey
      FOREIGN KEY (grupo_economico_id) REFERENCES public.grupos_economicos(id)
      ON DELETE SET NULL NOT VALID;
  END IF;
END $do$;
DO $do$
BEGIN
  ALTER TABLE public.empresa_cadastro
    VALIDATE CONSTRAINT empresa_cadastro_grupo_economico_id_fkey;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'FK grupo_economico permanece NOT VALID (ha empresa apontando para grupo inexistente no legado); a acao ON DELETE SET NULL ja vale.';
END $do$;

-- Confirmacao leve (so catalogo) ---------------------------------------------
SELECT 'qa_cpf(1033) valido?' AS item,
       CASE WHEN public.qa_cpf(1033) = '99900103319' THEN 'sim' ELSE 'gerou: ' || public.qa_cpf(1033) END AS valor
UNION ALL
SELECT 'COLAB-033 indice',
       COALESCE((SELECT 'presente' FROM pg_class WHERE relname='usuarios_base_cpf_norm_tenant_uidx'),
                'ausente (legado duplicado)')
UNION ALL
SELECT 'HIER-002 FK ON DELETE',
       (SELECT CASE confdeltype WHEN 'n' THEN 'SET NULL (ok)' ELSE confdeltype::text END
          FROM pg_constraint WHERE conname='empresa_cadastro_grupo_economico_id_fkey'
            AND conrelid='public.empresa_cadastro'::regclass)
UNION ALL
SELECT 'LEGADO: grupos de CPF normalizado duplicado em usuarios_base',
       (SELECT count(*)::text FROM (
          SELECT tenant_id, regexp_replace(cpf,'[^0-9]','','g') AS d
          FROM public.usuarios_base
          WHERE cpf IS NOT NULL AND regexp_replace(cpf,'[^0-9]','','g') <> ''
          GROUP BY 1,2 HAVING count(*) > 1) x)
ORDER BY item;
