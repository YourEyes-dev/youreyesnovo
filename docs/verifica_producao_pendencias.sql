-- ============================================================================
-- VERIFICACAO READ-ONLY DA PRODUCAO — o que ainda falta no banco antes de
-- publicar as telas acumuladas. SO LE (nenhum INSERT/UPDATE/DDL). Seguro para
-- colar no SQL Editor de PRODUCAO. Retorna uma tabela:
--   feature | tipo | objeto | existe_em_producao
-- Onde existe=false => precisa colar o script de banco daquela feature ANTES
-- de publicar a tela correspondente.
--
-- Como ler: agrupe por 'feature'. Se TODAS as linhas da feature = true, o banco
-- dela ja esta em producao e a tela pode ser publicada. Qualquer false => segure
-- a publicacao daquela feature e me mande o resultado que eu digo qual script
-- colar.
--
-- A lista de objetos (VALUES abaixo) e preenchida a partir da auditoria por
-- feature. Marcador: << PREENCHER >> enquanto incompleto.
-- ============================================================================

WITH alvo(feature, tipo, nome, arg_ou_tabela) AS (
  VALUES
  -- feature                        | tipo        | nome                                         | arg(funcao) OU tabela(coluna/politica/trigger) OU typename(enum)

  -- 1) Assinatura / biometria (script_ass0001_fundacao.sql)
  ('1-assinatura',                  'funcao',    'selar_assinatura',                           'text,text,timestamptz,text'),
  ('1-assinatura',                  'funcao',    'registrar_assinatura_trilha',                'jsonb'),
  ('1-assinatura',                  'tabela',    'public.assinaturas_trilha',                  ''),
  ('1-assinatura',                  'tabela',    'public.consentimentos_assinatura',           ''),
  ('1-assinatura',                  'bucket',    'assinatura-evidencias',                      ''),

  -- 2) ISOL-005 documento_audit_logs (SEM script docs/ ainda — risco de exposicao entre empresas)
  ('2-isol005-audit-docs',          'politica',  'documento_audit_logs_leitura_tenant',        'public.documento_audit_logs'),

  -- 3) Jornada leitura lote1b (script_jornada_lote1b_leitura_por_perfil.sql)
  ('3-jornada-lote1b',              'politica',  'perfil_restringe_leitura_ponto_acordos',     'public.ponto_acordos'),

  -- 4) Jornada escrita por perfil (script_jornada_escrita_por_perfil.sql)
  ('4-jornada-escrita',             'politica',  'perfil_restringe_escrita_ponto_ajustes_ins', 'public.ponto_ajustes'),

  -- 5) Profiles trava tenant (script_profiles_trava_tenant.sql)
  ('5-profiles-trava',              'trigger',   'trg_profiles_protege_tenant',                'public.profiles'),

  -- 6) Usuario vinculos por perfil (script_usuario_vinculos_por_perfil.sql)
  ('6-usuario-vinculos',            'funcao',    'ye_meu_usuario_base_id',                     'uuid'),
  ('6-usuario-vinculos',            'politica',  'perfil_restringe_leitura_usuario_vinculos',  'public.usuario_vinculos'),

  -- 7) Logs de acesso por perfil (script_logs_de_acesso_por_perfil.sql)
  ('7-logs-acesso',                 'funcao',    'audit_carimba_autor',                        ''),
  ('7-logs-acesso',                 'politica',  'perfil_restringe_leitura_usuario_audit_log', 'public.usuario_audit_log'),

  -- 8) Saude/RH leitura por perfil (script_saude_rh_leitura_por_perfil.sql)
  ('8-saude-rh',                    'funcao',    'afastamentos_ativos_resumo',                 ''),
  ('8-saude-rh',                    'politica',  'perfil_restringe_leitura_afastamentos',      'public.afastamentos'),

  -- 9) Salario padrao fechado (script_salario_padrao_fechado.sql) — ALTERA DADO
  ('9-salario-padrao',              'tabela',    'public.contratos_experiencia_segura',        ''),
  ('9-salario-padrao',              'funcao',    'contratos_preserva_salario_mascarado',       ''),

  -- 10) Admissoes funcoes de leitura (script_admissoes_funcoes_leitura.sql) — 5 telas dependem
  ('10-admissoes-funcoes',          'funcao',    'colaboradores_diretorio',                    'uuid'),
  ('10-admissoes-funcoes',          'funcao',    'meu_time_admissoes',                         ''),
  ('10-admissoes-funcoes',          'funcao',    'celebracoes_pessoas',                        'uuid'),
  ('10-admissoes-funcoes',          'funcao',    'admissoes_contagens',                        'uuid'),
  ('10-admissoes-funcoes',          'funcao',    'admissoes_historico_status',                 'uuid,timestamptz,timestamptz'),

  -- 11) Admissoes trava de leitura (script_admissoes_trava_leitura.sql)
  ('11-admissoes-trava',            'funcao',    'ye_modulos_dados_pessoas',                   ''),
  ('11-admissoes-trava',            'politica',  'perfil_restringe_leitura_admissoes',         'public.admissoes'),

  -- 12) Perfis de acesso leitura/escrita (script_perfis_acesso_leitura_escrita.sql)
  ('12-perfis-acesso',              'funcao',    'ye_meus_perfis_ids',                         'uuid'),
  ('12-perfis-acesso',              'politica',  'perfil_restringe_leitura_perfil_permissoes', 'public.perfil_permissoes'),

  -- 13) Usuarios funcoes de leitura (script_usuarios_funcoes_leitura.sql) — 4 telas dependem
  ('13-usuarios-funcoes',           'funcao',    'usuarios_diretorio',                         ''),
  ('13-usuarios-funcoes',           'funcao',    'usuario_por_cpf',                            'text'),
  ('13-usuarios-funcoes',           'funcao',    'usuarios_contar_por_cargo',                  'text'),

  -- 14) Avaliacoes/metas leitura (script_avaliacoes_metas_leitura_por_perfil.sql)
  ('14-avaliacoes-metas',           'politica',  'perfil_restringe_leitura_metas',             'public.metas'),

  -- 15) Perfil criticas saude/humor/avaliacao (script_perfil_criticas_saude_humor_avaliacao_leitura.sql)
  ('15-perfil-criticas',            'politica',  'perfil_restringe_leitura_humor_diario',      'public.humor_diario'),

  -- 16) SEG-0007 perfil modelo SST table-driven (script_seg0007_perfil_modelo_sst_table_driven.sql)
  ('16-seg0007-modelo-sst',         'coluna',    'modelo_sistema',                             'public.perfis_acesso'),
  ('16-seg0007-modelo-sst',         'funcao',    'perfil_modelo_tecnico_sst',                  'uuid'),

  -- 17) SEG-0008 admin master modelo tabela (script_seg0008_admin_master_modelo_tabela.sql)
  ('17-seg0008-admin-master',       'funcao',    'admin_master_modulos_plano',                 ''),
  ('17-seg0008-admin-master',       'funcao',    'admin_master_modulos_faltantes',             ''),

  -- 18) Backup schema privado (script_backup_schema_privado.sql)
  ('18-backup-schema',              'tabela',    'backup.perfis_modelo_sst_20261026',          ''),

  -- 19) Hub do contador (script_hub_contador_link_publico.sql)
  ('19-hub-contador',               'tabela',    'public.hub_contador_links',                  ''),
  ('19-hub-contador',               'funcao',    'buscar_contador_acesso_por_token',           'text'),
  ('19-hub-contador',               'coluna',    'visivel_contabilidade',                      'public.hub_processo_documentos'),

  -- 20) Psicossocial evidencias fase1 (script_psicossocial_evidencias_fase1.sql)
  ('20-psicossocial-evid',          'tabela',    'public.psicossocial_fatores_catalogo',       ''),
  ('20-psicossocial-evid',          'coluna',    'fator_id',                                   'public.psicossocial_evidencias'),
  ('20-psicossocial-evid',          'funcao',    'psicossocial_recalcular_evidencias',         'uuid'),

  -- 21) EPI status 'recusado' (script_epi_status_recusado_parte1/2.sql) — feature ja publicada; so o enum e novo
  ('21-epi-recusado',               'enum_valor','recusado',                                   'entrega_status'),

  -- 22) PONTO (ja aplicado por voce em producao — conferencia de que esta la)
  ('22-ponto-noturno-cron',         'funcao',    'ponto_adicional_noturno_minutos',            'date,time,time,time,time,boolean'),
  ('22-ponto-noturno-cron',         'coluna',    'adicional_noturno_minutos',                  'public.ponto_diario'),
  ('22-ponto-noturno-cron',         'cron',      'ponto-banco-vencido-diario',                 '')
),
chk AS (
  SELECT
    a.feature,
    a.tipo,
    a.nome
      || CASE WHEN a.tipo = 'funcao'  AND a.arg_ou_tabela <> '' THEN '(' || a.arg_ou_tabela || ')' ELSE '' END
      || CASE WHEN a.tipo IN ('coluna','politica') THEN '  @ ' || a.arg_ou_tabela ELSE '' END
      AS objeto,
    CASE a.tipo
      WHEN 'funcao' THEN
        (to_regprocedure('public.' || a.nome || '(' || a.arg_ou_tabela || ')') IS NOT NULL)
      WHEN 'tabela' THEN
        (to_regclass(a.nome) IS NOT NULL)                       -- nome ja com schema se preciso (ex.: backup.x)
      WHEN 'coluna' THEN
        EXISTS (SELECT 1 FROM information_schema.columns c
                 WHERE c.table_schema = split_part(a.arg_ou_tabela, '.', 1)
                   AND c.table_name   = split_part(a.arg_ou_tabela, '.', 2)
                   AND c.column_name  = a.nome)
      WHEN 'politica' THEN
        EXISTS (SELECT 1 FROM pg_policies p
                 WHERE p.schemaname = COALESCE(NULLIF(split_part(a.arg_ou_tabela,'.',1),''),'public')
                   AND p.tablename  = split_part(a.arg_ou_tabela, '.', 2)
                   AND p.policyname = a.nome)
      WHEN 'trigger' THEN
        EXISTS (SELECT 1 FROM pg_trigger t
                 WHERE NOT t.tgisinternal AND t.tgname = a.nome
                   AND t.tgrelid = to_regclass(a.arg_ou_tabela))
      WHEN 'bucket' THEN
        EXISTS (SELECT 1 FROM storage.buckets b WHERE b.id = a.nome)
      WHEN 'cron' THEN
        EXISTS (SELECT 1 FROM cron.job j WHERE j.jobname = a.nome)
      WHEN 'enum_valor' THEN
        EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type ty ON ty.oid = e.enumtypid
                 WHERE ty.typname = a.arg_ou_tabela AND e.enumlabel = a.nome)
      ELSE NULL
    END AS existe_em_producao
  FROM alvo a
  WHERE a.feature <> '__placeholder__'
)
SELECT feature, tipo, objeto, existe_em_producao
FROM chk
ORDER BY feature,
         existe_em_producao NULLS FIRST,   -- faltando primeiro, dentro da feature
         tipo, objeto;
