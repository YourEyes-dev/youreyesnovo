-- ============================================================================
-- ENTREGA — objetos AUSENTES na producao (funcoes que existem no teste e faltam)
--
-- O QUE ESTE SCRIPT FAZ:
--   Cria na producao tres funcoes que hoje so existem no teste (nao sao drift
--   de logica — sao objetos que faltam):
--     1. ponto_adicional_noturno_rural(text) — regime noturno rural (Lei
--        5.889/73): lavoura 21h-5h, pecuaria 20h-4h, adicional 25%, hora cheia.
--     2. ponto_auditoria_ajustes_motivo(...) — relatorio: ajustes de ponto
--        agrupados por colaborador+motivo (com/sem anexo, aprovados, etc.).
--     3. ponto_auditoria_motivos_resumo(...) — resumo do anterior, por motivo.
--   (2) e (3) alimentam a tela de auditoria de ajustes.
--
--   Corpo dos tres envelopado em DO/EXECUTE (padrao da casa para o SQL Editor
--   do Supabase nao se atrapalhar). Rode BLOCO 1, 2 e 3, um de cada vez.
--
-- SEGURANCA: so cria funcoes; nao altera nem apaga dado; idempotente
--   (CREATE OR REPLACE). Nenhuma delas escreve — sao somente leitura.
-- ============================================================================

SET lock_timeout = '10s';

-- ── BLOCO 1: ponto_adicional_noturno_rural ──────────────────────────────────
DO $ptdo$
BEGIN
  EXECUTE $ptsql$
CREATE OR REPLACE FUNCTION public.ponto_adicional_noturno_rural(p_regime text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $fn$
  -- Trabalhador RURAL tem regime noturno proprio (Lei 5.889/73): lavoura
  -- 21h-5h, pecuaria 20h-4h, adicional 25% e hora CHEIA (sem hora ficta),
  -- diferente do urbano (22h-5h, 20%, hora ficta de 52m30s).
  SELECT CASE p_regime
    WHEN 'rural_lavoura'  THEN jsonb_build_object('inicio','21:00','fim','05:00','adicional',25,'hora_ficta',false,'base','Lei 5.889/73')
    WHEN 'rural_pecuaria' THEN jsonb_build_object('inicio','20:00','fim','04:00','adicional',25,'hora_ficta',false,'base','Lei 5.889/73')
    ELSE jsonb_build_object('inicio','22:00','fim','05:00','adicional',20,'hora_ficta',true,'base','CLT art. 73')
  END;
$fn$;
  $ptsql$;
END
$ptdo$;

-- ── BLOCO 2: ponto_auditoria_ajustes_motivo ─────────────────────────────────
DO $ptdo$
BEGIN
  EXECUTE $ptsql$
CREATE OR REPLACE FUNCTION public.ponto_auditoria_ajustes_motivo(p_tenant_id uuid, p_empresa_id uuid, p_ini date, p_fim date)
 RETURNS TABLE(colaborador_cpf text, colaborador_nome text, motivo text, justificativa_nome text, requer_anexo boolean, qtd_ajustes integer, qtd_com_anexo integer, qtd_sem_anexo integer, qtd_sem_anexo_exigido integer, qtd_aprovados integer, qtd_pendentes integer, dias_distintos integer, meses_distintos integer, primeira_data date, ultima_data date, media_por_mes numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
  WITH base AS (
    SELECT
      a.colaborador_cpf,
      a.colaborador_nome,
      COALESCE(NULLIF(btrim(a.motivo), ''), 'Sem motivo declarado') AS motivo,
      j.nome AS justificativa_nome,
      COALESCE(j.requer_anexo, false) AS requer_anexo,
      a.data_referencia::date AS dia,
      a.status,
      -- anexos é jsonb/json com a lista de arquivos do ajuste
      (CASE
         WHEN a.anexos IS NULL THEN false
         WHEN jsonb_typeof(a.anexos::jsonb) = 'array' THEN jsonb_array_length(a.anexos::jsonb) > 0
         WHEN jsonb_typeof(a.anexos::jsonb) = 'object' THEN a.anexos::jsonb <> '{}'::jsonb
         ELSE false
       END) AS tem_anexo
    FROM public.ponto_ajustes a
    LEFT JOIN public.ponto_justificativas j ON j.id = a.justificativa_id
    WHERE a.tenant_id = p_tenant_id
      AND a.data_referencia::date BETWEEN p_ini AND p_fim
      AND (p_empresa_id IS NULL OR a.empresa_id = p_empresa_id)
  )
  SELECT
    b.colaborador_cpf,
    MAX(b.colaborador_nome),
    b.motivo,
    MAX(b.justificativa_nome),
    bool_or(b.requer_anexo),
    COUNT(*)::int,
    COUNT(*) FILTER (WHERE b.tem_anexo)::int,
    COUNT(*) FILTER (WHERE NOT b.tem_anexo)::int,
    COUNT(*) FILTER (WHERE NOT b.tem_anexo AND b.requer_anexo)::int,
    COUNT(*) FILTER (WHERE b.status = 'aprovado')::int,
    COUNT(*) FILTER (WHERE b.status = 'pendente')::int,
    COUNT(DISTINCT b.dia)::int,
    COUNT(DISTINCT date_trunc('month', b.dia))::int,
    MIN(b.dia),
    MAX(b.dia),
    ROUND(COUNT(*)::numeric / GREATEST(COUNT(DISTINCT date_trunc('month', b.dia)), 1), 1)
  FROM base b
  GROUP BY b.colaborador_cpf, b.motivo
  ORDER BY COUNT(*) DESC, MAX(b.colaborador_nome);
$fn$;
  $ptsql$;
END
$ptdo$;

-- ── BLOCO 3: ponto_auditoria_motivos_resumo ─────────────────────────────────
DO $ptdo$
BEGIN
  EXECUTE $ptsql$
CREATE OR REPLACE FUNCTION public.ponto_auditoria_motivos_resumo(p_tenant_id uuid, p_empresa_id uuid, p_ini date, p_fim date)
 RETURNS TABLE(motivo text, qtd_ajustes integer, qtd_colaboradores integer, qtd_com_anexo integer, qtd_sem_anexo integer, qtd_sem_anexo_exigido integer, pct_sem_anexo numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
  SELECT
    m.motivo,
    SUM(m.qtd_ajustes)::int,
    COUNT(DISTINCT m.colaborador_cpf)::int,
    SUM(m.qtd_com_anexo)::int,
    SUM(m.qtd_sem_anexo)::int,
    SUM(m.qtd_sem_anexo_exigido)::int,
    ROUND(100.0 * SUM(m.qtd_sem_anexo) / GREATEST(SUM(m.qtd_ajustes), 1), 1)
  FROM public.ponto_auditoria_ajustes_motivo(p_tenant_id, p_empresa_id, p_ini, p_fim) m
  GROUP BY m.motivo
  ORDER BY SUM(m.qtd_ajustes) DESC;
$fn$;
  $ptsql$;
END
$ptdo$;

-- ── CONFERENCIA — RODE SEPARADO (numa consulta nova) ────────────────────────
-- Mostra o md5 das tres funcoes na base atual. Compare com o md5 do TESTE
-- (rode a MESMA consulta no teste) — devem bater linha a linha. Md5 de
-- referencia do CSV inicial (pode estar velho se o teste foi editado depois):
--   ponto_adicional_noturno_rural   -> 113e6f18028d466760b04a6506b74a5b
--   ponto_auditoria_ajustes_motivo  -> 4e66e9e69187b01635136a0c6b77e795
--   ponto_auditoria_motivos_resumo  -> 27ee275ddacdb48d12b0ce049bfd1466
--   SELECT proname,
--          md5(regexp_replace(pg_get_functiondef(oid), '\s+', ' ', 'g')) AS md5
--   FROM pg_proc
--   WHERE proname IN ('ponto_adicional_noturno_rural',
--                     'ponto_auditoria_ajustes_motivo',
--                     'ponto_auditoria_motivos_resumo')
--     AND pronamespace = 'public'::regnamespace
--   ORDER BY proname;
