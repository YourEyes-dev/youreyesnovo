-- =====================================================================
-- QA — PONTO-394 acusa a chave antiga em vez de quebrar
--
-- MOTIVO: na bateria da homologação (01/09), depois da leva de tolerância,
-- sobraram 2 casos em ERRO. Um deles é o PONTO-394:
--
--   duplicate key value violates unique constraint "unique_ponto_diario"
--
-- Esse erro NÃO é defeito do teste: é exatamente o achado que o caso
-- existe para provar. Onde a onda 1 (20260818190000) ainda não chegou, a
-- chave da apuração diária é (tenant, cpf, data) — sem a empresa —, e o
-- segundo vínculo do mesmo trabalhador colide com o primeiro: dois
-- contratos no mesmo grupo são estruturalmente impossíveis de apurar.
--
-- O problema é a FORMA de reportar. Chegando como ERRO ("a rotina
-- quebrou"), o achado some do relatório: quem lê não distingue de uma
-- rotina defeituosa. Aqui o caso passa a conferir a chave ANTES e, quando
-- ela não inclui a empresa, devolve FALHA COM ACHADO, dizendo o efeito
-- prático e apontando a correção que já existe no projeto.
--
-- Onde a chave já é a nova, o corpo original roda igual — inclusive
-- continuando a reprovar se a apuração separar mal os dois vínculos.
--
-- NADA DE REGRA DE NEGÓCIO MUDA. Só a bancada que a verifica.
-- =====================================================================

SET lock_timeout = '10s';

DO $envelopa$
BEGIN
  IF to_regprocedure('public.qa_caso_ponto_394()') IS NULL THEN
    RAISE NOTICE 'qa_caso_ponto_394 nao existe nesta base — nada a envelopar.';
    RETURN;
  END IF;

  IF to_regprocedure('public.qa_caso_ponto_394_corpo()') IS NULL THEN
    ALTER FUNCTION public.qa_caso_ponto_394() RENAME TO qa_caso_ponto_394_corpo;
  END IF;

  CREATE OR REPLACE FUNCTION public.qa_caso_ponto_394()
  RETURNS public.qa_retorno
  LANGUAGE plpgsql
  AS $corpo$
  DECLARE r public.qa_retorno; v_def text;
  BEGIN
    SELECT indexdef INTO v_def
    FROM pg_indexes
    WHERE schemaname = 'public' AND tablename = 'ponto_diario'
      AND indexname = 'unique_ponto_diario';

    IF v_def IS NOT NULL AND v_def NOT ILIKE '%empresa_id%' THEN
      r.passo_ordem := 1;
      r.passo_acao  := 'Conferir se a chave da apuracao diaria comporta dois vinculos';
      r.esperado    := 'Chave por tenant, CPF, data E EMPRESA — dois contratos coexistem no mesmo dia';
      r.situacao    := 'falhou';
      r.obtido      := 'ACHADO ESTRUTURAL: a chave da apuracao diaria deste ambiente e '
                    || '(tenant, CPF, data), SEM a empresa. Dois vinculos do mesmo '
                    || 'trabalhador — duas empresas do grupo, dois estabelecimentos — sao '
                    || 'impossiveis de apurar: o segundo contrato colide com o primeiro no '
                    || 'indice unique_ponto_diario e a gravacao do dia e recusada. Na '
                    || 'pratica, o segundo vinculo fica sem espelho, sem jornada e sem '
                    || 'horas extras. Correcao: incluir a empresa na chave, como o projeto '
                    || 'ja faz desde a onda 1 (migration 20260818190000), que acompanha um '
                    || 'gatilho de reconciliacao para nao duplicar o dia de quem tem um '
                    || 'unico vinculo.';
      r.erro_tecnico := 'Indice atual: ' || v_def;
      RETURN r;
    END IF;

    RETURN public.qa_caso_ponto_394_corpo();
  END $corpo$;

  RAISE NOTICE 'PONTO-394 passa a acusar a chave antiga como achado, em vez de quebrar.';
END $envelopa$;
