-- ============================================================================
-- PONTO — backfill: batidas externas antigas sem empresa herdam a do colaborador
--
-- Complementa 20260924175330 (que fez o registro externo passar a gravar a
-- empresa daqui pra frente). Aqui preenchemos as batidas JÁ existentes que
-- ficaram com empresa_id NULL, usando a empresa da admissão do colaborador.
--
-- UPDATE com JOIN (set-based, sem função por linha — não estoura o timeout em
-- tabela grande). Só toca linhas com empresa_id NULL: nunca sobrescreve empresa
-- já preenchida. Escopo: registro externo (dispositivo = 'mobile_web'). Em banco
-- vazio é no-op.
-- ============================================================================

UPDATE public.ponto_marcacoes m
SET empresa_id = a.empresa_id
FROM public.admissoes a
WHERE m.colaborador_id = a.id
  AND m.tenant_id = a.tenant_id
  AND m.dispositivo = 'mobile_web'
  AND m.empresa_id IS NULL
  AND a.empresa_id IS NOT NULL;
