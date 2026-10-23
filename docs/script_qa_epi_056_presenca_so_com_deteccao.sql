-- ============================================================================
-- ENTREGA — QA do EPI: caso EPI-056 (presença só com detecção) e sua rotina
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de TESTE depois do script
-- script_epi_fix_presenca_so_com_deteccao.sql. Só documenta o caso e cria a
-- rotina; não altera comportamento nem dado de cliente. UMA transação,
-- idempotente, sem criar tabela.
-- ============================================================================

-- =========================================================
-- QA — EPI-056: a verificação de presença só conta como "detectada" quando houve
-- detecção automática registrada.
--
-- O defeito: epi_entregas.liveness_detected era verdadeiro sempre que o
-- colaborador percorria as etapas da tela (o wizard gravava livenessData !== null),
-- mesmo sem qualquer detecção do piscar ou da virada de cabeça. O nome do campo
-- prometia mais do que o sistema fazia, e isso pesa quando a ficha é contestada.
--
-- Regra no banco: liveness_detected só fica verdadeiro quando liveness_data traz
-- metodo = 'face-landmarker' (detecção automática no aparelho). Sem o método, ou
-- com 'manual', fica falso. O banco não consegue provar a detecção (ela acontece
-- no navegador), mas passa a impedir o rótulo sem o método declarado.
--
-- Só documenta e liga o teste; não altera comportamento. Idempotente.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'saude-ocupacional/epi');
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo saude-ocupacional/epi não encontrado.'; END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'EPI-056',
   'A verificação de presença só é marcada como detectada quando houve detecção automática registrada',
   'negativo', 'alta', 'aprovado', 'api',
   'Lei 14.063/2020, art. 4º (identificação do signatário); LGPD art. 6º, V e X (qualidade dos dados e prestação de contas); EPI-041 (biometria)',
   'Marcar a presença como "detectada" quando ninguém detectou nada afirma mais do que o sistema fez e enfraquece a ficha se contestada. O rótulo precisa refletir o método usado: detecção automática do piscar e da virada de cabeça, ou confirmação manual.',
   'Sandbox QA com um EPI em estoque.',
   '[{"ordem":1,"acao":"Registrar a entrega com liveness_detected verdadeiro e metodo face-landmarker","resultado_esperado":"Fica verdadeiro"},
     {"ordem":2,"acao":"Registrar com liveness_detected verdadeiro e metodo manual","resultado_esperado":"Fica falso"},
     {"ordem":3,"acao":"Registrar com liveness_detected verdadeiro e sem método (cliente antigo)","resultado_esperado":"Fica falso"}]'::jsonb,
   'O rótulo de presença detectada só existe com a detecção automática declarada.',
   'Guarda a opção A (detecção real). O banco só garante a coerência do rótulo; a detecção em si roda no navegador e a evidência (fotos e pontuações por ação) fica em liveness_data.')
  ON CONFLICT (codigo) DO UPDATE SET
    titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo, passos = EXCLUDED.passos,
    resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;
END $doc$;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_056()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_tipo uuid; v_epi uuid; v_auto boolean; v_manual boolean; v_legado boolean;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar entregas com o rótulo de presença verdadeiro e métodos diferentes';
  r.esperado := 'Verdadeiro só com metodo face-landmarker';
  INSERT INTO public.epi_tipos (tenant_id, nome, ca_numero, ca_validade, is_active)
  VALUES (v_t, 'QA — Luva presença', '99056', CURRENT_DATE + 365, true) RETURNING id INTO v_tipo;
  INSERT INTO public.epis (tenant_id, tipo_id, codigo, quantidade_estoque, data_validade)
  VALUES (v_t, v_tipo, 'QA-EPI-056', 10, CURRENT_DATE + 365) RETURNING id INTO v_epi;

  v_auto := (public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 056 A',
    'colaborador_cpf', public.qa_cpf(56), 'quantidade', 1, 'data_entrega', CURRENT_DATE,
    'status', 'ativa', 'assinatura_url', 'qa/a.png', 'signed_at', now(),
    'liveness_detected', true,
    'liveness_data', jsonb_build_object('metodo', 'face-landmarker')))->>'liveness_detected')::boolean;
  v_manual := (public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 056 B',
    'colaborador_cpf', public.qa_cpf(56), 'quantidade', 1, 'data_entrega', CURRENT_DATE,
    'status', 'ativa', 'assinatura_url', 'qa/b.png', 'signed_at', now(),
    'liveness_detected', true,
    'liveness_data', jsonb_build_object('metodo', 'manual')))->>'liveness_detected')::boolean;
  v_legado := (public.epi_registrar_entrega(jsonb_build_object(
    'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 056 C',
    'colaborador_cpf', public.qa_cpf(56), 'quantidade', 1, 'data_entrega', CURRENT_DATE,
    'status', 'ativa', 'assinatura_url', 'qa/c.png', 'signed_at', now(),
    'liveness_detected', true,
    'liveness_data', jsonb_build_object('actions', jsonb_build_array('blink'))))->>'liveness_detected')::boolean;

  IF v_manual IS TRUE OR v_legado IS TRUE THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o rótulo de presença detectada foi gravado como verdadeiro sem detecção automática (manual: %s; sem método: %s).',
                       v_manual, v_legado);
  ELSIF v_auto IS NOT TRUE THEN
    r.situacao := 'falhou';
    r.obtido := 'Com a detecção automática declarada o rótulo deveria ficar verdadeiro e ficou falso.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'O rótulo de presença detectada só ficou verdadeiro com metodo face-landmarker; manual e sem método ficaram falsos.';
  END IF;
  r.detalhe := jsonb_build_object('automatico', v_auto, 'manual', v_manual, 'sem_metodo', v_legado);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('EPI-056', 'qa_caso_epi_056')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql;

-- Conferência final (o editor mostra só este resultado):
SELECT
  EXISTS (SELECT 1 FROM public.qa_casos_teste WHERE codigo = 'EPI-056') AS caso_documentado,
  EXISTS (SELECT 1 FROM public.qa_implementacoes WHERE codigo = 'EPI-056'
           AND funcao_sql = 'qa_caso_epi_056') AS rotina_registrada,
  (SELECT count(*) FROM pg_proc WHERE proname = 'qa_caso_epi_056') AS funcao_criada,
  NULL::text AS erro_tecnico;

-- Para desfazer:
--   DELETE FROM public.qa_implementacoes WHERE codigo = 'EPI-056';
--   DROP FUNCTION IF EXISTS public.qa_caso_epi_056();
--   DELETE FROM public.qa_casos_teste WHERE codigo = 'EPI-056';
