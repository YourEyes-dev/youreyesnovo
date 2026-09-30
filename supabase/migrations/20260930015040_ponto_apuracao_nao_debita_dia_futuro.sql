-- ============================================================================
-- Ponto — a apuração não debita dia que ainda não fechou (corte por fuso local)
--
-- ACHADO (produção, tela do banco, noite de 29/09/2026): o saldo já debitava
-- 30/09 (amanhã) como falta de jornada inteira. Causa: o gerador de dias da
-- apuração cortava os dias sintéticos (sem marcação) por "g.d <= CURRENT_DATE",
-- e CURRENT_DATE é UTC. Depois das ~21h de Brasília o UTC já virou o dia
-- seguinte, então "amanhã" entrava como falta. Também debitava o próprio dia de
-- HOJE antes de ele acabar (a pessoa ainda pode bater o ponto).
--
-- CORREÇÃO ([corte-dia-local]): só conta dia SEM marcação como falta depois que
-- ele FECHOU no fuso do estabelecimento — corta ESTRITAMENTE antes de hoje na
-- data local (America/Sao_Paulo). Dia com marcação continua aparecendo pela
-- outra condição (d.data IS NOT NULL), então hoje com batida segue normal.
--
-- Cirúrgico e idempotente (pg_get_functiondef + replace, com marcador). Espelha
-- o padrão de 20260929233840 / 20260902100000.
-- ============================================================================

DO $item$
DECLARE
  v_nome text; v_src text; v_novo text; v_achou boolean := false;
  v_alvo text; v_troca text;
BEGIN
  v_alvo := E'         AND g.d::date <= CURRENT_DATE';
  v_troca :=
       E'         -- [corte-dia-local] So conta dia SEM marcacao como falta depois que\n'
    || E'         -- ele FECHOU no fuso do estabelecimento. CURRENT_DATE e UTC: a noite\n'
    || E'         -- (>21h BRT) ja virou amanha e o dia seguinte entrava como falta.\n'
    || E'         -- Usa a data local e corta ESTRITAMENTE antes de hoje (hoje ainda\n'
    || E'         -- pode ser batido; dia com marcacao aparece pela outra condicao).\n'
    || E'         AND g.d::date < (timezone(''America/Sao_Paulo'', now()))::date';

  FOREACH v_nome IN ARRAY ARRAY['ponto_saldo_dias_competencia_bruto',
                                'ponto_saldo_dias_competencia'] LOOP
    SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname=v_nome
      AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_colaborador_cpf text, p_competencia text'
    LIMIT 1;

    IF v_src IS NULL OR position('v_tol_bat' IN v_src)=0 THEN CONTINUE; END IF;
    IF position('[corte-dia-local]' IN v_src) > 0 THEN
      RAISE NOTICE '% ja corta dia futuro pelo fuso local — nada a fazer.', v_nome; v_achou:=true; CONTINUE;
    END IF;
    IF position(v_alvo IN v_src)=0 THEN
      RAISE NOTICE 'ATENCAO: em % a ancora do corte de dia nao foi encontrada; NADA alterado.', v_nome; CONTINUE;
    END IF;

    v_novo := replace(v_src, v_alvo, v_troca);
    EXECUTE v_novo;
    v_achou := true;
    RAISE NOTICE 'Em %: dia sem marcacao so vira falta depois de fechar no fuso local.', v_nome;
  END LOOP;

  IF NOT v_achou THEN RAISE NOTICE 'Apuracao de saldo nao encontrada — nada a corrigir.'; END IF;
END $item$;
