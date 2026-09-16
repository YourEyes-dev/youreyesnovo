/// <reference types="cypress" />

// =====================================================================
// Módulo Prestadores / Terceiros (/terceiros) — testes de tela (nível e2e).
// Cada it() corresponde a um caso documentado (TERC-TELA-*), ligado pela
// ponte qa_cobertura_e2e. Escopo: entrada de cada caso (módulo/abas montam,
// o formulário abre), sem salvar nada nem depender de dado semeado.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Prestadores / Terceiros", () => {
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
    cy.visit(`${baseUrl}/terceiros`);
    cy.contains("h1", "Gestão de Terceiros & SST", { timeout: 20000 }).should("be.visible");
  });

  // TERC-TELA-01
  it("abre o módulo Terceiros com as abas", () => {
    cy.contains("button", "Novo Terceiro", { timeout: 20000 }).should("be.visible");
    cy.contains('[role="tab"]', "Dashboard").should("exist");
    cy.contains('[role="tab"]', "Terceiros").should("exist");
    cy.contains('[role="tab"]', "Permissões de Trabalho").should("exist");
    cy.contains('[role="tab"]', "Vencimentos").should("exist");
  });

  // TERC-TELA-02
  it("abre o formulário de Novo Terceiro", () => {
    cy.contains("button", "Novo Terceiro", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 }).should("be.visible");
  });

  // TERC-TELA-03
  it("abre a aba Terceiros e tem a busca", () => {
    abrirAba("Terceiros");
    cy.get('input[placeholder*="Buscar por razão social"]', { timeout: 20000 }).should("exist");
  });

  // TERC-TELA-04
  it("abre a aba Permissões de Trabalho", () => {
    abrirAba("Permissões de Trabalho");
  });

  // TERC-TELA-05
  it("abre a aba Vencimentos", () => {
    abrirAba("Vencimentos");
  });

  // TERC-TELA-06
  it("abre a aba Dashboard", () => {
    abrirAba("Dashboard");
  });

  // TERC-TELA-07
  it("mostra o estado vazio orientando a cadastrar o primeiro terceiro", () => {
    abrirAba("Terceiros");
    cy.contains("Nenhum terceiro cadastrado", { timeout: 20000 }).should("be.visible");
  });
});
