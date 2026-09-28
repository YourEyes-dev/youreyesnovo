-- ============================================================================
-- DIAGNÓSTICO ADM-103 residual — admissões concluídas ainda no limbo
--                                 (SOMENTE LEITURA)
--
-- NÃO altera nada. Lista as admissões CONCLUÍDAS cujos documentos continuam sem
-- dono/pasta DEPOIS do backfill — ou seja, os casos que a reconciliação não
-- conseguiu resolver porque NÃO existe usuário (usuarios_base) com aquele CPF.
--
-- Para cada uma, dá pistas de triagem:
--  • existe_usuario_por_cpf  = há usuário com exatamente esse CPF? (esperado: não,
--    por isso ficou no limbo)
--  • usuarios_mesmo_nome     = quantos usuários têm o MESMO nome (sinal de CPF
--    digitado diferente entre a admissão e o cadastro do usuário)
--  • docs_no_limbo           = quantos documentos dessa pessoa estão soltos
--
-- Possíveis desfechos (decisão sua):
--  a) CPF divergente: o usuário existe com outro CPF → corrigir o CPF (na
--     admissão ou no cadastro) e rodar de novo o backfill (resolve sozinho).
--  b) Usuário nunca provisionado: a pessoa concluiu admissão mas não virou
--     usuário → criar/regularizar o usuário e rodar o backfill.
--  c) Registro de teste/legado: aceitar como está (documentar no caso).
--
-- Não expõe mais dado pessoal que o necessário para a triagem (CPF e nome da
-- pessoa aparecem porque são o que você precisa para localizá-la). Evite
-- circular o resultado.
-- ============================================================================

WITH docs_adm AS MATERIALIZED (
  SELECT * FROM public.documentos WHERE observacoes = 'Documento da admissão'
),
residual AS MATERIALIZED (
  -- Mesma população da auditoria ADM-103: concluída + doc no limbo.
  SELECT DISTINCT a.id AS admissao_id, a.tenant_id, a.empresa_id,
         a.nome_completo, a.cpf AS admissao_cpf,
         regexp_replace(COALESCE(a.cpf,''),'[^0-9]','','g') AS cpf_norm
  FROM public.admissoes a
  JOIN docs_adm d
    ON d.colaborador_cpf = a.cpf AND d.tenant_id = a.tenant_id
  WHERE a.status = 'concluido'
    AND (d.colaborador_id IS NULL OR d.pasta_id IS NULL)
)
SELECT
  COALESCE(e.nome_fantasia, e.razao_social, '(sem empresa)') AS empresa,
  res.nome_completo,
  res.admissao_cpf,
  -- há usuário com esse CPF? (esperado: não)
  EXISTS (SELECT 1 FROM public.usuarios_base ub
           WHERE ub.tenant_id = res.tenant_id
             AND regexp_replace(COALESCE(ub.cpf,''),'[^0-9]','','g') = res.cpf_norm
             AND COALESCE(ub.status::text,'ativo') <> 'excluido') AS existe_usuario_por_cpf,
  -- usuários com o MESMO nome (pista de CPF divergente)
  (SELECT count(*) FROM public.usuarios_base ub
    WHERE ub.tenant_id = res.tenant_id
      AND lower(btrim(ub.nome_completo)) = lower(btrim(res.nome_completo))
      AND COALESCE(ub.status::text,'ativo') <> 'excluido') AS usuarios_mesmo_nome,
  -- quantos documentos dessa pessoa estão no limbo
  (SELECT count(*) FROM docs_adm d
    WHERE d.tenant_id = res.tenant_id AND d.colaborador_cpf = res.admissao_cpf
      AND (d.colaborador_id IS NULL OR d.pasta_id IS NULL)) AS docs_no_limbo,
  res.admissao_id
FROM residual res
LEFT JOIN public.empresa_cadastro e ON e.id = res.empresa_id
ORDER BY empresa, res.nome_completo;
