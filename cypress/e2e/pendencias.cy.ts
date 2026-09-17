/// <reference types="cypress" />

// =====================================================================
// Módulo Central de Pendências (/pendencias) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (PEND-TELA-*), ligado pela ponte
// qa_cobertura_e2e. Escopo: o módulo monta com o cabeçalho e os 3 cartões, a
// busca e os 4 filtros por perfil aparecem, a busca sem resultado orienta, e
// alternar o filtro por perfil ativa a aba. Todos DATA-INDEPENDENTES (valem com
// ou sem pendências na ilha; o vazio é forçado via busca) — sem fixtures.
//
// A Central de Pendências foi tirada do menu lateral (fica no dashboard); aqui
// navegamos direto pela rota /pendencias.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Central de Pendências", () => {
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
    cy.visit(`${baseUrl}/pendencias`);
    cy.contains("h1", "Central de Pendências", { timeout: 20000 }).should("be.visible");
  }

  function fecharHumorSePresente() {
    cy.get("body", { timeout: 10000 }).then(($b) => {
      if ($b.text().includes("Como você está hoje")) {
        cy.get("body").type("{esc}", { force: true });
        cy.wait(300);
      }
    });
  }

  beforeEach(() => {
    login();
    goToModulo();
    fecharHumorSePresente();
  });

  // PEND-TELA-01
  it("carrega a Central de Pendências com o cabeçalho e os cartões", () => {
    cy.contains("Urgentes", { timeout: 20000 }).should("be.visible");
    cy.contains("Em Atenção").should("exist");
    cy.contains("Total de Ações").should("exist");
  });

  // PEND-TELA-02
  it("mostra a busca e os filtros por perfil", () => {
    cy.get('input[placeholder*="Buscar pend"]', { timeout: 20000 }).should("exist");
    cy.contains("button", "Tudo").should("be.visible").and("have.class", "shadow-md");
    cy.contains("button", "Meu Perfil").should("exist");
    cy.contains("button", "Minha Equipe").should("exist");
    cy.contains("button", "Gestão / RH").should("exist");
  });

  // PEND-TELA-03
  it("buscar um termo inexistente mostra o vazio orientativo", () => {
    cy.get('input[placeholder*="Buscar pend"]', { timeout: 20000 })
      .clear({ force: true })
      .type("zzz-nao-existe-999", { force: true });
    cy.contains("Nenhuma pendência encontrada", { timeout: 20000 }).should("be.visible");
    cy.contains("Você está em dia").should("exist");
  });

  // PEND-TELA-04
  it("selecionar o filtro Gestão / RH ativa a aba", () => {
    cy.contains("button", "Gestão / RH", { timeout: 20000 }).click({ force: true });
    cy.contains("button", "Gestão / RH").should("have.class", "shadow-md");
    // A tela segue consistente: cabeçalho e busca permanecem.
    cy.contains("h1", "Central de Pendências").should("be.visible");
    cy.get('input[placeholder*="Buscar pend"]').should("exist");
  });
});
