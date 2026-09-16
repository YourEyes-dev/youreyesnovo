-- =========================================================
-- 13o Salario — CONFERENCIA DE AMBIENTE (somente leitura)
--
-- Cole no SQL Editor de QUALQUER ambiente (homologacao, teste ou
-- producao) para saber, numa tela so, se o modulo esta inteiro ali e,
-- se nao estiver, QUAL script falta colar.
--
-- Nao altera nada. Pode rodar quantas vezes quiser.
-- =========================================================

WITH pecas AS MATERIALIZED (
    SELECT * FROM (VALUES
      -- (ordem, script, peca, especie, nome)
      (1,'script_13o_apuracao_avos_e_medias.sql',        'apuracao dos avos (Lei 4.090)',        'funcao','decimo_terceiro_avos'),
      (1,'script_13o_apuracao_avos_e_medias.sql',        'media das variaveis do ano',            'funcao','decimo_terceiro_media_variaveis'),
      (1,'script_13o_apuracao_avos_e_medias.sql',        'parametros do 13o por empresa',         'tabela','decimo_terceiro_config'),
      (2,'script_13o_entrega2_estrutura_encargos_lote.sql','INSS do 13o no banco',                'funcao','decimo_terceiro_inss'),
      (2,'script_13o_entrega2_estrutura_encargos_lote.sql','IRRF do 13o no banco',                'funcao','decimo_terceiro_irrf'),
      (2,'script_13o_entrega2_estrutura_encargos_lote.sql','processamento em lote',               'funcao','decimo_terceiro_lote'),
      (2,'script_13o_entrega2_estrutura_encargos_lote.sql','prazo legal (30/11 e 20/12)',         'funcao','decimo_terceiro_prazo_legal'),
      (2,'script_13o_entrega2_estrutura_encargos_lote.sql','reabertura com dupla aprovacao',      'funcao','decimo_terceiro_reabrir'),
      (2,'script_13o_entrega2_estrutura_encargos_lote.sql','uma parcela viva por colaborador',    'indice','folha_13_calculo_parcela_viva_uq'),
      (3,'script_13o_adiantamento_e_media_sumula347.sql', 'media fisica das horas extras (S. 347)','funcao','decimo_terceiro_media_horas_extras'),
      (4,'script_13o_entrega3_alertas_prazos.sql',        'varredura de alertas de prazo',        'funcao','decimo_terceiro_alertas_varrer'),
      (4,'script_13o_entrega3_alertas_prazos.sql',        'alerta vira Plano de Acao',            'funcao','decimo_terceiro_alerta_gerar_acao'),
      (5,'script_13o_entrega4_provisao_rescisao_ferias.sql','provisao contabil mensal',           'funcao','decimo_terceiro_provisionar'),
      (5,'script_13o_entrega4_provisao_rescisao_ferias.sql','conciliacao provisionado x pago',    'funcao','decimo_terceiro_conciliar_provisao'),
      (5,'script_13o_entrega4_provisao_rescisao_ferias.sql','13o da rescisao',                    'funcao','decimo_terceiro_da_rescisao'),
      (5,'script_13o_entrega4_provisao_rescisao_ferias.sql','adiantamento junto as ferias',       'funcao','decimo_terceiro_adiantamento_nas_ferias'),
      (6,'script_13o_entrega5_esocial.sql',               'validacao previa do eSocial',          'funcao','decimo_terceiro_esocial_validar'),
      (6,'script_13o_entrega5_esocial.sql',               'montagem do S-1200 e S-1210',          'funcao','decimo_terceiro_esocial_gerar'),
      (8,'script_13o_culpa_reciproca.sql',                'trava dos dois erros da rescisao',     'funcao','decimo_terceiro_rescisao_valida')
    ) AS t(ordem, script, peca, especie, nome)
)
SELECT p.ordem AS passo, p.peca AS item,
       CASE WHEN CASE p.especie
              WHEN 'funcao' THEN EXISTS (SELECT 1 FROM pg_proc pr JOIN pg_namespace n ON n.oid=pr.pronamespace
                                          WHERE n.nspname='public' AND pr.proname = p.nome)
              WHEN 'tabela' THEN to_regclass('public.' || p.nome) IS NOT NULL
              WHEN 'indice' THEN EXISTS (SELECT 1 FROM pg_class WHERE relname = p.nome AND relkind='i')
            END THEN 'OK' ELSE 'FALTA' END AS situacao,
       CASE WHEN CASE p.especie
              WHEN 'funcao' THEN EXISTS (SELECT 1 FROM pg_proc pr JOIN pg_namespace n ON n.oid=pr.pronamespace
                                          WHERE n.nspname='public' AND pr.proname = p.nome)
              WHEN 'tabela' THEN to_regclass('public.' || p.nome) IS NOT NULL
              WHEN 'indice' THEN EXISTS (SELECT 1 FROM pg_class WHERE relname = p.nome AND relkind='i')
            END THEN NULL ELSE 'cole o ' || p.script END AS erro_tecnico
  FROM pecas p
 UNION ALL
SELECT 3, 'a politica do adiantamento vale no calculo',
       CASE WHEN position('adiantamento_base' in pr.prosrc) > 0 THEN 'OK' ELSE 'FALTA' END,
       CASE WHEN position('adiantamento_base' in pr.prosrc) > 0 THEN NULL
            ELSE 'cole o script_13o_adiantamento_e_media_sumula347.sql (sempre DEPOIS do script 2)' END
  FROM pg_proc pr JOIN pg_namespace n ON n.oid=pr.pronamespace
 WHERE n.nspname='public' AND pr.proname='decimo_terceiro_calcular'
 UNION ALL
SELECT 7, 'aviso previo indenizado projeta o tempo (CLT 487 §1o)',
       CASE WHEN position('v_fim_contrato' in pr.prosrc) > 0 THEN 'OK' ELSE 'FALTA' END,
       CASE WHEN position('v_fim_contrato' in pr.prosrc) > 0 THEN NULL
            ELSE 'cole o script_13o_testes_leva2_e_correcoes.sql' END
  FROM pg_proc pr JOIN pg_namespace n ON n.oid=pr.pronamespace
 WHERE n.nspname='public' AND pr.proname='decimo_terceiro_avos'
 UNION ALL
SELECT 7, 'acidente de trabalho nao derruba avo (Sumula 46 TST)',
       CASE WHEN position('''B31'', ''B32''' in pr.prosrc) > 0 THEN 'OK' ELSE 'FALTA' END,
       CASE WHEN position('''B31'', ''B32''' in pr.prosrc) > 0 THEN NULL
            ELSE 'cole o script_13o_testes_leva2_e_correcoes.sql' END
  FROM pg_proc pr JOIN pg_namespace n ON n.oid=pr.pronamespace
 WHERE n.nspname='public' AND pr.proname='decimo_terceiro_avos'
 UNION ALL
SELECT 7, 'casos de teste documentados (esperado 31)',
       CASE WHEN count(*) >= 31 THEN 'OK' ELSE 'FALTA' END,
       CASE WHEN count(*) >= 31 THEN 'documentados: ' || count(*)::text
            ELSE 'documentados: ' || count(*)::text || ' — cole o script_13o_testes_leva2_e_correcoes.sql' END
  FROM public.qa_casos_teste c JOIN public.qa_modulos m ON m.id = c.modulo_id
 WHERE m.path = 'financeiro/decimo-terceiro'
 UNION ALL
SELECT 7, 'sonda de QA DEC13-070 ajustada a trava de pagamento',
       CASE WHEN position('data_pagamento' in pr.prosrc) > 0 THEN 'OK' ELSE 'FALTA' END,
       CASE WHEN position('data_pagamento' in pr.prosrc) > 0 THEN NULL
            ELSE 'cole o script_13o_corrige_sonda_dec13_070.sql' END
  FROM pg_proc pr JOIN pg_namespace n ON n.oid=pr.pronamespace
 WHERE n.nspname='public' AND pr.proname='qa_caso_dec13_070'
 UNION ALL
SELECT 8, 'motivo CULPA_RECIPROCA no vocabulario de rescisao',
       CASE WHEN EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
                          WHERE t.typname='rescisao_tipo' AND e.enumlabel='CULPA_RECIPROCA')
            THEN 'OK' ELSE 'FALTA' END,
       CASE WHEN EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
                          WHERE t.typname='rescisao_tipo' AND e.enumlabel='CULPA_RECIPROCA')
            THEN NULL ELSE 'cole o script_13o_culpa_reciproca.sql' END
 UNION ALL
SELECT 9, 'varredura diaria de alertas agendada',
       CASE WHEN NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN 'INFORMATIVO'
            WHEN EXISTS (SELECT 1 FROM cron.job WHERE jobname='decimo_terceiro_alertas_diario') THEN 'OK'
            ELSE 'FALTA' END,
       CASE WHEN NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron')
            THEN 'pg_cron nao instalado: a varredura roda pelo botao da tela'
            WHEN EXISTS (SELECT 1 FROM cron.job WHERE jobname='decimo_terceiro_alertas_diario')
            THEN NULL
            ELSE 'rode: SELECT cron.schedule(''decimo_terceiro_alertas_diario'', ''25 6 * * *'', ''SELECT public.decimo_terceiro_alertas_varrer();'');' END
 ORDER BY 3 DESC, 1, 2;
