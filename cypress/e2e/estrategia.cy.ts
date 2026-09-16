/// <reference types="cypress" />

// =====================================================================
// Estratégia (/estrategia) — testes de tela (nível e2e).
//
// A página /estrategia hospeda TRÊS módulos, trocados pelo parâmetro ?tab=:
//   Planejamento Estratégico (PLEST-TELA-*) — /estrategia (SWOT + Oceano Azul)
//   Organograma (ORG-TELA-*)                — /estrategia?tab=organograma
//   Identidade / Cultura (IDENT-TELA-*)     — /estrategia?tab=cultura
//
// O SWOT em si já é coberto em profundidade por swot.cy.ts; aqui os it() de
// PLEST cobrem só a estrutura da página (sub-abas, Oceano Azul, guia), sem
// repetir aquilo. Cada it() é ligado ao caso documentado pela ponte.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Estratégia (/estrategia)", () => {
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
  });

  // ── Planejamento Estratégico ──
  // PLEST-TELA-01
  it("abre Planejamento Estratégico com SWOT e Oceano Azul", () => {
    cy.visit(`${baseUrl}/estrategia`);
    cy.contains("h1", "Planejamento Estratégico", { timeout: 20000 }).should("be.visible");
    cy.contains('[role="tab"]', "SWOT").should("exist");
    cy.contains('[role="tab"]', "Oceano Azul").should("exist");
    cy.contains("button", "Guia Rapido").should("exist");
  });

  // PLEST-TELA-03
  it("abre a sub-aba Oceano Azul", () => {
    cy.visit(`${baseUrl}/estrategia`);
    cy.contains("h1", "Planejamento Estratégico", { timeout: 20000 }).should("be.visible");
    abrirAba("Oceano Azul");
    cy.contains("Eliminar, Reduzir, Elevar e Criar", { timeout: 20000 }).should("be.visible");
  });

  // PLEST-TELA-06
  it("abre o Guia Rápido da estratégia", () => {
    cy.visit(`${baseUrl}/estrategia`);
    cy.contains("button", "Guia Rapido", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 }).should("be.visible");
  });

  // ── Organograma ──
  // ORG-TELA-01
  it("abre o Organograma", () => {
    cy.visit(`${baseUrl}/estrategia?tab=organograma`);
    cy.contains("h1", "Organograma", { timeout: 20000 }).should("be.visible");
  });

  // ORG-TELA-02
  it("abre o formulário de Nova Posição", () => {
    cy.visit(`${baseUrl}/estrategia?tab=organograma`);
    cy.contains("button", "Nova Posição", { timeout: 20000 }).click({ force: true });
    cy.contains("Nova Posição no Organograma", { timeout: 20000 }).should("be.visible");
  });

  // ── Identidade / Cultura ──
  // IDENT-TELA-01
  it("abre a Cultura com Missão, Visão e Valores", () => {
    cy.visit(`${baseUrl}/estrategia?tab=cultura`);
    cy.contains("h1", "Cultura", { timeout: 20000 }).should("be.visible");
    cy.contains("Missão").should("be.visible");
    cy.contains("Visão").should("be.visible");
  });

  // IDENT-TELA-04
  it("tem o gerador de manual com IA", () => {
    cy.visit(`${baseUrl}/estrategia?tab=cultura`);
    cy.contains("button", /Gerar Manual com IA|Regerar Manual/, { timeout: 20000 }).should("exist");
  });
});
