-- ============================================================================
-- ENTREGA — o espelho para de prometer 50% onde o credito e de 1 por 1
-- Alvo: a fonte unica do banco de horas (ganha uma coluna)
-- Caso: PONTO-475 (novo)
--
-- O QUE ESTE ARQUIVO CORRIGE
-- Na auditoria de fechamento de 01/09/2026, cada dia com sobra saia no
-- espelho rotulado assim:
--
--     Soma Banco Horas 50%
--
-- e creditava no banco exatamente os minutos trabalhados a mais. Um por um.
-- O "50%" nao entrava em conta nenhuma — era so a palavra.
--
-- Os dois numeros existem na lei, mas em caminhos DIFERENTES (CLT art. 59):
--   * hora extra PAGA sai na folha com adicional de no minimo 50% (§1º);
--   * hora COMPENSADA no banco e trocada na exata medida, uma por uma (§2º).
-- Escrever "50%" ao lado de um credito de 1 por 1 e prometer no documento o
-- que a conta nao faz — e e o documento que o trabalhador assina.
--
-- Para o espelho saber em qual dos dois casos esta, a fonte unica do banco de
-- horas passa a informar se ha instrumento de compensacao vigente
-- (tem_regime). Ela ja consultava isso para zerar o banco quando nao ha
-- instrumento; agora devolve a informacao em vez de guarda-la.
--
-- NENHUM NUMERO MUDA. O credito ja era de 1 por 1 e continua sendo. Nenhum
-- dado e alterado ou apagado: o arquivo so recria uma funcao de LEITURA
-- (criada nesta mesma leva de correcoes) com uma coluna a mais.
--
-- ATENCAO: a troca do rotulo em si acontece na TELA — o dia passa a sair como
-- "Soma Banco Horas (1:1)" com banco vigente, ou "Hora extra 50%" (100% em
-- domingo e feriado, Sumula 146 do TST) quando nao ha banco e as horas serao
-- pagas. Isso chega com o Publicar no Lovable; este arquivo prepara o banco.
--
-- Idempotente. PRE-REQUISITO: a bancada de testes (tabelas qa_*) instalada e
-- a fonte unica ja entregue (docs/script_ponto_banco_horas_fonte_unica.sql).
-- ============================================================================

SET lock_timeout = '10s';

DROP FUNCTION IF EXISTS public.ponto_banco_horas_oficial(uuid, text, uuid, text);

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
  apurado_em timestamptz,
  -- Ha instrumento de compensacao vigente? Com ele, a sobra vai para o
  -- banco e vale 1 por 1 (CLT art. 59, §2º). Sem ele, nao ha banco: as
  -- horas sao devidas em dinheiro, com adicional (art. 59, §1º). E o que
  -- decide o rotulo que o espelho imprime no dia.
  tem_regime boolean
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
    -- O instrumento de compensacao decide se existe banco para este vinculo.
    v_regime := public.ponto_banco_regime_vigente(
                  p_tenant_id, c.colaborador_cpf, NULL, v_fim);
    tem_regime := (v_regime.id IS NOT NULL);

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
    -- O credito e de 1 por 1 — a hora compensada e trocada na exata medida
    -- (CLT art. 59, §2º). O adicional de 50% pertence a hora PAGA (§1º), e
    -- por isso nao aparece em lugar nenhum desta conta.
    SELECT
      COALESCE(SUM(CASE WHEN s.saldo_min > 0 THEN s.saldo_min ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN s.saldo_min < 0 THEN -s.saldo_min ELSE 0 END), 0)
    INTO v_ap_cred, v_ap_deb
    FROM public.ponto_saldo_dias_competencia(p_tenant_id, c.colaborador_cpf, p_competencia) s;

    -- Sem instrumento vigente nao ha banco: as horas sao devidas em dinheiro
    -- na folha (CLT art. 59, §§2º/5º).
    IF NOT tem_regime THEN
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
  'Fonte unica do banco de horas de uma competencia. Competencia fechada devolve a fotografia gravada (Sumula 338); competencia aberta devolve a apuracao de agora somada aos lancamentos manuais e compensacoes. O credito e de 1 por 1 (CLT art. 59, §2º) — o adicional de 50% pertence a hora PAGA (§1º). tem_regime diz se existe instrumento de compensacao vigente; divergencia_min mostra o quanto a fotografia envelheceu. Somente leitura.';

-- ---------------------------------------------------------------------
-- 2) O caso de teste
-- ---------------------------------------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-475',
  m.id,
  'Hora que vai para o banco vale 1 por 1 — e o documento diz isso',
  'O espelho rotulava cada dia com sobra como "Soma Banco Horas 50%" e creditava, no banco, '
  || 'exatamente os minutos trabalhados a mais: um por um. O percentual não entrava em conta '
  || 'nenhuma. Os dois números existem na lei, mas em caminhos diferentes (CLT art. 59): a hora '
  || 'extra PAGA sai na folha com adicional de no mínimo 50% (§1º); a hora COMPENSADA no banco é '
  || 'trocada na exata medida, uma por uma (§2º). Escrever 50% ao lado de um crédito de 1 por 1 é '
  || 'prometer no documento o que a conta não faz — e é o documento que o trabalhador assina.',
  'feliz',
  'api',
  'critica',
  'aprovado',
  'CLT art. 59, §1º e §2º; Súmula 146 do TST (domingo e feriado a 100%)',
  jsonb_build_array(
    jsonb_build_object('ordem', 1,
      'acao', 'Apurar um dia com 60 minutos de sobra, com regime de compensação vigente',
      'esperado', 'O banco credita 60 minutos — nem 90, nem 30: um por um'),
    jsonb_build_object('ordem', 2,
      'acao', 'Consultar se a competência tem regime de compensação vigente',
      'esperado', 'A fonte única informa isso, para o espelho escrever "1:1" ou o percentual da hora paga — cada um no seu caso')
  ),
  'em_triagem',
  'Nasceu da auditoria de fechamento de 01/09/2026 feita por especialista em DP. A troca do '
  || 'rótulo em si acontece na tela; este caso guarda a regra de cálculo que o rótulo tem de '
  || 'refletir, e a informação que permite escrever o rótulo certo.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_475()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4751);
  v_base date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
  v_d1 date;
  v_comp text;
  v_of RECORD;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Apurar um dia com 60 minutos de sobra e conferir o crédito no banco';
  r.esperado    := '60 minutos creditados — a hora compensada é trocada na exata medida';

  IF to_regprocedure('public.ponto_banco_horas_oficial(uuid, text, uuid, text)') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nao existe fonte unica do banco de horas nesta base.';
    RETURN r;
  END IF;

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();

  v_d1   := v_base + ((8 - EXTRACT(ISODOW FROM v_base)::int) % 7);  -- segunda-feira
  v_comp := to_char(v_d1, 'YYYY-MM');

  IF NOT EXISTS (SELECT 1 FROM public.ponto_banco_horas_config g
                  WHERE g.tenant_id = v_t AND COALESCE(g.ativo, false)) THEN
    INSERT INTO public.ponto_banco_horas_config
      (tenant_id, tipo, prazo_compensacao_dias, exige_acordo_individual,
       exige_cct_act, data_inicio, ativo)
    VALUES (v_t, 'individual', 180, false, false, v_base - 365, true);
  END IF;

  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Credito Um Por Um', 480, 10, v_d1, v_d1);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Credito Um Por Um', v_d1, 540);  -- +60

  SELECT * INTO v_of
  FROM public.ponto_banco_horas_oficial(v_t, v_comp, NULL::uuid, v_cpf) o
  LIMIT 1;

  IF v_of IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A fonte unica nao devolveu linha para o colaborador da massa de teste.';
    RETURN r;
  END IF;

  IF v_of.creditos_min = 60 AND v_of.tem_regime THEN
    r.situacao := 'passou';
    r.obtido := 'Os 60 minutos de sobra creditaram 60 minutos no banco — um por um, como manda '
             || 'o art. 59, §2º. E a fonte informa que ha regime vigente, entao o espelho sabe '
             || 'escrever "1:1" em vez de um percentual que nao existe nesta conta.';
  ELSIF v_of.creditos_min = 90 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: os 60 minutos de sobra viraram 90 no banco — o adicional de 50% foi '
             || 'aplicado a uma hora COMPENSADA. O acrescimo pertence a hora PAGA (CLT art. 59, '
             || '§1º); a hora compensada e trocada na exata medida (§2º).';
    r.detalhe := jsonb_build_object('creditos_min', v_of.creditos_min, 'esperado', 60);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Credito inesperado: %s minutos (esperado 60), regime vigente: %s '
             || '(esperado sim). Sem saber se ha regime, o documento nao consegue distinguir a '
             || 'hora que vai para o banco (1 por 1) da hora que sera paga (com adicional), e '
             || 'volta a imprimir um percentual onde ele nao vale.',
             v_of.creditos_min, coalesce(v_of.tem_regime::text, 'desconhecido'));
    r.detalhe := jsonb_build_object('creditos_min', v_of.creditos_min,
                                    'tem_regime', v_of.tem_regime);
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-475', 'qa_caso_ponto_475', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;


-- ============================================================================
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: as duas linhas com OK.
-- ============================================================================
SELECT 1 AS ordem,
       'fonte unica informa o regime'::text AS o_que,
       CASE WHEN EXISTS (
              SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'ponto_banco_horas_oficial'
                AND pg_get_function_result(p.oid) ILIKE '%tem_regime%')
            THEN 'a coluna tem_regime existe'
            ELSE 'a coluna tem_regime nao existe' END AS detalhe,
       CASE WHEN EXISTS (
              SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'ponto_banco_horas_oficial'
                AND pg_get_function_result(p.oid) ILIKE '%tem_regime%')
            THEN 'OK'
            ELSE 'PENDENTE: rode antes o script da fonte unica do banco de horas' END AS erro_tecnico
UNION ALL
SELECT 2,
       'caso de teste PONTO-475',
       (SELECT count(*)::text FROM public.qa_casos_teste WHERE codigo = 'PONTO-475')
         || ' documentado; '
         || (SELECT count(*)::text FROM public.qa_implementacoes
              WHERE codigo = 'PONTO-475' AND ativo)
         || ' com rotina ativa',
       CASE WHEN (SELECT count(*) FROM public.qa_casos_teste WHERE codigo = 'PONTO-475') = 1
            THEN 'OK' ELSE 'PENDENTE: caso de teste faltando' END
ORDER BY ordem;
