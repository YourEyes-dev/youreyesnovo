-- ============================================================================
-- ESCALAS POR PERÍODO — SUDOMED (somente leitura)
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
-- NÃO altera nada. Mostra, para os 7 colaboradores do fechamento de julho,
-- o HISTÓRICO de escala (qual escala, de que data até que data, ativa ou não).
-- Serve para ver se a troca de escala foi gravada com corte de data correto
-- (ex.: Natieli — 44h até 31/08, 36h a partir de 01/09) ou se sobrescreveu
-- o histórico (atribuição retroativa).
-- ============================================================================
WITH tn AS MATERIALIZED (
  SELECT DISTINCT tenant_id
  FROM public.empresa_cadastro
  WHERE regexp_replace(COALESCE(cnpj,''),'[^0-9]','','g')
        IN ('26114701000145','31219374000126','41085456000189','41085456000260')
),
alvo(nome) AS (VALUES
  ('%natiele%'),('%tania%'),('%kailaine%'),
  ('%luiza%'),('%juleide%'),('%vera%'),('%jaquel%')
)
SELECT
  a.colaborador_nome AS colaborador,
  es.nome            AS escala,
  'sem '||(COALESCE(es.jornada_semanal_minutos,0)/60)||'h'||lpad((COALESCE(es.jornada_semanal_minutos,0)%60)::text,2,'0')
    ||' · dia '||(COALESCE(es.jornada_diaria_minutos,0)/60)||'h'||lpad((COALESCE(es.jornada_diaria_minutos,0)%60)::text,2,'0')
    ||' · sábado '||CASE WHEN COALESCE(es.sabado_util,false) THEN 'útil' ELSE 'folga' END AS jornada,
  COALESCE(a.data_inicio::text,'?') AS inicio,
  COALESCE(a.data_fim::text,'(sem fim)') AS fim,
  CASE WHEN COALESCE(a.ativa,true) THEN 'ATIVA' ELSE 'inativa' END AS situacao
FROM public.ponto_escala_atribuicoes a
JOIN public.ponto_escalas es ON es.id = a.escala_id
WHERE a.tenant_id IN (SELECT tenant_id FROM tn)
  AND EXISTS (SELECT 1 FROM alvo WHERE a.colaborador_nome ILIKE alvo.nome)
ORDER BY a.colaborador_nome, a.data_inicio NULLS FIRST, a.data_fim NULLS LAST;
