/// <reference types="cypress" />

// =====================================================================
// Módulo Usuários (/usuarios) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (USR-TELA-*), ligado pela
// ponte qa_cobertura_e2e. Escopo: o módulo monta, as métricas e os filtros
// aparecem, o modal de Novo Usuário abre e o vazio orienta. Todos
// DATA-INDEPENDENTES (valem na ilha vazia) — sem fixtures.
//
// Os casos de MOTOR do módulo (CTX/ISOL/USR/PER — permissão e isolamento)
// seguem no motor SQL; aqui é só a estrutura de tela.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Usuários", () => {
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
    cy.visit(`${baseUrl}/usuarios`);
    cy.contains("h1", "Usuários", { timeout: 20000 }).should("be.visible");
  }

  function fecharHumorSePresente() {
    cy.get("body", { timeout: 10000 }).then(($b) => {
      if ($b.text().includes("Como você está hoje")) {
        cy.get("body").type("{esc}", { force: true });
        cy.wait(300);
      }
    });
  }

  // Abre um filtro do Radix (Select de status/tipo, Popover de empresa) de forma
  // robusta. O flake da #54 vinha daqui: o clique com force pode ser interceptado
  // pelo overlay do "humor" (scroll-lock) e o portal do Radix ainda anima —
  // então a asserção da opção/input começava antes do conteúdo montar. Aqui
  // clicamos e, se o conteúdo esperado não montou, dispensamos o humor e
  // clicamos de novo; só então afirmamos que o conteúdo está visível.
  function abrirFiltro(rotuloTrigger: string, seletorConteudo: string) {
    const trigger = () =>
      cy.contains('[role="combobox"]', rotuloTrigger, { timeout: 20000 });
    trigger().should("be.visible").scrollIntoView().click({ force: true });
    cy.get("body").then(($b) => {
      if ($b.find(seletorConteudo).length === 0) {
        if ($b.text().includes("Como você está hoje")) {
          cy.get("body").type("{esc}", { force: true });
          cy.wait(200);
        }
        trigger().click({ force: true });
      }
    });
    cy.get(seletorConteudo, { timeout: 15000 }).should("be.visible");
  }

  beforeEach(() => {
    login();
    goToModulo();
    fecharHumorSePresente();
  });

  // USR-TELA-01
  it("carrega o módulo Usuários com o cabeçalho, as métricas e a ação", () => {
    cy.contains("button", "Novo Usuário", { timeout: 20000 }).should("be.visible");
    cy.contains("Com convite").should("exist");
    cy.contains("Multiempresa").should("exist");
    cy.contains("Alertas IA").should("exist");
  });

  // USR-TELA-02
  it("mostra os filtros de busca, empresa, status e tipo", () => {
    cy.get('input[placeholder*="Buscar por nome"]', { timeout: 20000 }).should("exist");
    cy.contains('[role="combobox"]', "Todas as empresas").should("exist");
    cy.contains('[role="combobox"]', "Todos os status").should("exist");
    cy.contains('[role="combobox"]', "Todos os tipos de usuário").should("exist");
  });

  // USR-TELA-03
  it("abre o modal de Novo Usuário", () => {
    cy.contains("button", "Novo Usuário", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 15000 }).contains("Dados Básicos").should("exist");
    cy.get("body").type("{esc}", { force: true });
    cy.get('[role="dialog"]').should("not.exist");
  });

  // USR-TELA-04
  it("o filtro de status abre com as opções", () => {
    abrirFiltro("Todos os status", '[role="listbox"]');
    cy.get('[role="listbox"]').contains('[role="option"]', "Todos os status").should("be.visible");
    cy.get("body").type("{esc}", { force: true });
  });

  // USR-TELA-05
  it("buscar um usuário inexistente mostra o vazio orientativo", () => {
    cy.get('input[placeholder*="Buscar por nome"]', { timeout: 20000 })
      .type("zzz-nao-existe-999", { force: true });
    cy.contains("Nenhum usuário encontrado", { timeout: 20000 }).should("be.visible");
  });

  // USR-TELA-06
  it("o filtro de tipo de usuário abre com as opções", () => {
    abrirFiltro("Todos os tipos de usuário", '[role="listbox"]');
    cy.get('[role="listbox"]').contains('[role="option"]', "Todos os tipos de usuário").should("be.visible");
    cy.get("body").type("{esc}", { force: true });
  });

  // USR-TELA-07
  it("o filtro por empresa abre", () => {
    // O seletor de conteúdo já é o próprio input de busca de empresa: abrirFiltro
    // clica (com re-tentativa) e afirma que o input ficou visível.
    abrirFiltro("Todas as empresas", 'input[placeholder*="Buscar empresa"]');
    cy.get("body").type("{esc}", { force: true });
  });
});
