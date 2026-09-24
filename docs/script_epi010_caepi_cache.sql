-- ============================================================================
-- ENTREGA — EPI-010: cache da base oficial CAEPI e conferencia do CA
--
-- Espelha a parte EPI-010 da migration 20260915233000_fase4_epi010_caepi_
-- ferias015_audit.sql (fonte da verdade, ja no teste), ausente em homologacao
-- e producao (passivo medido em 09/2026 pelo inventario).
--
-- O QUE ENTREGA:
--   * tabela public.caepi_cache — cache local da base oficial CAEPI (numero do
--     CA, equipamento, fabricante, validade, situacao), populada por edge
--     function; base da conferencia do CA cadastrado nos EPIs;
--   * funcao public.epi_ca_conferir_caepi(text) — confere o CA informado contra
--     o cache; sem registro, devolve "nao_confirmado".
--
-- NAO entra aqui a correcao do caso de QA FERIAS-015 (que esta na mesma
-- migration): o inventario mostra qa_caso_ferias_015 JA identico em homolog e
-- producao — nao ha o que entregar.
--
-- RLS: caepi_cache NAO tem RLS/politica, de proposito e igual ao teste — e cache
-- de base PUBLICA (CAEPI, base do governo de EPI aprovados), sem dado pessoal. A
-- tela nao le a tabela direto; o acesso e pela funcao (SECURITY DEFINER) e pela
-- edge function que popula. SE o editor do Supabase oferecer "habilitar RLS"
-- nesta tabela, pode RECUSAR — habilitar sem politica so fecharia o cache sem
-- ganho, e divergiria do teste. Ainda que habilite por engano, nao quebra nada
-- (o acesso e pela funcao definer, que ignora RLS).
--
-- SEGURANCA: entrega ADITIVA e de CRIACAO pura (tabela + funcao AUSENTES
-- embaixo — conferido, nada a sobrescrever). Nao altera nem apaga dado. Sem
-- backup. Idempotente. Roda inteiro em UMA transacao. DDL pura no topo, o bloco
-- com aspas-dolar (a funcao) depois — para o editor nao se perder na contagem.
--
-- CONFERENCIA: rode a query do fim como uma query SEPARADA. Esperado: t | t | OK
-- ============================================================================

SET lock_timeout = '10s';

-- ── EPI-010: cache CAEPI (DDL pura) ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.caepi_cache (
  ca_numero       text PRIMARY KEY,
  equipamento     text,
  fabricante      text,
  cnpj_fabricante text,
  validade        date,
  situacao        text,
  bruto           jsonb,
  atualizado_em   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.caepi_cache IS
  'EPI-010: cache local da base oficial CAEPI (populado por edge function); base da conferencia do CA.';

-- ── EPI-010: funcao de conferencia (bloco com aspas-dolar, depois da DDL) ────
CREATE OR REPLACE FUNCTION public.epi_ca_conferir_caepi(p_ca_numero text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE c public.caepi_cache%ROWTYPE;
BEGIN
  SELECT * INTO c FROM public.caepi_cache
   WHERE ca_numero = regexp_replace(COALESCE(p_ca_numero,''), '[^0-9]', '', 'g');
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ca_numero', p_ca_numero, 'conferido', false, 'situacao', 'nao_confirmado');
  END IF;
  RETURN jsonb_build_object(
    'ca_numero', c.ca_numero, 'conferido', true,
    'equipamento', c.equipamento, 'fabricante', c.fabricante,
    'validade', c.validade, 'situacao', c.situacao,
    'vencido', (c.validade IS NOT NULL AND c.validade < CURRENT_DATE));
END;
$$;

COMMENT ON FUNCTION public.epi_ca_conferir_caepi(text) IS
  'EPI-010: confere o CA de epi_tipos contra o cache da base oficial CAEPI.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — rode SEPARADA (query propria) apos aplicar.
-- Esperado: tabela_ok = t | funcao_ok = t | erro_tecnico = OK
-- ---------------------------------------------------------------------------
WITH chk AS MATERIALIZED (
  SELECT
    to_regclass('public.caepi_cache') IS NOT NULL AS tabela_ok,
    to_regprocedure('public.epi_ca_conferir_caepi(text)') IS NOT NULL AS funcao_ok
)
SELECT
  tabela_ok,
  funcao_ok,
  CASE WHEN tabela_ok AND funcao_ok THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico
FROM chk;
