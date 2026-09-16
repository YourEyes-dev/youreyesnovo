-- =========================================================
-- QA — FERIAS-033 passa a conferir o MOTOR, não só a existência
--
-- A rotina anterior procurava qualquer função com "media" no nome e dava
-- por satisfeita. Agora que ferias_media_variaveis existe, o caso confere
-- o que interessa: a função responde, devolve a memória (competências,
-- rubricas, divisor, fundamento) e respeita a parametrização por empresa.
--
-- Somente leitura: a chamada de sonda usa um CPF inexistente, então não
-- lê dado de ninguém e não grava nada.
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_ferias_033()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
    r          public.qa_retorno;
    v_existe   BOOLEAN;
    v_sonda    JSONB;
    v_faltando TEXT[];
    v_param    BOOLEAN;
BEGIN
    r.passo_ordem := 1;
    r.passo_acao  := 'AUDITORIA (somente leitura): a média das variáveis do art. 142 é apurada da folha, com memória?';
    r.esperado    := 'Função que soma as rubricas marcadas como integrantes das férias na janela do período e devolve média + memória competência a competência';

    SELECT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'ferias_media_variaveis'
    ) INTO v_existe;

    IF NOT v_existe THEN
        r.situacao := 'falhou';
        r.obtido := 'ACHADO CENTRAL do documento de requisitos: a média das variáveis não é '
                 || 'apurada — o campo é digitado e nasce zerado. Quem recebe hora extra '
                 || 'habitual, comissão ou adicional leva a MÉDIA para as férias; calcular só '
                 || 'o fixo paga a menos, e sem memória nada se audita. Correção: apuração '
                 || 'determinística a partir das rubricas marcadas com incide_ferias, com '
                 || 'memória exportável (RF-004 e RNF-001 do documento).';
        RETURN r;
    END IF;

    -- Sonda: CPF que não existe. Interessa a FORMA da resposta, não o valor.
    v_sonda := public.ferias_media_variaveis(
        '00000000-0000-0000-0000-000000000000'::uuid,
        '00000000000', DATE '2025-01-01', DATE '2025-12-31'
    );

    SELECT array_agg(chave) INTO v_faltando
      FROM unnest(ARRAY['media','total','meses_divisor','base','divisor_regra',
                        'janela_inicio','janela_fim','competencias','rubricas',
                        'parametros_vigencia','fundamento']) AS chave
     WHERE NOT (v_sonda ? chave);

    SELECT public.qa_col_existe('ferias_config', 'media_base') IS NOT NULL
       AND public.qa_col_existe('ferias_config', 'media_divisor') IS NOT NULL
      INTO v_param;

    IF v_faltando IS NOT NULL THEN
        r.situacao := 'falhou';
        r.obtido := format('A apuração existe, mas a memória está incompleta: faltam %s no '
                 || 'retorno. Sem esses campos o valor não se reproduz depois (RNF-008).',
                 array_to_string(v_faltando, ', '));
    ELSIF NOT coalesce(v_param, false) THEN
        r.situacao := 'falhou';
        r.obtido := 'A apuração existe e devolve memória, mas a base e o divisor não são '
                 || 'parametrizáveis por empresa (ferias_config.media_base / media_divisor). '
                 || 'O documento pede parâmetro com vigência, não regra fixa no código (RNF-002).';
    ELSE
        r.situacao := 'passou';
        r.obtido := format('Média apurada da folha por ferias_media_variaveis, com memória '
                 || 'completa (janela %s a %s, base "%s", divisor "%s") e parâmetros por '
                 || 'empresa com vigência.',
                 v_sonda->>'janela_inicio', v_sonda->>'janela_fim',
                 v_sonda->>'base', v_sonda->>'divisor_regra');
    END IF;

    RETURN r;
EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
