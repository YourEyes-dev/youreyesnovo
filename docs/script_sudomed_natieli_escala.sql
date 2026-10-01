-- ============================================================================
-- NATIELI — raio-x da escala (somente leitura)
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
-- NÃO altera nada. Mostra TODAS as atribuições de escala da Natieli (ativas e
-- inativas), com a jornada de cada escala e QUANDO cada atribuição foi criada.
-- Serve para ver onde está gravado o período de 44h e conferir as datas de corte.
-- ============================================================================
WITH tn AS MATERIALIZED (
  SELECT DISTINCT tenant_id
  FROM public.empresa_cadastro
  WHERE regexp_replace(COALESCE(cnpj,''),'[^0-9]','','g')
        IN ('26114701000145','31219374000126','41085456000189','41085456000260')
)
SELECT
  a.colaborador_nome                                   AS colaborador,
  es.nome                                              AS escala,
  'sem '||(COALESCE(es.jornada_semanal_minutos,0)/60)||'h'||lpad((COALESCE(es.jornada_semanal_minutos,0)%60)::text,2,'0')
    ||' · dia '||(COALESCE(es.jornada_diaria_minutos,0)/60)||'h'||lpad((COALESCE(es.jornada_diaria_minutos,0)%60)::text,2,'0') AS jornada,
  COALESCE(a.data_inicio::text,'?')                    AS inicio,
  COALESCE(a.data_fim::text,'(sem fim)')               AS fim,
  CASE WHEN COALESCE(a.ativa,true) THEN 'ATIVA' ELSE 'inativa' END AS situacao,
  to_char(a.created_at,'YYYY-MM-DD HH24:MI')           AS criada_em,
  a.id::text                                           AS atribuicao_id,
  es.id::text                                          AS escala_id
FROM public.ponto_escala_atribuicoes a
JOIN public.ponto_escalas es ON es.id = a.escala_id
WHERE a.tenant_id IN (SELECT tenant_id FROM tn)
  AND a.colaborador_nome ILIKE '%natiele%'
ORDER BY a.created_at, a.data_inicio NULLS FIRST;
