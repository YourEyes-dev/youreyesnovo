-- ============================================================================
-- CORRETIVO — Fechamento (zeragem) de banco de horas POR MOVIMENTO — GRUPO
-- Encerramento do ciclo em 2026-08 para os colaboradores da lista (qualquer
-- empresa do grupo). Cole INTEIRO no SQL Editor de PRODUÇÃO (uma transação).
--
-- NÃO cria função (não sofre o auto-RLS). O backup é criado por EXECUTE (string
-- montada, sem a sequência CREATE+TABLE contígua) e preenchido por INSERT.
--
-- O QUE FAZ: para cada CPF da LISTA, na competência de encerramento, lança um
-- MOVIMENTO de liquidação (nunca escreve o saldo direto — RQ-062) que leva o
-- saldo OFICIAL a zero, e reapura os meses seguintes (abertos) em ordem, para o
-- zero escorrer para a frente.
--   · DEVEDOR (negativo) -> crédito de "absorção pela empresa" (a empresa perdoa
--     a dívida; não prejudica o colaborador).
--   · CREDOR  (positivo) -> compensação/pagamento. DESLIGADO por padrão: zerar
--     credor sem pagar/compensar é supressão de crédito. Ligue (v_zerar_credores
--     := true) só com decisão de DP, ciente de que o registro afirma que houve
--     pagamento ou folga concedida.
--
-- IDEMPOTENTE: se já houver movimento de liquidação no colaborador, pula.
-- BACKUP: backup_fechamento_banco_20260929 (rede de segurança).
--
-- >>> PREENCHA v_cpfs COM OS CPFs A ENCERRAR. Sem lista, não faz nada. <<<
-- ============================================================================

DO $liq$
DECLARE
  v_competencia text := '2026-08';        -- competência de encerramento
  v_cpfs text[] := ARRAY[
    -- Itapejara (26114701000145):
    '071.542.019-40',   -- Leticia   (devedor)
    '085.949.149-89',   -- Luciana   (devedor)
    '117.626.459-12',   -- Luciani   (devedor)
    '112.899.749-50',   -- Paulo     (devedor)
    '061.531.139-31',   -- Adriana   (ja 0 — sera pulada)
    '014.160.681-98',   -- Cleciane  (ja 0 — sera pulada)
    '093.329.719-00'    -- Marina    (ja 0 — sera pulada)
    -- Realeza (41085456000189):  AYLYN, DEISI  -> incluir CPFs
    -- Dois Vizinhos (31219374000126): CAROL     -> incluir CPF
  ]::text[];
  v_zerar_credores boolean := false;      -- só true com decisão de DP
  v_fim date := (to_date(v_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
  rec RECORD;
  v_saldo int;
  v_n int := 0;
BEGIN
  IF cardinality(v_cpfs) = 0 THEN
    RAISE NOTICE 'Lista de CPFs vazia — nada a fazer.';
    RETURN;
  END IF;

  -- BACKUP das linhas que podem ser reescritas (só as dos CPFs da lista).
  IF to_regclass('public.backup_fechamento_banco_20260929') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_fechamento_banco_20260929 '
         || '(LIKE public.ponto_banco_horas INCLUDING DEFAULTS)';
    INSERT INTO public.backup_fechamento_banco_20260929
      SELECT * FROM public.ponto_banco_horas
      WHERE competencia >= v_competencia
        AND regexp_replace(COALESCE(colaborador_cpf,''), '[^0-9]', '', 'g') IN (
              SELECT regexp_replace(x, '[^0-9]', '', 'g') FROM unnest(v_cpfs) AS x);
    RAISE NOTICE 'Backup criado em backup_fechamento_banco_20260929.';
  ELSE
    RAISE NOTICE 'Backup ja existe — mantido.';
  END IF;

  -- LIQUIDAÇÃO na competência de encerramento.
  FOR rec IN
    SELECT b.id AS banco_id, b.tenant_id, b.empresa_id, b.colaborador_cpf, b.colaborador_nome
    FROM public.ponto_banco_horas b
    WHERE b.competencia = v_competencia
      AND regexp_replace(COALESCE(b.colaborador_cpf,''), '[^0-9]', '', 'g') IN (
            SELECT regexp_replace(x, '[^0-9]', '', 'g') FROM unnest(v_cpfs) AS x)
  LOOP
    IF EXISTS (SELECT 1 FROM public.ponto_banco_horas_movimentacoes m
               WHERE m.banco_horas_id = rec.banco_id
                 AND m.origem IN ('liquidacao_absorcao', 'liquidacao_compensacao')) THEN
      RAISE NOTICE 'Ja liquidado, pulando: %', rec.colaborador_nome;
      CONTINUE;
    END IF;

    v_saldo := COALESCE((
      SELECT o.saldo_atual_min
      FROM public.ponto_banco_horas_oficial(rec.tenant_id, v_competencia, rec.empresa_id, rec.colaborador_cpf) o
      LIMIT 1), 0);

    IF v_saldo = 0 THEN
      RAISE NOTICE 'Saldo ja zero, pulando: %', rec.colaborador_nome;
      CONTINUE;
    ELSIF v_saldo < 0 THEN
      INSERT INTO public.ponto_banco_horas_movimentacoes (
        tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem
      ) VALUES (
        rec.tenant_id, rec.banco_id, rec.colaborador_cpf, v_fim, 'credito', -v_saldo,
        'Fechamento de banco - absorcao de saldo devedor pela empresa', 'liquidacao_absorcao');
      v_n := v_n + 1;
      RAISE NOTICE 'Devedor absorvido: % (% min)', rec.colaborador_nome, v_saldo;
    ELSE
      IF NOT v_zerar_credores THEN
        RAISE NOTICE 'CREDOR NAO zerado (exige pagamento/compensacao — DP): % (+% min)',
          rec.colaborador_nome, v_saldo;
        CONTINUE;
      END IF;
      INSERT INTO public.ponto_banco_horas_movimentacoes (
        tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem
      ) VALUES (
        rec.tenant_id, rec.banco_id, rec.colaborador_cpf, v_fim, 'compensacao', v_saldo,
        'Fechamento de banco - liquidacao de saldo credor (pagamento/compensacao)', 'liquidacao_compensacao');
      v_n := v_n + 1;
      RAISE NOTICE 'Credor liquidado: % (+% min)', rec.colaborador_nome, v_saldo;
    END IF;
  END LOOP;

  -- REAPURA a competência de encerramento e as seguintes (abertas), em ordem,
  -- só para os CPFs da lista — o zero escorre para a frente.
  FOR rec IN
    SELECT b.tenant_id, b.colaborador_cpf, b.competencia, b.empresa_id
    FROM public.ponto_banco_horas b
    WHERE b.competencia >= v_competencia
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
      rec.tenant_id, rec.colaborador_cpf, rec.competencia, rec.empresa_id);
  END LOOP;

  RAISE NOTICE 'Liquidacoes lancadas: %. Reapuracao concluida.', v_n;
END;
$liq$;

-- CONFERÊNCIA: saldos dos CPFs encerrados, de 2026-08 em diante (foto x oficial).
SELECT b.competencia, b.colaborador_nome, b.colaborador_cpf,
       b.saldo_atual_minutos AS saldo_foto,
       o.saldo_atual_min     AS saldo_oficial
FROM public.ponto_banco_horas b
LEFT JOIN LATERAL public.ponto_banco_horas_oficial(
  b.tenant_id, b.competencia, b.empresa_id, b.colaborador_cpf) o ON true
WHERE b.competencia >= '2026-08'
  AND regexp_replace(COALESCE(b.colaborador_cpf,''), '[^0-9]', '', 'g') IN (
        '07154201940','08594914989','11762645912','11289974950',
        '06153113931','01416068198','09332971900'
        -- + CPFs de AYLYN, DEISI, CAROL quando incluídos
      )
ORDER BY b.colaborador_nome, b.competencia;
