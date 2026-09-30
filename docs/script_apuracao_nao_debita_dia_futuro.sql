-- ============================================================================
-- ENTREGA — a apuração para de debitar dia que ainda não fechou
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
--
-- ACHADO (tela do banco, noite de 29/09): o saldo já debitava 30/09 (amanhã)
-- como falta de jornada inteira, e debitava o próprio dia de hoje antes de
-- acabar. Causa: o corte dos dias sintéticos usava CURRENT_DATE, que é UTC —
-- depois das ~21h de Brasília o UTC já virou o dia seguinte.
--
-- CORREÇÃO ([corte-dia-local]): só conta dia SEM marcação como falta depois que
-- ele FECHOU no fuso do estabelecimento (America/Sao_Paulo), cortando
-- ESTRITAMENTE antes de hoje. Dia com marcação continua normal.
--
-- SEGURANÇA: só redefine a função de apuração (não cria tabela, não escreve
-- dado). Idempotente (rodar 2x diz "nada a fazer"). Assim que aplicar, a tela
-- (que lê o oficial ao vivo) se corrige sozinha nos meses abertos: o débito
-- indevido de hoje/amanhã some.
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

-- Conferência (o editor mostra só o último resultado): confirma a marca no corpo.
SELECT position('[corte-dia-local]' IN pg_get_functiondef(p.oid)) > 0 AS corte_dia_ok
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname='public' AND p.proname='ponto_saldo_dias_competencia_bruto';
