-- ============================================================================
-- CONSULTA SOMENTE LEITURA — impacto da Fatia 1 do banco configurável
-- (ponto_banco_regime_vigente: regra "sem_banco" passa a valer como SEM banco;
--  data_fim respeitada; regra presa a convenção fica para a Fatia 2)
--
-- Pode colar em PRODUÇÃO antes ou depois do script de entrega: não altera nada,
-- não cria nada e não depende das colunas novas (lê data_fim/instrumento_id por
-- to_jsonb, que devolve nulo quando a coluna ainda não existe).
-- Sem dado pessoal: só contagens por conta e por empresa (nome da empresa).
--
-- Colunas:
--   regras_sem_banco_ativas   regras "sem_banco" ativas da empresa (+ as da conta, sem empresa)
--   colaboradores_ativos      admissões concluídas e não inativas
--   tinham_banco_hoje         regime pela regra ANTIGA na data de hoje
--   tem_banco_nova_regra      regime pela regra NOVA na data de hoje
--   passam_a_sem_banco        tinham banco e deixam de ter (o que muda)
--   passam_a_ter_banco        o contrário (esperado 0)
-- A regra antiga e a nova são reproduzidas aqui, com a MESMA precedência da
-- função (escala > empresa > conta, data_inicio mais recente, acordo exigido).
-- ============================================================================
WITH colab AS MATERIALIZED (
  SELECT a.tenant_id, a.empresa_id,
         regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') AS cpf
  FROM public.admissoes a
  WHERE a.status = 'concluido' AND NOT COALESCE(a.inativo, false)
),
cfg AS MATERIALIZED (
  SELECT c.id, c.tenant_id, c.empresa_id, c.escala_id, c.tipo, c.data_inicio,
         NULLIF(to_jsonb(c)->>'data_fim', '')::date AS data_fim,
         NULLIF(to_jsonb(c)->>'instrumento_id', '') AS instrumento_id,
         ((COALESCE(c.exige_acordo_individual, false) = false AND COALESCE(c.exige_cct_act, false) = false)
          OR c.acordo_id IS NOT NULL) AS acordo_ok
  FROM public.ponto_banco_horas_config c
  WHERE COALESCE(c.ativo, false)
    AND (c.data_inicio IS NULL OR c.data_inicio <= CURRENT_DATE)
),
esc AS MATERIALIZED (
  SELECT DISTINCT ON (k.tenant_id, k.cpf) k.tenant_id, k.cpf, at.escala_id
  FROM colab k
  JOIN public.ponto_escala_atribuicoes at
    ON at.tenant_id = k.tenant_id
   AND regexp_replace(COALESCE(at.colaborador_cpf, ''), '[^0-9]', '', 'g') = k.cpf
  WHERE COALESCE(at.ativa, true)
    AND (at.data_inicio IS NULL OR at.data_inicio <= CURRENT_DATE)
    AND (at.data_fim IS NULL OR at.data_fim >= CURRENT_DATE)
  ORDER BY k.tenant_id, k.cpf, at.data_inicio DESC NULLS LAST
),
regime AS MATERIALIZED (
  SELECT k.tenant_id, k.empresa_id,
         (SELECT c.id IS NOT NULL
            FROM cfg c
           WHERE c.tenant_id = k.tenant_id AND c.acordo_ok
             AND (c.escala_id IS NULL OR c.escala_id = e.escala_id)
             AND (c.empresa_id IS NULL OR c.empresa_id = k.empresa_id)
           ORDER BY (c.escala_id IS NOT NULL) DESC, (c.empresa_id IS NOT NULL) DESC, c.data_inicio DESC NULLS LAST
           LIMIT 1) AS tem_antigo,
         (SELECT c.tipo <> 'sem_banco'
            FROM cfg c
           WHERE c.tenant_id = k.tenant_id AND c.acordo_ok
             AND (c.data_fim IS NULL OR c.data_fim >= CURRENT_DATE)
             AND c.instrumento_id IS NULL
             AND (c.escala_id IS NULL OR c.escala_id = e.escala_id)
             AND (c.empresa_id IS NULL OR c.empresa_id = k.empresa_id)
           ORDER BY (c.escala_id IS NOT NULL) DESC, (c.empresa_id IS NOT NULL) DESC, c.data_inicio DESC NULLS LAST
           LIMIT 1) AS tem_novo
  FROM colab k
  LEFT JOIN esc e ON e.tenant_id = k.tenant_id AND e.cpf = k.cpf
)
SELECT t.nome AS conta,
       COALESCE(ec.nome_fantasia, ec.razao_social, '(sem empresa)') AS empresa,
       (SELECT count(*) FROM public.ponto_banco_horas_config s
         WHERE s.tenant_id = r.tenant_id AND s.tipo = 'sem_banco' AND COALESCE(s.ativo, false)
           AND (s.empresa_id IS NULL OR s.empresa_id = r.empresa_id)) AS regras_sem_banco_ativas,
       count(*) AS colaboradores_ativos,
       count(*) FILTER (WHERE COALESCE(r.tem_antigo, false)) AS tinham_banco_hoje,
       count(*) FILTER (WHERE COALESCE(r.tem_novo, false)) AS tem_banco_nova_regra,
       count(*) FILTER (WHERE COALESCE(r.tem_antigo, false) AND NOT COALESCE(r.tem_novo, false)) AS passam_a_sem_banco,
       count(*) FILTER (WHERE NOT COALESCE(r.tem_antigo, false) AND COALESCE(r.tem_novo, false)) AS passam_a_ter_banco
FROM regime r
JOIN public.tenants t ON t.id = r.tenant_id
LEFT JOIN public.empresa_cadastro ec ON ec.id = r.empresa_id
GROUP BY t.nome, r.tenant_id, r.empresa_id, ec.nome_fantasia, ec.razao_social
HAVING count(*) FILTER (WHERE COALESCE(r.tem_antigo, false)) > 0
    OR (SELECT count(*) FROM public.ponto_banco_horas_config s
         WHERE s.tenant_id = r.tenant_id AND s.tipo = 'sem_banco' AND COALESCE(s.ativo, false)) > 0
ORDER BY passam_a_sem_banco DESC, conta, empresa;
