-- ============================================================================
-- ENTREGA — Jornada: ESCRITA pelo perfil de acesso (18 tabelas de ponto/jornada)
--
-- Cole no SQL Editor (TESTE e HOMOLOGACAO primeiro; depois PRODUCAO). UMA transacao, idempotente.
-- So politicas de escrita (RESTRICTIVE) e a troca de 2 gatilhos de atestado para "security definer";
-- nenhum dado e alterado e nenhuma tabela e criada. Cada tabela e atomica: se uma falhar, so ela fica de fora
-- e o aviso diz qual. Pre-requisito: lotes 1a e 1b de leitura ja aplicados.
-- Rode ANTES as consultas consulta_jornada_escrita_quem_muda.sql e consulta_jornada_escrita_sem_perfil.sql.
-- Termina com UMA conferencia SELECT.
-- ============================================================================
SET lock_timeout = '10s';

-- ── 1) Gatilhos de atestado gravam por conta do sistema ─────────────────────
DO $gat$
DECLARE
  v_fn text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['public.ponto_atestado_detectar_sobreposicao()',
                              'public.ponto_atestado_encaminhar_afastamento()'] LOOP
    BEGIN
      IF to_regprocedure(v_fn) IS NULL THEN
        RAISE NOTICE 'Escrita jornada: % nao existe nesta base; pulada.', v_fn;
        CONTINUE;
      END IF;
      EXECUTE 'ALTER FUNCTION ' || v_fn || ' SECURITY DEFINER SET search_path TO ''public''';
      RAISE NOTICE 'Escrita jornada: % agora grava por conta do sistema.', v_fn;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % nao foi ajustada: %', v_fn, SQLERRM;
    END;
  END LOOP;
END $gat$;

-- ── 2) Escrita pela gestao (perfil decide) ──────────────────────────────────
DO $esc$
DECLARE
  r record;
  v_mods text;
  v_ins text;
  v_upd text;
  v_del text;
  v_cols text;
  v_own text := 'regexp_replace(COALESCE(colaborador_cpf,''''),''[^0-9]'','''',''g'') = public.cpf_do_usuario_logado()';
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('ponto_banco_horas',               ARRAY['ponto','colaboradores'],                    'cpf'),
      ('ponto_banco_horas_movimentacoes', ARRAY['ponto','colaboradores'],                    'cpf'),
      ('ponto_links',                     ARRAY['ponto','colaboradores'],                    'cpf'),
      ('ponto_pre_assinalacao',           ARRAY['ponto','colaboradores'],                    'cpf'),
      ('ponto_escala_atribuicoes',        ARRAY['ponto','colaboradores'],                    'cpf'),
      ('ponto_acordos',                   ARRAY['ponto','colaboradores'],                    'sem_cpf'),
      ('jornada_alertas',                 ARRAY['analise_jornada','ponto','colaboradores'],  'cpf'),
      ('jornada_analises',                ARRAY['analise_jornada','ponto','colaboradores'],  'cpf'),
      ('ponto_troca_turno',               ARRAY['ponto','colaboradores'],                    'troca'),
      ('ponto_alertas',                   ARRAY['ponto','colaboradores'],                    'alerta'),
      ('ponto_ajustes',                   ARRAY['ponto','colaboradores'],                    'ajuste')
    ) AS t(tabela, modulos, modo)
  LOOP
    BEGIN
      IF to_regclass('public.' || r.tabela) IS NULL THEN
        RAISE NOTICE 'Escrita jornada: tabela % nao existe; pulada.', r.tabela;
        CONTINUE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = r.tabela AND column_name = 'tenant_id') THEN
        RAISE NOTICE 'ATENCAO: % sem tenant_id; ficou SEM a trava de escrita.', r.tabela;
        CONTINUE;
      END IF;

      v_mods := quote_literal(r.modulos) || '::text[]';

      IF r.modo = 'troca' THEN
        v_ins := '(public.perfil_permite_modulo(tenant_id, VARIADIC ' || v_mods || ') '
              || 'AND public.perfil_escreve(tenant_id, ' || v_mods || ', ARRAY[''criar'']::text[], colaborador_a_cpf) '
              || 'AND public.perfil_escreve(tenant_id, ' || v_mods || ', ARRAY[''criar'']::text[], colaborador_b_cpf))';
        v_upd := '(public.perfil_permite_modulo(tenant_id, VARIADIC ' || v_mods || ') '
              || 'AND public.perfil_escreve(tenant_id, ' || v_mods || ', ARRAY[''editar'',''aprovar'']::text[], colaborador_a_cpf) '
              || 'AND public.perfil_escreve(tenant_id, ' || v_mods || ', ARRAY[''editar'',''aprovar'']::text[], colaborador_b_cpf))';
        v_del := '(public.perfil_permite_modulo(tenant_id, VARIADIC ' || v_mods || ') '
              || 'AND public.perfil_escreve(tenant_id, ' || v_mods || ', ARRAY[''excluir'']::text[], colaborador_a_cpf) '
              || 'AND public.perfil_escreve(tenant_id, ' || v_mods || ', ARRAY[''excluir'']::text[], colaborador_b_cpf))';
      ELSE
        v_cols := CASE WHEN r.modo = 'sem_cpf' THEN 'NULL::text' ELSE 'colaborador_cpf' END;
        v_ins := '(public.perfil_permite_modulo(tenant_id, VARIADIC ' || v_mods || ') '
              || 'AND public.perfil_escreve(tenant_id, ' || v_mods || ', ARRAY[''criar'']::text[], ' || v_cols || '))';
        v_upd := '(public.perfil_permite_modulo(tenant_id, VARIADIC ' || v_mods || ') '
              || 'AND public.perfil_escreve(tenant_id, ' || v_mods || ', ARRAY[''editar'',''aprovar'']::text[], ' || v_cols || '))';
        v_del := '(public.perfil_permite_modulo(tenant_id, VARIADIC ' || v_mods || ') '
              || 'AND public.perfil_escreve(tenant_id, ' || v_mods || ', ARRAY[''excluir'']::text[], ' || v_cols || '))';
        IF r.modo = 'ajuste' THEN
          -- o colaborador solicita o proprio ajuste; ja entra pendente
          v_ins := '((' || v_own || ' AND COALESCE(status,''pendente'') = ''pendente'') OR ' || v_ins || ')';
        END IF;
      END IF;

      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_escrita_' || r.tabela || '_ins', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_escrita_' || r.tabela || '_upd', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_escrita_' || r.tabela || '_del', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'escrita_so_dono_' || r.tabela || '_ins', r.tabela);

      IF r.modo = 'alerta' THEN
        -- alerta nasce do sistema (rotinas security definer e agendador): o cliente so resolve ou exclui
        EXECUTE format(
          'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated '
          || 'WITH CHECK (public.is_superadmin(auth.uid()) OR public.ye_eh_dono(auth.uid(), tenant_id))',
          'escrita_so_dono_' || r.tabela || '_ins', r.tabela);
        v_upd := '(public.perfil_permite_modulo(tenant_id, VARIADIC ' || v_mods || ') '
              || 'AND public.perfil_escreve(tenant_id, ' || v_mods || ', ARRAY[''editar'',''aprovar'']::text[], colaborador_cpf))';
        v_del := '(public.perfil_permite_modulo(tenant_id, VARIADIC ' || v_mods || ') '
              || 'AND public.perfil_escreve(tenant_id, ' || v_mods || ', ARRAY[''excluir'']::text[], colaborador_cpf))';
      ELSE
        EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (%s)',
                       'perfil_restringe_escrita_' || r.tabela || '_ins', r.tabela, v_ins);
      END IF;
      EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated USING (%s) WITH CHECK (%s)',
                     'perfil_restringe_escrita_' || r.tabela || '_upd', r.tabela, v_upd, v_upd);
      EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR DELETE TO authenticated USING (%s)',
                     'perfil_restringe_escrita_' || r.tabela || '_del', r.tabela, v_del);
      RAISE NOTICE 'Escrita jornada: perfil decide em %.', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % ficou SEM a trava de escrita: %', r.tabela, SQLERRM;
    END;
  END LOOP;
END $esc$;

-- ── 3) Tabelas que ninguem grava pelo cliente: so Super Admin e dono ─────────
DO $dono$
DECLARE
  v_tab text;
  v_alt text;
BEGIN
  FOREACH v_tab IN ARRAY ARRAY['ponto_semanal','ponto_equalizacao_mensal','ponto_comprovantes','ponto_memoria_calculo',
                               'ponto_compensacao_falta','ponto_lotacao_historico','ponto_acesso_sensivel_log'] LOOP
    BEGIN
      IF to_regclass('public.' || v_tab) IS NULL THEN
        RAISE NOTICE 'Escrita jornada: tabela % nao existe; pulada.', v_tab;
        CONTINUE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = v_tab AND column_name = 'tenant_id') THEN
        RAISE NOTICE 'ATENCAO: % sem tenant_id; ficou SEM a trava de escrita.', v_tab;
        CONTINUE;
      END IF;

      -- a trilha de auditoria nao e alterada nem apagada nem pelo dono do cliente
      v_alt := CASE WHEN v_tab = 'ponto_acesso_sensivel_log'
                    THEN 'public.is_superadmin(auth.uid())'
                    ELSE 'public.is_superadmin(auth.uid()) OR public.ye_eh_dono(auth.uid(), tenant_id)' END;

      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'escrita_so_dono_' || v_tab || '_ins', v_tab);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'escrita_so_dono_' || v_tab || '_upd', v_tab);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'escrita_so_dono_' || v_tab || '_del', v_tab);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated '
        || 'WITH CHECK (public.is_superadmin(auth.uid()) OR public.ye_eh_dono(auth.uid(), tenant_id))',
        'escrita_so_dono_' || v_tab || '_ins', v_tab);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated USING (%s) WITH CHECK (%s)',
        'escrita_so_dono_' || v_tab || '_upd', v_tab, v_alt, v_alt);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR DELETE TO authenticated USING (%s)',
        'escrita_so_dono_' || v_tab || '_del', v_tab, v_alt);
      RAISE NOTICE 'Escrita jornada: direta fechada (so Super Admin e dono) em %.', v_tab;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % nao foi endurecida: %', v_tab, SQLERRM;
    END;
  END LOOP;
END $dono$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT count(DISTINCT tablename) FROM pg_policies
    WHERE schemaname='public' AND permissive='RESTRICTIVE'
      AND (policyname LIKE 'perfil_restringe_escrita_%' OR policyname LIKE 'escrita_so_dono_%')
      AND tablename IN ('ponto_banco_horas','ponto_banco_horas_movimentacoes','ponto_links','ponto_pre_assinalacao','ponto_escala_atribuicoes',
                        'ponto_acordos','jornada_alertas','jornada_analises','ponto_troca_turno','ponto_alertas','ponto_ajustes','ponto_semanal',
                        'ponto_equalizacao_mensal','ponto_comprovantes','ponto_memoria_calculo','ponto_compensacao_falta','ponto_lotacao_historico',
                        'ponto_acesso_sensivel_log'))                                   AS tabelas_com_a_trava,
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind='r'
      AND c.relname IN ('ponto_banco_horas','ponto_banco_horas_movimentacoes','ponto_links','ponto_pre_assinalacao','ponto_escala_atribuicoes',
                        'ponto_acordos','jornada_alertas','jornada_analises','ponto_troca_turno','ponto_alertas','ponto_ajustes','ponto_semanal',
                        'ponto_equalizacao_mensal','ponto_comprovantes','ponto_memoria_calculo','ponto_compensacao_falta','ponto_lotacao_historico',
                        'ponto_acesso_sensivel_log'))                                   AS tabelas_do_lote_que_existem,
  (SELECT count(*) FROM pg_proc WHERE oid IN (to_regprocedure('public.ponto_atestado_detectar_sobreposicao()'),
                                              to_regprocedure('public.ponto_atestado_encaminhar_afastamento()')) AND prosecdef) AS gatilhos_atestado_definer;
-- Esperado: 18, 18 e 2. Depois rode a bateria do Ponto e compare "falhou" e "erro" com o de antes:
--   SELECT public.qa_rodar_bateria('manual', 'jornada-rotina/ponto');
--   SELECT total, passou, falhou, erro, nao_implementado FROM public.qa_execucoes
--    WHERE modulo_path = 'jornada-rotina/ponto' ORDER BY iniciada_em DESC NULLS LAST LIMIT 1;
--
-- DESFAZER (so se algo errado aparecer; devolve a escrita aberta ao tenant, como era). Para cada tabela do lote:
--   DROP POLICY IF EXISTS perfil_restringe_escrita_<tabela>_ins ON public.<tabela>;  (e _upd, _del)
--   DROP POLICY IF EXISTS escrita_so_dono_<tabela>_ins ON public.<tabela>;           (e _upd, _del)
-- e, se quiser voltar os gatilhos: ALTER FUNCTION public.ponto_atestado_detectar_sobreposicao() SECURITY INVOKER; (idem o outro).
