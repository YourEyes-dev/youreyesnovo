/// <reference types="cypress" />

// =====================================================================
// Módulo Afastamentos (Central GAF, /atestados) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (AFAST-TELA-*), ligado pela
// ponte qa_cobertura_e2e. Escopo: a entrada de cada caso (a central monta,
// as abas abrem, o formulário aparece), sem depender de dado semeado.
//
// De propósito, este spec não toca as abas Absenteísmo e Saúde Mental: elas
// só aparecem para quem tem permissão de dashboards gerais, então não são
// entrada robusta para todo perfil. Ficam na homologação manual.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Afastamentos (Central GAF)", () => {
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
    cy.visit(`${baseUrl}/atestados`);
    cy.contains("h1", "MOD-GAF", { timeout: 20000 }).should("be.visible");
  });

  // AFAST-TELA-01
  it("abre a Central GAF com as abas", () => {
    cy.contains('[role="tab"]', "Atestados").should("exist");
    cy.contains('[role="tab"]', "Afastamentos").should("exist");
    cy.contains('[role="tab"]', "FAP/RAT").should("exist");
    cy.contains('[role="tab"]', "Pendências").should("exist");
  });

  // AFAST-TELA-02
  it("abre a aba Afastamentos", () => {
    abrirAba("Afastamentos");
  });

  // AFAST-TELA-03
  it("abre o formulário de Novo Afastamento", () => {
    abrirAba("Afastamentos");
    cy.contains("button", "Novo Afastamento", { timeout: 20000 }).should("be.visible").click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 }).should("be.visible");
  });

  // AFAST-TELA-04
  it("abre a aba Atestados com a ação de Novo Atestado", () => {
    abrirAba("Atestados");
    cy.contains("button", "Novo Atestado", { timeout: 20000 }).should("be.visible");
  });

  // AFAST-TELA-08
  it("abre a aba Pendências", () => {
    abrirAba("Pendências");
  });

  // AFAST-TELA-09
  it("tem a busca por trabalhador ou CID", () => {
    cy.get('input[placeholder*="Buscar trabalhador"]', { timeout: 20000 }).should("exist");
  });

  // AFAST-TELA-07
  it("abre a aba FAP/RAT com o cartão de CAT Pendente", () => {
    abrirAba("FAP/RAT");
    cy.contains("CAT Pendente", { timeout: 20000 }).should("be.visible");
  });
});
