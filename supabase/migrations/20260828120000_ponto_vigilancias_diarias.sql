-- ============================================================================
-- Vigilâncias do ponto: rotina diária que faz as monitorias RODAREM
--
-- As ondas 5, 8, 9 e 10 criaram rotinas de vigilância que geram alerta no
-- painel de Alertas CLT. Nenhuma delas tem gatilho nem agendamento: são
-- funções que alguém precisa chamar. Como nenhuma tela chama, na prática
-- cinco famílias de alerta nunca foram emitidas — o banco está pronto e
-- silencioso desde 19/08.
--
-- O QUE FAZ (aditivo)
--   (1) ponto_vigilancias_diarias(): passa por todos os tenants ativos e
--       executa as monitorias, uma a uma, isolando erro por tenant/rotina
--       (uma falha não impede as demais). Devolve o resumo do que rodou.
--   (2) Agenda essa rotina uma vez por dia no pg_cron, às 03:37 UTC. O
--       horário é de madrugada e fora dos minutos já ocupados por outras
--       rotinas do módulo (03:17 links, 04:41 expurgo, 05:23 faltas), para
--       não disputar o banco com elas.
--
-- GARANTIAS
--   · As seis rotinas chamadas só INSEREM alerta e todas já se protegem
--     contra duplicidade (NOT EXISTS por tipo/escopo/data), então rodar
--     diariamente não enche o painel de repetição.
--   · Nenhuma delas altera marcação, apuração, saldo ou espelho.
--   · Sem pg_cron (réplica local), a criação da função continua valendo e a
--     rotina pode ser chamada à mão.
--   · Aditivo e idempotente: CREATE OR REPLACE + unschedule antes do
--     schedule.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ponto_vigilancias_diarias()
RETURNS TABLE(rotina text, alertas integer, tenants_com_erro integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t          RECORD;
  v_n        integer;
  v_banco    integer := 0;
  v_art62    integer := 0;  v_e_art62    integer := 0;
  v_estab    integer := 0;  v_e_estab    integer := 0;
  v_cct      integer := 0;  v_e_cct      integer := 0;
  v_escala   integer := 0;  v_e_escala   integer := 0;
  v_cobert   integer := 0;  v_e_cobert   integer := 0;
BEGIN
  -- (a) Banco de horas: vencimento e teto de acúmulo. É a única sem
  -- tenant_id no argumento — varre a base inteira de uma vez.
  BEGIN
    SELECT public.ponto_banco_alertas_monitorar() INTO v_n;
    v_banco := COALESCE(v_n, 0);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ponto_banco_alertas_monitorar falhou: %', SQLERRM;
    v_banco := -1;
  END;

  -- (b) Demais vigilâncias: por tenant ativo, isolando o erro de cada uma.
  FOR t IN SELECT id FROM public.tenants WHERE COALESCE(ativo, true) = true LOOP

    BEGIN
      SELECT public.ponto_detectar_descaracterizacao_art62(t.id) INTO v_n;
      v_art62 := v_art62 + COALESCE(v_n, 0);
    EXCEPTION WHEN OTHERS THEN
      v_e_art62 := v_e_art62 + 1;
      RAISE NOTICE 'descaracterizacao_art62 falhou no tenant %: %', t.id, SQLERRM;
    END;

    BEGIN
      SELECT public.ponto_estabelecimento_obrigatoriedade_monitorar(t.id) INTO v_n;
      v_estab := v_estab + COALESCE(v_n, 0);
    EXCEPTION WHEN OTHERS THEN
      v_e_estab := v_e_estab + 1;
      RAISE NOTICE 'estabelecimento_obrigatoriedade falhou no tenant %: %', t.id, SQLERRM;
    END;

    BEGIN
      SELECT public.ponto_cct_vigiar_vigencia(t.id) INTO v_n;
      v_cct := v_cct + COALESCE(v_n, 0);
    EXCEPTION WHEN OTHERS THEN
      v_e_cct := v_e_cct + 1;
      RAISE NOTICE 'cct_vigiar_vigencia falhou no tenant %: %', t.id, SQLERRM;
    END;

    BEGIN
      SELECT public.ponto_escala_formalizacao_monitorar(t.id) INTO v_n;
      v_escala := v_escala + COALESCE(v_n, 0);
    EXCEPTION WHEN OTHERS THEN
      v_e_escala := v_e_escala + 1;
      RAISE NOTICE 'escala_formalizacao falhou no tenant %: %', t.id, SQLERRM;
    END;

    BEGIN
      SELECT public.ponto_escala_cobertura_monitorar(t.id) INTO v_n;
      v_cobert := v_cobert + COALESCE(v_n, 0);
    EXCEPTION WHEN OTHERS THEN
      v_e_cobert := v_e_cobert + 1;
      RAISE NOTICE 'escala_cobertura falhou no tenant %: %', t.id, SQLERRM;
    END;

  END LOOP;

  RETURN QUERY
  SELECT * FROM (VALUES
    ('banco_horas_vencimento_e_teto', v_banco,  0),
    ('descaracterizacao_art62',       v_art62,  v_e_art62),
    ('estabelecimento_obrigatorio',   v_estab,  v_e_estab),
    ('cct_vigencia',                  v_cct,    v_e_cct),
    ('escala_formalizacao',           v_escala, v_e_escala),
    ('escala_cobertura_turno',        v_cobert, v_e_cobert)
  ) AS x(rotina, alertas, tenants_com_erro);
END;
$$;

COMMENT ON FUNCTION public.ponto_vigilancias_diarias() IS
  'Executa as vigilancias do ponto (banco de horas, art. 62, obrigatoriedade por estabelecimento, vigencia de CCT, formalizacao de escala e cobertura de turno) em todos os tenants ativos, isolando erro por tenant/rotina. Somente insere alerta; nao altera marcacao, apuracao nem espelho. Agendada diariamente.';

REVOKE EXECUTE ON FUNCTION public.ponto_vigilancias_diarias() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ponto_vigilancias_diarias() TO authenticated;

-- Agendamento diário -------------------------------------------------------
DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('ponto-vigilancias-diarias')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ponto-vigilancias-diarias');
    PERFORM cron.schedule('ponto-vigilancias-diarias', '37 3 * * *',
      'SELECT public.ponto_vigilancias_diarias();');
    RAISE NOTICE 'Vigilancias do ponto agendadas (03:37 UTC, diariamente).';
  ELSE
    RAISE NOTICE 'pg_cron ausente — chame public.ponto_vigilancias_diarias() pela aplicacao.';
  END IF;
END $cron$;
