-- ============================================================================
-- Fase 4 (motores) — EPI: ciclo físico e prova de entrega.
--
-- EPI-021: FEFO — sugestão de saída pelo lote que vence primeiro.
-- EPI-040: trava na entrega de item VENCIDO (item vencido não é entregável).
-- EPI-042: lacre de integridade (hash) da ficha assinada (Lei 14.063/2020).
-- EPI-044: arquivamento da ficha assinada no módulo Documentos, na pasta do
--          colaborador, ao gravar signed_at.
-- EPI-051: kit inicial de EPI da admissão em função de risco (pendências).
--
-- Adiados honestamente:
--   EPI-010 (consulta oficial CAEPI no cadastro do CA) exige uma edge function
--     com a base pública do CAEPI — integração externa, não cabe numa migration.
--   EPI-043 (reserva antes da assinatura, baixa só com signed_at) CONFLITA com
--     o EPI-001, que hoje está verde e exige o oposto: a entrega registrada
--     (status 'ativa', sem assinatura) baixa o estoque na hora. Os dois inserts
--     são idênticos (status 'ativa', signed_at nulo), então não há sinal para
--     separar os dois comportamentos — atender o EPI-043 quebraria o EPI-001.
--     É uma decisão de produto (qual é o comportamento canônico) que precisa
--     rever o contrato do EPI-001 junto. Fica registrado, sem gambiarra.
-- ============================================================================

-- ── EPI-040: trava de entrega de item vencido ───────────────────────────────
CREATE OR REPLACE FUNCTION public.epi_entrega_bloqueia_vencido()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_validade date;
BEGIN
  SELECT e.data_validade INTO v_validade
    FROM public.epis e
   WHERE e.id = NEW.epi_id;

  IF v_validade IS NOT NULL AND v_validade < NEW.data_entrega THEN
    RAISE EXCEPTION
      'EPI vencido em % nao pode ser entregue (data da entrega %): item vencido fica segregado, fora do saldo entregavel (NR-6).',
      to_char(v_validade, 'DD/MM/YYYY'), to_char(NEW.data_entrega, 'DD/MM/YYYY')
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_epi_entrega_bloqueia_vencido ON public.epi_entregas;
CREATE TRIGGER trg_epi_entrega_bloqueia_vencido
  BEFORE INSERT ON public.epi_entregas
  FOR EACH ROW EXECUTE FUNCTION public.epi_entrega_bloqueia_vencido();

-- ── EPI-021: FEFO — sugestão do lote que vence primeiro ─────────────────────
-- Devolve os lotes com saldo do tipo pedido, ordenados pela validade mais
-- próxima (o que vence primeiro sai primeiro), respeitando tamanho e local
-- quando informados. Vencidos ficam de fora (casa com o EPI-040).
CREATE OR REPLACE FUNCTION public.epi_sugerir_lote_fefo(
  p_tenant   uuid,
  p_tipo_id  uuid,
  p_tamanho  text DEFAULT NULL,
  p_local    text DEFAULT NULL
) RETURNS TABLE (epi_id uuid, codigo text, data_validade date, quantidade_estoque integer)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $$
  SELECT e.id, e.codigo, e.data_validade, e.quantidade_estoque
    FROM public.epis e
   WHERE e.tenant_id = p_tenant
     AND e.tipo_id   = p_tipo_id
     AND COALESCE(e.quantidade_estoque, 0) > 0
     AND (e.data_validade IS NULL OR e.data_validade >= CURRENT_DATE)
     AND (p_tamanho IS NULL OR e.tamanho IS NOT DISTINCT FROM p_tamanho)
     AND (p_local   IS NULL OR e.localizacao IS NOT DISTINCT FROM p_local)
   ORDER BY e.data_validade ASC NULLS LAST, e.codigo;
$$;

COMMENT ON FUNCTION public.epi_sugerir_lote_fefo(uuid, uuid, text, text) IS
  'EPI-021: sugere o lote de EPI pela validade mais proxima (FEFO), por tipo x tamanho x local.';

-- ── EPI-042: lacre de integridade (hash) da ficha assinada ──────────────────
ALTER TABLE public.epi_entregas
  ADD COLUMN IF NOT EXISTS assinatura_hash text;

COMMENT ON COLUMN public.epi_entregas.assinatura_hash IS
  'EPI-042: hash SHA-256 do recibo no ato da assinatura — detecta modificacao posterior (Lei 14.063/2020, art. 4, II).';

CREATE OR REPLACE FUNCTION public.epi_entrega_sela_integridade()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  -- No momento em que a entrega é assinada, grava o hash que lacra o recibo.
  IF NEW.signed_at IS NOT NULL AND OLD.signed_at IS NULL
     AND NEW.assinatura_hash IS NULL THEN
    NEW.assinatura_hash := encode(
      public.digest(
        COALESCE(NEW.assinatura_url, '') || '|' ||
        COALESCE(NEW.recebido_por_assinatura, '') || '|' ||
        NEW.signed_at::text || '|' || NEW.id::text,
        'sha256'),
      'hex');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_epi_entrega_sela_integridade ON public.epi_entregas;
CREATE TRIGGER trg_epi_entrega_sela_integridade
  BEFORE UPDATE OF signed_at ON public.epi_entregas
  FOR EACH ROW EXECUTE FUNCTION public.epi_entrega_sela_integridade();

-- ── EPI-044: arquiva a ficha assinada no módulo Documentos ──────────────────
-- Ao gravar signed_at, registra o recibo em documentos (pasta do colaborador),
-- com tipo e vínculo à entrega. Defensivo: nunca bloqueia a assinatura.
CREATE OR REPLACE FUNCTION public.epi_entrega_arquivar_documento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Ponte epi_entregas -> documentos: leva a ficha assinada para a pasta do
  -- colaborador no modulo Documentos, com vinculo a entrega.
  IF NEW.signed_at IS NOT NULL AND OLD.signed_at IS NULL
     AND COALESCE(NEW.assinatura_url, '') <> '' THEN
    BEGIN
      INSERT INTO public.documentos
        (tenant_id, colaborador_nome, colaborador_cpf, nome_arquivo, nome_original,
         tipo, tamanho, mime_type, storage_path, status, classificacao, observacoes)
      SELECT NEW.tenant_id, NEW.colaborador_nome, NEW.colaborador_cpf,
             'ficha-epi-' || NEW.id::text || '.pdf',
             'Ficha de entrega de EPI',
             'ficha_epi', 0, 'application/pdf', NEW.assinatura_url,
             'ativo', 'documento_epi',
             'Recibo de entrega de EPI ' || NEW.id::text
      WHERE NOT EXISTS (
        SELECT 1 FROM public.documentos d
         WHERE d.tenant_id = NEW.tenant_id
           AND d.storage_path = NEW.assinatura_url
           AND d.tipo = 'ficha_epi'
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Arquivamento da ficha de EPI % pulado: %', NEW.id, SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_epi_entrega_arquivar_documento ON public.epi_entregas;
CREATE TRIGGER trg_epi_entrega_arquivar_documento
  AFTER UPDATE OF signed_at ON public.epi_entregas
  FOR EACH ROW EXECUTE FUNCTION public.epi_entrega_arquivar_documento();

-- ── EPI-051: kit inicial de EPI da admissão em função de risco ──────────────
-- Lista os EPIs exigidos pela função do admitido (epi_tipos.obrigatorio_para_
-- funcoes) que ainda não têm entrega assinada — a pendência do kit inicial que
-- o painel de onboarding acompanha até a última ficha (NR-6 c/c NR-1).
CREATE OR REPLACE FUNCTION public.epi_kit_admissao_pendencias(p_admissao_id uuid)
RETURNS TABLE (epi_tipo_id uuid, epi_nome text, ja_entregue boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_tenant uuid;
  v_cargo  text;
  v_cpf    text;
BEGIN
  SELECT a.tenant_id, a.cargo, a.cpf
    INTO v_tenant, v_cargo, v_cpf
    FROM public.admissoes a
   WHERE a.id = p_admissao_id;

  IF v_cargo IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
    SELECT et.id, et.nome,
           EXISTS (
             SELECT 1 FROM public.epi_entregas ee
              JOIN public.epis e ON e.id = ee.epi_id
             WHERE ee.tenant_id = v_tenant
               AND e.tipo_id = et.id
               AND regexp_replace(COALESCE(ee.colaborador_cpf,''), '[^0-9]', '', 'g')
                 = regexp_replace(COALESCE(v_cpf,''), '[^0-9]', '', 'g')
               AND ee.signed_at IS NOT NULL
           ) AS ja_entregue
      FROM public.epi_tipos et
     WHERE et.tenant_id = v_tenant
       AND et.obrigatorio_para_funcoes IS NOT NULL
       AND v_cargo = ANY (et.obrigatorio_para_funcoes);
END;
$$;

COMMENT ON FUNCTION public.epi_kit_admissao_pendencias(uuid) IS
  'EPI-051: EPIs exigidos pela funcao do admitido (obrigatorio_para_funcoes) e o que falta entregar.';
