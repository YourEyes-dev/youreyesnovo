/// <reference types="cypress" />

// =====================================================================
// Site institucional — diagnóstico psicossocial (isca do tráfego pago).
//
// Visitante SEM login: a raiz do site de teste mostra o site. Cada it()
// corresponde a um caso documentado (qa_casos_teste, nível e2e) ligado por
// qa_cobertura_e2e. Casos cobertos: SITE-001, SITE-002, SITE-003.
//
// Nada sai de verdade: a gravação do lead e as duas funções de servidor
// (meta-capi, hubspot-lead) são interceptadas e respondidas aqui. O teste
// confere O QUE a tela manda, não a Meta nem o HubSpot (esses são validados
// à mão, com o código de teste da Meta e um contato fictício).
// =====================================================================

describe("Site — diagnóstico psicossocial", () => {
  const baseUrl = String(Cypress.config("baseUrl") || "").replace(/\/$/, "");
  const urlAnuncio = `${baseUrl}/?utm_source=qa&utm_medium=cypress&utm_campaign=sst_qa&utm_content=cypress#diagnostico`;

  function responderDiagnostico() {
    cy.get("#diagnostico", { timeout: 30000 }).should("exist");
    cy.contains("button", "20 a 99", { timeout: 30000 }).click();
    cy.contains("button", "Serviços / Escritório").click();
    // 8 perguntas: responde "Não" em todas (índice alto, perfil crítico).
    for (let i = 0; i < 8; i++) {
      cy.contains("button", /^Não$/).click();
    }
    cy.get('input[placeholder="Seu nome"]').type("Robô QA Site");
    cy.get('input[placeholder="Nome da empresa"]').type("Empresa Staging LTDA");
    cy.get('input[placeholder="Ex.: Gestor de RH"]').type("Analista de RH");
    cy.get('input[placeholder="voce@empresa.com.br"]').type("robo.site@youreyes.local");
    cy.get('input[placeholder="(46) 99999-9999"]').type("46999990000");
    cy.contains("button", "Ver meu resultado").click();
  }

  beforeEach(() => {
    // Gravação do lead respondida aqui: o teste não deixa lixo no banco nem
    // esbarra na trava de 5 envios/10 min por acesso.
    cy.intercept("POST", "**/rest/v1/landing_leads*", { statusCode: 201, body: "" }).as("gravarLead");
  });

  it("SITE-001: conclusão envia o Lead ao servidor e o contato ao HubSpot com as UTMs da chegada, sem as respostas", () => {
    cy.intercept("POST", "**/functions/v1/meta-capi", { statusCode: 200, body: { enviado: false } }).as("capi");
    cy.intercept("POST", "**/functions/v1/hubspot-lead", { statusCode: 200, body: { enviado: false } }).as("hubspot");

    cy.visit(urlAnuncio);
    cy.get("#diagnostico", { timeout: 30000 }).should("exist");
    // Navegação que apaga a query: as UTMs precisam sobreviver (sessionStorage).
    cy.window().then((win) => win.history.replaceState(null, "", `${win.location.pathname}#diagnostico`));
    responderDiagnostico();

    cy.wait("@gravarLead").then(({ request }) => {
      const corpo = Array.isArray(request.body) ? request.body[0] : request.body;
      expect(corpo.diagnostico_resultado.origem.utm_source).to.eq("qa");
      expect(corpo.diagnostico_resultado.origem.utm_campaign).to.eq("sst_qa");
    });

    cy.wait("@capi").then(({ request }) => {
      const corpo = typeof request.body === "string" ? JSON.parse(request.body) : request.body;
      expect(corpo.event_name).to.eq("Lead");
      expect(String(corpo.event_id || ""), "event_id").to.have.length.greaterThan(0);
      expect(corpo.email).to.eq("robo.site@youreyes.local");
      expect(String(request.headers["content-type"])).to.match(/^text\/plain/);
    });

    cy.wait("@hubspot").then(({ request }) => {
      const corpo = typeof request.body === "string" ? JSON.parse(request.body) : request.body;
      expect(corpo.formulario).to.eq("site-diagnostico-psicossocial");
      expect(corpo.email).to.eq("robo.site@youreyes.local");
      expect(corpo.score).to.be.a("number");
      expect(corpo.angulo_dor).to.eq("sst");
      expect(corpo.fonte_origem).to.eq("qa / sst_qa / cypress");
      // LGPD: nenhuma resposta individual do questionário sai para o CRM.
      const texto = JSON.stringify(corpo);
      expect(texto).not.to.match(/respostas|q_inventario|q_canal|dimensoes/);
    });

    cy.contains("Seu resultado").should("be.visible");
  });

  it("SITE-002: fora do domínio de produção o Pixel da Meta não carrega", () => {
    let chamadasPixel = 0;
    cy.intercept("**/connect.facebook.net/**", (req) => {
      chamadasPixel += 1;
      req.reply({ statusCode: 204, body: "" });
    });
    cy.intercept("**/www.facebook.com/tr*", (req) => {
      chamadasPixel += 1;
      req.reply({ statusCode: 204, body: "" });
    });
    cy.visit(urlAnuncio);
    cy.get("#diagnostico", { timeout: 30000 }).should("exist");
    cy.window().then((win) => {
      expect(typeof (win as unknown as { fbq?: unknown }).fbq, "window.fbq").to.eq("undefined");
      expect(chamadasPixel, "chamadas ao Pixel").to.eq(0);
    });
  });

  it("SITE-003: falha no servidor da Meta ou do HubSpot não impede o resultado", () => {
    cy.intercept("POST", "**/functions/v1/meta-capi", { forceNetworkError: true }).as("capi");
    cy.intercept("POST", "**/functions/v1/hubspot-lead", { statusCode: 500, body: { error: "fora do ar" } }).as("hubspot");

    cy.visit(urlAnuncio);
    responderDiagnostico();

    cy.contains("Seu resultado", { timeout: 20000 }).should("be.visible");
    cy.contains("Falar com um especialista").should("be.visible");
    cy.contains("Não conseguimos registrar seus dados").should("not.exist");
  });
});
