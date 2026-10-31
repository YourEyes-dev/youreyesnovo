-- =====================================================================
-- CONSULTA SOMENTE LEITURA — impacto da EC 141/2026 nas escalas
-- (rodar na PRODUÇÃO ANTES do script de entrega EC 141 F1; não altera nada)
--
-- Um único SELECT. Sem dado pessoal: só nome da conta, nome da empresa e
-- contagens. Usa apenas tabelas que já existem hoje (não depende da F1).
--
-- Colunas:
--   usa_ponto_set_out        a conta tem batidas desde 01/09/2026 (impacto real)
--   escalas_ativas / colaboradores   escalas ativas com gente atribuída hoje
--   *_acima_42h / *_acima_40h        carga semanal atual acima do teto da etapa
--   *_6dias_sem_coletivo     6+ dias trabalhados por semana e nenhuma CCT/ACT
--                            ativa e vigente em 15/12/2026 para a empresa
--   escalas_ciclo            12x36 / móvel (regime próprio, fora da conta de teto)
--   escalas_equalizacao      equalização mensal ligada (contratada 44h)
-- A carga semanal segue a conta da tela de escalas: janela do dia menos o
-- almoço (ou o intervalo do dia, ou a pré-assinalação vigente) + compensações
-- mensais / 4,345. Valores malformados contam como 0 (a consulta não quebra).
-- =====================================================================
WITH esc AS MATERIALIZED (
  SELECT e.id, e.tenant_id, e.empresa_id, COALESCE(e.tipo, '') AS tipo, COALESCE(e.modalidade, '') AS modalidade,
         e.dias_config, e.compensacoes_mensais, e.jornada_semanal_minutos, e.jornada_diaria_minutos,
         COALESCE(e.equalizacao_mensal_ativa, false) AS equalizacao
    FROM public.ponto_escalas e
   WHERE COALESCE(e.ativa, true)
),
decl AS MATERIALIZED (
  SELECT DISTINCT ON (pa.escala_id) pa.escala_id, pa.intervalo_minutos
    FROM public.ponto_pre_assinalacao pa
   WHERE pa.escala_id IS NOT NULL AND COALESCE(pa.ativa, true)
     AND pa.data_inicio <= CURRENT_DATE AND (pa.data_fim IS NULL OR pa.data_fim >= CURRENT_DATE)
   ORDER BY pa.escala_id, pa.data_inicio DESC
),
dia AS MATERIALIZED (
  SELECT s.id, s.dias_config -> k.dia AS c
    FROM esc s
    CROSS JOIN (VALUES ('segunda'), ('terca'), ('quarta'), ('quinta'), ('sexta'), ('sabado'), ('domingo')) AS k(dia)
   WHERE jsonb_typeof(s.dias_config) = 'object'
),
dia_min AS MATERIALIZED (
  SELECT d.id,
         CASE
           WHEN jsonb_typeof(d.c) <> 'object' OR lower(COALESCE(d.c->>'trabalha', 'false')) <> 'true' THEN 0
           WHEN NOT (COALESCE(d.c->>'entrada', '') ~ '^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$'
                 AND COALESCE(d.c->>'saida', '') ~ '^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$') THEN 0
           ELSE GREATEST(0,
                  (EXTRACT(EPOCH FROM ((d.c->>'saida')::time - (d.c->>'entrada')::time)) / 60)::int
                  - CASE
                      WHEN lower(COALESCE(d.c->>'tem_almoco', 'false')) = 'true'
                           AND COALESCE(d.c->>'inicio_almoco', '') ~ '^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$'
                           AND COALESCE(d.c->>'fim_almoco', '') ~ '^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$'
                        THEN (EXTRACT(EPOCH FROM ((d.c->>'fim_almoco')::time - (d.c->>'inicio_almoco')::time)) / 60)::int
                      WHEN COALESCE(d.c->>'intervalo', '') ~ '^[0-9]+$' THEN (d.c->>'intervalo')::int
                      ELSE COALESCE((SELECT x.intervalo_minutos FROM decl x WHERE x.escala_id = d.id), 0)
                    END)
         END AS minutos
    FROM dia d
),
comp AS MATERIALIZED (
  SELECT s.id,
         round(COALESCE(sum(GREATEST(0,
           CASE WHEN COALESCE(c->>'entrada', '') ~ '^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$'
                 AND COALESCE(c->>'saida', '') ~ '^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$'
                THEN (EXTRACT(EPOCH FROM ((c->>'saida')::time - (c->>'entrada')::time)) / 60)::int
                     - CASE WHEN COALESCE(c->>'intervalo', '') ~ '^[0-9]+$' THEN (c->>'intervalo')::int ELSE 0 END
                ELSE 0 END)), 0)::numeric / 4.345)::int AS comp_min
    FROM esc s
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(s.compensacoes_mensais) = 'array'
                                                 THEN s.compensacoes_mensais ELSE '[]'::jsonb END) AS a(c)
   GROUP BY s.id
),
carga AS MATERIALIZED (
  SELECT s.*,
         CASE WHEN jsonb_typeof(s.dias_config) = 'object'
              THEN COALESCE((SELECT sum(m.minutos) FROM dia_min m WHERE m.id = s.id), 0)
                   + COALESCE((SELECT c.comp_min FROM comp c WHERE c.id = s.id), 0)
              ELSE COALESCE(NULLIF(s.jornada_semanal_minutos, 0), COALESCE(s.jornada_diaria_minutos, 0) * 5)
         END AS carga_min,
         CASE WHEN jsonb_typeof(s.dias_config) = 'object'
              THEN (SELECT count(*) FROM dia_min m WHERE m.id = s.id AND m.minutos > 0)
              WHEN s.tipo = '6x1' THEN 6 WHEN s.tipo = '5x2' THEN 5 ELSE 0
         END AS dias_trab,
         (s.tipo = '12x36' OR s.modalidade = 'movel') AS ciclo
    FROM esc s
),
colab AS MATERIALIZED (
  SELECT a.escala_id,
         count(DISTINCT COALESCE(NULLIF(regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g'), ''), a.colaborador_id::text)) AS n
    FROM public.ponto_escala_atribuicoes a
   WHERE COALESCE(a.ativa, true) AND (a.data_fim IS NULL OR a.data_fim >= CURRENT_DATE)
   GROUP BY a.escala_id
),
lin AS MATERIALIZED (
  SELECT c.tenant_id, c.empresa_id, c.carga_min, c.dias_trab, c.ciclo, c.equalizacao,
         COALESCE(cb.n, 0) AS n,
         EXISTS (SELECT 1 FROM public.ponto_acordos ac
                  WHERE ac.tenant_id = c.tenant_id AND COALESCE(ac.ativo, false) AND ac.tipo IN ('act', 'cct')
                    AND (ac.vigencia_inicio IS NULL OR ac.vigencia_inicio <= DATE '2026-12-15')
                    AND (ac.vigencia_fim IS NULL OR ac.vigencia_fim >= DATE '2026-12-15')
                    AND (ac.empresa_id IS NULL OR c.empresa_id IS NULL OR ac.empresa_id = c.empresa_id)) AS coletivo
    FROM carga c
    LEFT JOIN colab cb ON cb.escala_id = c.id
   WHERE COALESCE(cb.n, 0) > 0
)
SELECT
  t.nome AS conta,
  COALESCE(ec.nome_fantasia, ec.razao_social, 'Sem empresa definida') AS empresa,
  EXISTS (SELECT 1 FROM public.ponto_marcacoes pm
           WHERE pm.tenant_id = l.tenant_id AND pm.data_marcacao >= DATE '2026-09-01') AS usa_ponto_set_out,
  count(*) AS escalas_ativas,
  sum(l.n) AS colaboradores,
  count(*) FILTER (WHERE NOT l.ciclo AND l.carga_min > 2520) AS escalas_acima_42h,
  COALESCE(sum(l.n) FILTER (WHERE NOT l.ciclo AND l.carga_min > 2520), 0) AS colab_acima_42h,
  count(*) FILTER (WHERE NOT l.ciclo AND l.carga_min > 2400) AS escalas_acima_40h,
  COALESCE(sum(l.n) FILTER (WHERE NOT l.ciclo AND l.carga_min > 2400), 0) AS colab_acima_40h,
  count(*) FILTER (WHERE l.dias_trab >= 6 AND NOT l.coletivo) AS escalas_6dias_sem_coletivo,
  COALESCE(sum(l.n) FILTER (WHERE l.dias_trab >= 6 AND NOT l.coletivo), 0) AS colab_6dias_sem_coletivo,
  count(*) FILTER (WHERE l.ciclo) AS escalas_ciclo,
  count(*) FILTER (WHERE l.equalizacao) AS escalas_equalizacao
FROM lin l
JOIN public.tenants t ON t.id = l.tenant_id
LEFT JOIN public.empresa_cadastro ec ON ec.id = l.empresa_id
GROUP BY t.nome, l.tenant_id, COALESCE(ec.nome_fantasia, ec.razao_social, 'Sem empresa definida')
ORDER BY usa_ponto_set_out DESC, conta, empresa;
