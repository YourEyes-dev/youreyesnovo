-- SOMENTE LEITURA: estado das 2 funcoes que meus testes podem ter revertido na homologacao
DO $d$
DECLARE v_consol text; v_resumo text;
BEGIN
  v_consol := pg_get_functiondef('public.consolidar_ponto_diario_manual(uuid,text,date)'::regprocedure);
  v_resumo := pg_get_functiondef('public.ponto_espelho_resumo(uuid,text,date)'::regprocedure);
  RAISE NOTICE 'CONSOLID tem bloco feriado (ponto_grava_feriado_neutro)? %', (position('ponto_grava_feriado_neutro' IN v_consol) > 0);
  RAISE NOTICE 'CONSOLID tem meu PERFORM noturno (nao deveria)? %', (position('calcular_he_adicional_noturno_dia' IN v_consol) > 0);
  RAISE NOTICE 'RESUMO tem patch equalizacao ([falta-nao-conta-equalizacao])? %', (position('falta-nao-conta-equalizacao' IN v_resumo) > 0);
  RAISE NOTICE 'RESUMO tem coluna noturno (do meu teste B revertido, nao deveria)? %', (v_resumo ILIKE '%adicional_noturno_min%');
END $d$;
