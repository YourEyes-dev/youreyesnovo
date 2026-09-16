-- ============================================================================
-- CONFERENCIA DE EFEITO — a entrega funcionou, e mexeu so onde devia?
--
-- QUANDO RODAR
-- No SQL Editor do MESMO ambiente, DEPOIS das partes da entrega, tendo o
-- retrato tirado ANTES (script_ponto_retrato_antes.sql). Sem o retrato, a
-- primeira secao nao tem com o que comparar e o script avisa.
--
-- SOMENTE LEITURA. Nao cria, nao altera e nao apaga nada — nem uma linha.
-- Pode rodar quantas vezes quiser, a qualquer hora.
--
-- O QUE ELE RESPONDE, EM TRES SECOES
--
-- 1) O PASSADO NAO FOI REESCRITO
--    Compara competencia por competencia o que o retrato guardou com o que
--    esta na base agora. Competencia ja apurada tem de bater NUMERO A NUMERO.
--    Qualquer diferenca aqui e sinal de parar: significa que a entrega mexeu
--    em espelho que o colaborador ja viu (Sumula 338) e em dado que ja virou
--    folha. A unica diferenca legitima e no mes CORRENTE, que segue vivo.
--
-- 2) O QUE MUDA DE VERDADE, E POR QUE
--    Reapura em paralelo (sem gravar) os dias do mes corrente a partir das
--    marcacoes e compara com o que esta guardado. Cada linha divergente sai
--    com colaborador, data, minutos antes, minutos depois e a diferenca —
--    e um indicativo do motivo (feriado no dia, intervalo, tolerancia).
--    E aqui que se enxerga o dinheiro se mexer ANTES de virar folha.
--
-- 3) AS TRAVAS ESTAO ATIVAS
--    Confere pelo nome E pelo corpo as protecoes que a entrega instala:
--    gatilhos, indices e regras. Peca presente mas em versao antiga aparece
--    como ausente, que e o que interessa saber.
--
-- COMO LER O RESULTADO
-- Uma linha por achado, agrupada por secao, e uma linha final de VEREDITO.
-- Secao 1 com qualquer linha = PARE. Secao 2 com linhas = normal, e a lista
-- para conferir com o DP. Secao 3 com linhas = alguma parte nao chegou.
-- ============================================================================

SET lock_timeout = '10s';

-- Guarda: sem o retrato nao ha secao 1. Aqui a interrupcao e desejada — o
-- script nao grava nada, entao nao ha trabalho a perder, e a mensagem diz o
-- que fazer em vez de o editor reclamar de uma tabela que nao existe.
DO $guarda$
BEGIN
  IF to_regclass('public.ponto_retrato_pre') IS NULL THEN
    RAISE EXCEPTION 'Nao existe retrato neste ambiente. Rode antes o script_ponto_retrato_antes.sql — e, numa entrega, rode-o ANTES de aplicar as partes. Nada foi conferido.';
  END IF;
END $guarda$;

WITH retrato AS MATERIALIZED (
  SELECT r.*
  FROM public.ponto_retrato_pre r
  WHERE r.tirado_em = (SELECT max(tirado_em) FROM public.ponto_retrato_pre)
),

-- ---------------------------------------------------------------------
-- 1) O PASSADO NAO FOI REESCRITO
-- ---------------------------------------------------------------------
-- O retrato guarda uma linha por EMPRESA; a comparacao e por colaborador e
-- competencia. Somar antes de comparar e o que evita acusar diferenca onde ha
-- apenas dois vinculos do mesmo trabalhador — o caso do PONTO-394.
retrato_agr AS MATERIALIZED (
  SELECT r.tenant_id, r.competencia, r.colaborador_cpf,
         sum(r.dias)::bigint            AS dias,
         sum(r.trabalhadas_min)::bigint AS trabalhadas_min,
         sum(r.espelhos)::bigint        AS espelhos
  FROM retrato r
  GROUP BY 1, 2, 3
),
agora AS MATERIALIZED (
  SELECT d.tenant_id,
         to_char(d.data, 'YYYY-MM')                                          AS competencia,
         d.colaborador_cpf,
         count(*)::bigint                                                    AS dias,
         sum(COALESCE(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60, 0))::bigint AS trabalhadas_min
  FROM public.ponto_diario d
  WHERE d.data >= (date_trunc('month', CURRENT_DATE) - INTERVAL '12 months')::date
  GROUP BY 1, 2, 3
),
espelhos_agora AS MATERIALIZED (
  SELECT e.tenant_id, e.competencia, e.colaborador_cpf, count(*)::bigint AS espelhos
  FROM public.ponto_espelhos e
  GROUP BY 1, 2, 3
),
passado AS MATERIALIZED (
  SELECT COALESCE(r.competencia, a.competencia)      AS competencia,
         COALESCE(r.colaborador_cpf, a.colaborador_cpf) AS cpf,
         COALESCE(r.dias, 0)                         AS dias_antes,
         COALESCE(a.dias, 0)                         AS dias_agora,
         COALESCE(r.trabalhadas_min, 0)              AS min_antes,
         COALESCE(a.trabalhadas_min, 0)              AS min_agora,
         COALESCE(r.espelhos, 0)                     AS esp_antes,
         COALESCE(e.espelhos, 0)                     AS esp_agora
  FROM retrato_agr r
  FULL JOIN agora a
    ON a.tenant_id = r.tenant_id
   AND a.competencia = r.competencia
   AND a.colaborador_cpf = r.colaborador_cpf
  LEFT JOIN espelhos_agora e
    ON e.tenant_id      = COALESCE(r.tenant_id, a.tenant_id)
   AND e.competencia    = COALESCE(r.competencia, a.competencia)
   AND e.colaborador_cpf = COALESCE(r.colaborador_cpf, a.colaborador_cpf)
  WHERE COALESCE(r.competencia, a.competencia) < to_char(CURRENT_DATE, 'YYYY-MM')
),
secao1 AS MATERIALIZED (
  SELECT '1. PASSADO REESCRITO'::text                                  AS secao,
         competencia                                                   AS referencia,
         'CPF ...' || right(regexp_replace(cpf, '\D', '', 'g'), 3)                                    AS quem,
         format('antes %s dias / %s min / %s espelho(s) — agora %s dias / %s min / %s espelho(s)',
                dias_antes, min_antes, esp_antes,
                dias_agora, min_agora, esp_agora)                      AS detalhe,
         'PARE: competencia ja apurada mudou. Espelho entregue e dado que virou folha nao podem mudar por baixo dos panos.'::text AS o_que_fazer
  FROM passado
  WHERE dias_antes IS DISTINCT FROM dias_agora
     OR min_antes  IS DISTINCT FROM min_agora
     OR esp_antes  IS DISTINCT FROM esp_agora
  LIMIT 50
),

-- ---------------------------------------------------------------------
-- 2) O QUE MUDA DE VERDADE NO MES CORRENTE
-- ---------------------------------------------------------------------
recalculo AS MATERIALIZED (
  SELECT d.colaborador_cpf,
         d.data,
         COALESCE(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60, 0)::int  AS min_guardado,
         COALESCE(EXTRACT(EPOCH FROM c.o_horas)/60, 0)::int            AS min_recalculado,
         d.status                                                      AS status_guardado,
         c.o_status                                                    AS status_recalculado,
         (c.o_salm IS NOT NULL AND c.o_ralm IS NOT NULL)               AS intervalo_batido
  FROM public.ponto_diario d
  CROSS JOIN LATERAL public._ponto_calc_dia(d.tenant_id, d.colaborador_cpf, d.data, d.colaborador_id) c
  WHERE d.data >= date_trunc('month', CURRENT_DATE)::date
    AND EXISTS (SELECT 1 FROM public.ponto_marcacoes m
                WHERE m.tenant_id = d.tenant_id
                  AND m.colaborador_cpf = d.colaborador_cpf
                  AND m.data_marcacao = d.data)
),
secao2 AS MATERIALIZED (
  SELECT '2. MUDA NO MES ABERTO'::text                                 AS secao,
         to_char(data, 'DD/MM/YYYY')                                   AS referencia,
         'CPF ...' || right(regexp_replace(colaborador_cpf, '\D', '', 'g'), 3)                        AS quem,
         format('%s min guardados x %s min reapurados (%s%s min)%s',
                min_guardado, min_recalculado,
                CASE WHEN min_recalculado >= min_guardado THEN '+' ELSE '' END,
                min_recalculado - min_guardado,
                CASE WHEN intervalo_batido THEN ' — intervalo batido no dia' ELSE '' END) AS detalhe,
         CASE
           WHEN status_guardado IS DISTINCT FROM status_recalculado
             THEN format('Confira com o DP: a situacao do dia passa de %s para %s.',
                         COALESCE(status_guardado,'-'), COALESCE(status_recalculado,'-'))
           WHEN min_recalculado > min_guardado
             THEN 'Confira com o DP: o dia passa a contar MAIS tempo — verba a pagar que antes nao aparecia.'
           ELSE 'Confira com o DP: o dia passa a contar MENOS tempo — confirme a regra antes de fechar a competencia.'
         END                                                           AS o_que_fazer
  FROM recalculo
  WHERE min_guardado IS DISTINCT FROM min_recalculado
     OR status_guardado IS DISTINCT FROM status_recalculado
  ORDER BY abs(min_recalculado - min_guardado) DESC
  LIMIT 50
),

-- ---------------------------------------------------------------------
-- 3) AS TRAVAS ESTAO ATIVAS
-- ---------------------------------------------------------------------
travas (tipo, nome, marcador, porque) AS MATERIALIZED (
  VALUES
    ('indice',  'unique_ponto_diario', 'empresa_id',
     'Dois vinculos do mesmo trabalhador so coexistem se a empresa estiver na chave da apuracao (PONTO-394).'),
    ('gatilho', 'trg_ponto_bloquear_marcacao_futura', NULL,
     'Sem ela, grava-se o ponto de amanha por API ou SQL, e a fidelidade que a Portaria 671 exige cai por terra.'),
    ('gatilho', 'trg_ponto_atribuir_nsr', NULL,
     'Sem NSR nao ha serie continua e o AFD nao fecha na fiscalizacao.'),
    ('gatilho', 'trg_ponto_diario_pre_assinalacao', NULL,
     'E o que faz a batida real do almoco vencer o intervalo declarado (Sumula 338, III).'),
    ('funcao',  'ponto_banco_regime_vigente', NULL,
     'Guardiao do instrumento: sem ele, hora extra vai para banco sem lastro, quando era devida em dinheiro.'),
    ('funcao',  'ponto_feriado_adicional_competencia', NULL,
     'Sem ela o feriado trabalhado sai como dia comum, sem a dobra, em silencio (Lei 605/49; Sumula 146).'),
    ('funcao',  'ponto_saldo_dias_competencia_bruto', NULL,
     'E a fonte que prova que o agrupamento por dia nao alterou um dia normal.'),
    ('funcao',  'ponto_vigilancias_diarias', NULL,
     'Vigilancia que ninguem chama e alerta que nunca chega: o painel fica limpo por omissao.'),
    ('funcao',  'ponto_atestado_encaminhar_afastamento', 'bloco PROPRIO',
     'Na versao antiga, o aviso repetido desfazia o afastamento do INSS do 16o dia (Lei 8.213, arts. 59-60).'),
    ('tabela',  'feriado_folga_compensatoria', NULL,
     'Sem ela nao ha como provar a compensacao e afastar o pagamento em dobro.'),
    ('tabela',  'ponto_dossies_fiscalizacao', NULL,
     'E a peca que se apresenta ao Auditor-Fiscal.')
),
secao3 AS MATERIALIZED (
  SELECT '3. TRAVA AUSENTE'::text                                      AS secao,
         t.tipo                                                        AS referencia,
         t.nome                                                        AS quem,
         'nao encontrada neste ambiente (ou em versao anterior a da entrega)'::text AS detalhe,
         t.porque                                                      AS o_que_fazer
  FROM travas t
  WHERE NOT (
    CASE t.tipo
      WHEN 'indice' THEN EXISTS (SELECT 1 FROM pg_indexes i
                                  WHERE i.schemaname = 'public' AND i.indexname = t.nome
                                    AND (t.marcador IS NULL OR i.indexdef ILIKE '%' || t.marcador || '%'))
      WHEN 'gatilho' THEN EXISTS (SELECT 1 FROM pg_trigger g
                                   WHERE NOT g.tgisinternal AND g.tgname = t.nome)
      WHEN 'funcao' THEN EXISTS (SELECT 1 FROM pg_proc p
                                  JOIN pg_namespace n ON n.oid = p.pronamespace
                                 WHERE n.nspname = 'public' AND p.proname = t.nome
                                   AND (t.marcador IS NULL OR p.prosrc LIKE '%' || t.marcador || '%'))
      WHEN 'tabela' THEN to_regclass('public.' || t.nome) IS NOT NULL
    END
  )
),

tudo AS MATERIALIZED (
  SELECT * FROM secao1
  UNION ALL SELECT * FROM secao2
  UNION ALL SELECT * FROM secao3
)

SELECT secao, referencia, quem, detalhe, o_que_fazer FROM tudo
UNION ALL
SELECT
  'VEREDITO',
  CASE WHEN (SELECT count(*) FROM retrato) = 0 THEN 'sem retrato'
       ELSE 'retrato de ' || to_char((SELECT max(tirado_em) FROM public.ponto_retrato_pre), 'DD/MM/YYYY') END,
  format('%s no passado, %s no mes aberto, %s trava(s) ausente(s)',
         (SELECT count(*) FROM secao1), (SELECT count(*) FROM secao2), (SELECT count(*) FROM secao3)),
  CASE WHEN (SELECT count(*) FROM retrato) = 0
       THEN 'Sem retrato guardado: a secao 1 nao pode ser conferida. Rode o retrato antes da proxima entrega.'
       ELSE 'Secoes conferidas com o retrato mais recente.' END,
  CASE
    WHEN (SELECT count(*) FROM secao1) > 0
      THEN 'PARE — competencia ja apurada mudou. Nao siga para a proxima parte nem para a folha antes de entender cada linha da secao 1.'
    WHEN (SELECT count(*) FROM secao3) > 0
      THEN 'CONFERIR — a entrega chegou incompleta: veja as travas ausentes na secao 3.'
    WHEN (SELECT count(*) FROM secao2) > 0
      THEN 'OK COM LISTA — o passado esta intacto e as travas ativas. Os dias da secao 2 sao a mudanca esperada: leve a lista ao DP antes de fechar a competencia.'
    ELSE 'OK — passado intacto, travas ativas e nenhum dia do mes aberto muda de resultado.'
  END
ORDER BY 1, 2, 3;
