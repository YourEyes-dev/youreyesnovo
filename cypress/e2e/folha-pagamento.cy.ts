/// <reference types="cypress" />

// =====================================================================
// Folha de Pagamento (abas do módulo /financeiro) — testes de tela (e2e).
//
// Cada it() corresponde a um caso documentado (FOLHA-*), ligado pela ponte
// qa_cobertura_e2e. Escopo data-independente (vale na ilha vazia, sem
// fixture): as abas Tabelas e CCT EXPÕEM as bases legais que a folha usa —
// a tabela progressiva do INSS (com teto), a do IRRF (com dedução por
// dependente) e o adicional noturno das convenções. O valor calculado de
// cada regra é verificado pelo Motor (casos de nível api).
//
// Fora deste lote (precisam de uma folha calculada / condições cadastradas,
// portanto de fixture): FOLHA-021 (insalubridade/periculosidade),
// FOLHA-022 (DSR) e FOLHA-041 (holerite discriminado por colaborador).
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Folha de Pagamento", () => {
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

  function fecharHumorSePresente() {
    cy.get("body", { timeout: 10000 }).then(($b) => {
      if ($b.text().includes("Como você está hoje")) {
        cy.get("body").type("{esc}", { force: true });
        cy.wait(300);
      }
    });
  }

  function abrirAbaPorId(id: string) {
    cy.get(`#${id}`, { timeout: 20000 }).scrollIntoView().click({ force: true });
    cy.contains("Algo deu errado").should("not.exist");
  }

  beforeEach(() => {
    login();
    cy.visit(`${baseUrl}/financeiro`);
    cy.contains("h1", "Módulo Financeiro", { timeout: 20000 }).should("be.visible");
    fecharHumorSePresente();
  });

  // FOLHA-010
  it("aba Tabelas mostra a tabela de INSS por faixas com teto", () => {
    abrirAbaPorId("tab-folha-tabelas");
    cy.contains("Tabela INSS", { timeout: 20000 }).should("exist");
    cy.contains("Teto:").should("exist");
    cy.contains("th", "Faixa").should("exist");
    cy.contains("th", "Alíquota").should("exist");
  });

  // FOLHA-011
  it("aba Tabelas mostra a tabela de IRRF com dedução por dependente", () => {
    abrirAbaPorId("tab-folha-tabelas");
    cy.contains("Tabela IRRF", { timeout: 20000 }).should("exist");
    cy.contains("Dedução/dep").should("exist");
  });

  // FOLHA-020
  it("aba CCT expõe o adicional noturno das convenções coletivas", () => {
    abrirAbaPorId("tab-folha-cct");
    cy.contains("Convenções Coletivas", { timeout: 20000 }).should("exist");
    cy.contains("th", "Noturno").should("exist");
  });
});
