import { useState, useRef, useCallback, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import {
  ArrowLeft, Shield, Database, Server, LayoutGrid, Zap,
  AlertTriangle, CheckCircle, Info, ChevronDown, ChevronUp,
  Loader2, Bug, Activity, Play, Bot, Clock, CheckCircle2,
  XCircle, AlertCircle, FileText,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  Collapsible, CollapsibleContent, CollapsibleTrigger,
} from "@/components/ui/collapsible";
import { supabase } from "@/integrations/supabase/client";
import { getSupabaseFunctionUrl } from "@/lib/supabaseFunctions";
import { toast } from "sonner";
import ReactMarkdown from "react-markdown";
import { useAuthContext } from "@/contexts/AuthContext";

// ═══════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════

interface Finding {
  categoria: string;
  severidade: "critico" | "alto" | "medio" | "baixo" | "info";
  titulo: string;
  descricao: string;
  sugestao: string;
  modulo: string;
}

interface ScanResult {
  success: boolean;
  categoria: string;
  timestamp: string;
  total_findings: number;
  criticos: number;
  altos: number;
  medios: number;
  baixos: number;
  info: number;
  findings: Finding[];
  ai_summary: string;
}

interface StepResult {
  step: string;
  action: string;
  status: "success" | "fail" | "warning";
  details: string;
  duration_ms: number;
}

interface FlowResult {
  flow: string;
  flow_label: string;
  steps: StepResult[];
  passed: number;
  failed: number;
  warnings: number;
  total_duration_ms: number;
}

interface AgentResult {
  success: boolean;
  timestamp: string;
  total_flows: number;
  total_steps: number;
  total_passed: number;
  total_failed: number;
  score: number;
  flows: FlowResult[];
  ai_report: string;
}

interface LiveStep {
  flow: string;
  step: string;
  action: string;
  status: "running" | "success" | "fail" | "warning";
  details?: string;
  duration_ms?: number;
}

interface LiveFlow {
  flow: string;
  label: string;
  status: "running" | "done";
  steps: LiveStep[];
}

// ═══════════════════════════════════════════════════
// ROUTE MAPPING — which page to show for each flow
// ═══════════════════════════════════════════════════

const FLOW_ROUTES: Record<string, string> = {
  login_auth: "/",
  empresa: "/empresa",
  departamentos: "/cadastros/departamentos",
  cargos: "/cadastros/cargos",
  filiais: "/cadastros/filiais",
  terceiros: "/terceiros",
  marketplace: "/marketplace",
  admissao: "/colaboradores",
  onboarding: "/onboarding-rh",
  ferias: "/ferias",
  atestado: "/atestados",
  ocorrencias: "/feedback-ocorrencias",
  ouvidoria: "/ouvidoria",
  ponto: "/ponto",
  trilhas: "/trilhas",
  cultura: "/cultura-celebracoes",
  bem_estar: "/felicidade",
  avaliacoes: "/avaliacoes",
  pdi: "/pdi",
  epi: "/epis",
  compliance_sst: "/compliance-sst",
  incidentes: "/incidentes-acidentes",
  ergonomia: "/ergonomia",
  psicossocial: "/psicossocial",
  estrategia_swot: "/estrategia",
  plano_acao: "/plano-acao",
  documentos: "/documentos",
  beneficios: "/financeiro/beneficios",
  hub_contabil: "/hub-contabil",
  financeiro: "/financeiro",
  rls_isolamento: "/",
  edge_functions: "/",
};

// ═══════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════

const SCAN_CATEGORIES = [
  { id: "dados", label: "Dados & Integridade", icon: Database, description: "Verifica integridade referencial, perfis órfãos, dados incompletos.", color: "text-blue-500", bgColor: "bg-blue-900/10 hover:bg-blue-900/20 border-blue-900/20" },
  { id: "seguranca", label: "Segurança & RLS", icon: Shield, description: "Testa acesso anônimo, políticas RLS, distribuição de roles.", color: "text-red-500", bgColor: "bg-red-900/10 hover:bg-red-900/20 border-red-900/20" },
  { id: "edge_functions", label: "Edge Functions", icon: Server, description: "Testa disponibilidade de todas as edge functions.", color: "text-purple-500", bgColor: "bg-purple-900/10 hover:bg-purple-900/20 border-purple-900/20" },
  { id: "modulos", label: "Módulos do Sistema", icon: LayoutGrid, description: "Verifica campanhas, estoque EPIs, afastamentos, ASOs.", color: "text-amber-500", bgColor: "bg-amber-900/10 hover:bg-amber-900/20 border-amber-900/20" },
  { id: "todos", label: "Varredura Completa", icon: Zap, description: "Executa TODAS as verificações.", color: "text-emerald-500", bgColor: "bg-emerald-900/10 hover:bg-emerald-900/20 border-emerald-900/20" },
];

interface AgentFlow {
  id: string;
  label: string;
  icon: string;
  description: string;
  steps: number;
  category: string;
}

const AGENT_FLOW_CATEGORIES = [
  { id: "infra", label: "🔧 Infraestrutura & Auth" },
  { id: "estrutura", label: "🏢 Estrutura Organizacional" },
  { id: "pessoas", label: "👥 PESSOAS" },
  { id: "sst", label: "🛡️ Saúde & Segurança" },
  { id: "estrategia", label: "📊 Estratégia & Planos" },
  { id: "docs_fin", label: "📁 Documentos & Financeiro" },
];

const AGENT_FLOWS: AgentFlow[] = [
  // Infraestrutura
  { id: "login_auth", label: "Autenticação & Perfil", icon: "🔑", description: "Login, perfil, roles e sessão.", steps: 5, category: "infra" },
  { id: "rls_isolamento", label: "Isolamento RLS", icon: "🔒", description: "Anônimo, cross-tenant, integridade.", steps: 4, category: "infra" },
  { id: "edge_functions", label: "Health Check Functions", icon: "⚡", description: "Pinga edge functions.", steps: 11, category: "infra" },

  // Estrutura Organizacional
  { id: "empresa", label: "Cadastro de Empresa", icon: "🏢", description: "Empresa, departamento, cargo.", steps: 7, category: "estrutura" },
  { id: "departamentos", label: "Departamentos", icon: "🏗️", description: "CRUD departamentos e validação.", steps: 4, category: "estrutura" },
  { id: "cargos", label: "Funções / Cargos", icon: "💼", description: "CRUD cargos com faixa salarial.", steps: 4, category: "estrutura" },
  { id: "filiais", label: "Estabelecimentos / Obras", icon: "🏭", description: "Unidades e filiais.", steps: 3, category: "estrutura" },
  { id: "terceiros", label: "Terceiros & SST", icon: "👷", description: "Terceiros, documentos, trabalhadores.", steps: 5, category: "estrutura" },
  { id: "marketplace", label: "MarketYE", icon: "🏪", description: "Marketplace de serviços: especialistas, anúncios e leads.", steps: 3, category: "estrutura" },

  // Pessoas & Cultura
  { id: "admissao", label: "Admissão Completa", icon: "👤", description: "Admissão com dados e documentos.", steps: 8, category: "pessoas" },
  { id: "onboarding", label: "Onboarding", icon: "🎓", description: "Templates e processos.", steps: 4, category: "pessoas" },
  { id: "ferias", label: "Férias", icon: "🏖️", description: "Solicitação e aprovação.", steps: 4, category: "pessoas" },
  { id: "atestado", label: "Atestado Médico", icon: "🏥", description: "Assistencial e ocupacional.", steps: 4, category: "pessoas" },
  { id: "ocorrencias", label: "Feedback & Ocorrências", icon: "⚠️", description: "Cria ocorrência, atualiza status.", steps: 3, category: "pessoas" },
  { id: "ouvidoria", label: "Ouvidoria", icon: "📢", description: "Canal de denúncias e sugestões.", steps: 3, category: "pessoas" },
  { id: "ponto", label: "Ponto Eletrônico", icon: "⏰", description: "Marcações, escalas, banco de horas.", steps: 5, category: "pessoas" },
  { id: "trilhas", label: "Trilhas de Aprendizado", icon: "🛤️", description: "Trilhas, módulos, progresso.", steps: 5, category: "pessoas" },
  { id: "cultura", label: "Cultura & Celebrações", icon: "🎉", description: "Aniversários, datas, ações.", steps: 3, category: "pessoas" },
  { id: "bem_estar", label: "Bem-Estar", icon: "💚", description: "Pesquisas e indicadores.", steps: 3, category: "pessoas" },
  { id: "avaliacoes", label: "Avaliações", icon: "⭐", description: "Templates, ciclos, 9Box.", steps: 5, category: "pessoas" },
  { id: "pdi", label: "PDI", icon: "🎯", description: "Planos de desenvolvimento.", steps: 4, category: "pessoas" },

  // Saúde & Segurança
  { id: "epi", label: "EPI — Fluxo Completo", icon: "🦺", description: "Tipo → EPI → Local → Entrada → Entrega → Devolução.", steps: 14, category: "sst" },
  { id: "compliance_sst", label: "Compliance SST", icon: "📋", description: "Documentos SST, PCMSO, PGR.", steps: 4, category: "sst" },
  { id: "incidentes", label: "Incidentes & Acidentes", icon: "🚨", description: "Registro e investigação.", steps: 4, category: "sst" },
  { id: "ergonomia", label: "Ergonomia", icon: "🪑", description: "Avaliações ergonômicas.", steps: 3, category: "sst" },
  { id: "psicossocial", label: "Psicossocial NR-01", icon: "🧠", description: "Questionários e IPS.", steps: 4, category: "sst" },

  // Estratégia & Planos
  { id: "estrategia_swot", label: "Estratégia SWOT", icon: "📊", description: "CRUD completo, 4 quadrantes, XSS, IDOR.", steps: 14, category: "estrategia" },
  { id: "plano_acao", label: "Plano de Ação", icon: "📋", description: "Ação com tarefas e trigger.", steps: 5, category: "estrategia" },

  // Documentos & Financeiro
  { id: "documentos", label: "Gestão de Documentos", icon: "📁", description: "Pastas e documentos.", steps: 3, category: "docs_fin" },
  { id: "beneficios", label: "Benefícios", icon: "🎁", description: "Tipos e atribuições.", steps: 4, category: "docs_fin" },
  { id: "hub_contabil", label: "Hub Contábil", icon: "📊", description: "Competências e checklists.", steps: 3, category: "docs_fin" },
  { id: "financeiro", label: "Financeiro", icon: "💰", description: "Certidões e guias.", steps: 3, category: "docs_fin" },
];

const severityConfig = {
  critico: { icon: AlertTriangle, color: "text-red-600", bg: "bg-red-500 text-red-100 border-red-200", label: "Crítico" },
  alto: { icon: AlertTriangle, color: "text-orange-500", bg: "bg-orange-700 text-orange-100 border-orange-200", label: "Alto" },
  medio: { icon: Info, color: "text-amber-500", bg: "bg-amber-700 text-amber-100 border-amber-200", label: "Médio" },
  baixo: { icon: Info, color: "text-blue-500", bg: "bg-blue-700 text-blue-100 border-blue-200", label: "Baixo" },
  info: { icon: CheckCircle, color: "text-emerald-500", bg: "bg-emerald-700 text-emerald-100 border-emerald-200", label: "Info" },
};

// ═══════════════════════════════════════════════════
// COMPONENT
// ═══════════════════════════════════════════════════

export default function QADashboard() {
  const navigate = useNavigate();
  const { profile } = useAuthContext();

  // Scan state
  const [scanning, setScanning] = useState<string | null>(null);
  const [scanResult, setScanResult] = useState<ScanResult | null>(null);
  const [expandedFindings, setExpandedFindings] = useState<Set<number>>(new Set());

  // Agent state
  const [agentRunning, setAgentRunning] = useState<string | null>(null);
  const [agentResult, setAgentResult] = useState<AgentResult | null>(null);
  const [expandedFlows, setExpandedFlows] = useState<Set<string>>(new Set());

  // Live streaming state
  const [liveFlows, setLiveFlows] = useState<LiveFlow[]>([]);
  const [liveMessage, setLiveMessage] = useState<string>("");
  const [isGeneratingReport, setIsGeneratingReport] = useState(false);
  const liveContainerRef = useRef<HTMLDivElement>(null);

   // Flow label state
  const [currentFlowLabel, setCurrentFlowLabel] = useState("");

  // ── Scan handlers ──
  const runScan = async (categoria: string) => {
    setScanning(categoria);
    setScanResult(null);
    setExpandedFindings(new Set());
    try {
      const { data, error } = await supabase.functions.invoke("ai-qa-scan", { body: { categoria } });
      if (error) throw error;
      setScanResult(data as ScanResult);
      if (data.criticos > 0) toast.error(`Varredura: ${data.criticos} problemas críticos`);
      else if (data.altos > 0) toast.warning(`Varredura: ${data.altos} problemas altos`);
      else toast.success("Varredura concluída sem problemas críticos");
    } catch (e: any) {
      toast.error(e.message || "Erro ao executar varredura");
    } finally {
      setScanning(null);
    }
  };

  // ── Navigate stub (iframe removed) ──
  const navigateIframe = useCallback((_flowId: string) => {}, []);

  // ── Agent handlers (streaming) ──
  const runAgent = async (flow: string) => {
    setAgentRunning(flow);
    setAgentResult(null);
    setExpandedFlows(new Set());
    setLiveFlows([]);
    setLiveMessage("Conectando ao agente...");
    setIsGeneratingReport(false);
    setCurrentFlowLabel("");

    // Navigate iframe to dashboard first
    navigateIframe("login_auth");

    try {
      const { data: { session } } = await supabase.auth.getSession();
      const token = session?.access_token;
      const url = getSupabaseFunctionUrl("ai-qa-agent");

      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
          apikey: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || "",
        },
        body: JSON.stringify({ flow, tenantId: profile?.tenant_id, stream: true }),
      });

      if (!response.ok) {
        const text = await response.text();
        throw new Error(text || `HTTP ${response.status}`);
      }

      const reader = response.body?.getReader();
      if (!reader) throw new Error("Stream não disponível");

      const decoder = new TextDecoder();
      let buffer = "";

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() || "";

        let currentEvent = "";
        for (const line of lines) {
          if (line.startsWith("event: ")) {
            currentEvent = line.slice(7).trim();
          } else if (line.startsWith("data: ") && currentEvent) {
            try {
              const data = JSON.parse(line.slice(6));
              handleSSEEvent(currentEvent, data);
            } catch { /* skip bad json */ }
            currentEvent = "";
          }
        }
      }
    } catch (e: any) {
      toast.error(e.message || "Erro ao executar agente");
      setLiveMessage("");
    } finally {
      setAgentRunning(null);
      setLiveMessage("");
      setIsGeneratingReport(false);
    }
  };

  const handleSSEEvent = useCallback((event: string, data: any) => {
    switch (event) {
      case "flow_start":
        setLiveFlows(prev => [...prev, {
          flow: data.flow,
          label: data.label,
          status: "running",
          steps: [],
        }]);
        setLiveMessage(`▶ ${data.label}`);
        setCurrentFlowLabel(data.label);
        // Navigate iframe to matching page
        navigateIframe(data.flow);
        break;

      case "step_start":
        setLiveFlows(prev => prev.map(f =>
          f.flow === data.flow
            ? {
              ...f,
              steps: [...f.steps, {
                flow: data.flow,
                step: data.step,
                action: data.action,
                status: "running" as const,
              }],
            }
            : f
        ));
        setLiveMessage(`⏳ ${data.step}`);
        break;

      case "step_done":
        setLiveFlows(prev => prev.map(f =>
          f.flow === data.flow
            ? {
              ...f,
              steps: f.steps.map(s =>
                s.step === data.step
                  ? { ...s, status: data.status, details: data.details, duration_ms: data.duration_ms }
                  : s
              ),
            }
            : f
        ));
        setLiveMessage(
          data.status === "success"
            ? `✅ ${data.step}`
            : `❌ ${data.step}`
        );
        break;

      case "navigate":
        if (data.label) setCurrentFlowLabel(data.label);
        break;

      case "refresh":
        break;

      case "flow_done":
        setLiveFlows(prev => prev.map(f =>
          f.flow === data.flow ? { ...f, status: "done" } : f
        ));
        break;

      case "ai_start":
        setIsGeneratingReport(true);
        setLiveMessage("🤖 Gerando relatório com IA...");
        setCurrentFlowLabel("Relatório IA");
        navigateIframe("login_auth");
        break;

      case "complete":
        setAgentResult(data as AgentResult);
        setExpandedFlows(new Set(data.flows?.map((f: FlowResult) => f.flow) || []));
        if (data.total_failed > 0) toast.error(`Agente: ${data.total_failed} testes falharam`);
        else toast.success(`Agente: todos os ${data.total_passed} testes passaram ✓`);
        break;
    }

    // Auto-scroll log
    setTimeout(() => {
      liveContainerRef.current?.scrollTo({
        top: liveContainerRef.current.scrollHeight,
        behavior: "smooth",
      });
    }, 50);
  }, [navigateIframe]);

  const toggleFinding = (i: number) => setExpandedFindings(p => { const n = new Set(p); n.has(i) ? n.delete(i) : n.add(i); return n; });
  const toggleFlow = (f: string) => setExpandedFlows(p => { const n = new Set(p); n.has(f) ? n.delete(f) : n.add(f); return n; });

  const healthScore = scanResult ? Math.max(0, 100 - (scanResult.criticos * 20 + scanResult.altos * 10 + scanResult.medios * 5 + scanResult.baixos * 2)) : null;

  const isAgentActive = agentRunning !== null || (liveFlows.length > 0 && !agentResult);

  return (
    <div className="min-h-screen bg-gray-900 text-white p-4 md:p-6">
      <div className="max-w-[1600px] mx-auto space-y-4">
        {/* Header */}
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" onClick={() => navigate("/admin")}>            <ArrowLeft className="w-5 h-5" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
              <Bug className="w-7 h-7 text-primary" />
              QA & Testes com IA
            </h1>
            <p className="text-muted-foreground text-sm">
              Agente de testes automatizados + varredura de integridade
            </p>
          </div>
          <Button variant="default" size="sm" className="ml-auto" onClick={() => navigate("/admin/qa/runner")}>
            <Play className="w-4 h-4 mr-2" />
            Executar testes
          </Button>
          <Button variant="outline" size="sm" className="bg-background text-foreground" onClick={() => navigate("/admin/qa/docs")}>
            <FileText className="w-4 h-4 mr-2" />
            Documentação de testes
          </Button>
        </div>

        {/* Tabs — a aba do agente antigo (que escrevia em cliente real via
            OpenAI) foi retirada da interface. Testes agora sao pelo runner
            novo, no botao 'Executar testes' do topo. So a Varredura fica. */}
        <Tabs defaultValue="scan" className="space-y-4">
          <TabsList className="grid w-full max-w-xs grid-cols-1">
            <TabsTrigger value="scan" className="gap-2">
              <Database className="w-4 h-4" /> Varredura de integridade
            </TabsTrigger>
          </TabsList>

          {/* ═══════════════════════════════════════════ */}
          {/* TAB: AGENTE VISUAL */}
          {/* ═══════════════════════════════════════════ */}
          <TabsContent value="agent" className="space-y-4">
            {/* Flow selection grid — compact when running */}
            {!isAgentActive && !agentResult && (
              <>
                <Card className="border-primary/20 bg-primary/5">
                  <CardContent className="p-3 flex items-start gap-3">
                    <Bot className="w-5 h-5 text-primary mt-0.5 shrink-0" />
                    <div>
                      <p className="font-semibold text-sm">Agente de Testes Automatizado</p>
                      <p className="text-xs text-muted-foreground mt-1">
                        O agente autentica como <code className="bg-muted px-1 rounded text-[10px]">wallasmonteirobarros@gmail.com</code>,
                        executa testes reais no banco e exibe os logs em tempo real.
                      </p>
                    </div>
                  </CardContent>
                </Card>

                {/* Executar TODOS — prominent button */}
                <Card
                  className="cursor-pointer transition-all border border-primary/30 bg-primary/5 hover:shadow-md hover:border-primary/50"
                  onClick={() => runAgent("todos")}
                >
                  <CardContent className="p-3 flex items-center justify-center gap-3">
                    <span className="text-2xl">🚀</span>
                    <div>
                      <div className="flex items-center gap-1.5">
                        <h3 className="font-semibold text-sm">Executar TODOS os Módulos</h3>
                        <Badge variant="secondary" className="text-[9px] px-1 py-0">
                          {AGENT_FLOWS.reduce((a, f) => a + f.steps, 0)}
                        </Badge>
                      </div>
                      <p className="text-[10px] text-muted-foreground">Todos os {AGENT_FLOWS.length} fluxos + relatório IA.</p>
                    </div>
                  </CardContent>
                </Card>

                {/* Grouped by category */}
                {AGENT_FLOW_CATEGORIES.map((cat) => {
                  const flows = AGENT_FLOWS.filter((f) => f.category === cat.id);
                  if (flows.length === 0) return null;
                  return (
                    <div key={cat.id}>
                      <h3 className="text-xs font-semibold text-muted-foreground mb-1.5 mt-3">{cat.label}</h3>
                      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-2">
                        {flows.map((f) => (
                          <Card
                            key={f.id}
                            className="cursor-pointer transition-all border hover:shadow-md hover:border-primary/40"
                            onClick={() => runAgent(f.id)}
                          >
                            <CardContent className="p-2.5">
                              <div className="flex items-start gap-2">
                                <span className="text-lg">{f.icon}</span>
                                <div className="flex-1 min-w-0">
                                  <div className="flex items-center gap-1.5">
                                    <h3 className="font-semibold text-[11px] leading-tight">{f.label}</h3>
                                    <Badge variant="secondary" className="text-[9px] px-1 py-0 shrink-0">{f.steps}</Badge>
                                  </div>
                                  <p className="text-[10px] text-muted-foreground mt-0.5 line-clamp-1">{f.description}</p>
                                </div>
                              </div>
                            </CardContent>
                          </Card>
                        ))}
                      </div>
                    </div>
                  );
                })}
              </>
            )}

            {/* ═══ LIVE LOG ═══ */}
            {isAgentActive && (
              <Card className="overflow-hidden border-muted">
                <CardHeader className="py-2 px-3 bg-muted/30">
                  <div className="flex items-center gap-2">
                    <Activity className="w-4 h-4 text-primary animate-pulse" />
                    <span className="text-xs font-medium">Log de Execução</span>
                    {agentRunning && (
                      <div className="flex items-center gap-1 ml-2">
                        <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse" />
                        <span className="text-[10px] text-red-500 font-medium">EXECUTANDO</span>
                      </div>
                    )}
                    {liveMessage && (
                      <span className="text-[10px] text-muted-foreground truncate max-w-[300px] ml-auto">
                        {liveMessage}
                      </span>
                    )}
                  </div>
                </CardHeader>
                <div
                  ref={liveContainerRef}
                  className="h-[500px] overflow-y-auto p-3 space-y-1 bg-card"
                >
                  {liveFlows.map((liveFlow) => (
                    <div key={liveFlow.flow} className="mb-3">
                      <div className="flex items-center gap-2 font-semibold text-xs mb-1.5 text-primary">
                        {liveFlow.status === "running" ? (
                          <Loader2 className="w-3 h-3 animate-spin" />
                        ) : (
                          <CheckCircle2 className="w-3 h-3 text-emerald-600" />
                        )}
                        <span>{liveFlow.label}</span>
                      </div>
                      {liveFlow.steps.map((step, i) => (
                        <div key={i} className="flex items-start gap-2 pl-4 py-0.5">
                          {step.status === "running" ? (
                            <Loader2 className="w-3 h-3 animate-spin text-primary mt-0.5 shrink-0" />
                          ) : step.status === "success" ? (
                            <CheckCircle2 className="w-3 h-3 text-emerald-600 mt-0.5 shrink-0" />
                          ) : step.status === "fail" ? (
                            <XCircle className="w-3 h-3 text-destructive mt-0.5 shrink-0" />
                          ) : (
                            <AlertCircle className="w-3 h-3 text-amber-500 mt-0.5 shrink-0" />
                          )}
                          <div className="flex-1 min-w-0">
                            <span className="text-[11px] font-medium text-foreground">{step.step}</span>
                            {step.duration_ms !== undefined && (
                              <span className="text-[9px] text-muted-foreground ml-1">{step.duration_ms}ms</span>
                            )}
                            {step.details && (
                              <div className={`text-[9px] mt-0 leading-tight ${
                                step.status === "fail" ? "text-destructive" : "text-muted-foreground"
                              }`}>
                                {step.details.slice(0, 150)}
                              </div>
                            )}
                          </div>
                        </div>
                      ))}
                    </div>
                  ))}
                  {isGeneratingReport && (
                    <div className="flex items-center gap-2 text-primary pt-2">
                      <Loader2 className="w-3 h-3 animate-spin" />
                      <span className="text-xs">Gerando relatório com IA...</span>
                    </div>
                  )}
                </div>
              </Card>
            )}

            {/* Agent Results */}
            {agentResult && (
              <div className="space-y-4">
                {/* Score header */}
                <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
                  <Card className={`col-span-2 md:col-span-1 ${agentResult.score >= 80 ? "border-emerald-300 bg-emerald-50 dark:bg-emerald-950/30" : agentResult.score >= 50 ? "border-amber-300 bg-amber-50 dark:bg-amber-950/30" : "border-red-300 bg-red-50 dark:bg-red-950/30"}`}>
                    <CardContent className="p-4 text-center">
                      <Activity className={`w-6 h-6 mx-auto ${agentResult.score >= 80 ? "text-emerald-600" : agentResult.score >= 50 ? "text-amber-600" : "text-red-600"}`} />
                      <p className={`text-3xl font-bold mt-1 ${agentResult.score >= 80 ? "text-emerald-700 dark:text-emerald-400" : agentResult.score >= 50 ? "text-amber-700 dark:text-amber-400" : "text-red-700 dark:text-red-400"}`}>
                        {agentResult.score}%
                      </p>
                      <p className="text-[10px] text-muted-foreground">Score</p>
                    </CardContent>
                  </Card>
                  <Card>
                    <CardContent className="p-4 text-center">
                      <p className="text-2xl font-bold text-foreground">{agentResult.total_flows}</p>
                      <p className="text-[10px] text-muted-foreground">Fluxos</p>
                    </CardContent>
                  </Card>
                  <Card>
                    <CardContent className="p-4 text-center">
                      <p className="text-2xl font-bold text-foreground">{agentResult.total_steps}</p>
                      <p className="text-[10px] text-muted-foreground">Steps</p>
                    </CardContent>
                  </Card>
                  <Card>
                    <CardContent className="p-4 text-center">
                      <p className="text-2xl font-bold text-emerald-600">{agentResult.total_passed}</p>
                      <p className="text-[10px] text-muted-foreground">Passou</p>
                    </CardContent>
                  </Card>
                  <Card>
                    <CardContent className="p-4 text-center">
                      <p className="text-2xl font-bold text-destructive">{agentResult.total_failed}</p>
                      <p className="text-[10px] text-muted-foreground">Falhou</p>
                    </CardContent>
                  </Card>
                </div>

                {/* Rerun button */}
                <div className="flex justify-end">
                  <Button variant="outline" size="sm" onClick={() => { setAgentResult(null); setLiveFlows([]); }}>
                    <Play className="w-3 h-3 mr-1" /> Executar Novamente
                  </Button>
                </div>

                {/* Flow details */}
                {agentResult.flows.map((flow) => {
                  const isExpanded = expandedFlows.has(flow.flow);
                  const allPassed = flow.failed === 0;
                  return (
                    <Card key={flow.flow} className={`border ${allPassed ? "border-emerald-200" : "border-red-200"}`}>
                      <Collapsible open={isExpanded} onOpenChange={() => toggleFlow(flow.flow)}>
                        <CollapsibleTrigger asChild>
                          <CardHeader className="cursor-pointer hover:bg-muted/30 transition-colors pb-3">
                            <div className="flex items-center justify-between">
                              <div className="flex items-center gap-3">
                                {allPassed ? (
                                  <CheckCircle2 className="w-5 h-5 text-emerald-600" />
                                ) : (
                                  <XCircle className="w-5 h-5 text-destructive" />
                                )}
                                <div>
                                  <CardTitle className="text-sm">{flow.flow_label}</CardTitle>
                                  <div className="flex items-center gap-2 mt-1">
                                    <Badge variant={allPassed ? "default" : "destructive"} className="text-[10px]">
                                      {flow.passed}/{flow.steps.length} passou
                                    </Badge>
                                    <span className="text-[10px] text-muted-foreground flex items-center gap-1">
                                      <Clock className="w-3 h-3" /> {flow.total_duration_ms}ms
                                    </span>
                                  </div>
                                </div>
                              </div>
                              {isExpanded ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
                            </div>
                          </CardHeader>
                        </CollapsibleTrigger>
                        <CollapsibleContent>
                          <CardContent className="pt-0">
                            <div className="space-y-2">
                              {flow.steps.map((step, i) => (
                                <div key={i} className={`flex items-start gap-3 p-3 rounded-lg ${
                                  step.status === "success" ? "bg-emerald-50/50 dark:bg-emerald-950/20" : step.status === "fail" ? "bg-red-50/50 dark:bg-red-950/20" : "bg-amber-50/50 dark:bg-amber-950/20"
                                }`}>
                                  {step.status === "success" ? (
                                    <CheckCircle2 className="w-4 h-4 text-emerald-600 mt-0.5 shrink-0" />
                                  ) : step.status === "fail" ? (
                                    <XCircle className="w-4 h-4 text-destructive mt-0.5 shrink-0" />
                                  ) : (
                                    <AlertCircle className="w-4 h-4 text-amber-600 mt-0.5 shrink-0" />
                                  )}
                                  <div className="flex-1 min-w-0">
                                    <div className="flex items-center gap-2 flex-wrap">
                                      <span className="font-medium text-sm">{step.step}</span>
                                      <code className="text-[10px] bg-muted px-1.5 py-0.5 rounded">{step.action}</code>
                                      <span className="text-[10px] text-muted-foreground">{step.duration_ms}ms</span>
                                    </div>
                                    <p className={`text-xs mt-0.5 ${step.status === "fail" ? "text-destructive" : "text-muted-foreground"}`}>
                                      {step.details}
                                    </p>
                                  </div>
                                </div>
                              ))}
                            </div>
                          </CardContent>
                        </CollapsibleContent>
                      </Collapsible>
                    </Card>
                  );
                })}

                {/* AI Report */}
                {agentResult.ai_report && (
                  <Card className="border-primary/30 bg-primary/5">
                    <CardHeader className="pb-2">
                      <CardTitle className="text-sm flex items-center gap-2">
                        <Bot className="w-4 h-4 text-primary" />
                        Relatório do Agente (IA)
                      </CardTitle>
                    </CardHeader>
                    <CardContent>
                      <div className="prose prose-sm max-w-none text-foreground">
                        <ReactMarkdown>{agentResult.ai_report}</ReactMarkdown>
                      </div>
                    </CardContent>
                  </Card>
                )}
              </div>
            )}
          </TabsContent>

          {/* ═══════════════════════════════════════════ */}
          {/* TAB: VARREDURA */}
          {/* ═══════════════════════════════════════════ */}
          <TabsContent value="scan" className="space-y-6">
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {SCAN_CATEGORIES.map((cat) => {
                const Icon = cat.icon;
                const isScanning = scanning === cat.id;
                const isAnyScanning = scanning !== null;
                return (
                  <Card
                    key={cat.id}
                    className={`cursor-pointer transition-all border-2 ${cat.bgColor} ${isAnyScanning && !isScanning ? "opacity-50" : ""}`}
                    onClick={() => !isAnyScanning && runScan(cat.id)}
                  >
                    <CardContent className="p-5">
                      <div className="flex items-start gap-3">
                        <div className={`p-3 rounded-xl bg-background/80 ${cat.color}`}>
                          {isScanning ? <Loader2 className="w-6 h-6 animate-spin" /> : <Icon className="w-6 h-6" />}
                        </div>
                        <div className="flex-1">
                          <h3 className="font-semibold text-foreground">{cat.label}</h3>
                          <p className="text-xs text-muted-foreground mt-1 leading-relaxed">{cat.description}</p>
                          {isScanning && <p className="text-xs text-primary mt-2 font-medium animate-pulse">Executando...</p>}
                        </div>
                      </div>
                    </CardContent>
                  </Card>
                );
              })}
            </div>

            {/* Scan Results */}
            {scanResult && (
              <div className="space-y-4">
                <div className="grid grid-cols-2 md:grid-cols-6 gap-3">
                  {healthScore !== null && (
                    <Card className="col-span-2 md:col-span-1">
                      <CardContent className="p-4 text-center">
                        <Activity className={`w-6 h-6 mx-auto ${healthScore >= 80 ? "text-emerald-500" : healthScore >= 50 ? "text-amber-500" : "text-red-500"}`} />
                        <p className={`text-2xl font-bold mt-1 ${healthScore >= 80 ? "text-emerald-600" : healthScore >= 50 ? "text-amber-600" : "text-red-600"}`}>{healthScore}</p>
                        <p className="text-[10px] text-muted-foreground">Saúde</p>
                      </CardContent>
                    </Card>
                  )}
                  <Card><CardContent className="p-4 text-center"><p className="text-2xl font-bold text-red-600">{scanResult.criticos}</p><p className="text-[10px] text-muted-foreground">Críticos</p></CardContent></Card>
                  <Card><CardContent className="p-4 text-center"><p className="text-2xl font-bold text-orange-500">{scanResult.altos}</p><p className="text-[10px] text-muted-foreground">Altos</p></CardContent></Card>
                  <Card><CardContent className="p-4 text-center"><p className="text-2xl font-bold text-amber-500">{scanResult.medios}</p><p className="text-[10px] text-muted-foreground">Médios</p></CardContent></Card>
                  <Card><CardContent className="p-4 text-center"><p className="text-2xl font-bold text-blue-500">{scanResult.baixos}</p><p className="text-[10px] text-muted-foreground">Baixos</p></CardContent></Card>
                  <Card><CardContent className="p-4 text-center"><p className="text-2xl font-bold text-emerald-500">{scanResult.info}</p><p className="text-[10px] text-muted-foreground">Info</p></CardContent></Card>
                </div>

                {scanResult.ai_summary && (
                  <Card className="border-primary/30 bg-primary/5">
                    <CardHeader className="pb-2">
                      <CardTitle className="text-sm flex items-center gap-2"><Zap className="w-4 h-4 text-primary" /> Análise da IA</CardTitle>
                    </CardHeader>
                    <CardContent>
                      <div className="prose prose-sm max-w-none text-foreground">
                        <ReactMarkdown>{scanResult.ai_summary}</ReactMarkdown>
                      </div>
                    </CardContent>
                  </Card>
                )}

                <Card>
                  <CardHeader>
                    <CardTitle className="text-sm">
                      {scanResult.total_findings} findings
                      <span className="text-muted-foreground font-normal ml-2">{new Date(scanResult.timestamp).toLocaleString("pt-BR")}</span>
                    </CardTitle>
                  </CardHeader>
                  <CardContent className="space-y-2">
                    {scanResult.findings
                      .sort((a, b) => {
                        const order: Record<string, number> = { critico: 0, alto: 1, medio: 2, baixo: 3, info: 4 };
                        return (order[a.severidade] ?? 4) - (order[b.severidade] ?? 4);
                      })
                      .map((finding, i) => {
                        const config = severityConfig[finding.severidade];
                        const SevIcon = config.icon;
                        const isExpanded = expandedFindings.has(i);
                        return (
                          <Collapsible key={i} open={isExpanded} onOpenChange={() => toggleFinding(i)}>
                            <CollapsibleTrigger asChild>
                              <div className="flex items-center gap-3 p-3 rounded-lg hover:bg-muted/50 cursor-pointer transition-colors">
                                <SevIcon className={`w-4 h-4 shrink-0 ${config.color}`} />
                                <div className="flex-1 min-w-0">
                                  <div className="flex items-center gap-2 flex-wrap">
                                    <span className="font-medium text-sm">{finding.titulo}</span>
                                    <Badge variant="outline" className={`text-[10px] ${config.bg}`}>{config.label}</Badge>
                                    <Badge variant="secondary" className="text-[10px]">{finding.modulo}</Badge>
                                  </div>
                                </div>
                                {finding.sugestao && (isExpanded ? <ChevronUp className="w-4 h-4 text-muted-foreground" /> : <ChevronDown className="w-4 h-4 text-muted-foreground" />)}
                              </div>
                            </CollapsibleTrigger>
                            {finding.sugestao && (
                              <CollapsibleContent>
                                <div className="ml-7 pl-4 pb-3 border-l-2 border-muted space-y-1">
                                  <p className="text-sm text-muted-foreground">{finding.descricao}</p>
                                  <p className="text-sm text-primary font-medium">💡 {finding.sugestao}</p>
                                </div>
                              </CollapsibleContent>
                            )}
                          </Collapsible>
                        );
                      })}
                  </CardContent>
                </Card>
              </div>
            )}
          </TabsContent>
        </Tabs>
      </div>
    </div>
  );
}

