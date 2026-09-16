/// <reference types="cypress" />

// =====================================================================
// Contratos de Experiência (/contratos-experiencia) — testes de tela (e2e).
//
// Cada it() corresponde a um caso documentado (EXP-*), ligado pela ponte
// qa_cobertura_e2e. Escopo: entrada/validação — o painel monta com as abas e
// os KPIs, a lista tem busca e filtros, e a Configuração da Empresa trava um
// modelo de períodos que excede 90 dias (CLT art. 445). NADA aqui salva
// configuração nem cria/altera contrato (a trava dos 90 dias deixa o botão
// desabilitado), então não depende de dado semeado além da ilha padrão.
//
// A aba Config mostra o formulário porque a ilha de QA já tem a empresa
// (matriz) semeada — o contexto de empresa ativa a seleciona sozinho.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Contratos de Experiência (/contratos-experiencia)", () => {
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

  beforeEach(() => {
    login();
    cy.visit(`${baseUrl}/contratos-experiencia`);
    cy.contains("h1", "Contratos de Experiência", { timeout: 20000 }).should("be.visible");
  });

  // EXP-001
  it("abre o painel com as abas e os KPIs", () => {
    ["Painel", "Configuração da Empresa"].forEach((t) =>
      cy.contains('[role="tab"]', t).should("exist")
    );
    ["Em Experiência", "Vencendo em 7 dias", "Vencendo em 15 dias", "Vencendo em 30 dias", "Total de Contratos"]
      .forEach((l) => cy.contains(l).should("be.visible"));
  });

  // EXP-003
  it("tem busca e filtros na lista de contratos", () => {
    cy.get('input[placeholder^="Buscar colaborador"]').should("exist");
    // Filtros de status/prazo/unidade são seletores (Radix combobox).
    cy.get('button[role="combobox"]').should("have.length.at.least", 2);
  });

  // EXP-060
  it("bloqueia a configuração de períodos que excede 90 dias", () => {
    cy.contains('[role="tab"]', "Configuração da Empresa").click({ force: true });
    cy.contains("label", "Duração do 1º período", { timeout: 20000 }).should("be.visible");
    // O campo é um input numérico controlado do React: digitar tecla a tecla
    // re-renderiza e solta o elemento do DOM. Setamos o valor com UM evento
    // 'input' (padrão confiável), pelo realm do próprio app (ownerDocument).
    cy.contains("label", "Duração do 1º período").parent().find('input[type="number"]').then(($i) => {
      const input = $i[0] as HTMLInputElement;
      const win = input.ownerDocument.defaultView as (Window & typeof globalThis);
      const setter = Object.getOwnPropertyDescriptor(win.HTMLInputElement.prototype, "value")!.set!;
      setter.call(input, "95");
      input.dispatchEvent(new win.Event("input", { bubbles: true }));
    });
    cy.contains("excede 90", { timeout: 20000 }).should("be.visible");
    cy.contains("button", "Salvar Configuração").should("be.disabled");
  });
});
