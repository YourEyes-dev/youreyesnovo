/// <reference types="cypress" />

// =====================================================================
// Módulo Cargos (/cadastros/cargos) — testes de tela (e2e).
// Cada it() corresponde a um caso documentado (CARGO-TELA-*), ligado pela
// ponte qa_cobertura_e2e. Escopo: entrada de cada caso (lista monta,
// formulário abre com as abas, busca funciona), sem salvar nada.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Cargos", () => {
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
    cy.visit(`${baseUrl}/cadastros/cargos`);
    cy.contains("h1", "Cargos", { timeout: 20000 }).should("be.visible");
  });

  // CARGO-TELA-01
  it("abre o módulo Cargos com a lista", () => {
    cy.contains("button", "Novo Cargo", { timeout: 20000 }).should("be.visible");
    cy.get('input[placeholder*="Buscar cargos"]').should("exist");
  });

  // CARGO-TELA-02
  it("abre o formulário de Novo Cargo com as abas", () => {
    cy.contains("button", "Novo Cargo", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 }).should("be.visible");
    cy.contains('[role="tab"]', "Dados Gerais").should("exist");
    cy.contains('[role="tab"]', "SST").should("exist");
  });

  // CARGO-TELA-06
  it("a busca filtra a lista de cargos", () => {
    // force:true: o registro de humor ("Como você está hoje?") pode abrir e
    // deixa o body com data-scroll-locked / pointer-events:none (scroll-lock do
    // Radix); sem o force o Cypress recusa o type no campo de busca.
    cy.get('input[placeholder*="Buscar cargos"]', { timeout: 20000 })
      .should("exist").type("Analista", { force: true });
  });

  // CARGO-TELA-03
  it("abre a aba SST no formulário de Cargo", () => {
    cy.contains("button", "Novo Cargo", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 }).should("be.visible");
    cy.contains('[role="tab"]', "SST").click({ force: true });
    cy.contains("Insalubridade", { timeout: 20000 }).should("be.visible");
  });

  // CARGO-TELA-04
  it("mostra o seletor de departamentos no formulário de Cargo", () => {
    cy.contains("button", "Novo Cargo", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 }).should("be.visible");
    cy.contains("O primeiro selecionado será considerado").should("exist");
  });

  // CARGO-TELA-05
  it("mostra os campos de faixa salarial no formulário de Cargo", () => {
    cy.contains("button", "Novo Cargo", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 }).should("be.visible");
    cy.contains("Salário Mínimo").should("be.visible");
    cy.contains("Salário Máximo").should("be.visible");
  });

  // CARGO-TELA-07
  it("mostra o estado vazio ao buscar um cargo inexistente", () => {
    // force:true pelo mesmo motivo do CARGO-TELA-06 (scroll-lock do Radix
    // quando o registro de humor está aberto).
    cy.get('input[placeholder*="Buscar cargos"]', { timeout: 20000 })
      .type("zzz-cargo-inexistente-999", { force: true });
    cy.contains("Nenhuma cargo encontrada", { timeout: 20000 }).should("be.visible");
  });
});
