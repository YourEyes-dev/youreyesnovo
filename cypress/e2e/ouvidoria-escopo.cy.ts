/// <reference types="cypress" />

// =====================================================================
// Ouvidoria × escopo do perfil de acesso — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (OUV-061..063), ligado pela ponte
// qa_cobertura_e2e. Reproduz o achado grave de 10/2026 (Taeco): usuário com Ouvidoria em
// "Próprio usuário" via manifestações de outras pessoas porque o papel técnico (gestor)
// abria tudo. O usuário de teste tem de propósito papel `manager` + tipo `gestor`.
//
// Massa (seed-e2e-user, tudo fictício): E2E-OUV-PROPRIA (dele), E2E-OUV-ALHEIA (outro
// autor) e E2E-OUV-ANONIMA. Nenhum teste grava ou apaga manifestação.
// =====================================================================

import { credenciaisDeTeste, credenciaisOuvidoria } from "../support/credenciais";

describe("Ouvidoria × escopo do perfil", () => {
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

  function abrirOuvidoria(aba: string | RegExp) {
    cy.visit(`${baseUrl}/ouvidoria`);
    cy.contains("h1", "Ouvidoria", { timeout: 20000 }).should("be.visible");
    fecharHumorSePresente();
    cy.contains('[role="tab"]', aba, { timeout: 20000 }).click({ force: true });
  }

  // OUV-061
  it("usuário com Ouvidoria em Próprio usuário vê só as próprias manifestações, mesmo com papel de gestão", () => {
    entrar(credenciaisOuvidoria());
    abrirOuvidoria("Minhas Manifestações");
    cy.contains("h3", "E2E-OUV-PROPRIA", { timeout: 20000 }).should("exist");
    cy.get("main").should("not.contain.text", "E2E-OUV-ALHEIA");
    cy.get("main").should("not.contain.text", "E2E-OUV-ANONIMA");
    cy.contains('[role="tab"]', "Todas Manifestações").should("not.exist");
  });

  // OUV-062
  it("usuário com Ouvidoria em Próprio usuário não recebe os controles de gestão", () => {
    entrar(credenciaisOuvidoria());
    abrirOuvidoria("Minhas Manifestações");
    cy.contains("h3", "E2E-OUV-PROPRIA", { timeout: 20000 }).should("exist");
    cy.contains('[role="tab"]', "Configurações").should("not.exist");
    cy.contains("button", "Responder").should("not.exist");
    cy.contains("button", "Criar Ações").should("not.exist");
    cy.get("main").should("not.contain.text", "Anônimas");
  });

  // OUV-063
  it("o dono continua vendo todas as manifestações da empresa", () => {
    entrar(credenciaisDeTeste());
    abrirOuvidoria("Todas Manifestações");
    cy.get('input[placeholder*="Buscar por assunto"]', { timeout: 20000 }).clear().type("E2E-OUV-");
    cy.contains("h3", "E2E-OUV-PROPRIA", { timeout: 20000 }).should("exist");
    cy.contains("h3", "E2E-OUV-ALHEIA").should("exist");
    cy.contains("h3", "E2E-OUV-ANONIMA").should("exist");
  });
});
