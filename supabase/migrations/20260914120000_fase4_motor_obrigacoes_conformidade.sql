-- ============================================================================
-- Fase 4 (motores) — Obrigações automáticas de conformidade (REGRA-001..006).
--
-- Hoje as obrigações do cadastro (déficit de cota PcD, CIPA não constituída,
-- SESMT inexistente, FAP alto, TAC declarado, grau de risco elevado) só entram
-- no painel de conformidade quando alguém clica em "Gerar Obrigações" na tela.
-- Sem o clique, a irregularidade fica invisível.
--
-- Este motor passa a MANTER a conformidade em dia sozinho: quando o cadastro da
-- empresa entra numa condição irregular, a obrigação correspondente é aberta
-- (origem 'cadastro_empresa', status 'pendente'); quando a condição é sanada, a
-- obrigação AINDA PENDENTE é retirada — sem nunca mexer no que um humano já
-- moveu (em_adequacao/conforme/etc.).
--
-- REGRA-001: déficit de cota de PcD (Lei 8.213/91, art. 93).
-- REGRA-002: CIPA obrigatória e não constituída (NR-05).
-- REGRA-003: SESMT obrigatório e inexistente (NR-04) — criticidade crítica.
-- REGRA-004: FAP acima de 1,5 (plano de redução).
-- REGRA-005: TAC declarado (cumprimento — criticidade crítica).
-- REGRA-006: grau de risco 3 ou 4 (avaliação de impacto).
-- ============================================================================

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
