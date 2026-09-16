/// <reference types="cypress" />

// =====================================================================
// Módulo Documentos — testes de tela (nível e2e).
// Cada it() corresponde a um caso documentado (DOCS-TELA-*), ligado pela
// ponte qa_cobertura_e2e. Escopo: entrada de cada caso (o módulo/abas montam,
// os formulários abrem), sem salvar nada nem depender de dado semeado.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Documentos", () => {
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
    cy.visit(`${baseUrl}/documentos`);
    cy.contains("h1", "Documentos", { timeout: 20000 }).should("be.visible");
  });

  // DOCS-TELA-01
  it("abre o módulo Documentos com as abas", () => {
    cy.contains("button", "Nova Pasta", { timeout: 20000 }).should("be.visible");
    cy.contains("button", "Upload").should("be.visible");
    cy.contains('[role="tab"]', "Estrutura").should("exist");
    cy.contains('[role="tab"]', "Conformidade").should("exist");
    cy.contains('[role="tab"]', "Auditoria").should("exist");
  });

  // DOCS-TELA-03
  it("abre o formulário de Nova Pasta", () => {
    cy.contains("button", "Nova Pasta", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 }).should("be.visible");
  });

  // DOCS-TELA-04
  it("abre o formulário de Upload", () => {
    cy.contains("button", "Upload", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 }).should("be.visible");
  });

  // DOCS-TELA-05
  it("abre a aba Conformidade", () => {
    abrirAba("Conformidade");
    cy.contains("Mapa de Conformidade Documental", { timeout: 20000 }).should("be.visible");
  });

  // DOCS-TELA-06
  it("abre a aba Governança", () => {
    abrirAba("Governança");
  });

  // DOCS-TELA-09
  it("abre a aba Auditoria", () => {
    abrirAba("Auditoria");
  });

  // DOCS-TELA-07
  it("abre a aba PDCA", () => {
    abrirAba("PDCA");
    cy.contains("Motor de Melhoria Contínua", { timeout: 20000 }).should("be.visible");
  });

  // DOCS-TELA-08
  it("abre a aba Notificações", () => {
    abrirAba("Notificações");
    cy.contains("Configuração de Alertas", { timeout: 20000 }).should("be.visible");
  });
});
