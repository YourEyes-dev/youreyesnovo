/**
 * Identidade visual dos PDFs do módulo de ponto.
 *
 * Os relatórios saíam com cabeçalho em texto puro e tabela cinza — o RH
 * reclamou, com razão: é documento que sai da empresa e às vezes vai para
 * fiscalização. Aqui ficam a marca, as cores e o cabeçalho/rodapé, num
 * lugar só, para todo relatório novo nascer no mesmo padrão.
 *
 * As cores são as mesmas do sistema (index.css), convertidas de HSL:
 *   --brand-blue   207 90% 39%   → 10, 108, 189
 *   --brand-green  152 66% 39%   → 34, 165, 104
 *   --brand-orange  33 100% 50%  → 255, 140,   0
 *   --brand-navy   215 65% 12%   → 11,  27,  50
 */
import type jsPDF from "jspdf";
// PNG do próprio repositório (Vite resolve a URL respeitando o base de
// /teste/ e /homologacao/). Não usar /__l5e/... do antigo host Lovable.
import logoUrl from "@/assets/logo-youreyes-mark.png";


export type RGB = [number, number, number];

export const MARCA = {
  azul: [10, 108, 189] as RGB,
  verde: [34, 165, 104] as RGB,
  laranja: [255, 140, 0] as RGB,
  navy: [11, 27, 50] as RGB,
  cinza: [100, 116, 139] as RGB,
  cinzaClaro: [241, 245, 249] as RGB,
  vermelho: [190, 30, 45] as RGB,
  branco: [255, 255, 255] as RGB,
};

/** Converte o PNG do bundle em dataURL, uma vez por sessão. */
let logoCache: string | null | undefined;

export async function carregarLogo(): Promise<string | null> {
  if (logoCache !== undefined) return logoCache;
  try {
    const resp = await fetch(logoUrl);
    const blob = await resp.blob();
    if (!resp.ok || !blob.type.startsWith("image/")) throw new Error("logo inválida");
    logoCache = await new Promise<string>((resolve, reject) => {
      const fr = new FileReader();
      fr.onload = () => resolve(String(fr.result));
      fr.onerror = reject;
      fr.readAsDataURL(blob);
    });
  } catch {
    // Documento sem logo é melhor que documento que não sai.
    logoCache = null;
  }
  return logoCache;
}

export interface CabecalhoOpts {
  titulo: string;
  subtitulo?: string;
  /** Empresa/cliente a que o relatório se refere. */
  empresa?: string | null;
  /** CNPJ da empresa/filial, já formatado. */
  cnpj?: string | null;
  competencia?: string | null;
  geradoEm: string;
  logoDataUrl?: string | null;
}


/** Altura ocupada pelo cabeçalho — use como startY das tabelas. */
export const ALTURA_CABECALHO = 46;

export function desenharCabecalho(doc: jsPDF, o: CabecalhoOpts) {
  const pageW = doc.internal.pageSize.getWidth();

  // Faixa da marca
  doc.setFillColor(...MARCA.navy);
  doc.rect(0, 0, pageW, 30, "F");
  // Fio de destaque, nas três cores da marca
  const fio = 1.6;
  doc.setFillColor(...MARCA.azul);
  doc.rect(0, 30, pageW * 0.55, fio, "F");
  doc.setFillColor(...MARCA.verde);
  doc.rect(pageW * 0.55, 30, pageW * 0.3, fio, "F");
  doc.setFillColor(...MARCA.laranja);
  doc.rect(pageW * 0.85, 30, pageW * 0.15, fio, "F");

  let textoX = 14;
  if (o.logoDataUrl) {
    try {
      // Placa branca atrás da marca: o símbolo tem o ponto central navy,
      // que sumiria sobre a faixa navy do cabeçalho.
      doc.setFillColor(...MARCA.branco);
      doc.roundedRect(13, 6, 18, 18, 2.5, 2.5, "F");
      doc.addImage(o.logoDataUrl, "PNG", 15, 8, 14, 14);
      textoX = 36;
    } catch {
      /* logo inválida: segue sem ela */
    }
  }

  doc.setTextColor(...MARCA.branco);
  doc.setFont("helvetica", "bold");
  doc.setFontSize(15);
  doc.text("YourEyes", textoX, 15);
  doc.setFont("helvetica", "normal");
  doc.setFontSize(8);
  doc.setTextColor(200, 214, 232);
  doc.text("Gestão de Jornada · Portaria 671 MTP", textoX, 21);

  // Título do relatório, à direita da faixa
  doc.setFont("helvetica", "bold");
  doc.setFontSize(12);
  doc.setTextColor(...MARCA.branco);
  doc.text(o.titulo.toUpperCase(), pageW - 14, 15, { align: "right" });
  if (o.subtitulo) {
    doc.setFont("helvetica", "normal");
    doc.setFontSize(8);
    doc.setTextColor(200, 214, 232);
    doc.text(o.subtitulo, pageW - 14, 21, { align: "right" });
  }

  // Linha de contexto: empresa, competência e emissão
  doc.setTextColor(...MARCA.navy);
  doc.setFont("helvetica", "bold");
  doc.setFontSize(10);
  doc.text(o.empresa || "Todas as empresas", 14, 40);

  if (o.cnpj) {
    const larguraNome = doc.getTextWidth(o.empresa || "Todas as empresas");
    doc.setFont("helvetica", "normal");
    doc.setFontSize(8.5);
    doc.setTextColor(...MARCA.cinza);
    doc.text(`CNPJ ${o.cnpj}`, 14 + larguraNome + 4, 40);
  }


  doc.setFont("helvetica", "normal");
  doc.setFontSize(8.5);
  doc.setTextColor(...MARCA.cinza);
  const direita: string[] = [];
  if (o.competencia) direita.push(`Competência ${o.competencia}`);
  direita.push(`Emitido em ${o.geradoEm}`);
  doc.text(direita.join("   ·   "), pageW - 14, 40, { align: "right" });

  doc.setDrawColor(226, 232, 240);
  doc.setLineWidth(0.4);
  doc.line(14, 43, pageW - 14, 43);
}

export function desenharRodape(doc: jsPDF, pagina: number, total: number) {
  const pageW = doc.internal.pageSize.getWidth();
  const pageH = doc.internal.pageSize.getHeight();

  doc.setDrawColor(226, 232, 240);
  doc.setLineWidth(0.4);
  doc.line(14, pageH - 14, pageW - 14, pageH - 14);

  doc.setFont("helvetica", "normal");
  doc.setFontSize(7.5);
  doc.setTextColor(...MARCA.cinza);
  doc.text("YourEyes · Registro fiel e auditável da jornada", 14, pageH - 9);
  doc.text(`Página ${pagina} de ${total}`, pageW - 14, pageH - 9, { align: "right" });
}

/** Estilo padrão das tabelas (autoTable). */
export function estiloTabela(startY = ALTURA_CABECALHO) {
  return {
    startY,
    theme: "grid" as const,
    styles: {
      font: "helvetica",
      fontSize: 8.5,
      cellPadding: 2.4,
      lineColor: [226, 232, 240] as RGB,
      lineWidth: 0.2,
      textColor: [30, 41, 59] as RGB,
    },
    headStyles: {
      fillColor: MARCA.azul,
      textColor: MARCA.branco,
      fontStyle: "bold" as const,
      fontSize: 8.5,
      halign: "left" as const,
    },
    alternateRowStyles: { fillColor: [248, 250, 252] as RGB },
    margin: { top: ALTURA_CABECALHO, left: 14, right: 14 },
  };
}
