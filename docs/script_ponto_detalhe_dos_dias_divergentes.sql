-- ============================================================================
-- OS DIAS QUE DIVERGEM, UM A UM — o que explica cada anomalia
--
-- SOMENTE LEITURA. Nao cria, nao altera e nao apaga NADA.
--
-- POR QUE ESTE ARQUIVO EXISTE
-- A medicao da reconsolidacao (script_ponto_quanto_mudaria_reconsolidar.sql)
-- devolveu tres coisas que precisam de nome antes de qualquer decisao:
--
--   1. UM dia que PERDERIA tempo — e sozinho ele derruba o total da
--      competencia de +762 min para -8 min;
--   2. dois colaboradores com ganho muito acima dos demais (+296 e +97 min,
--      contra ~+20 dos outros). A correcao do minuto rende 1 a 2 minutos por
--      dia; ganho de 20 min/dia vem de outra coisa;
--   3. dias com menos de quatro marcacoes, que e o assunto do 27/08.
--
-- Este arquivo abre cada dia divergente e mostra, lado a lado: o que esta
-- GRAVADO, o que a conta responde AGORA, quantas marcacoes existem e quais
-- sao — que e o suficiente para dizer se a diferenca e o minuto ou outra
-- coisa.
--
-- COMO USAR
-- Troque a competencia e, se quiser olhar so uma pessoa, os tres ultimos
-- digitos do CPF nas linhas marcadas com AJUSTE AQUI. Deixe o CPF como NULL
-- para ver todos os dias divergentes da competencia.
--
-- O CPF sai mascarado. As marcacoes saem so como horario.
-- ============================================================================

SET statement_timeout = '600s';

WITH parametros AS MATERIALIZED (
  SELECT '2026-08'::text AS competencia,   -- AJUSTE AQUI
         NULL::text      AS cpf_final3     -- AJUSTE AQUI: ex.: '955', ou NULL para todos
),
dias AS MATERIALIZED (
  SELECT d.tenant_id, d.colaborador_cpf, d.colaborador_id, d.data, d.status,
         COALESCE(e.nome_fantasia, e.razao_social) AS empresa,
         d.entrada, d.saida, d.intervalo_origem,
         COALESCE(floor(EXTRACT(EPOCH FROM d.horas_trabalhadas) / 60)::int, 0) AS min_gravado
  FROM public.ponto_diario d
  JOIN public.empresa_cadastro e ON e.id = d.empresa_id
  CROSS JOIN parametros p
  WHERE COALESCE(e.usa_controle_ponto, false) = true
    AND to_char(d.data, 'YYYY-MM') = p.competencia
    AND (p.cpf_final3 IS NULL
         OR right(regexp_replace(COALESCE(d.colaborador_cpf, ''), '[^0-9]', '', 'g'), 3) = p.cpf_final3)
    AND EXISTS (
      SELECT 1 FROM public.ponto_marcacoes m
      WHERE m.tenant_id = d.tenant_id
        AND m.colaborador_cpf = d.colaborador_cpf
        AND m.data_marcacao = d.data)
),
recalc AS MATERIALIZED (
  SELECT x.*,
         COALESCE(EXTRACT(EPOCH FROM c.o_horas) / 60, 0)::int AS min_recalculado,
         c.o_status AS status_recalculado,
         (SELECT count(*) FROM public.ponto_marcacoes m
           WHERE m.tenant_id = x.tenant_id
             AND m.colaborador_cpf = x.colaborador_cpf
             AND m.data_marcacao = x.data)                     AS marcacoes,
         (SELECT string_agg(to_char(m.hora_marcacao, 'HH24:MI'), ' ' ORDER BY m.hora_marcacao)
            FROM public.ponto_marcacoes m
           WHERE m.tenant_id = x.tenant_id
             AND m.colaborador_cpf = x.colaborador_cpf
             AND m.data_marcacao = x.data
             AND NOT COALESCE(m.desconsiderada, false))        AS batidas,
         (SELECT count(*) FROM public.ponto_marcacoes m
           WHERE m.tenant_id = x.tenant_id
             AND m.colaborador_cpf = x.colaborador_cpf
             AND m.data_marcacao = x.data
             AND COALESCE(m.desconsiderada, false))            AS descartadas
  FROM dias x
  CROSS JOIN LATERAL public._ponto_calc_dia(
    x.tenant_id, x.colaborador_cpf, x.data, x.colaborador_id::uuid) c
)
SELECT
  to_char(data, 'DD/MM')                                              AS dia,
  left(COALESCE(empresa, '-'), 18)                                    AS empresa,
  '***' || right(regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g'), 3) AS cpf,
  min_gravado::text || ' -> ' || min_recalculado::text || ' min'      AS gravado_recalculado,
  CASE WHEN (min_recalculado - min_gravado) >= 0 THEN '+' ELSE '' END
    || (min_recalculado - min_gravado)::text || ' min'                AS diferenca,
  marcacoes::text || ' batida(s)'
    || CASE WHEN descartadas > 0 THEN ' (+' || descartadas::text || ' descartada(s))' ELSE '' END
    || COALESCE(': ' || batidas, '')                                  AS registro,
  COALESCE(status, '-') || ' -> ' || COALESCE(status_recalculado, '-') AS situacao,
  CASE
    WHEN status = 'justificado'
      OR EXISTS (SELECT 1 FROM public.atestados a
                  WHERE a.tenant_id = recalc.tenant_id
                    AND regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g')
                      = regexp_replace(COALESCE(recalc.colaborador_cpf, ''), '[^0-9]', '', 'g')
                    AND a.data_inicio_afastamento IS NOT NULL
                    AND a.data_inicio_afastamento <= recalc.data
                    AND COALESCE(a.data_fim_afastamento, a.data_inicio_afastamento) >= recalc.data)
      THEN 'JA TRATADO: dia de abono/atestado, com marcacao da parte trabalhada. Correto como esta — a reconsolidacao NAO toca (recontaria o tempo). Nao e ganho do minuto.'
    WHEN descartadas > 0
      THEN 'Ha marcacao DESCONSIDERADA no dia: o valor gravado vem de um registro que hoje nao conta mais.'
    WHEN marcacoes < 4 AND intervalo_origem IS DISTINCT FROM 'pre_assinalado'
      THEN 'Menos de quatro batidas e sem pre-assinalacao: o intervalo nao foi registrado.'
    WHEN abs(min_recalculado - min_gravado) <= 3
      THEN 'Diferenca compativel com o minuto descartado (ate ~2 min/dia).'
    ELSE 'Diferenca GRANDE demais para o minuto: o valor gravado nao vem destas marcacoes. Conferir antes de reconsolidar.'
  END                                                                 AS erro_tecnico
FROM recalc
WHERE min_recalculado <> min_gravado
ORDER BY abs(min_recalculado - min_gravado) DESC, data;
