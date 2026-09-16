-- ============================================================================
-- Fase 0 do plano de correção do Motor — DESL-003
-- Contrato suspenso por afastamento não admite dispensa imotivada (CLT art. 476).
--
-- ACHADO do Motor: o banco aceitava UPDATE de admissoes para status 'desligado'
-- com motivo 'sem_justa_causa' mesmo havendo afastamento ATIVO do colaborador.
-- Durante a suspensão do contrato a dispensa imotivada é ineficaz — a discussão
-- vira reintegração. A tela consultava afastamentos, mas nenhuma trava impedia a
-- gravação por outras rotas.
--
-- Correção: gatilho BEFORE UPDATE em admissoes que recusa a transição para
-- 'desligado' quando (1) o motivo é dispensa imotivada (sem_justa_causa) e
-- (2) existe afastamento ativo do mesmo CPF no tenant. Falecimento, término de
-- contrato a termo, justa causa, pedido de demissão e demais motivos seguem
-- liberados (a vedação do art. 476 é da dispensa imotivada).
--
-- Também corrige o FIXTURE da própria rotina qa_caso_desl_003: ela inseria um
-- afastamento ativo com data_fim NULL e sem prazo_indeterminado, hoje recusado
-- pela guarda de criação (20260813100000). Um afastamento ativo sem previsão de
-- retorno É, por definição, prazo indeterminado — o próprio "contrato suspenso"
-- do caso. Só o fixture muda; a asserção permanece idêntica.
-- ============================================================================

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


-- ── Fixture da rotina DESL-003 atualizado (afastamento ativo = prazo indeterminado) ──
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
