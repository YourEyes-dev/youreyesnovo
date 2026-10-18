-- =====================================================================
-- PORTAO / GOLDEN — Unificacao de feriados, FASE 2 (SOMENTE LEITURA)
--
-- Rode ANTES de aplicar o script da Fase 2 em cada ambiente (homologacao e,
-- depois, producao). Nao cria, nao altera, nao apaga nada.
--
-- O que prova: a Fase 2 so remove do resolver a possibilidade de o vencedor ter
-- origem='filial'. Se, com a Fase 1 ja aplicada, NENHUM vencedor de
-- feriados_da_empresa tem origem='filial' em nenhuma unidade (janela de 4 anos),
-- entao remover o ramo 'filial' nao muda saida alguma — a apuracao fica
-- identica. Checa tambem o backfill (faltando = 0).
--
-- CRITERIO PARA SEGUIR:
--   vencedores_filial = 0   E   faltando = 0
-- Qualquer valor > 0 = NAO aplicar a Fase 2 ainda (rode/revise a Fase 1).
-- =====================================================================

WITH units AS (
  SELECT DISTINCT f.tenant_id, f.empresa_id
  FROM public.feriados f
  WHERE f.abrangencia = 'filial'
    AND f.tenant_id IS NOT NULL
    AND f.empresa_id IS NOT NULL
    AND COALESCE(f.ativo, true) = true
),
janela AS (
  SELECT make_date(EXTRACT(YEAR FROM now())::int - 1, 1, 1)  AS ini,
         make_date(EXTRACT(YEAR FROM now())::int + 2, 12, 31) AS fim
),
-- (1) ainda ha vencedor 'filial' no resolver ATUAL?
venc AS (
  SELECT count(*) AS vencedores_filial
  FROM units u
  CROSS JOIN janela j
  CROSS JOIN LATERAL public.feriados_da_empresa(u.tenant_id, u.empresa_id, j.ini, j.fim) h
  WHERE h.origem = 'filial'
),
-- (2) backfill completo? (mesma conferencia da Fase 1)
fil AS (
  SELECT f.tenant_id, f.empresa_id, f.nome,
         COALESCE(f.recorrente, false) AS recorrente, f.data, f.dia, f.mes,
         (SELECT v.tabela_id FROM public.feriado_tabela_empresas v
           WHERE v.tenant_id = f.tenant_id AND v.empresa_id = f.empresa_id
           LIMIT 1) AS tabela_id
  FROM public.feriados f
  WHERE f.abrangencia = 'filial'
    AND f.tenant_id IS NOT NULL AND f.empresa_id IS NOT NULL
    AND COALESCE(f.ativo, true) = true
    AND (
      (COALESCE(f.recorrente, false) = true  AND f.dia BETWEEN 1 AND 31 AND f.mes BETWEEN 1 AND 12)
      OR (COALESCE(f.recorrente, false) = false AND f.data IS NOT NULL)
    )
),
faltando AS (
  SELECT count(*) AS faltando
  FROM fil
  WHERE fil.tabela_id IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM public.feriado_tabela_itens it
       WHERE it.tabela_id = fil.tabela_id
         AND it.nome = fil.nome
         AND COALESCE(it.recorrente, false) = fil.recorrente
         AND (
           (fil.recorrente = true  AND it.dia = fil.dia AND it.mes = fil.mes)
           OR (fil.recorrente = false AND it.data = fil.data)
         )
     )
)
SELECT venc.vencedores_filial, faltando.faltando,
       CASE WHEN venc.vencedores_filial = 0 AND faltando.faltando = 0
            THEN 'OK — pode aplicar a Fase 2'
            ELSE 'NAO aplicar — revisar a Fase 1' END AS veredito
FROM venc, faltando;
