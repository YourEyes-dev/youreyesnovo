-- =========================================================
-- QA — profiles: o usuario nao troca a propria empresa
--
--   PERFIL-031 (api, somente leitura)  a tabela profiles tem o gatilho que impede alterar tenant_id/user_id por usuario
--              logado e NAO tem a politica de INSERT que deixava qualquer cadastro novo criar o profile em qualquer empresa.
--
-- A prova e estrutural (catalogo do banco): nao ha como simular o ataque sem gravar. Idempotente.
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_perfil_031()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_def text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): profiles com a empresa e o usuario protegidos';
  r.esperado    := 'Gatilho trg_profiles_protege_tenant ativo e sem politica de INSERT que aceite so user_id = auth.uid()';

  IF to_regclass('public.profiles') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela profiles ausente nesta base.';
    RETURN r;
  END IF;

  v_def := (SELECT pg_get_triggerdef(t.oid) FROM pg_trigger t
             WHERE t.tgrelid = 'public.profiles'::regclass AND t.tgname = 'trg_profiles_protege_tenant'
               AND NOT t.tgisinternal AND t.tgenabled <> 'D');
  IF v_def IS NULL THEN
    v_falhas := v_falhas || 'falta o gatilho trg_profiles_protege_tenant (ou esta desligado)'::text;
  ELSIF v_def !~* 'BEFORE UPDATE' THEN
    v_falhas := v_falhas || 'o gatilho de profiles nao e BEFORE UPDATE'::text;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname = 'profiles_protege_tenant' AND p.pronamespace = 'public'::regnamespace
                   AND position('is_superadmin' IN pg_get_functiondef(p.oid)) > 0
                   AND position('tenant_id' IN pg_get_functiondef(p.oid)) > 0) THEN
    v_falhas := v_falhas || 'a funcao profiles_protege_tenant nao confere tenant_id/Super Admin'::text;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_policies
              WHERE schemaname = 'public' AND tablename = 'profiles' AND cmd = 'INSERT' AND permissive = 'PERMISSIVE'
                AND regexp_replace(lower(COALESCE(with_check, '')), '[\s()]', '', 'g') = 'user_id=auth.uid') THEN
    v_falhas := v_falhas || 'ha politica de INSERT em profiles que aceita so user_id = auth.uid() (qualquer empresa)'::text;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido   := 'FALHA GRAVE: ' || array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
  ELSE
    r.situacao := 'passou';
    r.obtido   := 'profiles protegida: o usuario logado nao troca tenant_id/user_id e nao cria profile em empresa alheia.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-031 nao documentado.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-031', 'Isolamento entre empresas: o usuario nao troca a propria empresa no profile',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD arts. 6º e 46',
   'A empresa de cada usuario vem de profiles.tenant_id, que quase toda regra do sistema usa para isolar os dados. Antes, qualquer usuario logado podia alterar o proprio tenant_id (UPDATE do proprio profile sem trava de coluna) e quem acabava de se cadastrar podia criar o profile apontando para qualquer empresa. Agora um gatilho impede mudar tenant_id e user_id por usuario logado (Super Admin e chave de servico passam) e a politica de INSERT aberta foi removida.',
   'Script de trava do profile aplicado.',
   '[{"ordem":1,"acao":"Conferir o gatilho BEFORE UPDATE trg_profiles_protege_tenant ativo e a funcao que confere tenant_id e Super Admin","resultado_esperado":"Presentes"},{"ordem":2,"acao":"Conferir que nao existe politica de INSERT em profiles com so user_id = auth.uid()","resultado_esperado":"Ausente"}]'::jsonb,
   'Cada usuario fica na propria empresa.', 'Rotina qa_caso_perfil_031 (somente leitura, estrutural).')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('PERFIL-031', 'qa_caso_perfil_031', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-031 nao registrada: %', SQLERRM;
END $doc$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). A rotina fica registrada e entra na proxima execucao.', SQLERRM;
END $roda$;
