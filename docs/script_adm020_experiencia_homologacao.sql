-- ============================================================================
-- ENTREGA — ADM-020 · teto do contrato de experiência (90 dias) — HOMOLOGAÇÃO
--
-- Cole no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na PRODUÇÃO.
--
-- ADM-020 estava vermelho na produção: o banco aceitava experiência fora do teto
-- legal (100 dias diretos; 60+45=105 com prorrogação). As duas CHECKs que barram
-- isso existem no repositório (migration 20260913150500) mas só foram "entregues"
-- dentro do monolito script_motor_qa_fases_0a3.sql — que NUNCA é colado (cria
-- tabela → aciona o auto-RLS do editor). Por isso nunca chegaram à produção.
-- Aqui vão limpas.
--
-- SEGURANÇA: só ALTER TABLE ... ADD CONSTRAINT ... NOT VALID. Não cria tabela
-- (auto-RLS não liga), não apaga dado. NOT VALID enforça linha nova/alterada
-- sem varrer as legadas (contratos de experiência antigos > 90 dias não quebram
-- a aplicação da constraint). lock_timeout curto. Idempotente (DROP IF EXISTS +
-- ADD).
-- ============================================================================

SET lock_timeout = '10s';

-- Primeiro período entre 1 e 90 dias (art. 445, parágrafo único, CLT).
ALTER TABLE public.contratos_experiencia
  DROP CONSTRAINT IF EXISTS chk_experiencia_primeiro_periodo;
ALTER TABLE public.contratos_experiencia
  ADD CONSTRAINT chk_experiencia_primeiro_periodo
  CHECK (duracao_primeiro_periodo IS NULL OR duracao_primeiro_periodo BETWEEN 1 AND 90) NOT VALID;

-- Soma (primeiro + prorrogação) não passa de 90 dias — uma única prorrogação.
ALTER TABLE public.contratos_experiencia
  DROP CONSTRAINT IF EXISTS chk_experiencia_soma_90;
ALTER TABLE public.contratos_experiencia
  ADD CONSTRAINT chk_experiencia_soma_90
  CHECK (COALESCE(duracao_primeiro_periodo,0) + COALESCE(duracao_prorrogacao,0) <= 90) NOT VALID;

-- ════════════════════ CONFERÊNCIA (única — esperado tudo 'ok') ════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('ADM-020 · CHECK primeiro período ≤ 90 dias',
       EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_experiencia_primeiro_periodo' AND conrelid='public.contratos_experiencia'::regclass)),
    ('ADM-020 · CHECK soma (primeiro+prorrogação) ≤ 90',
       EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_experiencia_soma_90' AND conrelid='public.contratos_experiencia'::regclass))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao FROM alvo ORDER BY item;
