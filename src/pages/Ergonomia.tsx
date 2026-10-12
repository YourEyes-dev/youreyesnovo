import { useState } from "react";
import { motion } from "framer-motion";
import {
  Activity,
  RefreshCw,
  Plus,
  AlertTriangle,
  ClipboardCheck,
  Brain,
  Building2,
  FileText,
  ShieldCheck,
  ChevronRight,
  Dumbbell,
  Database,
  Map,
  BarChart3,
  Search,
  BarChart2,
  ListChecks,
  Wrench,
  Eye,
  HelpCircle,
  Zap,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Skeleton } from "@/components/ui/skeleton";
import { useErgonomia } from "@/hooks/useErgonomia";
import { useErgonomiaAnalises } from "@/hooks/useErgonomiaAnalises";
import { CategoriaCard } from "@/components/ergonomia/CategoriaCard";
import { ItemDetailModal } from "@/components/ergonomia/ItemDetailModal";
import { EmptyState } from "@/components/ergonomia/EmptyState";
import { AcaoForm } from "@/components/ergonomia/AcaoForm";
import { AcoesList } from "@/components/ergonomia/AcoesList";
import { AnaliseIASection } from "@/components/ergonomia/AnaliseIASection";
import { RegistrosErgonomicos } from "@/components/ergonomia/RegistrosErgonomicos";
import { MapaRiscoErgonomico } from "@/components/ergonomia/MapaRiscoErgonomico";
import { InventarioRiscos } from "@/components/ergonomia/InventarioRiscos";
import { AEPGenerator } from "@/components/ergonomia/aep/AEPGenerator";
import { AEPGeneratorMulti } from "@/components/ergonomia/aep/AEPGeneratorMulti";
import { GROPainel } from "@/components/ergonomia/GROPainel";
import { DocumentoMetodologia } from "@/components/ergonomia/DocumentoMetodologia";
import { ComunicacaoTrabalhadores } from "@/components/ergonomia/ComunicacaoTrabalhadores";
import { GuiaRapidoErgonomia } from "@/components/ergonomia/GuiaRapidoErgonomia";
import { useGRORiscos } from "@/hooks/useGRORiscos";
import { RiscoForm } from "@/components/ergonomia/RiscoForm";
import {
  ITENS_NR17_PADRAO,
  MATURIDADE_LABELS,
  MATURIDADE_COLORS,
  type ItemNR17,
  type ErgonomiaStatus,
  type ErgonomiaCategoria,
  type AcaoStatus,
  type RiscoSeveridade,
} from "@/types/ergonomia";
import type { NovoGRORisco, GROSeveridade, GROProbabilidade } from "@/types/gro";

// ── Ponte Ergonomia → GRO unificado ──────────────────────────────────────────
// O cadastro de risco da tela sempre foi "físico/ergonômico", então ele alimenta
// o inventário unificado gro_riscos (subtipo 'fisico'), que é o que o Inventário
// GRO, os cards de prioridade e as ações leem. Antes, o form gravava em
// ergonomia_riscos — tabela que a tela não exibe (ver docs/BLOQUEIOS_PRODUTO_QA_E2E.md,
// Bloqueio 1). As escalas diferem: a Ergonomia usa 4 níveis; o GRO usa 4 de
// severidade e 5 de probabilidade. O nivel_risco (criticidade) NÃO é enviado —
// o trigger calcular_nivel_gro_risco o calcula no banco.
const SEVERIDADE_ERGO_PARA_GRO: Record<RiscoSeveridade, GROSeveridade> = {
  baixo: "leve",
  medio: "moderada",
  alto: "grave",
  critico: "gravissima",
};
const PROBABILIDADE_ERGO_PARA_GRO: Record<RiscoSeveridade, GROProbabilidade> = {
  baixo: "baixa",
  medio: "moderada",
  alto: "alta",
  critico: "muito_alta",
};

// Observação de modelo: o GRO não tem campo para o "eixo" (físico/cognitivo/
// organizacional) nem para "impactos potenciais"; esses ficam fora do registro
// unificado (ERGO-012 — classificação por eixo — segue sem suporte no GRO).
function riscoFormParaGRO(data: {
  titulo: string;
  descricao?: string;
  severidade: RiscoSeveridade;
  probabilidade: RiscoSeveridade;
  fonte?: string;
  departamento?: string;
  setor?: string;
  medidas_existentes?: string[];
  medidas_recomendadas?: string[];
}): NovoGRORisco {
  return {
    subtipo: "fisico",
    fonte: "manual",
    titulo: data.titulo,
    descricao: data.descricao || undefined,
    perigo_identificado: data.fonte || undefined,
    setor: data.setor || undefined,
    unidade: data.departamento || undefined,
    probabilidade: PROBABILIDADE_ERGO_PARA_GRO[data.probabilidade],
    severidade: SEVERIDADE_ERGO_PARA_GRO[data.severidade],
    medidas_existentes: data.medidas_existentes?.length ? data.medidas_existentes : undefined,
    medidas_recomendadas: data.medidas_recomendadas?.length ? data.medidas_recomendadas : undefined,
    base_normativa: ["NR-01", "NR-17"],
  };
}

const CATEGORIAS_ORDENADAS: ErgonomiaCategoria[] = [
  "organizacao_trabalho",
  "mobiliario",
  "equipamentos",
  "condicoes_ambientais",
  "levantamento_cargas",
  "aet",
];

export default function Ergonomia() {
  const [selectedItem, setSelectedItem] = useState<ItemNR17 | null>(null);
  const [isDetailOpen, setIsDetailOpen] = useState(false);
  const [showRiscoForm, setShowRiscoForm] = useState(false);
  const [showAcaoForm, setShowAcaoForm] = useState(false);
  const [showStatusGRO, setShowStatusGRO] = useState(false);
  const [statusEixo, setStatusEixo] = useState<"todos" | "fisico" | "cognitivo" | "organizacional">("todos");
  const [aepMode, setAepMode] = useState<"simples" | "multi">("simples");
  const [showGuiaRapido, setShowGuiaRapido] = useState(false);

  const { riscos: groRiscos, criarRisco: criarRiscoGRO } = useGRORiscos();

  const {
    itensNR17,
    acoes,
    itensPorCategoria,
    estatisticas,
    percentualConformidade,
    nivelMaturidade,
    isLoadingItens,
    isLoadingAcoes,
    initializeItens,
    updateItemStatus,
    createAcao,
    updateAcaoStatus,
    isInitializing,
    isUpdatingStatus,
    isCreatingAcao,
    refetchItens,
  } = useErgonomia();

  const { analises, isLoading: isLoadingAnalises, stats, mapaRiscos, arquivarAnalise } =
    useErgonomiaAnalises();

  const handleViewItem = (item: ItemNR17) => {
    setSelectedItem(item);
    setIsDetailOpen(true);
  };

  const handleUpdateStatus = async (id: string, status: ErgonomiaStatus) => {
    await updateItemStatus({ id, status });
  };

  const handleSaveItem = async (id: string, status: ErgonomiaStatus, observacoes?: string) => {
    await updateItemStatus({ id, status, observacoes });
  };

  const handleInitialize = async () => {
    await initializeItens(ITENS_NR17_PADRAO);
  };

  const handleUpdateAcaoStatus = async (id: string, status: AcaoStatus) => {
    await updateAcaoStatus({ id, status });
  };

  const openStatusGRO = (eixo?: "todos" | "fisico" | "cognitivo" | "organizacional") => {
    setStatusEixo(eixo || "todos");
    setShowStatusGRO(true);
  };

  if (isLoadingItens) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <Skeleton className="h-10 w-64" />
          <Skeleton className="h-10 w-32" />
        </div>
        <div className="grid grid-cols-4 gap-4">
          {[1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-24" />)}
        </div>
        <Skeleton className="h-64" />
      </div>
    );
  }

  const categoriasEixo: Record<string, ErgonomiaCategoria[]> = {
    todos: CATEGORIAS_ORDENADAS,
    fisico: ["mobiliario", "equipamentos", "levantamento_cargas", "condicoes_ambientais"],
    cognitivo: ["aet"],
    organizacional: ["organizacao_trabalho"],
  };

  const riscosCriticosAltos = groRiscos.filter(r => ["alto", "critico"].includes(r.nivel_risco));
  const acoesPendentes = acoes.filter(a => a.status === "pendente");

  return (
    <div className="space-y-6">
      {/* ── Header ── */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="flex flex-col md:flex-row md:items-center justify-between gap-4"
      >
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <ShieldCheck className="h-7 w-7 text-primary" />
            Gestão de Risco Ergonômico
          </h1>
          <p className="text-muted-foreground mt-0.5 text-sm">
            Fluxo GRO · NR-1 · NR-17 · ISO 45003 — Identificação, avaliação, controle e monitoramento de riscos
          </p>
          <p className="text-muted-foreground mt-1 text-sm">
            Aqui você acompanha e organiza os riscos ergonômicos, define ações e monitora a evolução para manter o trabalho seguro e saudável.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <Button id="btn-ergo-guia-rapido" variant="outline" size="sm" onClick={() => setShowGuiaRapido(true)} className="gap-2 text-primary border-primary/30 hover:bg-primary/5">
            <HelpCircle className="h-4 w-4" />
            Guia Rápido
          </Button>
          <Button id="btn-ergo-atualizar" variant="outline" size="sm" onClick={() => refetchItens()}>
            <RefreshCw className="h-4 w-4 mr-2" />
            Atualizar
          </Button>
          <Button id="btn-ergo-novo-risco" variant="outline" size="sm" onClick={() => setShowRiscoForm(true)}>
            <AlertTriangle className="h-4 w-4 mr-2" />
            Novo Risco
          </Button>
          <Button id="btn-ergo-nova-acao" size="sm" onClick={() => setShowAcaoForm(true)}>
            <Plus className="h-4 w-4 mr-2" />
            Nova Ação
          </Button>
        </div>
      </motion.div>

      {/* ── KPIs do Fluxo GRO ── */}
      <motion.div
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.05 }}
        className="grid grid-cols-2 md:grid-cols-4 gap-3"
      >
        {/* Status GRO Ergonômico */}
        <Card
          className="border-border/50 cursor-pointer hover:shadow-md transition-all group col-span-2 md:col-span-2"
          onClick={() => openStatusGRO("todos")}
        >
          <CardContent className="py-3 px-4">
            <div className="flex items-center justify-between gap-4">
              <div className="flex items-center gap-3 min-w-0 flex-1">
                <div className="p-2 rounded-lg bg-primary/10 shrink-0">
                  <ShieldCheck className="h-4 w-4 text-primary" />
                </div>
                <div className="min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-semibold text-sm text-foreground">Status GRO Ergonômico</span>
                    <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${MATURIDADE_COLORS[nivelMaturidade]}`}>
                      {MATURIDADE_LABELS[nivelMaturidade]}
                    </span>
                  </div>
                  <div className="flex items-center gap-3 mt-1.5">
                    <Progress value={percentualConformidade} className="h-1.5 w-28 md:w-44" />
                    <span className="text-xs text-muted-foreground">{percentualConformidade}% conformidade NR-17</span>
                  </div>
                </div>
              </div>
              <div className="hidden md:flex items-center gap-4 text-sm shrink-0">
                <div className="text-center">
                  <p className="font-bold text-success">{estatisticas.atendidos}</p>
                  <p className="text-[11px] text-muted-foreground">Atendidos</p>
                </div>
                <div className="text-center">
                  <p className="font-bold text-warning">{estatisticas.parciais}</p>
                  <p className="text-[11px] text-muted-foreground">Parciais</p>
                </div>
                <div className="text-center">
                  <p className="font-bold text-destructive">{estatisticas.naoAtendidos}</p>
                  <p className="text-[11px] text-muted-foreground">Pendentes</p>
                </div>
              </div>
              <Button
                variant="ghost"
                size="sm"
                className="gap-1.5 text-primary shrink-0 group-hover:bg-primary/10"
                onClick={(e) => { e.stopPropagation(); openStatusGRO("todos"); }}
              >
                Ver <ChevronRight className="h-4 w-4" />
              </Button>
            </div>
          </CardContent>
        </Card>

        {/* Riscos Prioritários */}
        <Card className={`border-border/50 ${riscosCriticosAltos.length > 0 ? "border-destructive/30 bg-destructive/5" : ""}`}>
          <CardContent className="py-3 px-4">
            <div className="flex items-center gap-2 mb-1">
              <AlertTriangle className={`h-4 w-4 ${riscosCriticosAltos.length > 0 ? "text-destructive" : "text-muted-foreground"}`} />
              <span className="text-xs text-muted-foreground">Riscos Prioritários</span>
            </div>
            <p className={`text-2xl font-bold ${riscosCriticosAltos.length > 0 ? "text-destructive" : ""}`}>
              {riscosCriticosAltos.length}
            </p>
            <p className="text-xs text-muted-foreground">críticos + altos</p>
          </CardContent>
        </Card>

        {/* Ações Pendentes */}
        <Card className={`border-border/50 ${acoesPendentes.length > 0 ? "border-warning/30 bg-warning/5" : ""}`}>
          <CardContent className="py-3 px-4">
            <div className="flex items-center gap-2 mb-1">
              <Wrench className={`h-4 w-4 ${acoesPendentes.length > 0 ? "text-warning" : "text-muted-foreground"}`} />
              <span className="text-xs text-muted-foreground">Ações Pendentes</span>
            </div>
            <p className={`text-2xl font-bold ${acoesPendentes.length > 0 ? "text-warning" : ""}`}>
              {acoesPendentes.length}
            </p>
            <p className="text-xs text-muted-foreground">no plano de ação</p>
          </CardContent>
        </Card>
      </motion.div>

      {/* ── Indicadores da Base Ergonômica ── */}
      {stats.totalAnalises > 0 && (
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.08 }}
        >
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <Card className="border-border/50">
              <CardContent className="py-3 px-4">
                <div className="flex items-center gap-2 mb-1">
                  <Database className="h-4 w-4 text-primary" />
                  <span className="text-xs text-muted-foreground">Análises Realizadas</span>
                </div>
                <p className="text-2xl font-bold">{stats.totalAnalises}</p>
              </CardContent>
            </Card>
            <Card className="border-border/50">
              <CardContent className="py-3 px-4">
                <div className="flex items-center gap-2 mb-1">
                  <Building2 className="h-4 w-4 text-primary" />
                  <span className="text-xs text-muted-foreground">Postos Avaliados</span>
                </div>
                <p className="text-2xl font-bold">{stats.postosAvaliados}</p>
              </CardContent>
            </Card>
            <Card className="border-border/50">
              <CardContent className="py-3 px-4">
                <div className="flex items-center gap-2 mb-1">
                  <AlertTriangle className="h-4 w-4 text-destructive" />
                  <span className="text-xs text-muted-foreground">Riscos Identificados</span>
                </div>
                <p className="text-2xl font-bold text-destructive">{stats.totalRiscosIdentificados}</p>
              </CardContent>
            </Card>
            <Card className="border-border/50">
              <CardContent className="py-3 px-4">
                <div className="flex items-center gap-2 mb-1">
                  <BarChart3 className="h-4 w-4 text-primary" />
                  <span className="text-xs text-muted-foreground">Conformidade Média</span>
                </div>
                <p className="text-2xl font-bold">{stats.conformidadeMedia}%</p>
              </CardContent>
            </Card>
          </div>
        </motion.div>
      )}

      {itensNR17.length === 0 ? (
        <EmptyState onInitialize={handleInitialize} isInitializing={isInitializing} />
      ) : (
        <>
          {/* ── Tabs — Fluxo GRO ── */}
          <Tabs defaultValue="aep" className="space-y-4">
            {/* Barra de navegação com fluxo de etapas */}
            <div className="space-y-1">
              <p className="text-xs text-muted-foreground px-1 font-medium uppercase tracking-wide">
                Fluxo GRO — Ciclo de Gestão de Risco
              </p>
              <TabsList className="flex-wrap h-auto gap-1">
                {/* 1. Entrada */}
                <TabsTrigger id="tab-ergo-aep" value="aep" className="gap-2">
                  <Search className="h-4 w-4" />
                  <span className="hidden sm:inline">1.</span> Avaliar Riscos (AEP)
                </TabsTrigger>

                {/* 2. Identificação + Avaliação → Inventário GRO */}
                <TabsTrigger id="tab-ergo-inventario" value="inventario_gro" className="gap-2">
                  <ListChecks className="h-4 w-4" />
                  <span className="hidden sm:inline">2.</span> Inventário GRO
                  {groRiscos.length > 0 && (
                    <Badge variant="secondary" className="h-5 px-1.5 text-[10px]">{groRiscos.length}</Badge>
                  )}
                </TabsTrigger>

                {/* 3. Riscos Prioritários */}
                <TabsTrigger id="tab-ergo-prioritarios" value="prioritarios" className="gap-2">
                  <AlertTriangle className="h-4 w-4" />
                  <span className="hidden sm:inline">3.</span> Riscos Prioritários
                  {riscosCriticosAltos.length > 0 && (
                    <Badge variant="destructive" className="h-5 px-1.5 text-[10px]">{riscosCriticosAltos.length}</Badge>
                  )}
                </TabsTrigger>

                {/* 4. Plano de Ação */}
                <TabsTrigger id="tab-ergo-acoes" value="acoes" className="gap-2">
                  <Wrench className="h-4 w-4" />
                  <span className="hidden sm:inline">4.</span> Plano de Ação
                  {acoes.length > 0 && (
                    <Badge variant="secondary" className="h-5 px-1.5 text-[10px]">{acoes.length}</Badge>
                  )}
                </TabsTrigger>

                {/* 5. Monitoramento */}
                <TabsTrigger id="tab-ergo-monitoramento" value="monitoramento" className="gap-2">
                  <Eye className="h-4 w-4" />
                  <span className="hidden sm:inline">5.</span> Monitoramento
                  {stats.totalAnalises > 0 && (
                    <Badge variant="secondary" className="h-5 px-1.5 text-[10px]">{stats.totalAnalises}</Badge>
                  )}
                </TabsTrigger>

                {/* Suporte */}
                <TabsTrigger id="tab-ergo-analise-ia" value="analise_ia" className="gap-2">
                  <Brain className="h-4 w-4" />
                  Análise por IA
                </TabsTrigger>
                <TabsTrigger id="tab-ergo-base" value="base_ergonomica" className="gap-2">
                  <Database className="h-4 w-4" />
                  Base Ergonômica
                  {stats.totalAnalises > 0 && (
                    <Badge variant="secondary" className="h-5 px-1.5 text-[10px]">{stats.totalAnalises}</Badge>
                  )}
                </TabsTrigger>
              </TabsList>
            </div>

            {/* ① Avaliar Riscos — AEP (ponto de entrada principal) */}
            <TabsContent value="aep" className="space-y-4">
              <div className="flex items-center gap-4 mb-4 p-4 bg-muted/50 rounded-lg">
                <div>
                  <p className="text-sm font-medium text-foreground">Análise Ergonômica Preliminar (AEP)</p>
                  <p className="text-xs text-muted-foreground">Ponto de entrada: identifique perigos e gere riscos automaticamente para o inventário GRO</p>
                </div>
                <div className="flex gap-2 ml-auto shrink-0">
                  <Button
                    variant={aepMode === "simples" ? "default" : "outline"}
                    size="sm"
                    onClick={() => setAepMode("simples")}
                  >
                    <FileText className="h-4 w-4 mr-2" />
                    Função Única
                  </Button>
                  <Button
                    variant={aepMode === "multi" ? "default" : "outline"}
                    size="sm"
                    onClick={() => setAepMode("multi")}
                  >
                    <Building2 className="h-4 w-4 mr-2" />
                    Multi-Setor
                  </Button>
                </div>
              </div>
              {aepMode === "simples" ? <AEPGenerator /> : <AEPGeneratorMulti />}
            </TabsContent>

            {/* ② Inventário GRO — Identificação + Avaliação unificados */}
            <TabsContent value="inventario_gro">
              <GROPainel onNovo={() => setShowRiscoForm(true)} />
            </TabsContent>

            {/* ③ Riscos Prioritários — Críticos e Altos que exigem ação */}
            <TabsContent value="prioritarios">
              <InventarioRiscos analises={analises} />
            </TabsContent>

            {/* ④ Plano de Ação */}
            <TabsContent value="acoes" className="space-y-4">
              {isLoadingAcoes ? (
                <div className="space-y-4">{[1, 2, 3].map((i) => <Skeleton key={i} className="h-32" />)}</div>
              ) : (
                <AcoesList acoes={acoes} onUpdateStatus={handleUpdateAcaoStatus} />
              )}
            </TabsContent>

            {/* ⑤ Monitoramento — evolução + mapa visual */}
            <TabsContent value="monitoramento" className="space-y-4">
              <MapaRiscoErgonomico mapaRiscos={mapaRiscos} />
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
                <DocumentoMetodologia riscos={groRiscos} />
                <ComunicacaoTrabalhadores riscos={groRiscos} />
              </div>
            </TabsContent>

            {/* Suporte: Análise por IA */}
            <TabsContent value="analise_ia">
              <AnaliseIASection />
            </TabsContent>

            {/* Suporte: Base Ergonômica */}
            <TabsContent value="base_ergonomica">
              <RegistrosErgonomicos
                analises={analises}
                onArquivar={arquivarAnalise}
              />
            </TabsContent>
          </Tabs>
        </>
      )}

      {/* ══ Sheet: Status GRO (itens NR-17) ══ */}
      <Sheet open={showStatusGRO} onOpenChange={setShowStatusGRO}>
        <SheetContent side="right" className="w-full sm:max-w-2xl flex flex-col p-0">
          <SheetHeader className="px-6 pt-6 pb-4 border-b shrink-0">
            <SheetTitle className="flex items-center gap-2">
              <ShieldCheck className="h-5 w-5 text-primary" />
              Status GRO Ergonômico
            </SheetTitle>
            <SheetDescription>
              Itens normativos NR-17 avaliados — {percentualConformidade}% de conformidade
            </SheetDescription>
            <Tabs
              value={statusEixo}
              onValueChange={(v) => setStatusEixo(v as typeof statusEixo)}
              className="mt-3"
            >
              <TabsList className="w-full">
                <TabsTrigger value="todos" className="flex-1 gap-1.5 text-xs">
                  <Activity className="h-3.5 w-3.5" /> Todos
                </TabsTrigger>
                <TabsTrigger value="fisico" className="flex-1 gap-1.5 text-xs">
                  <Dumbbell className="h-3.5 w-3.5" /> Físico
                </TabsTrigger>
                <TabsTrigger value="cognitivo" className="flex-1 gap-1.5 text-xs">
                  <Brain className="h-3.5 w-3.5" /> Cognitivo
                </TabsTrigger>
                <TabsTrigger value="organizacional" className="flex-1 gap-1.5 text-xs">
                  <Building2 className="h-3.5 w-3.5" /> Organizacional
                </TabsTrigger>
              </TabsList>
            </Tabs>
          </SheetHeader>

          <div className="flex-1 overflow-y-auto px-6 py-4 space-y-4">
            {categoriasEixo[statusEixo].map((categoria) => {
              const itens = itensPorCategoria[categoria] || [];
              if (itens.length === 0) return null;
              return (
                <CategoriaCard
                  key={categoria}
                  categoria={categoria}
                  itens={itens}
                  onUpdateStatus={handleUpdateStatus}
                  onViewItem={handleViewItem}
                />
              );
            })}
          </div>
        </SheetContent>
      </Sheet>

      {/* Modais */}
      <ItemDetailModal
        item={selectedItem}
        open={isDetailOpen}
        onOpenChange={setIsDetailOpen}
        onSave={handleSaveItem}
      />
      <RiscoForm
        open={showRiscoForm}
        onOpenChange={setShowRiscoForm}
        onSubmit={async (data) => {
          // Grava no inventário unificado (gro_riscos), que é o que a tela exibe.
          await criarRiscoGRO.mutateAsync(riscoFormParaGRO(data));
          setShowRiscoForm(false);
        }}
        isLoading={criarRiscoGRO.isPending}
      />
      <AcaoForm
        open={showAcaoForm}
        onOpenChange={setShowAcaoForm}
        onSubmit={async (data) => {
          await createAcao(data);
          setShowAcaoForm(false);
        }}
        isLoading={isCreatingAcao}
      />

      <GuiaRapidoErgonomia open={showGuiaRapido} onOpenChange={setShowGuiaRapido} />
    </div>
  );
}
