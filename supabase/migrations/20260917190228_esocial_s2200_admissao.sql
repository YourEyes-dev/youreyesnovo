-- ============================================================================
-- eSocial S-2200 (admissao) — gerador + gatilho + backfill historico.
--
-- Achado ADM-090: a admissao concluida NAO gera evento S-2200 (fila
-- esocial_transmissoes vazia). O MOS exige o S-2200 ate o dia ANTERIOR ao inicio
-- das atividades. Espelha o padrao de ferias_esocial_gerar.
--
-- IMPORTANTE (compliance): a admissao existente (historica) e enfileirada com
-- status 'historico' — NAO entra na esteira de transmissao (que so processa
-- 'pendente_assinatura'). Assim o ADM-090 conta o evento sem arriscar transmitir
-- em massa admissoes antigas ao governo. Admissoes NOVAS (via gatilho) nascem
-- 'pendente_assinatura' para o fluxo normal de assinatura/envio.
-- ============================================================================

-- 1) Idempotencia: um S-2200 por admissao ---------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_esocial_s2200_admissao
  ON public.esocial_transmissoes (tenant_id, origem_id, tipo_evento)
  WHERE origem_modulo = 'admissao';

-- 2) Gerador --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admissao_esocial_gerar_s2200(
  p_admissao uuid, p_status text DEFAULT 'pendente_assinatura')
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE a RECORD; v_cpf text; v_payload jsonb; v_limite date;
BEGIN
  SELECT * INTO a FROM public.admissoes WHERE id = p_admissao AND status = 'concluido';
  IF NOT FOUND THEN RETURN 0; END IF;

  v_cpf := regexp_replace(COALESCE(a.cpf,''), '\D', '', 'g');
  -- MOS: envio ate o dia imediatamente anterior ao inicio das atividades.
  v_limite := COALESCE(a.data_admissao, CURRENT_DATE) - 1;
  v_payload := jsonb_build_object(
    'evento','S-2200','cpfTrab',v_cpf,'nmTrab',a.nome_completo,
    'dtNascto',a.data_nascimento,'dtAdm',a.data_admissao,
    'codCargo',a.cargo,'matricula',a.matricula_esocial,'CBO',a.cbo,
    'tpRegTrab',1,'tpRegPrev',1);

  INSERT INTO public.esocial_transmissoes
    (tenant_id, empresa_id, tipo_evento, origem_modulo, origem_id, colaborador_cpf,
     competencia, data_limite, xml_enviado, status, leiaute_versao, updated_at)
  VALUES
    (a.tenant_id, a.empresa_id, 'S-2200', 'admissao', a.id, v_cpf,
     to_char(COALESCE(a.data_admissao, CURRENT_DATE), 'YYYY-MM'), v_limite,
     v_payload::text, p_status, 'S-1.3.0', now())
  ON CONFLICT (tenant_id, origem_id, tipo_evento) WHERE origem_modulo = 'admissao'
  DO UPDATE SET
     xml_enviado = EXCLUDED.xml_enviado,
     data_limite = EXCLUDED.data_limite,
     -- nunca reabre evento ja enviado/processado
     status = CASE WHEN public.esocial_transmissoes.status IN ('processado','enviado')
                   THEN public.esocial_transmissoes.status ELSE EXCLUDED.status END,
     updated_at = now();
  RETURN 1;
END $fn$;

-- 3) Gatilho: admissao que conclui gera o S-2200 (fluxo normal) -----------
CREATE OR REPLACE FUNCTION public.trg_admissao_gera_s2200()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.status = 'concluido'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'concluido') THEN
    PERFORM public.admissao_esocial_gerar_s2200(NEW.id, 'pendente_assinatura');
  END IF;
  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS admissao_gera_s2200 ON public.admissoes;
CREATE TRIGGER admissao_gera_s2200
  AFTER INSERT OR UPDATE OF status ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.trg_admissao_gera_s2200();

-- 4) Backfill das admissoes historicas (status 'historico' — nao transmite) --
-- Em banco novo/staging isso pega as poucas admissoes existentes; em producao
-- o script de entrega faz o mesmo, em lotes. Idempotente pelo indice.
DO $bf$
DECLARE v_n int := 0; r RECORD;
BEGIN
  FOR r IN SELECT id FROM public.admissoes WHERE status = 'concluido'
             AND NOT EXISTS (SELECT 1 FROM public.esocial_transmissoes e
                              WHERE e.origem_modulo='admissao' AND e.origem_id = admissoes.id
                                AND e.tipo_evento='S-2200')
  LOOP
    PERFORM public.admissao_esocial_gerar_s2200(r.id, 'historico');
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE 'eSocial S-2200: % admissao(oes) historica(s) enfileirada(s) como nao-transmitir.', v_n;
END $bf$;
