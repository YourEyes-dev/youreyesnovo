-- ============================================================================
-- SCRIPT DE ENTREGA (PRODUÇÃO) — F1 PARTE 2 de 2: dados (rode DEPOIS da parte 1)
-- 1) BACKUP no schema privado backup das marcações não originais que serão tocadas
-- 2) rótulo: não originais com origem 'O' passam a 'A' (incluída)
-- 3) ligação: preenche ajuste_id onde o casamento com o ajuste aprovado é 1:1
-- Não muda hora, data, NSR nem hash. O log de auditoria registra cada mudança.
-- Idempotente. Sem funções neste arquivo (a criação do backup é por EXECUTE).
-- DESFAZER (se precisar):
--   UPDATE public.ponto_marcacoes m SET origem_marcacao = b.origem_marcacao, ajuste_id = b.ajuste_id
--     FROM backup.ponto_marcacoes_origem_20261029 b WHERE m.id = b.id;
-- ============================================================================

DO $bk$
BEGIN
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS backup.ponto_marcacoes_origem_20261029 AS '
       || 'SELECT * FROM public.ponto_marcacoes WHERE marcacao_original IS FALSE '
       || 'AND (origem_marcacao = ''O'' OR ajuste_id IS NULL)';
END
$bk$;

-- Dados antigos (idempotente)
UPDATE public.ponto_marcacoes
   SET origem_marcacao = 'A'
 WHERE marcacao_original IS FALSE AND origem_marcacao = 'O';

WITH cand AS MATERIALIZED (
  SELECT m.id AS marcacao_id, a.id AS ajuste_id
  FROM public.ponto_marcacoes m
  JOIN public.ponto_ajustes a
    ON a.tenant_id = m.tenant_id
   AND regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g')
     = regexp_replace(COALESCE(m.colaborador_cpf, ''), '[^0-9]', '', 'g')
   AND a.data_referencia = m.data_marcacao
   AND a.status = 'aprovado'
   AND a.tipo_ajuste IN ('inclusao', 'correcao')
   AND a.hora_solicitada IS NOT NULL
   AND to_char(a.hora_solicitada, 'HH24:MI') = to_char(m.hora_marcacao, 'HH24:MI')
  WHERE m.marcacao_original IS FALSE
    AND m.ajuste_id IS NULL
),
unicos AS MATERIALIZED (
  SELECT c.marcacao_id, min(c.ajuste_id::text)::uuid AS ajuste_id
  FROM cand c
  WHERE NOT EXISTS (SELECT 1 FROM cand c2 WHERE c2.marcacao_id = c.marcacao_id AND c2.ajuste_id <> c.ajuste_id)
    AND NOT EXISTS (SELECT 1 FROM cand c3 WHERE c3.ajuste_id = c.ajuste_id AND c3.marcacao_id <> c.marcacao_id)
  GROUP BY c.marcacao_id
)
UPDATE public.ponto_marcacoes m
   SET ajuste_id = u.ajuste_id
  FROM unicos u
 WHERE m.id = u.marcacao_id AND m.ajuste_id IS NULL;

-- Conferência
SELECT json_build_object(
  'linhas_no_backup', (SELECT count(*) FROM backup.ponto_marcacoes_origem_20261029),
  'nao_originais_rotuladas_O_restantes', (SELECT count(*) FROM public.ponto_marcacoes WHERE marcacao_original IS FALSE AND origem_marcacao = 'O'),
  'incluidas_ligadas_ao_ajuste', (SELECT count(*) FROM public.ponto_marcacoes WHERE marcacao_original IS FALSE AND ajuste_id IS NOT NULL),
  'incluidas_sem_ligacao', (SELECT count(*) FROM public.ponto_marcacoes WHERE marcacao_original IS FALSE AND ajuste_id IS NULL)
) AS resultado;
