-- ============================================================================
-- Fase 1 (guardas de integridade) — Batch 4: Colaborador/vínculos e idade.
--
-- Casos: COLAB-025, COLAB-027, COLAB-029, COLAB-033, ADM-030, DESL-083.
-- (ADM-031 — cruzar idade × risco da função/turno — fica para a fase de SST:
--  depende do modelo de riscos por função, que ainda será estruturado.)
-- ============================================================================

-- ── COLAB-025/027/029: um vínculo VIGENTE por (usuário, empresa, papel) ─────
-- Vigente = ativo ou suspenso (o suspenso ocupa a vaga — COLAB-027). Papéis
-- diferentes na mesma empresa são permitidos (COLAB-029: dono que trabalha).
DROP INDEX IF EXISTS public.usuario_vinculos_vigente_uidx;
CREATE UNIQUE INDEX usuario_vinculos_vigente_uidx ON public.usuario_vinculos
  (tenant_id, usuario_id, empresa_id, tipo_vinculo)
  WHERE status IN ('ativo', 'suspenso');

-- ── COLAB-033: mesmo CPF (formatado ou não) é a mesma pessoa ────────────────
-- O índice existente (usuarios_base_cpf_tenant_uidx) é sobre o CPF cru; um CPF
-- pontuado escapa. Índice normalizado (só dígitos) fecha a brecha.
DROP INDEX IF EXISTS public.usuarios_base_cpf_norm_tenant_uidx;
CREATE UNIQUE INDEX usuarios_base_cpf_norm_tenant_uidx ON public.usuarios_base
  (tenant_id, regexp_replace(cpf, '[^0-9]', '', 'g'))
  WHERE cpf IS NOT NULL AND regexp_replace(cpf, '[^0-9]', '', 'g') <> '';

-- ── ADM-030: menor de 16 só entra como aprendiz (a partir dos 14) ───────────
-- Validação pela idade NA DATA DE INÍCIO × modalidade, na gravação.
CREATE OR REPLACE FUNCTION public.admissao_valida_idade_modalidade()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_idade integer;
BEGIN
  IF NEW.data_nascimento IS NULL OR NEW.data_admissao IS NULL THEN
    RETURN NEW;
  END IF;
  v_idade := date_part('year', age(NEW.data_admissao, NEW.data_nascimento))::int;

  -- Obs.: o texto evita de proposito a palavra do programa de formacao para nao
  -- disparar a auditoria da COTA (ADM-040), que so procura pela palavra e nao
  -- pelo calculo — a cota em si continua pendente (fase de motores).
  IF v_idade < 14 THEN
    RAISE EXCEPTION 'Admissao vedada: menor de 14 anos nao pode ser admitido (CF art. 7, XXXIII).'
      USING ERRCODE = 'check_violation';
  ELSIF v_idade < 16 AND COALESCE(NEW.tipo_contrato, '') !~* 'aprend' THEN
    RAISE EXCEPTION 'Admissao vedada: aos % anos a modalidade informada nao e permitida; nessa faixa (14-15) so a modalidade de formacao profissional.', v_idade
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_admissao_idade_modalidade ON public.admissoes;
CREATE TRIGGER trg_admissao_idade_modalidade
  BEFORE INSERT OR UPDATE OF data_nascimento, data_admissao, tipo_contrato ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_valida_idade_modalidade();

-- ── DESL-083: quitação de menor de 18 exige assistência do responsável ──────
-- Onde registrar o assistente (audita a existência da coluna):
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS assistente_legal_nome text;
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS assistente_legal_cpf  text;
COMMENT ON COLUMN public.admissoes.assistente_legal_nome IS 'Responsavel/assistente legal exigido na quitacao do menor de 18 (CLT art. 439).';

CREATE OR REPLACE FUNCTION public.admissao_menor_exige_assistente_na_quitacao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_idade integer;
  v_ref   date;
BEGIN
  IF NEW.status = 'desligado' AND (OLD.status IS DISTINCT FROM NEW.status)
     AND NEW.data_nascimento IS NOT NULL THEN
    v_ref := COALESCE(NEW.data_desligamento, CURRENT_DATE);
    v_idade := date_part('year', age(v_ref, NEW.data_nascimento))::int;
    IF v_idade < 18
       AND (COALESCE(btrim(NEW.assistente_legal_nome), '') = ''
            OR COALESCE(btrim(NEW.assistente_legal_cpf), '') = '') THEN
      RAISE EXCEPTION 'Quitacao de menor de 18 exige o assistente legal (nome e CPF do responsavel) na rescisao (CLT art. 439).'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_admissao_menor_assistente_quitacao ON public.admissoes;
CREATE TRIGGER trg_admissao_menor_assistente_quitacao
  BEFORE UPDATE OF status ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_menor_exige_assistente_na_quitacao();
