/// <reference types="cypress" />

// =====================================================================
// Central de Suporte (/suporte) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (SUP-*), ligado pela ponte
// qa_cobertura_e2e. Escopo: entrada/validação — a central monta com stats e
// filtros, o modal de novo ticket trava sem título/descrição e oferece
// tipo/prioridade/módulo, e a lista vazia orienta a abrir um ticket. NADA
// aqui cria ticket (não submete o formulário), então não depende de dado
// semeado.
//
// SUP-050 força a lista vazia buscando um termo inexistente — funciona tendo
// ou não tickets na base, sem criar nada.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Central de Suporte (/suporte)", () => {
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

  function abrirNovoTicket() {
    cy.contains("button", "Novo Ticket").first().click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 }).should("be.visible").and("contain.text", "Novo Ticket");
  }

  beforeEach(() => {
    login();
    cy.visit(`${baseUrl}/suporte`);
    cy.contains("h1", "Central de Suporte", { timeout: 20000 }).should("be.visible");
  });

  // SUP-001
  it("abre a central com stats e filtros", () => {
    ["Total", "Abertos", "Em Andamento", "Resolvidos"].forEach((l) =>
      cy.contains(l).should("be.visible")
    );
    cy.get('input[placeholder="Buscar tickets..."]').should("exist");
    ["Todos", "Abertos", "Resolvidos"].forEach((t) =>
      cy.contains('[role="tab"]', t).should("exist")
    );
  });

  // SUP-011
  it("bloqueia o envio de ticket sem título ou descrição", () => {
    abrirNovoTicket();
    cy.get('[role="dialog"]').contains("button", "Enviar Ticket").should("be.disabled");
  });

  // SUP-012
  it("permite escolher tipo, prioridade e módulo no novo ticket", () => {
    abrirNovoTicket();
    cy.get('[role="dialog"]').within(() => {
      cy.contains("label", "Tipo").should("exist");
      cy.contains("label", "Prioridade").should("exist");
      cy.contains("label", "Módulo relacionado").should("exist");
    });
  });

  // SUP-050
  it("mostra a lista vazia orientando a abrir um ticket", () => {
    cy.get('input[placeholder="Buscar tickets..."]').type("zzz-nao-existe-nenhum-ticket-999");
    cy.contains("Nenhum ticket encontrado", { timeout: 20000 }).should("be.visible");
  });
});
