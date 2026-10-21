/// <reference types="cypress" />

// =====================================================================
// Acesso crítico — Onda 1 do plano de cobertura (docs/PLANO_COBERTURA_CYPRESS.md).
//
// Diferente de autenticacao.cy.ts (que exercita a tela de login SEM entrar),
// aqui o login é VÁLIDO e o que se confere é o resultado: a sessão nasce, sobrevive
// a um reload, morre no logout e a área de SuperAdmin barra quem não é superadmin.
// Também cobre as telas de recuperação/ativação de conta que o usuário usa sozinho.
//
// Cada it() é ligado a um caso documentado (AUTH-*) pela ponte qa_cobertura_e2e.
// Usa a conta-robô do ambiente de teste (credenciaisDeTeste) — que é administradora
// da Empresa Staging e NÃO é superadmin.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Acesso crítico", () => {
  const { email, senha } = credenciaisDeTeste();
  const baseUrl = Cypress.config("baseUrl") as string;

  const temSessao = (win: Window) =>
    Object.keys(win.localStorage).some((k) => k.startsWith("sb-") && k.endsWith("-auth-token"));

  function entrar() {
    cy.visit(`${baseUrl}/login`);
    cy.get('input[type="email"]', { timeout: 20000 })
      .should("exist").scrollIntoView().should("be.visible").clear().type(email);
    cy.get('input[autocomplete="current-password"]', { timeout: 20000 })
      .should("exist").scrollIntoView().should("be.visible").clear().type(senha, { log: false });
    cy.contains("button", /^Entrar$/).click();
    cy.aguardarSessaoSupabase();
    cy.location("pathname", { timeout: 20000 }).should("not.match", /\/login/);
  }

  beforeEach(() => {
    cy.clearCookies();
    cy.clearLocalStorage();
  });

  // AUTH-002
  it("login com credenciais válidas entra no sistema", () => {
    entrar();
    // Entrou de verdade: saiu do /login, a sessão existe e o menu do usuário está na tela.
    cy.window().should((win) => expect(temSessao(win), "sessão persistida").to.be.true);
    cy.get("header", { timeout: 20000 }).should("be.visible");
    cy.contains("h1", "Login").should("not.exist");
  });

  // AUTH-010
  it("a sessão persiste ao recarregar a página", () => {
    entrar();
    cy.reload();
    cy.window().should((win) => expect(temSessao(win), "sessão após reload").to.be.true);
    cy.location("pathname", { timeout: 20000 }).should("not.match", /\/login/);
    cy.get("header", { timeout: 20000 }).should("be.visible");
  });

  // AUTH-011
  it("logout limpa a sessão", () => {
    entrar();
    cy.get("header .lucide-chevron-down", { timeout: 20000 }).closest("button").click();
    cy.contains('[role="menuitem"]', "Sair").click();
    cy.location("pathname", { timeout: 20000 }).should("match", /\/login/);
    cy.window().should((win) => expect(temSessao(win), "sessão após sair").to.be.false);
    // Rota protegida volta a exigir login.
    cy.visit(`${baseUrl}/colaboradores`);
    cy.contains("h1", "Login", { timeout: 20000 }).should("be.visible");
  });

  // AUTH-021
  it("área de superadmin barra quem não é superadmin", () => {
    entrar();
    cy.visit(`${baseUrl}/admin`);
    cy.contains("Acesso Restrito", { timeout: 20000 }).should("be.visible");
    cy.contains("Esta área é restrita a Super Administradores.").should("be.visible");
  });

  // AUTH-031
  it("redefinir senha sem sessão de recuperação é barrado", () => {
    cy.visit(`${baseUrl}/reset-password`);
    cy.contains("h1", "Link inválido ou expirado", { timeout: 20000 }).should("be.visible");
    cy.contains("a", "Solicitar novo link").should("have.attr", "href").and("include", "/forgot-password");
    // O formulário de nova senha não aparece sem o link do e-mail.
    cy.contains("h1", "Criar nova senha").should("not.exist");
  });

  // AUTH-040
  it("recuperar senha barra e-mail inválido e oferece voltar ao login", () => {
    // Caminho do usuário: do login, pelo link "Esqueceu a senha?". (A abertura DIRETA de
    // /forgot-password num navegador sem cache trava ~20 s em "Iniciando sistema…" na 1ª
    // vez — achado de produto registrado em docs/PLANO_COBERTURA_CYPRESS.md.)
    cy.visit(`${baseUrl}/login`);
    cy.contains("h1", "Login", { timeout: 20000 }).should("be.visible");
    cy.contains("a", "Esqueceu a senha?").click();
    cy.location("pathname").should("include", "/forgot-password");
    cy.contains("h1", "Recuperar senha", { timeout: 20000 }).should("be.visible");
    cy.contains("button", "Enviar link de recuperação").click();
    cy.contains("E-mail inválido", { timeout: 20000 }).should("be.visible");
    cy.contains("h1", "Recuperar senha").should("be.visible"); // não avançou
    cy.contains("a", "Voltar para o login").click();
    cy.contains("h1", "Login", { timeout: 20000 }).should("be.visible");
  });

  // AUTH-041
  it("ativar conta sem o link do convite mostra link inválido", () => {
    cy.visit(`${baseUrl}/ativar-conta`);
    cy.contains("h2", "Link Inválido", { timeout: 20000 }).should("be.visible");
    cy.contains("Link de ativação inválido. Solicite um novo convite.").should("be.visible");
    cy.contains("button", "Ir para Login").click();
    cy.contains("h1", "Login", { timeout: 20000 }).should("be.visible");
  });
});
