/// <reference types="cypress" />

// =====================================================================
// Módulo Trilhas (Aprendizagem) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (qa_casos_teste, nível e2e)
// ligado pela ponte qa_cobertura_e2e.
// Casos cobertos: TRILHA-001, TRILHA-002, TRILHA-040 (estrutura) +
//   TRILHA-010 (criar uma trilha na Gestão).
// Atribuir/gerar por IA/quiz seguem documentados e sem spec por ora.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Trilhas", () => {
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
    cy.visit(`${baseUrl}/trilhas`);
    cy.contains("h1", "Trilhas", { timeout: 20000 }).should("be.visible");
  }

  function abrirAba(label: string) {
    cy.contains('[role="tab"]', label).scrollIntoView().click({ force: true });
    cy.contains('[role="tab"]', label).should("have.attr", "aria-selected", "true");
  }

  beforeEach(() => {
    login();
    goToModulo();
  });

  it("carrega o módulo de Trilhas com as abas", () => {
    cy.contains('[role="tab"]', "Minhas Trilhas", { timeout: 20000 }).should("exist");
    cy.contains('[role="tab"]', "Gamificação").should("exist");
    cy.contains('[role="tab"]', "Analytics").should("exist");
  });

  it("mostra as trilhas atribuídas em Minhas Trilhas", () => {
    abrirAba("Minhas Trilhas");
    cy.contains("Algo deu errado").should("not.exist");
  });

  it("abre a aba de Gamificação", () => {
    abrirAba("Gamificação");
    cy.contains("Algo deu errado").should("not.exist");
  });

  it("cria uma trilha na Gestão", () => {
    // O botão "Nova Trilha" do cabeçalho está sempre presente (abre um diálogo).
    // force:true nos cliques: o scroll-lock do Radix deixa o body com
    // pointer-events:none e o Cypress recusa o clique sem o force.
    cy.contains("button", "Nova Trilha", { timeout: 20000 }).first().click({ force: true });
    cy.get('[role="dialog"]', { timeout: 15000 }).contains("Nova Trilha").should("exist");
    const nome = `Trilha automatizada ${Date.now()}`;
    // Só o Nome é obrigatório; os demais campos têm padrão.
    cy.get('[role="dialog"]').find('input[placeholder="Ex: Gestão de Prioridades"]').type(nome, { force: true });
    cy.get('[role="dialog"]').contains("button", "Criar Trilha").should("not.be.disabled").click({ force: true });
    cy.contains("Trilha criada!", { timeout: 20000 }).should("exist");
  });
});
