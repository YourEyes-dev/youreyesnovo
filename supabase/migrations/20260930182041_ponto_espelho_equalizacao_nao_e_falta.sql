-- ============================================================================
-- Ponto — sábado de equalização não conta como FALTA no espelho-resumo
-- ----------------------------------------------------------------------------
-- Contexto: escalas com "Equalização mensal (sábado variável)" fecham a carga
-- mensal num sábado. Quando esse sábado NÃO é trabalhado, o motor já o trata
-- como DÉBITO do banco de horas (compensação de jornada, CLT art. 59, §2º):
-- ponto_saldo_dias marca o dia com equalizacao=true e saldo negativo.
--
-- O espelho-resumo (ponto_espelho_resumo), porém, contava esse mesmo dia como
-- FALTA (o filtro de total_faltas só olhava jornada>0 e trabalhado=0). Efeito
-- duplo: o dia entrava no banco como débito E aparecia como ausência para a
-- folha — a mesma hora cobrada duas vezes, e ainda com risco de perder o DSR
-- da semana. É o mesmo princípio do PONTO-421 (folga compensatória não vira
-- falta) e do PONTO-474 (não descontar a mesma coisa duas vezes).
--
-- Correção: o filtro de total_faltas passa a excluir os dias de equalização
-- (equalizacao=true). O débito no banco continua intacto (não mexemos em
-- saldo/débitos) — só paramos de tipificar o dia como falta de folha.
--
-- Aplica-se também a ponto_espelho_resumo_empresa, que apenas delega para
-- ponto_espelho_resumo (uma correção, duas telas).
-- ============================================================================

-- ---------------------------------------------------------------------
-- 1) Correção cirúrgica e idempotente do filtro de faltas
-- ---------------------------------------------------------------------
DO $patch$
DECLARE
  v_src text;
  v_new text;
  v_anchor text := 'WHERE NOT d.protegido AND d.jornada_min > 0 AND d.trabalhado_min = 0';
  v_repl  text := 'WHERE NOT d.protegido AND d.jornada_min > 0 AND d.trabalhado_min = 0'
                 || ' AND NOT COALESCE(d.equalizacao, false) /* [falta-nao-conta-equalizacao] */';
BEGIN
  v_src := pg_get_functiondef('public.ponto_espelho_resumo(uuid,text,text)'::regprocedure);

  IF position('[falta-nao-conta-equalizacao]' IN v_src) > 0 THEN
    RAISE NOTICE 'ponto_espelho_resumo: correcao [falta-nao-conta-equalizacao] ja aplicada; nada a fazer.';
    RETURN;
  END IF;

  IF position(v_anchor IN v_src) = 0 THEN
    RAISE NOTICE 'ponto_espelho_resumo: ancora do filtro de faltas NAO encontrada; revisar manualmente.';
    RETURN;
  END IF;

  v_new := replace(v_src, v_anchor, v_repl);
  EXECUTE v_new;
  RAISE NOTICE 'ponto_espelho_resumo: correcao [falta-nao-conta-equalizacao] aplicada.';
END;
$patch$;

-- ---------------------------------------------------------------------
-- 2) PONTO-478 — sábado de equalização não trabalhado é débito, não falta
-- ---------------------------------------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-478',
  m.id,
  'Sábado de equalização não trabalhado é débito de banco, não falta',
  'A escala de equalização mensal fecha a carga do mês num sábado. Quando esse '
  || 'sábado não é trabalhado, o dia compensa jornada pelo banco de horas '
  || '(CLT art. 59, §2º) — sai como DÉBITO do saldo. Contá-lo também como falta '
  || 'no espelho cobra a mesma hora duas vezes (banco + folha) e ainda ameaça o '
  || 'DSR da semana. O espelho-resumo precisa manter o débito e NÃO tipificar o '
  || 'dia como ausência — mesmo princípio do PONTO-421 e do PONTO-474.',
  'negativo',
  'api',
  'critica',
  'aprovado',
  'CLT art. 59, §2º; Lei 605/1949, art. 6º',
  jsonb_build_array(
    jsonb_build_object('ordem', 1,
      'acao', 'Apurar uma competência de escala com equalização mensal em que o sábado de fechamento não foi trabalhado',
      'esperado', 'O dia aparece como equalização com saldo negativo (débito no banco)'),
    jsonb_build_object('ordem', 2,
      'acao', 'Conferir o espelho-resumo da competência',
      'esperado', 'O débito da equalização está nos débitos, mas o dia NÃO é contado em total_faltas')
  ),
  'em_triagem',
  'Nasceu do caso da Kailaine (sábado de equalização 19/09), auditoria de set/2026.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

-- ---------------------------------------------------------------------
-- 3) Rotina de execução (somente leitura sobre seed de sandbox)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_478()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4781);
  v_ini date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;  -- mês fechado
  v_fim date := (date_trunc('month', CURRENT_DATE) - INTERVAL '1 day')::date;
  v_comp text := to_char(v_ini, 'YYYY-MM');
  v_d date;
  v_eq_dias int;         -- dias de equalização não trabalhados (jornada>0, trab=0)
  v_deb_eq int;          -- débito (min) originado na equalização
  v_faltas_esperado int; -- faltas reais: jornada>0, trab=0, não protegido, NÃO equalização
  v_resumo_faltas int;   -- total_faltas do espelho
  v_resumo_deb int;      -- total_debitos_min do espelho
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Apurar um mês de equalização com o sábado de fechamento não trabalhado';
  r.esperado    := 'Sábado vira débito de banco e o espelho NÃO o conta como falta';

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();

  -- Vínculo + escala de equalização mensal (carga contratada acima da real)
  IF NOT EXISTS (SELECT 1 FROM public.admissoes a
                  WHERE a.tenant_id = v_t AND a.cpf = v_cpf
                    AND COALESCE(a.inativo, false) = false) THEN
    PERFORM public.qa_ponto_admissao('QA Equalizacao Sabado', 4781, NULL, v_ini - 30);
  END IF;

  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Equalizacao Sabado', 518, 10, v_ini, NULL);
  UPDATE public.ponto_escalas e
     SET equalizacao_mensal_ativa = true,
         carga_semanal_contratada_min = 2640
   WHERE e.tenant_id = v_t
     AND e.id IN (SELECT a.escala_id FROM public.ponto_escala_atribuicoes a
                   WHERE a.tenant_id = v_t
                     AND regexp_replace(COALESCE(a.colaborador_cpf,''),'[^0-9]','','g') = v_cpf
                     AND COALESCE(a.ativa, true));

  -- Trabalha todos os dias úteis (seg–sex); não registra nenhum sábado
  FOR v_d IN
    SELECT g::date FROM generate_series(v_ini, v_fim, INTERVAL '1 day') g
    WHERE EXTRACT(ISODOW FROM g) BETWEEN 1 AND 5
  LOOP
    PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Equalizacao Sabado', v_d, 518);
  END LOOP;

  -- Fotografia dos dias apurados
  SELECT
    count(*) FILTER (WHERE s.equalizacao AND s.jornada_min > 0 AND s.trabalhado_min = 0),
    COALESCE(-SUM(s.saldo_min) FILTER (WHERE s.equalizacao AND s.saldo_min < 0), 0),
    count(*) FILTER (WHERE NOT s.protegido AND s.jornada_min > 0 AND s.trabalhado_min = 0
                       AND NOT COALESCE(s.equalizacao, false))
    INTO v_eq_dias, v_deb_eq, v_faltas_esperado
  FROM public.ponto_saldo_dias_competencia(v_t, v_cpf, v_comp) s;

  SELECT e.total_faltas, e.total_debitos_min
    INTO v_resumo_faltas, v_resumo_deb
  FROM public.ponto_espelho_resumo(v_t, v_cpf, v_comp) e;

  IF COALESCE(v_eq_dias, 0) = 0 OR COALESCE(v_deb_eq, 0) = 0 THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'O cenário não materializou um sábado de equalização não trabalhado com débito '
             || '(a escala não gerou o dia de equalização) — nada a conferir nesta corrida.';
    r.detalhe := jsonb_build_object('eq_dias', v_eq_dias, 'debito_eq_min', v_deb_eq, 'competencia', v_comp);
    RETURN r;
  ELSIF v_resumo_faltas = v_faltas_esperado AND v_resumo_deb >= v_deb_eq THEN
    r.situacao := 'passou';
    r.obtido := format('O sábado de equalização virou débito de %s min no banco e ficou FORA das '
             || 'faltas: o espelho conta %s falta(s) (só as ausências reais), sem somar o(s) %s dia(s) '
             || 'de equalização.', v_deb_eq, v_resumo_faltas, v_eq_dias);
    r.detalhe := jsonb_build_object('faltas_espelho', v_resumo_faltas, 'faltas_esperado', v_faltas_esperado,
                                    'eq_dias', v_eq_dias, 'debito_eq_min', v_deb_eq,
                                    'debitos_espelho', v_resumo_deb, 'competencia', v_comp);
  ELSIF v_resumo_faltas = v_faltas_esperado + v_eq_dias THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o espelho contou o sábado de equalização como FALTA (total_faltas=%s = '
             || '%s reais + %s de equalização). O dia já debita o banco (%s min); contá-lo como '
             || 'ausência cobra a mesma hora duas vezes e ameaça o DSR. Excluir dias de equalização '
             || 'do total_faltas.', v_resumo_faltas, v_faltas_esperado, v_eq_dias, v_deb_eq);
    r.detalhe := jsonb_build_object('faltas_espelho', v_resumo_faltas, 'faltas_esperado', v_faltas_esperado,
                                    'eq_dias', v_eq_dias, 'debito_eq_min', v_deb_eq, 'competencia', v_comp);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Resultado inesperado: total_faltas=%s (esperado %s, com %s dia(s) de '
             || 'equalização à parte); débitos do espelho=%s (esperado ao menos %s da equalização).',
             v_resumo_faltas, v_faltas_esperado, v_eq_dias, v_resumo_deb, v_deb_eq);
    r.detalhe := jsonb_build_object('faltas_espelho', v_resumo_faltas, 'faltas_esperado', v_faltas_esperado,
                                    'eq_dias', v_eq_dias, 'debito_eq_min', v_deb_eq,
                                    'debitos_espelho', v_resumo_deb, 'competencia', v_comp);
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-478', 'qa_caso_ponto_478', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

DO $fim$
BEGIN
  RAISE NOTICE 'Espelho-resumo: sabado de equalizacao nao trabalhado sai das faltas (segue como debito de banco).';
END $fim$;
