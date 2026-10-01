-- ============================================================================
-- BUG: troca de escala recalcula o PASSADO com a escala NOVA.
--
-- Causa: ao trocar a escala de um colaborador, a atribuição antiga é encerrada
-- com data_fim E marcada ativa=false. Mas os resolvedores "do dia" da apuração
-- filtram "COALESCE(a.ativa,true)=true" — ou seja, IGNORAM a atribuição
-- encerrada mesmo para dias DENTRO do período dela. Com isso, para os meses em
-- que a pessoa estava na escala antiga, o motor não a encontra e cai na escala
-- ATUAL. (Ex.: Natieli — agosto, quando ela era 44h, foi calculado com 36h.)
--
-- Correção: o período (data_inicio..data_fim) é o que define a validade da
-- atribuição. Uma atribuição ENCERRADA (ativa=false COM data_fim) continua sendo
-- a escala vigente nos dias dentro do seu intervalo. Só as CANCELADAS
-- (ativa=false SEM data_fim) seguem ignoradas. Troca-se, nos resolvedores por
-- dia, "COALESCE(a.ativa,true)=true" por
-- "(COALESCE(a.ativa,true)=true OR a.data_fim IS NOT NULL)".
--
-- Patch cirúrgico e idempotente: parte da definição atual de cada função e
-- injeta só essa condição. Se a âncora não existir (versão diferente) ou já
-- estiver corrigida, apenas avisa e segue. Só mexe no alias "a" (atribuição) —
-- não toca em "pa.ativa" (pré-assinalação). Só substitui FUNÇÃO.
-- ============================================================================
DO $fix$
DECLARE
  v_fn text;
  v_funcs text[] := ARRAY[
    'ponto_jornada_do_dia',
    'ponto_escala_do_dia',
    'ponto_intervalo_janela_do_dia',
    'ponto_apurar_ciclo_plantao_do_dia',
    'ponto_debito_batida_do_dia',
    'ponto_pre_assinalacao_do_dia'
  ];
  v_oid oid;
  v_src text;
  v_anchor text := 'AND COALESCE(a.ativa, true) = true'
                 || E'\n    AND a.data_inicio <= p_data';
  v_fixed text := 'AND (COALESCE(a.ativa, true) = true OR a.data_fim IS NOT NULL)'
                 || E'\n    AND a.data_inicio <= p_data';
BEGIN
  FOREACH v_fn IN ARRAY v_funcs LOOP
    FOR v_oid IN
      SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = v_fn AND p.prokind = 'f'
    LOOP
      v_src := pg_get_functiondef(v_oid);

      IF position(v_fixed IN v_src) > 0 THEN
        RAISE NOTICE '[%] já corrigida — nada a fazer.', v_fn;
        CONTINUE;
      END IF;

      IF position(v_anchor IN v_src) = 0 THEN
        RAISE NOTICE '[%] âncora não encontrada (confira manualmente) — pulada.', v_fn;
        CONTINUE;
      END IF;

      EXECUTE replace(v_src, v_anchor, v_fixed);
      RAISE NOTICE '[%] corrigida.', v_fn;
    END LOOP;
  END LOOP;
END $fix$;


-- ---------------------------------------------------------------------
-- QA PONTO-484 — apuração respeita a escala vigente em cada período
-- ---------------------------------------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-484',
  m.id,
  'Troca de escala não recalcula o passado com a escala nova',
  'Ao trocar a escala de um colaborador, a atribuição antiga é encerrada '
  || '(data_fim + ativa=false). A apuração de um dia DENTRO do período antigo '
  || 'precisa usar a escala ANTIGA, não a atual. Atribuição cancelada '
  || '(inativa SEM data_fim) continua ignorada.',
  'negativo',
  'api',
  'critica',
  'aprovado',
  'Fidelidade da jornada por período (CLT art. 74 · Portaria 671)',
  jsonb_build_array(
    jsonb_build_object('ordem', 1, 'acao', 'Dia no período da escala encerrada',
      'esperado', 'Jornada = escala antiga'),
    jsonb_build_object('ordem', 2, 'acao', 'Dia no período da escala atual',
      'esperado', 'Jornada = escala nova'),
    jsonb_build_object('ordem', 3, 'acao', 'Atribuição cancelada (sem data_fim)',
      'esperado', 'Ignorada (sem jornada)')
  ),
  'em_triagem',
  'Correção do bug de escala retroativa na apuração.'
FROM public.qa_modulos m WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_484()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(9484);
  v_cid uuid := gen_random_uuid();
  v_escA uuid; v_escB uuid; v_escC uuid;
  v_cpf2 text := public.qa_cpf(9485);
  v_cid2 uuid := gen_random_uuid();
  v_jA int; v_jB int; v_jC int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apuração do dia respeita a escala vigente no período (encerrada vale no seu intervalo)';
  r.esperado := 'Período antigo = escala antiga; período novo = escala nova; cancelada (sem data_fim) ignorada';

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();

  -- Estado limpo
  DELETE FROM public.ponto_escala_atribuicoes WHERE tenant_id=v_t AND colaborador_cpf IN (v_cpf, v_cpf2);
  DELETE FROM public.ponto_escalas WHERE tenant_id=v_t
    AND nome IN ('QA484 A (8h)','QA484 B (6h)','QA484 C cancelada (8h)');

  INSERT INTO public.ponto_escalas (tenant_id, nome, jornada_diaria_minutos, ativa)
    VALUES (v_t,'QA484 A (8h)',480,true) RETURNING id INTO v_escA;
  INSERT INTO public.ponto_escalas (tenant_id, nome, jornada_diaria_minutos, ativa)
    VALUES (v_t,'QA484 B (6h)',360,true) RETURNING id INTO v_escB;
  INSERT INTO public.ponto_escalas (tenant_id, nome, jornada_diaria_minutos, ativa)
    VALUES (v_t,'QA484 C cancelada (8h)',480,true) RETURNING id INTO v_escC;

  -- Troca de escala: A encerrada (ativa=false + data_fim) -> B atual.
  INSERT INTO public.ponto_escala_atribuicoes
    (tenant_id, escala_id, colaborador_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim, ativa)
    VALUES (v_t, v_escA, v_cid, 'QA484 Pessoa', v_cpf, CURRENT_DATE-60, CURRENT_DATE-30, false);
  INSERT INTO public.ponto_escala_atribuicoes
    (tenant_id, escala_id, colaborador_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim, ativa)
    VALUES (v_t, v_escB, v_cid, 'QA484 Pessoa', v_cpf, CURRENT_DATE-30, NULL, true);

  -- Pessoa 2: atribuição CANCELADA (ativa=false, SEM data_fim).
  INSERT INTO public.ponto_escala_atribuicoes
    (tenant_id, escala_id, colaborador_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim, ativa)
    VALUES (v_t, v_escC, v_cid2, 'QA484 Cancelada', v_cpf2, CURRENT_DATE-60, NULL, false);

  SELECT jornada_min INTO v_jA FROM public.ponto_jornada_do_dia(v_t, v_cpf,  v_cid::text,  CURRENT_DATE-45);
  SELECT jornada_min INTO v_jB FROM public.ponto_jornada_do_dia(v_t, v_cpf,  v_cid::text,  CURRENT_DATE-10);
  SELECT jornada_min INTO v_jC FROM public.ponto_jornada_do_dia(v_t, v_cpf2, v_cid2::text, CURRENT_DATE-10);

  -- Limpeza
  DELETE FROM public.ponto_escala_atribuicoes WHERE tenant_id=v_t AND colaborador_cpf IN (v_cpf, v_cpf2);
  DELETE FROM public.ponto_escalas WHERE id IN (v_escA, v_escB, v_escC);

  IF COALESCE(v_jA,0) <> 480 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: dia do período antigo não usou a escala antiga (obtido '||COALESCE(v_jA::text,'NULL')||', esperado 480).';
  ELSIF COALESCE(v_jB,0) <> 360 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: dia do período novo não usou a escala nova (obtido '||COALESCE(v_jB::text,'NULL')||', esperado 360).';
  ELSIF v_jC IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: atribuição cancelada (sem data_fim) foi usada (obtido '||v_jC::text||', esperado NULL).';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Período antigo=8h, período novo=6h, cancelada ignorada.';
    r.detalhe := jsonb_build_object('antigo_min', v_jA, 'novo_min', v_jB, 'cancelada', v_jC);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-484', 'qa_caso_ponto_484', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

DO $fim$
BEGIN
  RAISE NOTICE 'Apuracao passa a respeitar a escala vigente em cada periodo (escala encerrada vale no seu intervalo).';
END $fim$;
