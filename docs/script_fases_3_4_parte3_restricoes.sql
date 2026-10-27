-- ============================================================================
-- ENTREGA — Fases 3 e 4 (estrutura que faltava na producao) — parte 3/3: EPI, retencao de ponto e entrevista psicossocial (3 restricoes)
--
-- Cole ESTE arquivo inteiro no SQL Editor (HOMOLOGACAO e, depois, PRODUCAO), numa aba nova e vazia.
-- Rode as 3 partes na ordem. Origem: levantamento main x producao de 20/10/2026 (docs/LEVANTAMENTO_MAIN_VS_PRODUCAO_20261020.md).
-- Equivale ao que as migrations fase3_ferias_pontes_afastamento_ponto, fase4_desligamento_prazos_ritos,
-- fase4_avulsos_metas_ponto_perfil, qa_estabilidades_protocolo_lgpd, fase1_guardas_adm_afast_epi_ferias,
-- qa_ponto_links_autoaprovacao_retencao e entrevista_coletiva_workshop criaram e a producao ainda nao tem.
--
-- Cria cada restricao SO se nenhuma linha existente a violar (senao avisa e nao cria). Nao altera dado.
-- Roda em UMA transacao e e idempotente. Uma tabela por parte (regra da casa contra deadlock em tabela movimentada).
-- ============================================================================

SET lock_timeout = '10s';

DO $c6$
DECLARE n bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_epis_estoque_nao_negativo' AND conrelid = 'public.epis'::regclass) THEN
    RETURN;
  END IF;
  n := (SELECT count(*) FROM public.epis WHERE (quantidade_estoque IS NULL OR quantidade_estoque >= 0) IS FALSE);
  IF n > 0 THEN
    RAISE NOTICE 'chk_epis_estoque_nao_negativo: % linha(s) violam a regra; restricao NAO criada (limpar o dado e rodar de novo).', n;
    RETURN;
  END IF;
  EXECUTE 'ALTER TABLE public.epis ADD CONSTRAINT chk_epis_estoque_nao_negativo CHECK (quantidade_estoque IS NULL OR quantidade_estoque >= 0)';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'restricao chk_epis_estoque_nao_negativo nao criada: %', SQLERRM;
END
$c6$;

DO $c7$
DECLARE n bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ponto_retencao_config_geolocalizacao_dias_check' AND conrelid = 'public.ponto_retencao_config'::regclass) THEN
    RETURN;
  END IF;
  n := (SELECT count(*) FROM public.ponto_retencao_config WHERE (geolocalizacao_dias >= 30 AND geolocalizacao_dias <= 1825) IS FALSE);
  IF n > 0 THEN
    RAISE NOTICE 'ponto_retencao_config_geolocalizacao_dias_check: % linha(s) violam a regra; restricao NAO criada (limpar o dado e rodar de novo).', n;
    RETURN;
  END IF;
  EXECUTE 'ALTER TABLE public.ponto_retencao_config ADD CONSTRAINT ponto_retencao_config_geolocalizacao_dias_check CHECK (geolocalizacao_dias >= 30 AND geolocalizacao_dias <= 1825)';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'restricao ponto_retencao_config_geolocalizacao_dias_check nao criada: %', SQLERRM;
END
$c7$;

DO $c8$
DECLARE n bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'psicossocial_entrevistas_tipo_sessao_chk' AND conrelid = 'public.psicossocial_entrevistas'::regclass) THEN
    RETURN;
  END IF;
  n := (SELECT count(*) FROM public.psicossocial_entrevistas WHERE (tipo_sessao = ANY (ARRAY['individual','coletiva'])) IS FALSE);
  IF n > 0 THEN
    RAISE NOTICE 'psicossocial_entrevistas_tipo_sessao_chk: % linha(s) violam a regra; restricao NAO criada (limpar o dado e rodar de novo).', n;
    RETURN;
  END IF;
  EXECUTE 'ALTER TABLE public.psicossocial_entrevistas ADD CONSTRAINT psicossocial_entrevistas_tipo_sessao_chk CHECK (tipo_sessao = ANY (ARRAY[''individual'',''coletiva'']))';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'restricao psicossocial_entrevistas_tipo_sessao_chk nao criada: %', SQLERRM;
END
$c8$;

-- Conferencia. Esperado: as 3 restricoes = true (ou false com a contagem das linhas que violam).
SELECT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_epis_estoque_nao_negativo' AND conrelid = 'public.epis'::regclass) AS restricao_estoque_epi,
       (SELECT count(*) FROM public.epis WHERE (quantidade_estoque IS NULL OR quantidade_estoque >= 0) IS FALSE) AS violam_estoque_epi,
       EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ponto_retencao_config_geolocalizacao_dias_check' AND conrelid = 'public.ponto_retencao_config'::regclass) AS restricao_geolocalizacao_dias,
       (SELECT count(*) FROM public.ponto_retencao_config WHERE (geolocalizacao_dias >= 30 AND geolocalizacao_dias <= 1825) IS FALSE) AS violam_geolocalizacao_dias,
       EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'psicossocial_entrevistas_tipo_sessao_chk' AND conrelid = 'public.psicossocial_entrevistas'::regclass) AS restricao_tipo_sessao,
       (SELECT count(*) FROM public.psicossocial_entrevistas WHERE (tipo_sessao = ANY (ARRAY['individual','coletiva'])) IS FALSE) AS violam_tipo_sessao;
-- Para desfazer: ALTER TABLE public.epis DROP CONSTRAINT IF EXISTS chk_epis_estoque_nao_negativo; (idem nas outras duas tabelas)
