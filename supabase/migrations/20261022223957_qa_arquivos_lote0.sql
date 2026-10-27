-- =========================================================
-- QA — Arquivos (storage) lote 0: empresa + perfil
--
--   PERFIL-027 (api, somente leitura)  as regras dos buckets atestados, trilha-evidencias,
--              epi-signatures, ergonomia-evidencias e hub-contabil exigem a EMPRESA e o PERFIL;
--              nenhuma decide so pelo papel de gestao.
--
-- Nao ha prova funcional no motor: ela exigiria criar arquivos de duas empresas (a rotina e
-- somente leitura). A prova funcional foi feita em replica local (antes/depois) e consta no PR.
-- Idempotente: caso com ON CONFLICT (codigo) DO NOTHING; implementacao por upsert.
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_perfil_027()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  b text;
  v_exige text;
  rec record;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): regras de arquivos sensiveis exigem empresa e perfil';
  r.esperado    := 'Nenhuma regra dos 5 buckets decide so pelo papel; cada bucket tem regra com a empresa e o perfil';

  -- 1) Nenhuma regra desses buckets pode decidir so pelo papel (has_minimum_role / has_role de gestao)
  FOR rec IN
    SELECT p.policyname, p.cmd, lower(COALESCE(p.qual, '') || ' ' || COALESCE(p.with_check, '')) AS txt
      FROM pg_policies p
     WHERE p.schemaname = 'storage' AND p.tablename = 'objects'
       AND lower(COALESCE(p.qual, '') || ' ' || COALESCE(p.with_check, '')) ~
           '(atestados|trilha-evidencias|epi-signatures|ergonomia-evidencias|hub-contabil)'
  LOOP
    IF rec.txt ~ 'has_(minimum_)?role' AND rec.txt !~ 'superadmin' AND rec.txt !~ 'perfil_permite_modulo' THEN
      v_falhas := v_falhas || ('regra "' || rec.policyname || '" (' || rec.cmd || ') decide so pelo papel')::text;
    END IF;
  END LOOP;

  -- 2) Regras novas presentes, com empresa e (quando aplicavel) perfil
  FOREACH b IN ARRAY ARRAY[
      'Atestados: leitura pela empresa e pelo perfil',
      'Atestados: envio pela empresa e pelo perfil',
      'Atestados: exclusao pela empresa e pelo perfil',
      'Trilha: evidencias da empresa lidas pelo perfil',
      'EPI assinaturas: exclusao pela empresa e pelo perfil',
      'EPI assinaturas: envio so na pasta da empresa',
      'Ergonomia: exclusao pela empresa e pelo perfil',
      'Hub contabil: exclusao pela empresa e pelo perfil'] LOOP
    v_exige := (SELECT lower(COALESCE(qual, '') || ' ' || COALESCE(with_check, ''))
                  FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = b);
    IF v_exige IS NULL THEN
      v_falhas := v_falhas || ('falta a regra "' || b || '"')::text;
    ELSE
      IF v_exige !~ 'get_user_tenant_id|ye_trilha_evidencia_da_empresa' THEN
        v_falhas := v_falhas || ('"' || b || '" nao confere a empresa')::text;
      END IF;
      IF b NOT LIKE '%envio so na pasta%' AND v_exige !~ 'perfil_permite_modulo' THEN
        v_falhas := v_falhas || ('"' || b || '" nao consulta o perfil')::text;
      END IF;
    END IF;
  END LOOP;

  -- 3) Funcao de apoio da trilha: existe e e SECURITY DEFINER
  IF to_regprocedure('public.ye_trilha_evidencia_da_empresa(text)') IS NULL THEN
    v_falhas := v_falhas || 'falta a funcao ye_trilha_evidencia_da_empresa'::text;
  ELSIF NOT (SELECT prosecdef FROM pg_proc WHERE oid = to_regprocedure('public.ye_trilha_evidencia_da_empresa(text)')) THEN
    v_falhas := v_falhas || 'ye_trilha_evidencia_da_empresa nao e SECURITY DEFINER'::text;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Regras de arquivos dos 5 buckets exigem a empresa e o perfil; nenhuma decide so pelo papel.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
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
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-027 nao documentado.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PERFIL-027', 'Arquivos sensiveis (atestados, trilha, EPI, ergonomia, hub) exigem a empresa e o perfil',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD arts. 6º, 11 e 46',
   'Achado do levantamento de 10/2026: regras de arquivos decidiam so pelo papel de gestao, sem a empresa, e permitiam a um gestor de uma empresa ler, enviar e apagar arquivos de outras (atestados medicos inclusive). Garante que as regras dos 5 buckets conferem a empresa e o perfil e que nenhuma volta a decidir so pelo papel.',
   'Lote 0 de arquivos aplicado.',
   '[{"ordem":1,"acao":"Varrer as regras de storage.objects dos buckets atestados, trilha-evidencias, epi-signatures, ergonomia-evidencias e hub-contabil","resultado_esperado":"Nenhuma decide so por has_minimum_role"},{"ordem":2,"acao":"Conferir as 8 regras novas e a funcao de apoio da trilha","resultado_esperado":"Presentes, com empresa e perfil"}]'::jsonb,
   'Todas as regras de arquivos com empresa e perfil.', 'Rotina qa_caso_perfil_027 (somente leitura). Prova funcional antes/depois em replica local, descrita no PR do lote 0. O bucket epi-signatures segue publico para leitura (etapa seguinte).')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('PERFIL-027', 'qa_caso_perfil_027', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-027 nao registrada: %', SQLERRM;
END $doc$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). A rotina fica registrada e entra na proxima execucao.', SQLERRM;
END $roda$;
