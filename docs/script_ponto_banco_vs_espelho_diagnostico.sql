-- ============================================================================
-- DIAGNOSTICO — por que o espelho e o banco de horas discordam?
--
-- SOMENTE LEITURA. Nao cria, nao altera e nao apaga NADA. Pode rodar na
-- producao sem medo.
--
-- O QUE MOSTRA
-- Para cada colaborador de uma competencia, lado a lado:
--   * o que esta GRAVADO na tabela ponto_banco_horas (a fotografia que o
--     relatorio de Banco de Horas imprime);
--   * o que a APURACAO diz agora (o numero que o espelho imprime).
-- E a diferenca entre os dois, em minutos.
--
-- Se as duas colunas baterem, a fotografia esta em dia. Se nao baterem, a
-- diferenca e exatamente a mudanca que entrou depois da ultima apuracao: um
-- ajuste aprovado, um atestado lancado, uma marcacao que chegou atrasada.
--
-- COMO USAR
-- Troque a competencia e, se quiser, o CNPJ da empresa nas duas linhas
-- marcadas com AJUSTE AQUI. Deixe o CNPJ como NULL para olhar o tenant
-- inteiro.
--
-- O CPF sai mascarado (so os tres ultimos digitos): o resultado desta
-- consulta costuma ser copiado para conversas e documentos.
-- ============================================================================

WITH parametros AS MATERIALIZED (
  SELECT
    '2026-08'::text AS competencia,   -- AJUSTE AQUI: competencia
    NULL::text      AS cnpj_empresa   -- AJUSTE AQUI: CNPJ, ou NULL para todas
),
alvo AS MATERIALIZED (
  SELECT p.competencia,
         e.id AS empresa_id,
         e.razao_social
  FROM parametros p
  LEFT JOIN public.empresa_cadastro e
    ON p.cnpj_empresa IS NOT NULL
   AND regexp_replace(COALESCE(e.cnpj, ''), '[^0-9]', '', 'g')
     = regexp_replace(p.cnpj_empresa, '[^0-9]', '', 'g')
),
foto AS MATERIALIZED (
  -- O que o relatorio de Banco de Horas imprime hoje.
  SELECT b.tenant_id,
         regexp_replace(COALESCE(b.colaborador_cpf, ''), '[^0-9]', '', 'g') AS cpf,
         b.colaborador_nome,
         b.empresa_id,
         COALESCE(b.saldo_anterior_minutos, 0) AS saldo_anterior,
         COALESCE(b.creditos_minutos, 0)       AS creditos,
         COALESCE(b.debitos_minutos, 0)        AS debitos,
         COALESCE(b.compensados_minutos, 0)    AS compensados,
         COALESCE(b.saldo_atual_minutos, 0)    AS saldo_atual,
         b.updated_at
  FROM public.ponto_banco_horas b, alvo a
  WHERE b.competencia = a.competencia
    AND (a.empresa_id IS NULL OR b.empresa_id = a.empresa_id)
),
agora AS MATERIALIZED (
  -- O que a apuracao diz neste momento (a conta do espelho).
  SELECT f.tenant_id, f.cpf,
         COALESCE(SUM(CASE WHEN s.saldo_min > 0 THEN s.saldo_min ELSE 0 END), 0)::int  AS creditos,
         COALESCE(SUM(CASE WHEN s.saldo_min < 0 THEN -s.saldo_min ELSE 0 END), 0)::int AS debitos
  FROM foto f
  CROSS JOIN LATERAL public.ponto_saldo_dias_competencia(
    f.tenant_id, f.cpf, (SELECT competencia FROM alvo)) s
  GROUP BY f.tenant_id, f.cpf
),
comparado AS MATERIALIZED (
  SELECT f.cpf,
         f.colaborador_nome,
         f.saldo_anterior,
         f.creditos    AS cred_foto,
         g.creditos    AS cred_agora,
         f.debitos     AS deb_foto,
         g.debitos     AS deb_agora,
         f.compensados,
         f.saldo_atual AS saldo_foto,
         (f.saldo_anterior + g.creditos - g.debitos - f.compensados) AS saldo_agora,
         f.updated_at
  FROM foto f
  LEFT JOIN agora g ON g.tenant_id = f.tenant_id AND g.cpf = f.cpf
)
SELECT
  CASE WHEN c.saldo_foto = c.saldo_agora THEN 'EM DIA' ELSE 'DIVERGENTE' END AS situacao,
  left(COALESCE(c.colaborador_nome, ''), 28)                                 AS colaborador,
  '***' || right(COALESCE(c.cpf, '   '), 3)                                  AS cpf,
  c.saldo_anterior                                                           AS saldo_anterior_min,
  c.cred_foto || ' -> ' || COALESCE(c.cred_agora::text, '?')                 AS creditos_foto_agora,
  c.deb_foto  || ' -> ' || COALESCE(c.deb_agora::text, '?')                  AS debitos_foto_agora,
  c.saldo_foto || ' -> ' || COALESCE(c.saldo_agora::text, '?')               AS saldo_foto_agora,
  (COALESCE(c.saldo_agora, c.saldo_foto) - c.saldo_foto)                     AS diferenca_min,
  to_char(c.updated_at, 'DD/MM/YYYY HH24:MI')                                AS apurado_em,
  CASE
    WHEN c.saldo_agora IS NULL THEN 'CONFERIR: a apuracao nao devolveu dias para este CPF'
    WHEN c.saldo_foto = c.saldo_agora THEN 'OK'
    ELSE 'A fotografia envelheceu: algo mudou depois de ' ||
         to_char(c.updated_at, 'DD/MM HH24:MI') || '. Rodar a apuracao alinha os dois.'
  END                                                                        AS erro_tecnico
FROM comparado c
ORDER BY (c.saldo_foto = c.saldo_agora), abs(COALESCE(c.saldo_agora, c.saldo_foto) - c.saldo_foto) DESC,
         c.colaborador_nome;
