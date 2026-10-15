-- ============================================================================
-- Perfil "pode ver salário" — CADASTRO (admissoes.salario mascarado no servidor)
--
-- Aqui o colaborador precisa continuar visível; só o VALOR do salário some para
-- quem não pode ver. Como Postgres não mascara coluna por usuário via RLS, a
-- leitura passa por uma VIEW que devolve o salário condicionado ao perfil:
--
--   admissoes_segura.salario = CASE WHEN pode_ver_salario(tenant) THEN salario END
--
-- A view é security_invoker (mantém o RLS da tabela base para o usuário) e o
-- front lê o cadastro por ela. As ESCRITAS seguem na tabela base admissoes.
--
-- Risco coberto: um usuário que não vê salário, ao editar o colaborador,
-- enxerga o campo vazio (mascarado) e um save poderia APAGAR o salário real.
-- Um trigger BEFORE UPDATE preserva o salário nesse caso — proteção no
-- servidor, independente do front.
-- ============================================================================

-- ── 1. View de leitura com salário mascarado (colunas montadas dinamicamente,
--        para acompanhar o schema de admissoes sem listar à mão) ─────────────
DO $mk$
DECLARE
  v_cols text;
BEGIN
  SELECT string_agg(
           CASE WHEN column_name = 'salario'
                THEN 'CASE WHEN public.pode_ver_salario(a.tenant_id) THEN a.salario ELSE NULL END AS salario'
                ELSE 'a.' || quote_ident(column_name)
           END,
           ', ' ORDER BY ordinal_position)
    INTO v_cols
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'admissoes';

  EXECUTE 'CREATE OR REPLACE VIEW public.admissoes_segura '
       || 'WITH (security_invoker = true) AS SELECT ' || v_cols
       || ' FROM public.admissoes a';
END $mk$;

GRANT SELECT ON public.admissoes_segura TO authenticated;

COMMENT ON VIEW public.admissoes_segura IS
  'Leitura de admissoes com salario mascarado por pode_ver_salario(). O front '
  'le o cadastro por aqui; escritas seguem na tabela admissoes. Se admissoes '
  'ganhar colunas, rodar de novo esta criacao para a view acompanhar.';

-- ── 2. Trigger: quem não pode ver salário não o altera (preserva o valor) ───
CREATE OR REPLACE FUNCTION public.admissoes_preserva_salario_mascarado()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
BEGIN
  -- Sem permissão de ver salário: qualquer tentativa de alterar o campo é
  -- ignorada (mantém o valor atual). Protege contra o "save mascarado apaga".
  IF NOT public.pode_ver_salario(NEW.tenant_id) THEN
    NEW.salario := OLD.salario;
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_admissoes_preserva_salario ON public.admissoes;
CREATE TRIGGER trg_admissoes_preserva_salario
  BEFORE UPDATE ON public.admissoes
  FOR EACH ROW
  EXECUTE FUNCTION public.admissoes_preserva_salario_mascarado();
