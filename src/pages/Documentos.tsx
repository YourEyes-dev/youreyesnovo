import { useState, useEffect, useCallback, useRef, useMemo } from "react";
import { useSearchParams } from "react-router-dom";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { motion } from "framer-motion";
import { 
  FileText, 
  Upload, 
  Search,
  FolderTree,
  History,
  FolderPlus,
  Loader2,
  AlertCircle,
  ShieldCheck,
  Radar,
  RefreshCw,
  Pencil,
  FoldVertical,
  UnfoldVertical,
  Bell,
} from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import {
  ResizableHandle,
  ResizablePanel,
  ResizablePanelGroup,
} from "@/components/ui/resizable";
import { ScrollArea } from "@/components/ui/scroll-area";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";

import { useDocumentoPastas } from "@/hooks/useDocumentoPastas";
import { useAuth } from "@/hooks/useAuth";
import { usePerfilPermissions } from "@/hooks/usePerfilPermissions";
import { useDocumentos } from "@/hooks/useDocumentos";
import { PastaTreeView } from "@/components/documentos/PastaTreeView";
import { PastaDocumentosList } from "@/components/documentos/PastaDocumentosList";
import { CreatePastaModal } from "@/components/documentos/CreatePastaModal";
import { DocumentoAuditLog } from "@/components/documentos/DocumentoAuditLog";
import { DocumentoUploadForm } from "@/components/documentos/DocumentoUploadForm";

import { MapaConformidade } from "@/components/documentos/MapaConformidade";
import { RadarGovernanca } from "@/components/documentos/RadarGovernanca";
import { PDCADashboard } from "@/components/documentos/PDCADashboard";
import { NotificacoesVencimento } from "@/components/documentos/NotificacoesVencimento";
import type { DocumentoPastaNode, DocumentoItem } from "@/types/documentoPasta";

function filterTree(nodes: DocumentoPastaNode[], term: string): DocumentoPastaNode[] {
  const normalized = term.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
  function matches(node: DocumentoPastaNode): boolean {
    const name = node.nome.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    return name.includes(normalized);
  }
  function filterNode(node: DocumentoPastaNode): DocumentoPastaNode | null {
    const filteredChildren = node.children.map(filterNode).filter(Boolean) as DocumentoPastaNode[];
    if (matches(node) || filteredChildren.length > 0) {
      return { ...node, children: matches(node) ? node.children : filteredChildren };
    }
    return null;
  }
  return nodes.map(filterNode).filter(Boolean) as DocumentoPastaNode[];
}

const Documentos = () => {
  const [searchParams] = useSearchParams();
  const colaboradorIdFromUrl = searchParams.get("colaborador");
  const { tenantId, hasMinimumRole } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const { temAcessoModuloAdmin, isOwner, perfilVinculado } = usePerfilPermissions();

  // Acesso AMPLO ao módulo — espelha perfil_permite_modulo no servidor (Fase 1):
  // superadmin/owner acima; um perfil com escopo <> proprio_usuario dá amplo;
  // e papel manager+ só concede amplo quando NÃO há perfil vinculado (sem
  // perfil = comportamento legado). Com perfil vinculado, o perfil decide —
  // então um gestor com perfil "próprio usuário" vê só a própria pasta.
  const podeGerirDocumentos =
    isOwner ||
    temAcessoModuloAdmin(["documentos", "configuracoes", "colaboradores"]) ||
    (!perfilVinculado && hasMinimumRole("manager"));

  const [activeTab, setActiveTab] = useState("arvore");
  const [searchTerm, setSearchTerm] = useState("");
  const [auditSearchTerm, setAuditSearchTerm] = useState("");
  const [auditActionFilter, setAuditActionFilter] = useState<string>("all");
  const [expandAllSignal, setExpandAllSignal] = useState({ expand: false, key: 0 });
  const [selectedPasta, setSelectedPasta] = useState<DocumentoPastaNode | null>(null);
  const [showUploadForm, setShowUploadForm] = useState(false);
  const [uploadForPastaId, setUploadForPastaId] = useState<string | undefined>(undefined);
  const [uploadPastaColaboradorId, setUploadPastaColaboradorId] = useState<string | undefined>(undefined);
  const [novaVersaoDocId, setNovaVersaoDocId] = useState<string | undefined>(undefined);
  const [showCreatePasta, setShowCreatePasta] = useState(false);
  const [createPastaParentId, setCreatePastaParentId] = useState<string | null>(null);
  const [createPastaParentNome, setCreatePastaParentNome] = useState<string | null>(null);
  const [pastaToDelete, setPastaToDelete] = useState<string | null>(null);
  const [pastaToRename, setPastaToRename] = useState<DocumentoPastaNode | null>(null);
  const [renameValue, setRenameValue] = useState("");
  const [renaming, setRenaming] = useState(false);
  const [autoInitDone, setAutoInitDone] = useState<string | null>(null);
  const [dragContext, setDragContext] = useState<{
    documentoId: string;
    documentoNome: string;
    pastaOrigemId: string;
    pastaOrigemNome: string;
  } | null>(null);

  const {
    pastas,
    tree,
    auditLogs,
    loading,
    loadingAudit,
    createPasta,
    updatePasta,
    deletePasta,
    moveDocumento,
    movingDoc,
    initializeDefaultStructure,
    initializing,
    needsSync,
    syncColaboradores,
    syncing,
  } = useDocumentoPastas();

  const {
    documentos,
    isLoading: loadingDocs,
    stats,
    deleteDocumento,
    deleting,
    getSignedUrl,
  } = useDocumentos();

  // Mantém o nó selecionado sincronizado com a árvore (após upload, mover, etc.).
  const livePasta = useMemo(() => {
    if (!selectedPasta) return null;
    const find = (nodes: DocumentoPastaNode[]): DocumentoPastaNode | null => {
      for (const n of nodes) {
        if (n.id === selectedPasta.id) return n;
        const f = find(n.children);
        if (f) return f;
      }
      return null;
    };
    return find(tree) || selectedPasta;
  }, [tree, selectedPasta]);

  // Reset estado ao trocar empresa ativa (evita exibir pasta/upload da empresa anterior)
  useEffect(() => {
    setSelectedPasta(null);
    setShowUploadForm(false);
    setUploadForPastaId(undefined);
    setNovaVersaoDocId(undefined);
    setShowCreatePasta(false);
    setCreatePastaParentId(null);
    setCreatePastaParentNome(null);
    setSearchTerm("");
  }, [empresaAtivaId]);

  // Abrir pasta de colaborador se especificado na URL
  useEffect(() => {
    if (colaboradorIdFromUrl && tree.length > 0) {
      const findPastaColaborador = (nodes: DocumentoPastaNode[]): DocumentoPastaNode | null => {
        for (const node of nodes) {
          if (node.colaborador_id === colaboradorIdFromUrl) return node;
          const found = findPastaColaborador(node.children);
          if (found) return found;
        }
        return null;
      };
      const pasta = findPastaColaborador(tree);
      if (pasta) setSelectedPasta(pasta);
    }
  }, [colaboradorIdFromUrl, tree]);

  // Força a aba "Estrutura" para quem só tem acesso próprio (as demais abas
  // trazem visão de empresa e ficam ocultas abaixo).
  useEffect(() => {
    if (!podeGerirDocumentos) setActiveTab("arvore");
  }, [podeGerirDocumentos]);

  // Auto-sync: criar pastas para colaboradores novos (só para quem gere os
  // documentos — o usuário "próprio" não cria pastas; a escrita nem passaria).
  useEffect(() => {
    if (!podeGerirDocumentos) return;
    if (needsSync && !syncing) {
      syncColaboradores();
    }
  }, [podeGerirDocumentos, needsSync, syncing, syncColaboradores]);

  // Auto-gerar estrutura padrão silenciosamente (idempotente — cria apenas pastas faltantes)
  useEffect(() => {
    if (!podeGerirDocumentos) return;
    if (!tenantId || loading || initializing) return;
    const initKey = `${tenantId}_${empresaAtivaId || 'default'}`;
    if (autoInitDone === initKey) return;
    setAutoInitDone(initKey);
    initializeDefaultStructure(undefined).catch(() => {});
  }, [podeGerirDocumentos, tenantId, loading, initializing, empresaAtivaId]); // eslint-disable-line react-hooks/exhaustive-deps

  const handleOpenUpload = useCallback((pastaId?: string) => {
    setUploadForPastaId(pastaId);
    // Descobre se a pasta de destino é de um colaborador. Se for, o
    // colaborador é exigido e pré-selecionado. Se for pasta da empresa
    // (unidade/categoria/etc.), o colaborador não é obrigatório.
    const buscar = (nodes: DocumentoPastaNode[]): DocumentoPastaNode | null => {
      for (const node of nodes) {
        if (node.id === pastaId) return node;
        const found = buscar(node.children);
        if (found) return found;
      }
      return null;
    };
    const pasta = pastaId ? buscar(tree) : null;
    setUploadPastaColaboradorId(pasta?.colaborador_id || undefined);
    setShowUploadForm(true);
  }, [tree]);

  const handleCreateSubfolder = useCallback((parentId: string) => {
    const findPasta = (nodes: DocumentoPastaNode[]): DocumentoPastaNode | null => {
      for (const node of nodes) {
        if (node.id === parentId) return node;
        const found = findPasta(node.children);
        if (found) return found;
      }
      return null;
    };
    const parent = findPasta(tree);
    setCreatePastaParentId(parentId);
    setCreatePastaParentNome(parent?.nome || null);
    setShowCreatePasta(true);
  }, [tree]);

  const handleRenamePasta = useCallback((pasta: DocumentoPastaNode) => {
    setPastaToRename(pasta);
    setRenameValue(pasta.nome);
  }, []);

  const confirmRenamePasta = async () => {
    if (!pastaToRename || !renameValue.trim()) return;
    setRenaming(true);
    try {
      await updatePasta({ id: pastaToRename.id, nome: renameValue.trim() });
      toast.success("Pasta renomeada com sucesso!");
      if (selectedPasta?.id === pastaToRename.id) {
        setSelectedPasta(prev => prev ? { ...prev, nome: renameValue.trim() } : prev);
      }
    } catch {
      // Error handled in hook
    }
    setRenaming(false);
    setPastaToRename(null);
  };

  const handleDeletePasta = useCallback((pastaId: string) => {
    setPastaToDelete(pastaId);
  }, []);

  const confirmDeletePasta = async () => {
    if (!pastaToDelete) return;
    try {
      await deletePasta(pastaToDelete);
      if (selectedPasta?.id === pastaToDelete) {
        setSelectedPasta(null);
      }
    } catch (error) {
      // Error handled in hook
    }
    setPastaToDelete(null);
  };

  const handleDropDocument = useCallback(async (documentoId: string, pastaDestinoId: string) => {
    if (!dragContext) return;
    
    const findPasta = (nodes: DocumentoPastaNode[]): DocumentoPastaNode | null => {
      for (const node of nodes) {
        if (node.id === pastaDestinoId) return node;
        const found = findPasta(node.children);
        if (found) return found;
      }
      return null;
    };
    
    const pastaDestino = findPasta(tree);
    
    await moveDocumento({
      documentoId,
      documentoNome: dragContext.documentoNome,
      pastaOrigemId: dragContext.pastaOrigemId,
      pastaOrigemNome: dragContext.pastaOrigemNome,
      pastaDestinoId,
      pastaDestinoNome: pastaDestino?.nome || null,
    });
    
    setDragContext(null);
  }, [dragContext, tree, moveDocumento]);

  const handleDragStart = useCallback((documentoId: string, documentoNome: string, pastaOrigemId: string, pastaOrigemNome: string) => {
    setDragContext({ documentoId, documentoNome, pastaOrigemId, pastaOrigemNome });
  }, []);

  const generatePopHtml = (pop: any): string => {
    const statusLabels: Record<string, string> = {
      rascunho: "Rascunho", em_revisao: "Em revisão", publicado: "Publicado", desatualizado: "Desatualizado",
    };
    const st = statusLabels[pop.status] || pop.status;
    const fmtDate = (d: string) => d ? new Date(d).toLocaleDateString("pt-BR") : "—";

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
ul{padding-left:20px}li{margin:4px 0}
@media print{body{padding:0;max-width:100%}}
</style></head><body>
<h1>${pop.codigo} — ${pop.titulo}</h1>
<div class="header">
<span><strong>Versão:</strong> ${pop.versao_atual}</span>
<span><strong>Status:</strong> ${st}</span>
<span><strong>Criado por:</strong> ${pop.criado_por_nome || "—"}</span>
<span><strong>Criado em:</strong> ${fmtDate(pop.created_at)}</span>
${pop.aprovado_por_nome ? `<span><strong>Aprovado por:</strong> ${pop.aprovado_por_nome}</span>` : ""}
${pop.data_aprovacao ? `<span><strong>Data aprovação:</strong> ${fmtDate(pop.data_aprovacao)}</span>` : ""}
${pop.gerado_por_ia ? `<span><strong>🤖 Gerado por IA</strong></span>` : ""}
</div>
${pop.objetivo ? `<h2>1. Objetivo</h2><p>${pop.objetivo}</p>` : ""}
${pop.escopo ? `<h2>2. Escopo</h2><p>${pop.escopo}</p>` : ""}
<h2>3. Responsabilidades</h2>
<ul>
<li><strong>Executante:</strong> ${pop.responsabilidades?.executante || "—"}</li>
<li><strong>Supervisão:</strong> ${pop.responsabilidades?.supervisao || "—"}</li>
<li><strong>Interfaces:</strong> ${pop.responsabilidades?.interfaces || "—"}</li>
</ul>
${pop.definicoes ? `<h2>4. Definições</h2><p>${pop.definicoes}</p>` : ""}
${pop.pre_requisitos?.length ? `<h2>5. Pré-requisitos</h2><ul>${pop.pre_requisitos.map((p: string) => `<li>${p}</li>`).join("")}</ul>` : ""}
${pop.materiais_ferramentas?.length ? `<h2>6. Materiais e Ferramentas</h2><ul>${pop.materiais_ferramentas.map((m: string) => `<li>${m}</li>`).join("")}</ul>` : ""}
${pop.epis_sst ? `<h2>7. EPIs / Requisitos de SST</h2><p>${pop.epis_sst}</p>` : ""}
${pop.procedimento_passos?.length ? `<h2>8. Procedimento Passo a Passo</h2>${pop.procedimento_passos.map((p: any) => `<div class="step"><span class="step-num">Passo ${p.numero}:</span> ${p.descricao}${p.tempo_estimado ? ` <em>(${p.tempo_estimado})</em>` : ""}${p.ponto_atencao ? `<div class="attention">⚠️ ${p.ponto_atencao}</div>` : ""}</div>`).join("")}` : ""}
${pop.criterios_qualidade ? `<h2>9. Critérios de Qualidade</h2><p>${pop.criterios_qualidade}</p>` : ""}
${pop.registros_evidencias ? `<h2>10. Registros e Evidências</h2><p>${pop.registros_evidencias}</p>` : ""}
${pop.tratamento_nao_conformidades ? `<h2>11. Tratamento de Não Conformidades</h2><p>${pop.tratamento_nao_conformidades}</p>` : ""}
${pop.referencias ? `<h2>12. Referências</h2><p>${pop.referencias}</p>` : ""}
</body></html>`;
  };

  const fetchPopData = async (popId: string) => {
    const { data, error } = await fromTable("funcao_pops")
      .select("*")
      .eq("id", popId)
      .single() as { data: any; error: any };
    if (error || !data) {
      toast.error("POP não encontrado. Pode ter sido removido.");
      return null;
    }
    return data;
  };

  const handleDownload = async (doc: DocumentoItem) => {
    try {
      if (doc.storage_path.startsWith("pop://")) {
        const pop = await fetchPopData(doc.storage_path.replace("pop://", ""));
        if (!pop) return;
        const html = generatePopHtml(pop);
        const blob = new Blob([html], { type: "text/html" });
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = `${pop.codigo} - ${pop.titulo}.html`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
        toast.success("POP exportado com sucesso!");
        return;
      }

      const url = await getSignedUrl(doc.storage_path);
      if (!url) {
        toast.error("Não foi possível gerar o link do documento. Verifique se o arquivo ainda existe.");
        return;
      }
      const response = await fetch(url);
      if (!response.ok) {
        toast.error("Erro ao baixar arquivo: " + response.statusText);
        return;
      }
      const blob = await response.blob();
      const blobUrl = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = blobUrl;
      a.download = doc.nome_original || "documento";
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(blobUrl);
    } catch (err: any) {
      console.error("Erro ao baixar documento:", err);
      toast.error("Erro ao acessar documento: " + (err.message || "Erro desconhecido"));
    }
  };

  const handleViewDoc = async (doc: DocumentoItem) => {
    try {
      if (doc.storage_path.startsWith("pop://")) {
        const pop = await fetchPopData(doc.storage_path.replace("pop://", ""));
        if (!pop) return;
        const html = generatePopHtml(pop);
        const blob = new Blob([html], { type: "text/html" });
        const url = URL.createObjectURL(blob);
        window.open(url, "_blank");
        setTimeout(() => URL.revokeObjectURL(url), 5000);
        return;
      }
      const url = await getSignedUrl(doc.storage_path);
      if (!url) {
        toast.error("Não foi possível gerar o link do documento.");
        return;
      }
      window.open(url, "_blank");
    } catch (err: any) {
      toast.error("Erro ao visualizar documento: " + (err.message || "Erro desconhecido"));
    }
  };

  const handleDeleteDoc = async (doc: DocumentoItem) => {
    const fullDoc = documentos.find(d => d.id === doc.id);
    if (fullDoc) {
      await deleteDocumento(fullDoc);
    }
  };

  const handleCreatePasta = async (data: { nome: string; tipo: string; pasta_pai_id: string | null }) => {
    await createPasta({
      nome: data.nome,
      tipo: data.tipo as 'custom' | 'ano' | 'mes' | 'categoria',
      pasta_pai_id: data.pasta_pai_id,
    });
  };

  const showEmptyState = !loading && pastas.length === 0;

  return (
    <div className="h-[calc(100vh-8rem)] flex flex-col gap-4">
      {/* Page Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4 }}
        className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4"
      >
        <div>
          <h1 className="text-2xl font-bold text-foreground">Documentos</h1>
          <p className="text-muted-foreground">Gestão hierárquica de arquivos e prontuários</p>
        </div>
        <div className="flex items-center gap-2">
          {podeGerirDocumentos && (
            <Button variant="outline" onClick={() => setShowCreatePasta(true)}>
              <FolderPlus className="w-4 h-4 mr-2" />
              Nova Pasta
            </Button>
          )}
          <Button onClick={() => handleOpenUpload(selectedPasta?.id)}>
            <Upload className="w-4 h-4 mr-2" />
            Upload
          </Button>
        </div>
      </motion.div>

      {/* Stats */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4, delay: 0.1 }}
        className="grid grid-cols-1 md:grid-cols-4 gap-4"
      >
        <div className="bg-primary/5 border border-primary/20 rounded-xl p-4 flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-primary/10">
            <FileText className="w-5 h-5 text-primary" />
          </div>
          <div>
            <p className="text-xl font-bold text-foreground">{stats.total}</p>
            <p className="text-xs text-muted-foreground">Total</p>
          </div>
        </div>
        <div className="bg-muted/50 border border-border rounded-xl p-4 flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-muted">
            <FolderTree className="w-5 h-5 text-muted-foreground" />
          </div>
          <div>
            <p className="text-xl font-bold text-foreground">{pastas.length}</p>
            <p className="text-xs text-muted-foreground">Pastas</p>
          </div>
        </div>
        <div className="bg-warning/5 border border-warning/20 rounded-xl p-4 flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-warning/10">
            <AlertCircle className="w-5 h-5 text-warning" />
          </div>
          <div>
            <p className="text-xl font-bold text-foreground">{stats.vencendo}</p>
            <p className="text-xs text-muted-foreground">Vencendo</p>
          </div>
        </div>
        <div className="bg-destructive/5 border border-destructive/20 rounded-xl p-4 flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-destructive/10">
            <AlertCircle className="w-5 h-5 text-destructive" />
          </div>
          <div>
            <p className="text-xl font-bold text-foreground">{stats.vencidos}</p>
            <p className="text-xs text-muted-foreground">Vencidos</p>
          </div>
        </div>
      </motion.div>

      {/* Tabs */}
      <Tabs value={activeTab} onValueChange={setActiveTab} className="flex-1 flex flex-col">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.4, delay: 0.15 }}
        >
          <TabsList className="bg-muted/50">
            <TabsTrigger value="arvore" className="gap-2">
              <FolderTree className="w-4 h-4" />
              Estrutura
            </TabsTrigger>
            {podeGerirDocumentos && (
              <>
                <TabsTrigger value="conformidade" className="gap-2">
                  <ShieldCheck className="w-4 h-4" />
                  Conformidade
                </TabsTrigger>
                <TabsTrigger value="radar" className="gap-2">
                  <Radar className="w-4 h-4" />
                  Governança
                </TabsTrigger>
                <TabsTrigger value="pdca" className="gap-2">
                  <RefreshCw className="w-4 h-4" />
                  PDCA
                </TabsTrigger>
                <TabsTrigger value="notificacoes" className="gap-2 relative">
                  <Bell className="w-4 h-4" />
                  Notificações
                  {(stats.vencidos > 0 || stats.vencendo > 0) && (
                    <span className="absolute -top-1 -right-1 bg-destructive text-destructive-foreground text-[10px] font-bold rounded-full min-w-[16px] h-4 flex items-center justify-center px-1">
                      {stats.vencidos + stats.vencendo}
                    </span>
                  )}
                </TabsTrigger>
                <TabsTrigger value="historico" className="gap-2">
                  <History className="w-4 h-4" />
                  Auditoria
                </TabsTrigger>
              </>
            )}
          </TabsList>
        </motion.div>

        {/* Tree View Tab */}
        <TabsContent value="arvore" className="flex-1 min-h-0 mt-4 flex flex-col">
          {showEmptyState ? (
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              className="flex flex-col items-center justify-center h-full bg-card rounded-xl border border-border border-dashed p-12"
            >
              {podeGerirDocumentos ? (
                <>
                  <Loader2 className="w-10 h-10 text-primary animate-spin mb-4" />
                  <h3 className="text-xl font-semibold mb-2">Gerando estrutura de pastas…</h3>
                  <p className="text-muted-foreground text-center max-w-md">
                    A estrutura padrão está sendo criada automaticamente para esta empresa.
                  </p>
                </>
              ) : (
                <>
                  <FolderTree className="w-10 h-10 text-muted-foreground mb-4" />
                  <h3 className="text-xl font-semibold mb-2">Nenhuma pasta disponível</h3>
                  <p className="text-muted-foreground text-center max-w-md">
                    Seu acesso aos documentos está limitado à sua própria pasta. Se ela
                    ainda não aparece, peça ao RH para criá-la.
                  </p>
                </>
              )}
            </motion.div>
          ) : (
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              className="flex-1 min-h-0"
            >
              <ResizablePanelGroup direction="horizontal" className="h-full rounded-xl border border-border">
                {/* Tree Panel */}
                <ResizablePanel defaultSize={30} minSize={20} maxSize={50}>
                  <div className="h-full flex flex-col bg-card">
                    {/* Search + Expand/Collapse */}
                    <div className="p-3 border-b border-border space-y-2">
                      <div className="relative">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                        <Input
                          placeholder="Buscar pasta..."
                          value={searchTerm}
                          onChange={(e) => setSearchTerm(e.target.value)}
                          className="pl-9 h-9"
                        />
                      </div>
                      <div className="flex gap-1">
                        <Button
                          variant="ghost"
                          size="sm"
                          className="h-7 text-xs flex-1"
                          onClick={() => setExpandAllSignal(prev => ({ expand: true, key: prev.key + 1 }))}
                        >
                          <UnfoldVertical className="w-3.5 h-3.5 mr-1" />
                          Expandir
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          className="h-7 text-xs flex-1"
                          onClick={() => setExpandAllSignal(prev => ({ expand: false, key: prev.key + 1 }))}
                        >
                          <FoldVertical className="w-3.5 h-3.5 mr-1" />
                          Minimizar
                        </Button>
                      </div>
                    </div>
                    
                    {/* Tree */}
                    <div className="flex-1 min-h-0 relative">
                      <div className="absolute inset-0 overflow-y-scroll overflow-x-hidden documentos-folder-tree-scroll">
                        <div className="p-2 pr-3">
                      {loading ? (
                        <div className="flex items-center justify-center py-8">
                          <Loader2 className="w-6 h-6 animate-spin text-primary" />
                        </div>
                      ) : (
                        <PastaTreeView
                          tree={searchTerm ? filterTree(tree, searchTerm) : tree}
                          selectedPastaId={selectedPasta?.id || null}
                          onSelectPasta={setSelectedPasta}
                          onCreateSubfolder={handleCreateSubfolder}
                          onRenamePasta={handleRenamePasta}
                          onDeletePasta={handleDeletePasta}
                          onDropDocument={handleDropDocument}
                          expandAllSignal={expandAllSignal}
                        />
                      )}
                        </div>
                      </div>
                    </div>
                  </div>
                </ResizablePanel>

                <ResizableHandle withHandle />

                {/* Documents Panel */}
                <ResizablePanel defaultSize={70}>
                  <div className="h-full p-4 bg-background">
                    <PastaDocumentosList
                      pasta={livePasta}
                      onUpload={handleOpenUpload}
                      onCreateSubfolder={handleCreateSubfolder}

                      onView={handleViewDoc}
                      onDownload={handleDownload}
                      onDelete={handleDeleteDoc}
                      deleting={deleting}
                      onDragStart={handleDragStart}
                      documentosCompletos={documentos}
                      onNovaVersao={(doc) => {
                        setNovaVersaoDocId(doc.id);
                        setUploadForPastaId(selectedPasta?.id);
                        setShowUploadForm(true);
                      }}
                    />
                  </div>
                </ResizablePanel>
              </ResizablePanelGroup>
            </motion.div>
          )}
        </TabsContent>

        {/* Conformidade Tab */}
        <TabsContent value="conformidade" className="flex-1 mt-4">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="bg-card rounded-xl border border-border p-6"
          >
            <div className="flex items-center justify-between mb-6">
              <div>
                <h3 className="font-semibold flex items-center gap-2">
                  <ShieldCheck className="w-5 h-5 text-primary" />
                  Mapa de Conformidade Documental
                </h3>
                <p className="text-xs text-muted-foreground mt-0.5">Visão consolidada dos documentos esperados vs. existentes por categoria</p>
              </div>
            </div>
            <MapaConformidade tree={tree} pastas={pastas} />
          </motion.div>
        </TabsContent>

        {/* Radar Governança Tab */}
        <TabsContent value="radar" className="flex-1 mt-4">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="space-y-4"
          >
            <RadarGovernanca tree={tree} />
          </motion.div>
        </TabsContent>

        {/* PDCA Tab */}
        <TabsContent value="pdca" className="flex-1 mt-4">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="bg-card rounded-xl border border-border p-6"
          >
            <div className="flex items-center justify-between mb-6">
              <div>
                <h3 className="font-semibold flex items-center gap-2">
                  <RefreshCw className="w-5 h-5 text-primary" />
                  Motor de Melhoria Contínua — PDCA
                </h3>
                <p className="text-xs text-muted-foreground mt-0.5">
                  Consolidação de riscos, ações, auditorias e melhorias em um único painel
                </p>
              </div>
            </div>
            <PDCADashboard />
          </motion.div>
        </TabsContent>

        {/* Notificações Tab */}
        <TabsContent value="notificacoes" className="flex-1 mt-4">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="h-full bg-card rounded-xl border border-border p-6 overflow-auto"
          >
            <NotificacoesVencimento documentos={documentos} />
          </motion.div>
        </TabsContent>

        {/* Audit Tab */}
        <TabsContent value="historico" className="flex-1 mt-4">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="h-full bg-card rounded-xl border border-border p-6 flex flex-col gap-4 overflow-hidden"
          >
            <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
              <div className="flex items-center gap-2">
                <History className="w-5 h-5 text-primary" />
                <h3 className="font-semibold">Trilha de Auditoria</h3>
                <Badge variant="outline">{auditLogs.length} registros</Badge>
              </div>

              <div className="flex flex-col sm:flex-row gap-2 w-full sm:w-auto">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                  <Input 
                    placeholder="Filtrar por nome ou usuário..." 
                    className="pl-10 w-full sm:w-64"
                    value={auditSearchTerm}
                    onChange={(e) => setAuditSearchTerm(e.target.value)}
                  />
                </div>
                <select 
                  className="h-10 px-3 rounded-md border border-input bg-background text-sm focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2"
                  value={auditActionFilter}
                  onChange={(e) => setAuditActionFilter(e.target.value)}
                >
                  <option value="all">Ações: Todas</option>
                  <option value="upload">Upload</option>
                  <option value="move">Movimentação</option>
                  <option value="rename">Renomeação</option>
                  <option value="delete">Exclusão</option>
                  <option value="restore">Restauração</option>
                </select>
              </div>
            </div>

            <ScrollArea className="flex-1">
              <DocumentoAuditLog 
                loading={loadingAudit} 
                logs={auditLogs.filter(log => {
                  const term = auditSearchTerm.toLowerCase();
                  const matchesSearch = !auditSearchTerm || 
                    log.documento_nome.toLowerCase().includes(term) ||
                    (log.usuario_nome || "").toLowerCase().includes(term);
                  
                  const matchesAction = auditActionFilter === "all" || log.acao === auditActionFilter;
                  
                  return matchesSearch && matchesAction;
                })} 
              />
            </ScrollArea>
          </motion.div>
        </TabsContent>
      </Tabs>

      {/* Modals */}

      <DocumentoUploadForm
        open={showUploadForm}
        onOpenChange={(v) => { setShowUploadForm(v); if (!v) setNovaVersaoDocId(undefined); }}
        preSelectedColaboradorId={uploadPastaColaboradorId}
        colaboradorObrigatorio={!!uploadPastaColaboradorId}
        documentoExistenteId={novaVersaoDocId}
        pastaId={uploadForPastaId}
      />

      <CreatePastaModal
        open={showCreatePasta}
        onOpenChange={setShowCreatePasta}
        parentPastaId={createPastaParentId}
        parentPastaNome={createPastaParentNome}
        onCreate={handleCreatePasta}
        creating={false}
      />

      {/* Delete Pasta Confirmation */}
      <AlertDialog open={!!pastaToDelete} onOpenChange={() => setPastaToDelete(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle className="flex items-center gap-2">
              <AlertCircle className="w-5 h-5 text-destructive" />
              Excluir Pasta
            </AlertDialogTitle>
            <AlertDialogDescription>
              Tem certeza que deseja excluir esta pasta? Todas as subpastas também serão excluídas.
              Os documentos não serão excluídos, apenas ficarão sem pasta.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction
              onClick={confirmDeletePasta}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              Excluir
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Rename Pasta Dialog */}
      <Dialog open={!!pastaToRename} onOpenChange={(o) => { if (!o) setPastaToRename(null); }}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Pencil className="w-4 h-4" />
              Renomear Pasta
            </DialogTitle>
          </DialogHeader>
          <div className="py-2">
            <Label className="text-xs text-muted-foreground mb-1.5 block">Novo nome</Label>
            <Input
              value={renameValue}
              onChange={(e) => setRenameValue(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && confirmRenamePasta()}
              autoFocus
            />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setPastaToRename(null)}>Cancelar</Button>
            <Button onClick={confirmRenamePasta} disabled={renaming || !renameValue.trim()}>
              {renaming ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : null}
              Salvar
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default Documentos;
