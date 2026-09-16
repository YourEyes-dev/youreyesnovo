/// <reference types="cypress" />

// =====================================================================
// MarketYE — testes de tela (nível e2e).
// Cada it() corresponde a um caso documentado (qa_casos_teste, nível e2e)
// ligado pela ponte qa_cobertura_e2e: MKY-020, MKY-021, MKY-022.
// MKY-020/021 entram com a conta-robô da empresa de teste; MKY-022 é público.
// O mobiliário da ilha de teste ("Especialista Staging (QA)", 2 anúncios
// publicados) é semeado/reparado a cada corrida pela função do banco
// marketye_semear_ilha_teste(), chamada pelo passo "Semear a conta-robô"
// (seed-e2e-user); o diagnóstico sai na resposta do seed, no log da esteira.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("MarketYE", () => {
  const { email, senha: password } = credenciaisDeTeste();
  const baseUrl = Cypress.config("baseUrl") as string;

  function login() {
    cy.visit(`${baseUrl}/login`);
    cy.get('input[type="email"]', { timeout: 20000 }).should("exist").scrollIntoView().should("be.visible").clear().type(email);
    cy.get('input[autocomplete="current-password"]', { timeout: 20000 }).should("exist").scrollIntoView().should("be.visible").clear().type(password, { log: false });
    cy.contains("button", /^Entrar$/).click();
    cy.aguardarSessaoSupabase();
    cy.wait(1500);
  }

  it("MKY-020: Cabeçalho: botão MarketYE abre a vitrine do marketplace de serviços", () => {
    login();
    cy.visit(`${baseUrl}/`);
    cy.get('[data-testid="header-marketye"]', { timeout: 30000 }).should("contain.text", "MarketYE");
    cy.contains("Rede de Parceiros").should("not.exist");
    cy.visit(`${baseUrl}/marketplace`);
    cy.get('[data-testid="marketye-titulo"]', { timeout: 30000 }).should("contain.text", "MarketYE");
    cy.get('[data-testid="marketye-busca"]').should("be.visible");
    cy.get('[data-testid="marketye-filtros"]').should("exist");
    cy.get('[data-testid="aba-conversas"]').should("exist");
  });

  it("MKY-021: Vitrine: filtrar por categoria lista anúncios; busca sem oferta oferece alternativas", () => {
    login();
    cy.visit(`${baseUrl}/marketplace?categoria=seguranca-trabalho`);
    cy.get('[data-testid="marketye-titulo"]', { timeout: 30000 }).should("exist");
    // Com a categoria do mobiliário de teste, ao menos um card aparece.
    cy.get('[data-testid="marketye-anuncio"]', { timeout: 30000 }).should("have.length.at.least", 1);
    cy.get('[data-testid="marketye-contatar"]').first().should("be.visible");
    // Termo sem oferta: nunca "0 resultados" seco — aviso + Avise-me.
    cy.get('[data-testid="marketye-busca"]').clear().type("xyzservicoinexistente{enter}");
    cy.get('[data-testid="marketye-vazio"]', { timeout: 30000 }).should("exist");
    cy.get('[data-testid="marketye-avise-me"]').should("exist");
  });

  it("MKY-022: Página pública MarketYE: proposta ao especialista e caminho para o cadastro", () => {
    cy.visit(`${baseUrl}/marketye`);
    cy.get('[data-testid="marketye-publico"]', { timeout: 30000 }).should("exist");
    cy.contains("h1", /empresas/i).should("be.visible");
    cy.get('[data-testid="marketye-cta-cadastro"]').click();
    cy.location("pathname", { timeout: 20000 }).should("match", /\/marketye\/cadastro$/);
    cy.get('[data-testid="marketye-cadastro"]').should("exist");
    cy.get('[data-testid="cad-nome"]').should("be.visible");
    cy.get('[data-testid="cad-email"]').should("be.visible");
    cy.get('[data-testid="cad-documento"]').should("be.visible");
    cy.get('[data-testid="cad-aceite"]').should("exist");
  });
});
