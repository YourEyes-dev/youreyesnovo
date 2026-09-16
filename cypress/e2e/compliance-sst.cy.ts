/// <reference types="cypress" />

// =====================================================================
// Módulo Compliance SST — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (CSST-TELA-*), ligado pela
// ponte qa_cobertura_e2e. Escopo: a entrada de cada caso (o módulo monta,
// as abas abrem, o aviso legal aparece), sem depender de dado semeado.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Compliance SST", () => {
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

  function abrirAba(texto: string) {
    cy.contains('[role="tab"]', texto, { timeout: 20000 }).click({ force: true });
    cy.contains('[role="tab"]', texto).should("have.attr", "data-state", "active");
  }

  beforeEach(() => {
    login();
    cy.visit(`${baseUrl}/compliance-sst`);
    cy.contains("h1", "Compliance SST", { timeout: 20000 }).should("be.visible");
  });

  // CSST-TELA-01
  it("abre o módulo Compliance SST com o aviso legal e as abas", () => {
    cy.contains("Aviso legal", { timeout: 20000 }).should("be.visible");
    cy.contains('[role="tab"]', "Importação IA").should("exist");
    cy.contains('[role="tab"]', "Documentos").should("exist");
    cy.contains('[role="tab"]', "eSocial").should("exist");
  });

  // CSST-TELA-02
  it("abre a aba Importação IA", () => {
    abrirAba("Importação IA");
  });

  // CSST-TELA-03
  it("abre a aba Documentos", () => {
    abrirAba("Documentos");
  });

  // CSST-TELA-04
  it("abre a aba Ordem De Serviço", () => {
    abrirAba("Ordem De Serviço");
  });

  // CSST-TELA-05
  it("abre a aba Painel", () => {
    abrirAba("Painel");
  });

  // CSST-TELA-08
  it("abre a aba eSocial com a auditoria de eventos", () => {
    abrirAba("eSocial");
    cy.contains("Auditoria eSocial", { timeout: 20000 }).should("be.visible");
  });

  // CSST-TELA-09
  it("mostra o aviso legal de escopo (PGR, PCMSO, LTCAT)", () => {
    cy.contains("PGR, PCMSO, LTCAT", { timeout: 20000 }).should("be.visible");
  });
});
