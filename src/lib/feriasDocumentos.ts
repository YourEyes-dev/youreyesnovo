import jsPDF from "jspdf";

interface FeriasDocData {
  colaboradorNome: string;
  colaboradorCpf?: string;
  departamento: string;
  cargo?: string;
  dataInicio: string;
  dataFim: string;
  diasSolicitados: number;
  abonoPecuniario: boolean;
  diasAbono: number;
  salarioBase: number;
  empresaNome?: string;
}

function formatDate(dateStr: string): string {
  return new Date(dateStr + "T12:00:00").toLocaleDateString("pt-BR", {
    day: "2-digit",
    month: "long",
    year: "numeric",
  });
}

function formatCurrency(value: number): string {
  return value.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
}

/**
 * Gera PDF do Aviso de Férias conforme CLT
 */
export function gerarAvisoFeriasPDF(data: FeriasDocData): jsPDF {
  const doc = new jsPDF();
  const pageWidth = doc.internal.pageSize.getWidth();
  const margin = 20;
  let y = 25;

  // Header
  doc.setFontSize(16);
  doc.setFont("helvetica", "bold");
  doc.text("AVISO DE FÉRIAS", pageWidth / 2, y, { align: "center" });
  y += 8;

  doc.setFontSize(9);
  doc.setFont("helvetica", "normal");
  doc.text("Art. 135 da Consolidação das Leis do Trabalho", pageWidth / 2, y, { align: "center" });
  y += 15;

  // Separator
  doc.setDrawColor(200);
  doc.line(margin, y, pageWidth - margin, y);
  y += 10;

  // Company info
  if (data.empresaNome) {
    doc.setFontSize(10);
    doc.setFont("helvetica", "bold");
    doc.text("EMPRESA:", margin, y);
    doc.setFont("helvetica", "normal");
    doc.text(data.empresaNome, margin + 25, y);
    y += 8;
  }

  // Employee info
  doc.setFontSize(10);
  doc.setFont("helvetica", "bold");
  doc.text("COLABORADOR:", margin, y);
  doc.setFont("helvetica", "normal");
  doc.text(data.colaboradorNome, margin + 38, y);
  y += 7;

  if (data.colaboradorCpf) {
    doc.setFont("helvetica", "bold");
    doc.text("CPF:", margin, y);
    doc.setFont("helvetica", "normal");
    doc.text(data.colaboradorCpf, margin + 14, y);
    y += 7;
  }

  if (data.cargo) {
    doc.setFont("helvetica", "bold");
    doc.text("CARGO:", margin, y);
    doc.setFont("helvetica", "normal");
    doc.text(data.cargo, margin + 19, y);
    y += 7;
  }

  doc.setFont("helvetica", "bold");
  doc.text("DEPARTAMENTO:", margin, y);
  doc.setFont("helvetica", "normal");
  doc.text(data.departamento, margin + 42, y);
  y += 12;

  // Separator
  doc.line(margin, y, pageWidth - margin, y);
  y += 10;

  // Period details
  doc.setFontSize(11);
  doc.setFont("helvetica", "bold");
  doc.text("PERÍODO DE FÉRIAS", margin, y);
  y += 8;

  doc.setFontSize(10);
  doc.setFont("helvetica", "normal");

  const details = [
    ["Data de Início:", formatDate(data.dataInicio)],
    ["Data de Término:", formatDate(data.dataFim)],
    ["Dias de Gozo:", `${data.diasSolicitados} dias corridos`],
  ];

  if (data.abonoPecuniario) {
    details.push(["Abono Pecuniário:", `${data.diasAbono} dias (Art. 143 CLT)`]);
  }

  details.forEach(([label, value]) => {
    doc.setFont("helvetica", "bold");
    doc.text(label, margin + 5, y);
    doc.setFont("helvetica", "normal");
    doc.text(value, margin + 55, y);
    y += 7;
  });

  y += 5;

  // Financial summary
  if (data.salarioBase > 0) {
    doc.line(margin, y, pageWidth - margin, y);
    y += 10;

    doc.setFontSize(11);
    doc.setFont("helvetica", "bold");
    doc.text("DEMONSTRATIVO FINANCEIRO", margin, y);
    y += 8;

    doc.setFontSize(10);
    const salarioDia = data.salarioBase / 30;
    const valorFerias = salarioDia * data.diasSolicitados;
    const tercoConstitucional = valorFerias / 3;
    const valorAbono = data.abonoPecuniario ? salarioDia * data.diasAbono : 0;
    const total = valorFerias + tercoConstitucional + valorAbono;

    const financials = [
      ["Salário Base:", formatCurrency(data.salarioBase)],
      [`Férias (${data.diasSolicitados} dias):`, formatCurrency(valorFerias)],
      ["1/3 Constitucional:", formatCurrency(tercoConstitucional)],
    ];

    if (data.abonoPecuniario) {
      financials.push([`Abono Pecuniário (${data.diasAbono}d):`, formatCurrency(valorAbono)]);
    }

    financials.forEach(([label, value]) => {
      doc.setFont("helvetica", "normal");
      doc.text(label, margin + 5, y);
      doc.text(value, pageWidth - margin - 5, y, { align: "right" });
      y += 7;
    });

    y += 2;
    doc.setDrawColor(0);
    doc.line(margin + 5, y, pageWidth - margin - 5, y);
    y += 7;

    doc.setFont("helvetica", "bold");
    doc.text("TOTAL BRUTO:", margin + 5, y);
    doc.text(formatCurrency(total), pageWidth - margin - 5, y, { align: "right" });
    y += 5;

    doc.setFontSize(8);
    doc.setFont("helvetica", "italic");
    doc.text("* Valores sujeitos a descontos legais (INSS, IRRF)", margin + 5, y);
    y += 3;
    if (data.abonoPecuniario) {
      doc.text("* O abono pecuniário não integra salário para fins de FGTS e INSS", margin + 5, y);
    }
  }

  y += 15;

  // Legal text
  doc.setFontSize(9);
  doc.setFont("helvetica", "normal");
  const legalText = `Comunicamos que foram concedidas férias ao colaborador acima identificado, conforme período descrito. O pagamento das férias será efetuado até 2 (dois) dias antes do início do respectivo período, conforme Art. 145 da CLT.`;
  const splitLegal = doc.splitTextToSize(legalText, pageWidth - margin * 2 - 10);
  doc.text(splitLegal, margin + 5, y);
  y += splitLegal.length * 5 + 15;

  // Signatures
  const sigWidth = (pageWidth - margin * 2 - 20) / 2;

  doc.line(margin, y, margin + sigWidth, y);
  doc.text("Empregador / RH", margin + sigWidth / 2, y + 5, { align: "center" });

  doc.line(pageWidth - margin - sigWidth, y, pageWidth - margin, y);
  doc.text("Colaborador(a)", pageWidth - margin - sigWidth / 2, y + 5, { align: "center" });

  y += 15;

  // Date
  const hoje = new Date().toLocaleDateString("pt-BR", {
    day: "2-digit",
    month: "long",
    year: "numeric",
  });
  doc.setFontSize(9);
  doc.text(`Emitido em ${hoje}`, pageWidth / 2, y, { align: "center" });

  // Footer
  doc.setFontSize(7);
  doc.setTextColor(150);
  doc.text("Documento gerado automaticamente pelo sistema YourEyes", pageWidth / 2, 285, { align: "center" });

  return doc;
}

/**
 * Gera PDF do Recibo de Férias
 */
export function gerarReciboFeriasPDF(data: FeriasDocData): jsPDF {
  const doc = new jsPDF();
  const pageWidth = doc.internal.pageSize.getWidth();
  const margin = 20;
  let y = 25;

  doc.setFontSize(14);
  doc.setFont("helvetica", "bold");
  doc.text("RECIBO DE PAGAMENTO DE FÉRIAS", pageWidth / 2, y, { align: "center" });
  y += 8;
  doc.setFontSize(9);
  doc.setFont("helvetica", "normal");
  doc.text("Art. 145, CLT — Pagamento até 2 dias antes do início", pageWidth / 2, y, { align: "center" });
  y += 15;

  doc.setDrawColor(200);
  doc.line(margin, y, pageWidth - margin, y);
  y += 10;

  // Employee
  doc.setFontSize(10);
  const info = [
    ["Colaborador:", data.colaboradorNome],
    ["CPF:", data.colaboradorCpf || "—"],
    ["Departamento:", data.departamento],
    ["Período:", `${formatDate(data.dataInicio)} a ${formatDate(data.dataFim)}`],
    ["Dias de Gozo:", `${data.diasSolicitados} dias`],
  ];
  if (data.abonoPecuniario) {
    info.push(["Abono Pecuniário:", `${data.diasAbono} dias`]);
  }

  info.forEach(([label, value]) => {
    doc.setFont("helvetica", "bold");
    doc.text(label, margin, y);
    doc.setFont("helvetica", "normal");
    doc.text(value, margin + 45, y);
    y += 7;
  });

  y += 5;
  doc.line(margin, y, pageWidth - margin, y);
  y += 10;

  // Financial
  doc.setFontSize(11);
  doc.setFont("helvetica", "bold");
  doc.text("PROVENTOS", margin, y);
  y += 8;

  const salarioDia = data.salarioBase / 30;
  const valorFerias = salarioDia * data.diasSolicitados;
  const tercoConstitucional = valorFerias / 3;
  const valorAbono = data.abonoPecuniario ? salarioDia * data.diasAbono : 0;
  const total = valorFerias + tercoConstitucional + valorAbono;

  doc.setFontSize(10);
  const rows = [
    [`Férias — ${data.diasSolicitados} dias`, formatCurrency(valorFerias)],
    ["Adicional 1/3 Constitucional", formatCurrency(tercoConstitucional)],
  ];
  if (data.abonoPecuniario) {
    rows.push([`Abono Pecuniário — ${data.diasAbono} dias`, formatCurrency(valorAbono)]);
  }

  rows.forEach(([label, value]) => {
    doc.setFont("helvetica", "normal");
    doc.text(label, margin + 5, y);
    doc.text(value, pageWidth - margin - 5, y, { align: "right" });
    y += 7;
  });

  y += 3;
  doc.setDrawColor(0);
  doc.setLineWidth(0.5);
  doc.line(margin, y, pageWidth - margin, y);
  y += 7;
  doc.setFont("helvetica", "bold");
  doc.setFontSize(11);
  doc.text("TOTAL BRUTO:", margin + 5, y);
  doc.text(formatCurrency(total), pageWidth - margin - 5, y, { align: "right" });

  y += 20;

  // Signature
  doc.setFontSize(9);
  doc.setFont("helvetica", "normal");
  doc.text("Recebi o pagamento acima discriminado referente às minhas férias.", margin, y);
  y += 20;

  const sigWidth = (pageWidth - margin * 2 - 20) / 2;
  doc.line(margin, y, margin + sigWidth, y);
  doc.text("Data", margin + sigWidth / 2, y + 5, { align: "center" });

  doc.line(pageWidth - margin - sigWidth, y, pageWidth - margin, y);
  doc.text("Assinatura do Colaborador", pageWidth - margin - sigWidth / 2, y + 5, { align: "center" });

  doc.setFontSize(7);
  doc.setTextColor(150);
  doc.text("Documento gerado automaticamente pelo sistema YourEyes", pageWidth / 2, 285, { align: "center" });

  return doc;
}

/**
 * Gera HTML do Recibo de Férias — usado na assinatura digital pelo colaborador.
 */
export function gerarReciboFeriasHTML(data: FeriasDocData): string {
  const salarioDia = data.salarioBase / 30;
  const valorFerias = salarioDia * data.diasSolicitados;
  const terco = valorFerias / 3;
  const valorAbono = data.abonoPecuniario ? salarioDia * data.diasAbono : 0;
  const total = valorFerias + terco + valorAbono;

  const linhaAbono = data.abonoPecuniario
    ? `<tr><td>Abono Pecuniário — ${data.diasAbono} dias</td><td style="text-align:right;">${formatCurrency(valorAbono)}</td></tr>`
    : "";
  const infoAbono = data.abonoPecuniario
    ? `<tr><td><strong>Abono Pecuniário:</strong></td><td>${data.diasAbono} dias</td></tr>`
    : "";

  return `<!DOCTYPE html>
<html lang="pt-BR"><head><meta charset="UTF-8"><title>Recibo de Férias — ${data.colaboradorNome}</title>
<style>
body{font-family:Arial,Helvetica,sans-serif;max-width:780px;margin:24px auto;padding:24px;color:#1f2937;}
h1{text-align:center;font-size:20px;margin:0 0 4px;}
h2{font-size:14px;margin:24px 0 8px;border-bottom:2px solid #333;padding-bottom:4px;}
.sub{text-align:center;color:#666;font-size:12px;margin-bottom:24px;}
table{width:100%;border-collapse:collapse;font-size:13px;margin-bottom:12px;}
td{padding:6px 4px;vertical-align:top;}
.tot{border-top:2px solid #000;font-weight:700;font-size:14px;}
.decl{margin-top:32px;font-size:13px;line-height:1.5;}
.sig{margin-top:60px;display:flex;justify-content:space-around;font-size:12px;text-align:center;}
.sig div{width:45%;border-top:1px solid #000;padding-top:4px;}
.foot{margin-top:40px;text-align:center;font-size:10px;color:#888;}
</style></head><body>
<h1>RECIBO DE PAGAMENTO DE FÉRIAS</h1>
<p class="sub">Art. 145 da CLT — Pagamento até 2 dias antes do início do gozo</p>
<h2>Identificação</h2>
<table>
<tr><td><strong>Colaborador:</strong></td><td>${data.colaboradorNome}</td></tr>
<tr><td><strong>CPF:</strong></td><td>${data.colaboradorCpf || "—"}</td></tr>
<tr><td><strong>Departamento:</strong></td><td>${data.departamento || "—"}</td></tr>
<tr><td><strong>Período de gozo:</strong></td><td>${formatDate(data.dataInicio)} a ${formatDate(data.dataFim)}</td></tr>
<tr><td><strong>Dias de gozo:</strong></td><td>${data.diasSolicitados} dias</td></tr>
${infoAbono}
</table>
<h2>Composição do Pagamento</h2>
<table>
<tr><td>Férias — ${data.diasSolicitados} dias</td><td style="text-align:right;">${formatCurrency(valorFerias)}</td></tr>
<tr><td>Adicional 1/3 Constitucional</td><td style="text-align:right;">${formatCurrency(terco)}</td></tr>
${linhaAbono}
<tr class="tot"><td>TOTAL BRUTO</td><td style="text-align:right;">${formatCurrency(total)}</td></tr>
</table>
<p class="decl">Declaro para os devidos fins que recebi da empresa o valor acima discriminado, referente às minhas férias e respectivos direitos legais, nada mais tendo a reclamar a este título.</p>
<div class="sig"><div>Data</div><div>Assinatura do Colaborador</div></div>
<p class="foot">Documento gerado automaticamente pelo sistema YourEyes</p>
</body></html>`;
}


/**
 * Aviso de Férias em HTML — versão para arquivar em Documentos e colher a
 * ciência do colaborador (art. 135 da CLT, antecedência de 30 dias). Espelha
 * o gerarReciboFeriasHTML: mesmo esqueleto, texto do aviso.
 */
export function gerarAvisoFeriasHTML(data: FeriasDocData): string {
  const infoAbono = data.abonoPecuniario
    ? `<tr><td><strong>Abono Pecuniário:</strong></td><td>${data.diasAbono} dias</td></tr>`
    : "";

  return `<!DOCTYPE html>
<html lang="pt-BR"><head><meta charset="UTF-8"><title>Aviso de Férias — ${data.colaboradorNome}</title>
<style>
body{font-family:Arial,Helvetica,sans-serif;max-width:780px;margin:24px auto;padding:24px;color:#1f2937;}
h1{text-align:center;font-size:20px;margin:0 0 4px;}
h2{font-size:14px;margin:24px 0 8px;border-bottom:2px solid #333;padding-bottom:4px;}
.sub{text-align:center;color:#666;font-size:12px;margin-bottom:24px;}
table{width:100%;border-collapse:collapse;font-size:13px;margin-bottom:12px;}
td{padding:6px 4px;vertical-align:top;}
.decl{margin-top:32px;font-size:13px;line-height:1.5;}
.sig{margin-top:60px;display:flex;justify-content:space-around;font-size:12px;text-align:center;}
.sig div{width:45%;border-top:1px solid #000;padding-top:4px;}
.foot{margin-top:40px;text-align:center;font-size:10px;color:#888;}
</style></head><body>
<h1>AVISO DE FÉRIAS</h1>
<p class="sub">Art. 135 da CLT — Comunicação com no mínimo 30 dias de antecedência, mediante recibo</p>
<h2>Identificação</h2>
<table>
<tr><td><strong>Colaborador:</strong></td><td>${data.colaboradorNome}</td></tr>
<tr><td><strong>CPF:</strong></td><td>${data.colaboradorCpf || "—"}</td></tr>
<tr><td><strong>Departamento:</strong></td><td>${data.departamento || "—"}</td></tr>
<tr><td><strong>Período de gozo:</strong></td><td>${formatDate(data.dataInicio)} a ${formatDate(data.dataFim)}</td></tr>
<tr><td><strong>Dias de gozo:</strong></td><td>${data.diasSolicitados} dias</td></tr>
${infoAbono}
</table>
<p class="decl">Comunicamos que suas férias foram concedidas para o período acima. Declaro estar ciente da data de início e do período de gozo das minhas férias, nos termos do art. 135 da CLT.</p>
<div class="sig"><div>Data</div><div>Assinatura do Colaborador (ciência)</div></div>
<p class="foot">Documento gerado automaticamente pelo sistema YourEyes</p>
</body></html>`;
}
