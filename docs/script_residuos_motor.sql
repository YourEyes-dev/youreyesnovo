-- ============================================================================
-- Residuos do motor — COLAB-011/023/033, DESL-003, HIER-002 — ENTREGA producao.
-- SO funcoes/indice/FK (parte de aplicar). A CONFERENCIA (roda as rotinas) esta
-- em docs/conferencia_residuos.sql — rodar DEPOIS, em transacao propria.
--
-- Causas-raiz (todas drift de objetos que ja existem em migrations do repo):
--  - COLAB-011/023/033 (producao): o gerador de CPF de teste qa_cpf estava
--    stale e gerava CPF com digito verificador invalido — validar_cpf_usuario
--    (validador real) recusava. Reentrega o qa_cpf/qa_cpf_formatado atuais
--    (helpers de QA; nao mexe no validador real).
--  - COLAB-033 (ambos): faltava o indice unico de CPF NORMALIZADO em
--    usuarios_base (CPF pontuado x cru escapava do indice cru). Guardado contra
--    legado duplicado.
--  - DESL-003 (ambos): afastamento_sem_prazo_e_legitimo estava stale e nao
--    reconhecia prazo_indeterminado/beneficio INSS como legitimo, entao o
--    afastamento indeterminado era recusado na escrita. Reentrega o helper.
--  - HIER-002 (ambos): a FK grupo_economico existia SEM ON DELETE SET NULL —
--    apagar um grupo dava erro. Recria a FK com SET NULL.
--
-- So cria/atualiza objetos; nao altera nem apaga dado. Idempotente.
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

-- DESL-003: afastamento indeterminado / beneficio INSS e legitimo ------------
CREATE OR REPLACE FUNCTION public.afastamento_sem_prazo_e_legitimo(
  p_prazo_indeterminado boolean, p_status text, p_status_geral text, p_tipo_principal text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $fn$
  SELECT COALESCE(p_prazo_indeterminado, false)
      OR COALESCE(p_status, '')       = 'beneficio_inss'
      OR COALESCE(p_status_geral, '') IN ('prazo_indeterminado', 'em_beneficio')
      OR COALESCE(p_tipo_principal, '') IN ('beneficio_b31', 'beneficio_b91', 'licenca_maternidade');
$fn$;

-- DESL-003 (parte 2): derivacao de campos do afastamento. O gatilho
-- afastamento_campos_before (que roda ANTES de afastamento_valida_e_encerra)
-- estava stale e nao marcava status_geral_new='prazo_indeterminado' para
-- afastamento indeterminado — entao o afastamento sem data_fim era recusado.
-- Coluna data_fim_estabilidade referenciada pelo gatilho (drift-safety).
ALTER TABLE public.afastamentos ADD COLUMN IF NOT EXISTS data_fim_estabilidade date;

CREATE OR REPLACE FUNCTION public.afastamento_campos_before()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
    v_dias integer;
BEGIN
    IF COALESCE(NEW.prazo_indeterminado, FALSE) THEN
        IF NEW.status_geral_new IS NULL
           OR NEW.status_geral_new NOT IN ('prazo_indeterminado', 'em_beneficio') THEN
            NEW.status_geral_new := 'prazo_indeterminado';
        END IF;
    END IF;

    IF NEW.data_inicio IS NOT NULL AND NEW.data_fim IS NOT NULL THEN
        v_dias := (NEW.data_fim - NEW.data_inicio) + 1;
    ELSIF NEW.data_inicio IS NOT NULL THEN
        v_dias := (CURRENT_DATE - NEW.data_inicio) + 1;
    ELSE
        v_dias := 0;
    END IF;

    IF NOT COALESCE(NEW.prazo_indeterminado, FALSE)
       AND v_dias > 15
       AND (NEW.status_geral_new IS NULL
            OR NEW.status_geral_new NOT IN
               ('aguardando_inss', 'em_beneficio', 'encerrado', 'cancelado', 'prazo_indeterminado')) THEN
        NEW.status_geral_new := 'aguardando_inss';
    END IF;

    IF NEW.tipo_principal_new IN ('acidente_tipico', 'acidente_trajeto', 'doenca_ocupacional')
       AND NEW.data_fim IS NOT NULL THEN
        NEW.data_fim_estabilidade := (NEW.data_fim + INTERVAL '12 months')::date;
    END IF;

    RETURN NEW;
END;
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
SELECT 'afastamento_sem_prazo_e_legitimo(indeterminado)',
       public.afastamento_sem_prazo_e_legitimo(true, 'ativo', NULL, NULL)::text
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
