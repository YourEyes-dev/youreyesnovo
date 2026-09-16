-- ============================================================================
-- QUANTO MUDARIA SE AGOSTO FOSSE RECONSOLIDADO?
--
-- SOMENTE LEITURA. Nao cria, nao altera e nao apaga NADA — nem uma linha. Pode
-- rodar na producao a qualquer hora, quantas vezes quiser.
--
-- POR QUE ESTE ARQUIVO EXISTE
-- Das cinco correcoes, QUATRO ja valem para agosto sem reabrir nada: elas
-- agem na hora de calcular o saldo, e o calculo e refeito a cada consulta. A
-- unica que NAO alcanca agosto e a do minuto (o truncamento), porque ela vive
-- na consolidacao diaria — a rotina que le as marcacoes uma a uma e grava o
-- dia. Dias ja gravados so mudam se forem consolidados de novo.
--
-- Reconsolidar REESCREVE ponto_diario. Antes de reescrever qualquer coisa,
-- vale saber quanto se ganha. E o que este arquivo responde: ele chama a
-- mesma conta que a consolidacao usaria e COMPARA com o que esta gravado, sem
-- gravar nada.
--
-- COMO USAR
-- Troque a competencia na linha marcada com AJUSTE AQUI, se quiser outra.
--
-- COMO LER
--   * RESUMO — quantos dias mudariam e quantos minutos no total;
--   * POR COLABORADOR — os 25 maiores ganhos, com o antes e o depois;
--   * SEM VINCULO — colaboradores cuja empresa a consolidacao nao consegue
--     descobrir sozinha. Para eles, reconsolidar cria um dia DUPLICADO (uma
--     segunda linha, com empresa vazia), porque a chave do dia inclui a
--     empresa. Descoberto ensaiando esta reconsolidacao;
--   * VEREDITO — se algum dia PERDERIA tempo. A correcao do minuto so pode
--     somar (ela para de descartar segundos), entao qualquer perda aqui e
--     sinal de investigar antes de reconsolidar.
--
-- O CPF sai mascarado (so os tres ultimos digitos).
-- ============================================================================

SET statement_timeout = '600s';

WITH parametros AS MATERIALIZED (
  SELECT '2026-08'::text AS competencia   -- AJUSTE AQUI
),
dias AS MATERIALIZED (
  -- So quem bate ponto de verdade, em empresa com o modulo ligado. Quem nunca
  -- bateu nao tem marcacao para reler: reconsolidar essa gente e justamente o
  -- que recria falta fantasma, e por isso ela fica fora daqui.
  SELECT d.id, d.tenant_id, d.colaborador_cpf, d.colaborador_id, d.data,
         COALESCE(e.nome_fantasia, e.razao_social) AS empresa,
         d.status,
         COALESCE(floor(EXTRACT(EPOCH FROM d.horas_trabalhadas) / 60)::int, 0) AS min_gravado
  FROM public.ponto_diario d
  JOIN public.empresa_cadastro e ON e.id = d.empresa_id
  CROSS JOIN parametros p
  WHERE COALESCE(e.usa_controle_ponto, false) = true
    AND to_char(d.data, 'YYYY-MM') = p.competencia
    AND EXISTS (
      SELECT 1 FROM public.ponto_marcacoes m
      WHERE m.tenant_id = d.tenant_id
        AND m.colaborador_cpf = d.colaborador_cpf
        AND m.data_marcacao = d.data)
),
recalc AS MATERIALIZED (
  SELECT x.*,
         COALESCE(EXTRACT(EPOCH FROM c.o_horas) / 60, 0)::int AS min_recalculado,
         c.o_status                                            AS status_recalculado
  FROM dias x
  CROSS JOIN LATERAL public._ponto_calc_dia(
    x.tenant_id, x.colaborador_cpf, x.data, x.colaborador_id::uuid) c
),
mudou AS MATERIALIZED (
  SELECT * , (min_recalculado - min_gravado) AS diferenca
  FROM recalc
  WHERE min_recalculado <> min_gravado
),
por_colab AS MATERIALIZED (
  SELECT empresa, colaborador_cpf,
         count(*) AS dias_mudariam,
         SUM(diferenca) AS minutos
  FROM mudou
  GROUP BY empresa, colaborador_cpf
),
sem_empresa AS MATERIALIZED (
  -- A consolidacao descobre a empresa do colaborador por conta propria, pelo
  -- cadastro. Quando ela NAO consegue, grava o dia com empresa vazia — e como
  -- a chave do dia inclui a empresa, isso cria uma SEGUNDA linha para a mesma
  -- data em vez de atualizar a existente. Dia duplicado suja o espelho e a
  -- contagem de faltas. Estes CPFs precisam ter o vinculo arrumado ANTES de
  -- qualquer reconsolidacao.
  SELECT DISTINCT x.empresa, x.colaborador_cpf
  FROM dias x
  WHERE COALESCE(
          public.ponto_empresa_do_colaborador(x.colaborador_id::uuid),
          public.ponto_empresa_do_cpf(x.tenant_id, x.colaborador_cpf)
        ) IS NULL
)
SELECT 1 AS ordem,
       'RESUMO'::text                                                   AS bloco,
       (SELECT competencia FROM parametros)                             AS referencia,
       (SELECT count(*) FROM mudou)::text || ' dia(s) mudariam, de '
         || (SELECT count(*) FROM dias)::text || ' conferido(s)'        AS detalhe,
       CASE WHEN (SELECT COALESCE(SUM(diferenca), 0) FROM mudou) >= 0 THEN '+' ELSE '' END
         || (SELECT COALESCE(SUM(diferenca), 0) FROM mudou)::text || ' min ('
         || to_char((SELECT COALESCE(SUM(diferenca), 0) FROM mudou) / 60.0, 'FM9990.0')
         || ' h) no total'                                              AS valor,
       'Nada foi alterado — este arquivo so mede'::text                 AS erro_tecnico
UNION ALL
SELECT 2, 'POR COLABORADOR', left(COALESCE(empresa, '-'), 24),
       '***' || right(colaborador_cpf, 3) || ' — ' || dias_mudariam::text || ' dia(s)',
       CASE WHEN minutos >= 0 THEN '+' ELSE '' END || minutos::text || ' min',
       'Ganho da correcao do minuto na competencia'
FROM (SELECT * FROM por_colab ORDER BY abs(minutos) DESC LIMIT 25) t
UNION ALL
SELECT 3, 'SEM VINCULO', left(COALESCE(empresa, '-'), 24),
       '***' || right(colaborador_cpf, 3),
       'empresa nao resolvida',
       'PARE para este CPF: reconsolidar criaria um dia DUPLICADO (linha com empresa vazia). Arrume o vinculo do colaborador antes.'
FROM sem_empresa
UNION ALL
SELECT 9, 'VEREDITO',
       (SELECT count(*) FROM mudou WHERE diferenca < 0)::text || ' dia(s) perderiam tempo',
       (SELECT count(DISTINCT colaborador_cpf) FROM mudou)::text || ' colaborador(es) afetado(s)',
       CASE WHEN (SELECT count(*) FROM mudou WHERE diferenca < 0) = 0
             AND (SELECT count(*) FROM sem_empresa) = 0 THEN 'OK' ELSE 'CONFERIR' END,
       CASE WHEN (SELECT count(*) FROM sem_empresa) > 0
              THEN 'CONFERIR: ha colaborador cuja empresa a consolidacao nao resolve (bloco SEM VINCULO). Reconsolidar criaria dia DUPLICADO para ele. Arrume o vinculo antes, ou me avise para eu restringir o alvo.'
            WHEN (SELECT count(*) FROM mudou WHERE diferenca < 0) > 0
              THEN 'CONFERIR: ha dia que PERDERIA tempo ao ser reconsolidado. A correcao do minuto so pode somar; uma perda aqui vem de outra coisa (marcacao desconsiderada, ajuste, escala trocada). Me envie este resultado antes de reconsolidar.'
            ELSE 'OK — reconsolidar so somaria tempo, e todo mundo tem vinculo resolvido' END
ORDER BY ordem, referencia, detalhe;
