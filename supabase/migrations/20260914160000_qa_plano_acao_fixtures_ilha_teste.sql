-- =========================================================
-- QA — Plano de Ação: fixtures na ILHA DE TESTE (padrão "fixtures na ilha")
--
-- Mesmo motivo do Metas: os casos e2e profundos (PACAO-TELA-10/11/12) dependem
-- de ações JÁ EXISTENTES. Na HOMOLOGAÇÃO isso vem da função seed-e2e-user
-- (semearPlanoAcao). A esteira do TESTE (staging.yml) não roda o seed (o passo
-- é condicionado a um secret ausente nela), mas APLICA migrations no TESTE
-- (db push) — então semear por migration é o que alcança a ilha do TESTE e
-- mantém o CI automático de fundo verde.
--
-- SEGURANÇA (idêntica à migration de fixtures do Metas):
-- - Só semeia onde a ilha existe (tenant + empresa fixos). Em PRODUÇÃO esses
--   ids não existem -> no-op; EXCEPTION protege contra qualquer violação. Não
--   vira script de entrega: dado fictício, exclusivo do ambiente de teste.
-- - Idempotente: guarda pela ação-sentinela (título único "(QA)").
-- - Dado 100% fictício. codigo:'' deixa o trigger gerar ACO-NNNNN.
-- =========================================================

SET lock_timeout = '10s';

DO $seed_pacao$
DECLARE
  v_tenant  uuid := '11111111-1111-1111-1111-111111111111';
  v_empresa uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.tenants WHERE id = v_tenant)
     OR NOT EXISTS (SELECT 1 FROM public.empresa_cadastro WHERE id = v_empresa) THEN
    RAISE NOTICE 'Ilha de teste ausente (tenant/empresa) — ações fictícias não semeadas.';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.plano_acoes
    WHERE tenant_id = v_tenant
      AND titulo = 'Instalar guarda-corpo na plataforma de carga (QA)'
  ) THEN
    RAISE NOTICE 'Ações fictícias já semeadas — nada a fazer.';
    RETURN;
  END IF;

  INSERT INTO public.plano_acoes
    (tenant_id, empresa_id, codigo, origem_modulo, tipo, prazo, criado_por_nome,
     titulo, descricao, status, prioridade, gravidade, urgencia, tendencia, progresso)
  VALUES
    (v_tenant, v_empresa, '', 'manual', 'corretiva', '2026-12-31', 'Robô de Testes',
     'Instalar guarda-corpo na plataforma de carga (QA)',
     'Ação fictícia de QA — instalar guarda-corpo na plataforma.',
     'pendente', 'imediato', 5, 5, 4, 0),

    (v_tenant, v_empresa, '', 'manual', 'corretiva', '2026-12-31', 'Robô de Testes',
     'Revisar extintores vencidos (QA)',
     'Ação fictícia de QA — revisão dos extintores vencidos.',
     'em_andamento', 'urgente', 4, 4, 3, 50),

    (v_tenant, v_empresa, '', 'manual', 'corretiva', '2026-12-31', 'Robô de Testes',
     'Treinar brigada de incêndio (QA)',
     'Ação fictícia de QA — treinamento da brigada de incêndio.',
     'concluida', 'medio', 3, 2, 2, 100);

  RAISE NOTICE 'Ações fictícias (3) semeadas na ilha de teste.';

EXCEPTION
  WHEN foreign_key_violation OR not_null_violation OR raise_exception THEN
    RAISE NOTICE 'Ações fictícias não semeadas (ambiente sem a ilha de teste): %', SQLERRM;
END $seed_pacao$;
