import { useState, useRef, useCallback } from "react";
import { FileText, Upload, Loader2, Check, X, Sparkles, ClipboardPaste } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { Checkbox } from "@/components/ui/checkbox";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

interface AtividadeExtraida {
  nome: string;
  descricao: string;
  frequencia: string;
  complexidade: string;
  classificacao: string;
  selecionada: boolean;
}

interface TextoAtividadesImportProps {
  funcaoNome?: string;
  onImportar: (atividades: Omit<AtividadeExtraida, "selecionada">[]) => Promise<void>;
}

const FREQ_LABELS: Record<string, string> = { diaria: "Diária", semanal: "Semanal", mensal: "Mensal", eventual: "Eventual" };
const COMPL_LABELS: Record<string, string> = { baixa: "Baixa", media: "Média", alta: "Alta" };
const CLASS_LABELS: Record<string, string> = { rotineira: "Rotineira", critica: "Crítica", excepcional: "Excepcional" };

export function TextoAtividadesImport({ funcaoNome, onImportar }: TextoAtividadesImportProps) {
  const [open, setOpen] = useState(false);
  const [step, setStep] = useState<"input" | "processando" | "resultado">("input");
  const [texto, setTexto] = useState("");
  const [atividades, setAtividades] = useState<AtividadeExtraida[]>([]);
  const [importando, setImportando] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const MAX_CHARS = 30000;

  const processarTexto = useCallback(async (conteudoBruto: string) => {
    const conteudo = conteudoBruto.length > MAX_CHARS
      ? conteudoBruto.slice(0, MAX_CHARS)
      : conteudoBruto;

    if (conteudo.trim().length < 20) {
      toast.error("Texto muito curto. Forneça uma descrição mais detalhada.");
      return;
    }

    if (conteudoBruto.length > MAX_CHARS) {
      toast.info(`Texto longo: usando os primeiros ${MAX_CHARS.toLocaleString("pt-BR")} caracteres para extração.`);
    }

    setStep("processando");
    try {
      const { data, error } = await supabase.functions.invoke("ai-texto-atividades", {
        body: { texto: conteudo, funcaoNome },
      });

      if (error) throw new Error(error.message);
      if (data?.error) throw new Error(data.error);

      setAtividades((data.atividades || []).map((a: any) => ({ ...a, selecionada: true })));
      setStep("resultado");
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Erro ao processar texto";
      toast.error(msg);
      setStep("input");
    }
  }, [funcaoNome]);

  const handleFileUpload = useCallback(async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const allowedExtensions = [".txt", ".csv", ".md", ".text", ".doc", ".docx"];
    const ext = file.name.toLowerCase().substring(file.name.lastIndexOf("."));

    if (!allowedExtensions.includes(ext)) {
      toast.error("Formato não suportado. Use .txt, .csv, .md, .doc ou .docx");
      e.target.value = "";
      return;
    }

    try {
      let conteudo = "";

      if (ext === ".docx" || ext === ".doc") {
        try {
          const mammoth = await import("mammoth");
          const arrayBuffer = await file.arrayBuffer();
          const result = await mammoth.extractRawText({ arrayBuffer });
          conteudo = (result.value || "").trim();
          if (!conteudo) {
            toast.error("Não foi possível extrair texto do arquivo. Tente salvar como .docx ou .txt.");
            e.target.value = "";
            return;
          }
        } catch (docErr) {
          console.error("Erro ao ler DOCX:", docErr);
          toast.error("Erro ao ler arquivo Word. Para .doc antigos, salve como .docx e tente novamente.");
          e.target.value = "";
          return;
        }
      } else {
        conteudo = await file.text();
      }

      // Normaliza quebras e remove caracteres de controle problemáticos
      conteudo = conteudo
        .replace(/\r\n/g, "\n")
        .replace(/\u0000/g, "")
        .trim();

      setTexto(conteudo);
      toast.success(`Arquivo carregado (${conteudo.length.toLocaleString("pt-BR")} caracteres)`);
      await processarTexto(conteudo);
    } catch (err) {
      console.error("Erro ao ler arquivo:", err);
      toast.error("Erro ao ler o arquivo");
    }
    e.target.value = "";
  }, [processarTexto]);

  const toggleAtividade = (index: number) => {
    setAtividades(prev => prev.map((a, i) => i === index ? { ...a, selecionada: !a.selecionada } : a));
  };

  const toggleTodas = () => {
    const todasSelecionadas = atividades.every(a => a.selecionada);
    setAtividades(prev => prev.map(a => ({ ...a, selecionada: !todasSelecionadas })));
  };

  const handleImportar = async () => {
    const selecionadas = atividades.filter(a => a.selecionada);
    if (selecionadas.length === 0) {
      toast.error("Selecione ao menos uma atividade");
      return;
    }

    setImportando(true);
    try {
      await onImportar(selecionadas.map(({ selecionada, ...rest }) => rest));
      toast.success(`${selecionadas.length} atividade(s) importada(s) com sucesso!`);
      handleClose();
    } catch (e: any) {
      console.error("Falha ao importar atividades:", e);
      toast.error(e?.message ? `Erro ao importar: ${e.message}` : "Erro ao importar atividades");
    } finally {
      setImportando(false);
    }
  };

  const handleClose = () => {
    setOpen(false);
    setStep("input");
    setAtividades([]);
    setTexto("");
  };

  const selecionadasCount = atividades.filter(a => a.selecionada).length;
  const complColor: Record<string, string> = { baixa: "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300", media: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-300", alta: "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300" };

  return (
    <>
      <Button variant="outline" size="sm" className="gap-1.5" onClick={() => setOpen(true)}>
        <FileText className="w-4 h-4" /> Importar por Texto
      </Button>

      <input type="file" ref={fileInputRef} className="hidden" accept=".txt,.csv,.md,.text,.doc,.docx,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document" onChange={handleFileUpload} />

      <Dialog open={open} onOpenChange={(v) => { if (!v) handleClose(); }}>
        <DialogContent className="max-w-2xl h-[85vh] overflow-hidden flex flex-col">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Sparkles className="w-5 h-5 text-primary" /> Importar Atividades por Texto
            </DialogTitle>
            <DialogDescription>
              Cole uma descrição de cargo, job description ou texto descritivo. A IA extrairá as atividades automaticamente.
            </DialogDescription>
          </DialogHeader>

          {step === "input" && (
            <div className="flex flex-col gap-4 py-2">
              <Tabs defaultValue="colar" className="w-full">
                <TabsList className="grid w-full grid-cols-2">
                  <TabsTrigger value="colar" className="gap-1.5">
                    <ClipboardPaste className="w-3.5 h-3.5" /> Colar Texto
                  </TabsTrigger>
                  <TabsTrigger value="arquivo" className="gap-1.5">
                    <Upload className="w-3.5 h-3.5" /> Enviar Arquivo
                  </TabsTrigger>
                </TabsList>

                <TabsContent value="colar" className="space-y-3 mt-3">
                  <Textarea
                    placeholder="Cole aqui a descrição do cargo, job description, lista de atividades ou qualquer texto descritivo da função..."
                    value={texto}
                    onChange={(e) => setTexto(e.target.value)}
                    rows={10}
                    className="resize-none text-sm"
                  />
                  <div className="flex items-center justify-between">
                    <span className="text-xs text-muted-foreground">
                      {texto.length > 0 ? `${texto.length} caracteres` : "Mínimo 20 caracteres"}
                    </span>
                    <Button
                      className="gap-2"
                      onClick={() => processarTexto(texto)}
                      disabled={texto.trim().length < 20}
                    >
                      <Sparkles className="w-4 h-4" /> Extrair Atividades com IA
                    </Button>
                  </div>
                </TabsContent>

                <TabsContent value="arquivo" className="mt-3">
                  <div
                    className="border-2 border-dashed border-border rounded-lg p-8 text-center cursor-pointer hover:border-primary/50 hover:bg-primary/5 transition-colors"
                    onClick={() => fileInputRef.current?.click()}
                  >
                    <Upload className="w-10 h-10 text-muted-foreground mx-auto mb-3" />
                    <p className="text-sm font-medium text-foreground">Clique para selecionar um arquivo</p>
                    <p className="text-xs text-muted-foreground mt-1">Formatos aceitos: .txt, .csv, .md, .doc, .docx</p>
                  </div>
                </TabsContent>
              </Tabs>
            </div>
          )}

          {step === "processando" && (
            <div className="flex flex-col items-center gap-4 py-12">
              <Loader2 className="w-10 h-10 animate-spin text-primary" />
              <p className="text-sm text-muted-foreground">Analisando texto e extraindo atividades...</p>
              <p className="text-xs text-muted-foreground">Isso pode levar alguns segundos</p>
            </div>
          )}

          {step === "resultado" && (
            <div className="flex flex-col gap-3 min-h-0 flex-1 overflow-hidden">
              <div className="flex items-center justify-between flex-shrink-0">
                <p className="text-sm font-medium">{atividades.length} atividade(s) identificada(s)</p>
                <Button variant="ghost" size="sm" onClick={toggleTodas}>
                  {atividades.every(a => a.selecionada) ? "Desmarcar todas" : "Selecionar todas"}
                </Button>
              </div>

              <ScrollArea className="flex-1 min-h-0">
                <div className="space-y-2 pr-3">
                  {atividades.map((at, i) => (
                    <div
                      key={i}
                      className={`border rounded-lg p-3 cursor-pointer transition-colors ${at.selecionada ? "border-primary bg-primary/5" : "border-border opacity-60"}`}
                      onClick={() => toggleAtividade(i)}
                    >
                      <div className="flex items-start gap-3">
                        <Checkbox checked={at.selecionada} className="mt-0.5" />
                        <div className="flex-1 min-w-0">
                          <p className="font-medium text-sm">{at.nome}</p>
                          <p className="text-xs text-muted-foreground mt-1 line-clamp-2">{at.descricao}</p>
                          <div className="flex gap-1.5 mt-2 flex-wrap">
                            <Badge variant="outline" className="text-xs">{FREQ_LABELS[at.frequencia] || at.frequencia}</Badge>
                            <Badge className={`text-xs ${complColor[at.complexidade] || ""}`}>{COMPL_LABELS[at.complexidade] || at.complexidade}</Badge>
                            <Badge className="text-xs bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-300">{CLASS_LABELS[at.classificacao] || at.classificacao}</Badge>
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </ScrollArea>

              <div className="flex items-center justify-between pt-2 border-t flex-shrink-0">
                <Button variant="ghost" onClick={() => { setStep("input"); setAtividades([]); }}>
                  <X className="w-4 h-4 mr-1" /> Voltar
                </Button>
                <Button className="gap-2" onClick={handleImportar} disabled={importando || selecionadasCount === 0}>
                  {importando ? <Loader2 className="w-4 h-4 animate-spin" /> : <Check className="w-4 h-4" />}
                  Importar {selecionadasCount} atividade(s)
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}
