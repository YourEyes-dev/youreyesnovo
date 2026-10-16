-- ============================================================================
-- Perfil "pode ver salário" — CARGOS e FÉRIAS (mascara o valor, mantém a tela)
--
-- Mesmo padrão do cadastro: o registro continua visível; só os valores de
-- remuneração são mascarados por pode_ver_salario(), via VIEW de leitura, e um
-- trigger preserva os valores quando um usuário mascarado salva.
--
--   cargos_segura            → mascara faixa_salarial_min / faixa_salarial_max
--   ferias_solicitacoes_segura → mascara salario_base, valor_ferias,
--                                valor_terco, valor_abono, valor_total_bruto
--
-- Front passa a LER por essas views; escritas seguem nas tabelas base.
-- ============================================================================

-- ── Views de leitura com valores mascarados (colunas montadas dinamicamente) ─
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
    RAISE NOTICE 'View mascarada criada: %_segura.', rec.tabela;
  END LOOP;
END $mk$;

-- ── Trigger cargos: preserva faixa salarial de quem não pode ver ────────────
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

-- ── Trigger ferias_solicitacoes: preserva os valores de quem não pode ver ───
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
