/// <reference types="cypress" />

// =====================================================================
// Cultura & Celebrações (/cultura-celebracoes) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (CULT-*), ligado pela ponte
// qa_cobertura_e2e. Escopo: entrada/validação — a tela monta com os KPIs e as
// abas, os indicadores culturais consolidam os números, e o modal de nova ação
// não cria nada sem título/data. NADA aqui cria ação, ritual ou preferência,
// então não depende de dado semeado.
//
// Obs.: o <h1> da página é "Cultura & Celebrações" — é o que o beforeEach confere.
// Painel Hoje, Calendário, Cobertura e a checagem de celular só olham a montagem
// (data-testid), sem depender de colaborador ou ação semeados.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Cultura & Celebrações (/cultura-celebracoes)", () => {
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
    cy.visit(`${baseUrl}/cultura-celebracoes`);
    cy.contains("h1", "Cultura & Celebrações", { timeout: 20000 }).should("be.visible");
  });

  // CULT-001
  it("abre com as abas e os KPIs", () => {
    ["Datas Ativas", "Ações Pendentes", "Ações Concluídas", "Rituais Ativos"].forEach((l) =>
      cy.contains(l).should("be.visible")
    );
    ["Experiência do Colaborador", "Preferências", "Rituais e Reconhecimento"].forEach((t) =>
      cy.contains('[role="tab"]', t).should("exist")
    );
  });

  // CULT-003
  it("mostra a janela de dias da configuração no card de celebrações", () => {
    cy.contains(/Próximas Celebrações \(\d+ dias\)/, { timeout: 20000 }).should("be.visible");
  });

  // CULT-080
  it("mostra o painel Hoje", () => {
    cy.get('[data-testid="painel-hoje"]', { timeout: 20000 }).should("be.visible").and("contain.text", "Hoje");
  });

  // CULT-081
  it("mostra o calendário e alterna para a visão anual", () => {
    cy.get('[data-testid="calendario-celebracoes"]', { timeout: 20000 }).should("be.visible");
    cy.get('[data-testid="calendario-celebracoes"]').contains("button", "Ano").click();
    cy.get('[data-testid="calendario-ano"]').should("be.visible");
    cy.get('[data-testid="calendario-celebracoes"]').contains("button", "Mês").click();
    cy.get('[data-testid="calendario-ano"]').should("not.exist");
  });

  // CULT-096
  it("mostra o botão de baixar o PDF do calendário", () => {
    cy.get('[data-testid="calendario-celebracoes"]', { timeout: 20000 })
      .contains("button", "Baixar PDF")
      .should("be.visible");
  });

  // CULT-082
  it("mostra a cobertura de celebração nos indicadores", () => {
    cy.get('[data-testid="cobertura-celebracao"]', { timeout: 20000 })
      .should("be.visible")
      .and("contain.text", "Cobertura de celebração");
  });

  // CULT-086
  it("não estoura a largura no celular", () => {
    cy.viewport(375, 812);
    cy.reload();
    cy.contains("h1", "Cultura & Celebrações", { timeout: 20000 }).should("be.visible");
    ["painel-hoje", "calendario-celebracoes", "cobertura-celebracao"].forEach((id) =>
      cy.get(`[data-testid="${id}"]`, { timeout: 20000 }).then(($el) => {
        expect($el[0].scrollWidth, id).to.be.at.most($el[0].clientWidth + 1);
      })
    );
  });

  // CULT-091
  it("mostra as opções de automação na Configuração", () => {
    cy.contains('[role="tab"]', "Rituais e Reconhecimento", { timeout: 20000 }).click({ force: true });
    cy.contains('[role="tab"]', "Configuração").click({ force: true });
    cy.get('[data-testid="config-automacao"]', { timeout: 20000 })
      .should("be.visible")
      .and("contain.text", "Criar ação pendente sozinha")
      .and("contain.text", "Gerar ações agora");
  });

  // CULT-098
  it("mostra a aba Dias da Profissão com a análise de cargos por IA", () => {
    cy.contains('[role="tab"]', "Rituais e Reconhecimento", { timeout: 20000 }).click({ force: true });
    cy.contains('[role="tab"]', "Dias da Profissão").click({ force: true });
    cy.get('[data-testid="dias-profissao"]', { timeout: 20000 })
      .should("be.visible")
      .and("contain.text", "Analisar cargos com IA")
      .and("contain.text", "Definidos pela empresa");
  });

  // CULT-094
  it("mostra o painel de alertas", () => {
    cy.get('[data-testid="alertas-cultura"]', { timeout: 20000 }).should("be.visible").and("contain.text", "Alertas");
  });

  // CULT-011
  it("não cria ação sem título ou data", () => {
    cy.contains("button", "Nova Ação").click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 })
      .should("be.visible")
      .and("contain.text", "Nova Ação Cultural");
    // Clicar em "Criar Ação" com os campos obrigatórios vazios não cria nada:
    // o modal continua aberto (o handler ignora o envio sem título/data).
    cy.get('[role="dialog"]').contains("button", "Criar Ação").click({ force: true });
    cy.get('[role="dialog"]').should("be.visible").and("contain.text", "Nova Ação Cultural");
  });

  // CULT-060
  it("mostra os indicadores culturais", () => {
    cy.contains("Indicadores Culturais").should("be.visible");
    cy.contains("Taxa de Realização").should("be.visible");
  });
});
