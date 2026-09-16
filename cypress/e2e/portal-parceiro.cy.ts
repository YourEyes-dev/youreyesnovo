/// <reference types="cypress" />

// =====================================================================
// Área do Parceiro — testes de tela (nível e2e).
//
// Entra com a conta do robô-parceiro (sem perfil de tenant), semeada pela
// função seed-e2e-user junto com a conta principal. Cada it() corresponde a
// um caso documentado (qa_casos_teste, nível e2e) ligado por qa_cobertura_e2e.
// Casos cobertos: PGP-030, PGP-031, PGP-032.
// PGP-020/021 (aba Parceiros do SuperAdmin) seguem sem it(): a conta-robô
// não é superadmin e não deve virar — ficam documentados até existir um
// robô-superadmin próprio.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Área do Parceiro", () => {
  const { senha } = credenciaisDeTeste();
  const email = String(Cypress.env("parceiroEmail") || "parceiro.robo@youreyes.local");
  const baseUrl = Cypress.config("baseUrl") as string;

  function loginParceiro() {
    cy.visit(`${baseUrl}/parceiros/entrar`);
    cy.get('input[type="email"]', { timeout: 20000 }).should("be.visible").clear().type(email);
    cy.get('input[autocomplete="current-password"]', { timeout: 20000 }).should("be.visible").clear().type(senha, { log: false });
    cy.contains("button", /^Entrar$/).click();
  }

  // A conta do robô-parceiro é semeada pela esteira (passo "Semear a conta-robô"),
  // que só roda com o secret QA_E2E_TOKEN. Sem o secret, a conta pode não
  // existir: aí estes testes ficam PENDENTES (pulados) com o motivo no log, em
  // vez de pintar a corrida de vermelho por um problema de configuração.
  beforeEach(function () {
    loginParceiro();
    // Primeiro decide se a conta existe (toast de erro OU sessão gravada);
    // só depois exige a sessão. A ordem inversa estourava o timeout da
    // sessão antes de a checagem de pulo rodar.
    cy.window({ timeout: 20000 }).should((win) => {
      const temSessao = Object.keys(win.localStorage).some((k) => k.startsWith("sb-") && k.endsWith("-auth-token"));
      const falhou = /Não foi possível entrar/i.test(win.document.body.innerText || "");
      // eslint-disable-next-line @typescript-eslint/no-unused-expressions
      expect(temSessao || falhou, "login respondeu (sessão ou erro)").to.be.true;
    });
    cy.get("body").then(($b) => {
      if (/Não foi possível entrar/i.test($b.text())) {
        cy.task("diag", `Robô-parceiro (${email}) não existe no ambiente de teste. ` +
          "Cadastre o secret QA_E2E_TOKEN no repositório para a esteira semear a conta. Testes PGP-030..032 pulados.");
        this.skip();
      }
    });
    cy.aguardarSessaoSupabase();
    cy.location("pathname", { timeout: 30000 }).should("match", /\/parceiro$/);
    cy.get('[data-testid="portal-parceiro"]', { timeout: 30000 }).should("exist");
  });

  it("PGP-030: Parceiro sem empresa loga pelo site e cai na Área do Parceiro", () => {
    cy.get('[data-testid="portal-parceiro-nome"]').should("contain.text", "Clínica Staging SST");
    // Nunca o menu do sistema: sem sidebar do app, sem "Colaboradores".
    cy.get('[data-sidebar="sidebar"]').should("not.exist");
    cy.contains("Colaboradores").should("not.exist");
  });

  it("PGP-031: Portal: copiar o link de indicação", () => {
    cy.window().then((win) => {
      cy.stub(win.navigator.clipboard, "writeText").as("copiar").resolves();
    });
    cy.get('[data-testid="portal-link-principal"]').should("contain.text", "?ref=CLINICASTAGING");
    cy.get('[data-testid="portal-copiar-link"]').click();
    cy.get("@copiar").should("have.been.calledWithMatch", /\?ref=CLINICASTAGING$/);
    cy.contains(/Copiado/).should("exist");
  });

  it("PGP-032: Portal: carteira lista as empresas originadas com estágio e exporta CSV", () => {
    cy.get('[data-testid="portal-carteira"] tbody tr', { timeout: 20000 }).should("have.length.at.least", 1);
    cy.get('[data-testid="portal-carteira"]').should("contain.text", "Empresa Staging LTDA");
    cy.get('[data-testid="portal-carteira"] [data-testid="estagio"]').first().invoke("text").should("match", /Lead|Proposta|Contrato|Implantação|Go-live|Ativo|Churn/);
    cy.window().then((win) => {
      cy.stub(win.URL, "createObjectURL").as("csv").returns("blob:csv");
    });
    cy.get('[data-testid="portal-exportar"]').click();
    cy.get("@csv").should("have.been.called");
  });
});
