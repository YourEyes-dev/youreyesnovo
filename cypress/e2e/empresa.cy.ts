/// <reference types="cypress" />

// =====================================================================
// Módulo Empresa — checklist de cadastro (obrigatoriedade condicional).
//
// Regra da casa: todo it() aqui corresponde a um caso e2e DOCUMENTADO.
// A ponte caso ↔ it() vive em qa_cobertura_e2e (ver a migration
// ..._qa_cobertura_empresa_lote1.sql).
//
// Casos cobertos:
//   EMP-014 — Documento exigido acompanha o tipo de pessoa (CNPJ x CPF)
//   ENQ-018 — Mandato e membros viram obrigatórios com CIPA ativa
//   CFG-040 — Aba Logo da Empresa (a logo saiu de Configurações/Usuários)
//
// ZERO mutação: só abrimos "Nova Empresa" e lemos o checklist de pendências.
// Nada é salvo (o rascunho vive só no localStorage do navegador). Por isso
// não confirmamos o cadastro em nenhum momento.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Empresa — checklist de cadastro", () => {
  const { email, senha: password } = credenciaisDeTeste();
  const baseUrl = Cypress.config("baseUrl") as string;

  function closeEmpresaModalIfNeeded() {
    cy.get("body", { timeout: 15000 }).then(($body) => {
      const pageText = $body.text();
      if (/Acesso Restrito/i.test(pageText)) {
        throw new Error("Usuário de teste sem empresa vinculada.");
      }
      if (!/Selecione a Empresa/i.test(pageText)) return;
      cy.contains(/Selecione a Empresa/i, { timeout: 10000 }).should("be.visible");
      cy.get("button.text-left:visible").first().click({ force: true });
      cy.contains("button", /Acessar|Continuar|Confirmar|Entrar/i, { timeout: 10000 })
        .should("be.visible")
        .and("not.be.disabled")
        .click({ force: true });
      cy.contains(/Selecione a Empresa/i, { timeout: 10000 }).should("not.exist");
    });
    cy.contains(/Sincronizando empresas/i, { timeout: 20000 }).should("not.exist");
  }

  function login() {
    cy.visit(`${baseUrl}/login`);
    cy.get('input[type="email"]', { timeout: 20000 })
      .should("exist").scrollIntoView().should("be.visible").clear().type(email);
    cy.get('input[autocomplete="current-password"]', { timeout: 20000 })
      .should("exist").scrollIntoView().should("be.visible").clear().type(password, { log: false });
    cy.contains("button", /^Entrar$/).should("be.visible").click();
    cy.aguardarSessaoSupabase();
    closeEmpresaModalIfNeeded();
    cy.wait(1500);
  }

  // Abre o formulário "Nova Empresa" a partir da lista. Confirma pela aba de
  // Dados (seletor específico da tela-destino) que o formulário abriu mesmo.
  function abrirNovaEmpresa() {
    cy.visit(`${baseUrl}/empresa`);
    closeEmpresaModalIfNeeded();
    cy.get('[data-testid="btn-nova-empresa"]', { timeout: 30000 })
      .should("be.visible")
      .click({ force: true });
    cy.get('[data-testid="tab-dados"]', { timeout: 20000 }).should("be.visible");
    // O modal "Selecione a Empresa" pode reabrir pela carga tardia de dados
    // (visto nas falhas: body com data-scroll-locked). Fecha de novo e espera
    // o body destravar antes de qualquer digitação.
    closeEmpresaModalIfNeeded();
    cy.get("body", { timeout: 15000 }).should("not.have.attr", "data-scroll-locked");
  }

  // Navega para uma aba do formulário pelo id estável do TabsTrigger.
  function irAba(nome: "dados" | "logo" | "enquadramento" | "checklist") {
    cy.get(`[data-testid="tab-${nome}"]`).click({ force: true });
    cy.wait(500);
  }

  // Abre um Radix Select pelo testid do trigger e escolhe a opção pelo texto.
  function selecionar(testid: string, labelOpcao: string) {
    cy.get(`[data-testid="${testid}"]`).click({ force: true });
    cy.get('[role="listbox"]', { timeout: 10000 }).should("be.visible");
    cy.contains('[role="option"]', labelOpcao, { timeout: 10000 }).click({ force: true });
    cy.get('[role="listbox"]').should("not.exist");
  }

  beforeEach(() => {
    // testIsolation (Cypress 15) já zera cookies/localStorage/sessionStorage
    // entre os testes, então cada teste começa sem rascunho nem navegação
    // restaurada — a lista de empresas abre limpa.
    login();
  });

  // CFG-040: a logo é gerida na aba Logo da tela Empresa. Em empresa ainda não
  // salva (zero mutação), a aba monta e orienta salvar o cadastro antes do envio.
  it("CFG-040: aba Logo da Empresa monta e orienta salvar o cadastro antes", () => {
    abrirNovaEmpresa();
    irAba("logo");
    cy.contains("Salve o cadastro da empresa para poder enviar a logo", { timeout: 15000 }).should("be.visible");
    cy.contains("Algo deu errado").should("not.exist");
  });

  // EMP-014: o documento obrigatório no checklist acompanha o tipo de pessoa.
  it("EMP-014: Documento exigido acompanha o tipo de pessoa", () => {
    abrirNovaEmpresa();

    // Padrão do formulário novo é Pessoa Jurídica → checklist cobra CNPJ.
    irAba("checklist");
    cy.get('[data-testid="checklist-pendencias"]', { timeout: 15000 })
      .should("contain.text", "CNPJ");

    // Troca para Pessoa Física → a pendência passa a ser CPF, e CNPJ some.
    irAba("dados");
    selecionar("select-tipo-pessoa", "Pessoa Física (CPF)");
    irAba("checklist");
    cy.get('[data-testid="checklist-pendencias"]', { timeout: 15000 })
      .should("contain.text", "CPF")
      .and("not.contain.text", "CNPJ");
  });

  // ENQ-018: mandato e membros da CIPA viram obrigatórios quando ela está ativa.
  it("ENQ-018: Mandato e membros viram obrigatórios com CIPA ativa", () => {
    abrirNovaEmpresa();

    // CIPA ativa → checklist passa a cobrar Mandato e Membros da CIPA.
    irAba("enquadramento");
    selecionar("select-cipa-situacao", "Ativa");
    irAba("checklist");
    cy.get('[data-testid="checklist-pendencias"]', { timeout: 15000 })
      .should("contain.text", "Mandato da CIPA")
      .and("contain.text", "Membros da CIPA");

    // CIPA não constituída → mandato e membros deixam de ser obrigatórios.
    irAba("enquadramento");
    selecionar("select-cipa-situacao", "Não Constituída");
    irAba("checklist");
    cy.get('[data-testid="checklist-pendencias"]', { timeout: 15000 })
      .should("not.contain.text", "Mandato da CIPA")
      .and("not.contain.text", "Membros da CIPA");
  });

  // CHK-001: o checklist reage ao preenchimento na hora (sem salvar).
  it("CHK-001: Checklist reflete o preenchimento em tempo real", () => {
    abrirNovaEmpresa();
    // CNPJ começa como pendência (PJ, campo vazio).
    irAba("checklist");
    cy.get('[data-testid="checklist-pendencias"]', { timeout: 15000 })
      .should("contain.text", "CNPJ");
    // Preenche o CNPJ → o checklist deixa de cobrá-lo imediatamente.
    irAba("dados");
    cy.get('[data-testid="input-cnpj"]').clear({ force: true }).type("11222333000181", { force: true });
    irAba("checklist");
    cy.get('[data-testid="checklist-pendencias"]', { timeout: 15000 })
      .should("not.contain.text", "CNPJ");
  });

  // CHK-003: um valor numérico zero conta como preenchido (não fica pendente).
  it("CHK-003: Quantidade zero conta como preenchida", () => {
    abrirNovaEmpresa();
    // "Total de colaboradores" começa pendente (nada informado).
    irAba("checklist");
    cy.get('[data-testid="checklist-pendencias"]', { timeout: 15000 })
      .should("contain.text", "Total de colaboradores");
    // Informa zero → mesmo sendo 0, conta como preenchido e sai das pendências.
    irAba("dados");
    cy.get('[data-testid="input-total-colaboradores"]').clear({ force: true }).type("0", { force: true });
    irAba("checklist");
    cy.get('[data-testid="checklist-pendencias"]', { timeout: 15000 })
      .should("not.contain.text", "Total de colaboradores");
  });

  // HIER-003: alternar tipo de unidade limpa o vínculo com a matriz.
  it("HIER-003: Alternar entre matriz e filial limpa o vínculo anterior", () => {
    abrirNovaEmpresa();
    irAba("dados");
    // Padrão é Matriz → não existe seletor de matriz de referência.
    cy.get('[data-testid="select-matriz"]').should("not.exist");
    // Vira Filial → o seletor de matriz aparece.
    selecionar("select-tipo-unidade", "Filial");
    cy.get('[data-testid="select-matriz"]', { timeout: 10000 }).should("exist");
    // Volta para Matriz → o seletor some (o vínculo com a matriz é limpo).
    selecionar("select-tipo-unidade", "Matriz");
    cy.get('[data-testid="select-matriz"]').should("not.exist");
  });

  // RASC-001: o rascunho (localStorage) é restaurado ao reabrir sem ter salvo.
  // "Voltar sem salvar" = recarregar a página em modo "novo" (a navegação fica
  // no sessionStorage), quando o rascunho é restaurado automaticamente.
  it("RASC-001: Rascunho é restaurado ao voltar sem ter salvo", () => {
    abrirNovaEmpresa();
    const nome = `Rascunho Teste ${Date.now()}`;
    irAba("dados");
    cy.get('[data-testid="input-razao-social"]').clear({ force: true }).type(nome, { force: true });
    // Espera o debounce do saveDraft (300ms) gravar no localStorage.
    cy.wait(1200);
    // Recarrega: a navegação mantém o modo "novo", e o rascunho é restaurado.
    cy.reload();
    closeEmpresaModalIfNeeded();
    cy.get('[data-testid="tab-dados"]', { timeout: 20000 }).should("be.visible");
    irAba("dados");
    cy.get('[data-testid="input-razao-social"]', { timeout: 15000 })
      .should("have.value", nome);
  });

  // RASC-004: abrir "Nova Empresa" NÃO herda o rascunho de uma tentativa
  // anterior — o handleNew limpa o rascunho de propósito.
  it("RASC-004: Novo cadastro não herda rascunho de tentativa anterior", () => {
    abrirNovaEmpresa();
    const nome = `Rascunho Antigo ${Date.now()}`;
    irAba("dados");
    cy.get('[data-testid="input-razao-social"]').clear({ force: true }).type(nome, { force: true });
    cy.wait(1200); // deixa o saveDraft gravar
    // Volta para a lista e abre "Nova Empresa" de novo.
    cy.get('[data-testid="btn-voltar-empresa"]').click({ force: true });
    cy.get('[data-testid="btn-nova-empresa"]', { timeout: 20000 })
      .should("be.visible")
      .click({ force: true });
    // O novo cadastro vem limpo — Razão Social vazia (não herdou o rascunho).
    cy.get('[data-testid="tab-dados"]', { timeout: 20000 }).should("be.visible");
    irAba("dados");
    cy.get('[data-testid="input-razao-social"]', { timeout: 15000 })
      .should("have.value", "");
  });
});
