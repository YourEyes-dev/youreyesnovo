-- ============================================================================
-- SCRIPT DE ENTREGA — Ponto: vincula à empresa (CNPJ) os DIAS do ponto
-- (ponto_diario) que ficaram SEM empresa (empresa_id nulo) nas 4 empresas.
--
-- Por quê: o espelho e o banco de horas são montados por empresa e incluem
-- os dias sem empresa em TODAS as empresas — o espelho de um CNPJ mistura
-- colaboradores de outro. A empresa certa é a que o próprio sistema atribui
-- pelo cadastro (ponto_empresa_do_cpf); só corrige quando o resultado é uma
-- das 4 empresas abaixo.
--
-- Batidas (ponto_marcacoes) NÃO são alteradas: o NSR é numerado por empresa
-- ("balde") e as batidas sem empresa têm sequência própria; movê-las colidiria
-- NSR. O espelho já casa as batidas pelo CPF. Ajustes também não são alterados
-- (o gatilho de consolidação reprocessaria o dia).
--
-- O que muda: só a coluna empresa_id do dia. Nenhum valor do dia (horas,
-- status, saldo) é recalculado: os gatilhos de recálculo e a trava de período
-- fechado ficam desligados só durante o UPDATE, dentro da transação.
-- Dia que já tem linha com a empresa certa no mesmo dia NÃO é tocado (evita
-- duplicar) — aparece na conferência como "dias_conflito_ou_sem_cpf".
--
-- Backup antes (schema privado backup). Desfazer:
--   UPDATE public.ponto_diario d SET empresa_id = NULL
--     FROM backup.ponto_vinc_emp_diario_20261029 b WHERE b.id = d.id;
-- Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- 1) Backup das linhas sem empresa do(s) tenant(s) das 4 empresas
DO $bkp$
DECLARE
  v_tenants text := 'SELECT ec.tenant_id FROM public.empresa_cadastro ec '
    || 'WHERE regexp_replace(COALESCE(ec.cnpj,''''),''[^0-9]'','''',''g'') '
    || '= ANY (ARRAY[''26114701000145'',''41085456000189'',''41085456000260'',''31219374000126''])';
BEGIN
  CREATE SCHEMA IF NOT EXISTS backup;
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS backup.ponto_vinc_emp_marc_20261029 AS '
    || 'SELECT m.id, m.tenant_id, m.colaborador_cpf, m.data_marcacao, m.empresa_id '
    || 'FROM public.ponto_marcacoes m WHERE m.empresa_id IS NULL AND m.tenant_id IN (' || v_tenants || ')';
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS backup.ponto_vinc_emp_diario_20261029 AS '
    || 'SELECT d.id, d.tenant_id, d.colaborador_cpf, d.data, d.empresa_id '
    || 'FROM public.ponto_diario d WHERE d.empresa_id IS NULL AND d.tenant_id IN (' || v_tenants || ')';
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS backup.ponto_vinc_emp_ajustes_20261029 AS '
    || 'SELECT a.id, a.tenant_id, a.colaborador_cpf, a.data_referencia, a.empresa_id '
    || 'FROM public.ponto_ajustes a WHERE a.empresa_id IS NULL AND a.tenant_id IN (' || v_tenants || ')';
END
$bkp$;

-- 2) Dias (sem duplicar dia que já tem linha com a empresa certa)
-- Só a empresa muda: os gatilhos que RECALCULAM o dia (pré-assinalação,
-- adicional noturno, supressão de intervalo, semanal, alertas) e a trava de
-- período fechado ficam desligados durante este UPDATE, para nenhum valor
-- histórico do dia ser recalculado. Auditoria e updated_at seguem ligados.
DO $desliga$
DECLARE r record;
BEGIN
  FOR r IN SELECT tgname FROM pg_trigger
            WHERE tgrelid = 'public.ponto_diario'::regclass AND NOT tgisinternal
              AND tgname IN ('trg_validar_periodo_aberto_ponto_diario', 'trg_ponto_diario_pre_assinalacao', 'trg_ponto_diario_adicional_noturno', 'trg_ponto_diario_supressao_intervalo', 'trg_consolidar_ponto_semanal', 'trigger_gerar_alertas_ponto')
  LOOP
    EXECUTE format('ALTER TABLE public.ponto_diario DISABLE TRIGGER %I', r.tgname);
  END LOOP;
END
$desliga$;

WITH emp AS MATERIALIZED (
  SELECT ec.id AS empresa_id
  FROM public.empresa_cadastro ec
  WHERE regexp_replace(COALESCE(ec.cnpj,''),'[^0-9]','','g')
        = ANY (ARRAY['26114701000145','41085456000189','41085456000260','31219374000126'])
),
mapa AS MATERIALIZED (
  SELECT x.tenant_id, x.colaborador_cpf,
         public.ponto_empresa_do_cpf(x.tenant_id, x.colaborador_cpf) AS empresa_id
  FROM (SELECT DISTINCT tenant_id, colaborador_cpf FROM backup.ponto_vinc_emp_diario_20261029
        WHERE COALESCE(colaborador_cpf,'') <> '') x
)
UPDATE public.ponto_diario d
   SET empresa_id = mp.empresa_id
  FROM mapa mp
 WHERE d.empresa_id IS NULL
   AND d.tenant_id = mp.tenant_id
   AND d.colaborador_cpf = mp.colaborador_cpf
   AND mp.empresa_id IN (SELECT empresa_id FROM emp)
   AND NOT EXISTS (SELECT 1 FROM public.ponto_diario d2
                    WHERE d2.tenant_id = d.tenant_id
                      AND d2.colaborador_cpf = d.colaborador_cpf
                      AND d2.data = d.data
                      AND d2.empresa_id = mp.empresa_id);

DO $religa$
DECLARE r record;
BEGIN
  FOR r IN SELECT tgname FROM pg_trigger
            WHERE tgrelid = 'public.ponto_diario'::regclass AND NOT tgisinternal
              AND tgname IN ('trg_validar_periodo_aberto_ponto_diario', 'trg_ponto_diario_pre_assinalacao', 'trg_ponto_diario_adicional_noturno', 'trg_ponto_diario_supressao_intervalo', 'trg_consolidar_ponto_semanal', 'trigger_gerar_alertas_ponto')
  LOOP
    EXECUTE format('ALTER TABLE public.ponto_diario ENABLE TRIGGER %I', r.tgname);
  END LOOP;
END
$religa$;

-- 3) Conferência
SELECT json_build_object(
  'batidas_sem_empresa_info', (SELECT count(*) FROM backup.ponto_vinc_emp_marc_20261029),
  'dias_sem_empresa_antes', (SELECT count(*) FROM backup.ponto_vinc_emp_diario_20261029),
  'dias_vinculados', (SELECT count(*) FROM backup.ponto_vinc_emp_diario_20261029 b
                       JOIN public.ponto_diario d ON d.id = b.id WHERE d.empresa_id IS NOT NULL),
  'dias_conflito_ou_sem_cpf', (SELECT count(*) FROM backup.ponto_vinc_emp_diario_20261029 b
                       JOIN public.ponto_diario d ON d.id = b.id WHERE d.empresa_id IS NULL),
  'ajustes_sem_empresa_info', (SELECT count(*) FROM backup.ponto_vinc_emp_ajustes_20261029),
  'gatilhos_do_dia_religados', (SELECT bool_and(tgenabled <> 'D') FROM pg_trigger
                          WHERE tgrelid = 'public.ponto_diario'::regclass AND NOT tgisinternal)
) AS resultado;
