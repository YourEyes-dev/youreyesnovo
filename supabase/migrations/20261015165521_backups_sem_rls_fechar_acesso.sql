-- Fecha o acesso via API as tabelas de backup que ficaram sem RLS (copias de ponto,
-- afastamento, ouvidoria e planos guardadas pelas correcoes de set/2026).
-- Nao altera nem apaga dado: so liga RLS e retira o acesso de anon e authenticated.
-- Sem politica, service_role e o dono do banco continuam lendo (rollback e conferencia).
-- Idempotente; tabela ausente (staging) e ignorada.
DO $rls$
DECLARE
  v_tab text;
  v_tabs text[] := ARRAY[
    'backup_conf_deslig_foto_20260929',
    'backup_conf_deslig_movs_20260929',
    'backup_encerra_deslig_afast_20260929',
    'backup_escala_desligados_20260929',
    'backup_features_20260925',
    'backup_features_nomes_20260925',
    'backup_ouv_pontes_20260925',
    'backup_plan_entitlements_20260925'
  ];
BEGIN
  SET LOCAL lock_timeout = '10s';
  FOREACH v_tab IN ARRAY v_tabs LOOP
    BEGIN
      IF to_regclass('public.' || quote_ident(v_tab)) IS NOT NULL THEN
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', v_tab);
        EXECUTE format('REVOKE ALL ON TABLE public.%I FROM anon, authenticated', v_tab);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'backup %: % (%)', v_tab, SQLERRM, SQLSTATE;
    END;
  END LOOP;
END
$rls$;
