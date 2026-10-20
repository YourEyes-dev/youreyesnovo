import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import { eachDayOfInterval, endOfMonth, endOfWeek, format, isSameDay, isSameMonth, startOfMonth, startOfWeek } from "date-fns";
import { ptBR } from "date-fns/locale";
import { STATUS_ACAO_LABELS } from "@/types/cultura";
import type { EventoCalendario } from "@/lib/celebracoes";

// PDF do calendário do mês (Cultura & Celebrações). Nunca traz idade nem ano de
// nascimento (RN-007): só dia/mês. Quem pediu reconhecimento reservado é retirado
// por quem chama (ver `ocultos`) — o papel sai impresso e circula.

export interface DiaPdf {
  data: Date;
  foraDoMes: boolean;
  eventos: EventoCalendario[];
}

const MAX_POR_CELULA = 3;

/** Rótulo curto para caber na célula do calendário. */
export function rotuloCurto(e: EventoCalendario): string {
  switch (e.tipo) {
    case "aniversario":
      return `Aniv.: ${e.titulo}`;
    case "tempo_casa":
      return `${e.celebracao?.anos ?? ""} ${e.celebracao?.anos === 1 ? "ano" : "anos"}: ${e.titulo}`.trim();
    case "dia_profissao":
      return e.titulo;
    case "ritual":
      return `Ritual: ${e.titulo}`;
    case "data":
      return e.titulo;
    default:
      return e.titulo;
  }
}

/** Semanas (segunda a domingo) que cobrem o mês, com os eventos de cada dia. */
export function montarSemanas(mes: Date, eventos: EventoCalendario[]): DiaPdf[][] {
  const dias = eachDayOfInterval({
    start: startOfWeek(startOfMonth(mes), { weekStartsOn: 1 }),
    end: endOfWeek(endOfMonth(mes), { weekStartsOn: 1 }),
  });
  const semanas: DiaPdf[][] = [];
  for (let i = 0; i < dias.length; i += 7) {
    semanas.push(
      dias.slice(i, i + 7).map((data) => ({
        data,
        foraDoMes: !isSameMonth(data, mes),
        eventos: eventos.filter((e) => isSameDay(e.data, data)),
      })),
    );
  }
  return semanas;
}

/** Texto da célula: número do dia + até 3 itens + "+N". */
export function textoDaCelula(dia: DiaPdf): string {
  if (dia.foraDoMes) return "";
  const linhas = dia.eventos.slice(0, MAX_POR_CELULA).map(rotuloCurto);
  if (dia.eventos.length > MAX_POR_CELULA) linhas.push(`+${dia.eventos.length - MAX_POR_CELULA} no detalhamento`);
  return [format(dia.data, "d"), ...linhas].join("\n");
}

export function nomeDoArquivo(mes: Date): string {
  return `calendario-celebracoes-${format(mes, "yyyy-MM")}.pdf`;
}

const AZUL: [number, number, number] = [33, 53, 85];

export function gerarCalendarioPdf(args: {
  mes: Date;
  eventos: EventoCalendario[];
  empresaNome?: string;
  /** rótulo do filtro ativo (Tudo, Pessoas, Datas, Rituais) */
  filtro?: string;
  /** quantos itens ficaram de fora por preferência de reconhecimento reservado */
  ocultos?: number;
  agora?: Date;
}): jsPDF {
  const { mes, eventos, empresaNome, filtro = "Tudo", ocultos = 0, agora = new Date() } = args;
  const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" });
  const largura = doc.internal.pageSize.getWidth();
  const margem = 12;
  const titulo = format(mes, "MMMM 'de' yyyy", { locale: ptBR });

  doc.setFont("helvetica", "bold");
  doc.setFontSize(16);
  doc.setTextColor(...AZUL);
  doc.text("Calendário de Celebrações", margem, 14);
  doc.setFontSize(12);
  doc.text(titulo.charAt(0).toUpperCase() + titulo.slice(1), largura - margem, 14, { align: "right" });
  doc.setFont("helvetica", "normal");
  doc.setFontSize(9);
  doc.setTextColor(90);
  doc.text([empresaNome, filtro !== "Tudo" ? `Filtro: ${filtro}` : null].filter(Boolean).join("  |  ") || " ", margem, 20);
  doc.setTextColor(0);

  const semanas = montarSemanas(mes, eventos);
  autoTable(doc, {
    startY: 24,
    head: [["seg", "ter", "qua", "qui", "sex", "sáb", "dom"]],
    body: semanas.map((s) => s.map(textoDaCelula)),
    theme: "grid",
    margin: { left: margem, right: margem },
    // sete colunas iguais; a altura mínima vale só para o corpo (no cabeçalho esticaria a faixa)
    tableWidth: largura - 2 * margem,
    columnStyles: Object.fromEntries([0, 1, 2, 3, 4, 5, 6].map((i) => [i, { cellWidth: (largura - 2 * margem) / 7 }])),
    styles: { fontSize: 8, cellPadding: 1.5, valign: "top", overflow: "linebreak", lineColor: [200, 200, 200] },
    bodyStyles: { minCellHeight: semanas.length > 5 ? 25 : 29 },
    headStyles: { fillColor: AZUL, halign: "center", fontSize: 8, minCellHeight: 7 },
    didParseCell: (d) => {
      if (d.section !== "body") return;
      const dia = semanas[d.row.index]?.[d.column.index];
      if (!dia) return;
      if (dia.foraDoMes) d.cell.styles.fillColor = [240, 240, 240];
      else if (dia.eventos.length) d.cell.styles.fillColor = [238, 244, 252];
    },
  });

  // Detalhamento: tudo do mês, inclusive o que não coube nas células
  const ordenados = semanas.flat().filter((d) => !d.foraDoMes).flatMap((d) => d.eventos);
  doc.addPage();
  doc.setFont("helvetica", "bold");
  doc.setFontSize(13);
  doc.setTextColor(...AZUL);
  doc.text("Detalhamento do mês", margem, 16);
  doc.setTextColor(0);
  autoTable(doc, {
    startY: 20,
    head: [["Data", "O quê", "Quem / Nome", "Situação"]],
    body: ordenados.length
      ? ordenados.map((e) => [
          format(e.data, "dd/MM (EEE)", { locale: ptBR }),
          e.detalhe ?? "",
          e.titulo,
          e.acao ? STATUS_ACAO_LABELS[e.acao.status] || e.acao.status : "",
        ])
      : [["", "Nenhum item neste mês", "", ""]],
    theme: "striped",
    margin: { left: margem, right: margem, bottom: 14 },
    styles: { fontSize: 9 },
    headStyles: { fillColor: AZUL },
  });

  // Rodapé em todas as páginas
  const total = doc.getNumberOfPages();
  const altura = doc.internal.pageSize.getHeight();
  for (let p = 1; p <= total; p++) {
    doc.setPage(p);
    doc.setFont("helvetica", "normal");
    doc.setFontSize(7);
    doc.setTextColor(120);
    const nota = ocultos > 0 ? ` ${ocultos} ${ocultos === 1 ? "pessoa" : "pessoas"} com reconhecimento reservado não ${ocultos === 1 ? "consta" : "constam"}.` : "";
    doc.text(`Documento interno do RH, com dados pessoais (LGPD).${nota}`, margem, altura - 7);
    doc.text(`Gerado em ${format(agora, "dd/MM/yyyy 'às' HH:mm")}  |  Página ${p} de ${total}`, largura - margem, altura - 7, { align: "right" });
  }
  return doc;
}
