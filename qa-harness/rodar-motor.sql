SET client_min_messages = warning;  -- cala os NOTICE cosméticos da bateria
-- Dispara o Motor em TODOS os módulos no banco efêmero.
-- Limpa antes as execuções que rodaram durante a aplicação das migrations
-- (algumas migrations do próprio Motor rodam uma bateria ao serem aplicadas),
-- para o snapshot refletir só esta passada completa.
DELETE FROM public.qa_execucoes;

DO $rede$
DECLARE m record;
BEGIN
  PERFORM public.qa_modo_ligar();
  FOR m IN SELECT path FROM public.qa_modulos ORDER BY path LOOP
    PERFORM public.qa_rodar_bateria('manual', m.path);
  END LOOP;
END $rede$;
