-- ============================================================================
-- ENTREGA — Admissao (Fase 4): estrutura e travas basicas
--
-- Espelha a migration 20260914123000_fase4_admissao_estrutura_e_travas.sql (no
-- teste), ausente em homologacao e producao (passivo 09/2026).
--
-- O QUE ENTREGA:
--   * 11 colunas novas em admissoes (prazo determinado, intermitente, vale-
--     transporte, justificativa retroativa, ASO admissional) — ADD COLUMN aditivo;
--   * tabela admissao_checklist_config (ADM-052) + RLS + politica + trigger de
--     updated_at;
--   * 4 funcoes: admissao_valida_prazo_determinado (ADM-021, trigger),
--     admissao_confere_piso_cct (ADM-051), admissao_bloqueia_conclusao_inapto
--     (ADM-072, trigger), admissao_expurgar_reprovadas (ADM-073, LGPD, callable);
--   * 2 triggers em admissoes (teto de 2 anos do prazo determinado; bloqueio de
--     conclusao com ASO admissional INAPTO, NR-07).
--
-- UM SCRIPT SO (sem parte1/parte2): os triggers vao em admissoes (movimentada,
-- 2 triggers na MESMA tabela, ok) e em admissao_checklist_config (tabela NOVA,
-- vazia, nao movimentada). A regra do deadlock e sobre DUAS tabelas movimentadas
-- diferentes — nao e o caso aqui.
--
-- SEGURANCA: aditivo. Cria tabela/funcoes/colunas novas (ADD COLUMN IF NOT
-- EXISTS nao mexe em linha existente; as 4 funcoes e a tabela estao AUSENTES
-- embaixo — conferido). admissao_expurgar_reprovadas so anonimiza QUANDO
-- CHAMADA; este script apenas a DEFINE (nao roda expurgo). Nao ALTERA nem APAGA
-- dado aqui — sem backup. Roda em UMA transacao. DDL pura no topo; funcoes
-- (com tag nomeada) depois; triggers de admissoes por ultimo (dependem das funcoes).
-- Dependencias ja presentes embaixo: admissoes (com exame_admissional_resultado),
-- folha_cct (com piso_salarial), get_user_tenant_id(), update_updated_at_column().
--
-- CONFERENCIA: rode a query do fim SEPARADA. Esperado: t | 11 | 4 | 3 | OK
-- ============================================================================

SET lock_timeout = '10s';

-- ═══════════════════════════════════════════════════════════════════════════
-- DDL PURA — colunas de admissoes, tabela nova, RLS, politica, trigger updated_at
-- ═══════════════════════════════════════════════════════════════════════════

-- ADM-021: prazo determinado estruturado
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS prazo_determinado boolean NOT NULL DEFAULT false;
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS data_fim_contrato date;
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS prorrogacao_determinado_count integer NOT NULL DEFAULT 0;
-- ADM-022: intermitente
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS contrato_intermitente boolean NOT NULL DEFAULT false;
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS valor_hora numeric(12,2);
-- ADM-050: opcao de vale-transporte
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS vale_transporte_opcao boolean;
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS vale_transporte_renuncia boolean NOT NULL DEFAULT false;
-- ADM-071: justificativa de admissao retroativa
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS justificativa_retroativa text;
-- ADM-107: ASO admissional (documento de saude proprio)
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS aso_admissional_data date;
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS aso_admissional_resultado text;
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS aso_admissional_documento_id uuid;
COMMENT ON COLUMN public.admissoes.aso_admissional_resultado IS
  'Resultado do ASO admissional (apto/inapto/apto_com_restricoes) — dado de saude, NR-07/LGPD art. 11.';

-- ADM-052: checklist de documentos parametrizavel (tabela nova + RLS + politica)
CREATE TABLE IF NOT EXISTS public.admissao_checklist_config (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL,
  empresa_id      uuid,
  categoria       text,
  documento       text NOT NULL,
  obrigatorio     boolean NOT NULL DEFAULT true,
  base_legal      text,
  vigencia_inicio date,
  vigencia_fim    date,
  ativo           boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.admissao_checklist_config ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.admissao_checklist_config IS
  'ADM-052: checklist de documentos da admissao parametrizavel por empresa/categoria/vigencia.';

DROP POLICY IF EXISTS "Tenant isolation admissao_checklist_config" ON public.admissao_checklist_config;
CREATE POLICY "Tenant isolation admissao_checklist_config"
  ON public.admissao_checklist_config FOR ALL
  USING (tenant_id = public.get_user_tenant_id())
  WITH CHECK (tenant_id = public.get_user_tenant_id());

DROP TRIGGER IF EXISTS update_admissao_checklist_config_updated_at ON public.admissao_checklist_config;
CREATE TRIGGER update_admissao_checklist_config_updated_at
  BEFORE UPDATE ON public.admissao_checklist_config
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ═══════════════════════════════════════════════════════════════════════════
-- FUNCOES (com tag nomeada) — depois da DDL
-- ═══════════════════════════════════════════════════════════════════════════

-- ADM-021: valida teto de 2 anos e prorrogacao unica (funcao do trigger)
CREATE OR REPLACE FUNCTION public.admissao_valida_prazo_determinado()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $fn$
DECLARE
  v_dias integer;
BEGIN
  IF NOT COALESCE(NEW.prazo_determinado, false) THEN
    RETURN NEW;
  END IF;
  IF NEW.data_fim_contrato IS NULL OR NEW.data_admissao IS NULL THEN
    RAISE EXCEPTION 'Contrato por prazo determinado exige data de admissao e data de fim.'
      USING ERRCODE = 'check_violation';
  END IF;
  v_dias := (NEW.data_fim_contrato - NEW.data_admissao) + 1;
  IF v_dias > 730 THEN
    RAISE EXCEPTION
      'Prazo determinado de % dias excede o teto legal de 2 anos (art. 445 CLT).', v_dias
      USING ERRCODE = 'check_violation';
  END IF;
  IF COALESCE(NEW.prorrogacao_determinado_count, 0) > 1 THEN
    RAISE EXCEPTION
      'Contrato por prazo determinado admite uma unica prorrogacao (art. 451 CLT).'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$fn$;

-- ADM-051: confere salario contra o piso da CCT (read-only)
CREATE OR REPLACE FUNCTION public.admissao_confere_piso_cct(
  p_tenant uuid, p_empresa uuid, p_cargo text, p_salario numeric,
  p_referencia date DEFAULT CURRENT_DATE
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_piso numeric;
BEGIN
  SELECT fc.piso_salarial INTO v_piso
    FROM public.folha_cct fc
   WHERE fc.tenant_id = p_tenant
     AND (fc.empresa_id IS NULL OR fc.empresa_id = p_empresa)
     AND COALESCE(fc.vigencia_inicio, p_referencia) <= p_referencia
     AND (fc.vigencia_fim IS NULL OR fc.vigencia_fim >= p_referencia)
   ORDER BY fc.piso_salarial DESC NULLS LAST
   LIMIT 1;
  RETURN jsonb_build_object(
    'piso_salarial', v_piso,
    'salario', p_salario,
    'atende_piso', (v_piso IS NULL OR COALESCE(p_salario, 0) >= v_piso),
    'diferenca', CASE WHEN v_piso IS NOT NULL AND COALESCE(p_salario,0) < v_piso
                      THEN v_piso - COALESCE(p_salario,0) ELSE 0 END
  );
END;
$fn$;
COMMENT ON FUNCTION public.admissao_confere_piso_cct(uuid, uuid, text, numeric, date) IS
  'ADM-051: confere o salario da admissao contra o piso_salarial da CCT vigente.';

-- ADM-072: bloqueia conclusao com ASO admissional inapto (funcao do trigger)
CREATE OR REPLACE FUNCTION public.admissao_bloqueia_conclusao_inapto()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.status::text = 'concluido'
     AND COALESCE(OLD.status::text, '') <> 'concluido'
     AND (lower(COALESCE(NEW.exame_admissional_resultado, '')) = 'inapto'
          OR lower(COALESCE(NEW.aso_admissional_resultado, '')) = 'inapto') THEN
    RAISE EXCEPTION
      'Admissao com ASO admissional INAPTO nao pode ser concluida (NR-07): o colaborador esta impedido de iniciar nesta funcao.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$fn$;

-- ADM-073: expurgo/anonimizacao de admissoes reprovadas/canceladas (LGPD, callable)
CREATE OR REPLACE FUNCTION public.admissao_expurgar_reprovadas(
  p_tenant uuid, p_anos integer DEFAULT 2
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_corte date := (CURRENT_DATE - make_interval(years => GREATEST(p_anos, 1)))::date;
  v_qtd   integer;
BEGIN
  WITH alvo AS (
    SELECT id FROM public.admissoes
     WHERE tenant_id = p_tenant
       AND status::text IN ('reprovado', 'cancelado')
       AND COALESCE(updated_at::date, created_at::date) < v_corte
       AND nome_completo IS DISTINCT FROM '[anonimizado]'
  )
  UPDATE public.admissoes a
     SET nome_completo                = '[anonimizado]',
         cpf                          = NULL,
         exame_admissional_resultado  = NULL,
         aso_admissional_resultado    = NULL,
         aso_admissional_documento_id = NULL,
         justificativa_retroativa     = NULL
    FROM alvo
   WHERE a.id = alvo.id;
  GET DIAGNOSTICS v_qtd = ROW_COUNT;
  RETURN v_qtd;
END;
$fn$;
COMMENT ON FUNCTION public.admissao_expurgar_reprovadas(uuid, integer) IS
  'ADM-073: expurgo/anonimizacao de admissoes reprovadas/canceladas alem do prazo de retencao (LGPD).';

-- ═══════════════════════════════════════════════════════════════════════════
-- TRIGGERS em admissoes (por ultimo — dependem das funcoes acima)
-- ═══════════════════════════════════════════════════════════════════════════
DROP TRIGGER IF EXISTS trg_admissao_prazo_determinado ON public.admissoes;
CREATE TRIGGER trg_admissao_prazo_determinado
  BEFORE INSERT OR UPDATE OF prazo_determinado, data_fim_contrato, data_admissao,
                            prorrogacao_determinado_count
  ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_valida_prazo_determinado();

DROP TRIGGER IF EXISTS trg_admissao_bloqueia_conclusao_inapto ON public.admissoes;
CREATE TRIGGER trg_admissao_bloqueia_conclusao_inapto
  BEFORE UPDATE OF status ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_bloqueia_conclusao_inapto();

-- ---------------------------------------------------------------------------
-- CONFERENCIA — rode SEPARADA. Esperado: t | 11 | 4 | 3 | OK
--   tabela_ok | colunas_admissoes_de_11 | funcoes_de_4 | triggers_de_3 | erro
-- ---------------------------------------------------------------------------
WITH col AS MATERIALIZED (
  SELECT count(*) AS n FROM information_schema.columns
  WHERE table_schema='public' AND table_name='admissoes' AND column_name IN (
    'prazo_determinado','data_fim_contrato','prorrogacao_determinado_count',
    'contrato_intermitente','valor_hora','vale_transporte_opcao',
    'vale_transporte_renuncia','justificativa_retroativa','aso_admissional_data',
    'aso_admissional_resultado','aso_admissional_documento_id')
),
fns AS MATERIALIZED (
  SELECT count(*) AS n FROM (VALUES
    ('public.admissao_valida_prazo_determinado()'),
    ('public.admissao_confere_piso_cct(uuid, uuid, text, numeric, date)'),
    ('public.admissao_bloqueia_conclusao_inapto()'),
    ('public.admissao_expurgar_reprovadas(uuid, integer)')
  ) v(sig) WHERE to_regprocedure(v.sig) IS NOT NULL
),
trg AS MATERIALIZED (
  SELECT count(*) AS n FROM pg_trigger
  WHERE NOT tgisinternal AND tgname IN (
    'trg_admissao_prazo_determinado','trg_admissao_bloqueia_conclusao_inapto',
    'update_admissao_checklist_config_updated_at')
)
SELECT
  (to_regclass('public.admissao_checklist_config') IS NOT NULL) AS tabela_ok,
  (SELECT n FROM col) AS colunas_admissoes_de_11,
  (SELECT n FROM fns) AS funcoes_de_4,
  (SELECT n FROM trg) AS triggers_de_3,
  CASE WHEN to_regclass('public.admissao_checklist_config') IS NOT NULL
        AND (SELECT n FROM col)=11 AND (SELECT n FROM fns)=4 AND (SELECT n FROM trg)=3
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;
