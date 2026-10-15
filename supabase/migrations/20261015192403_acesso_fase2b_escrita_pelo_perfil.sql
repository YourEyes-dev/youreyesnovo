-- ============================================================================
-- Acesso — Fase 2b: o PERFIL também manda na ESCRITA (primeira fatia)
--
-- Até aqui a camada de perfil só filtrava LEITURA (políticas RESTRICTIVE de
-- SELECT). A gravação seguia pelas políticas PERMISSIVE antigas — e em muitas
-- tabelas elas dizem "qualquer membro do cliente" (ou "Managers+" mais uma
-- política de vínculo que, para usuário interno, devolve sempre verdadeiro).
-- Resultado: um perfil só de leitura, ou o Colaborador (padrão), ainda
-- conseguia gravar direto pela API.
--
-- Só política RESTRICTIVE por comando estreita escrita (somar outra permissiva
-- não estreita nada). Esta migration cria:
--
--  1) perfil_escreve(tenant, módulos, verbos, cpf): a decisão de escrita.
--       • Super Admin e dono (owner) do cliente passam;
--       • cadastro que não está 'ativo' não grava;
--       • SEM perfil vinculado: não muda nada (as políticas antigas decidem) —
--         é a mesma regra da Fase 1a, ninguém é trancado pra fora;
--       • COM perfil: precisa de um dos verbos no módulo com escopo amplo
--         (nem próprio, nem subordinados), ou de uma liberação pontual; e, para
--         módulos com recorte por subordinados, o verbo com escopo
--         'subordinados_diretos' vale só para a linha de um subordinado direto.
--     'administrar' vale por todos os verbos (como em perfil_permite_acao).
--  2) Políticas RESTRICTIVE de INSERT/UPDATE/DELETE em 12 tabelas em que SÓ a
--     gestão escreve pelo cliente (mapeadas no código): férias, espelho de
--     ponto e psicossocial. INSERT exige 'criar'; UPDATE 'editar' ou 'aprovar';
--     DELETE 'excluir'.
--  3) Endurecimento de 5 tabelas que NINGUÉM grava pelo cliente (escrevem
--     RPC/gatilho SECURITY DEFINER ou função de borda): a escrita direta passa
--     a ser só do Super Admin e do dono.
--  4) perfil_permite_acao alinhada às regras da Fase 1a/2a (perfil manda, dono
--     estrito). Nenhuma política a usa ainda; fica correta para quando usar.
--
-- FICAM DE FORA, de propósito (acoplamento ou autosserviço — ver QA/handoff):
-- documentos, documento_pastas, atestados, alertas_saude, epi_entregas,
-- ponto_marcacoes, ouvidoria, folha_*, beneficios_colaboradores,
-- ferias_solicitacoes, admissao_documentos e o mapa comportamental.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1) A decisão de escrita ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.perfil_escreve(
  p_tenant_id uuid,
  p_modulos   text[],
  p_acoes     text[],
  p_cpf       text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
  v_empresa uuid;
  v_tem_perfil boolean;
  v_cpf text := regexp_replace(COALESCE(p_cpf, ''), '[^0-9]', '', 'g');
BEGIN
  IF v_uid IS NULL OR p_tenant_id IS NULL THEN
    RETURN false;
  END IF;

  IF public.is_superadmin(v_uid) THEN
    RETURN true;
  END IF;
  IF public.ye_eh_dono(v_uid, p_tenant_id) THEN
    RETURN true;
  END IF;

  v_status := (SELECT ub.status::text FROM public.usuarios_base ub
                WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
                LIMIT 1);
  IF v_status IS NOT NULL AND v_status <> 'ativo' THEN
    RETURN false;
  END IF;

  v_empresa := public.empresa_ativa();

  v_tem_perfil := EXISTS (
    SELECT 1
      FROM public.usuarios_base ub
      JOIN public.usuario_perfil_vinculos v
        ON v.usuario_id = ub.id AND v.tenant_id = ub.tenant_id
       AND COALESCE(v.ativo, true) = true
       AND (v.expira_em IS NULL OR v.expira_em > now())
       AND (v_empresa IS NULL OR v.empresa_id IS NULL OR v.empresa_id = v_empresa)
      JOIN public.perfis_acesso pa
        ON pa.id = v.perfil_id
       AND COALESCE(pa.ativo, true) = true
       AND (pa.expira_em IS NULL OR pa.expira_em > now())
     WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
  );

  -- Sem perfil vinculado: as políticas antigas decidem (legado, sem regressão).
  IF NOT v_tem_perfil THEN
    RETURN true;
  END IF;

  IF v_empresa IS NULL AND public.empresa_ativa_obrigatoria() THEN
    RETURN false;
  END IF;

  -- Escopo amplo (nem próprio, nem subordinados) com o verbo no módulo.
  IF EXISTS (
    SELECT 1
      FROM public.usuarios_base ub
      JOIN public.usuario_perfil_vinculos v
        ON v.usuario_id = ub.id AND v.tenant_id = ub.tenant_id
       AND COALESCE(v.ativo, true) = true
       AND (v.expira_em IS NULL OR v.expira_em > now())
       AND (v_empresa IS NULL OR v.empresa_id IS NULL OR v.empresa_id = v_empresa)
      JOIN public.perfis_acesso pa
        ON pa.id = v.perfil_id
       AND COALESCE(pa.ativo, true) = true
       AND (pa.expira_em IS NULL OR pa.expira_em > now())
      JOIN public.perfil_permissoes pp
        ON pp.perfil_id = v.perfil_id
       AND COALESCE(pp.ativo, true) = true
       AND pp.modulo = ANY (p_modulos)
       AND (pp.acao::text = ANY (p_acoes) OR pp.acao::text = 'administrar')
       AND COALESCE(pp.escopo::text, '') NOT IN ('proprio_usuario', 'subordinados_diretos')
     WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
  ) THEN
    RETURN true;
  END IF;

  -- Liberação pontual (exceção adicional) com o verbo, escopo amplo.
  IF EXISTS (
    SELECT 1
      FROM public.usuarios_base ub
      JOIN public.perfil_excecoes pe
        ON pe.usuario_id = ub.id AND pe.tenant_id = ub.tenant_id
       AND COALESCE(pe.ativo, true) = true
       AND COALESCE(pe.tipo, 'adicional') = 'adicional'
       AND (pe.expira_em IS NULL OR pe.expira_em > now())
       AND pe.modulo = ANY (p_modulos)
       AND COALESCE(pe.acao::text, 'administrar') = ANY (p_acoes || ARRAY['administrar'])
       AND COALESCE(pe.escopo::text, '') NOT IN ('proprio_usuario', 'subordinados_diretos')
       AND (v_empresa IS NULL OR pe.empresa_id IS NULL OR pe.empresa_id = v_empresa)
     WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
  ) THEN
    RETURN true;
  END IF;

  -- Recorte por subordinados diretos: o verbo vale só para a linha de um
  -- subordinado meu (a linha precisa trazer o CPF).
  IF v_cpf <> ''
     AND EXISTS (
       SELECT 1
         FROM public.usuarios_base ub
         JOIN public.usuario_perfil_vinculos v
           ON v.usuario_id = ub.id AND v.tenant_id = ub.tenant_id
          AND COALESCE(v.ativo, true) = true
          AND (v.expira_em IS NULL OR v.expira_em > now())
          AND (v_empresa IS NULL OR v.empresa_id IS NULL OR v.empresa_id = v_empresa)
         JOIN public.perfis_acesso pa
           ON pa.id = v.perfil_id
          AND COALESCE(pa.ativo, true) = true
          AND (pa.expira_em IS NULL OR pa.expira_em > now())
         JOIN public.perfil_permissoes pp
           ON pp.perfil_id = v.perfil_id
          AND COALESCE(pp.ativo, true) = true
          AND pp.modulo = ANY (p_modulos)
          AND (pp.acao::text = ANY (p_acoes) OR pp.acao::text = 'administrar')
          AND COALESCE(pp.escopo::text, '') = 'subordinados_diretos'
        WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
     )
     AND public.ye_cpf_eh_subordinado_direto(p_tenant_id, v_cpf) THEN
    RETURN true;
  END IF;

  RETURN false;
END $fn$;

REVOKE EXECUTE ON FUNCTION public.perfil_escreve(uuid, text[], text[], text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.perfil_escreve(uuid, text[], text[], text) TO authenticated, service_role;

COMMENT ON FUNCTION public.perfil_escreve(uuid, text[], text[], text) IS
  'Decisão de ESCRITA pelo perfil. Super Admin e dono passam; cadastro inativo não grava; sem perfil vinculado nada muda (políticas antigas decidem); com perfil, exige o verbo no módulo com escopo amplo (ou subordinados direto, para a linha de um subordinado). Administrar vale por todos os verbos.';

-- ── 2) Políticas RESTRICTIVE de escrita: 12 tabelas só de gestão ────────────
DO $w$
DECLARE
  r record;
  v_cpf text;
  v_mods text;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('ferias_periodos_aquisitivos',     ARRAY['ferias', 'colaboradores'],                    true),
      ('ferias_programacao',              ARRAY['ferias', 'colaboradores'],                    true),
      ('ferias_assinatura_links',         ARRAY['ferias', 'colaboradores'],                    true),
      ('folha_ferias_calculo',            ARRAY['ferias', 'colaboradores'],                    true),
      ('ferias_vinculo_familiar',         ARRAY['ferias', 'colaboradores'],                    false),
      ('ferias_coletivas',                ARRAY['ferias'],                                     false),
      ('ferias_coletivas_comunicados',    ARRAY['ferias'],                                     false),
      ('ponto_espelhos',                  ARRAY['ponto', 'colaboradores'],                     true),
      ('ponto_diario',                    ARRAY['ponto', 'analise_jornada', 'colaboradores'],  false),
      ('psicossocial_participacoes',      ARRAY['psicossocial'],                               false),
      ('questionario_psicossocial_convites', ARRAY['psicossocial'],                            false),
      ('psicossocial_entrevistas',        ARRAY['psicossocial'],                               false)
    ) AS t(tabela, modulos, usa_subordinados)
  LOOP
    BEGIN
      IF to_regclass('public.' || r.tabela) IS NULL THEN
        RAISE NOTICE 'Escrita por perfil: tabela % nao existe; pulada.', r.tabela;
        CONTINUE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = r.tabela
                        AND column_name = 'tenant_id') THEN
        RAISE NOTICE 'Escrita por perfil: % sem tenant_id; pulada.', r.tabela;
        CONTINUE;
      END IF;

      v_cpf := CASE WHEN r.usa_subordinados
                     AND EXISTS (SELECT 1 FROM information_schema.columns
                                  WHERE table_schema = 'public' AND table_name = r.tabela
                                    AND column_name = 'colaborador_cpf')
                    THEN 'colaborador_cpf' ELSE 'NULL::text' END;
      v_mods := quote_literal(r.modulos::text);

      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                     'perfil_restringe_escrita_' || r.tabela || '_ins', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                     'perfil_restringe_escrita_' || r.tabela || '_upd', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                     'perfil_restringe_escrita_' || r.tabela || '_del', r.tabela);

      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated '
        || 'WITH CHECK (public.perfil_escreve(tenant_id, %s::text[], ARRAY[''criar'']::text[], %s))',
        'perfil_restringe_escrita_' || r.tabela || '_ins', r.tabela, v_mods, v_cpf);

      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated '
        || 'USING (public.perfil_escreve(tenant_id, %s::text[], ARRAY[''editar'', ''aprovar'']::text[], %s)) '
        || 'WITH CHECK (public.perfil_escreve(tenant_id, %s::text[], ARRAY[''editar'', ''aprovar'']::text[], %s))',
        'perfil_restringe_escrita_' || r.tabela || '_upd', r.tabela, v_mods, v_cpf, v_mods, v_cpf);

      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR DELETE TO authenticated '
        || 'USING (public.perfil_escreve(tenant_id, %s::text[], ARRAY[''excluir'']::text[], %s))',
        'perfil_restringe_escrita_' || r.tabela || '_del', r.tabela, v_mods, v_cpf);

      RAISE NOTICE 'Escrita por perfil aplicada em %.', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % ficou sem a trava de escrita por perfil: %', r.tabela, SQLERRM;
    END;
  END LOOP;
END $w$;

-- ── 3) Endurecimento: tabelas que ninguém grava pelo cliente ────────────────
-- Quem escreve nelas é RPC/gatilho SECURITY DEFINER ou função de borda (service
-- role), que não passam pela RLS. A escrita direta pelo cliente deixa de ser
-- "qualquer membro" e passa a ser só Super Admin e dono.
DO $h$
DECLARE
  v_tab text;
BEGIN
  FOREACH v_tab IN ARRAY ARRAY[
    'afastamentos_saude', 'psicossocial_entrevistas_evidencias', 'psicossocial_alertas',
    'ferias_alertas', 'ferias_historico'
  ] LOOP
    BEGIN
      IF to_regclass('public.' || v_tab) IS NULL THEN
        RAISE NOTICE 'Endurecimento: tabela % nao existe; pulada.', v_tab;
        CONTINUE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = v_tab
                        AND column_name = 'tenant_id') THEN
        RAISE NOTICE 'Endurecimento: % sem tenant_id; pulada.', v_tab;
        CONTINUE;
      END IF;

      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'escrita_so_dono_' || v_tab || '_ins', v_tab);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'escrita_so_dono_' || v_tab || '_upd', v_tab);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'escrita_so_dono_' || v_tab || '_del', v_tab);

      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated '
        || 'WITH CHECK (public.is_superadmin(auth.uid()) OR public.ye_eh_dono(auth.uid(), tenant_id))',
        'escrita_so_dono_' || v_tab || '_ins', v_tab);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated '
        || 'USING (public.is_superadmin(auth.uid()) OR public.ye_eh_dono(auth.uid(), tenant_id)) '
        || 'WITH CHECK (public.is_superadmin(auth.uid()) OR public.ye_eh_dono(auth.uid(), tenant_id))',
        'escrita_so_dono_' || v_tab || '_upd', v_tab);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR DELETE TO authenticated '
        || 'USING (public.is_superadmin(auth.uid()) OR public.ye_eh_dono(auth.uid(), tenant_id))',
        'escrita_so_dono_' || v_tab || '_del', v_tab);

      RAISE NOTICE 'Escrita direta fechada (so Super Admin e dono) em %.', v_tab;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % nao foi endurecida: %', v_tab, SQLERRM;
    END;
  END LOOP;
END $h$;

-- ── 4) perfil_permite_acao alinhada à Fase 1a/2a ────────────────────────────
CREATE OR REPLACE FUNCTION public.perfil_permite_acao(
  p_tenant_id uuid,
  p_modulo    text,
  p_acao      text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
  v_empresa uuid;
  v_tem_perfil boolean;
BEGIN
  IF v_uid IS NULL OR p_tenant_id IS NULL OR p_modulo IS NULL OR p_acao IS NULL THEN
    RETURN false;
  END IF;

  IF public.is_superadmin(v_uid) THEN
    RETURN true;
  END IF;
  IF public.ye_eh_dono(v_uid, p_tenant_id) THEN
    RETURN true;
  END IF;

  v_status := (SELECT ub.status::text FROM public.usuarios_base ub
                WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
                LIMIT 1);

  IF v_status IS NULL THEN
    RETURN public.has_minimum_role(v_uid, 'manager'::public.app_role)
       AND EXISTS (SELECT 1 FROM public.profiles pr
                    WHERE pr.user_id = v_uid AND pr.tenant_id = p_tenant_id);
  END IF;

  IF v_status <> 'ativo' THEN
    RETURN false;
  END IF;

  v_empresa := public.empresa_ativa();

  v_tem_perfil := EXISTS (
    SELECT 1
      FROM public.usuarios_base ub
      JOIN public.usuario_perfil_vinculos v
        ON v.usuario_id = ub.id AND v.tenant_id = ub.tenant_id
       AND COALESCE(v.ativo, true) = true
       AND (v.expira_em IS NULL OR v.expira_em > now())
       AND (v_empresa IS NULL OR v.empresa_id IS NULL OR v.empresa_id = v_empresa)
      JOIN public.perfis_acesso pa
        ON pa.id = v.perfil_id
       AND COALESCE(pa.ativo, true) = true
       AND (pa.expira_em IS NULL OR pa.expira_em > now())
     WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
  );

  IF NOT v_tem_perfil THEN
    IF public.has_minimum_role(v_uid, 'manager'::public.app_role) THEN
      RETURN true;
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.usuarios_base ub
       WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
         AND ub.tipo_usuario::text IN ('administrador', 'gestor')
    ) THEN
      RETURN true;
    END IF;
  END IF;

  IF v_empresa IS NULL AND public.empresa_ativa_obrigatoria() THEN
    RETURN false;
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.usuarios_base ub
      JOIN public.usuario_perfil_vinculos v
        ON v.usuario_id = ub.id AND v.tenant_id = ub.tenant_id
       AND COALESCE(v.ativo, true) = true
       AND (v.expira_em IS NULL OR v.expira_em > now())
       AND (v_empresa IS NULL OR v.empresa_id IS NULL OR v.empresa_id = v_empresa)
      JOIN public.perfis_acesso pa
        ON pa.id = v.perfil_id
       AND COALESCE(pa.ativo, true) = true
       AND (pa.expira_em IS NULL OR pa.expira_em > now())
      JOIN public.perfil_permissoes pp
        ON pp.perfil_id = v.perfil_id
       AND COALESCE(pp.ativo, true) = true
       AND pp.modulo = p_modulo
       AND pp.acao::text IN (p_acao, 'administrar')
       AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario'
     WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
  ) THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1
      FROM public.usuarios_base ub
      JOIN public.perfil_excecoes pe
        ON pe.usuario_id = ub.id AND pe.tenant_id = ub.tenant_id
       AND COALESCE(pe.ativo, true) = true
       AND COALESCE(pe.tipo, 'adicional') = 'adicional'
       AND (pe.expira_em IS NULL OR pe.expira_em > now())
       AND pe.modulo = p_modulo
       AND COALESCE(pe.acao::text, 'administrar') IN (p_acao, 'administrar')
       AND COALESCE(pe.escopo::text, '') <> 'proprio_usuario'
       AND (v_empresa IS NULL OR pe.empresa_id IS NULL OR pe.empresa_id = v_empresa)
     WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
  );
END $fn$;

-- ── 5) QA: PERFIL-012 (estrutura) e PERFIL-013 (efeito) ────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_012()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_tab text;
  v_cmd text;
  v_oid oid;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): travas de escrita por perfil — decisão, 12 tabelas de gestão e 5 endurecidas';
  r.esperado    := 'perfil_escreve SECURITY DEFINER; política RESTRICTIVE de INSERT, UPDATE e DELETE em cada tabela';

  v_oid := to_regprocedure('public.perfil_escreve(uuid,text[],text[],text)');
  IF v_oid IS NULL THEN
    v_falhas := v_falhas || 'função perfil_escreve ausente'::text;
  ELSIF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_oid) THEN
    v_falhas := v_falhas || 'perfil_escreve não é SECURITY DEFINER'::text;
  END IF;

  FOREACH v_tab IN ARRAY ARRAY[
    'ferias_periodos_aquisitivos', 'ferias_programacao', 'ferias_assinatura_links',
    'folha_ferias_calculo', 'ferias_vinculo_familiar', 'ferias_coletivas',
    'ferias_coletivas_comunicados', 'ponto_espelhos', 'ponto_diario',
    'psicossocial_participacoes', 'questionario_psicossocial_convites', 'psicossocial_entrevistas'
  ] LOOP
    IF to_regclass('public.' || v_tab) IS NULL THEN
      CONTINUE;
    END IF;
    FOREACH v_cmd IN ARRAY ARRAY['ins', 'upd', 'del'] LOOP
      IF NOT EXISTS (SELECT 1 FROM pg_policies pl
                      WHERE pl.schemaname = 'public' AND pl.tablename = v_tab
                        AND pl.policyname = 'perfil_restringe_escrita_' || v_tab || '_' || v_cmd
                        AND pl.permissive = 'RESTRICTIVE'
                        AND position('perfil_escreve' IN COALESCE(pl.qual, '') || COALESCE(pl.with_check, '')) > 0) THEN
        v_falhas := v_falhas || ('sem a trava de escrita ' || v_cmd || ' em ' || v_tab)::text;
      END IF;
    END LOOP;
  END LOOP;

  FOREACH v_tab IN ARRAY ARRAY[
    'afastamentos_saude', 'psicossocial_entrevistas_evidencias', 'psicossocial_alertas',
    'ferias_alertas', 'ferias_historico'
  ] LOOP
    IF to_regclass('public.' || v_tab) IS NULL THEN
      CONTINUE;
    END IF;
    FOREACH v_cmd IN ARRAY ARRAY['ins', 'upd', 'del'] LOOP
      IF NOT EXISTS (SELECT 1 FROM pg_policies pl
                      WHERE pl.schemaname = 'public' AND pl.tablename = v_tab
                        AND pl.policyname = 'escrita_so_dono_' || v_tab || '_' || v_cmd
                        AND pl.permissive = 'RESTRICTIVE') THEN
        v_falhas := v_falhas || ('escrita direta aberta (' || v_cmd || ') em ' || v_tab)::text;
      END IF;
    END LOOP;
  END LOOP;

  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Decisão de escrita e travas por comando íntegras nas 17 tabelas.';
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

CREATE OR REPLACE FUNCTION public.qa_caso_perfil_013()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  c record;
  v_uid uuid;
  v_tenant uuid;
  v_claims_antes text;
  v_pode_criar boolean;
  v_pode_excluir boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'FUNCIONAL (somente leitura): usuário só com o Colaborador (padrão) tenta escrever em férias e ponto';
  r.esperado    := 'perfil_escreve = false para criar e excluir em férias e ponto';

  FOR c IN
    SELECT ub.auth_user_id, ub.tenant_id
      FROM public.usuarios_base ub
     WHERE ub.auth_user_id IS NOT NULL
       AND COALESCE(ub.status::text, 'ativo') = 'ativo'
       AND EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                     JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
                    WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true
                      AND pa.nome = 'Colaborador (padrão)')
       AND NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                         JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
                        WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true
                          AND (v.expira_em IS NULL OR v.expira_em > now())
                          AND pa.nome <> 'Colaborador (padrão)')
       AND NOT EXISTS (SELECT 1 FROM public.perfil_excecoes pe
                        WHERE pe.usuario_id = ub.id AND COALESCE(pe.ativo, true) = true)
       AND NOT EXISTS (SELECT 1 FROM public.user_roles ur
                        WHERE ur.user_id = ub.auth_user_id AND ur.role::text = 'owner')
     LIMIT 25
  LOOP
    IF NOT public.is_superadmin(c.auth_user_id) THEN
      v_uid := c.auth_user_id;
      v_tenant := c.tenant_id;
      EXIT;
    END IF;
  END LOOP;

  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Nenhum usuário só com o Colaborador (padrão). Crie um usuário de tipo colaborador, sem perfil escolhido.';
    RETURN r;
  END IF;

  v_claims_antes := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  BEGIN
    v_pode_criar   := public.perfil_escreve(v_tenant, ARRAY['ferias', 'colaboradores', 'ponto'],
                                            ARRAY['criar'], NULL);
    v_pode_excluir := public.perfil_escreve(v_tenant, ARRAY['ferias', 'colaboradores', 'ponto'],
                                            ARRAY['excluir'], NULL);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);
    RAISE;
  END;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);

  IF v_pode_criar IS FALSE AND v_pode_excluir IS FALSE THEN
    r.situacao := 'passou';
    r.obtido   := 'Usuário só com o Colaborador (padrão) não pode criar nem excluir em férias e ponto.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := 'Usuário só com o Colaborador (padrão) obteve escrita: criar=' || COALESCE(v_pode_criar::text, 'nulo')
               || ', excluir=' || COALESCE(v_pode_excluir::text, 'nulo') || '.';
    r.detalhe  := jsonb_build_object('criar', v_pode_criar, 'excluir', v_pode_excluir);
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
    RAISE NOTICE 'Motor de QA ausente nesta base; casos PERFIL-012/013 nao documentados.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; casos PERFIL-012/013 nao documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado)
  VALUES
  (v_mod, 'PERFIL-012', 'Travas de escrita por perfil presentes nas tabelas de gestão e endurecidas',
   'feliz', 'critica', 'aprovado', 'api',
   'LGPD, art. 46 (medidas de segurança)',
   'A camada de perfil só filtrava leitura; a escrita seguia em "qualquer membro". Garante a função de decisão (SECURITY DEFINER) e uma política RESTRICTIVE por comando (INSERT, UPDATE, DELETE) nas 12 tabelas em que só a gestão escreve e nas 5 que ninguém grava pelo cliente.',
   'Fase 2b aplicada.',
   '[{"ordem":1,"acao":"Varrer o catálogo: função perfil_escreve e as políticas perfil_restringe_escrita_* e escrita_so_dono_* por comando","resultado_esperado":"Todas presentes e RESTRICTIVE"}]',
   'Travas de escrita íntegras nas 17 tabelas.'),

  (v_mod, 'PERFIL-013', 'Usuário só com o Colaborador (padrão) não escreve em férias nem em ponto',
   'negativo', 'critica', 'aprovado', 'api',
   'LGPD, art. 46',
   'Prova o efeito: quem só tem o perfil de autosserviço (tudo em escopo próprio) não pode criar nem excluir registros de férias e ponto, mesmo sendo membro do cliente (que era o suficiente para gravar pela API).',
   'Usuário de teste do tipo colaborador, sem perfil escolhido.',
   '[{"ordem":1,"acao":"Simular o usuário e chamar perfil_escreve para criar e excluir em férias, colaboradores e ponto","resultado_esperado":"Falso nas duas"}]',
   'Sem escrita para o perfil de autosserviço.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PERFIL-012', 'qa_caso_perfil_012', true),
      ('PERFIL-013', 'qa_caso_perfil_013', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-012/013 nao registrada: %', SQLERRM;
END $qa$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). As rotinas ficam registradas e entram na proxima execucao agendada.', SQLERRM;
END $roda$;
