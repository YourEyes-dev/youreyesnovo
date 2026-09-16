/// <reference types="cypress" />

// =====================================================================
// Módulo Meu Bem-Estar — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (qa_casos_teste, nível e2e)
// ligado pela ponte qa_cobertura_e2e.
// Casos cobertos: BEM-001, BEM-002, BEM-011 (estrutura) +
//   BEM-020 (registrar reflexão), BEM-021 (registrar gratidão).
// Dados de bem-estar são pessoais do próprio usuário — as escritas aqui
// gravam só no ambiente de teste, sob a conta-robô.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Meu Bem-Estar", () => {
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
    cy.visit(`${baseUrl}/felicidade`);
    cy.contains("h1", "Meu Bem-Estar no Trabalho", { timeout: 20000 }).should("be.visible");
  }

  // A legenda abaixo do radar tem um botão por eixo, rotulado pela 1ª parte do
  // nome do eixo (ex.: "Sentido" de "Sentido & Propósito").
  function abrirEixo(rotuloLegenda: string) {
    cy.contains("button", rotuloLegenda, { timeout: 20000 }).scrollIntoView().click({ force: true });
  }

  beforeEach(() => {
    login();
    goToModulo();
  });

  it("carrega o Mapa de Bem-Estar", () => {
    cy.contains("Meu Mapa de Bem-Estar", { timeout: 20000 }).should("be.visible");
  });

  it("exibe o aviso de espaço seguro", () => {
    cy.contains("Espaço seguro", { timeout: 20000 }).should("be.visible");
  });

  it("abre o painel ao clicar num eixo", () => {
    abrirEixo("Autoconhecimento");
    cy.contains("Autoconhecimento & Emoções").should("be.visible");
  });

  it("registra uma reflexão num eixo", () => {
    abrirEixo("Sentido");
    cy.contains("Sentido & Propósito", { timeout: 20000 }).should("be.visible");
    // O slider já vem no valor padrão (3), então dá para registrar direto.
    cy.contains("button", "Registrar percepção", { timeout: 20000 }).click({ force: true });
    // Sinal de sucesso estável: o agradecimento troca a área de interação.
    cy.contains("Obrigado pela reflexão. Ela é só sua.", { timeout: 20000 }).should("exist");
  });

  it("registra uma gratidão no eixo de gratidão", () => {
    abrirEixo("Gratidão");
    cy.contains("Gratidão & Cultura Positiva", { timeout: 20000 }).should("be.visible");
    cy.get('textarea[placeholder="Pode ser um texto curto, um emoji 😊, ou nada..."]', { timeout: 20000 })
      .type("Gratidão automatizada de teste");
    cy.contains("button", "Registrar percepção").click({ force: true });
    cy.contains("Obrigado pela reflexão. Ela é só sua.", { timeout: 20000 }).should("exist");
  });
});
