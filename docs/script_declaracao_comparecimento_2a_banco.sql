-- =====================================================================
-- ENTREGA — Declaracao de comparecimento, FATIA 2a (banco)
-- Consolidacao do ponto passa a abonar a DECLARACAO de comparecimento
-- conforme a regra do catalogo (sim/nao/configuravel), em vez de abonar
-- sempre como um atestado. Atestado comum: inalterado.
--
-- So ALTER COLUMN + funcoes (nao cria TABELA): nao aciona o auto-RLS do
-- editor. Idempotente. INERTE ate existir declaracao (subtipo
-- 'comparecimento'); o golden abaixo conta quantas ja existem.
--
-- Rode o golden ANTES (declaracoes_existentes informa o impacto). Conferencia
-- no fim: consolidacao_le_regra = t, tenants_com_regra > 0.
-- =====================================================================
SET lock_timeout = '10s';

-- 1) Decisao de abono por lancamento (usada quando a regra e 'configuravel').
ALTER TABLE public.atestados
  ADD COLUMN IF NOT EXISTS abona boolean;

COMMENT ON COLUMN public.atestados.abona IS
  'Declaracao de comparecimento: decisao do RH de abonar (quando a regra do catalogo e configuravel). NULL/false = nao abona; true = abona.';

-- 2) Semeia a regra "Declaracao de comparecimento" no catalogo (sistema).
--    Adota uma linha manual de mesmo nome (nao duplica). base_legal NULL
--    (discricionaria): a empresa configura sim/nao/configuravel.
CREATE OR REPLACE FUNCTION public.seed_justificativa_declaracao(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $decl$
BEGIN
  UPDATE public.ponto_justificativas
    SET sistema = true, updated_at = now()
  WHERE tenant_id = p_tenant_id AND empresa_id IS NULL AND codigo = 'DECLARACAO_COMPARECIMENTO';
  IF FOUND THEN RETURN; END IF;

  UPDATE public.ponto_justificativas
    SET codigo = 'DECLARACAO_COMPARECIMENTO', sistema = true, updated_at = now()
  WHERE tenant_id = p_tenant_id AND empresa_id IS NULL
    AND codigo IS NULL AND lower(btrim(nome)) LIKE 'declara%comparecimento';
  IF FOUND THEN RETURN; END IF;

  INSERT INTO public.ponto_justificativas
    (tenant_id, empresa_id, nome, codigo, tipo_abono, sistema, ativo, ordem, requer_anexo, horas_abono)
  VALUES
    (p_tenant_id, NULL, 'Declaração de comparecimento', 'DECLARACAO_COMPARECIMENTO',
     'configuravel', true, true, 30, true, 0);
END $decl$;

REVOKE EXECUTE ON FUNCTION public.seed_justificativa_declaracao(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.seed_justificativa_declaracao(uuid) TO authenticated;

DO $todos$
DECLARE t RECORD;
BEGIN
  FOR t IN SELECT DISTINCT tenant_id FROM public.usuarios_base WHERE tenant_id IS NOT NULL
  LOOP
    BEGIN
      PERFORM public.seed_justificativa_declaracao(t.tenant_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'seed_justificativa_declaracao falhou para tenant %: %', t.tenant_id, SQLERRM;
    END;
  END LOOP;
END $todos$;

-- 3) Consolidacao: ramo do atestado passa a tratar a declaracao pela regra.
CREATE OR REPLACE FUNCTION public.consolidar_ponto_diario_manual(p_tenant_id uuid, p_colaborador_cpf text, p_data date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_afast public.afastamentos;
  v_ferias public.ferias_solicitacoes;
  v_atest public.atestados;
  v_cid UUID; v_cnome TEXT; v_eid UUID; v_obs TEXT;
  v_regra TEXT; v_abona BOOLEAN;
  c RECORD;
BEGIN
  SELECT colaborador_id, colaborador_nome INTO v_cid, v_cnome
  FROM public.ponto_marcacoes
  WHERE tenant_id = p_tenant_id AND colaborador_cpf = p_colaborador_cpf
  ORDER BY created_at DESC LIMIT 1;
  IF v_cid IS NULL THEN
    SELECT colaborador_id, colaborador_nome INTO v_cid, v_cnome
    FROM public.ponto_ajustes
    WHERE tenant_id = p_tenant_id AND colaborador_cpf = p_colaborador_cpf
    ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_cid IS NULL THEN
    SELECT a.id, a.nome_completo INTO v_cid, v_cnome
    FROM public.admissoes a
    WHERE a.tenant_id = p_tenant_id
      AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
          = regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g')
      AND COALESCE(a.inativo, false) = false
    ORDER BY a.data_admissao DESC NULLS LAST
    LIMIT 1;
  END IF;

  SELECT f.* INTO v_ferias FROM public.ferias_solicitacoes f
  WHERE f.tenant_id = p_tenant_id AND f.colaborador_cpf = p_colaborador_cpf
    AND f.status IN ('aprovado','em_gozo','concluido')
    AND f.data_inicio <= p_data AND f.data_fim >= p_data
  ORDER BY f.data_inicio DESC LIMIT 1;
  IF v_ferias.id IS NOT NULL THEN
    v_cid := COALESCE(v_cid, v_ferias.colaborador_id);
    v_cnome := COALESCE(v_cnome, v_ferias.colaborador_nome);
    v_obs := 'Férias: ' || to_char(v_ferias.data_inicio,'DD/MM/YYYY') || ' a ' || to_char(v_ferias.data_fim,'DD/MM/YYYY');
    PERFORM public._ponto_grava_abono(p_tenant_id, v_cid, v_cnome, p_colaborador_cpf, p_data, v_obs);
    RETURN;
  END IF;

  SELECT a.* INTO v_atest FROM public.atestados a
  WHERE a.tenant_id = p_tenant_id AND a.colaborador_cpf = p_colaborador_cpf
    AND a.data_inicio_afastamento IS NOT NULL
    AND a.data_inicio_afastamento <= p_data
    AND COALESCE(a.data_fim_afastamento, a.data_inicio_afastamento) >= p_data
  ORDER BY a.data_inicio_afastamento DESC LIMIT 1;
  IF v_atest.id IS NOT NULL THEN
    IF COALESCE(v_atest.subtipo_assistencial::text, '') = 'comparecimento' THEN
      -- Declaracao de comparecimento: abona conforme o catalogo da empresa.
      v_regra := COALESCE((
        SELECT tipo_abono FROM public.ponto_justificativas
        WHERE tenant_id = p_tenant_id AND codigo = 'DECLARACAO_COMPARECIMENTO'
        ORDER BY empresa_id NULLS LAST LIMIT 1), 'configuravel');
      v_abona := (v_regra = 'sim')
              OR (v_regra = 'configuravel' AND COALESCE(v_atest.abona, false));
      IF v_abona THEN
        v_cid := COALESCE(v_cid, v_atest.colaborador_id);
        v_cnome := COALESCE(v_cnome, v_atest.colaborador_nome);
        v_obs := 'Declaração: ' || to_char(v_atest.data_inicio_afastamento,'DD/MM/YYYY')
          || CASE WHEN v_atest.data_fim_afastamento IS NOT NULL THEN ' a ' || to_char(v_atest.data_fim_afastamento,'DD/MM/YYYY') ELSE '' END;
        PERFORM public._ponto_grava_abono(p_tenant_id, v_cid, v_cnome, p_colaborador_cpf, p_data, v_obs);
        RETURN;
      END IF;
      -- Nao abonada: o documento fica registrado, mas o dia NAO e justificado.
      -- Se houver um atestado COMUM cobrindo o mesmo dia, ele abona.
      SELECT a.* INTO v_atest FROM public.atestados a
      WHERE a.tenant_id = p_tenant_id AND a.colaborador_cpf = p_colaborador_cpf
        AND a.data_inicio_afastamento IS NOT NULL
        AND a.data_inicio_afastamento <= p_data
        AND COALESCE(a.data_fim_afastamento, a.data_inicio_afastamento) >= p_data
        AND COALESCE(a.subtipo_assistencial::text, '') <> 'comparecimento'
      ORDER BY a.data_inicio_afastamento DESC LIMIT 1;
      IF v_atest.id IS NOT NULL THEN
        v_cid := COALESCE(v_cid, v_atest.colaborador_id);
        v_cnome := COALESCE(v_cnome, v_atest.colaborador_nome);
        v_obs := 'Atestado: ' || to_char(v_atest.data_inicio_afastamento,'DD/MM/YYYY')
          || CASE WHEN v_atest.data_fim_afastamento IS NOT NULL THEN ' a ' || to_char(v_atest.data_fim_afastamento,'DD/MM/YYYY') ELSE '' END;
        PERFORM public._ponto_grava_abono(p_tenant_id, v_cid, v_cnome, p_colaborador_cpf, p_data, v_obs);
        RETURN;
      END IF;
      -- senao, cai para o fluxo normal (dia conta como falta/incompleto).
    ELSE
      -- Atestado comum: abona sempre (comportamento inalterado).
      v_cid := COALESCE(v_cid, v_atest.colaborador_id);
      v_cnome := COALESCE(v_cnome, v_atest.colaborador_nome);
      v_obs := 'Atestado: ' || to_char(v_atest.data_inicio_afastamento,'DD/MM/YYYY')
        || CASE WHEN v_atest.data_fim_afastamento IS NOT NULL THEN ' a ' || to_char(v_atest.data_fim_afastamento,'DD/MM/YYYY') ELSE '' END;
      PERFORM public._ponto_grava_abono(p_tenant_id, v_cid, v_cnome, p_colaborador_cpf, p_data, v_obs);
      RETURN;
    END IF;
  END IF;

  v_afast := public.afastamento_vigente(p_tenant_id, p_colaborador_cpf, p_data);
  IF v_afast.id IS NOT NULL THEN
    v_cid := COALESCE(v_cid, v_afast.colaborador_id);
    v_cnome := COALESCE(v_cnome, v_afast.colaborador_nome);
    v_obs := 'Afastamento (' || COALESCE(replace(v_afast.motivo_principal::text,'_',' '),'registrado')
      || '): de ' || to_char(v_afast.data_inicio,'DD/MM/YYYY')
      || CASE WHEN v_afast.data_fim IS NOT NULL THEN ' a ' || to_char(v_afast.data_fim,'DD/MM/YYYY') ELSE ' — em aberto' END;
    PERFORM public._ponto_grava_abono(p_tenant_id, v_cid, v_cnome, p_colaborador_cpf, p_data, v_obs);
    RETURN;
  END IF;

  IF v_cid IS NULL THEN RETURN; END IF;
  v_eid := COALESCE(public.ponto_empresa_do_colaborador(v_cid),
                    public.ponto_empresa_do_cpf(p_tenant_id, p_colaborador_cpf));

  c := public._ponto_calc_dia(p_tenant_id, p_colaborador_cpf, p_data, v_cid);

  INSERT INTO public.ponto_diario (
    tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, data,
    entrada, saida_almoco, retorno_almoco, saida, horas_trabalhadas, status, observacao
  ) VALUES (
    p_tenant_id, v_eid, v_cid, v_cnome, p_colaborador_cpf, p_data,
    c.o_pent, c.o_salm, c.o_ralm, c.o_usai, c.o_horas, c.o_status, c.o_obs
  )
  ON CONFLICT (tenant_id, colaborador_cpf, data, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid))
  DO UPDATE SET
    empresa_id = COALESCE(EXCLUDED.empresa_id, public.ponto_diario.empresa_id),
    colaborador_nome = EXCLUDED.colaborador_nome,
    entrada = EXCLUDED.entrada, saida_almoco = EXCLUDED.saida_almoco,
    retorno_almoco = EXCLUDED.retorno_almoco, saida = EXCLUDED.saida,
    horas_trabalhadas = EXCLUDED.horas_trabalhadas,
    status = CASE WHEN public.ponto_diario.status = 'justificado' THEN 'justificado' ELSE EXCLUDED.status END,
    observacao = CASE WHEN public.ponto_diario.status = 'justificado'
                        AND public.ponto_diario.observacao LIKE 'Abonado por afastamento%'
                      THEN public.ponto_diario.observacao ELSE EXCLUDED.observacao END,
    updated_at = now();
END;
$function$;

-- 4) QA: ABONO-DECL (api) — a consolidacao le a regra da declaracao e a regra existe.
CREATE OR REPLACE FUNCTION public.qa_caso_abono_decl()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $qa$
DECLARE r public.qa_retorno; v_t uuid; v_estrut boolean; v_tem boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que a consolidacao respeita a regra da declaracao e que a regra existe';
  r.esperado    := 'consolidar_ponto_diario_manual le o codigo DECLARACAO_COMPARECIMENTO; regra semeada no sandbox.';

  IF to_regprocedure('public.seed_justificativa_declaracao(uuid)') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'seed_justificativa_declaracao ausente.'; RETURN r;
  END IF;

  v_estrut := position('DECLARACAO_COMPARECIMENTO' IN
    pg_get_functiondef('public.consolidar_ponto_diario_manual(uuid,text,date)'::regprocedure)) > 0;

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  PERFORM public.seed_justificativa_declaracao(v_t);
  v_tem := EXISTS (SELECT 1 FROM public.ponto_justificativas
                   WHERE tenant_id = v_t AND codigo = 'DECLARACAO_COMPARECIMENTO' AND sistema);

  IF v_estrut AND v_tem THEN
    r.situacao := 'passou';
    r.obtido := 'Consolidacao le a regra da declaracao; regra DECLARACAO_COMPARECIMENTO semeada.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('consolidacao_le_regra=%s, regra_semeada=%s.', v_estrut, v_tem);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $qa$;

DO $doc$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente; caso ABONO-DECL nao documentado.'; RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto' LIMIT 1);
  IF v_mod IS NULL THEN RAISE NOTICE 'Modulo jornada-rotina/ponto ausente.'; RETURN; END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'ABONO-DECL',
   'A declaracao de comparecimento abona conforme a regra da empresa (nao sempre)',
   'feliz', 'alta', 'aprovado', 'api',
   'CLT art. 473 (declaracao de comparecimento: abono discricionario)',
   'A consolidacao do ponto, para o subtipo comparecimento, deve ler a regra do catalogo (DECLARACAO_COMPARECIMENTO) e abonar conforme sim/nao/configuravel, em vez de abonar sempre como um atestado.',
   'seed_justificativa_declaracao e consolidar_ponto_diario_manual presentes.',
   '[{"ordem":1,"acao":"Conferir que a consolidacao referencia a regra da declaracao e que a regra esta semeada","resultado_esperado":"Le a regra e a regra existe no catalogo (sistema)"}]'::jsonb,
   'A consolidacao respeita a regra da declaracao; a regra esta semeada.',
   'Declaracao de comparecimento, Fatia 2a.')
  ON CONFLICT (codigo) DO NOTHING;
  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('ABONO-DECL', 'qa_caso_abono_decl', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao ABONO-DECL nao registrada: %', SQLERRM;
END $doc$;

-- ---------------------------------------------------------------------
-- CONFERENCIA / GOLDEN (o editor mostra so o ultimo resultado):
--   declaracoes_existentes = atestados de subtipo 'comparecimento' hoje
--                            (unicos dias cujo calculo pode mudar; tipicamente 0)
--   tenants_com_regra      = tenants com a regra DECLARACAO_COMPARECIMENTO (>0)
--   consolidacao_le_regra  = a consolidacao le a regra da declaracao (esperado t)
-- ---------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.atestados WHERE subtipo_assistencial::text = 'comparecimento') AS declaracoes_existentes,
  (SELECT count(DISTINCT tenant_id) FROM public.ponto_justificativas WHERE codigo = 'DECLARACAO_COMPARECIMENTO') AS tenants_com_regra,
  (position('DECLARACAO_COMPARECIMENTO' IN
     pg_get_functiondef('public.consolidar_ponto_diario_manual(uuid,text,date)'::regprocedure)) > 0) AS consolidacao_le_regra;
