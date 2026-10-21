-- ============================================================================
-- ENTREGA — Fases 3 e 4 (estrutura que faltava na producao) — parte 1/3: Ferias (coluna do art. 133 da CLT)
--
-- Cole ESTE arquivo inteiro no SQL Editor (HOMOLOGACAO e, depois, PRODUCAO), numa aba nova e vazia.
-- Rode as 3 partes na ordem. Origem: levantamento main x producao de 20/10/2026 (docs/LEVANTAMENTO_MAIN_VS_PRODUCAO_20261020.md).
-- Equivale ao que as migrations fase3_ferias_pontes_afastamento_ponto, fase4_desligamento_prazos_ritos,
-- fase4_avulsos_metas_ponto_perfil, qa_estabilidades_protocolo_lgpd, fase1_guardas_adm_afast_epi_ferias,
-- qa_ponto_links_autoaprovacao_retencao e entrevista_coletiva_workshop criaram e a producao ainda nao tem.
--
-- So acrescenta uma coluna com valor padrao falso: nao altera nem apaga dado. A funcao ferias_recalcular_periodo ja usa essa coluna.
-- Roda em UMA transacao e e idempotente. Uma tabela por parte (regra da casa contra deadlock em tabela movimentada).
-- ============================================================================

SET lock_timeout = '10s';

DO $c1$
BEGIN
  ALTER TABLE public.ferias_periodos_aquisitivos ADD COLUMN IF NOT EXISTS interrompido_art133 boolean NOT NULL DEFAULT false;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'coluna ferias_periodos_aquisitivos.interrompido_art133 nao criada: %', SQLERRM;
END
$c1$;

-- Conferencia (o editor mostra so o ultimo resultado). Esperado: coluna_ok = true.
SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ferias_periodos_aquisitivos' AND column_name = 'interrompido_art133') AS coluna_ok,
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ferias_periodos_aquisitivos' AND column_name = 'interrompido_afastamento_id') AS coluna_afastamento_ok;
-- Para desfazer: ALTER TABLE public.ferias_periodos_aquisitivos DROP COLUMN interrompido_art133;
