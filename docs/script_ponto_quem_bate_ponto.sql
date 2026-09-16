-- ============================================================================
-- QUEM BATE PONTO DE VERDADE — por empresa, no ano corrente
--
-- POR QUE ESTE LEVANTAMENTO
-- O retrato da producao (01/09) mostrou 100.690 dias de FALTA em 105.554 dias
-- apurados. A causa mecanica esta identificada: a tarefa diaria
-- ponto_materializar_faltas cria o dia como falta para todo colaborador
-- cadastrado que nao bateu ponto na vespera. A pergunta que sobra e de
-- negocio, nao de codigo: dessas pessoas, quantas DEVERIAM estar batendo?
--
-- Isso importa agora porque o DSR — desconto do repouso por falta
-- injustificada (Lei 605/49, art. 6) — passou a existir na producao. Ele nao
-- roda sozinho, mas quando a folha for exportada, cada falta vira desconto.
-- Descontar repouso de quem nunca deveria marcar ponto e erro caro e visivel
-- no contracheque.
--
-- O QUE ESTE ARQUIVO RESPONDE, POR EMPRESA
--   * quantos colaboradores tem apuracao no ano;
--   * quantos deles marcaram ponto ao menos uma vez;
--   * quantos nunca marcaram — e quantos dias de falta isso gerou;
--   * a leitura provavel de cada caso.
--
-- SOMENTE LEITURA. Nao cria, nao altera e nao apaga nada. Nao mostra nome nem
-- CPF de ninguem: so contagens por empresa.
-- ============================================================================

WITH base AS MATERIALIZED (
  SELECT d.tenant_id,
         d.empresa_id,
         d.colaborador_cpf,
         count(*)                                        AS dias,
         count(*) FILTER (WHERE d.status = 'falta')      AS faltas
  FROM public.ponto_diario d
  WHERE d.data >= date_trunc('year', CURRENT_DATE)::date
  GROUP BY 1, 2, 3
),
marcou AS MATERIALIZED (
  SELECT DISTINCT m.tenant_id, m.colaborador_cpf
  FROM public.ponto_marcacoes m
  WHERE m.data_marcacao >= date_trunc('year', CURRENT_DATE)::date
),
por_empresa AS MATERIALIZED (
  SELECT b.empresa_id,
         count(*)                                                        AS colaboradores,
         count(*) FILTER (WHERE k.colaborador_cpf IS NOT NULL)           AS com_marcacao,
         count(*) FILTER (WHERE k.colaborador_cpf IS NULL)               AS sem_marcacao,
         sum(b.faltas) FILTER (WHERE k.colaborador_cpf IS NULL)          AS faltas_de_quem_nunca_marcou,
         sum(b.faltas)                                                   AS faltas_total
  FROM base b
  LEFT JOIN marcou k
    ON k.tenant_id = b.tenant_id AND k.colaborador_cpf = b.colaborador_cpf
  GROUP BY b.empresa_id
)
SELECT empresa, colaboradores, marcaram_no_ano, nunca_marcaram,
       faltas_de_quem_nunca_marcou, leitura
FROM (
SELECT 1                                                                 AS ordem,
       CASE
         WHEN e.razao_social IS NOT NULL THEN left(e.razao_social, 40)
         WHEN p.empresa_id IS NULL       THEN '(apuracao sem empresa no registro)'
         ELSE '(empresa nao encontrada no cadastro: ' || left(p.empresa_id::text, 8) || ')'
       END                                                               AS empresa,
       p.colaboradores                                                   AS colaboradores,
       p.com_marcacao                                                    AS marcaram_no_ano,
       p.sem_marcacao                                                    AS nunca_marcaram,
       COALESCE(p.faltas_de_quem_nunca_marcou, 0)                        AS faltas_de_quem_nunca_marcou,
       CASE
         WHEN p.colaboradores = 0 THEN '-'
         WHEN p.com_marcacao = 0
           THEN 'NINGUEM marca ponto nesta empresa — ou o modulo nao e usado, ou o quadro e todo dispensado de controle'
         WHEN p.sem_marcacao = 0
           THEN 'Todo mundo marca — falta aqui e falta de verdade'
         WHEN p.sem_marcacao::numeric / p.colaboradores >= 0.9
           THEN 'Quase ninguem marca: so ' || p.com_marcacao || ' de ' || p.colaboradores
             || '. Conferir enquadramento do art. 62 e cadastro antes de qualquer desconto de DSR'
         ELSE 'Uso parcial: ' || p.com_marcacao || ' de ' || p.colaboradores
             || ' marcam. Separar quem e controlado de quem nao e'
       END                                                               AS leitura
FROM por_empresa p
LEFT JOIN public.empresa_cadastro e ON e.id = p.empresa_id
UNION ALL
SELECT 0, 'TOTAL NO ANO',
       sum(colaboradores),
       sum(com_marcacao),
       sum(sem_marcacao),
       COALESCE(sum(faltas_de_quem_nunca_marcou), 0),
       'Cada falta de quem nunca marcou vira desconto de repouso se a folha for exportada com DSR'
FROM por_empresa
) t
ORDER BY t.ordem, t.colaboradores DESC;
