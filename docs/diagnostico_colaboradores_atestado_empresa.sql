-- ============================================================================
-- DIAGNÓSTICO 2 — "Selecionar Colaborador" vazio no Novo Atestado
--                 (SOMENTE LEITURA — não altera nada)
--
-- O diagnóstico 1 provou que os colaboradores EXISTEM (25 admissões
-- 'concluido', todas com empresa_id). Então o modal não vem vazio por falta de
-- dado — vem vazio por FILTRO DE EMPRESA.
--
-- Como o código funciona (confirmado em src/):
--   • O seletor de empresa do topo SEMPRE tem uma empresa ativa (o contexto
--     auto-seleciona a primeira quando nada está salvo — não existe modo
--     "todas as empresas").
--   • O hook useColaboradores lista admissões do tenant com status='concluido'
--     E empresa_id = EMPRESA ATIVA.
--   • A lista de atestados (à esquerda) usa o MESMO filtro de empresa ativa,
--     mas o atestado guarda o NOME do colaborador como texto — ele não depende
--     de haver admissão naquela empresa. Por isso a lista pode mostrar nomes
--     mesmo que a empresa ativa não tenha nenhum colaborador cadastrado.
--
-- Conclusão provável: a empresa ativa no topo (na tela, "BARROS & NUERNBERG
-- ENGENH...") NÃO tem admissões 'concluido' — os 25 colaboradores estão nas
-- empresas-irmãs (CAPANEMA, DOIS VIZINHOS, ITAPEJARA, REALEZA) do mesmo tenant.
--
-- Este diagnóstico lista TODAS as empresas do tenant lado a lado:
--   colaboradores (admissões concluído) x atestados já lançados.
-- A empresa com "0 colaboradores" e ">0 atestados" é exatamente a que, quando
-- ativa, deixa o modal vazio.
--
-- Ajuste o filtro do tenant se o nome não casar (troque 'nuernberg').
-- ============================================================================

WITH alvo AS (
  SELECT DISTINCT tenant_id
  FROM public.empresa_cadastro
  WHERE nome_fantasia ILIKE '%nuernberg%' OR razao_social ILIKE '%nuernberg%'
)
SELECT
  COALESCE(e.nome_fantasia, e.razao_social, '(sem nome)')          AS empresa,
  e.ativo                                                          AS empresa_ativa_flag,
  (SELECT count(*) FROM public.admissoes a
     WHERE a.tenant_id = e.tenant_id
       AND a.empresa_id = e.id
       AND a.status = 'concluido')                                 AS colaboradores_concluido,
  (SELECT count(*) FROM public.atestados at
     WHERE at.tenant_id = e.tenant_id
       AND at.empresa_id = e.id)                                   AS atestados_lancados
FROM public.empresa_cadastro e
JOIN alvo ON alvo.tenant_id = e.tenant_id
ORDER BY colaboradores_concluido DESC, atestados_lancados DESC, empresa;
