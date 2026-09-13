-- ============================================================================
-- Fase 2 — Camada de perfil (LGPD) e log de acesso ao dado clínico.
--
-- Casos: DESL-110 (folha_rescisoes), FOLHA-090 (folha_itens), EPI-041
-- (biometria de epi_entregas), SST-041 (canal de assédio), AFAST-080 e SST-080
-- (log de acesso ao CID / acervo clínico).
--
-- Padrão da casa: política RESTRICTIVE `perfil_restringe_leitura_*` via
-- perfil_permite_modulo (só ESTREITA o SELECT; não afeta escrita nem quem já
-- administra). Aditivo e idempotente.
-- ============================================================================

-- ── AFAST-080 + SST-080: cofre do clínico — leitura do CID com trilha ───────
-- Tabela append-only + função SECURITY DEFINER que lê o CID e registra QUEM
-- consultou o diagnóstico de QUEM e quando (LGPD art. 11; seção 22/29).
CREATE TABLE IF NOT EXISTS public.log_acesso_clinico (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid,
  leitor_id    uuid,
  titular_cpf  text,
  origem       text NOT NULL,          -- 'afastamento_saude' | 'atestado' | 'evento_saude'
  registro_id  uuid,
  cid          text,
  acessado_em  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.log_acesso_clinico ENABLE ROW LEVEL SECURITY;
-- Leitura da trilha só para perfil da medicina/SST; escrita só pela função.
DO $pol$
BEGIN
  DROP POLICY IF EXISTS perfil_restringe_leitura_log_acesso_clinico ON public.log_acesso_clinico;
  CREATE POLICY perfil_restringe_leitura_log_acesso_clinico
    ON public.log_acesso_clinico AS RESTRICTIVE FOR SELECT
    USING (public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['sst'::text, 'atestados'::text]));
  DROP POLICY IF EXISTS leitura_log_acesso_clinico ON public.log_acesso_clinico;
  CREATE POLICY leitura_log_acesso_clinico
    ON public.log_acesso_clinico FOR SELECT USING (true);
END $pol$;

-- Lê o CID/diagnóstico do registro clínico e grava o log de acesso (append-only).
-- Referencia atestados (cid_codigo), afastamentos_saude (cid_principal) e
-- eventos_saude — serve de ponto único de leitura auditada do acervo clínico.
CREATE OR REPLACE FUNCTION public.ler_cid_clinico(p_origem text, p_registro_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  -- Trilha de acesso ao dado sensivel (append-only): quem leu, de quem, quando.
  INSERT INTO public.log_acesso_clinico (tenant_id, leitor_id, titular_cpf, origem, registro_id, cid)
  VALUES (v_tenant, auth.uid(), v_cpf, p_origem, p_registro_id, v_cid);

  RETURN v_cid;
END;
$$;
COMMENT ON FUNCTION public.ler_cid_clinico(text, uuid) IS
  'Le o CID/diagnostico (atestados.cid_codigo, afastamentos_saude.cid_principal, eventos_saude) e grava o log de acesso em log_acesso_clinico — cofre do clinico (AFAST-080/SST-080, LGPD art. 11).';

-- ── DESL-110: dossiê rescisório restrito por perfil ─────────────────────────
ALTER TABLE public.folha_rescisoes ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  DROP POLICY IF EXISTS perfil_restringe_leitura_folha_rescisoes ON public.folha_rescisoes;
  CREATE POLICY perfil_restringe_leitura_folha_rescisoes
    ON public.folha_rescisoes AS RESTRICTIVE FOR SELECT
    USING (
      public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['financeiro'::text, 'colaboradores'::text])
      OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
    );
END $pol$;
COMMENT ON POLICY perfil_restringe_leitura_folha_rescisoes ON public.folha_rescisoes IS
  'RESTRICTIVE: dossie rescisorio so por perfil (financeiro/colaboradores) ou pelo proprio colaborador. DESL-110.';

-- ── FOLHA-090: itens da folha (holerite) restritos por perfil ───────────────
ALTER TABLE public.folha_itens ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  DROP POLICY IF EXISTS perfil_restringe_leitura_folha_itens ON public.folha_itens;
  CREATE POLICY perfil_restringe_leitura_folha_itens
    ON public.folha_itens AS RESTRICTIVE FOR SELECT
    USING (
      public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['financeiro'::text, 'colaboradores'::text])
      OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
    );
END $pol$;
COMMENT ON POLICY perfil_restringe_leitura_folha_itens ON public.folha_itens IS
  'RESTRICTIVE: itens/holerite so por perfil (financeiro/colaboradores) ou pelo proprio colaborador. FOLHA-090.';

-- ── EPI-041: biometria da entrega de EPI restrita por perfil ────────────────
ALTER TABLE public.epi_entregas ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  DROP POLICY IF EXISTS perfil_restringe_leitura_epi_entregas ON public.epi_entregas;
  CREATE POLICY perfil_restringe_leitura_epi_entregas
    ON public.epi_entregas AS RESTRICTIVE FOR SELECT
    USING (
      public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['sst'::text, 'colaboradores'::text])
      OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
    );
END $pol$;
COMMENT ON POLICY perfil_restringe_leitura_epi_entregas ON public.epi_entregas IS
  'RESTRICTIVE: entrega de EPI (material biometrico) so por perfil (sst/colaboradores) ou pelo proprio colaborador — LGPD art. 11. EPI-041.';

-- ── SST-041: canal de assédio — sigilo reforçado e prazo de apuração ────────
ALTER TABLE public.ouvidoria ADD COLUMN IF NOT EXISTS prazo_apuracao_ate date;
COMMENT ON COLUMN public.ouvidoria.prazo_apuracao_ate IS
  'Prazo de tratativa/apuracao da denuncia (Lei 14.457/2022). SST-041.';
ALTER TABLE public.ouvidoria ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  DROP POLICY IF EXISTS perfil_restringe_leitura_ouvidoria ON public.ouvidoria;
  CREATE POLICY perfil_restringe_leitura_ouvidoria
    ON public.ouvidoria AS RESTRICTIVE FOR SELECT
    USING (
      public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['configuracoes'::text])
      OR autor_id = auth.uid()
      OR responsavel_id = auth.uid()
      OR respondido_por = auth.uid()
    );
END $pol$;
COMMENT ON POLICY perfil_restringe_leitura_ouvidoria ON public.ouvidoria IS
  'RESTRICTIVE: denuncia (assedio) so pelo fluxo de apuracao (perfil de configuracoes/compliance, responsavel ou autor) — sigilo reforcado da Lei 14.457. SST-041.';
