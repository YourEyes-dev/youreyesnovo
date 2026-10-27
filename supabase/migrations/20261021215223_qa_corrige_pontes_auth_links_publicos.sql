-- =========================================================
-- QA — corrige as pontes AUTH-050..059 (links públicos).
--
-- A migration 20261021204922 gravou em qa_cobertura_e2e o TÍTULO DO CASO (com maiúscula
-- inicial) em vez do título exato do it() em cypress/e2e/links-publicos.cy.ts (minúsculo).
-- A guarda da esteira (qa:cobertura-e2e) não achou a ponte, tratou os 10 testes como
-- "sem caso documentado" e reprovou o job de testes de tela. Aqui a ponte passa a ter o
-- título exato do it(). Idempotente (delete-then-insert por código); só dado de QA.
-- =========================================================

SET lock_timeout = '10s';

DO $ponte$
BEGIN
  DELETE FROM public.qa_cobertura_e2e
  WHERE codigo IN ('AUTH-050','AUTH-051','AUTH-052','AUTH-053','AUTH-054',
                   'AUTH-055','AUTH-056','AUTH-057','AUTH-058','AUTH-059');

  INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
  VALUES
  ('AUTH-050', 'cypress/e2e/links-publicos.cy.ts', 'aceite de documento com link inexistente mostra link inválido'),
  ('AUTH-051', 'cypress/e2e/links-publicos.cy.ts', 'assinatura de contrato com link inexistente mostra contrato não encontrado'),
  ('AUTH-052', 'cypress/e2e/links-publicos.cy.ts', 'assinar contrato de parceiro com link inexistente mostra link inválido'),
  ('AUTH-053', 'cypress/e2e/links-publicos.cy.ts', 'assinatura de férias com link inexistente mostra link inválido'),
  ('AUTH-054', 'cypress/e2e/links-publicos.cy.ts', 'assinatura de PDI com link inexistente mostra link inválido'),
  ('AUTH-055', 'cypress/e2e/links-publicos.cy.ts', 'assinatura de experiência com link inexistente mostra link inválido'),
  ('AUTH-056', 'cypress/e2e/links-publicos.cy.ts', 'assinatura do manual de função com link inexistente mostra link inválido'),
  ('AUTH-057', 'cypress/e2e/links-publicos.cy.ts', 'assinatura de ordem de serviço com link inexistente mostra link inválido'),
  ('AUTH-058', 'cypress/e2e/links-publicos.cy.ts', 'ouvidoria externa com link inexistente mostra link inválido'),
  ('AUTH-059', 'cypress/e2e/links-publicos.cy.ts', 'entrevista guiada com link inexistente mostra link inválido');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Ponte e2e (links públicos) não corrigida: %', SQLERRM;
END $ponte$;

SELECT 'pontes AUTH-050..059 com título do it()' AS item,
       (SELECT count(*)::text FROM public.qa_cobertura_e2e
         WHERE codigo ~ '^AUTH-05[0-9]$' AND teste = lower(left(teste,1)) || substr(teste,2)) AS valor;
