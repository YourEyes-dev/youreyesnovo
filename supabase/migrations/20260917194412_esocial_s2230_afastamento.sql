-- ============================================================================
-- eSocial S-2230 (afastamento) — prazo + gerador + gatilho + backfill historico.
--
-- Achado AFAST-060: a inteligencia cria a pendencia de S-2230, mas (1) a
-- pendencia nao tem data-limite e (2) ninguem gera o evento para a fila.
-- Prazo do S-2230 (regra pratica): 16o dia do afastamento na doenca > 15 dias;
-- senao, dia 15 do mes seguinte ao inicio. Mesmo molde do S-2200/S-2299:
-- gatilho blindado, historicos entram como 'historico' (nao transmitem).
-- ============================================================================

-- Colunas de esocial_transmissoes (drift) — no-op onde ja existem
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS empresa_id uuid;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS origem_modulo text;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS origem_id uuid;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS colaborador_cpf text;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS competencia text;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS data_limite date;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS leiaute_versao text;

-- Prazo do S-2230 por duracao (funcao pura) ----------------------------------
CREATE OR REPLACE FUNCTION public.afastamento_s2230_prazo(p_inicio date, p_dias int)
RETURNS date LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE
    WHEN p_inicio IS NULL THEN NULL
    -- doenca > 15 dias: S-2230 ate o 16o dia do afastamento
    WHEN COALESCE(p_dias, 999) > 15 THEN p_inicio + 15
    -- regra geral: dia 15 do mes seguinte ao inicio
    ELSE (date_trunc('month', p_inicio) + interval '1 month' + interval '14 days')::date
  END;
$fn$;

-- 1) Preenche o PRAZO na pendencia de S-2230 (ADM-060: prazo) -----------------
CREATE OR REPLACE FUNCTION public.afastamento_pendencia_prazo(p_afastamento uuid)
RETURNS date
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE a RECORD; v_prazo date;
BEGIN
  SELECT * INTO a FROM public.afastamentos WHERE id = p_afastamento;
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_prazo := public.afastamento_s2230_prazo(a.data_inicio,
               COALESCE(a.dias_totais, (a.data_fim - a.data_inicio) + 1));
  -- Grava a data-limite nas pendencias de S-2230 deste afastamento que estao sem prazo.
  UPDATE public.afastamentos_pendencias
     SET prazo = v_prazo, updated_at = now()
   WHERE afastamento_id = p_afastamento AND prazo IS NULL
     AND (tipo_pendencia ILIKE '%2230%' OR tipo_pendencia ILIKE '%esocial%'
          OR descricao ILIKE '%2230%' OR descricao ILIKE '%eSocial%');
  RETURN v_prazo;
END $fn$;

-- 2) Gera o S-2230 na fila (AFAST-060: geracao) ------------------------------
CREATE OR REPLACE FUNCTION public.afastamento_esocial_gerar_s2230(
  p_afastamento uuid, p_status text DEFAULT 'pendente_assinatura')
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE a RECORD; v_cpf text; v_payload jsonb; v_limite date;
BEGIN
  SELECT * INTO a FROM public.afastamentos WHERE id = p_afastamento;
  IF NOT FOUND OR a.data_inicio IS NULL THEN RETURN 0; END IF;
  v_cpf := regexp_replace(COALESCE(a.colaborador_cpf,''), '\D', '', 'g');
  v_limite := public.afastamento_s2230_prazo(a.data_inicio,
                COALESCE(a.dias_totais, (a.data_fim - a.data_inicio) + 1));
  v_payload := jsonb_build_object(
    'evento','S-2230','cpfTrab',v_cpf,'nmTrab',a.colaborador_nome,
    'dtIniAfast',a.data_inicio,'dtTermAfast',a.data_fim,
    'codMotAfast',a.motivo_principal::text);
  -- eSocial S-2230 vai para esocial_transmissoes
  INSERT INTO public.esocial_transmissoes
    (tenant_id, empresa_id, tipo_evento, origem_modulo, origem_id, colaborador_cpf,
     competencia, data_limite, xml_enviado, status, leiaute_versao, updated_at)
  VALUES
    (a.tenant_id, a.empresa_id, 'S-2230', 'afastamento', a.id, v_cpf,
     to_char(a.data_inicio, 'YYYY-MM'), v_limite, v_payload::text, p_status, 'S-1.3.0', now())
  ON CONFLICT (tenant_id, origem_id, tipo_evento) WHERE origem_modulo = 'afastamento'
  DO UPDATE SET
     xml_enviado = EXCLUDED.xml_enviado, data_limite = EXCLUDED.data_limite,
     status = CASE WHEN public.esocial_transmissoes.status IN ('processado','enviado')
                   THEN public.esocial_transmissoes.status ELSE EXCLUDED.status END,
     updated_at = now();
  RETURN 1;
END $fn$;

-- 3) Idempotencia
CREATE UNIQUE INDEX IF NOT EXISTS uq_esocial_s2230_afastamento
  ON public.esocial_transmissoes (tenant_id, origem_id, tipo_evento)
  WHERE origem_modulo = 'afastamento';

-- 4) Gatilho (blindado): afastamento >= 16 dias ou indeterminado gera S-2230 --
CREATE OR REPLACE FUNCTION public.trg_afastamento_gera_s2230()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.data_inicio IS NOT NULL
     AND (COALESCE(NEW.dias_totais, (NEW.data_fim - NEW.data_inicio) + 1, 999) >= 16
          OR NEW.prazo_indeterminado IS TRUE) THEN
    BEGIN
      PERFORM public.afastamento_esocial_gerar_s2230(NEW.id, 'pendente_assinatura');
      PERFORM public.afastamento_pendencia_prazo(NEW.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'S-2230 nao gerado para afastamento % (segue sem bloquear): %', NEW.id, SQLERRM;
    END;
  END IF;
  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS afastamento_gera_s2230 ON public.afastamentos;
CREATE TRIGGER afastamento_gera_s2230
  AFTER INSERT OR UPDATE OF data_inicio, data_fim, dias_totais, prazo_indeterminado, status
  ON public.afastamentos
  FOR EACH ROW EXECUTE FUNCTION public.trg_afastamento_gera_s2230();

-- 5) Backfill dos afastamentos historicos (status 'historico') ----------------
DO $bf$
DECLARE v_n int := 0; r RECORD;
BEGIN
  FOR r IN SELECT id FROM public.afastamentos a
             WHERE a.data_inicio IS NOT NULL
               AND (COALESCE(a.dias_totais, (a.data_fim - a.data_inicio) + 1, 999) >= 16
                    OR a.prazo_indeterminado IS TRUE)
               AND NOT EXISTS (SELECT 1 FROM public.esocial_transmissoes e
                                WHERE e.origem_modulo='afastamento' AND e.origem_id = a.id
                                  AND e.tipo_evento='S-2230')
  LOOP
    PERFORM public.afastamento_esocial_gerar_s2230(r.id, 'historico');
    PERFORM public.afastamento_pendencia_prazo(r.id);
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE 'eSocial S-2230: % afastamento(s) historico(s) enfileirado(s) como nao-transmitir.', v_n;
END $bf$;
