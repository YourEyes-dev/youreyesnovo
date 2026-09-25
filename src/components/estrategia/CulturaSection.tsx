import { useState, useEffect, useRef } from "react";
import { Heart, Plus, X, Save, Loader2, Sparkles, Wand2, Eye, LayoutGrid, ListTodo, FileText, Upload, Download } from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { useEstrategia } from "@/hooks/useEstrategia";
import { useAuth } from "@/hooks/useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import type { EstrategiaOrganograma } from "@/types/estrategia";
import type { EstrategiaEscopo } from "./EstrategiaEscopoSelector";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { toast } from "sonner";
import { ManualCulturaModal } from "./ManualCulturaModal";
import { arquivarDocumento } from "@/utils/arquivarDocumento";
import { useQuery } from "@tanstack/react-query";

type ListField = "valores" | "principios" | "comportamentos_esperados" | "comportamentos_nao_tolerados";

export function CulturaSection({ escopo }: { escopo: EstrategiaEscopo }) {
  const { cultura, loadingCultura, upsertCultura, organograma } = useEstrategia(escopo);
  const { profile, tenantId, user } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const [form, setForm] = useState({
    missao: "",
    visao: "",
    valores: [] as string[],
    principios: [] as string[],
    comportamentos_esperados: [] as string[],
    comportamentos_nao_tolerados: [] as string[],
  });
  const [newValue, setNewValue] = useState({ valores: "", principios: "", comportamentos_esperados: "", comportamentos_nao_tolerados: "" });
  const [activeTab, setActiveTab] = useState("editor");
  const [manualOpen, setManualOpen] = useState(false);
  const [manualHtml, setManualHtml] = useState("");
  const [manualLoading, setManualLoading] = useState(false);
  const [aiLoading, setAiLoading] = useState<string | null>(null);

  // Load cached manual
  const { data: cachedManual, refetch: refetchCached } = useQuery({
    queryKey: ["manuais_gerados", tenantId, "cultura"],
    queryFn: async () => {
      if (!tenantId) return null;
      const { data } = await fromTable("manuais_gerados")
        .select("id, titulo, html, created_at")
        .eq("tenant_id", tenantId)
        .eq("tipo", "cultura")
        .order("created_at", { ascending: false })
        .limit(1) as { data: any[] | null };
      return data?.[0] || null;
    },
    enabled: !!tenantId,
  });

  // Manual de cultura ENVIADO pela empresa (upload). Fica salvo no módulo de
  // Documentos (bucket privado "documentos"); aqui só listamos o mais recente.
  const TIPO_MANUAL_ENVIADO = "Manual de Cultura (enviado)";
  const ACCEPT_MANUAL = ".pdf,.doc,.docx,application/pdf,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document";
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [uploadingManual, setUploadingManual] = useState(false);

  const { data: uploadedManual, refetch: refetchUploaded } = useQuery({
    queryKey: ["manual_cultura_enviado", tenantId],
    queryFn: async () => {
      if (!tenantId) return null;
      const { data } = await fromTable("documentos")
        .select("id, nome_original, storage_path, created_at")
        .eq("tenant_id", tenantId)
        .eq("tipo", TIPO_MANUAL_ENVIADO)
        .order("created_at", { ascending: false })
        .limit(1) as { data: any[] | null };
      return data?.[0] || null;
    },
    enabled: !!tenantId,
  });

  const handleUploadManual = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (e.target) e.target.value = ""; // permite reenviar o mesmo arquivo
    if (!file) return;
    if (!tenantId || !user) { toast.error("Sessão inválida."); return; }
    const nome = file.name.toLowerCase();
    const extOk = [".pdf", ".doc", ".docx"].some((ext) => nome.endsWith(ext));
    if (!extOk) { toast.error("Envie um arquivo PDF ou Word (.pdf, .doc, .docx)."); return; }
    if (file.size > 20 * 1024 * 1024) { toast.error("Arquivo muito grande (máx. 20 MB)."); return; }
    setUploadingManual(true);
    try {
      const res = await arquivarDocumento({
        tenantId,
        empresaId: empresaAtivaId || null,
        userId: user.id,
        userNome: profile?.nome_completo || user.email || "",
        file,
        fileName: file.name,
        mimeType: file.type || "application/octet-stream",
        tipo: TIPO_MANUAL_ENVIADO,
        pastaCategoria: "Cultura",
        observacoes: "Manual de Cultura enviado pela empresa (upload).",
      });
      if (!res) throw new Error("Falha no envio.");
      toast.success("Manual de cultura enviado e salvo!");
      refetchUploaded();
    } catch (err: any) {
      toast.error("Não foi possível enviar o manual. " + (err?.message || ""));
    } finally {
      setUploadingManual(false);
    }
  };

  const handleDownloadUploaded = async () => {
    if (!uploadedManual?.storage_path) return;
    const { data, error } = await supabase.storage
      .from("documentos")
      .createSignedUrl(uploadedManual.storage_path, 60);
    if (error || !data?.signedUrl) { toast.error("Não foi possível gerar o link para download."); return; }
    window.open(data.signedUrl, "_blank");
  };

  useEffect(() => {
    // Reset form whenever the active scope (empresa/grupo) changes,
    // so switching empresas doesn't carry over stale Missão/Visão/Valores.
    if (cultura) {
      setForm({
        missao: cultura.missao || "",
        visao: cultura.visao || "",
        valores: Array.isArray(cultura.valores) ? cultura.valores : [],
        principios: Array.isArray(cultura.principios) ? cultura.principios : [],
        comportamentos_esperados: Array.isArray(cultura.comportamentos_esperados) ? cultura.comportamentos_esperados : [],
        comportamentos_nao_tolerados: Array.isArray(cultura.comportamentos_nao_tolerados) ? cultura.comportamentos_nao_tolerados : [],
      });
    } else {
      setForm({
        missao: "",
        visao: "",
        valores: [],
        principios: [],
        comportamentos_esperados: [],
        comportamentos_nao_tolerados: [],
      });
    }
  }, [cultura, empresaAtivaId, escopo?.tipo, escopo?.grupoId]);

  const addItem = (field: ListField) => {
    const val = newValue[field].trim();
    if (!val) return;
    setForm({ ...form, [field]: [...form[field], val] });
    setNewValue({ ...newValue, [field]: "" });
  };

  const removeItem = (field: ListField, idx: number) => {
    setForm({ ...form, [field]: form[field].filter((_, i) => i !== idx) });
  };

  const handleSave = () => {
    upsertCultura.mutate(form);
  };

  const handleAiSuggest = async (campo: string) => {
    setAiLoading(campo);
    try {
      const contexto: Record<string, any> = {
        missao: form.missao,
        visao: form.visao,
        valores: form.valores,
        principios: form.principios,
      };

      if (campo === "valores") contexto.valores_existentes = form.valores;
      if (campo === "principios") contexto.principios_existentes = form.principios;
      if (campo === "comportamentos_esperados") contexto.existentes = form.comportamentos_esperados;
      if (campo === "comportamentos_nao_tolerados") contexto.existentes = form.comportamentos_nao_tolerados;

      const { data, error } = await supabase.functions.invoke("ai-cultura-sugestao", {
        body: { campo, contexto, tenantId },
      });

      if (error) throw error;
      if (data?.error) {
        toast.error(data.error);
        return;
      }

      if (campo === "missao" || campo === "visao") {
        setForm(prev => ({ ...prev, [campo]: data.texto || "" }));
        toast.success(`${campo === "missao" ? "Missão" : "Visão"} gerada pela IA!`);
      } else {
        const items: string[] = data.items || [];
        if (items.length === 0) {
          toast.info("A IA não retornou sugestões. Tente novamente.");
          return;
        }
        const existing = new Set(form[campo as ListField].map(s => s.toLowerCase()));
        const newItems = items.filter(i => !existing.has(i.toLowerCase()));
        if (newItems.length === 0) {
          toast.info("Todas as sugestões já estão na lista.");
          return;
        }
        setForm(prev => ({ ...prev, [campo]: [...prev[campo as ListField], ...newItems] }));
        toast.success(`${newItems.length} sugestão(ões) adicionada(s)!`);
      }
    } catch (err: any) {
      console.error("Erro IA:", err);
      toast.error("Erro ao gerar sugestão. Tente novamente.");
    } finally {
      setAiLoading(null);
    }
  };

  const saveManualCache = async (html: string) => {
    if (!tenantId || !user) return;
    try {
      await fromTable("manuais_gerados")
        .delete()
        .eq("tenant_id", tenantId)
        .eq("tipo", "cultura");

      await fromTable("manuais_gerados").insert({
        tenant_id: tenantId,
        empresa_id: empresaAtivaId || null,
        tipo: "cultura",
        referencia_id: null,
        titulo: "Manual de Cultura Organizacional",
        html,
        gerado_por: user.id,
        gerado_por_nome: profile?.nome_completo || "",
      } as any);

      refetchCached();
    } catch (err) {
      console.error("Erro ao salvar cache:", err);
    }
  };

  const archiveManual = async (html: string) => {
    if (!tenantId || !user) return;
    try {
      const blob = new Blob([html], { type: "text/html;charset=utf-8" });
      await arquivarDocumento({
        tenantId,
        empresaId: empresaAtivaId,
        userId: user.id,
        userNome: profile?.nome_completo || "",
        file: blob,
        fileName: `manual-cultura-${Date.now()}.html`,
        mimeType: "text/html",
        tipo: "Manual de Cultura",
        observacoes: "Manual de Cultura Organizacional gerado por IA",
        pastaCategoria: "Cultura",
      });
    } catch (err) {
      console.error("Erro ao arquivar:", err);
    }
  };

  const handleGenerateManual = async () => {
    const hasContent = form.missao || form.visao || form.valores.length > 0 || form.principios.length > 0;
    if (!hasContent) {
      toast.error("Preencha ao menos Missão, Visão ou Valores antes de gerar o manual.");
      return;
    }

    setManualOpen(true);
    setManualLoading(true);
    setManualHtml("");

    try {
      const { data, error } = await supabase.functions.invoke("ai-cultura-manual", {
        body: {
          ...form,
          empresa_nome: profile?.nome_completo || "Nossa Empresa",
          organograma: organograma || [],
          tenantId,
        },
      });

      if (error) throw error;
      if (data?.error) {
        toast.error(data.error);
        setManualOpen(false);
        return;
      }

      const html = data.html || "";
      setManualHtml(html);

      await saveManualCache(html);
      await archiveManual(html);

      toast.success("Manual gerado e arquivado com sucesso!");
    } catch (err: any) {
      console.error("Erro ao gerar manual:", err);
      toast.error("Erro ao gerar o manual. Tente novamente.");
      setManualOpen(false);
    } finally {
      setManualLoading(false);
    }
  };

  const handleViewCached = () => {
    if (!cachedManual) return;
    setManualHtml(cachedManual.html);
    setManualOpen(true);
  };

  const handlePdfArchive = async (blob: Blob, filename: string) => {
    if (!tenantId || !user) return;
    try {
      await arquivarDocumento({
        tenantId,
        empresaId: empresaAtivaId,
        userId: user.id,
        userNome: profile?.nome_completo || "",
        file: blob,
        fileName: filename,
        mimeType: "application/pdf",
        tipo: "Manual de Cultura (PDF)",
        observacoes: "PDF do Manual de Cultura Organizacional",
        pastaCategoria: "Cultura",
      });
      toast.success("PDF arquivado no módulo Documentos!");
    } catch (err) {
      console.error("Erro ao arquivar PDF:", err);
    }
  };

  if (loadingCultura) {
    return <div className="flex justify-center py-12"><Loader2 className="w-6 h-6 animate-spin text-muted-foreground" /></div>;
  }

  const listFields = [
    { key: "valores" as const, label: "Valores", color: "bg-primary/10 text-primary" },
    { key: "principios" as const, label: "Princípios Culturais", color: "bg-accent text-accent-foreground" },
    { key: "comportamentos_esperados" as const, label: "Comportamentos Esperados", color: "bg-emerald-100 text-emerald-800" },
    { key: "comportamentos_nao_tolerados" as const, label: "Comportamentos Não Tolerados", color: "bg-red-100 text-red-800" },
  ];

  const AiButton = ({ campo, label }: { campo: string; label: string }) => (
    <Button
      variant="ghost"
      size="sm"
      className="text-xs gap-1 h-7 text-primary hover:text-primary/80"
      onClick={() => handleAiSuggest(campo)}
      disabled={aiLoading !== null}
    >
      {aiLoading === campo ? (
        <Loader2 className="w-3 h-3 animate-spin" />
      ) : (
        <Wand2 className="w-3 h-3" />
      )}
      {aiLoading === campo ? "Gerando..." : `Sugerir com IA`}
    </Button>
  );

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <Heart className="w-5 h-5 text-primary" /> Cultura Organizacional
          </h3>
          <p className="text-sm text-muted-foreground">Formalize e gerencie a identidade cultural da empresa</p>
          {uploadedManual && (
            <p className="text-xs text-muted-foreground mt-1 flex items-center gap-1">
              <FileText className="w-3.5 h-3.5" /> Manual enviado: <span className="font-medium">{uploadedManual.nome_original}</span>
            </p>
          )}
        </div>
        <div className="flex items-center gap-2 flex-wrap sm:justify-end">
          {activeTab === "editor" && (
            <>
              {cachedManual && (
                <Button variant="outline" size="sm" onClick={handleViewCached}>
                  <Eye className="w-4 h-4 mr-1" /> Ver Manual
                </Button>
              )}
              <Button variant="outline" size="sm" onClick={handleGenerateManual} disabled={manualLoading}>
                <Sparkles className="w-4 h-4 mr-1" /> {cachedManual ? "Regerar Manual" : "Gerar Manual com IA"}
              </Button>
              {uploadedManual && (
                <Button variant="outline" size="sm" onClick={handleDownloadUploaded}>
                  <Download className="w-4 h-4 mr-1" /> Baixar enviado
                </Button>
              )}
              <Button variant="outline" size="sm" onClick={() => fileInputRef.current?.click()} disabled={uploadingManual}>
                {uploadingManual ? <Loader2 className="w-4 h-4 mr-1 animate-spin" /> : <Upload className="w-4 h-4 mr-1" />}
                {uploadedManual ? "Substituir enviado" : "Enviar manual pronto"}
              </Button>
              <input ref={fileInputRef} type="file" accept={ACCEPT_MANUAL} className="hidden" onChange={handleUploadManual} />
              <Button size="sm" onClick={handleSave} disabled={upsertCultura.isPending}>
                <Save className="w-4 h-4 mr-1" /> {upsertCultura.isPending ? "Salvando..." : "Salvar"}
              </Button>
            </>
          )}
        </div>
      </div>

      <Tabs value={activeTab} onValueChange={setActiveTab} className="w-full">
        <TabsList className="grid w-full grid-cols-2 max-w-[400px]">
          <TabsTrigger value="editor" className="gap-2">
            <LayoutGrid className="w-4 h-4" /> Editor de Cultura
          </TabsTrigger>
          <TabsTrigger value="dashboard" className="gap-2">
            <ListTodo className="w-4 h-4" /> Painel de Gestão
          </TabsTrigger>
        </TabsList>

        <TabsContent value="editor" className="space-y-6 mt-6">
          <div className="grid md:grid-cols-2 gap-4">
            <Card>
              <CardHeader className="pb-2 flex flex-row items-center justify-between">
                <CardTitle className="text-sm">Missão</CardTitle>
                <AiButton campo="missao" label="Missão" />
              </CardHeader>
              <CardContent>
                <Textarea value={form.missao} onChange={(e) => setForm({ ...form, missao: e.target.value })} placeholder="Por que existimos? Qual o propósito da empresa?" rows={4} />
              </CardContent>
            </Card>
            <Card>
              <CardHeader className="pb-2 flex flex-row items-center justify-between">
                <CardTitle className="text-sm">Visão</CardTitle>
                <AiButton campo="visao" label="Visão" />
              </CardHeader>
              <CardContent>
                <Textarea value={form.visao} onChange={(e) => setForm({ ...form, visao: e.target.value })} placeholder="Onde queremos chegar? Como será o futuro?" rows={4} />
              </CardContent>
            </Card>
          </div>

          {listFields.map(({ key, label, color }) => (
            <Card key={key}>
              <CardHeader className="pb-2 flex flex-row items-center justify-between">
                <CardTitle className="text-sm">{label}</CardTitle>
                <AiButton campo={key} label={label} />
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="flex gap-2">
                  <Input
                    placeholder={`Adicionar ${label.toLowerCase()}...`}
                    value={newValue[key]}
                    onChange={(e) => setNewValue({ ...newValue, [key]: e.target.value })}
                    onKeyDown={(e) => e.key === "Enter" && addItem(key)}
                  />
                  <Button variant="outline" size="icon" onClick={() => addItem(key)}><Plus className="w-4 h-4" /></Button>
                </div>
                <div className="flex flex-wrap gap-2">
                  {form[key].map((item, i) => (
                    <Badge key={i} className={`${color} gap-1`}>
                      {item}
                      <button onClick={() => removeItem(key, i)} className="ml-1 hover:opacity-70"><X className="w-3 h-3" /></button>
                    </Badge>
                  ))}
                  {form[key].length === 0 && <p className="text-xs text-muted-foreground">Nenhum item adicionado</p>}
                </div>
              </CardContent>
            </Card>
          ))}
        </TabsContent>

        <TabsContent value="dashboard" className="mt-6 space-y-6">
          <div className="grid md:grid-cols-3 gap-4">
            <Card className="md:col-span-2">
              <CardHeader>
                <CardTitle className="text-base flex items-center gap-2">
                  <FileText className="w-5 h-5 text-primary" /> Visão Estruturada
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-6">
                <div>
                  <h4 className="text-sm font-semibold text-primary mb-1">Propósito (Missão)</h4>
                  <p className="text-sm text-muted-foreground p-3 bg-muted/30 rounded-lg border">
                    {form.missao || "Missão não definida"}
                  </p>
                </div>
                <div>
                  <h4 className="text-sm font-semibold text-primary mb-1">Destino (Visão)</h4>
                  <p className="text-sm text-muted-foreground p-3 bg-muted/30 rounded-lg border">
                    {form.visao || "Visão não definida"}
                  </p>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <h4 className="text-sm font-semibold text-primary mb-1">Valores Base</h4>
                    <div className="flex flex-wrap gap-2">
                      {form.valores.map((v, i) => <Badge key={i} variant="secondary">{v}</Badge>)}
                      {form.valores.length === 0 && <span className="text-xs text-muted-foreground italic">Vazio</span>}
                    </div>
                  </div>
                  <div>
                    <h4 className="text-sm font-semibold text-primary mb-1">Princípios</h4>
                    <div className="flex flex-wrap gap-2">
                      {form.principios.map((p, i) => <Badge key={i} variant="secondary">{p}</Badge>)}
                      {form.principios.length === 0 && <span className="text-xs text-muted-foreground italic">Vazio</span>}
                    </div>
                  </div>
                </div>
              </CardContent>
            </Card>

            <div className="space-y-4">
              <Card className="bg-emerald-500/5 border-emerald-500/20">
                <CardHeader className="py-3">
                  <CardTitle className="text-sm text-emerald-700">O que incentivamos</CardTitle>
                </CardHeader>
                <CardContent className="text-xs space-y-2">
                  {form.comportamentos_esperados.map((c, i) => (
                    <div key={i} className="flex gap-2 items-start">
                      <div className="w-1.5 h-1.5 rounded-full bg-emerald-500 mt-1.5" />
                      <span>{c}</span>
                    </div>
                  ))}
                  {form.comportamentos_esperados.length === 0 && <p className="italic text-muted-foreground">Nenhum comportamento listado</p>}
                </CardContent>
              </Card>

              <Card className="bg-red-500/5 border-red-500/20">
                <CardHeader className="py-3">
                  <CardTitle className="text-sm text-red-700">Não tolerado</CardTitle>
                </CardHeader>
                <CardContent className="text-xs space-y-2">
                  {form.comportamentos_nao_tolerados.map((c, i) => (
                    <div key={i} className="flex gap-2 items-start">
                      <div className="w-1.5 h-1.5 rounded-full bg-red-500 mt-1.5" />
                      <span>{c}</span>
                    </div>
                  ))}
                  {form.comportamentos_nao_tolerados.length === 0 && <p className="italic text-muted-foreground">Nenhum comportamento listado</p>}
                </CardContent>
              </Card>
            </div>
          </div>
        </TabsContent>
      </Tabs>

      <ManualCulturaModal
        open={manualOpen}
        onClose={() => setManualOpen(false)}
        html={manualHtml}
        loading={manualLoading}
        onPdfGenerated={handlePdfArchive}
      />
    </div>
  );
}
