-- ============================================================================
-- BANCO DE HORAS — quem tem regime vigente, e quem tem saldo parado SEM regime
--
-- SOMENTE LEITURA. Nao cria, nao altera e nao apaga NADA.
--
-- POR QUE ESTA CONSULTA EXISTE
-- O espelho passou a respeitar o instrumento de compensacao: sem regime de
-- banco vigente, o excedente vai para PAGAMENTO (nao credita o banco) e o
-- deficit e atraso a descontar (nao debita o banco) — CLT art. 59, §2º, que
-- exige acordo formal para o banco existir.
--
-- Isso expos um estado que o espelho antigo escondia: colaborador com um
-- SALDO de banco parado (saldo_anterior) mas SEM regime ativo que o sustente.
-- Nesse estado o documento fica meio-a-meio: fala de banco no saldo, mas nao
-- move o banco. Precisa de decisao — configurar o regime, ou liquidar o saldo
-- e tratar tudo como a pagar/descontar.
--
-- Esta consulta lista, por empresa e colaborador, em qual dos casos cada um
-- esta. O CPF sai mascarado.
--
-- COMO LER
--   * TEM REGIME .......... ok, o banco funciona normalmente
--   * SEM REGIME, saldo 0 .. ok, e a pagar/descontar puro, sem legado
--   * SEM REGIME, saldo <>0  ATENCAO — saldo de banco parado sem instrumento.
--     Ou se cadastra o regime (e o saldo volta a se mover), ou se liquida o
--     saldo e o vinculo passa a a-pagar/descontar de forma limpa.
-- ============================================================================

WITH p AS MATERIALIZED (
  SELECT to_char(CURRENT_DATE, 'YYYY-MM')  AS comp_atual,
         (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::date AS ref
),
pessoas AS MATERIALIZED (
  -- Quem tem linha de banco em qualquer competencia (traz o saldo) OU bate
  -- ponto na competencia atual.
  SELECT DISTINCT b.tenant_id,
         regexp_replace(COALESCE(b.colaborador_cpf, ''), '[^0-9]', '', 'g') AS cpf,
         b.colaborador_nome,
         b.empresa_id
  FROM public.ponto_banco_horas b
  UNION
  SELECT DISTINCT d.tenant_id,
         regexp_replace(COALESCE(d.colaborador_cpf, ''), '[^0-9]', '', 'g') AS cpf,
         max(d.colaborador_nome) OVER (PARTITION BY d.tenant_id, d.colaborador_cpf),
         d.empresa_id
  FROM public.ponto_diario d, p
  WHERE to_char(d.data, 'YYYY-MM') = p.comp_atual
    AND EXISTS (SELECT 1 FROM public.ponto_marcacoes m
                 WHERE m.tenant_id = d.tenant_id
                   AND m.colaborador_cpf = d.colaborador_cpf
                   AND m.data_marcacao = d.data)
),
avaliado AS MATERIALIZED (
  SELECT pe.tenant_id, pe.cpf, pe.colaborador_nome, pe.empresa_id,
         COALESCE(e.nome_fantasia, e.razao_social) AS empresa,
         (public.ponto_banco_regime_vigente(pe.tenant_id, pe.cpf, NULL, p.ref)).id IS NOT NULL AS tem_regime,
         COALESCE((
           SELECT b.saldo_atual_minutos
           FROM public.ponto_banco_horas b
           WHERE b.tenant_id = pe.tenant_id
             AND regexp_replace(COALESCE(b.colaborador_cpf, ''), '[^0-9]', '', 'g') = pe.cpf
           ORDER BY b.competencia DESC NULLS LAST, b.updated_at DESC NULLS LAST
           LIMIT 1), 0) AS saldo_atual
  FROM pessoas pe
  CROSS JOIN p
  LEFT JOIN public.empresa_cadastro e ON e.id = pe.empresa_id
  WHERE COALESCE(e.usa_controle_ponto, false) = true
)
SELECT left(COALESCE(empresa, 'sem empresa'), 30)          AS empresa,
       '***' || right(cpf, 3)                              AS cpf,
       CASE WHEN tem_regime THEN 'sim' ELSE 'nao' END      AS tem_regime,
       (saldo_atual / 60) || 'h' || abs(saldo_atual % 60) || 'min'  AS saldo_banco,
       CASE
         WHEN tem_regime
           THEN 'OK — banco vigente, funciona normalmente'
         WHEN saldo_atual = 0
           THEN 'OK — a pagar/descontar puro, sem legado'
         ELSE 'ATENCAO — saldo de banco parado SEM regime: decidir (cadastrar regime ou liquidar o saldo)'
       END                                                 AS situacao
FROM avaliado
ORDER BY (tem_regime) ASC, (saldo_atual <> 0) DESC, empresa, cpf;
