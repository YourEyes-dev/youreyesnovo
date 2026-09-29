import { useState, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { Card, CardContent } from "@/components/ui/card";
import { Loader2, Save, Sparkles, Plus, Trash2, History, Download, FileText, Eye, GitCompareArrows, ListChecks, AlertTriangle, Minimize2, Maximize2 } from "lucide-react";
import { toast } from "sonner";
import type { PopData, PopVersao } from "@/hooks/usePopAtividade";
import { PopDiffModal } from "./PopDiffModal";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import jsPDF from "jspdf";
import { AcaoProtegida } from "@/components/shared/AcaoProtegida";

interface PopEditorModalProps {
  open: boolean;
  onClose: () => void;
  pop: PopData;
  onSave: (id: string, updates: Partial<PopData>, motivo?: string) => Promise<void>;
  saving: boolean;
  buscarVersoes: (popId: string) => Promise<PopVersao[]>;
  reescreverTrechoIA: (trecho: string, instrucao: string) => Promise<string>;
}

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  rascunho: { label: "Rascunho", color: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-300" },
  em_revisao: { label: "Em revisão", color: "bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-300" },
  publicado: { label: "Publicado", color: "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300" },
  desatualizado: { label: "Desatualizado", color: "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300" },
};

export function PopEditorModal({ open, onClose, pop, onSave, saving, buscarVersoes, reescreverTrechoIA }: PopEditorModalProps) {
  const [tab, setTab] = useState("estruturado");
  const [objetivo, setObjetivo] = useState(pop.objetivo || "");
  const [escopo, setEscopo] = useState(pop.escopo || "");
  const [responsabilidades, setResponsabilidades] = useState(pop.responsabilidades || { executante: "", supervisao: "", interfaces: "" });
  const [definicoes, setDefinicoes] = useState(pop.definicoes || "");
  const [preRequisitos, setPreRequisitos] = useState<string[]>(pop.pre_requisitos || []);
  const [materiaisFerramentas, setMateriaisFerramentas] = useState<string[]>(pop.materiais_ferramentas || []);
  const [episSst, setEpisSst] = useState(pop.epis_sst || "");
  const [passos, setPassos] = useState(pop.procedimento_passos || []);
  const [criteriosQualidade, setCriteriosQualidade] = useState(pop.criterios_qualidade || "");
  const [registrosEvidencias, setRegistrosEvidencias] = useState(pop.registros_evidencias || "");
  const [tratamentoNc, setTratamentoNc] = useState(pop.tratamento_nao_conformidades || "");
  const [referencias, setReferencias] = useState(pop.referencias || "");
  const [status, setStatus] = useState(pop.status);
  const [motivo, setMotivo] = useState("");
  
  const [versoes, setVersoes] = useState<PopVersao[]>([]);
  const [loadingVersoes, setLoadingVersoes] = useState(false);
  const [showDiff, setShowDiff] = useState(false);

  const [rewriteField, setRewriteField] = useState<string | null>(null);
  const [rewriting, setRewriting] = useState(false);

  useEffect(() => {
    setObjetivo(pop.objetivo || "");
    setEscopo(pop.escopo || "");
    setResponsabilidades(pop.responsabilidades || { executante: "", supervisao: "", interfaces: "" });
    setDefinicoes(pop.definicoes || "");
    setPreRequisitos(pop.pre_requisitos || []);
    setMateriaisFerramentas(pop.materiais_ferramentas || []);
    setEpisSst(pop.epis_sst || "");
    setPassos(pop.procedimento_passos || []);
    setCriteriosQualidade(pop.criterios_qualidade || "");
    setRegistrosEvidencias(pop.registros_evidencias || "");
    setTratamentoNc(pop.tratamento_nao_conformidades || "");
    setReferencias(pop.referencias || "");
    setStatus(pop.status);
    setMotivo("");
  }, [pop]);

  const handleSave = async () => {
    await onSave(pop.id, {
      objetivo, escopo, responsabilidades: responsabilidades as any,
      definicoes, pre_requisitos: preRequisitos as any,
      materiais_ferramentas: materiaisFerramentas as any,
      epis_sst: episSst, procedimento_passos: passos as any,
      criterios_qualidade: criteriosQualidade,
      registros_evidencias: registrosEvidencias,
      tratamento_nao_conformidades: tratamentoNc,
      referencias, status,
    } as any, motivo);
    onClose();
  };

  const loadVersoes = async () => {
    setLoadingVersoes(true);
    const v = await buscarVersoes(pop.id);
    setVersoes(v);
    setLoadingVersoes(false);
  };

  const handleRewrite = async (field: string, value: string, instrucao: string) => {
    if (!value.trim()) return;
    setRewriteField(field);
    setRewriting(true);
    try {
      const result = await reescreverTrechoIA(value, instrucao);
      switch (field) {
        case "objetivo": setObjetivo(result); break;
        case "escopo": setEscopo(result); break;
        case "definicoes": setDefinicoes(result); break;
        case "epis_sst": setEpisSst(result); break;
        case "criterios_qualidade": setCriteriosQualidade(result); break;
        case "registros_evidencias": setRegistrosEvidencias(result); break;
        case "tratamento_nc": setTratamentoNc(result); break;
        case "referencias": setReferencias(result); break;
      }
      toast.success("Texto reescrito pela IA!");
    } catch (err: any) {
      toast.error(err.message || "Erro na IA");
    } finally {
      setRewriting(false);
      setRewriteField(null);
    }
  };

  // IA dedicated actions for full POP
  const handleIAAction = async (action: "detalhar" | "simplificar" | "pontos_atencao" | "checklist") => {
    const popResumo = `Objetivo: ${objetivo}\nEscopo: ${escopo}\nPassos: ${passos.map(p => `${p.numero}. ${p.descricao}`).join("; ")}\nCritérios: ${criteriosQualidade}\nEPIs: ${episSst}`;

    const instrucoes: Record<string, string> = {
      detalhar: `Analise este POP e DETALHE cada seção, adicionando mais profundidade, exemplos práticos e especificações técnicas. Retorne APENAS o texto detalhado, cobrindo cada seção de forma mais completa.`,
      simplificar: `Analise este POP e SIMPLIFIQUE a linguagem para que qualquer colaborador consiga entender facilmente, sem perder informações essenciais. Retorne APENAS o texto simplificado.`,
      pontos_atencao: `Analise este POP e identifique TODOS os pontos críticos de atenção, riscos de erro, etapas que precisam de mais cuidado e possíveis falhas. Liste cada ponto de atenção de forma clara e objetiva. Retorne APENAS a lista de pontos de atenção.`,
      checklist: `Com base neste POP, gere um CHECKLIST operacional completo que um colaborador pode usar para verificar se executou todos os passos corretamente. Formato: lista com checkboxes (☐). Retorne APENAS o checklist.`,
    };

    setRewriteField(action);
    setRewriting(true);
    try {
      const result = await reescreverTrechoIA(popResumo, instrucoes[action]);

      if (action === "detalhar") {
        setObjetivo(prev => prev + "\n\n📋 Detalhamento IA:\n" + result);
      } else if (action === "simplificar") {
        setObjetivo(prev => prev + "\n\n✅ Versão Simplificada IA:\n" + result);
      } else if (action === "pontos_atencao") {
        setTratamentoNc(prev => (prev ? prev + "\n\n" : "") + "⚠️ Pontos de Atenção (IA):\n" + result);
      } else if (action === "checklist") {
        setRegistrosEvidencias(prev => (prev ? prev + "\n\n" : "") + "📝 Checklist (IA):\n" + result);
      }
      toast.success("Conteúdo gerado pela IA!");
    } catch (err: any) {
      toast.error(err.message || "Erro na IA");
    } finally {
      setRewriting(false);
      setRewriteField(null);
    }
  };

  const addPasso = () => setPassos([...passos, { numero: passos.length + 1, descricao: "", tempo_estimado: "", ponto_atencao: "" }]);
  const removePasso = (i: number) => setPassos(passos.filter((_, idx) => idx !== i).map((p, idx) => ({ ...p, numero: idx + 1 })));
  const updatePasso = (i: number, field: string, val: string) => setPassos(passos.map((p, idx) => idx === i ? { ...p, [field]: val } : p));

  const addListItem = (list: string[], setter: (v: string[]) => void) => setter([...list, ""]);
  const updateListItem = (list: string[], setter: (v: string[]) => void, i: number, val: string) => setter(list.map((item, idx) => idx === i ? val : item));
  const removeListItem = (list: string[], setter: (v: string[]) => void, i: number) => setter(list.filter((_, idx) => idx !== i));

  const IAButton = ({ field, value, instrucao }: { field: string; value: string; instrucao: string }) => (
    <Button variant="ghost" size="sm" className="text-xs gap-1 text-primary" disabled={rewriting}
      onClick={() => handleRewrite(field, value, instrucao)}>
      {rewriting && rewriteField === field ? <Loader2 className="w-3 h-3 animate-spin" /> : <Sparkles className="w-3 h-3" />}
      Reescrever com IA
    </Button>
  );

  const st = STATUS_LABELS[pop.status] || STATUS_LABELS.rascunho;

  // PDF Export
  const exportPDF = async () => {
    try {
      const html = generatePopHtml();
      const iframe = document.createElement("iframe");
      iframe.style.position = "fixed";
      iframe.style.left = "-9999px";
      iframe.style.width = "800px";
      iframe.style.height = "1200px";
      document.body.appendChild(iframe);
      iframe.contentDocument?.open();
      iframe.contentDocument?.write(html);
      iframe.contentDocument?.close();

      await new Promise(r => setTimeout(r, 500));

      const { default: html2canvas } = await import("html2canvas");
      const body = iframe.contentDocument?.body;
      if (!body) throw new Error("Erro ao renderizar");

      const canvas = await html2canvas(body, { scale: 2, useCORS: true, width: 800 });
      document.body.removeChild(iframe);

      const pdf = new jsPDF("p", "mm", "a4");
      const imgWidth = 210;
      const pageHeight = 297;
      const imgHeight = (canvas.height * imgWidth) / canvas.width;
      let heightLeft = imgHeight;
      let position = 0;

      const imgData = canvas.toDataURL("image/png");
      pdf.addImage(imgData, "PNG", 0, position, imgWidth, imgHeight);
      heightLeft -= pageHeight;

      while (heightLeft > 0) {
        position -= pageHeight;
        pdf.addPage();
        pdf.addImage(imgData, "PNG", 0, position, imgWidth, imgHeight);
        heightLeft -= pageHeight;
      }

      pdf.save(`${pop.codigo} - ${pop.titulo}.pdf`);
      toast.success("PDF exportado com sucesso!");
    } catch (err: any) {
      console.error("PDF export error:", err);
      toast.error("Erro ao exportar PDF. Exportando como HTML...");
      const html = generatePopHtml();
      const blob = new Blob([html], { type: "text/html" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `${pop.codigo} - ${pop.titulo}.html`;
      a.click();
      URL.revokeObjectURL(url);
    }
  };

  const generatePopHtml = () => {
    return `<!DOCTYPE html>
<html lang="pt-BR"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${pop.codigo} - ${pop.titulo}</title>
<style>
body{font-family:Arial,sans-serif;max-width:800px;margin:0 auto;padding:20px;color:#333;font-size:14px}
h1{color:#1a365d;border-bottom:2px solid #2563eb;padding-bottom:8px}
h2{color:#1e40af;margin-top:24px;font-size:16px;border-left:4px solid #2563eb;padding-left:8px}
.header{display:grid;grid-template-columns:1fr 1fr;gap:8px;background:#f8fafc;padding:12px;border-radius:8px;margin-bottom:20px;font-size:12px}
.header span{display:block}.header strong{color:#1e40af}
.step{background:#f0f9ff;padding:12px;border-radius:6px;margin:8px 0;border-left:3px solid #2563eb}
.step-num{font-weight:bold;color:#1e40af}.attention{background:#fef3c7;padding:8px;border-radius:4px;margin-top:4px;font-size:12px}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:11px;font-weight:600}
.rascunho{background:#fef3c7;color:#92400e}.publicado{background:#dcfce7;color:#166534}
ul{padding-left:20px}li{margin:4px 0}
p{white-space:pre-wrap}
@media print{body{margin:0;padding:10px}}
</style></head><body>
<h1>${pop.codigo} — ${pop.titulo}</h1>
<div class="header">
<span><strong>Versão:</strong> ${pop.versao_atual}</span>
<span><strong>Status:</strong> <span class="badge ${pop.status}">${st.label}</span></span>
<span><strong>Criado por:</strong> ${pop.criado_por_nome || "—"}</span>
<span><strong>Criado em:</strong> ${format(new Date(pop.created_at), "dd/MM/yyyy", { locale: ptBR })}</span>
${pop.aprovado_por_nome ? `<span><strong>Aprovado por:</strong> ${pop.aprovado_por_nome}</span>` : ""}
${pop.data_aprovacao ? `<span><strong>Data aprovação:</strong> ${format(new Date(pop.data_aprovacao), "dd/MM/yyyy", { locale: ptBR })}</span>` : ""}
${pop.gerado_por_ia ? `<span><strong>🤖 Gerado por IA</strong></span>` : ""}
</div>
${objetivo ? `<h2>1. Objetivo</h2><p>${objetivo}</p>` : ""}
${escopo ? `<h2>2. Escopo</h2><p>${escopo}</p>` : ""}
<h2>3. Responsabilidades</h2>
<ul>
<li><strong>Executante:</strong> ${(responsabilidades as any)?.executante || "—"}</li>
<li><strong>Supervisão:</strong> ${(responsabilidades as any)?.supervisao || "—"}</li>
<li><strong>Interfaces:</strong> ${(responsabilidades as any)?.interfaces || "—"}</li>
</ul>
${definicoes ? `<h2>4. Definições</h2><p>${definicoes}</p>` : ""}
${preRequisitos.length > 0 ? `<h2>5. Pré-requisitos</h2><ul>${preRequisitos.map(p => `<li>${p}</li>`).join("")}</ul>` : ""}
${materiaisFerramentas.length > 0 ? `<h2>6. Materiais, Ferramentas e Sistemas</h2><ul>${materiaisFerramentas.map(m => `<li>${m}</li>`).join("")}</ul>` : ""}
${episSst ? `<h2>7. EPIs / Requisitos de SST</h2><p>${episSst}</p>` : ""}
${passos.length > 0 ? `<h2>8. Procedimento Passo a Passo</h2>${passos.map(p => `<div class="step"><span class="step-num">Passo ${p.numero}:</span> ${p.descricao}${p.tempo_estimado ? ` <em>(${p.tempo_estimado})</em>` : ""}${p.ponto_atencao ? `<div class="attention">⚠️ ${p.ponto_atencao}</div>` : ""}</div>`).join("")}` : ""}
${criteriosQualidade ? `<h2>9. Critérios de Qualidade</h2><p>${criteriosQualidade}</p>` : ""}
${registrosEvidencias ? `<h2>10. Registros e Evidências</h2><p>${registrosEvidencias}</p>` : ""}
${tratamentoNc ? `<h2>11. Tratamento de Não Conformidades</h2><p>${tratamentoNc}</p>` : ""}
${referencias ? `<h2>12. Referências</h2><p>${referencias}</p>` : ""}
</body></html>`;
  };

  const openDiff = async () => {
    if (versoes.length === 0) {
      await loadVersoes();
    }
    setShowDiff(true);
  };

  return (
    <>
      <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
        <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <div className="flex items-center justify-between">
              <DialogTitle className="flex items-center gap-2">
                <FileText className="w-5 h-5" />
                {pop.codigo} — {pop.titulo}
              </DialogTitle>
              <div className="flex items-center gap-2">
                <Badge className={st.color}>{st.label}</Badge>
                {pop.gerado_por_ia && <Badge variant="outline" className="gap-1"><Sparkles className="w-3 h-3" /> IA</Badge>}
                <span className="text-xs text-muted-foreground">v{pop.versao_atual}</span>
              </div>
            </div>
          </DialogHeader>

          {/* IA Dedicated Action Buttons */}
          <div className="flex flex-wrap gap-2 border rounded-lg p-2 bg-muted/30">
            <span className="text-xs text-muted-foreground flex items-center gap-1 mr-1">
              <Sparkles className="w-3 h-3" /> Assistente IA:
            </span>
            <Button
              variant="outline" size="sm" className="text-xs gap-1 h-7"
              disabled={rewriting}
              onClick={() => handleIAAction("detalhar")}
            >
              {rewriting && rewriteField === "detalhar" ? <Loader2 className="w-3 h-3 animate-spin" /> : <Maximize2 className="w-3 h-3" />}
              Detalhar
            </Button>
            <Button
              variant="outline" size="sm" className="text-xs gap-1 h-7"
              disabled={rewriting}
              onClick={() => handleIAAction("simplificar")}
            >
              {rewriting && rewriteField === "simplificar" ? <Loader2 className="w-3 h-3 animate-spin" /> : <Minimize2 className="w-3 h-3" />}
              Simplificar
            </Button>
            <Button
              variant="outline" size="sm" className="text-xs gap-1 h-7"
              disabled={rewriting}
              onClick={() => handleIAAction("pontos_atencao")}
            >
              {rewriting && rewriteField === "pontos_atencao" ? <Loader2 className="w-3 h-3 animate-spin" /> : <AlertTriangle className="w-3 h-3" />}
              Pontos de Atenção
            </Button>
            <Button
              variant="outline" size="sm" className="text-xs gap-1 h-7"
              disabled={rewriting}
              onClick={() => handleIAAction("checklist")}
            >
              {rewriting && rewriteField === "checklist" ? <Loader2 className="w-3 h-3 animate-spin" /> : <ListChecks className="w-3 h-3" />}
              Checklist
            </Button>
          </div>

          <Tabs value={tab} onValueChange={setTab}>
            <TabsList>
              <TabsTrigger value="estruturado" className="gap-1"><FileText className="w-4 h-4" /> Estruturado</TabsTrigger>
              <TabsTrigger value="preview" className="gap-1"><Eye className="w-4 h-4" /> Visualizar</TabsTrigger>
              <TabsTrigger value="versoes" className="gap-1" onClick={loadVersoes}><History className="w-4 h-4" /> Versões</TabsTrigger>
            </TabsList>

            <TabsContent value="estruturado" className="space-y-4 mt-4">
              <div className="flex gap-2 items-end">
                <div className="flex-1 space-y-1">
                  <Label>Status</Label>
                  <Select value={status} onValueChange={setStatus}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="rascunho">Rascunho</SelectItem>
                      <SelectItem value="em_revisao">Em revisão</SelectItem>
                      <SelectItem value="publicado">Publicado</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="flex-1 space-y-1">
                  <Label>Motivo da alteração</Label>
                  <Input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Descreva brevemente..." />
                </div>
              </div>

              <Accordion type="multiple" defaultValue={["objetivo", "procedimento"]} className="space-y-1">
                <AccordionItem value="objetivo">
                  <AccordionTrigger className="text-sm font-semibold">1. Objetivo</AccordionTrigger>
                  <AccordionContent className="space-y-1">
                    <Textarea value={objetivo} onChange={(e) => setObjetivo(e.target.value)} rows={3} />
                    <IAButton field="objetivo" value={objetivo} instrucao="Reescreva o objetivo de forma mais clara e profissional para um POP." />
                  </AccordionContent>
                </AccordionItem>

                <AccordionItem value="escopo">
                  <AccordionTrigger className="text-sm font-semibold">2. Escopo</AccordionTrigger>
                  <AccordionContent className="space-y-1">
                    <Textarea value={escopo} onChange={(e) => setEscopo(e.target.value)} rows={2} />
                    <IAButton field="escopo" value={escopo} instrucao="Reescreva o escopo para ser mais específico e abrangente." />
                  </AccordionContent>
                </AccordionItem>

                <AccordionItem value="responsabilidades">
                  <AccordionTrigger className="text-sm font-semibold">3. Responsabilidades</AccordionTrigger>
                  <AccordionContent className="grid grid-cols-3 gap-2">
                    <div className="space-y-1">
                      <Label className="text-xs">Executante</Label>
                      <Input value={(responsabilidades as any)?.executante || ""} onChange={(e) => setResponsabilidades({ ...responsabilidades, executante: e.target.value })} />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Supervisão</Label>
                      <Input value={(responsabilidades as any)?.supervisao || ""} onChange={(e) => setResponsabilidades({ ...responsabilidades, supervisao: e.target.value })} />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Interfaces</Label>
                      <Input value={(responsabilidades as any)?.interfaces || ""} onChange={(e) => setResponsabilidades({ ...responsabilidades, interfaces: e.target.value })} />
                    </div>
                  </AccordionContent>
                </AccordionItem>

                <AccordionItem value="definicoes">
                  <AccordionTrigger className="text-sm font-semibold">4. Definições</AccordionTrigger>
                  <AccordionContent className="space-y-1">
                    <Textarea value={definicoes} onChange={(e) => setDefinicoes(e.target.value)} rows={2} />
                  </AccordionContent>
                </AccordionItem>

                <AccordionItem value="pre_requisitos">
                  <AccordionTrigger className="text-sm font-semibold">5. Pré-requisitos</AccordionTrigger>
                  <AccordionContent className="space-y-2">
                    {preRequisitos.map((p, i) => (
                      <div key={i} className="flex gap-2">
                        <Input value={p} onChange={(e) => updateListItem(preRequisitos, setPreRequisitos, i, e.target.value)} placeholder="Pré-requisito" />
                        <Button variant="ghost" size="icon" onClick={() => removeListItem(preRequisitos, setPreRequisitos, i)}><Trash2 className="w-3 h-3 text-destructive" /></Button>
                      </div>
                    ))}
                    <Button variant="ghost" size="sm" onClick={() => addListItem(preRequisitos, setPreRequisitos)} className="gap-1"><Plus className="w-3 h-3" /> Adicionar</Button>
                  </AccordionContent>
                </AccordionItem>

                <AccordionItem value="materiais">
                  <AccordionTrigger className="text-sm font-semibold">6. Materiais, Ferramentas e Sistemas</AccordionTrigger>
                  <AccordionContent className="space-y-2">
                    {materiaisFerramentas.map((m, i) => (
                      <div key={i} className="flex gap-2">
                        <Input value={m} onChange={(e) => updateListItem(materiaisFerramentas, setMateriaisFerramentas, i, e.target.value)} />
                        <Button variant="ghost" size="icon" onClick={() => removeListItem(materiaisFerramentas, setMateriaisFerramentas, i)}><Trash2 className="w-3 h-3 text-destructive" /></Button>
                      </div>
                    ))}
                    <Button variant="ghost" size="sm" onClick={() => addListItem(materiaisFerramentas, setMateriaisFerramentas)} className="gap-1"><Plus className="w-3 h-3" /> Adicionar</Button>
                  </AccordionContent>
                </AccordionItem>

                <AccordionItem value="epis">
                  <AccordionTrigger className="text-sm font-semibold">7. EPIs / Requisitos de SST</AccordionTrigger>
                  <AccordionContent className="space-y-1">
                    <Textarea value={episSst} onChange={(e) => setEpisSst(e.target.value)} rows={2} />
                    <IAButton field="epis_sst" value={episSst} instrucao="Detalhe os requisitos de SST de forma clara e técnica." />
                  </AccordionContent>
                </AccordionItem>

                <AccordionItem value="procedimento">
                  <AccordionTrigger className="text-sm font-semibold">8. Procedimento Passo a Passo</AccordionTrigger>
                  <AccordionContent className="space-y-3">
                    {passos.map((p, i) => (
                      <Card key={i}>
                        <CardContent className="p-3 space-y-2">
                          <div className="flex items-center justify-between">
                            <span className="text-sm font-medium text-primary">Passo {p.numero}</span>
                            <Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => removePasso(i)}><Trash2 className="w-3 h-3 text-destructive" /></Button>
                          </div>
                          <Textarea value={p.descricao} onChange={(e) => updatePasso(i, "descricao", e.target.value)} placeholder="Descrição do passo" rows={2} />
                          <div className="grid grid-cols-2 gap-2">
                            <Input value={p.tempo_estimado || ""} onChange={(e) => updatePasso(i, "tempo_estimado", e.target.value)} placeholder="Tempo estimado (ex: 5 min)" />
                            <Input value={p.ponto_atencao || ""} onChange={(e) => updatePasso(i, "ponto_atencao", e.target.value)} placeholder="⚠️ Ponto de atenção" />
                          </div>
                        </CardContent>
                      </Card>
                    ))}
                    <Button variant="outline" size="sm" onClick={addPasso} className="gap-1"><Plus className="w-3 h-3" /> Adicionar passo</Button>
                  </AccordionContent>
                </AccordionItem>

                <AccordionItem value="criterios">
                  <AccordionTrigger className="text-sm font-semibold">9. Critérios de Qualidade</AccordionTrigger>
                  <AccordionContent className="space-y-1">
                    <Textarea value={criteriosQualidade} onChange={(e) => setCriteriosQualidade(e.target.value)} rows={2} />
                    <IAButton field="criterios_qualidade" value={criteriosQualidade} instrucao="Detalhe critérios objetivos e mensuráveis de qualidade." />
                  </AccordionContent>
                </AccordionItem>

                <AccordionItem value="registros">
                  <AccordionTrigger className="text-sm font-semibold">10. Registros e Evidências</AccordionTrigger>
                  <AccordionContent className="space-y-1">
                    <Textarea value={registrosEvidencias} onChange={(e) => setRegistrosEvidencias(e.target.value)} rows={2} />
                  </AccordionContent>
                </AccordionItem>

                <AccordionItem value="nc">
                  <AccordionTrigger className="text-sm font-semibold">11. Tratamento de Não Conformidades</AccordionTrigger>
                  <AccordionContent className="space-y-1">
                    <Textarea value={tratamentoNc} onChange={(e) => setTratamentoNc(e.target.value)} rows={2} />
                    <IAButton field="tratamento_nc" value={tratamentoNc} instrucao="Detalhe ações corretivas e preventivas de forma estruturada." />
                  </AccordionContent>
                </AccordionItem>

                <AccordionItem value="referencias">
                  <AccordionTrigger className="text-sm font-semibold">12. Referências</AccordionTrigger>
                  <AccordionContent className="space-y-1">
                    <Textarea value={referencias} onChange={(e) => setReferencias(e.target.value)} rows={2} />
                  </AccordionContent>
                </AccordionItem>
              </Accordion>

              <div className="flex justify-between pt-4">
                <div className="flex gap-2">
                  <AcaoProtegida modulo="trilhas" acao="exportar">
                    <Button variant="outline" onClick={exportPDF} className="gap-1"><Download className="w-4 h-4" /> Exportar PDF</Button>
                  </AcaoProtegida>
                  <Button variant="outline" onClick={openDiff} className="gap-1"><GitCompareArrows className="w-4 h-4" /> Comparar Versões</Button>
                </div>
                <div className="flex gap-2">
                  <Button variant="ghost" onClick={onClose}>Cancelar</Button>
                  <Button onClick={handleSave} disabled={saving} className="gap-1">
                    {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
                    Salvar
                  </Button>
                </div>
              </div>
            </TabsContent>

            <TabsContent value="preview" className="mt-4">
              <div className="border rounded-lg overflow-hidden">
                <iframe
                  srcDoc={generatePopHtml()}
                  className="w-full h-[600px]"
                  title="POP Preview"
                />
              </div>
            </TabsContent>

            <TabsContent value="versoes" className="mt-4 space-y-3">
              {loadingVersoes ? (
                <div className="text-center py-8"><Loader2 className="w-6 h-6 animate-spin mx-auto text-muted-foreground" /></div>
              ) : versoes.length === 0 ? (
                <div className="text-center py-8 text-sm text-muted-foreground">Nenhuma versão anterior registrada.</div>
              ) : (
                <>
                  <div className="flex justify-end">
                    <Button variant="outline" size="sm" className="gap-1" onClick={() => setShowDiff(true)}>
                      <GitCompareArrows className="w-4 h-4" /> Comparar com versão atual
                    </Button>
                  </div>
                  {versoes.map((v) => (
                    <Card key={v.id}>
                      <CardContent className="p-3 flex items-center justify-between">
                        <div>
                          <div className="flex items-center gap-2">
                            <Badge variant="outline">v{v.versao}</Badge>
                            <Badge className={STATUS_LABELS[v.status]?.color || ""}>{STATUS_LABELS[v.status]?.label || v.status}</Badge>
                            <span className="text-xs text-muted-foreground">{format(new Date(v.created_at), "dd/MM/yyyy HH:mm", { locale: ptBR })}</span>
                          </div>
                          <p className="text-xs text-muted-foreground mt-1">
                            {v.alterado_por_nome || "Sistema"} {v.motivo_alteracao ? `— ${v.motivo_alteracao}` : ""}
                          </p>
                        </div>
                      </CardContent>
                    </Card>
                  ))}
                </>
              )}
            </TabsContent>
          </Tabs>
        </DialogContent>
      </Dialog>

      {showDiff && versoes.length > 0 && (
        <PopDiffModal
          open={showDiff}
          onClose={() => setShowDiff(false)}
          pop={pop}
          versoes={versoes}
        />
      )}
    </>
  );
}
