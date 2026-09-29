-- ============================================================================
-- FIX PONTO-402 (erro) — qa_feriado_da_unidade idempotente sob o UNIQUE do FER-003
--
-- O FER-003 criou uq_feriado_tabela_empresa_por_unidade UNIQUE (tenant_id,
-- empresa_id): uma tabela de feriados por unidade. O helper de QA
-- qa_feriado_da_unidade (usado por PONTO-402 e pelas rotinas de férias) criava,
-- a CADA chamada, uma tabela de feriados nova e revinculava a MESMA unidade — o
-- que passava antes do UNIQUE, mas agora estoura o unique na 2a rodada da
-- bateria e o PONTO-402 vira 'erro' (duplicate key ...uq_feriado_tabela_empresa_por_unidade).
--
-- Correção: o helper passa a REAPROVEITAR a tabela já vinculada à unidade e só
-- garante o item do feriado na data pedida. Idempotente: rodar a bateria N vezes
-- não duplica vínculo nem estoura o unique. Só CREATE OR REPLACE de função —
-- não cria tabela, não altera dado de produção.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.qa_feriado_da_unidade(
  p_empresa_id uuid, p_data date, p_nome text DEFAULT '[QA] Feriado de Teste'
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_t uuid := public.qa_sandbox_tenant_id(); v_tab uuid;
BEGIN
  -- Reaproveita a tabela de feriados já vinculada à unidade (uma por unidade).
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

  -- Garante o item do feriado na data pedida (idempotente).
  IF NOT EXISTS (
    SELECT 1 FROM public.feriado_tabela_itens
     WHERE tenant_id = v_t AND tabela_id = v_tab AND data = p_data
  ) THEN
    INSERT INTO public.feriado_tabela_itens
      (tenant_id, tabela_id, nome, data, recorrente, tipo, ativo)
    VALUES (v_t, v_tab, p_nome, p_data, false, 'feriado', true);
  END IF;

  RETURN v_tab;
END $$;
