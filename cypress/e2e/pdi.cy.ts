/// <reference types="cypress" />

// =====================================================================
// PDI — Plano de Desenvolvimento Individual (/pdi) — testes de tela (e2e).
//
// Cada it() corresponde a um caso documentado (PDI-*), ligado pela ponte
// qa_cobertura_e2e. Escopo: entrada/validação — a tela monta com as abas, o
// FAQ abre/fecha, as estatísticas do topo aparecem, e o modal de novo PDI
// trava enquanto faltar colaborador ou datas. NADA aqui cria PDI (não
// submete o formulário), então não depende de dado semeado nem suja a base.
// (Selecionar um colaborador no modal usa os colaboradores da ilha de QA,
//  mas é só leitura do seletor — nenhum registro é criado.)
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("PDI — Plano de Desenvolvimento Individual (/pdi)", () => {
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

  function abrirModalNovoPdi() {
    cy.contains("button", "Criar novo PDI").click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 }).should("be.visible").and("contain.text", "Novo PDI");
  }

  beforeEach(() => {
    login();
    cy.visit(`${baseUrl}/pdi`);
    cy.contains("h1", "Plano de Desenvolvimento Individual", { timeout: 20000 }).should("be.visible");
  });

  // PDI-001
  it("abre com a lista e as abas Todos, Ativos e Concluídos", () => {
    ["Todos", "Ativos", "Concluídos"].forEach((t) =>
      cy.contains('[role="tab"]', t).should("exist")
    );
  });

  // PDI-003
  it("abre e fecha o FAQ em accordion", () => {
    cy.contains("Quando devo criar um PDI?").should("not.exist");
    cy.contains("Dúvidas frequentes sobre o PDI").click({ force: true });
    cy.contains("Quando devo criar um PDI?").should("be.visible");
    cy.contains("Dúvidas frequentes sobre o PDI").click({ force: true });
    cy.contains("Quando devo criar um PDI?").should("not.exist");
  });

  // PDI-011
  it("bloqueia a criação de PDI sem colaborador", () => {
    abrirModalNovoPdi();
    cy.get('[role="dialog"]').within(() => {
      cy.get('input[placeholder^="Ex: PDI"]').type("PDI de teste sem colaborador");
      cy.get('input[type="date"]').eq(1).type("2026-12-31");
      // com título e data fim, mas SEM colaborador, o botão continua bloqueado
      cy.contains("button", "Criar PDI").should("be.disabled");
    });
  });

  // PDI-012
  it("bloqueia a criação de PDI sem as datas", () => {
    abrirModalNovoPdi();
    // seleciona o primeiro colaborador (a ilha de QA tem colaboradores semeados)
    cy.get('[role="dialog"] button[role="combobox"]').first().click({ force: true });
    cy.get('[role="option"]', { timeout: 20000 }).first().click({ force: true });
    cy.get('[role="dialog"]').within(() => {
      cy.get('input[placeholder^="Ex: PDI"]').type("PDI de teste sem data fim");
      // com colaborador e título, mas SEM data fim, o botão continua bloqueado
      cy.contains("button", "Criar PDI").should("be.disabled");
    });
  });

  // PDI-031
  it("mostra as estatísticas do topo", () => {
    ["PDIs Ativos", "PDIs Concluídos", "Total de Metas", "Progresso Médio"].forEach((l) =>
      cy.contains(l).should("be.visible")
    );
  });
});
