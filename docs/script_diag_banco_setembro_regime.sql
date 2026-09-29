-- ============================================================================
-- DIAGNÓSTICO (SOMENTE LEITURA) — Banco de horas Setembro/2026 x regime
-- Seguro em PRODUÇÃO. Explica por que a tabela do banco mostra 0 para quem tem
-- movimento no detalhamento: o banco só acumula quando há REGIME de compensação
-- vigente; sem regime, as horas vão para a folha (banco fica 0, corretamente).
--
-- Mostra, por colaborador (empresas do grupo), em 2026-09:
--   · snap_saldo      = fotografia (o que a tela lia antes);
--   · oficial_saldo/cred/deb = apuração oficial ao vivo (o que a tela lê agora);
--   · tem_regime      = há instrumento de compensação vigente? (decide o banco);
--   · diario_bruto    = soma do saldo diário do mês (o que o DETALHE mostra),
--     independente de regime.
-- Leitura: tem_regime = false com diario_bruto <> 0  => banco 0 é CORRETO
-- (débito/crédito vai para a folha, não para o banco).
-- ============================================================================

WITH emp AS (
  SELECT id AS empresa_id, tenant_id, cnpj
  FROM public.empresa_cadastro
  WHERE regexp_replace(COALESCE(cnpj,''),'[^0-9]','','g') IN (
    '26114701000145','41085456000189','31219374000126')
)
SELECT
  emp.cnpj AS empresa_cnpj,
  b.colaborador_nome,
  b.colaborador_cpf,
  b.saldo_atual_minutos AS snap_saldo,
  o.saldo_atual_min     AS oficial_saldo,
  o.creditos_min        AS oficial_cred,
  o.debitos_min         AS oficial_deb,
  o.tem_regime,
  COALESCE((SELECT SUM(s.saldo_min)
            FROM public.ponto_saldo_dias_competencia(b.tenant_id, b.colaborador_cpf, b.competencia) s), 0) AS diario_bruto
FROM public.ponto_banco_horas b
JOIN emp ON emp.empresa_id = b.empresa_id
LEFT JOIN LATERAL public.ponto_banco_horas_oficial(
  b.tenant_id, b.competencia, b.empresa_id, b.colaborador_cpf) o ON true
WHERE b.competencia = '2026-09'
ORDER BY emp.cnpj, b.colaborador_nome;
