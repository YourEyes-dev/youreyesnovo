-- Acesso: backfill dos COLABORADORES sem perfil recebem o "Colaborador (padrão)"
--
-- Contexto: desde a Fase 1a o perfil vinculado manda no acesso. Quem NAO tem perfil
-- segue no comportamento legado (papel/tipo), e a trava de escrita (Fases 2b a 2e) so
-- vale para quem tem perfil. A Fase 2a deu o modelo aos usuarios de gestao; ficaram
-- de fora os colaboradores (decisao a parte: muda a navegacao deles, de hierarquia de
-- papeis para perfil de autosservico, tudo em escopo proprio usuario).
--
-- Quem recebe: usuario ATIVO, com login, do tipo colaborador, sem papel de dono,
-- manager ou admin, que nao seja Super Admin e que NAO tenha nenhum perfil vigente.
-- Quem NAO e tocado: qualquer outro tipo (rh, proprietario, tecnico_seguranca,
-- saude_ocupacional, parceiros, auditor...), que opera por papel e precisa de decisao
-- individual; quem ja tem perfil (o perfil manda); owners e superadmins.
--
-- O vinculo segue o mesmo desenho do cadastro de usuario novo (gatilho
-- trg_vincular_perfil_padrao): ativo, NAO principal, perfil_padrao_colaborador do
-- cliente (criado se ainda nao existir). Cada linha nova leva a marca "Sistema
-- (Backfill colaboradores)", para o desfazer ser exato. Idempotente.
-- A copia de seguranca dos vinculos dos usuarios alvo fica em
-- backup_vinculos_colab_20261016 (fechada para a API).
DO $bf$
DECLARE
  v_ids uuid[];
  v_perfil uuid;
  v_total int := 0;
  v_erros int := 0;
  r record;
BEGIN
  v_ids := ARRAY(
    SELECT ub.id
      FROM public.usuarios_base ub
     WHERE ub.auth_user_id IS NOT NULL
       AND ub.tenant_id IS NOT NULL
       AND ub.status::text = 'ativo'
       AND ub.tipo_usuario::text = 'colaborador'
       AND NOT EXISTS (SELECT 1 FROM public.user_roles ur
                        WHERE ur.user_id = ub.auth_user_id
                          AND ur.role::text IN ('owner', 'manager', 'admin'))
       AND NOT public.is_superadmin(ub.auth_user_id)
       AND NOT EXISTS (
             SELECT 1 FROM public.usuario_perfil_vinculos v
               JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
              WHERE v.usuario_id = ub.id
                AND COALESCE(v.ativo, true) = true
                AND (v.expira_em IS NULL OR v.expira_em > now())
                AND COALESCE(pa.ativo, true) = true
                AND (pa.expira_em IS NULL OR pa.expira_em > now()))
  );

  IF COALESCE(array_length(v_ids, 1), 0) = 0 THEN
    RAISE NOTICE 'Backfill colaboradores: nenhum colaborador sem perfil.';
    RETURN;
  END IF;

  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS public.backup_vinculos_colab_20261016 AS '
       || 'SELECT * FROM public.usuario_perfil_vinculos WHERE usuario_id = ANY ('
       || quote_literal(v_ids::text) || '::uuid[])';
  EXECUTE 'ALTER ' || 'TABLE public.backup_vinculos_colab_20261016 ENABLE ROW LEVEL SECURITY';
  EXECUTE 'REVOKE ALL ON public.backup_vinculos_colab_20261016 FROM PUBLIC, anon, authenticated';

  FOR r IN
    SELECT ub.id AS usuario_id, ub.tenant_id
      FROM public.usuarios_base ub
     WHERE ub.id = ANY (v_ids)
  LOOP
    BEGIN
      v_perfil := public.perfil_padrao_colaborador(r.tenant_id);
      IF v_perfil IS NULL THEN
        CONTINUE;
      END IF;

      -- vinculo ao padrao que existe desligado: religa
      UPDATE public.usuario_perfil_vinculos x
         SET ativo = true,
             observacao = COALESCE(x.observacao, '')
               || ' [religado no backfill de colaboradores em 16/10/2026]'
       WHERE x.usuario_id = r.usuario_id AND x.perfil_id = v_perfil
         AND COALESCE(x.ativo, true) = false;

      INSERT INTO public.usuario_perfil_vinculos
        (tenant_id, usuario_id, perfil_id, ativo, is_perfil_principal,
         atribuido_por_nome, observacao)
      SELECT r.tenant_id, r.usuario_id, v_perfil, true, false,
             'Sistema (Backfill colaboradores)',
             'Backfill 16/10/2026: colaborador sem perfil recebe o perfil de autosserviço.'
       WHERE NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos x
                          WHERE x.usuario_id = r.usuario_id AND x.perfil_id = v_perfil);

      v_total := v_total + 1;
    EXCEPTION WHEN OTHERS THEN
      v_erros := v_erros + 1;
      RAISE NOTICE 'Backfill colaboradores: usuario % nao processado: % (%)',
        r.usuario_id, SQLERRM, SQLSTATE;
    END;
  END LOOP;

  RAISE NOTICE 'Backfill colaboradores: % usuario(s) processado(s), % erro(s).', v_total, v_erros;
END
$bf$;

-- QA PERFIL-014: guarda de regressao. Nenhum colaborador ativo pode ficar sem perfil
-- (se o gatilho de cadastro falhar em silencio, a rotina acusa).
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_014()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_qtd bigint;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): colaboradores ativos sem nenhum perfil vigente';
  r.esperado    := 'Nenhum colaborador ativo (sem papel de dono, manager ou admin) sem perfil vinculado';

  v_qtd := (
    SELECT count(*)
      FROM public.usuarios_base ub
     WHERE ub.auth_user_id IS NOT NULL
       AND ub.tenant_id IS NOT NULL
       AND ub.status::text = 'ativo'
       AND ub.tipo_usuario::text = 'colaborador'
       AND NOT EXISTS (SELECT 1 FROM public.user_roles ur
                        WHERE ur.user_id = ub.auth_user_id
                          AND ur.role::text IN ('owner', 'manager', 'admin'))
       AND NOT public.is_superadmin(ub.auth_user_id)
       AND NOT EXISTS (
             SELECT 1 FROM public.usuario_perfil_vinculos v
               JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
              WHERE v.usuario_id = ub.id
                AND COALESCE(v.ativo, true) = true
                AND (v.expira_em IS NULL OR v.expira_em > now())
                AND COALESCE(pa.ativo, true) = true
                AND (pa.expira_em IS NULL OR pa.expira_em > now()))
  );

  IF v_qtd = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Todo colaborador ativo tem perfil vinculado.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := v_qtd::text || ' colaborador(es) ativo(s) sem perfil (rodar o backfill de colaboradores).';
    r.detalhe  := jsonb_build_object('sem_perfil', v_qtd);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

DO $qa$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente nesta base; caso PERFIL-014 nao documentado.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; caso PERFIL-014 nao documentado.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado)
  VALUES
  (v_mod, 'PERFIL-014', 'Nenhum colaborador ativo fica sem perfil de acesso',
   'negativo', 'alta', 'aprovado', 'api',
   'LGPD, art. 46',
   'O perfil so protege quem o tem: a trava de escrita e a leitura por perfil valem para o usuario com perfil vinculado, e quem nao tem segue no comportamento legado. Garante que todo colaborador ativo (sem papel de dono, manager ou admin) tem perfil vigente, para o cadastro novo (gatilho) e para o backfill dos existentes.',
   'Backfill de colaboradores aplicado.',
   '[{"ordem":1,"acao":"Contar usuarios ativos do tipo colaborador, sem papel de dono, manager ou admin e sem Super Admin, que nao tenham vinculo vigente a perfil ativo","resultado_esperado":"Zero"}]',
   'Nenhum colaborador ativo sem perfil.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PERFIL-014', 'qa_caso_perfil_014', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-014 nao registrada: %', SQLERRM;
END $qa$;
