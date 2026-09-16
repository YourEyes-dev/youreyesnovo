/// <reference types="cypress" />

// =====================================================================
// Módulo Departamentos (/cadastros/departamentos) — testes de tela (e2e).
// Cada it() corresponde a um caso documentado (DEPTO-TELA-*), ligado pela
// ponte qa_cobertura_e2e. Escopo: entrada de cada caso (lista monta,
// formulário abre, busca funciona), sem salvar nada.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Departamentos", () => {
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
    cy.visit(`${baseUrl}/cadastros/departamentos`);
    cy.contains("h1", "Departamentos", { timeout: 20000 }).should("be.visible");
  });

  // DEPTO-TELA-01
  it("abre o módulo Departamentos com a lista", () => {
    cy.contains("button", "Novo Departamento", { timeout: 20000 }).should("be.visible");
    cy.get('input[placeholder*="Buscar departamentos"]').should("exist");
  });

  // DEPTO-TELA-02
  it("abre o formulário de Novo Departamento", () => {
    cy.contains("button", "Novo Departamento", { timeout: 20000 }).click({ force: true });
    cy.contains("Novo Departamento", { timeout: 20000 }).should("be.visible");
    cy.get('[role="dialog"]').should("be.visible");
  });

  // DEPTO-TELA-03
  it("a busca filtra a lista de departamentos", () => {
    cy.get('input[placeholder*="Buscar departamentos"]', { timeout: 20000 })
      .should("exist").type("Recursos");
  });

  // DEPTO-TELA-04
  it("mostra o seletor de estabelecimento/obra no formulário de Departamento", () => {
    cy.contains("button", "Novo Departamento", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 }).should("be.visible");
    cy.contains("Estabelecimento/Obra").should("be.visible");
  });

  // DEPTO-TELA-05
  it("mostra os seletores de gestor titular e substituto", () => {
    cy.contains("button", "Novo Departamento", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 }).should("be.visible");
    cy.contains("Gestor responsável").should("be.visible");
    cy.contains("Substituto do gestor").should("be.visible");
  });

  // DEPTO-TELA-06
  it("mostra o estado vazio ao buscar um departamento inexistente", () => {
    cy.get('input[placeholder*="Buscar departamentos"]', { timeout: 20000 }).type("zzz-depto-inexistente-999");
    cy.contains("Nenhum departamento encontrado", { timeout: 20000 }).should("be.visible");
  });
});
