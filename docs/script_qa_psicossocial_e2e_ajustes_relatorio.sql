-- =====================================================================
-- ENTREGA — QA e2e das telas do Relatório de Melhorias do Psicossocial
--
-- Documenta 4 casos de tela (nível e2e) e a ponte caso <-> it() para os
-- ajustes do Relatório de Melhorias:
--   TELA-PSICO-051  Plano de Ação PGR em linhas expansíveis por GHE (item 6)
--   TELA-PSICO-052  Enviar ao GRO abre confirmação rastreável (item 4)
--   TELA-PSICO-053  Revisar ação da IA abre rascunho editável (item 2)
--   TELA-PSICO-054  Contraprova mostra evidências ou sem dados (item 1)
--
-- Equivale à migration 20260929234745_qa_psicossocial_e2e_ajustes_relatorio.
-- Só INSERTs idempotentes (sem tabela nova, sem função, sem dado sensível).
-- Cole no SQL Editor de PRODUÇÃO. Rodar duas vezes não duplica nem quebra.
-- =====================================================================

INSERT INTO public.qa_casos_teste
  (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, observacoes)
SELECT m.id, v.codigo, v.titulo,
       v.tipo::public.qa_caso_tipo,
       'media'::public.qa_prioridade,
       'aprovado'::public.qa_caso_status,
       'e2e',
       'Tela do Relatório de Melhorias do Psicossocial. Teste de tela em cypress/e2e/psicossocial.cy.ts; o resultado da suíte cai no relatório de QA.',
       'Criado a partir do título real do it(). A ligação com o Cypress vive em qa_cobertura_e2e.'
FROM public.qa_modulos m
CROSS JOIN (VALUES
    ('TELA-PSICO-051', 'TC-51: Plano de Ação PGR em linhas expansíveis por GHE', 'alternativo'),
    ('TELA-PSICO-052', 'TC-52: Enviar ao GRO abre confirmação rastreável', 'feliz'),
    ('TELA-PSICO-053', 'TC-53: Revisar ação da IA abre rascunho editável', 'feliz'),
    ('TELA-PSICO-054', 'TC-54: Contraprova mostra evidências ou sem dados', 'alternativo')
) AS v(codigo, titulo, tipo)
WHERE m.path = 'saude-seguranca/psicossocial'
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, 'cypress/e2e/psicossocial.cy.ts', v.teste
FROM (VALUES
    ('TELA-PSICO-051', 'TC-51: Plano de Ação PGR em linhas expansíveis por GHE'),
    ('TELA-PSICO-052', 'TC-52: Enviar ao GRO abre confirmação rastreável'),
    ('TELA-PSICO-053', 'TC-53: Revisar ação da IA abre rascunho editável'),
    ('TELA-PSICO-054', 'TC-54: Contraprova mostra evidências ou sem dados')
) AS v(codigo, teste)
WHERE EXISTS (SELECT 1 FROM public.qa_casos_teste c WHERE c.codigo = v.codigo)
ON CONFLICT (codigo) DO UPDATE
  SET spec = EXCLUDED.spec, teste = EXCLUDED.teste, ativo = true;

-- ── Conferência (o SQL Editor mostra só o último resultado) ──────────
SELECT c.codigo,
       c.nivel,
       cob.spec,
       cob.teste,
       CASE WHEN cob.codigo IS NULL THEN 'PONTE AUSENTE' ELSE 'ok' END AS ponte
FROM public.qa_casos_teste c
LEFT JOIN public.qa_cobertura_e2e cob ON cob.codigo = c.codigo
WHERE c.codigo IN ('TELA-PSICO-051','TELA-PSICO-052','TELA-PSICO-053','TELA-PSICO-054')
ORDER BY c.codigo;
