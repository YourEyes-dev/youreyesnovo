-- ============================================================================
-- BLOCO A2 — Duplicidade (unicidade de CPF/CNPJ/vinculo).
-- Producao aceitava duplicatas (EMP-020/021 CNPJ, EMP-070/071 CPF de empresa,
-- ADM-002 CPF em admissoes, VIN-008 vinculo). O dev ja tem a correcao.
--
-- DUAS naturezas:
--  (1) GATILHO de CNPJ (prevent_duplicate_active_cnpj): so valida gravacao
--      FUTURA — seguro sobre dado existente.
--  (2) TRES INDICES UNICOS (empresa CPF, admissoes CPF, vinculo): um indice
--      unico FALHA se a producao ja tiver duplicata. Por isso cada indice aqui
--      so e criado SE NAO houver duplicata hoje; havendo, o bloco NAO cria e
--      AVISA quantos grupos duplicados existem — para limpeza a parte (com
--      backup). O script NUNCA falha e NUNCA apaga dado.
--
-- Idempotente; blocos guardados (re-run nao pega lock); lock_timeout curto.
-- Aplicar com o ambiente tranquilo.
-- ============================================================================

SET lock_timeout = '5s';

-- (1) GATILHO de CNPJ duplicado — seguro (valida so escrita futura)
CREATE OR REPLACE FUNCTION public.prevent_duplicate_active_cnpj()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  cnpj_norm text := regexp_replace(coalesce(NEW.cnpj,''), '[^0-9]', '', 'g');
BEGIN
  IF NEW.ativo IS TRUE AND cnpj_norm <> '' THEN
    IF EXISTS (
      SELECT 1 FROM public.empresa_cadastro
      WHERE id <> NEW.id
        AND tenant_id = NEW.tenant_id
        AND ativo = true
        AND regexp_replace(coalesce(cnpj,''), '[^0-9]', '', 'g') = cnpj_norm
    ) THEN
      RAISE EXCEPTION 'Já existe outra empresa ATIVA com o CNPJ % neste tenant. Desative a duplicata antes de ativar esta.', NEW.cnpj
        USING ERRCODE = 'unique_violation';
    END IF;
  END IF;
  RETURN NEW;
END $function$

;
DO $blk$
BEGIN
  PERFORM set_config('lock_timeout','5s',true);
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_prevent_duplicate_active_cnpj' AND NOT tgisinternal) THEN
    EXECUTE 'CREATE TRIGGER trg_prevent_duplicate_active_cnpj BEFORE INSERT OR UPDATE OF cnpj, ativo, tenant_id ON public.empresa_cadastro FOR EACH ROW EXECUTE FUNCTION public.prevent_duplicate_active_cnpj()';
  END IF;
END $blk$;

-- (2) INDICES UNICOS — so cria se NAO houver duplicata hoje

-- 2a) Empresa: CPF de PF ativa unico por tenant (EMP-070/071)
DO $blk$
DECLARE v_dup int;
BEGIN
  PERFORM set_config('lock_timeout','5s',true);
  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_empresa_cpf_ativa') THEN RETURN; END IF;
  SELECT count(*) INTO v_dup FROM (
    SELECT tenant_id, regexp_replace(cpf,'[^0-9]','','g') AS k
    FROM public.empresa_cadastro WHERE ativo AND cpf IS NOT NULL
    GROUP BY 1,2 HAVING count(*) > 1) d;
  IF v_dup > 0 THEN
    RAISE NOTICE 'A2 ADIADO: % grupo(s) de CPF de empresa ATIVA duplicado(s); indice uq_empresa_cpf_ativa NAO criado. Limpar antes.', v_dup;
  ELSE
    EXECUTE $ddl$CREATE UNIQUE INDEX uq_empresa_cpf_ativa ON public.empresa_cadastro USING btree (tenant_id, regexp_replace(cpf, '[^0-9]'::text, ''::text, 'g'::text)) WHERE (ativo AND (cpf IS NOT NULL))$ddl$;
  END IF;
END $blk$;

-- 2b) Admissoes: CPF unico por tenant enquanto ativa (ADM-002)
DO $blk$
DECLARE v_dup int;
BEGIN
  PERFORM set_config('lock_timeout','5s',true);
  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_admissoes_cpf_ativa') THEN RETURN; END IF;
  SELECT count(*) INTO v_dup FROM (
    SELECT tenant_id, regexp_replace(cpf,'[^0-9]','','g') AS k
    FROM public.admissoes
    WHERE cpf IS NOT NULL AND status <> ALL (ARRAY['desligado'::admissao_status,'reprovado'::admissao_status])
    GROUP BY 1,2 HAVING count(*) > 1) d;
  IF v_dup > 0 THEN
    RAISE NOTICE 'A2 ADIADO: % grupo(s) de CPF de admissao ativa duplicado(s); indice uq_admissoes_cpf_ativa NAO criado. Limpar antes.', v_dup;
  ELSE
    EXECUTE $ddl$CREATE UNIQUE INDEX uq_admissoes_cpf_ativa ON public.admissoes USING btree (tenant_id, regexp_replace(cpf, '[^0-9]'::text, ''::text, 'g'::text)) WHERE ((cpf IS NOT NULL) AND (status <> ALL (ARRAY['desligado'::admissao_status, 'reprovado'::admissao_status])))$ddl$;
  END IF;
END $blk$;

-- 2c) Vinculo: um vinculo ativo por (usuario, empresa) (VIN-008)
DO $blk$
DECLARE v_dup int;
BEGIN
  PERFORM set_config('lock_timeout','5s',true);
  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='usuario_perfil_vinculos_ativo_uidx') THEN RETURN; END IF;
  SELECT count(*) INTO v_dup FROM (
    SELECT usuario_id, COALESCE(empresa_id,'00000000-0000-0000-0000-000000000000'::uuid) AS k
    FROM public.usuario_perfil_vinculos WHERE COALESCE(ativo,true)
    GROUP BY 1,2 HAVING count(*) > 1) d;
  IF v_dup > 0 THEN
    RAISE NOTICE 'A2 ADIADO: % grupo(s) de vinculo ativo duplicado(s); indice usuario_perfil_vinculos_ativo_uidx NAO criado. Limpar antes.', v_dup;
  ELSE
    EXECUTE $ddl$CREATE UNIQUE INDEX usuario_perfil_vinculos_ativo_uidx ON public.usuario_perfil_vinculos USING btree (usuario_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)) WHERE COALESCE(ativo, true)$ddl$;
  END IF;
END $blk$;

-- ----------------------------------------------------------------------------
-- CONFERENCIA (unico SELECT): o que instalou, duplicatas existentes e rotinas.
-- ----------------------------------------------------------------------------
WITH estrutura AS (
  SELECT 1 ord, 'gatilho CNPJ (trg_prevent_duplicate_active_cnpj)' item,
         (EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_prevent_duplicate_active_cnpj' AND NOT tgisinternal))::text res
  UNION ALL SELECT 1,'indice uq_empresa_cpf_ativa', (EXISTS(SELECT 1 FROM pg_indexes WHERE indexname='uq_empresa_cpf_ativa'))::text
  UNION ALL SELECT 1,'indice uq_admissoes_cpf_ativa', (EXISTS(SELECT 1 FROM pg_indexes WHERE indexname='uq_admissoes_cpf_ativa'))::text
  UNION ALL SELECT 1,'indice usuario_perfil_vinculos_ativo_uidx', (EXISTS(SELECT 1 FROM pg_indexes WHERE indexname='usuario_perfil_vinculos_ativo_uidx'))::text
),
dups AS (
  SELECT 2 ord,'DUP empresa CPF ativa (grupos)' item,
         (SELECT count(*)::text FROM (SELECT 1 FROM public.empresa_cadastro WHERE ativo AND cpf IS NOT NULL GROUP BY tenant_id, regexp_replace(cpf,'[^0-9]','','g') HAVING count(*)>1) d) res
  UNION ALL SELECT 2,'DUP admissoes CPF ativa (grupos)',
         (SELECT count(*)::text FROM (SELECT 1 FROM public.admissoes WHERE cpf IS NOT NULL AND status <> ALL(ARRAY['desligado'::admissao_status,'reprovado'::admissao_status]) GROUP BY tenant_id, regexp_replace(cpf,'[^0-9]','','g') HAVING count(*)>1) d)
  UNION ALL SELECT 2,'DUP vinculo ativo (grupos)',
         (SELECT count(*)::text FROM (SELECT 1 FROM public.usuario_perfil_vinculos WHERE COALESCE(ativo,true) GROUP BY usuario_id, COALESCE(empresa_id,'00000000-0000-0000-0000-000000000000'::uuid) HAVING count(*)>1) d)
),
rotinas AS (
  SELECT 3 ord, t.codigo item, (public.qa_executar_descartavel(t.fn)).situacao::text res
  FROM (VALUES ('EMP-020','qa_caso_emp_020'),('EMP-021','qa_caso_emp_021'),('EMP-070','qa_caso_emp_070'),
               ('EMP-071','qa_caso_emp_071'),('ADM-002','qa_caso_adm_002'),('VIN-008','qa_caso_vin_008')) t(codigo,fn)
  WHERE to_regprocedure('public.'||t.fn||'()') IS NOT NULL
)
SELECT item, res FROM (SELECT * FROM estrutura UNION ALL SELECT * FROM dups UNION ALL SELECT * FROM rotinas) z ORDER BY ord, item;
