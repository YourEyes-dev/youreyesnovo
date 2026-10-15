-- ============================================================================
-- ENTREGA — Perfil "pode ver salário" · CARGOS e FÉRIAS
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
-- PRE-REQUISITO: o script da FUNDACAO
-- (script_perfil_pode_ver_salario_fundacao.sql) ja aplicado nesta base.
--
-- Roda em UMA transacao, idempotente. Cria as views de leitura com os valores
-- mascarados por pode_ver_salario() e os triggers que preservam os valores
-- quando um usuario mascarado salva:
--   cargos_segura              -> faixa_salarial_min / faixa_salarial_max
--   ferias_solicitacoes_segura -> salario_base, valor_ferias, valor_terco,
--                                 valor_abono, valor_total_bruto
-- O front le por essas views; escritas seguem nas tabelas base.
--
-- OBS de editor: NAO cria tabela (cria VIEW + funcoes/triggers) -> sem auto-RLS.
-- Nao altera nem apaga dado. Se cargos/ferias_solicitacoes ganharem colunas,
-- rodar de novo para a view acompanhar.
-- ============================================================================

DO $mk$
DECLARE
  rec record;
  v_cols text;
BEGIN
  FOR rec IN
    SELECT * FROM (VALUES
      ('cargos', ARRAY['faixa_salarial_min','faixa_salarial_max']),
      ('ferias_solicitacoes', ARRAY['salario_base','valor_ferias','valor_terco','valor_abono','valor_total_bruto'])
    ) AS t(tabela, money_cols)
  LOOP
    IF to_regclass('public.' || rec.tabela) IS NULL THEN
      RAISE NOTICE 'Tabela % nao existe; view pulada.', rec.tabela;
      CONTINUE;
    END IF;

    SELECT string_agg(
             CASE WHEN column_name = ANY (rec.money_cols)
                  THEN 'CASE WHEN public.pode_ver_salario(a.tenant_id) THEN a.'
                       || quote_ident(column_name) || ' ELSE NULL END AS ' || quote_ident(column_name)
                  ELSE 'a.' || quote_ident(column_name)
             END,
             ', ' ORDER BY ordinal_position)
      INTO v_cols
      FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = rec.tabela;

    EXECUTE 'CREATE OR REPLACE VIEW public.' || quote_ident(rec.tabela || '_segura')
         || ' WITH (security_invoker = true) AS SELECT ' || v_cols
         || ' FROM public.' || quote_ident(rec.tabela) || ' a';
    EXECUTE 'GRANT SELECT ON public.' || quote_ident(rec.tabela || '_segura') || ' TO authenticated';
  END LOOP;
END $mk$;

CREATE OR REPLACE FUNCTION public.cargos_preserva_faixa_mascarada()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
BEGIN
  IF NOT public.pode_ver_salario(NEW.tenant_id) THEN
    NEW.faixa_salarial_min := OLD.faixa_salarial_min;
    NEW.faixa_salarial_max := OLD.faixa_salarial_max;
  END IF;
  RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS trg_cargos_preserva_faixa ON public.cargos;
CREATE TRIGGER trg_cargos_preserva_faixa
  BEFORE UPDATE ON public.cargos
  FOR EACH ROW EXECUTE FUNCTION public.cargos_preserva_faixa_mascarada();

CREATE OR REPLACE FUNCTION public.ferias_sol_preserva_valores_mascarados()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
BEGIN
  IF NOT public.pode_ver_salario(NEW.tenant_id) THEN
    NEW.salario_base      := OLD.salario_base;
    NEW.valor_ferias      := OLD.valor_ferias;
    NEW.valor_terco       := OLD.valor_terco;
    NEW.valor_abono       := OLD.valor_abono;
    NEW.valor_total_bruto := OLD.valor_total_bruto;
  END IF;
  RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS trg_ferias_sol_preserva_valores ON public.ferias_solicitacoes;
CREATE TRIGGER trg_ferias_sol_preserva_valores
  BEFORE UPDATE ON public.ferias_solicitacoes
  FOR EACH ROW EXECUTE FUNCTION public.ferias_sol_preserva_valores_mascarados();

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM information_schema.views
     WHERE table_schema='public' AND table_name IN ('cargos_segura','ferias_solicitacoes_segura')) AS views_ok_esperado_2,
  (SELECT count(*) FROM pg_trigger
     WHERE tgname IN ('trg_cargos_preserva_faixa','trg_ferias_sol_preserva_valores')) AS triggers_ok_esperado_2;
