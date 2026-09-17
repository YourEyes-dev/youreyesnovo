-- ============================================================================
-- TEMA 3 — Segregacao de funcao / rito de desligamento — ENTREGA producao.
-- Fecha DESL-002 (reescrita de desligamento), DESL-106 (reversao sem rito) e
-- FERIAS-056 (ferias autoaprovadas). Instala tambem a trava do PONTO-252.
--
-- So CRIA coisa nova: 1 coluna, 1 tabela de historico, 3 funcoes, 2 gatilhos e
-- 2 travas CHECK. NAO altera nem apaga dado existente.
--
-- CUIDADO com o legado: as travas CHECK entram como NOT VALID (valem para
-- gravacoes NOVAS, nao reprovam linhas antigas que ja violam — a producao tem
-- autoaprovacoes historicas). Onde a base esta limpa, um bloco DO tenta VALIDAR
-- a trava; onde ha legado, ela fica NOT VALID e sai um NOTICE. Idempotente.
-- Roda em UMA transacao no SQL Editor.
-- ============================================================================

SET lock_timeout = '10s';

-- Coluna que sustenta o rito de reversao (DESL-106) ---------------------------
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS reversao_desligamento_justificativa text;

-- Historico de desligamento (DESL-002): o desligamento deixa de ser so colunas
-- na admissao e passa a ter trilha de eventos (registro/retificacao/reversao).
CREATE TABLE IF NOT EXISTS public.desligamento_eventos (
  id                           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id                    uuid NOT NULL,
  admissao_id                  uuid NOT NULL REFERENCES public.admissoes(id) ON DELETE CASCADE,
  colaborador_cpf              text,
  colaborador_nome             text,
  evento                       text NOT NULL,
  data_desligamento_anterior   date,
  motivo_desligamento_anterior text,
  data_desligamento_nova       date,
  motivo_desligamento_novo     text,
  justificativa                text,
  registrado_por               uuid,
  registrado_em                timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT desligamento_eventos_evento_check
    CHECK (evento = ANY (ARRAY['registro'::text, 'retificacao'::text, 'reversao'::text]))
);
CREATE INDEX IF NOT EXISTS idx_desligamento_eventos_admissao
  ON public.desligamento_eventos (admissao_id, registrado_em DESC);
CREATE INDEX IF NOT EXISTS idx_desligamento_eventos_tenant
  ON public.desligamento_eventos (tenant_id, registrado_em DESC);

ALTER TABLE public.desligamento_eventos ENABLE ROW LEVEL SECURITY;
DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'Tenant le desligamento_eventos') THEN
    CREATE POLICY "Tenant le desligamento_eventos"
      ON public.desligamento_eventos FOR SELECT TO authenticated
      USING (tenant_id = public.current_user_tenant_id());
  END IF;
END;
$do$;

-- DESL-002: barra regravar por cima de desligamento ja registrado -------------
CREATE OR REPLACE FUNCTION public.admissao_guardar_desligamento()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_ja_desligada boolean;
  v_mudou boolean;
  v_retificando boolean;
  v_evento text;
BEGIN
  v_ja_desligada := OLD.data_desligamento IS NOT NULL OR OLD.status = 'desligado';
  v_mudou := NEW.data_desligamento IS DISTINCT FROM OLD.data_desligamento
             OR NEW.motivo_desligamento IS DISTINCT FROM OLD.motivo_desligamento;
  IF NOT v_mudou THEN
    RETURN NEW;
  END IF;

  -- Desfazer o desligamento fica registrado como 'reversao'.
  IF NEW.data_desligamento IS NULL AND NEW.motivo_desligamento IS NULL THEN
    INSERT INTO public.desligamento_eventos (
      tenant_id, admissao_id, colaborador_cpf, colaborador_nome, evento,
      data_desligamento_anterior, motivo_desligamento_anterior,
      data_desligamento_nova, motivo_desligamento_novo, registrado_por
    ) VALUES (
      NEW.tenant_id, NEW.id, NEW.cpf, NEW.nome_completo, 'reversao',
      OLD.data_desligamento, OLD.motivo_desligamento, NULL, NULL, auth.uid()
    );
    RETURN NEW;
  END IF;

  v_retificando := COALESCE(current_setting('app.retificar_desligamento', true), '') = 'on';

  IF v_ja_desligada AND NOT v_retificando THEN
    RAISE EXCEPTION
      'Esta admissao ja tem desligamento registrado em % (%). Regravar por cima apagaria o '
      'registro original. Para corrigir, use desligamento_retificar(admissao_id, data, motivo, '
      'justificativa) — a correcao fica registrada no historico.',
      to_char(OLD.data_desligamento, 'DD/MM/YYYY'),
      COALESCE(OLD.motivo_desligamento, 'motivo nao informado')
      USING ERRCODE = 'unique_violation';
  END IF;

  v_evento := CASE WHEN v_ja_desligada THEN 'retificacao' ELSE 'registro' END;

  INSERT INTO public.desligamento_eventos (
    tenant_id, admissao_id, colaborador_cpf, colaborador_nome, evento,
    data_desligamento_anterior, motivo_desligamento_anterior,
    data_desligamento_nova, motivo_desligamento_novo,
    justificativa, registrado_por
  ) VALUES (
    NEW.tenant_id, NEW.id, NEW.cpf, NEW.nome_completo, v_evento,
    OLD.data_desligamento, OLD.motivo_desligamento,
    NEW.data_desligamento, NEW.motivo_desligamento,
    NULLIF(current_setting('app.retificar_justificativa', true), ''),
    auth.uid()
  );
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_admissao_guardar_desligamento ON public.admissoes;
CREATE TRIGGER trg_admissao_guardar_desligamento
  BEFORE UPDATE OF data_desligamento, motivo_desligamento ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_guardar_desligamento();

-- DESL-106: barra reverter desligamento por UPDATE cru (exige justificativa) --
CREATE OR REPLACE FUNCTION public.admissao_bloqueia_reversao_desligamento()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $fn$
BEGIN
  IF OLD.status::text = 'desligado'
     AND NEW.status::text <> 'desligado'
     AND COALESCE(NEW.reversao_desligamento_justificativa, '') = '' THEN
    RAISE EXCEPTION
      'Reversao de desligamento exige rito (motivo, aprovacao, estorno e tratamento do S-2299). Registre a justificativa da reversao.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_admissao_bloqueia_reversao_desligamento ON public.admissoes;
CREATE TRIGGER trg_admissao_bloqueia_reversao_desligamento
  BEFORE UPDATE OF status ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_bloqueia_reversao_desligamento();

-- Caminho sancionado de correcao do desligamento (retificacao com trilha) -----
CREATE OR REPLACE FUNCTION public.desligamento_retificar(
  p_admissao_id uuid, p_data_desligamento date, p_motivo_desligamento text, p_justificativa text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_adm public.admissoes;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nao autenticado';
  END IF;
  IF COALESCE(btrim(p_justificativa), '') = '' THEN
    RAISE EXCEPTION 'A justificativa da retificacao e obrigatoria — e ela que sustenta a alteracao numa auditoria.';
  END IF;
  SELECT * INTO v_adm FROM public.admissoes WHERE id = p_admissao_id;
  IF v_adm.id IS NULL THEN
    RAISE EXCEPTION 'Admissao nao encontrada.';
  END IF;
  IF NOT public.has_minimum_role(v_uid, 'manager'::public.app_role) THEN
    RAISE EXCEPTION 'Apenas gestor/RH pode retificar desligamento.';
  END IF;

  PERFORM set_config('app.retificar_desligamento', 'on', true);
  PERFORM set_config('app.retificar_justificativa', p_justificativa, true);
  UPDATE public.admissoes
     SET data_desligamento = p_data_desligamento, motivo_desligamento = p_motivo_desligamento
   WHERE id = p_admissao_id;
  PERFORM set_config('app.retificar_desligamento', 'off', true);

  RETURN jsonb_build_object('success', true, 'admissao_id', p_admissao_id,
    'data_anterior', v_adm.data_desligamento, 'motivo_anterior', v_adm.motivo_desligamento,
    'data_nova', p_data_desligamento, 'motivo_novo', p_motivo_desligamento);
END;
$fn$;

-- FERIAS-056: trava de autoaprovacao (NOT VALID; valida onde a base esta limpa)
DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'chk_ferias_sem_autoaprovacao'
                    AND conrelid = 'public.ferias_solicitacoes'::regclass) THEN
    ALTER TABLE public.ferias_solicitacoes
      ADD CONSTRAINT chk_ferias_sem_autoaprovacao
      CHECK (aprovado_por IS NULL OR aprovado_por::text <> colaborador_id::text) NOT VALID;
  END IF;
END;
$do$;
DO $do$
BEGIN
  ALTER TABLE public.ferias_solicitacoes VALIDATE CONSTRAINT chk_ferias_sem_autoaprovacao;
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'chk_ferias_sem_autoaprovacao permanece NOT VALID: ha solicitacoes historicas com autoaprovacao. A trava vale para as gravacoes novas.';
END;
$do$;

-- PONTO-252: trava de autoaprovacao no ajuste de ponto (idem, se a tabela existe)
DO $do$
BEGIN
  IF to_regclass('public.ponto_ajustes') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_constraint
                      WHERE conname = 'chk_ajuste_sem_autoaprovacao'
                        AND conrelid = 'public.ponto_ajustes'::regclass) THEN
    ALTER TABLE public.ponto_ajustes
      ADD CONSTRAINT chk_ajuste_sem_autoaprovacao
      CHECK (aprovado_por IS NULL OR aprovado_por::text <> colaborador_id::text) NOT VALID;
  END IF;
END;
$do$;
DO $do$
BEGIN
  IF to_regclass('public.ponto_ajustes') IS NOT NULL THEN
    ALTER TABLE public.ponto_ajustes VALIDATE CONSTRAINT chk_ajuste_sem_autoaprovacao;
  END IF;
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'chk_ajuste_sem_autoaprovacao permanece NOT VALID: ha ajustes historicos autoaprovados (os 76 conhecidos). A trava vale para as gravacoes novas; os historicos exigem decisao de produto a parte.';
END;
$do$;

-- Conferencia (leve) ----------------------------------------------------------
SELECT 'DESL-002' AS caso, (public.qa_executar_descartavel('qa_caso_desl_002')).situacao::text AS situacao
UNION ALL
SELECT 'DESL-106', (public.qa_executar_descartavel('qa_caso_desl_106')).situacao::text
UNION ALL
SELECT 'FERIAS-056', (public.qa_executar_descartavel('qa_caso_ferias_056')).situacao::text
UNION ALL
SELECT 'PONTO-252 (trava instalada; historicos a decidir)',
       (public.qa_executar_descartavel('qa_caso_ponto_252')).situacao::text
ORDER BY caso;
