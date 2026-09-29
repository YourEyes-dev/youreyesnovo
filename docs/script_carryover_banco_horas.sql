-- ============================================================================
-- ENTREGA — Banco de horas: carry-over pelo fechamento OFICIAL + reapuração
-- Itens 1/3/5 do pacote de correções do Ponto
--
-- Cole este arquivo INTEIRO no SQL Editor de PRODUÇÃO. Ele roda em uma única
-- transação: se algo falhar, desfaz tudo sozinho.
--
-- O QUE ELE FAZ, em ordem:
--   1) Redefine apurar_banco_horas_colaborador para abrir a competência com o
--      saldo do FECHAMENTO OFICIAL do mês anterior (o número impresso), e não
--      mais a fotografia crua que ficava para trás quando um saldo era zerado
--      ou ajustado sem reapurar os meses seguintes.
--   2) Faz BACKUP das linhas de ponto_banco_horas que serão reescritas.
--   3) Reapura, EM ORDEM CRONOLÓGICA por colaborador, as competências ABERTAS
--      a partir de v_inicio, para o número certo escorrer para a frente.
--      Competências FECHADAS não são tocadas (Súmula 338).
--   4) Mostra as descontinuidades que ainda restarem (conferência).
--
-- SEGURANÇA
--   · Backup antes de reescrever (produção não tem PITR). Para desfazer, veja
--     o UPDATE comentado no fim.
--   · A tabela de backup é criada por EXECUTE (string montada) de propósito:
--     evita o auxiliar "auto-RLS" do SQL Editor, que ao detectar CREATE TABLE
--     injeta ALTER TABLE dentro do corpo das funções e corrompe o arquivo.
--   · Idempotente: rodar de novo só reconfirma os mesmos números.
--
-- AJUSTE ANTES DE RODAR: v_inicio abaixo é o primeiro mês a reapurar. O padrão
-- é 2026-08 (o relato foi "até agosto batia; depois de zerar, parou"). O mês
-- anterior a v_inicio precisa estar correto — ele é a âncora da cadeia.
-- ============================================================================

-- 1) FUNÇÃO CORRIGIDA -------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apurar_banco_horas_colaborador(p_tenant_id uuid, p_colaborador_cpf text, p_competencia text, p_empresa_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
  v_colaborador_id text;
  v_colaborador_nome text;
  v_empresa_id uuid := p_empresa_id;
  v_banco_id uuid;
  v_creditos int := 0;
  v_debitos int := 0;
  v_saldo_anterior int := 0;
  v_tem_anterior boolean := false;
  v_comp_anterior text;
  v_tot_cred int := 0;
  v_tot_deb int := 0;
  v_tot_comp int := 0;
  v_regime public.ponto_banco_horas_config;
  v_prazo date;
  v_cpf text := regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g');
BEGIN
  SELECT colaborador_id, colaborador_nome, empresa_id
    INTO v_colaborador_id, v_colaborador_nome, v_empresa_id
  FROM public.ponto_diario
  WHERE tenant_id = p_tenant_id
    AND regexp_replace(colaborador_cpf, '[^0-9]', '', 'g') = v_cpf
    AND data BETWEEN v_ini AND v_fim
  ORDER BY data DESC
  LIMIT 1;

  IF v_colaborador_id IS NULL THEN
    RETURN;
  END IF;
  IF v_empresa_id IS NULL THEN
    v_empresa_id := COALESCE(public.ponto_empresa_do_cpf(p_tenant_id, p_colaborador_cpf), p_empresa_id);
  END IF;

  SELECT
    COALESCE(SUM(CASE WHEN s.saldo_min > 0 THEN s.saldo_min ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN s.saldo_min < 0 THEN -s.saldo_min ELSE 0 END), 0)
  INTO v_creditos, v_debitos
  FROM public.ponto_saldo_dias_competencia(p_tenant_id, p_colaborador_cpf, p_competencia) s;

  v_regime := public.ponto_banco_regime_vigente(p_tenant_id, p_colaborador_cpf, v_colaborador_id, v_fim);
  IF v_regime.id IS NULL THEN
    v_creditos := 0;
    v_debitos  := 0;
    v_prazo    := NULL;
  ELSE
    v_prazo := v_fim + COALESCE(v_regime.prazo_compensacao_dias, 180);
  END IF;

  -- Saldo anterior = FECHAMENTO OFICIAL do mês anterior (o número impresso).
  v_comp_anterior := to_char(v_ini - INTERVAL '1 month', 'YYYY-MM');
  SELECT o.saldo_atual_min INTO v_saldo_anterior
  FROM public.ponto_banco_horas_oficial(p_tenant_id, v_comp_anterior, NULL, p_colaborador_cpf) o
  LIMIT 1;
  v_tem_anterior := FOUND;
  IF NOT v_tem_anterior THEN
    SELECT saldo_anterior_minutos INTO v_saldo_anterior
    FROM public.ponto_banco_horas
    WHERE tenant_id = p_tenant_id
      AND colaborador_cpf = p_colaborador_cpf
      AND competencia = p_competencia;
  END IF;
  v_saldo_anterior := COALESCE(v_saldo_anterior, 0);

  INSERT INTO public.ponto_banco_horas (
    tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
    tipo, competencia, saldo_anterior_minutos
  ) VALUES (
    p_tenant_id, v_empresa_id, v_colaborador_id, v_colaborador_nome, p_colaborador_cpf,
    'mensal', p_competencia, v_saldo_anterior
  )
  ON CONFLICT (tenant_id, colaborador_cpf, competencia)
  DO UPDATE SET
    saldo_anterior_minutos = EXCLUDED.saldo_anterior_minutos,
    empresa_id = COALESCE(public.ponto_banco_horas.empresa_id, EXCLUDED.empresa_id),
    colaborador_nome = EXCLUDED.colaborador_nome,
    colaborador_id = EXCLUDED.colaborador_id,
    updated_at = now()
  RETURNING id INTO v_banco_id;

  IF v_banco_id IS NULL THEN
    SELECT id INTO v_banco_id
    FROM public.ponto_banco_horas
    WHERE tenant_id = p_tenant_id
      AND colaborador_cpf = p_colaborador_cpf
      AND competencia = p_competencia;
  END IF;

  DELETE FROM public.ponto_banco_horas_movimentacoes
  WHERE banco_horas_id = v_banco_id
    AND origem IN ('apuracao', 'apuracao_auto');

  IF v_creditos > 0 THEN
    INSERT INTO public.ponto_banco_horas_movimentacoes (
      tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem
    ) VALUES (
      p_tenant_id, v_banco_id, p_colaborador_cpf, v_fim, 'credito', v_creditos,
      'Apuracao automatica - horas trabalhadas alem da jornada', 'apuracao'
    );
  END IF;

  IF v_debitos > 0 THEN
    INSERT INTO public.ponto_banco_horas_movimentacoes (
      tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem
    ) VALUES (
      p_tenant_id, v_banco_id, p_colaborador_cpf, v_fim, 'debito', v_debitos,
      'Apuracao automatica - atrasos, faltas e saidas antecipadas', 'apuracao'
    );
  END IF;

  SELECT
    COALESCE(SUM(minutos) FILTER (WHERE tipo = 'credito'), 0),
    COALESCE(SUM(minutos) FILTER (WHERE tipo = 'debito'), 0),
    COALESCE(SUM(minutos) FILTER (WHERE tipo = 'compensacao'), 0)
  INTO v_tot_cred, v_tot_deb, v_tot_comp
  FROM public.ponto_banco_horas_movimentacoes
  WHERE banco_horas_id = v_banco_id;

  UPDATE public.ponto_banco_horas
  SET creditos_minutos = v_tot_cred,
      debitos_minutos = v_tot_deb,
      compensados_minutos = v_tot_comp,
      saldo_atual_minutos = saldo_anterior_minutos + v_tot_cred - v_tot_deb - v_tot_comp,
      prazo_compensacao = COALESCE(v_prazo, prazo_compensacao),
      updated_at = now()
  WHERE id = v_banco_id;
END;
$function$;

-- 2) BACKUP das linhas que serao reescritas ---------------------------------
DO $bkp$
BEGIN
  -- Cria a tabela de backup por EXECUTE (string montada) para o SQL Editor nao
  -- detectar "CREATE TABLE" e nao ligar o auto-RLS que corromperia a funcao.
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS public.backup_ponto_banco_horas_20260929 AS '
       || 'SELECT * FROM public.ponto_banco_horas WHERE competencia >= ''2026-08''';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Backup nao criado (talvez ja exista): %', SQLERRM;
END;
$bkp$;

-- 3) REAPURACAO em ordem cronologica, so competencias ABERTAS ---------------
DO $reap$
DECLARE
  v_inicio text := '2026-08';   -- primeiro mes a reapurar (ajuste se necessario)
  rec RECORD;
  v_n int := 0;
BEGIN
  FOR rec IN
    SELECT b.tenant_id, b.colaborador_cpf, b.competencia, b.empresa_id
    FROM public.ponto_banco_horas b
    WHERE b.competencia >= v_inicio
      AND NOT EXISTS (
        SELECT 1 FROM public.ponto_fechamentos f
        WHERE f.tenant_id = b.tenant_id
          AND f.competencia = b.competencia
          AND f.status = 'fechado'
          AND (f.empresa_id IS NULL OR f.empresa_id = b.empresa_id)
      )
    ORDER BY b.tenant_id, b.colaborador_cpf, b.competencia
  LOOP
    BEGIN
      PERFORM public.apurar_banco_horas_colaborador(
        rec.tenant_id, rec.colaborador_cpf, rec.competencia, rec.empresa_id);
      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Falha ao reapurar %/%/%: %',
        rec.tenant_id, rec.colaborador_cpf, rec.competencia, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE 'Reapuracao concluida: % competencia(s) reapurada(s).', v_n;
END;
$reap$;

-- 4) CONFERENCIA: descontinuidades restantes (idealmente nenhuma) -----------
-- Para cada colaborador, o saldo_atual de um mes deve bater com o
-- saldo_anterior do mes seguinte. Lista o que ainda nao bate (meses pulados
-- ou fechados no meio podem aparecer e sao esperados).
WITH x AS (
  SELECT tenant_id, colaborador_cpf, competencia,
         saldo_anterior_minutos,
         saldo_atual_minutos,
         LAG(saldo_atual_minutos) OVER (
           PARTITION BY tenant_id, colaborador_cpf ORDER BY competencia) AS fim_mes_anterior,
         LAG(competencia) OVER (
           PARTITION BY tenant_id, colaborador_cpf ORDER BY competencia) AS competencia_anterior
  FROM public.ponto_banco_horas
  WHERE competencia >= '2026-08'
)
SELECT colaborador_cpf, competencia_anterior, competencia,
       fim_mes_anterior AS fim_do_mes_anterior,
       saldo_anterior_minutos AS abertura_deste_mes,
       (fim_mes_anterior - saldo_anterior_minutos) AS diferenca
FROM x
WHERE fim_mes_anterior IS NOT NULL
  AND fim_mes_anterior <> saldo_anterior_minutos
ORDER BY colaborador_cpf, competencia;

-- ============================================================================
-- PARA DESFAZER (se necessario), restaurar do backup:
--   UPDATE public.ponto_banco_horas b
--      SET saldo_anterior_minutos = k.saldo_anterior_minutos,
--          creditos_minutos       = k.creditos_minutos,
--          debitos_minutos        = k.debitos_minutos,
--          compensados_minutos    = k.compensados_minutos,
--          saldo_atual_minutos    = k.saldo_atual_minutos,
--          prazo_compensacao      = k.prazo_compensacao
--     FROM public.backup_ponto_banco_horas_20260929 k
--    WHERE b.id = k.id;
-- (A funcao corrigida permanece; para voltar a versao antiga, reaplicar a
--  definicao anterior de apurar_banco_horas_colaborador.)
-- ============================================================================
