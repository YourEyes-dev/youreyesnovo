-- ============================================================================
-- QA — LOTE 0: religar rotinas "sem vinculo ativo" na producao.
--
-- Estas 24 rotinas JA EXISTEM como funcao na producao; so o vinculo em
-- qa_implementacoes estava inativo/ausente. Religar so mexe na tabela de
-- METADADOS do motor de QA — nao cria funcao, nao toca em dado de negocio.
-- Idempotente. No dev, 23 passam e 1 (EMP-050) falha por ACHADO REAL (o
-- recalculo de cota nao conta das admissoes) — nao e defeito da rotina.
-- ============================================================================

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
  ('EMP-050','qa_caso_emp_050', true),
  ('FERIAS-015','qa_caso_ferias_015', true),
  ('FERIAS-017','qa_caso_ferias_017', true),
  ('FERIAS-033','qa_caso_ferias_033', true),
  ('FERIAS-055','qa_caso_ferias_055', true),
  ('FERIAS-060','qa_caso_ferias_060', true),
  ('FERIAS-061','qa_caso_ferias_061', true),
  ('FERIAS-062','qa_caso_ferias_062', true),
  ('FERIAS-080','qa_caso_ferias_080', true),
  ('FERIAS-081','qa_caso_ferias_081', true),
  ('FERIAS-082','qa_caso_ferias_082', true),
  ('PONTO-004','qa_caso_ponto_004', true),
  ('PONTO-023','qa_caso_ponto_023', true),
  ('PONTO-210','qa_caso_ponto_210', true),
  ('PONTO-380','qa_caso_ponto_380', true),
  ('PONTO-383','qa_caso_ponto_383', true),
  ('PONTO-391','qa_caso_ponto_391', true),
  ('PONTO-395','qa_caso_ponto_395', true),
  ('PONTO-396','qa_caso_ponto_396', true),
  ('PONTO-401','qa_caso_ponto_401', true),
  ('PONTO-402','qa_caso_ponto_402', true),
  ('PONTO-410','qa_caso_ponto_410', true),
  ('PONTO-421','qa_caso_ponto_421', true),
  ('PONTO-451','qa_caso_ponto_451', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- Conferencia: roda as 24 e mostra a situacao de cada uma.
WITH alvo(codigo) AS (VALUES
  ('EMP-050'),('FERIAS-015'),('FERIAS-017'),('FERIAS-033'),('FERIAS-055'),
  ('FERIAS-060'),('FERIAS-061'),('FERIAS-062'),('FERIAS-080'),('FERIAS-081'),
  ('FERIAS-082'),('PONTO-004'),('PONTO-023'),('PONTO-210'),('PONTO-380'),
  ('PONTO-383'),('PONTO-391'),('PONTO-395'),('PONTO-396'),('PONTO-401'),
  ('PONTO-402'),('PONTO-410'),('PONTO-421'),('PONTO-451'))
SELECT a.codigo,
       (public.qa_executar_descartavel(i.funcao_sql)).situacao::text AS situacao
FROM alvo a
JOIN public.qa_implementacoes i ON i.codigo = a.codigo
ORDER BY situacao, a.codigo;
