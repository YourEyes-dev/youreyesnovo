-- ============================================================================
-- SCRIPT DE ENTREGA — Ponto: registra o SÁBADO EQUALIZADOR que faltava
-- (ponto_equalizacao_mensal) nas 4 empresas do grupo, jun a out/2026.
--
-- Por quê: a escala de 44 h (8h38 seg–sex + 1 sábado por mês que completa a
-- jornada) foi substituída em 06/10/2026 e a atribuição antiga ficou INATIVA.
-- O cálculo ao vivo do saldo procura a equalização na escala ATIVA de hoje,
-- que não tem sábado equalizador: o sábado trabalhado de jun–set passou a
-- aparecer como crédito/HE nas telas e no espelho. O valor que o sistema já
-- GRAVOU nas apurações de ago/set (antes da troca) está certo; são as telas
-- que recalculam errado. Quando existe a linha de equalização do mês, o
-- cálculo a usa antes de olhar a escala — é o mesmo registro que o RH faz
-- pela tela "Equalização mensal" (já feito em agosto para parte da equipe).
--
-- Regra (a do próprio sistema): para cada colaborador e mês SEM linha de
-- equalização, pega o PRIMEIRO sábado do mês em que houve batida, a escala
-- atribuída que valia NAQUELE sábado (mesmo que hoje inativa) e o total que
-- a função oficial ponto_equalizacao_competencia calcula para ela. Só grava
-- se a escala tem a equalização mensal ativada (total > 0). Sábados depois
-- de 06/10/2026 ficam de fora (a escala nova não tem equalizador).
--
-- Só INSERE linhas novas (origem 'auto', memória marcada com este script);
-- não altera batidas, dias, ajustes nem linhas de equalização existentes.
-- Desfazer:
--   DELETE FROM public.ponto_equalizacao_mensal
--    WHERE memoria->>'script' = 'equalizacao_sabados_sudomed_20261029';
-- Idempotente (ON CONFLICT DO NOTHING).
-- ============================================================================

WITH emp AS MATERIALIZED (
  SELECT ec.id AS empresa_id, ec.tenant_id
  FROM public.empresa_cadastro ec
  WHERE regexp_replace(COALESCE(ec.cnpj,''),'[^0-9]','','g')
        = ANY (ARRAY['26114701000145','41085456000189','41085456000260','31219374000126'])
),
sabados AS MATERIALIZED (
  SELECT m.tenant_id,
         regexp_replace(COALESCE(m.colaborador_cpf,''),'[^0-9]','','g') AS cpf,
         to_char(m.data_marcacao,'YYYY-MM') AS competencia,
         min(m.data_marcacao) AS sabado
  FROM public.ponto_marcacoes m
  WHERE m.tenant_id IN (SELECT tenant_id FROM emp)
    AND m.data_marcacao BETWEEN DATE '2026-06-01' AND DATE '2026-10-06'
    AND EXTRACT(ISODOW FROM m.data_marcacao) = 6
    AND COALESCE(m.desconsiderada, false) = false
    AND length(regexp_replace(COALESCE(m.colaborador_cpf,''),'[^0-9]','','g')) = 11
  GROUP BY 1, 2, 3
),
sem_linha AS MATERIALIZED (
  SELECT s.*
  FROM sabados s
  WHERE NOT EXISTS (SELECT 1 FROM public.ponto_equalizacao_mensal q
                     WHERE q.tenant_id = s.tenant_id
                       AND q.colaborador_cpf = s.cpf
                       AND q.competencia = s.competencia)
),
com_escala AS MATERIALIZED (
  SELECT DISTINCT ON (s.tenant_id, s.cpf, s.competencia)
         s.tenant_id, s.cpf, s.competencia, s.sabado,
         a.escala_id, a.colaborador_nome, e.empresa_id
  FROM sem_linha s
  JOIN public.ponto_escala_atribuicoes a
    ON a.tenant_id = s.tenant_id
   AND regexp_replace(COALESCE(a.colaborador_cpf,''),'[^0-9]','','g') = s.cpf
   AND a.data_inicio <= s.sabado
   AND (a.data_fim IS NULL OR a.data_fim >= s.sabado)
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
         k.sabado, k.escala_id, (k.mem->>'total_equalizacao_min')::int,
         k.mem || jsonb_build_object('script','equalizacao_sabados_sudomed_20261029',
                                     'motivo','sabado equalizador da escala vigente na data (troca de escala em 06/10/2026)'),
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
  'sabados_sem_escala_com_equalizador', (SELECT count(*) FROM calc
               WHERE COALESCE((mem->>'total_equalizacao_min')::int, 0) = 0),
  'sabados_sem_atribuicao_na_data', (SELECT count(*) FROM sem_linha s
               WHERE NOT EXISTS (SELECT 1 FROM com_escala c
                                  WHERE c.tenant_id = s.tenant_id AND c.cpf = s.cpf
                                    AND c.competencia = s.competencia))
) AS resultado;
