/// <reference types="cypress" />

// =====================================================================
// Módulo Aprendizado & Papéis (/aprendizado-papeis) — testes de tela (e2e).
//
// A DOCUMENTAÇÃO já existia (casos APR-*, migration 20260901130500) — o que
// faltava era o teste de tela e a ponte. Aqui implementamos o subconjunto
// DATA-INDEPENDENTE dos casos documentados, ligado pela ponte qa_cobertura_e2e:
//   APR-001  o módulo monta com as 4 abas;
//   APR-002  a aba Funções lista os cargos e a busca filtra (força o vazio);
//   APR-010  abrir o detalhe de uma função e voltar à lista;
//   APR-040  a aba Assinaturas orienta quando não há manual enviado;
//   APR-050  a aba Indicadores monta com os cartões.
//
// A ilha de QA (seed-e2e-user) planta 4 cargos fixos — os mesmos no TESTE e na
// HOMOLOGAÇÃO —, então APR-002/APR-010 podem contar com uma função ("Analista
// Financeiro"). Os estados vazios são forçados via busca (não dependem de a
// base estar limpa). Os demais casos APR (adicionar atividade/competência,
// gerar manual por IA, assinaturas com envios, salvar config, isolamento)
// exigem fixtures e seguem como casos documentados sem teste — só aviso na
// guarda, nunca reprova.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Aprendizado & Papéis", () => {
  const { email, senha: password } = credenciaisDeTeste();
  const baseUrl = Cypress.config("baseUrl") as string;

  // Um dos cargos fixos da ilha (seed-e2e-user): existe no teste e na homologação.
  const CARGO_ILHA = "Analista Financeiro";

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
    cy.visit(`${baseUrl}/aprendizado-papeis`);
    cy.contains("h1", "Aprendizado & Papéis", { timeout: 20000 }).should("be.visible");
  }

  function fecharHumorSePresente() {
    cy.get("body", { timeout: 10000 }).then(($b) => {
      if ($b.text().includes("Como você está hoje")) {
        cy.get("body").type("{esc}", { force: true });
        cy.wait(300);
      }
    });
  }

  function abrirAba(nome: string) {
    cy.contains('[role="tab"]', nome, { timeout: 20000 }).click({ force: true });
  }

  beforeEach(() => {
    login();
    goToModulo();
    fecharHumorSePresente();
  });

  // APR-001
  it("carrega o módulo Aprendizado & Papéis com as abas", () => {
    cy.contains('[role="tab"]', "Funções", { timeout: 20000 }).should("be.visible");
    cy.contains('[role="tab"]', "Assinaturas").should("exist");
    cy.contains('[role="tab"]', "Indicadores").should("exist");
    cy.contains('[role="tab"]', "Configurações").should("exist");
  });

  // APR-002
  it("a aba Funções lista as funções e a busca filtra", () => {
    // A aba Funções é a inicial; a função semeada aparece na lista.
    cy.contains(CARGO_ILHA, { timeout: 20000 }).should("be.visible");
    // Buscar um termo inexistente esvazia a lista → estado vazio orientativo.
    cy.get('input[placeholder*="Buscar funções"]', { timeout: 20000 })
      .clear({ force: true })
      .type("zzz-nao-existe-999", { force: true });
    cy.contains("Nenhuma função cadastrada", { timeout: 20000 }).should("be.visible");
    // Limpar a busca traz a lista de volta.
    cy.get('input[placeholder*="Buscar funções"]').clear({ force: true });
    cy.contains(CARGO_ILHA, { timeout: 20000 }).should("be.visible");
  });

  // APR-010
  it("abre o detalhe de uma função e volta à lista", () => {
    cy.contains(CARGO_ILHA, { timeout: 20000 }).should("be.visible").click({ force: true });
    cy.contains("button", "Voltar à lista", { timeout: 20000 }).should("be.visible").click({ force: true });
    // De volta à lista: a busca reaparece.
    cy.get('input[placeholder*="Buscar funções"]', { timeout: 20000 }).should("exist");
  });

  // APR-040
  it("a aba Assinaturas orienta quando não há manual enviado", () => {
    abrirAba("Assinaturas");
    cy.get('input[placeholder*="Buscar por colaborador"]', { timeout: 20000 })
      .clear({ force: true })
      .type("zzz-nao-existe-999", { force: true });
    cy.contains("Nenhum manual enviado para assinatura ainda", { timeout: 20000 }).should("be.visible");
  });

  // APR-050
  it("a aba Indicadores monta com os cartões", () => {
    abrirAba("Indicadores");
    cy.contains("Total de Atividades", { timeout: 20000 }).should("be.visible");
    cy.contains("Funções sem Atividades").should("exist");
  });
});
