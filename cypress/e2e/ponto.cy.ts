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
//   PONTO-HOM-H1 (escalas), PONTO-HOM-F1 (feriados unificados),
//   PONTO-498 (justificativas: natureza, app e aviso de nome × regra),
//   ESP-ASS-012..015 (espelho com assinatura eletrônica: pré-visualização,
//   botão de envio com a regra da competência fechada, /assinar com token
//   inválido e o painel de selos). O envio real e a assinatura com câmera
//   (ESP-ASS-013 completo e ESP-ASS-016) são homologação manual.
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

  // PONTO-HOM-F1 — Configurações › Feriados: a unificação dos dois cadastros.
  // Confere as duas seções (Calendário da unidade / Feriados por localização) e
  // que o cadastro por localização não oferece mais a abrangência 'Filial'.
  it("abre Configurações › Feriados com as duas seções e sem a abrangência Filial", () => {
    abrirArea("tab-ponto-configuracoes");
    abrirSub("Feriados");
    cy.contains("Calendário da unidade", { timeout: 20000 }).should("be.visible");
    cy.contains("Feriados por localização").should("be.visible");
    cy.contains("button", "Adicionar feriado", { timeout: 20000 }).should("be.visible").click({ force: true });
    cy.get('[role="dialog"]', { timeout: 15000 }).should("exist");
    // a abrangência 'Filial / unidade' saiu do cadastro por localização
    cy.get('[role="dialog"]').contains("Filial / unidade").should("not.exist");
    cy.get("body").type("{esc}", { force: true });
  });

  // PONTO-498 — Configurações › Geral › Justificativas: colunas Natureza e
  // No app, e o aviso ao vivo quando o nome contradiz a regra de abono.
  // Não salva nada (o aviso aparece antes de salvar).
  it("abre Configurações › Geral › Justificativas com natureza, app e aviso de nome × regra", () => {
    abrirArea("tab-ponto-configuracoes");
    cy.contains('[role="tab"]', /^\s*Geral\s*$/, { timeout: 20000 }).click({ force: true });
    cy.contains("button", "Configurar Justificativas", { timeout: 20000 }).should("be.visible").click({ force: true });
    cy.get('[role="dialog"]', { timeout: 15000 }).should("exist");
    cy.get('[role="dialog"]').contains("th", "Natureza", { timeout: 20000 }).should("exist");
    cy.get('[role="dialog"]').contains("th", "No app").should("exist");
    cy.get('[role="dialog"]').find('input[placeholder="Ex.: Atestado médico"]').clear().type("Falta não abonada");
    cy.get('[data-testid="just-abono"]').click({ force: true });
    cy.contains('[role="option"]', "Sim (abona)", { timeout: 10000 }).click({ force: true });
    cy.get('[data-testid="just-aviso-divergencia"]', { timeout: 10000 })
      .should("be.visible")
      .and("contain.text", "NÃO abona");
    cy.get("body").type("{esc}", { force: true });
  });

  // ESP-ASS-012 — Relatórios › Espelho: Visualizar abre o PDF num diálogo, sem
  // botão de baixar. Não depende de massa: com ou sem apuração o diálogo abre.
  it("abre Relatórios › Espelho de Ponto e a pré-visualização sem botão de baixar", () => {
    abrirArea("tab-ponto-apuracao");
    abrirSub("Relatórios");
    cy.get('[data-testid="btn-visualizar-espelho"]', { timeout: 20000 }).should("be.visible").click({ force: true });
    cy.get('[data-testid="espelho-visualizar"]', { timeout: 20000 }).should("be.visible").within(() => {
      cy.contains("Pré-visualização do espelho").should("be.visible");
      cy.contains("button", /baixar|download/i).should("not.exist");
    });
    cy.get("body").type("{esc}", { force: true });
  });

  // ESP-ASS-013 (entrada) — o botão de envio existe e diz a regra quando ainda
  // não pode enviar (competência aberta ou colaborador não escolhido).
  it("mostra Enviar para assinatura no Espelho de Ponto com a regra da competência fechada", () => {
    abrirArea("tab-ponto-apuracao");
    abrirSub("Relatórios");
    cy.get('[data-testid="btn-enviar-assinatura"]', { timeout: 20000 }).should("exist");
    cy.get('[data-testid="regra-envio-assinatura"]', { timeout: 20000 })
      .should("be.visible")
      .invoke("text")
      .should("match", /compet[eê]ncia|colaborador|espelho/i);
  });

  // ESP-ASS-014 — página pública com token inválido não revela nada.
  it("abre /assinar com token inválido e mostra Link inválido", () => {
    cy.visit(`${baseUrl}/assinar/token-invalido-qa`);
    cy.contains("Link inválido", { timeout: 20000 }).should("be.visible");
  });

  // ESP-ASS-015 — painel de assinaturas com a legenda dos selos.
  it("mostra o painel de assinaturas do espelho com a legenda dos selos", () => {
    abrirArea("tab-ponto-apuracao");
    abrirSub("Relatórios");
    cy.get('[data-testid="painel-assinaturas-espelho"]', { timeout: 20000 }).should("be.visible");
    cy.get('[data-testid="legenda-selos"]').within(() => {
      cy.contains("Assinado ✓").should("exist");
      cy.contains("Ressalva").should("exist");
      cy.contains("Contestado").should("exist");
      cy.contains("Pendente").should("exist");
    });
  });
});
