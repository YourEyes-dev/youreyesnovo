WITH deps AS (
  SELECT 1 ord, 'qa_rls.conta_auth existe' AS item, (to_regprocedure('qa_rls.conta_auth(text)') IS NOT NULL)::text AS r
  UNION ALL SELECT 1, 'qa_rls.conta_anon existe', (to_regprocedure('qa_rls.conta_anon(text)') IS NOT NULL)::text
  UNION ALL SELECT 1, 'qa_mky_claims existe', (to_regprocedure('public.qa_mky_claims(uuid)') IS NOT NULL)::text
  UNION ALL SELECT 1, 'qa_mky_especialista existe', (to_regprocedure('public.qa_mky_especialista(text,text)') IS NOT NULL)::text
  UNION ALL SELECT 1, 'qa_mky_usuario_empresa existe', (to_regprocedure('public.qa_mky_usuario_empresa(uuid,text)') IS NOT NULL)::text
  UNION ALL SELECT 1, 'cercado (qa_sandbox_tenant_id)', COALESCE(public.qa_sandbox_tenant_id()::text,'NULL')
),
erros AS (
  SELECT 2 ord, t.codigo AS item, x.situacao::text||' :: '||COALESCE(x.erro_tecnico, x.obtido) AS r
  FROM (VALUES ('MKY-091','qa_caso_mky_091'),('PONTO-HOM-F2','qa_caso_ponto_hom_f2'),
               ('RLS-002','qa_caso_rls_002'),('RLS-003','qa_caso_rls_003'),('RLS-004','qa_caso_rls_004'),
               ('RLS-005','qa_caso_rls_005'),('RLS-006','qa_caso_rls_006'),('RLS-007','qa_caso_rls_007')) t(codigo,funcao),
  LATERAL public.qa_executar_descartavel(t.funcao) x
)
SELECT item, r FROM (SELECT * FROM deps UNION ALL SELECT * FROM erros) z ORDER BY ord, item;
