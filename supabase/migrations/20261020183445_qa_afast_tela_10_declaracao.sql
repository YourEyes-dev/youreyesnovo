-- =========================================================
-- QA — Caso e2e AFAST-TELA-10: Declaração de comparecimento sem CRM.
--
-- Documenta (Documentação de Testes) + liga (qa_cobertura_e2e) o teste de tela
-- que guarda a regra da declaração de comparecimento no formulário de atestado:
-- ao escolher o tipo "Declaração de comparecimento", o formulário NÃO exige
-- CRM nem médico (é comprovante de presença, não atestado de incapacidade) e
-- esconde a seção médica/CID. Regressão real já corrigida (#844/#845).
--
-- Módulo: jornada-rotina/afastamentos (Central GAF, /atestados), onde moram os
-- demais AFAST-TELA-*. Nível e2e. Spec: cypress/e2e/afastamentos.cy.ts.
--
-- Idempotente: o caso usa ON CONFLICT (codigo) DO NOTHING; a ponte é
-- delete-then-insert por codigo (converge o título do it() em qualquer estado).
-- =========================================================

SET lock_timeout = '10s';

-- 1) Caso documentado (nível e2e) no módulo de Afastamentos.
DO $doc$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'jornada-rotina/afastamentos';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo jornada-rotina/afastamentos não encontrado.'; END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'AFAST-TELA-10',
   'Declaração de comparecimento abre sem exigir CRM',
   'feliz', 'alta', 'aprovado', 'e2e',
   'CLT art. 473 (declaração de comparecimento: comprovante de presença, não atestado de incapacidade)',
   'A declaração de comparecimento costuma vir de clínica ou secretaria de saúde, sem profissional com registro. O formulário não pode exigir CRM nem médico; se exigir, trava o lançamento.',
   'Usuário autenticado com acesso ao módulo; Central GAF (/atestados).',
   '[{"ordem":1,"acao":"Abrir a aba Atestados e clicar em Novo Atestado","resultado_esperado":"Abre o diálogo do formulário"},
     {"ordem":2,"acao":"Em Tipo de Lançamento, escolher Declaração de comparecimento","resultado_esperado":"Aparece o bloco Não exige CRM nem CID com a chave Abonar o dia; a seção médica (CRM/CRO) some"}]'::jsonb,
   'O tipo Declaração de comparecimento abre sem campo de CRM e sem exigir médico.',
   'Declaração de comparecimento, Fatia 2b. Guarda a regressão corrigida em #844/#845.')
  ON CONFLICT (codigo) DO NOTHING;
END $doc$;

-- 2) Ponte caso -> it() (título EXATO do it() em afastamentos.cy.ts).
DELETE FROM public.qa_cobertura_e2e WHERE codigo = 'AFAST-TELA-10';
INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
VALUES ('AFAST-TELA-10', 'cypress/e2e/afastamentos.cy.ts',
        'abre a Declaração de comparecimento sem exigir CRM');
