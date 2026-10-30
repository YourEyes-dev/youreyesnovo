-- ============================================================================
-- ESPELHO DE PONTO COM ASSINATURA ELETRÔNICA — Fatia 1, PARTE 3 de 4 (lembretes e agenda)
-- Cole INTEIRO no SQL Editor, depois da parte 2.
-- Equivale à migration 20261030100649_assinatura_lembretes_cron.sql.
-- A rotina SÓ chama a função de borda se app_config tiver 'supabase_url' e
-- 'assinatura_despachar_segredo' (o segredo é gerado aqui, se faltar).
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.assinatura_expirar_vencidas()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_id uuid;
  v_n  int := 0;
BEGIN
  FOR v_id IN
    SELECT s.id FROM public.assinatura_solicitacoes s
     WHERE s.status IN ('na_fila', 'enviado', 'visualizado')
       AND s.expira_em IS NOT NULL AND s.expira_em < now()
  LOOP
    UPDATE public.assinatura_solicitacoes
       SET status = 'expirado', proximo_lembrete_em = NULL
     WHERE id = v_id;
    PERFORM public.assinatura_evento(v_id, 'expirado', 'sistema', NULL, '{}'::jsonb);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.assinatura_lembretes_devidos(p_limite integer DEFAULT 200)
RETURNS TABLE (
  solicitacao_id   uuid,
  tenant_id        uuid,
  colaborador_nome text,
  email            text,
  link_base        text,
  referencia       text,
  lembrete_numero  integer,
  expira_em        timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT s.id, s.tenant_id, s.colaborador_nome, s.email, s.link_base, s.referencia,
         s.lembretes_enviados + 1, s.expira_em
    FROM public.assinatura_solicitacoes s
   WHERE s.status IN ('enviado', 'visualizado')
     AND s.proximo_lembrete_em IS NOT NULL
     AND s.proximo_lembrete_em <= now()
     AND s.lembretes_enviados < 3
     AND s.expira_em > now()
     AND COALESCE(s.email, '') <> ''
     -- Só colaborador ativo: desligado não recebe lembrete.
     AND EXISTS (
       SELECT 1 FROM public.admissoes a
        WHERE a.tenant_id = s.tenant_id
          AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') = s.colaborador_cpf
          AND a.status::text = 'concluido'
          AND (a.data_desligamento IS NULL OR a.data_desligamento::date > CURRENT_DATE))
   ORDER BY s.proximo_lembrete_em
   LIMIT GREATEST(COALESCE(p_limite, 200), 1);
$fn$;

CREATE OR REPLACE FUNCTION public.assinatura_disparar_lembretes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_url      text := (SELECT valor FROM public.app_config WHERE chave = 'supabase_url');
  v_segredo  text := (SELECT valor FROM public.app_config WHERE chave = 'assinatura_despachar_segredo');
  v_expiradas int := public.assinatura_expirar_vencidas();
  v_devidos  int := (SELECT count(*) FROM public.assinatura_lembretes_devidos(1000));
  v_fila     int := (SELECT count(*) FROM public.assinatura_solicitacoes s
                      WHERE s.status = 'na_fila' AND s.envio_proxima_em IS NOT NULL AND s.envio_proxima_em <= now());
BEGIN
  IF COALESCE(v_url, '') = '' OR COALESCE(v_segredo, '') = '' THEN
    RAISE NOTICE 'assinatura_disparar_lembretes: app_config sem supabase_url/assinatura_despachar_segredo — ninguém foi chamado (proteção de ambiente).';
    RETURN jsonb_build_object('chamou', false, 'motivo', 'sem_configuracao', 'expiradas', v_expiradas, 'devidos', v_devidos);
  END IF;
  IF v_devidos = 0 AND v_fila = 0 THEN
    RETURN jsonb_build_object('chamou', false, 'motivo', 'nada_devido', 'expiradas', v_expiradas);
  END IF;

  PERFORM net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/assinatura-despachar',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-assinatura-segredo', v_segredo),
    body := jsonb_build_object('modo', 'agendado'));
  RETURN jsonb_build_object('chamou', true, 'expiradas', v_expiradas, 'devidos', v_devidos, 'fila', v_fila);
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.assinatura_expirar_vencidas() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.assinatura_lembretes_devidos(integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.assinatura_disparar_lembretes() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.assinatura_expirar_vencidas() TO service_role;
GRANT EXECUTE ON FUNCTION public.assinatura_lembretes_devidos(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.assinatura_disparar_lembretes() TO service_role;

-- Segredo próprio da rotina (a função de borda lê o mesmo valor de app_config).
-- Gerado no banco, uma vez por ambiente; não fica no código.
INSERT INTO public.app_config (chave, valor)
SELECT 'assinatura_despachar_segredo', encode(public.gen_random_bytes(24), 'hex')
WHERE to_regclass('public.app_config') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.app_config WHERE chave = 'assinatura_despachar_segredo');

DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('assinatura-lembretes-diario')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'assinatura-lembretes-diario');
    PERFORM cron.schedule('assinatura-lembretes-diario', '0 12 * * *',
      $job$ SELECT public.assinatura_disparar_lembretes(); $job$);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Agenda assinatura-lembretes-diario nao criada: %', SQLERRM;
END $cron$;

-- CONFERÊNCIA (não dispara nada; só mostra a configuração).
SELECT
  EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'assinatura-lembretes-diario')              AS agenda_ok,
  EXISTS (SELECT 1 FROM public.app_config WHERE chave = 'supabase_url' AND valor <> '')       AS tem_supabase_url,
  EXISTS (SELECT 1 FROM public.app_config WHERE chave = 'assinatura_despachar_segredo')      AS tem_segredo,
  to_regprocedure('public.assinatura_lembretes_devidos(integer)') IS NOT NULL                AS lembretes_ok;
