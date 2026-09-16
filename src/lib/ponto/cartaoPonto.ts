/**
 * Cartão Ponto — leiaute clássico de cartão ponto (o mesmo modelo que o RH
 * recebe do contador), reproduzido com a identidade visual do YourEyes.
 *
 * Blocos, na ordem do modelo:
 *   1. Cabeçalho da marca (faixa navy + logo) e faixa "CARTÃO PONTO".
 *   2. Identificação do empregador e do empregado.
 *   3. Corpo dia a dia: Data | Sem | Hor | Marcações | H.D. H.N. H.E. A.N.
 *      H.C. H.A. F.N. F.J.
 *   4. Totalização do resumo diário.
 *   5. Resumo de Horas do Mês e Resumo do Banco de Horas.
 *   6. Legenda das siglas e bloco de ciência/assinaturas.
 *
 * Uma página (ou mais, se o mês transbordar) por colaborador.
 */
import type jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import { MARCA, desenharRodape } from "./pdfMarca";
import { formatarHoraRelogio } from "./formatoHoras";

export interface CartaoMarcacao {
  hora: string;
  /** O = original do colaborador, I/A = incluída manualmente pelo RH. */
  origem: "O" | "A";
}

export interface CartaoDia {
  dia: string; // yyyy-MM-dd
  trabalhado_min: number;
  jornada_min: number;
  saldo_min: number;
  protegido: boolean;
  equalizacao: boolean;
  excedente_retido_min: number;
  marcacoes: CartaoMarcacao[];
  /**
   * Súmula 338, III do TST / Portaria MTP 671/2021: quando o intervalo do dia
   * não foi batido e existe pré-assinalação vigente, o espelho precisa dizer
   * isso — é o que sustenta a validade da jornada de duas batidas. Opcional:
   * dia sem declaração não traz nada.
   */
  intervalo_origem?: "marcado" | "pre_assinalado" | null;
  intervalo_pre_assinalado_min?: number | null;
  /**
   * Dia com marcação sem par (ou com ajuste em aberto). A apuração não gera
   * débito nesses dias — a falha de registro é responsabilidade do empregador
   * (CLT art. 74, §2º; Súmula 338 do TST) —, então o cartão precisa dizer que
   * o dia está pendente em vez de imprimir um zero sem explicação.
   */
  pendencia?: boolean;
  /**
   * Dia declarado como folga compensatória. O débito vem da compensação
   * registrada no banco, não de uma ausência inferida — e o cartão precisa
   * dizer isso: é o que distingue, para quem assina, folga acordada de falta
   * (Súmula 338 do TST).
   */
  folga_compensatoria?: boolean;
}

export interface CartaoEmpregador {
  razaoSocial: string;
  cnpj?: string | null;
  endereco?: string | null;
  cidade?: string | null;
  uf?: string | null;
}

export interface CartaoEmpregado {
  nome: string;
  cpf?: string | null;
  matricula?: string | null;
  cargo?: string | null;
  setor?: string | null;
  admissao?: string | null;
  categoria?: string | null;
  horarios?: string | null;
}

export interface CartaoBanco {
  saldoAnterior: number;
  creditos: number;
  debitos: number;
  compensados: number;
  saldoAtual: number;
  /**
   * Existe instrumento de compensação vigente? Com ele, a sobra do dia vai
   * para o banco e vale 1 por 1 (CLT art. 59, §2º). Sem ele não há banco: as
   * horas são devidas em dinheiro, com adicional (§1º). É o que decide o
   * rótulo impresso em cada dia. Ausente = trata como banco, que é o
   * comportamento de quem usa o módulo.
   */
  temRegime?: boolean;
}

export interface CartaoPontoInput {
  empregador: CartaoEmpregador;
  empregado: CartaoEmpregado;
  periodo: string;
  emissao: string;
  dias: CartaoDia[];
  banco?: CartaoBanco | null;
  /** false = não desenhar o painel de banco de horas (folha sem banco). */
  incluirBanco?: boolean;
  logoDataUrl?: string | null;
}

const DIAS_SEMANA = ["DOM", "SEG", "TER", "QUA", "QUI", "SEX", "SAB"];

const diaSemana = (iso: string) => {
  const [a, m, d] = iso.split("-").map(Number);
  return DIAS_SEMANA[new Date(a, m - 1, d).getDay()];
};
const dataCurta = (iso: string) => {
  const [, m, d] = iso.split("-");
  return `${d}/${m}`;
};
const hm = (min: number) => {
  if (!min || min <= 0) return "";
  const h = Math.floor(min / 60);
  const m = min % 60;
  return `${h}:${String(m).padStart(2, "0")}`;
};

/**
 * Marcações em uma única linha (até 4 batidas). Só quebra em pares quando
 * o dia tem 5+ batidas — assim cada dia ocupa uma única linha da tabela e o
 * cartão inteiro cabe em uma página.
 */
const marcacoesTexto = (marcacoes: CartaoMarcacao[], d?: CartaoDia) => {
  const tokens = marcacoes.map((m) => `${m.hora}-${m.origem === "A" ? "I" : "O"}`);
  const linhas: string[] = [];
  if (tokens.length <= 4) {
    linhas.push(tokens.join(" "));
  } else {
    for (let i = 0; i < tokens.length; i += 4) {
      linhas.push(tokens.slice(i, i + 4).join(" "));
    }
  }
  // Pré-assinalação: o intervalo não foi batido, foi declarado. O espelho
  // precisa dizer isso (Súmula 338, III do TST), e diz ao LADO das marcações
  // do dia — não numa linha própria.
  //
  // A linha própria custava uma linha extra em CADA dia do mês: num mês de 31
  // dias, dobrava a altura da tabela e estourava o espaço reservado para o
  // rodapé, que só previa a linha extra da legenda. O resultado era o bloco de
  // legenda e assinaturas impresso POR CIMA do resumo de horas. O sentido é o
  // mesmo; o custo de espaço, um quinto.
  if (d?.intervalo_origem === "pre_assinalado") {
    const min = d.intervalo_pre_assinalado_min || 0;
    const nota = `Int. ${min ? `${hm(min)} ` : ""}(P)`;
    const ultima = linhas.length > 0 ? linhas[linhas.length - 1] : "";
    // Dia sem batida (sábado, DSR) traz só a nota, sem separador solto.
    if (ultima === "") linhas[linhas.length > 0 ? linhas.length - 1 : 0] = nota;
    else linhas[linhas.length - 1] = `${ultima}  ·  ${nota}`;
    if (linhas.length === 0) linhas.push(nota);
  }
  return linhas.join("\n");
};


/**
 * Colunas H.C./H.A./F.N./F.J. e o rótulo da ocorrência, na lógica do modelo.
 * `temRegimeBanco` diz se existe instrumento de compensação vigente: com ele a
 * sobra vai para o banco (1:1); sem ele não há banco, e as horas são devidas
 * em dinheiro, com adicional.
 */
function classificarDia(d: CartaoDia, temRegimeBanco: boolean) {
  const domingo = diaSemana(d.dia) === "DOM";
  const semJornada = d.jornada_min === 0;
  const semTrabalho = d.trabalhado_min === 0;

  let ocorrencia = "";
  let hc = 0;
  let ha = 0;
  let fn = 0;
  let fj = 0;
  let he = 0;

  if (d.folga_compensatoria) {
    // A folga já debitou o banco pela compensação registrada; contar de novo
    // aqui debitaria a mesma tarde duas vezes.
    ocorrencia = d.trabalhado_min > 0
      ? "Folga compensatória (meio período)"
      : "Folga compensatória";
  } else if (d.pendencia) {
    // Nem crédito nem débito: o dia não fecha enquanto a marcação não for
    // completada. Imprimir horas aqui daria ares de conta fechada a um
    // registro que o próprio sistema sabe estar pela metade.
    ocorrencia = "Pendência — marcação incompleta";
  } else if (d.equalizacao) {
    ocorrencia = "Compensado";
    hc = d.trabalhado_min;
  } else if (d.protegido && semTrabalho) {
    ocorrencia = "Justificado";
    fj = d.jornada_min;
  } else if (semTrabalho && !semJornada) {
    ocorrencia = "Falta";
    fn = d.jornada_min;
  } else if (semTrabalho && domingo) {
    ocorrencia = "DSR";
  } else if (semTrabalho) {
    ocorrencia = semJornada ? "Sem jornada" : "";
  } else if (d.saldo_min > 0) {
    he = d.saldo_min;
    // CLT art. 59: a hora COMPENSADA no banco é trocada na exata medida, uma
    // por uma (§2º); o adicional de no mínimo 50% pertence à hora PAGA (§1º),
    // e 100% em domingo e feriado (Súmula 146 do TST). Escrever um percentual
    // ao lado de um crédito de 1 por 1 promete no documento o que a conta não
    // faz — e é o documento que o trabalhador assina.
    ocorrencia = temRegimeBanco
      ? "Soma Banco Horas (1:1)"
      : `Hora extra ${domingo || semJornada ? "100%" : "50%"}`;
  } else if (d.saldo_min < 0) {
    ha = -d.saldo_min;
    // A mesma moeda do lado positivo: com regime de banco vigente, o déficit
    // diminui o banco; SEM regime não há banco a diminuir — é atraso ou saída
    // antecipada a descontar (ou a compensar num acordo). Dizer "Diminui Banco
    // Horas" quando o resumo do banco mostra débito 0:00 afirma no documento um
    // movimento que não aconteceu, e o documento é o que o trabalhador assina
    // (Súmula 338 do TST: o controle tem de sustentar o que declara).
    ocorrencia = temRegimeBanco
      ? "Diminui Banco Horas"
      : "Atraso / saída antecipada";
  } else {
    ocorrencia = "Trabalhando";
  }

  if (d.excedente_retido_min > 0) ocorrencia = "Excedente retido";
  return { ocorrencia, hc, ha, fn, fj, he };
}

/** Altura total da faixa de marca (banda + fio). */
const ALTURA_FAIXA = 19;

function faixaTitulo(doc: jsPDF, input: CartaoPontoInput, pagina: number) {
  const pageW = doc.internal.pageSize.getWidth();

  doc.setFillColor(...MARCA.navy);
  doc.rect(0, 0, pageW, 18, "F");
  const fio = 1.1;
  doc.setFillColor(...MARCA.azul);
  doc.rect(0, 18, pageW * 0.55, fio, "F");
  doc.setFillColor(...MARCA.verde);
  doc.rect(pageW * 0.55, 18, pageW * 0.3, fio, "F");
  doc.setFillColor(...MARCA.laranja);
  doc.rect(pageW * 0.85, 18, pageW * 0.15, fio, "F");

  let x = 12;
  if (input.logoDataUrl) {
    try {
      doc.setFillColor(...MARCA.branco);
      doc.roundedRect(11, 3, 12, 12, 1.8, 1.8, "F");
      doc.addImage(input.logoDataUrl, "PNG", 12.2, 4.2, 9.6, 9.6);
      x = 26;
    } catch {
      /* sem logo */
    }
  }

  doc.setTextColor(...MARCA.branco);
  doc.setFont("helvetica", "bold");
  doc.setFontSize(11);
  doc.text("CARTÃO PONTO", x, 8.5);
  doc.setFont("helvetica", "normal");
  doc.setFontSize(6.6);
  doc.setTextColor(200, 214, 232);
  doc.text("YourEyes · Gestão de Jornada · Portaria 671/2021 MTP", x, 13.5);

  doc.setFont("helvetica", "bold");
  doc.setFontSize(8);
  doc.setTextColor(...MARCA.branco);
  doc.text(`Período: ${input.periodo}`, pageW - 12, 8, { align: "right" });
  doc.setFont("helvetica", "normal");
  doc.setFontSize(6.6);
  doc.setTextColor(200, 214, 232);
  doc.text(`Emissão: ${input.emissao}   ·   Pág. ${pagina}`, pageW - 12, 13.5, { align: "right" });
}

/** Bloco de identificação (empregador + empregado). Devolve o Y final. */
function blocoIdentificacao(doc: jsPDF, input: CartaoPontoInput) {
  const pageW = doc.internal.pageSize.getWidth();
  const x = 12;
  const largura = pageW - 24;
  const topo = ALTURA_FAIXA + 3;
  const altura = 28;

  doc.setFillColor(248, 250, 252);
  doc.setDrawColor(226, 232, 240);
  doc.setLineWidth(0.3);
  doc.roundedRect(x, topo, largura, altura, 1.5, 1.5, "FD");

  const { empregador: er, empregado: eo } = input;

  const colX = [0, largura * 0.42, largura * 0.68];
  const colW = [largura * 0.42 - 6, largura * 0.26 - 6, largura * 0.32 - 6];

  const linha = (
    y: number,
    campos: Array<[string, string | null | undefined]>,
    maxLinhas = 1,
  ) => {
    campos.forEach(([rotulo, valor], i) => {
      if (!valor) return;
      const cx = x + 3 + colX[i];
      doc.setFont("helvetica", "normal");
      doc.setFontSize(5.9);
      doc.setTextColor(...MARCA.cinza);
      doc.text(rotulo.toUpperCase(), cx, y);
      doc.setFont("helvetica", "bold");
      doc.setFontSize(7);
      doc.setTextColor(...MARCA.navy);
      const linhas = doc.splitTextToSize(String(valor), colW[i]).slice(0, maxLinhas);
      doc.text(linhas, cx, y + 3.3, { lineHeightFactor: 1.1 });
    });
  };

  // A TERCEIRA COLUNA É DO EMPREGADO, não da empresa.
  //
  // "Atividade" (o CNAE da empresa) era o único item de empresa nessa coluna,
  // enquanto cargo e departamento — que quem lê o cartão procura primeiro —
  // ficavam numa linha cinza de 6,4pt FORA da caixa. Agora a coluna 3 é
  // uniforme: Cargo / Departamento / Admissão.
  //
  // A geometria não muda (mesma altura, três linhas, mesmo fio separador),
  // então o cálculo de compressão da tabela mais abaixo não é afetado e o
  // cartão não corre risco de virar duas páginas.
  linha(topo + 4, [
    ["Empregador", er.razaoSocial],
    ["CNPJ", er.cnpj],
    ["Cargo", eo.cargo],
  ]);
  linha(topo + 12, [
    ["Endereço", er.endereco],
    ["Cidade / UF", [er.cidade, er.uf].filter(Boolean).join(" - ") || null],
    ["Departamento", eo.setor],
  ]);

  doc.setDrawColor(226, 232, 240);
  doc.line(x + 2, topo + 17.5, x + largura - 2, topo + 17.5);

  linha(topo + 21, [
    ["Empregado", eo.nome],
    ["CPF", eo.cpf],
    ["Admissão", eo.admissao],
  ]);

  const y2 = topo + altura + 4;
  doc.setFont("helvetica", "normal");
  doc.setFontSize(6.4);
  doc.setTextColor(...MARCA.cinza);
  // Cargo e Setor saíram daqui: subiram para a caixa. Categoria desceu para
  // cá, no lugar deles — continua sendo informação útil, só não é a primeira
  // que se procura.
  const rodapeIdent = [
    eo.categoria ? `Categoria: ${eo.categoria}` : null,
    eo.matricula ? `Matrícula: ${eo.matricula}` : null,
    eo.horarios ? `Horários: ${eo.horarios}` : null,
  ].filter(Boolean).join("   ·   ");
  if (rodapeIdent) doc.text(rodapeIdent, x, y2 - 1.5);

  return y2 + 1;
}

/**
 * Desenha o cartão ponto de um colaborador no documento informado.
 * O chamador é responsável por criar/paginar o `doc`.
 */
export function desenharCartaoPonto(doc: jsPDF, input: CartaoPontoInput) {
  const pageW = doc.internal.pageSize.getWidth();
  let pagina = 1;

  faixaTitulo(doc, input, pagina);
  const inicio = blocoIdentificacao(doc, input);

  const totais = { hd: 0, hn: 0, he: 0, hc: 0, ha: 0, fn: 0, fj: 0 };
  const corpo = input.dias.map((d) => {
    const k = classificarDia(d, input.banco?.temRegime !== false);
    totais.hd += d.trabalhado_min;
    totais.hn += d.jornada_min;
    totais.he += k.he;
    totais.hc += k.hc;
    totais.ha += k.ha;
    totais.fn += k.fn;
    totais.fj += k.fj;
    return [
      dataCurta(d.dia),
      diaSemana(d.dia),
      marcacoesTexto(d.marcacoes, d),
      k.ocorrencia,
      hm(d.trabalhado_min),
      hm(d.jornada_min),
      hm(k.he),
      "",
      hm(k.hc),
      hm(k.ha),
      hm(k.fn),
      hm(k.fj),
    ];
  });

  const pageH = doc.internal.pageSize.getHeight();

  // Espaço reservado abaixo da tabela para que o cartão de cada colaborador
  // caiba em UMA única página: painel de horas (30,4) + faixa de banco (17)
  // + legenda (17 — três linhas, com a do intervalo pré-assinalado) +
  // declaração e assinaturas (30) + rodapé institucional (14). A tabela se
  // comprime para caber no que sobra — nunca o contrário.
  const RESERVA_RODAPE = 111;
  const espacoTabela = pageH - 14 - inicio - RESERVA_RODAPE;


  // Linhas efetivas: dias com 5+ batidas ocupam mais de uma linha.
  const linhasEfetivas = corpo.reduce(
    (acc, l) => acc + String(l[2]).split("\n").length,
    0,
  ) + 2; // cabeçalho + totalização
  const alturaLinha = espacoTabela / Math.max(linhasEfetivas, 1);
  const padding = alturaLinha < 4.4 ? 0.7 : 1.2;
  const fonte = Math.min(7, Math.max(4.6, (alturaLinha - 2 * padding) / 0.42));

  autoTable(doc, {
    startY: inicio,
    theme: "grid",
    head: [["Data", "Sem", "Marcações", "Ocorrência", "H.D.", "H.N.", "H.E.", "A.N.", "H.C.", "H.A.", "F.N.", "F.J."]],
    body: corpo.length > 0 ? corpo : [["", "", "Sem dias apurados", "", "", "", "", "", "", "", "", ""]],
    foot: [[
      "Totalização", "", "", "Resumo diário",
      hm(totais.hd), hm(totais.hn), hm(totais.he), "",
      hm(totais.hc), hm(totais.ha), hm(totais.fn), hm(totais.fj),
    ]],
    styles: {
      font: "helvetica",
      fontSize: fonte,
      cellPadding: { top: padding, bottom: padding, left: 1, right: 1 },
      lineColor: [226, 232, 240],
      lineWidth: 0.15,
      textColor: [30, 41, 59],
      overflow: "linebreak",
      valign: "middle",
    },
    headStyles: {
      fillColor: MARCA.azul,
      textColor: MARCA.branco,
      fontStyle: "bold",
      fontSize: fonte,
      halign: "center",
    },
    footStyles: {
      fillColor: MARCA.cinzaClaro,
      textColor: MARCA.navy,
      fontStyle: "bold",
      fontSize: fonte,
      halign: "right",
    },
    alternateRowStyles: { fillColor: [250, 251, 253] },
    columnStyles: {
      0: { cellWidth: 11, halign: "center" },
      1: { cellWidth: 9, halign: "center" },
      2: { cellWidth: 42, halign: "center" },
      3: { cellWidth: 30 },
      4: { cellWidth: 10, halign: "right" },
      5: { cellWidth: 10, halign: "right" },
      6: { cellWidth: 10, halign: "right" },
      7: { cellWidth: 10, halign: "right" },
      8: { cellWidth: 10, halign: "right" },
      9: { cellWidth: 10, halign: "right" },
      10: { cellWidth: 10, halign: "right" },
      11: { cellWidth: 10, halign: "right" },
    },
    didParseCell: (dados) => {
      if (dados.section !== "body") return;
      const texto = String(dados.row.raw?.[3] ?? "");
      if (texto === "DSR" || texto === "Feriado") dados.cell.styles.fillColor = [237, 242, 249];
      if (texto === "Falta") dados.cell.styles.textColor = MARCA.vermelho;
      if (texto.startsWith("Pendência")) dados.cell.styles.textColor = [180, 83, 9];
      if (texto.startsWith("Folga")) dados.cell.styles.textColor = [29, 78, 216];
      if (texto.startsWith("Soma")) dados.cell.styles.textColor = [22, 101, 52];
    },
    margin: { left: 12, right: 12, top: ALTURA_FAIXA + 5 },
    didDrawPage: () => {
      if (pagina > 1) faixaTitulo(doc, input, pagina);
      pagina += 1;
    },
  });

  // Resumos
  const b = input.banco;
  let y = (doc as any).lastAutoTable.finalY + 4;

  const painel = (
    titulo: string,
    itens: Array<[string, string]>,
    x: number,
    largura: number,
    topo: number,
  ) => {
    const linhas = Math.ceil(itens.length / 2);
    const altura = 8 + linhas * 5.6;
    doc.setFillColor(...MARCA.navy);
    doc.roundedRect(x, topo, largura, 6, 1.2, 1.2, "F");
    doc.setFillColor(252, 253, 254);
    doc.setDrawColor(226, 232, 240);
    doc.rect(x, topo + 6, largura, altura - 6, "FD");
    doc.setFont("helvetica", "bold");
    doc.setFontSize(6.8);
    doc.setTextColor(...MARCA.branco);
    doc.text(titulo.toUpperCase(), x + 3, topo + 4.2);

    itens.forEach(([rotulo, valor], i) => {
      if (!rotulo) return;
      const col = i % 2;
      const linhaIdx = Math.floor(i / 2);
      const cx = x + 3 + col * (largura / 2);
      const cy = topo + 11 + linhaIdx * 5.6;
      doc.setFont("helvetica", "normal");
      doc.setFontSize(6);
      doc.setTextColor(...MARCA.cinza);
      doc.text(rotulo, cx, cy);
      doc.setFont("helvetica", "bold");
      doc.setFontSize(7);
      doc.setTextColor(...MARCA.navy);
      doc.text(valor, cx + largura / 2 - 6, cy, { align: "right" });
    });
    return topo + altura;
  };

  const mostrarBanco = input.incluirBanco !== false;
  const largura = pageW - 24;
  const fim1 = painel("Resumo de horas do mês", [
    ["Horas normais", hm(totais.hn) || "00:00"],
    ["Horas trabalhadas", hm(totais.hd) || "00:00"],
    [
      // O mesmo cuidado do rótulo do dia: com banco vigente estas horas vão
      // para o banco, uma por uma; sem banco elas serão pagas, com adicional.
      input.banco?.temRegime !== false ? "Horas p/ o banco (1:1)" : "Horas extras (a pagar)",
      hm(totais.he) || "00:00",
    ],
    ["Horas compensadas", hm(totais.hc) || "00:00"],
    ["Horas de ausência", hm(totais.ha) || "00:00"],
    ["Adicional noturno", "n/a"],
    ["Faltas não justificadas", hm(totais.fn) || "00:00"],
    ["Faltas justificadas", hm(totais.fj) || "00:00"],
  ], 12, largura, y);

  // RN44 — Resumo do Banco de Horas: faixa única ao final do cartão, no
  // formato de referência da contabilidade (Saldo Anterior / Crédito /
  // Débito / Saldo Atual em uma só linha). Não depende de coluna de
  // acumulado diário: a evolução do dia já está na coluna "Ocorrência".
  y = fim1 + 4;
  if (mostrarBanco) {
    const creditos = b?.creditos ?? totais.he;
    const debitos = b?.debitos ?? totais.ha;
    const saldoAnterior = b?.saldoAnterior ?? 0;
    const saldoAtual = b?.saldoAtual ?? saldoAnterior + creditos - debitos;
    const campos: Array<[string, string]> = [
      ["Saldo Anterior:", formatarHoraRelogio(saldoAnterior)],
      ["Crédito Banco de Horas:", formatarHoraRelogio(creditos)],
      ["Débito Banco de Horas:", formatarHoraRelogio(debitos)],
      ["Saldo Atual:", formatarHoraRelogio(saldoAtual)],
    ];
    const alturaFaixa = 6 + 7;
    doc.setFillColor(...MARCA.navy);
    doc.roundedRect(12, y, largura, 6, 1.2, 1.2, "F");
    doc.setFillColor(252, 253, 254);
    doc.setDrawColor(226, 232, 240);
    doc.rect(12, y + 6, largura, alturaFaixa - 6, "FD");
    doc.setFont("helvetica", "bold");
    doc.setFontSize(6.8);
    doc.setTextColor(...MARCA.branco);
    doc.text("RESUMO DO BANCO DE HORAS", 15, y + 4.2);

    const passo = largura / campos.length;
    campos.forEach(([rotulo, valor], i) => {
      const cx = 15 + i * passo;
      doc.setFont("helvetica", "normal");
      doc.setFontSize(6.2);
      doc.setTextColor(...MARCA.cinza);
      doc.text(rotulo, cx, y + 10.6);
      const larguraRotulo = doc.getTextWidth(rotulo);
      doc.setFont("helvetica", "bold");
      doc.setFontSize(7.2);
      doc.setTextColor(...MARCA.navy);
      doc.text(valor, cx + larguraRotulo + 2, y + 10.6);
    });
    y += alturaFaixa;
  }

  y += 5;

  // Um colaborador = uma página, e a tabela se comprime para isso (ver
  // RESERVA_RODAPE). Mas "ancorar" o bloco final ao limite da página com um
  // Math.min era uma âncora para CIMA: quando a tabela passava do espaço
  // reservado, o bloco subia e era impresso POR CIMA do resumo de horas —
  // legenda, declaração de acordo e assinaturas em cima dos totais do mês,
  // num documento feito para ser assinado.
  //
  // Agora o bloco nunca recua sobre o que já foi desenhado. Se não couber,
  // abre folha — uma segunda página é um defeito de estética; texto sobre
  // texto num cartão de ponto é um defeito de prova.
  const ALTURA_BLOCO_FINAL = 32;
  const LIMITE_UTIL = pageH - 16;
  if (y + ALTURA_BLOCO_FINAL > LIMITE_UTIL) {
    doc.addPage();
    faixaTitulo(doc, input, doc.getCurrentPageInfo().pageNumber);
    y = ALTURA_FAIXA + 8;
  }

  // Legenda
  doc.setFont("helvetica", "bold");
  doc.setFontSize(6.4);
  doc.setTextColor(...MARCA.navy);
  doc.text("Legenda", 12, y);
  doc.setFont("helvetica", "normal");
  doc.setFontSize(5.4);
  doc.setTextColor(...MARCA.cinza);
  [
    "H.D. = Total de horas do dia   H.N. = Hora normal (prevista)   H.E. = Hora extra   A.N. = Adicional noturno   H.C. = Hora compensada",
    "H.A. = Hora de ausência   F.N. = Falta não justificada   F.J. = Falta justificada   O = Marcação original   I = Marcação incluída pelo RH",
    "(P) = Intervalo pré-assinalado: intervalo declarado formalmente, não batido (Súmula 338, III do TST; Portaria MTP 671/2021)",
  ].forEach((linha, i) => doc.text(linha, 12, y + 3.2 + i * 2.8));

  y += 11;

  doc.setFontSize(6.2);
  doc.setTextColor(30, 41, 59);
  doc.text(
    "Estou de pleno acordo com o que demonstram as marcações acima, sendo que representam o ocorrido neste período.",
    12, y,
  );
  y += 10;
  doc.setDrawColor(148, 163, 184);
  doc.setLineWidth(0.3);
  doc.line(16, y, 90, y);
  doc.line(pageW - 90, y, pageW - 16, y);
  doc.setFontSize(6);
  doc.setTextColor(...MARCA.cinza);
  doc.text(input.empregado.nome, 53, y + 3.2, { align: "center" });
  doc.text("Assinatura da chefia", pageW - 53, y + 3.2, { align: "center" });



  const total = doc.getNumberOfPages();
  desenharRodape(doc, doc.getCurrentPageInfo().pageNumber, total);
}

