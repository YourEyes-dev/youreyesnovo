-- ============================================================================
-- Perfil "pode ver salário" — BENEFÍCIOS (mascara o valor, mantém a tela)
--
-- Mesmo padrão: o benefício do colaborador continua visível; só os valores
-- (valor e valor_desconto) são mascarados por pode_ver_salario(), via VIEW de
-- leitura, e um trigger preserva os valores quando um usuário mascarado salva.
--
--   beneficios_colaboradores_segura → mascara valor, valor_desconto
--
-- O front le por essa view; escritas seguem na tabela base.
--
-- Sobre TOTAIS de férias: o total exibido (custoTotal) é somado no cliente a
-- partir de valor_total_bruto, que já vem mascarado pela view
-- ferias_solicitacoes_segura — então o total já fica oculto para quem não pode
-- ver salário, sem mudança adicional aqui.
-- ============================================================================

DO $mk$
DECLARE
  v_cols text;
  v_money text[] := ARRAY['valor','valor_desconto'];
BEGIN
  IF to_regclass('public.beneficios_colaboradores') IS NULL THEN
    RAISE NOTICE 'beneficios_colaboradores nao existe; view pulada.';
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
   WHERE table_schema = 'public' AND table_name = 'beneficios_colaboradores';

  EXECUTE 'CREATE OR REPLACE VIEW public.beneficios_colaboradores_segura '
       || 'WITH (security_invoker = true) AS SELECT ' || v_cols
       || ' FROM public.beneficios_colaboradores a';
  EXECUTE 'GRANT SELECT ON public.beneficios_colaboradores_segura TO authenticated';
END $mk$;

CREATE OR REPLACE FUNCTION public.beneficios_preserva_valor_mascarado()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
BEGIN
  IF NOT public.pode_ver_salario(NEW.tenant_id) THEN
    NEW.valor := OLD.valor;
    NEW.valor_desconto := OLD.valor_desconto;
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_beneficios_preserva_valor ON public.beneficios_colaboradores;
CREATE TRIGGER trg_beneficios_preserva_valor
  BEFORE UPDATE ON public.beneficios_colaboradores
  FOR EACH ROW EXECUTE FUNCTION public.beneficios_preserva_valor_mascarado();
