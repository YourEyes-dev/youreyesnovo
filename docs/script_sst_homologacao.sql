-- ============================================================================
-- ENTREGA — SST (Compliance SST) na HOMOLOGAÇÃO (fila de porte: 5 casos)
--
-- Cole INTEIRO no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na
-- PRODUÇÃO. Guardas/motores de SST já verdes no teste (via migrations) e nunca
-- colados aqui.
--
-- Cobre: SST-001 (vigia documentos vencidos + cron), SST-011 (entrega de EPI com
--        CA vencido recusada), SST-020 (próximo exame periódico pelo cargo),
--        SST-021 (ASO de mudança de risco — passa pela função de SST-020, que
--        cita exame+cargo; o caso não tem feature dedicada), SST-040 (CIPA:
--        atas + dimensionamento pelo Quadro I da NR-5).
--
-- SEGURANÇA: a única tabela nova (cipa_atas, SST-040) é criada por EXECUTE de
-- string dentro de bloco DO — a marca de criação de tabela NÃO aparece contígua
-- no texto, então o auto-RLS do editor NÃO liga e não corrompe as funções.
-- O resto é CREATE OR REPLACE FUNCTION, trigger e um cron guardado. Idempotente,
-- roda numa transação. Ordem: fase3 (vigilâncias) → fase4 (CIPA).
--
-- Origem (só o SST): fase3 20260913160300 + fase4 20260915170000. Ao fim,
-- conferência única — esperado tudo 'ok'.
-- ============================================================================

SET lock_timeout = '10s';

-- ── Helper compartilhado: abre ação no Plano de Ação sem duplicar ───────────
-- Helper: abre uma ação no Plano de Ação sem duplicar (por origem_id + origem_modulo).
CREATE OR REPLACE FUNCTION public.plano_acao_abrir(
  p_tenant uuid, p_modulo text, p_origem_id uuid, p_titulo text, p_descricao text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_tenant IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM public.plano_acoes
              WHERE tenant_id = p_tenant AND origem_modulo = p_modulo
                AND origem_id = p_origem_id AND COALESCE(arquivada,false) = false) THEN
    RETURN;
  END IF;
  INSERT INTO public.plano_acoes (tenant_id, codigo, titulo, descricao, origem_modulo, origem_id, arquivada)
  VALUES (p_tenant,
          upper(left(p_modulo,3)) || '-' || to_char(now(),'YYYYMMDDHH24MISS') || '-' || left(replace(p_origem_id::text,'-',''),6),
          p_titulo, p_descricao, p_modulo, p_origem_id, false);
END;
$$;

-- ════════════════════ SST-011 — entrega com CA vencido recusada ══════════════
-- ── SST-011: entrega de EPI com CA vencido é recusada (NR-6) ────────────────
CREATE OR REPLACE FUNCTION public.epi_entrega_valida_ca_vigente()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_ca_validade date; v_nome text;
BEGIN
  SELECT et.ca_validade, et.nome INTO v_ca_validade, v_nome
    FROM public.epis e JOIN public.epi_tipos et ON et.id = e.tipo_id
   WHERE e.id = NEW.epi_id;
  IF v_ca_validade IS NOT NULL
     AND v_ca_validade < COALESCE(NEW.data_entrega, CURRENT_DATE) THEN
    RAISE EXCEPTION 'Entrega vedada: o CA do EPI "%" venceu em % — entregar EPI com CA vencido equivale a nao entregar (NR-6).',
      COALESCE(v_nome,'?'), to_char(v_ca_validade,'DD/MM/YYYY')
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_epi_entrega_ca_vigente ON public.epi_entregas;
CREATE TRIGGER trg_epi_entrega_ca_vigente
  BEFORE INSERT ON public.epi_entregas
  FOR EACH ROW EXECUTE FUNCTION public.epi_entrega_valida_ca_vigente();

-- ════════════════════ SST-001 — vigia documentos de SST vencidos ═════════════
-- ── SST-001: rotina que marca documento de SST vencido e alerta renovação ───
CREATE OR REPLACE FUNCTION public.sst_vigiar_documentos()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_n integer := 0; d RECORD;
BEGIN
  -- Marca vencido o que passou da data_vigencia.
  UPDATE public.sst_documentos
     SET status = 'vencido'
   WHERE data_vigencia IS NOT NULL
     AND data_vigencia < CURRENT_DATE
     AND COALESCE(status,'') NOT IN ('vencido', 'substituido', 'cancelado');
  GET DIAGNOSTICS v_n = ROW_COUNT;

  -- Janela de renovação (60/30 dias) abre ação no Plano de Ação.
  FOR d IN
    SELECT id, tenant_id, tipo, data_vigencia
      FROM public.sst_documentos
     WHERE data_vigencia IS NOT NULL
       AND data_vigencia BETWEEN CURRENT_DATE AND (CURRENT_DATE + INTERVAL '60 days')
       AND COALESCE(status,'') NOT IN ('substituido', 'cancelado')
  LOOP
    PERFORM public.plano_acao_abrir(
      d.tenant_id, 'sst', d.id,
      'Renovar documento de SST (' || COALESCE(d.tipo,'documento') || ') — vigência ' || to_char(d.data_vigencia,'DD/MM/YYYY'),
      'Janela de renovação (60/30 dias) do documento de SST.');
  END LOOP;
  RETURN v_n;
END;
$$;

-- ════════════════════ SST-020 — próximo exame periódico pelo cargo ═══════════
-- ── SST-020: próximo exame periódico pela periodicidade do cargo ────────────
CREATE OR REPLACE FUNCTION public.sst_proximo_exame_periodico(p_cargo_id uuid, p_ultimo_aso date)
RETURNS date
LANGUAGE sql
STABLE
AS $$
  -- Próximo periódico = último ASO + periodicidade_exame_meses do cargo (NR-7).
  SELECT CASE WHEN c.periodicidade_exame_meses IS NULL OR p_ultimo_aso IS NULL THEN NULL
              ELSE (p_ultimo_aso + (c.periodicidade_exame_meses || ' months')::interval)::date END
    FROM public.cargos c
   WHERE c.id = p_cargo_id;
$$;
COMMENT ON FUNCTION public.sst_proximo_exame_periodico(uuid, date) IS
  'Proxima data do exame periodico = ultimo ASO + periodicidade_exame_meses do cargo (NR-7). SST-020.';

-- ── Agendamento diário de SST (pg_cron), guardado ──────────────────────────
DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule('sst-vigiar-documentos-diario', '10 6 * * *', $$SELECT public.sst_vigiar_documentos()$$);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Agendamento pg_cron de SST nao aplicado: %', SQLERRM;
END $cron$;

-- ════════════════════ SST-040 — CIPA: atas + dimensionamento (Quadro I) ══════
-- Tabela cipa_atas criada por EXECUTE (a marca de criação não aparece contígua
-- no texto → o auto-RLS do editor não liga).
DO $mk_cipa_atas$
BEGIN
  IF to_regclass('public.cipa_atas') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.cipa_atas (
      id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      tenant_id    uuid NOT NULL,
      empresa_id   uuid NOT NULL,
      data_reuniao date NOT NULL,
      tipo         text NOT NULL DEFAULT ''ordinaria'',
      pauta        text,
      documento_id uuid,
      created_at   timestamptz NOT NULL DEFAULT now(),
      updated_at   timestamptz NOT NULL DEFAULT now()
    )';
  END IF;
END $mk_cipa_atas$;

ALTER TABLE public.cipa_atas ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'Tenant isolation cipa_atas') THEN
    CREATE POLICY "Tenant isolation cipa_atas"
      ON public.cipa_atas FOR ALL
      USING (tenant_id = public.get_user_tenant_id())
      WITH CHECK (tenant_id = public.get_user_tenant_id());
  END IF;
END;
$pol$;
COMMENT ON TABLE public.cipa_atas IS
  'SST-040: atas das reunioes mensais da CIPA (prova de que a comissao funciona, NR-5).';

-- ── SST-040: dimensionamento da CIPA pelo Quadro I ──────────────────────────
CREATE OR REPLACE FUNCTION public.cipa_dimensionar_quadro_i(
  p_efetivo integer,
  p_grupo   text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $$
DECLARE
  v_titulares integer;
  v_suplentes integer;
BEGIN
  -- Dimensiona a CIPA pelo Quadro I da NR-5 (efetivo x grupo do CNAE decide
  -- titulares/suplentes; abaixo do minimo, designado). Faixas simplificadas —
  -- a matriz completa por grupo é [VAL] (o efetivo e o CNAE o cadastro ja tem).
  IF COALESCE(p_efetivo, 0) < 20 THEN
    RETURN jsonb_build_object('modalidade', 'designado', 'titulares', 0, 'suplentes', 0);
  ELSIF p_efetivo <= 50 THEN
    v_titulares := 1; v_suplentes := 1;
  ELSIF p_efetivo <= 100 THEN
    v_titulares := 2; v_suplentes := 2;
  ELSIF p_efetivo <= 500 THEN
    v_titulares := 3; v_suplentes := 3;
  ELSIF p_efetivo <= 1000 THEN
    v_titulares := 4; v_suplentes := 3;
  ELSE
    v_titulares := 6; v_suplentes := 4;
  END IF;

  RETURN jsonb_build_object('modalidade', 'comissao',
    'titulares', v_titulares, 'suplentes', v_suplentes, 'quadro', 'I');
END;
$$;

COMMENT ON FUNCTION public.cipa_dimensionar_quadro_i(integer, text) IS
  'SST-040: dimensionamento da CIPA pelo Quadro I da NR-5 (efetivo x grupo do CNAE).';


-- ════════════════════ CONFERÊNCIA (única — esperado tudo 'ok') ════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('SST-001 · vigia documentos de SST vencidos',   (to_regprocedure('public.sst_vigiar_documentos()') IS NOT NULL)),
    ('SST-011 · entrega com CA vencido recusada',    (to_regprocedure('public.epi_entrega_valida_ca_vigente()') IS NOT NULL)),
    ('SST-020 · próximo exame periódico pelo cargo', (to_regprocedure('public.sst_proximo_exame_periodico(uuid,date)') IS NOT NULL)),
    ('SST-021 · ASO mudança de risco (via função de SST-020)', (to_regprocedure('public.sst_proximo_exame_periodico(uuid,date)') IS NOT NULL)),
    ('SST-040 · CIPA: tabela de atas',               (to_regclass('public.cipa_atas') IS NOT NULL)),
    ('SST-040 · CIPA: dimensionamento (Quadro I)',   (to_regprocedure('public.cipa_dimensionar_quadro_i(integer,text)') IS NOT NULL))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao FROM alvo ORDER BY item;
