/// <reference types="cypress" />

// =====================================================================
// Cultura & Celebrações (/cultura-celebracoes) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (CULT-*), ligado pela ponte
// qa_cobertura_e2e. Escopo: entrada/validação — a tela monta com os KPIs e as
// abas, os indicadores culturais consolidam os números, e o modal de nova ação
// não cria nada sem título/data. NADA aqui cria ação, ritual ou preferência,
// então não depende de dado semeado.
//
// Obs.: o <h1> da página é "PESSOAS" (o módulo Cultura & Celebrações vive sob
// essa área) — é o que o beforeEach confere.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Cultura & Celebrações (/cultura-celebracoes)", () => {
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
    cy.visit(`${baseUrl}/cultura-celebracoes`);
    cy.contains("h1", "PESSOAS", { timeout: 20000 }).should("be.visible");
  });

  // CULT-001
  it("abre com as abas e os KPIs", () => {
    ["Datas Ativas", "Ações Pendentes", "Ações Concluídas", "Rituais Ativos"].forEach((l) =>
      cy.contains(l).should("be.visible")
    );
    ["Experiência do Colaborador", "Preferências", "Rituais e Reconhecimento"].forEach((t) =>
      cy.contains('[role="tab"]', t).should("exist")
    );
  });

  // CULT-011
  it("não cria ação sem título ou data", () => {
    cy.contains("button", "Nova Ação").click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 })
      .should("be.visible")
      .and("contain.text", "Nova Ação Cultural");
    // Clicar em "Criar Ação" com os campos obrigatórios vazios não cria nada:
    // o modal continua aberto (o handler ignora o envio sem título/data).
    cy.get('[role="dialog"]').contains("button", "Criar Ação").click({ force: true });
    cy.get('[role="dialog"]').should("be.visible").and("contain.text", "Nova Ação Cultural");
  });

  // CULT-060
  it("mostra os indicadores culturais", () => {
    cy.contains("Indicadores Culturais").should("be.visible");
    cy.contains("Taxa de Realização").should("be.visible");
  });
});
