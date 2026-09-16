-- ============================================================================
-- HOMOLOGACAO — PONTO, PARTE 13 de 16: Atestados e ausencias legais
--
-- Deteccao de atestados sobrepostos, ponte automatica do atestado longo para
-- o afastamento previdenciario no 16o dia (Lei 8.213, arts. 59-60) e
-- comprovacao das ausencias do art. 473.
--
-- ONDE COLAR
-- No SQL Editor do projeto de HOMOLOGACAO. Nao e para a producao: a producao
-- so muda por gesto manual seu, depois de conferida aqui.
--
-- COMO USAR
-- Cole o arquivo INTEIRO e execute uma vez. Pode rodar de novo sem risco
-- (idempotente). As partes tem ordem: rode da 01 para a 16, conferindo o
-- resultado de cada uma antes de passar para a seguinte.
--
-- O QUE ESTE ARQUIVO REUNE
--   * script_ponto_onda11_atestados_sobrepostos.sql
--   * script_ponto_onda11_atestado_encaminha_inss.sql
--   * script_ponto_onda11_comprovacao_art473.sql
--
-- Ao final sai UMA conferencia, dizendo o que chegou e o que faltou.
-- ============================================================================



-- ############################################################
-- BLOCO: script_ponto_onda11_atestados_sobrepostos.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 11 (parte 2): atestados sobrepostos detectados, nao abonados
--                              em dobro (ESC-011)
--
-- Dois atestados que cobrem o mesmo periodo (um documento reenviado, ou dois
-- medicos para os mesmos dias) nao podem abonar em dobro nem confundir a
-- contagem dos 15 dias. Hoje eles entram como registros independentes — sem
-- deteccao —, e tudo que SOMA por atestado dobra: dias acumulados, a regua dos
-- 15 dias (o 16o dia do INSS calculado sobre dias somados em dobro) e os
-- indicadores de absenteismo. O mesmo documento reenviado passa como novo.
--
-- O QUE FAZ (aditivo, NAO bloqueia): um gatilho BEFORE INSERT em atestados que
-- detecta a SOBREPOSICAO de periodo (mesmo CPF/tenant) na entrada e SINALIZA —
-- um alerta ao DP decidir qual vale, mantendo o tratamento mais favoravel e a
-- contagem de dias unica (cada dia doente conta uma vez). Nao recusa o registro
-- (pode ser dois atendimentos legitimos); so evita a duplicidade silenciosa.
--
-- GARANTIAS: nao altera o motor de saldo, a apuracao, o espelho nem o
-- fechamento. So detecta e alerta. Aditivo e idempotente. Defensivo (o alerta
-- nunca quebra o registro do atestado). Roda inteiro em UMA transacao.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ponto_atestado_detectar_sobreposicao()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_prev RECORD;
  v_ini  date;
  v_fim  date;
BEGIN
  -- Deteccao de sobreposicao de periodos de atestado por CPF (nao bloqueia).
  IF NEW.data_inicio_afastamento IS NULL OR NEW.colaborador_cpf IS NULL THEN
    RETURN NEW;
  END IF;

  v_ini := NEW.data_inicio_afastamento;
  v_fim := COALESCE(NEW.data_fim_afastamento, NEW.data_inicio_afastamento);

  -- Procura um atestado JA registrado do mesmo colaborador cujo periodo se
  -- sobrepoe ao novo (intervalos se cruzam: inicio_a <= fim_b E fim_a >= inicio_b).
  SELECT a.id, a.data_inicio_afastamento AS di, a.data_fim_afastamento AS df
    INTO v_prev
  FROM public.atestados a
  WHERE a.tenant_id = NEW.tenant_id
    AND a.colaborador_cpf = NEW.colaborador_cpf
    AND (NEW.id IS NULL OR a.id <> NEW.id)
    AND a.data_inicio_afastamento IS NOT NULL
    AND a.data_inicio_afastamento <= v_fim
    AND COALESCE(a.data_fim_afastamento, a.data_inicio_afastamento) >= v_ini
  ORDER BY a.data_inicio_afastamento DESC
  LIMIT 1;

  IF FOUND THEN
    BEGIN
      INSERT INTO public.ponto_alertas
        (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
         tipo, severidade, titulo, descricao, data_referencia)
      VALUES
        (NEW.tenant_id, NEW.empresa_id, NEW.colaborador_id, NEW.colaborador_nome, NEW.colaborador_cpf,
         'atestado_sobreposto', 'media',
         'Atestados com periodos sobrepostos',
         format('O atestado novo (%s a %s) se sobrepoe a um atestado ja registrado (%s a %s) do mesmo '
             || 'colaborador. Confira se e reenvio/duplicidade ou dois atendimentos: o DP decide qual '
             || 'vale, mantendo o tratamento mais favoravel, e os dias em comum contam UMA vez (nao '
             || 'abona em dobro nem infla a contagem dos 15 dias).',
             v_ini, v_fim, v_prev.di, COALESCE(v_prev.df, v_prev.di)),
         v_ini);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Nao foi possivel registrar o alerta de atestado sobreposto (%). O atestado foi registrado.', SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.ponto_atestado_detectar_sobreposicao() IS
  'Detecta sobreposicao de periodos de atestado por CPF na entrada e sinaliza (alerta ao DP), sem bloquear — contagem de dias unica, nao abona em dobro. ESC-011.';

DO $trg$
BEGIN
  SET LOCAL lock_timeout = '10s';
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                 WHERE tgname = 'trg_ponto_atestado_sobreposicao'
                   AND tgrelid = 'public.atestados'::regclass AND NOT tgisinternal) THEN
    CREATE TRIGGER trg_ponto_atestado_sobreposicao
      BEFORE INSERT ON public.atestados
      FOR EACH ROW EXECUTE FUNCTION public.ponto_atestado_detectar_sobreposicao();
  END IF;
END $trg$;

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | OK — a funcao de deteccao existe e o gatilho esta em atestados.
-- ---------------------------------------------------------------------------
SELECT
  (to_regprocedure('public.ponto_atestado_detectar_sobreposicao()') IS NOT NULL) AS funcao_ok,
  EXISTS (SELECT 1 FROM pg_trigger
          WHERE tgname='trg_ponto_atestado_sobreposicao'
            AND tgrelid='public.atestados'::regclass AND NOT tgisinternal)         AS gatilho_ok,
  CASE WHEN to_regprocedure('public.ponto_atestado_detectar_sobreposicao()') IS NOT NULL
        AND EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgname='trg_ponto_atestado_sobreposicao'
                      AND tgrelid='public.atestados'::regclass AND NOT tgisinternal)
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda11_atestado_encaminha_inss.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 11 (parte 1): atestado acima de 15 dias encaminha ao INSS (ESC-010)
--
-- O atestado longo muda de natureza no 16º dia: até 15 dias a empresa abona; do
-- 16º em diante é benefício previdenciário do INSS (Lei 8.213, arts. 59-60). Hoje
-- um atestado de 20 dias entra e nenhum afastamento nasce.
--
-- O QUE FAZ (aditivo): um gatilho BEFORE INSERT em atestados que, quando o
-- período passa de 15 dias e o atestado ainda não tem afastamento vinculado, CRIA
-- o afastamento previdenciário (status beneficio_inss, tipo B31, começando no 16º
-- dia), VINCULA em atestados.afastamento_id e ALERTA o DP — uma única vez. A
-- criação é defensiva (EXCEPTION → NOTICE): não quebra o registro do atestado.
--
-- Não altera o motor de saldo, a apuração, o espelho nem o fechamento. Idempotente
-- (só age quando afastamento_id é nulo). Roda inteiro em UMA transação.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ponto_atestado_encaminhar_afastamento()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_dias   integer;
  v_dia16  date;
  v_afast  uuid;
BEGIN
  IF NEW.afastamento_id IS NOT NULL OR NEW.data_inicio_afastamento IS NULL THEN
    RETURN NEW;
  END IF;

  v_dias := COALESCE(NEW.dias_afastamento,
                     (NEW.data_fim_afastamento - NEW.data_inicio_afastamento + 1),
                     0);

  IF v_dias <= 15 THEN
    RETURN NEW;
  END IF;

  v_dia16 := NEW.data_inicio_afastamento + 15;  -- 16º dia: início do benefício INSS

  BEGIN
    INSERT INTO public.afastamentos
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
       data_inicio, data_fim, data_atestado, status, tipo_principal_new, observacoes)
    VALUES
      (NEW.tenant_id, NEW.empresa_id, NEW.colaborador_id, NEW.colaborador_nome, NEW.colaborador_cpf,
       v_dia16, NEW.data_fim_afastamento, NEW.data_emissao, 'beneficio_inss', 'beneficio_b31',
       'Encaminhamento previdenciario automatico — atestado acima de 15 dias (Lei 8.213, arts. 59-60). '
       || 'Empresa abona os primeiros 15 dias; do 16o dia em diante e beneficio do INSS (auxilio-doenca B31).')
    RETURNING id INTO v_afast;

    NEW.afastamento_id := v_afast;

    INSERT INTO public.ponto_alertas
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
       tipo, severidade, titulo, descricao, data_referencia)
    VALUES
      (NEW.tenant_id, NEW.empresa_id, NULL, NEW.colaborador_nome, NEW.colaborador_cpf,
       'atestado_encaminhado_inss', 'alta',
       'Atestado acima de 15 dias encaminhado ao INSS',
       format('O atestado de %s dias de %s (inicio %s) passou dos 15 dias abonados pela empresa. '
           || 'Foi criado o afastamento previdenciario a partir do 16o dia (%s), status beneficio_inss. '
           || 'Confira a documentacao e o encaminhamento ao INSS (Lei 8.213, arts. 59-60).',
           v_dias, COALESCE(NEW.colaborador_nome,'-'), NEW.data_inicio_afastamento, v_dia16),
       v_dia16);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Nao foi possivel encaminhar o afastamento automaticamente (%). O atestado foi registrado; abra o afastamento no modulo Afastamentos.', SQLERRM;
  END;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.ponto_atestado_encaminhar_afastamento() IS
  'Atestado acima de 15 dias: cria o afastamento previdenciario (beneficio_inss / B31) a partir do 16o dia, vincula em atestados.afastamento_id e alerta o DP (Lei 8.213, arts. 59-60). Uma unica vez; defensivo. ESC-010.';

DO $trg$
BEGIN
  SET LOCAL lock_timeout = '10s';
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                 WHERE tgname = 'trg_ponto_atestado_encaminha_inss'
                   AND tgrelid = 'public.atestados'::regclass AND NOT tgisinternal) THEN
    CREATE TRIGGER trg_ponto_atestado_encaminha_inss
      BEFORE INSERT ON public.atestados
      FOR EACH ROW EXECUTE FUNCTION public.ponto_atestado_encaminhar_afastamento();
  END IF;
END $trg$;

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | OK — a funcao da ponte existe e o gatilho esta em atestados.
-- ---------------------------------------------------------------------------
SELECT
  (to_regprocedure('public.ponto_atestado_encaminhar_afastamento()') IS NOT NULL) AS funcao_ok,
  EXISTS (SELECT 1 FROM pg_trigger
          WHERE tgname='trg_ponto_atestado_encaminha_inss'
            AND tgrelid='public.atestados'::regclass AND NOT tgisinternal)         AS gatilho_ok,
  CASE WHEN to_regprocedure('public.ponto_atestado_encaminhar_afastamento()') IS NOT NULL
        AND EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgname='trg_ponto_atestado_encaminha_inss'
                      AND tgrelid='public.atestados'::regclass AND NOT tgisinternal)
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda11_comprovacao_art473.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 11 (parte 3): ausencia do art. 473 sem documento fica pendente
--                              — nao abona por fe (ESC-012)
--
-- O rol do art. 473 da CLT abona a falta, mas MEDIANTE comprovacao (certidao de
-- obito/casamento, declaracao de comparecimento, comprovante de doacao de
-- sangue). Hoje o catalogo ponto_justificativas marca os tipos que exigem
-- documento (requer_anexo) e a tela recebe a flag — mas nada IMPEDIA o abono sem
-- documento: aprovava-se a justificativa e o abono se consumava, com ou sem
-- prova. Abonar sem documento e abrir mao de prova; descontar as cegas seria
-- descontar direito liquido (a certidao chega depois). O certo e ficar PENDENTE.
--
-- O QUE FAZ:
--   1) processar_ajuste_ponto passa a olhar requer_anexo: abono que exige
--      documento e entra SEM anexo NAO se consuma — o ajuste fica
--      'pendente_comprovacao', com PRAZO, e um alerta avisa o colaborador e o DP.
--      Nao abona sem prova; nao desconta as cegas.
--   2) Anexado o documento e reprocessado, o abono se efetiva (o estado
--      'pendente_comprovacao' e reprocessavel).
--   3) ponto_comprovacao_monitorar varre as pendencias com prazo vencido e
--      alerta o DP ANTES de o dia virar desconto.
--
-- Nova coluna ponto_ajustes.comprovacao_prazo guarda a data-limite; o CHECK de
-- status ganha 'pendente_comprovacao'. Aditivo e idempotente. Nao altera o motor
-- de saldo, a apuracao, o espelho nem o fechamento — so condiciona a consumacao
-- do abono a prova. Roda inteiro em UMA transacao.
-- ============================================================================

-- 1) Data-limite de comprovação no ajuste (aditiva; tabela movimentada).
SET lock_timeout = '10s';
ALTER TABLE public.ponto_ajustes
  ADD COLUMN IF NOT EXISTS comprovacao_prazo date;

COMMENT ON COLUMN public.ponto_ajustes.comprovacao_prazo IS
  'Data-limite para anexar o documento comprobatório de um abono que exige anexo (art. 473). Enquanto pendente_comprovacao, o abono não se consuma. ESC-012.';

-- 1b) O status ganha o estado 'pendente_comprovacao'. Recria o CHECK de forma
--     idempotente (nenhuma linha existente usa o valor novo, então valida sem
--     erro). Tabela movimentada: já sob o lock_timeout definido acima.
DO $c$
BEGIN
  ALTER TABLE public.ponto_ajustes DROP CONSTRAINT IF EXISTS ponto_ajustes_status_check;
  ALTER TABLE public.ponto_ajustes
    ADD CONSTRAINT ponto_ajustes_status_check
    CHECK (status = ANY (ARRAY['pendente'::text, 'aprovado'::text, 'rejeitado'::text, 'pendente_comprovacao'::text]));
END $c$;

-- 2) Guarda da comprovação no processamento do ajuste.
--    Reproduz processar_ajuste_ponto integralmente e apenas acrescenta o gate
--    do art. 473: resolve a justificativa ANTES de decidir o status, e quando o
--    abono exige anexo sem documento, grava pendente_comprovacao + prazo +
--    alerta e para — sem chamar o abono. Todo o resto é idêntico.
CREATE OR REPLACE FUNCTION public.processar_ajuste_ponto(
  p_ajuste_id uuid, p_aprovado boolean, p_observacao text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_ajuste public.ponto_ajustes%ROWTYPE;
  v_has_access boolean := false;
  v_is_gestor boolean := false;
  v_vinculo_role text;
  v_aprovador_nome text;
  v_aprovador_cpf text;
  v_auto_lancado boolean := false;
  v_just_tipo_abono text;
  v_just_nome text;
  v_deve_abonar boolean := false;
  v_colab_uuid uuid;
  v_tipo text;
  -- ESC-012: comprovacao do art. 473
  v_just_requer_anexo boolean := false;
  v_pendente_comprovacao boolean := false;
  v_comprov_prazo date;
  v_comprov_dias integer := 2;  -- prazo padrao de comprovacao (dias corridos); ajustavel
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Não autenticado'; END IF;

  SELECT * INTO v_ajuste FROM public.ponto_ajustes WHERE id = p_ajuste_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ajuste não encontrado'; END IF;
  -- ESC-012: 'pendente_comprovacao' tambem e reprocessavel (para efetivar o
  -- abono depois que o documento for anexado).
  IF v_ajuste.status NOT IN ('pendente', 'pendente_comprovacao') THEN
    RAISE EXCEPTION 'Este ajuste já foi processado';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.usuarios_base ub
    WHERE ub.auth_user_id = v_uid AND ub.tenant_id = v_ajuste.tenant_id AND ub.status = 'ativo'
  ) INTO v_has_access;

  IF NOT v_has_access THEN
    SELECT uv.tipo_vinculo::text INTO v_vinculo_role
    FROM public.usuario_vinculos uv
    JOIN public.usuarios_base ub2 ON ub2.id = uv.usuario_id
    WHERE ub2.auth_user_id = v_uid
      AND uv.tenant_id = v_ajuste.tenant_id
      AND uv.status = 'ativo'
      AND (uv.data_fim IS NULL OR uv.data_fim >= CURRENT_DATE)
    LIMIT 1;
    IF v_vinculo_role IS NOT NULL THEN
      v_has_access := true;
      v_is_gestor := v_vinculo_role IN ('gestor','administrador','proprietario','rh');
    END IF;
  END IF;

  IF NOT v_has_access THEN
    SELECT EXISTS (SELECT 1 FROM public.profiles p WHERE p.user_id = v_uid AND p.tenant_id = v_ajuste.tenant_id) INTO v_has_access;
  END IF;
  IF NOT v_has_access THEN RAISE EXCEPTION 'Sem acesso a este tenant'; END IF;

  IF NOT v_is_gestor THEN
    v_is_gestor :=
      public.has_role(v_uid, 'manager'::public.app_role)
      OR public.has_role(v_uid, 'admin'::public.app_role)
      OR public.has_role(v_uid, 'owner'::public.app_role)
      OR public.has_role(v_uid, 'superadmin'::public.app_role);
  END IF;

  IF NOT v_is_gestor THEN
    SELECT EXISTS (
      SELECT 1 FROM public.usuarios_base ub3
      WHERE ub3.auth_user_id = v_uid AND ub3.tipo_usuario IN ('gestor','administrador','proprietario','rh')
    ) INTO v_is_gestor;
  END IF;

  IF NOT v_is_gestor THEN RAISE EXCEPTION 'Apenas gestor/RH pode processar ajustes de ponto'; END IF;

  SELECT nome_completo, regexp_replace(COALESCE(cpf,''), '\D', '', 'g')
    INTO v_aprovador_nome, v_aprovador_cpf
  FROM public.usuarios_base
  WHERE auth_user_id = v_uid AND tenant_id = v_ajuste.tenant_id
  LIMIT 1;
  IF v_aprovador_nome IS NULL THEN
    SELECT nome_completo INTO v_aprovador_nome FROM public.profiles WHERE user_id = v_uid LIMIT 1;
  END IF;

  -- =========================================================
  -- Bloco 3 — Segregação de funções (MTP 671 / auditoria)
  -- 1) Ninguém aprova ajuste do PRÓPRIO ponto.
  -- 2) Quem lançou o ajuste e aprova o mesmo ajuste precisa
  --    justificar (observação >= 10 caracteres) e o registro
  --    fica marcado como auto-lançamento.
  -- =========================================================
  IF COALESCE(v_aprovador_cpf, '') <> ''
     AND regexp_replace(COALESCE(v_ajuste.colaborador_cpf,''), '\D', '', 'g') = v_aprovador_cpf THEN
    RAISE EXCEPTION 'Segregação de funções: não é permitido aprovar ou rejeitar ajuste do próprio ponto. Outro gestor/RH deve analisar.';
  END IF;

  v_auto_lancado := (v_ajuste.created_by IS NOT NULL AND v_ajuste.created_by = v_uid);

  IF v_auto_lancado AND p_aprovado AND length(COALESCE(btrim(p_observacao), '')) < 10 THEN
    RAISE EXCEPTION 'Você foi quem solicitou este ajuste. Informe uma observação de aprovação com no mínimo 10 caracteres justificando o auto-lançamento.';
  END IF;

  -- ── ESC-012: resolve a justificativa ANTES de decidir o status ──────────
  -- Decide se o abono exige documento (art. 473) e se ele entrou sem anexo.
  IF p_aprovado AND v_ajuste.justificativa_id IS NOT NULL THEN
    SELECT tipo_abono, nome, requer_anexo
      INTO v_just_tipo_abono, v_just_nome, v_just_requer_anexo
    FROM public.ponto_justificativas WHERE id = v_ajuste.justificativa_id;
    v_deve_abonar := (v_just_tipo_abono = 'sim')
      OR (v_just_tipo_abono = 'configuravel' AND COALESCE(v_ajuste.abonar_se_aprovado, false));
    -- Art. 473 abona MEDIANTE comprovacao: abono que exige anexo e entra sem
    -- documento fica pendente de comprovacao (nao abona sem prova).
    v_pendente_comprovacao := v_deve_abonar
      AND COALESCE(v_just_requer_anexo, false)
      AND jsonb_array_length(COALESCE(v_ajuste.anexos, '[]'::jsonb)) = 0;
    IF v_deve_abonar AND NOT v_pendente_comprovacao THEN
      BEGIN v_colab_uuid := v_ajuste.colaborador_id::uuid;
      EXCEPTION WHEN OTHERS THEN v_colab_uuid := NULL;
      END;
    END IF;
  END IF;

  IF v_pendente_comprovacao THEN
    v_comprov_prazo := current_date + v_comprov_dias;
  END IF;

  UPDATE public.ponto_ajustes
  SET status = CASE
                 WHEN NOT p_aprovado THEN 'rejeitado'
                 WHEN v_pendente_comprovacao THEN 'pendente_comprovacao'
                 ELSE 'aprovado'
               END,
      aprovado_por = v_uid,
      aprovado_por_nome = v_aprovador_nome,
      data_aprovacao = now(),
      observacao_aprovador = p_observacao,
      auto_lancado = v_auto_lancado,
      comprovacao_prazo = CASE WHEN v_pendente_comprovacao THEN v_comprov_prazo ELSE comprovacao_prazo END
  WHERE id = p_ajuste_id;

  IF v_auto_lancado THEN
    BEGIN
      INSERT INTO public.audit_logs (tenant_id, user_id, acao, entidade, entidade_id, detalhes)
      VALUES (
        v_ajuste.tenant_id, v_uid,
        CASE WHEN p_aprovado THEN 'ajuste_ponto_auto_aprovado' ELSE 'ajuste_ponto_auto_rejeitado' END,
        'ponto_ajustes', p_ajuste_id,
        jsonb_build_object(
          'colaborador_cpf', v_ajuste.colaborador_cpf,
          'data_referencia', v_ajuste.data_referencia,
          'observacao', p_observacao,
          'aprovador_nome', v_aprovador_nome
        )
      );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  -- ── ESC-012: abono pendente de comprovacao — alerta e para aqui ─────────
  -- Nao consuma o abono (nao chama _ponto_grava_abono): o dia fica falta
  -- pendente, com prazo; alerta ao colaborador e ao DP. A certidao que chega
  -- depois efetiva o abono (reprocessando o ajuste ja com o anexo).
  IF v_pendente_comprovacao THEN
    BEGIN
      INSERT INTO public.ponto_alertas
        (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
         tipo, severidade, titulo, descricao, data_referencia)
      SELECT
        v_ajuste.tenant_id, v_ajuste.empresa_id, v_ajuste.colaborador_id::text,
        v_ajuste.colaborador_nome, v_ajuste.colaborador_cpf,
        'justificativa_pendente_comprovacao', 'media',
        'Justificativa pendente de comprovacao (art. 473)',
        format('A justificativa "%s" de %s (%s) exige documento comprobatorio (art. 473) e '
            || 'entrou SEM anexo. Fica PENDENTE de comprovacao ate %s — nao abona sem prova '
            || 'nem desconta as cegas. Anexe o comprovante ate a data e reaprove para efetivar '
            || 'o abono. [ajuste:%s]',
            COALESCE(v_just_nome, v_ajuste.motivo), COALESCE(v_ajuste.colaborador_nome, '-'),
            to_char(v_ajuste.data_referencia, 'DD/MM/YYYY'),
            to_char(v_comprov_prazo, 'DD/MM/YYYY'), p_ajuste_id),
        v_ajuste.data_referencia
      WHERE NOT EXISTS (
        SELECT 1 FROM public.ponto_alertas a
        WHERE a.tenant_id = v_ajuste.tenant_id
          AND a.tipo = 'justificativa_pendente_comprovacao'
          AND a.descricao LIKE '%[ajuste:' || p_ajuste_id || ']%'
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Nao foi possivel alertar a pendencia de comprovacao (%). O ajuste ficou pendente_comprovacao.', SQLERRM;
    END;
    PERFORM public.consolidar_ponto_diario_manual(v_ajuste.tenant_id, v_ajuste.colaborador_cpf, v_ajuste.data_referencia);
    RETURN jsonb_build_object('success', true, 'pendente_comprovacao', true,
                              'prazo', v_comprov_prazo, 'auto_lancado', v_auto_lancado);
  END IF;

  IF NOT p_aprovado OR v_ajuste.tipo_ajuste IN ('justificativa', 'abono') THEN
    IF v_deve_abonar AND v_colab_uuid IS NOT NULL AND COALESCE(v_ajuste.dia_inteiro, false) THEN
      PERFORM public._ponto_gera_batidas_dia_inteiro(
        v_ajuste.tenant_id, v_colab_uuid, v_ajuste.colaborador_nome,
        v_ajuste.colaborador_cpf, v_ajuste.data_referencia, v_ajuste.id, v_uid
      );
    END IF;
    PERFORM public.consolidar_ponto_diario_manual(v_ajuste.tenant_id, v_ajuste.colaborador_cpf, v_ajuste.data_referencia);
    IF v_deve_abonar AND v_colab_uuid IS NOT NULL THEN
      PERFORM public._ponto_grava_abono(
        v_ajuste.tenant_id, v_colab_uuid, v_ajuste.colaborador_nome,
        v_ajuste.colaborador_cpf, v_ajuste.data_referencia,
        COALESCE(v_just_nome, v_ajuste.motivo)
      );
    END IF;
    BEGIN
      PERFORM public.apurar_banco_horas_colaborador(
        v_ajuste.tenant_id, v_ajuste.colaborador_cpf, to_char(v_ajuste.data_referencia, 'YYYY-MM')
      );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    RETURN jsonb_build_object('success', true, 'auto_lancado', v_auto_lancado);
  END IF;

  -- ── Ajustes de marcação (inclusão / correção) ────────────────────────
  v_tipo := COALESCE(v_ajuste.tipo_marcacao, 'batida');
  IF v_tipo = 'saida_almoco'   THEN v_tipo := 'saida';   END IF;
  IF v_tipo = 'retorno_almoco' THEN v_tipo := 'entrada'; END IF;

  IF v_ajuste.tipo_ajuste = 'correcao' AND v_ajuste.hora_original IS NOT NULL THEN
    UPDATE public.ponto_marcacoes
       SET desconsiderada = true,
           desconsiderada_motivo = COALESCE(NULLIF(btrim(v_ajuste.motivo), ''), 'Correcao por ajuste aprovado'),
           desconsiderada_por = COALESCE(v_ajuste.aprovado_por::text, v_ajuste.created_by::text),
           desconsiderada_em = now()
     WHERE tenant_id = v_ajuste.tenant_id
       AND colaborador_cpf = v_ajuste.colaborador_cpf
       AND data_marcacao = v_ajuste.data_referencia
       AND to_char(hora_marcacao, 'HH24:MI') = to_char(v_ajuste.hora_original, 'HH24:MI')
       AND NOT COALESCE(desconsiderada, false);
  END IF;

  IF v_ajuste.hora_solicitada IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.ponto_marcacoes
    WHERE tenant_id = v_ajuste.tenant_id
      AND colaborador_cpf = v_ajuste.colaborador_cpf
      AND data_marcacao = v_ajuste.data_referencia
      AND tipo_marcacao = v_tipo
      AND to_char(hora_marcacao, 'HH24:MI') = to_char(v_ajuste.hora_solicitada, 'HH24:MI')
  ) THEN
    INSERT INTO public.ponto_marcacoes (
      tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
      data_marcacao, hora_marcacao, tipo_marcacao, marcacao_original, created_by, hash_marcacao
    ) VALUES (
      v_ajuste.tenant_id, v_ajuste.empresa_id, v_ajuste.colaborador_id,
      v_ajuste.colaborador_nome, v_ajuste.colaborador_cpf,
      v_ajuste.data_referencia, v_ajuste.hora_solicitada, v_tipo, false, v_uid,
      'AJUSTE-' || p_ajuste_id
    );
  END IF;

  PERFORM public.consolidar_ponto_diario_manual(v_ajuste.tenant_id, v_ajuste.colaborador_cpf, v_ajuste.data_referencia);
  BEGIN
    PERFORM public.apurar_banco_horas_colaborador(
      v_ajuste.tenant_id, v_ajuste.colaborador_cpf, to_char(v_ajuste.data_referencia, 'YYYY-MM')
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object('success', true, 'auto_lancado', v_auto_lancado);
END;
$fn$;

COMMENT ON FUNCTION public.processar_ajuste_ponto(uuid, boolean, text) IS
  'Processa ajuste de ponto (aprova/rejeita). ESC-012: abono que exige anexo (art. 473) sem documento nao se consuma — vira pendente_comprovacao com prazo e alerta colaborador+DP; anexado o documento e reprocessado, o abono se efetiva.';

-- 3) Monitor: pendencias de comprovacao com prazo vencido -> alerta o DP
--    ANTES de o dia virar desconto. Somente insere alertas (idempotente).
CREATE OR REPLACE FUNCTION public.ponto_comprovacao_monitorar(
  p_tenant uuid, p_empresa uuid DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_n integer := 0;
BEGIN
  INSERT INTO public.ponto_alertas
    (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
     tipo, severidade, titulo, descricao, data_referencia)
  SELECT
    a.tenant_id, a.empresa_id, a.colaborador_id::text,
    a.colaborador_nome, a.colaborador_cpf,
    'comprovacao_vencida', 'alta',
    'Prazo de comprovacao vencido (art. 473)',
    format('A justificativa "%s" de %s (%s) segue SEM o documento comprobatorio e o prazo '
        || 'venceu em %s. Decida ANTES de virar desconto: cobrar/estender o prazo ou tratar '
        || 'como falta. Enquanto pendente, o abono nao foi consumado. [ajuste:%s]',
        COALESCE(j.nome, a.motivo), COALESCE(a.colaborador_nome, '-'),
        to_char(a.data_referencia, 'DD/MM/YYYY'),
        to_char(a.comprovacao_prazo, 'DD/MM/YYYY'), a.id),
    a.data_referencia
  FROM public.ponto_ajustes a
  JOIN public.ponto_justificativas j ON j.id = a.justificativa_id
  WHERE a.tenant_id = p_tenant
    AND (p_empresa IS NULL OR a.empresa_id = p_empresa)
    AND a.status = 'pendente_comprovacao'
    AND a.comprovacao_prazo IS NOT NULL
    AND a.comprovacao_prazo < current_date
    AND COALESCE(j.requer_anexo, false)
    AND jsonb_array_length(COALESCE(a.anexos, '[]'::jsonb)) = 0
    AND NOT EXISTS (
      SELECT 1 FROM public.ponto_alertas al
      WHERE al.tenant_id = a.tenant_id
        AND al.tipo = 'comprovacao_vencida'
        AND al.descricao LIKE '%[ajuste:' || a.id || ']%'
    );
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$fn$;

COMMENT ON FUNCTION public.ponto_comprovacao_monitorar(uuid, uuid) IS
  'Varre ajustes pendente_comprovacao (art. 473) com prazo vencido e sem anexo e alerta o DP antes de virar desconto. Idempotente. ESC-012.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | t | OK
--   coluna_ok  : ponto_ajustes.comprovacao_prazo existe
--   estado_ok  : o CHECK de status aceita 'pendente_comprovacao'
--   guarda_ok  : processar_ajuste_ponto cobra o anexo (requer_anexo no corpo)
--   monitor_ok : ponto_comprovacao_monitorar existe
-- ---------------------------------------------------------------------------
WITH x AS MATERIALIZED (
  SELECT
    EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='ponto_ajustes'
              AND column_name='comprovacao_prazo') AS coluna_ok,
    (position('pendente_comprovacao' IN COALESCE(
       pg_get_constraintdef((SELECT oid FROM pg_constraint
         WHERE conrelid='public.ponto_ajustes'::regclass
           AND conname='ponto_ajustes_status_check')), '')) > 0) AS estado_ok,
    EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='public' AND p.proname='processar_ajuste_ponto'
              AND p.prosrc ILIKE '%requer_anexo%') AS guarda_ok,
    (to_regprocedure('public.ponto_comprovacao_monitorar(uuid,uuid)') IS NOT NULL) AS monitor_ok
)
SELECT coluna_ok, estado_ok, guarda_ok, monitor_ok,
       CASE WHEN coluna_ok AND estado_ok AND guarda_ok AND monitor_ok
            THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico
FROM x;


-- ============================================================================
-- CONFERENCIA DESTA PARTE
-- Lista o que a parte deveria deixar no ambiente e diz o que chegou. A ultima
-- linha resume: OK quando nada faltou.
-- ============================================================================
WITH esperado (tipo, nome, marcador) AS MATERIALIZED (
  VALUES
    ('funcao', 'ponto_atestado_detectar_sobreposicao', 'Atestados com periodos sobrepostos'),
    ('funcao', 'ponto_atestado_encaminhar_afastamento', 'Atestado acima de 15 dias encaminhado ao INSS'),
    ('funcao', 'processar_ajuste_ponto', 'Apenas gestor/RH pode processar ajustes de ponto'),
    ('funcao', 'ponto_comprovacao_monitorar', 'Prazo de comprovacao vencido (art. 473)'),
    ('gatilho', 'trg_ponto_atestado_sobreposicao', NULL),
    ('gatilho', 'trg_ponto_atestado_encaminha_inss', NULL),
    ('coluna', 'ponto_ajustes.comprovacao_prazo', NULL)
), estado AS MATERIALIZED (
  SELECT e.tipo, e.nome, e.marcador,
         CASE e.tipo
           WHEN 'funcao'  THEN EXISTS (SELECT 1 FROM pg_proc p
                                        JOIN pg_namespace n ON n.oid = p.pronamespace
                                       WHERE n.nspname = 'public' AND p.proname = e.nome
                                         AND (e.marcador IS NULL
                                              OR p.prosrc LIKE '%' || e.marcador || '%'))
           WHEN 'tabela'  THEN to_regclass('public.' || e.nome) IS NOT NULL
           WHEN 'indice'  THEN EXISTS (SELECT 1 FROM pg_indexes
                                       WHERE schemaname = 'public' AND indexname = e.nome)
           WHEN 'gatilho' THEN EXISTS (SELECT 1 FROM pg_trigger
                                       WHERE NOT tgisinternal AND tgname = e.nome)
           WHEN 'coluna'  THEN EXISTS (SELECT 1 FROM information_schema.columns
                                       WHERE table_schema = 'public'
                                         AND table_name  = split_part(e.nome, '.', 1)
                                         AND column_name = split_part(e.nome, '.', 2))
         END AS presente
  FROM esperado e
)
SELECT tipo, nome, CASE WHEN presente THEN 'chegou' ELSE 'FALTOU' END AS situacao
FROM estado
WHERE NOT presente
UNION ALL
SELECT 'RESUMO',
       (SELECT count(*) FROM estado WHERE presente)::text || ' de '
         || (SELECT count(*) FROM estado)::text || ' pecas no lugar',
       CASE WHEN (SELECT count(*) FROM estado WHERE NOT presente) = 0
            THEN 'OK' ELSE 'CONFERIR as linhas acima' END
ORDER BY 1 DESC, 2;
