-- ============================================================================
-- SCRIPT DE ENTREGA — Ponto, Fase 2 / F4: aprovar AUSÊNCIA vira lançamento em
-- Atestados (nunca batida). Espelho da migration
-- 20261029215446_ponto_fase2_f4_aprovacao_ausencia.sql.
--
-- ORDEM: depois do script da F3 (script_ponto_fase2_f3_pedido.sql) e ANTES de
-- publicar as telas. Sem ele, uma ausência aprovada não geraria o atestado.
--
-- Colar INTEIRO no SQL Editor. Idempotente. Não cria tabela e não altera dado
-- existente: colunas novas em atestados (vazias/padrão), funções novas e uma
-- REINJEÇÃO em processar_ajuste_ponto (a função NÃO é reescrita: dois trechos
-- são inseridos no corpo vigente, só se as âncoras aparecerem exatamente 1 vez;
-- senão nada muda e a conferência mostra ausencia_ok = false → PARE e avise).
-- Pedidos antigos e correções de batida seguem o caminho de hoje.
--
-- Desfazer a reinjeção (se preciso): rodar de novo o CREATE OR REPLACE de
-- processar_ajuste_ponto que estava em produção (guarde antes:
--   SELECT pg_get_functiondef('public.processar_ajuste_ponto(uuid,boolean,text)'::regprocedure);
-- e cole o resultado num arquivo ANTES de rodar este script).
--
-- A última consulta mostra: reinjeções aplicadas, sanidade da consolidação
-- (feriado neutro presente), colunas novas e o resultado dos casos PONTO-495 e
-- 496 (rodam no cercado de QA, com um gestor fictício, e desfazem tudo no fim).
-- ============================================================================

SET lock_timeout = '10s';

-- 1) atestados ----------------------------------------------------------------
ALTER TABLE public.atestados
  ADD COLUMN IF NOT EXISTS ajuste_id uuid,
  ADD COLUMN IF NOT EXISTS arquivo_bucket text NOT NULL DEFAULT 'atestados';

COMMENT ON COLUMN public.atestados.ajuste_id IS
  'Ajuste de ponto (ponto_ajustes.id) cuja aprovação lançou este atestado (ausência pedida pelo colaborador). Sem FK.';
COMMENT ON COLUMN public.atestados.arquivo_bucket IS
  'Bucket do arquivo: atestados (lançado em Atestados) ou ponto-ajustes-anexos (anexo do pedido de ajuste).';

CREATE UNIQUE INDEX IF NOT EXISTS uq_atestados_ajuste_id
  ON public.atestados (ajuste_id) WHERE ajuste_id IS NOT NULL;

-- 2) Quem é gestor/RH do tenant (mesma regra de processar_ajuste_ponto) --------
CREATE OR REPLACE FUNCTION public._ponto_usuario_gestor_do_tenant(p_uid uuid, p_tenant uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $gestor$
DECLARE
  v_acesso boolean;
  v_role text;
BEGIN
  IF p_uid IS NULL OR p_tenant IS NULL THEN RETURN false; END IF;
  v_acesso := EXISTS (SELECT 1 FROM public.usuarios_base ub
                       WHERE ub.auth_user_id = p_uid AND ub.tenant_id = p_tenant AND ub.status = 'ativo');
  v_role := (SELECT uv.tipo_vinculo::text
               FROM public.usuario_vinculos uv
               JOIN public.usuarios_base ub2 ON ub2.id = uv.usuario_id
              WHERE ub2.auth_user_id = p_uid AND uv.tenant_id = p_tenant AND uv.status = 'ativo'
                AND (uv.data_fim IS NULL OR uv.data_fim >= CURRENT_DATE)
              LIMIT 1);
  v_acesso := v_acesso OR v_role IS NOT NULL
           OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.user_id = p_uid AND p.tenant_id = p_tenant);
  IF NOT v_acesso THEN RETURN false; END IF;
  RETURN COALESCE(v_role IN ('gestor', 'administrador', 'proprietario', 'rh'), false)
      OR public.has_role(p_uid, 'manager'::public.app_role)
      OR public.has_role(p_uid, 'admin'::public.app_role)
      OR public.has_role(p_uid, 'owner'::public.app_role)
      OR public.has_role(p_uid, 'superadmin'::public.app_role)
      OR EXISTS (SELECT 1 FROM public.usuarios_base ub3
                  WHERE ub3.auth_user_id = p_uid
                    AND ub3.tipo_usuario IN ('gestor', 'administrador', 'proprietario', 'rh'));
END $gestor$;

REVOKE ALL ON FUNCTION public._ponto_usuario_gestor_do_tenant(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- 3) RH decide o abono de uma ausência Configurável ----------------------------
CREATE OR REPLACE FUNCTION public.ponto_ajuste_definir_abono(p_ajuste_id uuid, p_abonar boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $abono$
DECLARE
  v_uid uuid := auth.uid();
  v_aj public.ponto_ajustes;
  v_regra text;
  v_meu_cpf text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Não autenticado'; END IF;
  v_aj := (SELECT a FROM public.ponto_ajustes a WHERE a.id = p_ajuste_id);
  IF v_aj.id IS NULL THEN RAISE EXCEPTION 'Ajuste não encontrado'; END IF;
  IF NOT public._ponto_usuario_gestor_do_tenant(v_uid, v_aj.tenant_id) THEN
    RAISE EXCEPTION 'Apenas gestor/RH pode decidir o abono';
  END IF;
  v_meu_cpf := (SELECT regexp_replace(COALESCE(ub.cpf, ''), '\D', '', 'g') FROM public.usuarios_base ub
                 WHERE ub.auth_user_id = v_uid AND ub.tenant_id = v_aj.tenant_id LIMIT 1);
  IF COALESCE(v_meu_cpf, '') <> ''
     AND regexp_replace(COALESCE(v_aj.colaborador_cpf, ''), '\D', '', 'g') = v_meu_cpf THEN
    RAISE EXCEPTION 'Segregação de funções: não é permitido decidir o abono do próprio ponto.';
  END IF;
  IF v_aj.status <> 'pendente' THEN
    RAISE EXCEPTION 'Este ajuste já foi processado';
  END IF;
  IF v_aj.natureza IS DISTINCT FROM 'ausencia' THEN
    RAISE EXCEPTION 'Só ausência tem decisão de abono na aprovação.';
  END IF;
  v_regra := (SELECT j.tipo_abono FROM public.ponto_justificativas j WHERE j.id = v_aj.justificativa_id);
  IF v_regra IS DISTINCT FROM 'configuravel' THEN
    RAISE EXCEPTION 'A regra de abono desta justificativa é fixa (definida no catálogo).';
  END IF;
  UPDATE public.ponto_ajustes SET abonar_se_aprovado = COALESCE(p_abonar, false) WHERE id = p_ajuste_id;
  RETURN jsonb_build_object('success', true, 'abonar_se_aprovado', COALESCE(p_abonar, false));
END $abono$;

REVOKE ALL ON FUNCTION public.ponto_ajuste_definir_abono(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ponto_ajuste_definir_abono(uuid, boolean) TO authenticated;

-- 4) Ausência aprovada -> Atestados (idempotente) ------------------------------
CREATE OR REPLACE FUNCTION public._ponto_ajuste_lanca_ausencia(
  p_ajuste_id uuid, p_abona boolean, p_uid uuid, p_uid_nome text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $lanca$
DECLARE
  v_id uuid;
  v_aj public.ponto_ajustes;
  v_cod text;
  v_nome text;
  v_tipo text;
  v_sub text;
  v_anexo jsonb;
  v_path text;
  v_tam text;
  v_min int;
  v_empresa uuid;
  v_abona boolean := COALESCE(p_abona, false);
  v_periodo text;
  v_extra int;
BEGIN
  v_id := (SELECT a.id FROM public.atestados a WHERE a.ajuste_id = p_ajuste_id LIMIT 1);
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  v_aj := (SELECT a FROM public.ponto_ajustes a WHERE a.id = p_ajuste_id);
  IF v_aj.id IS NULL THEN
    RAISE EXCEPTION 'Ajuste não encontrado';
  END IF;

  v_anexo := COALESCE(v_aj.anexos, '[]'::jsonb) -> 0;
  v_path := NULLIF(btrim(COALESCE(v_anexo->>'url', v_anexo->>'path', '')), '');
  IF v_path IS NULL THEN
    RAISE EXCEPTION 'Esta ausência não tem a declaração ou o atestado anexado. Rejeite e peça para o colaborador reenviar com o documento.';
  END IF;
  v_tam := v_anexo->>'tamanho';
  v_extra := GREATEST(jsonb_array_length(COALESCE(v_aj.anexos, '[]'::jsonb)) - 1, 0);

  v_cod := (SELECT j.codigo FROM public.ponto_justificativas j WHERE j.id = v_aj.justificativa_id);
  v_nome := COALESCE((SELECT j.nome FROM public.ponto_justificativas j WHERE j.id = v_aj.justificativa_id), v_aj.motivo);

  v_tipo := CASE WHEN v_cod LIKE 'LEI\_%' AND v_cod NOT IN ('LEI_ACOMP_GESTANTE', 'LEI_ACOMP_FILHO') THEN 'licencas'
                 ELSE 'atestados' END;
  v_sub := CASE
             WHEN v_cod = 'DECLARACAO_COMPARECIMENTO' THEN 'comparecimento'
             WHEN v_cod = 'APP_ATESTADO_MEDICO' THEN 'medico'
             WHEN v_cod IN ('ATESTADO_ACOMPANHAMENTO', 'LEI_ACOMP_GESTANTE', 'LEI_ACOMP_FILHO') THEN 'acompanhante'
             WHEN v_cod = 'LEI_FALECIMENTO' THEN 'falecimento'
             WHEN v_cod = 'LEI_CASAMENTO' THEN 'casamento'
             WHEN v_cod LIKE 'LEI\_%' THEN 'outras_licencas'
             ELSE 'outros_motivos'
           END;

  IF NOT COALESCE(v_aj.dia_inteiro, false) THEN
    v_min := GREATEST((EXTRACT(EPOCH FROM (v_aj.ausencia_hora_fim - v_aj.ausencia_hora_inicio)) / 60)::int, 0);
    v_periodo := to_char(v_aj.data_referencia, 'DD/MM/YYYY') || ' das '
              || to_char(v_aj.ausencia_hora_inicio, 'HH24:MI') || ' às ' || to_char(v_aj.ausencia_hora_fim, 'HH24:MI');
  ELSE
    v_periodo := to_char(v_aj.data_referencia, 'DD/MM/YYYY') || ', dia inteiro';
  END IF;

  v_empresa := COALESCE(public.ponto_empresa_do_colaborador(v_aj.colaborador_id), v_aj.empresa_id,
                        public.ponto_empresa_do_cpf(v_aj.tenant_id, v_aj.colaborador_cpf));

  v_id := gen_random_uuid();
  INSERT INTO public.atestados (
    id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
    tipo, subtipo_assistencial, data_emissao, profissional_nome, profissional_registro,
    data_inicio_afastamento, data_fim_afastamento, unidade_afastamento,
    dias_afastamento, horas_afastamento, minutos_afastamento, abona,
    arquivo_url, arquivo_nome, arquivo_tamanho, arquivo_bucket,
    observacoes, criado_por, criado_por_nome, ajuste_id
  ) VALUES (
    v_id, v_aj.tenant_id, v_empresa, NULL, v_aj.colaborador_nome, v_aj.colaborador_cpf,
    v_tipo::public.atestado_tipo, v_sub::public.atestado_subtipo_assistencial,
    v_aj.data_referencia, 'Conforme documento anexado', '',
    CASE WHEN v_abona THEN v_aj.data_referencia END,
    CASE WHEN v_abona THEN v_aj.data_referencia END,
    CASE WHEN COALESCE(v_aj.dia_inteiro, false) THEN 'dias' ELSE 'horas' END,
    CASE WHEN COALESCE(v_aj.dia_inteiro, false) THEN 1 END,
    CASE WHEN COALESCE(v_aj.dia_inteiro, false) THEN NULL ELSE v_min / 60 END,
    CASE WHEN COALESCE(v_aj.dia_inteiro, false) THEN 0 ELSE v_min % 60 END,
    v_abona,
    v_path, COALESCE(NULLIF(v_anexo->>'nome', ''), 'anexo do ajuste'),
    CASE WHEN v_tam ~ '^[0-9]{1,9}$' THEN v_tam::int END,
    'ponto-ajustes-anexos',
    'Lançado pela aprovação do pedido de ajuste de ponto: ' || v_nome || ' (' || v_periodo || ')'
      || CASE WHEN v_abona THEN ' — abona.' ELSE ' — não abona (documento arquivado; o período segue como débito).' END
      || CASE WHEN NULLIF(btrim(COALESCE(v_aj.observacao, '')), '') IS NOT NULL THEN ' Obs. do colaborador: ' || v_aj.observacao ELSE '' END
      || CASE WHEN v_extra > 0 THEN ' (+' || v_extra || ' anexo(s) no pedido de ajuste)' ELSE '' END,
    p_uid, p_uid_nome, p_ajuste_id
  );

  UPDATE public.ponto_ajustes SET atestado_id = v_id WHERE id = p_ajuste_id;

  IF v_abona AND NOT COALESCE(v_aj.dia_inteiro, false) THEN
    BEGIN
      INSERT INTO public.ponto_alertas
        (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
         tipo, severidade, titulo, descricao, data_referencia)
      SELECT v_aj.tenant_id, v_empresa, v_aj.colaborador_id::text, v_aj.colaborador_nome, v_aj.colaborador_cpf,
             'ausencia_parcial_abonada_dia_inteiro', 'media',
             'Ausência parcial abonada: o dia inteiro ficou abonado',
             format('A ausência de %s (%s) foi aprovada com abono. Até a próxima fase do ponto o sistema abona '
                 || 'o DIA INTEIRO, e não só as horas do documento. Confira se é isso que a empresa quer pagar. [ajuste:%s]',
                 COALESCE(v_aj.colaborador_nome, '-'), v_periodo, p_ajuste_id),
             v_aj.data_referencia
      WHERE NOT EXISTS (SELECT 1 FROM public.ponto_alertas a
                         WHERE a.tenant_id = v_aj.tenant_id
                           AND a.tipo = 'ausencia_parcial_abonada_dia_inteiro'
                           AND a.descricao LIKE '%[ajuste:' || p_ajuste_id || ']%');
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Alerta de ausência parcial abonada não registrado (%).', SQLERRM;
    END;
  END IF;

  RETURN v_id;
END $lanca$;

REVOKE ALL ON FUNCTION public._ponto_ajuste_lanca_ausencia(uuid, boolean, uuid, text) FROM PUBLIC, anon, authenticated;

-- 5) Reinjeção em processar_ajuste_ponto (idempotente; âncoras contadas) --------
DO $reinj$
DECLARE
  v_src text;
  v_novo text;
  v_ancora text := '  IF NOT p_aprovado OR v_ajuste.tipo_ajuste IN (''justificativa'', ''abono'') THEN';
  v_bloco text;
  v_n int;
BEGIN
  v_src := pg_get_functiondef('public.processar_ajuste_ponto(uuid,boolean,text)'::regprocedure);

  IF position('[fase2-ausencia]' IN v_src) > 0 THEN
    RAISE NOTICE 'processar_ajuste_ponto: [fase2-ausencia] ja aplicado; nada a fazer.';
    RETURN;
  END IF;

  v_n := (length(v_src) - length(replace(v_src, v_ancora, ''))) / length(v_ancora);
  IF v_n <> 1 THEN
    RAISE NOTICE 'processar_ajuste_ponto: ancora de [fase2-ausencia] aparece % vez(es) (esperado 1); nada alterado — revisar.', v_n;
    RETURN;
  END IF;

  v_bloco :=
       '  -- [fase2-ausencia] Ausência (declaração/atestado) não grava marcação:' || chr(10)
    || '  -- vira lançamento em Atestados com o anexo (abona ou só arquiva).' || chr(10)
    || '  IF p_aprovado AND v_ajuste.natureza = ''ausencia'' THEN' || chr(10)
    || '    PERFORM public._ponto_ajuste_lanca_ausencia(p_ajuste_id, v_deve_abonar, v_uid, v_aprovador_nome);' || chr(10)
    || '    PERFORM public.consolidar_ponto_diario_manual(v_ajuste.tenant_id, v_ajuste.colaborador_cpf, v_ajuste.data_referencia);' || chr(10)
    || '    BEGIN' || chr(10)
    || '      PERFORM public.apurar_banco_horas_colaborador(' || chr(10)
    || '        v_ajuste.tenant_id, v_ajuste.colaborador_cpf, to_char(v_ajuste.data_referencia, ''YYYY-MM'')' || chr(10)
    || '      );' || chr(10)
    || '    EXCEPTION WHEN OTHERS THEN NULL;' || chr(10)
    || '    END;' || chr(10)
    || '    RETURN jsonb_build_object(''success'', true, ''auto_lancado'', v_auto_lancado, ''natureza'', ''ausencia'',' || chr(10)
    || '      ''abonou'', v_deve_abonar,' || chr(10)
    || '      ''atestado_id'', (SELECT a.atestado_id FROM public.ponto_ajustes a WHERE a.id = p_ajuste_id));' || chr(10)
    || '  END IF;' || chr(10) || chr(10);

  v_novo := replace(v_src, v_ancora, v_bloco || v_ancora);
  EXECUTE v_novo;
  RAISE NOTICE 'processar_ajuste_ponto: [fase2-ausencia] aplicado.';
END
$reinj$;

DO $reinj2$
DECLARE
  v_src text;
  v_novo text;
  v_ancora text := 'v_ajuste.tenant_id, v_ajuste.empresa_id, v_ajuste.colaborador_id,';
  v_troca text := 'v_ajuste.tenant_id, COALESCE(public.ponto_empresa_do_colaborador(v_ajuste.colaborador_id), v_ajuste.empresa_id), v_ajuste.colaborador_id,';
  v_n int;
BEGIN
  v_src := pg_get_functiondef('public.processar_ajuste_ponto(uuid,boolean,text)'::regprocedure);

  IF position(v_troca IN v_src) > 0 THEN
    RAISE NOTICE 'processar_ajuste_ponto: empresa da marcação incluída ja corrigida; nada a fazer.';
    RETURN;
  END IF;

  v_n := (length(v_src) - length(replace(v_src, v_ancora, ''))) / length(v_ancora);
  IF v_n <> 1 THEN
    RAISE NOTICE 'processar_ajuste_ponto: ancora da empresa aparece % vez(es) (esperado 1); nada alterado — revisar.', v_n;
    RETURN;
  END IF;

  v_novo := replace(v_src, v_ancora, v_troca);
  EXECUTE v_novo;
  RAISE NOTICE 'processar_ajuste_ponto: empresa da marcação incluída corrigida.';
END
$reinj2$;

-- 6) QA --------------------------------------------------------------------------
-- Gestor/RH fictício do cercado (conta + perfil + papel admin) para aprovar.
CREATE OR REPLACE FUNCTION public.qa_ponto_gestor_cercado(p_marca text)
RETURNS uuid
LANGUAGE plpgsql
SET search_path TO 'public'
AS $gest$
DECLARE v_uid uuid;
BEGIN
  v_uid := public.qa_mky_usuario_empresa(public.qa_sandbox_tenant_id(), p_marca);
  INSERT INTO public.user_roles (user_id, role) VALUES (v_uid, 'admin'::public.app_role);
  RETURN v_uid;
END $gest$;

-- PONTO-495 — aprovar ausência de dia inteiro que abona
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_495()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $qa495$
DECLARE
  r public.qa_retorno;
  m jsonb;
  v_claims text := current_setting('request.jwt.claims', true);
  v_uid uuid;
  v_d date := DATE '2026-08-11';   -- terça, sem feriado nacional
  v_aj uuid := gen_random_uuid();
  v_aj_corr uuid := gen_random_uuid();
  v_aj_conf uuid := gen_random_uuid();
  v_aj_fixo uuid := gen_random_uuid();
  v_res jsonb;
  v_marc_dia int; v_atest_n int; v_atest_n2 int;
  v_at public.atestados;
  v_ajuste_atest uuid; v_status_aj text; v_status_dia text;
  v_relanca uuid; v_reprocessa text;
  v_corr_origem text; v_corr_lig int;
  v_conf boolean; v_conf_fixa text;
  v_ok boolean := false;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'RH aprova uma ausência de dia inteiro que abona (com atestado anexado)';
  r.esperado    := 'Nenhuma marcação nova; 1 atestado ligado ao ajuste, com período, abona e arquivo no bucket do ajuste; '
                || 'dia Justificado; reaprovar não duplica; correção de batida segue gravando marcação A ligada; '
                || 'abono de justificativa Configurável é decidido pelo RH';

  IF to_regprocedure('public._ponto_ajuste_lanca_ausencia(uuid,boolean,uuid,text)') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := '_ponto_ajuste_lanca_ausencia ausente.'; RETURN r;
  END IF;

  PERFORM public.qa_modo_ligar();
  BEGIN
    m := public.qa_ponto_app_massa(49501);
    v_uid := public.qa_ponto_gestor_cercado('p495');

    INSERT INTO public.ponto_ajustes (id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
      data_referencia, tipo_ajuste, dia_inteiro, motivo, justificativa_id, natureza, anexos, status)
    VALUES (v_aj, (m->>'tenant')::uuid, (m->>'empresa')::uuid, (m->>'adm')::uuid, '[QA-PONTO] App 49501', m->>'cpf',
      v_d, 'justificativa', true, 'QA atestado', (m->>'aus')::uuid, 'ausencia', m->'anexo', 'pendente');

    PERFORM public.qa_mky_claims(v_uid);
    v_res := public.processar_ajuste_ponto(v_aj, true, 'QA aprova ausência');

    v_marc_dia := (SELECT count(*) FROM public.ponto_marcacoes mk
                    WHERE mk.tenant_id = (m->>'tenant')::uuid AND mk.colaborador_cpf = m->>'cpf' AND mk.data_marcacao = v_d);
    v_atest_n := (SELECT count(*) FROM public.atestados a WHERE a.ajuste_id = v_aj);
    v_at := (SELECT a FROM public.atestados a WHERE a.ajuste_id = v_aj LIMIT 1);
    v_ajuste_atest := (SELECT a.atestado_id FROM public.ponto_ajustes a WHERE a.id = v_aj);
    v_status_aj := (SELECT a.status FROM public.ponto_ajustes a WHERE a.id = v_aj);
    v_status_dia := (SELECT pd.status FROM public.ponto_diario pd
                      WHERE pd.tenant_id = (m->>'tenant')::uuid AND pd.colaborador_cpf = m->>'cpf' AND pd.data = v_d LIMIT 1);

    -- idempotência: lançar de novo devolve o mesmo; reprocessar é recusado
    v_relanca := public._ponto_ajuste_lanca_ausencia(v_aj, true, v_uid, 'QA');
    BEGIN
      PERFORM public.processar_ajuste_ponto(v_aj, true, 'QA de novo');
      v_reprocessa := 'aceitou';
    EXCEPTION WHEN OTHERS THEN v_reprocessa := SQLERRM;
    END;
    v_atest_n2 := (SELECT count(*) FROM public.atestados a WHERE a.ajuste_id = v_aj);

    -- correção de batida continua virando marcação incluída (A) ligada ao ajuste
    INSERT INTO public.ponto_ajustes (id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
      data_referencia, tipo_ajuste, tipo_marcacao, hora_solicitada, motivo, justificativa_id, status)
    VALUES (v_aj_corr, (m->>'tenant')::uuid, (m->>'empresa')::uuid, (m->>'adm')::uuid, '[QA-PONTO] App 49501', m->>'cpf',
      v_d + 1, 'inclusao', 'entrada', TIME '08:00', 'QA esqueci', (m->>'corr')::uuid, 'pendente');
    PERFORM public.processar_ajuste_ponto(v_aj_corr, true, 'QA aprova correção');
    v_corr_lig := (SELECT count(*) FROM public.ponto_marcacoes mk WHERE mk.ajuste_id = v_aj_corr);
    v_corr_origem := (SELECT mk.origem_marcacao FROM public.ponto_marcacoes mk WHERE mk.ajuste_id = v_aj_corr LIMIT 1);

    -- abono Configurável: decidido pelo RH; regra fixa é recusada
    INSERT INTO public.ponto_ajustes (id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
      data_referencia, tipo_ajuste, dia_inteiro, motivo, justificativa_id, anexos, status)
    VALUES (v_aj_conf, (m->>'tenant')::uuid, (m->>'empresa')::uuid, (m->>'adm')::uuid, '[QA-PONTO] App 49501', m->>'cpf',
      v_d + 2, 'justificativa', true, 'QA declaração', (m->>'aus_conf')::uuid, m->'anexo', 'pendente');
    PERFORM public.ponto_ajuste_definir_abono(v_aj_conf, true);
    v_conf := (SELECT a.abonar_se_aprovado FROM public.ponto_ajustes a WHERE a.id = v_aj_conf);
    BEGIN
      INSERT INTO public.ponto_ajustes (id, tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
        data_referencia, tipo_ajuste, dia_inteiro, motivo, justificativa_id, anexos, status)
      VALUES (v_aj_fixo, (m->>'tenant')::uuid, (m->>'adm')::uuid, '[QA-PONTO] App 49501', m->>'cpf',
        v_d + 7, 'justificativa', true, 'QA atestado regra fixa', (m->>'aus')::uuid, m->'anexo', 'pendente');
      PERFORM public.ponto_ajuste_definir_abono(v_aj_fixo, false);
      v_conf_fixa := 'aceitou';
    EXCEPTION WHEN OTHERS THEN v_conf_fixa := SQLERRM;
    END;

    PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);

    v_ok := COALESCE((v_res->>'success')::boolean, false) AND v_res->>'natureza' = 'ausencia'
        AND v_marc_dia = 0 AND v_atest_n = 1 AND v_atest_n2 = 1
        AND v_at.abona IS TRUE AND v_at.arquivo_bucket = 'ponto-ajustes-anexos'
        AND v_at.data_inicio_afastamento = v_d AND v_at.arquivo_url = (m->'anexo'->0->>'url')
        AND v_ajuste_atest = v_at.id AND v_status_aj = 'aprovado'
        AND COALESCE(v_status_dia, '') = 'justificado'
        AND v_relanca = v_at.id AND v_reprocessa <> 'aceitou'
        AND v_corr_lig = 1 AND v_corr_origem = 'A'
        AND v_conf IS TRUE AND v_conf_fixa LIKE '%fixa%';
    RAISE EXCEPTION 'qa_rollback';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
    IF SQLERRM <> 'qa_rollback' THEN
      r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
    END IF;
  END;

  r.detalhe := jsonb_build_object('retorno', v_res, 'marcacoes_no_dia', v_marc_dia, 'atestados', v_atest_n,
                 'atestados_apos_reaprovar', v_atest_n2, 'abona', v_at.abona, 'bucket', v_at.arquivo_bucket,
                 'inicio', v_at.data_inicio_afastamento, 'ligado_no_ajuste', v_ajuste_atest = v_at.id,
                 'status_ajuste', v_status_aj, 'status_dia', v_status_dia, 'reprocessar', v_reprocessa,
                 'correcao_marcacoes', v_corr_lig, 'correcao_origem', v_corr_origem,
                 'abono_configuravel', v_conf, 'abono_fixo', v_conf_fixa);
  IF v_ok THEN
    r.situacao := 'passou';
    r.obtido := 'Ausência aprovada virou 1 atestado (abona, com o anexo do pedido), sem marcação; dia Justificado; '
             || 'sem duplicar; correção de batida segue como marcação A; abono configurável decidido pelo RH.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: marcações no dia=%s (esperado 0); atestados=%s/%s (esperado 1); abona=%s; bucket=%s; '
             || 'dia=%s (esperado justificado); correção ligada=%s origem=%s; configurável=%s.',
             v_marc_dia, v_atest_n, v_atest_n2, v_at.abona, v_at.arquivo_bucket, COALESCE(v_status_dia, '—'),
             v_corr_lig, COALESCE(v_corr_origem, '—'), v_conf);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $qa495$;

-- PONTO-496 — aprovar ausência parcial que NÃO abona (e a variante que abona)
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_496()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $qa496$
DECLARE
  r public.qa_retorno;
  m jsonb;
  v_claims text := current_setting('request.jwt.claims', true);
  v_uid uuid;
  v_d date := DATE '2026-08-12';   -- quarta, sem feriado nacional
  v_d2 date := DATE '2026-08-13';  -- quinta
  v_aj uuid := gen_random_uuid();
  v_aj2 uuid := gen_random_uuid();
  v_nome text := '[QA-PONTO] App 49601';
  v_at public.atestados;
  v_at2 public.atestados;
  v_marc_dia int; v_lig int; v_status_dia text; v_saldo int; v_alerta int;
  v_ok boolean := false;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'RH aprova ausência de 2h que NÃO abona (dia trabalhado 6h de 8h) e uma de 2h que abona';
  r.esperado    := 'Não abona: atestado arquivado sem período, nenhuma marcação nova, dia não justificado e débito no saldo. '
                || 'Abona: atestado com período em horas e alerta ao DP de que o dia inteiro ficou abonado';

  IF to_regprocedure('public._ponto_ajuste_lanca_ausencia(uuid,boolean,uuid,text)') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := '_ponto_ajuste_lanca_ausencia ausente.'; RETURN r;
  END IF;

  PERFORM public.qa_modo_ligar();
  BEGIN
    m := public.qa_ponto_app_massa(49601);
    v_uid := public.qa_ponto_gestor_cercado('p496');
    PERFORM public.qa_ponto_escala_tol(m->>'cpf', v_nome, 480, 10, v_d, v_d2);
    PERFORM public.qa_ponto_marca(m->>'cpf', v_nome, v_d, TIME '08:00', 'entrada');
    PERFORM public.qa_ponto_marca(m->>'cpf', v_nome, v_d, TIME '12:00', 'saida');
    PERFORM public.qa_ponto_marca(m->>'cpf', v_nome, v_d, TIME '13:00', 'entrada');
    PERFORM public.qa_ponto_marca(m->>'cpf', v_nome, v_d, TIME '15:00', 'saida');

    INSERT INTO public.ponto_ajustes (id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
      data_referencia, tipo_ajuste, dia_inteiro, ausencia_hora_inicio, ausencia_hora_fim,
      motivo, justificativa_id, natureza, anexos, status)
    VALUES (v_aj, (m->>'tenant')::uuid, (m->>'empresa')::uuid, (m->>'adm')::uuid, v_nome, m->>'cpf',
      v_d, 'justificativa', false, TIME '15:00', TIME '17:00',
      'QA declaração', (m->>'aus_nao')::uuid, 'ausencia', m->'anexo', 'pendente');
    INSERT INTO public.ponto_ajustes (id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
      data_referencia, tipo_ajuste, dia_inteiro, ausencia_hora_inicio, ausencia_hora_fim,
      motivo, justificativa_id, natureza, anexos, status)
    VALUES (v_aj2, (m->>'tenant')::uuid, (m->>'empresa')::uuid, (m->>'adm')::uuid, v_nome, m->>'cpf',
      v_d2, 'justificativa', false, TIME '08:00', TIME '10:00',
      'QA atestado', (m->>'aus')::uuid, 'ausencia', m->'anexo', 'pendente');

    PERFORM public.qa_mky_claims(v_uid);
    PERFORM public.processar_ajuste_ponto(v_aj, true, 'QA aprova sem abono');
    PERFORM public.processar_ajuste_ponto(v_aj2, true, 'QA aprova com abono');
    PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);

    v_at := (SELECT a FROM public.atestados a WHERE a.ajuste_id = v_aj LIMIT 1);
    v_at2 := (SELECT a FROM public.atestados a WHERE a.ajuste_id = v_aj2 LIMIT 1);
    v_marc_dia := (SELECT count(*) FROM public.ponto_marcacoes mk
                    WHERE mk.tenant_id = (m->>'tenant')::uuid AND mk.colaborador_cpf = m->>'cpf' AND mk.data_marcacao = v_d);
    v_lig := (SELECT count(*) FROM public.ponto_marcacoes mk WHERE mk.ajuste_id IN (v_aj, v_aj2));
    v_status_dia := (SELECT pd.status FROM public.ponto_diario pd
                      WHERE pd.tenant_id = (m->>'tenant')::uuid AND pd.colaborador_cpf = m->>'cpf' AND pd.data = v_d LIMIT 1);
    v_saldo := (SELECT s.saldo_min FROM public.ponto_saldo_dias_competencia((m->>'tenant')::uuid, m->>'cpf', '2026-08') s
                 WHERE s.dia = v_d);
    v_alerta := (SELECT count(*) FROM public.ponto_alertas a
                  WHERE a.tenant_id = (m->>'tenant')::uuid AND a.tipo = 'ausencia_parcial_abonada_dia_inteiro'
                    AND a.descricao LIKE '%[ajuste:' || v_aj2 || ']%');

    v_ok := v_at.id IS NOT NULL AND v_at.data_inicio_afastamento IS NULL AND v_at.abona IS FALSE
        AND v_at.unidade_afastamento = 'horas' AND COALESCE(v_at.horas_afastamento, 0) = 2
        AND v_marc_dia = 4 AND v_lig = 0
        AND COALESCE(v_status_dia, '') <> 'justificado'
        AND COALESCE(v_saldo, 0) < 0
        AND v_at2.id IS NOT NULL AND v_at2.data_inicio_afastamento = v_d2 AND v_at2.abona IS TRUE
        AND v_at2.unidade_afastamento = 'horas' AND v_alerta = 1;
    RAISE EXCEPTION 'qa_rollback';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
    IF SQLERRM <> 'qa_rollback' THEN
      r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
    END IF;
  END;

  r.detalhe := jsonb_build_object('nao_abona_inicio', v_at.data_inicio_afastamento, 'nao_abona_abona', v_at.abona,
                 'nao_abona_horas', v_at.horas_afastamento, 'marcacoes_no_dia', v_marc_dia, 'marcacoes_ligadas', v_lig,
                 'status_dia', v_status_dia, 'saldo_dia', v_saldo,
                 'abona_inicio', v_at2.data_inicio_afastamento, 'abona_unidade', v_at2.unidade_afastamento, 'alerta_dp', v_alerta);
  IF v_ok THEN
    r.situacao := 'passou';
    r.obtido := format('Não abona: atestado arquivado sem período, sem marcação nova, dia não justificado, saldo do dia %s min. '
             || 'Abona: atestado em horas com período e alerta ao DP.', v_saldo);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: não abona com período=%s; marcações no dia=%s (esperado 4) e ligadas=%s (esperado 0); '
             || 'dia=%s; saldo=%s (esperado negativo); abona com período=%s; alerta=%s.',
             v_at.data_inicio_afastamento IS NOT NULL, v_marc_dia, v_lig, COALESCE(v_status_dia, '—'),
             COALESCE(v_saldo::text, 'nulo'), v_at2.data_inicio_afastamento IS NOT NULL, v_alerta);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $qa496$;

-- Documentação dos casos
DO $doc$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente; casos PONTO-495/496 não documentados.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo jornada-rotina/ponto ausente; casos não documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PONTO-495',
   'Aprovar ausência que abona vira atestado (sem batida) e não duplica',
   'feliz', 'critica', 'aprovado', 'api',
   'Lei 605/1949, art. 6º, § 1º; CLT art. 473; Portaria MTP 671/2021 (marcação não pode ser inventada)',
   'Ausência aprovada não grava marcação: vira lançamento em Atestados com o anexo do pedido, ligado ao ajuste. '
   || 'Quando a justificativa abona, o atestado tem período e o dia fica Justificado. Reaprovar não duplica. '
   || 'A correção de batida continua virando marcação incluída (A). O abono de justificativa Configurável é decidido pelo RH.',
   'Cercado de QA com colaborador, catálogo e um gestor fictício.',
   '[{"ordem":1,"acao":"Aprovar ausência de dia inteiro com justificativa que abona","resultado_esperado":"Nenhuma marcação; 1 atestado com período, abona, arquivo no bucket do ajuste; dia Justificado"},
     {"ordem":2,"acao":"Lançar de novo / reaprovar","resultado_esperado":"Mesmo atestado; reaprovar recusado"},
     {"ordem":3,"acao":"Aprovar uma correção de batida","resultado_esperado":"Marcação incluída (A) ligada ao ajuste"},
     {"ordem":4,"acao":"RH marca Abonar numa ausência Configurável; tenta em regra fixa","resultado_esperado":"Configurável aceita; fixa recusada"}]'::jsonb,
   'Ausência aprovada = atestado, nunca batida.',
   'Fase 2 do Ponto, F4 (out/2026). Tudo desfeito no fim da rotina (qa_rollback).'),

  (v_mod, 'PONTO-496',
   'Aprovar ausência que NÃO abona arquiva o atestado sem período e mantém o débito',
   'negativo', 'critica', 'aprovado', 'api',
   'CLT art. 462 (desconto só do que é devido) e art. 473; Lei 605/1949',
   'Ausência parcial cuja justificativa não abona vira atestado ARQUIVADO sem período (o documento fica guardado), sem marcação, '
   || 'e o déficit do dia segue para banco/folha. A ausência parcial que abona grava o período em horas e alerta o DP de que, '
   || 'até a Fase 4, o sistema abona o dia inteiro.',
   'Cercado de QA com colaborador, escala de 8h, marcações de 6h e um gestor fictício.',
   '[{"ordem":1,"acao":"Aprovar ausência de 2h que não abona","resultado_esperado":"Atestado sem período, abona=não; nenhuma marcação nova; dia não justificado; saldo negativo"},
     {"ordem":2,"acao":"Aprovar ausência de 2h que abona","resultado_esperado":"Atestado em horas com período; alerta ausencia_parcial_abonada_dia_inteiro ao DP"}]'::jsonb,
   'Não abona = documento arquivado + débito; abona parcial = alerta ao DP.',
   'Fase 2 do Ponto, F4 (out/2026). Tudo desfeito no fim da rotina (qa_rollback).')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PONTO-495', 'qa_caso_ponto_495', true),
      ('PONTO-496', 'qa_caso_ponto_496', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentação PONTO-495/496 não registrada: %', SQLERRM;
END $doc$;

-- ── Conferência (única) ─────────────────────────────────────────────────────
WITH q495 AS MATERIALIZED (SELECT r.situacao::text AS s, r.obtido, r.erro_tecnico FROM public.qa_caso_ponto_495() r),
     q496 AS MATERIALIZED (SELECT r.situacao::text AS s, r.obtido, r.erro_tecnico FROM public.qa_caso_ponto_496() r),
     f AS MATERIALIZED (SELECT pg_get_functiondef('public.processar_ajuste_ponto(uuid,boolean,text)'::regprocedure) AS src)
SELECT
  (SELECT position('[fase2-ausencia]' IN src) > 0 FROM f) AS ausencia_ok,
  (SELECT position('COALESCE(public.ponto_empresa_do_colaborador(v_ajuste.colaborador_id), v_ajuste.empresa_id), v_ajuste.colaborador_id,' IN src) > 0 FROM f) AS empresa_marcacao_ok,
  position('ponto_grava_feriado_neutro' IN pg_get_functiondef('public.consolidar_ponto_diario_manual(uuid,text,date)'::regprocedure)) > 0 AS consolidacao_feriado_intacta,
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'atestados'
      AND column_name IN ('ajuste_id', 'arquivo_bucket')) AS colunas_atestados_esperado_2,
  to_regclass('public.uq_atestados_ajuste_id') IS NOT NULL AS indice_unico_ok,
  has_function_privilege('authenticated', 'public.ponto_ajuste_definir_abono(uuid,boolean)', 'EXECUTE') AS definir_abono_ok,
  (SELECT s FROM q495) AS qa_ponto_495,
  (SELECT s FROM q496) AS qa_ponto_496,
  concat_ws(' | ',
    CASE WHEN (SELECT s FROM q495) <> 'passou' THEN (SELECT coalesce(erro_tecnico, obtido) FROM q495) END,
    CASE WHEN (SELECT s FROM q496) <> 'passou' THEN (SELECT coalesce(erro_tecnico, obtido) FROM q496) END) AS erro_tecnico;
