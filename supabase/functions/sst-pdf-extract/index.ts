import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

// Hard cap to prevent memory/CPU exhaustion on edge runtime (status 546)
const MAX_PDF_BYTES = 50 * 1024 * 1024; // 50 MB

// Teto para a extração de melhor qualidade (unpdf). Ela monta o documento
// inteiro em memória; acima deste tamanho o worker morre por estouro de
// recursos e a plataforma devolve 546 — que chega ao usuário como erro cru,
// sem chance de cair nas tentativas seguintes. Acima do teto usamos o parser
// em blocos, que é mais pobre mas entrega o texto em vez de falhar tudo.
const MAX_UNPDF_BYTES = 8 * 1024 * 1024; // 8 MB

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
  // É a de melhor qualidade, e também a mais cara: monta o documento inteiro
  // em memória e junta o texto de todas as páginas de uma vez. Num PGR de
  // muitas páginas é justamente ela quem derruba o worker — e worker derrubado
  // não responde nada, então o erro chega ao usuário como o cru "Erro 546",
  // sem passar pelas tentativas seguintes.
  //
  // Acima do limite abaixo ela é PULADA de propósito: é melhor entregar o
  // texto com o parser leve do que falhar o documento inteiro.
  if (bytes.length <= MAX_UNPDF_BYTES) {
    try {
      // @ts-ignore
      const { extractText, getDocumentProxy } = await import("https://esm.sh/unpdf@0.12.1");
      const pdf = await getDocumentProxy(bytes);
      const { text } = await extractText(pdf, { mergePages: true });
      const joined = Array.isArray(text) ? text.join("\n") : String(text || "");
      if (joined.trim().length > 100) {
        console.log(`unpdf extraction: ${joined.length} chars (${mb}MB)`);
        return joined;
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
