/// <reference types="cypress" />

// =====================================================================
// Perfil de acesso × tela Início — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (PERFIL-022..025), ligado pela
// ponte qa_cobertura_e2e. Prova o achado de campo de 10/2026: a tela Início
// mostrava pilares, indicadores, pendências e alertas da empresa para TODO
// usuário, e o perfil de acesso não tinha como escondê-los.
//
// Duas contas, ambas semeadas por seed-e2e-user no tenant de teste:
//   - conta-robô (owner): editor de perfil e controle positivo do painel completo;
//   - usuário restrito (perfil "E2E Restrito (Cypress)", inicio_blocos = vazio):
//     enxerga só a saudação e o nome do perfil no cabeçalho.
// Nenhum teste altera perfil ou vínculo: o editor é aberto e cancelado.
// =====================================================================

import { credenciaisDeTeste, credenciaisRestrito } from "../support/credenciais";

const NOME_PERFIL_RESTRITO = "E2E Restrito (Cypress)";
const BLOCOS = ["Visão geral dos pilares", "Indicadores", "Pendências", "Alertas críticos"];

describe("Perfil de acesso × tela Início", () => {
  const baseUrl = Cypress.config("baseUrl") as string;

  function entrar({ email, senha }: { email: string; senha: string }) {
    cy.clearCookies();
    cy.clearLocalStorage();
    cy.visit(`${baseUrl}/login`);
    cy.get('input[type="email"]', { timeout: 20000 })
      .should("exist").scrollIntoView().should("be.visible").clear().type(email);
    cy.get('input[autocomplete="current-password"]', { timeout: 20000 })
      .should("exist").scrollIntoView().should("be.visible").clear().type(senha, { log: false });
    cy.contains("button", /^Entrar$/).click();
    cy.aguardarSessaoSupabase();
    cy.location("pathname", { timeout: 20000 }).should("not.match", /\/login/);
  }

  function fecharHumorSePresente() {
    cy.get("body", { timeout: 10000 }).then(($b) => {
      if ($b.text().includes("Como você está hoje")) {
        cy.get("body").type("{esc}", { force: true });
        cy.wait(300);
      }
    });
  }

  function abrirInicio() {
    cy.visit(`${baseUrl}/`);
    fecharHumorSePresente();
  }

  // PERFIL-022
  it("o editor de perfil oferece a seção Tela inicial com os quatro blocos, todos desmarcados no perfil novo", () => {
    entrar(credenciaisDeTeste());
    cy.visit(`${baseUrl}/usuarios`);
    cy.contains("h1", "Usuários", { timeout: 20000 }).should("be.visible");
    fecharHumorSePresente();
    cy.contains('[role="tab"]', "Perfis").scrollIntoView().click({ force: true });
    cy.contains("button", "Novo Perfil", { timeout: 20000 }).click();

    // Pega a janela pelo título: pode haver outro [role="dialog"] oculto no DOM
    // (cy.within exige um único elemento).
    cy.contains('[role="dialog"]', "Novo Perfil", { timeout: 15000 }).within(() => {
      // A seção fica abaixo da dobra do formulário (área rolável): rola antes de exigir visibilidade.
      cy.contains("Tela inicial (Início)").scrollIntoView().should("be.visible");
      BLOCOS.forEach((bloco) => {
        cy.contains("label", bloco)
          .scrollIntoView()
          .find('[role="checkbox"]')
          .should("have.attr", "aria-checked", "false");
      });
      cy.contains("button", "Cancelar").click();
    });
    cy.contains('[role="dialog"]', "Novo Perfil").should("not.exist");
  });

  // PERFIL-023
  it("perfil sem blocos vê só a saudação na tela Início, sem números nem alertas da empresa", () => {
    entrar(credenciaisRestrito());
    abrirInicio();
    cy.contains("h1", /^Olá,/, { timeout: 20000 }).should("be.visible");
    cy.get("main").should("contain.text", "Use o menu ao lado");
    // "Governança do Trabalho Humano" aparece no subtítulo fixo da página; o cabeçalho do bloco de
    // pilares é identificado pela legenda própria dele.
    ["Visão integrada dos 4 pilares estratégicos", "KPIs Operacionais", "Colaboradores Ativos", "Pendências", "Alertas Críticos"].forEach(
      (texto) => cy.get("main").should("not.contain.text", texto),
    );
  });

  // PERFIL-024
  it("o cabeçalho mostra o nome do perfil de acesso, não o papel técnico", () => {
    entrar(credenciaisRestrito());
    abrirInicio();
    cy.get("header", { timeout: 20000 }).should("contain.text", NOME_PERFIL_RESTRITO);
    cy.get("header").should("not.contain.text", "Gestor");
  });

  // PERFIL-025
  it("o dono continua vendo o painel completo na tela Início", () => {
    entrar(credenciaisDeTeste());
    abrirInicio();
    cy.contains("h1", "Dashboard", { timeout: 20000 }).should("be.visible");
    cy.get("main", { timeout: 20000 }).should("contain.text", "Pendências");
    cy.get("main").should("contain.text", "Alertas Críticos");
    cy.get("main").should("contain.text", "KPIs Operacionais");
  });
});
