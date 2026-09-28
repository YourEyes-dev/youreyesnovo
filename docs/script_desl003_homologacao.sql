-- ============================================================================
-- ENTREGA — DESL-003 · dispensa vedada com afastamento ativo (art. 476) — HOMOLOGAÇÃO
--
-- Cole no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na PRODUÇÃO.
--
-- DESL-003 dava ERRO na produção ("Afastamento sem data de término"). Causa: a
-- rotina de QA (fixture) inseria um afastamento ativo com data_fim NULL e sem
-- prazo_indeterminado, hoje recusado pela guarda de criação de afastamentos —
-- então a rotina quebrava no próprio setup, antes de testar a asserção. Além
-- disso, o gatilho de produção que barra a dispensa imotivada com afastamento
-- ativo estava só no monolito (nunca colado) — logo a asserção também não tinha
-- o que a proteger na produção.
--
-- Este script leva os dois (origem: migration 20260913150200):
--   1) gatilho admissao_bloqueia_dispensa_com_afastamento em admissoes: recusa a
--      transição para 'desligado' com motivo de dispensa imotivada quando há
--      afastamento ATIVO do mesmo CPF (falecimento, término de contrato a termo,
--      justa causa etc. seguem liberados).
--   2) fixture corrigido da rotina qa_caso_desl_003 (afastamento ativo sem
--      retorno = prazo indeterminado). Só o fixture muda; a asserção é idêntica.
--
-- SEGURANÇA: só CREATE OR REPLACE FUNCTION + TRIGGER. Não cria tabela (auto-RLS
-- não liga), não apaga dado. O gatilho é BEFORE UPDATE em admissoes (tabela
-- quente) — se der "deadlock detected", rode de novo (idempotente). lock_timeout curto.
-- ============================================================================

SET lock_timeout = '10s';

-- 1) Gatilho: dispensa imotivada vedada com afastamento ativo (CLT art. 476).
CREATE OR REPLACE FUNCTION public.admissao_bloqueia_dispensa_com_afastamento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_afast_ativos integer;
BEGIN
    IF NEW.status = 'desligado'
       AND (OLD.status IS DISTINCT FROM NEW.status)
       AND lower(coalesce(NEW.motivo_desligamento, '')) IN ('sem_justa_causa', 'dispensa_arbitraria') THEN

        SELECT count(*) INTO v_afast_ativos
          FROM public.afastamentos a
         WHERE a.tenant_id = NEW.tenant_id
           AND regexp_replace(coalesce(a.colaborador_cpf, ''), '\D', '', 'g')
             = regexp_replace(coalesce(NEW.cpf, ''), '\D', '', 'g')
           AND a.status = 'ativo';

        IF v_afast_ativos > 0 THEN
            RAISE EXCEPTION 'Dispensa sem justa causa vedada: colaborador com afastamento ativo — o contrato está suspenso (CLT art. 476). Encerre o afastamento antes, ou registre motivo permitido (falecimento, término de contrato a termo, justa causa).';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_admissao_bloqueia_dispensa_afastamento ON public.admissoes;
CREATE TRIGGER trg_admissao_bloqueia_dispensa_afastamento
BEFORE UPDATE ON public.admissoes
FOR EACH ROW EXECUTE FUNCTION public.admissao_bloqueia_dispensa_com_afastamento();

-- 2) Fixture da rotina DESL-003 (afastamento ativo = prazo indeterminado).
CREATE OR REPLACE FUNCTION public.qa_caso_desl_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_adm uuid; v_cpf text := public.qa_cpf(100003); v_aceitou boolean := false;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao  := 'Cadastrar colaborador com afastamento ATIVO e sem data de retorno';
  INSERT INTO public.admissoes
    (tenant_id, nome_completo, cpf, email, cargo, status, data_admissao)
  VALUES (v_t, '[QA-DESL-003] Colaborador', v_cpf,
          'qa.desl003@sandbox.invalid', 'Operador', 'concluido', CURRENT_DATE - 1000)
  RETURNING id INTO v_adm;

  -- Afastamento ativo sem previsão de retorno = prazo indeterminado (contrato suspenso).
  INSERT INTO public.afastamentos
    (tenant_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim, status, prazo_indeterminado)
  VALUES (v_t, '[QA-DESL-003] Colaborador', v_cpf, CURRENT_DATE - 60, NULL, 'ativo', true);

  r.passo_ordem := 2;
  r.passo_acao  := 'Tentar dispensa sem justa causa com o contrato suspenso';
  r.esperado    := 'Recusado — CLT art. 476: durante o auxilio-doenca o contrato esta suspenso';
  BEGIN
    UPDATE public.admissoes SET
      status = 'desligado', data_desligamento = CURRENT_DATE,
      motivo_desligamento = 'sem_justa_causa'
    WHERE id = v_adm;
    v_aceitou := true;
  EXCEPTION WHEN OTHERS THEN v_aceitou := false;
  END;

  IF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido   := 'ACEITOU dispensa imotivada com afastamento ativo e sem retorno formal. '
               || 'O contrato suspenso (CLT art. 476) nao admite dispensa imotivada — o '
               || 'ato e ineficaz e a discussao vira reintegracao. A tela consulta '
               || 'afastamentos, mas o banco nao impede a gravacao por nenhuma outra rota. '
               || 'Correcao sugerida: trigger que recuse desligamento imotivado havendo '
               || 'afastamento ativo, liberando falecimento e termino de contrato a termo.';
  ELSE
    r.situacao := 'passou';
    r.obtido   := 'Recusado pelo banco. A suspensao do contrato e respeitada na escrita.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

-- ════════════════════ CONFERÊNCIA (única — esperado tudo 'ok') ════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('DESL-003 · gatilho de bloqueio da dispensa (admissoes)',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_admissao_bloqueia_dispensa_afastamento' AND NOT tgisinternal)),
    ('DESL-003 · função de bloqueio presente',
       (to_regprocedure('public.admissao_bloqueia_dispensa_com_afastamento()') IS NOT NULL)),
    ('DESL-003 · fixture com prazo_indeterminado (não quebra no setup)',
       (pg_get_functiondef('public.qa_caso_desl_003()'::regprocedure) ~* 'prazo_indeterminado'))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao FROM alvo ORDER BY item;
