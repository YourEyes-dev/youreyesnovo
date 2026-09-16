-- ============================================================================
-- Fase 4 (motores) — Admissão: estrutura e travas básicas.
--
-- ADM-021: prazo determinado com data de término, teto de 2 anos e prorrogação
--          única (art. 445/451 CLT).
-- ADM-022: contrato intermitente com valor da hora (art. 452-A).
-- ADM-050: opção/renúncia de vale-transporte colhida na admissão (Lei 7.418).
-- ADM-051: conferência do salário contra o piso da CCT (folha_cct.piso_salarial).
-- ADM-052: checklist de documentos parametrizável (admissao_checklist_config).
-- ADM-071: justificativa obrigatória para admissão retroativa (data no passado).
-- ADM-072: conclusão bloqueada com ASO admissional INAPTO (NR-07).
-- ADM-073: política de retenção/anonimização de candidato não admitido (LGPD).
-- ADM-107: ASO admissional como entidade de saúde própria (NR-07/LGPD art. 11).
--
-- Adiados honestamente: ADM-070 (condicionar a conclusão à assinatura do
-- contrato) exige estender o fluxo de assinatura da experiência ao contrato da
-- admissão de ponta a ponta (inclui a tela); um bloqueio cru no banco travaria
-- o onboarding em produção enquanto a captura da assinatura não estiver ligada.
-- ADM-031 (idade × risco da função) segue com a fase de SST (modelo de riscos).
-- ============================================================================

-- ── Colunas novas em admissoes ──────────────────────────────────────────────
-- ADM-021 — prazo determinado estruturado.
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS prazo_determinado boolean NOT NULL DEFAULT false;
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS data_fim_contrato date;
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS prorrogacao_determinado_count integer NOT NULL DEFAULT 0;

-- ADM-022 — intermitente.
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS contrato_intermitente boolean NOT NULL DEFAULT false;
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS valor_hora numeric(12,2);

-- ADM-050 — opção de vale-transporte.
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS vale_transporte_opcao boolean;
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS vale_transporte_renuncia boolean NOT NULL DEFAULT false;

-- ADM-071 — justificativa de admissão retroativa.
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS justificativa_retroativa text;

-- ADM-107 — ASO admissional (documento de saúde próprio).
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS aso_admissional_data date;
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS aso_admissional_resultado text;
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS aso_admissional_documento_id uuid;

COMMENT ON COLUMN public.admissoes.aso_admissional_resultado IS
  'Resultado do ASO admissional (apto/inapto/apto_com_restricoes) — dado de saúde, NR-07/LGPD art. 11.';

-- ── ADM-021: validação do teto de 2 anos e da prorrogação única ─────────────
CREATE OR REPLACE FUNCTION public.admissao_valida_prazo_determinado()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_dias integer;
BEGIN
  -- Só age no contrato por prazo determinado (a experiência tem tabela própria).
  IF NOT COALESCE(NEW.prazo_determinado, false) THEN
    RETURN NEW;
  END IF;

  -- Prazo determinado exige data de término.
  IF NEW.data_fim_contrato IS NULL OR NEW.data_admissao IS NULL THEN
    RAISE EXCEPTION 'Contrato por prazo determinado exige data de admissao e data de fim.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Teto legal de 2 anos (art. 445): admissao..fim nao passa de 730 dias.
  v_dias := (NEW.data_fim_contrato - NEW.data_admissao) + 1;
  IF v_dias > 730 THEN
    RAISE EXCEPTION
      'Prazo determinado de % dias excede o teto legal de 2 anos (art. 445 CLT).', v_dias
      USING ERRCODE = 'check_violation';
  END IF;

  -- Prorrogação única (art. 451): mais de uma descaracteriza o prazo.
  IF COALESCE(NEW.prorrogacao_determinado_count, 0) > 1 THEN
    RAISE EXCEPTION
      'Contrato por prazo determinado admite uma unica prorrogacao (art. 451 CLT).'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_admissao_prazo_determinado ON public.admissoes;
CREATE TRIGGER trg_admissao_prazo_determinado
  BEFORE INSERT OR UPDATE OF prazo_determinado, data_fim_contrato, data_admissao,
                            prorrogacao_determinado_count
  ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_valida_prazo_determinado();

-- ── ADM-051: conferência do salário contra o piso salarial da CCT ───────────
-- Read-only: devolve o piso vigente da CCT para o cargo e se o salário o atende.
-- A tela consulta na abertura da admissão; abaixo do piso, exige justificativa.
CREATE OR REPLACE FUNCTION public.admissao_confere_piso_cct(
  p_tenant   uuid,
  p_empresa  uuid,
  p_cargo    text,
  p_salario  numeric,
  p_referencia date DEFAULT CURRENT_DATE
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_piso numeric;
BEGIN
  -- Piso salarial da CCT vigente na referência (folha_cct.piso_salarial).
  SELECT fc.piso_salarial
    INTO v_piso
    FROM public.folha_cct fc
   WHERE fc.tenant_id = p_tenant
     AND (fc.empresa_id IS NULL OR fc.empresa_id = p_empresa)
     AND COALESCE(fc.vigencia_inicio, p_referencia) <= p_referencia
     AND (fc.vigencia_fim IS NULL OR fc.vigencia_fim >= p_referencia)
   ORDER BY fc.piso_salarial DESC NULLS LAST
   LIMIT 1;

  RETURN jsonb_build_object(
    'piso_salarial', v_piso,
    'salario', p_salario,
    'atende_piso', (v_piso IS NULL OR COALESCE(p_salario, 0) >= v_piso),
    'diferenca', CASE WHEN v_piso IS NOT NULL AND COALESCE(p_salario,0) < v_piso
                      THEN v_piso - COALESCE(p_salario,0) ELSE 0 END
  );
END;
$$;

COMMENT ON FUNCTION public.admissao_confere_piso_cct(uuid, uuid, text, numeric, date) IS
  'ADM-051: confere o salario da admissao contra o piso_salarial da CCT vigente.';

-- ── ADM-072: conclusão bloqueada com ASO admissional inapto (NR-07) ─────────
CREATE OR REPLACE FUNCTION public.admissao_bloqueia_conclusao_inapto()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.status::text = 'concluido'
     AND COALESCE(OLD.status::text, '') <> 'concluido'
     AND (lower(COALESCE(NEW.exame_admissional_resultado, '')) = 'inapto'
          OR lower(COALESCE(NEW.aso_admissional_resultado, '')) = 'inapto') THEN
    RAISE EXCEPTION
      'Admissao com ASO admissional INAPTO nao pode ser concluida (NR-07): o colaborador esta impedido de iniciar nesta funcao.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_admissao_bloqueia_conclusao_inapto ON public.admissoes;
CREATE TRIGGER trg_admissao_bloqueia_conclusao_inapto
  BEFORE UPDATE OF status ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_bloqueia_conclusao_inapto();

-- ── ADM-073: retenção/anonimização de candidato não admitido (LGPD) ─────────
-- Espelha o desenho do Ponto (ponto_expurgar_registros): anonimiza os dados
-- pessoais de admissoes encerradas sem contratação (reprovado/cancelado) além
-- do prazo de retenção, preservando a trilha sem conteúdo pessoal. Callable
-- (não agenda sozinha): a base era a execução do contrato que não houve.
CREATE OR REPLACE FUNCTION public.admissao_expurgar_reprovadas(
  p_tenant uuid,
  p_anos   integer DEFAULT 2
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_corte date := (CURRENT_DATE - make_interval(years => GREATEST(p_anos, 1)))::date;
  v_qtd   integer;
BEGIN
  -- Anonimiza (descarta o conteúdo pessoal) das admissoes reprovadas/canceladas
  -- antigas; mantém a linha e o status para a trilha de que existiu o processo.
  WITH alvo AS (
    SELECT id FROM public.admissoes
     WHERE tenant_id = p_tenant
       AND status::text IN ('reprovado', 'cancelado')
       AND COALESCE(updated_at::date, created_at::date) < v_corte
       AND nome_completo IS DISTINCT FROM '[anonimizado]'
  )
  UPDATE public.admissoes a
     SET nome_completo               = '[anonimizado]',
         cpf                         = NULL,
         exame_admissional_resultado = NULL,
         aso_admissional_resultado   = NULL,
         aso_admissional_documento_id = NULL,
         justificativa_retroativa    = NULL
    FROM alvo
   WHERE a.id = alvo.id;

  GET DIAGNOSTICS v_qtd = ROW_COUNT;
  RETURN v_qtd;
END;
$$;

COMMENT ON FUNCTION public.admissao_expurgar_reprovadas(uuid, integer) IS
  'ADM-073: expurgo/anonimizacao de admissoes reprovadas/canceladas alem do prazo de retencao (LGPD).';

-- ── ADM-052: checklist de documentos parametrizável ─────────────────────────
-- Mesmo desenho de empresa_experiencia_config: exigência por empresa/categoria/
-- vigência, consumida pela geração dos itens em admissao_documentos.
CREATE TABLE IF NOT EXISTS public.admissao_checklist_config (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL,
  empresa_id    uuid,
  categoria     text,                    -- CNAE/categoria/cargo a que se aplica
  documento     text NOT NULL,           -- nome do documento exigido
  obrigatorio   boolean NOT NULL DEFAULT true,
  base_legal    text,
  vigencia_inicio date,
  vigencia_fim  date,
  ativo         boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.admissao_checklist_config IS
  'ADM-052: checklist de documentos da admissao parametrizavel por empresa/categoria/vigencia.';

ALTER TABLE public.admissao_checklist_config ENABLE ROW LEVEL SECURITY;

DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'Tenant isolation admissao_checklist_config') THEN
    CREATE POLICY "Tenant isolation admissao_checklist_config"
      ON public.admissao_checklist_config
      FOR ALL
      USING (tenant_id = public.get_user_tenant_id())
      WITH CHECK (tenant_id = public.get_user_tenant_id());
  END IF;
END;
$pol$;

DROP TRIGGER IF EXISTS update_admissao_checklist_config_updated_at ON public.admissao_checklist_config;
CREATE TRIGGER update_admissao_checklist_config_updated_at
  BEFORE UPDATE ON public.admissao_checklist_config
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
