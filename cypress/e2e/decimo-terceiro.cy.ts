/// <reference types="cypress" />

// =====================================================================
// 13º Salário (aba do módulo /financeiro) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (DEC13-*), ligado pela ponte
// qa_cobertura_e2e. Escopo: a aba do 13º monta e EXPÕE, de forma
// data-independente (valem na ilha vazia, sem fixtures), os controles que
// materializam cada regra — a apuração dos avos (Lei 4.090), a média das
// variáveis, a política de adiantamento/afastamento, a dedução da 1ª
// parcela e as colunas de INSS/IRRF. O valor numérico de cada regra é
// verificado pelo Motor (casos de nível api: DEC13-030/031/051/070/071);
// aqui provamos que a TELA oferece e orienta cada uma.
//
// Fora deste primeiro lote (precisa de um 13º já calculado para aparecer no
// detalhe, portanto de fixture): DEC13-042 (FGTS nas duas parcelas).
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("13º Salário", () => {
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

  function fecharHumorSePresente() {
    cy.get("body", { timeout: 10000 }).then(($b) => {
      if ($b.text().includes("Como você está hoje")) {
        cy.get("body").type("{esc}", { force: true });
        cy.wait(300);
      }
    });
  }

  function abrir13() {
    cy.visit(`${baseUrl}/financeiro`);
    cy.contains("h1", "Módulo Financeiro", { timeout: 20000 }).should("be.visible");
    fecharHumorSePresente();
    // A aba tem id estável (independe do texto visível).
    cy.get("#tab-folha-13salario", { timeout: 20000 }).scrollIntoView().click({ force: true });
    cy.contains("h3", "13º Salário", { timeout: 20000 }).should("be.visible");
    cy.contains("Algo deu errado").should("not.exist");
  }

  // Abre o modal "Calcular 13º" e espera ele montar.
  function abrirCalcular() {
    cy.contains("button", "Calcular 13º", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 15000 }).contains("Calcular 13º Salário").should("exist");
  }
  function fecharDialog() {
    cy.get('[role="dialog"]').contains("button", "Cancelar").click({ force: true });
    cy.get('[role="dialog"]').should("not.exist");
  }

  beforeEach(() => {
    login();
    abrir13();
  });

  // DEC13-001
  it("apuração conta os avos (1/12 por mês, fração de 15 dias)", () => {
    abrirCalcular();
    cy.get('[role="dialog"]').contains("Avos (meses trabalhados)").should("exist");
    cy.get('[role="dialog"]').contains("button", /Apurar/).should("exist");
    cy.get('[role="dialog"]').contains("1/12 por mês").should("exist");
    cy.get('[role="dialog"]').contains("fração de 15 dias").should("exist");
    fecharDialog();
  });

  // DEC13-002
  it("apuração considera as faltas no cômputo dos avos", () => {
    abrirCalcular();
    // O texto da apuração declara que os avos saem da admissão, das faltas
    // e dos afastamentos — é a trava do avo cheio por faltas (RN da Lei 4.090).
    cy.get('[role="dialog"]').contains("faltas").should("exist");
    fecharDialog();
  });

  // DEC13-003
  it("política do 13º trata os afastamentos (15 dias antes do INSS)", () => {
    cy.get("button[title='Política do 13º']", { timeout: 20000 }).click({ force: true });
    cy.get('[role="dialog"]', { timeout: 15000 }).contains("Política do 13º salário").should("exist");
    cy.get('[role="dialog"]').contains("Dias de afastamento por conta da empresa").should("exist");
    cy.get('[role="dialog"]').contains("15 dias antes do benefício do INSS").should("exist");
    fecharDialog();
  });

  // DEC13-020
  it("apuração soma a média das variáveis do ano", () => {
    abrirCalcular();
    cy.get('[role="dialog"]').contains("Média das variáveis").should("exist");
    cy.get('[role="dialog"]').contains("média das variáveis do ano").should("exist");
    fecharDialog();
  });

  // DEC13-032
  it("oferece o adiantamento do 13º nas férias e a política da 1ª parcela", () => {
    cy.contains("button", "Adiantamento nas férias", { timeout: 20000 }).should("exist");
    cy.get("button[title='Política do 13º']").click({ force: true });
    cy.get('[role="dialog"]', { timeout: 15000 }).contains("Adiantamento (1ª parcela)").should("exist");
    fecharDialog();
  });

  // DEC13-033
  it("na 2ª parcela, a tela deduz a 1ª parcela já paga", () => {
    abrirCalcular();
    // Seleciona a 2ª parcela e confirma que aparece o campo de dedução.
    cy.get('[role="dialog"]').contains("label", "Parcela").parent().find('[role="combobox"]').click({ force: true });
    cy.contains('[role="option"]', "2ª Parcela").click({ force: true });
    cy.get('[role="dialog"]').contains("1ª Parcela (já paga)").should("exist");
    fecharDialog();
  });

  // DEC13-040
  it("a apuração do 13º expõe a coluna de INSS", () => {
    cy.contains("th", "INSS").should("exist");
  });

  // DEC13-041
  it("a apuração do 13º expõe a coluna de IRRF", () => {
    cy.contains("th", "IRRF").should("exist");
  });

  // DEC13-060
  it("apura o 13º proporcional pelos avos desde a admissão", () => {
    // 13º proporcional (inclusive na rescisão) é contado por avos a partir
    // da admissão — a tela expõe a coluna de Avos e o 13º integral.
    cy.contains("th", "Avos").should("exist");
    cy.contains("th", "13º integral").should("exist");
    abrirCalcular();
    cy.get('[role="dialog"]').contains("a partir da admissão").should("exist");
    fecharDialog();
  });

  // DEC13-042 — depende de um 13º já calculado (seed-folha-fixture): o FGTS
  // de 8% aparece discriminado no DETALHE de cada parcela.
  it("o detalhe de um 13º calculado discrimina o FGTS", () => {
    cy.get('[title="Detalhe"]', { timeout: 20000 }).first().click({ force: true });
    cy.get('[role="dialog"]', { timeout: 15000 }).contains("FGTS").should("exist");
    cy.get("body").type("{esc}", { force: true });
  });
});
