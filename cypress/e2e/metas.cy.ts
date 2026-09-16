/// <reference types="cypress" />

// =====================================================================
// Módulo Metas — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (qa_casos_teste, nível e2e,
// prefixo METAS-TELA-*), ligado pela ponte qa_cobertura_e2e.
//
// Escopo: a ENTRADA de cada caso — a tela/aba monta e o ponto de partida
// (abas, formulário) aparece. Parte robusta e não destrutiva: navega e
// confere que a tela existe, sem salvar nada.
//
// Casos "profundos" (METAS-TELA-10/11/12) DEPENDEM das metas fictícias que
// o seed-e2e-user semeia na ilha de QA (função semearMetas). É o piloto do
// padrão "fixtures na ilha": com metas na base dá para conferir listagem,
// filtro por nível e consolidação. Por isso o vazio de METAS-TELA-09 passou
// a ser o vazio-por-busca (buscar texto inexistente), já que a lista natural
// não é mais vazia na ilha semeada.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Metas", () => {
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

  // Aba por id estável (definido em MetasModule.tsx: tab-metas-<area>).
  function abrirAba(id: string) {
    cy.get(`#${id}`, { timeout: 20000 }).click({ force: true });
    cy.get(`#${id}`).should("have.attr", "data-state", "active");
  }

  beforeEach(() => {
    login();
    cy.visit(`${baseUrl}/metas`);
    cy.contains("h1", "Metas", { timeout: 20000 }).should("be.visible");
  });

  // METAS-TELA-01
  it("abre o módulo Metas com o cabeçalho e as abas", () => {
    cy.get("#btn-nova-meta", { timeout: 20000 }).should("be.visible");
    cy.get("#tab-metas-dashboard").should("exist");
    cy.get("#tab-metas-lista").should("exist");
    cy.get("#tab-metas-consolidacao").should("exist");
    cy.get("#tab-metas-chat").should("exist");
  });

  // METAS-TELA-03
  it("abre o formulário de Nova Meta", () => {
    cy.get("#btn-nova-meta", { timeout: 20000 }).click({ force: true });
    cy.contains("Nova Meta", { timeout: 20000 }).should("be.visible");
    cy.get('[role="dialog"]').should("be.visible");
  });

  // METAS-TELA-04
  it("abre Minhas Metas com o filtro por nível", () => {
    abrirAba("tab-metas-lista");
    cy.contains("Filtrar por nível", { timeout: 20000 }).should("be.visible");
  });

  // METAS-TELA-05
  it("abre a aba Consolidação", () => {
    abrirAba("tab-metas-consolidacao");
  });

  // METAS-TELA-06
  it("abre a aba Assistente IA", () => {
    abrirAba("tab-metas-chat");
  });

  // METAS-TELA-02
  it("mostra os cards por nível na Visão Geral", () => {
    abrirAba("tab-metas-dashboard");
    ["Metas Estratégicas", "Metas por Unidade", "Metas por Setor", "Metas Individuais"].forEach((l) =>
      cy.contains(l, { timeout: 20000 }).should("be.visible")
    );
  });

  // METAS-TELA-07
  it("abre o guia rápido do módulo de Metas", () => {
    cy.contains("button", "Guia", { timeout: 20000 }).first().click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 })
      .should("be.visible")
      .and("contain.text", "Guia do Módulo de Metas");
  });

  // METAS-TELA-09 — com metas na ilha, o vazio natural não é mais alcançável;
  // conferimos o vazio-por-busca: buscar um texto inexistente esvazia a lista.
  it("mostra o estado vazio em Minhas Metas", () => {
    abrirAba("tab-metas-lista");
    cy.get('input[placeholder="Buscar metas..."]', { timeout: 20000 })
      .should("be.visible").type("zzz-inexistente-9999");
    cy.contains("Nenhuma meta", { timeout: 20000 }).should("be.visible");
  });

  // METAS-TELA-10 — depende das metas semeadas na ilha (semearMetas).
  it("lista as metas semeadas em Minhas Metas", () => {
    abrirAba("tab-metas-lista");
    cy.contains("Reduzir índice de acidentes em 20% (QA)", { timeout: 20000 })
      .should("be.visible");
    cy.contains("Registrar 100% dos EPIs entregues (QA)").should("be.visible");
  });

  // METAS-TELA-11 — filtro por nível recorta a lista (chip Estratégicas).
  it("filtra Minhas Metas pelo nível Estratégica", () => {
    abrirAba("tab-metas-lista");
    cy.contains("Reduzir índice de acidentes em 20% (QA)", { timeout: 20000 })
      .should("be.visible");
    cy.contains("button", "Estratégicas").click({ force: true });
    cy.contains("Reduzir índice de acidentes em 20% (QA)").should("be.visible");
    cy.contains("Registrar 100% dos EPIs entregues (QA)").should("not.exist");
  });

  // METAS-TELA-12 — consolidação resume as metas semeadas por nível.
  it("consolida as metas semeadas por nível", () => {
    abrirAba("tab-metas-consolidacao");
    cy.contains("Atingimento Geral Ponderado", { timeout: 20000 }).should("be.visible");
    cy.contains("Estratégica").should("be.visible");
  });
});
