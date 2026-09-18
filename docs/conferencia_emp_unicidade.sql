-- ============================================================================
-- CONFERENCIA de EMP-020/021/070/071 — rodar DEPOIS do script de entrega
-- (docs/script_emp_unicidade_documento_ativo.sql), em transacao propria.
--
-- Roda as 4 rotinas com o executor descartavel (rollback) e conta o legado.
-- E somente-leitura no efeito (as insercoes de teste sao desfeitas). Se pegar
-- um lock transitorio numa base movimentada, simplesmente rode de novo.
-- ============================================================================

SET lock_timeout = '10s';

SELECT 'EMP-020' AS caso, (public.qa_executar_descartavel('qa_caso_emp_020')).situacao::text AS situacao
UNION ALL SELECT 'EMP-021', (public.qa_executar_descartavel('qa_caso_emp_021')).situacao::text
UNION ALL SELECT 'EMP-070', (public.qa_executar_descartavel('qa_caso_emp_070')).situacao::text
UNION ALL SELECT 'EMP-071', (public.qa_executar_descartavel('qa_caso_emp_071')).situacao::text
UNION ALL
SELECT 'LEGADO: grupos de CNPJ ativo duplicado', count(*)::text FROM (
  SELECT tenant_id, regexp_replace(cnpj,'[^0-9]','','g') AS d
  FROM public.empresa_cadastro WHERE ativo AND cnpj IS NOT NULL
    AND regexp_replace(cnpj,'[^0-9]','','g') <> ''
  GROUP BY 1,2 HAVING count(*) > 1) g
UNION ALL
SELECT 'LEGADO: grupos de CPF ativo duplicado', count(*)::text FROM (
  SELECT tenant_id, regexp_replace(cpf,'[^0-9]','','g') AS d
  FROM public.empresa_cadastro WHERE ativo AND cpf IS NOT NULL
    AND regexp_replace(cpf,'[^0-9]','','g') <> ''
  GROUP BY 1,2 HAVING count(*) > 1) g
ORDER BY caso;
