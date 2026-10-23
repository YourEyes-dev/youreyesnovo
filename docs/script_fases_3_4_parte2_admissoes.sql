-- ============================================================================
-- ENTREGA — Fases 3 e 4 (estrutura que faltava na producao) — parte 2/3: Admissoes (2 colunas e 2 restricoes)
--
-- Cole ESTE arquivo inteiro no SQL Editor (HOMOLOGACAO e, depois, PRODUCAO), numa aba nova e vazia.
-- Rode as 3 partes na ordem. Origem: levantamento main x producao de 20/10/2026 (docs/LEVANTAMENTO_MAIN_VS_PRODUCAO_20261020.md).
-- Equivale ao que as migrations fase3_ferias_pontes_afastamento_ponto, fase4_desligamento_prazos_ritos,
-- fase4_avulsos_metas_ponto_perfil, qa_estabilidades_protocolo_lgpd, fase1_guardas_adm_afast_epi_ferias,
-- qa_ponto_links_autoaprovacao_retencao e entrevista_coletiva_workshop criaram e a producao ainda nao tem.
--
-- Acrescenta regime_rural (padrao 'urbano') e reversao_desligamento_aprovada_por; cria as restricoes SO se nenhuma linha existente as violar (senao avisa e nao cria).
-- Roda em UMA transacao e e idempotente. Uma tabela por parte (regra da casa contra deadlock em tabela movimentada).
-- ============================================================================

SET lock_timeout = '10s';

DO $c2$
BEGIN
  ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS regime_rural text NOT NULL DEFAULT 'urbano';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'coluna admissoes.regime_rural nao criada: %', SQLERRM;
END
$c2$;

DO $c3$
BEGIN
  ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS reversao_desligamento_aprovada_por uuid;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'coluna admissoes.reversao_desligamento_aprovada_por nao criada: %', SQLERRM;
END
$c3$;

DO $c4$
DECLARE n bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'admissoes_regime_rural_chk' AND conrelid = 'public.admissoes'::regclass) THEN
    RETURN;
  END IF;
  n := (SELECT count(*) FROM public.admissoes WHERE (regime_rural = ANY (ARRAY['urbano','rural_lavoura','rural_pecuaria'])) IS FALSE);
  IF n > 0 THEN
    RAISE NOTICE 'admissoes_regime_rural_chk: % linha(s) violam a regra; restricao NAO criada (limpar o dado e rodar de novo).', n;
    RETURN;
  END IF;
  EXECUTE 'ALTER TABLE public.admissoes ADD CONSTRAINT admissoes_regime_rural_chk CHECK (regime_rural = ANY (ARRAY[''urbano'',''rural_lavoura'',''rural_pecuaria'']))';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'restricao admissoes_regime_rural_chk nao criada: %', SQLERRM;
END
$c4$;

DO $c5$
DECLARE n bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'admissoes_dispensa_exame_justificada' AND conrelid = 'public.admissoes'::regclass) THEN
    RETURN;
  END IF;
  n := (SELECT count(*) FROM public.admissoes WHERE (NOT exame_demissional_dispensado OR (exame_demissional_dispensa_motivo IS NOT NULL AND trim(exame_demissional_dispensa_motivo) <> '')) IS FALSE);
  IF n > 0 THEN
    RAISE NOTICE 'admissoes_dispensa_exame_justificada: % linha(s) violam a regra; restricao NAO criada (limpar o dado e rodar de novo).', n;
    RETURN;
  END IF;
  EXECUTE 'ALTER TABLE public.admissoes ADD CONSTRAINT admissoes_dispensa_exame_justificada CHECK (NOT exame_demissional_dispensado OR (exame_demissional_dispensa_motivo IS NOT NULL AND trim(exame_demissional_dispensa_motivo) <> ''''))';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'restricao admissoes_dispensa_exame_justificada nao criada: %', SQLERRM;
END
$c5$;

-- Conferencia. Esperado: colunas = true; restricao_* = true (ou, se alguma linha viola, false com a contagem em violam_*).
SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'admissoes' AND column_name = 'regime_rural') AS coluna_regime_rural,
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'admissoes' AND column_name = 'reversao_desligamento_aprovada_por') AS coluna_reversao_aprovada_por,
       EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'admissoes_regime_rural_chk' AND conrelid = 'public.admissoes'::regclass) AS restricao_regime_rural,
       EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'admissoes_dispensa_exame_justificada' AND conrelid = 'public.admissoes'::regclass) AS restricao_dispensa_exame,
       (SELECT count(*) FROM public.admissoes WHERE (NOT exame_demissional_dispensado OR (exame_demissional_dispensa_motivo IS NOT NULL AND trim(exame_demissional_dispensa_motivo) <> '')) IS FALSE) AS violam_dispensa_exame;
-- Para desfazer: ALTER TABLE public.admissoes DROP CONSTRAINT IF EXISTS admissoes_regime_rural_chk, DROP CONSTRAINT IF EXISTS admissoes_dispensa_exame_justificada;
--   (as colunas novas podem ficar; sao inofensivas)
