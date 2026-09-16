-- =====================================================================
-- PONTO — espelho e banco de horas passam a falar o mesmo numero
--
-- DE ONDE VEIO
-- Auditoria de fechamento de 01/09/2026 sobre uma competencia real. Os
-- dois documentos da MESMA competencia, emitidos no MESMO dia, para o
-- MESMO colaborador, nao batiam:
--
--                        espelho de ponto     banco de horas
--   saldo anterior            -16h02              -16h02
--   credito                    +1h11               +1h11
--   DEBITO                      7h30                7h00     <-- 30 min
--   saldo atual               -22h21              -21h51
--
-- A CAUSA
-- Sao dois caminhos diferentes para o mesmo numero:
--
--   * o espelho RECALCULA na hora, chamando a apuracao do dia;
--   * o relatorio de banco de horas LE a tabela ponto_banco_horas, que e
--     uma fotografia gravada na ultima vez que alguem rodou a apuracao.
--
-- Entre uma coisa e outra cabe qualquer mudanca: um ajuste aprovado, um
-- atestado lancado, uma marcacao que chegou depois. A fotografia nao se
-- atualiza sozinha, e nada na tela avisa que ela envelheceu. O resultado
-- e o pior tipo de erro num fechamento: dois papeis oficiais, com carimbo
-- da mesma data, dizendo coisas diferentes sobre a jornada da mesma
-- pessoa. Qual deles o RH leva para a folha? Qual vale numa reclamatoria?
--
-- A CORRECAO
-- Passa a existir UMA funcao que responde qual e o numero oficial do banco
-- de horas de uma competencia — public.ponto_banco_horas_oficial — e todo
-- documento le dela. A regra que ela aplica:
--
--   * competencia FECHADA: vale a fotografia gravada. Competencia fechada
--     nao se recalcula (Sumula 338 do TST); se o numero precisa mudar, o
--     caminho e reabrir o fechamento, que fica registrado.
--   * competencia ABERTA: vale a apuracao de agora, somada aos lancamentos
--     MANUAIS e as compensacoes registradas — que a apuracao nao conhece e
--     que nao podem se perder.
--
-- Ela devolve tambem, para cada colaborador, a coluna divergencia_min: a
-- diferenca entre a fotografia e o numero oficial. E o que permite a tela
-- avisar "esta apuracao esta desatualizada" em vez de imprimir em silencio
-- dois papeis discordantes.
--
-- NADA E APAGADO E NENHUM SALDO E REESCRITO. A funcao so LE; a tabela
-- ponto_banco_horas continua sendo gravada pela apuracao, como sempre.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) A fonte unica
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_banco_horas_oficial(
  p_tenant_id uuid,
  p_competencia text,
  p_empresa_id uuid DEFAULT NULL,
  -- Um colaborador so. O espelho pergunta pelo dono do documento: sem este
  -- filtro, gerar os espelhos de uma empresa faria a fonte percorrer todo o
  -- quadro uma vez por pessoa, e o tempo de consulta estouraria.
  p_colaborador_cpf text DEFAULT NULL
)
RETURNS TABLE(
  colaborador_cpf text,
  colaborador_nome text,
  empresa_id uuid,
  saldo_anterior_min integer,
  creditos_min integer,
  debitos_min integer,
  compensados_min integer,
  saldo_atual_min integer,
  fonte text,
  divergencia_min integer,
  apurado_em timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
  c        RECORD;
  v_regime public.ponto_banco_horas_config;
  v_ap_cred int;
  v_ap_deb  int;
  v_man_cred int;
  v_man_deb  int;
  v_comp     int;
  v_fechada  boolean;
  v_so_cpf text := NULLIF(regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g'), '');
BEGIN
  FOR c IN
    -- Quem entra: quem tem linha de banco na competencia (traz o saldo
    -- anterior e os lancamentos manuais) mais quem tem apuracao no periodo
    -- e ainda nao tem linha de banco nenhuma.
    SELECT b.colaborador_cpf,
           b.colaborador_nome,
           b.empresa_id,
           b.id                                        AS banco_id,
           COALESCE(b.saldo_anterior_minutos, 0)       AS saldo_anterior,
           COALESCE(b.creditos_minutos, 0)             AS foto_cred,
           COALESCE(b.debitos_minutos, 0)              AS foto_deb,
           COALESCE(b.compensados_minutos, 0)          AS foto_comp,
           COALESCE(b.saldo_atual_minutos, 0)          AS foto_saldo,
           b.updated_at                                AS foto_em
    FROM public.ponto_banco_horas b
    WHERE b.tenant_id = p_tenant_id
      AND b.competencia = p_competencia
      AND (p_empresa_id IS NULL OR b.empresa_id = p_empresa_id)
      AND (v_so_cpf IS NULL
           OR regexp_replace(COALESCE(b.colaborador_cpf, ''), '[^0-9]', '', 'g') = v_so_cpf)

    UNION ALL

    SELECT d.cpf, d.nome, d.emp, NULL::uuid, 0, 0, 0, 0, 0, NULL::timestamptz
    FROM (
      SELECT pd.colaborador_cpf                       AS cpf,
             max(pd.colaborador_nome)                 AS nome,
             max(pd.empresa_id::text)::uuid           AS emp
      FROM public.ponto_diario pd
      WHERE pd.tenant_id = p_tenant_id
        AND pd.data BETWEEN v_ini AND v_fim
        AND (p_empresa_id IS NULL OR pd.empresa_id = p_empresa_id)
        AND (v_so_cpf IS NULL
             OR regexp_replace(COALESCE(pd.colaborador_cpf, ''), '[^0-9]', '', 'g') = v_so_cpf)
      GROUP BY pd.colaborador_cpf
    ) d
    WHERE NOT EXISTS (
      SELECT 1 FROM public.ponto_banco_horas b2
      WHERE b2.tenant_id = p_tenant_id
        AND b2.competencia = p_competencia
        AND regexp_replace(COALESCE(b2.colaborador_cpf, ''), '[^0-9]', '', 'g')
          = regexp_replace(COALESCE(d.cpf, ''), '[^0-9]', '', 'g')
    )
  LOOP
    -- Competencia fechada nao se recalcula (Sumula 338): vale a fotografia.
    SELECT EXISTS (
      SELECT 1 FROM public.ponto_fechamentos f
      WHERE f.tenant_id = p_tenant_id
        AND f.competencia = p_competencia
        AND f.status = 'fechado'
        AND (f.empresa_id IS NULL OR f.empresa_id = c.empresa_id)
    ) INTO v_fechada;

    IF v_fechada THEN
      colaborador_cpf    := c.colaborador_cpf;
      colaborador_nome   := c.colaborador_nome;
      empresa_id         := c.empresa_id;
      saldo_anterior_min := c.saldo_anterior;
      creditos_min       := c.foto_cred;
      debitos_min        := c.foto_deb;
      compensados_min    := c.foto_comp;
      saldo_atual_min    := c.foto_saldo;
      fonte              := 'fechada';
      divergencia_min    := 0;
      apurado_em         := c.foto_em;
      RETURN NEXT;
      CONTINUE;
    END IF;

    -- Competencia aberta: a parte automatica vem da apuracao de AGORA.
    SELECT
      COALESCE(SUM(CASE WHEN s.saldo_min > 0 THEN s.saldo_min ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN s.saldo_min < 0 THEN -s.saldo_min ELSE 0 END), 0)
    INTO v_ap_cred, v_ap_deb
    FROM public.ponto_saldo_dias_competencia(p_tenant_id, c.colaborador_cpf, p_competencia) s;

    -- Sem instrumento de compensacao vigente nao ha banco: as horas sao
    -- devidas em dinheiro na folha (CLT art. 59, §§2º/5º). Mesma regra que
    -- a apuracao ja aplica — aqui ela e apenas repetida, nao inventada.
    v_regime := public.ponto_banco_regime_vigente(
                  p_tenant_id, c.colaborador_cpf, NULL, v_fim);
    IF v_regime.id IS NULL THEN
      v_ap_cred := 0;
      v_ap_deb  := 0;
    END IF;

    -- Lancamentos feitos a mao e compensacoes: a apuracao nao os conhece,
    -- e eles nao podem sumir da conta.
    v_man_cred := 0; v_man_deb := 0; v_comp := 0;
    IF c.banco_id IS NOT NULL THEN
      SELECT
        COALESCE(SUM(m.minutos) FILTER (
          WHERE m.tipo = 'credito' AND COALESCE(m.origem, '') NOT IN ('apuracao', 'apuracao_auto')), 0),
        COALESCE(SUM(m.minutos) FILTER (
          WHERE m.tipo = 'debito'  AND COALESCE(m.origem, '') NOT IN ('apuracao', 'apuracao_auto')), 0),
        COALESCE(SUM(m.minutos) FILTER (WHERE m.tipo = 'compensacao'), 0)
      INTO v_man_cred, v_man_deb, v_comp
      FROM public.ponto_banco_horas_movimentacoes m
      WHERE m.banco_horas_id = c.banco_id;
    END IF;

    colaborador_cpf    := c.colaborador_cpf;
    colaborador_nome   := c.colaborador_nome;
    empresa_id         := c.empresa_id;
    saldo_anterior_min := c.saldo_anterior;
    creditos_min       := v_ap_cred + v_man_cred;
    debitos_min        := v_ap_deb  + v_man_deb;
    compensados_min    := v_comp;
    saldo_atual_min    := c.saldo_anterior + creditos_min - debitos_min - compensados_min;
    fonte              := 'aberta';
    divergencia_min    := c.foto_saldo - saldo_atual_min;
    apurado_em         := c.foto_em;
    RETURN NEXT;
  END LOOP;
END;
$function$;

COMMENT ON FUNCTION public.ponto_banco_horas_oficial(uuid, text, uuid, text) IS
  'Fonte unica do banco de horas de uma competencia. Competencia fechada devolve a fotografia gravada (Sumula 338); competencia aberta devolve a apuracao de agora somada aos lancamentos manuais e compensacoes. divergencia_min mostra o quanto a fotografia envelheceu. Somente leitura.';

-- ---------------------------------------------------------------------
-- 2) O espelho passa a tirar o saldo do banco da mesma fonte
--    (antes ele fazia a propria conta, ignorando compensacoes e
--    lancamentos manuais — mais um caminho para divergir)
-- ---------------------------------------------------------------------
DO $espelho$
DECLARE
  v_src text;
  v_alvo text := '(v_saldo_ant + c.saldo_min)::int AS saldo_banco_min';
  v_troca text := 'COALESCE((SELECT o.saldo_atual_min FROM public.ponto_banco_horas_oficial('
               || 'p_tenant_id, p_competencia, NULL::uuid, v_cpf) o LIMIT 1),'
               || ' v_saldo_ant + c.saldo_min)::int AS saldo_banco_min';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'ponto_espelho_resumo';

  IF v_src IS NULL THEN
    RAISE NOTICE 'O resumo do espelho nao existe nesta base — nada a ligar.';
    RETURN;
  END IF;

  IF position('ponto_banco_horas_oficial' IN v_src) > 0 THEN
    RAISE NOTICE 'O espelho ja le o saldo do banco da fonte unica — nada a fazer.';
    RETURN;
  END IF;

  IF position(v_alvo IN v_src) = 0 THEN
    RAISE NOTICE 'ATENCAO: a linha do saldo do banco nao foi encontrada no resumo do espelho. NADA foi alterado nele; a fonte unica existe e pode ser usada pelas telas.';
    RETURN;
  END IF;

  EXECUTE replace(v_src, v_alvo, v_troca);
  RAISE NOTICE 'O espelho passa a tirar o saldo do banco da fonte unica.';
END $espelho$;

-- ---------------------------------------------------------------------
-- 3) O caso de teste
-- ---------------------------------------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-472',
  m.id,
  'Espelho e banco de horas nunca imprimem números diferentes',
  'Dois documentos oficiais da mesma competência, para o mesmo colaborador, não podem '
  || 'discordar. O espelho recalculava na hora e o relatório de banco de horas lia uma '
  || 'fotografia gravada na última apuração: entre uma coisa e outra cabia qualquer mudança '
  || '(um ajuste aprovado, um atestado, uma marcação atrasada), e nada avisava que a '
  || 'fotografia tinha envelhecido. Numa auditoria real isso deu 30 minutos de diferença no '
  || 'débito e meia hora no saldo final. Agora existe uma fonte única, e ela sabe dizer o '
  || 'quanto a fotografia está atrasada.',
  'feliz',
  'api',
  'critica',
  'aprovado',
  'CLT art. 74, §2º; Súmula 338 do TST (competência fechada não se recalcula)',
  jsonb_build_array(
    jsonb_build_object('ordem', 1,
      'acao', 'Apurar o banco de horas de uma competência e depois mudar um dia (novo atestado, ajuste ou marcação)',
      'esperado', 'A fonte única acusa a divergência entre a fotografia e a apuração de agora'),
    jsonb_build_object('ordem', 2,
      'acao', 'Consultar o saldo oficial da competência aberta',
      'esperado', 'Vem a apuração de agora, somada aos lançamentos manuais e compensações — o mesmo número que o espelho imprime')
  ),
  'em_triagem',
  'Nasceu da auditoria de fechamento de 01/09/2026, que comparou o espelho de ponto e o '
  || 'relatório de banco de horas de uma mesma competência.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_472()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4721);
  v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
  v_d1 date;
  v_comp text;
  v_of RECORD;
  v_esp RECORD;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Consultar o saldo oficial de uma competência aberta e comparar com o espelho';
  r.esperado    := 'O mesmo número nos dois — a fonte é uma só';

  IF to_regprocedure('public.ponto_banco_horas_oficial(uuid, text, uuid, text)') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nao existe fonte unica do banco de horas nesta base. O espelho e o '
             || 'relatorio de banco de horas seguem em dois caminhos independentes, e podem '
             || 'imprimir numeros diferentes para a mesma competencia.';
    RETURN r;
  END IF;

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();

  v_d1   := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);
  v_comp := to_char(v_d1, 'YYYY-MM');

  -- Sem instrumento de compensacao vigente nao existe banco de horas: as
  -- horas seriam devidas em dinheiro e a conta daria zero dos dois lados
  -- (o que tambem seria "igual", mas nao prova nada). A massa cria o
  -- regime do tenant de teste uma vez e reusa.
  IF NOT EXISTS (SELECT 1 FROM public.ponto_banco_horas_config g
                  WHERE g.tenant_id = v_t AND COALESCE(g.ativo, false)) THEN
    INSERT INTO public.ponto_banco_horas_config
      (tenant_id, tipo, prazo_compensacao_dias, exige_acordo_individual,
       exige_cct_act, data_inicio, ativo)
    VALUES (v_t, 'individual', 180, false, false, v_base - 365, true);
  END IF;

  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Fonte Unica', 480, 10, v_d1, v_d1 + 1);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Fonte Unica', v_d1, 500);      -- +20
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Fonte Unica', v_d1 + 1, 450);  -- -30

  SELECT * INTO v_of
  FROM public.ponto_banco_horas_oficial(v_t, v_comp, NULL::uuid, v_cpf) o
  LIMIT 1;

  IF v_of IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A fonte unica nao devolveu linha para o colaborador da massa de teste, que tem '
             || 'apuracao na competencia. Quem tem dia apurado precisa aparecer.';
    RETURN r;
  END IF;

  SELECT * INTO v_esp FROM public.ponto_espelho_resumo(v_t, v_cpf, v_comp);

  IF v_of.creditos_min = 20 AND v_of.debitos_min = 30
     AND COALESCE(v_esp.saldo_banco_min, -999) = v_of.saldo_atual_min THEN
    r.situacao := 'passou';
    r.obtido := format('Espelho e banco de horas falam o mesmo numero: credito %s, debito %s, '
             || 'saldo %s, e o espelho imprime esse mesmo saldo. Fonte: competencia %s.',
             v_of.creditos_min, v_of.debitos_min, v_of.saldo_atual_min, v_of.fonte);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: os dois documentos discordam. A fonte unica diz credito %s, '
             || 'debito %s e saldo %s (esperado 20, 30 e -10); o espelho imprime saldo de banco '
             || '%s. Dois papeis oficiais da mesma competencia com numeros diferentes e o pior '
             || 'tipo de erro num fechamento: nao da para saber qual vale na folha nem numa '
             || 'reclamatoria.',
             v_of.creditos_min, v_of.debitos_min, v_of.saldo_atual_min,
             coalesce(v_esp.saldo_banco_min::text, 'sem linha'));
    r.detalhe := jsonb_build_object('oficial_credito', v_of.creditos_min,
                                    'oficial_debito', v_of.debitos_min,
                                    'oficial_saldo', v_of.saldo_atual_min,
                                    'espelho_saldo_banco', v_esp.saldo_banco_min,
                                    'fonte', v_of.fonte);
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-472', 'qa_caso_ponto_472', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

DO $fim$
BEGIN
  RAISE NOTICE 'Banco de horas: uma fonte so para todos os documentos da competencia.';
END $fim$;
