-- ============================================================================
-- BLOCO A1 — Isolamento entre clientes (coerencia de tenant nas chaves).
-- Producao aceitava vinculo cruzando clientes (MCHK-011, PROC-011, FER-004,
-- HCAL-012): a FK aponta uma linha, mas nao confere se ela e do MESMO tenant.
-- O dev ja tem a correcao: uma funcao de gatilho (trg_valida_mesmo_tenant) e
-- gatilhos BEFORE INSERT/UPDATE nas 5 pontes.
--
-- SEGURO SOBRE DADO REAL: so cria funcao + gatilhos. NAO ha constraint que
-- valida linha existente, entao a aplicacao nao pode falhar por dado antigo.
-- Os gatilhos valem para escritas FUTURAS. A conferencia final conta se ja
-- existe alguma linha cruzada hoje (deveria ser 0).
--
-- Aplicar com o ambiente tranquilo (cria gatilho em 4 tabelas): lock_timeout
-- curto + blocos guardados que NAO pegam lock ao rodar de novo. Idempotente.
-- ============================================================================

SET lock_timeout = '5s';

-- 1) Funcao de coerencia de tenant (idempotente)
CREATE OR REPLACE FUNCTION public.trg_valida_mesmo_tenant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_fk_val   uuid;
    v_pai_tnt  uuid;
BEGIN
    EXECUTE format('SELECT ($1).%I', TG_ARGV[0]) INTO v_fk_val USING NEW;
    IF v_fk_val IS NULL THEN
        RETURN NEW;
    END IF;
    EXECUTE format('SELECT tenant_id FROM public.%I WHERE id = $1', TG_ARGV[1])
      INTO v_pai_tnt USING v_fk_val;
    IF v_pai_tnt IS NOT NULL AND v_pai_tnt <> NEW.tenant_id THEN
        RAISE EXCEPTION 'Vinculo entre clientes diferentes vedado: %.% aponta % de outro tenant.',
              TG_TABLE_NAME, TG_ARGV[0], TG_ARGV[1];
    END IF;
    RETURN NEW;
END;
$function$

;

-- 2) Gatilhos nas 5 pontes (um bloco por gatilho; nao pega lock em re-run)
DO $blk$
BEGIN
  PERFORM set_config('lock_timeout','5s',true);
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_feriado_vinculo_empresa_tenant' AND NOT tgisinternal) THEN
    EXECUTE 'CREATE TRIGGER trg_feriado_vinculo_empresa_tenant BEFORE INSERT OR UPDATE ON public.feriado_tabela_empresas FOR EACH ROW EXECUTE FUNCTION trg_valida_mesmo_tenant(''empresa_id'', ''empresa_cadastro'')';
  END IF;
END $blk$;
DO $blk$
BEGIN
  PERFORM set_config('lock_timeout','5s',true);
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_feriado_vinculo_tabela_tenant' AND NOT tgisinternal) THEN
    EXECUTE 'CREATE TRIGGER trg_feriado_vinculo_tabela_tenant BEFORE INSERT OR UPDATE ON public.feriado_tabela_empresas FOR EACH ROW EXECUTE FUNCTION trg_valida_mesmo_tenant(''tabela_id'', ''feriado_tabelas'')';
  END IF;
END $blk$;
DO $blk$
BEGIN
  PERFORM set_config('lock_timeout','5s',true);
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_hub_cal_status_tenant' AND NOT tgisinternal) THEN
    EXECUTE 'CREATE TRIGGER trg_hub_cal_status_tenant BEFORE INSERT OR UPDATE ON public.hub_calendario_status FOR EACH ROW EXECUTE FUNCTION trg_valida_mesmo_tenant(''calendario_id'', ''hub_calendario_envios'')';
  END IF;
END $blk$;
DO $blk$
BEGIN
  PERFORM set_config('lock_timeout','5s',true);
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_hub_processo_contab_tenant' AND NOT tgisinternal) THEN
    EXECUTE 'CREATE TRIGGER trg_hub_processo_contab_tenant BEFORE INSERT OR UPDATE ON public.hub_processos FOR EACH ROW EXECUTE FUNCTION trg_valida_mesmo_tenant(''contabilidade_id'', ''hub_contabilidades'')';
  END IF;
END $blk$;
DO $blk$
BEGIN
  PERFORM set_config('lock_timeout','5s',true);
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_mchk_mesmo_tenant' AND NOT tgisinternal) THEN
    EXECUTE 'CREATE TRIGGER trg_mchk_mesmo_tenant BEFORE INSERT OR UPDATE ON public.metas_checkins FOR EACH ROW EXECUTE FUNCTION trg_valida_mesmo_tenant(''meta_id'', ''metas'')';
  END IF;
END $blk$;

-- ----------------------------------------------------------------------------
-- CONFERENCIA (unico SELECT): funcao + 5 gatilhos presentes; linhas cruzadas
-- que JA existem hoje (deveria ser 0 em cada); e o veredito das rotinas.
-- ----------------------------------------------------------------------------
WITH estrutura AS (
  SELECT 1 ord, 'funcao trg_valida_mesmo_tenant' item,
         (to_regprocedure('public.trg_valida_mesmo_tenant()') IS NOT NULL)::text res
  UNION ALL SELECT 1, 'gatilhos de coerencia instalados (esperado 5)',
         (SELECT count(*)::text FROM pg_trigger tg JOIN pg_proc p ON p.oid=tg.tgfoid
           WHERE p.proname='trg_valida_mesmo_tenant' AND NOT tg.tgisinternal)
),
cruzados AS (
  SELECT 2 ord, 'metas_checkins cruzados (hoje)' item,
         (SELECT count(*)::text FROM public.metas_checkins x JOIN public.metas m ON m.id=x.meta_id WHERE m.tenant_id<>x.tenant_id) res
  UNION ALL SELECT 2, 'hub_processos cruzados (hoje)',
         (SELECT count(*)::text FROM public.hub_processos x JOIN public.hub_contabilidades c ON c.id=x.contabilidade_id WHERE c.tenant_id<>x.tenant_id)
  UNION ALL SELECT 2, 'feriado_tabela_empresas cruzados (hoje)',
         (SELECT count(*)::text FROM public.feriado_tabela_empresas x JOIN public.feriado_tabelas t ON t.id=x.tabela_id WHERE t.tenant_id<>x.tenant_id)
  UNION ALL SELECT 2, 'hub_calendario_status cruzados (hoje)',
         (SELECT count(*)::text FROM public.hub_calendario_status x JOIN public.hub_calendario_envios e ON e.id=x.calendario_id WHERE e.tenant_id<>x.tenant_id)
),
rotinas AS (
  SELECT 3 ord, t.codigo item, (public.qa_executar_descartavel(t.fn)).situacao::text res
  FROM (VALUES ('MCHK-011','qa_caso_mchk_011'),('PROC-011','qa_caso_proc_011'),
               ('FER-004','qa_caso_fer_004'),('HCAL-012','qa_caso_hcal_012')) t(codigo,fn)
  WHERE to_regprocedure('public.'||t.fn||'()') IS NOT NULL
)
SELECT item, res FROM (SELECT * FROM estrutura UNION ALL SELECT * FROM cruzados UNION ALL SELECT * FROM rotinas) z ORDER BY ord, item;
