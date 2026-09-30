-- ============================================================================
-- ENTREGA — corrige PONTO-001 e PONTO-024 (bateria dava "erro" à noite)
-- Colar no SQL Editor de HOMOLOGAÇÃO (e depois em produção, se quiser manter o
-- catálogo de QA igual).
--
-- ACHADO (bateria de 29/09/2026 21:11): as duas rotinas deram "erro" com
--   "Marcacao de ponto no futuro nao e aceita: informada 30/09 08:00, agora
--    29/09 21:11."
-- CAUSA: as rotinas semeavam a marcação em CURRENT_DATE, que segue o fuso da
-- sessão do banco (UTC), enquanto a trava de "marcação no futuro" compara com o
-- horário de São Paulo. Depois das 21h de Brasília o UTC já virou o dia seguinte,
-- então a marcação de teste caía no "futuro" e a trava (corretamente) recusava.
-- Só acontece na janela ~21h–24h BRT. A trava está certa (PONTO-376 comprova);
-- o dia usado no teste é que estava errado.
-- CORREÇÃO: ancorar as marcações de QA num dia ÚTIL PASSADO, como o resto do
-- catálogo já faz. Não muda nada no produto — só o dado de teste. Idempotente.
--
-- SEGURANÇA: só redefine duas funções de QA (nenhuma tabela criada, nenhum dado
-- de cliente tocado). Roda em qualquer horário.
-- ============================================================================

-- PONTO-001 — marcação gravada com data, hora, CPF e hash
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_cpf text; m record;
        v_dia date := public.qa_dia_util_passado();  -- dia util passado (nunca futuro)
BEGIN
  v_cpf := public.qa_ponto_admissao('QA Marcação Base', 5001);
  r.passo_ordem := 1;
  r.passo_acao := 'Registrar uma marcação e conferir os campos essenciais';
  r.esperado := 'Data, hora, CPF e hash presentes e coerentes';
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Marcação Base', v_dia, TIME '08:00', 'entrada');
  SELECT * INTO m FROM public.ponto_marcacoes
  WHERE tenant_id = public.qa_sandbox_tenant_id() AND colaborador_cpf = v_cpf
  ORDER BY created_at DESC LIMIT 1;
  IF m.data_marcacao = v_dia AND m.hora_marcacao = TIME '08:00'
     AND m.colaborador_cpf = v_cpf AND coalesce(m.hash_marcacao, '') <> ''
     AND m.hash_marcacao <> 'qa-seed' THEN
    r.situacao := 'passou';
    r.obtido := 'Marcação gravada com data, hora, CPF e hash gerado pelo gatilho.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Campos incompletos: data=%s hora=%s cpf=%s hash=%s. A identificação '
      || 'por CPF e o carimbo íntegro são a base da Portaria 671.',
      m.data_marcacao, m.hora_marcacao, m.colaborador_cpf,
      CASE WHEN coalesce(m.hash_marcacao,'') IN ('','qa-seed') THEN 'NÃO GERADO' ELSE 'ok' END);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PONTO-024 — ausência amparada não vira falta
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_024()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_cpf text; v_dia date := public.qa_dia_util_passado();
        v_status text;
BEGIN
  v_cpf := public.qa_ponto_admissao('QA Amparado', 5024);
  -- Batida em outro dia (passado, nunca futuro) só para o consolidador conseguir
  -- resolver o colaborador. CURRENT_DATE - 8 fica antes de v_dia e nunca cai no
  -- futuro, em qualquer fuso/horário.
  PERFORM public.qa_ponto_marca(v_cpf, 'QA Amparado', CURRENT_DATE - 8, TIME '08:00', 'entrada');
  INSERT INTO public.atestados
    (tenant_id, colaborador_cpf, colaborador_nome, tipo, data_emissao,
     profissional_nome, profissional_registro,
     data_inicio_afastamento, data_fim_afastamento, unidade_afastamento)
  VALUES (public.qa_sandbox_tenant_id(), v_cpf, 'QA Amparado',
          'atestados', v_dia, 'Dra. QA', 'CRM-QA-0001', v_dia, v_dia, 'dias');

  r.passo_ordem := 1;
  r.passo_acao := format('Materializar %s com atestado cobrindo o dia', v_dia);
  r.esperado := 'O dia não vira falta — ausência amparada tem regime próprio (art. 473 e afins)';
  PERFORM public.ponto_materializar_faltas(v_dia, v_dia, public.qa_sandbox_tenant_id());
  SELECT status INTO v_status FROM public.ponto_diario
  WHERE tenant_id = public.qa_sandbox_tenant_id() AND colaborador_cpf = v_cpf AND data = v_dia;

  IF coalesce(v_status, 'ausente') <> 'falta' THEN
    r.situacao := 'passou';
    r.obtido := format('O dia amparado por atestado não virou falta (ficou: %s).',
                       coalesce(v_status, 'sem linha — dia não materializado como falta'));
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'O dia COM ATESTADO virou falta — desconto indevido de DSR e de salário sobre '
             || 'ausência amparada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- Conferência (o editor mostra só o último resultado): confirma que as duas
-- rotinas passaram a ancorar em dia passado. Não executa as rotinas (evita
-- confusão com a trava anti-toque em reexecuções no mesmo dia).
SELECT
  position('qa_dia_util_passado' IN pg_get_functiondef('public.qa_caso_ponto_001()'::regprocedure)) > 0
    AS ponto_001_corrigido,
  position('CURRENT_DATE - 8' IN pg_get_functiondef('public.qa_caso_ponto_024()'::regprocedure)) > 0
    AS ponto_024_corrigido;
