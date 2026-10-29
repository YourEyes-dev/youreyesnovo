-- ============================================================================
-- SCRIPT DE ENTREGA — Ponto: complemento do sábado equalizador (parte 2)
-- Colaboradores da escala de 44 h que NÃO trabalharam nenhum sábado no mês.
--
-- Regra do próprio sistema (a mesma que valia antes da troca de escala de
-- 06/10/2026): mês encerrado, escala com equalização mensal ativa e nenhum
-- sábado trabalhado → as horas que faltam para fechar as 44 h viram débito no
-- ÚLTIMO sábado do mês. Com a escala antiga inativa, o cálculo ao vivo deixou
-- de lançar esse débito; o saldo GRAVADO nas apurações de ago/set já o tinha.
-- Esta parte registra a linha de equalização do mês para esses casos, com a
-- escala que valia no último sábado e o total calculado pela função oficial.
--
-- Só INSERE (origem 'auto'); não toca batidas, dias, ajustes nem as linhas
-- existentes (inclusive as gravadas pela parte 1). Só meses jun–set/2026.
-- Desfazer:
--   DELETE FROM public.ponto_equalizacao_mensal
--    WHERE memoria->>'script' = 'equalizacao_sem_sabado_sudomed_20261029';
-- Idempotente (ON CONFLICT DO NOTHING).
-- ============================================================================

WITH emp AS MATERIALIZED (
  SELECT ec.id AS empresa_id, ec.tenant_id
  FROM public.empresa_cadastro ec
  WHERE regexp_replace(COALESCE(ec.cnpj,''),'[^0-9]','','g')
        = ANY (ARRAY['26114701000145','41085456000189','41085456000260','31219374000126'])
),
meses AS MATERIALIZED (
  SELECT to_char(g,'YYYY-MM') AS competencia,
         -- último sábado do mês
         ((g + interval '1 month - 1 day')::date
           - ((EXTRACT(ISODOW FROM (g + interval '1 month - 1 day'))::int + 1) % 7)) AS ult_sab
  FROM generate_series(DATE '2026-06-01', DATE '2026-09-01', interval '1 month') g
),
colab_mes AS MATERIALIZED (
  -- colaborador ativo no mês (tem dia de ponto) e sem linha de equalização
  SELECT DISTINCT d.tenant_id,
         regexp_replace(COALESCE(d.colaborador_cpf,''),'[^0-9]','','g') AS cpf,
         m.competencia, m.ult_sab
  FROM public.ponto_diario d
  JOIN meses m ON to_char(d.data,'YYYY-MM') = m.competencia
  WHERE d.tenant_id IN (SELECT tenant_id FROM emp)
    AND length(regexp_replace(COALESCE(d.colaborador_cpf,''),'[^0-9]','','g')) = 11
    AND NOT EXISTS (SELECT 1 FROM public.ponto_equalizacao_mensal q
                     WHERE q.tenant_id = d.tenant_id
                       AND q.colaborador_cpf = regexp_replace(COALESCE(d.colaborador_cpf,''),'[^0-9]','','g')
                       AND q.competencia = m.competencia)
),
sem_sabado AS MATERIALIZED (
  SELECT c.*
  FROM colab_mes c
  WHERE NOT EXISTS (
    SELECT 1 FROM public.ponto_marcacoes mm
     WHERE mm.tenant_id = c.tenant_id
       AND regexp_replace(COALESCE(mm.colaborador_cpf,''),'[^0-9]','','g') = c.cpf
       AND to_char(mm.data_marcacao,'YYYY-MM') = c.competencia
       AND EXTRACT(ISODOW FROM mm.data_marcacao) = 6
       AND COALESCE(mm.desconsiderada, false) = false)
),
com_escala AS MATERIALIZED (
  SELECT DISTINCT ON (s.tenant_id, s.cpf, s.competencia)
         s.tenant_id, s.cpf, s.competencia, s.ult_sab,
         a.escala_id, a.colaborador_nome, e.empresa_id
  FROM sem_sabado s
  JOIN public.ponto_escala_atribuicoes a
    ON a.tenant_id = s.tenant_id
   AND regexp_replace(COALESCE(a.colaborador_cpf,''),'[^0-9]','','g') = s.cpf
   AND a.data_inicio <= s.ult_sab
   AND (a.data_fim IS NULL OR a.data_fim >= s.ult_sab)
  JOIN public.ponto_escalas e ON e.id = a.escala_id
  ORDER BY s.tenant_id, s.cpf, s.competencia, a.data_inicio DESC
),
calc AS MATERIALIZED (
  SELECT c.*, public.ponto_equalizacao_competencia(c.tenant_id, c.escala_id, c.competencia) AS mem
  FROM com_escala c
),
ins AS (
  INSERT INTO public.ponto_equalizacao_mensal (
    tenant_id, empresa_id, colaborador_cpf, colaborador_nome, competencia,
    data_equalizacao, escala_id, total_equalizacao_min, memoria, origem
  )
  SELECT k.tenant_id, k.empresa_id, k.cpf, k.colaborador_nome, k.competencia,
         k.ult_sab, k.escala_id, (k.mem->>'total_equalizacao_min')::int,
         k.mem || jsonb_build_object('script','equalizacao_sem_sabado_sudomed_20261029',
                                     'motivo','sem sabado trabalhado no mes: debito no ultimo sabado (regra do sistema antes da troca de escala de 06/10/2026)'),
         'auto'
  FROM calc k
  WHERE COALESCE((k.mem->>'total_equalizacao_min')::int, 0) > 0
  ON CONFLICT (tenant_id, colaborador_cpf, competencia) DO NOTHING
  RETURNING competencia, total_equalizacao_min
)
SELECT json_build_object(
  'linhas_inseridas', (SELECT count(*) FROM ins),
  'por_mes', (SELECT json_object_agg(competencia, n) FROM
               (SELECT competencia, count(*) AS n FROM ins GROUP BY 1) x),
  'minutos_por_mes', (SELECT json_object_agg(competencia, t) FROM
               (SELECT competencia, sum(total_equalizacao_min) AS t FROM ins GROUP BY 1) y),
  'meses_sem_equalizador_na_escala', (SELECT count(*) FROM calc
               WHERE COALESCE((mem->>'total_equalizacao_min')::int, 0) = 0)
) AS resultado;
