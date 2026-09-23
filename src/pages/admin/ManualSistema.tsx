import { useState, useEffect, useRef, useCallback } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft, BookOpen, Search, Printer, ChevronRight, Pencil, Save, X, Download, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { supabase } from "@/integrations/supabase/client";
import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";

// O arquivo estático vive em public/ e é servido SOB o base do build
// (import.meta.env.BASE_URL). Um caminho absoluto "/MANUAL_YourEyes.md" iria
// para a RAIZ do domínio (ex.: youreyes-dev.github.io/MANUAL_YourEyes.md), fora
// do subcaminho /youreyesnovo/teste/ — o host devolvia sua página 404 e ela era
// gravada como se fosse o manual. Com o base, resolve certo em teste, homologação
// e produção (onde o base é "/").
const MANUAL_URL = `${import.meta.env.BASE_URL}MANUAL_YourEyes.md`;

// O conteúdo válido do manual começa com um cabeçalho Markdown ("# ..."). Serve
// para NÃO gravar (nem exibir) uma página de erro HTML do host caso o arquivo
// não seja encontrado.
const pareceManual = (t?: string | null): t is string =>
  !!t && t.trimStart().startsWith("#");

// ── Geração do PDF no padrão ABNT (NBR 14724) ──────────────────────────────
// Gera TEXTO real (selecionável), não um print da tela. Padrão:
//   • Papel A4, fonte Arial (Helvetica) 12 no corpo, entrelinha 1,5;
//   • Margens 3 cm (esquerda/superior) e 2 cm (direita/inferior);
//   • Corpo justificado; títulos em negrito; número da página no canto
//     superior direito.
const PT_MM = 0.352778; // 1 ponto tipográfico em milímetros

function gerarManualPdf(md: string): jsPDF {
  const doc = new jsPDF({ unit: "mm", format: "a4" });
  const PAGE_W = 210, PAGE_H = 297;
  const ML = 30, MR = 20, MT = 30, MB = 20;
  const TEXT_W = PAGE_W - ML - MR;
  const FONT = "helvetica"; // equivalente ao Arial, aceito pela ABNT
  let y = MT;

  const newPage = () => { doc.addPage(); y = MT; };
  const emojiRe = /[\p{Extended_Pictographic}️•←-⇿⬀-⯿]/gu;
  const limpar = (s: string) => s.replace(emojiRe, "").replace(/\s+/g, " ").trim();

  type Word = { w: string; style: string; width: number };

  const medir = (txt: string, style: string, size: number) => {
    doc.setFont(FONT, style); doc.setFontSize(size); return doc.getTextWidth(txt);
  };

  const tokenizar = (texto: string) => {
    const limpo = texto.replace(emojiRe, "");
    const out: { t: string; style: string }[] = [];
    const re = /\*\*(.+?)\*\*|`(.+?)`|\*(.+?)\*/g;
    let last = 0, m: RegExpExecArray | null;
    while ((m = re.exec(limpo)) !== null) {
      if (m.index > last) out.push({ t: limpo.slice(last, m.index), style: "normal" });
      if (m[1] !== undefined) out.push({ t: m[1], style: "bold" });
      else if (m[2] !== undefined) out.push({ t: m[2], style: "normal" });
      else out.push({ t: m[3] as string, style: "italic" });
      last = re.lastIndex;
    }
    if (last < limpo.length) out.push({ t: limpo.slice(last), style: "normal" });
    return out;
  };

  const paragrafo = (
    texto: string,
    opts: { size?: number; lh?: number; indent?: number; justify?: boolean } = {},
  ) => {
    const size = opts.size ?? 12;
    const lh = opts.lh ?? 1.5;
    const indent = opts.indent ?? 0;
    const justify = opts.justify ?? true;
    const maxW = TEXT_W - indent;
    const spaceW = medir(" ", "normal", size);

    const words: Word[] = [];
    for (const tk of tokenizar(texto)) {
      for (const p of tk.t.split(/\s+/)) {
        if (p) words.push({ w: p, style: tk.style, width: medir(p, tk.style, size) });
      }
    }
    if (words.length === 0) return;

    const lines: { words: Word[]; natW: number }[] = [];
    let cur: Word[] = [], natW = 0;
    for (const wd of words) {
      if (cur.length === 0) { cur = [wd]; natW = wd.width; }
      else if (natW + spaceW + wd.width > maxW) { lines.push({ words: cur, natW }); cur = [wd]; natW = wd.width; }
      else { cur.push(wd); natW += spaceW + wd.width; }
    }
    if (cur.length) lines.push({ words: cur, natW });

    const lhmm = size * lh * PT_MM;
    lines.forEach((line, i) => {
      if (y + lhmm > PAGE_H - MB) newPage();
      const baseY = y + size * PT_MM * 0.9;
      const isLast = i === lines.length - 1;
      const gap = justify && !isLast && line.words.length > 1
        ? (maxW - line.natW) / (line.words.length - 1) : 0;
      let x = ML + indent;
      for (const wd of line.words) {
        doc.setFont(FONT, wd.style); doc.setFontSize(size);
        doc.text(wd.w, x, baseY);
        x += wd.width + spaceW + gap;
      }
      y += lhmm;
    });
    y += size * PT_MM * 0.35;
  };

  const titulo = (texto: string, nivel: number) => {
    const size = nivel === 1 ? 16 : nivel === 2 ? 13 : 12;
    const cleaned = limpar(texto);
    if (!cleaned) return;
    y += nivel <= 2 ? 5 : 3;
    doc.setFont(FONT, "bold"); doc.setFontSize(size);
    const linhas = doc.splitTextToSize(cleaned, TEXT_W) as string[];
    const lhmm = size * 1.2 * PT_MM;
    for (const l of linhas) {
      if (y + lhmm > PAGE_H - MB) newPage();
      const baseY = y + size * PT_MM * 0.9;
      if (nivel === 1) doc.text(l, PAGE_W / 2, baseY, { align: "center" });
      else doc.text(l, ML, baseY);
      y += lhmm;
    }
    y += 2;
  };

  const item = (texto: string, marcador: string, size = 12, indent = 8) => {
    if (y + size * 1.5 * PT_MM > PAGE_H - MB) newPage();
    doc.setFont(FONT, "normal"); doc.setFontSize(size);
    doc.text(marcador, ML + (indent - 6), y + size * PT_MM * 0.9);
    paragrafo(texto, { size, lh: 1.5, indent, justify: false });
  };

  const regua = () => {
    y += 2;
    if (y > PAGE_H - MB) newPage();
    doc.setDrawColor(210); doc.setLineWidth(0.2);
    doc.line(ML, y, PAGE_W - MR, y);
    y += 4;
  };

  const tabela = (head: string[], body: string[][]) => {
    autoTable(doc, {
      startY: y,
      head: [head.map(limpar)],
      body: body.map((r) => r.map(limpar)),
      margin: { left: ML, right: MR },
      tableWidth: TEXT_W,
      styles: { font: FONT, fontSize: 11, cellPadding: 2, valign: "top", textColor: [30, 30, 30], lineColor: [200, 200, 200], lineWidth: 0.1 },
      headStyles: { fillColor: [235, 235, 235], textColor: [20, 20, 20], fontStyle: "bold" },
      theme: "grid",
    });
    const fin = (doc as unknown as { lastAutoTable?: { finalY: number } }).lastAutoTable?.finalY;
    y = (fin ?? y) + 4;
  };

  // ── Parser do Markdown ──────────────────────────────────────────────────
  const linhas = md.replace(/\r/g, "").split("\n");
  let paraBuf: string[] = [];
  let quoteBuf: string[] = [];
  let tblBuf: string[] = [];

  const flushPara = () => { if (paraBuf.length) { paragrafo(paraBuf.join(" ")); paraBuf = []; } };
  const flushQuote = () => {
    if (!quoteBuf.length) return;
    for (const ql of quoteBuf) {
      const t = ql.trim();
      if (t === "") { y += 1.5; continue; }
      const b = t.match(/^[-*]\s+(.*)$/);
      if (b) item(b[1], "•", 11, 16);
      else paragrafo(t, { size: 11, lh: 1.25, indent: 12, justify: true });
    }
    quoteBuf = [];
  };
  const flushTable = () => {
    if (!tblBuf.length) return;
    const rows = tblBuf.map((r) => r.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((c) => c.trim()));
    const head = rows[0] ?? [];
    const body = rows.slice(1).filter((r) => !r.every((c) => /^:?-+:?$/.test(c) || c === ""));
    tblBuf = [];
    if (head.length) tabela(head, body);
  };

  for (const raw of linhas) {
    const line = raw.trimEnd();
    if (/^\s*\|/.test(line)) { flushPara(); flushQuote(); tblBuf.push(line); continue; }
    if (tblBuf.length) flushTable();

    if (/^\s*>/.test(line)) { flushPara(); quoteBuf.push(line.replace(/^\s*>\s?/, "")); continue; }
    if (quoteBuf.length) flushQuote();

    if (line.trim() === "") { flushPara(); continue; }
    const h = line.match(/^(#{1,4})\s+(.*)$/);
    if (h) { flushPara(); titulo(h[2], h[1].length); continue; }
    if (/^---+$/.test(line.trim())) { flushPara(); regua(); continue; }
    const ul = line.match(/^\s*[-*]\s+(.*)$/);
    if (ul) { flushPara(); item(ul[1], "•"); continue; }
    const ol = line.match(/^\s*(\d+)\.\s+(.*)$/);
    if (ol) { flushPara(); item(ol[2], `${ol[1]}.`); continue; }
    paraBuf.push(line.trim());
  }
  flushPara(); flushQuote(); flushTable();

  // Numeração de páginas (canto superior direito) — pós-processo, cobre também
  // páginas criadas pela renderização das tabelas.
  const total = doc.getNumberOfPages();
  for (let p = 1; p <= total; p++) {
    doc.setPage(p);
    doc.setFont(FONT, "normal"); doc.setFontSize(10); doc.setTextColor(90);
    doc.text(String(p), PAGE_W - MR, 15, { align: "right" });
  }
  doc.setTextColor(0);
  return doc;
}

function extractToc(md: string) {
  const lines = md.split("\n");
  const toc: { title: string; id: string }[] = [];
  for (const line of lines) {
    const match = line.match(/^## (.+)/);
    if (match) {
      const title = match[1].replace(/[🏛️🔐🏢👥💰🏖️📋🩺🔒🦺🧠📊📝📚🎓🎯📋🏗️🎉💚📢🏗️🚨📁🧾🌐⏰📰⚙️💬🤖📐🔒🏗️🎤]/g, "").trim();
      const id = title.toLowerCase().replace(/[^a-záàâãéèêíïóôõöúçñ0-9]+/gi, "-").replace(/-+/g, "-").replace(/^-|-$/g, "");
      toc.push({ title, id });
    }
  }
  return toc;
}

export default function ManualSistema() {
  const navigate = useNavigate();
  const [content, setContent] = useState("");
  const [editContent, setEditContent] = useState("");
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [activeSection, setActiveSection] = useState("");
  const contentRef = useRef<HTMLDivElement>(null);

  // Load manual: first try Supabase, fallback to static file
  useEffect(() => {
    async function loadManual() {
      const { data } = await supabase
        .from("system_manual")
        .select("content")
        .limit(1)
        .maybeSingle();

      if (pareceManual(data?.content)) {
        setContent(data.content);
        setLoading(false);
      } else {
        // Sem conteúdo válido no banco: carrega o arquivo estático e semeia.
        const res = await fetch(MANUAL_URL);
        const text = res.ok ? await res.text() : "";
        const bom = pareceManual(text) ? text : "";
        setContent(bom || "# Manual do Sistema\n\nNão foi possível carregar o manual agora. Recarregue a página.");
        setLoading(false);
        // Só semeia quando a tabela estava REALMENTE vazia (data == null) e o
        // texto é um manual de verdade — nunca grava página de erro do host,
        // e não cria uma 2ª linha por cima de um conteúdo inválido já existente.
        if (bom && !data) {
          await supabase.from("system_manual").insert({ content: bom });
        }
      }
    }
    loadManual();
  }, []);

  const startEditing = () => {
    setEditContent(content);
    setEditing(true);
  };

  const cancelEditing = () => {
    setEditing(false);
    setEditContent("");
  };

  const saveManual = async () => {
    setSaving(true);
    try {
      // Check if row exists
      const { data: existing } = await supabase
        .from("system_manual")
        .select("id")
        .limit(1)
        .maybeSingle();

      if (existing) {
        await supabase
          .from("system_manual")
          .update({ content: editContent, updated_at: new Date().toISOString() })
          .eq("id", existing.id);
      } else {
        await supabase.from("system_manual").insert({ content: editContent });
      }

      setContent(editContent);
      setEditing(false);
      toast.success("Manual salvo com sucesso!");
    } catch {
      toast.error("Erro ao salvar o manual.");
    } finally {
      setSaving(false);
    }
  };

  const exportPDF = useCallback(async () => {
    if (!pareceManual(content)) {
      toast.error("Manual sem conteúdo para exportar.");
      return;
    }
    setExporting(true);
    toast.info("Gerando PDF (padrão ABNT), aguarde...");

    try {
      // Texto real, formatado nas normas ABNT (ver gerarManualPdf).
      const doc = gerarManualPdf(content);
      doc.save("Manual_YourEyes.pdf");
      toast.success("PDF baixado com sucesso!");
    } catch (e) {
      console.error(e);
      toast.error("Erro ao gerar PDF.");
    } finally {
      setExporting(false);
    }
  }, [content]);

  const toc = extractToc(content);

  const scrollToSection = (id: string) => {
    setActiveSection(id);
    const el = document.getElementById(id);
    if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  return (
    <div className="min-h-screen bg-background print:bg-white">
      {/* Header */}
      <div className="sticky top-0 z-30 bg-card/95 backdrop-blur-sm border-b border-border px-6 py-3 print:hidden">
        <div className="max-w-[1400px] mx-auto flex items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <Button variant="ghost" size="icon" onClick={() => navigate("/admin")}>
              <ArrowLeft className="w-5 h-5" />
            </Button>
            <div className="flex items-center gap-2.5">
              <div className="p-1.5 rounded-lg bg-primary/10">
                <BookOpen className="w-5 h-5 text-primary" />
              </div>
              <div>
                <h1 className="text-lg font-bold text-foreground leading-tight">Manual do Sistema</h1>
                <p className="text-xs text-muted-foreground">YourEyes — Documentação Completa</p>
              </div>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {!editing && (
              <div className="relative w-56 hidden md:block">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                <Input
                  placeholder="Buscar no manual..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  className="pl-9 h-9 text-sm"
                />
              </div>
            )}

            {editing ? (
              <>
                <Button variant="outline" size="sm" onClick={cancelEditing} disabled={saving}>
                  <X className="w-4 h-4 mr-1.5" />
                  Cancelar
                </Button>
                <Button size="sm" onClick={saveManual} disabled={saving}>
                  {saving ? <Loader2 className="w-4 h-4 mr-1.5 animate-spin" /> : <Save className="w-4 h-4 mr-1.5" />}
                  Salvar
                </Button>
              </>
            ) : (
              <>
                <Button variant="outline" size="sm" onClick={startEditing}>
                  <Pencil className="w-4 h-4 mr-1.5" />
                  Editar
                </Button>
                <Button variant="outline" size="sm" onClick={exportPDF} disabled={exporting}>
                  {exporting ? <Loader2 className="w-4 h-4 mr-1.5 animate-spin" /> : <Download className="w-4 h-4 mr-1.5" />}
                  Baixar PDF
                </Button>
                <Button variant="outline" size="sm" onClick={() => window.print()}>
                  <Printer className="w-4 h-4 mr-1.5" />
                  Imprimir
                </Button>
              </>
            )}
          </div>
        </div>
      </div>

      <div className="max-w-[1400px] mx-auto flex">
        {/* Sidebar TOC */}
        {!editing && (
          <aside className="hidden lg:block w-72 shrink-0 sticky top-[57px] h-[calc(100vh-57px)] overflow-y-auto border-r border-border py-6 px-4 print:hidden">
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3 px-2">Índice</p>
            <nav className="space-y-0.5">
              {toc.map((item) => (
                <button
                  key={item.id}
                  onClick={() => scrollToSection(item.id)}
                  className={`w-full text-left text-sm px-3 py-2 rounded-lg transition-colors flex items-center gap-2 ${
                    activeSection === item.id
                      ? "bg-primary/10 text-primary font-medium"
                      : "text-muted-foreground hover:text-foreground hover:bg-muted/50"
                  }`}
                >
                  <ChevronRight className={`w-3.5 h-3.5 shrink-0 transition-transform ${activeSection === item.id ? "rotate-90" : ""}`} />
                  <span className="truncate">{item.title}</span>
                </button>
              ))}
            </nav>
          </aside>
        )}

        {/* Content */}
        <main className="flex-1 min-w-0 px-6 md:px-10 py-8 print:px-0">
          {loading ? (
            <div className="flex items-center justify-center py-20">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
            </div>
          ) : editing ? (
            <div className="space-y-4">
              <p className="text-sm text-muted-foreground">Edite o conteúdo Markdown abaixo:</p>
              <Textarea
                value={editContent}
                onChange={(e) => setEditContent(e.target.value)}
                className="min-h-[70vh] font-mono text-sm leading-relaxed"
                placeholder="Conteúdo do manual em Markdown..."
              />
            </div>
          ) : (
            <article className="manual-content" ref={contentRef}>
              <ReactMarkdown
                remarkPlugins={[remarkGfm]}
                components={{
                  h1: ({ children }) => (
                    <div className="mb-8 pb-6 border-b-2 border-primary/20">
                      <h1 className="text-3xl md:text-4xl font-extrabold text-foreground tracking-tight">{children}</h1>
                    </div>
                  ),
                  h2: ({ children }) => {
                    const text = String(children).replace(/[🏛️🔐🏢👥💰🏖️📋🩺🔒🦺🧠📊📝📚🎓🎯📋🏗️🎉💚📢🏗️🚨📁🧾🌐⏰📰⚙️💬🤖📐🔒🏗️🎤]/g, "").trim();
                    const id = text.toLowerCase().replace(/[^a-záàâãéèêíïóôõöúçñ0-9]+/gi, "-").replace(/-+/g, "-").replace(/^-|-$/g, "");
                    return (
                      <h2 id={id} className="text-xl md:text-2xl font-bold text-foreground mt-12 mb-4 pt-6 border-t border-border scroll-mt-20 flex items-center gap-3">
                        <span className="w-1 h-7 rounded-full bg-primary inline-block shrink-0" />
                        {children}
                      </h2>
                    );
                  },
                  h3: ({ children }) => (
                    <h3 className="text-lg font-semibold text-foreground mt-6 mb-3">{children}</h3>
                  ),
                  h4: ({ children }) => (
                    <h4 className="text-base font-semibold text-foreground mt-4 mb-2">{children}</h4>
                  ),
                  p: ({ children }) => (
                    <p className="text-sm leading-relaxed text-muted-foreground mb-3">{children}</p>
                  ),
                  strong: ({ children }) => (
                    <strong className="font-semibold text-foreground">{children}</strong>
                  ),
                  ul: ({ children }) => (
                    <ul className="space-y-1.5 mb-4 ml-1">{children}</ul>
                  ),
                  ol: ({ children }) => (
                    <ol className="space-y-1.5 mb-4 ml-1 list-decimal list-inside">{children}</ol>
                  ),
                  li: ({ children }) => (
                    <li className="text-sm text-muted-foreground flex items-start gap-2">
                      <span className="w-1.5 h-1.5 rounded-full bg-primary/40 mt-2 shrink-0" />
                      <span className="flex-1">{children}</span>
                    </li>
                  ),
                  blockquote: ({ children }) => (
                    <blockquote className="border-l-4 border-primary bg-primary/5 rounded-r-lg px-5 py-4 my-4 text-sm text-foreground italic">
                      {children}
                    </blockquote>
                  ),
                  table: ({ children }) => (
                    <div className="overflow-x-auto my-4 rounded-lg border border-border">
                      <table className="w-full text-sm">{children}</table>
                    </div>
                  ),
                  thead: ({ children }) => (
                    <thead className="bg-muted/70">{children}</thead>
                  ),
                  th: ({ children }) => (
                    <th className="text-left px-4 py-2.5 text-xs font-semibold text-foreground uppercase tracking-wider border-b border-border">
                      {children}
                    </th>
                  ),
                  td: ({ children }) => (
                    <td className="px-4 py-2.5 text-sm text-muted-foreground border-b border-border/50">
                      {children}
                    </td>
                  ),
                  hr: () => <hr className="my-8 border-border" />,
                  code: ({ children, className }) => {
                    if (className) {
                      return (
                        <pre className="bg-muted rounded-lg p-4 overflow-x-auto my-4 text-xs">
                          <code className="text-foreground">{children}</code>
                        </pre>
                      );
                    }
                    return (
                      <code className="bg-muted text-primary text-xs font-mono px-1.5 py-0.5 rounded">
                        {children}
                      </code>
                    );
                  },
                }}
              >
                {content}
              </ReactMarkdown>
            </article>
          )}
        </main>
      </div>
    </div>
  );
}
