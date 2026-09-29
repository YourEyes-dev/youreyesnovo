-- ============================================================================
-- DIAGNÓSTICO — por que o "Selecionar Colaborador" (Novo Atestado) vem vazio
--               (SOMENTE LEITURA)
--
-- O hook useColaboradores lista admissoes do tenant com status='concluido' E,
-- quando há empresa ativa, empresa_id = a empresa ativa. Se vier vazio, é uma
-- das duas: (a) não há admissão 'concluido'; (b) há, mas com empresa_id
-- nulo/diferente da empresa ativa (some do filtro).
--
-- Ajuste o filtro do tenant abaixo se o nome não casar (troque 'nuernberg').
-- ============================================================================

WITH alvo AS (
  SELECT DISTINCT tenant_id
  FROM public.empresa_cadastro
  WHERE nome_fantasia ILIKE '%nuernberg%' OR razao_social ILIKE '%nuernberg%'
)
-- Bloco 1: admissões por status (mostra se há 'concluido')
SELECT 1 AS ord, 'admissões por status'::text AS bloco,
       a.status::text AS chave, count(*)::text AS valor
FROM public.admissoes a JOIN alvo ON alvo.tenant_id = a.tenant_id
GROUP BY a.status

UNION ALL
-- Bloco 2: das concluídas, quantas têm empresa_id preenchido (senão somem do filtro)
SELECT 2, 'concluídas · empresa_id',
       CASE WHEN a.empresa_id IS NULL THEN 'SEM empresa_id (invisível no filtro por empresa)'
            ELSE 'com empresa_id' END,
       count(*)::text
FROM public.admissoes a JOIN alvo ON alvo.tenant_id = a.tenant_id
WHERE a.status = 'concluido'
GROUP BY (a.empresa_id IS NULL)

UNION ALL
-- Bloco 3: por empresa do tenant, quantas concluídas apontam para ela
SELECT 3, 'concluídas por empresa',
       COALESCE(e.nome_fantasia, e.razao_social, '(empresa)'),
       (SELECT count(*) FROM public.admissoes a
         WHERE a.tenant_id = e.tenant_id AND a.status = 'concluido' AND a.empresa_id = e.id)::text
FROM public.empresa_cadastro e JOIN alvo ON alvo.tenant_id = e.tenant_id

ORDER BY ord, chave;
