-- HOMOLOGAÇÃO — somente leitura: detalhe dos casos ESP-ASS-003/004/005.
SELECT c AS caso, (r).situacao::text AS situacao, (r).obtido AS obtido, (r).erro_tecnico AS erro_tecnico
FROM (SELECT c, public.qa_executar_descartavel(c) AS r
      FROM unnest(ARRAY['qa_caso_esp_ass_003','qa_caso_esp_ass_004','qa_caso_esp_ass_005']) c) x;
