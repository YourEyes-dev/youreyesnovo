-- ============================================================================
-- SCRIPT DE ENTREGA (PRODUÇÃO) — declaração respeita a regra do catálogo
-- [declaracao-respeita-catalogo]  ·  Plano do Ponto, Fase 2 / F0b
-- Corrige: declaração de comparecimento configurada "Não abona" era abonada
-- (em dias pelo gatilho legado; em horas pelo saldo, que apagava o débito).
-- Cria função de regra única, ajusta o gatilho legado e reinjeta a regra no
-- saldo (sem reescrever a função). Não altera dados: dias já marcados
-- 'justificado' no passado continuam como estão (revisão do RH).
-- Se as âncoras não baterem, o saldo NÃO é alterado e a conferência mostra
-- saldo_corrigido=false.
-- ============================================================================

-- 1) Regra única
CREATE OR REPLACE FUNCTION public.atestado_abona_no_ponto(
  p_tenant_id uuid, p_subtipo text, p_abona boolean
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH r AS (
    SELECT COALESCE((
      SELECT j.tipo_abono FROM public.ponto_justificativas j
      WHERE j.tenant_id = p_tenant_id AND j.codigo = 'DECLARACAO_COMPARECIMENTO'
      ORDER BY j.empresa_id NULLS LAST LIMIT 1), 'configuravel') AS regra
  )
  SELECT CASE
           WHEN COALESCE(p_subtipo, '') <> 'comparecimento' THEN true
           ELSE (SELECT regra = 'sim' OR (regra = 'configuravel' AND COALESCE(p_abona, false)) FROM r)
         END;
$function$;

COMMENT ON FUNCTION public.atestado_abona_no_ponto(uuid, text, boolean) IS
  'Regra única: atestado comum abona no ponto; declaração de comparecimento só abona '
  'se o catálogo (DECLARACAO_COMPARECIMENTO) disser Abona, ou Configurável e o documento '
  'estiver marcado para abonar. Usada pelo saldo diário. [declaracao-respeita-catalogo]';

REVOKE ALL ON FUNCTION public.atestado_abona_no_ponto(uuid, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.atestado_abona_no_ponto(uuid, text, boolean) TO authenticated;

-- 2) Gatilho legado ignora declarações (a consolidação aplica o catálogo)
DROP TRIGGER IF EXISTS trigger_justificar_ponto_atestado ON public.atestados;
CREATE TRIGGER trigger_justificar_ponto_atestado
  AFTER INSERT OR UPDATE ON public.atestados
  FOR EACH ROW
  WHEN (NEW.data_inicio_afastamento IS NOT NULL
        AND COALESCE(NEW.subtipo_assistencial::text, '') <> 'comparecimento')
  EXECUTE FUNCTION public.justificar_ponto_por_atestado();

-- 3) Reinjeção no saldo diário
DO $patch$
DECLARE
  v_src text;
  v_new text;
  v_dias text := 'AND COALESCE(a.unidade_afastamento, ''dias'') = ''dias''';
  v_horas text := 'AND COALESCE(a.unidade_afastamento, ''dias'') = ''horas''';
  v_cond text := ' AND public.atestado_abona_no_ponto(p_tenant_id, a.subtipo_assistencial::text, a.abona)';
  v_n_dias int;
  v_n_horas int;
BEGIN
  v_src := pg_get_functiondef('public.ponto_saldo_dias_competencia_bruto(uuid,text,text)'::regprocedure);

  IF position('[declaracao-respeita-catalogo]' IN v_src) > 0 THEN
    RAISE NOTICE 'saldo: [declaracao-respeita-catalogo] ja aplicado; nada a fazer.';
    RETURN;
  END IF;

  v_n_dias  := (length(v_src) - length(replace(v_src, v_dias, ''))) / length(v_dias);
  v_n_horas := (length(v_src) - length(replace(v_src, v_horas, ''))) / length(v_horas);

  IF v_n_dias <> 1 OR v_n_horas <> 2 THEN
    RAISE NOTICE 'saldo: ancoras de [declaracao-respeita-catalogo] nao batem (dias=%, horas=%); nada alterado — revisar.', v_n_dias, v_n_horas;
    RETURN;
  END IF;

  v_new := replace(v_src, v_dias, v_dias || v_cond || ' /* [declaracao-respeita-catalogo] */');
  v_new := replace(v_new, v_horas, v_horas || v_cond);
  EXECUTE v_new;
  RAISE NOTICE 'saldo: [declaracao-respeita-catalogo] aplicado.';
END;
$patch$;

-- Conferência (o editor mostra só este resultado)
SELECT json_build_object(
  'funcao_regra_existe', to_regprocedure('public.atestado_abona_no_ponto(uuid,text,boolean)') IS NOT NULL,
  'gatilho_ignora_declaracao', position('comparecimento' IN (SELECT pg_get_triggerdef(t.oid) FROM pg_trigger t WHERE t.tgname = 'trigger_justificar_ponto_atestado' AND NOT t.tgisinternal LIMIT 1)) > 0,
  'saldo_corrigido', position('[declaracao-respeita-catalogo]' IN pg_get_functiondef('public.ponto_saldo_dias_competencia_bruto(uuid,text,text)'::regprocedure)) > 0,
  'regra_declaracao_por_empresa', (SELECT json_agg(json_build_object('regra', tipo_abono, 'empresas', n)) FROM (
      SELECT tipo_abono, count(DISTINCT tenant_id) AS n FROM public.ponto_justificativas
      WHERE codigo = 'DECLARACAO_COMPARECIMENTO' GROUP BY tipo_abono) x)
) AS resultado;
