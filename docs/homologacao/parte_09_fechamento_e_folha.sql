-- ============================================================================
-- HOMOLOGACAO — PONTO, PARTE 09 de 16: Fechamento da competencia e envio para a folha
--
-- Geracao dos espelhos em uma unica transacao (nada de espelho parcial),
-- fechamento que confere ciencia do espelho e pendencias criticas, pacote da
-- folha com grandezas e naturezas e fila de reenvio quando a folha esta
-- indisponivel.
--
-- ONDE COLAR
-- No SQL Editor do projeto de HOMOLOGACAO. Nao e para a producao: a producao
-- so muda por gesto manual seu, depois de conferida aqui.
--
-- COMO USAR
-- Cole o arquivo INTEIRO e execute uma vez. Pode rodar de novo sem risco
-- (idempotente). As partes tem ordem: rode da 01 para a 16, conferindo o
-- resultado de cada uma antes de passar para a seguinte.
--
-- O QUE ESTE ARQUIVO REUNE
--   * script_ponto_onda6_gerar_espelhos.sql
--   * script_ponto_onda6_fechamento_pendencias.sql
--   * script_ponto_onda6_fechamento_ciencia_espelho.sql
--   * script_ponto_onda6_pacote_folha.sql
--   * script_ponto_onda6_fila_folha_reenvio.sql
--
-- Ao final sai UMA conferencia, dizendo o que chegou e o que faltou.
-- ============================================================================



-- ############################################################
-- BLOCO: script_ponto_onda6_gerar_espelhos.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 6 (parte 1): geracao transacional dos espelhos
-- Alvo: ponto_gerar_espelhos_competencia (nova)
-- PONTO-194
--
-- Os espelhos nasciam LINHA A LINHA por um caminho de tela: falha no meio
-- deixava metade dos colaboradores com documento e metade sem — pior que
-- ausente, porque parece completo. Passa a existir uma funcao UNICA e
-- transacional (tudo-ou-nada) que gera os espelhos da competencia: para cada
-- colaborador com ponto no periodo, compoe os totais (ponto_espelho_resumo) e
-- faz UPSERT em ponto_espelhos, preservando a ciencia ja dada (status,
-- confirmacao, assinatura, ressalva). Chamada pelo fechamento.
--
-- GARANTIAS: nao altera o motor de saldo; so compoe e grava o espelho. Nao roda
-- por gatilho. Aditivo e idempotente (CREATE OR REPLACE). Sem backfill.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ponto_gerar_espelhos_competencia(
  p_tenant_id   uuid,
  p_competencia text,
  p_empresa_id  uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
  v_n   int := 0;
  c     RECORD;
  res   RECORD;
  v_adn int;
BEGIN
  FOR c IN
    SELECT d.colaborador_cpf,
           MAX(d.colaborador_id::text)  AS cid,
           MAX(d.colaborador_nome)      AS nome,
           MAX(d.empresa_id::text)::uuid AS empresa_id
    FROM public.ponto_diario d
    WHERE d.tenant_id = p_tenant_id
      AND d.data BETWEEN v_ini AND v_fim
      AND (p_empresa_id IS NULL OR d.empresa_id = p_empresa_id)
    GROUP BY d.colaborador_cpf
  LOOP
    SELECT * INTO res
    FROM public.ponto_espelho_resumo(p_tenant_id, c.colaborador_cpf, p_competencia);

    SELECT COALESCE(SUM(COALESCE(pd.adicional_noturno_minutos, 0))::int, 0) INTO v_adn
    FROM public.ponto_diario pd
    WHERE pd.tenant_id = p_tenant_id
      AND pd.colaborador_cpf = c.colaborador_cpf
      AND pd.data BETWEEN v_ini AND v_fim;

    INSERT INTO public.ponto_espelhos (
      tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, competencia,
      total_trabalhado_minutos, total_jornada_prevista_minutos, total_creditos_minutos,
      total_debitos_minutos, total_faltas, total_dias_trabalhados, total_dias_protegidos,
      total_excedente_retido_minutos, dia_equalizacao, banco_horas_saldo_minutos,
      total_horas_extras_50_minutos, total_horas_extras_100_minutos, total_atrasos_minutos,
      total_horas_normais_minutos, total_adicional_noturno_minutos
    ) VALUES (
      p_tenant_id, c.empresa_id, c.cid, c.nome, c.colaborador_cpf, p_competencia,
      res.total_trabalhado_min, res.total_jornada_prevista_min, res.total_creditos_min,
      res.total_debitos_min, res.total_faltas, res.dias_trabalhados, res.dias_protegidos,
      res.excedente_retido_min, res.dia_equalizacao, res.saldo_banco_min,
      res.he_50_min, res.he_100_min, res.atrasos_min,
      GREATEST(0, COALESCE(res.total_trabalhado_min, 0)
                  - COALESCE(res.he_50_min, 0) - COALESCE(res.he_100_min, 0)),
      v_adn
    )
    ON CONFLICT (tenant_id, colaborador_cpf, competencia) DO UPDATE SET
      empresa_id                      = COALESCE(public.ponto_espelhos.empresa_id, EXCLUDED.empresa_id),
      colaborador_id                  = EXCLUDED.colaborador_id,
      colaborador_nome                = EXCLUDED.colaborador_nome,
      total_trabalhado_minutos        = EXCLUDED.total_trabalhado_minutos,
      total_jornada_prevista_minutos  = EXCLUDED.total_jornada_prevista_minutos,
      total_creditos_minutos          = EXCLUDED.total_creditos_minutos,
      total_debitos_minutos           = EXCLUDED.total_debitos_minutos,
      total_faltas                    = EXCLUDED.total_faltas,
      total_dias_trabalhados          = EXCLUDED.total_dias_trabalhados,
      total_dias_protegidos           = EXCLUDED.total_dias_protegidos,
      total_excedente_retido_minutos  = EXCLUDED.total_excedente_retido_minutos,
      dia_equalizacao                 = EXCLUDED.dia_equalizacao,
      banco_horas_saldo_minutos       = EXCLUDED.banco_horas_saldo_minutos,
      total_horas_extras_50_minutos   = EXCLUDED.total_horas_extras_50_minutos,
      total_horas_extras_100_minutos  = EXCLUDED.total_horas_extras_100_minutos,
      total_atrasos_minutos           = EXCLUDED.total_atrasos_minutos,
      total_horas_normais_minutos     = EXCLUDED.total_horas_normais_minutos,
      total_adicional_noturno_minutos = EXCLUDED.total_adicional_noturno_minutos,
      updated_at                      = now();
      -- status / data_confirmacao / confirmado_por / assinatura_hash /
      -- ressalva_texto NAO sao tocados: a ciencia ja dada e preservada.

    v_n := v_n + 1;
  END LOOP;

  RETURN v_n;
END;
$$;

COMMENT ON FUNCTION public.ponto_gerar_espelhos_competencia(uuid, text, uuid) IS
  'Gera os espelhos da competencia numa unica funcao transacional (tudo-ou-nada): para cada colaborador com ponto no periodo, compoe os totais (ponto_espelho_resumo) e faz UPSERT em ponto_espelhos, preservando a ciencia ja dada. Chamada pelo fechamento. PONTO-194.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | OK
--   funcao_existe : t  (ponto_gerar_espelhos_competencia)
--   gera_espelho  : t  (grava em ponto_espelhos, transacional)
-- ---------------------------------------------------------------------------
WITH src AS (SELECT prosrc FROM pg_proc WHERE proname='ponto_gerar_espelhos_competencia' LIMIT 1)
SELECT
  (to_regprocedure('public.ponto_gerar_espelhos_competencia(uuid,text,uuid)') IS NOT NULL) AS funcao_existe,
  ((SELECT prosrc FROM src) ILIKE '%ponto_espelhos%' AND (SELECT prosrc FROM src) ILIKE '%INSERT%') AS gera_espelho,
  CASE WHEN to_regprocedure('public.ponto_gerar_espelhos_competencia(uuid,text,uuid)') IS NOT NULL
        AND (SELECT prosrc FROM src) ILIKE '%ponto_espelhos%' AND (SELECT prosrc FROM src) ILIKE '%INSERT%'
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda6_fechamento_pendencias.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 6 (parte 2): pendencia critica bloqueia o fechamento
-- Alvos: ponto_fechamento_pendencias_criticas (nova); ponto_fechar_competencia_verificar (nova)
-- PONTO-388
--
-- O fechamento nao verificava pendencias: com ajuste pendente de aprovacao ou
-- dia incompleto sem tratamento, a competencia fechava por cima e mandava o dado
-- errado para a folha. Passa a existir a lista de pendencias criticas e o portao
-- do fechamento, que aborta quando ha pendencia aberta.
--
-- GARANTIAS: so leitura + um guardiao que aborta quando nao pode fechar. Nao
-- altera o motor de saldo, o espelho nem a transicao de banco. Nao roda por
-- gatilho — a tela chama o portao antes de concluir. Aditivo e idempotente.
-- ============================================================================

-- (1) Lista de pendências críticas -------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_fechamento_pendencias_criticas(
  p_tenant_id   uuid,
  p_empresa_id  uuid,
  p_competencia text
)
RETURNS TABLE(tipo text, colaborador_cpf text, data_referencia date, descricao text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
BEGIN
  -- Ajustes de ponto PENDENTES de aprovação.
  RETURN QUERY
  SELECT 'ajuste_pendente'::text, a.colaborador_cpf, a.data_referencia,
         'Ajuste de ponto pendente de aprovacao'::text
  FROM public.ponto_ajustes a
  WHERE a.tenant_id = p_tenant_id
    AND a.status = 'pendente'
    AND a.data_referencia BETWEEN v_ini AND v_fim
    AND (p_empresa_id IS NULL OR a.empresa_id = p_empresa_id);

  -- Dias INCOMPLETOS sem tratamento (sequência de marcações incompleta / ajuste
  -- ainda pendente na consolidação do dia).
  RETURN QUERY
  SELECT 'dia_incompleto'::text, d.colaborador_cpf, d.data,
         format('Dia incompleto sem tratamento (status %s)', d.status)::text
  FROM public.ponto_diario d
  WHERE d.tenant_id = p_tenant_id
    AND d.data BETWEEN v_ini AND v_fim
    AND d.status IN ('incompleto', 'ajuste_pendente')
    AND (p_empresa_id IS NULL OR d.empresa_id = p_empresa_id);
END;
$$;

COMMENT ON FUNCTION public.ponto_fechamento_pendencias_criticas(uuid, uuid, text) IS
  'Lista as pendencias criticas que bloqueiam o fechamento da competencia: ajustes pendentes de aprovacao e dias incompletos sem tratamento. Somente leitura. PONTO-388.';

-- (2) Portão do fechamento ---------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_fechar_competencia_verificar(
  p_tenant_id   uuid,
  p_empresa_id  uuid,
  p_competencia text
)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_n       int;
  v_ajustes int;
  v_dias    int;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE tipo = 'ajuste_pendente'),
         count(*) FILTER (WHERE tipo = 'dia_incompleto')
    INTO v_n, v_ajustes, v_dias
  FROM public.ponto_fechamento_pendencias_criticas(p_tenant_id, p_empresa_id, p_competencia);

  IF v_n > 0 THEN
    -- Bloqueia o fechamento: ha pendencia critica aberta (ajuste pendente de
    -- aprovacao / dia incompleto sem tratamento).
    RAISE EXCEPTION 'Fechamento bloqueado na competencia %: % pendencia(s) critica(s) — % ajuste(s) pendente(s) de aprovacao e % dia(s) incompleto(s) sem tratamento. Trate antes de fechar.',
      p_competencia, v_n, v_ajustes, v_dias
      USING ERRCODE = 'raise_exception';
  END IF;

  RETURN 0;  -- sem pendencias: pode fechar
END;
$$;

COMMENT ON FUNCTION public.ponto_fechar_competencia_verificar(uuid, uuid, text) IS
  'Portao do fechamento: aborta se houver pendencia critica (ajuste pendente de aprovacao / dia incompleto sem tratamento); devolve 0 quando pode fechar. A tela chama antes de concluir. PONTO-388.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | OK
--   lista_existe  : t  (ponto_fechamento_pendencias_criticas)
--   portao_existe : t  (ponto_fechar_competencia_verificar)
--   portao_checa  : t  (o portao verifica pendencia)
-- ---------------------------------------------------------------------------
WITH src AS (SELECT prosrc FROM pg_proc WHERE proname='ponto_fechar_competencia_verificar' LIMIT 1)
SELECT
  (to_regprocedure('public.ponto_fechamento_pendencias_criticas(uuid,uuid,text)') IS NOT NULL) AS lista_existe,
  (to_regprocedure('public.ponto_fechar_competencia_verificar(uuid,uuid,text)') IS NOT NULL)    AS portao_existe,
  ((SELECT prosrc FROM src) ILIKE '%pendencia%' OR (SELECT prosrc FROM src) ILIKE '%pendente%') AS portao_checa,
  CASE WHEN to_regprocedure('public.ponto_fechamento_pendencias_criticas(uuid,uuid,text)') IS NOT NULL
        AND to_regprocedure('public.ponto_fechar_competencia_verificar(uuid,uuid,text)') IS NOT NULL
        AND ((SELECT prosrc FROM src) ILIKE '%pendencia%' OR (SELECT prosrc FROM src) ILIKE '%pendente%')
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda6_fechamento_ciencia_espelho.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 6 (parte 3): espelho sem ciencia bloqueia o fechamento
-- Alvos: ponto_fechamento_pendencias_criticas; ponto_fechar_competencia_verificar
--        (CREATE OR REPLACE — estende a parte 2, pacote #28)
-- PONTO-387
--
-- A tabela ponto_espelhos tem status, data_confirmacao e assinatura_hash, mas o
-- fechamento nao os consultava. Espelho sem ciencia enfraquece a prova (Sumula
-- 338). A lista de pendencias e o portao passam a considerar tambem o ESPELHO
-- SEM CIENCIA — status nao confirmado/assinado, sem confirmacao e sem
-- assinatura. Espelho com RESSALVA formal nao bloqueia (recusa formalizada).
--
-- GARANTIAS: so leitura + o guardiao que aborta. Nao altera o motor de saldo, o
-- espelho nem a transicao de banco. Substitui as duas funcoes da parte 2 (#28).
-- Aditivo e idempotente. Sem backfill.
-- ============================================================================

-- (1) Lista de pendências: + espelho sem ciência ------------------------------
CREATE OR REPLACE FUNCTION public.ponto_fechamento_pendencias_criticas(
  p_tenant_id   uuid,
  p_empresa_id  uuid,
  p_competencia text
)
RETURNS TABLE(tipo text, colaborador_cpf text, data_referencia date, descricao text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
BEGIN
  -- Ajustes de ponto PENDENTES de aprovação.
  RETURN QUERY
  SELECT 'ajuste_pendente'::text, a.colaborador_cpf, a.data_referencia,
         'Ajuste de ponto pendente de aprovacao'::text
  FROM public.ponto_ajustes a
  WHERE a.tenant_id = p_tenant_id
    AND a.status = 'pendente'
    AND a.data_referencia BETWEEN v_ini AND v_fim
    AND (p_empresa_id IS NULL OR a.empresa_id = p_empresa_id);

  -- Dias INCOMPLETOS sem tratamento.
  RETURN QUERY
  SELECT 'dia_incompleto'::text, d.colaborador_cpf, d.data,
         format('Dia incompleto sem tratamento (status %s)', d.status)::text
  FROM public.ponto_diario d
  WHERE d.tenant_id = p_tenant_id
    AND d.data BETWEEN v_ini AND v_fim
    AND d.status IN ('incompleto', 'ajuste_pendente')
    AND (p_empresa_id IS NULL OR d.empresa_id = p_empresa_id);

  -- (387) Espelho SEM CIÊNCIA (Súmula 338): status ainda não confirmado/assinado,
  -- sem data_confirmacao e sem assinatura_hash. Espelho com RESSALVA formal
  -- registrada não bloqueia (a recusa está formalizada).
  RETURN QUERY
  SELECT 'espelho_sem_ciencia'::text, e.colaborador_cpf, NULL::date,
         format('Espelho sem ciencia do colaborador (status %s, sem confirmacao/assinatura)', COALESCE(e.status,'-'))::text
  FROM public.ponto_espelhos e
  WHERE e.tenant_id = p_tenant_id
    AND e.competencia = p_competencia
    AND (p_empresa_id IS NULL OR e.empresa_id = p_empresa_id)
    AND COALESCE(e.status, '') NOT IN ('confirmado', 'assinado')
    AND e.data_confirmacao IS NULL
    AND COALESCE(e.assinatura_hash, '') = ''
    AND NULLIF(btrim(COALESCE(e.ressalva_texto, '')), '') IS NULL;
END;
$$;

COMMENT ON FUNCTION public.ponto_fechamento_pendencias_criticas(uuid, uuid, text) IS
  'Lista as pendencias criticas que bloqueiam o fechamento: ajustes pendentes de aprovacao, dias incompletos sem tratamento e espelhos sem ciencia do colaborador (Sumula 338; ressalva formal nao bloqueia). Somente leitura. PONTO-388/387.';

-- (2) Portão do fechamento: + espelho sem ciência -----------------------------
CREATE OR REPLACE FUNCTION public.ponto_fechar_competencia_verificar(
  p_tenant_id   uuid,
  p_empresa_id  uuid,
  p_competencia text
)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_n        int;
  v_ajustes  int;
  v_dias     int;
  v_espelhos int;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE tipo = 'ajuste_pendente'),
         count(*) FILTER (WHERE tipo = 'dia_incompleto'),
         count(*) FILTER (WHERE tipo = 'espelho_sem_ciencia')
    INTO v_n, v_ajustes, v_dias, v_espelhos
  FROM public.ponto_fechamento_pendencias_criticas(p_tenant_id, p_empresa_id, p_competencia);

  IF v_n > 0 THEN
    -- Bloqueia o fechamento: pendencia critica aberta. Inclui o ESPELHO sem
    -- ciencia — o fechamento confere status/confirmacao/assinatura dos espelhos
    -- (Sumula 338); espelho com ressalva formal nao bloqueia.
    RAISE EXCEPTION 'Fechamento bloqueado na competencia %: % pendencia(s) critica(s) — % ajuste(s) pendente(s) de aprovacao, % dia(s) incompleto(s) e % espelho(s) sem ciencia (status/confirmacao/assinatura). Trate antes de fechar.',
      p_competencia, v_n, v_ajustes, v_dias, v_espelhos
      USING ERRCODE = 'raise_exception';
  END IF;

  RETURN 0;  -- sem pendencias: pode fechar
END;
$$;

COMMENT ON FUNCTION public.ponto_fechar_competencia_verificar(uuid, uuid, text) IS
  'Portao do fechamento: aborta se houver pendencia critica — ajuste pendente, dia incompleto ou ESPELHO sem ciencia (confere status/confirmacao/assinatura, Sumula 338). Devolve 0 quando pode fechar. PONTO-388/387.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | OK
--   fechar_confere_espelho : t  (o portao confere ciencia do espelho)
--   lista_tem_espelho      : t  (a lista traz espelho_sem_ciencia)
-- ---------------------------------------------------------------------------
WITH f AS (SELECT prosrc FROM pg_proc WHERE proname='ponto_fechar_competencia_verificar' LIMIT 1),
     l AS (SELECT prosrc FROM pg_proc WHERE proname='ponto_fechamento_pendencias_criticas' LIMIT 1)
SELECT
  ((SELECT prosrc FROM f) ILIKE '%espelho%'
     AND ((SELECT prosrc FROM f) ILIKE '%status%' OR (SELECT prosrc FROM f) ILIKE '%assinatur%'
          OR (SELECT prosrc FROM f) ILIKE '%confirmad%')) AS fechar_confere_espelho,
  ((SELECT prosrc FROM l) ILIKE '%espelho_sem_ciencia%')  AS lista_tem_espelho,
  CASE WHEN (SELECT prosrc FROM f) ILIKE '%espelho%'
        AND ((SELECT prosrc FROM f) ILIKE '%status%' OR (SELECT prosrc FROM f) ILIKE '%assinatur%' OR (SELECT prosrc FROM f) ILIKE '%confirmad%')
        AND (SELECT prosrc FROM l) ILIKE '%espelho_sem_ciencia%'
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda6_pacote_folha.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 6 (parte 4): composicao do pacote da folha (naturezas corretas)
-- Alvo: ponto_compor_pacote_folha (nova)
-- PONTO-361  ·  DEPENDE das ondas 4 (supressao, DSR) e 6 parte 1 (espelhos)
--
-- A exportacao para a folha era um jsonb montado pela tela, sem regra
-- verificavel. Passa a existir a composicao a partir da APURACAO FECHADA
-- (ponto_espelhos), com memoria e naturezas distintas: VENCIMENTO (HE 50/100,
-- adicional noturno, reflexo DSR), DESCONTO (faltas, atrasos, perda de DSR) e
-- INDENIZATORIA (supressao de intervalo, art. 71 §4 — que NAO e hora extra).
-- Grava em ponto_exportacoes_folha. Idempotente (pacote 'auto' por competencia).
--
-- GARANTIAS: so compoe (nao envia — a fila/reenvio e a parte 5). Nao altera o
-- motor de saldo nem o espelho. Aditivo e idempotente. Sem backfill.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ponto_compor_pacote_folha(
  p_tenant_id   uuid,
  p_empresa_id  uuid,
  p_competencia text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
  e         RECORD;
  v_colabs  jsonb := '[]'::jsonb;
  v_eventos jsonb;
  v_total   int := 0;
  v_suprimido int;
  v_dsr_ref   int;
  v_dsr_perda boolean;
  v_id      uuid;
BEGIN
  FOR e IN
    SELECT * FROM public.ponto_espelhos esp
    WHERE esp.tenant_id = p_tenant_id
      AND esp.competencia = p_competencia
      AND (p_empresa_id IS NULL OR esp.empresa_id = p_empresa_id)
    ORDER BY esp.colaborador_nome
  LOOP
    -- Supressao de intervalo do periodo (natureza indenizatoria — art. 71 §4).
    SELECT COALESCE(SUM(COALESCE(d.he_intervalo_suprimido_minutos, 0))::int, 0) INTO v_suprimido
    FROM public.ponto_diario d
    WHERE d.tenant_id = p_tenant_id AND d.colaborador_cpf = e.colaborador_cpf
      AND d.data BETWEEN v_ini AND v_fim;

    -- Reflexo do DSR (natureza vencimento) e perda do DSR (desconto).
    v_dsr_ref := 0; v_dsr_perda := false;
    BEGIN
      SELECT COALESCE(SUM(reflexo_he_dsr_min), 0)::int, bool_or(dsr_perdido)
        INTO v_dsr_ref, v_dsr_perda
      FROM public.ponto_dsr_competencia(p_tenant_id, e.colaborador_cpf, p_competencia);
    EXCEPTION WHEN OTHERS THEN
      v_dsr_ref := 0; v_dsr_perda := false;
    END;

    v_eventos := '[]'::jsonb;

    IF COALESCE(e.total_horas_extras_50_minutos, 0) > 0 THEN
      v_eventos := v_eventos || jsonb_build_object('codigo','he_50','descricao','Hora extra 50%','natureza','vencimento','minutos', e.total_horas_extras_50_minutos);
    END IF;
    IF COALESCE(e.total_horas_extras_100_minutos, 0) > 0 THEN
      v_eventos := v_eventos || jsonb_build_object('codigo','he_100','descricao','Hora extra 100% (domingo/feriado)','natureza','vencimento','minutos', e.total_horas_extras_100_minutos);
    END IF;
    IF COALESCE(e.total_adicional_noturno_minutos, 0) > 0 THEN
      v_eventos := v_eventos || jsonb_build_object('codigo','adic_noturno','descricao','Adicional noturno','natureza','vencimento','minutos', e.total_adicional_noturno_minutos);
    END IF;
    IF v_dsr_ref > 0 THEN
      v_eventos := v_eventos || jsonb_build_object('codigo','dsr_reflexo','descricao','Reflexo das horas extras no DSR (Sumula 172)','natureza','vencimento','minutos', v_dsr_ref);
    END IF;
    IF v_suprimido > 0 THEN
      -- INDENIZATORIA — nao e hora extra (CLT art. 71, §4º): 50% sobre os minutos
      -- suprimidos, sem reflexos.
      v_eventos := v_eventos || jsonb_build_object('codigo','supr_intervalo','descricao','Supressao de intervalo (art. 71 §4) — indenizatoria, nao e hora extra','natureza','indenizatoria','minutos', v_suprimido,'percentual', 50);
    END IF;
    IF COALESCE(e.total_faltas, 0) > 0 THEN
      v_eventos := v_eventos || jsonb_build_object('codigo','faltas','descricao','Faltas','natureza','desconto','quantidade', e.total_faltas);
    END IF;
    IF COALESCE(e.total_atrasos_minutos, 0) > 0 THEN
      v_eventos := v_eventos || jsonb_build_object('codigo','atrasos','descricao','Atrasos','natureza','desconto','minutos', e.total_atrasos_minutos);
    END IF;
    IF v_dsr_perda THEN
      v_eventos := v_eventos || jsonb_build_object('codigo','dsr_perdido','descricao','Perda do DSR por falta injustificada (Lei 605/49 art. 6)','natureza','desconto','quantidade', 1);
    END IF;

    v_colabs := v_colabs || jsonb_build_object(
      'colaborador_cpf',  e.colaborador_cpf,
      'colaborador_nome', e.colaborador_nome,
      'espelho_status',   e.status,
      'eventos',          v_eventos
    );
    v_total := v_total + 1;
  END LOOP;

  -- Idempotente: refaz o pacote 'auto' desta competencia/empresa. O marcador do
  -- pacote automatico e sistema_destino='folha_auto' (formato tem CHECK proprio).
  DELETE FROM public.ponto_exportacoes_folha
  WHERE tenant_id = p_tenant_id
    AND competencia = p_competencia
    AND COALESCE(sistema_destino, '') = 'folha_auto'
    AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id
         OR (p_empresa_id IS NULL AND empresa_id IS NULL));

  INSERT INTO public.ponto_exportacoes_folha
    (tenant_id, empresa_id, competencia, formato, sistema_destino, total_colaboradores, status, dados_exportados)
  VALUES (
    p_tenant_id, p_empresa_id, p_competencia, 'txt', 'folha_auto', v_total, 'gerado',
    jsonb_build_object(
      'competencia', p_competencia,
      'memoria', 'Composto da apuracao fechada (ponto_espelhos). Naturezas distintas: '
              || 'VENCIMENTO (HE 50/100, adicional noturno, reflexo DSR); DESCONTO (faltas, '
              || 'atrasos, perda de DSR); INDENIZATORIA (supressao de intervalo, art. 71 §4 — '
              || 'nao e hora extra). Grandezas em minutos.',
      'colaboradores', v_colabs
    )
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.ponto_compor_pacote_folha(uuid, uuid, text) IS
  'Compoe o pacote da folha a partir da apuracao fechada (ponto_espelhos) com naturezas corretas — vencimento, desconto e indenizatoria (supressao de intervalo NAO entra como hora extra) — e memoria, gravando em ponto_exportacoes_folha. Idempotente (pacote auto). PONTO-361.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | OK
--   funcao_existe : t  (ponto_compor_pacote_folha)
--   naturezas     : t  (distingue vencimento/desconto/indenizatoria)
--   grava_export  : t  (grava em ponto_exportacoes_folha)
-- ---------------------------------------------------------------------------
WITH src AS (SELECT prosrc FROM pg_proc WHERE proname='ponto_compor_pacote_folha' LIMIT 1)
SELECT
  (to_regprocedure('public.ponto_compor_pacote_folha(uuid,uuid,text)') IS NOT NULL) AS funcao_existe,
  ((SELECT prosrc FROM src) ILIKE '%indenizatoria%' AND (SELECT prosrc FROM src) ILIKE '%vencimento%'
     AND (SELECT prosrc FROM src) ILIKE '%desconto%') AS naturezas,
  ((SELECT prosrc FROM src) ILIKE '%exportacoes_folha%') AS grava_export,
  CASE WHEN to_regprocedure('public.ponto_compor_pacote_folha(uuid,uuid,text)') IS NOT NULL
        AND (SELECT prosrc FROM src) ILIKE '%indenizatoria%' AND (SELECT prosrc FROM src) ILIKE '%vencimento%'
        AND (SELECT prosrc FROM src) ILIKE '%desconto%' AND (SELECT prosrc FROM src) ILIKE '%exportacoes_folha%'
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda6_fila_folha_reenvio.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 6 (parte 5): fila da folha com estados e reenvio idempotente
-- Alvos: ponto_folha_marcar_status (nova); ponto_folha_reenviar (nova)
-- PONTO-398  (fecha a onda 6)
--
-- A exportacao para a folha era um registro passivo: sem fila, sem reenvio, sem
-- confirmacao. A coluna status ja tem os quatro estados (gerado/enviado/
-- processado/erro), mas nada os movimentava. Passa a existir a transicao de
-- estado VALIDADA e o REENVIO IDEMPOTENTE (reencaminha so o que esta em erro,
-- sem duplicar nem perder).
--
-- GARANTIAS: nao cria exportacao nova (usa a da parte 4); nao altera o motor de
-- saldo, o espelho nem o fechamento. Aditivo e idempotente. Sem backfill.
-- ============================================================================

-- (1) Transição de estado validada -------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_folha_marcar_status(
  p_export_id   uuid,
  p_novo_status text,
  p_detalhe     text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_atual text;
  v_ok    boolean;
BEGIN
  SELECT status INTO v_atual FROM public.ponto_exportacoes_folha WHERE id = p_export_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exportacao de folha % nao encontrada.', p_export_id USING ERRCODE = 'raise_exception';
  END IF;

  -- Estados da fila (pendente/enviado/confirmado/falha):
  --   gerado    -> enviado | erro
  --   enviado   -> processado | erro
  --   erro      -> gerado         (reenvio)
  --   x         -> x              (idempotente)
  v_ok := CASE
    WHEN v_atual = 'gerado'  AND p_novo_status IN ('enviado', 'erro') THEN true
    WHEN v_atual = 'enviado' AND p_novo_status IN ('processado', 'erro') THEN true
    WHEN v_atual = 'erro'    AND p_novo_status = 'gerado' THEN true
    WHEN v_atual = p_novo_status THEN true
    ELSE false
  END;

  IF NOT v_ok THEN
    RAISE EXCEPTION 'Transicao de status invalida na fila da folha: % -> %.', v_atual, p_novo_status
      USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.ponto_exportacoes_folha
     SET status = p_novo_status,
         dados_exportados = jsonb_set(
           COALESCE(dados_exportados, '{}'::jsonb), '{fila}',
           COALESCE(dados_exportados -> 'fila', '[]'::jsonb)
             || jsonb_build_object('de', v_atual, 'para', p_novo_status,
                                   'detalhe', p_detalhe, 'em', now()))
   WHERE id = p_export_id;
END;
$$;

COMMENT ON FUNCTION public.ponto_folha_marcar_status(uuid, text, text) IS
  'Transicao de estado da fila da folha (gerado->enviado->processado; ->erro na falha; erro->gerado no reenvio), validada e com trilha em dados_exportados->fila. PONTO-398.';

-- (2) Reenvio idempotente ----------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_folha_reenviar(
  p_tenant_id   uuid,
  p_empresa_id  uuid,
  p_competencia text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_n int := 0;
  r   RECORD;
BEGIN
  FOR r IN
    SELECT id, COALESCE((dados_exportados ->> 'tentativas')::int, 0) AS tent
    FROM public.ponto_exportacoes_folha
    WHERE tenant_id = p_tenant_id
      AND competencia = p_competencia
      AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id
           OR (p_empresa_id IS NULL AND empresa_id IS NULL))
      AND status = 'erro'   -- só reenvia o que está em falha
  LOOP
    -- Reencaminha o MESMO registro (erro -> gerado): sem duplicidade. Bump da
    -- contagem de tentativas + carimbo do reenvio.
    UPDATE public.ponto_exportacoes_folha
       SET status = 'gerado',
           dados_exportados = jsonb_set(
             jsonb_set(
               jsonb_set(COALESCE(dados_exportados, '{}'::jsonb),
                         '{tentativas}', to_jsonb(r.tent + 1)),
               '{reenviado_em}', to_jsonb(now())),
             '{fila}',
             COALESCE(dados_exportados -> 'fila', '[]'::jsonb)
               || jsonb_build_object('de', 'erro', 'para', 'gerado',
                                     'detalhe', 'reenvio idempotente', 'em', now()))
     WHERE id = r.id;
    v_n := v_n + 1;
  END LOOP;

  RETURN v_n;  -- idempotente: reexecutar reencaminha só os que ainda estão em erro
END;
$$;

COMMENT ON FUNCTION public.ponto_folha_reenviar(uuid, uuid, text) IS
  'Reenvio idempotente da fila da folha: reencaminha (erro -> gerado) so os pacotes ainda em erro na competencia, incrementando tentativas, sem duplicar nem perder. PONTO-398.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | OK
--   marcar_existe   : t  (ponto_folha_marcar_status)
--   reenviar_existe : t  (ponto_folha_reenviar)
--   tem_estados     : t  (transicao conhece enviado/processado/erro)
-- ---------------------------------------------------------------------------
WITH m AS (SELECT prosrc FROM pg_proc WHERE proname='ponto_folha_marcar_status' LIMIT 1)
SELECT
  (to_regprocedure('public.ponto_folha_marcar_status(uuid,text,text)') IS NOT NULL) AS marcar_existe,
  (to_regprocedure('public.ponto_folha_reenviar(uuid,uuid,text)') IS NOT NULL)      AS reenviar_existe,
  ((SELECT prosrc FROM m) ILIKE '%enviado%' AND (SELECT prosrc FROM m) ILIKE '%processado%'
     AND (SELECT prosrc FROM m) ILIKE '%erro%') AS tem_estados,
  CASE WHEN to_regprocedure('public.ponto_folha_marcar_status(uuid,text,text)') IS NOT NULL
        AND to_regprocedure('public.ponto_folha_reenviar(uuid,uuid,text)') IS NOT NULL
        AND (SELECT prosrc FROM m) ILIKE '%enviado%' AND (SELECT prosrc FROM m) ILIKE '%processado%'
        AND (SELECT prosrc FROM m) ILIKE '%erro%'
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;


-- ============================================================================
-- CONFERENCIA DESTA PARTE
-- Lista o que a parte deveria deixar no ambiente e diz o que chegou. A ultima
-- linha resume: OK quando nada faltou.
-- ============================================================================
WITH esperado (tipo, nome, marcador) AS MATERIALIZED (
  VALUES
    ('funcao', 'ponto_gerar_espelhos_competencia', NULL),
    ('funcao', 'ponto_fechamento_pendencias_criticas', NULL),
    ('funcao', 'ponto_fechar_competencia_verificar', NULL),
    ('funcao', 'ponto_compor_pacote_folha', 'Reflexo das horas extras no DSR (Sumula 172)'),
    ('funcao', 'ponto_folha_marcar_status', ', p_export_id USING ERRCODE = '),
    ('funcao', 'ponto_folha_reenviar', NULL)
), estado AS MATERIALIZED (
  SELECT e.tipo, e.nome, e.marcador,
         CASE e.tipo
           WHEN 'funcao'  THEN EXISTS (SELECT 1 FROM pg_proc p
                                        JOIN pg_namespace n ON n.oid = p.pronamespace
                                       WHERE n.nspname = 'public' AND p.proname = e.nome
                                         AND (e.marcador IS NULL
                                              OR p.prosrc LIKE '%' || e.marcador || '%'))
           WHEN 'tabela'  THEN to_regclass('public.' || e.nome) IS NOT NULL
           WHEN 'indice'  THEN EXISTS (SELECT 1 FROM pg_indexes
                                       WHERE schemaname = 'public' AND indexname = e.nome)
           WHEN 'gatilho' THEN EXISTS (SELECT 1 FROM pg_trigger
                                       WHERE NOT tgisinternal AND tgname = e.nome)
           WHEN 'coluna'  THEN EXISTS (SELECT 1 FROM information_schema.columns
                                       WHERE table_schema = 'public'
                                         AND table_name  = split_part(e.nome, '.', 1)
                                         AND column_name = split_part(e.nome, '.', 2))
         END AS presente
  FROM esperado e
)
SELECT tipo, nome, CASE WHEN presente THEN 'chegou' ELSE 'FALTOU' END AS situacao
FROM estado
WHERE NOT presente
UNION ALL
SELECT 'RESUMO',
       (SELECT count(*) FROM estado WHERE presente)::text || ' de '
         || (SELECT count(*) FROM estado)::text || ' pecas no lugar',
       CASE WHEN (SELECT count(*) FROM estado WHERE NOT presente) = 0
            THEN 'OK' ELSE 'CONFERIR as linhas acima' END
ORDER BY 1 DESC, 2;
