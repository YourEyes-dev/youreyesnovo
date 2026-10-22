/// <reference types="cypress" />

// =====================================================================
// Permissões — Onda 1 do plano de cobertura (docs/PLANO_COBERTURA_CYPRESS.md), lote 2.
//
// Todos os specs anteriores logam como o robô-owner, que enxerga tudo; por isso
// "o que um perfil restrito NÃO alcança" nunca tinha sido provado em tela. Aqui o
// login é de um colaborador comum cujo perfil libera SÓ Documentos (escopo próprio),
// semeado pela função seed-e2e-user. Controle positivo + negativos:
//   · o que o perfil libera abre (senão o teste "barrado" poderia passar por login quebrado);
//   · o que ele não libera mostra "Acesso Restrito";
//   · a tela de Usuários não entrega nenhuma aba administrativa.
//
// Cada it() é ligado a um caso documentado pela ponte qa_cobertura_e2e.
// (A segunda metade de PER-003 — o backend recusar mesmo sem o botão — fica para
// um teste de API; aqui só a metade de tela.)
// =====================================================================

import { credenciaisRestrito } from "../support/credenciais";

describe("Permissões — perfil restrito (só Documentos, escopo próprio)", () => {
  const { email, senha } = credenciaisRestrito();
  const baseUrl = Cypress.config("baseUrl") as string;

  function entrarComoRestrito() {
    cy.visit(`${baseUrl}/login`);
    cy.get('input[type="email"]', { timeout: 20000 })
      .should("exist").scrollIntoView().should("be.visible").clear().type(email);
    cy.get('input[autocomplete="current-password"]', { timeout: 20000 })
      .should("exist").scrollIntoView().should("be.visible").clear().type(senha, { log: false });
    cy.contains("button", /^Entrar$/).click();
    cy.aguardarSessaoSupabase();
    cy.location("pathname", { timeout: 20000 }).should("not.match", /\/login/);
  }

  const barrado = () => {
    cy.contains("h1", "Acesso Restrito", { timeout: 30000 }).should("be.visible");
    cy.contains("Seu perfil de acesso não inclui este módulo").should("be.visible");
    cy.contains("a", "Voltar ao início").should("be.visible");
  };

  beforeEach(() => {
    cy.clearCookies();
    cy.clearLocalStorage();
    entrarComoRestrito();
  });

  // PER-050
  it("perfil restrito entra e abre o módulo que o perfil libera", () => {
    cy.visit(`${baseUrl}/documentos`);
    cy.contains("h1", "Documentos", { timeout: 30000 }).should("be.visible");
    cy.contains("Seu perfil de acesso não inclui este módulo").should("not.exist");
  });

  // PER-051
  it("perfil restrito é barrado em Colaboradores", () => {
    cy.visit(`${baseUrl}/colaboradores`);
    barrado();
    // A lista de colaboradores não monta por trás do aviso.
    cy.contains("button", "Novo Colaborador").should("not.exist");
  });

  // PER-052
  it("perfil restrito é barrado em Financeiro, Ponto e Empresa", () => {
    cy.visit(`${baseUrl}/financeiro`);
    barrado();
    cy.visit(`${baseUrl}/ponto`);
    barrado();
    cy.visit(`${baseUrl}/empresa`);
    barrado();
  });

  // CFG-002
  it("usuário comum abre Usuários sem nenhuma aba administrativa", () => {
    cy.visit(`${baseUrl}/usuarios`);
    cy.contains("h1", "Usuários", { timeout: 30000 }).should("be.visible");
    cy.contains('[role="tab"]', "Perfis & Acessos").should("not.exist");
    cy.contains('[role="tab"]', "eSocial").should("not.exist");
    cy.contains('[role="tab"]', "Auditoria").should("not.exist");
    cy.contains("button", "Novo Usuário").should("not.exist");
  });
});
