-- HOMOLOGAÇÃO — somente leitura: há dados para testar a assinatura do espelho
-- na "Metalúrgica Exemplo" com o usuário informado?
WITH emp AS MATERIALIZED (
  SELECT ec.id, ec.tenant_id, ec.razao_social, ec.nome_fantasia
  FROM public.empresa_cadastro ec
  WHERE COALESCE(ec.razao_social,'') || ' ' || COALESCE(ec.nome_fantasia,'') ILIKE '%metal%rgica%exemplo%'
),
usr AS MATERIALIZED (
  SELECT ub.tenant_id, ub.tipo_usuario
  FROM public.usuarios_base ub
  WHERE lower(COALESCE(ub.email,'')) = 'leirinuernberg@gmail.com'
)
SELECT json_build_object(
  'empresas', (SELECT json_agg(json_build_object('razao', razao_social, 'fantasia', nome_fantasia,
                 'mesmo_tenant_do_usuario', tenant_id IN (SELECT tenant_id FROM usr))) FROM emp),
  'usuario_existe', (SELECT count(*) FROM usr),
  'usuario_tipos', (SELECT json_agg(DISTINCT tipo_usuario) FROM usr),
  'colaboradores_ativos', (SELECT count(*) FROM public.admissoes a WHERE a.empresa_id IN (SELECT id FROM emp) AND a.status::text = 'concluido'),
  'colab_com_email', (SELECT count(*) FROM public.admissoes a WHERE a.empresa_id IN (SELECT id FROM emp) AND a.status::text = 'concluido' AND COALESCE(a.email,'') <> ''),
  'marcacoes_por_mes', (SELECT json_object_agg(m, n) FROM (SELECT to_char(data_marcacao,'YYYY-MM') m, count(*) n FROM public.ponto_marcacoes
                         WHERE empresa_id IN (SELECT id FROM emp) AND data_marcacao >= DATE '2026-06-01' GROUP BY 1 ORDER BY 1) x),
  'diarios_por_mes', (SELECT json_object_agg(m, n) FROM (SELECT to_char(data,'YYYY-MM') m, count(*) n FROM public.ponto_diario
                         WHERE empresa_id IN (SELECT id FROM emp) AND data >= DATE '2026-06-01' GROUP BY 1 ORDER BY 1) x),
  'escalas_ativas', (SELECT count(*) FROM public.ponto_escala_atribuicoes pa JOIN public.ponto_escalas pe ON pe.id = pa.escala_id
                         WHERE pe.empresa_id IN (SELECT id FROM emp) AND COALESCE(pa.ativa,true)),
  'fechamentos', (SELECT json_agg(json_build_object('comp', competencia, 'status', status)) FROM public.ponto_fechamentos
                         WHERE empresa_id IN (SELECT id FROM emp) OR (empresa_id IS NULL AND tenant_id IN (SELECT tenant_id FROM emp))),
  'espelhos', (SELECT count(*) FROM public.ponto_espelhos WHERE empresa_id IN (SELECT id FROM emp))
) AS diag;
