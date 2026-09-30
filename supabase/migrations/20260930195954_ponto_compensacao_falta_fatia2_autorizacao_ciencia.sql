-- ============================================================================
-- Compensação de falta — FATIA 2: autorização, homologação, ciência, efetivação
-- ----------------------------------------------------------------------------
-- Continua a Fatia 1. Aqui a solicitação caminha pelo ciclo de vida e, só no
-- fim (ciência do colaborador), o DÉBITO entra no banco de horas.
--
-- Fluxo (RQ-048; D-17):
--   pendente_autorizacao --autorizar(gestor)--> autorizada
--                                          \--> pendente_homologacao (se acima
--                                               do limite do regime) --homologar(RH)--> autorizada
--   autorizada --ciencia(colaborador)--> efetivada  [aqui nasce o débito no banco]
--   (qualquer estado antes de efetivada) --cancelar--> cancelada
--
-- "Débito provisório até a ciência" (RQ-048/CA-054): enquanto a solicitação
-- está 'autorizada' (sem ciência), ela É a pendência — o valor está reservado
-- na solicitação, mas NENHUM movimento entra no banco ainda. O débito só é
-- lançado na EFETIVAÇÃO (ciência). Assim não existe débito firme sem a ciência
-- do colaborador, e o banco nunca carrega lançamento provisório.
--
-- IMPORTANTE — dependência da Fatia 3: enquanto a Fatia 3 (folha/DSR) não
-- estiver aplicada, uma falta efetivada gera o débito no banco E ainda conta
-- como falta na folha/DSR (duplo efeito). Por isso as Fatias 2 e 3 vão JUNTAS
-- para teste/produção; esta sozinha não deve ir à produção.
--
-- Marca o dia como "compensada"? NÃO altera ponto_diario: a falta permanece
-- como ocorrência (RQ-050). O estado "compensada" é derivado desta tabela
-- (ponto_compensacao_falta.status='efetivada'), que a Fatia 3 vai ler para
-- tirar a falta do desconto de folha e da perda de DSR.
-- ============================================================================

-- ---------------------------------------------------------------------
-- 0) Limite de homologação do RH (D-17), por regime de banco
-- ---------------------------------------------------------------------
ALTER TABLE public.ponto_banco_horas_config
  ADD COLUMN IF NOT EXISTS homologacao_rh_acima_min integer;

COMMENT ON COLUMN public.ponto_banco_horas_config.homologacao_rh_acima_min IS
  'Compensação de falta acima deste número de minutos exige homologação do RH além da autorização do gestor (D-17). NULL = nunca exige homologação.';

-- ---------------------------------------------------------------------
-- 1) Autorizar (gestor). Acima do limite do regime -> pendente_homologacao.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_autorizar_compensacao_falta(
  p_tenant_id uuid,
  p_id uuid,
  p_autorizado_por_nome text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.ponto_compensacao_falta;
  v_limite int;
  v_novo text;
BEGIN
  IF auth.uid() IS NOT NULL AND public.get_user_tenant_id() IS DISTINCT FROM p_tenant_id THEN
    RAISE EXCEPTION 'Acesso negado ao tenant';
  END IF;

  SELECT * INTO v_row FROM public.ponto_compensacao_falta
   WHERE id = p_id AND tenant_id = p_tenant_id;
  IF v_row.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'motivo', 'Solicitação não encontrada.');
  END IF;
  IF v_row.status <> 'pendente_autorizacao' THEN
    RETURN jsonb_build_object('success', false,
      'motivo', format('Só é possível autorizar quando pendente de autorização (estado atual: %s).', v_row.status));
  END IF;

  v_limite := (SELECT c.homologacao_rh_acima_min FROM public.ponto_banco_horas_config c
               WHERE c.id = v_row.regime_id);
  v_novo := CASE WHEN v_limite IS NOT NULL AND v_row.minutos > v_limite
                 THEN 'pendente_homologacao' ELSE 'autorizada' END;

  UPDATE public.ponto_compensacao_falta
     SET status = v_novo,
         autorizado_por = auth.uid(),
         autorizado_por_nome = p_autorizado_por_nome,
         autorizado_em = now(),
         updated_at = now()
   WHERE id = p_id;

  RETURN jsonb_build_object('success', true, 'status', v_novo,
    'exige_homologacao', (v_novo = 'pendente_homologacao'));
END;
$function$;

-- ---------------------------------------------------------------------
-- 2) Homologar (RH), quando exigido pelo limite.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_homologar_compensacao_falta(
  p_tenant_id uuid,
  p_id uuid,
  p_homologado_por_nome text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.ponto_compensacao_falta;
BEGIN
  IF auth.uid() IS NOT NULL AND public.get_user_tenant_id() IS DISTINCT FROM p_tenant_id THEN
    RAISE EXCEPTION 'Acesso negado ao tenant';
  END IF;

  SELECT * INTO v_row FROM public.ponto_compensacao_falta
   WHERE id = p_id AND tenant_id = p_tenant_id;
  IF v_row.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'motivo', 'Solicitação não encontrada.');
  END IF;
  IF v_row.status <> 'pendente_homologacao' THEN
    RETURN jsonb_build_object('success', false,
      'motivo', format('Só é possível homologar quando pendente de homologação (estado atual: %s).', v_row.status));
  END IF;

  UPDATE public.ponto_compensacao_falta
     SET status = 'autorizada',
         homologado_por = auth.uid(),
         homologado_por_nome = p_homologado_por_nome,
         homologado_em = now(),
         updated_at = now()
   WHERE id = p_id;

  RETURN jsonb_build_object('success', true, 'status', 'autorizada');
END;
$function$;

-- ---------------------------------------------------------------------
-- 3) Ciência do colaborador -> EFETIVA (lança o débito no banco)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_dar_ciencia_compensacao_falta(
  p_tenant_id uuid,
  p_id uuid,
  p_ciencia_por text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.ponto_compensacao_falta;
  v_cpf text;
  v_comp text;
  v_banco uuid;
  v_cid uuid; v_cnome text; v_eid uuid;
  v_mov uuid;
BEGIN
  IF auth.uid() IS NOT NULL AND public.get_user_tenant_id() IS DISTINCT FROM p_tenant_id THEN
    RAISE EXCEPTION 'Acesso negado ao tenant';
  END IF;

  SELECT * INTO v_row FROM public.ponto_compensacao_falta
   WHERE id = p_id AND tenant_id = p_tenant_id;
  IF v_row.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'motivo', 'Solicitação não encontrada.');
  END IF;
  IF v_row.status = 'efetivada' THEN
    RETURN jsonb_build_object('success', true, 'ja_efetivada', true,
      'status', 'efetivada', 'movimentacao_id', v_row.movimentacao_id);
  END IF;
  IF v_row.status <> 'autorizada' THEN
    RETURN jsonb_build_object('success', false,
      'motivo', format('Só é possível dar ciência quando autorizada (estado atual: %s).', v_row.status));
  END IF;

  v_cpf := regexp_replace(COALESCE(v_row.colaborador_cpf,''),'[^0-9]','','g');
  v_comp := to_char(v_row.data_falta, 'YYYY-MM');

  -- Dados do vínculo (para criar a linha de banco da competência se faltar)
  SELECT d.colaborador_id, d.colaborador_nome, d.empresa_id
    INTO v_cid, v_cnome, v_eid
  FROM public.ponto_diario d
  WHERE d.tenant_id = p_tenant_id
    AND regexp_replace(COALESCE(d.colaborador_cpf,''),'[^0-9]','','g') = v_cpf
    AND d.data = v_row.data_falta
  ORDER BY d.empresa_id NULLS LAST LIMIT 1;
  IF v_cid IS NULL THEN
    SELECT a.id, a.nome_completo, a.empresa_id INTO v_cid, v_cnome, v_eid
    FROM public.admissoes a
    WHERE a.tenant_id = p_tenant_id
      AND regexp_replace(COALESCE(a.cpf,''),'[^0-9]','','g') = v_cpf
      AND COALESCE(a.inativo,false) = false
    ORDER BY a.data_admissao DESC NULLS LAST LIMIT 1;
  END IF;

  -- Banco da competência (cria se faltar)
  SELECT b.id INTO v_banco FROM public.ponto_banco_horas b
  WHERE b.tenant_id = p_tenant_id
    AND regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') = v_cpf
    AND b.competencia = v_comp
  ORDER BY b.created_at DESC NULLS LAST LIMIT 1;
  IF v_banco IS NULL THEN
    INSERT INTO public.ponto_banco_horas
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, tipo,
       competencia, saldo_anterior_minutos, creditos_minutos, debitos_minutos,
       compensados_minutos, saldo_atual_minutos, convertido_extras)
    VALUES (p_tenant_id, v_eid, v_cid, v_cnome, v_cpf, 'mensal',
            v_comp, 0, 0, 0, 0, 0, false)
    RETURNING id INTO v_banco;
  END IF;

  -- Idempotente: a mesma compensação de falta não debita duas vezes.
  SELECT m.id INTO v_mov FROM public.ponto_banco_horas_movimentacoes m
  WHERE m.banco_horas_id = v_banco AND m.tipo = 'compensacao_falta'
    AND m.data_referencia = v_row.data_falta LIMIT 1;

  IF v_mov IS NULL THEN
    INSERT INTO public.ponto_banco_horas_movimentacoes
      (tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem)
    VALUES (p_tenant_id, v_banco, v_cpf, v_row.data_falta, 'compensacao_falta', v_row.minutos,
            'Compensação de falta (banco de horas) — ' || to_char(v_row.data_falta,'DD/MM/YYYY'),
            'compensacao_falta')
    RETURNING id INTO v_mov;

    UPDATE public.ponto_banco_horas
       SET debitos_minutos = COALESCE(debitos_minutos,0) + v_row.minutos,
           saldo_atual_minutos = COALESCE(saldo_atual_minutos,0) - v_row.minutos,
           updated_at = now()
     WHERE id = v_banco;
  END IF;

  UPDATE public.ponto_compensacao_falta
     SET status = 'efetivada',
         ciencia_em = now(),
         ciencia_por = p_ciencia_por,
         movimentacao_id = v_mov,
         updated_at = now()
   WHERE id = p_id;

  RETURN jsonb_build_object('success', true, 'status', 'efetivada',
    'movimentacao_id', v_mov, 'minutos', v_row.minutos, 'competencia', v_comp);
END;
$function$;

-- ---------------------------------------------------------------------
-- 4) Cancelar (antes de efetivar)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_cancelar_compensacao_falta(
  p_tenant_id uuid,
  p_id uuid,
  p_motivo text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.ponto_compensacao_falta;
BEGIN
  IF auth.uid() IS NOT NULL AND public.get_user_tenant_id() IS DISTINCT FROM p_tenant_id THEN
    RAISE EXCEPTION 'Acesso negado ao tenant';
  END IF;

  SELECT * INTO v_row FROM public.ponto_compensacao_falta
   WHERE id = p_id AND tenant_id = p_tenant_id;
  IF v_row.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'motivo', 'Solicitação não encontrada.');
  END IF;
  IF v_row.status = 'efetivada' THEN
    RETURN jsonb_build_object('success', false,
      'motivo', 'Compensação já efetivada não pode ser cancelada aqui (exigiria estorno do banco).');
  END IF;

  UPDATE public.ponto_compensacao_falta
     SET status = 'cancelada',
         motivo = COALESCE(p_motivo, motivo),
         updated_at = now()
   WHERE id = p_id;

  RETURN jsonb_build_object('success', true, 'status', 'cancelada');
END;
$function$;

DO $g$
BEGIN
  EXECUTE 'REVOKE ALL ON FUNCTION public.ponto_autorizar_compensacao_falta(uuid, uuid, text) FROM anon';
  EXECUTE 'REVOKE ALL ON FUNCTION public.ponto_homologar_compensacao_falta(uuid, uuid, text) FROM anon';
  EXECUTE 'REVOKE ALL ON FUNCTION public.ponto_dar_ciencia_compensacao_falta(uuid, uuid, text) FROM anon';
  EXECUTE 'REVOKE ALL ON FUNCTION public.ponto_cancelar_compensacao_falta(uuid, uuid, text) FROM anon';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.ponto_autorizar_compensacao_falta(uuid, uuid, text) TO authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.ponto_homologar_compensacao_falta(uuid, uuid, text) TO authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.ponto_dar_ciencia_compensacao_falta(uuid, uuid, text) TO authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.ponto_cancelar_compensacao_falta(uuid, uuid, text) TO authenticated';
END $g$;

-- ---------------------------------------------------------------------
-- 5) QA PONTO-480 — o fluxo completo até o débito
-- ---------------------------------------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-480',
  m.id,
  'Compensação de falta só debita o banco após autorização e ciência',
  'O débito por compensação de falta só existe quando o gestor autoriza e o colaborador dá ciência '
  || '(RQ-048). Enquanto autorizada sem ciência, nenhum movimento entra no banco (débito provisório). '
  || 'Na ciência, o débito é lançado com origem própria (sobrevive à reapuração). Acima do limite do '
  || 'regime, exige homologação do RH antes da ciência (D-17).',
  'feliz',
  'api',
  'critica',
  'aprovado',
  'CLT art. 59, §2º; art. 462',
  jsonb_build_array(
    jsonb_build_object('ordem', 1,
      'acao', 'Autorizar a compensação e conferir que nada entrou no banco antes da ciência',
      'esperado', 'Status autorizada e zero movimentos no banco'),
    jsonb_build_object('ordem', 2,
      'acao', 'Dar ciência e conferir o débito',
      'esperado', 'Status efetivada e um débito tipo compensacao_falta no banco, saldo reduzido')
  ),
  'em_triagem',
  'Recurso compensação de falta (RQ-047/048), Fatia 2.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_480()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4801);
  v_dia date := public.qa_dia_util_passado();
  v_empresa uuid;
  v_reg jsonb; v_aut jsonb; v_cie jsonb;
  v_banco uuid;
  v_movs_antes int; v_movs_depois int; v_saldo int;
  v_status text; v_id uuid;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Autorizar sem debitar; debitar só na ciência';
  r.esperado    := 'autorizada sem movimento; efetivada com débito compensacao_falta';

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();

  -- Vínculo + escala + falta
  IF NOT EXISTS (SELECT 1 FROM public.admissoes a
                  WHERE a.tenant_id = v_t AND a.cpf = v_cpf AND COALESCE(a.inativo,false)=false) THEN
    PERFORM public.qa_ponto_admissao('QA Comp Falta Fluxo', 4801);
  END IF;
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Comp Falta Fluxo', 480, 10, v_dia - 5, NULL);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Comp Falta Fluxo', v_dia, 0);
  UPDATE public.ponto_diario
     SET status='falta', entrada=NULL, saida=NULL, horas_trabalhadas=INTERVAL '0'
   WHERE tenant_id=v_t AND colaborador_cpf=v_cpf AND data=v_dia;

  -- Limpa estado anterior do teste
  DELETE FROM public.ponto_banco_horas_movimentacoes m
    USING public.ponto_banco_horas b
    WHERE m.banco_horas_id=b.id AND b.tenant_id=v_t
      AND regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g')=v_cpf
      AND m.tipo='compensacao_falta';
  DELETE FROM public.ponto_compensacao_falta WHERE tenant_id=v_t AND colaborador_cpf=v_cpf;
  UPDATE public.ponto_acordos SET ativo=false WHERE tenant_id=v_t AND titulo='QA Acordo Comp Falta Fluxo';
  UPDATE public.ponto_banco_horas_config SET ativo=false WHERE tenant_id=v_t AND forma_compensacao='QA-COMPFALTA-FLUXO';

  -- Instrumentos vigentes
  v_empresa := public.ponto_empresa_do_cpf(v_t, v_cpf);
  INSERT INTO public.ponto_banco_horas_config
    (tenant_id, empresa_id, tipo, prazo_compensacao_dias, forma_compensacao, data_inicio, ativo)
  VALUES (v_t, v_empresa, 'mensal', 90, 'QA-COMPFALTA-FLUXO', v_dia - 30, true);
  INSERT INTO public.ponto_acordos
    (tenant_id, empresa_id, colaborador_cpf, tipo, titulo, vigencia_inicio, vigencia_fim, permite_compensacao_falta, ativo)
  VALUES (v_t, v_empresa, v_cpf, 'individual', 'QA Acordo Comp Falta Fluxo', v_dia - 30, v_dia + 300, true, true);

  -- Registrar + autorizar
  v_reg := public.ponto_registrar_compensacao_falta(v_t, v_cpf, v_dia, 'Teste fluxo');
  v_id  := (v_reg->>'id')::uuid;
  v_aut := public.ponto_autorizar_compensacao_falta(v_t, v_id, 'Gestor QA');

  -- Antes da ciência: nenhum movimento
  SELECT b.id INTO v_banco FROM public.ponto_banco_horas b
   WHERE b.tenant_id=v_t AND regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g')=v_cpf
     AND b.competencia=to_char(v_dia,'YYYY-MM') LIMIT 1;
  v_movs_antes := (SELECT count(*) FROM public.ponto_banco_horas_movimentacoes m
                   WHERE m.banco_horas_id=v_banco AND m.tipo='compensacao_falta' AND m.data_referencia=v_dia);

  -- Ciência -> efetiva
  v_cie := public.ponto_dar_ciencia_compensacao_falta(v_t, v_id, 'Colaborador QA');

  SELECT b.id INTO v_banco FROM public.ponto_banco_horas b
   WHERE b.tenant_id=v_t AND regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g')=v_cpf
     AND b.competencia=to_char(v_dia,'YYYY-MM') LIMIT 1;
  v_movs_depois := (SELECT count(*) FROM public.ponto_banco_horas_movimentacoes m
                    WHERE m.banco_horas_id=v_banco AND m.tipo='compensacao_falta' AND m.data_referencia=v_dia);
  v_status := (SELECT c.status FROM public.ponto_compensacao_falta c
               WHERE c.tenant_id=v_t AND c.colaborador_cpf=v_cpf AND c.data_falta=v_dia LIMIT 1);

  IF COALESCE(v_aut->>'status','') <> 'autorizada' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: autorização não deixou em autorizada (retorno: %s).', v_aut);
  ELSIF v_movs_antes <> 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: houve %s movimento(s) no banco ANTES da ciência — o débito não deveria '
             || 'existir sem ciência (RQ-048).', v_movs_antes);
  ELSIF v_status <> 'efetivada' OR v_movs_depois <> 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: após a ciência, status=%s e %s movimento(s) (esperado efetivada e 1 débito). '
             || 'Retorno da ciência: %s', v_status, v_movs_depois, v_cie);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Autorizada sem tocar no banco; na ciência entrou 1 débito de %s min '
             || '(tipo compensacao_falta) e a solicitação ficou efetivada.', (v_cie->>'minutos'));
    r.detalhe := jsonb_build_object('autorizacao', v_aut, 'ciencia', v_cie);
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-480', 'qa_caso_ponto_480', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

DO $fim$
BEGIN
  RAISE NOTICE 'Compensacao de falta — Fatia 2 (autorizacao/homologacao/ciencia/efetivacao) aplicada.';
END $fim$;
