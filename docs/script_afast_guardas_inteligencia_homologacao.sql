-- ============================================================================
-- ENTREGA — AFASTAMENTOS: guardas + inteligência (AFAST-011, 020, 051) — HOMOLOGAÇÃO
--
-- Cole no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na PRODUÇÃO.
--
-- Os três estavam vermelhos na produção porque a camada de correção (fases 0/1)
-- foi aplicada só ao staging — nunca colada na produção (estava no monolito
-- script_motor_qa_fases_0a3, que a gente evita colar). Aqui vão limpos.
--
--   AFAST-011 · dois afastamentos ATIVOS do mesmo CPF não se sobrepõem (gatilho;
--               a prorrogação continua sendo o UPDATE do fim no próprio registro).
--   AFAST-051 · suspensão disciplinar limitada a 30 dias (CLT art. 474) — CHECK
--               NOT VALID (linha nova/alterada; legado > 30 não quebra a aplicação).
--   AFAST-020 · repara a regressão de 24/07 na inteligência: episódio único > 15
--               dias vira 'aguardando_inss' (Lei 8.213 art. 60) e volta a abrir a
--               pendência de INSS/S-2230 (o ramo do episódio único tinha sumido).
--               Só troca o corpo de duas funções que já existem (os gatilhos
--               permanecem); AFAST-031 (estabilidade) vem junto, mesma dupla.
--
-- SEGURANÇA: só CREATE OR REPLACE FUNCTION, TRIGGER e CHECK NOT VALID — não cria
-- tabela (auto-RLS não liga), não apaga dado. afastamentos é tabela quente e já
-- tem vários gatilhos: se aparecer "deadlock detected", rode de novo (idempotente).
-- lock_timeout curto.
--
-- Origem: migrations 20260913150500 (011/051) e 20260913150000 (020/031).
-- ============================================================================

SET lock_timeout = '10s';

-- ══════════════ AFAST-011 · sem sobreposição de afastamentos ativos ══════════
CREATE OR REPLACE FUNCTION public.afastamento_sem_sobreposicao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'ativo' AND NEW.data_inicio IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.afastamentos a
      WHERE a.id <> NEW.id
        AND a.tenant_id = NEW.tenant_id
        AND a.status = 'ativo'
        AND regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g')
          = regexp_replace(COALESCE(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g')
        AND regexp_replace(COALESCE(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g') <> ''
        AND daterange(a.data_inicio, COALESCE(a.data_fim, 'infinity'::date), '[]')
          && daterange(NEW.data_inicio, COALESCE(NEW.data_fim, 'infinity'::date), '[]')
    ) THEN
      RAISE EXCEPTION 'Afastamento sobreposto para o mesmo colaborador: use a prorrogacao (ajuste da data de fim do registro ativo), nao um registro paralelo.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_afastamento_sem_sobreposicao ON public.afastamentos;
CREATE TRIGGER trg_afastamento_sem_sobreposicao
  BEFORE INSERT OR UPDATE OF data_inicio, data_fim, status, colaborador_cpf ON public.afastamentos
  FOR EACH ROW EXECUTE FUNCTION public.afastamento_sem_sobreposicao();

-- ══════════════ AFAST-051 · suspensão disciplinar ≤ 30 dias (art. 474) ═══════
ALTER TABLE public.afastamentos DROP CONSTRAINT IF EXISTS chk_afast_suspensao_disciplinar_30d;
ALTER TABLE public.afastamentos ADD CONSTRAINT chk_afast_suspensao_disciplinar_30d
  CHECK (tipo_principal_new <> 'suspensao_disciplinar'
         OR data_fim IS NULL OR data_inicio IS NULL
         OR (data_fim - data_inicio + 1) <= 30) NOT VALID;

-- ══════════════ AFAST-020/031 · inteligência (BEFORE + AFTER) ════════════════
-- BEFORE: campos da própria linha (status 'aguardando_inss' no episódio único
-- > 15 dias; data_fim_estabilidade nos tipos acidentários).
CREATE OR REPLACE FUNCTION public.afastamento_campos_before()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_dias integer;
BEGIN
    IF COALESCE(NEW.prazo_indeterminado, FALSE) THEN
        IF NEW.status_geral_new IS NULL
           OR NEW.status_geral_new NOT IN ('prazo_indeterminado', 'em_beneficio') THEN
            NEW.status_geral_new := 'prazo_indeterminado';
        END IF;
    END IF;

    IF NEW.data_inicio IS NOT NULL AND NEW.data_fim IS NOT NULL THEN
        v_dias := (NEW.data_fim - NEW.data_inicio) + 1;
    ELSIF NEW.data_inicio IS NOT NULL THEN
        v_dias := (CURRENT_DATE - NEW.data_inicio) + 1;
    ELSE
        v_dias := 0;
    END IF;

    IF NOT COALESCE(NEW.prazo_indeterminado, FALSE)
       AND v_dias > 15
       AND (NEW.status_geral_new IS NULL
            OR NEW.status_geral_new NOT IN
               ('aguardando_inss', 'em_beneficio', 'encerrado', 'cancelado', 'prazo_indeterminado')) THEN
        NEW.status_geral_new := 'aguardando_inss';
    END IF;

    IF NEW.tipo_principal_new IN ('acidente_tipico', 'acidente_trajeto', 'doenca_ocupacional')
       AND NEW.data_fim IS NOT NULL THEN
        NEW.data_fim_estabilidade := (NEW.data_fim + INTERVAL '12 months')::date;
    END IF;

    RETURN NEW;
END;
$$;

-- AFTER: marcadores, pendências, FAP e escalada de status.
CREATE OR REPLACE FUNCTION public.processar_inteligencia_afastamento()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_dias              INTEGER := 0;
    v_cid               TEXT;
    v_cnae              TEXT;
    v_ntep_status       TEXT;
    v_acumulado_60_dias INTEGER := 0;
    v_episodio_dias     INTEGER := 0;
    v_inss_15           BOOLEAN := FALSE;
    v_setor_id          UUID;
    v_mental_setor_count INTEGER := 0;
    v_criticas          INTEGER := 0;
BEGIN
    IF pg_trigger_depth() > 1 THEN
        RETURN NULL;
    END IF;

    v_dias     := COALESCE(NEW.dias_totais, 0);
    v_setor_id := NEW.setor_id;

    SELECT cid_principal INTO v_cid
      FROM public.afastamentos_saude
     WHERE afastamento_id = NEW.id;

    SELECT cnae_principal INTO v_cnae
      FROM public.empresa_cadastro
     WHERE id = NEW.empresa_id;

    DELETE FROM public.afastamentos_marcadores
     WHERE afastamento_id = NEW.id AND origem = 'sistema';

    IF v_cid LIKE 'F%' THEN
        INSERT INTO public.afastamentos_marcadores (afastamento_id, tenant_id, marcador)
        VALUES (NEW.id, NEW.tenant_id, 'saude_mental'),
               (NEW.id, NEW.tenant_id, 'cid_f'),
               (NEW.id, NEW.tenant_id, 'poss_risco_psicossocial');

        INSERT INTO public.afastamentos_pendencias
            (afastamento_id, tenant_id, tipo_pendencia, descricao, prioridade)
        VALUES (NEW.id, NEW.tenant_id, 'entrevista_retorno',
                'Realizar entrevista de retorno obrigatoria por CID F', 'media')
        ON CONFLICT DO NOTHING;

        IF v_setor_id IS NOT NULL THEN
            SELECT count(*) INTO v_mental_setor_count
              FROM public.afastamentos a
              JOIN public.afastamentos_saude s ON a.id = s.afastamento_id
             WHERE a.setor_id = v_setor_id
               AND s.cid_principal LIKE 'F%'
               AND a.created_at >= (now() - interval '90 days');

            IF v_mental_setor_count >= 3 THEN
                INSERT INTO public.afastamentos_marcadores (afastamento_id, tenant_id, marcador)
                VALUES (NEW.id, NEW.tenant_id, 'padrao_coletivo_setor');

                INSERT INTO public.afastamentos_pendencias
                    (afastamento_id, tenant_id, tipo_pendencia, descricao, prioridade)
                VALUES (NEW.id, NEW.tenant_id, 'revisao_sst',
                        'Alerta: 3+ afastamentos CID F no setor em 90 dias. Revisar PGR/FPR.', 'alta')
                ON CONFLICT DO NOTHING;
            END IF;
        END IF;
    END IF;

    v_episodio_dias := v_dias;
    IF v_cid IS NOT NULL AND NEW.colaborador_id IS NOT NULL THEN
        SELECT COALESCE(SUM(a.dias_totais), 0) INTO v_acumulado_60_dias
          FROM public.afastamentos a
          JOIN public.afastamentos_saude s ON a.id = s.afastamento_id
         WHERE a.colaborador_id = NEW.colaborador_id
           AND a.id <> NEW.id
           AND s.cid_principal = v_cid
           AND a.data_inicio >= (NEW.data_inicio - interval '60 days');
        v_episodio_dias := v_episodio_dias + v_acumulado_60_dias;
    END IF;

    IF v_episodio_dias > 15 THEN
        v_inss_15 := TRUE;
        INSERT INTO public.afastamentos_marcadores (afastamento_id, tenant_id, marcador)
        VALUES (NEW.id, NEW.tenant_id, 'acumulacao_previdenciaria_15_dias'),
               (NEW.id, NEW.tenant_id, 'afastamento_superior_15_dias');

        INSERT INTO public.afastamentos_pendencias
            (afastamento_id, tenant_id, tipo_pendencia, descricao, prioridade)
        VALUES (NEW.id, NEW.tenant_id, 'inss',
                'Trabalhador atingiu 15+ dias (episodio unico ou acumulado no mesmo CID em 60 dias). Avaliar INSS.', 'critica')
        ON CONFLICT DO NOTHING;

        INSERT INTO public.afastamentos_pendencias
            (afastamento_id, tenant_id, tipo_pendencia, descricao, prioridade)
        VALUES (NEW.id, NEW.tenant_id, 's2230',
                'Enviar evento S-2230 por afastamento superior a 15 dias.', 'alta')
        ON CONFLICT DO NOTHING;
    END IF;

    IF v_cid IS NOT NULL AND v_cnae IS NOT NULL THEN
        v_ntep_status := public.check_ntep_relationship(v_cid, v_cnae);

        IF v_ntep_status = 'suspeito' THEN
            INSERT INTO public.afastamentos_marcadores (afastamento_id, tenant_id, marcador)
            VALUES (NEW.id, NEW.tenant_id, 'ntep_suspeito'),
                   (NEW.id, NEW.tenant_id, 'risco_impacto_fap');

            INSERT INTO public.afastamentos_pendencias
                (afastamento_id, tenant_id, tipo_pendencia, descricao, prioridade)
            VALUES (NEW.id, NEW.tenant_id, 'ntep',
                    'Possivel NTEP identificado. Avaliar nexo ocupacional.', 'alta')
            ON CONFLICT DO NOTHING;

            INSERT INTO public.afastamentos_fap
                (afastamento_id, tenant_id, impacta_fap, nivel_risco, motivo_impacto)
            VALUES (NEW.id, NEW.tenant_id, FALSE, 'risco_alto', 'NTEP Suspeito (' || v_cid || ')')
            ON CONFLICT (afastamento_id)
            DO UPDATE SET nivel_risco    = 'risco_alto',
                          motivo_impacto = EXCLUDED.motivo_impacto;
        END IF;
    END IF;

    IF NEW.tipo_principal_new IN ('acidente_tipico', 'acidente_trajeto', 'doenca_ocupacional') THEN
        INSERT INTO public.afastamentos_marcadores (afastamento_id, tenant_id, marcador)
        VALUES (NEW.id, NEW.tenant_id, 'cat_obrigatoria'),
               (NEW.id, NEW.tenant_id, 'cat_pendente');

        INSERT INTO public.afastamentos_pendencias
            (afastamento_id, tenant_id, tipo_pendencia, descricao, prioridade)
        VALUES (NEW.id, NEW.tenant_id, 'cat',
                'CAT obrigatoria para este tipo de afastamento.', 'critica')
        ON CONFLICT DO NOTHING;

        INSERT INTO public.afastamentos_pendencias
            (afastamento_id, tenant_id, tipo_pendencia, descricao, prioridade)
        VALUES (NEW.id, NEW.tenant_id, 's2210',
                'Enviar S-2210 referente a CAT obrigatoria.', 'critica')
        ON CONFLICT DO NOTHING;
    END IF;

    IF v_dias >= 30
       OR NEW.tipo_principal_new IN ('beneficio_b31', 'beneficio_b91', 'licenca_maternidade') THEN
        INSERT INTO public.afastamentos_marcadores (afastamento_id, tenant_id, marcador)
        VALUES (NEW.id, NEW.tenant_id, 'retorno_obrigatorio');

        INSERT INTO public.afastamentos_pendencias
            (afastamento_id, tenant_id, tipo_pendencia, descricao, prioridade)
        VALUES (NEW.id, NEW.tenant_id, 'aso_retorno',
                'Exame de retorno ao trabalho obrigatorio (>30 dias ou beneficio)', 'alta')
        ON CONFLICT DO NOTHING;
    END IF;

    IF NEW.tipo_principal_new IN ('beneficio_b91', 'licenca_maternidade', 'mandato_sindical',
                                  'acidente_tipico', 'acidente_trajeto', 'doenca_ocupacional') THEN
        INSERT INTO public.afastamentos_marcadores (afastamento_id, tenant_id, marcador)
        VALUES (NEW.id, NEW.tenant_id, 'estabilidade_provisoria');
    END IF;

    SELECT count(*) INTO v_criticas
      FROM public.afastamentos_pendencias
     WHERE afastamento_id = NEW.id
       AND status = 'pendente'
       AND prioridade = 'critica';

    IF v_inss_15
       AND NEW.status_geral_new NOT IN
           ('aguardando_inss', 'em_beneficio', 'encerrado', 'cancelado', 'prazo_indeterminado') THEN
        UPDATE public.afastamentos
           SET status_geral_new = 'aguardando_inss'
         WHERE id = NEW.id;
    ELSIF v_criticas > 0
       AND NEW.status_geral_new NOT IN
           ('aguardando_inss', 'em_beneficio', 'encerrado', 'cancelado', 'prazo_indeterminado')
       AND NEW.status_geral_new IS DISTINCT FROM 'pendencia_critica' THEN
        UPDATE public.afastamentos
           SET status_geral_new = 'pendencia_critica'
         WHERE id = NEW.id;
    END IF;

    RETURN NULL;
END;
$$;

-- ════════════════════ CONFERÊNCIA (única — esperado tudo 'ok') ════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('AFAST-011 · gatilho sem sobreposição',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_afastamento_sem_sobreposicao' AND NOT tgisinternal)),
    ('AFAST-051 · CHECK suspensão disciplinar ≤ 30 dias',
       EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_afast_suspensao_disciplinar_30d' AND conrelid='public.afastamentos'::regclass)),
    ('AFAST-020 · BEFORE vira status aguardando_inss (>15 dias)',
       (pg_get_functiondef('public.afastamento_campos_before()'::regprocedure) ~* 'aguardando_inss')),
    ('AFAST-020 · AFTER restaura pendência do episódio único',
       (pg_get_functiondef('public.processar_inteligencia_afastamento()'::regprocedure) ~* 'v_episodio_dias > 15'))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao FROM alvo ORDER BY item;
