/// <reference types="cypress" />

// =====================================================================
// Onboarding Gamificado (/onboarding-rh) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (ONB-*), ligado pela ponte
// qa_cobertura_e2e. Escopo: entrada/validação — a tela monta com as três
// abas, o modal de novo template trava sem nome, e a aba de Indicadores
// consolida os números. NADA aqui cria template nem processo, então não
// depende de dado semeado.
//
// Os casos que exigem dado (ONB-013 ativar/inativar, ONB-021 etapa sem
// título, ONB-040 andamento dos processos, ONB-051 estados vazios) ficam
// documentados e pendentes até um teste com dado.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Onboarding Gamificado (/onboarding-rh)", () => {
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
    cy.visit(`${baseUrl}/onboarding-rh`);
    cy.contains("h1", "Onboarding Gamificado", { timeout: 20000 }).should("be.visible");
  });

  // ONB-001
  it("abre com as três abas Processos, Indicadores e Templates", () => {
    ["Processos", "Indicadores", "Templates"].forEach((t) =>
      cy.contains('[role="tab"]', t).should("exist")
    );
  });

  // ONB-011
  it("bloqueia a criação de template sem nome", () => {
    abrirAba("Templates");
    // O botão muda conforme haja templates: "Novo Template" (com lista) ou
    // "Criar Primeiro Template" (estado vazio) — os dois abrem o mesmo modal.
    cy.contains("button", /Novo Template|Criar Primeiro Template/, { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 })
      .should("be.visible")
      .and("contain.text", "Novo Template de Onboarding");
    // Sem nome, o botão de criar continua bloqueado.
    cy.get('[role="dialog"]').contains("button", "Criar Template").should("be.disabled");
  });

  // ONB-050
  it("mostra os indicadores consolidados", () => {
    abrirAba("Indicadores");
    cy.contains("Total Processos", { timeout: 20000 }).should("be.visible");
    cy.contains("Taxa Conclusão").should("be.visible");
    cy.contains("Progresso Geral").should("be.visible");
  });
});
