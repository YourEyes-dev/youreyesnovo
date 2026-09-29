-- ============================================================================
-- DIAGNÓSTICO (SOMENTE LEITURA) — Cacilda, Mila (desligadas) e Fabieli (afastada)
-- Seguro em PRODUÇÃO: não altera nada.
--
-- Mostra, por colaborador e competência:
--   · saldo_anterior e saldo_atual da linha de banco;
--   · data_admissao, data_desligamento e status do vínculo (para saber em qual
--     competência zerar as desligadas);
--   · TODOS os movimentos daquele mês, com tipo, minutos, origem e data — para
--     identificar se Fabieli tem um "saldo inicial" (origem manual no primeiro
--     mês de uso) que deva ser MANTIDO.
-- ============================================================================

WITH alvo(cpf) AS (
  VALUES ('03343755923'),  -- Cacilda (desligada)
         ('14023338974'),  -- Mila    (desligada)
         ('07444157995')   -- Fabieli (afastada)
)
SELECT
  b.colaborador_nome,
  b.colaborador_cpf,
  b.competencia,
  b.saldo_anterior_minutos AS saldo_anterior,
  b.saldo_atual_minutos    AS saldo_atual,
  v.data_admissao,
  v.data_desligamento,
  v.status,
  (SELECT string_agg(
            m.tipo || ' ' || m.minutos || 'min (' || COALESCE(m.origem, '?')
              || ' ' || COALESCE(to_char(m.data_referencia, 'YYYY-MM-DD'), '') || ')',
            '  |  ' ORDER BY m.data_referencia, m.id)
     FROM public.ponto_banco_horas_movimentacoes m
     WHERE m.banco_horas_id = b.id) AS movimentos_do_mes
FROM public.ponto_banco_horas b
JOIN alvo ON regexp_replace(COALESCE(b.colaborador_cpf, ''), '[^0-9]', '', 'g') = alvo.cpf
LEFT JOIN LATERAL (
  SELECT a.data_admissao, a.data_desligamento, a.status
  FROM public.admissoes a
  WHERE regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') = alvo.cpf
    AND (a.empresa_id = b.empresa_id OR b.empresa_id IS NULL)
  ORDER BY a.data_admissao DESC NULLS LAST
  LIMIT 1
) v ON true
ORDER BY b.colaborador_nome, b.competencia;
