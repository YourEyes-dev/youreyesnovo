/// <reference types="cypress" />

// =====================================================================
// Módulo Configurações — testes de tela (nível e2e).
//
// Toda a tela é restrita a admin. A conta-robô do ambiente de teste é
// owner/administrador, então as abas administrativas renderizam.
// Cada it() corresponde a um caso documentado (qa_casos_teste, nível e2e)
// ligado pela ponte qa_cobertura_e2e.
// Casos cobertos: CFG-001, CFG-010, CFG-011, CFG-020, CFG-030, CFG-040
//   (estrutura) + CFG-051 (sem banner de pendência), CFG-060 (troca de
//   abas estável), CFG-070 (criar usuário exige campos essenciais).
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Configurações", () => {
  const { email, senha: password } = credenciaisDeTeste();
  const baseUrl = Cypress.config("baseUrl") as string;

  function login() {
    cy.visit(`${baseUrl}/login`);
    cy.get('input[type="email"]', { timeout: 20000 })
      .should("exist")
      .scrollIntoView()
      .should("be.visible")
      .clear()
      .type(email);
    cy.get('input[autocomplete="current-password"]', { timeout: 20000 })
      .should("exist")
      .scrollIntoView()
      .should("be.visible")
      .clear()
      .type(password, { log: false });
    cy.contains("button", /^Entrar$/).click();
    cy.aguardarSessaoSupabase();
    cy.wait(1500);
  }

  function goToModulo() {
    cy.visit(`${baseUrl}/configuracoes`);
    cy.contains("h1", "Configurações", { timeout: 20000 }).should("be.visible");
  }

  function abrirAba(label: string | RegExp) {
    cy.contains('[role="tab"]', label).scrollIntoView().click({ force: true });
    cy.contains('[role="tab"]', label).should("have.attr", "aria-selected", "true");
  }

  beforeEach(() => {
    login();
    goToModulo();
  });

  it("carrega Configurações com as abas administrativas", () => {
    cy.contains('[role="tab"]', "Usuários", { timeout: 20000 }).should("exist");
    cy.contains('[role="tab"]', "Perfis").should("exist");
    cy.contains('[role="tab"]', "eSocial").should("exist");
    cy.contains('[role="tab"]', "Auditoria").should("exist");
    cy.contains('[role="tab"]', "Logo").should("exist");
  });

  it("abre a aba de Usuários", () => {
    abrirAba("Usuários");
    cy.contains("Algo deu errado").should("not.exist");
  });

  it("abre a aba de Perfis & Acessos", () => {
    abrirAba("Perfis");
    cy.contains("Algo deu errado").should("not.exist");
  });

  it("abre a aba de eSocial", () => {
    abrirAba("eSocial");
    cy.contains("Algo deu errado").should("not.exist");
  });

  it("abre a aba de Auditoria", () => {
    abrirAba("Auditoria");
    cy.contains("Algo deu errado").should("not.exist");
  });

  it("abre a aba de Logo", () => {
    abrirAba("Logo");
    cy.contains("Algo deu errado").should("not.exist");
  });

  it("não mostra o aviso de configuração pendente quando já configurado", () => {
    // O tenant da conta-robô já tem cadastro de empresa, então o banner de
    // onboarding não aparece.
    cy.contains("Configuração inicial pendente").should("not.exist");
  });

  it("percorre as abas administrativas sem erro", () => {
    ["Usuários", "Perfis", "eSocial", "Auditoria", "Logo"].forEach((aba) => {
      cy.contains('[role="tab"]', aba).scrollIntoView().click({ force: true });
      cy.contains("Algo deu errado").should("not.exist");
    });
  });

  it("exige os campos essenciais ao criar um usuário", () => {
    abrirAba("Usuários");
    cy.contains("button", "Novo Usuário", { timeout: 20000 }).click();
    cy.get('[role="dialog"]', { timeout: 15000 }).contains("Dados Básicos").should("exist");
    // Sem nome e e-mail, "Próximo" não avança para a etapa de vínculo.
    cy.get('[role="dialog"]').contains("button", "Próximo").click({ force: true });
    cy.get('[role="dialog"]').contains("Vínculo & Revisão").should("not.exist");
    cy.get('[role="dialog"]').contains("Dados Básicos").should("exist");
  });
});
