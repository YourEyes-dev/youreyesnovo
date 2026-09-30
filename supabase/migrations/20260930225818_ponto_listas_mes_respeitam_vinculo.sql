-- ============================================================================
-- Ponto — listas do mês respeitam o vínculo (não trazem desligado após a data)
-- ----------------------------------------------------------------------------
-- ACHADO: as telas mensais (Apuração/Fechamento, Banco, e a nova Compensação
-- de Faltas) traziam colaboradores DESLIGADOS mesmo em meses posteriores à data
-- de desligamento. Duas camadas somavam o defeito:
--   1. A materialização diária gerava 'falta' em ponto_diario para todo
--      admitido com inativo=false, SEM teto por data_desligamento (o
--      desligamento não seta inativo) — o desligado ganhava falta todo dia útil,
--      indefinidamente.
--   2. As fontes das listas escolhiam o colaborador pela mera presença de linha
--      em ponto_diario/ponto_banco_horas no mês, SEM filtro de vínculo.
--
-- REGRA (a mesma da visão diária que já funciona): o colaborador aparece no mês
-- só até a data de desligamento; mês inteiramente após o desligamento, não
-- aparece. Quem não tem admissão efetivada registrada não é filtrado (mesma
-- salvaguarda do [vinculo-corte] da Fase 1).
--
-- CORREÇÃO:
--   A. ponto_vinculo_cobre_periodo(tenant, cpf, ini, fim) — regra única, reusável.
--   B. consolidar_ponto_dia_todos — para de materializar após o desligamento.
--   C. ponto_espelho_resumo_empresa (Fechamento) — filtra por vínculo.
--   D. ponto_banco_horas_oficial (Banco) — filtra por vínculo.
--   E. ponto_faltas_do_mes — fonte da Compensação de Faltas, validando escala
--      (só dia com jornada prevista) E vínculo (corrige fim de semana e desligado).
--
-- Observação: linhas de 'falta' já materializadas para desligados continuam na
-- base, mas deixam de aparecer nas listas (filtradas por vínculo); a materialização
-- para de acumular novas. Limpeza dessas linhas antigas é opcional (script à parte).
-- ============================================================================

-- ---------------------------------------------------------------------
-- A) Regra única de vínculo ativo num período
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_vinculo_cobre_periodo(
  p_tenant_id uuid,
  p_colaborador_cpf text,
  p_ini date,
  p_fim date
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  -- true quando: (a) o CPF não tem admissão efetivada registrada (não filtramos
  -- quem não tem cadastro — salvaguarda do [vinculo-corte]); ou (b) existe uma
  -- admissão efetivada cujo intervalo [data_admissao, data_desligamento|infinito]
  -- cruza [p_ini, p_fim].
  SELECT
    NOT EXISTS (
      SELECT 1 FROM public.admissoes a
      WHERE a.tenant_id = p_tenant_id
        AND regexp_replace(COALESCE(a.cpf,''),'[^0-9]','','g')
            = regexp_replace(COALESCE(p_colaborador_cpf,''),'[^0-9]','','g')
        AND a.status::text IN ('concluido','desligado')
    )
    OR EXISTS (
      SELECT 1 FROM public.admissoes a
      WHERE a.tenant_id = p_tenant_id
        AND regexp_replace(COALESCE(a.cpf,''),'[^0-9]','','g')
            = regexp_replace(COALESCE(p_colaborador_cpf,''),'[^0-9]','','g')
        AND a.status::text IN ('concluido','desligado')
        AND COALESCE(a.data_admissao, '-infinity'::date) <= p_fim
        AND COALESCE(a.data_desligamento, 'infinity'::date) >= p_ini
    );
$function$;

COMMENT ON FUNCTION public.ponto_vinculo_cobre_periodo(uuid, text, date, date) IS
  'true se o vínculo do colaborador cobre algum dia de [ini,fim] (admissao efetivada; desligado conta até a data_desligamento). Sem admissão efetivada registrada, retorna true (não filtra). Regra única das listas mensais do Ponto.';

-- ---------------------------------------------------------------------
-- B) Materialização para de gerar 'falta' após o desligamento
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.consolidar_ponto_dia_todos(p_tenant_id UUID, p_data DATE)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $todos$
DECLARE
  v_colab RECORD;
  v_n INT := 0;
BEGIN
  FOR v_colab IN
    SELECT DISTINCT regexp_replace(a.cpf, '[^0-9]', '', 'g') AS cpf
    FROM public.admissoes a
    WHERE a.tenant_id = p_tenant_id AND a.cpf IS NOT NULL
      AND COALESCE(a.inativo, false) = false
      AND COALESCE(a.bate_ponto, true) = true
      AND a.data_admissao <= p_data
      -- [lista-respeita-vinculo] Não materializar dia após o desligamento
      -- (mantém o próprio dia do desligamento, como o [vinculo-corte]).
      AND (a.data_desligamento IS NULL OR a.data_desligamento >= p_data)
      AND (
        a.empresa_id IN (SELECT r.empresa_id FROM public.ponto_empresas_em_regime(p_tenant_id) r)
        OR regexp_replace(a.cpf, '[^0-9]', '', 'g')
           IN (SELECT c.cpf FROM public.ponto_cpfs_em_regime(p_tenant_id, p_data) c)
      )
  LOOP
    PERFORM public.consolidar_ponto_diario_manual(p_tenant_id, v_colab.cpf, p_data);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$todos$;

-- ---------------------------------------------------------------------
-- C) Fechamento: ponto_espelho_resumo_empresa filtra por vínculo (patch)
-- ---------------------------------------------------------------------
DO $patchC$
DECLARE
  v_src text; v_novo text;
  v_alvo text := E'      AND COALESCE(pd.colaborador_cpf, \'\') <> \'\'';
  v_troca text := E'      AND COALESCE(pd.colaborador_cpf, \'\') <> \'\'\n'
    || E'      -- [lista-respeita-vinculo] não traz desligado após a data\n'
    || E'      AND public.ponto_vinculo_cobre_periodo(p_tenant_id, regexp_replace(pd.colaborador_cpf, \'[^0-9]\', \'\', \'g\'), v_ini, v_fim)';
BEGIN
  v_src := pg_get_functiondef('public.ponto_espelho_resumo_empresa(uuid,uuid,text)'::regprocedure);
  IF position('[lista-respeita-vinculo]' IN v_src) > 0 THEN
    RAISE NOTICE 'ponto_espelho_resumo_empresa ja filtra por vinculo — nada a fazer.'; RETURN;
  END IF;
  IF position(v_alvo IN v_src) = 0 THEN
    RAISE NOTICE 'ATENCAO: ancora do loop de cpf em ponto_espelho_resumo_empresa nao encontrada; NADA alterado.'; RETURN;
  END IF;
  v_novo := replace(v_src, v_alvo, v_troca);
  EXECUTE v_novo;
  RAISE NOTICE 'ponto_espelho_resumo_empresa: lista do mes passa a respeitar o vinculo.';
END;
$patchC$;

-- ---------------------------------------------------------------------
-- D) Banco: ponto_banco_horas_oficial filtra por vínculo (patch, 2 ramos)
-- ---------------------------------------------------------------------
DO $patchD$
DECLARE
  v_src text; v_novo text; v_ok boolean := true;
  v_alvo_b text := E'      AND (v_so_cpf IS NULL\n           OR regexp_replace(COALESCE(b.colaborador_cpf, \'\'), \'[^0-9]\', \'\', \'g\') = v_so_cpf)';
  v_troca_b text := E'      AND (v_so_cpf IS NULL\n           OR regexp_replace(COALESCE(b.colaborador_cpf, \'\'), \'[^0-9]\', \'\', \'g\') = v_so_cpf)\n'
    || E'      AND public.ponto_vinculo_cobre_periodo(p_tenant_id, regexp_replace(COALESCE(b.colaborador_cpf, \'\'), \'[^0-9]\', \'\', \'g\'), v_ini, v_fim) /* [lista-respeita-vinculo] */';
  v_alvo_d text := E'        AND (v_so_cpf IS NULL\n             OR regexp_replace(COALESCE(pd.colaborador_cpf, \'\'), \'[^0-9]\', \'\', \'g\') = v_so_cpf)';
  v_troca_d text := E'        AND (v_so_cpf IS NULL\n             OR regexp_replace(COALESCE(pd.colaborador_cpf, \'\'), \'[^0-9]\', \'\', \'g\') = v_so_cpf)\n'
    || E'        AND public.ponto_vinculo_cobre_periodo(p_tenant_id, regexp_replace(COALESCE(pd.colaborador_cpf, \'\'), \'[^0-9]\', \'\', \'g\'), v_ini, v_fim) /* [lista-respeita-vinculo] */';
BEGIN
  v_src := pg_get_functiondef('public.ponto_banco_horas_oficial(uuid,text,uuid,text)'::regprocedure);
  IF position('[lista-respeita-vinculo]' IN v_src) > 0 THEN
    RAISE NOTICE 'ponto_banco_horas_oficial ja filtra por vinculo — nada a fazer.'; RETURN;
  END IF;
  IF position(v_alvo_b IN v_src) = 0 OR position(v_alvo_d IN v_src) = 0 THEN
    RAISE NOTICE 'ATENCAO: ancora(s) em ponto_banco_horas_oficial nao encontrada(s); NADA alterado.'; RETURN;
  END IF;
  v_novo := replace(v_src, v_alvo_b, v_troca_b);
  v_novo := replace(v_novo, v_alvo_d, v_troca_d);
  EXECUTE v_novo;
  RAISE NOTICE 'ponto_banco_horas_oficial: lista do mes passa a respeitar o vinculo.';
END;
$patchD$;

-- ---------------------------------------------------------------------
-- E) Fonte da Compensação de Faltas: valida escala (jornada>0) e vínculo
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_faltas_do_mes(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_competencia text
)
RETURNS TABLE(
  colaborador_cpf text,
  colaborador_nome text,
  colaborador_id uuid,
  data date,
  jornada_min integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH janela AS (
    SELECT to_date(p_competencia || '-01','YYYY-MM-DD') AS ini,
           (to_date(p_competencia || '-01','YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date AS fim
  )
  SELECT
    regexp_replace(pd.colaborador_cpf,'[^0-9]','','g') AS colaborador_cpf,
    pd.colaborador_nome,
    pd.colaborador_id,
    pd.data,
    j.jornada_min
  FROM janela w
  JOIN public.ponto_diario pd
    ON pd.tenant_id = p_tenant_id
   AND pd.data BETWEEN w.ini AND w.fim
   AND pd.status = 'falta'
   AND COALESCE(pd.colaborador_cpf,'') <> ''
   AND (p_empresa_id IS NULL OR pd.empresa_id = p_empresa_id)
  CROSS JOIN LATERAL public.ponto_jornada_do_dia(
    p_tenant_id,
    regexp_replace(pd.colaborador_cpf,'[^0-9]','','g'),
    pd.colaborador_id::text,
    pd.data) j
  WHERE COALESCE(j.jornada_min,0) > 0                       -- valida a escala (sem fim de semana)
    AND public.ponto_vinculo_cobre_periodo(                 -- não traz desligado após a data
          p_tenant_id,
          regexp_replace(pd.colaborador_cpf,'[^0-9]','','g'),
          pd.data, pd.data)
  ORDER BY pd.data DESC, pd.colaborador_nome;
$function$;

COMMENT ON FUNCTION public.ponto_faltas_do_mes(uuid, uuid, text) IS
  'Faltas reais do mês para a tela de Compensação de Faltas: só dias com jornada prevista (valida a escala — sem sábado/domingo neutro) e dentro do vínculo (desligado só até a data_desligamento).';

REVOKE ALL ON FUNCTION public.ponto_faltas_do_mes(uuid, uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.ponto_faltas_do_mes(uuid, uuid, text) TO authenticated;

-- ---------------------------------------------------------------------
-- F) QA PONTO-482 — faltas do mês respeitam escala (sem fim de semana) e vínculo
-- ---------------------------------------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-482',
  m.id,
  'Faltas do mês só trazem dia útil da escala e vínculo ativo',
  'A lista de faltas do mês (Compensação de Faltas) não pode trazer dia sem jornada prevista '
  || '(sábado/domingo fora da escala) nem colaborador desligado depois da data de desligamento. '
  || 'Valida a escala (jornada > 0) e o vínculo (desligado só até a data_desligamento).',
  'negativo',
  'api',
  'critica',
  'aprovado',
  'Regra de negócio: apuração por escala e por vínculo',
  jsonb_build_array(
    jsonb_build_object('ordem', 1, 'acao', 'Marcar falta num sábado sem jornada e num dia útil',
      'esperado', 'Só o dia útil entra na lista de faltas'),
    jsonb_build_object('ordem', 2, 'acao', 'Marcar falta antes e depois do desligamento',
      'esperado', 'Só a falta anterior ao desligamento entra')
  ),
  'em_triagem',
  'Correção listas do mês respeitam vínculo/escala.'
FROM public.qa_modulos m WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_482()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpfA text := public.qa_cpf(4821);  -- ativo, escala cobre o mês
  v_cpfB text := public.qa_cpf(4822);  -- desligado no meio do mês
  v_cpfC text := public.qa_cpf(4823);  -- vínculo ativo, mas escala já encerrada
  v_ini date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
  v_comp text;
  v_seg date; v_antes date; v_depois date; v_desl date; v_segC date;
  v_tem_seg boolean; v_tem_antes boolean; v_tem_depois boolean; v_tem_C boolean;
  v_todas_jornada_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Faltas do mês respeitam escala (jornada > 0) e vínculo (desligado só até a data)';
  r.esperado := 'Dia útil sim; falta pós-desligamento não; falta sem escala não; toda linha com jornada>0';

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  v_comp := to_char(v_ini, 'YYYY-MM');

  -- Estado limpo: UMA escala ativa por colaborador (sem escalas de corridas anteriores).
  UPDATE public.ponto_escala_atribuicoes SET ativa = false
    WHERE tenant_id = v_t
      AND regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g') IN (v_cpfA, v_cpfB, v_cpfC);

  -- Uma segunda e uma quarta do mês (dias úteis)
  v_seg  := v_ini + ((8 - EXTRACT(ISODOW FROM v_ini)::int) % 7);
  v_segC := v_seg + 2;

  -- Colaborador A: ativo, escala cobre o mês. Falta em dia útil -> deve aparecer.
  IF NOT EXISTS (SELECT 1 FROM public.admissoes a WHERE a.tenant_id=v_t AND a.cpf=v_cpfA AND COALESCE(a.inativo,false)=false) THEN
    PERFORM public.qa_ponto_admissao('QA Vinculo Escala A', 4821, NULL, v_ini - 60);
  END IF;
  PERFORM public.qa_ponto_escala_tol(v_cpfA, 'QA Vinculo Escala A', 480, 10, v_ini - 60, NULL);
  PERFORM public.qa_ponto_dia_min(v_cpfA, 'QA Vinculo Escala A', v_seg, 0);
  UPDATE public.ponto_diario SET status='falta', horas_trabalhadas=INTERVAL '0'
    WHERE tenant_id=v_t AND colaborador_cpf=v_cpfA AND data=v_seg;

  -- Colaborador B: desligado no meio do mês. Falta antes -> aparece; depois -> não.
  v_desl   := v_ini + 14;
  v_antes  := v_seg + 7;                     -- 2a semana
  IF v_antes > v_desl THEN v_antes := v_desl - 3; END IF;
  v_depois := v_desl + 7;                    -- após desligamento
  IF NOT EXISTS (SELECT 1 FROM public.admissoes a WHERE a.tenant_id=v_t AND a.cpf=v_cpfB) THEN
    PERFORM public.qa_ponto_admissao('QA Vinculo Escala B', 4822, NULL, v_ini - 60);
  END IF;
  PERFORM public.qa_ponto_escala_tol(v_cpfB, 'QA Vinculo Escala B', 480, 10, v_ini - 60, NULL);
  UPDATE public.admissoes SET data_desligamento = v_desl, status = 'desligado'
    WHERE tenant_id=v_t AND cpf=v_cpfB;
  PERFORM public.qa_ponto_dia_min(v_cpfB, 'QA Vinculo Escala B', v_antes, 0);
  UPDATE public.ponto_diario SET status='falta', horas_trabalhadas=INTERVAL '0'
    WHERE tenant_id=v_t AND colaborador_cpf=v_cpfB AND data=v_antes;
  PERFORM public.qa_ponto_dia_min(v_cpfB, 'QA Vinculo Escala B', v_depois, 0);
  UPDATE public.ponto_diario SET status='falta', horas_trabalhadas=INTERVAL '0'
    WHERE tenant_id=v_t AND colaborador_cpf=v_cpfB AND data=v_depois;

  -- Colaborador C: vínculo ativo, mas a escala terminou ANTES do mês -> os dias
  -- do mês não têm jornada prevista. Falta em dia útil -> NÃO deve aparecer
  -- (corte pela escala, não pelo vínculo).
  IF NOT EXISTS (SELECT 1 FROM public.admissoes a WHERE a.tenant_id=v_t AND a.cpf=v_cpfC AND COALESCE(a.inativo,false)=false) THEN
    PERFORM public.qa_ponto_admissao('QA Vinculo Escala C', 4823, NULL, v_ini - 60);
  END IF;
  PERFORM public.qa_ponto_escala_tol(v_cpfC, 'QA Vinculo Escala C', 480, 10, v_ini - 60, v_ini - 1);
  PERFORM public.qa_ponto_dia_min(v_cpfC, 'QA Vinculo Escala C', v_segC, 0);
  UPDATE public.ponto_diario SET status='falta', horas_trabalhadas=INTERVAL '0'
    WHERE tenant_id=v_t AND colaborador_cpf=v_cpfC AND data=v_segC;

  -- Resultado da fonte
  SELECT
    bool_or(f.colaborador_cpf=v_cpfA AND f.data=v_seg),
    bool_or(f.colaborador_cpf=v_cpfB AND f.data=v_antes),
    bool_or(f.colaborador_cpf=v_cpfB AND f.data=v_depois),
    bool_or(f.colaborador_cpf=v_cpfC AND f.data=v_segC),
    COALESCE(bool_and(f.jornada_min > 0), true)
    INTO v_tem_seg, v_tem_antes, v_tem_depois, v_tem_C, v_todas_jornada_ok
  FROM public.ponto_faltas_do_mes(v_t, NULL, v_comp) f;

  IF COALESCE(v_tem_seg,false) <> true THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a falta de dia útil (colaborador ativo) não apareceu (deveria aparecer).';
  ELSIF COALESCE(v_tem_antes,false) <> true THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a falta ANTES do desligamento não apareceu (deveria aparecer).';
  ELSIF COALESCE(v_tem_depois,false) <> false THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a falta DEPOIS do desligamento apareceu (deveria ser filtrada pelo vínculo).';
  ELSIF COALESCE(v_tem_C,false) <> false THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: falta em dia sem jornada prevista (escala encerrada) apareceu (deveria ser filtrada pela escala).';
  ELSIF v_todas_jornada_ok <> true THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a lista trouxe dia com jornada 0 (fim de semana/dia sem escala) — deve validar a escala.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Só dia útil dentro do vínculo entrou; pós-desligamento e dia sem jornada ficaram de fora; toda linha tem jornada>0.';
    r.detalhe := jsonb_build_object('dia_util', v_tem_seg, 'antes_desl', v_tem_antes,
                                    'depois_desl', v_tem_depois, 'sem_escala', v_tem_C,
                                    'todas_jornada_ok', v_todas_jornada_ok);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-482', 'qa_caso_ponto_482', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

DO $fim$
BEGIN
  RAISE NOTICE 'Listas do mes do Ponto passam a respeitar o vinculo (desligado so ate a data); Comp. Faltas valida escala.';
END $fim$;
