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
import html2canvas from "html2canvas";
import jsPDF from "jspdf";

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
    if (!contentRef.current) return;
    setExporting(true);
    toast.info("Gerando PDF, aguarde...");

    try {
      const canvas = await html2canvas(contentRef.current, {
        scale: 2,
        useCORS: true,
        logging: false,
        windowWidth: 900,
      });

      const imgData = canvas.toDataURL("image/jpeg", 0.95);
      const pdf = new jsPDF("p", "mm", "a4");
      const pdfWidth = pdf.internal.pageSize.getWidth();
      const pdfHeight = pdf.internal.pageSize.getHeight();
      const imgWidth = pdfWidth - 20;
      const imgHeight = (canvas.height * imgWidth) / canvas.width;

      let heightLeft = imgHeight;
      let position = 10;

      pdf.addImage(imgData, "JPEG", 10, position, imgWidth, imgHeight);
      heightLeft -= pdfHeight - 20;

      while (heightLeft > 0) {
        position = position - pdfHeight + 20;
        pdf.addPage();
        pdf.addImage(imgData, "JPEG", 10, position, imgWidth, imgHeight);
        heightLeft -= pdfHeight - 20;
      }

      pdf.save("Manual_YourEyes.pdf");
      toast.success("PDF baixado com sucesso!");
    } catch {
      toast.error("Erro ao gerar PDF.");
    } finally {
      setExporting(false);
    }
  }, []);

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
