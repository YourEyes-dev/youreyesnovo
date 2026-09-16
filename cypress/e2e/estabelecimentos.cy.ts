/// <reference types="cypress" />

// =====================================================================
// Módulo Estabelecimentos (/cadastros/filiais) — testes de tela (e2e).
// Cada it() corresponde a um caso documentado (ESTAB-TELA-*), ligado pela
// ponte qa_cobertura_e2e.
//
// Escopo: a fase de ENTRADA da tela — a página monta e pede para selecionar a
// empresa (matriz), com a busca por CNPJ. Os casos que dependem de uma empresa
// já selecionada COM registros (lista, Novo Registro, CNO da obra) seguem na
// homologação manual — um teste de tela não semeia essa massa de forma confiável.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Estabelecimentos", () => {
  const { email, senha: password } = credenciaisDeTeste();
  const baseUrl = Cypress.config("baseUrl") as string;

  function login() {
    cy.visit(`${baseUrl}/login`);
    cy.get('input[type="email"]', { timeout: 20000 })
      .should("exist").scrollIntoView().should("be.visible").clear().type(email);
    cy.get('input[autocomplete="current-password"]', { timeout: 20000 })
      .should("exist").scrollIntoView().should("be.visible").clear().type(password, { log: false });
    cy.contains("button", /^Entrar$/).click();
    cy.aguardarSessaoSupabase();
    cy.wait(1500);
  }

  beforeEach(() => {
    login();
    cy.visit(`${baseUrl}/cadastros/filiais`);
    cy.contains("h1", "Estabelecimento ou Obra", { timeout: 20000 }).should("be.visible");
  });

  // ESTAB-TELA-01
  it("pede para selecionar a empresa (matriz)", () => {
    cy.contains("Selecione a empresa", { timeout: 20000 }).should("be.visible");
  });

  // ESTAB-TELA-07
  it("tem a busca de empresa por CNPJ", () => {
    cy.get('input[placeholder*="Buscar por CNPJ"]', { timeout: 20000 }).should("exist");
  });
});
