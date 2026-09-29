-- ============================================================================
-- CONFORMIDADE — remove débitos errôneos do banco e zera do mês de encerramento
-- Cacilda (desl. 02/07 -> 2026-07), Mila (desl. 09/06 -> 2026-06),
-- Fabieli (afastada -> 2026-06). Cole INTEIRO no SQL Editor de PRODUÇÃO.
--
-- POR QUE: a apuração debitou meses inteiros de quem não estava trabalhando
-- (dias sem marcação pós-desligamento/afastamento), inflando o saldo devedor em
-- competências JÁ FECHADAS. Zerar só de agosto deixava esses débitos errôneos no
-- histórico. Este script, para cada colaboradora, a partir do mês de encerramento:
--   1) APAGA os movimentos de apuração automática (origem apuracao/apuracao_auto)
--      — são os débitos-fantasma de dias não trabalhados — e as absorções
--      anteriores (liquidacao_absorcao), para refazer a cadeia do zero;
--   2) lança uma ABSORÇÃO pela empresa do saldo devedor remanescente (o saldo
--      continua sendo soma de movimentos + saldo anterior; a absorção é o
--      movimento que documenta o encerramento);
--   3) recalcula a fotografia (inclusive em meses fechados, onde a apuração não
--      roda) para o oficial e a fotografia baterem em 0.
--
-- Preserva os meses ANTERIORES ao encerramento (histórico legítimo trabalhado).
-- NÃO cria função (sem auto-RLS). Backup de fotografia E movimentos. Idempotente.
-- ============================================================================

DO $conf$
DECLARE
  v_alvo RECORD;
  rec RECORD;
  v_anterior int;
  v_residual int;
  v_cred int; v_deb int; v_comp int;
  v_fimmes date;
BEGIN
  -- BACKUP (fotografia + movimentos das 3, todas as competências).
  IF to_regclass('public.backup_conf_deslig_foto_20260929') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_conf_deslig_foto_20260929 (LIKE public.ponto_banco_horas INCLUDING DEFAULTS)';
    INSERT INTO public.backup_conf_deslig_foto_20260929
      SELECT * FROM public.ponto_banco_horas
      WHERE regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g') IN ('03343755923','14023338974','07444157995');
    EXECUTE 'CREATE ' || 'TABLE public.backup_conf_deslig_movs_20260929 (LIKE public.ponto_banco_horas_movimentacoes INCLUDING DEFAULTS)';
    INSERT INTO public.backup_conf_deslig_movs_20260929
      SELECT m.* FROM public.ponto_banco_horas_movimentacoes m
      JOIN public.ponto_banco_horas b ON b.id = m.banco_horas_id
      WHERE regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') IN ('03343755923','14023338974','07444157995');
    RAISE NOTICE 'Backup criado (foto + movimentos).';
  ELSE
    RAISE NOTICE 'Backup ja existe — mantido.';
  END IF;

  FOR v_alvo IN
    SELECT * FROM (VALUES
      ('03343755923', '2026-07'),   -- Cacilda
      ('14023338974', '2026-06'),   -- Mila
      ('07444157995', '2026-06')    -- Fabieli
    ) AS t(cpf, enc)
  LOOP
    FOR rec IN
      SELECT b.id, b.tenant_id, b.colaborador_cpf, b.colaborador_nome, b.competencia,
             b.saldo_anterior_minutos
      FROM public.ponto_banco_horas b
      WHERE regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') = v_alvo.cpf
        AND b.competencia >= v_alvo.enc
      ORDER BY b.competencia, b.id
    LOOP
      v_fimmes := (to_date(rec.competencia || '-01','YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;

      -- 1) apaga apuração automática (débito-fantasma) e absorções anteriores.
      DELETE FROM public.ponto_banco_horas_movimentacoes
      WHERE banco_horas_id = rec.id
        AND origem IN ('apuracao', 'apuracao_auto', 'liquidacao_absorcao');

      -- Saldo anterior: no mês de encerramento mantém o herdado (histórico
      -- legítimo dos meses trabalhados); nos meses seguintes abre em 0.
      IF rec.competencia = v_alvo.enc THEN
        v_anterior := COALESCE(rec.saldo_anterior_minutos, 0);
      ELSE
        v_anterior := 0;
      END IF;

      -- 2) residual após remover os movimentos-fantasma; absorve se devedor.
      -- COALESCE em CADA soma (senão a ausência de um tipo torna o total NULL).
      v_residual := v_anterior
        + COALESCE((SELECT SUM(minutos) FROM public.ponto_banco_horas_movimentacoes WHERE banco_horas_id = rec.id AND tipo = 'credito'), 0)
        - COALESCE((SELECT SUM(minutos) FROM public.ponto_banco_horas_movimentacoes WHERE banco_horas_id = rec.id AND tipo = 'debito'), 0)
        - COALESCE((SELECT SUM(minutos) FROM public.ponto_banco_horas_movimentacoes WHERE banco_horas_id = rec.id AND tipo = 'compensacao'), 0);

      IF v_residual < 0 THEN
        INSERT INTO public.ponto_banco_horas_movimentacoes (
          tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem
        ) VALUES (
          rec.tenant_id, rec.id, rec.colaborador_cpf, v_fimmes, 'credito', -v_residual,
          'Conformidade - absorcao de saldo devedor por encerramento (desligamento/afastamento)', 'liquidacao_absorcao');
        RAISE NOTICE 'Absorvido: % % (residual % min)', rec.colaborador_nome, rec.competencia, v_residual;
      ELSIF v_residual > 0 THEN
        RAISE NOTICE 'CREDOR remanescente (rever): % % (+% min)', rec.colaborador_nome, rec.competencia, v_residual;
      END IF;

      -- 3) recalcula a fotografia a partir dos movimentos (inclui meses fechados).
      v_cred := COALESCE((SELECT SUM(minutos) FILTER (WHERE tipo='credito') FROM public.ponto_banco_horas_movimentacoes WHERE banco_horas_id=rec.id),0);
      v_deb  := COALESCE((SELECT SUM(minutos) FILTER (WHERE tipo='debito')  FROM public.ponto_banco_horas_movimentacoes WHERE banco_horas_id=rec.id),0);
      v_comp := COALESCE((SELECT SUM(minutos) FILTER (WHERE tipo='compensacao') FROM public.ponto_banco_horas_movimentacoes WHERE banco_horas_id=rec.id),0);

      UPDATE public.ponto_banco_horas
      SET saldo_anterior_minutos = v_anterior,
          creditos_minutos = v_cred,
          debitos_minutos = v_deb,
          compensados_minutos = v_comp,
          saldo_atual_minutos = v_anterior + v_cred - v_deb - v_comp,
          updated_at = now()
      WHERE id = rec.id;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'Conformidade concluida.';
END;
$conf$;

-- CONFERÊNCIA: as três, de 2026-06 em diante (esperado tudo 0/0, sem débito).
SELECT b.competencia, b.colaborador_nome,
       b.debitos_minutos AS debitos,
       b.saldo_atual_minutos AS saldo_foto,
       o.saldo_atual_min AS saldo_oficial,
       (SELECT count(*) FROM public.ponto_banco_horas_movimentacoes m
          WHERE m.banco_horas_id = b.id AND m.origem IN ('apuracao','apuracao_auto')) AS movs_apuracao_restantes
FROM public.ponto_banco_horas b
LEFT JOIN LATERAL public.ponto_banco_horas_oficial(
  b.tenant_id, b.competencia, b.empresa_id, b.colaborador_cpf) o ON true
WHERE regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') IN ('03343755923','14023338974','07444157995')
  AND b.competencia >= '2026-06'
ORDER BY b.colaborador_nome, b.competencia, b.id;
