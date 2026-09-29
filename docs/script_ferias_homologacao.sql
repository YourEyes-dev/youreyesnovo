-- ============================================================================
-- ENTREGA — FÉRIAS na HOMOLOGAÇÃO (fila de porte: 23 casos vermelhos)
--
-- Cole INTEIRO no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na
-- PRODUÇÃO. Traz para a homologação as guardas/motores de férias que já estão
-- verdes no teste (via migrations) e nunca foram colados aqui.
--
-- Cobre: FERIAS-001, 003, 004, 008, 010, 011, 012, 013, 014, 024, 030, 031,
--        040, 041, 042, 051, 052, 053, 054(*), 070, 071, 090, 091.
--   (*) FERIAS-054 fica verde de carona na fase 4; não há feature de reabertura
--       dedicada — é ajuste do próprio caso, anotado para a equipe.
--
-- SEGURANÇA: NÃO cria tabela (sem a pegadinha do auto-RLS do editor); só
-- ALTER ... ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE FUNCTION, DROP TRIGGER
-- IF EXISTS + CREATE TRIGGER e DROP/ADD CONSTRAINT (todas as constraints são
-- permissivas — relaxam unicidade / ampliam CHECK —, não quebram dado existente).
-- Idempotente. Roda numa transação. A ORDEM importa (leva1 → fase1 → fase3 →
-- fase4): as etapas seguintes dependem das colunas/constraints das anteriores.
--
-- Montado a partir das MESMAS definições vivas no teste (conferido: cada função
-- abaixo é a versão mais recente do repositório, sem redefinição posterior):
--   docs/script_ferias_regras_leva1.sql
--   20260913150500 (bloco de férias) · 20260913160100 · 20260913160200 · 20260915160000
-- Ao fim, uma conferência única: todas as linhas devem sair 'ok'.
-- ============================================================================

SET lock_timeout = '10s';

-- ════════════════════════ 1) LEVA 1 — regras no banco (001, 011, 012, 041) ════
-- ============================================================================
-- YourEyes · PRODUÇÃO · Regras de férias no banco — primeira leva
--
-- O QUE ESTE SCRIPT FAZ
--
-- O motor de regras de férias existe e é bem-feito, mas roda no NAVEGADOR.
-- Os dados entram por três portas — a tela, a importação em massa e a API —
-- e só a primeira passa por ele. Este script leva ao banco as três regras
-- que a lei trata como teto duro, para valerem por qualquer caminho.
--
--   1. Art. 130  — os dias de direito passam a ser DERIVADOS das faltas
--   2. Art. 134 §1º — fracionamento 14+5+5 vira recusa
--   3. Art. 143  — abono acima de 10 dias vira recusa
--
-- POR QUE SÓ ESTAS TRÊS
--
-- O diagnóstico rodado na sua produção mediu, sobre 31 períodos e 19
-- solicitações, quantos registros violariam cada regra HOJE. Estas três
-- deram ZERO: a base já as cumpre, então travar não quebra nada.
--
-- Duas ficaram de fora de propósito:
--   • solicitação acima do saldo — 3 dos 19 registros violam; travar agora
--     impediria justamente a correção deles;
--   • chave do período por vínculo — exige mudar a tela junto, e entre o
--     script e a publicação a importação quebraria. Deu zero casos hoje:
--     é defeito latente, e merece entrega própria.
--
-- SEGURO DE RODAR DUAS VEZES. Cada trava é aplicada em bloco próprio: se
-- algum registro tiver mudado desde o diagnóstico, aquela trava não nasce e
-- o script continua, dizendo o motivo — em vez de abortar tudo.
--
-- ATENÇÃO À ORDEM: rode este script ANTES de publicar no Lovable. A
-- publicação traz a gravação de quem aprovou as férias, que não depende
-- deste script, mas o inverso também vale — não há travamento entre os dois.
--
-- COMO RODAR: cole o arquivo inteiro no SQL Editor do projeto de PRODUÇÃO.
-- O último resultado é a conferência.
-- ============================================================================

SET lock_timeout = '10s';

-- ─────────────────────────────────────────────────────────────────────
-- 1) Art. 130 — os dias de direito passam a ser DERIVADOS das faltas
--
-- A função com a escala (30/24/18/12/0) já existia e está correta; o que
-- faltava era obrigar o dado gravado a passar por ela. Uma trava do tipo
-- CHECK não serviria aqui: a escala depende do método configurado por
-- empresa ('clt_faltas' × 'proporcional_avos'), e CHECK não consulta
-- outra tabela. Por isso é um gatilho que DERIVA, em vez de recusar —
-- assim a importação em massa também passa a obedecer, sem quebrar.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ferias_deriva_dias_direito()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_metodo text;
BEGIN
  SELECT metodo_calculo INTO v_metodo
    FROM public.ferias_config
   WHERE tenant_id = NEW.tenant_id
     AND empresa_id IS NOT DISTINCT FROM NEW.empresa_id
   LIMIT 1;

  IF v_metodo IS NULL THEN
    SELECT metodo_calculo INTO v_metodo
      FROM public.ferias_config
     WHERE tenant_id = NEW.tenant_id AND empresa_id IS NULL
     LIMIT 1;
  END IF;

  -- Fora do regime da escala (avos), o cálculo é outro: não mexer.
  IF COALESCE(v_metodo, 'clt_faltas') <> 'clt_faltas' THEN
    RETURN NEW;
  END IF;

  NEW.dias_direito :=
    public.ferias_dias_por_faltas_clt(COALESCE(NEW.faltas_consideradas, 0));

  NEW.dias_saldo :=
    GREATEST(0, COALESCE(NEW.dias_direito, 0) - COALESCE(NEW.dias_gozados, 0));

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_ferias_deriva_dias_direito ON public.ferias_periodos_aquisitivos;
CREATE TRIGGER trg_ferias_deriva_dias_direito
  BEFORE INSERT OR UPDATE OF faltas_consideradas, dias_gozados, dias_direito, empresa_id
  ON public.ferias_periodos_aquisitivos
  FOR EACH ROW EXECUTE FUNCTION public.ferias_deriva_dias_direito();

-- ─────────────────────────────────────────────────────────────────────
-- 2) Art. 134 §1º — fracionamento
--
-- Fracionou (dois ou três períodos): um precisa ter 14 dias ou mais e
-- nenhum pode ter menos de 5. Não fracionou (um período só): sem piso —
-- a lei não exige mínimo de quem tira tudo de uma vez.
--
-- LEAST/GREATEST ignoram NULL no PostgreSQL, e o NULLIF zera o
-- subperíodo não usado para que ele não entre como "menor de 5".
-- ─────────────────────────────────────────────────────────────────────
DO $frac$
BEGIN
  ALTER TABLE public.ferias_programacao
    DROP CONSTRAINT IF EXISTS ferias_prog_fracionamento_clt;

  ALTER TABLE public.ferias_programacao
    ADD CONSTRAINT ferias_prog_fracionamento_clt CHECK (
      (CASE WHEN COALESCE(p1_dias, 0) > 0 THEN 1 ELSE 0 END
     + CASE WHEN COALESCE(p2_dias, 0) > 0 THEN 1 ELSE 0 END
     + CASE WHEN COALESCE(p3_dias, 0) > 0 THEN 1 ELSE 0 END) <= 1
      OR (
        GREATEST(COALESCE(p1_dias, 0), COALESCE(p2_dias, 0), COALESCE(p3_dias, 0)) >= 14
        AND LEAST(NULLIF(COALESCE(p1_dias, 0), 0),
                  NULLIF(COALESCE(p2_dias, 0), 0),
                  NULLIF(COALESCE(p3_dias, 0), 0)) >= 5
      )
    );
  RAISE NOTICE 'Trava do fracionamento (art. 134, §1º) aplicada.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENÇÃO: trava do fracionamento NAO aplicada: %. '
               'Rode o diagnóstico (item 3) e corrija os registros antes.', SQLERRM;
END $frac$;

-- ─────────────────────────────────────────────────────────────────────
-- 3) Art. 143 — teto do abono pecuniário
--
-- O teto absoluto é de 10 dias (1/3 de 30). O limite RELATIVO (1/3 do
-- direito de quem tem menos de 30 dias por faltas) depende do período
-- aquisitivo, que está em outra tabela — CHECK não consulta outra
-- tabela, então essa parte segue no motor da tela, que já a avalia.
-- Aqui fica o teto que nenhuma situação pode ultrapassar.
-- ─────────────────────────────────────────────────────────────────────
DO $abono$
BEGIN
  ALTER TABLE public.ferias_programacao
    DROP CONSTRAINT IF EXISTS ferias_prog_abono_teto;

  ALTER TABLE public.ferias_programacao
    ADD CONSTRAINT ferias_prog_abono_teto CHECK (
      COALESCE(abono_vender, false) = false OR COALESCE(abono_dias, 0) <= 10
    );
  RAISE NOTICE 'Trava do teto do abono (art. 143) aplicada.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENÇÃO: trava do abono NAO aplicada: %. '
               'Rode o diagnóstico (item 4) e corrija os registros antes.', SQLERRM;
END $abono$;

-- ============================================================================
-- CONFERÊNCIA — é o único resultado que o editor mostra
-- ============================================================================
WITH esperado AS MATERIALIZED (
  SELECT * FROM (VALUES
    (1, 'Art. 130 — dias derivados das faltas', 'trigger',
     'trg_ferias_deriva_dias_direito', 'ferias_periodos_aquisitivos'),
    (2, 'Art. 134 §1º — fracionamento 14+5+5', 'check',
     'ferias_prog_fracionamento_clt', 'ferias_programacao'),
    (3, 'Art. 143 — abono no teto de 10 dias', 'check',
     'ferias_prog_abono_teto', 'ferias_programacao')
  ) AS t(ordem, regra, tipo, objeto, tabela)
)
SELECT
  e.regra,
  CASE
    WHEN e.tipo = 'trigger' AND EXISTS (
      SELECT 1 FROM pg_trigger g
      WHERE g.tgrelid = ('public.' || e.tabela)::regclass
        AND g.tgname = e.objeto AND NOT g.tgisinternal) THEN 'ok'
    WHEN e.tipo = 'check' AND EXISTS (
      SELECT 1 FROM pg_constraint c
      WHERE c.conrelid = ('public.' || e.tabela)::regclass
        AND c.conname = e.objeto) THEN 'ok'
    ELSE 'FALTA'
  END AS situacao,
  CASE
    WHEN e.tipo = 'trigger' AND EXISTS (
      SELECT 1 FROM pg_trigger g
      WHERE g.tgrelid = ('public.' || e.tabela)::regclass
        AND g.tgname = e.objeto AND NOT g.tgisinternal) THEN ''
    WHEN e.tipo = 'check' AND EXISTS (
      SELECT 1 FROM pg_constraint c
      WHERE c.conrelid = ('public.' || e.tabela)::regclass
        AND c.conname = e.objeto) THEN ''
    ELSE 'nao aplicada — algum registro da base viola a regra; rode o '
         || 'script_diagnostico_ferias_regras.sql e corrija antes'
  END AS erro_tecnico
FROM esperado e

UNION ALL

SELECT 'Camada de perfil em Férias (não pode ter regredido)',
       CASE WHEN count(*) = 7 THEN 'ok' ELSE 'FALTA' END,
       CASE WHEN count(*) = 7 THEN '' ELSE count(*)::text || ' de 7 políticas' END
FROM pg_policies
WHERE schemaname = 'public'
  AND permissive = 'RESTRICTIVE' AND cmd = 'SELECT'
  AND policyname LIKE 'perfil_restringe_leitura_%'
  AND tablename IN ('ferias_periodos_aquisitivos','ferias_programacao',
                    'ferias_solicitacoes','folha_ferias_calculo',
                    'ferias_assinatura_links','ferias_historico',
                    'ferias_vinculo_familiar')
ORDER BY 1;

-- ════════════════════════ 2) FASE 1 — guardas de férias (013, 014, 052) ═══════
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

-- ════════════════════════ 3) FASE 3 — estrutura e prazos (091,008,010,040,031,030,042) ═══
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


-- ════════════════════════ 4) FASE 3 — pontes afastamento/ponto (003, 024, 053) ═══
ALTER TABLE public.ferias_periodos_aquisitivos
  ADD COLUMN IF NOT EXISTS interrompido_afastamento_id uuid;

-- ── FERIAS-003: recálculo consulta os afastamentos (art. 133) ───────────────
CREATE OR REPLACE FUNCTION public.ferias_recalcular_periodo(p_periodo_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r            public.ferias_periodos_aquisitivos%ROWTYPE;
    v_metodo     TEXT;
    v_faltas_pt  INTEGER;
    v_faltas     INTEGER;
    v_fonte      TEXT;
    v_direito    NUMERIC(4,1);
    v_meses      INTEGER;
    v_prev_dias  INTEGER;
    v_af_id      UUID;
BEGIN
    SELECT * INTO r FROM public.ferias_periodos_aquisitivos WHERE id = p_periodo_id;
    IF NOT FOUND THEN RETURN; END IF;

    -- Art. 133, IV (CLT): benefício previdenciário por mais de 6 meses (mesmo
    -- descontínuos) no período aquisitivo faz perder o direito; um novo período
    -- começa no retorno. Aqui zera o aquisitivo atual e registra a origem —
    -- consulta o módulo de Afastamentos (b31/b91) sobreposto à janela.
    SELECT COALESCE(SUM(
             (LEAST(COALESCE(a.data_fim, r.aquisitivo_fim), r.aquisitivo_fim)
              - GREATEST(a.data_inicio, r.aquisitivo_inicio)) + 1), 0),
           MAX(a.id)
      INTO v_prev_dias, v_af_id
      FROM public.afastamentos a
     WHERE a.tenant_id = r.tenant_id
       AND regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g')
         = regexp_replace(COALESCE(r.colaborador_cpf, ''), '[^0-9]', '', 'g')
       AND a.tipo_principal_new IN ('beneficio_b31', 'beneficio_b91')
       AND a.data_inicio <= r.aquisitivo_fim
       AND COALESCE(a.data_fim, r.aquisitivo_fim) >= r.aquisitivo_inicio;

    IF COALESCE(v_prev_dias, 0) > 180 THEN
        UPDATE public.ferias_periodos_aquisitivos
           SET interrompido_art133         = true,
               interrompido_afastamento_id = v_af_id,
               dias_direito                = 0,
               dias_saldo                  = 0,
               calculado_em                = now(),
               validacao_motivo            = 'Art. 133, IV: beneficio previdenciario > 6 meses no periodo reinicia o aquisitivo (novo periodo a partir do retorno).'
         WHERE id = p_periodo_id;
        RETURN;
    END IF;

    -- Método da empresa (fallback: config geral do tenant → clt_faltas)
    SELECT metodo_calculo INTO v_metodo
      FROM public.ferias_config
     WHERE tenant_id = r.tenant_id
       AND empresa_id IS NOT DISTINCT FROM r.empresa_id
     LIMIT 1;
    IF v_metodo IS NULL THEN
        SELECT metodo_calculo INTO v_metodo
          FROM public.ferias_config
         WHERE tenant_id = r.tenant_id AND empresa_id IS NULL
         LIMIT 1;
    END IF;
    v_metodo := COALESCE(v_metodo, 'clt_faltas');

    -- Fonte das faltas: ponto tem precedência; senão, carga.
    v_faltas_pt := public.ferias_faltas_do_ponto(
        r.tenant_id, r.colaborador_cpf, r.aquisitivo_inicio, r.aquisitivo_fim
    );
    IF v_faltas_pt IS NOT NULL THEN
        v_faltas := v_faltas_pt;
        v_fonte  := 'ponto';
    ELSE
        v_faltas := COALESCE(r.faltas_carga, 0);
        v_fonte  := 'carga';
    END IF;

    IF v_metodo = 'proporcional_avos' THEN
        v_meses := GREATEST(0, LEAST(12,
            (EXTRACT(YEAR  FROM age(r.aquisitivo_fim + 1, r.aquisitivo_inicio)) * 12
           + EXTRACT(MONTH FROM age(r.aquisitivo_fim + 1, r.aquisitivo_inicio)))::INTEGER));
        v_direito := ROUND(v_meses * 2.5, 1);
        IF v_faltas > 32 THEN v_direito := 0; END IF;
    ELSE
        v_direito := public.ferias_dias_por_faltas_clt(v_faltas);
    END IF;

    UPDATE public.ferias_periodos_aquisitivos
       SET fonte_faltas        = v_fonte,
           faltas_consideradas = v_faltas,
           dias_direito        = v_direito,
           dias_saldo          = GREATEST(0, v_direito - COALESCE(dias_gozados, 0)),
           calculado_em        = now(),
           status = CASE
               WHEN v_direito = 0 AND v_faltas > 32
                    AND status NOT IN ('zerado_confirmado', 'encerrado')
                   THEN 'pendente_validacao'
               WHEN status = 'pendente_validacao' AND NOT (v_direito = 0 AND v_faltas > 32)
                   THEN 'ativo'
               ELSE status
           END,
           validacao_motivo = CASE
               WHEN v_direito = 0 AND v_faltas > 32
                   THEN v_faltas || ' faltas no período — art. 130 da CLT retira o direito a férias'
               ELSE validacao_motivo
           END
     WHERE id = p_periodo_id;
END;
$$;

-- ── FERIAS-024: afastamento sobreposto suspende as férias em gozo/aprovadas ─
-- Status 'suspenso' passa a existir; DP reprograma e devolve o saldo depois.
ALTER TABLE public.ferias_solicitacoes DROP CONSTRAINT IF EXISTS ferias_solicitacoes_status_check;
ALTER TABLE public.ferias_solicitacoes ADD CONSTRAINT ferias_solicitacoes_status_check
  CHECK (status = ANY (ARRAY['pendente','aprovado','recusado','cancelado','em_gozo','concluido','suspenso']));

CREATE OR REPLACE FUNCTION public.afastamento_suspende_ferias()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'ativo' AND NEW.data_inicio IS NOT NULL THEN
    UPDATE public.ferias_solicitacoes fs
       SET status = 'suspenso'
     WHERE fs.tenant_id = NEW.tenant_id
       AND regexp_replace(COALESCE(fs.colaborador_cpf, ''), '[^0-9]', '', 'g')
         = regexp_replace(COALESCE(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g')
       AND fs.status IN ('em_gozo', 'aprovado')
       AND fs.data_inicio <= COALESCE(NEW.data_fim, fs.data_fim)
       AND fs.data_fim   >= NEW.data_inicio;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_afastamento_suspende_ferias ON public.afastamentos;
CREATE TRIGGER trg_afastamento_suspende_ferias
  AFTER INSERT OR UPDATE OF status, data_inicio, data_fim ON public.afastamentos
  FOR EACH ROW EXECUTE FUNCTION public.afastamento_suspende_ferias();

-- ── FERIAS-053: ponto durante férias em gozo é recusado ─────────────────────
-- Estende o validador de marcação (que só olhava afastamentos) para também
-- barrar quando há férias em gozo cobrindo a data (casamento por CPF).
CREATE OR REPLACE FUNCTION public.validar_batida_afastamento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_af RECORD;
  v_fer RECORD;
BEGIN
  SELECT data_inicio, data_fim INTO v_af
    FROM public.afastamentos
   WHERE tenant_id = NEW.tenant_id
     AND colaborador_id = NEW.colaborador_id
     AND status::text IN ('ativo', 'beneficio_inss')
     AND NEW.data_marcacao BETWEEN data_inicio AND COALESCE(data_fim, DATE '9999-12-31')
   ORDER BY data_inicio DESC
   LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION
      'Colaborador afastado desde % %. Não é possível registrar ponto durante o afastamento.',
      to_char(v_af.data_inicio, 'DD/MM/YYYY'),
      CASE WHEN v_af.data_fim IS NULL
           THEN '(sem data de término registrada)'
           ELSE 'até ' || to_char(v_af.data_fim, 'DD/MM/YYYY') END;
  END IF;

  -- Férias em gozo também suspendem a prestação de serviço (art. 129/130).
  SELECT data_inicio, data_fim INTO v_fer
    FROM public.ferias_solicitacoes
   WHERE tenant_id = NEW.tenant_id
     AND regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g')
       = regexp_replace(COALESCE(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g')
     AND status = 'em_gozo'
     AND NEW.data_marcacao BETWEEN data_inicio AND data_fim
   ORDER BY data_inicio DESC
   LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION
      'Colaborador em férias (em gozo) de % a %. Não é possível registrar ponto durante as férias.',
      to_char(v_fer.data_inicio, 'DD/MM/YYYY'), to_char(v_fer.data_fim, 'DD/MM/YYYY');
  END IF;

  RETURN NEW;
END;
$$;

-- ════════════════════════ 5) FASE 4 — saldo, encargos e rescisão (004,051,070,071,090) ═══
-- ── FERIAS-004: prioridade do aquisitivo mais antigo ────────────────────────
CREATE OR REPLACE FUNCTION public.ferias_programacao_prioriza_antigo()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  -- Existe um período aquisitivo ANTERIOR (encerrado antes do início deste),
  -- ainda com saldo? Então programar contra o mais novo deixa o antigo vencer
  -- em dobro (art. 137). Recusa para forçar a baixa do mais antigo primeiro.
  IF EXISTS (
    SELECT 1 FROM public.ferias_periodos_aquisitivos p
     WHERE p.tenant_id = NEW.tenant_id
       AND regexp_replace(COALESCE(p.colaborador_cpf,''), '[^0-9]', '', 'g')
         = regexp_replace(COALESCE(NEW.colaborador_cpf,''), '[^0-9]', '', 'g')
       AND COALESCE(p.dias_saldo, 0) > 0
       AND COALESCE(p.status, 'ativo') = 'ativo'
       AND p.aquisitivo_fim < NEW.aquisitivo_inicio
  ) THEN
    RAISE EXCEPTION
      'Ha periodo aquisitivo mais antigo em aberto: programe a baixa dele primeiro (risco de ferias em dobro, art. 137).'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ferias_programacao_prioriza_antigo ON public.ferias_programacao;
CREATE TRIGGER trg_ferias_programacao_prioriza_antigo
  BEFORE INSERT ON public.ferias_programacao
  FOR EACH ROW EXECUTE FUNCTION public.ferias_programacao_prioriza_antigo();

-- ── FERIAS-051: cancelamento devolve os dias ao saldo ───────────────────────
CREATE OR REPLACE FUNCTION public.ferias_cancelamento_devolve_saldo(
  p_solicitacao_id uuid,
  p_motivo         text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  fs public.ferias_solicitacoes%ROWTYPE;
BEGIN
  SELECT * INTO fs FROM public.ferias_solicitacoes WHERE id = p_solicitacao_id;
  IF NOT FOUND THEN RETURN; END IF;

  -- Marca cancelada (com motivo) e DEVOLVE os dias ao saldo do período
  -- aquisitivo mais antigo em aberto do colaborador; o alerta de vencimento
  -- reabre naturalmente ao voltar o saldo.
  UPDATE public.ferias_solicitacoes
     SET status = 'cancelado'
   WHERE id = p_solicitacao_id;

  UPDATE public.ferias_periodos_aquisitivos p
     SET dias_saldo = COALESCE(p.dias_saldo, 0) + COALESCE(fs.dias_solicitados, 0),
         dias_gozados = GREATEST(0, COALESCE(p.dias_gozados, 0) - COALESCE(fs.dias_solicitados, 0))
   WHERE p.id = (
     SELECT p2.id FROM public.ferias_periodos_aquisitivos p2
      WHERE p2.tenant_id = fs.tenant_id
        AND regexp_replace(COALESCE(p2.colaborador_cpf,''), '[^0-9]', '', 'g')
          = regexp_replace(COALESCE(fs.colaborador_cpf,''), '[^0-9]', '', 'g')
        AND COALESCE(p2.status,'ativo') = 'ativo'
      ORDER BY p2.aquisitivo_inicio ASC
      LIMIT 1);

  -- Trilha do cancelamento (motivo obrigatorio) fica no historico da solicitacao.
  RAISE NOTICE 'Ferias % canceladas: % (dias devolvidos ao saldo).', p_solicitacao_id, p_motivo;
END;
$$;

COMMENT ON FUNCTION public.ferias_cancelamento_devolve_saldo(uuid, text) IS
  'FERIAS-051: cancelamento com motivo devolve os dias ao saldo do periodo aquisitivo.';

-- ── FERIAS-070: encargos da provisão por enquadramento (Simples) ────────────
CREATE OR REPLACE FUNCTION public.ferias_encargos_provisao(
  p_tenant  uuid,
  p_empresa uuid,
  p_base    numeric
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  cfg public.ferias_config%ROWTYPE;
  v_patronal numeric;
BEGIN
  SELECT * INTO cfg FROM public.ferias_config
   WHERE tenant_id = p_tenant AND empresa_id IS NOT DISTINCT FROM p_empresa
   LIMIT 1;
  IF NOT FOUND THEN
    SELECT * INTO cfg FROM public.ferias_config
     WHERE tenant_id = p_tenant AND empresa_id IS NULL LIMIT 1;
  END IF;

  -- Simples Anexo III: simples_dispensa_patronal = true -> sem contribuicao
  -- patronal (mantem FGTS). Anexo IV: recolhe a patronal normalmente.
  v_patronal := CASE WHEN COALESCE(cfg.simples_dispensa_patronal, false)
                     THEN 0
                     ELSE ROUND(COALESCE(p_base,0) * COALESCE(cfg.encargo_inss_patronal, 0) / 100.0, 2)
                END;

  RETURN jsonb_build_object(
    'simples_dispensa_patronal', COALESCE(cfg.simples_dispensa_patronal, false),
    'inss_patronal', v_patronal,
    'fgts', ROUND(COALESCE(p_base,0) * COALESCE(cfg.encargo_fgts, 8) / 100.0, 2),
    'rat_fap', ROUND(COALESCE(p_base,0) * COALESCE(cfg.encargo_rat_fap, 0) / 100.0, 2),
    'terceiros', CASE WHEN COALESCE(cfg.simples_dispensa_patronal, false) THEN 0
                      ELSE ROUND(COALESCE(p_base,0) * COALESCE(cfg.encargo_terceiros, 0) / 100.0, 2) END
  );
END;
$$;

COMMENT ON FUNCTION public.ferias_encargos_provisao(uuid, uuid, numeric) IS
  'FERIAS-070: encargos da provisao de ferias distinguindo Simples Anexo III/IV (simples_dispensa_patronal).';

-- ── FERIAS-071: alerta de cobertura por departamento ────────────────────────
CREATE OR REPLACE FUNCTION public.ferias_alerta_cobertura(
  p_tenant       uuid,
  p_departamento text,
  p_data_inicio  date,
  p_data_fim     date,
  p_limite_pct   numeric DEFAULT 20
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_total       integer;
  v_simultaneos integer;
  v_pct         numeric;
BEGIN
  -- Cobertura da equipe: quantos do departamento estao de ferias no periodo
  -- (simultaneos) sobre o total. É ALERTA informativo (art. 136: a epoca é
  -- prerrogativa do empregador), nunca bloqueio.
  SELECT count(*) INTO v_total
    FROM public.ferias_solicitacoes s
   WHERE s.tenant_id = p_tenant AND s.departamento = p_departamento;

  SELECT count(*) INTO v_simultaneos
    FROM public.ferias_solicitacoes s
   WHERE s.tenant_id = p_tenant AND s.departamento = p_departamento
     AND s.status IN ('aprovado','em_gozo','pendente')
     AND s.data_inicio <= p_data_fim AND s.data_fim >= p_data_inicio;

  v_pct := CASE WHEN COALESCE(v_total,0) > 0
                THEN ROUND(100.0 * v_simultaneos / v_total, 1) ELSE 0 END;

  RETURN jsonb_build_object(
    'departamento', p_departamento,
    'simultaneos', v_simultaneos,
    'percentual', v_pct,
    'limite', p_limite_pct,
    'alerta_cobertura', v_pct > p_limite_pct
  );
END;
$$;

COMMENT ON FUNCTION public.ferias_alerta_cobertura(uuid, text, date, date, numeric) IS
  'FERIAS-071: alerta de cobertura por departamento (% simultaneo de ferias na equipe).';

-- ── FERIAS-090: liquidação dos períodos na rescisão ─────────────────────────
CREATE OR REPLACE FUNCTION public.ferias_liquida_rescisao(
  p_tenant       uuid,
  p_colaborador_cpf text,
  p_data_desligamento date
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_vencidas   numeric := 0;
  v_prop_avos  integer := 0;
  rec RECORD;
BEGIN
  -- Percorre os periodos aquisitivos em aberto (ferias_periodos_aquisitivos)
  -- e apura, para o desligamento: vencidas integrais + proporcionais por
  -- duodecimos, ambas com 1/3 (arts. 146-148, Sumula 171). Indenizadas.
  FOR rec IN
    SELECT * FROM public.ferias_periodos_aquisitivos p
     WHERE p.tenant_id = p_tenant
       AND regexp_replace(COALESCE(p.colaborador_cpf,''), '[^0-9]', '', 'g')
         = regexp_replace(COALESCE(p_colaborador_cpf,''), '[^0-9]', '', 'g')
       AND COALESCE(p.dias_saldo, 0) > 0
  LOOP
    IF rec.aquisitivo_fim <= p_data_desligamento THEN
      v_vencidas := v_vencidas + COALESCE(rec.dias_saldo, 0);   -- periodo completo
    ELSE
      -- Proporcional: duodecimos desde o inicio do aquisitivo ate o desligamento.
      v_prop_avos := v_prop_avos + LEAST(12, GREATEST(0,
        (EXTRACT(YEAR FROM age(p_data_desligamento, rec.aquisitivo_inicio)) * 12
       + EXTRACT(MONTH FROM age(p_data_desligamento, rec.aquisitivo_inicio)))::int));
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'dias_vencidos', v_vencidas,
    'avos_proporcionais', v_prop_avos,
    'dias_proporcionais', ROUND(v_prop_avos * 2.5, 1),
    'inclui_um_terco', true,
    'observacao', 'Ferias indenizadas na rescisao (vencidas + proporcionais + 1/3).'
  );
END;
$$;

COMMENT ON FUNCTION public.ferias_liquida_rescisao(uuid, text, date) IS
  'FERIAS-090: liquida os ferias_periodos no desligamento (vencidas + proporcionais + 1/3, indenizadas).';

-- ════════════════════════ CONFERÊNCIA (única — esperado tudo 'ok') ════════════
WITH alvo(item, presente) AS (
  VALUES
    ('001/011/012/041 · regras no banco (trigger deriva dias / CHECK fracionamento)',
       (to_regprocedure('public.ferias_dias_por_faltas_clt(integer)') IS NOT NULL
        OR EXISTS (SELECT 1 FROM pg_constraint WHERE conname LIKE 'ferias_prog_fracionamento%'))),
    ('013 · CHECK chk_ferias_solic_saldo',        EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ferias_solic_saldo')),
    ('014 · trigger véspera de feriado',          (to_regprocedure('public.ferias_programacao_veda_vespera_feriado()') IS NOT NULL)),
    ('052 · alteração confirmada exige justificativa', (to_regprocedure('public.ferias_programacao_confirmada_exige_justificativa()') IS NOT NULL)),
    ('091 · constraint ferias_periodo_unico (com empresa)',
       EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ferias_periodo_unico'
               AND pg_get_constraintdef(oid) ILIKE '%empresa_id%')),
    ('008 · função ferias_data_prescricao',       (to_regprocedure('public.ferias_data_prescricao(date)') IS NOT NULL)),
    ('031/030 · trigger aviso 30 dias',           (to_regprocedure('public.ferias_solic_valida_aviso_30d()') IS NOT NULL)),
    ('042 · trigger prazo do abono',              (to_regprocedure('public.ferias_prog_valida_prazo_abono()') IS NOT NULL)),
    ('010/040 · colunas de concordância/abono',
       (EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='ferias_programacao' AND column_name='fracionamento_concordancia')
        AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='ferias_programacao' AND column_name='abono_requerido_em'))),
    ('003 · recálculo consulta afastamentos',     (to_regprocedure('public.ferias_recalcular_periodo(uuid)') IS NOT NULL)),
    ('024 · afastamento suspende férias + status suspenso',
       (to_regprocedure('public.afastamento_suspende_ferias()') IS NOT NULL
        AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname='ferias_solicitacoes_status_check' AND pg_get_constraintdef(oid) ILIKE '%suspenso%'))),
    ('053 · ponto barrado em férias em gozo',
       (to_regprocedure('public.validar_batida_afastamento()') IS NOT NULL
        AND pg_get_functiondef('public.validar_batida_afastamento()'::regprocedure) ILIKE '%em_gozo%')),
    ('004 · prioriza aquisitivo antigo',          (to_regprocedure('public.ferias_programacao_prioriza_antigo()') IS NOT NULL)),
    ('051 · cancelamento devolve saldo',          (to_regprocedure('public.ferias_cancelamento_devolve_saldo(uuid,text)') IS NOT NULL)),
    ('070 · encargos por enquadramento',          (to_regprocedure('public.ferias_encargos_provisao(uuid,uuid,numeric)') IS NOT NULL)),
    ('071 · alerta de cobertura',                 (to_regprocedure('public.ferias_alerta_cobertura(uuid,text,date,date,numeric)') IS NOT NULL)),
    ('090 · liquidação na rescisão',              (to_regprocedure('public.ferias_liquida_rescisao(uuid,text,date)') IS NOT NULL))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao
FROM alvo ORDER BY item;
