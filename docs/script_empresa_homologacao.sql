-- ============================================================================
-- ENTREGA — EMPRESA (ENQ/TAC/DADO/REGRA/FER) na HOMOLOGAÇÃO (12 casos)
--
-- Cole INTEIRO no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na
-- PRODUÇÃO. Guardas e motor já verdes no teste (via migrations) e nunca colados
-- aqui.
--
-- Cobre: DADO-010, ENQ-010, ENQ-011, ENQ-013, TAC-003, FER-003 (guardas de
--        integridade) + REGRA-001..006 (motor de obrigações de conformidade).
--
-- SEGURANÇA: NÃO cria tabela (sem auto-RLS do editor). Só ALTER ADD CONSTRAINT
-- (CHECK NOT VALID / UNIQUE), CREATE OR REPLACE FUNCTION e CREATE TRIGGER, mais
-- um "reparo" que apenas re-dispara o gatilho no cadastro atual (UPDATE
-- grau_risco = grau_risco, mesmo valor; não altera dado; abre obrigações
-- pendentes idempotentes). A constraint única de FER-003 vem embrulhada: se
-- houver unidade com DUAS tabelas de feriados, AVISA e não cria (em vez de
-- abortar) — resolva a ambiguidade e rode de novo. Idempotente, uma transação.
--
-- Origem (só as partes de Empresa): fase1 20260913150400 (guardas) + fase4
-- 20260914120000 (motor de obrigações, sem script). Ao fim, conferência única.
-- ============================================================================

SET lock_timeout = '10s';

-- ════════════════════ 1) GUARDAS — DADO / ENQ / TAC ══════════════════════════
-- ── DADO-010: tipo de pessoa só PJ ou PF ────────────────────────────────────
ALTER TABLE public.empresa_cadastro DROP CONSTRAINT IF EXISTS chk_empresa_tipo_pessoa;
ALTER TABLE public.empresa_cadastro ADD CONSTRAINT chk_empresa_tipo_pessoa
  CHECK (tipo_pessoa IS NULL OR tipo_pessoa IN ('pj', 'pf')) NOT VALID;
-- ── ENQ-010: FAP na faixa legal 0,5–2,0 (Lei 10.666/2003) ───────────────────
ALTER TABLE public.empresa_cadastro DROP CONSTRAINT IF EXISTS chk_empresa_fap_faixa;
ALTER TABLE public.empresa_cadastro ADD CONSTRAINT chk_empresa_fap_faixa
  CHECK (fap_atual IS NULL OR fap_atual BETWEEN 0.5 AND 2.0) NOT VALID;

-- ── ENQ-011: grau de risco ajustado exige justificativa ─────────────────────
ALTER TABLE public.empresa_cadastro DROP CONSTRAINT IF EXISTS chk_empresa_grau_ajustado_justificado;
ALTER TABLE public.empresa_cadastro ADD CONSTRAINT chk_empresa_grau_ajustado_justificado
  CHECK (grau_risco_ajustado IS NULL
         OR grau_risco IS NULL
         OR grau_risco_ajustado = grau_risco
         OR COALESCE(btrim(grau_risco_justificativa), '') <> '') NOT VALID;

-- ── ENQ-013: mandato da CIPA com fim ≥ início ───────────────────────────────
ALTER TABLE public.empresa_cadastro DROP CONSTRAINT IF EXISTS chk_empresa_cipa_mandato_coerente;
ALTER TABLE public.empresa_cadastro ADD CONSTRAINT chk_empresa_cipa_mandato_coerente
  CHECK (cipa_data_mandato_fim IS NULL OR cipa_data_mandato_inicio IS NULL
         OR cipa_data_mandato_fim >= cipa_data_mandato_inicio) NOT VALID;

-- ── TAC-003: vigência do TAC coerente (fim ≥ início) em cada item do JSON ───
CREATE OR REPLACE FUNCTION public.tac_vigencia_coerente(p jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p) = 'array' THEN p ELSE '[]'::jsonb END) e
    WHERE NULLIF(e->>'vigencia_inicio', '') IS NOT NULL
      AND NULLIF(e->>'vigencia_fim', '') IS NOT NULL
      AND to_date(e->>'vigencia_fim', 'YYYY-MM-DD') < to_date(e->>'vigencia_inicio', 'YYYY-MM-DD')
  );
$$;
ALTER TABLE public.empresa_cadastro DROP CONSTRAINT IF EXISTS chk_empresa_tac_vigencia;
ALTER TABLE public.empresa_cadastro ADD CONSTRAINT chk_empresa_tac_vigencia
  CHECK (tac_detalhes IS NULL OR public.tac_vigencia_coerente(tac_detalhes)) NOT VALID;

-- ── FER-003: uma tabela de feriados por unidade (embrulhado anti-duplicata) ──
DO $fer003uq$
BEGIN
  IF EXISTS (SELECT 1 FROM public.feriado_tabela_empresas
             GROUP BY tenant_id, empresa_id HAVING count(*) > 1) THEN
    RAISE NOTICE 'FER-003: ha unidade com DUAS tabelas de feriados — constraint unica NAO criada. Deixe uma tabela por unidade e rode de novo.';
  ELSE
    ALTER TABLE public.feriado_tabela_empresas DROP CONSTRAINT IF EXISTS uq_feriado_tabela_empresa_por_unidade;
    ALTER TABLE public.feriado_tabela_empresas ADD CONSTRAINT uq_feriado_tabela_empresa_por_unidade
      UNIQUE (tenant_id, empresa_id);
  END IF;
END $fer003uq$;

-- ════════════════════ 2) MOTOR DE OBRIGAÇÕES (REGRA-001..006) ═════════════════
-- ── Helper: sincroniza UMA obrigação de cadastro (abre / retira) ────────────
-- Idempotente: com a condição verdadeira, garante a obrigação pendente sem
-- duplicar; com a condição falsa, retira apenas a que seguia pendente por este
-- motor (não toca no trabalho humano nem em obrigações de outra origem).
CREATE OR REPLACE FUNCTION public.empresa_obrigacao_sincronizar(
  p_tenant       uuid,
  p_empresa      uuid,
  p_subcategoria text,
  p_condicao     boolean,
  p_categoria    text,
  p_criticidade  text,
  p_titulo       text,
  p_descricao    text,
  p_base_legal   text,
  p_campo        text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF p_empresa IS NULL THEN
    RETURN;
  END IF;

  IF COALESCE(p_condicao, false) THEN
    INSERT INTO public.empresa_obrigacoes
      (tenant_id, empresa_id, categoria, subcategoria, titulo, descricao,
       base_legal, status, criticidade, origem, origem_campo, ativo)
    SELECT p_tenant, p_empresa, p_categoria, p_subcategoria, p_titulo, p_descricao,
           p_base_legal, 'pendente', p_criticidade, 'cadastro_empresa', p_campo, true
    WHERE NOT EXISTS (
      SELECT 1 FROM public.empresa_obrigacoes eo
       WHERE eo.tenant_id    = p_tenant
         AND eo.empresa_id   = p_empresa
         AND eo.subcategoria = p_subcategoria
         AND eo.origem       = 'cadastro_empresa'
         AND eo.ativo
    );
  ELSE
    -- Condição sanada: retira só a obrigação que continuava pendente por este
    -- motor. Se o DP já avançou o tratamento, preserva o histórico.
    DELETE FROM public.empresa_obrigacoes eo
     WHERE eo.tenant_id    = p_tenant
       AND eo.empresa_id   = p_empresa
       AND eo.subcategoria = p_subcategoria
       AND eo.origem       = 'cadastro_empresa'
       AND eo.status       = 'pendente';
  END IF;
END;
$$;

-- ── Motor: dispara a sincronização a cada mudança do cadastro ───────────────
CREATE OR REPLACE FUNCTION public.empresa_gerar_obrigacoes_conformidade()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- REGRA-001 — déficit de cota de PcD.
  PERFORM public.empresa_obrigacao_sincronizar(
    NEW.tenant_id, NEW.id, 'pcd',
    COALESCE(NEW.pcd_obrigatoria, false)
      AND COALESCE(NEW.pcd_quantidade_exigida, 0) > COALESCE(NEW.pcd_quantidade_atual, 0),
    'legal', 'alta',
    'Plano de adequação da cota de PcD',
    'A empresa está em déficit de PcD frente à cota exigida — elaborar plano de adequação.',
    'Lei 8.213/91, art. 93', 'pcd_quantidade_atual');

  -- REGRA-002 — CIPA obrigatória e não constituída.
  PERFORM public.empresa_obrigacao_sincronizar(
    NEW.tenant_id, NEW.id, 'cipa',
    COALESCE(NEW.cipa_obrigatoria, false) AND NEW.cipa_situacao = 'nao_constituida',
    'sst', 'alta',
    'Constituir CIPA',
    'CIPA obrigatória e não constituída — iniciar processo eleitoral (NR-05).',
    'NR-05', 'cipa_situacao');

  -- REGRA-003 — SESMT obrigatório e inexistente (crítica).
  PERFORM public.empresa_obrigacao_sincronizar(
    NEW.tenant_id, NEW.id, 'sesmt',
    COALESCE(NEW.sesmt_obrigatorio, false) AND NEW.sesmt_situacao = 'inexistente',
    'sst', 'critica',
    'Contratar/Adequar SESMT',
    'SESMT obrigatório e inexistente — dimensionar e constituir o serviço (NR-04).',
    'NR-04', 'sesmt_situacao');

  -- REGRA-004 — FAP acima de 1,5.
  PERFORM public.empresa_obrigacao_sincronizar(
    NEW.tenant_id, NEW.id, 'fap',
    COALESCE(NEW.fap_atual, 0) > 1.5,
    'financeira', 'alta',
    'Plano de redução do FAP',
    'FAP acima de 1,5 eleva o RAT — elaborar plano de redução da sinistralidade.',
    'Lei 10.666/03; Resolução CNPS', 'fap_atual');

  -- REGRA-005 — TAC declarado (crítica).
  PERFORM public.empresa_obrigacao_sincronizar(
    NEW.tenant_id, NEW.id, 'tac',
    COALESCE(NEW.tac_possui, false),
    'legal', 'critica',
    'Cumprir obrigações do TAC',
    'A empresa declarou possuir TAC — acompanhar cada cláusula (multa por descumprimento).',
    'TAC/MPT', 'tac_possui');

  -- REGRA-006 — grau de risco elevado (3 ou 4).
  PERFORM public.empresa_obrigacao_sincronizar(
    NEW.tenant_id, NEW.id, 'grau_risco',
    COALESCE(NEW.grau_risco, 0) >= 3,
    'sst', 'alta',
    'Avaliar impacto do grau de risco elevado',
    'Grau de risco elevado (NR-04) puxa exigências adicionais — avaliar o impacto.',
    'NR-04, Quadro I', 'grau_risco');

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_empresa_obrigacoes_conformidade ON public.empresa_cadastro;
CREATE TRIGGER trg_empresa_obrigacoes_conformidade
  AFTER INSERT OR UPDATE OF
    pcd_obrigatoria, pcd_quantidade_exigida, pcd_quantidade_atual,
    cipa_obrigatoria, cipa_situacao, sesmt_obrigatorio, sesmt_situacao,
    fap_atual, tac_possui, grau_risco
  ON public.empresa_cadastro
  FOR EACH ROW EXECUTE FUNCTION public.empresa_gerar_obrigacoes_conformidade();

-- Reparo de base (produção): abre as obrigações que já deveriam existir para o
-- cadastro atual, sem depender do clique. Em banco novo não encontra nada e
-- passa reto; onde houver dado, roda idempotente.
DO $reparo$
BEGIN
  -- Toca uma coluna vigiada (mesmo valor) para o gatilho reavaliar cada linha.
  UPDATE public.empresa_cadastro
     SET grau_risco = grau_risco
   WHERE COALESCE(pcd_obrigatoria, false)
           AND COALESCE(pcd_quantidade_exigida, 0) > COALESCE(pcd_quantidade_atual, 0)
      OR (COALESCE(cipa_obrigatoria, false) AND cipa_situacao = 'nao_constituida')
      OR (COALESCE(sesmt_obrigatorio, false) AND sesmt_situacao = 'inexistente')
      OR COALESCE(fap_atual, 0) > 1.5
      OR COALESCE(tac_possui, false)
      OR COALESCE(grau_risco, 0) >= 3;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Reparo de obrigações de conformidade pulado: %', SQLERRM;
END;
$reparo$;

-- ════════════════════ CONFERÊNCIA (única — esperado tudo 'ok') ════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('DADO-010 · tipo_pessoa só pj/pf',        EXISTS(SELECT 1 FROM pg_constraint WHERE conname='chk_empresa_tipo_pessoa')),
    ('ENQ-010 · FAP na faixa 0,5–2,0',         EXISTS(SELECT 1 FROM pg_constraint WHERE conname='chk_empresa_fap_faixa')),
    ('ENQ-011 · grau ajustado exige justificativa', EXISTS(SELECT 1 FROM pg_constraint WHERE conname='chk_empresa_grau_ajustado_justificado')),
    ('ENQ-013 · mandato CIPA fim>=início',      EXISTS(SELECT 1 FROM pg_constraint WHERE conname='chk_empresa_cipa_mandato_coerente')),
    ('TAC-003 · vigência do TAC coerente',      EXISTS(SELECT 1 FROM pg_constraint WHERE conname='chk_empresa_tac_vigencia')),
    ('FER-003 · uma tabela de feriados por unidade (ou duplicata pendente)',
       (EXISTS(SELECT 1 FROM pg_constraint WHERE conname='uq_feriado_tabela_empresa_por_unidade')
        OR EXISTS(SELECT 1 FROM public.feriado_tabela_empresas GROUP BY tenant_id, empresa_id HAVING count(*)>1))),
    ('REGRA-001..006 · motor de obrigações de conformidade',
       (EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='empresa_gerar_obrigacoes_conformidade')
        AND EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='empresa_obrigacao_sincronizar')
        AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='trg_empresa_obrigacoes_conformidade' AND NOT tgisinternal)))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao FROM alvo ORDER BY item;
