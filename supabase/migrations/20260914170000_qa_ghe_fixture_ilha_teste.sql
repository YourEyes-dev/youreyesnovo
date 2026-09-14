-- =========================================================
-- QA — GHE (psicossocial): fixture na ILHA DE TESTE
--
-- A criação de campanha psicossocial (caso TC-01) exige um GHE ATIVO na
-- empresa. Nada semeava GHE (nem staging.sql, nem migration): no ambiente de
-- teste o caso só passava por GHEs deixados por corridas antigas (frágil).
-- Esta migration planta UM GHE ativo na ilha do TESTE, de forma determinística.
-- Na homologação o mesmo GHE vem da função de seed (semearGhe).
--
-- SEGURANÇA (mesmo padrão das outras fixtures):
-- - Só semeia onde a ilha existe (tenant + empresa fixos). Fora dela: no-op;
--   EXCEPTION protege. Produção nunca roda migration. Dado 100% fictício.
-- - Idempotente: guarda pelo código GHE-001.
-- =========================================================

SET lock_timeout = '10s';

DO $seed_ghe$
DECLARE
  v_tenant  uuid := '11111111-1111-1111-1111-111111111111';
  v_empresa uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.tenants WHERE id = v_tenant)
     OR NOT EXISTS (SELECT 1 FROM public.empresa_cadastro WHERE id = v_empresa) THEN
    RAISE NOTICE 'Ilha de teste ausente (tenant/empresa) — GHE fictício não semeado.';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.psicossocial_ghe
    WHERE tenant_id = v_tenant AND codigo = 'GHE-001'
  ) THEN
    RAISE NOTICE 'GHE fictício já semeado — nada a fazer.';
    RETURN;
  END IF;

  INSERT INTO public.psicossocial_ghe
    (tenant_id, empresa_id, codigo, nome, descricao, ativo)
  VALUES
    (v_tenant, v_empresa, 'GHE-001', 'Administrativo (QA)',
     'GHE fictício de QA para campanhas psicossociais.', true);

  RAISE NOTICE 'GHE fictício (GHE-001) semeado na ilha de teste.';

EXCEPTION
  WHEN foreign_key_violation OR not_null_violation OR raise_exception THEN
    RAISE NOTICE 'GHE fictício não semeado (ambiente sem a ilha de teste): %', SQLERRM;
END $seed_ghe$;
