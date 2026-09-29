-- ============================================================================
-- ENTREGA — FIX PONTO-402 (erro no motor): qa_feriado_da_unidade idempotente
--
-- Cole no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na PRODUÇÃO.
-- Equivalente à migration 20260929183009_fix_qa_feriado_da_unidade_idempotente_fer003.sql
--
-- PROBLEMA: o FER-003 criou uq_feriado_tabela_empresa_por_unidade UNIQUE
-- (tenant_id, empresa_id) — uma tabela de feriados por unidade. O helper de QA
-- qa_feriado_da_unidade criava tabela nova e revinculava a MESMA unidade a cada
-- chamada; na 2a rodada da bateria isso estoura o unique e o caso PONTO-402 vira
-- 'erro' (duplicate key value violates ...uq_feriado_tabela_empresa_por_unidade).
-- É efeito colateral do próprio FER-003 sobre o arnês de teste.
--
-- CORREÇÃO: o helper passa a REAPROVEITAR a tabela já vinculada à unidade e só
-- garante o item do feriado na data pedida. Idempotente (testado em réplica:
-- 3 chamadas iguais = 1 vínculo/1 tabela/1 item; data nova reaproveita a tabela).
--
-- SEGURANÇA: só CREATE OR REPLACE de FUNÇÃO — não cria tabela (não aciona o
-- auto-RLS do editor), não altera dado de produção. Mexe apenas em como o QA
-- monta o feriado no cercado (tenant qa-sandbox).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.qa_feriado_da_unidade(
  p_empresa_id uuid, p_data date, p_nome text DEFAULT '[QA] Feriado de Teste'
)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_t uuid := public.qa_sandbox_tenant_id(); v_tab uuid;
BEGIN
  SELECT fte.tabela_id INTO v_tab
    FROM public.feriado_tabela_empresas fte
   WHERE fte.tenant_id = v_t AND fte.empresa_id = p_empresa_id
   LIMIT 1;

  IF v_tab IS NULL THEN
    INSERT INTO public.feriado_tabelas (tenant_id, nome, uf, municipio, ano, ativo)
    VALUES (v_t, p_nome || ' ' || p_data, 'SP', 'São Paulo', EXTRACT(YEAR FROM p_data)::int, true)
    RETURNING id INTO v_tab;
    INSERT INTO public.feriado_tabela_empresas (tenant_id, tabela_id, empresa_id)
    VALUES (v_t, v_tab, p_empresa_id)
    ON CONFLICT (tenant_id, empresa_id) DO NOTHING;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.feriado_tabela_itens
     WHERE tenant_id = v_t AND tabela_id = v_tab AND data = p_data
  ) THEN
    INSERT INTO public.feriado_tabela_itens
      (tenant_id, tabela_id, nome, data, recorrente, tipo, ativo)
    VALUES (v_t, v_tab, p_nome, p_data, false, 'feriado', true);
  END IF;

  RETURN v_tab;
END $fn$;

-- ════════════════════ CONFERÊNCIA (única — esperado 'ok') ═════════════════════
SELECT
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='qa_feriado_da_unidade'
  ) THEN 'ok — helper atualizado' ELSE 'CONFERIR — helper ausente' END AS situacao;
