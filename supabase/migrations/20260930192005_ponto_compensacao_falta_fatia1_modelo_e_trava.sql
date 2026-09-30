-- ============================================================================
-- Compensação de falta — FATIA 1: modelo de dados + trava do instrumento
-- ----------------------------------------------------------------------------
-- Objetivo do recurso (RQ-047/048/050/051): permitir converter uma FALTA
-- injustificada em DÉBITO do banco de horas, de forma controlada — só com
-- instrumento normativo vigente, autorização do gestor e ciência do
-- colaborador; mantendo a falta como ocorrência e sem cobrar duas vezes.
--
-- Esta fatia NÃO tem efeito financeiro. Ela só:
--   1. cria o campo que marca um acordo como autorizador de compensação de
--      falta (RQ-047, decisão D-15: exige acordo individual de compensação,
--      além do acordo de banco);
--   2. cria a tabela de SOLICITAÇÃO/estado da compensação (ponto_compensacao_falta);
--   3. cria a TRAVA de leitura (ponto_falta_compensavel): só é compensável se
--      houver regime de banco vigente E acordo de compensação vigente;
--   4. cria ponto_registrar_compensacao_falta, que apenas REGISTRA a solicitação
--      em estado 'pendente_autorizacao' (sem tocar em saldo, folha ou DSR).
--
-- Autorização/ciência (Fatia 2) e reconciliação com folha/DSR (Fatia 3) vêm
-- em entregas seguintes. Enquanto isso, nada muda no comportamento atual: a
-- falta segue neutra no banco (PONTO-474) até que uma solicitação seja
-- efetivada — o que ainda não acontece nesta fatia.
-- ============================================================================

-- ---------------------------------------------------------------------
-- 1) Acordo pode autorizar compensação de falta (D-15)
-- ---------------------------------------------------------------------
ALTER TABLE public.ponto_acordos
  ADD COLUMN IF NOT EXISTS permite_compensacao_falta boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.ponto_acordos.permite_compensacao_falta IS
  'Quando true, este acordo (tipicamente individual) autoriza converter falta injustificada em débito do banco de horas (CLT art. 462; compensação de falta é instituto distinto do acordo de banco).';

-- ---------------------------------------------------------------------
-- 2) Tabela de solicitação/estado da compensação de falta
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ponto_compensacao_falta (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  empresa_id uuid,
  colaborador_cpf text NOT NULL,
  colaborador_id uuid,
  data_falta date NOT NULL,
  minutos integer NOT NULL,
  acordo_id uuid REFERENCES public.ponto_acordos(id) ON DELETE SET NULL,
  regime_id uuid REFERENCES public.ponto_banco_horas_config(id) ON DELETE SET NULL,
  prazo_compensacao_dias integer,
  prazo_ate date,
  -- ciclo de vida: pendente_autorizacao -> autorizada -> ciente -> efetivada
  --                (ou recusada / cancelada em qualquer ponto antes de efetivar)
  status text NOT NULL DEFAULT 'pendente_autorizacao'
    CHECK (status IN ('pendente_autorizacao','autorizada','ciente','efetivada','recusada','cancelada')),
  motivo text,
  -- autorização (D-17: gestor autoriza; RH homologa acima de um limite)
  autorizado_por uuid,
  autorizado_por_nome text,
  autorizado_em timestamptz,
  homologado_por uuid,
  homologado_por_nome text,
  homologado_em timestamptz,
  -- ciência do colaborador (débito fica provisório até aqui)
  ciencia_em timestamptz,
  ciencia_por text,
  -- preenchido na efetivação (Fatia 2): a movimentação de débito gerada
  movimentacao_id uuid,
  created_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- No máximo uma compensação viva por dia de falta (as recusadas/canceladas não contam).
CREATE UNIQUE INDEX IF NOT EXISTS ux_compensacao_falta_viva
  ON public.ponto_compensacao_falta (tenant_id, colaborador_cpf, data_falta)
  WHERE status NOT IN ('recusada','cancelada');

ALTER TABLE public.ponto_compensacao_falta ENABLE ROW LEVEL SECURITY;

DO $rls$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies
                 WHERE tablename='ponto_compensacao_falta' AND policyname='compfalta tenant select') THEN
    CREATE POLICY "compfalta tenant select" ON public.ponto_compensacao_falta
      FOR SELECT USING (tenant_id = public.get_user_tenant_id());
    CREATE POLICY "compfalta tenant insert" ON public.ponto_compensacao_falta
      FOR INSERT WITH CHECK (tenant_id = public.get_user_tenant_id());
    CREATE POLICY "compfalta tenant update" ON public.ponto_compensacao_falta
      FOR UPDATE USING (tenant_id = public.get_user_tenant_id());
    CREATE POLICY "compfalta tenant delete" ON public.ponto_compensacao_falta
      FOR DELETE USING (tenant_id = public.get_user_tenant_id());
  END IF;
END $rls$;

-- ---------------------------------------------------------------------
-- 3) TRAVA (somente leitura): esta falta é compensável?
--    RQ-047 + D-15: exige regime de banco vigente E acordo de compensação
--    (individual, permite_compensacao_falta=true) vigente na data.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_falta_compensavel(
  p_tenant_id uuid,
  p_colaborador_cpf text,
  p_data date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_cpf text := regexp_replace(COALESCE(p_colaborador_cpf,''),'[^0-9]','','g');
  v_empresa uuid;
  v_status text;
  v_jornada int;
  v_regime public.ponto_banco_horas_config;
  v_acordo_id uuid;
  v_regime_ok boolean;
  v_motivos text[] := ARRAY[]::text[];
BEGIN
  IF auth.uid() IS NOT NULL AND public.get_user_tenant_id() IS DISTINCT FROM p_tenant_id THEN
    RAISE EXCEPTION 'Acesso negado ao tenant';
  END IF;

  v_empresa := public.ponto_empresa_do_cpf(p_tenant_id, p_colaborador_cpf);

  -- O dia precisa ser uma falta com jornada prevista.
  v_status := (SELECT d.status FROM public.ponto_diario d
               WHERE d.tenant_id = p_tenant_id
                 AND regexp_replace(COALESCE(d.colaborador_cpf,''),'[^0-9]','','g') = v_cpf
                 AND d.data = p_data
               LIMIT 1);
  v_jornada := (SELECT j.jornada_min FROM public.ponto_jornada_do_dia(p_tenant_id, p_colaborador_cpf, NULL, p_data) j);

  IF COALESCE(v_status,'') <> 'falta' THEN
    v_motivos := v_motivos || ARRAY['O dia não está registrado como falta (status atual: '
                 || COALESCE(v_status,'sem registro') || ').'];
  END IF;
  IF COALESCE(v_jornada,0) <= 0 THEN
    v_motivos := v_motivos || ARRAY['A escala não prevê jornada neste dia — não há o que compensar.'];
  END IF;

  -- Regime de banco vigente (o próprio banco precisa existir para receber o débito).
  v_regime := public.ponto_banco_regime_vigente(p_tenant_id, p_colaborador_cpf, NULL, p_data);
  v_regime_ok := v_regime.id IS NOT NULL;
  IF NOT v_regime_ok THEN
    v_motivos := v_motivos || ARRAY['Não há regime de banco de horas vigente para este vínculo na data.'];
  END IF;

  -- Acordo de compensação de falta vigente (D-15: além do acordo de banco).
  v_acordo_id := (SELECT ac.id FROM public.ponto_acordos ac
                  WHERE ac.tenant_id = p_tenant_id
                    AND COALESCE(ac.ativo,true) = true
                    AND COALESCE(ac.permite_compensacao_falta,false) = true
                    AND (ac.empresa_id IS NULL OR ac.empresa_id = v_empresa)
                    AND (ac.vigencia_inicio IS NULL OR ac.vigencia_inicio <= p_data)
                    AND (ac.vigencia_fim IS NULL OR ac.vigencia_fim >= p_data)
                  ORDER BY (ac.empresa_id IS NOT NULL) DESC, ac.vigencia_inicio DESC NULLS LAST
                  LIMIT 1);
  IF v_acordo_id IS NULL THEN
    v_motivos := v_motivos || ARRAY['Não há acordo de compensação de falta vigente e vinculado (CLT art. 462).'];
  END IF;

  RETURN jsonb_build_object(
    'compensavel', (array_length(v_motivos,1) IS NULL),
    'competencia', to_char(p_data,'YYYY-MM'),
    'data_falta', p_data,
    'status_dia', v_status,
    'jornada_min', COALESCE(v_jornada,0),
    'regime_id', v_regime.id,
    'prazo_compensacao_dias', v_regime.prazo_compensacao_dias,
    'acordo_id', v_acordo_id,
    'motivos', to_jsonb(v_motivos),
    'avaliado_em', now()
  );
END;
$function$;

COMMENT ON FUNCTION public.ponto_falta_compensavel(uuid, text, date) IS
  'Somente leitura. Diz se a falta do dia pode ser compensada: exige status=falta com jornada, regime de banco vigente e acordo de compensação de falta vigente (RQ-047, D-15). Retorna jsonb com compensavel + motivos.';

-- ---------------------------------------------------------------------
-- 4) Registrar a solicitação de compensação (sem efeito financeiro)
--    Cria a solicitação em 'pendente_autorizacao'. A efetivação (débito no
--    banco) só ocorre na Fatia 2, após autorização e ciência.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_registrar_compensacao_falta(
  p_tenant_id uuid,
  p_colaborador_cpf text,
  p_data date,
  p_motivo text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_cpf text := regexp_replace(COALESCE(p_colaborador_cpf,''),'[^0-9]','','g');
  v_gate jsonb;
  v_empresa uuid;
  v_colab uuid;
  v_regime public.ponto_banco_horas_config;
  v_prazo int;
  v_min int;
  v_id uuid;
  v_existente public.ponto_compensacao_falta;
BEGIN
  IF auth.uid() IS NOT NULL AND public.get_user_tenant_id() IS DISTINCT FROM p_tenant_id THEN
    RAISE EXCEPTION 'Acesso negado ao tenant';
  END IF;

  v_gate := public.ponto_falta_compensavel(p_tenant_id, p_colaborador_cpf, p_data);
  IF (v_gate->>'compensavel')::boolean IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false,
      'motivo', 'Falta não é compensável nesta data.',
      'detalhe', v_gate->'motivos');
  END IF;

  -- Já existe uma solicitação viva para este dia? Idempotente.
  SELECT * INTO v_existente
  FROM public.ponto_compensacao_falta c
  WHERE c.tenant_id = p_tenant_id
    AND regexp_replace(COALESCE(c.colaborador_cpf,''),'[^0-9]','','g') = v_cpf
    AND c.data_falta = p_data
    AND c.status NOT IN ('recusada','cancelada')
  LIMIT 1;
  IF v_existente.id IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'ja_existe', true,
      'id', v_existente.id, 'status', v_existente.status, 'minutos', v_existente.minutos);
  END IF;

  v_empresa := public.ponto_empresa_do_cpf(p_tenant_id, p_colaborador_cpf);
  v_colab := (SELECT a.id FROM public.admissoes a
              WHERE a.tenant_id = p_tenant_id AND a.cpf = v_cpf
                AND COALESCE(a.inativo,false) = false
              ORDER BY a.data_admissao DESC LIMIT 1);
  v_regime := public.ponto_banco_regime_vigente(p_tenant_id, p_colaborador_cpf, NULL, p_data);
  v_prazo := COALESCE(v_regime.prazo_compensacao_dias, 180);  -- D-13: prazo do regime
  v_min := COALESCE((v_gate->>'jornada_min')::int, 0);

  INSERT INTO public.ponto_compensacao_falta
    (tenant_id, empresa_id, colaborador_cpf, colaborador_id, data_falta, minutos,
     acordo_id, regime_id, prazo_compensacao_dias, prazo_ate, status, motivo, created_by)
  VALUES
    (p_tenant_id, v_empresa, v_cpf, v_colab, p_data, v_min,
     NULLIF(v_gate->>'acordo_id','')::uuid, v_regime.id, v_prazo, p_data + v_prazo,
     'pendente_autorizacao', p_motivo, COALESCE(auth.uid()::text,'sistema'))
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('success', true, 'ja_existe', false,
    'id', v_id, 'status', 'pendente_autorizacao', 'minutos', v_min,
    'prazo_ate', p_data + v_prazo);
END;
$function$;

COMMENT ON FUNCTION public.ponto_registrar_compensacao_falta(uuid, text, date, text) IS
  'Registra a solicitação de compensação de falta em pendente_autorizacao, se a trava (ponto_falta_compensavel) permitir. NÃO toca em saldo/folha/DSR — a efetivação vem na Fatia 2 após autorização e ciência. Idempotente por (tenant, cpf, data).';

REVOKE ALL ON FUNCTION public.ponto_registrar_compensacao_falta(uuid, text, date, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.ponto_registrar_compensacao_falta(uuid, text, date, text) TO authenticated;

-- ---------------------------------------------------------------------
-- 5) QA PONTO-479 — a trava do instrumento
-- ---------------------------------------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-479',
  m.id,
  'Compensar falta só com instrumento vigente',
  'Converter falta injustificada em débito do banco é instituto distinto do acordo de banco '
  || '(CLT art. 462). Sem regime de banco vigente E acordo de compensação vigente, o sistema não '
  || 'oferece a opção e trata como falta. Com os dois instrumentos, registra a solicitação em '
  || 'pendente_autorizacao — sem tocar no saldo (a efetivação depende de autorização e ciência).',
  'negativo',
  'api',
  'critica',
  'aprovado',
  'CLT art. 462; art. 59, §2º',
  jsonb_build_array(
    jsonb_build_object('ordem', 1,
      'acao', 'Sem instrumento vinculado, avaliar se a falta é compensável',
      'esperado', 'compensavel = false, com motivo apontando a falta de instrumento'),
    jsonb_build_object('ordem', 2,
      'acao', 'Com regime de banco e acordo de compensação vigentes, registrar a compensação',
      'esperado', 'A solicitação nasce em pendente_autorizacao, sem débito no banco')
  ),
  'em_triagem',
  'Recurso compensação de falta (RQ-047/048), Fatia 1.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_479()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(4791);
  v_dia date := public.qa_dia_util_passado();
  v_empresa uuid;
  v_gate1 jsonb; v_gate2 jsonb; v_reg jsonb;
  v_status_compfalta text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Sem instrumento a falta não é compensável; com instrumento vira solicitação pendente';
  r.esperado    := 'compensavel=false sem instrumento; pendente_autorizacao com instrumento, sem débito';

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();

  -- Vínculo + escala + um dia de FALTA
  IF NOT EXISTS (SELECT 1 FROM public.admissoes a
                  WHERE a.tenant_id = v_t AND a.cpf = v_cpf AND COALESCE(a.inativo,false)=false) THEN
    PERFORM public.qa_ponto_admissao('QA Compensacao Falta', 4791);
  END IF;
  PERFORM public.qa_ponto_escala_tol(v_cpf, 'QA Compensacao Falta', 480, 10, v_dia - 5, NULL);
  PERFORM public.qa_ponto_dia_min(v_cpf, 'QA Compensacao Falta', v_dia, 0);
  UPDATE public.ponto_diario
     SET status = 'falta', entrada = NULL, saida = NULL, horas_trabalhadas = INTERVAL '0'
   WHERE tenant_id = v_t AND colaborador_cpf = v_cpf AND data = v_dia;

  -- Limpa instrumentos de corridas anteriores (idempotência do teste)
  DELETE FROM public.ponto_compensacao_falta
    WHERE tenant_id = v_t AND colaborador_cpf = v_cpf;
  UPDATE public.ponto_acordos SET ativo = false
    WHERE tenant_id = v_t AND titulo = 'QA Acordo Compensacao Falta';
  UPDATE public.ponto_banco_horas_config SET ativo = false
    WHERE tenant_id = v_t AND forma_compensacao = 'QA-COMPFALTA';

  -- PASSO 1: sem instrumento -> não compensável
  v_gate1 := public.ponto_falta_compensavel(v_t, v_cpf, v_dia);

  -- PASSO 2: cria regime de banco + acordo de compensação vigentes
  v_empresa := public.ponto_empresa_do_cpf(v_t, v_cpf);
  INSERT INTO public.ponto_banco_horas_config
    (tenant_id, empresa_id, tipo, prazo_compensacao_dias, forma_compensacao, data_inicio, ativo)
  VALUES (v_t, v_empresa, 'mensal', 90, 'QA-COMPFALTA', v_dia - 30, true);
  INSERT INTO public.ponto_acordos
    (tenant_id, empresa_id, tipo, titulo, vigencia_inicio, vigencia_fim, permite_compensacao_falta, ativo)
  VALUES (v_t, v_empresa, 'individual', 'QA Acordo Compensacao Falta', v_dia - 30, v_dia + 300, true, true);

  v_gate2 := public.ponto_falta_compensavel(v_t, v_cpf, v_dia);
  v_reg   := public.ponto_registrar_compensacao_falta(v_t, v_cpf, v_dia, 'Teste QA');

  v_status_compfalta := (SELECT c.status FROM public.ponto_compensacao_falta c
                         WHERE c.tenant_id = v_t AND c.colaborador_cpf = v_cpf AND c.data_falta = v_dia
                         LIMIT 1);

  IF (v_gate1->>'compensavel')::boolean IS NOT FALSE THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: sem regime/acordo vigente, o sistema considerou a falta compensável '
             || '(deveria recusar por falta de instrumento — CLT art. 462). Retorno: %s', v_gate1);
  ELSIF (v_gate2->>'compensavel')::boolean IS NOT TRUE THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: com regime de banco e acordo de compensação vigentes, a trava ainda '
             || 'recusou. Retorno: %s', v_gate2);
  ELSIF COALESCE(v_reg->>'success','false') <> 'true' OR v_status_compfalta IS DISTINCT FROM 'pendente_autorizacao' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: com instrumento, a solicitação não nasceu em pendente_autorizacao '
             || '(registro=%s, status=%s).', v_reg, COALESCE(v_status_compfalta,'sem linha'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Sem instrumento a falta não é compensável (motivos: %s); com regime + acordo '
             || 'vigentes a solicitação nasceu em pendente_autorizacao, sem débito no banco.',
             v_gate1->'motivos');
    r.detalhe := jsonb_build_object('sem_instrumento', v_gate1, 'com_instrumento', v_gate2, 'registro', v_reg);
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-479', 'qa_caso_ponto_479', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

DO $fim$
BEGIN
  RAISE NOTICE 'Compensacao de falta — Fatia 1 (modelo + trava do instrumento) aplicada. Sem efeito financeiro.';
END $fim$;
