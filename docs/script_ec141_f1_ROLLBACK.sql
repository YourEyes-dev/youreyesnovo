-- =====================================================================
-- ROLLBACK da entrega EC 141 F1 (marcos legais + escala "vale a partir de")
--
-- Só use se a entrega precisar ser desfeita. Roda inteiro em UMA transação,
-- é idempotente e devolve o COMPORTAMENTO de antes:
--   1) cancela todos os agendamentos de escala ainda pendentes (as escalas
--      voltam aos valores de hoje);
--   2) desativa os marcos EC 141 (global e exceções de conta);
--   3) devolve o gatilho de versão e o overlay da PONTO-153 ao corpo original
--      (congela sempre até ontem, 7 campos);
--   4) retira as duas reinjeções marcadas [ec141-f1] (formalização e
--      equalização), removendo exatamente o texto injetado.
-- As tabelas/colunas novas ficam (inertes): não guardam dado pessoal e
-- preservam o histórico. Nada de dado de cliente é apagado.
-- Conferência final em um SELECT.
-- =====================================================================

SET lock_timeout = '10s';

-- 1) Agendamentos pendentes de todas as contas.
DO $rb_agend$
BEGIN
  IF to_regprocedure('public.ponto_escalas_cancelar_agendamentos_lote(uuid,text)') IS NOT NULL THEN
    PERFORM public.ponto_escalas_cancelar_agendamentos_lote(NULL, NULL);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Rollback EC141 F1: agendamentos nao cancelados: %', SQLERRM;
END $rb_agend$;

-- 2) Marcos EC 141 inativos.
DO $rb_marcos$
BEGIN
  IF to_regclass('public.ponto_marcos_legais') IS NOT NULL THEN
    UPDATE public.ponto_marcos_legais
       SET ativo = false, desativado_em = now(), motivo = 'Rollback da entrega EC 141 F1', atualizado_em = now()
     WHERE codigo LIKE 'EC141%' AND ativo;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Rollback EC141 F1: marcos nao desativados: %', SQLERRM;
END $rb_marcos$;

-- 3a) Gatilho de versão — corpo original da PONTO-153.
CREATE OR REPLACE FUNCTION public.ponto_escala_arquiva_versao()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
DECLARE
  v_inicio date;
BEGIN
  IF NEW.jornada_diaria_minutos         IS DISTINCT FROM OLD.jornada_diaria_minutos
     OR NEW.tolerancia_minutos          IS DISTINCT FROM OLD.tolerancia_minutos
     OR NEW.tolerancia_diaria_minutos   IS DISTINCT FROM OLD.tolerancia_diaria_minutos
     OR NEW.hora_entrada_padrao         IS DISTINCT FROM OLD.hora_entrada_padrao
     OR NEW.hora_saida_padrao           IS DISTINCT FROM OLD.hora_saida_padrao
     OR NEW.intervalo_intrajornada_minutos IS DISTINCT FROM OLD.intervalo_intrajornada_minutos
     OR NEW.dias_config                 IS DISTINCT FROM OLD.dias_config
  THEN
    v_inicio := (SELECT COALESCE(max(vigencia_fim) + 1, DATE '1900-01-01')
                   FROM public.ponto_escala_param_versoes WHERE escala_id = OLD.id);
    IF v_inicio <= CURRENT_DATE - 1 THEN
      INSERT INTO public.ponto_escala_param_versoes
        (escala_id, tenant_id, vigencia_inicio, vigencia_fim,
         jornada_diaria_minutos, hora_entrada_padrao, hora_saida_padrao,
         intervalo_intrajornada_minutos, tolerancia_minutos, tolerancia_diaria_minutos,
         dias_config)
      VALUES (OLD.id, OLD.tenant_id, v_inicio, CURRENT_DATE - 1,
              OLD.jornada_diaria_minutos, OLD.hora_entrada_padrao, OLD.hora_saida_padrao,
              OLD.intervalo_intrajornada_minutos, OLD.tolerancia_minutos, OLD.tolerancia_diaria_minutos,
              OLD.dias_config);
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;

-- 3b) Overlay — corpo original da PONTO-153 (7 campos).
CREATE OR REPLACE FUNCTION public.ponto_escala_com_versao(esc public.ponto_escalas, p_data date)
RETURNS public.ponto_escalas
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v public.ponto_escala_param_versoes;
BEGIN
  IF esc.id IS NULL OR p_data IS NULL THEN
    RETURN esc;
  END IF;
  v := (SELECT pv FROM public.ponto_escala_param_versoes pv
         WHERE pv.escala_id = esc.id
           AND p_data BETWEEN pv.vigencia_inicio AND pv.vigencia_fim
         ORDER BY pv.vigencia_inicio DESC
         LIMIT 1);
  IF v.id IS NULL THEN
    RETURN esc;
  END IF;
  esc.jornada_diaria_minutos          := v.jornada_diaria_minutos;
  esc.tolerancia_minutos              := v.tolerancia_minutos;
  esc.tolerancia_diaria_minutos       := v.tolerancia_diaria_minutos;
  esc.hora_entrada_padrao             := v.hora_entrada_padrao;
  esc.hora_saida_padrao               := v.hora_saida_padrao;
  esc.intervalo_intrajornada_minutos  := v.intervalo_intrajornada_minutos;
  esc.dias_config                     := v.dias_config;
  RETURN esc;
END;
$fn$;

-- 4a) Retira a reinjeção da formalização (texto exato injetado).
DO $rb_form$
DECLARE
  v_def text;
  v_add text := E'\n  -- [ec141-f1] versao do dia + instrumento coletivo da empresa na data (ver ponto_escala_formalizacao_status_em)\n  RETURN public.ponto_escala_formalizacao_status_em(p_escala_id, CURRENT_DATE);\n';
BEGIN
  v_def := (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
             WHERE p.oid = to_regprocedure('public.ponto_escala_formalizacao_status(uuid)'));
  IF v_def IS NULL OR position(v_add IN v_def) = 0 THEN
    RAISE NOTICE 'Rollback EC141 F1: formalizacao sem reinjecao (nada a retirar).';
    RETURN;
  END IF;
  EXECUTE replace(v_def, v_add, '');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Rollback EC141 F1: formalizacao nao restaurada: %', SQLERRM;
END $rb_form$;

-- 4b) Retira a reinjeção da equalização (texto exato injetado).
DO $rb_eq$
DECLARE
  v_def text;
  v_add text := E'\n\n  -- [ec141-f1] parametros da versao vigente no ultimo dia da competencia (escala com "vigente a partir de").\n'
    || E'  --   So vale para versoes gravadas com os campos novos; versoes antigas leem como antes.\n'
    || E'  DECLARE v_ec141_ver public.ponto_escalas;\n'
    || E'  BEGIN\n'
    || E'    IF EXISTS (SELECT 1 FROM public.ponto_escala_param_versoes pv\n'
    || E'                WHERE pv.escala_id = v_esc.id AND v_fim BETWEEN pv.vigencia_inicio AND pv.vigencia_fim\n'
    || E'                  AND pv.inclui_campos_ec141) THEN\n'
    || E'      v_ec141_ver := public.ponto_escala_na_data(v_esc.id, v_fim);\n'
    || E'      v_esc.dias_config := v_ec141_ver.dias_config;\n'
    || E'      v_esc.jornada_diaria_minutos := v_ec141_ver.jornada_diaria_minutos;\n'
    || E'      v_esc.ativa := COALESCE(v_ec141_ver.equalizacao_mensal_ativa, false);\n'
    || E'      v_contratada := COALESCE(v_ec141_ver.carga_semanal_contratada_min, 2640);\n'
    || E'    END IF;\n'
    || E'  END;';
BEGIN
  v_def := (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
             WHERE p.oid = to_regprocedure('public.ponto_equalizacao_competencia(uuid,uuid,text)'));
  IF v_def IS NULL OR position(v_add IN v_def) = 0 THEN
    RAISE NOTICE 'Rollback EC141 F1: equalizacao sem reinjecao (nada a retirar).';
    RETURN;
  END IF;
  EXECUTE replace(v_def, v_add, '');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Rollback EC141 F1: equalizacao nao restaurada: %', SQLERRM;
END $rb_eq$;

-- Conferência (um SELECT).
SELECT
  (SELECT count(*) FROM public.ponto_escala_param_versoes WHERE vigencia_fim >= CURRENT_DATE) AS agendamentos_pendentes_deve_ser_0,
  (SELECT string_agg(codigo || '=' || CASE WHEN ativo THEN 'ATIVO' ELSE 'inativo' END, ' | ' ORDER BY codigo)
     FROM public.ponto_marcos_legais WHERE tenant_id IS NULL) AS marcos,
  position('[ec141-f1]' IN pg_get_functiondef('public.ponto_escala_formalizacao_status(uuid)'::regprocedure)) = 0 AS formalizacao_restaurada,
  position('[ec141-f1]' IN pg_get_functiondef('public.ponto_equalizacao_competencia(uuid,uuid,text)'::regprocedure)) = 0 AS equalizacao_restaurada,
  position('parametros_vigentes_desde' IN pg_get_functiondef('public.ponto_escala_arquiva_versao()'::regprocedure)) = 0 AS gatilho_restaurado,
  position('inclui_campos_ec141' IN pg_get_functiondef('public.ponto_escala_com_versao(public.ponto_escalas,date)'::regprocedure)) = 0 AS overlay_restaurado;
