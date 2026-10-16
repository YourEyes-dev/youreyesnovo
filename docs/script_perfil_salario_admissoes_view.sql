-- ============================================================================
-- ENTREGA — Perfil "pode ver salário" · CADASTRO (admissoes.salario)
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
-- PRE-REQUISITO: o script da FUNDACAO
-- (script_perfil_pode_ver_salario_fundacao.sql) ja aplicado nesta base.
--
-- Roda em UMA transacao, idempotente. Cria:
--  1) a VIEW public.admissoes_segura (leitura do cadastro com o salario
--     mascarado por pode_ver_salario(); o colaborador continua visivel);
--  2) um trigger BEFORE UPDATE em admissoes que preserva o salario quando o
--     usuario nao pode ve-lo (um save mascarado nao apaga o valor real).
--
-- O front passa a LER o cadastro pela view; as escritas seguem na tabela
-- admissoes. Se admissoes ganhar colunas novas depois, rode este script de
-- novo para a view acompanhar o schema.
--
-- OBS de editor: NAO cria tabela (cria VIEW + funcao/trigger) -> sem auto-RLS.
-- Nao altera nem apaga dado.
-- ============================================================================

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

CREATE OR REPLACE FUNCTION public.admissoes_preserva_salario_mascarado()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
BEGIN
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

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM information_schema.views
     WHERE table_schema='public' AND table_name='admissoes_segura')     AS view_ok,
  (SELECT count(*) FROM pg_trigger
     WHERE tgname='trg_admissoes_preserva_salario')                     AS trigger_ok;
