/// <reference types="cypress" />

// =====================================================================
// Autenticação (/login) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (AUTH-*), ligado pela ponte
// qa_cobertura_e2e. Ao contrário dos outros specs, este NÃO loga no
// beforeEach — ele exercita a própria tela de login. Escopo: a tela monta,
// os campos vazios/ inválidos barram o envio, o olho mostra/oculta a senha,
// a senha errada dá erro genérico (anti-enumeração) e uma rota protegida sem
// login redireciona para o /login. NENHUM it() faz login válido, então não
// cria sessão nem depende de dado semeado.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Autenticação (/login)", () => {
  const { email } = credenciaisDeTeste();
  const baseUrl = Cypress.config("baseUrl") as string;

  beforeEach(() => {
    cy.clearCookies();
    cy.clearLocalStorage();
    cy.visit(`${baseUrl}/login`);
    cy.contains("h1", "Login", { timeout: 20000 }).should("be.visible");
  });

  // AUTH-001
  it("monta a tela de login com os campos e ações", () => {
    cy.get('input[type="email"]').should("exist");
    cy.get('input[autocomplete="current-password"]').should("exist");
    cy.contains("button", /^Entrar$/).should("exist");
    cy.contains("a", "Esqueceu a senha?").should("exist");
    // A porta livre de cadastro tem chave (SuperAdmin → YourEyes/Empresas):
    // aberta, a tela oferece "Cadastre sua empresa"; fechada — o padrão hoje —
    // ela manda para os planos. As duas são estados válidos da mesma tela, e o
    // que o caso AUTH-001 cobra é que o convite exista, não qual dos dois é.
    cy.contains(/Cadastre sua empresa|Conheça os planos e contrate/).should("exist");
  });

  // AUTH-004
  it("barra o envio com campos vazios ou inválidos", () => {
    cy.contains("button", /^Entrar$/).click();
    cy.contains("E-mail inválido", { timeout: 20000 }).should("be.visible");
    cy.contains("h1", "Login").should("be.visible"); // não navegou
  });

  // AUTH-005
  it("mostra e oculta a senha", () => {
    cy.get('input[autocomplete="current-password"]').should("have.attr", "type", "password").type("umasenha123");
    cy.get('input[autocomplete="current-password"]').parent().find('button[type="button"]').click({ force: true });
    cy.get('input[autocomplete="current-password"]').should("have.attr", "type", "text");
    cy.get('input[autocomplete="current-password"]').parent().find('button[type="button"]').click({ force: true });
    cy.get('input[autocomplete="current-password"]').should("have.attr", "type", "password");
  });

  // AUTH-003
  it("mostra erro genérico com senha errada", () => {
    cy.get('input[type="email"]').type(email);
    cy.get('input[autocomplete="current-password"]').type("senha-errada-de-proposito-123", { log: false });
    cy.contains("button", /^Entrar$/).click();
    cy.contains("Não foi possível entrar", { timeout: 20000 }).should("be.visible");
  });

  // AUTH-020
  it("redireciona rota protegida sem login para o login", () => {
    cy.visit(`${baseUrl}/colaboradores`);
    cy.contains("h1", "Login", { timeout: 20000 }).should("be.visible");
  });
});
