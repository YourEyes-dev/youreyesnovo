import { useMemo, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ChevronDown, ChevronRight, CheckCircle, XCircle, Paperclip, FileText, Shield, Search, Trash2, ShieldAlert, Camera, Loader2 } from "lucide-react";
import { confirm } from "@/components/ui/confirm-dialog";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { urlTemporariaSelfie } from "@/lib/ponto/selfie";
import { Checkbox } from "@/components/ui/checkbox";

import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Label } from "@/components/ui/label";
import { Tooltip, TooltipContent, TooltipTrigger, TooltipProvider } from "@/components/ui/tooltip";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import type { PontoAjuste } from "@/hooks/usePonto";
import { usePontoJustificativas } from "@/hooks/usePontoJustificativas";
import { useAuthContext } from "@/contexts/AuthContext";
import { abreviacaoDiaSemana } from "@/lib/ponto/diaSemana";

const MOTIVOS_REJEICAO = [
  "Horário incoerente com a jornada",
  "Informação divergente do comprovante",
  "Marcação duplicada",
  "Não compareceu ao trabalho",
  "Esqueceu de registrar no horário correto",
  "Outro"
];

const hhmm = (t?: string | null) => (t || "").slice(0, 5);

// RPCs novas ainda fora dos tipos gerados do Supabase.
type RpcLivre = (fn: string, args: Record<string, unknown>) => Promise<{ error: { message: string } | null }>;
const rpcLivre = (fn: string, args: Record<string, unknown>) =>
  (supabase.rpc as unknown as RpcLivre)(fn, args);

const formatDate = (iso: string) => {
  const raw = (iso || "").toString().slice(0, 10);
  const [y, m, d] = raw.split("-");
  return d && m && y ? `${d}/${m}/${y}` : iso;
};

interface Props {
  ajustes: PontoAjuste[];
  processarAjuste: (args: { ajusteId: string; aprovado: boolean; observacao?: string; multiple?: boolean }) => Promise<unknown> | void;
  processando: boolean;
  excluirAjuste?: (args: { ajusteId: string }) => Promise<unknown> | void;
  excluindoAjuste?: boolean;
  onOpenAnexos: (ajuste: PontoAjuste) => void;
}

export function AjustesAprovacaoPlanilha({ ajustes, processarAjuste, processando, excluirAjuste, excluindoAjuste, onOpenAnexos }: Props) {

  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<"todos" | "pendente" | "aprovado" | "rejeitado">("pendente");
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());
  const [rejeitarDialogOpen, setRejeitarDialogOpen] = useState(false);
  const [rejeitarObservacao, setRejeitarObservacao] = useState("");
  const [rejeitarMotivoPredefinido, setRejeitarMotivoPredefinido] = useState("");
  const [itemsParaRejeitar, setItemsParaRejeitar] = useState<PontoAjuste[]>([]);

  // Segregação de funções (Bloco 3 / MTP 671): quem lançou o ajuste só pode
  // aprová-lo com justificativa registrada; ninguém aprova o próprio ponto.
  const { user, profile } = useAuthContext();
  const soDigitos = (v?: string | null) => (v || "").replace(/\D/g, "");
  const meuCpf = soDigitos((profile as { cpf?: string } | null)?.cpf);
  const isProprioPonto = (aj: PontoAjuste) =>
    !!meuCpf && soDigitos(aj.colaborador_cpf) === meuCpf;
  const isAutoLancado = (aj: PontoAjuste) => !!user?.id && aj.created_by === user.id;
  const [autoDialogOpen, setAutoDialogOpen] = useState(false);
  const [autoJustificativa, setAutoJustificativa] = useState("");
  const [itemsAutoAprovar, setItemsAutoAprovar] = useState<PontoAjuste[]>([]);

  // Regra de abono por justificativa (para sinalizar ao aprovador que aprovar
  // aquele item vai abonar o dia).
  const { justificativas } = usePontoJustificativas();
  const abonoPorId = useMemo(() => {
    const m: Record<string, string> = {};
    justificativas.forEach((j) => { m[j.id] = j.tipo_abono; });
    return m;
  }, [justificativas]);
  const ajusteAbona = (aj: PontoAjuste): boolean => {
    const ta = aj.justificativa_id ? abonoPorId[aj.justificativa_id] : undefined;
    return ta === "sim" || (ta === "configuravel" && !!aj.abonar_se_aprovado);
  };
  const regraAbono = (aj: PontoAjuste): string | undefined =>
    aj.justificativa_id ? abonoPorId[aj.justificativa_id] : undefined;
  const ehAusencia = (aj: PontoAjuste) => aj.natureza === "ausencia";

  // Fase 2: na ausência com regra "Configurável", quem decide o abono é o RH,
  // antes de aprovar (o colaborador não decide abono).
  const queryClient = useQueryClient();
  const [definindoAbono, setDefinindoAbono] = useState<string | null>(null);
  const definirAbono = async (aj: PontoAjuste, abonar: boolean) => {
    setDefinindoAbono(aj.id);
    try {
      const { error } = await rpcLivre("ponto_ajuste_definir_abono", {
        p_ajuste_id: aj.id,
        p_abonar: abonar,
      });
      if (error) throw error;
      await queryClient.invalidateQueries({ queryKey: ["ponto-ajustes-pendentes"] });
    } catch (e) {
      toast.error("Não foi possível marcar o abono: " + (e as Error).message);
    } finally {
      setDefinindoAbono(null);
    }
  };

  // Selfie do pedido (app): bucket privado, link temporário, acesso registrado
  // na trilha (LGPD arts. 11 e 46) — mesmo cuidado da selfie da batida.
  const [selfieAberta, setSelfieAberta] = useState<{ nome: string; src: string | null; carregando: boolean } | null>(null);
  const verSelfie = async (aj: PontoAjuste) => {
    setSelfieAberta({ nome: aj.colaborador_nome, src: null, carregando: true });
    const src = await urlTemporariaSelfie(aj.selfie_url);
    setSelfieAberta({ nome: aj.colaborador_nome, src, carregando: false });
    if (!src) toast.error("Não foi possível abrir a selfie.");
    try {
      await rpcLivre("ponto_log_acesso_sensivel", {
        p_tenant_id: aj.tenant_id,
        p_acao: "visualizou_selfie",
        p_recurso: "ponto_ajustes",
        p_recurso_id: aj.id,
        p_colaborador_cpf: aj.colaborador_cpf || null,
        p_descricao: "Selfie do pedido de ajuste exibida na Folha de Aprovação.",
      });
    } catch {
      // O registro não pode impedir o RH de trabalhar.
    }
  };

  // Group: colaborador_id -> data_referencia -> ajustes[]
  const grouped = useMemo(() => {
    const filtered = ajustes.filter((a) => {
      if (statusFilter !== "todos" && a.status !== statusFilter) return false;
      if (search && !a.colaborador_nome.toLowerCase().includes(search.toLowerCase())) return false;
      return true;
    });

    const map = new Map<string, { nome: string; cpf: string; days: Map<string, PontoAjuste[]> }>();
    for (const a of filtered) {
      const colabId = a.colaborador_id;
      if (!map.has(colabId)) {
        map.set(colabId, { nome: a.colaborador_nome, cpf: a.colaborador_cpf, days: new Map() });
      }
      const colab = map.get(colabId)!;
      const dateKey = (a.data_referencia || "").toString().slice(0, 10);
      if (!colab.days.has(dateKey)) colab.days.set(dateKey, []);
      colab.days.get(dateKey)!.push(a);
    }
    return Array.from(map.entries())
      .map(([id, info]) => ({
        id,
        nome: info.nome,
        cpf: info.cpf,
        days: Array.from(info.days.entries())
          .map(([date, items]) => ({ date, items }))
          .sort((a, b) => b.date.localeCompare(a.date)),
        totalPendentes: Array.from(info.days.values()).flat().filter((a) => a.status === "pendente").length,
      }))
      .sort((a, b) => b.totalPendentes - a.totalPendentes || a.nome.localeCompare(b.nome));
  }, [ajustes, statusFilter, search]);

  const toggle = (id: string) => {
    setCollapsed((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const aprovarLote = async (pendentes: PontoAjuste[], observacao?: string) => {
    // Processa todos menos o último silenciosamente
    for (let i = 0; i < pendentes.length - 1; i++) {
      await processarAjuste({ ajusteId: pendentes[i].id, aprovado: true, observacao, multiple: true });
    }
    // O último dispara o feedback visual
    await processarAjuste({ ajusteId: pendentes[pendentes.length - 1].id, aprovado: true, observacao });
  };

  const handleApprovarDia = async (items: PontoAjuste[]) => {
    const pendentesRaw = items.filter((a) => a.status === "pendente");
    if (pendentesRaw.length === 0) return;

    // Ordena por horário solicitado para respeitar a sequência cronológica
    // (a trigger de validação exige marcações em ordem crescente no tempo).
    const pendentes = [...pendentesRaw].sort(
      (a, b) => String(a.hora_solicitada || "").localeCompare(String(b.hora_solicitada || ""))
    );

    // Ausência parcial que abona: até a Fase 4 o sistema abona o DIA INTEIRO.
    // O RH precisa confirmar isso conscientemente.
    const parciaisQueAbonam = pendentes.filter(
      (a) => ehAusencia(a) && !a.dia_inteiro && ajusteAbona(a)
    );
    if (parciaisQueAbonam.length > 0) {
      const ok = await confirm({
        title: "Ausência de parte do dia que abona",
        description:
          "Este dia tem uma ausência de parte do dia com justificativa que abona. Por enquanto, ao aprovar, o sistema abona o DIA INTEIRO (não só as horas do documento) e avisa o DP para conferir. Deseja aprovar mesmo assim?",
        confirmLabel: "Aprovar",
      });
      if (!ok) return;
    }

    // Auto-lançamento: exige justificativa antes de enviar ao backend
    // (o RPC rejeita observação com menos de 10 caracteres).
    if (pendentes.some(isAutoLancado)) {
      setItemsAutoAprovar(pendentes);
      setAutoJustificativa("");
      setAutoDialogOpen(true);
      return;
    }

    await aprovarLote(pendentes);
  };

  const confirmarAutoAprovacao = async () => {
    if (itemsAutoAprovar.length === 0) return;
    await aprovarLote(itemsAutoAprovar, autoJustificativa.trim());
    setAutoDialogOpen(false);
    setItemsAutoAprovar([]);
  };

  const handleRejeitarDia = (items: PontoAjuste[]) => {
    const pendentes = items.filter((a) => a.status === "pendente");
    if (pendentes.length === 0) return;
    setItemsParaRejeitar(pendentes);
    setRejeitarObservacao("");
    setRejeitarMotivoPredefinido("");
    setRejeitarDialogOpen(true);
  };


  const confirmarRejeicao = async () => {
    if (itemsParaRejeitar.length === 0) return;

    const finalMotivo = rejeitarMotivoPredefinido === "Outro" 
      ? rejeitarObservacao 
      : (rejeitarMotivoPredefinido + (rejeitarObservacao ? ` - ${rejeitarObservacao}` : ""));

    const obs = finalMotivo || undefined;
    
    // Processa todos menos o último silenciosamente
    for (let i = 0; i < itemsParaRejeitar.length - 1; i++) {
      await processarAjuste({ ajusteId: itemsParaRejeitar[i].id, aprovado: false, observacao: obs, multiple: true });
    }
    // O último dispara o feedback visual
    await processarAjuste({ ajusteId: itemsParaRejeitar[itemsParaRejeitar.length - 1].id, aprovado: false, observacao: obs });
    
    setRejeitarDialogOpen(false);
    setItemsParaRejeitar([]);
  };

  const handleExcluirDia = async (items: PontoAjuste[]) => {
    if (!excluirAjuste || items.length === 0) return;
    const ok = await confirm({
      title: "Excluir ajustes do dia",
      description: `Excluir permanentemente ${items.length} solicitação(ões) de ajuste deste dia? Esta ação não pode ser desfeita e ficará registrada na auditoria.`,
      confirmLabel: "Excluir",
      variant: "destructive",
    });
    if (!ok) return;
    for (const a of items) {
      await excluirAjuste({ ajusteId: a.id });
    }
  };



  return (
    <TooltipProvider delayDuration={150}>
      <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="bg-card rounded-2xl border overflow-hidden shadow-sm">
        {/* Toolbar */}
        <div className="px-5 py-4 border-b bg-muted/30 flex items-center justify-between flex-wrap gap-3">
          <div>
            <h3 className="text-base font-bold tracking-tight">Folha de Aprovação de Ajustes</h3>
            <p className="text-xs text-muted-foreground mt-0.5">
              Cada linha = um dia. Aprove ou rejeite o dia inteiro de uma só vez. <strong>Correção de batida</strong> grava
              o horário como trabalho. <strong>Ausência</strong> vira lançamento em Atestados, com o documento anexado e a
              regra de abono da justificativa — não grava marcação.
            </p>
          </div>
          <div className="flex items-center gap-2">
            <div className="relative">
              <Search className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <Input
                placeholder="Buscar colaborador..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="h-9 pl-8 w-56 text-sm"
              />
            </div>
            <Select value={statusFilter} onValueChange={(v) => setStatusFilter(v as typeof statusFilter)}>
              <SelectTrigger className="h-9 w-40 text-sm"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="pendente">Apenas pendentes</SelectItem>
                <SelectItem value="aprovado">Aprovados</SelectItem>
                <SelectItem value="rejeitado">Rejeitados</SelectItem>
                <SelectItem value="todos">Todos os status</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>

        {/* Legenda */}
        <div className="px-5 py-2 border-b bg-muted/10 flex items-center gap-4 flex-wrap text-[11px] text-muted-foreground">
          <div className="flex items-center gap-1.5">
            <span className="inline-block w-3 h-3 rounded bg-emerald-100 border border-emerald-300" />
            <span>Inclusão (marcação nova)</span>
          </div>
          <div className="flex items-center gap-1.5">
            <span className="inline-block w-3 h-3 rounded bg-amber-100 border border-amber-300" />
            <span>Alteração (substitui original)</span>
          </div>
          <div className="flex items-center gap-1.5">
            <span className="inline-block w-3 h-3 rounded bg-slate-100 border border-slate-300" />
            <span>Sem alteração</span>
          </div>
          <div className="flex items-center gap-1.5">
            <span className="inline-block w-3 h-3 rounded bg-violet-100 border border-violet-300" />
            <span>Ausência (vira Atestado)</span>
          </div>
          <div className="flex items-center gap-1.5">
            <span className="inline-block w-3 h-3 rounded bg-indigo-100 border border-indigo-300" />
            <span>Lançamento do RH (dia inteiro)</span>
          </div>
        </div>

        <div className="divide-y">
          {grouped.length === 0 && (
            <div className="text-center py-12 text-sm text-muted-foreground">
              Nenhuma solicitação de ajuste encontrada com os filtros atuais.
            </div>
          )}

          {grouped.map((colab) => {
            const isCollapsed = collapsed.has(colab.id);
            return (
              <div key={colab.id} className="bg-card">
                {/* Cabeçalho colaborador */}
                <button
                  type="button"
                  onClick={() => toggle(colab.id)}
                  className="w-full px-5 py-3 flex items-center justify-between gap-3 hover:bg-muted/30 transition-colors text-left"
                >
                  <div className="flex items-center gap-3 min-w-0">
                    {isCollapsed ? <ChevronRight className="w-4 h-4 text-muted-foreground shrink-0" /> : <ChevronDown className="w-4 h-4 text-muted-foreground shrink-0" />}
                    <Avatar className="h-9 w-9 shrink-0">
                      <AvatarFallback className="bg-primary/10 text-primary text-xs font-semibold">
                        {colab.nome.trim().split(/\s+/).map((n) => n[0]).join("").slice(0, 2).toUpperCase()}
                      </AvatarFallback>
                    </Avatar>
                    <div className="min-w-0">
                      <p className="font-semibold text-sm truncate">{colab.nome}</p>
                      <p className="text-[11px] text-muted-foreground">
                        {colab.days.length} dia(s) com ajustes • {colab.days.reduce((s, d) => s + d.items.length, 0)} marcação(ões)
                      </p>
                    </div>
                  </div>
                  {colab.totalPendentes > 0 && (
                    <Badge className="bg-amber-100 text-amber-800 hover:bg-amber-100 font-semibold">
                      {colab.days.filter(d => d.items.some(a => a.status === "pendente")).length} dia(s) pendente(s)
                    </Badge>
                  )}
                </button>

                {/* Planilha de dias */}
                <AnimatePresence initial={false}>
                  {!isCollapsed && (
                    <motion.div
                      initial={{ height: 0, opacity: 0 }}
                      animate={{ height: "auto", opacity: 1 }}
                      exit={{ height: 0, opacity: 0 }}
                      transition={{ duration: 0.18 }}
                      className="overflow-hidden"
                    >
                      <div className="overflow-x-auto">
                        <table className="w-full text-sm border-t">
                          <thead className="bg-muted/40">
                            <tr>
                              <th className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground py-2 px-3 text-left w-28">Data</th>
                              {/* Largura FIXA: a folga da tabela vai para a coluna Motivo, e o
                                  título "Motivo" fica cravado na fronteira dos 260px — alinhado
                                  com os blocos de motivo do corpo (grid 248px + gap 12px). */}
                              <th className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground py-2 px-3 text-left w-[260px] min-w-[260px]">Marcações (Entrada / Saída)</th>
                              <th className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground py-2 px-3 text-left min-w-[180px]">Motivo</th>
                              <th className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground py-2 px-3 text-center w-20">Anexos</th>
                              <th className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground py-2 px-3 text-right w-52">Ações do Dia</th>
                            </tr>
                          </thead>
                          <tbody>
                            {colab.days.map(({ date, items }) => {
                              const hasPendente = items.some((a) => a.status === "pendente");
                              const allApr = items.every((a) => a.status === "aprovado");
                              const allRej = items.every((a) => a.status === "rejeitado");
                              const totalAnexos = new Set(
                                items.flatMap((a) => a.anexos ?? []).map((x: any) => x.url ?? x.path ?? x.nome)
                              ).size;
                              const firstAjusteAnexo = items.find((a) => (a.anexos?.length ?? 0) > 0);
                              const comSelfie = items.find((a) => !!a.selfie_url);

                              return (
                                <tr key={date} className={cn("border-t hover:bg-muted/20", !hasPendente && "opacity-90")}>
                                  <td className="py-2.5 px-3 font-mono font-semibold text-sm text-foreground/90 align-top">
                                    {formatDate(date)}{" "}
                                    {/* RN16: abreviação do dia da semana ao lado da data. */}
                                    <span className="text-muted-foreground font-medium">
                                      {abreviacaoDiaSemana(date)}
                                    </span>
                                  </td>

                                  {(() => {
                                    // Ordena os ajustes do dia por horário.
                                    const ordenados = [...items]
                                      .filter((a) => a.tipo_ajuste !== "justificativa")
                                      .sort((a, b) => String(a.hora_solicitada || "").localeCompare(String(b.hora_solicitada || "")));
                                    const ausencias = items.filter((a) => ehAusencia(a));
                                    const justificativas = items.filter((a) => a.tipo_ajuste === "justificativa" && !ehAusencia(a));

                                    // Monta linhas Entrada|Saída pelo TIPO salvo (não pela
                                    // posição): cada linha = uma Entrada (coluna esquerda) +
                                    // uma Saída (coluna direita). Uma Saída "solta" (a Entrada
                                    // do dia é uma marcação real, não um ajuste) vira uma linha
                                    // só com Saída, com a Entrada vazia. batida/sem tipo: alterna.
                                    const ehEntradaTipo = (c: PontoAjuste["tipo_marcacao"]) =>
                                      c === "entrada" || c === "retorno_almoco";
                                    const ehSaidaTipo = (c: PontoAjuste["tipo_marcacao"]) =>
                                      c === "saida" || c === "saida_almoco";
                                    const linhas: { entrada: PontoAjuste | null; saida: PontoAjuste | null }[] = [];
                                    for (const ajuste of ordenados) {
                                      const c = ajuste.tipo_marcacao;
                                      const aberta = linhas[linhas.length - 1];
                                      const temAberta = !!(aberta && aberta.entrada && !aberta.saida);
                                      const ehEntrada = ehEntradaTipo(c) ? true : ehSaidaTipo(c) ? false : !temAberta;
                                      if (ehEntrada) linhas.push({ entrada: ajuste, saida: null });
                                      else if (temAberta) aberta!.saida = ajuste;
                                      else linhas.push({ entrada: null, saida: ajuste });
                                    }

                                    const renderBox = (ajuste: PontoAjuste, ehEntrada: boolean) => {
                                      const isInclusao = ajuste.tipo_ajuste === "inclusao";
                                      const isCorrecao = ajuste.tipo_ajuste === "correcao";
                                      return (
                                        <div className="flex flex-col gap-0.5">
                                          <span className={cn("text-[9px] font-semibold", ehEntrada ? "text-emerald-600" : "text-rose-600")}>
                                            {ehEntrada ? "Entrada" : "Saída"}
                                          </span>
                                          <Tooltip>
                                            <TooltipTrigger asChild>
                                              <div
                                                className={cn(
                                                  "rounded border px-2 py-1.5 font-mono text-sm font-semibold cursor-help text-center min-w-[78px]",
                                                  isInclusao && "bg-emerald-50 border-emerald-300 text-emerald-900",
                                                  isCorrecao && "bg-amber-50 border-amber-300 text-amber-900",
                                                )}
                                              >
                                                {ajuste.hora_solicitada || "—"}
                                                {isCorrecao && ajuste.hora_original && (
                                                  <div className="text-[10px] font-normal text-muted-foreground line-through mt-0.5">
                                                    {ajuste.hora_original}
                                                  </div>
                                                )}
                                              </div>
                                            </TooltipTrigger>
                                            <TooltipContent side="top" className="max-w-xs">
                                              <p className="font-semibold mb-1">{ehEntrada ? "Entrada" : "Saída"} — {isInclusao ? "Inclusão" : "Alteração"}</p>
                                              <p className="text-xs">Motivo: {ajuste.motivo}</p>
                                              {isCorrecao && ajuste.hora_original && (
                                                <p className="text-xs mt-1">Original: <span className="line-through">{ajuste.hora_original}</span> → Solicitado: <strong>{ajuste.hora_solicitada}</strong></p>
                                              )}
                                            </TooltipContent>
                                          </Tooltip>
                                        </div>
                                      );
                                    };

                                    // Slot vazio: placeholder discreto p/ manter o grid alinhado.
                                    const slotVazio = (ehEntrada: boolean) => (
                                      <div className="flex flex-col gap-0.5">
                                        <span className="text-[9px] font-semibold text-muted-foreground/40">
                                          {ehEntrada ? "Entrada" : "Saída"}
                                        </span>
                                        <div className="rounded border border-dashed border-muted-foreground/20 px-2 py-1.5 text-sm text-muted-foreground/40 text-center min-w-[78px]">—</div>
                                      </div>
                                    );

                                    // Motivo/observação do PERÍODO: cada par mostra a SUA
                                    // justificativa ao lado, em vez de juntar as do dia todo.
                                    const renderMotivoPeriodo = (ajustes: (PontoAjuste | null)[], semSelo = false) => {
                                      const ms = Array.from(new Set(ajustes.map((a) => a?.motivo).filter((x): x is string => !!x)));
                                      const obs = Array.from(new Set(ajustes.map((a) => a?.observacao).filter((x): x is string => !!x)));
                                      const presentes = ajustes.filter((a): a is PontoAjuste => !!a);
                                      const correcao = presentes.some((a) => a.natureza === "correcao_batida");
                                      const antigo = presentes.some((a) => !a.natureza && (a.tipo_ajuste === "inclusao" || a.tipo_ajuste === "correcao"));
                                      return (
                                        <div className="min-w-0 pt-4">
                                          {!semSelo && correcao && (
                                            <Badge variant="outline" className="text-[9px] mb-0.5 border-amber-300 text-amber-800">Correção de batida</Badge>
                                          )}
                                          {!semSelo && !correcao && antigo && (
                                            <Tooltip>
                                              <TooltipTrigger asChild>
                                                <Badge variant="outline" className="text-[9px] mb-0.5 border-slate-300 text-slate-600 cursor-help">Pedido antigo</Badge>
                                              </TooltipTrigger>
                                              <TooltipContent side="top" className="max-w-xs">
                                                <p className="text-xs">
                                                  Pedido feito antes da separação entre Correção de batida e Ausência, com motivo
                                                  em texto livre. Aprovar grava o horário como trabalho. Se na verdade for uma
                                                  ausência com declaração ou atestado, rejeite e peça para o colaborador reenviar
                                                  como <strong>Ausência</strong>, com o documento.
                                                </p>
                                              </TooltipContent>
                                            </Tooltip>
                                          )}
                                          <p className="text-xs font-medium leading-snug">{ms.join(" • ") || "—"}</p>
                                          {obs.length > 0 && (
                                            <p className="text-[11px] text-muted-foreground italic leading-snug mt-0.5">{obs.join(" • ")}</p>
                                          )}
                                        </div>
                                      );
                                    };

                                    return (
                                      <td className="py-2.5 px-3 align-top" colSpan={2}>
                                        <div className="flex flex-col gap-1.5">
                                          {ordenados.length === 0 && justificativas.length === 0 && ausencias.length === 0 && (
                                            <span className="text-xs text-muted-foreground/60">—</span>
                                          )}
                                          {/* Cada linha = um PERÍODO: par Entrada+Saída à esquerda,
                                              motivo/observação DESSE período à direita. */}
                                          {linhas.map((linha, idx) => (
                                            <div key={`linha-${idx}`} className="grid grid-cols-[248px_1fr] gap-3 items-start">
                                              <div className="grid grid-cols-2 gap-2 w-fit">
                                                {linha.entrada ? renderBox(linha.entrada, true) : slotVazio(true)}
                                                {linha.saida ? renderBox(linha.saida, false) : slotVazio(false)}
                                              </div>
                                              {renderMotivoPeriodo([linha.entrada, linha.saida])}
                                            </div>
                                          ))}
                                          {ausencias.map((aj) => {
                                            const regra = regraAbono(aj);
                                            const abona = ajusteAbona(aj);
                                            const pendente = aj.status === "pendente";
                                            const periodo = aj.dia_inteiro
                                              ? "Dia inteiro"
                                              : `${hhmm(aj.ausencia_hora_inicio)}–${hhmm(aj.ausencia_hora_fim)}`;
                                            return (
                                              <div key={aj.id} className="grid grid-cols-[248px_1fr] gap-3 items-start">
                                                <div className="flex flex-col gap-0.5">
                                                  <span className="text-[9px] font-semibold text-violet-700">Ausência</span>
                                                  <div className="rounded border px-2 py-1.5 text-[11px] bg-violet-50 border-violet-300 text-violet-900 w-fit min-w-[160px] space-y-1">
                                                    <span className="block font-mono font-semibold text-sm">{periodo}</span>
                                                    {regra === "configuravel" ? (
                                                      pendente ? (
                                                        <label className="flex items-center gap-1.5 cursor-pointer">
                                                          {definindoAbono === aj.id ? (
                                                            <Loader2 className="w-3 h-3 animate-spin" />
                                                          ) : (
                                                            <Checkbox
                                                              checked={!!aj.abonar_se_aprovado}
                                                              onCheckedChange={(c) => definirAbono(aj, c === true)}
                                                              disabled={processando || !!definindoAbono}
                                                            />
                                                          )}
                                                          <span className="text-[10px]">Abonar (decisão do RH)</span>
                                                        </label>
                                                      ) : (
                                                        <span className="block text-[10px]">{abona ? "abonou ✓" : "não abonou"}</span>
                                                      )
                                                    ) : (
                                                      <span className={cn("block text-[10px]", abona ? "text-emerald-700" : "text-rose-700")}>
                                                        {abona ? "abona ✓" : "não abona (débito segue)"}
                                                      </span>
                                                    )}
                                                    <div className="flex items-center gap-1 pt-0.5">
                                                      {(aj.anexos?.length ?? 0) > 0 && (
                                                        <Button size="sm" variant="outline" className="h-6 gap-1 px-1.5 text-[10px]" onClick={() => onOpenAnexos(aj)}>
                                                          <Paperclip className="w-3 h-3" /> Documento
                                                        </Button>
                                                      )}
                                                      {aj.atestado_id && (
                                                        <Badge variant="outline" className="text-[9px] border-violet-300 text-violet-700">
                                                          <FileText className="w-3 h-3 mr-0.5" /> Em Atestados
                                                        </Badge>
                                                      )}
                                                    </div>
                                                  </div>
                                                </div>
                                                {renderMotivoPeriodo([aj], true)}
                                              </div>
                                            );
                                          })}
                                          {justificativas.map((aj) => {
                                            const abona = ajusteAbona(aj);
                                            return (
                                              <div key={aj.id} className="grid grid-cols-[248px_1fr] gap-3 items-start">
                                                <div className="flex flex-col gap-0.5">
                                                  <span className="text-[9px] font-semibold text-indigo-600">
                                                    {aj.dia_inteiro ? "Dia inteiro" : "Justif."}
                                                  </span>
                                                  <Tooltip>
                                                    <TooltipTrigger asChild>
                                                      <div className="rounded border px-2 py-1 text-[11px] font-semibold bg-indigo-50 border-indigo-300 text-indigo-900 text-center min-w-[78px] cursor-help">
                                                        <span className="block truncate max-w-[140px]">{aj.motivo || "Justificativa"}</span>
                                                        {abona && <span className="block text-[9px] font-normal text-emerald-700">abona ✓</span>}
                                                      </div>
                                                    </TooltipTrigger>
                                                    <TooltipContent side="top" className="max-w-xs">
                                                      <p className="font-semibold mb-1">{aj.dia_inteiro ? "Dia inteiro" : "Justificativa"}</p>
                                                      <p className="text-xs">Motivo: {aj.motivo}</p>
                                                      {aj.observacao && <p className="text-xs mt-1">Obs.: {aj.observacao}</p>}
                                                      <p className="text-xs mt-1 text-muted-foreground">
                                                        {abona ? "Ao aprovar, o dia fica Justificado (abonado)." : "Não abona o dia."}
                                                      </p>
                                                    </TooltipContent>
                                                  </Tooltip>
                                                </div>
                                                {renderMotivoPeriodo([aj])}
                                              </div>
                                            );
                                          })}
                                        </div>
                                      </td>
                                    );
                                  })()}

                                  <td className="py-2.5 px-3 text-center align-top">
                                    <div className="flex flex-col items-center gap-1">
                                      {totalAnexos > 0 && firstAjusteAnexo ? (
                                        <Button size="sm" variant="outline" className="h-7 gap-1 px-2" onClick={() => onOpenAnexos(firstAjusteAnexo)}>
                                          <Paperclip className="w-3 h-3" />
                                          <span className="text-[11px]">{totalAnexos}</span>
                                        </Button>
                                      ) : null}
                                      {comSelfie && (
                                        <Button
                                          size="sm"
                                          variant="outline"
                                          className="h-7 gap-1 px-2"
                                          onClick={() => verSelfie(comSelfie)}
                                          title="Ver a selfie tirada no envio do pedido"
                                        >
                                          <Camera className="w-3 h-3" />
                                          <span className="text-[11px]">Selfie</span>
                                        </Button>
                                      )}
                                      {!(totalAnexos > 0 && firstAjusteAnexo) && !comSelfie && (
                                        <span className="text-xs text-muted-foreground">—</span>
                                      )}
                                    </div>
                                  </td>

                                  <td className="py-2.5 px-3 text-right align-top">
                                    <div className="flex items-center justify-end gap-1.5 flex-wrap">
                                      {hasPendente ? (
                                        items.some(isProprioPonto) ? (
                                          <Tooltip>
                                            <TooltipTrigger asChild>
                                              <Badge variant="outline" className="text-[10px] gap-1 border-amber-300 text-amber-700">
                                                <ShieldAlert className="w-3 h-3" /> Seu próprio ponto
                                              </Badge>
                                            </TooltipTrigger>
                                            <TooltipContent side="left" className="max-w-xs">
                                              <p className="text-xs">
                                                Segregação de funções: ajustes do seu próprio ponto devem ser analisados
                                                por outro gestor/RH.
                                              </p>
                                            </TooltipContent>
                                          </Tooltip>
                                        ) : (
                                        <>
                                          {items.some(isAutoLancado) && (
                                            <Tooltip>
                                              <TooltipTrigger asChild>
                                                <Badge variant="outline" className="text-[10px] gap-1 border-amber-300 text-amber-700">
                                                  <ShieldAlert className="w-3 h-3" /> Auto-lançado
                                                </Badge>
                                              </TooltipTrigger>
                                              <TooltipContent side="left" className="max-w-xs">
                                                <p className="text-xs">
                                                  Você é o solicitante deste ajuste. A aprovação exige justificativa e fica
                                                  registrada na auditoria.
                                                </p>
                                              </TooltipContent>
                                            </Tooltip>
                                          )}
                                          <Button
                                            size="sm"
                                            variant="outline"
                                            className="h-7 px-2 text-emerald-700 border-emerald-300 hover:bg-emerald-50 hover:text-emerald-700"
                                            onClick={() => handleApprovarDia(items)}
                                            disabled={processando}
                                          >
                                            <CheckCircle className="w-3.5 h-3.5 mr-1" /> Aprovar dia
                                          </Button>
                                          <Button
                                            size="sm"
                                            variant="outline"
                                            className="h-7 px-2 text-rose-700 border-rose-300 hover:bg-rose-50 hover:text-rose-700"
                                            onClick={() => handleRejeitarDia(items)}
                                            disabled={processando}
                                          >
                                            <XCircle className="w-3.5 h-3.5 mr-1" /> Rejeitar
                                          </Button>
                                        </>
                                        )
                                      ) : (
                                        <>
                                          {/* Sem a coluna Status, o selo do dia já processado
                                              vem inline aqui (Aprovado/Rejeitado/Misto). */}
                                          {allApr && <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100 text-[10px]">Aprovado</Badge>}
                                          {allRej && <Badge className="bg-rose-100 text-rose-800 hover:bg-rose-100 text-[10px]">Rejeitado</Badge>}
                                          {!allApr && !allRej && <Badge variant="outline" className="text-[10px]">Misto</Badge>}
                                          <span className="text-[11px] text-muted-foreground mr-1">
                                            {items[0].aprovado_por_nome ? `por ${items[0].aprovado_por_nome}` : "—"}
                                          </span>
                                        </>
                                      )}
                                      {excluirAjuste && (
                                        <Tooltip>
                                          <TooltipTrigger asChild>
                                            <Button
                                              size="sm"
                                              variant="ghost"
                                              className="h-7 w-7 p-0 text-rose-600 hover:bg-rose-50 hover:text-rose-700"
                                              onClick={() => handleExcluirDia(items)}
                                              disabled={!!excluindoAjuste}
                                              aria-label="Excluir ajustes do dia"
                                            >
                                              <Trash2 className="w-3.5 h-3.5" />
                                            </Button>
                                          </TooltipTrigger>
                                          <TooltipContent side="top">Excluir permanentemente</TooltipContent>
                                        </Tooltip>
                                      )}
                                    </div>
                                  </td>

                                </tr>
                              );
                            })}
                          </tbody>
                        </table>
                      </div>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            );
          })}
        </div>

        <div className="px-5 py-3 border-t bg-muted/20 flex items-center gap-2 text-[10px] text-muted-foreground uppercase tracking-wider">
          <Shield className="w-3.5 h-3.5" />
          Logs de auditoria em conformidade com Portaria 671 MTP
        </div>
      </motion.div>
      <Dialog open={!!selfieAberta} onOpenChange={(v) => { if (!v) setSelfieAberta(null); }}>
        <DialogContent className="sm:max-w-[380px]">
          <DialogHeader>
            <DialogTitle>Selfie do pedido</DialogTitle>
            <DialogDescription>
              Foto tirada por {selfieAberta?.nome} ao enviar o pedido de ajuste. O acesso fica registrado.
            </DialogDescription>
          </DialogHeader>
          <div className="flex items-center justify-center min-h-[200px]">
            {selfieAberta?.carregando ? (
              <Loader2 className="w-5 h-5 animate-spin text-muted-foreground" />
            ) : selfieAberta?.src ? (
              <img src={selfieAberta.src} alt="Selfie do pedido de ajuste" className="max-h-[60vh] rounded-md" />
            ) : (
              <span className="text-sm text-muted-foreground">Selfie indisponível.</span>
            )}
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={rejeitarDialogOpen} onOpenChange={setRejeitarDialogOpen}>
        <DialogContent className="sm:max-w-[425px]">
          <DialogHeader>
            <DialogTitle>Observação para Rejeição</DialogTitle>
            <DialogDescription>
              Informe o motivo da rejeição das {itemsParaRejeitar.length} marcação(ões) do dia selecionado.
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-5 py-4">
            <div className="grid gap-2">
              <Label htmlFor="motivo-rejeicao" className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                Motivo Principal
              </Label>
              <Select value={rejeitarMotivoPredefinido} onValueChange={setRejeitarMotivoPredefinido}>
                <SelectTrigger id="motivo-rejeicao">
                  <SelectValue placeholder="Selecione um motivo..." />
                </SelectTrigger>
                <SelectContent>
                  {MOTIVOS_REJEICAO.map((motivo) => (
                    <SelectItem key={motivo} value={motivo}>
                      {motivo}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="grid gap-2">
              <Label htmlFor="observacao-rejeicao" className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                {rejeitarMotivoPredefinido === "Outro" ? "Especifique o motivo" : "Observações Adicionais (opcional)"}
              </Label>
              <Textarea
                id="observacao-rejeicao"
                placeholder={rejeitarMotivoPredefinido === "Outro" ? "Descreva o motivo da rejeição..." : "Digite aqui observações adicionais sobre a rejeição..."}
                value={rejeitarObservacao}
                onChange={(e) => setRejeitarObservacao(e.target.value)}
                className="min-h-[80px]"
              />
            </div>
          </div>
          <DialogFooter className="gap-2 sm:gap-0">
            <Button variant="outline" onClick={() => setRejeitarDialogOpen(false)} disabled={processando}>
              Cancelar
            </Button>
            <Button variant="destructive" onClick={confirmarRejeicao} disabled={processando}>
              {processando ? "Processando..." : "Confirmar Rejeição"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Auto-lançamento: solicitante = aprovador (segregação de funções) */}
      <Dialog open={autoDialogOpen} onOpenChange={setAutoDialogOpen}>
        <DialogContent className="sm:max-w-[480px]">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <ShieldAlert className="w-4 h-4 text-amber-600" /> Justifique o auto-lançamento
            </DialogTitle>
            <DialogDescription>
              Você foi quem solicitou {itemsAutoAprovar.length} ajuste(s) deste dia. Para aprovar, registre a
              justificativa — ela fica gravada na auditoria (Portaria 671 MTP).
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-2 py-2">
            <Label htmlFor="obs-auto" className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              Justificativa (mínimo 10 caracteres)
            </Label>
            <Textarea
              id="obs-auto"
              placeholder="Ex.: Correção solicitada pelo colaborador por e-mail, com comprovante anexado."
              value={autoJustificativa}
              onChange={(e) => setAutoJustificativa(e.target.value)}
              className="min-h-[90px]"
            />
            <span className="text-[11px] text-muted-foreground">{autoJustificativa.trim().length}/10</span>
          </div>
          <DialogFooter className="gap-2 sm:gap-0">
            <Button variant="outline" onClick={() => setAutoDialogOpen(false)} disabled={processando}>
              Cancelar
            </Button>
            <Button onClick={confirmarAutoAprovacao} disabled={processando || autoJustificativa.trim().length < 10}>
              {processando ? "Processando..." : "Aprovar com justificativa"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </TooltipProvider>
  );
}
