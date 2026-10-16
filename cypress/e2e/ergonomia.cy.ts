/// <reference types="cypress" />

// =====================================================================
// Gestão de Risco Ergonômico (/ergonomia) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (ERGO-*), ligado pela ponte
// qa_cobertura_e2e. Escopo: a entrada do módulo — o Guia Rápido abre e fecha,
// a trava de risco sem título segura o cadastro, e o fluxo GRO monta as 7 abas
// após a base NR-17 estar inicializada.
//
// SOBRE SEMEAR DADO (ERGO-001): a página só renderiza as 7 abas quando o
// módulo tem inventário NR-17; vazio, mostra o EmptyState com o botão
// "Inicializar Itens NR-17". O lote anterior ADIOU o ERGO-001 justamente por
// isso (migration 20260909130000_qa_cobertura_e2e_ergo001_adiar.sql). Aqui o
// retomamos pela via sancionada em cypress.config.ts ("A suíte Cypress escreve
// dados ... só roda no ambiente de teste"): o próprio it() inicializa a base
// NR-17 se ela estiver vazia. O backend é IDEMPOTENTE (useErgonomia.
// initializeItens confere os códigos existentes e não duplica), então rodar de
// novo não acumula nem quebra.
//   Consequência consciente (conferência de impacto): inicializar deixa a ilha
//   de QA do robô com inventário NR-17 permanentemente. Isso NÃO afeta os it()
//   ERGO-002/ERGO-011 (abrem diálogos, independem do estado da ilha). Deixa,
//   porém, o ERGO-072 (estado vazio de primeiro acesso) sem como reproduzir
//   nesta mesma ilha — ele segue pendente e exigirá um tenant recém-criado.
//
// ERGO-010: o Bloqueio 1 foi resolvido — o "Novo Risco" da tela agora grava no
// inventário unificado `gro_riscos` (via useGRORiscos.criarRisco), então o risco
// cadastrado APARECE no Inventário GRO, como o caso pede. O it() abaixo semeia e
// confere isso de ponta a ponta. (Ver docs/BLOQUEIOS_PRODUTO_QA_E2E.md.)
//
// Ainda NÃO cobertos (agora destravados; follow-up) ou por descompasso real:
//   • ERGO-014/015/020/024/061 — destravados pela mesma correção (leem/alimentam
//     `gro_riscos`); faltam escrever os it() correspondentes.
//   • ERGO-012 — "eixo ergonômico classifica o risco": o modelo GRO não guarda o
//     eixo (físico/cognitivo/organizacional), então segue sem suporte.
//   • ERGO-021 — o caso pede "Responsável exigido na ação", mas o AcaoForm só
//     trava o salvar por falta de título (responsável é opcional na tela).
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Gestão de Risco Ergonômico (/ergonomia)", () => {
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
    cy.visit(`${baseUrl}/ergonomia`);
    cy.contains("h1", "Gestão de Risco Ergonômico", { timeout: 20000 }).should("be.visible");
  });

  // ERGO-001
  it("inicializa a base NR-17 e abre as 7 abas do fluxo GRO", () => {
    // Ilha vazia → EmptyState com o botão de inicializar. Se já inicializada,
    // o botão não existe e as abas já estão lá. initializeItens é idempotente.
    cy.get("body", { timeout: 20000 }).then(($b) => {
      if ($b.text().includes("Inicializar Itens NR-17")) {
        cy.contains("button", "Inicializar Itens NR-17").click({ force: true });
      }
    });
    // As 7 abas do fluxo GRO renderizam. Asserção por id (estável ao texto).
    [
      "#tab-ergo-aep",
      "#tab-ergo-inventario",
      "#tab-ergo-prioritarios",
      "#tab-ergo-acoes",
      "#tab-ergo-monitoramento",
      "#tab-ergo-analise-ia",
      "#tab-ergo-base",
    ].forEach((sel) => cy.get(sel, { timeout: 20000 }).should("be.visible"));
  });

  // ERGO-002
  it("abre e fecha o Guia Rápido sem afetar a tela", () => {
    cy.get("#btn-ergo-guia-rapido").click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 })
      .should("be.visible")
      .and("contain.text", "Guia Rápido — Ergonomia");
    cy.get("body").type("{esc}");
    cy.get('[role="dialog"]').should("not.exist");
    cy.contains("h1", "Gestão de Risco Ergonômico").should("be.visible");
  });

  // ERGO-011
  it("bloqueia o cadastro de risco sem título", () => {
    cy.get("#btn-ergo-novo-risco").click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 })
      .should("be.visible")
      .and("contain.text", "Cadastrar Risco Ergonômico");
    cy.contains("button", "Cadastrar Risco").should("be.disabled");
  });

  // ERGO-010
  it("cadastra um risco e ele aparece no Inventário GRO", () => {
    // O Inventário GRO (como as outras abas) só monta com a base NR-17; garante.
    cy.get("body", { timeout: 20000 }).then(($b) => {
      if ($b.text().includes("Inicializar Itens NR-17")) {
        cy.contains("button", "Inicializar Itens NR-17").click({ force: true });
      }
    });
    // Título único por execução, pra a asserção não colidir com riscos antigos.
    const titulo = `[E2E] Risco ergonômico ${Date.now()}`;
    cy.get("#btn-ergo-novo-risco").click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 })
      .should("be.visible")
      .and("contain.text", "Cadastrar Risco Ergonômico");
    // Título é o obrigatório; eixo/severidade/probabilidade já vêm com padrão.
    cy.get("#titulo").clear().type(titulo);
    cy.contains("button", "Cadastrar Risco").should("not.be.disabled").click({ force: true });
    // A app confirma a persistência no inventário unificado (gro_riscos).
    cy.contains("Risco registrado no GRO", { timeout: 20000 }).should("be.visible");
    // E o risco aparece no Inventário GRO — o que o Bloqueio 1 impedia.
    cy.get("#tab-ergo-inventario", { timeout: 20000 }).click({ force: true });
    cy.contains(titulo, { timeout: 20000 }).should("be.visible");
  });
});
