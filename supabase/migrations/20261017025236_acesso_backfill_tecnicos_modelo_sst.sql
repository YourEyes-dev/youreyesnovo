-- Acesso: backfill dos TECNICOS DE SEGURANCA que ja existem (modelo de SST)
--
-- Contexto: a correcao do cadastro novo (perfil_modelo_para_tipo) so vale para usuarios
-- criados dali em diante. Tecnicos de seguranca criados antes nasceram com o
-- "Colaborador (padrao)" (so os proprios dados) ou ficaram sem perfil. Este backfill
-- leva esses tecnicos ao modelo "Tecnico de Seguranca (padrao)", como a Fase 2a fez
-- com a gestao.
--
-- Quem recebe: usuario ATIVO, com login, do tipo tecnico_seguranca, sem papel de dono,
-- manager ou admin, que nao seja Super Admin e que NAO tenha perfil escolhido pelo RH
-- (vinculo vigente a um perfil que nao seja de sistema). Quem tem perfil escolhido: o
-- perfil manda, nao se mexe. Outros tipos (inclusive rh) ficam de fora.
--
-- O que faz: guarda os vinculos dos alvos em backup_vinculos_tecnicos_20261017 (RLS ligada,
-- fechada para a API), desativa os vinculos ativos sem empresa deles (o automatico) e
-- vincula o modelo como perfil principal. Cada vinculo novo leva a marca "Sistema
-- (Backfill tecnicos)". Idempotente.
DO $bt$
DECLARE
  v_ids uuid[];
  v_modelo uuid;
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
       AND ub.tipo_usuario::text = 'tecnico_seguranca'
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
                AND (pa.expira_em IS NULL OR pa.expira_em > now())
                AND COALESCE(pa.tipo::text, '') <> 'padrao_sistema')
       AND NOT EXISTS (
             SELECT 1 FROM public.usuario_perfil_vinculos v
               JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
              WHERE v.usuario_id = ub.id
                AND COALESCE(v.ativo, true) = true
                AND pa.nome = 'Técnico de Segurança (padrão)')
  );

  IF COALESCE(array_length(v_ids, 1), 0) = 0 THEN
    RAISE NOTICE 'Backfill tecnicos: nenhum tecnico para corrigir.';
    RETURN;
  END IF;

  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS public.backup_vinculos_tecnicos_20261017 AS '
       || 'SELECT * FROM public.usuario_perfil_vinculos WHERE usuario_id = ANY ('
       || quote_literal(v_ids::text) || '::uuid[])';
  EXECUTE 'ALTER ' || 'TABLE public.backup_vinculos_tecnicos_20261017 ENABLE ROW LEVEL SECURITY';
  EXECUTE 'REVOKE ALL ON public.backup_vinculos_tecnicos_20261017 FROM PUBLIC, anon, authenticated';
  -- reexecucao: acrescenta a copia dos alvos novos (a tabela ja existe e o CREATE acima nao refaz)
  EXECUTE 'INSERT INTO public.backup_vinculos_tecnicos_20261017 SELECT x.* FROM public.usuario_perfil_vinculos x '
       || 'WHERE x.usuario_id = ANY (' || quote_literal(v_ids::text) || '::uuid[]) '
       || 'AND NOT EXISTS (SELECT 1 FROM public.backup_vinculos_tecnicos_20261017 b WHERE b.id = x.id)';

  FOR r IN
    SELECT ub.id AS usuario_id, ub.tenant_id
      FROM public.usuarios_base ub
     WHERE ub.id = ANY (v_ids)
  LOOP
    BEGIN
      v_modelo := public.perfil_modelo_tecnico_sst(r.tenant_id);
      IF v_modelo IS NULL THEN
        CONTINUE;
      END IF;

      -- Desativa os vinculos ativos "sem empresa" do usuario (o automatico "Colaborador
      -- (padrao)", mesmo que o nome do perfil seja outro, e vinculos a perfil expirado ou
      -- desativado): o indice usuario_perfil_vinculos_ativo_uidx permite UM vinculo ativo por
      -- usuario e empresa, e o modelo entra sem empresa. Ninguem aqui tem perfil escolhido
      -- vigente (os alvos foram filtrados), entao nada que valia e desligado.
      UPDATE public.usuario_perfil_vinculos v
         SET ativo = false,
             is_perfil_principal = false,
             observacao = COALESCE(v.observacao, '')
               || ' [desativado no backfill de tecnicos: passa ao modelo de SST em '
               || to_char(now(), 'DD/MM/YYYY') || ']'
       WHERE v.usuario_id = r.usuario_id
         AND COALESCE(v.ativo, true) = true
         AND v.empresa_id IS NULL
         AND v.perfil_id <> v_modelo;

      INSERT INTO public.usuario_perfil_vinculos
        (tenant_id, usuario_id, perfil_id, ativo, is_perfil_principal,
         atribuido_por_nome, observacao)
      SELECT r.tenant_id, r.usuario_id, v_modelo, true, true,
             'Sistema (Backfill tecnicos)',
             'Backfill 17/10/2026: tecnico de seguranca sem perfil escolhido recebe o modelo de SST.'
       WHERE NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos x
                          WHERE x.usuario_id = r.usuario_id AND x.perfil_id = v_modelo);

      UPDATE public.usuario_perfil_vinculos x
         SET ativo = true, is_perfil_principal = true
       WHERE x.usuario_id = r.usuario_id AND x.perfil_id = v_modelo;

      v_total := v_total + 1;
    EXCEPTION WHEN OTHERS THEN
      v_erros := v_erros + 1;
      RAISE NOTICE 'Backfill tecnicos: usuario % nao processado: % (%)',
        r.usuario_id, SQLERRM, SQLSTATE;
    END;
  END LOOP;

  RAISE NOTICE 'Backfill tecnicos: % usuario(s) processado(s), % erro(s).', v_total, v_erros;
END
$bt$;

-- QA PERFIL-016: guarda de regressao. Nenhum tecnico de seguranca ativo (sem papel de
-- dono, manager ou admin e sem perfil escolhido) fica fora do modelo de SST.
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_016()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_qtd bigint;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): tecnicos de seguranca ativos sem perfil escolhido e fora do modelo de SST';
  r.esperado    := 'Todo tecnico de seguranca ativo sem perfil escolhido tem o modelo Técnico de Segurança (padrão)';

  v_qtd := (
    SELECT count(*)
      FROM public.usuarios_base ub
     WHERE ub.auth_user_id IS NOT NULL
       AND ub.tenant_id IS NOT NULL
       AND ub.status::text = 'ativo'
       AND ub.tipo_usuario::text = 'tecnico_seguranca'
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
                AND (pa.expira_em IS NULL OR pa.expira_em > now())
                AND COALESCE(pa.tipo::text, '') <> 'padrao_sistema')
       AND NOT EXISTS (
             SELECT 1 FROM public.usuario_perfil_vinculos v
               JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
              WHERE v.usuario_id = ub.id
                AND COALESCE(v.ativo, true) = true
                AND pa.nome = 'Técnico de Segurança (padrão)')
  );

  IF v_qtd = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Todo técnico de segurança ativo sem perfil escolhido está no modelo de SST.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := v_qtd::text || ' técnico(s) de segurança ativo(s) fora do modelo de SST (rodar o backfill de técnicos).';
    r.detalhe  := jsonb_build_object('fora_do_modelo', v_qtd);
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
    RAISE NOTICE 'Motor de QA ausente nesta base; caso PERFIL-016 nao documentado.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; caso PERFIL-016 nao documentado.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado)
  VALUES
  (v_mod, 'PERFIL-016', 'Nenhum técnico de segurança ativo fica fora do modelo de SST',
   'negativo', 'alta', 'aprovado', 'api',
   'LGPD, art. 46',
   'Técnicos de segurança criados antes da correção do cadastro nasceram com o Colaborador (padrão) e ficaram sem tela de trabalho. Garante que todo técnico ativo sem perfil escolhido (e sem papel de dono, manager ou admin) tem o modelo Técnico de Segurança (padrão), para o cadastro novo e para o backfill dos existentes.',
   'Correção do cadastro e backfill de técnicos aplicados.',
   '[{"ordem":1,"acao":"Contar técnicos de segurança ativos, sem papel de dono, manager ou admin, sem perfil escolhido pelo RH e sem o modelo de SST vinculado","resultado_esperado":"Zero"}]',
   'Nenhum técnico fora do modelo de SST.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PERFIL-016', 'qa_caso_perfil_016', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-016 nao registrada: %', SQLERRM;
END $qa$;
