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
--   4) retira todas as reinjeções marcadas [ec141-f1] (formalização,
--      equalização, saldo, intervalo, débito, batidas de dia inteiro, troca de
--      turno), trocando exatamente o texto injetado pela âncora original.
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

-- 4) Retira TODAS as reinjeções [ec141-f1], pelo mesmo registro que as
--    aplicou (troca exata do texto novo pela âncora original).
DO $rb_reinj$
DECLARE
  r record;
  v text;
BEGIN
  IF to_regprocedure('public._ponto_ec141_reinjecoes()') IS NULL THEN
    RAISE NOTICE 'Rollback EC141 F1: registro de reinjecoes ausente (nada a retirar).';
    RETURN;
  END IF;
  FOR r IN SELECT * FROM public._ponto_ec141_reinjecoes() LOOP
    v := public._ponto_ec141_reinjetar(r.fn, r.pares, true);
    RAISE NOTICE 'Rollback EC141 F1: %: %', r.fn, v;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Rollback EC141 F1: reinjecoes nao retiradas: %', SQLERRM;
END $rb_reinj$;

-- Conferência (um SELECT).
SELECT
  (SELECT count(*) FROM public.ponto_escala_param_versoes WHERE vigencia_fim >= CURRENT_DATE) AS agendamentos_pendentes_deve_ser_0,
  (SELECT string_agg(codigo || '=' || CASE WHEN ativo THEN 'ATIVO' ELSE 'inativo' END, ' | ' ORDER BY codigo)
     FROM public.ponto_marcos_legais WHERE tenant_id IS NULL) AS marcos,
  (SELECT string_agg(r.fn, ', ') FROM public._ponto_ec141_reinjecoes() r
     WHERE to_regprocedure(r.fn) IS NOT NULL
       AND position('[ec141-f1]' IN pg_get_functiondef(to_regprocedure(r.fn))) > 0) AS reinjecoes_restantes_deve_ser_nulo,
  position('parametros_vigentes_desde' IN pg_get_functiondef('public.ponto_escala_arquiva_versao()'::regprocedure)) = 0 AS gatilho_restaurado,
  position('inclui_campos_ec141' IN pg_get_functiondef('public.ponto_escala_com_versao(public.ponto_escalas,date)'::regprocedure)) = 0 AS overlay_restaurado;
