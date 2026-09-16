-- ============================================================================
-- ENTREGA — PONTO-394 acusa a chave antiga em vez de quebrar
--
-- ONDE COLAR: SQL Editor da HOMOLOGACAO (e da PRODUCAO, quando a trilha da
-- bancada for aplicada la). Depois do script_qa_bancada_tolerante_ambiente_antigo.
--
-- O QUE RESOLVE
-- Na bateria de 01/09 na homologacao sobraram 2 casos em ERRO. Este e um
-- deles:  duplicate key value violates unique constraint "unique_ponto_diario"
--
-- Nao e defeito do teste — e o proprio achado que o caso existe para provar:
-- onde a onda 1 nao chegou, a chave da apuracao diaria e (tenant, CPF, data),
-- sem a empresa, e o SEGUNDO vinculo do mesmo trabalhador colide com o
-- primeiro. O que estava errado era a FORMA de reportar: como ERRO, o achado
-- sumia do relatorio. Agora vira FALHA COM ACHADO, com o efeito pratico e a
-- correcao ja existente no projeto (migration 20260818190000).
--
-- O OUTRO ERRO que sobrou (PONTO-354) tem entrega propria:
-- docs/script_ponto_correcoes_bateria_homologacao.sql — rode-o tambem.
--
-- GARANTIAS
--   - NAO altera nenhuma regra de negocio. So a bancada que as verifica.
--   - Idempotente: a rotina original so e renomeada uma vez.
--   - Onde a chave ja e a nova, o caso roda como sempre.
-- Roda inteiro em UMA transacao.
-- ============================================================================

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

-- ---------------------------------------------------------------------------
-- CONFERENCIA FINAL — o caso agora responde sem quebrar.
-- Esperado neste ambiente: falhou | com_guarda = t | OK
-- ---------------------------------------------------------------------------
WITH x AS MATERIALIZED (
  SELECT (public.qa_caso_ponto_394()).situacao AS situacao,
         to_regprocedure('public.qa_caso_ponto_394_corpo()') IS NOT NULL AS com_guarda
)
SELECT situacao, com_guarda,
       CASE WHEN com_guarda AND situacao IN ('passou','falhou') THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico
FROM x;
