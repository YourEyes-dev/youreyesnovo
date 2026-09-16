/// <reference types="cypress" />

// =====================================================================
// Módulo Análise de Jornada (/analise-jornada) — testes de tela (nível e2e).
// Cada it() corresponde a um caso documentado (AJOR-*), ligado pela ponte
// qa_cobertura_e2e. Escopo: entrada de cada caso (o módulo monta e cada aba
// abre), sem rodar a análise nem depender de dado semeado.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Análise de Jornada", () => {
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
    cy.visit(`${baseUrl}/analise-jornada`);
    cy.contains("h1", "Análise de Carga de Trabalho & Jornada", { timeout: 20000 }).should("be.visible");
  });

  // AJOR-001
  it("abre o módulo Análise de Jornada com as 8 abas", () => {
    ["Dashboard", "Importação", "Individual", "Coletiva", "Conformidade", "Alertas", "Documentos", "Relatórios"]
      .forEach((t) => cy.contains('[role="tab"]', t).should("exist"));
  });

  // AJOR-011
  it("abre a aba Dashboard", () => {
    abrirAba("Dashboard");
  });

  // AJOR-030
  it("abre a aba Importação", () => {
    abrirAba("Importação");
  });

  // AJOR-040
  it("abre a aba Individual", () => {
    abrirAba("Individual");
  });

  // AJOR-050
  it("abre a aba Conformidade", () => {
    abrirAba("Conformidade");
  });

  // AJOR-060
  it("abre a aba Alertas", () => {
    abrirAba("Alertas");
  });

  // AJOR-070
  it("abre a aba Documentos", () => {
    abrirAba("Documentos");
  });

  // AJOR-080
  it("abre a aba Relatórios", () => {
    abrirAba("Relatórios");
  });
});
