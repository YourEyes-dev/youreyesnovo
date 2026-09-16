/// <reference types="cypress" />

// =====================================================================
// Módulo Colaboradores (/colaboradores) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (COLAB-TELA-*), ligado pela
// ponte qa_cobertura_e2e. Escopo: o módulo monta, as abas abrem, os modais
// principais (Novo Cadastro, Importar) aparecem, a busca/filtros existem e o
// vazio orienta. Todos DATA-INDEPENDENTES (valem na ilha vazia) — sem fixtures.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Colaboradores", () => {
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
    cy.visit(`${baseUrl}/colaboradores`);
    cy.contains("h1", "Colaboradores", { timeout: 20000 }).should("be.visible");
  }

  // O registro de humor ("Como você está hoje?") pode abrir após o login e
  // travar o body (scroll-lock do Radix). Fecha-o se estiver presente.
  function fecharHumorSePresente() {
    cy.get("body", { timeout: 10000 }).then(($b) => {
      if ($b.text().includes("Como você está hoje")) {
        cy.get("body").type("{esc}", { force: true });
        cy.wait(300);
      }
    });
  }

  function abrirAba(label: string) {
    cy.contains('[role="tab"]', label).scrollIntoView().click({ force: true });
    cy.contains('[role="tab"]', label).should("have.attr", "aria-selected", "true");
    cy.contains("Algo deu errado").should("not.exist");
  }

  beforeEach(() => {
    login();
    goToModulo();
    fecharHumorSePresente();
  });

  // COLAB-TELA-01
  it("carrega o módulo de Colaboradores com o cabeçalho, as abas e as ações", () => {
    cy.contains('[role="tab"]', "Ativos").should("exist");
    cy.contains('[role="tab"]', "Admissões").should("exist");
    cy.contains('[role="tab"]', "Desligados").should("exist");
    cy.contains("button", "Novo Cadastro").should("be.visible");
    cy.contains("button", "Importar Colaboradores").should("be.visible");
  });

  // COLAB-TELA-02
  it("a aba Ativos traz a busca e os filtros", () => {
    cy.get('input[placeholder*="Buscar por nome"]', { timeout: 20000 }).should("exist");
    cy.contains('[role="combobox"]', "Todos Departamentos").should("exist");
    cy.contains('[role="combobox"]', "Todos os estabelecimentos").should("exist");
  });

  // COLAB-TELA-03
  it("alterna entre a visualização em cards e em lista", () => {
    cy.get('[aria-label="Visualização em lista"]', { timeout: 20000 }).click({ force: true });
    cy.get('[aria-label="Visualização em lista"]').should("have.attr", "data-state", "on");
    cy.get('[aria-label="Visualização em cards"]').click({ force: true });
    cy.get('[aria-label="Visualização em cards"]').should("have.attr", "data-state", "on");
  });

  // COLAB-TELA-04
  it("abre a escolha de Novo Cadastro (colaborador ou terceiro)", () => {
    cy.contains("button", "Novo Cadastro", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 15000 }).contains("O que deseja cadastrar").should("exist");
    cy.get('[role="dialog"]').contains("Empresa Terceira").should("exist");
    cy.get("body").type("{esc}", { force: true });
  });

  // COLAB-TELA-05
  it("abre o modal de Importar Colaboradores", () => {
    cy.contains("button", "Importar Colaboradores", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 15000 }).contains("Importe uma planilha").should("exist");
    cy.get("body").type("{esc}", { force: true });
  });

  // COLAB-TELA-06
  it("o filtro de Departamento abre com as opções", () => {
    cy.contains('[role="combobox"]', "Todos Departamentos", { timeout: 20000 }).click({ force: true });
    cy.contains('[role="option"]', "Todos Departamentos", { timeout: 10000 }).should("be.visible");
    cy.get("body").type("{esc}", { force: true });
  });

  // COLAB-TELA-07
  it("abre a aba Admissões", () => {
    abrirAba("Admissões");
  });

  // COLAB-TELA-08
  it("abre a aba Desligados", () => {
    abrirAba("Desligados");
  });

  // COLAB-TELA-09
  it("mostra o contador de colaboradores", () => {
    cy.contains(/Mostrando .* de .* colaboradores/, { timeout: 20000 }).should("exist");
  });
});
