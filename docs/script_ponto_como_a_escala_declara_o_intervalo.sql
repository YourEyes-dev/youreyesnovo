-- ============================================================================
-- COMO A ESCALA DECLARA O INTERVALO? — e o dia 27/08 visto por dentro
--
-- SOMENTE LEITURA. Nao cria, nao altera e nao apaga NADA.
--
-- POR QUE PRECISO DISTO
-- A auditoria apontou que o dia 27/08 (duas marcacoes, 08:05 e 11:21) virou
-- 5h33 de debito no banco em vez de pendencia. Para o sistema tratar esse dia
-- como registro incompleto, ele precisa saber que aquela escala PREVE
-- intervalo — e ha mais de um jeito de a escala declarar isso:
--
--   * pelo dias_config (tem_almoco + inicio_almoco + fim_almoco por dia da
--     semana), que e de onde a apuracao tira o intervalo previsto;
--   * pela coluna intervalo_intrajornada_minutos, que a apuracao NAO le;
--   * por uma versao vigente da escala, que pode sobrescrever o dias_config.
--
-- Se eu escrever a regra olhando para o lugar errado, ela nunca dispara — e um
-- conserto que nao dispara e pior que nenhum, porque parece resolvido. Este
-- arquivo mostra qual dos caminhos esta em uso no cliente real.
--
-- COMO USAR
-- Troque o CNPJ na linha marcada com AJUSTE AQUI e me mande o resultado.
--
-- Nenhum nome ou CPF completo sai daqui.
-- ============================================================================

WITH parametros AS MATERIALIZED (
  SELECT '28.443.305/0001-97'::text AS cnpj,   -- AJUSTE AQUI
         '2026-08'::text            AS competencia
),
alvo AS MATERIALIZED (
  SELECT e.id AS empresa_id, e.tenant_id, p.competencia
  FROM public.empresa_cadastro e, parametros p
  WHERE regexp_replace(COALESCE(e.cnpj, ''), '[^0-9]', '', 'g')
      = regexp_replace(p.cnpj, '[^0-9]', '', 'g')
),
escalas AS MATERIALIZED (
  SELECT DISTINCT esc.id, esc.nome, esc.jornada_diaria_minutos,
         esc.intervalo_intrajornada_minutos,
         esc.dias_config
  FROM public.ponto_escala_atribuicoes a
  JOIN public.ponto_escalas esc ON esc.id = a.escala_id
  JOIN alvo v ON v.tenant_id = a.tenant_id
  WHERE COALESCE(a.ativa, true) = true
)
SELECT 1 AS ordem,
       'ESCALA'::text                                                    AS bloco,
       left(COALESCE(nome, 'sem nome'), 30)                              AS referencia,
       'jornada ' || COALESCE(jornada_diaria_minutos::text, '-') || ' min' AS detalhe,
       CASE
         WHEN dias_config IS NULL OR jsonb_typeof(dias_config) <> 'object'
           THEN 'dias_config VAZIO'
         WHEN EXISTS (
           SELECT 1 FROM jsonb_each(dias_config) d
           WHERE COALESCE((d.value->>'tem_almoco')::boolean, false)
             AND (d.value->>'inicio_almoco') IS NOT NULL
             AND (d.value->>'fim_almoco') IS NOT NULL)
           THEN 'dias_config DECLARA intervalo'
         ELSE 'dias_config existe, mas SEM intervalo declarado'
       END                                                               AS valor,
       'coluna intervalo_intrajornada_minutos = '
         || COALESCE(intervalo_intrajornada_minutos::text, 'nulo')
         || ' (a apuracao NAO le esta coluna)'                           AS erro_tecnico
FROM escalas
UNION ALL
SELECT 2, 'DIA DA SEMANA',
       left(COALESCE(e.nome, '-'), 20) || ' · ' || d.key,
       COALESCE(d.value->>'entrada', '-') || ' as ' || COALESCE(d.value->>'saida', '-'),
       CASE WHEN COALESCE((d.value->>'tem_almoco')::boolean, false)
            THEN 'almoco ' || COALESCE(d.value->>'inicio_almoco', '?')
                 || ' as ' || COALESCE(d.value->>'fim_almoco', '?')
            ELSE 'sem almoco declarado' END,
       'trabalha: ' || COALESCE(d.value->>'trabalha', '-')
FROM escalas e
CROSS JOIN LATERAL jsonb_each(COALESCE(e.dias_config, '{}'::jsonb)) d
WHERE jsonb_typeof(COALESCE(e.dias_config, '{}'::jsonb)) = 'object'
UNION ALL
-- Quantos dias da competencia tem menos de quatro marcacoes: e o tamanho do
-- problema que a regra nova trataria.
SELECT 3, 'DIAS COM POUCAS BATIDAS',
       to_char(d.data, 'DD/MM'),
       '***' || right(regexp_replace(COALESCE(d.colaborador_cpf, ''), '[^0-9]', '', 'g'), 3),
       (SELECT count(*) FROM public.ponto_marcacoes m
         WHERE m.tenant_id = d.tenant_id
           AND m.colaborador_cpf = d.colaborador_cpf
           AND m.data_marcacao = d.data)::text || ' marcacao(oes)',
       'situacao atual: ' || COALESCE(d.status, '-')
         || ' · intervalo: ' || COALESCE(d.intervalo_origem, 'nao declarado')
FROM public.ponto_diario d
JOIN alvo v ON v.tenant_id = d.tenant_id AND v.empresa_id = d.empresa_id
WHERE to_char(d.data, 'YYYY-MM') = v.competencia
  AND (SELECT count(*) FROM public.ponto_marcacoes m
        WHERE m.tenant_id = d.tenant_id
          AND m.colaborador_cpf = d.colaborador_cpf
          AND m.data_marcacao = d.data) BETWEEN 1 AND 3
ORDER BY ordem, referencia;
