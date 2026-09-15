-- ============================================================================
-- Fase 4 (motores) — Avulsos: metas, ponto rural e camada de perfil de férias.
--
-- MCHK-002: check-in aplica valor/progresso/status na meta (o banco deriva).
-- PONTO-113: regime noturno RURAL (janela/percentual/hora cheia próprios).
-- PERFIL-003: camada de perfil nas 3 tabelas de férias que faltavam.
-- (PGP-014 já passa — a sugestão por proximidade e o encaminhamento estão
--  corretos; não requer mudança.)
--
-- NÃO incluído — MWKF-011 CONFLITA com o MWKF-001 (hoje verde). Um gatilho que
-- grave a trilha sozinho no UPDATE de workflow_status é o que o MWKF-011 pede,
-- mas o MWKF-001 já grava a linha PELO FRONT (INSERT manual, com justificativa)
-- e conta exatamente 2 linhas — o gatilho dobraria a contagem e o quebraria. E
-- a justificativa do MWKF-001 vem do usuário na tela, que o banco não tem no
-- gatilho. É decisão de produto: se o banco passar a ser a fonte da trilha, o
-- front deixa de inserir e o MWKF-001 precisa ser revisto junto. Registrado,
-- sem gambiarra (mesma natureza do conflito EPI-001 × EPI-043).
-- ============================================================================

-- ── MCHK-002: check-in reflete na meta ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.meta_checkin_aplica_na_meta()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  -- O check-in é a fonte: aplica valor e progresso na meta e deriva o status
  -- (100% => concluida; >0 => em_andamento). Nao mexe em metas canceladas.
  UPDATE public.metas m
     SET valor_atual = COALESCE(NEW.valor_novo, m.valor_atual),
         progresso   = COALESCE(NEW.progresso_novo, m.progresso),
         status = CASE
           WHEN m.status = 'cancelada' THEN m.status
           WHEN COALESCE(NEW.progresso_novo, m.progresso) >= 100 THEN 'concluida'::meta_status
           WHEN COALESCE(NEW.progresso_novo, m.progresso) > 0   THEN 'em_andamento'::meta_status
           ELSE m.status
         END
   WHERE m.id = NEW.meta_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_meta_checkin_aplica_na_meta ON public.metas_checkins;
CREATE TRIGGER trg_meta_checkin_aplica_na_meta
  AFTER INSERT ON public.metas_checkins
  FOR EACH ROW EXECUTE FUNCTION public.meta_checkin_aplica_na_meta();

-- ── PONTO-113: regime noturno rural ─────────────────────────────────────────
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS regime_rural text NOT NULL DEFAULT 'urbano';

COMMENT ON COLUMN public.admissoes.regime_rural IS
  'PONTO-113: urbano | rural_lavoura | rural_pecuaria — regime noturno proprio (Lei 5.889/73).';

DO $chk$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'admissoes_regime_rural_chk') THEN
    ALTER TABLE public.admissoes
      ADD CONSTRAINT admissoes_regime_rural_chk
      CHECK (regime_rural = ANY (ARRAY['urbano','rural_lavoura','rural_pecuaria'])) NOT VALID;
  END IF;
END;
$chk$;

CREATE OR REPLACE FUNCTION public.ponto_adicional_noturno_rural(p_regime text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $$
  -- Trabalhador RURAL tem regime noturno proprio (Lei 5.889/73): lavoura
  -- 21h-5h, pecuaria 20h-4h, adicional 25% e hora CHEIA (sem hora ficta),
  -- diferente do urbano (22h-5h, 20%, hora ficta de 52m30s).
  SELECT CASE p_regime
    WHEN 'rural_lavoura'  THEN jsonb_build_object('inicio','21:00','fim','05:00','adicional',25,'hora_ficta',false,'base','Lei 5.889/73')
    WHEN 'rural_pecuaria' THEN jsonb_build_object('inicio','20:00','fim','04:00','adicional',25,'hora_ficta',false,'base','Lei 5.889/73')
    ELSE jsonb_build_object('inicio','22:00','fim','05:00','adicional',20,'hora_ficta',true,'base','CLT art. 73')
  END;
$$;

COMMENT ON FUNCTION public.ponto_adicional_noturno_rural(text) IS
  'PONTO-113: parametros do adicional noturno rural (janela, 25%, sem hora ficta) x urbano.';

-- ── PERFIL-003: camada de perfil nas tabelas de férias ──────────────────────
-- ferias_alertas guarda dado pessoal (CPF/nome/custo por pessoa): política com
-- módulo OU o próprio dono (mesmo desenho de ferias_periodos_aquisitivos).
ALTER TABLE public.ferias_alertas ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'perfil_restringe_leitura_ferias_alertas') THEN
    CREATE POLICY perfil_restringe_leitura_ferias_alertas
      ON public.ferias_alertas
      AS RESTRICTIVE FOR SELECT
      USING (
        public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['ferias','colaboradores'])
        OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
      );
  END IF;
END;
$pol$;

-- ferias_coletivas e ferias_coletivas_comunicados são ORGANIZACIONAIS (decisão
-- por empresa/departamento, sem pessoa identificada): política só por módulo.
ALTER TABLE public.ferias_coletivas ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'perfil_restringe_leitura_ferias_coletivas') THEN
    CREATE POLICY perfil_restringe_leitura_ferias_coletivas
      ON public.ferias_coletivas
      AS RESTRICTIVE FOR SELECT
      USING (public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['ferias']));
  END IF;
END;
$pol$;

ALTER TABLE public.ferias_coletivas_comunicados ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'perfil_restringe_leitura_ferias_coletivas_comunicados') THEN
    CREATE POLICY perfil_restringe_leitura_ferias_coletivas_comunicados
      ON public.ferias_coletivas_comunicados
      AS RESTRICTIVE FOR SELECT
      USING (public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['ferias']));
  END IF;
END;
$pol$;
