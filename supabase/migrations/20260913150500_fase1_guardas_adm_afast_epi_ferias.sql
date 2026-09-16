-- ============================================================================
-- Fase 1 (guardas de integridade) — Batch 3: Admissão (experiência),
-- Afastamentos, EPI e Férias.
--
-- Casos: ADM-020, AFAST-011, AFAST-051, EPI-020, EPI-030,
-- FERIAS-013, FERIAS-014, FERIAS-052.
-- CHECKs sobre tabela com dado real vão NOT VALID (enforçam em linha nova/
-- alterada sem quebrar em dado legado).
-- ============================================================================

-- ── ADM-020: contrato de experiência dentro do teto de 90 dias ──────────────
ALTER TABLE public.contratos_experiencia DROP CONSTRAINT IF EXISTS chk_experiencia_primeiro_periodo;
ALTER TABLE public.contratos_experiencia ADD CONSTRAINT chk_experiencia_primeiro_periodo
  CHECK (duracao_primeiro_periodo IS NULL OR duracao_primeiro_periodo BETWEEN 1 AND 90) NOT VALID;
ALTER TABLE public.contratos_experiencia DROP CONSTRAINT IF EXISTS chk_experiencia_soma_90;
ALTER TABLE public.contratos_experiencia ADD CONSTRAINT chk_experiencia_soma_90
  CHECK (COALESCE(duracao_primeiro_periodo, 0) + COALESCE(duracao_prorrogacao, 0) <= 90) NOT VALID;

-- ── AFAST-011: dois afastamentos ATIVOS do mesmo colaborador não se sobrepõem ─
-- Trigger (em vez de EXCLUDE gist) para normalizar o CPF e filtrar por status;
-- a prorrogação continua sendo o UPDATE do fim no próprio registro (excluído por
-- id <> NEW.id).
CREATE OR REPLACE FUNCTION public.afastamento_sem_sobreposicao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'ativo' AND NEW.data_inicio IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.afastamentos a
      WHERE a.id <> NEW.id
        AND a.tenant_id = NEW.tenant_id
        AND a.status = 'ativo'
        AND regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g')
          = regexp_replace(COALESCE(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g')
        AND regexp_replace(COALESCE(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g') <> ''
        AND daterange(a.data_inicio, COALESCE(a.data_fim, 'infinity'::date), '[]')
          && daterange(NEW.data_inicio, COALESCE(NEW.data_fim, 'infinity'::date), '[]')
    ) THEN
      RAISE EXCEPTION 'Afastamento sobreposto para o mesmo colaborador: use a prorrogacao (ajuste da data de fim do registro ativo), nao um registro paralelo.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_afastamento_sem_sobreposicao ON public.afastamentos;
CREATE TRIGGER trg_afastamento_sem_sobreposicao
  BEFORE INSERT OR UPDATE OF data_inicio, data_fim, status, colaborador_cpf ON public.afastamentos
  FOR EACH ROW EXECUTE FUNCTION public.afastamento_sem_sobreposicao();

-- ── AFAST-051: suspensão disciplinar limitada a 30 dias (art. 474) ──────────
ALTER TABLE public.afastamentos DROP CONSTRAINT IF EXISTS chk_afast_suspensao_disciplinar_30d;
ALTER TABLE public.afastamentos ADD CONSTRAINT chk_afast_suspensao_disciplinar_30d
  CHECK (tipo_principal_new <> 'suspensao_disciplinar'
         OR data_fim IS NULL OR data_inicio IS NULL
         OR (data_fim - data_inicio + 1) <= 30) NOT VALID;

-- ── EPI-020: estoque de EPI nunca fica negativo ─────────────────────────────
-- O gatilho atualizar_estoque_epi subtrai do saldo; com o CHECK, a subtração que
-- levaria a negativo é recusada (check_violation) na própria baixa.
ALTER TABLE public.epis DROP CONSTRAINT IF EXISTS chk_epis_estoque_nao_negativo;
ALTER TABLE public.epis ADD CONSTRAINT chk_epis_estoque_nao_negativo
  CHECK (quantidade_estoque IS NULL OR quantidade_estoque >= 0) NOT VALID;

-- ── EPI-030: chave de acesso da NF única e com 44 dígitos ───────────────────
ALTER TABLE public.epi_notas_fiscais DROP CONSTRAINT IF EXISTS chk_epi_nf_chave_44;
ALTER TABLE public.epi_notas_fiscais ADD CONSTRAINT chk_epi_nf_chave_44
  CHECK (chave_acesso IS NULL OR chave_acesso ~ '^[0-9]{44}$') NOT VALID;
DROP INDEX IF EXISTS public.uq_epi_nf_chave_acesso;
CREATE UNIQUE INDEX uq_epi_nf_chave_acesso ON public.epi_notas_fiscais
  (tenant_id, chave_acesso) WHERE chave_acesso IS NOT NULL;

-- ── FERIAS-013: não programar mais dias do que o saldo ──────────────────────
ALTER TABLE public.ferias_solicitacoes DROP CONSTRAINT IF EXISTS chk_ferias_solic_saldo;
ALTER TABLE public.ferias_solicitacoes ADD CONSTRAINT chk_ferias_solic_saldo
  CHECK (saldo_dias IS NULL OR dias_solicitados IS NULL OR dias_solicitados <= saldo_dias) NOT VALID;

-- ── FERIAS-014: não iniciar férias nos 2 dias que antecedem feriado da unidade
-- (art. 134, §3º). Fonte única: feriados_da_empresa(tenant, empresa, ini, fim).
CREATE OR REPLACE FUNCTION public.ferias_programacao_veda_vespera_feriado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inicio date;
BEGIN
  IF NEW.empresa_id IS NULL THEN
    RETURN NEW;
  END IF;
  FOREACH v_inicio IN ARRAY ARRAY[NEW.p1_inicio, NEW.p2_inicio, NEW.p3_inicio] LOOP
    IF v_inicio IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.feriados_da_empresa(NEW.tenant_id, NEW.empresa_id, v_inicio + 1, v_inicio + 2)
    ) THEN
      RAISE EXCEPTION 'Inicio de ferias vedado: % cai nos 2 dias que antecedem um feriado da unidade (art. 134, §3º).', v_inicio
        USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_ferias_prog_vespera_feriado ON public.ferias_programacao;
CREATE TRIGGER trg_ferias_prog_vespera_feriado
  BEFORE INSERT OR UPDATE OF p1_inicio, p2_inicio, p3_inicio, empresa_id ON public.ferias_programacao
  FOR EACH ROW EXECUTE FUNCTION public.ferias_programacao_veda_vespera_feriado();

-- ── FERIAS-052: alterar data de programação CONFIRMADA exige justificativa ──
-- A justificativa é registrada em observacao; sem uma nova, a mudança de data é
-- recusada (histórico continua registrando, mas agora exige motivo).
CREATE OR REPLACE FUNCTION public.ferias_programacao_confirmada_exige_justificativa()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_data_mudou boolean;
  v_justificou boolean;
BEGIN
  IF OLD.estado IS DISTINCT FROM 'confirmado' THEN
    RETURN NEW;
  END IF;
  v_data_mudou :=
       NEW.p1_inicio IS DISTINCT FROM OLD.p1_inicio OR NEW.p1_fim IS DISTINCT FROM OLD.p1_fim
    OR NEW.p2_inicio IS DISTINCT FROM OLD.p2_inicio OR NEW.p2_fim IS DISTINCT FROM OLD.p2_fim
    OR NEW.p3_inicio IS DISTINCT FROM OLD.p3_inicio OR NEW.p3_fim IS DISTINCT FROM OLD.p3_fim;
  v_justificou :=
       NEW.observacao IS DISTINCT FROM OLD.observacao
   AND COALESCE(btrim(NEW.observacao), '') <> '';
  IF v_data_mudou AND NOT v_justificou THEN
    RAISE EXCEPTION 'Alteracao de data de ferias confirmadas exige justificativa (preencha a observacao com o motivo).';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_ferias_prog_confirmada_justificativa ON public.ferias_programacao;
CREATE TRIGGER trg_ferias_prog_confirmada_justificativa
  BEFORE UPDATE ON public.ferias_programacao
  FOR EACH ROW EXECUTE FUNCTION public.ferias_programacao_confirmada_exige_justificativa();
