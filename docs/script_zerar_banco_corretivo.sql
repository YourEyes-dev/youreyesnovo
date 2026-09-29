-- ============================================================================
-- CORRETIVO — Encerrar (zerar) saldo do banco de horas POR MOVIMENTO
-- Empresa CNPJ 26114701000145 — competência de encerramento 2026-08
--
-- Cole INTEIRO no SQL Editor de PRODUÇÃO (roda em uma transação; se falhar,
-- desfaz). NÃO cria função — não sofre o auto-RLS. O backup é criado por
-- EXECUTE (string montada), sem a sequência CREATE+TABLE contígua no texto.
--
-- O QUE FAZ: para cada colaborador da LISTA abaixo, lança um MOVIMENTO de
-- liquidação (nunca escreve o saldo direto) que leva o saldo OFICIAL da
-- competência de encerramento a zero, e reapura os meses seguintes (abertos)
-- em ordem, para o zero escorrer para a frente.
--   · Saldo DEVEDOR (negativo)  -> crédito de "absorção pela empresa".
--   · Saldo CREDOR  (positivo)  -> compensação/pagamento. DESLIGADO por padrão:
--     zerar credor sem pagar/compensar é supressão de crédito. Ligue só com
--     decisão de DP (v_zerar_credores := true), ciente de que o registro
--     afirma que houve pagamento ou folga concedida.
--
-- IDEMPOTENTE: se já houver movimento de liquidação para o colaborador, pula.
-- BACKUP: backup_zerar_banco_26114701000145 (rede de segurança).
--
-- >>> PREENCHA v_cpfs COM OS CPFs A ENCERRAR. Sem lista, não faz nada. <<<
-- ============================================================================

-- 1) BACKUP das linhas que podem ser reescritas -----------------------------
DO $bkp$
BEGIN
  IF to_regclass('public.backup_zerar_banco_26114701000145') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_zerar_banco_26114701000145 AS '
         || 'SELECT * FROM public.ponto_banco_horas '
         || 'WHERE competencia >= ''2026-08'' '
         || 'AND empresa_id IN (SELECT id FROM public.empresa_cadastro '
         || 'WHERE regexp_replace(COALESCE(cnpj,''''), ''[^0-9]'', '''', ''g'') = ''26114701000145'')';
    RAISE NOTICE 'Backup criado em backup_zerar_banco_26114701000145.';
  ELSE
    RAISE NOTICE 'Backup ja existe — mantido.';
  END IF;
END;
$bkp$;

-- 2) LIQUIDAÇÃO por movimento + reapuração para a frente ---------------------
DO $liq$
DECLARE
  v_cnpj text := '26114701000145';
  v_competencia text := '2026-08';         -- competência de encerramento
  v_cpfs text[] := ARRAY[
    -- 'CPF1', 'CPF2', ...   <<< PREENCHA (com ou sem máscara)
  ]::text[];
  v_zerar_credores boolean := false;       -- só true com decisão de DP
  v_empresa_id uuid;
  v_tenant uuid;
  v_fim date := (to_date(v_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
  rec RECORD;
  v_saldo int;
  v_n int := 0;
BEGIN
  IF cardinality(v_cpfs) = 0 THEN
    RAISE NOTICE 'Lista de CPFs vazia — nada a fazer. Preencha v_cpfs.';
    RETURN;
  END IF;

  v_empresa_id := (SELECT id FROM public.empresa_cadastro
                   WHERE regexp_replace(COALESCE(cnpj,''), '[^0-9]', '', 'g') = v_cnpj LIMIT 1);
  IF v_empresa_id IS NULL THEN
    RAISE NOTICE 'Empresa com CNPJ % nao encontrada.', v_cnpj;
    RETURN;
  END IF;
  v_tenant := (SELECT tenant_id FROM public.empresa_cadastro WHERE id = v_empresa_id);

  FOR rec IN
    SELECT b.id AS banco_id, b.colaborador_cpf, b.colaborador_nome
    FROM public.ponto_banco_horas b
    WHERE b.tenant_id = v_tenant
      AND b.empresa_id = v_empresa_id
      AND b.competencia = v_competencia
      AND regexp_replace(COALESCE(b.colaborador_cpf,''), '[^0-9]', '', 'g') IN (
            SELECT regexp_replace(x, '[^0-9]', '', 'g') FROM unnest(v_cpfs) AS x)
  LOOP
    -- Já liquidado? Idempotência.
    IF EXISTS (SELECT 1 FROM public.ponto_banco_horas_movimentacoes m
               WHERE m.banco_horas_id = rec.banco_id
                 AND m.origem IN ('liquidacao_absorcao', 'liquidacao_compensacao')) THEN
      RAISE NOTICE 'Ja liquidado, pulando: %', rec.colaborador_nome;
      CONTINUE;
    END IF;

    -- Saldo OFICIAL atual (antes da liquidação).
    v_saldo := COALESCE((
      SELECT o.saldo_atual_min
      FROM public.ponto_banco_horas_oficial(v_tenant, v_competencia, v_empresa_id, rec.colaborador_cpf) o
      LIMIT 1), 0);

    IF v_saldo = 0 THEN
      RAISE NOTICE 'Saldo ja zero, pulando: %', rec.colaborador_nome;
      CONTINUE;
    ELSIF v_saldo < 0 THEN
      -- Devedor: absorção pela empresa (crédito que quita a dívida).
      INSERT INTO public.ponto_banco_horas_movimentacoes (
        tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem
      ) VALUES (
        v_tenant, rec.banco_id, rec.colaborador_cpf, v_fim, 'credito', -v_saldo,
        'Encerramento de saldo devedor - absorcao pela empresa (corretivo)', 'liquidacao_absorcao');
      v_n := v_n + 1;
      RAISE NOTICE 'Devedor absorvido: % (% min)', rec.colaborador_nome, v_saldo;
    ELSE
      -- Credor: só com autorização explícita (pagamento/compensação).
      IF NOT v_zerar_credores THEN
        RAISE NOTICE 'CREDOR NAO zerado (exige pagamento/compensacao — DP): % (+% min)',
          rec.colaborador_nome, v_saldo;
        CONTINUE;
      END IF;
      INSERT INTO public.ponto_banco_horas_movimentacoes (
        tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem
      ) VALUES (
        v_tenant, rec.banco_id, rec.colaborador_cpf, v_fim, 'compensacao', v_saldo,
        'Encerramento de saldo credor - compensacao/pagamento (corretivo)', 'liquidacao_compensacao');
      v_n := v_n + 1;
      RAISE NOTICE 'Credor liquidado: % (+% min)', rec.colaborador_nome, v_saldo;
    END IF;
  END LOOP;

  -- Reapura a competência de encerramento e as seguintes (abertas), em ordem,
  -- só para os CPFs da lista — o zero escorre para a frente.
  FOR rec IN
    SELECT b.colaborador_cpf, b.competencia, b.empresa_id
    FROM public.ponto_banco_horas b
    WHERE b.tenant_id = v_tenant
      AND b.empresa_id = v_empresa_id
      AND b.competencia >= v_competencia
      AND regexp_replace(COALESCE(b.colaborador_cpf,''), '[^0-9]', '', 'g') IN (
            SELECT regexp_replace(x, '[^0-9]', '', 'g') FROM unnest(v_cpfs) AS x)
      AND NOT EXISTS (
        SELECT 1 FROM public.ponto_fechamentos f
        WHERE f.tenant_id = b.tenant_id
          AND f.competencia = b.competencia
          AND f.status = 'fechado'
          AND (f.empresa_id IS NULL OR f.empresa_id = b.empresa_id))
    ORDER BY b.colaborador_cpf, b.competencia
  LOOP
    PERFORM public.apurar_banco_horas_colaborador(
      v_tenant, rec.colaborador_cpf, rec.competencia, rec.empresa_id);
  END LOOP;

  RAISE NOTICE 'Liquidacoes lancadas: %. Reapuracao concluida.', v_n;
END;
$liq$;

-- 3) CONFERÊNCIA: saldos da empresa após o corretivo ------------------------
SELECT b.competencia, b.colaborador_nome, b.saldo_atual_minutos AS saldo_foto,
       o.saldo_atual_min AS saldo_oficial
FROM public.ponto_banco_horas b
JOIN public.empresa_cadastro e ON e.id = b.empresa_id
LEFT JOIN LATERAL public.ponto_banco_horas_oficial(
  b.tenant_id, b.competencia, b.empresa_id, b.colaborador_cpf) o ON true
WHERE regexp_replace(COALESCE(e.cnpj,''), '[^0-9]', '', 'g') = '26114701000145'
  AND b.competencia >= '2026-08'
ORDER BY b.colaborador_nome, b.competencia;
