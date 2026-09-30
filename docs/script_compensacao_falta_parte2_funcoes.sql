-- ============================================================================
-- ENTREGA — Compensação de falta, PARTE 2 de 2: funções
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
-- RODAR DEPOIS DA PARTE 1 (estas funções usam a tabela ponto_compensacao_falta).
--
-- Este script só CRIA/SUBSTITUI FUNÇÃO (não cria tabela): o auxiliar de auto-RLS
-- do SQL Editor não liga, então os SELECT ... INTO das funções ficam a salvo.
-- Idempotente (CREATE OR REPLACE; o patch da folha só aplica se ainda não
-- estiver aplicado). Não altera nem apaga dado.
--
-- Ordem: trava e registro -> autorização/homologação/ciência/cancelamento ->
-- folha/DSR (não cobram a falta compensada duas vezes).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Trava de leitura + registro da solicitação (Fatia 1)
-- ----------------------------------------------------------------------------
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
                    AND (ac.colaborador_cpf IS NULL
                         OR regexp_replace(COALESCE(ac.colaborador_cpf,''),'[^0-9]','','g') = v_cpf)
                    AND (ac.vigencia_inicio IS NULL OR ac.vigencia_inicio <= p_data)
                    AND (ac.vigencia_fim IS NULL OR ac.vigencia_fim >= p_data)
                  ORDER BY (ac.colaborador_cpf IS NOT NULL) DESC,
                           (ac.empresa_id IS NOT NULL) DESC,
                           ac.vigencia_inicio DESC NULLS LAST
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

-- ----------------------------------------------------------------------------
-- Autorização (gestor), homologação (RH), ciência (efetiva o débito), cancelar
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- Folha e DSR não cobram a falta compensada duas vezes (Fatia 3)
-- ----------------------------------------------------------------------------
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

-- Conferência (o editor mostra só o último resultado): funções no lugar? (t)
SELECT
  to_regprocedure('public.ponto_falta_compensavel(uuid,text,date)') IS NOT NULL AS trava_ok,
  to_regprocedure('public.ponto_registrar_compensacao_falta(uuid,text,date,text)') IS NOT NULL AS registrar_ok,
  to_regprocedure('public.ponto_dar_ciencia_compensacao_falta(uuid,uuid,text)') IS NOT NULL AS ciencia_ok,
  to_regprocedure('public.ponto_faltas_compensadas_competencia(uuid,text,text)') IS NOT NULL AS helper_ok,
  position('[folha-desconta-falta-compensada]' IN
    pg_get_functiondef('public.ponto_compor_pacote_folha(uuid,uuid,text)'::regprocedure)) > 0 AS folha_ok,
  position('[dsr-ignora-falta-compensada]' IN
    pg_get_functiondef('public.ponto_dsr_competencia(uuid,text,text)'::regprocedure)) > 0 AS dsr_ok;
