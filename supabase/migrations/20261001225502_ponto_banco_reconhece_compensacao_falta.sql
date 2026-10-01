-- ============================================================================
-- Banco de horas: reconhecer o débito de COMPENSAÇÃO DE FALTA no saldo.
--
-- BUG: a ciência da compensação de falta (Fatia 2) grava a movimentação com
-- tipo = 'compensacao_falta'. Mas as funções que somam o saldo do banco só
-- conheciam 'credito', 'debito' e 'compensacao' — então o débito da compensação
-- ficava INVISÍVEL: o saldo não mudava e a reapuração o ignorava.
--
-- CORREÇÃO: tratar 'compensacao_falta' como DÉBITO nas duas somas de
-- movimentação por tipo:
--   * ponto_banco_horas_oficial       (fonte única — tela e conferência)
--   * apurar_banco_horas_colaborador  (apuração que grava debitos_minutos;
--                                       o fechamento lê esse campo)
-- Não há risco de dobra: a apuração já NÃO debita a falta no banco
-- ([falta-fora-do-banco] em ponto_saldo_dias_competencia_bruto -> v_diff=0),
-- então o débito da compensação passa a ser a ÚNICA cobrança (CLT art. 59 §2º).
--
-- Patch cirúrgico (pg_get_functiondef + replace + EXECUTE), idempotente: só
-- troca o pedaço do FILTER de débito; se já corrigido, pula; se a âncora não
-- existir, avisa. Só substitui FUNÇÃO — não cria tabela, não altera dado.
-- ============================================================================
DO $fix$
DECLARE
  v_oid oid;
  v_src text;
  v_alvo_of text := 'm.tipo = ''debito''  AND COALESCE(m.origem';
  v_novo_of text := 'm.tipo IN (''debito'', ''compensacao_falta'') AND COALESCE(m.origem';
  v_alvo_ap text := 'FILTER (WHERE tipo = ''debito'')';
  v_novo_ap text := 'FILTER (WHERE tipo IN (''debito'', ''compensacao_falta''))';
BEGIN
  -- 1) ponto_banco_horas_oficial
  FOR v_oid IN
    SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='ponto_banco_horas_oficial' AND p.prokind='f'
  LOOP
    v_src := pg_get_functiondef(v_oid);
    IF position('IN (''debito'', ''compensacao_falta'') AND COALESCE(m.origem' IN v_src) > 0 THEN
      RAISE NOTICE '[oficial] ja reconhece compensacao_falta.';
    ELSIF position(v_alvo_of IN v_src) = 0 THEN
      RAISE NOTICE '[oficial] ancora do FILTER de debito nao encontrada — conferir manualmente.';
    ELSE
      EXECUTE replace(v_src, v_alvo_of, v_novo_of);
      RAISE NOTICE '[oficial] corrigida.';
    END IF;
  END LOOP;

  -- 2) apurar_banco_horas_colaborador
  FOR v_oid IN
    SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='apurar_banco_horas_colaborador' AND p.prokind='f'
  LOOP
    v_src := pg_get_functiondef(v_oid);
    IF position('FILTER (WHERE tipo IN (''debito'', ''compensacao_falta''))' IN v_src) > 0 THEN
      RAISE NOTICE '[apurar] ja reconhece compensacao_falta.';
    ELSIF position(v_alvo_ap IN v_src) = 0 THEN
      RAISE NOTICE '[apurar] ancora do FILTER de debito nao encontrada — conferir manualmente.';
    ELSE
      EXECUTE replace(v_src, v_alvo_ap, v_novo_ap);
      RAISE NOTICE '[apurar] corrigida.';
    END IF;
  END LOOP;
END $fix$;


-- ---------------------------------------------------------------------
-- QA PONTO-485 — a compensação de falta efetivada entra no saldo do banco
-- (uma vez). Valida que oficial E apuração passam a contar o débito
-- 'compensacao_falta'.
-- ---------------------------------------------------------------------
-- modulo_id resolvido pelo path (o UUID do módulo varia por ambiente).
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status)
SELECT
  'PONTO-485', m.id,
  'Compensação de falta efetivada entra no saldo do banco (uma vez)',
  'O débito gerado pela ciência da compensação de falta (tipo compensacao_falta) '
  || 'deve ser contado como débito pela fonte única (tela) e pela apuração — e só '
  || 'uma vez, pois a falta já fica fora do banco. Sem isso, o débito ficava invisível.',
  'feliz', 'api', 'alta', 'aprovado'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_485()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4851);
  v_dia date := public.qa_dia_util_passado();
  v_comp text := to_char(public.qa_dia_util_passado(),'YYYY-MM');
  v_empresa uuid;
  v_id uuid;
  v_saldo_com int; v_saldo_sem int;
  v_deb_com int; v_deb_sem int;
  v_qtd int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Efetivar compensação de falta e conferir que o débito entra no saldo (uma vez)';
  r.esperado    := 'oficial e apuração descontam a jornada (480) exatamente uma vez';

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();

  IF NOT EXISTS (SELECT 1 FROM public.admissoes a
                  WHERE a.tenant_id = v_t AND a.cpf = v_cpf AND COALESCE(a.inativo,false)=false) THEN
    PERFORM public.qa_ponto_admissao('QA Comp Falta Banco', 4851);
  END IF;
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Comp Falta Banco', 480, 10, v_dia - 5, NULL);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Comp Falta Banco', v_dia, 0);
  UPDATE public.ponto_diario
     SET status='falta', entrada=NULL, saida=NULL, horas_trabalhadas=INTERVAL '0'
   WHERE tenant_id=v_t AND colaborador_cpf=v_cpf AND data=v_dia;

  -- limpa estado anterior
  DELETE FROM public.ponto_banco_horas_movimentacoes m USING public.ponto_banco_horas b
    WHERE m.banco_horas_id=b.id AND b.tenant_id=v_t
      AND regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g')=v_cpf AND m.tipo='compensacao_falta';
  DELETE FROM public.ponto_compensacao_falta WHERE tenant_id=v_t AND colaborador_cpf=v_cpf;
  UPDATE public.ponto_acordos SET ativo=false WHERE tenant_id=v_t AND titulo='QA Acordo Comp Falta Banco';
  UPDATE public.ponto_banco_horas_config SET ativo=false WHERE tenant_id=v_t AND forma_compensacao='QA-COMPFALTA-BANCO';

  v_empresa := public.ponto_empresa_do_cpf(v_t, v_cpf);
  INSERT INTO public.ponto_banco_horas_config
    (tenant_id, empresa_id, tipo, prazo_compensacao_dias, forma_compensacao, data_inicio, ativo)
  VALUES (v_t, v_empresa, 'mensal', 90, 'QA-COMPFALTA-BANCO', v_dia - 30, true);
  INSERT INTO public.ponto_acordos
    (tenant_id, empresa_id, colaborador_cpf, tipo, titulo, vigencia_inicio, vigencia_fim, permite_compensacao_falta, ativo)
  VALUES (v_t, v_empresa, v_cpf, 'individual', 'QA Acordo Comp Falta Banco', v_dia - 30, v_dia + 300, true, true);

  -- registrar -> autorizar -> ciencia (efetiva: nasce o débito compensacao_falta)
  v_id := (public.ponto_registrar_compensacao_falta(v_t, v_cpf, v_dia, 'banco')->>'id')::uuid;
  PERFORM public.ponto_autorizar_compensacao_falta(v_t, v_id, 'Gestor');
  PERFORM public.ponto_dar_ciencia_compensacao_falta(v_t, v_id, 'Colaborador');

  -- COM o débito: apura e lê oficial + debitos gravados
  PERFORM public.apurar_banco_horas_colaborador(v_t, v_cpf, v_comp, v_empresa);
  SELECT o.saldo_atual_min INTO v_saldo_com
    FROM public.ponto_banco_horas_oficial(v_t, v_comp, NULL, v_cpf) o LIMIT 1;
  SELECT b.debitos_minutos INTO v_deb_com FROM public.ponto_banco_horas b
   WHERE b.tenant_id=v_t AND regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g')=v_cpf AND b.competencia=v_comp LIMIT 1;
  SELECT count(*) INTO v_qtd FROM public.ponto_banco_horas_movimentacoes m
    JOIN public.ponto_banco_horas b ON b.id=m.banco_horas_id
   WHERE b.tenant_id=v_t AND regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g')=v_cpf
     AND m.tipo='compensacao_falta' AND m.data_referencia=v_dia;

  -- SEM o débito: remove a movimentação, reapura e relê
  DELETE FROM public.ponto_banco_horas_movimentacoes m USING public.ponto_banco_horas b
    WHERE m.banco_horas_id=b.id AND b.tenant_id=v_t
      AND regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g')=v_cpf
      AND m.tipo='compensacao_falta' AND m.data_referencia=v_dia;
  PERFORM public.apurar_banco_horas_colaborador(v_t, v_cpf, v_comp, v_empresa);
  SELECT o.saldo_atual_min INTO v_saldo_sem
    FROM public.ponto_banco_horas_oficial(v_t, v_comp, NULL, v_cpf) o LIMIT 1;
  SELECT b.debitos_minutos INTO v_deb_sem FROM public.ponto_banco_horas b
   WHERE b.tenant_id=v_t AND regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g')=v_cpf AND b.competencia=v_comp LIMIT 1;

  IF COALESCE(v_qtd,0) <> 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: esperava 1 débito de compensacao_falta, achei %s.', v_qtd);
  ELSIF COALESCE(v_saldo_sem,0) - COALESCE(v_saldo_com,0) <> 480 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a fonte única não desconta o débito corretamente. saldo com=%s, sem=%s (esperava diferença 480).',
                       v_saldo_com, v_saldo_sem);
  ELSIF COALESCE(v_deb_com,0) - COALESCE(v_deb_sem,0) <> 480 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a apuração não grava o débito da compensação. debitos com=%s, sem=%s (esperava diferença 480).',
                       v_deb_com, v_deb_sem);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('OK: 1 débito de 480; oficial %s->%s e apuração debitos %s->%s ao remover (desconta uma vez).',
                       v_saldo_com, v_saldo_sem, v_deb_com, v_deb_sem);
  END IF;

  r.erro_tecnico := NULL;
  r.detalhe := jsonb_build_object('saldo_com', v_saldo_com, 'saldo_sem', v_saldo_sem,
                                  'deb_com', v_deb_com, 'deb_sem', v_deb_sem, 'qtd', v_qtd);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro';
  r.erro_tecnico := SQLERRM;
  RETURN r;
END;
$function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-485', 'qa_caso_ponto_485', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
