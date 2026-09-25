import html2canvas from "html2canvas";
import jsPDF from "jspdf";

interface GeneratePdfFromHtmlOptions {
  html: string;
  filenamePrefix: string;
}

// ABNT margins: superior 3cm, esquerda 3cm, inferior 2cm, direita 2cm
const PDF_MARGIN_TOP_MM = 30;
const PDF_MARGIN_LEFT_MM = 30;
const PDF_MARGIN_RIGHT_MM = 20;
const PDF_MARGIN_BOTTOM_MM = 20;
const PDF_RENDER_SCALE = 2;
const LONG_TEXT_MIN_LENGTH = 40;
const wait = (ms: number) => new Promise((resolve) => window.setTimeout(resolve, ms));


function sanitizeFilename(value: string) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9-_]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "")
    .toLowerCase();
}

function appendInlineStyle(element: Element, styleToAppend: string) {
  const existingStyle = element.getAttribute("style")?.trim() || "";
  const normalizedExisting = existingStyle
    ? `${existingStyle}${existingStyle.endsWith(";") ? "" : ";"}`
    : "";

  element.setAttribute("style", `${normalizedExisting}${styleToAppend}`);
}

function hasCenteredAncestor(element: Element | null) {
  let current = element;

  while (current) {
    const style = current.getAttribute("style") || "";
    if (/text-align\s*:\s*center/i.test(style)) {
      return true;
    }
    current = current.parentElement;
  }

  return false;
}

function hasVisualContainerStyle(element: HTMLElement) {
  const style = element.getAttribute("style") || "";
  return /(background|background-color|background-image|linear-gradient|box-shadow|border(?!-collapse)|border-radius|padding)/i.test(style);
}

function hasOpaqueInlineBackground(element: HTMLElement) {
  const style = element.getAttribute("style") || "";
  if (!/(background|background-color)/i.test(style)) return false;
  if (/transparent/i.test(style)) return false;
  if (/rgba\([^)]*,\s*0(?:\.0+)?\s*\)/i.test(style)) return false;
  return true;
}

function usesLightInlineText(element: HTMLElement) {
  const style = element.getAttribute("style") || "";
  return /color\s*:\s*(#fff(?:fff)?|white|rgb\(255\s*,\s*255\s*,\s*255\))/i.test(style);
}

export function normalizeManualHtml(html: string) {
  if (!html.trim()) return html;

  const parser = new DOMParser();
  const documentNode = parser.parseFromString(html, "text/html");

  const existingNormalizer = documentNode.head.querySelector("style[data-manual-normalizer='true']");
  existingNormalizer?.remove();

  const baseStyle = documentNode.createElement("style");
  baseStyle.setAttribute("data-manual-normalizer", "true");
  // Normalizador de SEGURANÇA, não de design.
  //
  // Nasceu quando a IA gerava HTML arbitrário: forçava tudo num padrão com
  // !important — Times New Roman, corpo de 604px centralizado e texto
  // justificado. Hoje isso atropela a folha de estilo do manual, e era a
  // origem do serifado, das faixas brancas nas laterais da prévia e dos rios
  // de espaço no texto.
  //
  // Os 604px seguem existindo onde de fato importam: o pipeline do PDF aplica
  // a largura no próprio container (mais abaixo neste arquivo). Aqui ficam só
  // as proteções estruturais.
  baseStyle.textContent = `
    html, body {
      background: #ffffff;
      margin: 0 !important;
      padding: 0 !important;
    }

    body {
      -webkit-font-smoothing: antialiased;
      text-rendering: geometricPrecision;
      font-kerning: normal;
      box-sizing: border-box;
      overflow-wrap: break-word;
      word-wrap: break-word;
      font-size: 13px;
      line-height: 1.6;
    }

    *, *::before, *::after { box-sizing: border-box; }

    img, svg, canvas {
      max-width: 100%;
      height: auto;
    }

    p, li, td, th, div, span, blockquote {
      max-width: 100%;
      overflow-wrap: break-word;
      word-wrap: break-word;
    }
  `;

  documentNode.head.appendChild(baseStyle);

  // Reduz tamanhos de fonte pensados para TELA (capa 42px, títulos 28px, corpo
  // 15px+), que no A4 ficam grandes demais e "estouram" o layout. Escala os
  // font-size inline em px por um fator, com um piso para não sumir.
  const FONT_SCALE = 0.78;
  const FONT_MIN_PX = 11;
  documentNode.body.querySelectorAll<HTMLElement>('[style*="font-size"]').forEach((el) => {
    const style = el.getAttribute("style") || "";
    const novo = style.replace(/font-size\s*:\s*([\d.]+)px/gi, (_m, px) => {
      const val = Math.max(FONT_MIN_PX, Math.round(parseFloat(px) * FONT_SCALE));
      return `font-size: ${val}px`;
    });
    if (novo !== style) el.setAttribute("style", novo);
  });

  // Ensure naked text nodes in body are wrapped in <p>
  Array.from(documentNode.body.childNodes).forEach(node => {
    if (node.nodeType === 3 && node.textContent?.trim()) { // 3 is Node.TEXT_NODE
      const p = documentNode.createElement("p");
      p.textContent = node.textContent;
      documentNode.body.insertBefore(p, node);
      documentNode.body.removeChild(node);
    }
  });

  // Fix double numbering: if <li> text already starts with "N." or "N)",
  // remove the auto-numbering from the parent <ol>.
  const orderedLists = documentNode.body.querySelectorAll("ol");
  orderedLists.forEach((ol) => {
    const items = Array.from(ol.children).filter((c) => c.tagName === "LI");
    if (!items.length) return;
    const allPrefixed = items.every((li) => /^\s*\d+\s*[.)]/.test(li.textContent || ""));
    if (allPrefixed) {
      appendInlineStyle(ol as HTMLElement, "list-style: none !important; padding-left: 0 !important;");
    }
  });

  const textElements = documentNode.body.querySelectorAll("p, li, td, blockquote");
  const headingElements = documentNode.body.querySelectorAll("h1, h2, h3, h4, h5, h6");
  const visualContainers = documentNode.body.querySelectorAll("div, section, article, header");

  visualContainers.forEach((container) => {
    const htmlElement = container as HTMLElement;
    const inlineStyle = htmlElement.getAttribute("style") || "";

    if (/linear-gradient/i.test(inlineStyle) && !/background-color/i.test(inlineStyle)) {
      appendInlineStyle(htmlElement, "background-color: #1e3a5f !important;");
    }

    if (hasVisualContainerStyle(htmlElement)) {
      appendInlineStyle(
        htmlElement,
        "break-inside: avoid !important; page-break-inside: avoid !important; overflow: visible !important;"
      );
    }
  });

  headingElements.forEach((el) => {
    const heading = el as HTMLElement;
    appendInlineStyle(
      heading,
      [
        "margin-bottom: 12px !important",
        "margin-top: 16px !important",
        "line-height: 1.25 !important",
        "padding-bottom: 6px !important",
        "page-break-after: avoid !important",
        "break-after: avoid !important",
        "page-break-inside: avoid !important",
        "break-inside: avoid !important",
        "background-clip: padding-box !important",
        "overflow-wrap: break-word !important",
        "word-wrap: break-word !important",
        "-webkit-print-color-adjust: exact",
        "print-color-adjust: exact",
      ].join(";") + ";"
    );

    if (usesLightInlineText(heading) && !hasOpaqueInlineBackground(heading)) {
      appendInlineStyle(
        heading,
        "color: #ffffff !important; background: #1e3a5f !important; display: block !important; padding: 12px 16px !important; border-radius: 12px !important;"
      );
    }
  });

  textElements.forEach((element) => {
    const text = element.textContent?.replace(/\s+/g, " ").trim() || "";

    if (text.length < LONG_TEXT_MIN_LENGTH || hasCenteredAncestor(element)) {
      if (element.tagName === "P") {
        appendInlineStyle(element, "margin-top: 0 !important; margin-bottom: 12px !important;");
      }
      return;
    }

    // NÃO remover word-spacing: sem ele o html2canvas cola as palavras
    // ("Facilitara execuçãodas rotinasde"). É remendo para um defeito da
    // rasterização, não escolha estética.
    // text-align: justify foi retirado de propósito: sem hifenização em
    // pt-BR ele abre rios de espaço entre as palavras.
    appendInlineStyle(
      element,
      [
        "white-space: normal !important",
        "word-break: normal !important",
        "overflow-wrap: break-word !important",
        "word-spacing: 0.05em !important",
        "letter-spacing: normal !important",
        "line-height: 1.6",
        "hyphens: none !important",
        "margin-top: 0 !important",
        "margin-bottom: 12px !important",
      ].join(";") + ";"
    );
  });

  return `<!DOCTYPE html>\n${documentNode.documentElement.outerHTML}`;
}

/**
 * Identify "block" elements within the body that should be captured as
 * non-splittable units.
 */
/**
 * @deprecated NÃO USAR. Foi o que quebrou o PDF do manual.
 *
 * Esta função decompõe o documento e clona cada elemento para dentro de um
 * <div> branco novo. Isso destrói todo seletor descendente — `.capa` perdia o
 * fundo, `.capa-titulo` perdia a cor, cards perdiam o contexto — porque o
 * elemento clonado deixa de ter os ancestrais que o CSS exige.
 *
 * O gerador passou a renderizar o documento inteiro de uma vez e a quebrar
 * páginas pela posição real dos blocos. Mantida apenas como referência
 * histórica.
 */
function collectSections(root: HTMLElement): HTMLElement[] {
  if (!root) return [];
  
  const sections: HTMLElement[] = [];
  const isHeading = (el: HTMLElement) => el && el.tagName && /^H[1-6]$/i.test(el.tagName);

  const isStandaloneRenderable = (node: HTMLElement) => {
    if (["STYLE", "SCRIPT"].includes(node.tagName)) return false;
    if (isHeading(node)) return true;
    if (["P", "TABLE", "UL", "OL", "BLOCKQUOTE", "HR", "SECTION", "ARTICLE"].includes(node.tagName)) return true;
    return hasVisualContainerStyle(node);
  };

  const walk = (node: HTMLElement) => {
    // If it's the root itself, always recurse
    if (node === root) {
      Array.from(node.children).forEach((child) => walk(child as HTMLElement));
      return;
    }

    if (isStandaloneRenderable(node)) {
      sections.push(node);
      return;
    }

    // For generic containers like DIV that aren't standalone, keep digging
    if (["DIV", "SPAN", "BODY", "MAIN"].includes(node.tagName)) {
      Array.from(node.children).forEach((child) => walk(child as HTMLElement));
    }
  };

  walk(root);

  if (sections.length === 0) {
    console.warn("Nenhuma seção renderizável encontrada via walk. Usando fallback de children.");
    return Array.from(root.children).filter(c => !["STYLE", "SCRIPT"].includes(c.tagName)) as HTMLElement[];
  }

  // Refined grouping: group headings with their immediate followers
  const grouped: HTMLElement[] = [];
  let i = 0;
  while (i < sections.length) {
    const current = sections[i];
    
    if (current && isHeading(current) && i + 1 < sections.length) {
      const wrapper = document.createElement("div");
      wrapper.style.cssText = "background:#ffffff; width: 100%; box-sizing: border-box; display: block; overflow: visible;";
      
      const headingClone = current.cloneNode(true) as HTMLElement;
      headingClone.style.marginBottom = "8px";
      headingClone.style.marginTop = "16px";
      wrapper.appendChild(headingClone);
      
      let j = i + 1;
      // Keep adding elements until we hit another heading or a large block
      while (j < sections.length && j < i + 5) {
        const next = sections[j];
        if (isHeading(next)) break;
        
        const nextClone = next.cloneNode(true) as HTMLElement;
        if (nextClone.tagName === "P") {
          nextClone.style.marginTop = "0px";
          nextClone.style.marginBottom = "12px";
        }
        wrapper.appendChild(nextClone);
        
        if (["TABLE", "UL", "OL"].includes(next.tagName) || hasVisualContainerStyle(next)) {
          j++;
          break;
        }
        j++;
      }
      
      grouped.push(wrapper);
      i = j;
    } else if (current) {
      grouped.push(current);
      i += 1;
    } else {
      i += 1;
    }
  }

  return grouped;
}

export async function generatePdfFromHtml({ html, filenamePrefix }: GeneratePdfFromHtmlOptions) {
  if (!html || !html.trim()) {
    throw new Error("O manual está vazio.");
  }

  console.log("Iniciando geração de PDF para:", filenamePrefix);
  const preparedHtml = normalizeManualHtml(html);

  const parser = new DOMParser();
  const doc = parser.parseFromString(preparedHtml, "text/html");
  const bodyContent = doc.body.innerHTML;
  const styles = Array.from(doc.querySelectorAll("style"))
    .map((s) => s.textContent)
    .join("\n");

  // Hidden offscreen container in the main document
  const container = document.createElement("div");
  container.setAttribute("aria-hidden", "true");
  container.className = "pdf-generation-container";
  container.style.cssText = [
    "position: fixed",
    "top: 0",
    "left: -5000px", // Less extreme offset
    "width: 604px",
    "background: #ffffff",
    "visibility: visible",
    "display: block",
    "pointer-events: none",
    "z-index: -9999",
    "overflow: visible",
  ].join(";");

  const styleEl = document.createElement("style");
  styleEl.textContent = styles;
  container.appendChild(styleEl);

  const contentDiv = document.createElement("div");
  contentDiv.innerHTML = bodyContent;
  contentDiv.style.cssText = [
    "width: 604px",
    "max-width: 604px",
    "margin: 0 auto",
    "padding: 0",
    "box-sizing: border-box",
    "overflow-wrap: break-word",
    "word-wrap: break-word",
    "background: #ffffff",
    "color: #1a1a1a",
  ].join(";");

  container.appendChild(contentDiv);

  document.body.appendChild(container);
  console.log("Conteúdo montado no DOM para captura.");

  try {
    // Ensure all images are loaded
    const images = container.querySelectorAll("img");
    await Promise.all(
      Array.from(images).map((img) => {
        if (img.complete) return Promise.resolve();
        return new Promise((resolve) => {
          img.onload = resolve;
          img.onerror = resolve;
        });
      })
    );

    if (document.fonts?.ready) {
      await document.fonts.ready;
    }
    await wait(800);

    const pdf = new jsPDF("p", "mm", "a4");
    const pdfWidth = pdf.internal.pageSize.getWidth();
    const pdfHeight = pdf.internal.pageSize.getHeight();
    const contentWidth = pdfWidth - PDF_MARGIN_LEFT_MM - PDF_MARGIN_RIGHT_MM;
    const usableHeight = pdfHeight - PDF_MARGIN_TOP_MM - PDF_MARGIN_BOTTOM_MM - 3; // safety
    const SECTION_GAP_MM = 2;

    // ── Render único + quebra semântica ───────────────────────────
    // Antes, o gerador DECOMPUNHA o documento: clonava elemento por elemento
    // para dentro de um <div> branco novo. Isso matava todo seletor
    // descendente (.capa .capa-titulo, .secao .secao-titulo...) — a capa saía
    // sem fundo, o título sem cor, os cards sem contexto.
    //
    // Agora o documento é renderizado INTEIRO, de uma vez, preservando o CSS.
    // E as quebras de página saem da POSIÇÃO REAL de cada bloco (medida antes
    // do render), não de caça a pixels em branco.

    const contentRect = contentDiv.getBoundingClientRect();

    // Altura útil de uma página em px de CSS (para não tratar um bloco maior que
    // uma página como "não pode cortar" — isso travaria a paginação).
    const usablePageCssPx = usableHeight * ((contentDiv.offsetWidth || 604) / contentWidth);

    // Pontos onde é aceitável cortar: começo e fim de cada bloco semântico.
    const breakPointsCss: number[] = [];
    const pushBreak = (el: HTMLElement) => {
      const r = el.getBoundingClientRect();
      breakPointsCss.push(r.top - contentRect.top);
      breakPointsCss.push(r.bottom - contentRect.top);
    };
    contentDiv
      .querySelectorAll(".capa, .sumario, .funcao, .secao, .grupo, .tabela, .cards, .card, .rodape")
      .forEach((el) => pushBreak(el as HTMLElement));

    // O manual gerado por IA usa ESTILO INLINE (sem as classes acima). Então
    // também tratamos títulos e contêineres visuais (cards/faixas com fundo,
    // borda, sombra ou padding) como fronteiras de bloco — é o que impede as
    // seções de serem cortadas no meio entre páginas.
    const headings = Array.from(contentDiv.querySelectorAll("h1, h2, h3, h4, h5, h6")) as HTMLElement[];
    const visualContainers = (Array.from(
      contentDiv.querySelectorAll("div[style], section[style], header[style], article[style]")
    ) as HTMLElement[]).filter((el) => hasVisualContainerStyle(el));

    headings.forEach((el) => pushBreak(el));
    visualContainers.forEach((el) => pushBreak(el));

    // Zonas onde cortar é PROIBIDO: dentro de um título, de uma linha de tabela
    // ou de um card/faixa que caiba numa página. Os pontos de quebra acima são
    // a preferência; isto é a garantia contra cortar um bloco ao meio.
    const zonasProibidasCss: Array<[number, number]> = [];
    const pushZona = (el: HTMLElement) => {
      const r = el.getBoundingClientRect();
      zonasProibidasCss.push([r.top - contentRect.top, r.bottom - contentRect.top]);
    };
    contentDiv
      .querySelectorAll(
        ".capa-titulo, .funcao-titulo, .secao-titulo, .grupo-titulo, .card-titulo, .sumario-titulo, tr, .rodape"
      )
      .forEach((el) => pushZona(el as HTMLElement));

    headings.forEach((el) => pushZona(el));
    // Só proíbe cortar DENTRO de um card se ele couber numa página; blocos
    // maiores que uma página precisam poder ser cortados (senão trava).
    visualContainers.forEach((el) => {
      const r = el.getBoundingClientRect();
      if (r.height > 0 && r.height <= usablePageCssPx) pushZona(el);
    });

    const canvas = await html2canvas(contentDiv, {
      scale: 2,
      useCORS: true,
      allowTaint: false,
      backgroundColor: "#ffffff",
      logging: false,
      // Altura explícita: sem isto o html2canvas pode parar antes do fim e
      // cortar o rodapé (era o "Gerado em..." picado na última página).
      width: contentDiv.scrollWidth,
      height: contentDiv.scrollHeight,
      // windowWidth largo de propósito: o contentDiv tem 604px e o CSS do
      // manual tem @media (max-width:640px). Passar 604 aqui dispararia o
      // layout mobile dentro do clone do html2canvas (cards em 1 coluna).
      windowWidth: 1280,
      windowHeight: contentDiv.scrollHeight,
    });

    if (!canvas.width || !canvas.height) {
      throw new Error("Não foi possível renderizar o manual para PDF.");
    }

    // CSS px -> canvas px. Derivado da LARGURA de propósito: a altura tem
    // ambiguidade (offsetHeight x scrollHeight) e errar a escala aqui joga
    // TODOS os pontos de quebra para o lugar errado — era o que cortava o
    // título "Erros e Riscos" ao meio entre as páginas 4 e 5. A largura é
    // fixa (604px) e o html2canvas escala os dois eixos igualmente.
    const cssToCanvas = canvas.width / (contentDiv.offsetWidth || 604);
    const breakPoints = Array.from(
      new Set(breakPointsCss.map((v) => Math.round(v * cssToCanvas)))
    )
      .filter((v) => v > 0 && v < canvas.height)
      .sort((a, b) => a - b);

    const pageHeightPx = Math.floor((canvas.width * usableHeight) / contentWidth);

    // Zonas proibidas convertidas para px de canvas, com folga de 2px.
    const zonasProibidas = zonasProibidasCss
      .map(([a, b]) => [Math.floor(a * cssToCanvas) - 2, Math.ceil(b * cssToCanvas) + 2] as [number, number])
      .filter(([a, b]) => b > a);

    /**
     * Procura, a partir de `corte`, a linha em branco mais próxima acima.
     * Trabalha nos PIXELS REAIS do canvas — por isso é imune a erro de
     * medição. O html2canvas clona a página para um iframe e renderiza lá;
     * as posições que medimos no DOM ao vivo podem não bater com o que foi
     * de fato desenhado. Os pixels não mentem.
     */
    const recuaAteLinhaBranca = (inicio: number, altura: number): number => {
      const ctx = canvas.getContext("2d", { willReadFrequently: true });
      if (!ctx) return altura;
      const minimo = Math.max(40, Math.floor(pageHeightPx * 0.25));
      let brancasSeguidas = 0;
      for (let row = altura; row >= minimo; row -= 1) {
        const abs = inicio + row;
        if (abs >= canvas.height) continue;
        const linha = ctx.getImageData(0, abs, canvas.width, 1).data;
        let tinta = 0;
        for (let i = 0; i < linha.length; i += 4) {
          if (linha[i + 3] > 10 && (linha[i] < 244 || linha[i + 1] < 244 || linha[i + 2] < 244)) {
            tinta += 1;
            if (tinta > 2) break;
          }
        }
        if (tinta <= 2) {
          brancasSeguidas += 1;
          // 6 linhas limpas seguidas = entrelinha de verdade, não buraco
          // entre duas palavras.
          if (brancasSeguidas >= 6) return row + brancasSeguidas - 1;
        } else {
          brancasSeguidas = 0;
        }
      }
      return altura;
    };

    /** Recua o corte se ele cair dentro de um título ou linha de tabela. */
    const ajustaCorte = (inicio: number, altura: number): number => {
      let h = altura;
      // Repete: recuar pode jogar o corte para dentro de outra zona acima.
      for (let tentativa = 0; tentativa < 6; tentativa += 1) {
        const corte = inicio + h;
        const zona = zonasProibidas.find(([a, b]) => corte > a && corte < b);
        if (!zona) return h;
        const novaAltura = zona[0] - inicio;
        // Se recuar não deixa página utilizável, aceita o corte original:
        // melhor uma linha partida do que loop infinito ou página vazia.
        if (novaAltura < pageHeightPx * 0.2) return h;
        h = novaAltura;
      }
      return h;
    };
    console.log(
      `Geração PDF: render único (${canvas.width}x${canvas.height}), ` +
      `${breakPoints.length} pontos de quebra.`
    );

    let y = 0;
    let primeiraPagina = true;

    while (y < canvas.height) {
      if (!primeiraPagina) pdf.addPage();
      primeiraPagina = false;

      let sliceH = Math.min(pageHeightPx, canvas.height - y);

      if (y + sliceH < canvas.height) {
        // 1) Preferência: cortar no fim de um bloco (posição medida no DOM).
        const minAproveitamento = y + pageHeightPx * 0.45;
        const cabem = breakPoints.filter((b) => b > minAproveitamento && b <= y + sliceH);
        if (cabem.length) {
          sliceH = cabem[cabem.length - 1] - y;
        }

        // 2) Preferência: não cortar dentro de um título (também medido).
        sliceH = ajustaCorte(y, sliceH);

        // 3) GARANTIA: o corte tem que cair numa entrelinha de verdade.
        //    Os passos 1 e 2 dependem de medição do DOM, que pode divergir do
        //    que o html2canvas desenhou no clone. Este passo olha o pixel e
        //    não erra — é o que impede letra partida ao meio.
        sliceH = recuaAteLinhaBranca(y, sliceH);
      }

      const slice = document.createElement("canvas");
      slice.width = canvas.width;
      slice.height = sliceH;
      const sliceCtx = slice.getContext("2d");
      if (!sliceCtx) throw new Error("Falha ao preparar página do PDF.");
      sliceCtx.fillStyle = "#ffffff";
      sliceCtx.fillRect(0, 0, slice.width, slice.height);
      sliceCtx.drawImage(canvas, 0, y, canvas.width, sliceH, 0, 0, canvas.width, sliceH);

      const sliceMm = (sliceH * contentWidth) / canvas.width;
      pdf.addImage(
        slice.toDataURL("image/png"),
        "PNG",
        PDF_MARGIN_LEFT_MM,
        PDF_MARGIN_TOP_MM,
        contentWidth,
        sliceMm
      );

      y += sliceH;
    }

    const finalTotalPages = pdf.getNumberOfPages();
    for (let page = 1; page <= finalTotalPages; page += 1) {
      pdf.setPage(page);
      pdf.setFontSize(8);
      pdf.setTextColor(140);
      pdf.text(`Página ${page}/${finalTotalPages}`, pdfWidth - 28, pdfHeight - 5);
    }

    const filename = `${sanitizeFilename(filenamePrefix || "manual") || "manual"}-${Date.now()}.pdf`;
    const blob = pdf.output("blob");

    return { blob, filename, pdf };
  } finally {
    container.remove();
  }
}
