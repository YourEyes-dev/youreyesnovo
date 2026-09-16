-- =========================================================
-- QA — Metas: fixtures na ILHA DE TESTE (piloto "fixtures na ilha")
--
-- POR QUE ESTA MIGRATION EXISTE
-- Os casos e2e profundos de Metas (METAS-TELA-10/11/12) e o vazio-por-busca do
-- METAS-TELA-09 dependem de metas JÁ EXISTENTES na ilha de QA. Na HOMOLOGAÇÃO
-- isso vem da função seed-e2e-user (semearMetas), que a esteira de homologação
-- roda a cada corrida. Mas a esteira do TESTE (staging.yml) NÃO roda o seed: o
-- passo "Semear a conta-robô" é condicionado ao secret QA_E2E_TOKEN, que não
-- está configurado ali — então as metas fictícias nunca chegavam ao TESTE e os
-- casos reprovavam só nesse ambiente. Como a esteira aplica migrations no TESTE
-- (db push), semear por migration é o caminho que alcança a ilha do TESTE.
--
-- SEGURANÇA
-- - Só semeia onde a ilha existe (tenant + empresa fixos). Em PRODUÇÃO esses
--   ids não existem, então o bloco não faz nada; o EXCEPTION ainda protege
--   contra qualquer violação (padrão prodseed da casa). Não gera script de
--   entrega: é dado fictício, exclusivo do ambiente de teste.
-- - Idempotente: guarda pela meta-sentinela (título único "(QA)"); rodar de
--   novo não duplica.
-- - Dado 100% fictício (títulos "(QA)", "Robô de Testes", "Colaborador 1").
-- =========================================================

SET lock_timeout = '10s';

DO $seed_metas$
DECLARE
  v_tenant  uuid := '11111111-1111-1111-1111-111111111111';
  v_empresa uuid := '22222222-2222-2222-2222-222222222222';
  v_setor   uuid;
BEGIN
  -- A ilha de teste precisa existir (tenant + empresa). Fora dela: no-op.
  IF NOT EXISTS (SELECT 1 FROM public.tenants WHERE id = v_tenant)
     OR NOT EXISTS (SELECT 1 FROM public.empresa_cadastro WHERE id = v_empresa) THEN
    RAISE NOTICE 'Ilha de teste ausente (tenant/empresa) — metas fictícias não semeadas.';
    RETURN;
  END IF;

  -- Idempotente: se a meta-sentinela já existe, nada a fazer.
  IF EXISTS (
    SELECT 1 FROM public.metas
    WHERE tenant_id = v_tenant
      AND titulo = 'Reduzir índice de acidentes em 20% (QA)'
  ) THEN
    RAISE NOTICE 'Metas fictícias já semeadas — nada a fazer.';
    RETURN;
  END IF;

  -- Departamento de RH para a meta de setor (setor_id -> departamentos). Se a
  -- ilha não tiver esse departamento, segue com NULL (coluna é opcional).
  SELECT id INTO v_setor
  FROM public.departamentos
  WHERE tenant_id = v_tenant AND nome = 'Recursos Humanos'
  LIMIT 1;

  INSERT INTO public.metas
    (tenant_id, empresa_id, ano, periodo, trimestre, peso, data_inicio, data_fim,
     workflow_status, criado_por_nome, nivel, titulo, descricao, status, progresso,
     responsavel_nome, setor_id, setor_nome, departamento_id, departamento_nome,
     colaborador_nome)
  VALUES
    (v_tenant, v_empresa, 2026, 'trimestral', 1, 1, '2026-01-01', '2026-12-31',
     'ativa', 'Robô de Testes', 'estrategica',
     'Reduzir índice de acidentes em 20% (QA)',
     'Meta fictícia de QA — reduzir acidentes de trabalho no ano.',
     'em_andamento', 40, 'Robô de Testes', NULL, NULL, NULL, NULL, NULL),

    (v_tenant, v_empresa, 2026, 'trimestral', 1, 1, '2026-01-01', '2026-12-31',
     'ativa', 'Robô de Testes', 'setor',
     'Concluir treinamentos NR obrigatórios (QA)',
     'Meta fictícia de QA — treinamentos NR do setor de RH.',
     'em_andamento', 60, NULL, v_setor, 'Recursos Humanos', v_setor,
     'Recursos Humanos', NULL),

    (v_tenant, v_empresa, 2026, 'trimestral', 1, 1, '2026-01-01', '2026-12-31',
     'ativa', 'Robô de Testes', 'individual',
     'Registrar 100% dos EPIs entregues (QA)',
     'Meta fictícia de QA — registro de entrega de EPIs.',
     'nao_iniciada', 0, NULL, NULL, NULL, NULL, NULL, 'Colaborador 1');

  RAISE NOTICE 'Metas fictícias (3) semeadas na ilha de teste.';

EXCEPTION
  WHEN foreign_key_violation OR not_null_violation OR raise_exception THEN
    RAISE NOTICE 'Metas fictícias não semeadas (ambiente sem a ilha de teste): %', SQLERRM;
END $seed_metas$;
