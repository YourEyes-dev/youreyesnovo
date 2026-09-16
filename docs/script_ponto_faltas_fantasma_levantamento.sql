-- ============================================================================
-- FALTAS FANTASMA — o que SERIA apagado, e o que NAO seria
--
-- SOMENTE LEITURA. Nao cria, nao altera e nao apaga NADA. E o levantamento que
-- vem antes da limpeza: mostra o volume exato para o numero ser aprovado antes
-- de qualquer exclusao.
--
-- O QUE E "FALTA FANTASMA"
-- O dia que a tarefa diaria criou como FALTA para colaborador de empresa que
-- nao usa o controle de ponto — gente que nunca bateu e nunca deveria bater.
-- Sao 99.251 dias assim, e cada um vira desconto de repouso (DSR) no dia em
-- que a folha for exportada.
--
-- OS CINCO FILTROS DO ALVO (acordados em 01/09/2026)
--   1. so dias com situacao FALTA — dia trabalhado, justificado, ferias ou
--      atestado nao entra;
--   2. so colaboradores que NUNCA bateram ponto — quem bateu uma vez tem
--      historico legitimo e fica intocado;
--   3. so empresas com o controle de ponto DESLIGADO — as sete ativas ficam
--      inteiramente de fora;
--   4. FORA competencias ja fechadas — competencia fechada nao se mexe
--      (Sumula 338 do TST);
--   5. FORA dias com espelho emitido ou com ajuste registrado — se alguem
--      tratou o dia, ele nao e lixo.
--
-- COMO LER O RESULTADO
--   * a linha RESUMO traz o total do alvo;
--   * as linhas ALVO mostram o volume por competencia;
--   * as linhas PRESERVADO mostram, filtro por filtro, quantos dias de falta
--     NAO seriam tocados e por que. E a prova de que a rede esta funcionando.
-- ============================================================================

WITH faltas AS MATERIALIZED (
  SELECT d.id, d.tenant_id, d.empresa_id, d.data, d.colaborador_cpf,
         regexp_replace(COALESCE(d.colaborador_cpf, ''), '[^0-9]', '', 'g') AS cpf,
         to_char(d.data, 'YYYY-MM') AS competencia
  FROM public.ponto_diario d
  WHERE d.status = 'falta'
),
bateu AS MATERIALIZED (
  SELECT DISTINCT m.tenant_id,
         regexp_replace(COALESCE(m.colaborador_cpf, ''), '[^0-9]', '', 'g') AS cpf
  FROM public.ponto_marcacoes m
  WHERE COALESCE(m.colaborador_cpf, '') <> ''
),
classificado AS MATERIALIZED (
  SELECT f.*,
         CASE
           WHEN f.empresa_id IS NULL
             THEN 'PRESERVADO: apuracao sem empresa no registro (nao da para saber se a empresa usa ponto)'
           WHEN e.id IS NULL
             THEN 'PRESERVADO: empresa da apuracao nao existe no cadastro'
           WHEN e.usa_controle_ponto IS TRUE
             THEN 'PRESERVADO: empresa USA o controle de ponto'
           WHEN b.cpf IS NOT NULL
             THEN 'PRESERVADO: colaborador ja bateu ponto alguma vez'
           WHEN EXISTS (SELECT 1 FROM public.ponto_fechamentos fe
                         WHERE fe.tenant_id = f.tenant_id
                           AND fe.competencia = f.competencia
                           AND fe.status = 'fechado'
                           AND (fe.empresa_id IS NULL OR fe.empresa_id = f.empresa_id))
             THEN 'PRESERVADO: competencia ja fechada'
           WHEN EXISTS (SELECT 1 FROM public.ponto_espelhos es
                         WHERE es.tenant_id = f.tenant_id
                           AND es.competencia = f.competencia
                           AND regexp_replace(COALESCE(es.colaborador_cpf,''), '[^0-9]', '', 'g') = f.cpf)
             THEN 'PRESERVADO: espelho ja emitido na competencia'
           WHEN EXISTS (SELECT 1 FROM public.ponto_ajustes aj
                         WHERE aj.tenant_id = f.tenant_id
                           AND aj.data_referencia = f.data
                           AND regexp_replace(COALESCE(aj.colaborador_cpf,''), '[^0-9]', '', 'g') = f.cpf)
             THEN 'PRESERVADO: dia tem ajuste registrado'
           ELSE 'ALVO'
         END AS destino
  FROM faltas f
  LEFT JOIN public.empresa_cadastro e ON e.id = f.empresa_id
  LEFT JOIN bateu b ON b.tenant_id = f.tenant_id AND b.cpf = f.cpf
),
alvo AS MATERIALIZED (
  SELECT * FROM classificado WHERE destino = 'ALVO'
)
SELECT 0 AS ordem,
       'RESUMO'::text                                                    AS bloco,
       'dias de falta na base: ' || (SELECT count(*) FROM classificado)::text AS referencia,
       (SELECT count(*) FROM alvo)::text || ' dia(s) no ALVO'            AS dias,
       (SELECT count(DISTINCT cpf) FROM alvo)::text || ' colaborador(es), '
         || (SELECT count(DISTINCT empresa_id) FROM alvo)::text || ' empresa(s)' AS quem,
       'Confira este numero antes de autorizar a limpeza. Nada foi alterado.'::text AS observacao
UNION ALL
SELECT 1,
       'ALVO',
       competencia,
       count(*)::text || ' dia(s)',
       count(DISTINCT cpf)::text || ' colaborador(es), '
         || count(DISTINCT empresa_id)::text || ' empresa(s)',
       'Faltas criadas pelo sistema para quem nunca bateu ponto em empresa que nao usa o modulo'
FROM alvo
GROUP BY competencia
UNION ALL
SELECT 2,
       'PRESERVADO',
       left(destino, 60),
       count(*)::text || ' dia(s)',
       count(DISTINCT cpf)::text || ' colaborador(es)',
       'Fica exatamente como esta'
FROM classificado
WHERE destino <> 'ALVO'
GROUP BY destino
ORDER BY ordem, referencia DESC;
