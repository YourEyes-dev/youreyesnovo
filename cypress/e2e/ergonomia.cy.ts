/// <reference types="cypress" />

// =====================================================================
// Gestão de Risco Ergonômico (/ergonomia) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (ERGO-*), ligado pela ponte
// qa_cobertura_e2e. Escopo: a entrada do módulo — o Guia Rápido abre e fecha
// e a trava de risco sem título segura o cadastro. NADA aqui cria risco,
// então não depende de dado semeado.
//
// ERGO-001 (as 7 abas do fluxo GRO) fica FORA deste lote de propósito: a
// página só renderiza as abas quando o módulo tem inventário NR-17 (senão
// mostra o EmptyState com botão de inicializar). Testar as abas exigiria
// inicializar o módulo (escrever a base NR-17 na ilha), o que sai do escopo
// "sem semear dado". Fica documentado e pendente até um teste com dado.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Gestão de Risco Ergonômico (/ergonomia)", () => {
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
    cy.visit(`${baseUrl}/ergonomia`);
    cy.contains("h1", "Gestão de Risco Ergonômico", { timeout: 20000 }).should("be.visible");
  });

  // ERGO-002
  it("abre e fecha o Guia Rápido sem afetar a tela", () => {
    cy.get("#btn-ergo-guia-rapido").click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 })
      .should("be.visible")
      .and("contain.text", "Guia Rápido — Ergonomia");
    cy.get("body").type("{esc}");
    cy.get('[role="dialog"]').should("not.exist");
    cy.contains("h1", "Gestão de Risco Ergonômico").should("be.visible");
  });

  // ERGO-011
  it("bloqueia o cadastro de risco sem título", () => {
    cy.get("#btn-ergo-novo-risco").click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 })
      .should("be.visible")
      .and("contain.text", "Cadastrar Risco Ergonômico");
    cy.contains("button", "Cadastrar Risco").should("be.disabled");
  });
});
