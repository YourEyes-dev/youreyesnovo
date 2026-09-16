import { useState, useMemo, useEffect } from "react";
import {
  CalendarRange, Search, Pencil, CheckCircle2, Lock, AlertTriangle, Send,
  LayoutGrid, GanttChartSquare,
  Clock, Loader2, Plus, Info,
} from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import {
  useFeriasProgramacao, type LinhaProgramacao, type SubPeriodo, type EstadoProg,
} from "@/hooks/useFeriasProgramacao";
import { formatBRL } from "@/lib/feriasFinanceiro";
import {
  avaliarRegrasProgramacao, temBloqueio,
  type ViolacaoRegra,
} from "@/lib/feriasRegras";
import { FeriasTimeline } from "./FeriasTimeline";
import { cn } from "@/lib/utils";
import { toast } from "sonner";
import { useAuth } from "@/hooks/useAuth";

const ESTADO_LABEL: Record<EstadoProg, { label: string; cls: string }> = {
  sugerido:   { label: "Sugerido",   cls: "bg-slate-100 text-slate-700" },
  planejado:  { label: "Planejado",  cls: "bg-blue-100 text-blue-700" },
  confirmado: { label: "Confirmado", cls: "bg-emerald-100 text-emerald-700" },
  ciente:     { label: "Ciente",     cls: "bg-teal-100 text-teal-700" },
  solicitado: { label: "Solicitado", cls: "bg-violet-100 text-violet-700" },
  aprovado:   { label: "Aprovado",   cls: "bg-green-100 text-green-700" },
  em_gozo:    { label: "Em gozo",    cls: "bg-sky-100 text-sky-700" },
  concluido:  { label: "Concluído",  cls: "bg-gray-100 text-gray-600" },
  cancelado:  { label: "Cancelado",  cls: "bg-red-100 text-red-700" },
};

const fmtData = (iso: string | null) =>
  iso ? new Date(iso + "T12:00:00").toLocaleDateString("pt-BR") : "—";

export function FeriasProgramacao() {
  const prog = useFeriasProgramacao();
  const [busca, setBusca] = useState("");
  const [filtroRisco, setFiltroRisco] = useState<"todos" | "ok" | "alerta" | "vencido">("todos");
  const [editando, setEditando] = useState<LinhaProgramacao | null>(null);
  const [visao, setVisao] = useState<"grade" | "timeline">("grade");

  // Reposiciona um sub-período (novo início, mesma duração), revalida e salva.
  const moverPeriodo = (linha: LinhaProgramacao, n: 1 | 2 | 3, novoInicio: string) => {
    // Período que já virou solicitação/aprovação não pode mudar de data pela
    // timeline: a solicitação formal na aba Solicitações ficaria com a data
    // antiga, e as duas telas divergiriam. Trava aqui, além do draggable da UI.
    if (["solicitado","aprovado","em_gozo","concluido"].includes(linha.estado)) {
      toast.error("Período já solicitado", {
        description: "Altere pela aba Solicitações para manter as duas telas em sincronia.",
      });
      return;
    }
    const key = `p${n}` as "p1" | "p2" | "p3";
    const sub = linha[key];
    if (!sub.dias) return;
    const ini = new Date(novoInicio + "T12:00:00");
    const fim = new Date(ini);
    fim.setDate(fim.getDate() + sub.dias - 1);
    const fimIso = `${fim.getFullYear()}-${String(fim.getMonth() + 1).padStart(2, "0")}-${String(fim.getDate()).padStart(2, "0")}`;
    const atualizada: LinhaProgramacao = {
      ...linha,
      [key]: { inicio: novoInicio, fim: fimIso, dias: sub.dias },
    };
    // Revalida pelas regras; bloqueio impede o movimento.
    const viol = avaliarRegrasProgramacao({
      aquisitivoFim: atualizada.aquisitivoFim, saldo: atualizada.saldo,
      p1: atualizada.p1, p2: atualizada.p2, p3: atualizada.p3,
      abonoVender: atualizada.abonoVender, abonoDias: atualizada.abonoDias,
      limiteConcessivo: atualizada.limiteConcessivoDate,
      contexto: {
        feriados: atualizada.feriados,
        feriasFamiliares: atualizada.feriasFamiliares,
        afastamentoReinicia: atualizada.afastamentoReinicia,
      },
    });
    if (temBloqueio(viol)) {
      toast.error("Movimento inválido", { description: viol.find(v => v.comportamento === "bloqueio")?.mensagem });
      return;
    }
    prog.salvar.mutate(atualizada);
  };

  const filtradas = useMemo(() => {
    const q = busca.trim().toLowerCase();
    return prog.linhas.filter(l => {
      if (filtroRisco !== "todos" && l.risco !== filtroRisco) return false;
      if (!q) return true;
      return l.nome.toLowerCase().includes(q) || l.departamento.toLowerCase().includes(q);
    });
  }, [prog.linhas, busca, filtroRisco]);

  const resumo = useMemo(() => {
    const total = prog.linhas.length;
    const programados = prog.linhas.filter(l => l.diasProgramados > 0).length;
    const vencendo = prog.linhas.filter(l => l.risco !== "ok").length;
    return { total, programados, vencendo, cobertura: total > 0 ? Math.round((programados / total) * 100) : 0 };
  }, [prog.linhas]);

  if (prog.isLoading) {
    return (
      <div className="flex items-center justify-center py-16 text-muted-foreground">
        <Loader2 className="h-5 w-5 animate-spin mr-2" /> Carregando programação...
      </div>
    );
  }

  if (!prog.temSaldos) {
    return (
      <Card>
        <CardContent className="py-16 text-center text-muted-foreground">
          <CalendarRange className="h-8 w-8 mx-auto mb-3 opacity-40" />
          <p className="text-sm font-medium">Programação indisponível</p>
          <p className="text-xs mt-1 max-w-sm mx-auto">
            A grade usa o saldo real de cada colaborador. Importe os saldos na aba Saldos para
            montar o plano anual.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      {/* Resumo */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
        <MiniCard label="Colaboradores" valor={String(resumo.total)} />
        <MiniCard label="Com programação" valor={String(resumo.programados)} />
        <MiniCard label="Cobertura" valor={`${resumo.cobertura}%`} tom={resumo.cobertura >= 70 ? "ok" : "neutro"} />
        <MiniCard label="Vencendo / vencidas" valor={String(resumo.vencendo)} tom={resumo.vencendo > 0 ? "alerta" : "neutro"} />
      </div>

      <div className="flex items-start gap-2 rounded-lg border border-blue-200 bg-blue-50/60 p-3 text-xs text-blue-800">
        <Info className="h-4 w-4 mt-0.5 shrink-0" />
        <p>
          Monte o plano de férias de 12 meses. Saldo e valor vêm do cálculo real (abas Saldos e
          Financeiro). As datas são validadas contra a CLT ao programar (art. 130, 134, 135, 137,
          143, 145). Três regras — feriado, vínculo familiar e afastamento — dependem de
          configuração ainda pendente.
        </p>
      </div>

      {/* Filtros */}
      <div className="flex items-center gap-2 flex-wrap">
        <div className="relative flex-1 min-w-[220px]">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <Input placeholder="Buscar colaborador ou departamento..." value={busca}
            onChange={e => setBusca(e.target.value)} className="pl-9" />
        </div>
        <Select value={filtroRisco} onValueChange={(v) => setFiltroRisco(v as typeof filtroRisco)}>
          <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="todos">Todos os prazos</SelectItem>
            <SelectItem value="vencido">Vencidas</SelectItem>
            <SelectItem value="alerta">Vencendo (90d)</SelectItem>
            <SelectItem value="ok">No prazo</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {/* Alternador de visão */}
      <div className="flex items-center gap-1 rounded-lg border p-0.5 w-fit">
        <Button size="sm" variant={visao === "grade" ? "secondary" : "ghost"}
          className="h-7 gap-1.5 text-xs" onClick={() => setVisao("grade")}>
          <LayoutGrid className="h-3.5 w-3.5" /> Grade
        </Button>
        <Button size="sm" variant={visao === "timeline" ? "secondary" : "ghost"}
          className="h-7 gap-1.5 text-xs" onClick={() => setVisao("timeline")}>
          <GanttChartSquare className="h-3.5 w-3.5" /> Linha do tempo
        </Button>
      </div>

      {visao === "timeline" ? (
        <FeriasTimeline linhas={filtradas} onMover={(l, sub, novoInicio) => moverPeriodo(l, sub, novoInicio)} />
      ) : (
      /* Grade */
      <Card>
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-xs text-muted-foreground">
                <tr className="text-left">
                  <th className="px-3 py-2.5 font-medium sticky left-0 bg-muted/50 z-10">Colaborador</th>
                  <th className="px-3 py-2.5 font-medium">Aquisitivo</th>
                  <th className="px-3 py-2.5 font-medium text-center">Saldo</th>
                  <th className="px-3 py-2.5 font-medium">Limite</th>
                  <th className="px-3 py-2.5 font-medium">Programação</th>
                  <th className="px-3 py-2.5 font-medium text-center">Não prog.</th>
                  <th className="px-3 py-2.5 font-medium text-right">Valor est.</th>
                  <th className="px-3 py-2.5 font-medium">Status</th>
                  <th className="px-3 py-2.5 font-medium text-center">Ações</th>
                </tr>
              </thead>
              <tbody>
                {filtradas.map(l => {
                  const est = ESTADO_LABEL[l.estado];
                  const travado = ["confirmado","solicitado","aprovado","em_gozo","concluido"].includes(l.estado);
                  return (
                    <tr key={l.cpf + l.aquisitivoInicio} className="border-t hover:bg-accent/30">
                      <td className="px-3 py-2 sticky left-0 bg-background z-10">
                        <div className="font-medium">{l.nome}</div>
                        <div className="text-[11px] text-muted-foreground">
                          {l.departamento}{l.temPeriodosAnteriores && (
                            <Badge variant="outline" className="ml-1 text-[9px] px-1 py-0 border-amber-300 text-amber-700">
                              +1 período
                            </Badge>
                          )}
                        </div>
                      </td>
                      <td className="px-3 py-2 whitespace-nowrap text-xs">
                        {fmtData(l.aquisitivoInicio)} — {fmtData(l.aquisitivoFim)}
                      </td>
                      <td className="px-3 py-2 text-center font-semibold">{l.saldo}d</td>
                      <td className="px-3 py-2 whitespace-nowrap">
                        <RiscoBadge risco={l.risco} dias={l.diasParaVencimento} label={l.limiteConcessivo} />
                      </td>
                      <td className="px-3 py-2 text-xs">
                        <ProgResumo l={l} />
                      </td>
                      <td className="px-3 py-2 text-center">
                        {l.diasNaoProgramados > 0
                          ? <span className="text-amber-600 font-medium">{l.diasNaoProgramados}d</span>
                          : <span className="text-emerald-600">0d</span>}
                      </td>
                      <td className="px-3 py-2 text-right text-xs">
                        {l.valorEstimado > 0 ? formatBRL(l.valorEstimado) : "—"}
                      </td>
                      <td className="px-3 py-2">
                        <Badge className={cn("text-[10px]", est.cls)}>{est.label}</Badge>
                      </td>
                      <td className="px-3 py-2">
                        <div className="flex items-center justify-center gap-1">
                          <Button size="sm" variant="ghost" className="h-7 w-7 p-0"
                            onClick={() => setEditando(l)}>
                            {travado ? <Lock className="h-3.5 w-3.5" /> : <Pencil className="h-3.5 w-3.5" />}
                          </Button>
                          {l.estado === "planejado" && l.diasProgramados > 0 && l.progId && (
                            <Button size="sm" variant="ghost" className="h-7 w-7 p-0 text-emerald-600"
                              onClick={() => prog.confirmar.mutate(l.progId!)}
                              title="Confirmar programação">
                              <CheckCircle2 className="h-3.5 w-3.5" />
                            </Button>
                          )}
                          {l.estado === "confirmado" && (
                            <Button size="sm" variant="ghost" className="h-7 w-7 p-0 text-violet-600"
                              onClick={() => prog.converter.mutate(l)}
                              disabled={prog.converter.isPending}
                              title="Converter em solicitação">
                              <Send className="h-3.5 w-3.5" />
                            </Button>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })}
                {filtradas.length === 0 && (
                  <tr><td colSpan={9} className="px-3 py-10 text-center text-muted-foreground text-sm">
                    Nenhum colaborador para este filtro.
                  </td></tr>
                )}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>
      )}

      {editando && (
        <EditarProgramacaoDialog
          linha={editando}
          onOpenChange={(o) => !o && setEditando(null)}
          onSalvar={(atualizada) => {
            prog.salvar.mutate(atualizada, { onSuccess: () => setEditando(null) });
          }}
          salvando={prog.salvar.isPending}
        />
      )}
    </div>
  );
}

function MiniCard({ label, valor, tom = "neutro" }: {
  label: string; valor: string; tom?: "ok" | "alerta" | "neutro";
}) {
  return (
    <div className={cn("rounded-lg border p-3",
      tom === "ok" && "border-emerald-200 bg-emerald-50/40",
      tom === "alerta" && "border-red-200 bg-red-50/40")}>
      <div className="text-xl font-bold">{valor}</div>
      <div className="text-[10px] text-muted-foreground">{label}</div>
    </div>
  );
}

function RiscoBadge({ risco, dias, label }: { risco: string; dias: number; label: string }) {
  if (risco === "vencido")
    return <Badge className="bg-red-100 text-red-700 text-[10px] gap-1"><AlertTriangle className="h-2.5 w-2.5" />Vencida</Badge>;
  if (risco === "alerta")
    return <span className="text-[11px] text-amber-600 flex items-center gap-1"><Clock className="h-3 w-3" />{dias}d · {label}</span>;
  return <span className="text-[11px] text-muted-foreground">{label}</span>;
}

function ProgResumo({ l }: { l: LinhaProgramacao }) {
  const partes: string[] = [];
  if (l.p1.dias) partes.push(`P1 ${l.p1.dias}d`);
  if (l.p2.dias) partes.push(`P2 ${l.p2.dias}d`);
  if (l.p3.dias) partes.push(`P3 ${l.p3.dias}d`);
  if (l.abonoDias) partes.push(`Abono ${l.abonoDias}d`);
  if (partes.length === 0) return <span className="text-muted-foreground italic">não programado</span>;
  return (
    <div className="space-y-0.5">
      <div>{partes.join(" · ")}</div>
      {l.p1.inicio && <div className="text-[10px] text-muted-foreground">a partir de {fmtData(l.p1.inicio)}</div>}
    </div>
  );
}

// ── Modal de edição ─────────────────────────────────────────────────────────

function EditarProgramacaoDialog({ linha, onOpenChange, onSalvar, salvando }: {
  linha: LinhaProgramacao;
  onOpenChange: (o: boolean) => void;
  onSalvar: (l: LinhaProgramacao) => void;
  salvando: boolean;
}) {
  const [l, setL] = useState<LinhaProgramacao>(linha);
  useEffect(() => setL(linha), [linha]);

  const { roles } = useAuth();
  const podeAutorizar = roles.some(r => ["admin", "owner", "superadmin"].includes(r));

  const travado = ["confirmado","solicitado","aprovado","em_gozo","concluido"].includes(l.estado);

  // Concessivo (art. 134): algum sub-período começa depois do limite?
  const concessivoExcedido = [l.p1, l.p2, l.p3].some(
    s => s.inicio && new Date(s.inicio + "T12:00:00") > l.limiteConcessivoDate,
  );

  // Recalcula dias de um sub-período pelas datas
  const setSub = (n: 1 | 2 | 3, patch: Partial<SubPeriodo>) => {
    const key = `p${n}` as "p1" | "p2" | "p3";
    const atual = { ...l[key], ...patch };
    if (atual.inicio && atual.fim) {
      const d1 = new Date(atual.inicio + "T12:00:00");
      const d2 = new Date(atual.fim + "T12:00:00");
      atual.dias = d2 >= d1 ? Math.round((d2.getTime() - d1.getTime()) / 86400000) + 1 : null;
    } else {
      atual.dias = null;
    }
    setL({ ...l, [key]: atual });
  };

  const totalProg = (l.p1.dias ?? 0) + (l.p2.dias ?? 0) + (l.p3.dias ?? 0) + (l.abonoVender ? l.abonoDias : 0);

  // Motor de regras (3B): avalia em tempo real conforme o RH edita as datas.
  const violacoes = useMemo<ViolacaoRegra[]>(
    () => avaliarRegrasProgramacao({
      aquisitivoFim: l.aquisitivoFim,
      saldo: l.saldo,
      p1: l.p1, p2: l.p2, p3: l.p3,
      abonoVender: l.abonoVender,
      abonoDias: l.abonoDias,
      limiteConcessivo: l.limiteConcessivoDate,
      autorizadoExcecao: l.autorizadoExcecao,
      valorEstimado: l.valorEstimado,
      contexto: {
        feriados: l.feriados,
        feriasFamiliares: l.feriasFamiliares,
        afastamentoReinicia: l.afastamentoReinicia,
      },
    }),
    [l.aquisitivoFim, l.saldo, l.p1, l.p2, l.p3, l.abonoVender, l.abonoDias, l.limiteConcessivoDate,
     l.autorizadoExcecao, l.valorEstimado, l.feriados, l.feriasFamiliares, l.afastamentoReinicia],
  );
  const bloqueado = temBloqueio(violacoes);
  const temProgramacao = totalProg > 0;

  return (
    <Dialog open onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[88vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{l.nome}</DialogTitle>
          <DialogDescription>
            Saldo {l.saldo}d · aquisitivo {fmtData(l.aquisitivoInicio)}–{fmtData(l.aquisitivoFim)} ·
            limite {l.limiteConcessivo}
          </DialogDescription>
        </DialogHeader>

        {travado && (
          <div className="flex items-start gap-2 rounded-lg border border-amber-200 bg-amber-50/60 p-2.5 text-xs text-amber-800">
            <Lock className="h-4 w-4 mt-0.5 shrink-0" />
            <p>Programação {ESTADO_LABEL[l.estado].label.toLowerCase()} — alteração exigiria justificativa. Nesta etapa a edição está bloqueada.</p>
          </div>
        )}

        <div className={cn("space-y-3", travado && "opacity-60 pointer-events-none")}>
          {[1, 2, 3].map(n => {
            const key = `p${n}` as "p1" | "p2" | "p3";
            const sub = l[key];
            return (
              <div key={n} className="rounded-lg border p-3 space-y-2">
                <div className="flex items-center justify-between">
                  <Label className="text-xs font-semibold">Período {n}{n === 1 ? " (≥ 14 dias)" : " (≥ 5 dias)"}</Label>
                  {sub.dias ? <Badge variant="secondary" className="text-[10px]">{sub.dias} dias</Badge> : null}
                </div>
                <div className="grid grid-cols-2 gap-2">
                  <div>
                    <Label className="text-[10px] text-muted-foreground">Início</Label>
                    <Input type="date" value={sub.inicio ?? ""}
                      onChange={e => setSub(n as 1|2|3, { inicio: e.target.value || null })} />
                  </div>
                  <div>
                    <Label className="text-[10px] text-muted-foreground">Fim</Label>
                    <Input type="date" value={sub.fim ?? ""}
                      onChange={e => setSub(n as 1|2|3, { fim: e.target.value || null })} />
                  </div>
                </div>
              </div>
            );
          })}

          <div className="rounded-lg border p-3 space-y-2">
            <div className="flex items-center justify-between">
              <Label className="text-xs font-semibold">Abono pecuniário (vender até 1/3)</Label>
              <Switch checked={l.abonoVender} onCheckedChange={v => setL({ ...l, abonoVender: v })} />
            </div>
            {l.abonoVender && (
              <div>
                <Label className="text-[10px] text-muted-foreground">Dias vendidos</Label>
                <Input type="number" min="0" max="10" value={l.abonoDias}
                  onChange={e => setL({ ...l, abonoDias: Number(e.target.value) })} />
              </div>
            )}
          </div>

          <div className="flex items-center justify-between rounded-lg border p-3">
            <Label className="text-xs">Adiantar 13º junto às férias</Label>
            <Switch checked={l.adiantar13} onCheckedChange={v => setL({ ...l, adiantar13: v })} />
          </div>
        </div>

        {/* Concessivo vencido (art. 134/137): alçada de diretoria */}
        {concessivoExcedido && !travado && (
          <div className={cn(
            "flex items-start gap-2 rounded-lg border p-2.5 text-xs",
            l.autorizadoExcecao ? "border-amber-200 bg-amber-50/60 text-amber-800"
                                : "border-red-200 bg-red-50/60 text-red-700",
          )}>
            <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
            <div className="flex-1 space-y-1.5">
              <p className="font-medium">Programação além do limite concessivo (art. 134)</p>
              <p className="opacity-90">
                As férias deviam ser concedidas até {l.limiteConcessivo}. Prosseguir assume o
                pagamento <strong>em dobro</strong> (art. 137){l.valorEstimado > 0
                  ? <> — custo estimado da dobra: <strong>{formatBRL(l.valorEstimado)}</strong></>
                  : null}.
              </p>
              {podeAutorizar ? (
                <label className="flex items-center gap-2 pt-0.5">
                  <Switch checked={l.autorizadoExcecao}
                    onCheckedChange={v => setL({ ...l, autorizadoExcecao: v })} />
                  <span>Autorizar a exceção (alçada de diretoria) e assumir a dobra</span>
                </label>
              ) : (
                <p className="opacity-80">Somente a diretoria (admin ou acima) pode autorizar esta exceção.</p>
              )}
            </div>
          </div>
        )}

        {/* Violações do motor de regras (3B) */}
        {violacoes.length > 0 && (
          <div className="space-y-1.5">
            {violacoes.map((viol, i) => {
              const estilo =
                viol.comportamento === "bloqueio" ? "border-red-200 bg-red-50/60 text-red-700"
                : viol.comportamento === "alerta" ? "border-amber-200 bg-amber-50/60 text-amber-800"
                : "border-blue-200 bg-blue-50/60 text-blue-800";
              const Icone =
                viol.comportamento === "bloqueio" ? Lock
                : viol.comportamento === "alerta" ? AlertTriangle : Info;
              return (
                <div key={i} className={cn("flex items-start gap-2 rounded-lg border p-2 text-xs", estilo)}>
                  <Icone className="h-3.5 w-3.5 mt-0.5 shrink-0" />
                  <div>
                    <span className="font-medium">{viol.regra}</span>{" "}
                    <span className="opacity-70">({viol.baseLegal})</span>
                    <p className="opacity-90">{viol.mensagem}</p>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        <div className={cn("flex items-center justify-between rounded-lg p-2.5 text-sm",
          bloqueado ? "bg-red-50 text-red-700" : "bg-muted/50")}>
          <span>Total programado</span>
          <span className="font-semibold">{totalProg}d de {l.saldo}d</span>
        </div>

        <DialogFooter className="flex-col sm:flex-row gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button disabled={salvando || travado || bloqueado || !temProgramacao}
            onClick={() => onSalvar({ ...l, estado: l.estado === "sugerido" ? "planejado" : l.estado })}
            className="gap-2">
            {salvando && <Loader2 className="h-4 w-4 animate-spin" />}
            Salvar programação
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
