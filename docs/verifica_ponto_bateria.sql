-- ============================================================================
-- CONFERENCIA (somente leitura de QA): roda a bateria do modulo Ponto na
-- homologacao e reporta o placar + quaisquer casos falhou/erro. Prova que a
-- restauracao das funcoes do espelho e da consolidacao nao regrediu nada.
-- Nao e entrega; nao vai pra producao.
-- ============================================================================
SET lock_timeout = '10s';

DO $run$
DECLARE
  v_exec uuid;
  v_total int; v_passou int; v_falhou int; v_erro int; v_ni int;
  v_lista text;
BEGIN
  v_exec := public.qa_rodar_bateria('manual', 'jornada-rotina/ponto');

  SELECT count(*),
         count(*) FILTER (WHERE situacao = 'passou'),
         count(*) FILTER (WHERE situacao = 'falhou'),
         count(*) FILTER (WHERE situacao = 'erro'),
         count(*) FILTER (WHERE situacao = 'nao_implementado')
    INTO v_total, v_passou, v_falhou, v_erro, v_ni
  FROM public.qa_resultados WHERE execucao_id = v_exec;

  SELECT string_agg(codigo || '=' || situacao::text, ', ' ORDER BY codigo)
    INTO v_lista
  FROM public.qa_resultados
  WHERE execucao_id = v_exec AND situacao IN ('falhou','erro');

  RAISE NOTICE 'BATERIA-PONTO: total=% passou=% falhou=% erro=% nao_implementado=%',
    v_total, v_passou, v_falhou, v_erro, v_ni;
  RAISE NOTICE 'BATERIA-PONTO problemas: %', COALESCE(v_lista, '(nenhum)');
END;
$run$;
