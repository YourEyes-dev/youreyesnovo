-- ============================================================================
-- ENTREGA — Vigilancias do ponto: rotina diaria que faz as monitorias RODAREM
--
-- Colar INTEIRO no SQL Editor do projeto de PRODUCAO e executar uma vez.
--
-- CONTEXTO
--   As ondas 5, 7, 8, 9 e 10 criaram rotinas de vigilancia que geram alerta no
--   painel de Alertas CLT (vencimento e teto do banco de horas, controle de
--   fato que descaracteriza o art. 62, obrigatoriedade do controle por
--   estabelecimento, vigencia de instrumento coletivo, formalizacao de escala
--   12x36/revezamento e cobertura de turno). Nenhuma tem gatilho nem
--   agendamento: sao funcoes que alguem precisa chamar. Como nenhuma tela
--   chama, essas familias de alerta nunca foram emitidas.
--
-- O QUE ESTE SCRIPT FAZ
--   (1) Cria a rotina public.ponto_vigilancias_diarias(), que percorre os
--       tenants ativos e executa cada uma das OITO monitorias isolando erro
--       por tenant/rotina (uma falha nao impede as demais): banco de horas,
--       art. 62, obrigatoriedade por estabelecimento, vigencia de CCT,
--       formalizacao de escala, cobertura de turno, vencimento do certificado
--       digital e prazo de 48h do comprovante.
--   (2) Agenda essa rotina no pg_cron para rodar 1x por dia, as 03:37 UTC.
--
-- SEGURANCA DO DADO
--   Este script SO CRIA coisa nova (uma funcao e um agendamento). Nao altera
--   nem apaga nenhuma linha existente, entao nao ha copia de seguranca a
--   fazer. As rotinas chamadas apenas INSEREM alerta e todas ja se protegem
--   contra duplicidade, entao rodar todo dia nao repete alerta. Nenhuma delas
--   altera marcacao, apuracao, saldo ou espelho.
--
-- IDEMPOTENTE: rodar duas vezes nao quebra nem duplica (CREATE OR REPLACE e
-- reagendamento do mesmo job).
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.ponto_vigilancias_diarias()
RETURNS TABLE(rotina text, alertas integer, tenants_com_erro integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $vig$
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
$vig$;

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
-- ============================================================================
-- CONFERENCIA (o editor mostra so o ultimo resultado)
-- ============================================================================
SELECT
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'ponto_vigilancias_diarias') = 1
    AS rotina_criada,
  EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
    AS pg_cron_presente,
  (SELECT count(*) FROM cron.job WHERE jobname = 'ponto-vigilancias-diarias') = 1
    AS agendamento_ativo,
  (SELECT schedule FROM cron.job WHERE jobname = 'ponto-vigilancias-diarias')
    AS horario_utc,
  (SELECT count(*) FROM public.tenants WHERE COALESCE(ativo, true) = true)
    AS tenants_que_serao_varridos,
  CASE
    WHEN (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proname = 'ponto_vigilancias_diarias') <> 1
      THEN 'FALHOU — a rotina nao foi criada; veja as mensagens acima'
    WHEN NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
      THEN 'ATENCAO — rotina criada, mas o pg_cron nao esta neste banco: nada sera agendado'
    WHEN (SELECT count(*) FROM cron.job WHERE jobname = 'ponto-vigilancias-diarias') = 1
      THEN 'OK'
    ELSE 'FALHOU — a rotina existe mas o agendamento nao foi criado'
  END AS erro_tecnico;
