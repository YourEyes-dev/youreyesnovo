-- ============================================================================
-- EFEITO DAS CINCO CORRECOES — quanto mudou, para quem, e para que lado
--
-- SOMENTE LEITURA. Nao cria, nao altera e nao apaga NADA. Pode rodar quantas
-- vezes quiser.
--
-- QUANDO RODAR
-- Depois de ter as DUAS fotografias do script_ponto_saldo_calculado_antes_
-- depois.sql (uma antes da entrega, outra depois). Sem as duas, ele NAO
-- compara e diz qual esta faltando — comparar contra uma fotografia ausente
-- acusaria todo mundo de ter perdido o saldo inteiro, um susto sem causa.
--
-- O QUE ELE RESPONDE
--   1. RESUMO — quantos colaboradores tiveram o saldo alterado, e o total de
--      minutos que a correcao devolveu (ou tirou).
--   2. POR EMPRESA — a mesma conta, por cliente, para o DP saber com quem
--      falar.
--   3. MAIORES MUDANCAS — as 20 maiores diferencas, colaborador a
--      colaborador, com o antes e o depois. E aqui que se confere com o
--      espelho, um por um.
--   4. VEREDITO — se alguma diferenca foi CONTRA o trabalhador.
--
-- COMO LER O VEREDITO
-- As cinco correcoes so podem melhorar o saldo de quem trabalha:
--   * o minuto que sumia volta (PONTO-470);
--   * a sobra de 6 a 10 min passa a contar (PONTO-353/471);
--   * dia incompleto deixa de virar debito (PONTO-473);
--   * falta deixa de debitar o banco (PONTO-474).
-- Nenhuma delas tira minuto de ninguem. Entao QUALQUER saldo que tenha PIORADO
-- e sinal de parar e investigar — o veredito acusa isso em letra clara.
--
-- Uma excecao legitima e conhecida: a correcao da tolerancia (PONTO-353) faz a
-- sobra de 6 a 10 minutos passar a contar, e a do minuto (PONTO-470) aumenta o
-- tempo apurado. Se um dia tinha DEFICIT de exatos 6 a 10 minutos que antes
-- cabia no teto diario e agora nao cabe mais... isso NAO acontece: o deficit ja
-- era absorvido so ate 5 minutos antes da mudanca. Por isso o veredito e
-- categorico: piora nenhuma.
--
-- O CPF sai mascarado (so os tres ultimos digitos): este resultado costuma ser
-- copiado para conversas e documentos.
-- ============================================================================

WITH existe AS MATERIALIZED (
  -- So compara quando as DUAS fotografias existem. Sem isso, a ausencia da
  -- fotografia "depois" apareceria como se todo mundo tivesse perdido o
  -- saldo inteiro — um PARE falso, do tipo mais assustador possivel.
  SELECT EXISTS (SELECT 1 FROM public.ponto_efeito_apuracao WHERE momento = 'antes')  AS tem_antes,
         EXISTS (SELECT 1 FROM public.ponto_efeito_apuracao WHERE momento = 'depois') AS tem_depois
),
antes AS MATERIALIZED (
  SELECT e.* FROM public.ponto_efeito_apuracao e, existe x
  WHERE e.momento = 'antes' AND x.tem_antes AND x.tem_depois
),
depois AS MATERIALIZED (
  SELECT e.* FROM public.ponto_efeito_apuracao e, existe x
  WHERE e.momento = 'depois' AND x.tem_antes AND x.tem_depois
),
par AS MATERIALIZED (
  SELECT COALESCE(a.empresa_nome, d.empresa_nome)   AS empresa,
         COALESCE(a.competencia, d.competencia)     AS competencia,
         COALESCE(a.colaborador_cpf, d.colaborador_cpf) AS cpf,
         COALESCE(a.saldo_min, 0)                   AS saldo_antes,
         COALESCE(d.saldo_min, 0)                   AS saldo_depois,
         COALESCE(d.saldo_min, 0) - COALESCE(a.saldo_min, 0) AS diferenca,
         COALESCE(a.trabalhado_min, 0)              AS trab_antes,
         COALESCE(d.trabalhado_min, 0)              AS trab_depois
  FROM antes a
  FULL JOIN depois d
    ON d.tenant_id = a.tenant_id
   AND COALESCE(d.empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)
     = COALESCE(a.empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)
   AND d.competencia = a.competencia
   AND d.colaborador_cpf = a.colaborador_cpf
),
mudou AS MATERIALIZED (
  SELECT * FROM par WHERE diferenca <> 0
)
SELECT 1 AS ordem,
       'RESUMO'::text                                                  AS bloco,
       (SELECT count(*) FROM par)::text || ' conferido(s)'             AS referencia,
       (SELECT count(*) FROM mudou)::text || ' com saldo alterado'     AS quem,
       CASE WHEN (SELECT COALESCE(SUM(diferenca), 0) FROM mudou) >= 0
            THEN '+' ELSE '' END
         || (SELECT COALESCE(SUM(diferenca), 0) FROM mudou)::text
         || ' min no total ('
         || to_char((SELECT COALESCE(SUM(diferenca), 0) FROM mudou) / 60.0, 'FM9990.0')
         || ' h)'                                                      AS valor,
       'Diferenca positiva = a correcao devolveu tempo ao trabalhador'::text AS erro_tecnico
UNION ALL
SELECT 2, 'POR EMPRESA', left(COALESCE(empresa, 'sem empresa'), 38),
       count(*)::text || ' colaborador(es)',
       CASE WHEN SUM(diferenca) >= 0 THEN '+' ELSE '' END
         || SUM(diferenca)::text || ' min',
       'Competencias ' || string_agg(DISTINCT competencia, ', ')
FROM mudou
GROUP BY empresa
UNION ALL
SELECT 3, 'MAIOR MUDANCA', left(COALESCE(empresa, '-'), 20) || ' · ' || competencia,
       '***' || right(cpf, 3),
       saldo_antes::text || ' -> ' || saldo_depois::text || ' min',
       CASE WHEN diferenca > 0
            THEN '+' || diferenca::text || ' min devolvidos'
            ELSE diferenca::text || ' min — CONFERIR, correcao nao deveria tirar tempo' END
FROM (SELECT * FROM mudou ORDER BY abs(diferenca) DESC LIMIT 20) t
UNION ALL
SELECT 9, 'VEREDITO',
       (SELECT count(*) FROM mudou WHERE diferenca < 0)::text || ' saldo(s) pioraram',
       (SELECT count(*) FROM mudou WHERE diferenca > 0)::text || ' saldo(s) melhoraram',
       CASE WHEN NOT (SELECT tem_antes AND tem_depois FROM existe) THEN 'FALTA FOTOGRAFIA'
            WHEN (SELECT count(*) FROM mudou WHERE diferenca < 0) = 0 THEN 'OK'
            ELSE 'PARE' END,
       CASE WHEN NOT (SELECT tem_antes FROM existe)
              THEN 'Nao ha fotografia "antes". Rode o script_ponto_saldo_calculado_antes_depois.sql ANTES da entrega.'
            WHEN NOT (SELECT tem_depois FROM existe)
              THEN 'Nao ha fotografia "depois". Rode o script_ponto_saldo_calculado_antes_depois.sql de novo, DEPOIS das partes da entrega — ai este arquivo tem o que comparar.'
            WHEN (SELECT count(*) FROM mudou WHERE diferenca < 0) = 0
              THEN 'OK — nenhuma correcao tirou tempo de ninguem, como esperado'
            ELSE 'PARE: ha saldo que PIOROU. Nenhuma das cinco correcoes pode reduzir o tempo apurado. Me envie as linhas do bloco MAIOR MUDANCA com diferenca negativa antes de seguir para o fechamento.' END
ORDER BY ordem, referencia;
