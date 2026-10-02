-- ============================================================================
-- DIAGNÓSTICO 2 (SOMENTE LEITURA) — Barros Grupo B: dado cru p/ planejar o fecho.
-- Colar no SQL Editor de PRODUÇÃO. NÃO altera nada. 3 resultados (rode os 3).
-- ============================================================================

-- (1) Linhas de JUNHO da Tania: CPF cru entre aspas + tamanho + tenant/empresa.
--     Mostra por que a duplicata driblou a restricao unica.
SELECT
  bh.id AS banco_id,
  '[' || bh.colaborador_cpf || ']' AS cpf_entre_colchetes,
  length(bh.colaborador_cpf) AS tam_cpf,
  bh.tenant_id,
  bh.empresa_id,
  bh.competencia,
  bh.saldo_atual_minutos AS st
FROM public.ponto_banco_horas bh
JOIN public.empresa_cadastro ec ON ec.id = bh.empresa_id
WHERE ec.razao_social ILIKE '%BARROS & NUERNBERG ENG%'
  AND bh.colaborador_nome ILIKE '%Tania Mara%'
  AND bh.competencia = '2026-06'
ORDER BY bh.saldo_atual_minutos;

-- (2) Status de fechamento de MAIO e JUNHO/JULHO da Barros.
SELECT ec.razao_social, f.competencia, f.status, f.data_fechamento
FROM public.ponto_fechamentos f
JOIN public.empresa_cadastro ec ON ec.id = f.empresa_id
WHERE ec.razao_social ILIKE '%BARROS & NUERNBERG ENG%'
  AND f.competencia IN ('2026-05','2026-06','2026-07')
ORDER BY f.competencia;

-- (3) Quantos dias de ponto cada uma das 3 tem em jun/jul (há trabalho a incluir?).
SELECT
  d.colaborador_nome,
  to_char(d.data,'YYYY-MM') AS competencia,
  count(*) AS dias_com_ponto
FROM public.ponto_diario d
JOIN public.empresa_cadastro ec ON ec.id = d.empresa_id
WHERE ec.razao_social ILIKE '%BARROS & NUERNBERG ENG%'
  AND (d.colaborador_nome ILIKE '%Tania Mara%'
       OR d.colaborador_nome ILIKE '%Kailaine%'
       OR d.colaborador_nome ILIKE '%Natiele Cust%')
  AND d.data BETWEEN DATE '2026-06-01' AND DATE '2026-07-31'
GROUP BY d.colaborador_nome, to_char(d.data,'YYYY-MM')
ORDER BY d.colaborador_nome, competencia;
