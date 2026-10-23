-- ============================================================================
-- PRE-CHECK das Fases 3 e 4 (SOMENTE LEITURA) — cole na PRODUCAO antes das 3 partes. Nao altera nada.
-- Mostra quantas linhas existentes violariam cada restricao. 0 = a restricao entra; maior que 0 = o script
-- NAO a cria e avisa (a limpeza do dado e decisao de produto).
-- ============================================================================
SELECT
  (SELECT count(*) FROM public.admissoes WHERE (NOT exame_demissional_dispensado OR (exame_demissional_dispensa_motivo IS NOT NULL AND trim(exame_demissional_dispensa_motivo) <> '')) IS FALSE) AS violam_dispensa_exame,
  (SELECT count(*) FROM public.epis WHERE (quantidade_estoque IS NULL OR quantidade_estoque >= 0) IS FALSE) AS violam_estoque_epi,
  (SELECT count(*) FROM public.ponto_retencao_config WHERE (geolocalizacao_dias >= 30 AND geolocalizacao_dias <= 1825) IS FALSE) AS violam_geolocalizacao_dias,
  (SELECT count(*) FROM public.psicossocial_entrevistas WHERE (tipo_sessao = ANY (ARRAY['individual','coletiva'])) IS FALSE) AS violam_tipo_sessao,
  (SELECT count(*) FROM public.admissoes) AS total_admissoes,
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ferias_periodos_aquisitivos' AND column_name = 'interrompido_art133') AS ja_tem_coluna_art133,
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'admissoes' AND column_name = 'regime_rural') AS ja_tem_regime_rural,
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'admissoes' AND column_name = 'reversao_desligamento_aprovada_por') AS ja_tem_reversao_aprovada_por;
