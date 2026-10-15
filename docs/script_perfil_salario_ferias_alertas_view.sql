-- ============================================================================
-- ENTREGA — Perfil "pode ver salário" · ALERTAS DE FÉRIAS
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
-- PRE-REQUISITO: o script da FUNDACAO
-- (script_perfil_pode_ver_salario_fundacao.sql) ja aplicado nesta base.
--
-- Roda em UMA transacao, idempotente. Cria a view de leitura dos alertas de
-- vencimento de ferias com o custo estimado (passivo de dobro) mascarado por
-- pode_ver_salario(), e o trigger que preserva o valor quando um usuario
-- mascarado salva:
--   ferias_alertas_segura -> custo_estimado
-- O front le por essa view; a varredura e as escritas seguem na tabela base.
--
-- OBS de editor: NAO cria tabela (cria VIEW + funcao/trigger) -> sem auto-RLS.
-- Nao altera nem apaga dado. Se ferias_alertas ganhar colunas, rodar de novo
-- para a view acompanhar.
-- ============================================================================

DO $mk$
DECLARE
  v_cols text;
  v_money text[] := ARRAY['custo_estimado'];
BEGIN
  IF to_regclass('public.ferias_alertas') IS NULL THEN
    RAISE NOTICE 'ferias_alertas nao existe; view pulada.';
    RETURN;
  END IF;

  SELECT string_agg(
           CASE WHEN column_name = ANY (v_money)
                THEN 'CASE WHEN public.pode_ver_salario(a.tenant_id) THEN a.'
                     || quote_ident(column_name) || ' ELSE NULL END AS ' || quote_ident(column_name)
                ELSE 'a.' || quote_ident(column_name)
           END,
           ', ' ORDER BY ordinal_position)
    INTO v_cols
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'ferias_alertas';

  EXECUTE 'CREATE OR REPLACE VIEW public.ferias_alertas_segura '
       || 'WITH (security_invoker = true) AS SELECT ' || v_cols
       || ' FROM public.ferias_alertas a';
  EXECUTE 'GRANT SELECT ON public.ferias_alertas_segura TO authenticated';
END $mk$;

CREATE OR REPLACE FUNCTION public.ferias_alertas_preserva_custo_mascarado()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
BEGIN
  IF NOT public.pode_ver_salario(NEW.tenant_id) THEN
    NEW.custo_estimado := OLD.custo_estimado;
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_ferias_alertas_preserva_custo ON public.ferias_alertas;
CREATE TRIGGER trg_ferias_alertas_preserva_custo
  BEFORE UPDATE ON public.ferias_alertas
  FOR EACH ROW EXECUTE FUNCTION public.ferias_alertas_preserva_custo_mascarado();

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM information_schema.views
     WHERE table_schema='public' AND table_name = 'ferias_alertas_segura') AS view_ok_esperado_1,
  (SELECT count(*) FROM pg_trigger
     WHERE tgname = 'trg_ferias_alertas_preserva_custo') AS trigger_ok_esperado_1;
