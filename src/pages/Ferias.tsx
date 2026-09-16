import { useState, useMemo } from "react";
import { motion } from "framer-motion";
import { FeriasCalendario } from "@/components/ferias/FeriasCalendario";
import { FeriasSaldos } from "@/components/ferias/FeriasSaldos";
import { FeriasFinanceiro } from "@/components/ferias/FeriasFinanceiro";
import { FeriasProgramacao } from "@/components/ferias/FeriasProgramacao";
import { FeriasInteligencia } from "@/components/ferias/FeriasInteligencia";
import { FeriasEvidenciaNR1 } from "@/components/ferias/FeriasEvidenciaNR1";
import { FeriasVinculoFamiliar } from "@/components/ferias/FeriasVinculoFamiliar";
import { useFeriasFinanceiro } from "@/hooks/useFeriasFinanceiro";
import { FeriasCultura } from "@/components/ferias/FeriasCultura";
import { FeriasRelatorios } from "@/components/ferias/FeriasRelatorios";
import { FeriasGovernanca } from "@/components/ferias/FeriasGovernanca";
import { FeriasAlertas } from "@/components/ferias/FeriasAlertas";
import { FeriasColetivas } from "@/components/ferias/FeriasColetivas";
import { useINR } from "@/hooks/useINR";
import { useFerias, type FeriasSolicitacao } from "@/hooks/useFerias";
import { calcularPeriodoFerias } from "@/lib/feriasPeriodo";
import {
  Calendar, Plus, Filter, CheckCircle, XCircle, Clock, Sun, Plane,
  ChevronsUpDown, Check, DollarSign, Info, Banknote, AlertTriangle,
  FileText, Send, TrendingUp, Brain, Heart, BarChart3, ShieldCheck, Wallet, CalendarRange, CalendarClock,
  Loader2, MessageSquare, PenLine,
} from "lucide-react";
import { useFeed } from "@/hooks/useFeed";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command";
import { Switch } from "@/components/ui/switch";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";
import { toast } from "sonner";
import { useColaboradores } from "@/hooks/useColaboradores";
import { useFinanceiro } from "@/hooks/useFinanceiro";
import { useAuth } from "@/hooks/useAuth";
import { validarFracionamentoCLT } from "@/lib/feriasPeriodo";
import { gerarAvisoFeriasPDF, gerarReciboFeriasPDF, gerarReciboFeriasHTML, gerarAvisoFeriasHTML } from "@/lib/feriasDocumentos";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useEnviarParaHub } from "@/hooks/useEnviarParaHub";

// ========== Adapter types for legacy components ==========
interface FeriasItemLegacy {
  id: number;
  colaborador: string;
  departamento: string;
  dataInicio: string;
  dataFim: string;
  diasSolicitados: number;
  saldoDias: number;
  status: "pendente" | "aprovado" | "recusado";
  dataSolicitacao: string;
  abonoPecuniario: boolean;
  diasAbono: number;
  salarioBase?: number;
}

function toLegacy(s: FeriasSolicitacao): FeriasItemLegacy {
  return {
    id: s.id as any,
    colaborador: s.colaborador_nome,
    departamento: s.departamento || "N/A",
    dataInicio: s.data_inicio,
    dataFim: s.data_fim,
    diasSolicitados: s.dias_solicitados,
    saldoDias: s.saldo_dias,
    status: (s.status === "em_gozo" || s.status === "concluido" ? "aprovado" : s.status === "cancelado" ? "recusado" : s.status) as any,
    dataSolicitacao: s.created_at?.split("T")[0] || "",
    abonoPecuniario: s.abono_pecuniario,
    diasAbono: s.dias_abono,
    salarioBase: s.salario_base,
  };
}

const statusConfig = {
  pendente: { label: "Pendente", icon: Clock, style: "bg-warning/10 text-warning border-warning/20" },
  aprovado: { label: "Aprovado", icon: CheckCircle, style: "bg-success/10 text-success border-success/20" },
  em_gozo: { label: "Em Gozo", icon: Plane, style: "bg-info/10 text-info border-info/20" },
  concluido: { label: "Concluído", icon: CheckCircle, style: "bg-primary/10 text-primary border-primary/20" },
  recusado: { label: "Recusado", icon: XCircle, style: "bg-destructive/10 text-destructive border-destructive/20" },
  cancelado: { label: "Cancelado", icon: XCircle, style: "bg-muted text-muted-foreground border-muted" },
};

interface FeriasCardProps {
  item: FeriasSolicitacao;
  index: number;
  onAprovar: (id: string) => void;
  onRecusar: (id: string) => void;
  onGerarAviso: (item: FeriasSolicitacao) => void;
  onGerarRecibo: (item: FeriasSolicitacao) => void;
  onGerarFinanceiro: (item: FeriasSolicitacao) => void;
  onLinkAssinatura: (item: FeriasSolicitacao) => void;
  onEnviarReciboAssinatura: (item: FeriasSolicitacao) => void;
  onVerReciboAssinado: (item: FeriasSolicitacao) => void;
  onPublicarFeed: (item: FeriasSolicitacao) => void;
  onIniciarGozo: (item: FeriasSolicitacao) => void;
  onRegistrarCiencia: (item: FeriasSolicitacao) => void;
}

const FeriasCard = ({ item, index, onAprovar, onRecusar, onGerarAviso, onGerarRecibo, onGerarFinanceiro, onLinkAssinatura, onEnviarReciboAssinatura, onVerReciboAssinado, onPublicarFeed, onIniciarGozo, onRegistrarCiencia }: FeriasCardProps) => {
  const config = statusConfig[item.status] || statusConfig.pendente;
  const startDate = new Date(item.data_inicio + "T12:00:00").toLocaleDateString("pt-BR");
  const endDate = new Date(item.data_fim + "T12:00:00").toLocaleDateString("pt-BR");

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, delay: 0.1 + index * 0.05 }}
      className="bg-card rounded-xl border border-border p-5 shadow-sm hover:shadow-md hover:border-primary/30 transition-all"
    >
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center gap-3">
          <Avatar className="h-10 w-10">
            <AvatarFallback className="bg-primary/10 text-primary font-semibold">
              {item.colaborador_nome.split(" ").map(n => n[0]).join("").slice(0, 2)}
            </AvatarFallback>
          </Avatar>
          <div>
            <h3 className="font-semibold text-foreground">{item.colaborador_nome}</h3>
            <p className="text-sm text-muted-foreground">{item.departamento}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {item.acao_preventiva && (
            <Tooltip>
              <TooltipTrigger>
                <Badge className="bg-info/10 text-info border-info/20 text-[10px]">INR™</Badge>
              </TooltipTrigger>
              <TooltipContent className="text-xs">Férias preventivas — geradas pelo INR™</TooltipContent>
            </Tooltip>
          )}
          <Badge className={cn("text-xs", config.style)}>
            <config.icon className="w-3 h-3 mr-1" />
            {config.label}
          </Badge>
        </div>
      </div>

      <div className="space-y-3">
        <div className="flex items-center gap-2 p-3 bg-muted/50 rounded-lg">
          <Calendar className="w-4 h-4 text-primary" />
          <div>
            <p className="text-sm font-medium">{startDate} - {endDate}</p>
            <p className="text-xs text-muted-foreground">{item.dias_solicitados} dias solicitados</p>
          </div>
        </div>

        {item.abono_pecuniario && (
          <div className="flex items-center gap-2 p-3 bg-success/5 border border-success/20 rounded-lg">
            <Banknote className="w-4 h-4 text-success" />
            <div>
              <p className="text-sm font-medium text-success">Abono Pecuniário</p>
              <p className="text-xs text-success/80">{item.dias_abono} dias vendidos</p>
            </div>
          </div>
        )}

        {item.valor_total_bruto && item.valor_total_bruto > 0 && (
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">Valor bruto:</span>
            <span className="font-medium text-foreground">
              R$ {Number(item.valor_total_bruto).toLocaleString("pt-BR", { minimumFractionDigits: 2 })}
            </span>
          </div>
        )}

        {item.inr_score_momento != null && (
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">INR™ no momento:</span>
            <Badge variant="outline" className={cn("text-[10px]",
              item.inr_nivel_momento === "critico" && "bg-destructive/10 text-destructive",
              item.inr_nivel_momento === "alto" && "bg-warning/10 text-warning",
              item.inr_nivel_momento === "moderado" && "bg-info/10 text-info",
              item.inr_nivel_momento === "baixo" && "bg-success/10 text-success",
            )}>
              {item.inr_score_momento}pts
            </Badge>
          </div>
        )}
      </div>

      {item.status === "pendente" && (
        <div className="mt-4 pt-4 border-t border-border flex gap-2">
          <Button size="sm" className="flex-1 gradient-primary" onClick={() => onAprovar(item.id)}>
            <CheckCircle className="w-4 h-4 mr-1" /> Aprovar
          </Button>
          <Button size="sm" variant="outline" className="flex-1" onClick={() => onRecusar(item.id)}>
            <XCircle className="w-4 h-4 mr-1" /> Recusar
          </Button>
        </div>
      )}

      {(item.status === "aprovado" || item.status === "em_gozo") && (
        <div className="mt-4 pt-4 border-t border-border space-y-2">
          <p className="text-xs font-medium text-muted-foreground mb-2">Ações pós-aprovação:</p>
          <div className="grid grid-cols-2 gap-2">
            <Button size="sm" variant="outline" className="text-xs" onClick={() => onGerarAviso(item)}
              disabled={item.aviso_gerado}>
              <FileText className="w-3.5 h-3.5 mr-1" />
              {item.aviso_gerado ? "✓ Aviso" : "Gerar Aviso"}
            </Button>
            <Button size="sm" variant="outline" className="text-xs" onClick={() => onGerarRecibo(item)}
              disabled={item.recibo_gerado}>
              <Banknote className="w-3.5 h-3.5 mr-1" />
              {item.recibo_gerado ? "✓ Recibo" : "Gerar Recibo"}
            </Button>
            <Button size="sm" variant="outline" className="text-xs" onClick={() => onGerarFinanceiro(item)}>
              <DollarSign className="w-3.5 h-3.5 mr-1" /> Reg. Financeiro
            </Button>
            <Button size="sm" variant="outline" className="text-xs" onClick={() => onLinkAssinatura(item)}>
              <Send className="w-3.5 h-3.5 mr-1" /> Aviso p/ Assinar
            </Button>
            <Button
              size="sm"
              variant="outline"
              className="text-xs col-span-2 border-primary/40 text-primary hover:bg-primary/5"
              onClick={() => onEnviarReciboAssinatura(item)}
            >
              <PenLine className="w-3.5 h-3.5 mr-1" /> Enviar Recibo p/ Assinatura
            </Button>
            {item.recibo_gerado && (
              <Button
                size="sm"
                variant="outline"
                className="text-xs col-span-2 border-success/40 text-success hover:bg-success/5"
                onClick={() => onVerReciboAssinado(item)}
              >
                <FileText className="w-3.5 h-3.5 mr-1" /> Ver Recibo Assinado
              </Button>
            )}
            {/* Ciencia do aviso + inicio do gozo (art. 135 / CA-005) */}
            {item.aviso_ciencia_em ? (
              <div className="col-span-2 text-xs text-success flex items-center gap-1.5">
                <CheckCircle className="w-3.5 h-3.5" /> Aviso com ciência
                {item.aviso_ciencia_origem === "papel" ? " (registrada em papel)" : ""}
              </div>
            ) : (
              <Button size="sm" variant="outline" className="text-xs col-span-2 text-muted-foreground"
                onClick={() => onRegistrarCiencia(item)}>
                <FileText className="w-3.5 h-3.5 mr-1" /> Registrar ciência (papel)
              </Button>
            )}
            {item.status === "aprovado" && (
              <Button size="sm" variant="outline"
                className="text-xs col-span-2 border-info/40 text-info hover:bg-info/5"
                onClick={() => onIniciarGozo(item)}>
                <Plane className="w-3.5 h-3.5 mr-1" /> Iniciar Gozo
              </Button>
            )}
            <Button size="sm" variant="outline" className="text-xs col-span-2 text-primary" onClick={() => onPublicarFeed(item)}>
              <MessageSquare className="w-3.5 h-3.5 mr-1" /> Publicar no Feed
            </Button>

          </div>
        </div>
      )}
    </motion.div>
  );
};

const Ferias = () => {
  const [statusFilter, setStatusFilter] = useState("all");
  const [activeTab, setActiveTab] = useState("programacao");
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [comboOpen, setComboOpen] = useState(false);
  const [newSolicitacao, setNewSolicitacao] = useState({
    colaborador: "", colaboradorCpf: "", colaboradorId: "", colaboradorEmpresaId: "", departamento: "", dataInicio: "", dataFim: "",
    periodoAquisitivoInicio: "", periodoAquisitivoFim: "",
    abonoPecuniario: false, diasAbono: 10, salarioBase: 0,
  });
  const [linkAssinaturaDialog, setLinkAssinaturaDialog] = useState<{ url: string; colaborador: string } | null>(null);

  // Férias é direito CLT — exclui PJ/Pró-labore/Terceiros.
  const { colaboradores, isLoading: loadingColabs } = useColaboradores({ excluirPJ: true });
  const { solicitacoes, isLoading: loadingFerias, criarSolicitacao, aprovar, recusar, iniciarGozo, registrarCienciaManual, atualizarCampo, stats } = useFerias();
  const { criarPeriodo, criarFolhaItem, useFolhaPeriodos } = useFinanceiro();
  const { data: periodos } = useFolhaPeriodos();
  const { tenantId, user, profile } = useAuth();
  const { enviarParaHub } = useEnviarParaHub();
  const { criarPost } = useFeed();

  // Legacy adapter for components that still need FeriasItemLegacy
  const feriasLegacy = useMemo(() => solicitacoes.map(toLegacy), [solicitacoes]);

  // ========== INR™ ==========
  const { ranking: inrRanking, criticos: inrCriticos, altos: inrAltos } = useINR(
    colaboradores, feriasLegacy, [], []
  );

  const colaboradoresPorSetor = useMemo(() => {
    const map: Record<string, { total: number; vencidos: number; alerta: number }> = {};
    colaboradores.forEach((c) => {
      const dept = c.departamento || "Sem Departamento";
      if (!map[dept]) map[dept] = { total: 0, vencidos: 0, alerta: 0 };
      map[dept].total++;
      const diasUsados = solicitacoes
        .filter((f) => f.colaborador_nome === c.nome_completo && ["aprovado", "em_gozo", "concluido"].includes(f.status))
        .reduce((sum, f) => sum + f.dias_solicitados, 0);
      const periodo = calcularPeriodoFerias(c.data_admissao || null, diasUsados);
      if (periodo?.statusVencimento === "vencido") map[dept].vencidos++;
      else if (periodo?.statusVencimento === "alerta") map[dept].alerta++;
    });
    return map;
  }, [colaboradores, solicitacoes]);

  const handleCriarAcaoPreventiva = (colab: any) => {
    toast.success(`Ação preventiva criada: "Antecipar férias — ${colab.nome}" no Plano de Ação`, { duration: 5000 });
  };

  // ========== PROVISÃO FINANCEIRA ==========
  // Provisão do card do topo vem do MESMO motor da aba Financeiro (Fase 2).
  // Antes era sal + sal/3 para todo colaborador, sem dias de direito e sem
  // encargos — divergia do valor da aba e superestimava o passivo.
  const { provisaoTotal } = useFeriasFinanceiro();

  // ========== SOBREPOSIÇÃO ==========
  const verificarSobreposicao = (item: FeriasSolicitacao): string[] => {
    const inicio = new Date(item.data_inicio);
    const fim = new Date(item.data_fim);
    return solicitacoes.filter(f =>
      f.id !== item.id && f.departamento === item.departamento &&
      ["aprovado", "em_gozo"].includes(f.status) &&
      new Date(f.data_inicio) <= fim && new Date(f.data_fim) >= inicio
    ).map(f => f.colaborador_nome);
  };

  const calcularVencimento2DiasUteis = (dataInicio: string): string => {
    const date = new Date(dataInicio + "T12:00:00");
    let diasUteis = 0;
    while (diasUteis < 2) { date.setDate(date.getDate() - 1); if (date.getDay() !== 0 && date.getDay() !== 6) diasUteis++; }
    return date.toISOString().split("T")[0];
  };

  // ========== APROVAR ==========
  const handleAprovar = async (id: string) => {
    const item = solicitacoes.find(f => f.id === id);
    if (!item) return;
    const sobrepostos = verificarSobreposicao(item);
    if (sobrepostos.length > 0) {
      toast.warning(`⚠ Sobreposição no setor "${item.departamento}": ${sobrepostos.join(", ")}`, { duration: 6000 });
    }
    aprovar.mutate(id);
  };

  // ========== PUBLICAR NO FEED ==========
  const handlePublicarFeed = (item: FeriasSolicitacao) => {
    const inicio = new Date(item.data_inicio + "T12:00:00").toLocaleDateString("pt-BR");
    const fim = new Date(item.data_fim + "T12:00:00").toLocaleDateString("pt-BR");
    const msg = `🏖️ Informamos que ${item.colaborador_nome} estará de férias no período de ${inicio} a ${fim} (${item.dias_solicitados} dias). Desejamos um ótimo descanso! 🌴`;
    criarPost.mutate({ conteudo: msg, tipo: "aviso" as any });
  };

  // Arquiva um documento HTML no modulo Documentos, na pasta do colaborador.
  // Reusa o padrao da casa (storage + tabela documentos). RF-003/CA-012: todo
  // aviso/recibo fica arquivado com empresa, colaborador e periodo.
  const arquivarEmDocumentos = async (
    item: FeriasSolicitacao, html: string, tipo: string, rotulo: string,
  ): Promise<string | null> => {
    const safeNome = item.colaborador_nome.replace(/[^a-zA-Z0-9._-]/g, "_");
    const storagePath = `${tenantId}/ferias/${tipo}_${item.id}_${Date.now()}_${safeNome}.html`;
    const blob = new Blob([html], { type: "text/html" });
    const { error: upErr } = await supabase.storage
      .from("documentos")
      .upload(storagePath, blob, { contentType: "text/html", upsert: false });
    if (upErr) throw upErr;

    let pastaId: string | null = null;
    if (item.colaborador_id) {
      const { data: pasta } = await fromTable("documento_pastas")
        .select("id").eq("tenant_id", tenantId).eq("colaborador_id", item.colaborador_id).maybeSingle();
      pastaId = (pasta as any)?.id || null;
    }

    const { data: docIns, error: insErr } = await fromTable("documentos").insert({
      tenant_id: tenantId,
      empresa_id: item.empresa_id || null,
      colaborador_id: item.colaborador_id || null,
      colaborador_nome: item.colaborador_nome,
      colaborador_cpf: item.colaborador_cpf || null,
      nome_arquivo: storagePath,
      nome_original: `${rotulo} - ${item.colaborador_nome}.html`,
      tipo: rotulo,
      tamanho: blob.size,
      mime_type: "text/html",
      storage_path: storagePath,
      status: "valido",
      observacoes: `Gerado do modulo Ferias (periodo ${item.data_inicio} a ${item.data_fim})`,
      pasta_id: pastaId,
      versao_atual: 1,
      total_versoes: 1,
    } as any).select("id").single();
    if (insErr) throw insErr;
    return (docIns as any)?.id || null;
  };

  // ========== GERAR AVISO PDF + ARQUIVAR ==========
  const handleGerarAviso = async (item: FeriasSolicitacao) => {
    if (!tenantId || !user) { toast.error("Usuário não autenticado"); return; }
    try {
      const docData = {
        colaboradorNome: item.colaborador_nome, colaboradorCpf: item.colaborador_cpf || undefined,
        departamento: item.departamento || "", dataInicio: item.data_inicio,
        dataFim: item.data_fim, diasSolicitados: item.dias_solicitados,
        abonoPecuniario: item.abono_pecuniario, diasAbono: item.dias_abono,
        salarioBase: item.salario_base || 0,
      };
      const avisoPdf = gerarAvisoFeriasPDF(docData);
      avisoPdf.save(`Aviso_Ferias_${item.colaborador_nome.replace(/\s/g, "_")}.pdf`);
      // Arquiva a versao (sem ciencia ainda) no modulo Documentos.
      await arquivarEmDocumentos(item, gerarAvisoFeriasHTML(docData), "aviso_ferias", "Aviso de Férias");
      atualizarCampo.mutate({ id: item.id, campo: "aviso_gerado", valor: true });
      toast.success("Aviso de Férias gerado e arquivado em Documentos!");
    } catch (err) { console.error(err); toast.error("Erro ao gerar/arquivar aviso de férias"); }
  };

  // ========== GERAR RECIBO PDF ==========
  const handleGerarRecibo = async (item: FeriasSolicitacao) => {
    if (!tenantId || !user) { toast.error("Usuário não autenticado"); return; }
    try {
      const docData = {
        colaboradorNome: item.colaborador_nome, colaboradorCpf: item.colaborador_cpf || undefined,
        departamento: item.departamento || "", dataInicio: item.data_inicio,
        dataFim: item.data_fim, diasSolicitados: item.dias_solicitados,
        abonoPecuniario: item.abono_pecuniario, diasAbono: item.dias_abono,
        salarioBase: item.salario_base || 0,
      };
      const reciboPdf = gerarReciboFeriasPDF(docData);
      reciboPdf.save(`Recibo_Ferias_${item.colaborador_nome.replace(/\s/g, "_")}.pdf`);
      await arquivarEmDocumentos(item, gerarReciboFeriasHTML(docData), "recibo_ferias", "Recibo de Férias");
      atualizarCampo.mutate({ id: item.id, campo: "recibo_gerado", valor: true });
      toast.success("Recibo de Férias gerado e arquivado em Documentos!");
    } catch (err) { console.error(err); toast.error("Erro ao gerar recibo de férias"); }
  };

  // ========== REGISTRO FINANCEIRO ==========
  const handleGerarFinanceiro = async (item: FeriasSolicitacao) => {
    if (!tenantId) return;
    try {
      const competencia = item.data_inicio.slice(0, 7);
      let periodoId: string | undefined;
      const periodoExistente = periodos?.find(p => p.competencia === competencia);
      if (periodoExistente) { periodoId = periodoExistente.id; }
      else {
        const novoPeriodo = await criarPeriodo({ competencia, observacoes: "Criado automaticamente - férias" });
        periodoId = (novoPeriodo as any)?.id;
      }
      if (!periodoId) return;
      const vencimento = calcularVencimento2DiasUteis(item.data_inicio);
      await criarFolhaItem({
        periodo_id: periodoId, colaborador_id: item.id, colaborador_nome: item.colaborador_nome,
        colaborador_cpf: item.colaborador_cpf, cargo: item.cargo, departamento: item.departamento,
        salario_base: item.salario_base, total_proventos: item.valor_total_bruto || 0,
        total_descontos: 0, total_liquido: item.valor_total_bruto || 0, status: "pendente",
        observacoes: `Férias ${item.dias_solicitados}d | Venc: ${new Date(vencimento + "T12:00:00").toLocaleDateString("pt-BR")}`,
      });
      atualizarCampo.mutate({ id: item.id, campo: "registro_financeiro_id", valor: periodoId });
      toast.success("Registro financeiro gerado!");
    } catch (err) { console.error(err); toast.error("Erro ao gerar registro financeiro"); }
  };

  // ========== AVISO PARA ASSINAR (coleta a ciencia — art. 135) ==========
  // Gera o HTML do AVISO, sobe ao storage e cria o link VINCULADO
  // (tipo_documento='aviso', ferias_solicitacao_id). Ao assinar, a edge
  // arquiva a versao assinada e a trigger do banco marca a ciencia — que
  // libera o inicio do gozo.
  const handleLinkAssinatura = async (item: FeriasSolicitacao) => {
    if (!tenantId) { toast.error("Tenant não encontrado"); return; }
    try {
      const docData = {
        colaboradorNome: item.colaborador_nome, colaboradorCpf: item.colaborador_cpf || undefined,
        departamento: item.departamento || "", dataInicio: item.data_inicio,
        dataFim: item.data_fim, diasSolicitados: item.dias_solicitados,
        abonoPecuniario: item.abono_pecuniario, diasAbono: item.dias_abono,
        salarioBase: item.salario_base || 0,
      };
      const safeNome = item.colaborador_nome.replace(/[^a-zA-Z0-9._-]/g, "_");
      const storagePath = `${tenantId}/ferias/aviso_${item.id}_${Date.now()}_${safeNome}.html`;
      const { error: upErr } = await supabase.storage
        .from("documentos")
        .upload(storagePath, new Blob([gerarAvisoFeriasHTML(docData)], { type: "text/html" }),
          { contentType: "text/html", upsert: false });
      if (upErr) throw upErr;

      const { data, error } = await fromTable("ferias_assinatura_links")
        .insert({
          tenant_id: tenantId,
          colaborador_id: item.colaborador_id,
          empresa_id: item.empresa_id || null,
          ferias_solicitacao_id: item.id,
          tipo_documento: "aviso",
          colaborador_nome: item.colaborador_nome,
          colaborador_cpf: item.colaborador_cpf,
          departamento: item.departamento, data_inicio_ferias: item.data_inicio,
          data_fim_ferias: item.data_fim, dias_ferias: item.dias_solicitados,
          abono_pecuniario: item.abono_pecuniario, dias_abono: item.dias_abono,
          salario_base: item.salario_base || 0, documento_storage_path: storagePath,
        } as any).select("token").single();
      if (error) throw error;
      const token = (data as any)?.token;
      if (token) {
        const url = `${window.location.origin}/ferias-assinatura/${token}`;
        setLinkAssinaturaDialog({ url, colaborador: item.colaborador_nome });
        atualizarCampo.mutate({ id: item.id, campo: "assinatura_link_id", valor: token });
      }
    } catch (err) { console.error(err); toast.error("Erro ao gerar link de assinatura do aviso"); }
  };
  // ========== ENVIAR RECIBO PARA ASSINATURA ==========
  const handleEnviarReciboAssinatura = async (item: FeriasSolicitacao) => {
    if (!tenantId || !user) { toast.error("Usuário não autenticado"); return; }
    try {
      // 1) Gera HTML do recibo
      const html = gerarReciboFeriasHTML({
        colaboradorNome: item.colaborador_nome,
        colaboradorCpf: item.colaborador_cpf || undefined,
        departamento: item.departamento || "",
        dataInicio: item.data_inicio,
        dataFim: item.data_fim,
        diasSolicitados: item.dias_solicitados,
        abonoPecuniario: item.abono_pecuniario,
        diasAbono: item.dias_abono,
        salarioBase: item.salario_base || 0,
      });

      // 2) Upload no storage
      const safeNome = item.colaborador_nome.replace(/[^a-zA-Z0-9._-]/g, "_");
      const storagePath = `${tenantId}/ferias/recibo_${item.id}_${Date.now()}_${safeNome}.html`;
      const { error: upErr } = await supabase.storage
        .from("documentos")
        .upload(storagePath, new Blob([html], { type: "text/html" }), {
          contentType: "text/html", upsert: false,
        });
      if (upErr) throw upErr;

      // 3) Cria link de assinatura
      const { data, error } = await fromTable("ferias_assinatura_links")
        .insert({
          tenant_id: tenantId,
          colaborador_id: item.colaborador_id,
          empresa_id: item.empresa_id || null,
          ferias_solicitacao_id: item.id,
          tipo_documento: "recibo",
          colaborador_nome: item.colaborador_nome,
          colaborador_cpf: item.colaborador_cpf,
          departamento: item.departamento,
          cargo: item.cargo,
          data_inicio_ferias: item.data_inicio,
          data_fim_ferias: item.data_fim,
          dias_ferias: item.dias_solicitados,
          abono_pecuniario: item.abono_pecuniario,
          dias_abono: item.dias_abono,
          salario_base: item.salario_base || 0,
          documento_storage_path: storagePath,
        } as any).select("token").single();
      if (error) throw error;
      const token = (data as any)?.token;
      if (token) {
        const url = `${window.location.origin}/ferias-assinatura/${token}`;
        setLinkAssinaturaDialog({ url, colaborador: item.colaborador_nome });
        atualizarCampo.mutate({ id: item.id, campo: "assinatura_link_id", valor: token });
        toast.success("Link de assinatura do recibo gerado!");
      }
    } catch (err) {
      console.error(err);
      toast.error("Erro ao enviar recibo para assinatura");
    }
  };

  // ========== VER RECIBO ASSINADO ==========
  const handleVerReciboAssinado = async (item: FeriasSolicitacao) => {
    try {
      const { data, error } = await fromTable("ferias_assinatura_links")
        .select("documento_storage_path,status")
        .eq("ferias_solicitacao_id", item.id)
        .eq("tipo_documento", "recibo")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      const path = (data as any)?.documento_storage_path;
      const status = (data as any)?.status;
      if (!path) { toast.error("Nenhum recibo encontrado para esta solicitação"); return; }
      if (status !== "assinado") {
        toast.info("O recibo ainda não foi assinado pelo colaborador");
      }
      // Recibos são HTML. Abrir a signed URL direto às vezes mostra o código-
      // fonte em vez de renderizar: o storage nem sempre devolve o header
      // Content-Type correto (objetos antigos, proxies), e o navegador cai em
      // text/plain. Buscamos o conteúdo e reabrimos como blob text/html local,
      // que renderiza sempre, independente do header do storage.
      const isHtml = path.toLowerCase().endsWith(".html");
      const { data: signed, error: signErr } = await supabase.storage
        .from("documentos").createSignedUrl(path, 3600);
      if (signErr) throw signErr;
      if (!signed?.signedUrl) { toast.error("Não foi possível gerar o link do recibo"); return; }

      if (isHtml) {
        const resp = await fetch(signed.signedUrl);
        const texto = await resp.text();
        const blobUrl = URL.createObjectURL(new Blob([texto], { type: "text/html;charset=utf-8" }));
        const win = window.open(blobUrl, "_blank");
        // Revoga após a aba carregar, sem cortar o carregamento.
        if (win) setTimeout(() => URL.revokeObjectURL(blobUrl), 60_000);
        else { URL.revokeObjectURL(blobUrl); toast.error("Permita pop-ups para visualizar o recibo."); }
      } else {
        window.open(signed.signedUrl, "_blank");
      }
    } catch (err) {
      console.error(err);
      toast.error("Erro ao abrir recibo assinado");
    }
  };

  // ========== NOVA SOLICITAÇÃO ==========
  const handleNovaSolicitacao = () => {
    if (!newSolicitacao.colaborador || !newSolicitacao.dataInicio || !newSolicitacao.dataFim) {
      toast.error("Preencha todos os campos obrigatórios"); return;
    }
    const dataInicio = new Date(newSolicitacao.dataInicio);
    const dataFim = new Date(newSolicitacao.dataFim);
    if (dataInicio > dataFim) {
      toast.error("A data de início não pode ser maior que a data fim."); return;
    }
    if (newSolicitacao.abonoPecuniario && newSolicitacao.diasAbono > 10) {
      toast.error("O abono pecuniário não pode exceder 10 dias (1/3 das férias)"); return;
    }
    const diasSolicitados = Math.ceil((dataFim.getTime() - dataInicio.getTime()) / (1000 * 60 * 60 * 24)) + 1;

    // Fracionamento por CPF, não por nome — homônimos não podem compartilhar o
    // limite de 3 períodos do art. 134. Fallback ao nome só quando não há CPF
    // (registros antigos), e ainda assim restrito ao mesmo período aquisitivo.
    const cpfAtual = (newSolicitacao.colaboradorCpf || "").replace(/\D/g, "");
    const fracionamentosAnteriores = solicitacoes
      .filter((f) => {
        if (f.status === "recusado" || f.status === "cancelado") return false;
        const cpfF = (f.colaborador_cpf || "").replace(/\D/g, "");
        if (cpfAtual && cpfF) return cpfF === cpfAtual;
        return f.colaborador_nome === newSolicitacao.colaborador;
      })
      .map((f) => f.dias_solicitados);
    const validacao = validarFracionamentoCLT(diasSolicitados, fracionamentosAnteriores);
    if (!validacao.valido) { toast.error(validacao.erro || "Fracionamento inválido"); return; }

    // Capture INR at creation
    const inrColab = inrRanking.find(r => r.nome === newSolicitacao.colaborador);

    criarSolicitacao.mutate({
      colaborador_nome: newSolicitacao.colaborador,
      colaborador_cpf: newSolicitacao.colaboradorCpf || null,
      colaborador_id: newSolicitacao.colaboradorId || null,
      empresa_id: newSolicitacao.colaboradorEmpresaId || null,
      departamento: newSolicitacao.departamento,
      data_inicio: newSolicitacao.dataInicio,
      data_fim: newSolicitacao.dataFim,
      dias_solicitados: diasSolicitados,
      abono_pecuniario: newSolicitacao.abonoPecuniario,
      dias_abono: newSolicitacao.abonoPecuniario ? newSolicitacao.diasAbono : 0,
      salario_base: newSolicitacao.salarioBase,
      periodo_aquisitivo_inicio: newSolicitacao.periodoAquisitivoInicio || null,
      periodo_aquisitivo_fim: newSolicitacao.periodoAquisitivoFim || null,
      inr_score_momento: inrColab?.score,
      inr_nivel_momento: inrColab?.nivel,
    });
    setNewSolicitacao({ colaborador: "", colaboradorCpf: "", colaboradorId: "", colaboradorEmpresaId: "", departamento: "", dataInicio: "", dataFim: "", periodoAquisitivoInicio: "", periodoAquisitivoFim: "", abonoPecuniario: false, diasAbono: 10, salarioBase: 0 });
    setIsModalOpen(false);
  };

  const filteredSolicitacoes = solicitacoes.filter(
    (f) => statusFilter === "all" || f.status === statusFilter
  );

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <motion.div initial={{ opacity: 0, y: -20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4 }}
        className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-foreground">Gestão de Férias</h1>
          <p className="text-muted-foreground text-sm">
            Ferramenta de organização do trabalho e recuperação humana
          </p>
        </div>
        <Button className="gradient-primary shadow-glow" onClick={() => setIsModalOpen(true)}>
          <Plus className="w-4 h-4 mr-2" /> Nova Solicitação
        </Button>
      </motion.div>

      {/* Stats */}
      <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4, delay: 0.1 }}
        className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-3">
        {[
          { label: "Pendentes", value: stats.pendentes, icon: Clock, color: "warning" },
          { label: "Aprovadas", value: stats.aprovados, icon: CheckCircle, color: "success" },
          { label: "Em Gozo", value: stats.emGozo, icon: Plane, color: "info" },
          { label: "Concluídas", value: stats.concluidos, icon: CheckCircle, color: "primary" },
          { label: "Com Abono", value: stats.comAbono, icon: Banknote, color: "primary" },
          { label: "Preventivas", value: stats.acoesPreventivas, icon: Brain, color: "info" },
          { label: "Provisão", value: provisaoTotal > 0
              ? (provisaoTotal >= 10000
                  ? `R$ ${(provisaoTotal / 1000).toFixed(0)}k`
                  : provisaoTotal.toLocaleString("pt-BR", { style: "currency", currency: "BRL", maximumFractionDigits: 0 }))
              : "—", icon: TrendingUp, color: "destructive" },
        ].map((s) => (
          <div key={s.label} className={cn(
            "rounded-xl border p-4 flex items-center gap-3",
            `bg-${s.color}/5 border-${s.color}/20`
          )}>
            <div className={cn("p-2 rounded-lg", `bg-${s.color}/10`)}>
              <s.icon className={cn("w-5 h-5", `text-${s.color}`)} />
            </div>
            <div>
              <p className="text-lg font-bold text-foreground">{s.value}</p>
              <p className="text-[11px] text-muted-foreground">{s.label}</p>
            </div>
          </div>
        ))}
      </motion.div>

      {/* Tabs */}
      <Tabs value={activeTab} onValueChange={setActiveTab} className="space-y-4">
        <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.15 }}
          className="flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
          <TabsList className="bg-muted/50 flex-wrap">
            <TabsTrigger value="programacao"><CalendarRange className="w-3.5 h-3.5 mr-1" /> Programação</TabsTrigger>
            <TabsTrigger value="solicitacoes">Solicitações</TabsTrigger>
            <TabsTrigger value="calendario">Calendário</TabsTrigger>
            <TabsTrigger value="saldos">Saldos</TabsTrigger>
            <TabsTrigger value="financeiro"><Wallet className="w-3.5 h-3.5 mr-1" /> Financeiro</TabsTrigger>
            <TabsTrigger value="inteligencia" className="flex items-center gap-1.5">
              <Brain className="w-3.5 h-3.5" /> INR™
              {inrCriticos.length > 0 && (
                <span className="ml-1 px-1.5 py-0.5 text-[10px] bg-destructive text-destructive-foreground rounded-full">
                  {inrCriticos.length}
                </span>
              )}
            </TabsTrigger>
            <TabsTrigger value="vencimentos"><CalendarClock className="w-3.5 h-3.5 mr-1" /> Vencimentos</TabsTrigger>
            <TabsTrigger value="coletivas"><CalendarRange className="w-3.5 h-3.5 mr-1" /> Coletivas</TabsTrigger>
            <TabsTrigger value="cultura"><Heart className="w-3.5 h-3.5 mr-1" /> Cultura</TabsTrigger>
            <TabsTrigger value="relatorios"><BarChart3 className="w-3.5 h-3.5 mr-1" /> Relatórios</TabsTrigger>
            <TabsTrigger value="governanca"><ShieldCheck className="w-3.5 h-3.5 mr-1" /> Governança</TabsTrigger>
          </TabsList>
          <Select value={statusFilter} onValueChange={setStatusFilter}>
            <SelectTrigger className="w-full md:w-[180px]">
              <SelectValue placeholder="Filtrar status" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Todos Status</SelectItem>
              <SelectItem value="pendente">Pendente</SelectItem>
              <SelectItem value="aprovado">Aprovado</SelectItem>
              <SelectItem value="em_gozo">Em Gozo</SelectItem>
              <SelectItem value="concluido">Concluído</SelectItem>
              <SelectItem value="recusado">Recusado</SelectItem>
            </SelectContent>
          </Select>
        </motion.div>

        <TabsContent value="programacao">
          <FeriasProgramacao />
        </TabsContent>

        <TabsContent value="solicitacoes" className="mt-0">
          {loadingFerias ? (
            <div className="bg-card rounded-xl border border-border p-10 text-center">
              <Loader2 className="w-6 h-6 animate-spin mx-auto text-primary mb-2" />
              <p className="text-sm text-muted-foreground">Carregando solicitações...</p>
            </div>
          ) : filteredSolicitacoes.length === 0 ? (
            <div className="bg-card rounded-xl border border-border p-10 text-center">
              <Sun className="w-8 h-8 text-muted-foreground/30 mx-auto mb-2" />
              <p className="text-sm text-muted-foreground">Nenhuma solicitação de férias encontrada.</p>
              <p className="text-xs text-muted-foreground mt-1">No YourEyes, férias não são ausência — são parte da organização do trabalho.</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
              {filteredSolicitacoes.map((item, index) => (
                <FeriasCard key={item.id} item={item} index={index}
                  onAprovar={handleAprovar} onRecusar={(id) => recusar.mutate({ id })}
                  onGerarAviso={handleGerarAviso} onGerarRecibo={handleGerarRecibo}
                  onGerarFinanceiro={handleGerarFinanceiro} onLinkAssinatura={handleLinkAssinatura}
                  onEnviarReciboAssinatura={handleEnviarReciboAssinatura}
                  onVerReciboAssinado={handleVerReciboAssinado}
                  onPublicarFeed={handlePublicarFeed}
                  onIniciarGozo={(it) => iniciarGozo.mutate(it.id)}
                  onRegistrarCiencia={(it) => registrarCienciaManual.mutate(it.id)}
                />

              ))}
            </div>
          )}
        </TabsContent>

        <TabsContent value="calendario">
          <FeriasCalendario ferias={feriasLegacy} onNewSolicitacao={(date) => {
            setNewSolicitacao((prev) => ({ ...prev, dataInicio: date }));
            setIsModalOpen(true);
          }} />
        </TabsContent>

        <TabsContent value="saldos">
          <FeriasSaldos ferias={feriasLegacy} />
        </TabsContent>

        <TabsContent value="financeiro">
          <FeriasFinanceiro />
        </TabsContent>

        <TabsContent value="vencimentos" className="space-y-4">
          <FeriasAlertas />
        </TabsContent>

        <TabsContent value="coletivas" className="space-y-4">
          <FeriasColetivas />
        </TabsContent>

        <TabsContent value="inteligencia" className="space-y-4">
          <FeriasInteligencia ranking={inrRanking} criticos={inrCriticos} altos={inrAltos}
            onCriarAcaoPreventiva={handleCriarAcaoPreventiva} colaboradoresPorSetor={colaboradoresPorSetor} />
          <FeriasEvidenciaNR1 ranking={inrRanking} />
        </TabsContent>

        <TabsContent value="cultura">
          <FeriasCultura ferias={feriasLegacy} />
        </TabsContent>

        <TabsContent value="relatorios">
          <FeriasRelatorios solicitacoes={solicitacoes} colaboradores={colaboradores} />
        </TabsContent>

        <TabsContent value="governanca" className="space-y-4">
          <FeriasGovernanca solicitacoes={solicitacoes} colaboradores={colaboradores} />
          <FeriasVinculoFamiliar colaboradores={colaboradores} />
        </TabsContent>
      </Tabs>

      {/* Modal Nova Solicitação */}
      <Dialog open={isModalOpen} onOpenChange={setIsModalOpen}>
        <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Nova Solicitação de Férias</DialogTitle>
            <DialogDescription>Preencha os dados — o sistema valida conformidade CLT automaticamente</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label>Colaborador *</Label>
              <Popover open={comboOpen} onOpenChange={setComboOpen}>
                <PopoverTrigger asChild>
                  <Button variant="outline" role="combobox" aria-expanded={comboOpen} className="w-full justify-between font-normal">
                    {newSolicitacao.colaborador || "Selecione o colaborador..."}
                    <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
                  </Button>
                </PopoverTrigger>
                <PopoverContent className="w-full p-0" align="start">
                  <Command>
                    <CommandInput placeholder="Buscar colaborador..." />
                    <CommandList>
                      <CommandEmpty>Nenhum colaborador encontrado.</CommandEmpty>
                      <CommandGroup>
                        {colaboradores.map((c) => (
                          <CommandItem key={c.id} value={c.nome_completo} onSelect={() => {
                            setNewSolicitacao(prev => ({
                              ...prev, colaborador: c.nome_completo,
                              // colaboradorId NÃO recebe c.id: a lista vem de "admissoes",
                              // mas a FK colaborador_id aponta para auth.users(id). O id de
                              // uma admissão nunca existe em auth.users, então gravá-lo viola
                              // a FK. A pessoa é identificada por nome + CPF, como no resto do
                              // fluxo de férias. Fica nulo (a coluna aceita).
                              colaboradorCpf: c.cpf || "", colaboradorId: "",
                              colaboradorEmpresaId: c.empresa_id || "",
                              departamento: c.departamento || "", salarioBase: (c as any).salario || 0,
                            }));
                            setComboOpen(false);
                          }}>
                            <Check className={cn("mr-2 h-4 w-4", newSolicitacao.colaborador === c.nome_completo ? "opacity-100" : "opacity-0")} />
                            <div>
                              <p className="text-sm">{c.nome_completo}</p>
                              {c.departamento && <p className="text-xs text-muted-foreground">{c.departamento}</p>}
                            </div>
                          </CommandItem>
                        ))}
                      </CommandGroup>
                    </CommandList>
                  </Command>
                </PopoverContent>
              </Popover>
            </div>
            <div className="space-y-2">
              <Label>Departamento</Label>
              <Input placeholder="Preenchido automaticamente" value={newSolicitacao.departamento} readOnly className="bg-muted/50" />
            </div>
            {/* Período de Gozo (quando o colaborador sai de férias) */}
            <div className="space-y-2">
              <Label className="text-sm font-semibold">Período de Gozo *</Label>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-1">
                  <Label className="text-xs text-muted-foreground">Data Início</Label>
                  <Input type="date" value={newSolicitacao.dataInicio} onChange={(e) => setNewSolicitacao(prev => ({ ...prev, dataInicio: e.target.value }))} />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs text-muted-foreground">Data Fim</Label>
                  <Input type="date" value={newSolicitacao.dataFim} onChange={(e) => setNewSolicitacao(prev => ({ ...prev, dataFim: e.target.value }))} />
                </div>
              </div>
              {newSolicitacao.dataInicio && newSolicitacao.dataFim && (() => {
                const ini = new Date(newSolicitacao.dataInicio);
                const fim = new Date(newSolicitacao.dataFim);
                if (fim < ini) return <p className="text-xs text-destructive">A data fim não pode ser antes do início.</p>;
                const dias = Math.ceil((fim.getTime() - ini.getTime()) / (1000 * 60 * 60 * 24)) + 1;
                return <p className="text-xs text-muted-foreground">Total: <span className="font-semibold text-foreground">{dias}</span> dia{dias !== 1 ? "s" : ""} de férias</p>;
              })()}
            </div>

            {/* Período Aquisitivo (intervalo de trabalho que dá direito às férias) */}
            <div className="space-y-2">
              <Label className="text-sm font-semibold">Período Aquisitivo</Label>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-1">
                  <Label className="text-xs text-muted-foreground">Início</Label>
                  <Input type="date" value={newSolicitacao.periodoAquisitivoInicio} onChange={(e) => setNewSolicitacao(prev => ({ ...prev, periodoAquisitivoInicio: e.target.value }))} />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs text-muted-foreground">Fim</Label>
                  <Input type="date" value={newSolicitacao.periodoAquisitivoFim} onChange={(e) => setNewSolicitacao(prev => ({ ...prev, periodoAquisitivoFim: e.target.value }))} />
                </div>
              </div>
              <p className="text-xs text-muted-foreground">Intervalo de 12 meses de trabalho que garante o direito às férias.</p>
            </div>
            <div className="space-y-2">
              <Label>Salário Base (R$)</Label>
              <Input type="number" min={0} step={100} placeholder="Preenchido ao selecionar colaborador"
                value={newSolicitacao.salarioBase || ""} onChange={(e) => setNewSolicitacao(prev => ({ ...prev, salarioBase: parseFloat(e.target.value) || 0 }))} />
            </div>

            {/* Abono Pecuniário */}
            <div className="space-y-3 p-4 rounded-lg border border-border bg-muted/30">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Banknote className="w-4 h-4 text-success" />
                  <Label className="text-sm font-medium cursor-pointer">Abono Pecuniário</Label>
                  <Tooltip>
                    <TooltipTrigger><Info className="w-3.5 h-3.5 text-muted-foreground" /></TooltipTrigger>
                    <TooltipContent side="top" className="max-w-[280px] text-xs">
                      <p className="font-semibold mb-1">Art. 143, CLT</p>
                      <p>Até 1/3 do período de férias (10 dias) pode ser convertido em abono pecuniário.</p>
                    </TooltipContent>
                  </Tooltip>
                </div>
                <Switch checked={newSolicitacao.abonoPecuniario}
                  onCheckedChange={(checked) => setNewSolicitacao(prev => ({ ...prev, abonoPecuniario: checked }))} />
              </div>
              {newSolicitacao.abonoPecuniario && (
                <div className="space-y-3 pt-2">
                  <div className="grid grid-cols-2 gap-3">
                    <div className="space-y-1.5">
                      <Label className="text-xs">Dias a vender (máx. 10)</Label>
                      <Input type="number" min={1} max={10} value={newSolicitacao.diasAbono}
                        onChange={(e) => setNewSolicitacao(prev => ({ ...prev, diasAbono: Math.min(10, Math.max(1, parseInt(e.target.value) || 0)) }))} />
                    </div>
                    <div className="space-y-1.5">
                      <Label className="text-xs">Salário Base (R$)</Label>
                      <Input type="number" value={newSolicitacao.salarioBase || ""} readOnly className="bg-muted/50" />
                    </div>
                  </div>
                  {newSolicitacao.salarioBase > 0 && (() => {
                    const salarioDia = newSolicitacao.salarioBase / 30;
                    const valorFerias = newSolicitacao.salarioBase;
                    const tercoConstitucional = valorFerias / 3;
                    const valorAbono = salarioDia * newSolicitacao.diasAbono;
                    const total = valorFerias + tercoConstitucional + valorAbono;
                    return (
                      <div className="bg-success/5 border border-success/20 rounded-lg p-3 space-y-1 text-xs">
                        <p className="font-semibold text-success flex items-center gap-1.5"><DollarSign className="w-3.5 h-3.5" /> Simulação</p>
                        <div className="flex justify-between"><span className="text-muted-foreground">Férias</span><span>R$ {valorFerias.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</span></div>
                        <div className="flex justify-between"><span className="text-muted-foreground">1/3 Constitucional</span><span>R$ {tercoConstitucional.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</span></div>
                        <div className="flex justify-between text-success"><span>Abono ({newSolicitacao.diasAbono}d)</span><span className="font-semibold">R$ {valorAbono.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</span></div>
                        <div className="border-t border-success/20 pt-1 flex justify-between font-bold text-foreground"><span>Total Bruto</span><span>R$ {total.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</span></div>
                      </div>
                    );
                  })()}
                </div>
              )}
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setIsModalOpen(false)}>Cancelar</Button>
            <Button onClick={handleNovaSolicitacao} className="gradient-primary" disabled={criarSolicitacao.isPending}>
              {criarSolicitacao.isPending ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Plus className="w-4 h-4 mr-2" />}
              Criar Solicitação
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Link Assinatura Dialog */}
      <Dialog open={!!linkAssinaturaDialog} onOpenChange={(open) => !open && setLinkAssinaturaDialog(null)}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>Link de Assinatura</DialogTitle>
            <DialogDescription>Link gerado para {linkAssinaturaDialog?.colaborador}.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="flex items-center gap-2">
              <Input readOnly value={linkAssinaturaDialog?.url || ""} className="text-xs flex-1"
                onClick={(e) => (e.target as HTMLInputElement).select()} />
              <Button size="sm" variant="outline" onClick={() => {
                if (linkAssinaturaDialog?.url) { navigator.clipboard.writeText(linkAssinaturaDialog.url); toast.success("Link copiado!"); }
              }}>Copiar</Button>
            </div>
            <Button className="w-full bg-[hsl(var(--success))] hover:bg-[hsl(var(--success))]/90 text-white" onClick={() => {
              if (linkAssinaturaDialog) {
                const msg = encodeURIComponent(`Olá ${linkAssinaturaDialog.colaborador}, segue o link para assinatura das suas férias:\n\n${linkAssinaturaDialog.url}`);
                window.open(`https://wa.me/?text=${msg}`, "_blank");
              }
            }}>
              <Send className="w-4 h-4 mr-2" /> Enviar via WhatsApp
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default Ferias;
