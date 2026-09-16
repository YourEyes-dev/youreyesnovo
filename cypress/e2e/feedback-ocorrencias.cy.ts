/// <reference types="cypress" />

// =====================================================================
// Módulo Feedback & Ocorrências — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (qa_casos_teste, nível e2e)
// ligado pela ponte qa_cobertura_e2e.
// Casos cobertos: FBK-001, FBK-011, FBK-020, FBK-040 (estrutura) +
//   FBK-010 (registrar feedback), FBK-013 (switch e-mail),
//   FBK-030 (registrar ocorrência), FBK-050 (stats do gestor).
// A conta-robô é owner/administrador (manager+), então o painel de stats
// aparece. Colaboradores semeados: "Colaborador 1".."Colaborador 20".
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Feedback & Ocorrências", () => {
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
    cy.visit(`${baseUrl}/feedback-ocorrencias`);
    cy.contains("h1", "Feedback & Ocorrências", { timeout: 20000 }).should("be.visible");
  }

  function abrirAba(label: string | RegExp) {
    cy.contains('[role="tab"]', label).scrollIntoView().click({ force: true });
    cy.contains('[role="tab"]', label).should("have.attr", "aria-selected", "true");
  }

  // O seletor de colaborador é um Popover (não um <select>): botão combobox →
  // busca → opção com o nome. force:true nos cliques porque um overlay do Radix
  // deixa o body com pointer-events:none (scroll-lock) e o Cypress recusa o
  // clique — mesmo tratamento do resto da suíte.
  function escolherColaborador(nome: string) {
    cy.contains("button", "Selecione o colaborador", { timeout: 20000 }).click({ force: true });
    cy.get('input[placeholder="Buscar por nome, cargo ou departamento..."]', { timeout: 20000 })
      .should("be.visible").clear().type(nome, { force: true });
    cy.contains("button", nome, { timeout: 20000 }).click({ force: true });
  }

  beforeEach(() => {
    login();
    goToModulo();
  });

  it("carrega o módulo com as quatro abas", () => {
    cy.contains('[role="tab"]', /Feedback$/, { timeout: 20000 }).should("exist");
    cy.contains('[role="tab"]', /^Feedbacks$/).should("exist");
    cy.contains('[role="tab"]', /Ocorrência$/).should("exist");
    cy.contains('[role="tab"]', /^Ocorrências$/).should("exist");
  });

  it("mantém o registro de feedback desabilitado sem os campos obrigatórios", () => {
    cy.contains("button", "Registrar Feedback", { timeout: 20000 }).should("be.disabled");
  });

  it("abre o histórico de Feedbacks", () => {
    abrirAba("Feedbacks");
    cy.contains("Histórico de Feedbacks").should("be.visible");
  });

  it("abre o histórico de Ocorrências", () => {
    abrirAba("Ocorrências");
    cy.contains("Histórico de Ocorrências").should("be.visible");
  });

  it("registra um feedback estruturado", () => {
    escolherColaborador("Colaborador 5");
    cy.contains("button", "Reconhecimento").click({ force: true });
    cy.get('textarea[placeholder="Descreva brevemente o fato ou situação observada..."]')
      .type("Feedback automatizado de teste.", { force: true });
    cy.contains("button", "Registrar Feedback").should("not.be.disabled").click({ force: true });
    cy.contains("Feedback registrado com sucesso!", { timeout: 20000 }).should("exist");
  });

  it("permite alternar o envio por e-mail ao colaborador", () => {
    cy.get('[role="switch"]', { timeout: 20000 }).first().as("switchEmail");
    cy.get("@switchEmail").click({ force: true });
    cy.get("@switchEmail").should("have.attr", "aria-checked", "true");
  });

  it("registra uma ocorrência", () => {
    abrirAba(/Ocorrência$/); // aba "Nova Ocorrência"
    escolherColaborador("Colaborador 6");
    cy.contains("button", "Positiva").click({ force: true });
    cy.get('textarea[placeholder="Descreva de forma objetiva o fato ocorrido..."]')
      .type("Ocorrência automatizada de teste.", { force: true });
    cy.contains("button", "Registrar Ocorrência").should("not.be.disabled").click({ force: true });
    cy.contains("Ocorrência registrada com sucesso!", { timeout: 20000 }).should("exist");
  });

  it("exibe as estatísticas para o gestor", () => {
    cy.contains("Advertências", { timeout: 20000 }).should("be.visible");
  });
});
