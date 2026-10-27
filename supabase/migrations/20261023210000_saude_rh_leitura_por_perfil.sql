-- ============================================================================
-- SAUDE E RH — LEITURA POR PERFIL (passo 2.2): afastamentos, eSocial, contratos de experiencia, condicoes especiais
--
-- Levantamento de 10/2026: estas tabelas eram legiveis por QUALQUER membro da empresa (so o tenant decidia).
--   afastamentos (+ cat, ntep, fap, esocial, retorno, marcadores, previdenciario, pendencias): quem esta afastado, por que
--     grupo clinico (ex.: saude mental), nexo com o trabalho, CAT, beneficio do INSS.  Dado de saude: LGPD art. 11.
--   esocial_transmissoes: CPF e o XML do evento; os eventos S-1200/S-1210 (ferias, 13o) trazem a remuneracao em claro.
--   esocial_certificados: o certificado digital da empresa.
--   contratos_experiencia (+ historico): CPF e dados do contrato (o salario fica para o passo do salario).
--   colaborador_condicoes_especiais: PCD, gestante e afins.
-- O selo "Afastado" mostrava o MOTIVO (inclusive saude mental) a quem abrisse PDI, feedback, EPI, incidentes etc.
--
-- Regra (RESTRICTIVE, soma-se as politicas antigas da conta):
--   afastamentos / contratos_experiencia   modulo da area em escopo amplo, ou a PROPRIA linha (CPF), ou a do subordinado
--                                          direto (escopo de subordinados). Sem perfil vinculado vale o legado por papel.
--   filhas de afastamentos                 clinicas (cat, ntep, fap, esocial, retorno, marcadores): Atestados ou SST amplo,
--                                          ou o proprio afastamento. Previdenciario: + Financeiro (o 13o conta os avos pelo
--                                          INSS). Pendencias: Atestados, SST ou Colaboradores.
--   esocial_transmissoes                   Financeiro, Incidentes, SST ou Configuracoes; os eventos com remuneracao exigem
--                                          tambem "pode ver salario" do perfil.
--   esocial_certificados                   le: Configuracoes, Incidentes, SST ou Financeiro; grava: Configuracoes + verbo.
--   condicoes especiais                    Colaboradores, Atestados ou SST amplo, ou a propria.
-- O selo "Afastado" passa a usar a funcao afastamentos_ativos_resumo(): devolve quem esta afastado e as datas a quem tem
-- modulo de pessoas, e o MOTIVO so a quem tem Atestados ou SST amplo.
--
-- Dependencias conferidas: as rotinas que leem estas tabelas por dentro do banco sao security definer, exceto o calculo dos
-- avos do 13o (Financeiro), a cobertura de escala (Ponto) e os gatilhos de pendencia (Atestados) — cobertos pelos modulos acima.
-- Nao altera dado. Idempotente. Atomico por tabela.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1) Selo "Afastado" sem motivo para quem nao e da saude ───────────────────
CREATE OR REPLACE FUNCTION public.afastamentos_ativos_resumo()
RETURNS TABLE (
  colaborador_nome text, colaborador_cpf text, colaborador_id text, status text,
  data_inicio date, data_fim date, motivo_principal text
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant uuid := public.get_user_tenant_id();
  v_motivo boolean;
BEGIN
  IF v_tenant IS NULL OR auth.uid() IS NULL THEN
    RETURN;
  END IF;
  IF NOT public.perfil_permite_modulo(v_tenant, 'colaboradores', 'pdi', 'feedback', 'epi', 'incidentes',
                                      'analise_jornada', 'ferias', 'atestados', 'sst', 'ponto', 'psicossocial', 'financeiro') THEN
    RETURN;
  END IF;
  v_motivo := public.perfil_amplo_sem_subordinados(v_tenant, 'atestados', 'sst');
  RETURN QUERY
    SELECT af.colaborador_nome::text, af.colaborador_cpf::text, af.colaborador_id::text, af.status::text,
           af.data_inicio, af.data_fim,
           CASE WHEN v_motivo THEN af.motivo_principal::text ELSE NULL END
      FROM public.afastamentos af
     WHERE af.tenant_id = v_tenant
       AND af.status::text IN ('ativo', 'beneficio_inss');
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.afastamentos_ativos_resumo() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.afastamentos_ativos_resumo() TO authenticated, service_role;

-- ── 2) Politicas de leitura ──────────────────────────────────────────────────
DO $rh$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('afastamentos',
       $p$public.perfil_amplo_sem_subordinados(tenant_id, 'atestados', 'sst', 'colaboradores', 'ferias', 'financeiro', 'psicossocial', 'ponto')
          OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
          OR (public.perfil_tem_escopo_subordinados(tenant_id, 'atestados', 'sst', 'colaboradores', 'ferias', 'financeiro', 'psicossocial', 'ponto')
              AND public.ye_cpf_eh_subordinado_direto(tenant_id, colaborador_cpf))$p$),
      ('contratos_experiencia',
       $p$public.perfil_amplo_sem_subordinados(tenant_id, 'contratos_experiencia', 'admissoes', 'onboarding', 'colaboradores')
          OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
          OR (public.perfil_tem_escopo_subordinados(tenant_id, 'contratos_experiencia', 'admissoes', 'onboarding', 'colaboradores')
              AND public.ye_cpf_eh_subordinado_direto(tenant_id, colaborador_cpf))$p$),
      ('contratos_experiencia_historico',
       $p$EXISTS (SELECT 1 FROM public.contratos_experiencia c WHERE c.id = contrato_id)$p$),
      ('afastamentos_pendencias',
       $p$public.perfil_amplo_sem_subordinados(tenant_id, 'atestados', 'sst', 'colaboradores')$p$),
      ('afastamentos_previdenciario',
       $p$public.perfil_amplo_sem_subordinados(tenant_id, 'atestados', 'sst', 'financeiro')
          OR EXISTS (SELECT 1 FROM public.afastamentos af WHERE af.id = afastamento_id
                      AND regexp_replace(COALESCE(af.colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado())$p$),
      ('colaborador_condicoes_especiais',
       $p$public.perfil_amplo_sem_subordinados(tenant_id, 'colaboradores', 'atestados', 'sst')
          OR regexp_replace(COALESCE(colaborador_id, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
          OR EXISTS (SELECT 1 FROM public.admissoes a WHERE a.id::text = colaborador_id
                      AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado())$p$),
      ('esocial_transmissoes',
       $p$public.perfil_permite_modulo(tenant_id, 'financeiro', 'incidentes', 'sst', 'configuracoes')
          AND (NOT (COALESCE(tipo_evento, '') IN ('S-1200', 'S-1210') OR ferias_calculo_id IS NOT NULL OR COALESCE(origem_modulo, '') = 'decimo_terceiro')
               OR public.pode_ver_salario(tenant_id))$p$),
      ('esocial_certificados',
       $p$public.perfil_permite_modulo(tenant_id, 'configuracoes', 'incidentes', 'sst', 'financeiro')$p$)
    ) AS t(tabela, predicado)
  LOOP
    BEGIN
      IF to_regclass('public.' || r.tabela) IS NULL THEN
        RAISE NOTICE 'Saude/RH: tabela % nao existe; pulada.', r.tabela;
        CONTINUE;
      END IF;
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_leitura_' || r.tabela, r.tabela);
      EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated USING (%s)',
                     'perfil_restringe_leitura_' || r.tabela, r.tabela, r.predicado);
      RAISE NOTICE 'Saude/RH: leitura por perfil aplicada em %.', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % ficou SEM a trava de leitura: %', r.tabela, SQLERRM;
    END;
  END LOOP;

  -- filhas clinicas de afastamentos: Atestados ou SST amplo, ou o proprio afastamento
  FOR r IN
    SELECT unnest(ARRAY['afastamentos_cat', 'afastamentos_ntep', 'afastamentos_fap', 'afastamentos_esocial',
                        'afastamentos_retorno', 'afastamentos_marcadores']) AS tabela
  LOOP
    BEGIN
      IF to_regclass('public.' || r.tabela) IS NULL THEN
        RAISE NOTICE 'Saude/RH: tabela % nao existe; pulada.', r.tabela;
        CONTINUE;
      END IF;
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_leitura_' || r.tabela, r.tabela);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated USING ('
        || 'public.perfil_amplo_sem_subordinados(tenant_id, ''atestados'', ''sst'') '
        || 'OR EXISTS (SELECT 1 FROM public.afastamentos af WHERE af.id = afastamento_id '
        || 'AND regexp_replace(COALESCE(af.colaborador_cpf, ''''), ''[^0-9]'', '''', ''g'') = public.cpf_do_usuario_logado()))',
        'perfil_restringe_leitura_' || r.tabela, r.tabela);
      RAISE NOTICE 'Saude/RH: leitura por perfil aplicada em %.', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % ficou SEM a trava de leitura: %', r.tabela, SQLERRM;
    END;
  END LOOP;
END $rh$;

-- ── 3) Certificado digital: quem grava ──────────────────────────────────────
-- A politica antiga se chama "tenant_admins" mas so conferia a empresa: qualquer membro podia trocar ou apagar o
-- certificado digital da empresa. Passa a exigir Configuracoes com o verbo.
DO $cert$
BEGIN
  IF to_regclass('public.esocial_certificados') IS NULL THEN
    RAISE NOTICE 'esocial_certificados ausente; escrita nao alterada.';
    RETURN;
  END IF;
  DROP POLICY IF EXISTS perfil_restringe_escrita_esocial_certificados_ins ON public.esocial_certificados;
  DROP POLICY IF EXISTS perfil_restringe_escrita_esocial_certificados_upd ON public.esocial_certificados;
  DROP POLICY IF EXISTS perfil_restringe_escrita_esocial_certificados_del ON public.esocial_certificados;
  CREATE POLICY perfil_restringe_escrita_esocial_certificados_ins ON public.esocial_certificados
    AS RESTRICTIVE FOR INSERT TO authenticated
    WITH CHECK (public.perfil_permite_modulo(tenant_id, 'configuracoes')
                AND public.perfil_escreve(tenant_id, ARRAY['configuracoes']::text[], ARRAY['criar']::text[], NULL));
  CREATE POLICY perfil_restringe_escrita_esocial_certificados_upd ON public.esocial_certificados
    AS RESTRICTIVE FOR UPDATE TO authenticated
    USING (public.perfil_permite_modulo(tenant_id, 'configuracoes')
           AND public.perfil_escreve(tenant_id, ARRAY['configuracoes']::text[], ARRAY['editar','aprovar']::text[], NULL))
    WITH CHECK (public.perfil_permite_modulo(tenant_id, 'configuracoes')
                AND public.perfil_escreve(tenant_id, ARRAY['configuracoes']::text[], ARRAY['editar','aprovar']::text[], NULL));
  CREATE POLICY perfil_restringe_escrita_esocial_certificados_del ON public.esocial_certificados
    AS RESTRICTIVE FOR DELETE TO authenticated
    USING (public.perfil_permite_modulo(tenant_id, 'configuracoes')
           AND public.perfil_escreve(tenant_id, ARRAY['configuracoes']::text[], ARRAY['excluir']::text[], NULL));
  RAISE NOTICE 'esocial_certificados: escrita pelo perfil aplicada.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: esocial_certificados ficou SEM a trava de escrita: %', SQLERRM;
END $cert$;
