-- =========================================================
-- QA — salario: padrao fechado e contratos de experiencia mascarados
--
--   PERFIL-036 (api, somente leitura)  perfis_acesso.pode_ver_salario nasce desligado; nenhum perfil "Colaborador (padrao)"
--              ve salario; a visao contratos_experiencia_segura mascara o salario por pode_ver_salario e o gatilho
--              preserva o valor de quem nao pode ver.
-- Idempotente: caso com ON CONFLICT (codigo) DO NOTHING; implementacao por upsert.
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_perfil_036()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_def text;
  v_n bigint;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): salario fechado por padrao e contratos de experiencia mascarados';
  r.esperado    := 'Padrao desligado, Colaborador (padrao) sem salario, visao e gatilho dos contratos presentes';

  v_def := (SELECT pg_get_expr(d.adbin, d.adrelid) FROM pg_attrdef d
             JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
            WHERE d.adrelid = 'public.perfis_acesso'::regclass AND a.attname = 'pode_ver_salario');
  IF v_def IS NULL OR v_def !~* 'false' THEN
    v_falhas := v_falhas || ('perfis_acesso.pode_ver_salario tem padrao ' || COALESCE(v_def, '(nenhum)'))::text;
  END IF;

  v_n := (SELECT count(*) FROM public.perfis_acesso WHERE nome = 'Colaborador (padrão)' AND pode_ver_salario);
  IF COALESCE(v_n, 0) > 0 THEN
    v_falhas := v_falhas || (v_n || ' perfil(is) Colaborador (padrao) ainda veem salario')::text;
  END IF;

  IF to_regclass('public.contratos_experiencia') IS NOT NULL THEN
    v_def := (SELECT pg_get_viewdef('public.contratos_experiencia_segura'::regclass));
    IF v_def IS NULL OR position('pode_ver_salario' IN v_def) = 0 THEN
      v_falhas := v_falhas || 'a visao contratos_experiencia_segura nao mascara o salario'::text;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.contratos_experiencia'::regclass
                    AND t.tgname = 'trg_contratos_preserva_salario' AND NOT t.tgisinternal AND t.tgenabled <> 'D') THEN
      v_falhas := v_falhas || 'falta o gatilho que preserva o salario do contrato'::text;
    END IF;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
  ELSE
    r.situacao := 'passou';
    r.obtido   := 'Salario fechado por padrao; Colaborador (padrao) sem salario; contratos de experiencia mascarados.';
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
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-036 nao documentado.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-036', 'Salario: fechado por padrao nos perfis novos e mascarado nos contratos de experiencia',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD arts. 6º e 46',
   'A opcao "Pode ver salario" do perfil nascia LIGADA, inclusive no perfil Colaborador (padrao) criado automaticamente, e o salario copiado nos contratos de experiencia nao tinha mascara. Agora: perfil novo nasce com salario desligado; os perfis Colaborador (padrao) existentes foram desligados (copia em backup_perfis_salario_20261023); os contratos de experiencia sao lidos por uma visao que mascara o salario e um gatilho preserva o valor de quem nao pode ver.',
   'Script do salario aplicado.',
   '[{"ordem":1,"acao":"Conferir o padrao desligado de perfis_acesso.pode_ver_salario e que nenhum Colaborador (padrao) ve salario","resultado_esperado":"Desligado"},{"ordem":2,"acao":"Conferir a visao contratos_experiencia_segura e o gatilho de preservacao","resultado_esperado":"Presentes"}]'::jsonb,
   'Menos acesso a salario por omissao.', 'Rotina qa_caso_perfil_036 (somente leitura, estrutural). Limite conhecido: quem le a linha da tabela de origem ainda le a coluna pela API direta.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('PERFIL-036', 'qa_caso_perfil_036', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-036 nao registrada: %', SQLERRM;
END $doc$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). A rotina fica registrada e entra na proxima execucao.', SQLERRM;
END $roda$;
