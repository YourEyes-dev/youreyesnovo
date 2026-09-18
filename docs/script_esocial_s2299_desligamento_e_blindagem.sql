-- ============================================================================
-- eSocial S-2299 (desligamento) + BLINDAGEM dos gatilhos — ENTREGA producao.
--
-- (1) Blinda o gatilho do S-2200 (ja em producao) para NAO bloquear a admissao
--     se a geracao falhar.
-- (2) Entrega o S-2299 do desligamento: gerador + indice + gatilho (blindado) +
--     backfill dos desligamentos historicos como 'historico' (NAO transmitem).
--
-- DECISAO (mesma do S-2200): os desligamentos JA existentes viram 'historico'
-- (contam, mas nao vao ao governo). Desligamentos NOVOS geram S-2299
-- 'pendente_assinatura' para o fluxo normal.
--
-- Nao altera dado existente (so INSERE eventos). lock_timeout curto; idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- Colunas (drift) — no-op onde ja existem
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS empresa_id uuid;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS origem_modulo text;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS origem_id uuid;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS colaborador_cpf text;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS competencia text;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS data_limite date;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS leiaute_versao text;

-- (1) BLINDAGEM do gatilho S-2200
CREATE OR REPLACE FUNCTION public.trg_admissao_gera_s2200()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.status = 'concluido'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'concluido') THEN
    BEGIN
      PERFORM public.admissao_esocial_gerar_s2200(NEW.id, 'pendente_assinatura');
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'S-2200 nao gerado para admissao % (segue sem bloquear): %', NEW.id, SQLERRM;
    END;
  END IF;
  RETURN NEW;
END $fn$;

-- (2) Gerador do S-2299
CREATE OR REPLACE FUNCTION public.desligamento_esocial_gerar_s2299(
  p_admissao uuid, p_status text DEFAULT 'pendente_assinatura')
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE a RECORD; v_cpf text; v_payload jsonb; v_limite date;
BEGIN
  SELECT * INTO a FROM public.admissoes
   WHERE id = p_admissao AND status = 'desligado' AND data_desligamento IS NOT NULL;
  IF NOT FOUND THEN RETURN 0; END IF;
  v_cpf := regexp_replace(COALESCE(a.cpf,''), '\D', '', 'g');
  v_limite := (date_trunc('month', a.data_desligamento) + interval '1 month' + interval '9 days')::date;
  v_payload := jsonb_build_object(
    'evento','S-2299','cpfTrab',v_cpf,'matricula',a.matricula_esocial,
    'dtDeslig',a.data_desligamento,'mtvDeslig',a.motivo_desligamento,'nmTrab',a.nome_completo);
  INSERT INTO public.esocial_transmissoes
    (tenant_id, empresa_id, tipo_evento, origem_modulo, origem_id, colaborador_cpf,
     competencia, data_limite, xml_enviado, status, leiaute_versao, updated_at)
  VALUES
    (a.tenant_id, a.empresa_id, 'S-2299', 'desligamento', a.id, v_cpf,
     to_char(a.data_desligamento, 'YYYY-MM'), v_limite, v_payload::text, p_status, 'S-1.3.0', now())
  ON CONFLICT (tenant_id, origem_id, tipo_evento) WHERE origem_modulo = 'desligamento'
  DO UPDATE SET
     xml_enviado = EXCLUDED.xml_enviado, data_limite = EXCLUDED.data_limite,
     status = CASE WHEN public.esocial_transmissoes.status IN ('processado','enviado')
                   THEN public.esocial_transmissoes.status ELSE EXCLUDED.status END,
     updated_at = now();
  RETURN 1;
END $fn$;

-- (3) Idempotencia
CREATE UNIQUE INDEX IF NOT EXISTS uq_esocial_s2299_desligamento
  ON public.esocial_transmissoes (tenant_id, origem_id, tipo_evento)
  WHERE origem_modulo = 'desligamento';

-- (4) Gatilho do S-2299 (blindado)
CREATE OR REPLACE FUNCTION public.trg_desligamento_gera_s2299()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.status = 'desligado' AND NEW.data_desligamento IS NOT NULL
     AND (TG_OP = 'INSERT'
          OR OLD.status IS DISTINCT FROM 'desligado'
          OR OLD.data_desligamento IS DISTINCT FROM NEW.data_desligamento) THEN
    BEGIN
      PERFORM public.desligamento_esocial_gerar_s2299(NEW.id, 'pendente_assinatura');
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'S-2299 nao gerado para desligamento % (segue sem bloquear): %', NEW.id, SQLERRM;
    END;
  END IF;
  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS desligamento_gera_s2299 ON public.admissoes;
CREATE TRIGGER desligamento_gera_s2299
  AFTER INSERT OR UPDATE OF status, data_desligamento ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.trg_desligamento_gera_s2299();

-- (5) Backfill dos desligamentos historicos (set-based, status 'historico')
INSERT INTO public.esocial_transmissoes
  (tenant_id, empresa_id, tipo_evento, origem_modulo, origem_id, colaborador_cpf,
   competencia, data_limite, xml_enviado, status, leiaute_versao, updated_at)
SELECT a.tenant_id, a.empresa_id, 'S-2299', 'desligamento', a.id,
       regexp_replace(COALESCE(a.cpf,''), '\D', '', 'g'),
       to_char(a.data_desligamento, 'YYYY-MM'),
       (date_trunc('month', a.data_desligamento) + interval '1 month' + interval '9 days')::date,
       jsonb_build_object('evento','S-2299','cpfTrab',regexp_replace(COALESCE(a.cpf,''),'\D','','g'),
         'matricula',a.matricula_esocial,'dtDeslig',a.data_desligamento,
         'mtvDeslig',a.motivo_desligamento,'nmTrab',a.nome_completo)::text,
       'historico', 'S-1.3.0', now()
FROM public.admissoes a
WHERE a.status = 'desligado' AND a.data_desligamento IS NOT NULL
ON CONFLICT (tenant_id, origem_id, tipo_evento) WHERE origem_modulo = 'desligamento'
DO NOTHING;

-- (6) Conferencia
SELECT '1. desligamentos' AS item, count(*)::text AS valor
  FROM public.admissoes WHERE status='desligado' AND data_desligamento IS NOT NULL
UNION ALL
SELECT '2. eventos S-2299 na fila', count(*)::text
  FROM public.esocial_transmissoes WHERE tipo_evento='S-2299'
UNION ALL
SELECT '3. QA DESL-091', (SELECT situacao::text FROM public.qa_executar_descartavel('qa_caso_desl_091'))
UNION ALL
SELECT '4. QA ADM-090 (segue verde)', (SELECT situacao::text FROM public.qa_executar_descartavel('qa_caso_adm_090'))
ORDER BY item;
