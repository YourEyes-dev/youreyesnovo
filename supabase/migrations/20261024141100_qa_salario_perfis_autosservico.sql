-- =========================================================
-- QA — salario: perfis de autosservico nao veem salario
--
--   PERFIL-037 (api, somente leitura)  nenhum perfil ATIVO que so libera os proprios dados (nenhuma permissao em escopo
--              diferente de "proprio usuario") tem "Pode ver salario" ligado.
-- Idempotente: caso com ON CONFLICT (codigo) DO NOTHING; implementacao por upsert.
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_perfil_037()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_n bigint;
  v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): perfis de autosservico com salario ligado';
  r.esperado    := 'Nenhum perfil ativo que so libera os proprios dados tem "Pode ver salario" ligado';

  v_n := (SELECT count(*) FROM public.perfis_acesso pa
           WHERE COALESCE(pa.ativo, true) AND pa.pode_ver_salario
             AND NOT EXISTS (SELECT 1 FROM public.perfil_permissoes pp
                              WHERE pp.perfil_id = pa.id AND COALESCE(pp.ativo, true)
                                AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario'));
  IF COALESCE(v_n, 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Nenhum perfil de autosservico ve salario.';
  ELSE
    v_lista := (SELECT string_agg(DISTINCT pa.nome, ', ') FROM public.perfis_acesso pa
                 WHERE COALESCE(pa.ativo, true) AND pa.pode_ver_salario
                   AND NOT EXISTS (SELECT 1 FROM public.perfil_permissoes pp
                                    WHERE pp.perfil_id = pa.id AND COALESCE(pp.ativo, true)
                                      AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario'));
    r.situacao := 'falhou';
    r.obtido   := v_n || ' perfil(is) de autosservico com salario ligado: ' || COALESCE(v_lista, '');
    r.detalhe  := jsonb_build_object('perfis', v_lista, 'quantidade', v_n);
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
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-037 nao documentado.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-037', 'Salario: perfil que so libera os proprios dados nao ve salario de ninguem',
   'negativo', 'alta', 'aprovado', 'api', 'LGPD arts. 6º e 46',
   'Dezenas de perfis "Colaborador com Acesso" (modelo criado para cada cliente) e outros perfis de autosservico estavam com "Pode ver salario" ligado: quem fosse vinculado a eles leria o salario de todos pela visao do cadastro. Agora esses perfis ficam desligados (copia em backup_perfis_salario_autoss_20261024); o proprio holerite continua visivel pela regra da folha. Perfis com acesso amplo ou de equipe sao decisao de cada cliente.',
   'Script dos perfis de autosservico aplicado.',
   '[{"ordem":1,"acao":"Contar perfis ativos sem nenhuma permissao fora de proprio_usuario e com pode_ver_salario ligado","resultado_esperado":"Zero"}]'::jsonb,
   'Autosservico nao ve salario alheio.', 'Rotina qa_caso_perfil_037 (somente leitura).')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('PERFIL-037', 'qa_caso_perfil_037', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-037 nao registrada: %', SQLERRM;
END $doc$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). A rotina fica registrada e entra na proxima execucao.', SQLERRM;
END $roda$;
