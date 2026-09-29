-- =====================================================================
-- QA e2e — telas do Relatório de Melhorias do Psicossocial
--
-- O Relatório de Melhorias trouxe quatro telas/fluxos que não tinham
-- caso de tela documentado nem teste de Cypress:
--   - Plano de Ação PGR em linhas expansíveis por GHE (item 6)
--   - Confirmação rastreável do "Enviar ao GRO" (item 4)
--   - Preview editável do 5W2H da IA antes de criar a ação (item 2)
--   - Contraprova distinguindo "sem dados" de "saudável" (item 1)
--
-- Aqui documentamos os quatro casos (TELA-PSICO-051..054, nível e2e) e a
-- ponte caso <-> it() em qa_cobertura_e2e. Os títulos são os títulos reais
-- dos it() em cypress/e2e/psicossocial.cy.ts — renomear um it() sem mexer
-- aqui quebra a ligação (a guarda npm run qa:cobertura-e2e denuncia).
--
-- Idempotente: rodar duas vezes não duplica nem quebra.
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
