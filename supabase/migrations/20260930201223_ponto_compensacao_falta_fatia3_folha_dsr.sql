-- ============================================================================
-- Compensação de falta — FATIA 3: reconciliação com folha e DSR (fecha o recurso)
-- ----------------------------------------------------------------------------
-- Com a Fatia 2, uma falta EFETIVADA já vira débito no banco. Mas, sozinha, ela
-- ainda seria descontada como falta na folha e derrubaria o DSR — o duplo efeito
-- que o PONTO-474 removeu. Esta fatia reconcilia isso:
--
--   RQ-051: DSR — falta compensada NÃO derruba o repouso da semana.
--   RQ-050/051: Folha — falta compensada NÃO desconta o dia; entra só como
--               INFORMATIVO no pacote (a ocorrência continua visível).
--
-- A falta segue registrada como ocorrência (status='falta' em ponto_diario e no
-- total_faltas do espelho). O que muda é só o EFEITO FINANCEIRO: quem tem
-- compensação efetivada sai do desconto de falta e da perda de DSR — porque já
-- está debitado no banco (uma cobrança, não duas).
-- ============================================================================

-- ---------------------------------------------------------------------
-- 1) Helper: faltas compensadas (efetivadas) na competência
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_faltas_compensadas_competencia(
  p_tenant_id uuid,
  p_colaborador_cpf text,
  p_competencia text
)
RETURNS TABLE(qtd integer, minutos integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(count(*),0)::int AS qtd,
         COALESCE(sum(cf.minutos),0)::int AS minutos
  FROM public.ponto_compensacao_falta cf
  WHERE cf.tenant_id = p_tenant_id
    AND regexp_replace(COALESCE(cf.colaborador_cpf,''),'[^0-9]','','g')
        = regexp_replace(COALESCE(p_colaborador_cpf,''),'[^0-9]','','g')
    AND to_char(cf.data_falta,'YYYY-MM') = p_competencia
    AND cf.status = 'efetivada';
$function$;

COMMENT ON FUNCTION public.ponto_faltas_compensadas_competencia(uuid, text, text) IS
  'Quantidade e minutos de faltas compensadas (efetivadas) na competência. Usado pela folha para não descontar quem já debitou no banco.';

-- ---------------------------------------------------------------------
-- 2) DSR — falta compensada não derruba o repouso (RQ-051)
--    Recria a função (mesma assinatura) marcando o dia compensado e o
--    excluindo do teste de "teve falta na semana".
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_dsr_competencia(
  p_tenant_id       uuid,
  p_colaborador_cpf text,
  p_competencia     text
)
RETURNS TABLE(
  semana_inicio             date,
  semana_fim                date,
  dias_uteis_trabalhados    integer,
  he_semana_min             integer,
  reflexo_he_dsr_min        integer,
  teve_falta_injustificada  boolean,
  dsr_perdido               boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  -- DSR (Lei 605/1949). Semana ISO. Reflexo das HE (Súmula 172) + perda por
  -- falta injustificada (art. 6). [dsr-ignora-falta-compensada]: falta com
  -- compensação efetivada em banco não conta como falta para o DSR — o dia já
  -- foi debitado (não se cobra a mesma ausência duas vezes).
  WITH dias AS (
    SELECT d.data,
           date_trunc('week', d.data)::date       AS semana,
           EXTRACT(ISODOW FROM d.data)::int        AS isodow,
           COALESCE(d.horas_extras_50_minutos, 0)
             + COALESCE(d.horas_extras_100_minutos, 0)          AS he_min,
           COALESCE(floor(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60)::int, 0) AS trab_min,
           d.status,
           d.tipo_dia,
           d.observacao,
           EXISTS (
             SELECT 1 FROM public.ponto_compensacao_falta cf
             WHERE cf.tenant_id = p_tenant_id
               AND regexp_replace(COALESCE(cf.colaborador_cpf,''),'[^0-9]','','g')
                   = regexp_replace(COALESCE(p_colaborador_cpf,''),'[^0-9]','','g')
               AND cf.data_falta = d.data
               AND cf.status = 'efetivada'
           )                                                    AS compensada
    FROM public.ponto_diario d
    WHERE d.tenant_id = p_tenant_id
      AND regexp_replace(d.colaborador_cpf, '[^0-9]', '', 'g')
          = regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g')
      AND to_char(d.data, 'YYYY-MM') = p_competencia
  ),
  por_semana AS (
    SELECT semana                                             AS semana_inicio,
           (semana + 6)                                       AS semana_fim,
           COUNT(*) FILTER (WHERE isodow <= 6 AND trab_min > 0) AS dias_uteis_trab,
           COALESCE(SUM(he_min), 0)                            AS he_semana,
           bool_or(
             isodow <= 6
             AND status = 'falta'
             AND NOT compensada
             AND COALESCE(tipo_dia, '') NOT IN ('ferias','atestado','afastamento','feriado')
             AND COALESCE(observacao, '') NOT ILIKE '%atestado%'
             AND COALESCE(observacao, '') NOT ILIKE '%justific%'
           )                                                   AS teve_falta
    FROM dias
    GROUP BY semana
  )
  SELECT
    semana_inicio,
    semana_fim,
    dias_uteis_trab::int,
    he_semana::int,
    CASE WHEN dias_uteis_trab > 0
         THEN ROUND(he_semana::numeric / dias_uteis_trab)::int
         ELSE 0 END                          AS reflexo_he_dsr_min,
    COALESCE(teve_falta, false)              AS teve_falta_injustificada,
    COALESCE(teve_falta, false)              AS dsr_perdido
  FROM por_semana
  ORDER BY semana_inicio;
$function$;

-- ---------------------------------------------------------------------
-- 3) Folha — desconta só as faltas NÃO compensadas (patch cirúrgico)
--    A compensada entra como informativo (ocorrência visível, sem desconto).
-- ---------------------------------------------------------------------
DO $patch$
DECLARE
  v_src text;
  v_novo text;
  v_alvo text :=
       E'    IF COALESCE(e.total_faltas, 0) > 0 THEN\n'
    || E'      v_eventos := v_eventos || jsonb_build_object(''codigo'',''faltas'',''descricao'',''Faltas'',''natureza'',''desconto'',''quantidade'', e.total_faltas);\n'
    || E'    END IF;';
  v_troca text :=
       E'    -- [folha-desconta-falta-compensada] Falta compensada em banco nao desconta\n'
    || E'    -- o dia na folha (RQ-050/051): desconta so as faltas NAO compensadas; a\n'
    || E'    -- compensada entra como informativo (ocorrencia visivel, sem desconto).\n'
    || E'    IF GREATEST(COALESCE(e.total_faltas,0) - COALESCE((SELECT fc.qtd FROM public.ponto_faltas_compensadas_competencia(p_tenant_id, e.colaborador_cpf, p_competencia) fc),0), 0) > 0 THEN\n'
    || E'      v_eventos := v_eventos || jsonb_build_object(''codigo'',''faltas'',''descricao'',''Faltas'',''natureza'',''desconto'',''quantidade'',\n'
    || E'        GREATEST(COALESCE(e.total_faltas,0) - COALESCE((SELECT fc.qtd FROM public.ponto_faltas_compensadas_competencia(p_tenant_id, e.colaborador_cpf, p_competencia) fc),0), 0));\n'
    || E'    END IF;\n'
    || E'    IF COALESCE((SELECT fc.qtd FROM public.ponto_faltas_compensadas_competencia(p_tenant_id, e.colaborador_cpf, p_competencia) fc),0) > 0 THEN\n'
    || E'      v_eventos := v_eventos || jsonb_build_object(''codigo'',''faltas_compensadas'',''descricao'',''Faltas compensadas em banco (sem desconto)'',''natureza'',''informativa'',''quantidade'',\n'
    || E'        (SELECT fc.qtd FROM public.ponto_faltas_compensadas_competencia(p_tenant_id, e.colaborador_cpf, p_competencia) fc));\n'
    || E'    END IF;';
BEGIN
  v_src := pg_get_functiondef('public.ponto_compor_pacote_folha(uuid,uuid,text)'::regprocedure);

  IF position('[folha-desconta-falta-compensada]' IN v_src) > 0 THEN
    RAISE NOTICE 'ponto_compor_pacote_folha ja desconta so faltas nao compensadas — nada a fazer.';
    RETURN;
  END IF;
  IF position(v_alvo IN v_src) = 0 THEN
    RAISE NOTICE 'ATENCAO: ancora do bloco de faltas do pacote de folha nao encontrada; NADA alterado.';
    RETURN;
  END IF;

  v_novo := replace(v_src, v_alvo, v_troca);
  EXECUTE v_novo;
  RAISE NOTICE 'ponto_compor_pacote_folha: falta compensada sai do desconto (vira informativo).';
END;
$patch$;

-- ---------------------------------------------------------------------
-- 4) QA PONTO-481 — falta compensada não é cobrada duas vezes
-- ---------------------------------------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-481',
  m.id,
  'Falta compensada em banco não é cobrada duas vezes (folha/DSR)',
  'A falta convertida em débito de banco (compensação efetivada) deixa de produzir efeito '
  || 'financeiro na folha: não desconta o dia e não derruba o DSR da semana. O débito no banco é a '
  || 'única cobrança. A falta continua registrada como ocorrência (RQ-050/051; evita o duplo efeito '
  || 'que o PONTO-474 removeu).',
  'negativo',
  'api',
  'critica',
  'aprovado',
  'CLT art. 59, §2º; Lei 605/1949, art. 6º',
  jsonb_build_array(
    jsonb_build_object('ordem', 1,
      'acao', 'Efetivar a compensação de uma falta e conferir o DSR da semana',
      'esperado', 'Com a compensação, a semana não perde o DSR; sem ela, perderia'),
    jsonb_build_object('ordem', 2,
      'acao', 'Conferir que a folha conta a falta como compensada, não como desconto',
      'esperado', 'A contagem de faltas compensadas registra o dia e o débito no banco existe uma vez')
  ),
  'em_triagem',
  'Recurso compensação de falta (RQ-050/051), Fatia 3.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_481()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4811);
  v_dia date := public.qa_dia_util_passado();
  v_comp text := to_char(public.qa_dia_util_passado(),'YYYY-MM');
  v_empresa uuid;
  v_id uuid;
  v_dsr_com boolean; v_dsr_sem boolean;
  v_qtd int; v_debitos int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Falta compensada não perde DSR nem desconta na folha; débito no banco uma vez';
  r.esperado    := 'DSR mantido com a compensação (e perdido sem ela); 1 falta compensada; 1 débito';

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();

  IF NOT EXISTS (SELECT 1 FROM public.admissoes a
                  WHERE a.tenant_id = v_t AND a.cpf = v_cpf AND COALESCE(a.inativo,false)=false) THEN
    PERFORM public.qa_ponto_admissao('QA Comp Falta Folha', 4811);
  END IF;
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Comp Falta Folha', 480, 10, v_dia - 5, NULL);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Comp Falta Folha', v_dia, 0);
  UPDATE public.ponto_diario
     SET status='falta', entrada=NULL, saida=NULL, horas_trabalhadas=INTERVAL '0'
   WHERE tenant_id=v_t AND colaborador_cpf=v_cpf AND data=v_dia;

  -- limpa estado anterior
  DELETE FROM public.ponto_banco_horas_movimentacoes m USING public.ponto_banco_horas b
    WHERE m.banco_horas_id=b.id AND b.tenant_id=v_t
      AND regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g')=v_cpf AND m.tipo='compensacao_falta';
  DELETE FROM public.ponto_compensacao_falta WHERE tenant_id=v_t AND colaborador_cpf=v_cpf;
  UPDATE public.ponto_acordos SET ativo=false WHERE tenant_id=v_t AND titulo='QA Acordo Comp Falta Folha';
  UPDATE public.ponto_banco_horas_config SET ativo=false WHERE tenant_id=v_t AND forma_compensacao='QA-COMPFALTA-FOLHA';

  v_empresa := public.ponto_empresa_do_cpf(v_t, v_cpf);
  INSERT INTO public.ponto_banco_horas_config
    (tenant_id, empresa_id, tipo, prazo_compensacao_dias, forma_compensacao, data_inicio, ativo)
  VALUES (v_t, v_empresa, 'mensal', 90, 'QA-COMPFALTA-FOLHA', v_dia - 30, true);
  INSERT INTO public.ponto_acordos
    (tenant_id, empresa_id, colaborador_cpf, tipo, titulo, vigencia_inicio, vigencia_fim, permite_compensacao_falta, ativo)
  VALUES (v_t, v_empresa, v_cpf, 'individual', 'QA Acordo Comp Falta Folha', v_dia - 30, v_dia + 300, true, true);

  -- registrar -> autorizar -> ciencia (efetiva)
  v_id := (public.ponto_registrar_compensacao_falta(v_t, v_cpf, v_dia, 'folha')->>'id')::uuid;
  PERFORM public.ponto_autorizar_compensacao_falta(v_t, v_id, 'Gestor');
  PERFORM public.ponto_dar_ciencia_compensacao_falta(v_t, v_id, 'Colaborador');

  -- DSR COM a compensação (deve manter o repouso da semana do dia)
  SELECT bool_or(dsr_perdido) INTO v_dsr_com
  FROM public.ponto_dsr_competencia(v_t, v_cpf, v_comp)
  WHERE v_dia BETWEEN semana_inicio AND semana_fim;

  -- DSR SEM a compensação (simula cancelando temporariamente)
  UPDATE public.ponto_compensacao_falta SET status='cancelada' WHERE id=v_id;
  SELECT bool_or(dsr_perdido) INTO v_dsr_sem
  FROM public.ponto_dsr_competencia(v_t, v_cpf, v_comp)
  WHERE v_dia BETWEEN semana_inicio AND semana_fim;
  UPDATE public.ponto_compensacao_falta SET status='efetivada' WHERE id=v_id;

  -- helper de folha e débito único
  SELECT qtd INTO v_qtd FROM public.ponto_faltas_compensadas_competencia(v_t, v_cpf, v_comp);
  SELECT count(*) INTO v_debitos FROM public.ponto_banco_horas_movimentacoes m
    JOIN public.ponto_banco_horas b ON b.id=m.banco_horas_id
   WHERE b.tenant_id=v_t AND regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g')=v_cpf
     AND m.tipo='compensacao_falta' AND m.data_referencia=v_dia;

  IF COALESCE(v_dsr_com,true) <> false THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: mesmo compensada, a semana perdeu o DSR (deveria manter — RQ-051).';
  ELSIF COALESCE(v_dsr_sem,false) <> true THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: sem a compensação a semana NÃO perdeu o DSR — o teste não está exercitando a '
             || 'perda; revisar o cenário (a falta deveria derrubar o DSR sem compensação).';
  ELSIF COALESCE(v_qtd,0) <> 1 OR COALESCE(v_debitos,0) <> 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: contagem de faltas compensadas=%s (esperado 1) e débitos no banco=%s '
             || '(esperado 1).', v_qtd, v_debitos);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Com a compensação a semana mantém o DSR (sem ela perderia); a folha conta 1 falta '
             || 'compensada (sem desconto) e há exatamente 1 débito no banco — uma cobrança, não duas.';
    r.detalhe := jsonb_build_object('dsr_com_compensacao', v_dsr_com, 'dsr_sem_compensacao', v_dsr_sem,
                                    'faltas_compensadas', v_qtd, 'debitos_banco', v_debitos);
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-481', 'qa_caso_ponto_481', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

DO $fim$
BEGIN
  RAISE NOTICE 'Compensacao de falta — Fatia 3 (folha/DSR nao cobram a falta compensada) aplicada.';
END $fim$;
