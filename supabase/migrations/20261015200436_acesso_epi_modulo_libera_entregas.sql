-- ============================================================================
-- EPI — o módulo "EPIs" passa a bastar para ler e gravar as entregas
--
-- Regra de produto (dono do produto, 10/2026): quem tem acesso ao módulo EPIs e
-- não tem Compliance SST deve ver o EPI normalmente.
--
-- O achado: a rota /epis é liberada só pelo módulo 'epi', mas a política de
-- LEITURA de epi_entregas (EPI-041, 09/2026) consultava apenas 'sst' e
-- 'colaboradores'. Perfil só com EPIs abria a tela e via as entregas VAZIAS, e o
-- assistente de entrega (que grava e lê de volta) falhava. A trava de escrita da
-- Fase 2c espelhou a leitura, então tinha o mesmo desvio.
--
-- Correção: 'epi' entra na lista de módulos da leitura E da escrita de
-- epi_entregas. O resto da política não muda: continua valendo o escopo do perfil
-- (próprio usuário vê só o próprio CPF), o registro do próprio colaborador, e o
-- mesmo recorte de quem não tem perfil. Vale para a biometria da entrega
-- (LGPD art. 11) a mesma regra de antes: só quem tem o módulo com escopo amplo.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1) Leitura: 'epi' passa a liberar as entregas ──────────────────────────
DO $rd$
BEGIN
  IF to_regclass('public.epi_entregas') IS NULL THEN
    RAISE NOTICE 'epi_entregas nao existe nesta base; leitura nao ajustada.';
    RETURN;
  END IF;

  DROP POLICY IF EXISTS perfil_restringe_leitura_epi_entregas ON public.epi_entregas;
  CREATE POLICY perfil_restringe_leitura_epi_entregas
    ON public.epi_entregas AS RESTRICTIVE FOR SELECT
    USING (
      public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['epi'::text, 'sst'::text, 'colaboradores'::text])
      OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
    );
  COMMENT ON POLICY perfil_restringe_leitura_epi_entregas ON public.epi_entregas IS
    'RESTRICTIVE: entrega de EPI (material biometrico) so por perfil com o modulo epi, sst ou colaboradores, ou pelo proprio colaborador — LGPD art. 11. EPI-041; epi incluido em 10/2026 (a rota /epis e liberada pelo modulo epi).';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: leitura de epi_entregas nao ajustada: %', SQLERRM;
END $rd$;

-- ── 2) Escrita: mesmos módulos (DELETE aceita excluir OU criar, como na 2c) ─
DO $wr$
BEGIN
  IF to_regclass('public.epi_entregas') IS NULL
     OR to_regprocedure('public.perfil_escreve(uuid,text[],text[],text)') IS NULL THEN
    RAISE NOTICE 'epi_entregas ou perfil_escreve ausente; escrita nao ajustada.';
    RETURN;
  END IF;

  DROP POLICY IF EXISTS perfil_restringe_escrita_epi_entregas_ins ON public.epi_entregas;
  DROP POLICY IF EXISTS perfil_restringe_escrita_epi_entregas_upd ON public.epi_entregas;
  DROP POLICY IF EXISTS perfil_restringe_escrita_epi_entregas_del ON public.epi_entregas;

  CREATE POLICY perfil_restringe_escrita_epi_entregas_ins
    ON public.epi_entregas AS RESTRICTIVE FOR INSERT TO authenticated
    WITH CHECK (public.perfil_escreve(tenant_id, ARRAY['epi', 'sst', 'colaboradores']::text[],
                                      ARRAY['criar']::text[], NULL::text));
  CREATE POLICY perfil_restringe_escrita_epi_entregas_upd
    ON public.epi_entregas AS RESTRICTIVE FOR UPDATE TO authenticated
    USING (public.perfil_escreve(tenant_id, ARRAY['epi', 'sst', 'colaboradores']::text[],
                                 ARRAY['editar', 'aprovar']::text[], NULL::text))
    WITH CHECK (public.perfil_escreve(tenant_id, ARRAY['epi', 'sst', 'colaboradores']::text[],
                                      ARRAY['editar', 'aprovar']::text[], NULL::text));
  CREATE POLICY perfil_restringe_escrita_epi_entregas_del
    ON public.epi_entregas AS RESTRICTIVE FOR DELETE TO authenticated
    USING (public.perfil_escreve(tenant_id, ARRAY['epi', 'sst', 'colaboradores']::text[],
                                 ARRAY['excluir', 'criar']::text[], NULL::text));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: escrita de epi_entregas nao ajustada: %', SQLERRM;
END $wr$;

-- ── 3) QA: PERFIL-013 passa a testar também o conjunto com 'epi' ────────────
DO $q13$
DECLARE
  v_def text;
  v_novo text;
BEGIN
  IF to_regprocedure('public.qa_caso_perfil_013()') IS NULL THEN
    RAISE NOTICE 'qa_caso_perfil_013 ausente; nao ajustada.';
    RETURN;
  END IF;
  v_def := pg_get_functiondef(to_regprocedure('public.qa_caso_perfil_013()'));
  v_novo := replace(v_def, $a$'sst,colaboradores',$a$, $b$'epi,sst,colaboradores',$b$);
  IF v_novo = v_def THEN
    RAISE NOTICE 'qa_caso_perfil_013 ja cobre o conjunto com epi (ou o trecho nao foi achado).';
  ELSE
    EXECUTE v_novo;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'qa_caso_perfil_013 nao ajustada: %', SQLERRM;
END $q13$;

-- ── 4) QA: EPI-070 — perfil com o módulo EPIs lê e grava as entregas ───────
CREATE OR REPLACE FUNCTION public.qa_caso_epi_070()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  c record;
  v_falhas text[] := ARRAY[]::text[];
  v_uid uuid;
  v_tenant uuid;
  v_claims_antes text;
  v_le boolean;
  v_grava boolean;
  v_funcional text := 'Sem usuário só com o módulo EPIs (sem SST/Colaboradores) para a prova funcional; a estrutura foi conferida.';
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA + FUNCIONAL (somente leitura): perfil só com o módulo EPIs lê e grava as entregas';
  r.esperado    := 'Leitura e escrita de epi_entregas incluem o módulo epi; usuário só com EPIs passa nas duas decisões';

  -- 1) Estrutura
  IF NOT EXISTS (SELECT 1 FROM pg_policies pl
                  WHERE pl.schemaname = 'public' AND pl.tablename = 'epi_entregas'
                    AND pl.policyname = 'perfil_restringe_leitura_epi_entregas'
                    AND pl.permissive = 'RESTRICTIVE'
                    AND position('''epi''' IN COALESCE(pl.qual, '')) > 0) THEN
    v_falhas := v_falhas || 'leitura de epi_entregas não inclui o módulo epi'::text;
  END IF;
  IF to_regprocedure('public.perfil_escreve(uuid,text[],text[],text)') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_policies pl
                    WHERE pl.schemaname = 'public' AND pl.tablename = 'epi_entregas'
                      AND pl.policyname = 'perfil_restringe_escrita_epi_entregas_ins'
                      AND position('''epi''' IN COALESCE(pl.with_check, '')) > 0) THEN
      v_falhas := v_falhas || 'escrita (insert) de epi_entregas não inclui o módulo epi'::text;
    END IF;
  END IF;

  -- 2) Funcional: perfil com 'epi' (amplo, com 'criar') e SEM sst/colaboradores amplos
  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    FOR c IN
      SELECT ub.auth_user_id, ub.tenant_id
        FROM public.usuarios_base ub
       WHERE ub.auth_user_id IS NOT NULL
         AND COALESCE(ub.status::text, 'ativo') = 'ativo'
         AND EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                       JOIN public.perfil_permissoes pp ON pp.perfil_id = v.perfil_id
                        AND COALESCE(pp.ativo, true) = true AND pp.modulo = 'epi'
                        AND pp.acao::text IN ('criar', 'administrar')
                        AND COALESCE(pp.escopo::text, '') NOT IN ('proprio_usuario', 'subordinados_diretos')
                      WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true)
         AND NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                           JOIN public.perfil_permissoes pp ON pp.perfil_id = v.perfil_id
                            AND COALESCE(pp.ativo, true) = true
                            AND pp.modulo IN ('sst', 'colaboradores')
                            AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario'
                          WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true)
         AND NOT EXISTS (SELECT 1 FROM public.perfil_excecoes pe
                          WHERE pe.usuario_id = ub.id AND COALESCE(pe.ativo, true) = true)
         AND NOT EXISTS (SELECT 1 FROM public.user_roles ur
                          WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('owner', 'manager', 'admin'))
         AND COALESCE(ub.tipo_usuario::text, '') NOT IN ('administrador', 'gestor')
       LIMIT 25
    LOOP
      IF NOT public.is_superadmin(c.auth_user_id) THEN
        v_uid := c.auth_user_id;
        v_tenant := c.tenant_id;
        EXIT;
      END IF;
    END LOOP;

    IF v_uid IS NOT NULL THEN
      v_claims_antes := current_setting('request.jwt.claims', true);
      PERFORM set_config('request.jwt.claims',
                         json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
      BEGIN
        v_le := public.perfil_permite_modulo(v_tenant, 'epi', 'sst', 'colaboradores');
        v_grava := CASE WHEN to_regprocedure('public.perfil_escreve(uuid,text[],text[],text)') IS NULL
                        THEN true
                        ELSE public.perfil_escreve(v_tenant, ARRAY['epi', 'sst', 'colaboradores'],
                                                   ARRAY['criar'], NULL) END;
      EXCEPTION WHEN OTHERS THEN
        PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);
        RAISE;
      END;
      PERFORM set_config('request.jwt.claims', COALESCE(v_claims_antes, ''), true);

      IF v_le IS NOT TRUE THEN
        v_falhas := v_falhas || 'usuário só com EPIs não lê as entregas'::text;
      END IF;
      IF v_grava IS NOT TRUE THEN
        v_falhas := v_falhas || 'usuário só com EPIs não grava entregas'::text;
      END IF;
      IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
        v_funcional := 'Prova funcional: usuário só com o módulo EPIs lê e grava as entregas.';
      END IF;
    END IF;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Leitura e escrita de entregas incluem o módulo EPIs. ' || v_funcional;
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

DO $qa$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente nesta base; caso EPI-070 nao documentado.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'saude-ocupacional/epi' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo saude-ocupacional/epi ausente; caso EPI-070 nao documentado.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado)
  VALUES
  (v_mod, 'EPI-070', 'Perfil só com o módulo EPIs vê e registra as entregas, sem precisar de Compliance SST',
   'feliz', 'alta', 'aprovado', 'api',
   'LGPD, art. 11 (dado biométrico) e art. 46',
   'A rota /epis é liberada pelo módulo epi, mas a leitura das entregas consultava só sst e colaboradores: quem tinha apenas EPIs abria a tela e via a lista vazia, e o assistente de entrega (que grava e lê de volta) falhava. Garante que leitura e escrita de epi_entregas incluem o módulo epi, mantendo o recorte do perfil (próprio usuário vê só o próprio CPF).',
   'Fase 2c e correção do módulo EPIs aplicadas.',
   '[{"ordem":1,"acao":"Conferir que a política de leitura e a de insert de epi_entregas citam o módulo epi","resultado_esperado":"Presente nas duas"},
     {"ordem":2,"acao":"Simular um usuário cujo perfil tem EPIs (criar, escopo amplo) e não tem Compliance SST nem Colaboradores, e chamar as decisões de leitura e de escrita","resultado_esperado":"Verdadeiro nas duas"}]',
   'Usuário só com EPIs lê e registra entregas.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('EPI-070', 'qa_caso_epi_070', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao EPI-070 nao registrada: %', SQLERRM;
END $qa$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'saude-ocupacional/epi');
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). As rotinas ficam registradas e entram na proxima execucao agendada.', SQLERRM;
END $roda$;
