-- ============================================================================
-- Motor de QA — blindar o descarte contra VAZAMENTO de estado de sessão.
--
-- Sintoma: com as rotinas de Usuários & Permissões ativas, ~22 casos de outros
-- módulos (desligamento, férias, 13º, empresa) que passam SOZINHOS falhavam no
-- full-run da bateria.
--
-- Causa: alguns apoios daquele módulo trocam o estado de sessão para simular o
-- usuário logado — request.jwt.claims (via set_config) e o papel (SET ROLE). O
-- descarte do motor (qa_executar_descartavel) confia que o rollback da
-- subtransação desfaz isso, mas set_config(...,true) e SET ROLE feitos dentro da
-- função chamada NÃO voltam sozinhos: vazam para o próximo caso da mesma
-- bateria. Um deles deixava request.jwt.claims = '' (nem JSON válido é), e o
-- caso seguinte quebrava ao ler as claims como json
-- ("invalid input syntax for type json"); outros deixavam o papel trocado
-- ("permission denied for table ...").
--
-- Correção (dois níveis):
--   1) qa_up_sair() grava '{}' (JSON válido, anônimo) em vez de '' — higiene.
--   2) qa_executar_descartavel() passa a RESTAURAR o estado de sessão (papel e
--      claims) ao fim de CADA caso, no sucesso e no erro. Assim nenhum caso
--      contamina o próximo, seja qual for o apoio que ele use. É a correção de
--      raiz e vale para o motor inteiro.
-- ============================================================================

-- 1) Higiene do apoio: "sair" com JSON válido.
CREATE OR REPLACE FUNCTION public.qa_up_sair()
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claims', '{}', true);
END $fn$;

-- 2) Descarte blindado: restaura papel e claims ao fim de cada caso.
CREATE OR REPLACE FUNCTION public.qa_executar_descartavel(p_funcao text)
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE
  r public.qa_retorno;
  v_claims text;
BEGIN
  -- Fotografa o estado de sessão ANTES do caso, para devolver depois.
  v_claims := current_setting('request.jwt.claims', true);

  PERFORM public.qa_modo_ligar();
  PERFORM public.qa_exigir_modo();

  BEGIN
    EXECUTE format('SELECT * FROM public.%I()', p_funcao) INTO r;
    RAISE EXCEPTION USING ERRCODE = 'QA000', MESSAGE = 'QA_DESCARTE';
  EXCEPTION
    WHEN SQLSTATE 'QA000' THEN
      NULL;  -- caminho normal: os dados de teste já foram desfeitos
    WHEN OTHERS THEN
      r.situacao     := 'erro';
      r.obtido       := 'A rotina quebrou. Nenhum dado ficou na base.';
      r.erro_tecnico := SQLERRM || ' [' || SQLSTATE || ']';
  END;

  -- Estado de sessão NÃO é desfeito pelo rollback da subtransação quando o caso
  -- usa set_config(...,true) / SET ROLE; devolvemos à mão para não vazar.
  BEGIN
    EXECUTE 'RESET ROLE';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);

  IF r.situacao IS NULL THEN
    r.situacao := 'erro';
    r.obtido   := 'A rotina nao devolveu veredito.';
  END IF;
  RETURN r;
END $fn$;
