-- ============================================================================
-- ENTREGA — Jornada LOTE 1b: leitura por pessoa em alertas, escala, troca de turno, acordos e lotacao
--
-- Cole no SQL Editor (TESTE e HOMOLOGACAO primeiro; depois PRODUCAO). UMA transacao, idempotente.
-- So politicas de leitura (RESTRICTIVE): nenhum dado e alterado e nenhuma tabela e criada.
-- Cada tabela e atomica: se uma falhar, so ela fica de fora e o aviso diz qual.
-- Pre-requisito: o script_fix_subordinados_departamento_por_nome.sql (lote 1a) ja aplicado.
-- Termina com UMA conferencia SELECT. Rode ANTES a consulta_jornada_lote1b_quem_muda.sql.
-- ============================================================================
SET lock_timeout = '10s';

DO $jor$
DECLARE
  r record;
  v_mods text;
  v_using text;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('ponto_alertas', 'padrao'),
      ('ponto_escala_atribuicoes', 'padrao'),
      ('ponto_lotacao_historico', 'padrao'),
      ('ponto_troca_turno',        'troca'),
      ('ponto_acordos',            'sem_cpf')
    ) AS t(tabela, modo)
  LOOP
    BEGIN
      IF to_regclass('public.' || r.tabela) IS NULL THEN
        RAISE NOTICE 'Jornada 1b: tabela % nao existe nesta base; pulada.', r.tabela;
        CONTINUE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = r.tabela AND column_name = 'tenant_id') THEN
        RAISE NOTICE 'ATENCAO: % sem tenant_id; ficou SEM a trava.', r.tabela;
        CONTINUE;
      END IF;

      v_mods := quote_literal(ARRAY['ponto','colaboradores']) || '::text[]';

      IF r.modo = 'troca' THEN
        v_using :=
             'public.perfil_amplo_sem_subordinados(tenant_id, VARIADIC ' || v_mods || ') '
          || 'OR regexp_replace(COALESCE(colaborador_a_cpf,''''),''[^0-9]'','''',''g'') = public.cpf_do_usuario_logado() '
          || 'OR regexp_replace(COALESCE(colaborador_b_cpf,''''),''[^0-9]'','''',''g'') = public.cpf_do_usuario_logado() '
          || 'OR (public.perfil_tem_escopo_subordinados(tenant_id, VARIADIC ' || v_mods || ') '
          || 'AND (public.ye_cpf_eh_subordinado_direto(tenant_id, colaborador_a_cpf) '
          || 'OR public.ye_cpf_eh_subordinado_direto(tenant_id, colaborador_b_cpf)))';
      ELSIF r.modo = 'sem_cpf' THEN
        v_using :=
             'public.perfil_amplo_sem_subordinados(tenant_id, VARIADIC ' || v_mods || ') '
          || 'OR public.perfil_tem_escopo_subordinados(tenant_id, VARIADIC ' || v_mods || ')';
      ELSE
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_schema = 'public' AND table_name = r.tabela AND column_name = 'colaborador_cpf') THEN
          RAISE NOTICE 'ATENCAO: % sem colaborador_cpf; ficou SEM a trava.', r.tabela;
          CONTINUE;
        END IF;
        v_using :=
             'public.perfil_amplo_sem_subordinados(tenant_id, VARIADIC ' || v_mods || ') '
          || 'OR regexp_replace(COALESCE(colaborador_cpf,''''),''[^0-9]'','''',''g'') = public.cpf_do_usuario_logado() '
          || 'OR (public.perfil_tem_escopo_subordinados(tenant_id, VARIADIC ' || v_mods || ') '
          || 'AND public.ye_cpf_eh_subordinado_direto(tenant_id, colaborador_cpf))';
        IF r.tabela = 'ponto_alertas' THEN
          v_using := v_using
            || ' OR (tipo IN (''excesso_jornada'',''intervalo_suprimido'',''interjornada_insuficiente'') '
            || 'AND public.perfil_amplo_sem_subordinados(tenant_id, VARIADIC ARRAY[''ergonomia'']::text[]))';
        END IF;
      END IF;

      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS perfil_restringe_leitura_%1$s ON public.%1$I', r.tabela);
      EXECUTE format('CREATE POLICY perfil_restringe_leitura_%1$s ON public.%1$I AS RESTRICTIVE FOR SELECT TO authenticated USING (%2$s)',
                     r.tabela, v_using);
      RAISE NOTICE 'Jornada 1b: leitura por perfil aplicada em %.', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % ficou SEM a trava de leitura: %', r.tabela, SQLERRM;
    END;
  END LOOP;
END $jor$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND permissive='RESTRICTIVE'
     AND policyname = 'perfil_restringe_leitura_' || tablename
     AND tablename IN ('ponto_alertas','ponto_escala_atribuicoes','ponto_lotacao_historico','ponto_troca_turno','ponto_acordos')) AS tabelas_com_a_trava,
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind='r'
      AND c.relname IN ('ponto_alertas','ponto_escala_atribuicoes','ponto_lotacao_historico','ponto_troca_turno','ponto_acordos')) AS tabelas_do_lote_que_existem;
-- Os dois numeros devem ser IGUAIS (5 e 5). Depois rode a bateria do Ponto:
--   SELECT public.qa_rodar_bateria('manual', 'jornada-rotina/ponto');
-- e compare "falhou" e "erro" com o de antes:
--   SELECT total, passou, falhou, erro, nao_implementado FROM public.qa_execucoes
--    WHERE modulo_path = 'jornada-rotina/ponto' ORDER BY iniciada_em DESC NULLS LAST LIMIT 1;
--
-- DESFAZER (so se algo errado aparecer; devolve a leitura aberta ao tenant, como era):
--   DROP POLICY perfil_restringe_leitura_ponto_alertas ON public.ponto_alertas;  (idem nas outras 4 tabelas)
