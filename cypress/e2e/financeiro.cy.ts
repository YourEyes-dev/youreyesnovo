/// <reference types="cypress" />

// =====================================================================
// Módulo Financeiro (/financeiro) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (FINAN-TELA-*), ligado pela
// ponte qa_cobertura_e2e. Escopo: o módulo monta, as abas abrem, os modais
// principais (Novo Período, Novo Tipo de Benefício) aparecem e os vazios
// orientam. Todos DATA-INDEPENDENTES (valem na ilha vazia) — sem fixtures.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Financeiro", () => {
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

  function goToModulo() {
    cy.visit(`${baseUrl}/financeiro`);
    cy.contains("h1", "Módulo Financeiro", { timeout: 20000 }).should("be.visible");
  }

  function fecharHumorSePresente() {
    cy.get("body", { timeout: 10000 }).then(($b) => {
      if ($b.text().includes("Como você está hoje")) {
        cy.get("body").type("{esc}", { force: true });
        cy.wait(300);
      }
    });
  }

  function abrirAba(label: string) {
    cy.contains('[role="tab"]', label).scrollIntoView().click({ force: true });
    cy.contains('[role="tab"]', label).should("have.attr", "aria-selected", "true");
    cy.contains("Algo deu errado").should("not.exist");
  }

  beforeEach(() => {
    login();
    goToModulo();
    fecharHumorSePresente();
  });

  // FINAN-TELA-01
  it("carrega o módulo Financeiro com o cabeçalho e as abas", () => {
    cy.contains('[role="tab"]', "Painel").should("exist");
    cy.contains('[role="tab"]', "Folha").should("exist");
    cy.contains('[role="tab"]', "Benefícios").should("exist");
    cy.contains('[role="tab"]', "eSocial").should("exist");
  });

  // FINAN-TELA-02
  it("o Painel mostra os KPIs e os cards", () => {
    cy.contains("Última Folha", { timeout: 20000 }).should("exist");
    cy.contains("Custos por Categoria").should("exist");
    cy.contains("Histórico de Folha").should("exist");
  });

  // FINAN-TELA-03
  it("abre a aba Folha com a ação de Novo Período", () => {
    abrirAba("Folha");
    cy.contains("button", "Novo Período", { timeout: 20000 }).should("be.visible");
  });

  // FINAN-TELA-04
  it("abre o modal de Novo Período de Folha", () => {
    abrirAba("Folha");
    cy.contains("button", "Novo Período", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 15000 }).contains("Novo Período de Folha").should("exist");
    cy.get('[role="dialog"]').contains("button", "Cancelar").click({ force: true });
    cy.get('[role="dialog"]').should("not.exist");
  });

  // FINAN-TELA-05
  it("abre a aba Benefícios com as ações", () => {
    abrirAba("Benefícios");
    cy.contains("button", "Novo Benefício", { timeout: 20000 }).should("be.visible");
    cy.contains("button", "Vincular Colaborador").should("exist");
  });

  // FINAN-TELA-06
  it("abre o modal de Novo Tipo de Benefício", () => {
    abrirAba("Benefícios");
    cy.contains("button", "Novo Benefício", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 15000 }).contains("Novo Tipo de Benefício").should("exist");
    cy.get('[role="dialog"]').contains("button", "Cancelar").click({ force: true });
    cy.get('[role="dialog"]').should("not.exist");
  });

  // FINAN-TELA-07
  it("abre a aba Rubricas", () => {
    abrirAba("Rubricas");
  });

  // FINAN-TELA-08
  it("abre a aba Provisões", () => {
    abrirAba("Provisões");
  });

  // FINAN-TELA-09
  it("abre a aba eSocial", () => {
    abrirAba("eSocial");
  });

  // FINAN-TELA-10
  it("abre a aba Tabelas", () => {
    abrirAba("Tabelas");
  });
});
