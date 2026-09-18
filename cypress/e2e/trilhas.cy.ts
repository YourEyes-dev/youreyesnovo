/// <reference types="cypress" />

// =====================================================================
// Módulo Trilhas (Aprendizagem) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (qa_casos_teste, nível e2e)
// ligado pela ponte qa_cobertura_e2e.
// Casos cobertos: TRILHA-001, TRILHA-002, TRILHA-040 (estrutura) +
//   TRILHA-010 (criar uma trilha na Gestão).
// Atribuir/gerar por IA/quiz seguem documentados e sem spec por ora.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Trilhas", () => {
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
    cy.visit(`${baseUrl}/trilhas`);
    cy.contains("h1", "Trilhas", { timeout: 20000 }).should("be.visible");
  }

  function abrirAba(label: string) {
    cy.contains('[role="tab"]', label).scrollIntoView().click({ force: true });
    cy.contains('[role="tab"]', label).should("have.attr", "aria-selected", "true");
  }

  beforeEach(() => {
    login();
    goToModulo();
  });

  it("carrega o módulo de Trilhas com as abas", () => {
    cy.contains('[role="tab"]', "Minhas Trilhas", { timeout: 20000 }).should("exist");
    cy.contains('[role="tab"]', "Gamificação").should("exist");
    cy.contains('[role="tab"]', "Analytics").should("exist");
  });

  it("mostra as trilhas atribuídas em Minhas Trilhas", () => {
    abrirAba("Minhas Trilhas");
    cy.contains("Algo deu errado").should("not.exist");
  });

  it("abre a aba de Gamificação", () => {
    abrirAba("Gamificação");
    cy.contains("Algo deu errado").should("not.exist");
  });

  it("cria uma trilha na Gestão", () => {
    // O botão "Nova Trilha" do cabeçalho está sempre presente (abre um diálogo).
    // force:true nos cliques: o scroll-lock do Radix deixa o body com
    // pointer-events:none e o Cypress recusa o clique sem o force.
    cy.contains("button", "Nova Trilha", { timeout: 20000 }).first().click({ force: true });
    cy.get('[role="dialog"]', { timeout: 15000 }).contains("Nova Trilha").should("exist");
    const nome = `Trilha automatizada ${Date.now()}`;
    // Só o Nome é obrigatório; os demais têm padrão. Endurecido: o campo do
    // diálogo (Radix ainda animando) precisa estar VISÍVEL e o valor precisa ter
    // sido COMITADO antes de submeter — sem isso o .type às vezes não registra e
    // a criação sai travada (o botão volta a ficar inerte).
    cy.get('[role="dialog"]')
      .find('input[placeholder="Ex: Gestão de Prioridades"]', { timeout: 15000 })
      .should("be.visible")
      .clear({ force: true })
      .type(nome, { force: true })
      .should("have.value", nome);
    cy.get('[role="dialog"]').contains("button", "Criar Trilha").should("not.be.disabled").click({ force: true });
    // Sucesso por sinal DURÁVEL, não pelo toast efêmero: o TrilhaForm fecha o
    // diálogo (onOpenChange(false)) só DEPOIS que criarTrilha resolve; no erro, o
    // catch mantém o diálogo ABERTO (foi o que a bateria #52 pegou: dialogs=1). O
    // toast "Trilha criada!" (sonner) some em ~4s e sozinho gerava flake quando a
    // asserção começava tarde. Aferimos o fechamento do diálogo como prova de
    // criação (no erro, o diálogo teria permanecido aberto com o formulário).
    cy.get('[role="dialog"]', { timeout: 20000 }).should("not.exist");
  });
});
