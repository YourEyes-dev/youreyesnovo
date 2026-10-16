-- =====================================================================
-- Ponte de cobertura e2e — 13º Salário (cypress/e2e/decimo-terceiro.cy.ts)
--
-- Liga cada caso DEC13 de nivel 'e2e' ao it() que o exercita na tela
-- (qa_cobertura_e2e: codigo -> spec + titulo exato do it()). A guarda
-- scripts/verificar-cobertura-e2e.mjs cruza estas linhas com os it() reais.
-- O titulo precisa bater AO CARACTERE com o do it() no spec.
--
-- Primeiro lote: 9 dos 10 casos e2e do modulo. Fica de fora DEC13-042
-- (FGTS nas duas parcelas), que so aparece no detalhe de um 13º ja
-- calculado — exige fixture; sera ligado quando houver semeadura.
-- =====================================================================
INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste, ativo, criado_em) VALUES
  ('DEC13-001', 'cypress/e2e/decimo-terceiro.cy.ts', 'apuração conta os avos (1/12 por mês, fração de 15 dias)', true, now()),
  ('DEC13-002', 'cypress/e2e/decimo-terceiro.cy.ts', 'apuração considera as faltas no cômputo dos avos', true, now()),
  ('DEC13-003', 'cypress/e2e/decimo-terceiro.cy.ts', 'política do 13º trata os afastamentos (15 dias antes do INSS)', true, now()),
  ('DEC13-020', 'cypress/e2e/decimo-terceiro.cy.ts', 'apuração soma a média das variáveis do ano', true, now()),
  ('DEC13-032', 'cypress/e2e/decimo-terceiro.cy.ts', 'oferece o adiantamento do 13º nas férias e a política da 1ª parcela', true, now()),
  ('DEC13-033', 'cypress/e2e/decimo-terceiro.cy.ts', 'na 2ª parcela, a tela deduz a 1ª parcela já paga', true, now()),
  ('DEC13-040', 'cypress/e2e/decimo-terceiro.cy.ts', 'a apuração do 13º expõe a coluna de INSS', true, now()),
  ('DEC13-041', 'cypress/e2e/decimo-terceiro.cy.ts', 'a apuração do 13º expõe a coluna de IRRF', true, now()),
  ('DEC13-060', 'cypress/e2e/decimo-terceiro.cy.ts', 'apura o 13º proporcional pelos avos desde a admissão', true, now())
ON CONFLICT (codigo) DO UPDATE SET
  spec = EXCLUDED.spec, teste = EXCLUDED.teste, ativo = true;
