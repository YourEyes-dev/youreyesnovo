-- =====================================================================
-- QA — Relatorio de cobertura de tela (e2e) por modulo
--
-- O verdadeiro buraco de teste nao esta no Motor (api), e nas telas: ha
-- muitos casos nivel 'e2e' documentados sem um it() do Cypress ligado pela
-- ponte qa_cobertura_e2e. Este relatorio da VISIBILIDADE a esse buraco —
-- ranqueia os modulos pela PIOR cobertura, para priorizar onde escrever
-- teste de tela primeiro. Nao escreve teste nenhum; so mostra onde faltam.
--
-- Duas funcoes somente-leitura, para rodar na tela de QA do SuperAdmin:
--   qa_cobertura_e2e_por_modulo()      -> placar por modulo (pior primeiro)
--   qa_cobertura_e2e_lacunas(modulo)   -> os casos e2e ainda SEM teste
-- =====================================================================

CREATE OR REPLACE FUNCTION public.qa_cobertura_e2e_por_modulo()
RETURNS TABLE(modulo text, e2e_total bigint, com_teste bigint, sem_teste bigint, cobertura_pct numeric)
LANGUAGE sql STABLE
AS $fn$
  SELECT m.path AS modulo,
         count(*) FILTER (WHERE ct.nivel = 'e2e')                                  AS e2e_total,
         count(*) FILTER (WHERE ct.nivel = 'e2e' AND cb.codigo IS NOT NULL)         AS com_teste,
         count(*) FILTER (WHERE ct.nivel = 'e2e' AND cb.codigo IS NULL)             AS sem_teste,
         round(100.0 * count(*) FILTER (WHERE ct.nivel = 'e2e' AND cb.codigo IS NOT NULL)
               / NULLIF(count(*) FILTER (WHERE ct.nivel = 'e2e'), 0), 1)            AS cobertura_pct
  FROM public.qa_casos_teste ct
  JOIN public.qa_modulos m ON m.id = ct.modulo_id
  LEFT JOIN (SELECT DISTINCT codigo FROM public.qa_cobertura_e2e WHERE ativo) cb
    ON cb.codigo = ct.codigo
  WHERE ct.status = 'aprovado' AND ct.nivel = 'e2e'
  GROUP BY m.path
  ORDER BY cobertura_pct ASC NULLS FIRST, e2e_total DESC;
$fn$;

COMMENT ON FUNCTION public.qa_cobertura_e2e_por_modulo() IS
  'Placar de cobertura de tela (e2e) por modulo, pior primeiro. cobertura_pct '
  'nula/zero = modulo com casos e2e documentados e nenhum teste Cypress ligado. '
  'So da visibilidade; nao cria teste.';

CREATE OR REPLACE FUNCTION public.qa_cobertura_e2e_lacunas(p_modulo text DEFAULT NULL)
RETURNS TABLE(modulo text, codigo text, titulo text, prioridade text)
LANGUAGE sql STABLE
AS $fn$
  SELECT m.path AS modulo, ct.codigo, ct.titulo, ct.prioridade::text
  FROM public.qa_casos_teste ct
  JOIN public.qa_modulos m ON m.id = ct.modulo_id
  WHERE ct.status = 'aprovado' AND ct.nivel = 'e2e'
    AND (p_modulo IS NULL OR m.path = p_modulo)
    AND NOT EXISTS (
      SELECT 1 FROM public.qa_cobertura_e2e cb WHERE cb.codigo = ct.codigo AND cb.ativo)
  ORDER BY m.path,
           CASE ct.prioridade WHEN 'critica' THEN 1 WHEN 'alta' THEN 2
                              WHEN 'media' THEN 3 ELSE 4 END,
           ct.codigo;
$fn$;

COMMENT ON FUNCTION public.qa_cobertura_e2e_lacunas(text) IS
  'Lista os casos e2e aprovados SEM teste Cypress ligado (opcionalmente de um '
  'modulo), por prioridade. E a fila de trabalho de teste de tela.';
