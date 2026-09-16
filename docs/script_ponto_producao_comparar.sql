-- ============================================================================
-- PRODUCAO — COMPARACAO ANTES x DEPOIS (portoes e conferencia final)
--
-- Rode em cada PORTAO e ao final de tudo. Ele refotografa a apuracao como
-- 'depois' e devolve, competencia por competencia, o que mudou em relacao ao
-- retrato de partida.
--
-- COMO LER O RESULTADO
--   - Competencia ABERTA com diferenca: normal. Gente batendo ponto muda o
--     numero o tempo todo, e as correcoes de motor tambem agem ali.
--   - Competencia FECHADA com diferenca: PRECISA DE DECISAO DO RH. A folha
--     daquele mes ja foi paga com o numero antigo. As correcoes sao legitimas
--     (tolerancia dos dois tetos, hora extra sem truncar, adicional noturno
--     prorrogado, turno da virada, domingo em dobro, 12x36), mas o que fazer
--     com a diferenca — reprocessar, pagar em folha seguinte, ou registrar e
--     nao mexer — e decisao de gestao, nao de banco.
--   - Nenhuma diferenca em competencia fechada: nada a decidir.
--
-- A coluna minutos_diferenca e a soma algebrica: positivo, a apuracao nova
-- reconhece MAIS tempo ao colaborador; negativo, menos.
--
-- NAO altera nenhum dado de ponto, folha ou colaborador. So escreve na propria
-- tabela de fotografia. Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

DELETE FROM public.ponto_apuracao_fotografia WHERE momento = 'depois';

INSERT INTO public.ponto_apuracao_fotografia
  (momento, tenant_id, colaborador_cpf, competencia, competencia_fechada, dia,
   entrada, saida, trabalhado_min, jornada_min, saldo_min, protegido,
   equalizacao, excedente_retido_min)
SELECT 'depois', a.tenant_id, a.colaborador_cpf, a.comp,
       (f.tenant_id IS NOT NULL), s.dia,
       s.entrada, s.saida, s.trabalhado_min, s.jornada_min, s.saldo_min,
       s.protegido, s.equalizacao, s.excedente_retido_min
FROM (
  SELECT DISTINCT d.tenant_id, d.colaborador_cpf, to_char(d.data, 'YYYY-MM') AS comp
  FROM public.ponto_diario d
) a
LEFT JOIN public.ponto_fechamentos f
  ON f.tenant_id = a.tenant_id AND f.competencia = a.comp AND f.status = 'fechado'
CROSS JOIN LATERAL public.ponto_saldo_dias_competencia(
  a.tenant_id, a.colaborador_cpf, a.comp) s
ON CONFLICT (momento, tenant_id, colaborador_cpf, competencia, dia) DO NOTHING;

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Uma linha por competencia que MUDOU, as fechadas primeiro. Zero linha
-- significa que nada mudou em lugar nenhum.
-- ---------------------------------------------------------------------------
WITH antes AS MATERIALIZED (
  SELECT * FROM public.ponto_apuracao_fotografia WHERE momento = 'antes'
),
depois AS MATERIALIZED (
  SELECT * FROM public.ponto_apuracao_fotografia WHERE momento = 'depois'
),
juntos AS MATERIALIZED (
  SELECT COALESCE(a.tenant_id, d.tenant_id)             AS tenant_id,
         COALESCE(a.competencia, d.competencia)         AS competencia,
         COALESCE(a.competencia_fechada, d.competencia_fechada, false) AS fechada,
         COALESCE(a.colaborador_cpf, d.colaborador_cpf) AS cpf,
         COALESCE(a.dia, d.dia)                         AS dia,
         a.saldo_min                                    AS saldo_antes,
         d.saldo_min                                    AS saldo_depois
  FROM antes a
  FULL OUTER JOIN depois d
    ON  d.tenant_id       = a.tenant_id
    AND d.colaborador_cpf = a.colaborador_cpf
    AND d.competencia     = a.competencia
    AND d.dia             = a.dia
),
mudou AS MATERIALIZED (
  SELECT * FROM juntos
  WHERE COALESCE(saldo_antes, -2147483648) IS DISTINCT FROM COALESCE(saldo_depois, -2147483648)
)
SELECT
  CASE WHEN fechada THEN 'FECHADA — decisao do RH' ELSE 'aberta — normal' END AS situacao,
  competencia,
  count(DISTINCT cpf)                                      AS colaboradores_afetados,
  count(*)                                                 AS dias_com_diferenca,
  sum(COALESCE(saldo_depois,0) - COALESCE(saldo_antes,0))  AS minutos_diferenca,
  round(sum(COALESCE(saldo_depois,0) - COALESCE(saldo_antes,0)) / 60.0, 2) AS horas_diferenca
FROM mudou
GROUP BY fechada, competencia
ORDER BY fechada DESC, competencia;
