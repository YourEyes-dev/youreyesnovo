-- ============================================================================
-- Vigilâncias do ponto — acrescenta as duas rotinas da onda 7
--
-- A rotina diária (20260828120000) cobria seis vigilâncias. Duas ficaram de
-- fora porque só apareceram ao ligar as telas da onda 7, e estavam no mesmo
-- estado das outras — funções sem gatilho e sem agendamento, que ninguém
-- chamava:
--   · ponto_certificado_vigiar_vencimento — certificado ICP-Brasil vencido
--     paralisa a emissão assinada do AFD/AEJ bem na hora da fiscalização;
--   · ponto_comprovante_vigiar_48h — marcação sem comprovante dentro do prazo
--     de 48h da Portaria 671.
--
-- O QUE FAZ: CREATE OR REPLACE da mesma função, agora com oito rotinas, e
-- reafirma o agendamento (mesmo nome de job e mesmo horário — reagendar o
-- mesmo nome não duplica).
--
-- GARANTIAS: as duas rotinas novas só INSEREM alerta, com a mesma proteção
-- contra duplicidade das demais; erro em uma não impede as outras. Não altera
-- marcação, apuração, saldo nem espelho. Aditivo e idempotente.
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
  v_cert     integer := 0;  v_e_cert     integer := 0;
  v_compr    integer := 0;  v_e_compr    integer := 0;
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

    BEGIN
      SELECT public.ponto_certificado_vigiar_vencimento(t.id) INTO v_n;
      v_cert := v_cert + COALESCE(v_n, 0);
    EXCEPTION WHEN OTHERS THEN
      v_e_cert := v_e_cert + 1;
      RAISE NOTICE 'certificado_vigiar_vencimento falhou no tenant %: %', t.id, SQLERRM;
    END;

    BEGIN
      SELECT public.ponto_comprovante_vigiar_48h(t.id) INTO v_n;
      v_compr := v_compr + COALESCE(v_n, 0);
    EXCEPTION WHEN OTHERS THEN
      v_e_compr := v_e_compr + 1;
      RAISE NOTICE 'comprovante_vigiar_48h falhou no tenant %: %', t.id, SQLERRM;
    END;

  END LOOP;

  RETURN QUERY
  SELECT * FROM (VALUES
    ('banco_horas_vencimento_e_teto', v_banco,  0),
    ('descaracterizacao_art62',       v_art62,  v_e_art62),
    ('estabelecimento_obrigatorio',   v_estab,  v_e_estab),
    ('cct_vigencia',                  v_cct,    v_e_cct),
    ('escala_formalizacao',           v_escala, v_e_escala),
    ('escala_cobertura_turno',        v_cobert, v_e_cobert),
    ('certificado_vencimento',        v_cert,   v_e_cert),
    ('comprovante_prazo_48h',         v_compr,  v_e_compr)
  ) AS x(rotina, alertas, tenants_com_erro);
END;
$$;

COMMENT ON FUNCTION public.ponto_vigilancias_diarias() IS
  'Executa as vigilancias do ponto (banco de horas, art. 62, obrigatoriedade por estabelecimento, vigencia de CCT, formalizacao de escala, cobertura de turno, vencimento do certificado digital e prazo de 48h do comprovante) em todos os tenants ativos, isolando erro por tenant/rotina. Somente insere alerta; nao altera marcacao, apuracao nem espelho. Agendada diariamente.';

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
