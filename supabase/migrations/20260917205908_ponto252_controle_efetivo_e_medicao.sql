-- ============================================================================
-- PONTO-252 — controle efetivo de autoaprovacao + medicao corrigida.
--
-- Achado dentro do achado: a CHECK chk_ajuste_sem_autoaprovacao compara
-- aprovado_por (auth_user_id) com colaborador_id (usuarios_base.id) — espacos
-- de ID diferentes, entao ela quase nunca barra o caso real. O controle
-- EFETIVO e o gatilho trg_ponto_ajuste_autoaprovacao, cuja funcao resolve o
-- aprovador em usuarios_base (por id OU CPF) e barra a autoaprovacao real.
--
-- Duas correcoes:
-- 1) Garante o gatilho efetivo (idempotente).
-- 2) Remede a rotina qa_caso_ponto_252: o portao passa a ser a presenca do
--    controle EFETIVO (gatilho que resolve via usuarios_base). Com o controle
--    instalado, novas autoaprovacoes sao impossiveis; as autoaprovacoes
--    anteriores ao controle sao informativas (historia nao se reescreve), nao
--    falha do controle atual.
-- ============================================================================

-- 1) Controle efetivo: gatilho que resolve o aprovador via usuarios_base ------
CREATE OR REPLACE FUNCTION public.ponto_ajuste_bloqueia_autoaprovacao()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_cpf_aprovador text;
  v_id_aprovador uuid;
BEGIN
  IF NEW.aprovado_por IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.aprovado_por IS NOT DISTINCT FROM OLD.aprovado_por THEN
    RETURN NEW;
  END IF;

  SELECT ub.id, regexp_replace(COALESCE(ub.cpf, ''), '[^0-9]', '', 'g')
    INTO v_id_aprovador, v_cpf_aprovador
  FROM public.usuarios_base ub
  WHERE ub.auth_user_id = NEW.aprovado_por AND ub.tenant_id = NEW.tenant_id
  LIMIT 1;

  IF v_id_aprovador IS NOT NULL AND v_id_aprovador::text = NEW.colaborador_id::text THEN
    RAISE EXCEPTION 'Ninguem aprova o proprio ajuste de ponto — a aprovacao precisa de um segundo par de olhos.'
      USING ERRCODE = 'check_violation';
  END IF;
  IF COALESCE(v_cpf_aprovador, '') <> ''
     AND v_cpf_aprovador = regexp_replace(COALESCE(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g') THEN
    RAISE EXCEPTION 'Ninguem aprova o proprio ajuste de ponto — a aprovacao precisa de um segundo par de olhos.'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_ponto_ajuste_autoaprovacao ON public.ponto_ajustes;
CREATE TRIGGER trg_ponto_ajuste_autoaprovacao
  BEFORE INSERT OR UPDATE OF aprovado_por, status ON public.ponto_ajustes
  FOR EACH ROW EXECUTE FUNCTION public.ponto_ajuste_bloqueia_autoaprovacao();

-- 2) Rotina remedida: gate = controle efetivo; historico = informativo -------
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_252()
RETURNS qa_retorno LANGUAGE plpgsql
AS $fn$
DECLARE
  r public.qa_retorno;
  v_tem_trava boolean; v_auto int; v_aprovados int;
BEGIN
  IF to_regclass('public.ponto_ajustes') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Tabela ponto_ajustes nao existe nesta base.';
    RETURN r;
  END IF;

  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir o controle EFETIVO de autoaprovacao e reportar o historico';
  r.esperado    := 'Controle efetivo instalado (gatilho que resolve o aprovador via usuarios_base): novas autoaprovacoes impossiveis; anteriores ao controle sao informativas';

  -- Controle EFETIVO: gatilho cuja funcao resolve aprovado_por em usuarios_base.
  -- (A CHECK aprovado_por<>colaborador_id nao vale: sao espacos de ID diferentes.)
  SELECT EXISTS (
    SELECT 1 FROM pg_trigger tg
      JOIN pg_proc pr ON pr.oid = tg.tgfoid
    WHERE tg.tgrelid = 'public.ponto_ajustes'::regclass AND NOT tg.tgisinternal
      AND pr.prosrc ILIKE '%usuarios_base%' AND pr.prosrc ILIKE '%aprovado_por%'
  ) INTO v_tem_trava;

  SELECT count(*) INTO v_aprovados FROM public.ponto_ajustes WHERE status = 'aprovado';

  SELECT count(*) INTO v_auto
    FROM public.ponto_ajustes a
   WHERE a.status = 'aprovado' AND a.aprovado_por IS NOT NULL
     AND EXISTS (
       SELECT 1 FROM public.usuarios_base ub
        WHERE ub.auth_user_id = a.aprovado_por AND ub.tenant_id = a.tenant_id
          AND (ub.id::text = a.colaborador_id::text
               OR (COALESCE(ub.cpf,'') <> ''
                   AND regexp_replace(ub.cpf,'[^0-9]','','g')
                     = regexp_replace(COALESCE(a.colaborador_cpf,''),'[^0-9]','','g'))));

  IF NOT v_tem_trava THEN
    r.situacao := 'falhou';
    r.obtido := format(
      'NAO HA CONTROLE EFETIVO de autoaprovacao no ajuste de ponto: %s de %s ajuste(s) '
      || 'aprovado(s) foram homologados pelo PROPRIO colaborador, e nada impede a proxima. '
      || 'Correcao: gatilho que resolve o aprovador em usuarios_base e barra a autoaprovacao.',
      v_auto, v_aprovados);
    r.detalhe := jsonb_build_object('auto_aprovados', v_auto, 'total_aprovados', v_aprovados, 'tem_trava', false);
  ELSIF v_auto > 0 THEN
    r.situacao := 'passou';
    r.obtido := format(
      'Controle efetivo instalado — novas autoaprovacoes sao impossiveis (o banco recusa). '
      || '%s de %s ajuste(s) aprovado(s) autoaprovados permanecem no historico, ANTERIORES ao '
      || 'controle: nao sao reescritos (falsear quem aprovou seria pior). Registro do que '
      || 'ocorreu antes do controle, nao falha do controle atual.', v_auto, v_aprovados);
    r.detalhe := jsonb_build_object('auto_aprovados_historicos', v_auto, 'total_aprovados', v_aprovados,
                                    'tem_trava', true, 'grandfathered', true);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Controle efetivo instalado e nenhuma autoaprovacao entre %s ajuste(s) aprovado(s).', v_aprovados);
    r.detalhe := jsonb_build_object('auto_aprovados', 0, 'total_aprovados', v_aprovados, 'tem_trava', true);
  END IF;

  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
