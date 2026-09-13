-- ============================================================================
-- Fase 3 (motores/estrutura) — Férias, lote 1.
--
-- Casos: FERIAS-091 (chave do aquisitivo por vínculo), FERIAS-008 (prescrição),
-- FERIAS-016 (estudante), FERIAS-010 (concordância do fracionamento),
-- FERIAS-040 (carimbo do requerimento de abono), FERIAS-031 (aviso < 30 dias),
-- FERIAS-042 (abono fora do prazo de 15 dias).
--
-- (Ficam para o próximo lote os motores maiores: FERIAS-003/024/053 pontes com
-- Afastamentos/Ponto, 030 aviso automático, 051 cancelamento que devolve saldo,
-- 070 encargos Simples III/IV, 071 cobertura, 090 liquidação na rescisão, e o
-- 020 que depende de alçada de diretoria.)
-- ============================================================================

-- ── FERIAS-091: o período aquisitivo é por VÍNCULO (tenant, empresa, CPF) ────
-- A chave antiga ignorava a empresa; dois contratos do mesmo CPF colidiam.
-- Incluir empresa_id só RELAXA a unicidade (não quebra dado existente).
ALTER TABLE public.ferias_periodos_aquisitivos DROP CONSTRAINT IF EXISTS ferias_periodo_unico;
ALTER TABLE public.ferias_periodos_aquisitivos ADD CONSTRAINT ferias_periodo_unico
  UNIQUE (tenant_id, empresa_id, colaborador_cpf, aquisitivo_inicio);

-- ── FERIAS-008: marco prescricional (fim do concessivo + 5 anos, art. 149) ──
CREATE OR REPLACE FUNCTION public.ferias_data_prescricao(p_aquisitivo_fim date)
RETURNS date LANGUAGE sql IMMUTABLE AS $$
  -- Concessivo = aquisitivo_fim + 12 meses; prescrição = concessivo + 5 anos.
  SELECT (p_aquisitivo_fim + INTERVAL '12 months' + INTERVAL '5 years')::date;
$$;
COMMENT ON FUNCTION public.ferias_data_prescricao(date) IS
  'Marco de prescricao do periodo de ferias: fim do concessivo (aquisitivo_fim + 12m) + 5 anos (art. 149 CLT). FERIAS-008.';

-- ── FERIAS-016: sinalização de estudante menor de 18 (art. 136, §2º) ────────
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS estudante boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.admissoes.estudante IS
  'Estudante — usado para alertar coincidencia das ferias com o recesso escolar no menor de 18 (art. 136, §2º). FERIAS-016.';

-- ── FERIAS-010: concordância do empregado com o fracionamento (art. 134, §1º)
ALTER TABLE public.ferias_programacao ADD COLUMN IF NOT EXISTS fracionamento_concordancia boolean;
ALTER TABLE public.ferias_programacao ADD COLUMN IF NOT EXISTS fracionamento_concordancia_em timestamptz;
ALTER TABLE public.ferias_programacao ADD COLUMN IF NOT EXISTS fracionamento_concordancia_por text;
COMMENT ON COLUMN public.ferias_programacao.fracionamento_concordancia IS
  'Concordancia do empregado com o fracionamento — o art. 134, §1º so o permite com ela. FERIAS-010.';

-- ── FERIAS-040: carimbo de QUANDO o abono foi requerido (art. 143, §1º) ─────
ALTER TABLE public.ferias_programacao ADD COLUMN IF NOT EXISTS abono_requerido_em date;
COMMENT ON COLUMN public.ferias_programacao.abono_requerido_em IS
  'Data do requerimento do abono pecuniario — prova do prazo do art. 143, §1º (ate 15 dias antes do fim do aquisitivo). FERIAS-040.';

-- ── FERIAS-031: aprovar com início em < 30 dias exige aviso ou justificativa ─
ALTER TABLE public.ferias_solicitacoes ADD COLUMN IF NOT EXISTS justificativa_excecao text;
COMMENT ON COLUMN public.ferias_solicitacoes.justificativa_excecao IS
  'Justificativa da excecao ao aviso de 30 dias (art. 135). FERIAS-031.';
CREATE OR REPLACE FUNCTION public.ferias_solic_valida_aviso_30d()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'aprovado'
     AND NEW.data_inicio IS NOT NULL
     AND (NEW.data_inicio - CURRENT_DATE) < 30
     AND COALESCE(NEW.aviso_gerado, false) = false
     AND COALESCE(btrim(NEW.justificativa_excecao), '') = '' THEN
    RAISE EXCEPTION 'Aprovacao com inicio em menos de 30 dias exige aviso emitido ou justificativa da excecao (art. 135).'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_ferias_solic_aviso_30d ON public.ferias_solicitacoes;
CREATE TRIGGER trg_ferias_solic_aviso_30d
  BEFORE INSERT OR UPDATE OF status, data_inicio, aviso_gerado, justificativa_excecao
  ON public.ferias_solicitacoes
  FOR EACH ROW EXECUTE FUNCTION public.ferias_solic_valida_aviso_30d();

-- ── FERIAS-042: abono requerido fora do prazo (menos de 15 dias) é recusado ─
CREATE OR REPLACE FUNCTION public.ferias_prog_valida_prazo_abono()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_requerido date;
BEGIN
  IF COALESCE(NEW.abono_dias, 0) > 0 AND NEW.aquisitivo_fim IS NOT NULL THEN
    v_requerido := COALESCE(NEW.abono_requerido_em, CURRENT_DATE);
    IF (NEW.aquisitivo_fim - v_requerido) < 15 THEN
      RAISE EXCEPTION 'Abono pecuniario deve ser requerido ate 15 dias antes do fim do periodo aquisitivo (art. 143, §1º); faltam % dia(s).', (NEW.aquisitivo_fim - v_requerido)
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_ferias_prog_prazo_abono ON public.ferias_programacao;
CREATE TRIGGER trg_ferias_prog_prazo_abono
  BEFORE INSERT OR UPDATE OF abono_dias, aquisitivo_fim, abono_requerido_em
  ON public.ferias_programacao
  FOR EACH ROW EXECUTE FUNCTION public.ferias_prog_valida_prazo_abono();

-- ── Ajuste da sonda FERIAS-055 para conviver com a nova trava (FERIAS-031) ──
-- A sonda insere uma solicitacao 'aprovado' com inicio HOJE para exercitar a
-- trava de CIENCIA do aviso (trg_ferias_trava_em_gozo). Com a FERIAS-031, um
-- 'aprovado' a menos de 30 dias exige aviso emitido ou justificativa. A sonda
-- passa a marcar aviso_gerado=true (o aviso foi EMITIDO; ela testa a CIENCIA,
-- nao a emissao) — cumpre a FERIAS-031 sem mudar o que a sonda verifica.
CREATE OR REPLACE FUNCTION public.qa_caso_ferias_055()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
    r          public.qa_retorno;
    v_tem_fn   BOOLEAN;
    v_tem_trg  BOOLEAN;
    v_barrou   BOOLEAN := false;
    v_liberou  BOOLEAN := false;
    v_id       UUID;
    v_ten      UUID;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao  := 'AUDITORIA: a ciencia do aviso trava o inicio do gozo (em_gozo)?';
    r.esperado    := 'Sem ciencia, em_gozo e barrado; com ciencia registrada, em_gozo passa (art. 135)';

    SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='public' AND p.proname='ferias_aviso_tem_ciencia')
      INTO v_tem_fn;
    SELECT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgname='trg_ferias_trava_em_gozo' AND NOT tgisinternal)
      INTO v_tem_trg;

    IF NOT v_tem_fn OR NOT v_tem_trg THEN
        r.situacao := 'falhou';
        r.obtido := 'ACHADO: nada condiciona a concessao a ciencia do aviso — em_gozo avanca '
                 || 'com o aviso pendente. O art. 135 exige comunicacao MEDIANTE RECIBO. '
                 || 'Correcao: trava de transicao para em_gozo condicionada a ciencia.';
        RETURN r;
    END IF;

    SELECT id INTO v_ten FROM public.tenants LIMIT 1;
    IF v_ten IS NULL THEN
        r.situacao := 'nao_implementado';
        r.obtido := 'Sem tenants na base para montar a sonda; a trava existe (funcao + trigger) '
                 || 'mas nao foi exercitada com dados.';
        RETURN r;
    END IF;

    BEGIN
        -- aviso_gerado=true: cumpre a FERIAS-031 (aviso EMITIDO); a sonda testa a CIENCIA.
        INSERT INTO public.ferias_solicitacoes
            (tenant_id, colaborador_nome, data_inicio, data_fim, dias_solicitados, status, aviso_gerado)
        VALUES (v_ten, 'QA Sonda FERIAS-055', CURRENT_DATE, CURRENT_DATE + 20, 20, 'aprovado', true)
        RETURNING id INTO v_id;

        BEGIN
            UPDATE public.ferias_solicitacoes SET status='em_gozo' WHERE id=v_id;
        EXCEPTION WHEN check_violation THEN
            v_barrou := true;
        END;

        UPDATE public.ferias_solicitacoes
           SET aviso_ciencia_em = now(), aviso_ciencia_origem = 'manual'
         WHERE id = v_id;
        BEGIN
            UPDATE public.ferias_solicitacoes SET status='em_gozo' WHERE id=v_id;
            v_liberou := true;
        EXCEPTION WHEN OTHERS THEN
            v_liberou := false;
        END;

        RAISE EXCEPTION 'qa_rollback';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'qa_rollback' THEN
            r.situacao := 'erro'; r.obtido := 'A sonda quebrou'; r.erro_tecnico := SQLERRM;
            RETURN r;
        END IF;
    END;

    IF v_barrou AND v_liberou THEN
        r.situacao := 'passou';
        r.obtido := 'A trava funciona: sem ciencia o inicio do gozo e barrado; com a ciencia '
                 || 'registrada, passa. A regra vive em ferias_aviso_tem_ciencia e na trigger '
                 || 'trg_ferias_trava_em_gozo.';
    ELSIF NOT v_barrou THEN
        r.situacao := 'falhou';
        r.obtido := 'A trava existe mas NAO barrou o em_gozo sem ciencia — a concessao avanca '
                 || 'sem a prova do art. 135.';
    ELSE
        r.situacao := 'falhou';
        r.obtido := 'A trava barrou ate com a ciencia registrada — esta bloqueando concessao '
                 || 'legitima. Revisar ferias_aviso_tem_ciencia.';
    END IF;
    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
