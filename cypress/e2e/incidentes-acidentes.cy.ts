/// <reference types="cypress" />

import { credenciaisDeTeste } from "../support/credenciais";

describe("Módulo Incidentes & Acidentes", () => {
  const { email, senha: password } = credenciaisDeTeste();
  const baseUrl = Cypress.config("baseUrl") as string;

  const texts = {
    modulo: "Incidentes & Acidentes",
    registrar: "Registrar Evento",
    guia: "Guia Rápido",
    tabs: ["Ocorrências", "Análise", "Indicadores", "Analytics", "Preditivo", "Cultura", "FAP", "Pirâmide"],
    categoria: "Quase queda",
    origem: "Comportamental",
    fator1: "Ritmo de trabalho acelerado / pressa",
    fator2: "Falta de pausas adequadas",
    agenteEsocial: "07.02 — Queda em mesmo nível",
  };

  function login() {
    cy.visit(`${baseUrl}/login`);
    cy.get('input[type="email"]', { timeout: 20000 })
      .should("exist")
      .scrollIntoView()
      .should("be.visible")
      .clear()
      .type(email);
    cy.get('input[autocomplete="current-password"]', { timeout: 20000 })
      .should("exist")
      .scrollIntoView()
      .should("be.visible")
      .clear()
      .type(password, { log: false });
    cy.contains("button", /^Entrar$/).click();
    // Espera a autenticação persistir de verdade (ver support/e2e.ts). O
    // antigo should("not.eq","/login") passava na hora sob o subcaminho.
    cy.aguardarSessaoSupabase();
    cy.wait(1500);
  }

  function goToModulo() {
    cy.visit(`${baseUrl}/incidentes-acidentes`);
    cy.contains("h1", texts.modulo, { timeout: 20000 }).should("be.visible");
  }

  function openTab(label: string) {
    // scrollIntoView + force: a lista de abas rola na horizontal e uma aba fora
    // da viewport não é "visível"/acionável — o clique falhava por isso.
    cy.contains('[role="tab"]', label).scrollIntoView().click({ force: true });
    // Re-query after click to avoid detached DOM from React re-render
    cy.contains('[role="tab"]', label).should("have.attr", "aria-selected", "true");
  }

  function openRadixSelectByText(triggerText: string) {
    cy.contains('button[role="combobox"]', triggerText).should("be.visible").click();
  }

  function selectRadixOption(optionText: string) {
    // Sem should("be.visible") antes do force: o portal do Radix anima ao abrir
    // e a asserção de visibilidade falhava durante a animação. cy.contains já
    // espera o item existir no DOM; o force ignora a acionabilidade.
    cy.contains('[role="option"], [data-radix-collection-item], [cmdk-item]', optionText)
      .click({ force: true });
  }

  function openNthCombobox(index: number) {
    cy.get('button[role="combobox"]').eq(index).should("be.visible").click({ force: true });
  }

  function selectCmdkOption(searchPlaceholder: string, value: string) {
    cy.get(`input[placeholder="${searchPlaceholder}"]`).should("be.visible").clear().type(value);
    cy.contains('[cmdk-item]', value).should("be.visible").click({ force: true });
  }

  function nextStep() {
    // Escopa ao diálogo e amplia o texto: o /^Próximo$/ exato não casava
    // (o botão do wizard pode ter ícone/variação de rótulo), e o global
    // pegava botões fora do diálogo.
    cy.get('[role="dialog"]')
      .contains("button", /Próximo|Avançar|Continuar/i)
      .click({ force: true });
  }

  function previousStep() {
    // O botão é "<ChevronLeft/> Anterior" — o texto tem um espaço à esquerda do
    // ícone, então /^Anterior$/ (ancorado) nunca casava. Regex frouxa + escopo
    // ao diálogo + force (o footer pode estar sob o scroll-lock por um instante).
    cy.get('[role="dialog"]').contains("button", /Anterior/i).should("be.visible").click({ force: true });
  }

  function fillTipoELocal(setor = "Administrativo", local = "Próximo ao refeitório", turno = "1º Turno") {
    cy.get('input[type="date"]').first().should("be.visible");
    // Trocar o tipo (incidente↔acidente) troca o array de passos e re-renderiza
    // o passo 1. Sem deixar assentar, o clique no combobox de Estabelecimento
    // caía no meio do re-render e a busca "Buscar estabelecimento..." nunca
    // abria (era a causa das falhas dos dois casos de ACIDENTE).
    cy.wait(600);
    // Combobox de Estabelecimento ESCOPADO ao diálogo: openNthCombobox global
    // pegava o 1º button[role=combobox] da página (os filtros da aba, atrás do
    // overlay), então "Buscar estabelecimento..." nunca abria. Reabre se o
    // primeiro clique não trouxe o campo de busca.
    cy.get('[role="dialog"]').find('button[role="combobox"]').eq(0).click({ force: true });
    cy.get("body").then(($b) => {
      if (!$b.find('input[placeholder="Buscar estabelecimento..."]').length) {
        cy.get('[role="dialog"]').find('button[role="combobox"]').eq(0).click({ force: true });
      }
    });
    cy.get('input[placeholder="Buscar estabelecimento..."]', { timeout: 15000 })
      .should("be.visible")
      .type("Matriz", { force: true });

    cy.get("body").then(($body) => {
      if ($body.find('[cmdk-item]').length > 0) {
        cy.get('[cmdk-item]').first().click({ force: true });
      } else {
        cy.get('input[placeholder="Buscar estabelecimento..."]').type("{enter}", { force: true });
      }
    });

    cy.get('[role="dialog"]').find('button[role="combobox"]').eq(1).click({ force: true });
    cy.get('input[placeholder="Buscar setor..."]').should("be.visible").clear().type(setor);
    cy.get("body").then(($body) => {
      if ($body.find('[cmdk-item]').length > 0) {
        cy.contains('[cmdk-item]', setor).click({ force: true });
      } else {
        cy.get('input[placeholder="Buscar setor..."]').type("{enter}", { force: true });
      }
    });

    // force: o scroll-lock do Radix (aberto pelos comboboxes acima) deixa o
    // body com pointer-events:none por um instante e o clear/type é recusado.
    cy.get('input[placeholder*="Linha 3"]').clear({ force: true }).type(local, { force: true });
    cy.contains("label", "Turno").parent().within(() => {
      cy.get('button[role="combobox"]').click({ force: true });
    });
    selectRadixOption(turno);
  }

  function fillEnvolvidosManual(nome: string, cargo: string) {
    // O Select "Colaborador Principal" já vem em "Digitar manualmente"
    // (value default "manual"), então os inputs abaixo já estão renderizados.
    // O placeholder "Selecione do cadastro ou digite" nunca aparece nesse
    // estado, então abrir o Select por esse texto travava o passo.
    cy.get('input[placeholder="Nome completo"]').clear().type(nome);
    cy.get('input[placeholder="Ex: Operador"]').clear().type(cargo);
    cy.get('textarea[placeholder*="testemunhas"]').clear().type("Maria teste, Pedro teste");
  }

  function fillClassificacao(gravidade = "Baixa") {
    cy.contains("button", texts.categoria).click();
    cy.contains("button", texts.origem).click();
    cy.contains("button", gravidade).click();
  }

  function fillGravidadeAcidente() {
    cy.contains("button", "Lesão leve").click();
    cy.contains("button", "Não houve afastamento").click();
    cy.contains("button", "Ambulatorial").click();
  }

  function fillClassificacaoLegal() {
    cy.contains("button", "Típico").click();
    cy.get('input[placeholder*="S60.0"]').clear().type("S60.0");
    cy.get('input[type="number"]').clear().type("3");
    cy.contains("button", "Confirmado").click();
    cy.get("select").select(texts.agenteEsocial);
  }

  function fillCat(emitir = true) {
    if (emitir) {
      cy.get("#cat_emitida").click({ force: true });
      cy.get('input[placeholder="Número"]').clear().type(`CAT-${Date.now()}`);
      cy.get('input[type="date"]').last().type("2026-03-31");
      cy.contains("button", "Inicial").click();
      cy.get("textarea").last().type("CAT emitida para teste automatizado.");
    } else {
      cy.contains("Marque acima se a CAT foi emitida").should("be.visible");
    }
  }

  function fillDescricao(sufixo: string) {
    cy.get("textarea").first().clear().type(`Descrição automatizada do evento ${sufixo}.`);
    cy.get("textarea").eq(1).clear().type(`Percepção inicial da causa do evento ${sufixo}.`);
  }

  function fillFatores() {
    cy.contains("button", texts.fator1).click();
    cy.contains("button", texts.fator2).click();
  }

  function submitForm() {
    // Escopar ao diálogo: existem DOIS botões "Registrar Evento" — o do header
    // (sempre no DOM, coberto pelo overlay do Dialog) e o do rodapé do form.
    // cy.contains global pegava o do header e o clique falhava (coberto).
    cy.get('[role="dialog"]')
      .contains("button", /Registrar Evento|Salvar Alterações/i)
      .click();
    cy.contains("Registrar Novo Evento SST").should("not.exist");
  }

  function openRegistrarEvento() {
    // Aqui ainda NÃO há diálogo aberto, então o único "Registrar Evento" é o do
    // header — clicar nele abre o form. O título é asserido dentro do diálogo.
    cy.contains("button", texts.registrar).should("be.visible").click();
    // "exist" em vez de "be.visible": o h2 do DialogTitle (Radix) chega a montar,
    // mas a sequência de re-renders (Error fetching user data) reinicia a animação
    // do portal e a asserção de visibilidade piscava. Basta o diálogo ter aberto.
    cy.get('[role="dialog"]', { timeout: 15000 })
      .contains(/Registrar Novo Evento SST|Editar Evento/)
      .should("exist");
  }

  function createIncidenteManual() {
    openRegistrarEvento();
    cy.contains("button", "Incidente").click({ force: true });
    fillTipoELocal("Administrativo", `Próximo ao refeitório ${Date.now()}`, "1º Turno");
    nextStep();
    fillEnvolvidosManual(`João Incidente ${Date.now()}`, "Operador");
    nextStep();
    fillClassificacao("Baixa");
    nextStep();
    fillDescricao("incidente");
    nextStep();
    fillFatores();
    submitForm();
  }

  function createAcidenteManual(emitirCat = true) {
    openRegistrarEvento();
    cy.contains("button", "Acidente").click({ force: true });
    fillTipoELocal("Administrativo", `Área de produção ${Date.now()}`, "2º Turno");
    nextStep();
    fillEnvolvidosManual(`Maria Acidente ${Date.now()}`, "Auxiliar");
    nextStep();
    fillClassificacao("Alta");
    nextStep();
    fillGravidadeAcidente();
    nextStep();
    fillClassificacaoLegal();
    nextStep();
    fillCat(emitirCat);
    nextStep();
    fillDescricao("acidente");
    nextStep();
    fillFatores();
    submitForm();
  }

  function ensureAtLeastOneRow() {
    openTab("Ocorrências");
    cy.get("body").then(($body) => {
      if ($body.text().includes("Nenhum evento encontrado.")) {
        createIncidenteManual();
      }
    });
    cy.get("tbody tr", { timeout: 20000 }).its("length").should("be.gte", 1);
  }

  beforeEach(() => {
    login();
    goToModulo();
  });

  it("carrega o módulo e todas as abas principais", () => {
    cy.contains("button", texts.guia).should("be.visible");
    cy.contains("button", texts.registrar).should("be.visible");

    texts.tabs.forEach((tab) => {
      openTab(tab);
    });
  });

  it("aplica filtros da aba ocorrências", () => {
    openTab("Ocorrências");
    // force:true por causa do scroll-lock do Radix (body pointer-events:none
    // herdado de um diálogo/combobox anterior) — padrão da suíte.
    cy.get('input[placeholder="Buscar por código, nome, setor..."]').clear({ force: true }).type("Administrativo", { force: true });

    openNthCombobox(0);
    selectRadixOption("Incidentes");

    openNthCombobox(1);
    selectRadixOption("Em Aberto");

    cy.get('button[role="combobox"]').then(($buttons) => {
      if ($buttons.length > 3) {
        openNthCombobox(3);
        selectRadixOption("1º Turno");
      }
    });

    cy.get('input[type="date"]').eq(0).clear({ force: true }).type("2026-03-01", { force: true });
    cy.get('input[type="date"]').eq(1).clear({ force: true }).type("2026-03-31", { force: true });
  });

  it("cadastra um incidente com colaborador manual", () => {
    createIncidenteManual();
    cy.contains("Nenhum evento encontrado.").should("not.exist");
  });

  it("cadastra um acidente com CAT emitida", () => {
    createAcidenteManual(true);
    cy.contains("Nenhum evento encontrado.").should("not.exist");
  });

  it("cadastra um acidente sem CAT emitida", () => {
    createAcidenteManual(false);
    cy.contains("Nenhum evento encontrado.").should("not.exist");
  });

  it("abre detalhes por linha, volta e usa ações do detalhe", () => {
    ensureAtLeastOneRow();
    cy.get("tbody tr").first().click();

    cy.contains("button", "Voltar").should("be.visible");
    cy.contains("button", /Baixar Relatório|Baixar Relatório CAT/i).should("be.visible");
    cy.contains("button", "Criar Ação Vinculada").should("be.visible");

    cy.get("body").then(($body) => {
      if ($body.text().includes("Concluir Evento")) {
        cy.contains("button", "Concluir Evento").click();
      }
    });

    cy.contains("button", "Criar Ação Vinculada").click();
    cy.contains("button", "Voltar").click();
    cy.contains("h1", texts.modulo).should("be.visible");
  });

  it("abre edição pela tabela", () => {
    ensureAtLeastOneRow();
    cy.get('tbody tr').first().within(() => {
      cy.get('button[title="Editar"]').click({ force: true });
    });
    cy.contains("Editar Evento").should("be.visible");
    // A edição abre no PRIMEIRO passo (Tipo & Local), onde ainda não existe o
    // botão "Anterior" (só aparece a partir do passo 2). Chamar previousStep
    // aqui estourava. Avança um passo e volta — exercita a navegação nos dois
    // sentidos sem depender de estar num passo intermediário.
    nextStep();
    previousStep();
    cy.contains("Editar Evento").should("be.visible");
    cy.get('body').type('{esc}');
  });

  it("acessa a aba pirâmide, muda filtros e abre camadas", () => {
    openTab("Pirâmide");

    openNthCombobox(0);
    selectRadixOption("Setor");

    cy.get('button[role="combobox"]').then(($buttons) => {
      if ($buttons.length > 1) {
        openNthCombobox(1);
        cy.get("body").then(($body) => {
          if ($body.text().includes("Administrativo")) {
            selectRadixOption("Administrativo");
          } else if ($body.text().includes("Todos")) {
            selectRadixOption("Todos");
          }
        });
      }
    });

    cy.contains("button", "Desvio").click({ force: true });
    cy.get('body').type('{esc}');

    [
      "Óbitos / Graves",
      "Acidentes c/ afastamento",
      "Acidentes s/ afastamento",
      "Incidentes / Quase-acid.",
      "Desvios de Segurança",
    ].forEach((layer) => {
      cy.contains("button", layer).click({ force: true });
      cy.get('body').type('{esc}');
    });
  });

  it("abre o guia rápido", () => {
    cy.contains("button", texts.guia).click();
    // Assere DENTRO do diálogo: o regex amplo /...|Incidentes/i casava primeiro
    // o link "Incidentes & Acidentes" do menu lateral (que pode estar fora da
    // viewport) e falhava o should("be.visible").
    cy.get('[role="dialog"]', { timeout: 10000 })
      .contains(/Guia Rápido/i)
      .should("exist");
    cy.get('body').type('{esc}');
  });
});