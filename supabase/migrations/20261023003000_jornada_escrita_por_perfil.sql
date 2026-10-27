-- ============================================================================
-- JORNADA — ESCRITA: quem pode gravar nas 18 tabelas de ponto/jornada (LGPD arts. 6 e 46)
--
-- Os lotes 1a e 1b fecharam a LEITURA. A escrita seguia liberada a qualquer membro da empresa (so o tenant):
-- um colaborador comum podia gravar escala, banco de horas, acordos e alertas. Aqui a escrita passa a seguir o
-- perfil de acesso, com a mesma decisao da Fase 2b (perfil_escreve) mais o porteiro do modulo
-- (perfil_permite_modulo), que e quem fecha o caso "sem perfil vinculado e sem papel de gestao".
--
-- QUEM ESCREVE (mapeado no codigo e nas funcoes):
--   A) so a gestao pelo cliente (tela de Ponto/Jornada): INSERT exige o verbo criar; UPDATE editar ou aprovar;
--      DELETE excluir, no modulo e com o escopo do perfil (lider de subordinados so na linha da equipe).
--      ponto_banco_horas, ponto_banco_horas_movimentacoes, ponto_links, ponto_pre_assinalacao,
--      ponto_escala_atribuicoes, ponto_acordos, jornada_alertas, jornada_analises, ponto_troca_turno
--      (vale para as DUAS pessoas da troca), ponto_alertas (UPDATE e DELETE).
--   B) ponto_ajustes: alem da gestao, o colaborador SOLICITA o proprio ajuste (INSERT na propria linha, sempre
--      pendente). Aprovar, editar e excluir continuam so da gestao.
--   C) ninguem grava pelo cliente (escrevem funcoes security definer, o agendador ou borda): a escrita direta
--      passa a ser so do Super Admin e do dono. ponto_semanal, ponto_equalizacao_mensal, ponto_comprovantes,
--      ponto_memoria_calculo, ponto_compensacao_falta, ponto_lotacao_historico, ponto_acesso_sensivel_log
--      (trilha de auditoria: apos gravada, so o Super Admin altera ou apaga) e o INSERT de ponto_alertas.
--
-- GATILHOS DE ATESTADO: ponto_atestado_detectar_sobreposicao e ponto_atestado_encaminhar_afastamento rodavam com o
-- direito de quem registra o atestado e gravam alerta (e o afastamento previdenciario). Com a trava, quem registra
-- atestado sem ter Ponto perderia o alerta em silencio (o bloco de excecao engole o erro). Passam a security
-- definer, como as demais rotinas que o sistema grava por conta propria; o corpo das funcoes nao muda.
--
-- Nao altera dado. Atomico por tabela: se uma falhar, so ela fica de fora e o aviso diz qual.
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
