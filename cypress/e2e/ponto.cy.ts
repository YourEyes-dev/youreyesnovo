/// <reference types="cypress" />

// =====================================================================
// Módulo Ponto — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado da Bateria de Homologação do
// Ponto (qa_casos_teste, nível e2e), ligado pela ponte qa_cobertura_e2e.
//
// Escopo destes testes automatizados: a ENTRADA de cada caso — a tela do
// caso monta e o ponto de partida (formulário/ação/controle) aparece. É a
// parte robusta e não destrutiva de cada fluxo: navega e confere que a tela
// existe, sem salvar nada nem depender de dado semeado específico.
//
// O que fica de fora, DE PROPÓSITO (segue como homologação manual, no
// roteiro): os passos que dependem de estado semeado (pendência aberta em
// B1, dois colaboradores com batidas em D2, escala 12x36 em H1), de arquivo
// adulterado (D6), de navegador anônimo com rate-limit (F3) ou de SQL Editor
// (C1, C2, F2). Um teste de tela não encena isso de forma confiável.
//
// Casos cobertos: PONTO-HOM-A1 (nova declaração de intervalo),
//   PONTO-HOM-E1 (novo certificado digital), PONTO-HOM-B1 (fechamento),
//   PONTO-HOM-E2 (dossiê fiscal), PONTO-HOM-I1 (alertas CLT),
//   PONTO-HOM-H1 (escalas).
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Ponto", () => {
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

  function irAoPonto() {
    cy.visit(`${baseUrl}/ponto`);
    cy.contains("h1", "Controle de Ponto Eletrônico", { timeout: 20000 }).should("be.visible");
  }

  // Aba de topo por id estável (definido em Ponto.tsx: tab-ponto-<area>).
  function abrirArea(id: string) {
    cy.get(`#${id}`, { timeout: 20000 }).click({ force: true });
  }

  // Sub-aba (Radix TabsTrigger vira role=tab) por texto.
  // force:true por causa do scroll-lock do Radix, padrão da suíte.
  function abrirSub(texto: string) {
    cy.contains('[role="tab"]', texto, { timeout: 20000 }).click({ force: true });
  }

  beforeEach(() => {
    login();
    irAoPonto();
  });

  // PONTO-HOM-A1 — Configurações › Intervalo pré-assinalado: a declaração
  // formal do intervalo. Confere que o formulário de Nova declaração abre.
  it("abre Configurações › Intervalo pré-assinalado e o formulário de nova declaração", () => {
    abrirArea("tab-ponto-configuracoes");
    abrirSub("Intervalo pré-assinalado");
    cy.contains("button", "Nova declaração", { timeout: 20000 }).should("be.visible").click({ force: true });
    cy.contains("Nova declaração de intervalo", { timeout: 20000 }).should("be.visible");
    cy.contains("Intervalo (minutos)").should("exist");
  });

  // PONTO-HOM-E1 — Configurações › Certificado digital: o certificado que
  // assina AFD/AEJ. Confere que o formulário de Novo certificado abre.
  it("abre Configurações › Certificado digital e o formulário de novo certificado", () => {
    abrirArea("tab-ponto-configuracoes");
    abrirSub("Certificado digital");
    cy.contains("button", "Novo certificado", { timeout: 20000 }).should("be.visible").click({ force: true });
    cy.contains("Novo certificado digital", { timeout: 20000 }).should("be.visible");
    cy.contains("Vence em").should("exist");
  });

  // PONTO-HOM-B1 — Apuração › Fechamento: o portão que trava o fechamento
  // com pendência. Confere que a tela de Fechamento monta com o controle.
  it("abre Apuração › Fechamento com o controle de fechar período", () => {
    abrirArea("tab-ponto-apuracao");
    abrirSub("Fechamento");
    cy.contains("Fechamento & Espelho de Ponto", { timeout: 20000 }).should("be.visible");
    cy.contains("button", /Fechar Período|Reabrir Período/).should("exist");
  });

  // PONTO-HOM-E2 — Compliance › Dossiê fiscal: reúne as peças da
  // fiscalização. Confere que a tela monta com a ação de montar o dossiê.
  it("abre Compliance › Dossiê fiscal com a ação de montar", () => {
    abrirArea("tab-ponto-compliance");
    abrirSub("Dossiê fiscal");
    cy.contains("Dossiê de fiscalização", { timeout: 20000 }).should("be.visible");
    cy.contains("button", /Montar dossiê|Montar de novo|Montando/, { timeout: 20000 }).should("exist");
  });

  // PONTO-HOM-I1 — Compliance › Alertas CLT: onde um alerta vira ação.
  // Confere que o painel de alertas monta.
  it("abre Compliance › Alertas CLT", () => {
    abrirArea("tab-ponto-compliance");
    abrirSub("Alertas CLT");
    cy.contains("Alertas Operacionais", { timeout: 20000 }).should("be.visible");
  });

  // PONTO-HOM-H1 — Escalas: onde a formalização (12x36, revezamento) é
  // cobrada. Confere que a lista de escalas monta com a ação de criar.
  it("abre Escalas com a ação de criar escala", () => {
    abrirArea("tab-ponto-escalas");
    cy.contains("button", "Criar Escala", { timeout: 20000 }).should("be.visible");
  });
});
