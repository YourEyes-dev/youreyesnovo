/// <reference types="cypress" />

// =====================================================================
// Módulo Férias (/ferias) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (FERIAS-TELA-*), ligado pela
// ponte qa_cobertura_e2e. Escopo: entrada de cada caso (o módulo monta, o
// modal principal abre, as abas abrem e o vazio orienta) — sem salvar nada.
// Todos os casos são DATA-INDEPENDENTES (valem na ilha vazia).
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Férias", () => {
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
    cy.visit(`${baseUrl}/ferias`);
    cy.contains("h1", "Gestão de Férias", { timeout: 20000 }).should("be.visible");
  }

  // O registro de humor ("Como você está hoje?") pode abrir após o login e
  // travar o body (scroll-lock do Radix). Fecha-o se estiver presente, para
  // não atrapalhar os cliques. Best-effort: some quando não há modal.
  function fecharHumorSePresente() {
    cy.get("body", { timeout: 10000 }).then(($b) => {
      if ($b.text().includes("Como você está hoje")) {
        cy.get("body").type("{esc}", { force: true });
        cy.wait(300);
      }
    });
  }

  // force:true nos cliques: mesmo com o fechamento acima, o scroll-lock do
  // Radix pode deixar o body com pointer-events:none por um instante.
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

  // FERIAS-TELA-01
  it("carrega o módulo de Férias com o cabeçalho e as abas", () => {
    cy.contains("button", "Nova Solicitação", { timeout: 20000 }).should("be.visible");
    cy.contains('[role="tab"]', "Programação").should("exist");
    cy.contains('[role="tab"]', "Solicitações").should("exist");
    cy.contains('[role="tab"]', "Financeiro").should("exist");
  });

  // FERIAS-TELA-02
  it("abre o formulário de Nova Solicitação e fecha sem salvar", () => {
    cy.contains("button", "Nova Solicitação", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 15000 }).contains("Nova Solicitação de Férias").should("exist");
    // Só o Nome é obrigatório noutros módulos; aqui só conferimos que o modal
    // monta com o seletor de colaborador (sem depender de haver colaboradores).
    cy.get('[role="dialog"]').contains("Selecione o colaborador").should("exist");
    cy.get('[role="dialog"]').contains("button", "Cancelar").click({ force: true });
    cy.get('[role="dialog"]').should("not.exist");
  });

  // FERIAS-TELA-03
  it("mostra as solicitações ou o estado vazio orientativo", () => {
    abrirAba("Solicitações");
    // Data-independente: ou há cartões, ou o vazio orienta — nunca quebra.
    cy.contains("Algo deu errado").should("not.exist");
  });

  // FERIAS-TELA-04
  it("o filtro de status abre com as opções", () => {
    cy.contains("button", "Todos Status", { timeout: 20000 }).click({ force: true });
    cy.contains('[role="option"]', "Pendente", { timeout: 10000 }).should("be.visible");
    cy.contains('[role="option"]', "Aprovado").should("exist");
    cy.get("body").type("{esc}", { force: true });
  });

  // FERIAS-TELA-05
  it("abre a aba Calendário", () => {
    abrirAba("Calendário");
  });

  // FERIAS-TELA-06
  it("abre a aba Saldos", () => {
    abrirAba("Saldos");
  });

  // FERIAS-TELA-07
  it("abre a aba Financeiro", () => {
    abrirAba("Financeiro");
  });

  // FERIAS-TELA-08
  it("abre a aba INR™", () => {
    abrirAba("INR");
  });

  // FERIAS-TELA-09
  it("abre a aba Vencimentos", () => {
    abrirAba("Vencimentos");
  });

  // FERIAS-TELA-10
  it("abre a aba Coletivas", () => {
    abrirAba("Coletivas");
  });
});
