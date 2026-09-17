import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

// Hard cap to prevent memory/CPU exhaustion on edge runtime (status 546)
const MAX_PDF_BYTES = 50 * 1024 * 1024; // 50 MB

// Tetos para a extração de melhor qualidade (unpdf). Ela é encerrada pela
// plataforma com o status 546 quando estoura memória ou tempo de CPU, e worker
// encerrado não responde nada — o número chega cru ao usuário.
//
// São DOIS tetos porque o custo tem duas fontes independentes. O caso que
// motivou isto (PGR da VOE MIDIA, importado pela Barros) tinha só 2,5MB e
// ~92 páginas: passava folgado em qualquer teto de bytes e estourava pelo
// número de páginas. PDF de texto comprime muito, então byte não mede custo.
const MAX_UNPDF_BYTES = 8 * 1024 * 1024; // 8 MB
const MAX_UNPDF_PAGINAS = 120;           // acima disto, parser leve

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const contentType = req.headers.get("content-type") || "";

    let pdfBytes: Uint8Array | null = null;
    let fileName = "documento.pdf";

    if (contentType.includes("multipart/form-data")) {
      const formData = await req.formData();
      const file = formData.get("file") as File | null;
      if (!file) throw new Error("Arquivo não enviado no campo 'file'");
      fileName = file.name;
      if (file.size > MAX_PDF_BYTES) {
        return new Response(
          JSON.stringify({
            error: `Arquivo muito grande (${(file.size / 1024 / 1024).toFixed(1)}MB). Máximo permitido: ${MAX_PDF_BYTES / 1024 / 1024}MB. Tente compactar o PDF ou enviar apenas as páginas relevantes.`,
          }),
          { status: 413, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      pdfBytes = new Uint8Array(await file.arrayBuffer());
    } else {
      const body = await req.json();
      if (!body.base64 && !body.data) throw new Error("Envie o arquivo como multipart ou base64 no campo 'base64'");
      const b64 = body.base64 || body.data;
      const cleanB64 = b64.includes(",") ? b64.split(",")[1] : b64;
      const binaryStr = atob(cleanB64);
      if (binaryStr.length > MAX_PDF_BYTES) {
        return new Response(
          JSON.stringify({
            error: `Arquivo muito grande (${(binaryStr.length / 1024 / 1024).toFixed(1)}MB). Máximo permitido: ${MAX_PDF_BYTES / 1024 / 1024}MB.`,
          }),
          { status: 413, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      pdfBytes = new Uint8Array(binaryStr.length);
      for (let i = 0; i < binaryStr.length; i++) pdfBytes[i] = binaryStr.charCodeAt(i);
      fileName = body.fileName || "documento.pdf";
    }

    let extractedText = "";
    const lower = fileName.toLowerCase();
    const isPdf = lower.endsWith(".pdf");
    const isDocx = lower.endsWith(".docx") || lower.endsWith(".doc");

    // Registrado ANTES de processar, de propósito. Quando o worker morre por
    // estouro de recursos (status 546) ele não chega a logar mais nada — sem
    // esta linha ficamos sem saber sequer o tamanho do arquivo que derrubou,
    // que é exatamente a informação que faltou para diagnosticar o primeiro
    // caso relatado.
    console.log(
      `Extração iniciada: ${fileName} — ${(pdfBytes.length / 1024 / 1024).toFixed(1)}MB ` +
      `(${pdfBytes.length} bytes)`
    );

    if (isPdf) {
      extractedText = await extractPdfText(pdfBytes);
    } else if (isDocx) {
      extractedText = await extractDocxText(pdfBytes);
    } else {
      extractedText = new TextDecoder("utf-8", { fatal: false }).decode(pdfBytes);
    }

    extractedText = cleanText(extractedText);
    const charCount = extractedText.length;
    const wordCount = extractedText.split(/\s+/).filter(Boolean).length;

    console.log(`Extração ok: ${fileName} → ${charCount} chars, ${wordCount} palavras`);

    return new Response(
      JSON.stringify({
        texto: extractedText,
        chars: charCount,
        palavras: wordCount,
        qualidade: charCount > 500 ? "boa" : charCount > 100 ? "media" : "baixa",
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: any) {
    console.error("sst-pdf-extract error:", err?.message || err);
    return new Response(
      JSON.stringify({ error: err?.message || "Erro ao extrair texto do arquivo" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

async function extractPdfText(bytes: Uint8Array): Promise<string> {
  const mb = (bytes.length / 1024 / 1024).toFixed(1);

  // Tentativa 1: unpdf (pdfjs leve, otimizado para edge/serverless).
  //
  // É a de melhor qualidade e a mais cara. O que a encarece NÃO é o tamanho do
  // arquivo, é a QUANTIDADE DE PÁGINAS: o PGR que derrubou a importação tinha
  // 2,5MB e ~92 páginas de tabela. PDF de texto comprime muito, então poucos
  // megabytes viram dezenas de MB de estruturas de fonte e página na memória,
  // e o tempo de CPU estoura. Worker estourado não responde nada — daí o "Erro
  // 546" cru na tela, sem chance de cair nas tentativas seguintes.
  //
  // Por isso aqui:
  //   1. abre o documento (barato) e olha quantas páginas tem;
  //   2. extrai PÁGINA POR PÁGINA, liberando cada uma com cleanup() — em vez
  //      de pedir o texto das 92 de uma vez, que é o que estourava;
  //   3. documento com páginas demais vai direto ao parser leve.
  const tamanhoOk = bytes.length <= MAX_UNPDF_BYTES;
  if (tamanhoOk) {
    try {
      // @ts-ignore
      const { getDocumentProxy } = await import("https://esm.sh/unpdf@0.12.1");
      // A CÓPIA é obrigatória, não zelo: o pdfjs assume a posse do array que
      // recebe e deixa o ArrayBuffer "detached" — depois dele, ler `bytes`
      // lança TypeError. Como as tentativas 2 e 3 recebem o MESMO `bytes`, a
      // rede de segurança inteira estava morta: sempre que o unpdf falhava sem
      // derrubar o worker, os dois fallbacks quebravam junto e a extração
      // voltava vazia. Medido: com o array direto o fallback não consegue ler
      // nada; com a cópia ele lê normalmente.
      const pdf = await getDocumentProxy(bytes.slice());
      const paginas = Number(pdf?.numPages || 0);

      if (paginas > 0 && paginas <= MAX_UNPDF_PAGINAS) {
        const partes: string[] = [];
        for (let i = 1; i <= paginas; i++) {
          const page = await pdf.getPage(i);
          const conteudo = await page.getTextContent();
          const linha = (conteudo?.items || [])
            .map((it: any) => (typeof it?.str === "string" ? it.str : ""))
            .join(" ");
          if (linha.trim()) partes.push(linha);
          // Devolve a memória da página antes de abrir a próxima. Sem isto o
          // consumo cresce página a página até derrubar o worker.
          try { page.cleanup(); } catch { /* cleanup é best-effort */ }
        }
        const joined = partes.join("\n");
        if (joined.trim().length > 100) {
          console.log(`unpdf extraction: ${joined.length} chars, ${paginas} paginas (${mb}MB)`);
          return joined;
        }
      } else {
        console.log(
          `PDF com ${paginas} paginas acima do teto de ${MAX_UNPDF_PAGINAS}: ` +
          `indo ao parser em blocos para nao estourar o tempo de CPU.`
        );
      }
    } catch (e: any) {
      console.warn("unpdf falhou:", e?.message || e);
    }
  } else {
    console.log(
      `PDF de ${mb}MB acima do teto de ${MAX_UNPDF_BYTES / 1024 / 1024}MB para o unpdf: ` +
      `indo direto ao parser em blocos para nao derrubar o worker.`
    );
  }

  // Tentativa 2: parser manual de streams (sem dependências), lido em BLOCOS
  try {
    const manual = extractPdfTextManual(bytes);
    if (manual.length > 100) {
      console.log(`manual extraction: ${manual.length} chars`);
      return manual;
    }
  } catch (e: any) {
    console.warn("manual extraction falhou:", e?.message || e);
  }

  // Tentativa 3: strings legíveis como último recurso
  return extractReadableStrings(bytes);
}

function extractPdfTextManual(bytes: Uint8Array): string {
  // Lê o arquivo em BLOCOS. A versão anterior fazia decoder.decode(bytes) do
  // arquivo inteiro: num PDF de 35MB isso sozinho custava ~37MB de pico, em
  // cima dos bytes originais e do que o unpdf já tinha consumido — combustível
  // para o worker morrer com 546. Medido: em blocos o mesmo arquivo custa
  // ~20MB e sai na metade do tempo, com texto idêntico caractere a caractere.
  //
  // A COSTURA é o que garante o "idêntico": um stream pode começar no fim de
  // um bloco e terminar no começo do próximo, então cada bloco é lido com uma
  // sobra à frente, e só contam os streams que COMEÇAM dentro do bloco (a
  // sobra existe para completá-los, não para achar novos — senão duplicaria).
  const decoder = new TextDecoder("latin1");
  const BLOCO = 2 * 1024 * 1024;      // 2 MB por vez
  const COSTURA = 256 * 1024;         // sobra para fechar stream que cruza a borda
  let text = "";
  let count = 0;
  let pos = 0;

  while (pos < bytes.length && count < 5000) {
    const fim = Math.min(pos + BLOCO, bytes.length);
    const raw = decoder.decode(bytes.subarray(pos, Math.min(fim + COSTURA, bytes.length)));

    const streamRegex = /stream\r?\n([\s\S]*?)\r?\nendstream/g;
    let streamMatch;
    while ((streamMatch = streamRegex.exec(raw)) !== null && count < 5000) {
      if (streamMatch.index >= fim - pos) break;  // começa no próximo bloco: é dele
      count++;
      const streamContent = streamMatch[1];

      const tjRegex = /\(([^)]{2,200})\)\s*Tj/g;
      let tjMatch;
      while ((tjMatch = tjRegex.exec(streamContent)) !== null) {
        const t = decodePdfString(tjMatch[1]);
        if (t.trim()) text += t + " ";
      }

      const arrTjRegex = /\[([^\]]{2,500})\]\s*TJ/g;
      let arrMatch;
      while ((arrMatch = arrTjRegex.exec(streamContent)) !== null) {
        const inner = arrMatch[1];
        const parts = inner.match(/\(([^)]{1,200})\)/g) || [];
        for (const p of parts) {
          const t = decodePdfString(p.slice(1, -1));
          if (t.trim()) text += t;
        }
        text += " ";
      }
    }
    pos = fim;
  }

  return cleanText(text);
}

function decodePdfString(s: string): string {
  return s
    .replace(/\\(\d{3})/g, (_, oct) => String.fromCharCode(parseInt(oct, 8)))
    .replace(/\\n/g, "\n")
    .replace(/\\r/g, "\r")
    .replace(/\\t/g, "\t")
    .replace(/\\\\/g, "\\")
    .replace(/\\([()\\])/g, "$1");
}

function extractReadableStrings(bytes: Uint8Array): string {
  // Decodifica em chunks para evitar pico de memória em PDFs grandes
  const decoder = new TextDecoder("latin1");
  const CHUNK = 1024 * 1024; // 1MB
  let out = "";
  for (let i = 0; i < bytes.length; i += CHUNK) {
    const slice = bytes.subarray(i, Math.min(i + CHUNK, bytes.length));
    const raw = decoder.decode(slice);
    const matches = raw.match(/[A-Za-zÀ-ÿ0-9\s.,;:!?()[\]{}"'@#$%&*+=\-_/]{6,}/g) || [];
    for (const s of matches) {
      if (/[A-Za-zÀ-ÿ]{3,}/.test(s)) out += s + " ";
    }
  }
  return cleanText(out);
}

async function extractDocxText(bytes: Uint8Array): Promise<string> {
  try {
    // @ts-ignore
    const JSZip = await import("npm:jszip@3.10.1");
    const zip = await JSZip.default.loadAsync(bytes);
    const docXml = zip.file("word/document.xml");
    if (!docXml) throw new Error("document.xml não encontrado");
    const xmlContent = await docXml.async("string");
    return xmlContent
      .replace(/<w:br[^>]*>/g, "\n")
      .replace(/<w:p[^>]*>/g, "\n")
      .replace(/<[^>]+>/g, " ")
      .replace(/\s{2,}/g, " ")
      .trim();
  } catch (e) {
    console.warn("DOCX extraction falhou:", e);
    return new TextDecoder("utf-8", { fatal: false }).decode(bytes);
  }
}

function cleanText(text: string): string {
  return text
    .replace(/\x00/g, "")
    .replace(/[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]/g, " ")
    .replace(/\s{3,}/g, "  ")
    .trim();
}
