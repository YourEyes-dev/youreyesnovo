-- ============================================================================
-- Protecao do menor de idade na admissao — ENTREGA producao.
-- Fecha ADM-030 (idade x modalidade), ADM-031 (idade x risco/turno) e
-- DESL-083 (quitacao do menor exige assistente legal).
--
-- Vedacoes: CF art. 7 XXXIII; CLT arts. 403/404/405/439. As travas rodam na
-- GRAVACAO (gatilho BEFORE), nao na tela — bloqueiam na fonte.
--
-- Esta camada entrou no desenvolvimento/staging por duas migrations
-- (20260913150600 fase1 e 20260915200000 fase4) mas nunca teve script de
-- entrega para homologacao/producao (drift): la os menores ficam sem trava.
--
-- So CRIA coisa nova: colunas IF NOT EXISTS (metadados, sem rewrite da tabela),
-- 3 funcoes CREATE OR REPLACE e 3 gatilhos. NAO altera nem apaga dado existente
-- — dispensa backup. Os gatilhos so agem em gravacoes FUTURAS; historico intacto.
-- Idempotente. Roda em UMA transacao no SQL Editor.
-- ============================================================================

SET lock_timeout = '10s';

-- Colunas de apoio (drift-safe) ----------------------------------------------
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS assistente_legal_nome text;
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS assistente_legal_cpf  text;
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS funcao_insalubre  boolean NOT NULL DEFAULT false;
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS funcao_periculosa boolean NOT NULL DEFAULT false;
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS escala_noturna    boolean NOT NULL DEFAULT false;

-- ADM-030: menor de 16 so entra como aprendiz (a partir dos 14) --------------
-- Validacao pela idade NA DATA DE INICIO x modalidade, na gravacao.
CREATE OR REPLACE FUNCTION public.admissao_valida_idade_modalidade()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
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
$fn$;

DROP TRIGGER IF EXISTS trg_admissao_idade_modalidade ON public.admissoes;
CREATE TRIGGER trg_admissao_idade_modalidade
  BEFORE INSERT OR UPDATE OF data_nascimento, data_admissao, tipo_contrato ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_valida_idade_modalidade();

-- ADM-031: idade x risco da funcao e turno -----------------------------------
-- Menor de 18 nao pode em jornada noturna (CLT art. 404) nem em funcao
-- insalubre/perigosa (CLT art. 405) — nao ha adicional que compense.
CREATE OR REPLACE FUNCTION public.admissao_valida_menor_risco()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
DECLARE
  v_idade integer;
BEGIN
  IF NEW.data_nascimento IS NULL THEN
    RETURN NEW;
  END IF;
  v_idade := EXTRACT(YEAR FROM age(COALESCE(NEW.data_admissao, CURRENT_DATE), NEW.data_nascimento))::int;
  IF v_idade < 18 THEN
    IF COALESCE(NEW.escala_noturna, false) THEN
      RAISE EXCEPTION
        'Menor de 18 anos nao pode ser alocado em jornada noturna (CLT art. 404).'
        USING ERRCODE = 'check_violation';
    END IF;
    IF COALESCE(NEW.funcao_insalubre, false) OR COALESCE(NEW.funcao_periculosa, false) THEN
      RAISE EXCEPTION
        'Menor de 18 anos nao pode ser admitido em funcao insalubre ou perigosa (CLT art. 405, CF art. 7 XXXIII).'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_admissao_valida_menor_risco ON public.admissoes;
CREATE TRIGGER trg_admissao_valida_menor_risco
  BEFORE INSERT OR UPDATE OF data_nascimento, data_admissao,
                            funcao_insalubre, funcao_periculosa, escala_noturna
  ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_valida_menor_risco();

-- DESL-083: quitacao de menor de 18 exige assistencia do responsavel ---------
CREATE OR REPLACE FUNCTION public.admissao_menor_exige_assistente_na_quitacao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
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
$fn$;

DROP TRIGGER IF EXISTS trg_admissao_menor_assistente_quitacao ON public.admissoes;
CREATE TRIGGER trg_admissao_menor_assistente_quitacao
  BEFORE UPDATE OF status ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_menor_exige_assistente_na_quitacao();

-- Conferencia (leve: os tres casos do tema) ----------------------------------
SELECT 'ADM-030' AS caso, (public.qa_executar_descartavel('qa_caso_adm_030')).situacao::text AS situacao
UNION ALL
SELECT 'ADM-031', (public.qa_executar_descartavel('qa_caso_adm_031')).situacao::text
UNION ALL
SELECT 'DESL-083', (public.qa_executar_descartavel('qa_caso_desl_083')).situacao::text
ORDER BY caso;
