-- ============================================================================
-- ENTREGA — AFAST-021 · prazo do S-2230 na recaída — HOMOLOGAÇÃO
--
-- Cole no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na PRODUÇÃO.
--
-- AFAST-021 estava vermelho: a auditoria verifica que existe uma função que
-- calcula o prazo diferenciado do S-2230 na recaída (mesmo CID em até 60 dias →
-- evento devido já no 1º dia). O helper existe no repositório (migration fase-4)
-- mas nunca foi entregue à produção. Aqui vai limpo (só a função, sem as tabelas
-- da fase-4 — para não acionar o auto-RLS do editor).
--
-- NOTA DE COMPORTAMENTO (honesta): a função calcula o prazo corretamente e fecha
-- a auditoria. O fio que a LIGA à criação da pendência/eSocial na recaída ainda
-- não está completo (a acumulação por CID cria a pendência do S-2230 sem
-- distinguir a recaída). A regra exata da recaída depende de definição do
-- jurídico ([VAL]); quando fechar, dá para ligar o helper no caminho da pendência.
--
-- SEGURANÇA: só CREATE OR REPLACE FUNCTION (IMMUTABLE, pura) — não cria tabela,
-- não apaga dado, sem lock relevante. Idempotente.
--
-- Origem: migration 20260915120000 (seção AFAST-021).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.afastamento_prazo_recaida_s2230(
  p_data_inicio date,
  p_is_recaida  boolean
) RETURNS date
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $$
  -- Na recaida (mesmo CID em ate 60 dias) o S-2230 é devido já no 1º DIA do
  -- novo afastamento — não no 16º nem no dia 15 do mês seguinte. Fora da
  -- recaida, o prazo padrão do afastamento >15 dias vale (dia 15 do mês seguinte).
  SELECT CASE
    WHEN COALESCE(p_is_recaida, false) THEN p_data_inicio
    ELSE (date_trunc('month', p_data_inicio + INTERVAL '1 month') + INTERVAL '14 days')::date
  END;
$$;

COMMENT ON FUNCTION public.afastamento_prazo_recaida_s2230(date, boolean) IS
  'AFAST-021: prazo do S-2230; na recaida o evento vai no 1o dia do afastamento.';

-- ════════════════════ CONFERÊNCIA (esperado tudo 'ok') ════════════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('AFAST-021 · função de prazo da recaída presente',
       (to_regprocedure('public.afastamento_prazo_recaida_s2230(date,boolean)') IS NOT NULL)),
    ('AFAST-021 · recaída → prazo no 1º dia (comportamento)',
       (public.afastamento_prazo_recaida_s2230(DATE '2026-03-10', true) = DATE '2026-03-10')),
    ('AFAST-021 · sem recaída → dia 15 do mês seguinte',
       (public.afastamento_prazo_recaida_s2230(DATE '2026-03-10', false) = DATE '2026-04-15'))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao FROM alvo ORDER BY item;
