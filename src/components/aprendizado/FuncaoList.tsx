import { useState } from "react";
import { Link } from "react-router-dom";
import { Search, Briefcase, ClipboardList, Brain, Shield, FileText, BookOpen, Loader2, Eye, ChevronDown, CheckCircle2, Plus } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { ManualFuncaoModal } from "./ManualFuncaoModal";
import { toast } from "sonner";
import { arquivarDocumento } from "@/utils/arquivarDocumento";
import { CriarFuncaoRapidaDialog } from "./CriarFuncaoRapidaDialog";
import { CompletudeBadgePopover } from "./CompletudeChecklist";
import { useCompletudeCargos } from "@/hooks/useCompletudeAprendizado";
import type { PopData } from "@/hooks/usePopAtividade";

interface Cargo {
  id: string;
  nome: string;
  nivel: string | null;
  departamento_id: string | null;
  descricao: string | null;
  objetivo_funcao?: string | null;
  departamento?: { id: string; nome: string } | null;
}

interface FuncaoListProps {
  cargos: Cargo[];
  isLoading: boolean;
  onSelect: (id: string) => void;
}

export function FuncaoList({ cargos, isLoading, onSelect }: FuncaoListProps) {
  const [search, setSearch] = useState("");
  const { tenantId, user, profile } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const [manualHtml, setManualHtml] = useState("");
  const [manualLoading, setManualLoading] = useState(false);
  const [manualOpen, setManualOpen] = useState(false);
  const [manualTitulo, setManualTitulo] = useState("");
  const [generatingId, setGeneratingId] = useState<string | null>(null);
  const [currentManualRef, setCurrentManualRef] = useState<string | null>(null);
  const [criarOpen, setCriarOpen] = useState(false);

  // Load cached manuals
  const { data: cachedManuais = [], refetch: refetchManuais } = useQuery({
    queryKey: ["manuais_gerados", tenantId, "funcao"],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data } = await fromTable("manuais_gerados")
        .select("id, tipo, referencia_id, titulo, html, created_at")
        .eq("tenant_id", tenantId)
        .in("tipo", ["funcao", "funcao_global"])
        .order("created_at", { ascending: false }) as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const getCachedManual = (tipo: string, refId?: string) => {
    return cachedManuais.find(
      (m: any) => m.tipo === tipo && (refId ? m.referencia_id === refId : !m.referencia_id)
    );
  };

  // Count activities and competencies per cargo
  const { data: atividadeCounts = {} } = useQuery({
    queryKey: ["funcao_atividades_count", tenantId],
    queryFn: async () => {
      if (!tenantId) return {};
      const { data, error } = await fromTable("funcao_atividades")
        .select("cargo_id")
        .eq("tenant_id", tenantId) as { data: { cargo_id: string }[] | null; error: Error | null };
      if (error) return {};
      const counts: Record<string, number> = {};
      (data || []).forEach((d) => { counts[d.cargo_id] = (counts[d.cargo_id] || 0) + 1; });
      return counts;
    },
    enabled: !!tenantId,
  });

  const { data: competenciaCounts = {} } = useQuery({
    queryKey: ["funcao_competencias_count", tenantId],
    queryFn: async () => {
      if (!tenantId) return {};
      const { data, error } = await fromTable("funcao_competencias")
        .select("cargo_id")
        .eq("tenant_id", tenantId) as { data: { cargo_id: string }[] | null; error: Error | null };
      if (error) return {};
      const counts: Record<string, number> = {};
      (data || []).forEach((d) => { counts[d.cargo_id] = (counts[d.cargo_id] || 0) + 1; });
      return counts;
    },
    enabled: !!tenantId,
  });

  const { data: epiCounts = {} } = useQuery({
    queryKey: ["funcao_epi_count", tenantId],
    queryFn: async () => {
      if (!tenantId) return {};
      const { data, error } = await fromTable("funcao_epi_vinculacoes")
        .select("cargo_id")
        .eq("tenant_id", tenantId) as { data: { cargo_id: string }[] | null; error: Error | null };
      if (error) return {};
      const counts: Record<string, number> = {};
      (data || []).forEach((d) => { counts[d.cargo_id] = (counts[d.cargo_id] || 0) + 1; });
      return counts;
    },
    enabled: !!tenantId,
  });

  const { completudePorCargo } = useCompletudeCargos(cargos);

  const filtered = cargos.filter(
    (c) =>
      c.nome.toLowerCase().includes(search.toLowerCase()) ||
      (c.nivel || "").toLowerCase().includes(search.toLowerCase())
  );

  const nivelLabel: Record<string, string> = {
    operacional: "Operacional",
    tatico: "Tático",
    estrategico: "Estratégico",
  };

  const nivelColor: Record<string, string> = {
    operacional: "bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-300",
    tatico: "bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300",
    estrategico: "bg-purple-100 text-purple-800 dark:bg-purple-900/30 dark:text-purple-300",
  };

  const saveManualCache = async (tipo: string, refId: string | null, titulo: string, html: string) => {
    if (!tenantId || !user) return;
    try {
      // Upsert: delete old and insert new
      await fromTable("manuais_gerados")
        .delete()
        .eq("tenant_id", tenantId)
        .eq("tipo", tipo)
        .eq("referencia_id", refId || "");

      await fromTable("manuais_gerados").insert({
        tenant_id: tenantId,
        empresa_id: empresaAtivaId || null,
        tipo,
        referencia_id: refId || null,
        titulo,
        html,
        gerado_por: user.id,
        gerado_por_nome: profile?.nome_completo || "",
      } as any);

      refetchManuais();
    } catch (err) {
      console.error("Erro ao salvar cache do manual:", err);
    }
  };

  const archiveManual = async (html: string, titulo: string) => {
    if (!tenantId || !user) return;
    try {
      const blob = new Blob([html], { type: "text/html;charset=utf-8" });
      const safeTitulo = titulo.replace(/[^a-zA-Z0-9\s]/g, "").replace(/\s+/g, "-").substring(0, 50);
      const fileName = `${safeTitulo}-${Date.now()}.html`;

      await arquivarDocumento({
        tenantId,
        empresaId: empresaAtivaId,
        userId: user.id,
        userNome: profile?.nome_completo || "",
        file: blob,
        fileName,
        mimeType: "text/html",
        tipo: "Manual de Função",
        observacoes: `Manual gerado por IA: ${titulo}`,
        pastaCategoria: "Aprendizado",
      });
    } catch (err) {
      console.error("Erro ao arquivar manual:", err);
    }
  };

  const gerarManual = async (cargoIds: string[] | null, titulo: string) => {
    try {
      setManualHtml("");
      setManualLoading(true);
      setManualOpen(true);
      setManualTitulo(titulo);

      const { data, error } = await supabase.functions.invoke("ai-manual-funcao", {
        body: { cargo_ids: cargoIds, tenantId },
      });

      if (error) {
        // supabase.functions.invoke wraps non-2xx as FunctionsHttpError
        // Try to extract the JSON body for a better message
        let msg = error.message || "Erro ao gerar manual";
        try {
          const ctx = (error as any).context;
          if (ctx && typeof ctx.json === "function") {
            const body = await ctx.json();
            if (body?.error) msg = body.error;
          }
        } catch { /* ignore */ }
        throw new Error(msg);
      }
      if (data?.error) throw new Error(data.error);

      const html = data.html || "";
      setManualHtml(html);

      // Save to cache and archive
      const tipo = cargoIds ? "funcao" : "funcao_global";
      const refId = cargoIds ? cargoIds[0] : null;
      setCurrentManualRef(refId);

      await saveManualCache(tipo, refId, titulo, html);
      await archiveManual(html, titulo);

      toast.success("Manual gerado e arquivado com sucesso!");
    } catch (err: any) {
      toast.error(err.message || "Erro ao gerar manual");
      setManualOpen(false);
    } finally {
      setManualLoading(false);
      setGeneratingId(null);
    }
  };

  const handleGerarPorFuncao = (e: React.MouseEvent, cargo: Cargo) => {
    e.stopPropagation();
    setGeneratingId(cargo.id);
    gerarManual([cargo.id], `Manual: ${cargo.nome}`);
  };

  const handleGerarGlobal = () => {
    setGeneratingId("global");
    gerarManual(null, "Manual Global de Funções");
  };

  const fetchPopsForCargo = async (cargoId: string): Promise<PopData[]> => {
    if (!tenantId) return [];
    const { data } = await fromTable("funcao_pops")
      .select("*")
      .eq("tenant_id", tenantId)
      .eq("cargo_id", cargoId)
      .order("codigo") as { data: PopData[] | null };
    return data || [];
  };

  const buildPopsHtmlSection = (pops: PopData[]): string => {
    if (!pops.length) return "";
    
    const popSections = pops.map((pop, i) => {
      const resp = (pop.responsabilidades || {}) as Record<string, string>;
      const passos = pop.procedimento_passos || [];
      
      return `
        <div style="page-break-before: always; padding: 32px 24px; max-width: 100%; box-sizing: border-box; overflow-wrap: break-word; word-wrap: break-word; word-break: break-word;">
          <h2 style="font-size: 22px; color: #1e3a5f; border-bottom: 3px solid #2563eb; padding-bottom: 8px; margin-bottom: 16px; word-wrap: break-word;">
            POP ${i + 1}: ${pop.codigo} - ${pop.titulo}
          </h2>
          <div style="display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 16px;">
            <span style="background: #f0f7ff; padding: 4px 12px; border-radius: 6px; font-size: 13px; color: #1e40af;">Versão: ${pop.versao_atual || "1.0"}</span>
            <span style="background: #f0f7ff; padding: 4px 12px; border-radius: 6px; font-size: 13px; color: #1e40af;">Status: ${pop.status}</span>
            ${pop.gerado_por_ia ? '<span style="background: #fef3c7; padding: 4px 12px; border-radius: 6px; font-size: 13px; color: #92640a;">Gerado por IA</span>' : ''}
          </div>
          ${pop.objetivo ? `<div style="margin-bottom: 14px;"><h3 style="font-size: 15px; color: #1a365d; margin-bottom: 4px;">1. Objetivo</h3><p style="font-size: 14px; color: #333; text-align: justify; line-height: 1.6; overflow-wrap: break-word; word-wrap: break-word;">${pop.objetivo}</p></div>` : ''}
          ${pop.escopo ? `<div style="margin-bottom: 14px;"><h3 style="font-size: 15px; color: #1a365d; margin-bottom: 4px;">2. Escopo</h3><p style="font-size: 14px; color: #333; text-align: justify; line-height: 1.6; overflow-wrap: break-word; word-wrap: break-word;">${pop.escopo}</p></div>` : ''}
          ${(resp.executante || resp.supervisao || resp.interfaces) ? `
            <div style="margin-bottom: 14px;"><h3 style="font-size: 15px; color: #1a365d; margin-bottom: 4px;">3. Responsabilidades</h3>
            <ul style="font-size: 14px; color: #333; line-height: 1.8; padding-left: 20px; overflow-wrap: break-word; word-wrap: break-word;">
              ${resp.executante ? `<li><strong>Executante:</strong> ${resp.executante}</li>` : ''}
              ${resp.supervisao ? `<li><strong>Supervisão:</strong> ${resp.supervisao}</li>` : ''}
              ${resp.interfaces ? `<li><strong>Interfaces:</strong> ${resp.interfaces}</li>` : ''}
            </ul></div>` : ''}
          ${pop.definicoes ? `<div style="margin-bottom: 14px;"><h3 style="font-size: 15px; color: #1a365d; margin-bottom: 4px;">4. Definições</h3><p style="font-size: 14px; color: #333; text-align: justify; line-height: 1.6; overflow-wrap: break-word; word-wrap: break-word;">${pop.definicoes}</p></div>` : ''}
          ${pop.pre_requisitos?.length ? `<div style="margin-bottom: 14px;"><h3 style="font-size: 15px; color: #1a365d; margin-bottom: 4px;">5. Pré-requisitos</h3><ul style="font-size: 14px; color: #333; line-height: 1.8; padding-left: 20px; overflow-wrap: break-word; word-wrap: break-word;">${pop.pre_requisitos.map(p => `<li>${p}</li>`).join('')}</ul></div>` : ''}
          ${pop.materiais_ferramentas?.length ? `<div style="margin-bottom: 14px;"><h3 style="font-size: 15px; color: #1a365d; margin-bottom: 4px;">6. Materiais e Ferramentas</h3><ul style="font-size: 14px; color: #333; line-height: 1.8; padding-left: 20px; overflow-wrap: break-word; word-wrap: break-word;">${pop.materiais_ferramentas.map(m => `<li>${m}</li>`).join('')}</ul></div>` : ''}
          ${pop.epis_sst ? `<div style="margin-bottom: 14px;"><h3 style="font-size: 15px; color: #1a365d; margin-bottom: 4px;">7. EPIs / SST</h3><p style="font-size: 14px; color: #333; text-align: justify; line-height: 1.6; overflow-wrap: break-word; word-wrap: break-word;">${pop.epis_sst}</p></div>` : ''}
          ${passos.length ? `
            <div style="margin-bottom: 14px;"><h3 style="font-size: 15px; color: #1a365d; margin-bottom: 8px;">8. Procedimento Passo a Passo</h3>
            ${passos.map(p => `
              <div style="background: #f0f7ff; border-radius: 8px; padding: 12px 16px; margin-bottom: 8px; overflow-wrap: break-word; word-wrap: break-word; word-break: break-word; box-sizing: border-box;">
                <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 4px; flex-wrap: wrap;">
                  <span style="background: #2563eb; color: #fff; padding: 2px 10px; border-radius: 4px; font-size: 12px; font-weight: bold;">Passo ${p.numero}</span>
                  ${p.tempo_estimado ? `<span style="font-size: 12px; color: #666;">(${p.tempo_estimado})</span>` : ''}
                </div>
                <p style="font-size: 14px; color: #333; margin: 4px 0 0 0; line-height: 1.5; text-align: justify; overflow-wrap: break-word; word-wrap: break-word;">${p.descricao}</p>
                ${p.ponto_atencao ? `<div style="background: #fef3c7; border-radius: 4px; padding: 6px 10px; margin-top: 6px; font-size: 13px; color: #92640a; overflow-wrap: break-word; word-wrap: break-word;"><strong>⚠ Atenção:</strong> ${p.ponto_atencao}</div>` : ''}
              </div>
            `).join('')}
            </div>` : ''}
          ${pop.criterios_qualidade ? `<div style="margin-bottom: 14px;"><h3 style="font-size: 15px; color: #1a365d; margin-bottom: 4px;">9. Critérios de Qualidade</h3><p style="font-size: 14px; color: #333; text-align: justify; line-height: 1.6; overflow-wrap: break-word; word-wrap: break-word;">${pop.criterios_qualidade}</p></div>` : ''}
          ${pop.registros_evidencias ? `<div style="margin-bottom: 14px;"><h3 style="font-size: 15px; color: #1a365d; margin-bottom: 4px;">10. Registros e Evidências</h3><p style="font-size: 14px; color: #333; text-align: justify; line-height: 1.6; overflow-wrap: break-word; word-wrap: break-word;">${pop.registros_evidencias}</p></div>` : ''}
          ${pop.tratamento_nao_conformidades ? `<div style="margin-bottom: 14px;"><h3 style="font-size: 15px; color: #1a365d; margin-bottom: 4px;">11. Tratamento de Não Conformidades</h3><p style="font-size: 14px; color: #333; text-align: justify; line-height: 1.6; overflow-wrap: break-word; word-wrap: break-word;">${pop.tratamento_nao_conformidades}</p></div>` : ''}
          ${pop.referencias ? `<div style="margin-bottom: 14px;"><h3 style="font-size: 15px; color: #1a365d; margin-bottom: 4px;">12. Referências</h3><p style="font-size: 14px; color: #333; text-align: justify; line-height: 1.6; overflow-wrap: break-word; word-wrap: break-word;">${pop.referencias}</p></div>` : ''}
        </div>
      `;
    }).join('');

    // Wrapper neutraliza qualquer layout de colunas/grid/flex herdado do Manual
    const resetWrapperStyle = [
      "all: initial",
      "display: block",
      "width: 100%",
      "max-width: 100%",
      "column-count: 1 !important",
      "columns: auto !important",
      "column-span: all !important",
      "-webkit-column-count: 1 !important",
      "-webkit-column-span: all !important",
      "float: none",
      "clear: both",
      "box-sizing: border-box",
      "font-family: inherit",
      "color: #333",
      "background: #ffffff",
    ].join("; ");

    return `
      <div style="${resetWrapperStyle}">
        <style>
          .pop-reset-container, .pop-reset-container * {
            column-count: 1 !important;
            column-span: all !important;
            -webkit-column-count: 1 !important;
            -webkit-column-span: all !important;
            float: none !important;
          }
          .pop-reset-container { display: block !important; width: 100% !important; }
        </style>
        <div class="pop-reset-container">
          <div style="page-break-before: always; padding: 40px 24px; text-align: center; box-sizing: border-box;">
            <h1 style="font-size: 28px; color: #1e3a5f; margin-bottom: 8px;">Procedimentos Operacionais Padrão (POPs)</h1>
            <p style="font-size: 14px; color: #888;">${pops.length} procedimento${pops.length !== 1 ? 's' : ''} vinculado${pops.length !== 1 ? 's' : ''}</p>
            <hr style="border: 1px solid #e5e7eb; margin: 20px 0;" />
          </div>
          ${popSections}
        </div>
      </div>
    `;
  };

  const combineManualWithPops = (manualHtml: string, popsHtml: string): string => {
    if (!popsHtml) return manualHtml;
    // Inserir os POPs APÓS </body> e </html> não é válido; então fechamos qualquer
    // container de colunas inserindo os POPs depois do </body> original via replace,
    // mas envoltos no wrapper que reseta colunas.
    if (manualHtml.toLowerCase().includes("</body>")) {
      return manualHtml.replace(/<\/body>/i, `${popsHtml}</body>`);
    }
    return manualHtml + popsHtml;
  };

  const handleVisualizarCached = (e: React.MouseEvent, cached: any) => {
    e.stopPropagation();
    setManualHtml(cached.html);
    setManualTitulo(cached.titulo);
    setManualOpen(true);
    setCurrentManualRef(cached.referencia_id);
  };

  const handleVisualizarComPops = async (e: React.MouseEvent, cached: any, cargoId: string) => {
    e.stopPropagation();
    try {
      const pops = await fetchPopsForCargo(cargoId);
      if (!pops.length) {
        toast.info("Nenhum POP encontrado para esta função. Exibindo apenas o manual.");
        handleVisualizarCached(e, cached);
        return;
      }
      const popsHtml = buildPopsHtmlSection(pops);
      const combined = combineManualWithPops(cached.html, popsHtml);
      setManualHtml(combined);
      setManualTitulo(`${cached.titulo} + POPs`);
      setManualOpen(true);
      setCurrentManualRef(cached.referencia_id);
    } catch (err) {
      console.error("Erro ao carregar POPs:", err);
      toast.error("Erro ao carregar POPs. Exibindo apenas o manual.");
      handleVisualizarCached(e, cached);
    }
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
        tipo: "Manual de Função (PDF)",
        observacoes: `PDF do manual: ${manualTitulo}`,
        pastaCategoria: "Aprendizado",
      });
      toast.success("PDF arquivado no módulo Documentos!");
    } catch (err) {
      console.error("Erro ao arquivar PDF:", err);
    }
  };

  if (isLoading) {
    return (
      <div className="space-y-3">
        {[1, 2, 3].map((i) => <Skeleton key={i} className="h-20 w-full rounded-xl" />)}
      </div>
    );
  }

  const globalCached = getCachedManual("funcao_global");

  return (
    <div className="space-y-4">
      <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-3">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <Input
            placeholder="Buscar funções..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-9"
          />
        </div>
        <div className="flex gap-2">
          {globalCached && (
            <Button
              variant="outline"
              size="sm"
              onClick={(e) => handleVisualizarCached(e, globalCached)}
              className="whitespace-nowrap gap-1.5 w-full sm:w-auto"
            >
              <Eye className="w-4 h-4" />
              Ver Manual Global
            </Button>
          )}
          <Button
            variant="outline"
            size="sm"
            onClick={handleGerarGlobal}
            disabled={!!generatingId || cargos.length === 0}
            className="whitespace-nowrap gap-1.5 w-full sm:w-auto"
          >
            {generatingId === "global" ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : (
              <BookOpen className="w-4 h-4" />
            )}
            {globalCached ? "Regerar Manual Global" : "Gerar Manual Global"}
          </Button>
        </div>
      </div>

      {filtered.length === 0 ? (
        cargos.length === 0 ? (
          <div className="text-center py-12 text-muted-foreground">
            <Briefcase className="w-12 h-12 mx-auto mb-3 opacity-30" />
            <p className="text-foreground font-medium">Nenhuma função cadastrada ainda.</p>
            <p className="text-sm mt-1">Crie a primeira função para começar a montar atividades, competências e POPs.</p>
            <div className="mt-4 flex flex-col items-center gap-2">
              <Button onClick={() => setCriarOpen(true)} className="gap-2">
                <Plus className="w-4 h-4" />
                Criar primeira função
              </Button>
              <Link
                to="/cadastros/cargos"
                className="text-xs text-muted-foreground underline underline-offset-2 hover:text-foreground"
              >
                ou gerenciar em Cadastros → Funções
              </Link>
            </div>
          </div>
        ) : (
          <div className="text-center py-12 text-muted-foreground">
            <Search className="w-12 h-12 mx-auto mb-3 opacity-30" />
            <p>Nenhuma função encontrada para “{search}”.</p>
            <p className="text-sm">Ajuste a busca ou crie uma nova função.</p>
            <Button variant="outline" size="sm" onClick={() => setCriarOpen(true)} className="gap-2 mt-4">
              <Plus className="w-4 h-4" />
              Criar função
            </Button>
          </div>
        )
      ) : (
        <div className="grid gap-3">
          {filtered.map((cargo) => {
            const cached = getCachedManual("funcao", cargo.id);
            return (
              <Card
                key={cargo.id}
                className="cursor-pointer hover:border-primary/50 transition-colors"
                onClick={() => onSelect(cargo.id)}
              >
                <CardContent className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
                      <Briefcase className="w-5 h-5 text-primary" />
                    </div>
                    <div>
                      <p className="font-medium text-foreground flex items-center gap-1.5">
                        {cargo.nome}
                        {cached && (
                          <span title="Manual gerado" className="text-emerald-500">
                            <CheckCircle2 className="w-4 h-4" />
                          </span>
                        )}
                      </p>
                      <div className="flex items-center gap-2 mt-1 flex-wrap">
                        {cached && (
                          <Badge variant="secondary" className="text-[10px] bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400">
                            Manual gerado
                          </Badge>
                        )}
                        {cargo.departamento?.nome && (
                          <span className="text-xs text-muted-foreground font-normal">
                            {cargo.departamento.nome}
                          </span>
                        )}
                        {cargo.departamento?.nome && cargo.nivel && (
                          <span className="text-xs text-muted-foreground/40">•</span>
                        )}
                        {cargo.nivel && (
                          <Badge variant="secondary" className={`text-xs ${nivelColor[cargo.nivel] || ""}`}>
                            {nivelLabel[cargo.nivel] || cargo.nivel}
                          </Badge>
                        )}
                      </div>
                    </div>
                  </div>

                  <div className="flex flex-wrap items-center gap-3 text-xs text-muted-foreground w-full sm:w-auto justify-between sm:justify-end">
                    <span className="flex items-center gap-1" title="Atividades">
                      <ClipboardList className="w-3.5 h-3.5" />
                      {atividadeCounts[cargo.id] || 0}
                    </span>
                    <span className="flex items-center gap-1" title="Competências">
                      <Brain className="w-3.5 h-3.5" />
                      {competenciaCounts[cargo.id] || 0}
                    </span>
                    <span className="flex items-center gap-1" title="EPIs">
                      <Shield className="w-3.5 h-3.5" />
                      {epiCounts[cargo.id] || 0}
                    </span>
                    {completudePorCargo[cargo.id] && (
                      <CompletudeBadgePopover
                        resultado={completudePorCargo[cargo.id]}
                        onNavegar={() => onSelect(cargo.id)}
                      />
                    )}
                    {cached && (
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild onClick={(e) => e.stopPropagation()}>
                          <Button variant="ghost" size="sm" className="gap-1.5 w-full sm:w-auto">
                            <Eye className="w-4 h-4" />
                            Ver Manual
                            <ChevronDown className="w-3 h-3 ml-0.5" />
                          </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end" onClick={(e) => e.stopPropagation()}>
                          <DropdownMenuItem onClick={(e) => handleVisualizarCached(e as any, cached)}>
                            <FileText className="w-4 h-4 mr-2" />
                            Apenas Manual
                          </DropdownMenuItem>
                          <DropdownMenuItem onClick={(e) => handleVisualizarComPops(e as any, cached, cargo.id)}>
                            <BookOpen className="w-4 h-4 mr-2" />
                            Manual + POPs
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    )}
                    <Button
                      variant="outline"
                      size="sm"
                      className="gap-1.5 w-full sm:w-auto"
                      disabled={!!generatingId}
                      onClick={(e) => handleGerarPorFuncao(e, cargo)}
                    >
                      {generatingId === cargo.id ? (
                        <Loader2 className="w-4 h-4 animate-spin" />
                      ) : (
                        <FileText className="w-4 h-4" />
                      )}
                      {cached ? "Regerar" : "Gerar Manual"}
                    </Button>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}

      <ManualFuncaoModal
        open={manualOpen}
        onClose={() => setManualOpen(false)}
        html={manualHtml}
        loading={manualLoading}
        titulo={manualTitulo}
        onPdfGenerated={handlePdfArchive}
        cargoId={currentManualRef}
        cargoNome={currentManualRef ? (cargos.find((c) => c.id === currentManualRef)?.nome || null) : null}
      />

      <CriarFuncaoRapidaDialog
        open={criarOpen}
        onClose={() => setCriarOpen(false)}
        onCreated={(id) => onSelect(id)}
      />
    </div>
  );
}
