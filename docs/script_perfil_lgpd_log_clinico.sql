-- ============================================================================
-- ENTREGA — Camada de perfil (LGPD) e log de acesso ao dado clinico (Fase 2)
--
-- Espelha a migration 20260913160000_fase2_perfil_lgpd_rls_e_log_clinico.sql (no
-- teste), ausente em homologacao e producao (passivo 09/2026).
--
-- DUAS coisas, leia com atencao:
--
-- (A) CRIACAO LIMPA:
--   * tabela log_acesso_clinico (trilha append-only de quem leu CID de quem) +
--     RLS + 2 politicas;
--   * funcao ler_cid_clinico(text, uuid) — cofre do clinico (SECURITY DEFINER):
--     le o CID de atestados/afastamentos_saude/eventos_saude e grava a trilha;
--   * coluna ouvidoria.prazo_apuracao_ate (ADD COLUMN aditivo).
--
-- (B) APERTO DE ACESSO em 4 tabelas SENSIVEIS EXISTENTES — muda quem le, nao a
--     estrutura. Adiciona a politica RESTRICTIVE perfil_restringe_leitura_* em
--     folha_rescisoes (DESL-110), folha_itens (FOLHA-090), epi_entregas (EPI-041)
--     e ouvidoria (SST-041). Depois disso, ler holerite/rescisao/biometria/
--     denuncia passa a exigir PERFIL do modulo OU ser o PROPRIO titular.
--
-- POR QUE E SEGURO (sem trancar ninguem): RESTRICTIVE so ESTREITA; as 4 tabelas
-- JA TEM politica PERMISSIVA de base embaixo (conferido no inventario:
-- isolamento por tenant / "usuarios podem ver..."), entao a RESTRICTIVE narrow
-- sobre uma base que ja concede — nao nega tudo. E o "OU cpf = titular" garante
-- que cada pessoa continua vendo o PROPRIO dado. E a mesma postura que o teste ja
-- roda; folha_rescisoes ja tem essa RESTRICTIVE embaixo (aqui vira no-op).
--
-- SEGURANCA: aditivo — cria tabela/funcao/coluna novas e adiciona politicas;
-- ENABLE RLS e idempotente (as tabelas ja tinham RLS ligada). Nao ALTERA nem
-- APAGA dado. Idempotente (DROP POLICY IF EXISTS + CREATE). Uma transacao.
-- CONFIRA NA HOMOLOGACAO O ACESSO (abaixo) antes da producao — e mudanca de quem
-- le dado sensivel. DDL/politicas literais no topo; a funcao (tag fn) por ultimo.
-- Dependencias presentes embaixo: perfil_permite_modulo, cpf_do_usuario_logado,
-- afastamentos_saude, atestados, eventos_saude, afastamentos.
--
-- CONFERENCIA: rode a query do fim SEPARADA. Esperado: t | t | 1 | 6 | OK
-- ============================================================================

SET lock_timeout = '10s';

-- ═══════════════════════════════════════════════════════════════════════════
-- (A) CRIACAO LIMPA — tabela nova, coluna nova, politicas (DDL literal)
-- ═══════════════════════════════════════════════════════════════════════════

-- AFAST-080 + SST-080: trilha append-only de leitura do CID
CREATE TABLE IF NOT EXISTS public.log_acesso_clinico (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid,
  leitor_id   uuid,
  titular_cpf text,
  origem      text NOT NULL,
  registro_id uuid,
  cid         text,
  acessado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.log_acesso_clinico ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS perfil_restringe_leitura_log_acesso_clinico ON public.log_acesso_clinico;
CREATE POLICY perfil_restringe_leitura_log_acesso_clinico
  ON public.log_acesso_clinico AS RESTRICTIVE FOR SELECT
  USING (public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['sst'::text, 'atestados'::text]));
DROP POLICY IF EXISTS leitura_log_acesso_clinico ON public.log_acesso_clinico;
CREATE POLICY leitura_log_acesso_clinico
  ON public.log_acesso_clinico FOR SELECT USING (true);

-- SST-041: coluna de prazo de apuracao na ouvidoria (ADD COLUMN aditivo)
ALTER TABLE public.ouvidoria ADD COLUMN IF NOT EXISTS prazo_apuracao_ate date;
COMMENT ON COLUMN public.ouvidoria.prazo_apuracao_ate IS
  'Prazo de tratativa/apuracao da denuncia (Lei 14.457/2022). SST-041.';

-- ═══════════════════════════════════════════════════════════════════════════
-- (B) APERTO DE ACESSO — RLS + RESTRICTIVE nas 4 tabelas sensiveis existentes
--     (idempotente; as permissivas de base ja existem embaixo)
-- ═══════════════════════════════════════════════════════════════════════════

-- DESL-110: dossie rescisorio (folha_rescisoes) — ja existente embaixo (no-op)
ALTER TABLE public.folha_rescisoes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS perfil_restringe_leitura_folha_rescisoes ON public.folha_rescisoes;
CREATE POLICY perfil_restringe_leitura_folha_rescisoes
  ON public.folha_rescisoes AS RESTRICTIVE FOR SELECT
  USING (
    public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['financeiro'::text, 'colaboradores'::text])
    OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
  );
COMMENT ON POLICY perfil_restringe_leitura_folha_rescisoes ON public.folha_rescisoes IS
  'RESTRICTIVE: dossie rescisorio so por perfil (financeiro/colaboradores) ou pelo proprio colaborador. DESL-110.';

-- FOLHA-090: itens/holerite (folha_itens)
ALTER TABLE public.folha_itens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS perfil_restringe_leitura_folha_itens ON public.folha_itens;
CREATE POLICY perfil_restringe_leitura_folha_itens
  ON public.folha_itens AS RESTRICTIVE FOR SELECT
  USING (
    public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['financeiro'::text, 'colaboradores'::text])
    OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
  );
COMMENT ON POLICY perfil_restringe_leitura_folha_itens ON public.folha_itens IS
  'RESTRICTIVE: itens/holerite so por perfil (financeiro/colaboradores) ou pelo proprio colaborador. FOLHA-090.';

-- EPI-041: biometria da entrega de EPI (epi_entregas)
ALTER TABLE public.epi_entregas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS perfil_restringe_leitura_epi_entregas ON public.epi_entregas;
CREATE POLICY perfil_restringe_leitura_epi_entregas
  ON public.epi_entregas AS RESTRICTIVE FOR SELECT
  USING (
    public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['sst'::text, 'colaboradores'::text])
    OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
  );
COMMENT ON POLICY perfil_restringe_leitura_epi_entregas ON public.epi_entregas IS
  'RESTRICTIVE: entrega de EPI (material biometrico) so por perfil (sst/colaboradores) ou pelo proprio colaborador — LGPD art. 11. EPI-041.';

-- SST-041: canal de assedio (ouvidoria) — sigilo reforcado
ALTER TABLE public.ouvidoria ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS perfil_restringe_leitura_ouvidoria ON public.ouvidoria;
CREATE POLICY perfil_restringe_leitura_ouvidoria
  ON public.ouvidoria AS RESTRICTIVE FOR SELECT
  USING (
    public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['configuracoes'::text])
    OR autor_id = auth.uid()
    OR responsavel_id = auth.uid()
    OR respondido_por = auth.uid()
  );
COMMENT ON POLICY perfil_restringe_leitura_ouvidoria ON public.ouvidoria IS
  'RESTRICTIVE: denuncia (assedio) so pelo fluxo de apuracao (perfil de configuracoes/compliance, responsavel ou autor) — sigilo reforcado da Lei 14.457. SST-041.';

-- ═══════════════════════════════════════════════════════════════════════════
-- FUNCAO (tag fn) — por ultimo
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ler_cid_clinico(p_origem text, p_registro_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_cid    text;
  v_tenant uuid;
  v_cpf    text;
BEGIN
  IF p_origem = 'afastamento_saude' THEN
    SELECT s.cid_principal, s.tenant_id, a.colaborador_cpf
      INTO v_cid, v_tenant, v_cpf
      FROM public.afastamentos_saude s
      LEFT JOIN public.afastamentos a ON a.id = s.afastamento_id
     WHERE s.id = p_registro_id;
  ELSIF p_origem = 'atestado' THEN
    SELECT cid_codigo, tenant_id, colaborador_cpf
      INTO v_cid, v_tenant, v_cpf
      FROM public.atestados WHERE id = p_registro_id;
  ELSIF p_origem = 'evento_saude' THEN
    SELECT NULL::text, tenant_id, colaborador_cpf
      INTO v_cid, v_tenant, v_cpf
      FROM public.eventos_saude WHERE id = p_registro_id;
  ELSE
    RAISE EXCEPTION 'Origem clinica invalida: %', p_origem;
  END IF;

  INSERT INTO public.log_acesso_clinico (tenant_id, leitor_id, titular_cpf, origem, registro_id, cid)
  VALUES (v_tenant, auth.uid(), v_cpf, p_origem, p_registro_id, v_cid);

  RETURN v_cid;
END;
$fn$;
COMMENT ON FUNCTION public.ler_cid_clinico(text, uuid) IS
  'Le o CID/diagnostico (atestados.cid_codigo, afastamentos_saude.cid_principal, eventos_saude) e grava o log de acesso em log_acesso_clinico — cofre do clinico (AFAST-080/SST-080, LGPD art. 11).';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — rode SEPARADA. Esperado: t | t | 1 | 6 | OK
--   tabela_log | funcao_ler_cid | col_ouvidoria_prazo | politicas_de_6 | erro
-- ---------------------------------------------------------------------------
WITH col AS MATERIALIZED (
  SELECT count(*) AS n FROM information_schema.columns
  WHERE table_schema='public' AND table_name='ouvidoria' AND column_name='prazo_apuracao_ate'
),
pol AS MATERIALIZED (
  SELECT count(*) AS n FROM pg_policies
  WHERE schemaname='public' AND policyname IN (
    'perfil_restringe_leitura_log_acesso_clinico','leitura_log_acesso_clinico',
    'perfil_restringe_leitura_folha_rescisoes','perfil_restringe_leitura_folha_itens',
    'perfil_restringe_leitura_epi_entregas','perfil_restringe_leitura_ouvidoria')
)
SELECT
  (to_regclass('public.log_acesso_clinico') IS NOT NULL) AS tabela_log,
  (to_regprocedure('public.ler_cid_clinico(text, uuid)') IS NOT NULL) AS funcao_ler_cid,
  (SELECT n FROM col) AS col_ouvidoria_prazo,
  (SELECT n FROM pol) AS politicas_de_6,
  CASE WHEN to_regclass('public.log_acesso_clinico') IS NOT NULL
        AND to_regprocedure('public.ler_cid_clinico(text, uuid)') IS NOT NULL
        AND (SELECT n FROM col)=1 AND (SELECT n FROM pol)=6
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;
