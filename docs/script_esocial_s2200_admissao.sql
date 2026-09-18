-- ============================================================================
-- eSocial S-2200 (admissao) — ENTREGA para a producao.
-- Gerador + indice de idempotencia + gatilho + backfill das admissoes historicas.
--
-- DECISAO DE COMPLIANCE (confirme antes de rodar em producao):
--   As admissoes JA existentes (concluidas) sao enfileiradas com status
--   'historico' — elas CONTAM para o controle, mas NAO entram na esteira de
--   transmissao (que so processa 'pendente_assinatura'). Assim o sistema nao
--   tenta transmitir ao governo, em massa, admissoes antigas (que ja foram
--   declaradas por outro meio ou sao anteriores ao uso do sistema).
--   Admissoes NOVAS (a partir de agora, via gatilho) nascem
--   'pendente_assinatura' e seguem o fluxo normal de assinatura/envio.
--
-- Nao altera dado existente (so INSERE eventos novos) — sem backup necessario.
-- DDL cria gatilho em admissoes (tabela movimentada): lock_timeout curto,
-- aplicar com o ambiente tranquilo. Idempotente (indice + ON CONFLICT).
-- ============================================================================

SET lock_timeout = '10s';

-- 0) Colunas que o dev tem e a producao/homologacao podem nao ter (drift) ----
--    ADD IF NOT EXISTS e no-op onde ja existem; nullable, sem default (rapido).
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS empresa_id uuid;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS origem_modulo text;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS origem_id uuid;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS colaborador_cpf text;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS competencia text;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS data_limite date;
ALTER TABLE public.esocial_transmissoes ADD COLUMN IF NOT EXISTS leiaute_versao text;

-- 1) Idempotencia
CREATE UNIQUE INDEX IF NOT EXISTS uq_esocial_s2200_admissao
  ON public.esocial_transmissoes (tenant_id, origem_id, tipo_evento)
  WHERE origem_modulo = 'admissao';

-- 2) Gerador
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
     xml_enviado = EXCLUDED.xml_enviado, data_limite = EXCLUDED.data_limite,
     status = CASE WHEN public.esocial_transmissoes.status IN ('processado','enviado')
                   THEN public.esocial_transmissoes.status ELSE EXCLUDED.status END,
     updated_at = now();
  RETURN 1;
END $fn$;

-- 3) Gatilho (fluxo normal das NOVAS admissoes)
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

-- 4) Backfill das historicas (set-based, status 'historico' = NAO transmite) --
INSERT INTO public.esocial_transmissoes
  (tenant_id, empresa_id, tipo_evento, origem_modulo, origem_id, colaborador_cpf,
   competencia, data_limite, xml_enviado, status, leiaute_versao, updated_at)
SELECT a.tenant_id, a.empresa_id, 'S-2200', 'admissao', a.id,
       regexp_replace(COALESCE(a.cpf,''), '\D', '', 'g'),
       to_char(COALESCE(a.data_admissao, CURRENT_DATE), 'YYYY-MM'),
       COALESCE(a.data_admissao, CURRENT_DATE) - 1,
       jsonb_build_object('evento','S-2200','cpfTrab',regexp_replace(COALESCE(a.cpf,''),'\D','','g'),
         'nmTrab',a.nome_completo,'dtNascto',a.data_nascimento,'dtAdm',a.data_admissao,
         'codCargo',a.cargo,'matricula',a.matricula_esocial,'CBO',a.cbo,
         'tpRegTrab',1,'tpRegPrev',1)::text,
       'historico', 'S-1.3.0', now()
FROM public.admissoes a
WHERE a.status = 'concluido'
ON CONFLICT (tenant_id, origem_id, tipo_evento) WHERE origem_modulo = 'admissao'
DO NOTHING;

-- 5) Conferencia
SELECT '1. admissoes concluidas' AS item, count(*)::text AS valor FROM public.admissoes WHERE status='concluido'
UNION ALL
SELECT '2. eventos S-2200 na fila (total)', count(*)::text FROM public.esocial_transmissoes WHERE tipo_evento='S-2200'
UNION ALL
SELECT '3. dos quais historicos (nao transmitem)', count(*)::text FROM public.esocial_transmissoes WHERE tipo_evento='S-2200' AND status='historico'
UNION ALL
SELECT '4. QA ADM-090', (SELECT situacao::text FROM public.qa_executar_descartavel('qa_caso_adm_090'))
ORDER BY item;
