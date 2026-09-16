import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import * as XLSX from "xlsx";
import type { QaBateria, QaResultado } from "@/hooks/useQaRunner";

/**
 * Gera relatorios de uma bateria de testes em tres formatos: PDF, CSV e uma
 * janela imprimivel. Usa as libs que o projeto ja tem (jspdf, xlsx).
 *
 * O PDF e a fonte da verdade que vai para o setor responsavel corrigir, entao
 * o detalhe de cada FALHA e completo e auto-suficiente: arquivo + teste, o
 * ERRO EXATO que o Cypress reportou, o print da tela no momento da falha, o
 * objetivo do caso e o passo a passo para reproduzir.
 */

const SIT_LABEL: Record<string, string> = {
  passou: "Passou",
  falhou: "Falhou",
  erro: "Erro",
  nao_implementado: "Sem rotina",
};

function nomeArquivo(bateria: QaBateria, ext: string): string {
  const data = new Date(bateria.iniciada_em)
    .toLocaleString("pt-BR")
    .replace(/[/:]/g, "-")
    .replace(/[, ]+/g, "_");
  const mod = (bateria.modulo_path || "todos").split("/").pop();
  return `relatorio_qa_${mod}_${data}.${ext}`;
}

function ordenar(resultados: QaResultado[]): QaResultado[] {
  const ordem: Record<string, number> = { falhou: 0, erro: 1, passou: 2, nao_implementado: 3 };
  return [...resultados].sort(
    (a, b) => (ordem[a.situacao] - ordem[b.situacao]) || a.codigo.localeCompare(b.codigo),
  );
}

const eProblema = (r: QaResultado) => r.situacao === "falhou" || r.situacao === "erro";

// O nome do arquivo/spec do Cypress vem embutido em `esperado` como
// "Teste de tela em cypress/e2e/x.cy.ts" (ver qa_registrar_bateria_e2e).
function specDoResultado(r: QaResultado): string {
  return (r.esperado || "").replace(/^Teste de tela em\s*/i, "").trim();
}

// Texto do "erro exato": para falha/erro é o que o Cypress reportou
// (erro_tecnico = displayError). Só cai no genérico se não houver.
function erroExato(r: QaResultado): string {
  const e = (r.erro_tecnico || "").trim();
  if (e) return e;
  return "(o Cypress não retornou uma mensagem de erro para este teste)";
}

// Resumo curto do erro para a coluna da tabela (a tabela é panorama; o detalhe
// completo vem depois). Para quem passou, mantém a frase amigável.
function resumoResultado(r: QaResultado): string {
  if (eProblema(r)) {
    const e = (r.erro_tecnico || r.obtido || "").replace(/\s+/g, " ").trim();
    return e.length > 100 ? e.slice(0, 100) + "…" : e;
  }
  return r.obtido || "";
}

// ─────────────────────────────────────────────────────────
// PDF
// ─────────────────────────────────────────────────────────
export function gerarPDF(bateria: QaBateria, resultados: QaResultado[]) {
  const doc = new jsPDF();
  const M = 14; // margem esquerda
  const LIMITE_Y = 285; // rodapé útil
  const quando = new Date(bateria.iniciada_em).toLocaleString("pt-BR");
  const mod = bateria.modulo_path === "todos" || !bateria.modulo_path
    ? "Todos os módulos"
    : bateria.modulo_path;

  // cursor com quebra de página automática
  let y = 0;
  const novaPagina = () => { doc.addPage(); y = 20; };
  const garantir = (h: number) => { if (y + h > LIMITE_Y) novaPagina(); };
  const escrever = (
    texto: string,
    opts: { x?: number; size?: number; color?: [number, number, number]; bold?: boolean; lineH?: number } = {},
  ) => {
    const x = opts.x ?? M;
    const size = opts.size ?? 9;
    const lineH = opts.lineH ?? size * 0.5;
    doc.setFontSize(size);
    doc.setTextColor(...(opts.color ?? [0, 0, 0]));
    doc.setFont("helvetica", opts.bold ? "bold" : "normal");
    const linhas = doc.splitTextToSize(texto, 210 - x - M);
    for (const ln of linhas) {
      garantir(lineH);
      doc.text(ln, x, y);
      y += lineH;
    }
  };

  // Cabecalho
  doc.setFontSize(16);
  doc.setTextColor(0);
  doc.text("Relatório de Testes Automatizados", M, 18);
  doc.setFontSize(10);
  doc.setTextColor(100);
  doc.text(`Módulo: ${mod}`, M, 26);
  doc.text(`Execução: ${quando}`, M, 31);
  if (bateria.disparada_por_nome) doc.text(`Disparado por: ${bateria.disparada_por_nome}`, M, 36);

  // Placar
  doc.setTextColor(0);
  doc.setFontSize(11);
  const placar = `${bateria.passou} passou · ${bateria.falhou} falhou · ${bateria.erro} erro · ${bateria.nao_implementado} sem rotina  (total ${bateria.total})`;
  doc.text(placar, M, 45);

  const ordenados = ordenar(resultados);
  const problemas = ordenados.filter(eProblema);

  // ── Falhas PRIMEIRO — é o que o setor responsável precisa ver, sem ter de
  //    rolar a lista inteira. O panorama de todos os casos vem depois. ──
  y = 52;
  if (problemas.length === 0) {
    escrever("Nenhuma falha nesta corrida. 🎉", { size: 12, bold: true, color: [21, 128, 61] });
    y += 4;
  } else {
    escrever(`Falhas para correção (${problemas.length})`, { size: 13, bold: true });
    escrever(
      "Cada bloco é auto-suficiente: arquivo do teste, o erro exato reportado pelo Cypress, o print da tela no momento da falha e o passo a passo para reproduzir.",
      { size: 8, color: [90, 90, 90] },
    );
    y += 3;
  }

  problemas.forEach((r, idx) => {
    garantir(24);
    // régua separadora
    doc.setDrawColor(210);
    doc.line(M, y, 210 - M, y);
    y += 5;

    // Identificação
    escrever(`${idx + 1}. ${r.codigo}${r.titulo ? " — " + r.titulo : ""}`, { size: 11, bold: true });
    const spec = specDoResultado(r);
    if (spec) escrever(`Arquivo: ${spec}`, { size: 8, color: [80, 80, 80] });
    if (r.passo_acao) escrever(`Teste: "${r.passo_acao}"`, { size: 8, color: [80, 80, 80] });
    escrever(`Situação: ${SIT_LABEL[r.situacao] || r.situacao}`, {
      size: 8,
      bold: true,
      color: r.situacao === "falhou" ? [185, 28, 28] : [194, 65, 12],
    });
    y += 1.5;

    // ERRO EXATO — o item mais importante para o dev
    escrever("Erro exato (Cypress):", { size: 9.5, bold: true, color: [150, 30, 30] });
    escrever(erroExato(r), { x: 16, size: 8.5, color: [20, 20, 20], lineH: 4.2 });
    y += 2;

    // Print da tela no momento da falha
    if (r.evidencia_png) {
      escrever("Tela no momento da falha:", { size: 8.5, bold: true, color: [40, 40, 40] });
      try {
        const dataUrl = r.evidencia_png.startsWith("data:")
          ? r.evidencia_png
          : `data:image/png;base64,${r.evidencia_png}`;
        let w = 170;
        let h = w * 0.5625; // fallback 16:9
        try {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const props = (doc as any).getImageProperties(dataUrl);
          if (props?.width && props?.height) {
            h = (props.height / props.width) * w;
            const maxH = 165;
            if (h > maxH) { h = maxH; w = (props.width / props.height) * h; }
          }
        } catch { /* usa o fallback 16:9 */ }
        if (y + h > LIMITE_Y) novaPagina();
        doc.addImage(dataUrl, "PNG", 16, y, w, h);
        y += h + 3;
      } catch {
        escrever("(não consegui embutir o print; ele está no artefato da corrida na esteira)", {
          x: 16, size: 7.5, color: [120, 120, 120],
        });
      }
    }

    // Contexto: objetivo do caso
    if (r.objetivo) {
      escrever(`Objetivo do teste: ${r.objetivo}`, { x: 16, size: 8, color: [90, 90, 90] });
    }

    // Passo a passo para reproduzir
    if (r.passos && r.passos.length > 0) {
      escrever("Passo a passo para reproduzir:", { x: 16, size: 8, bold: true, color: [40, 40, 40] });
      r.passos.forEach((p) => {
        const partes = [`${p.ordem}. ${p.acao}`];
        if (p.onde_na_tela && p.onde_na_tela !== "-") partes.push(`   Onde: ${p.onde_na_tela}`);
        if (p.dados && p.dados !== "-") partes.push(`   Dados: ${p.dados}`);
        if (p.resultado_esperado) partes.push(`   Esperado: ${p.resultado_esperado}`);
        escrever(partes.join("\n"), { x: 18, size: 8, color: [90, 90, 90] });
      });
    }

    if (r.duracao_ms != null) {
      escrever(`Duração: ${r.duracao_ms} ms`, { x: 16, size: 7.5, color: [120, 120, 120] });
    }
    y += 5;
  });

  // ── Panorama de TODOS os casos (depois das falhas) ──
  garantir(20);
  y += 4;
  escrever("Todos os casos", { size: 12, bold: true });
  y += 2;
  autoTable(doc, {
    startY: y,
    head: [["Caso", "Situação", "Resultado / início do erro"]],
    body: ordenados.map((r) => [r.codigo, SIT_LABEL[r.situacao] || r.situacao, resumoResultado(r)]),
    styles: { fontSize: 8, cellPadding: 2, overflow: "linebreak" },
    headStyles: { fillColor: [30, 41, 59] },
    columnStyles: { 0: { cellWidth: 26 }, 1: { cellWidth: 22 }, 2: { cellWidth: "auto" } },
    didParseCell: (data) => {
      if (data.section === "body" && data.column.index === 1) {
        const s = ordenados[data.row.index]?.situacao;
        if (s === "falhou") data.cell.styles.textColor = [185, 28, 28];
        else if (s === "erro") data.cell.styles.textColor = [194, 65, 12];
        else if (s === "passou") data.cell.styles.textColor = [21, 128, 61];
        else data.cell.styles.textColor = [100, 116, 139];
      }
    },
  });

  doc.save(nomeArquivo(bateria, "pdf"));
}

// ─────────────────────────────────────────────────────────
// CSV / planilha (xlsx gera um .csv real, abrivel no Excel)
// ─────────────────────────────────────────────────────────
export function gerarCSV(bateria: QaBateria, resultados: QaResultado[]) {
  const linhas = ordenar(resultados).map((r) => ({
    Caso: r.codigo,
    Titulo: r.titulo || "",
    Situacao: SIT_LABEL[r.situacao] || r.situacao,
    Arquivo: specDoResultado(r),
    Teste: r.passo_acao || "",
    Erro_exato: eProblema(r) ? erroExato(r) : "",
    Objetivo: r.objetivo || "",
    Impacto_e_correcao: r.observacoes || "",
    Duracao_ms: r.duracao_ms ?? "",
    Tem_print: r.evidencia_png ? "sim" : "",
  }));
  const ws = XLSX.utils.json_to_sheet(linhas);
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, "Resultados");
  XLSX.writeFile(wb, nomeArquivo(bateria, "csv"));
}

// ─────────────────────────────────────────────────────────
// Janela imprimivel (abre uma aba com HTML pronto para imprimir/salvar PDF)
// ─────────────────────────────────────────────────────────
export function abrirImprimivel(bateria: QaBateria, resultados: QaResultado[]) {
  const quando = new Date(bateria.iniciada_em).toLocaleString("pt-BR");
  const mod = bateria.modulo_path === "todos" || !bateria.modulo_path
    ? "Todos os módulos" : bateria.modulo_path;
  const cor: Record<string, string> = {
    passou: "#15803d", falhou: "#b91c1c", erro: "#c2410c", nao_implementado: "#64748b",
  };
  const esc = (s: string) => (s || "").replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c] as string));
  const ordenados = ordenar(resultados);

  const linhas = ordenados.map((r) => `
    <tr>
      <td style="font-family:monospace;white-space:nowrap">${esc(r.codigo)}</td>
      <td style="color:${cor[r.situacao]};font-weight:600">${SIT_LABEL[r.situacao] || r.situacao}</td>
      <td>${esc(resumoResultado(r))}</td>
    </tr>`).join("");

  const problemas = ordenados.filter(eProblema);
  const detalhes = problemas.map((r, i) => {
    const spec = specDoResultado(r);
    const img = r.evidencia_png
      ? `<div class="lbl">Tela no momento da falha:</div>
         <img class="print" src="${r.evidencia_png.startsWith("data:") ? r.evidencia_png : `data:image/png;base64,${r.evidencia_png}`}" alt="print da falha ${esc(r.codigo)}">`
      : "";
    const passos = (r.passos && r.passos.length)
      ? `<div class="lbl">Passo a passo para reproduzir:</div><ol class="passos">${r.passos.map((p) =>
          `<li>${esc(p.acao)}${p.resultado_esperado ? ` <em>(esperado: ${esc(p.resultado_esperado)})</em>` : ""}</li>`).join("")}</ol>`
      : "";
    return `
      <section class="falha">
        <h3>${i + 1}. ${esc(r.codigo)}${r.titulo ? " — " + esc(r.titulo) : ""}</h3>
        <div class="meta2">${spec ? `Arquivo: <code>${esc(spec)}</code> · ` : ""}${r.passo_acao ? `Teste: “${esc(r.passo_acao)}” · ` : ""}<span style="color:${cor[r.situacao]};font-weight:600">${SIT_LABEL[r.situacao] || r.situacao}</span></div>
        <div class="lbl erro">Erro exato (Cypress):</div>
        <pre class="erro">${esc(erroExato(r))}</pre>
        ${img}
        ${r.objetivo ? `<div class="obj">Objetivo do teste: ${esc(r.objetivo)}</div>` : ""}
        ${passos}
      </section>`;
  }).join("");

  const html = `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
    <title>Relatório QA — ${esc(mod)}</title>
    <style>
      body{font-family:system-ui,sans-serif;max-width:900px;margin:24px auto;padding:0 16px;color:#0f172a}
      h1{font-size:18px;margin:0 0 4px} .meta{color:#64748b;font-size:13px;margin-bottom:16px}
      .placar{font-size:14px;margin:12px 0 20px;padding:10px;background:#f1f5f9;border-radius:8px}
      table{width:100%;border-collapse:collapse;font-size:13px}
      th,td{text-align:left;padding:6px 8px;border-bottom:1px solid #e2e8f0;vertical-align:top}
      th{background:#1e293b;color:#fff}
      h2{font-size:15px;margin:26px 0 6px}
      .falha{border:1px solid #e2e8f0;border-radius:8px;padding:12px 14px;margin:12px 0;page-break-inside:avoid}
      .falha h3{font-size:14px;margin:0 0 4px}
      .meta2{color:#64748b;font-size:12px;margin-bottom:8px}
      .lbl{font-weight:600;font-size:12px;margin:8px 0 3px}
      .lbl.erro{color:#b91c1c}
      pre.erro{background:#fef2f2;border:1px solid #fecaca;color:#7f1d1d;padding:10px;border-radius:6px;white-space:pre-wrap;word-break:break-word;font-size:12px;margin:0}
      img.print{max-width:100%;border:1px solid #e2e8f0;border-radius:6px;margin:4px 0}
      .obj{color:#475569;font-size:12px;margin-top:8px}
      ol.passos{font-size:12px;color:#475569;margin:4px 0 0 18px}
      code{background:#f1f5f9;padding:1px 4px;border-radius:4px;font-size:12px}
      @media print{th{background:#1e293b!important;-webkit-print-color-adjust:exact;print-color-adjust:exact}
        pre.erro,img.print{-webkit-print-color-adjust:exact;print-color-adjust:exact}}
      .btn{margin:16px 0;padding:8px 16px;background:#2563eb;color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:14px}
      @media print{.btn{display:none}}
    </style></head><body>
    <h1>Relatório de Testes Automatizados</h1>
    <div class="meta">Módulo: ${esc(mod)} · Execução: ${quando}${bateria.disparada_por_nome ? " · " + esc(bateria.disparada_por_nome) : ""}</div>
    <button class="btn" onclick="window.print()">Imprimir / Salvar PDF</button>
    <div class="placar"><strong>${bateria.passou}</strong> passou ·
      <strong style="color:#b91c1c">${bateria.falhou}</strong> falhou ·
      <strong style="color:#c2410c">${bateria.erro}</strong> erro ·
      <strong style="color:#64748b">${bateria.nao_implementado}</strong> sem rotina
      (total ${bateria.total})</div>
    ${problemas.length
      ? `<h2>Falhas para correção (${problemas.length})</h2>${detalhes}`
      : `<div class="obj" style="font-size:14px;color:#15803d;font-weight:600">Nenhuma falha nesta corrida. 🎉</div>`}
    <h2>Todos os casos</h2>
    <table><thead><tr><th>Caso</th><th>Situação</th><th>Resultado / início do erro</th></tr></thead>
    <tbody>${linhas}</tbody></table>
    </body></html>`;

  const w = window.open("", "_blank");
  if (w) { w.document.write(html); w.document.close(); }
}
