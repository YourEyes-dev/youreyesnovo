/// <reference types="cypress" />

// =====================================================================
// Módulo Mural Interno (Feed) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (qa_casos_teste, nível e2e)
// ligado pela ponte qa_cobertura_e2e.
// Casos cobertos: MURAL-001, MURAL-050, MURAL-060 (estrutura) +
//   MURAL-010 (publicar texto), MURAL-012 (bloquear vazio),
//   MURAL-021 (comentar), MURAL-030 (excluir o próprio post).
// Reagir/imagem/menção/widget seguem documentados e sem spec por ora.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Mural Interno", () => {
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
    cy.visit(`${baseUrl}/feed`);
    cy.contains("h1", "Mural Interno", { timeout: 20000 }).should("be.visible");
  }

  // O compositor só expande (e mostra o botão Publicar) ao focar a textarea.
  // force:true nos cliques: um overlay do Radix deixa o body com
  // pointer-events:none (scroll-lock) e o Cypress recusa o clique — o mesmo
  // tratamento que o resto da suíte já usa.
  function publicar(texto: string) {
    cy.get('textarea[placeholder="No que você está pensando?"]', { timeout: 20000 })
      .click({ force: true })
      .type(texto, { force: true });
    cy.contains("button", "Publicar").should("not.be.disabled").click({ force: true });
    cy.contains("Post publicado!", { timeout: 20000 }).should("exist");
  }

  beforeEach(() => {
    login();
    goToModulo();
  });

  it("carrega o Mural com o compositor e o feed", () => {
    cy.get('textarea[placeholder="No que você está pensando?"]', { timeout: 20000 }).should("exist");
  });

  it("trata o feed (posts ou estado vazio) sem erro", () => {
    cy.contains("Algo deu errado").should("not.exist");
    cy.get('textarea[placeholder="No que você está pensando?"]').should("exist");
  });

  it("atualiza o feed", () => {
    cy.contains("button", "Atualizar", { timeout: 20000 }).should("be.visible").click({ force: true });
    cy.contains("Algo deu errado").should("not.exist");
    cy.contains("h1", "Mural Interno").should("be.visible");
  });

  it("publica um post de texto", () => {
    const texto = `Post automatizado ${Date.now()}`;
    publicar(texto);
    cy.contains(texto, { timeout: 20000 }).should("exist");
  });

  it("mantém o Publicar desabilitado com o compositor vazio", () => {
    // Focar expande o compositor; sem texto e sem imagem, Publicar fica travado.
    cy.get('textarea[placeholder="No que você está pensando?"]', { timeout: 20000 }).click({ force: true });
    cy.contains("button", "Publicar").should("be.disabled");
  });

  it("comenta em um post", () => {
    publicar(`Post para comentar ${Date.now()}`);
    // O post recém-criado é o primeiro do feed; abre os comentários dele.
    cy.contains("button", "Comentar", { timeout: 20000 }).first().click({ force: true });
    const comentario = `Comentário automatizado ${Date.now()}`;
    cy.get('input[placeholder="Escreva um comentário... Use @ para mencionar"]', { timeout: 20000 })
      .first()
      .type(`${comentario}{enter}`, { force: true });
    cy.contains(comentario, { timeout: 20000 }).should("exist");
  });

  it("exclui o próprio post", () => {
    const texto = `Post para excluir ${Date.now()}`;
    publicar(texto);
    cy.contains(texto, { timeout: 20000 }).should("exist");
    // Menu "..." ESCOPADO ao card do post (evita pegar o menu do cabeçalho).
    cy.contains(texto)
      .closest('[class*="rounded-"]')
      .find('button[aria-haspopup="menu"]')
      .first()
      .click({ force: true });
    cy.contains('[role="menuitem"]', "Excluir").click({ force: true });
    cy.contains("Post excluído", { timeout: 20000 }).should("exist");
    cy.contains(texto).should("not.exist");
  });
});
