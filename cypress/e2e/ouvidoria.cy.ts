/// <reference types="cypress" />

// =====================================================================
// Ouvidoria (/ouvidoria) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (OUV-*), ligado pela ponte
// qa_cobertura_e2e. Escopo: a aba Enviar (a porta de entrada do módulo) —
// o formulário monta, os cinco tipos aparecem, as travas de campo
// obrigatório seguram o envio e o modo anônimo avisa. NADA aqui envia
// manifestação, então não depende de dado semeado nem suja a base.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Ouvidoria (/ouvidoria)", () => {
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
    cy.visit(`${baseUrl}/ouvidoria`);
    cy.contains("h1", "Ouvidoria", { timeout: 20000 }).should("be.visible");
  });

  // OUV-001
  it("abre na aba Enviar com o formulário pronto", () => {
    cy.contains('[role="tab"]', "Nova Manifestação").should("have.attr", "data-state", "active");
    cy.contains("Tipo de Manifestação").should("be.visible");
    cy.contains("label", "Assunto").should("be.visible");
    cy.contains("label", "Mensagem").should("be.visible");
    cy.get('[role="switch"]').should("exist");
  });

  // OUV-003
  it("mostra os cinco tipos de manifestação", () => {
    ["Sugestão", "Reclamação", "Denúncia", "Elogio", "Dúvida"].forEach((t) =>
      cy.contains("button", t).should("be.visible")
    );
  });

  // OUV-004
  it("bloqueia o envio sem assunto", () => {
    cy.contains("button", "Sugestão").click({ force: true });
    cy.get("#mensagem").type("Mensagem de teste de uma manifestação sem assunto preenchido.");
    cy.contains("button", "Enviar Manifestação").should("be.disabled");
  });

  // OUV-005
  it("bloqueia o envio sem mensagem", () => {
    cy.contains("button", "Reclamação").click({ force: true });
    cy.get("#assunto").type("Assunto de teste sem mensagem");
    cy.contains("button", "Enviar Manifestação").should("be.disabled");
  });

  // OUV-011
  it("avisa ao ativar o modo anônimo e retira o aviso ao desligar", () => {
    cy.contains("Manifestação Anônima").should("not.exist");
    cy.get('[role="switch"]').click({ force: true });
    cy.contains("Manifestação Anônima").should("be.visible");
    cy.get('[role="switch"]').click({ force: true });
    cy.contains("Manifestação Anônima").should("not.exist");
  });
});
