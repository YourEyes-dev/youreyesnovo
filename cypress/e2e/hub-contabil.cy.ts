/// <reference types="cypress" />

// =====================================================================
// Módulo Hub Contábil — testes de tela (nível e2e).
// Cada it() corresponde a um caso documentado (HUBC-TELA-*), ligado pela
// ponte qa_cobertura_e2e. Escopo: entrada de cada caso (módulo/abas montam,
// o modal de novo processo abre), sem salvar nada nem depender de dado semeado.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Hub Contábil", () => {
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
    cy.visit(`${baseUrl}/hub-contabil`);
    cy.contains("h1", "Hub de Comunicação Contábil", { timeout: 20000 }).should("be.visible");
  });

  // HUBC-TELA-01
  it("abre o Hub Contábil com o painel e as abas", () => {
    cy.contains('[role="tab"]', "Painel").should("exist");
    cy.contains('[role="tab"]', "Férias").should("exist");
    cy.contains('[role="tab"]', "Kanban").should("exist");
  });

  // HUBC-TELA-03
  it("abre o modal de novo processo", () => {
    cy.contains("button", /Nova Solicitação|Novo Processo/, { timeout: 20000 })
      .first().click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 }).should("be.visible");
  });

  // HUBC-TELA-04
  it("abre uma aba por tipo (Férias)", () => {
    abrirAba("Férias");
  });

  // HUBC-TELA-05
  it("abre a aba Kanban", () => {
    abrirAba("Kanban");
  });

  // HUBC-TELA-07
  it("abre a aba Relatórios", () => {
    abrirAba("Relatórios");
  });

  // HUBC-TELA-08
  it("abre a aba Config", () => {
    abrirAba("Config");
  });
});
