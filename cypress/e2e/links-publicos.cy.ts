/// <reference types="cypress" />

// =====================================================================
// Links públicos (sem login) — Onda 1 do plano de cobertura.
//
// São as telas que o colaborador, o cliente e o parceiro abrem sozinhos, pelo
// link recebido por e-mail/WhatsApp: assinatura de contrato, férias, PDI,
// experiência, manual de função, ordem de serviço, aceite de documento,
// ouvidoria externa e entrevista guiada. Se uma delas quebra (tela branca,
// erro de rota, ErrorBoundary), ninguém percebe até chegar reclamação — e o
// link já foi enviado.
//
// O que se garante aqui: com um token que NÃO existe, cada tela monta e mostra
// o estado de "link inválido" próprio dela, sem derrubar a aplicação e sem
// pedir login. (O fluxo feliz de assinatura exige um link semeado e entra numa
// etapa seguinte.) Tudo sem sessão: nenhum it() faz login nem grava dado.
//
// Cada it() é ligado a um caso AUTH-05x documentado pela ponte qa_cobertura_e2e.
//
// ATENÇÃO — título do it(): a ponte no banco (migrations 20261021204922 e 20261021215223)
// guarda o título EXATO e em MINÚSCULA. Mudar um título aqui sem mudar a ponte reprova a
// guarda da esteira ("it() sem caso documentado"). Antes de commitar: npm run qa:pontes AUTH-05
// =====================================================================

describe("Links públicos com token inexistente", () => {
  const baseUrl = Cypress.config("baseUrl") as string;
  // UUID bem-formado que não existe: vale para colunas uuid e text, sem erro de cast.
  const TOKEN = "00000000-0000-4000-8000-0000000000e2";

  beforeEach(() => {
    cy.clearCookies();
    cy.clearLocalStorage();
  });

  const semQuebrar = () => {
    cy.contains("Algo deu errado").should("not.exist"); // ErrorBoundary
    cy.contains("h1", "Login").should("not.exist"); // link público não manda para o login
  };

  // AUTH-050
  it("aceite de documento com link inexistente mostra link inválido", () => {
    cy.visit(`${baseUrl}/aceite-documento/${TOKEN}`);
    cy.contains("Link inválido", { timeout: 30000 }).should("be.visible");
    semQuebrar();
  });

  // AUTH-051
  it("assinatura de contrato com link inexistente mostra contrato não encontrado", () => {
    cy.visit(`${baseUrl}/contrato-assinatura/${TOKEN}`);
    cy.contains("Contrato não encontrado", { timeout: 30000 }).should("be.visible");
    semQuebrar();
  });

  // AUTH-052
  it("assinar contrato de parceiro com link inexistente mostra link inválido", () => {
    cy.visit(`${baseUrl}/assinar-contrato/${TOKEN}`);
    cy.contains("Link inválido ou expirado.", { timeout: 30000 }).should("be.visible");
    semQuebrar();
  });

  // AUTH-053
  it("assinatura de férias com link inexistente mostra link inválido", () => {
    cy.visit(`${baseUrl}/ferias-assinatura/${TOKEN}`);
    cy.contains("Link inválido", { timeout: 30000 }).should("be.visible");
    semQuebrar();
  });

  // AUTH-054
  it("assinatura de PDI com link inexistente mostra link inválido", () => {
    cy.visit(`${baseUrl}/pdi-assinatura/${TOKEN}`);
    cy.contains("Link inválido", { timeout: 30000 }).should("be.visible");
    semQuebrar();
  });

  // AUTH-055
  it("assinatura de experiência com link inexistente mostra link inválido", () => {
    cy.visit(`${baseUrl}/experiencia-assinatura/${TOKEN}`);
    cy.contains("Link inválido ou expirado", { timeout: 30000 }).should("be.visible");
    semQuebrar();
  });

  // AUTH-056
  it("assinatura do manual de função com link inexistente mostra link inválido", () => {
    cy.visit(`${baseUrl}/manual-funcao/assinatura/${TOKEN}`);
    cy.contains("Link inválido.", { timeout: 30000 }).should("be.visible");
    semQuebrar();
  });

  // AUTH-057
  it("assinatura de ordem de serviço com link inexistente mostra link inválido", () => {
    cy.visit(`${baseUrl}/os/${TOKEN}`);
    cy.contains("Link inválido.", { timeout: 30000 }).should("be.visible");
    semQuebrar();
  });

  // AUTH-058
  it("ouvidoria externa com link inexistente mostra link inválido", () => {
    cy.visit(`${baseUrl}/ouvidoria-externa/${TOKEN}`);
    cy.contains(/Link inválido/, { timeout: 30000 }).should("be.visible");
    semQuebrar();
  });

  // AUTH-059
  it("entrevista guiada com link inexistente mostra link inválido", () => {
    cy.visit(`${baseUrl}/entrevista/${TOKEN}`);
    cy.contains("Link inválido", { timeout: 30000 }).should("be.visible");
    semQuebrar();
  });
});
