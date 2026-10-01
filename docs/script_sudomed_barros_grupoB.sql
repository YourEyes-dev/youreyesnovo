-- ============================================================================
-- ACERTO DO BANCO — BARROS · GRUPO B: incluir o trabalho de jun/jul + limpar
-- a duplicata cross-tenant da Tania.
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
--
-- CONTEXTO (descoberto no diagnóstico):
--   O Grupo B da Barros (Tania, Kailaine, Natiele) tem 20-28 dias de ponto em
--   jun/jul que NÃO entraram no saldo — jun/jul ficaram congelados no migrado.
--   Além disso, a Tania tem uma linha órfã de junho sob OUTRO tenant
--   (299779a8), separada da linha correta (tenant da empresa = 83f1b040).
--   E MAIO está ABERTO — como o migrado da Kailaine/Tania está em maio, reapurar
--   junho sem travar maio recalcularia maio e contaria o trabalho de maio EM
--   DOBRO com o migrado.
--
-- O QUE FAZ (uma transação):
--   1) TRAVA maio da Barros (congela o migrado) — se ainda não travado.
--   2) APAGA a linha órfã de junho da Tania (banco sob tenant 299779a8) + movs.
--   3) REAPURA jun->out das 3, por pessoa, sob o tenant da empresa (83f1b040),
--      na ordem das competências (cada mês lê o oficial do anterior). Com maio
--      travado, junho lê o migrado congelado e soma só o trabalho de jun/jul.
--   NÃO toca no Grupo A (só os 3 CPFs do Grupo B). NÃO usa o botão "Fechar"
--   (sem RN29). Idempotente (maio: NOT EXISTS; órfã: já apagada; reapuração:
--   recalcula igual).
--
-- VALIDADO em réplica (01/10/2026): lock de maio congela o oficial; reapuração
--   de junho lê o migrado congelado; remoção da órfã cross-tenant.
--
-- SEGURANÇA: originais no backup do Passo 0. jun/jul seguem fechados (a
--   apuração atualiza a fotografia; Súmula 338 preservada pelo lock).
-- ============================================================================

DO $gb$
DECLARE
  v_tenant  uuid;
  v_empresa uuid;
  v_cpf  text;
  v_comp text;
  v_cpfs  text[] := ARRAY['11869993900','07978291995','10599656905']; -- Kailaine, Natiele, Tania
  v_comps text[] := ARRAY['2026-06','2026-07','2026-08','2026-09','2026-10'];
  v_del int := 0;
BEGIN
  SELECT ec.id, ec.tenant_id INTO v_empresa, v_tenant
  FROM public.empresa_cadastro ec
  WHERE ec.razao_social ILIKE '%BARROS & NUERNBERG ENG%'
  ORDER BY ec.created_at NULLS LAST
  LIMIT 1;

  IF v_empresa IS NULL THEN
    RAISE EXCEPTION 'Empresa Barros não encontrada.';
  END IF;

  -- 1) Travar MAIO (congela o migrado) se ainda não travado.
  INSERT INTO public.ponto_fechamentos (tenant_id, empresa_id, competencia, status, data_fechamento)
  SELECT v_tenant, v_empresa, '2026-05', 'fechado', now()
  WHERE NOT EXISTS (
    SELECT 1 FROM public.ponto_fechamentos
    WHERE tenant_id = v_tenant AND competencia = '2026-05'
      AND empresa_id IS NOT DISTINCT FROM v_empresa);
  RAISE NOTICE 'Maio: travado (ou ja estava).';

  -- 2) Apagar a linha órfã de junho da Tania (sob tenant 299779a8).
  DELETE FROM public.ponto_banco_horas_movimentacoes
  WHERE banco_horas_id = 'c80e385d-f7e8-4071-8ade-4e916df9ace4';
  DELETE FROM public.ponto_banco_horas
  WHERE id = 'c80e385d-f7e8-4071-8ade-4e916df9ace4'
    AND tenant_id = '299779a8-1cd2-4ffe-9462-78181426cd1a';
  GET DIAGNOSTICS v_del = ROW_COUNT;
  RAISE NOTICE 'Orfa da Tania (junho/299779a8): % linha(s) removida(s).', v_del;

  -- 3) Reapurar jun->out das 3, por pessoa, na ordem das competências.
  FOREACH v_comp IN ARRAY v_comps LOOP
    FOREACH v_cpf IN ARRAY v_cpfs LOOP
      PERFORM public.apurar_banco_horas_colaborador(v_tenant, v_cpf, v_comp, v_empresa);
    END LOOP;
  END LOOP;
  RAISE NOTICE 'Reapuracao jun->out concluida (Kailaine, Natiele, Tania).';
END $gb$;


-- ---------------------------------------------------------------------
-- CONFERÊNCIA — saldos das 3 por competência (migrado + trabalho real).
-- ---------------------------------------------------------------------
SELECT
  bh.colaborador_nome,
  bh.competencia,
  (CASE WHEN bh.saldo_atual_minutos<0 THEN '-' ELSE '' END)
    || abs(bh.saldo_atual_minutos)/60 || 'h'
    || lpad((abs(bh.saldo_atual_minutos)%60)::text,2,'0') AS saldo_atual
FROM public.ponto_banco_horas bh
JOIN public.empresa_cadastro ec ON ec.id = bh.empresa_id
WHERE ec.razao_social ILIKE '%BARROS & NUERNBERG ENG%'
  AND (bh.colaborador_nome ILIKE '%Tania Mara%'
       OR bh.colaborador_nome ILIKE '%Kailaine%'
       OR bh.colaborador_nome ILIKE '%Natiele Cust%')
ORDER BY bh.colaborador_nome, bh.competencia;
