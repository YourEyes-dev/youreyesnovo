import { useMemo, useState } from "react";
import {
  addMonths, eachDayOfInterval, endOfMonth, endOfYear, format, isSameDay, isSameMonth,
  startOfMonth, startOfWeek, endOfWeek, startOfYear,
} from "date-fns";
import { ptBR } from "date-fns/locale";
import { CalendarDays, ChevronLeft, ChevronRight, Lock } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { useCelebracoes } from "@/hooks/useCelebracoes";
import {
  GRUPO_LABELS, montarEventosCalendario, pessoaReservada,
  type EventoCalendario, type GrupoEvento,
} from "@/lib/celebracoes";
import { STATUS_ACAO_COLORS, STATUS_ACAO_LABELS } from "@/types/cultura";
import type { CulturaAcao, CulturaData, CulturaPreferencia, CulturaRitual } from "@/types/cultura";

interface Props {
  acoes: CulturaAcao[];
  rituais: CulturaRitual[];
  datas: CulturaData[];
  preferencias: CulturaPreferencia[];
}

const COR_PONTO: Record<string, string> = {
  aniversario: "bg-pink-500",
  tempo_casa: "bg-blue-500",
  dia_profissao: "bg-amber-500",
  acao: "bg-violet-500",
  data: "bg-violet-500",
  ritual: "bg-emerald-500",
};

const DIAS_SEMANA = ["seg", "ter", "qua", "qui", "sex", "sáb", "dom"];

export const CalendarioCelebracoes = ({ acoes, rituais, datas, preferencias }: Props) => {
  const { pessoas, config } = useCelebracoes({ exigirEmpresa: true });
  const [visao, setVisao] = useState<"mes" | "ano">("mes");
  const [ref, setRef] = useState(() => startOfMonth(new Date()));
  const [grupo, setGrupo] = useState<"todos" | GrupoEvento>("todos");
  const [diaAberto, setDiaAberto] = useState<Date | null>(null);

  const [inicio, fim] = useMemo(
    () => (visao === "mes" ? [startOfMonth(ref), endOfMonth(ref)] : [startOfYear(ref), endOfYear(ref)]),
    [visao, ref],
  );

  const eventos = useMemo(
    () => montarEventosCalendario({ pessoas, config, acoes, rituais, datas, de: inicio, ate: fim }),
    [pessoas, config, acoes, rituais, datas, inicio, fim],
  );
  const visiveis = grupo === "todos" ? eventos : eventos.filter((e) => e.grupo === grupo);

  const dias = useMemo(
    () => eachDayOfInterval({ start: startOfWeek(inicio, { weekStartsOn: 1 }), end: endOfWeek(fim, { weekStartsOn: 1 }) }),
    [inicio, fim],
  );
  const doDia = (d: Date) => visiveis.filter((e) => isSameDay(e.data, d));
  const hoje = new Date();

  const naoPublico = (e: EventoCalendario) =>
    e.grupo === "pessoas" && pessoaReservada(preferencias, e.celebracao?.pessoaId, e.acao?.colaborador_nome || e.titulo);

  const porMes = useMemo(() => {
    const m = Array.from({ length: 12 }, () => 0);
    visiveis.forEach((e) => { m[e.data.getMonth()]++; });
    return m;
  }, [visiveis]);
  const maxMes = Math.max(1, ...porMes);

  const titulo = visao === "mes" ? format(ref, "MMMM 'de' yyyy", { locale: ptBR }) : format(ref, "yyyy");
  const passo = (n: number) => setRef((r) => (visao === "mes" ? addMonths(r, n) : addMonths(r, 12 * n)));

  return (
    <Card data-testid="calendario-celebracoes">
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between gap-2 flex-wrap">
          <CardTitle className="text-base flex items-center gap-2">
            <CalendarDays className="h-4 w-4 text-primary" strokeWidth={1.75} /> Calendário
          </CardTitle>
          <div className="flex items-center gap-1 flex-wrap">
            {(["mes", "ano"] as const).map((v) => (
              <Button key={v} size="sm" variant={visao === v ? "default" : "outline"} className="h-7 text-xs" onClick={() => setVisao(v)}>
                {v === "mes" ? "Mês" : "Ano"}
              </Button>
            ))}
          </div>
        </div>
        <div className="flex items-center justify-between gap-2 flex-wrap pt-2">
          <div className="flex items-center gap-1">
            <Button size="icon" variant="ghost" className="h-7 w-7" aria-label="Anterior" onClick={() => passo(-1)}>
              <ChevronLeft className="h-4 w-4" />
            </Button>
            <span className="text-sm font-medium capitalize min-w-[9rem] text-center">{titulo}</span>
            <Button size="icon" variant="ghost" className="h-7 w-7" aria-label="Próximo" onClick={() => passo(1)}>
              <ChevronRight className="h-4 w-4" />
            </Button>
          </div>
          <div className="flex items-center gap-1 flex-wrap">
            {(Object.keys(GRUPO_LABELS) as Array<"todos" | GrupoEvento>).map((g) => (
              <Button key={g} size="sm" variant={grupo === g ? "secondary" : "ghost"} className="h-7 text-xs px-2" onClick={() => setGrupo(g)}>
                {GRUPO_LABELS[g]}
              </Button>
            ))}
          </div>
        </div>
      </CardHeader>
      <CardContent>
        {visao === "mes" ? (
          <div className="grid grid-cols-7 gap-px rounded-lg border bg-border overflow-hidden">
            {DIAS_SEMANA.map((d) => (
              <div key={d} className="bg-muted/50 py-1 text-center text-[10px] uppercase text-muted-foreground">{d}</div>
            ))}
            {dias.map((d) => {
              const evs = doDia(d);
              const foraDoMes = !isSameMonth(d, ref);
              return (
                <button
                  key={d.toISOString()}
                  type="button"
                  disabled={evs.length === 0}
                  onClick={() => setDiaAberto(d)}
                  aria-label={`${format(d, "dd/MM")}: ${evs.length} item(ns)`}
                  className={`min-w-0 min-h-[3.25rem] p-1 bg-background text-left flex flex-col items-start gap-1 transition-colors ${
                    foraDoMes ? "opacity-40" : ""
                  } ${evs.length ? "hover:bg-muted/60 cursor-pointer" : "cursor-default"} ${
                    isSameDay(d, hoje) ? "ring-1 ring-inset ring-primary" : ""
                  }`}
                >
                  <span className="text-xs">{format(d, "d")}</span>
                  <span className="flex items-center gap-0.5 flex-wrap">
                    {evs.slice(0, 3).map((e) => (
                      <span key={e.id} className={`h-1.5 w-1.5 rounded-full ${COR_PONTO[e.tipo] ?? "bg-violet-500"}`} />
                    ))}
                    {evs.length > 3 && <span className="text-[9px] text-muted-foreground leading-none">+{evs.length - 3}</span>}
                  </span>
                </button>
              );
            })}
          </div>
        ) : (
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-2" data-testid="calendario-ano">
            {porMes.map((n, i) => (
              <button
                key={i}
                type="button"
                onClick={() => { setRef(new Date(ref.getFullYear(), i, 1)); setVisao("mes"); }}
                className="rounded-lg border p-3 text-left hover:border-primary transition-colors"
                style={{ backgroundColor: n ? `hsl(var(--primary) / ${0.06 + (0.24 * n) / maxMes})` : undefined }}
              >
                <p className="text-xs capitalize text-muted-foreground">{format(new Date(ref.getFullYear(), i, 1), "MMMM", { locale: ptBR })}</p>
                <p className="text-lg font-semibold">{n}</p>
              </button>
            ))}
          </div>
        )}

        <div className="flex items-center gap-3 flex-wrap mt-3 text-[10px] text-muted-foreground">
          {[["aniversario", "Aniversário"], ["tempo_casa", "Tempo de casa"], ["dia_profissao", "Dia da profissão"], ["acao", "Ação / data"], ["ritual", "Ritual"]].map(([k, l]) => (
            <span key={k} className="flex items-center gap-1"><span className={`h-2 w-2 rounded-full ${COR_PONTO[k]}`} />{l}</span>
          ))}
        </div>
      </CardContent>

      <Sheet open={!!diaAberto} onOpenChange={(o) => !o && setDiaAberto(null)}>
        <SheetContent className="w-full sm:max-w-md overflow-y-auto">
          <SheetHeader>
            <SheetTitle className="capitalize">{diaAberto && format(diaAberto, "EEEE, dd 'de' MMMM", { locale: ptBR })}</SheetTitle>
            <SheetDescription>Itens deste dia</SheetDescription>
          </SheetHeader>
          <div className="space-y-2 mt-4">
            {(diaAberto ? doDia(diaAberto) : []).map((e) => (
              <div key={e.id} className="flex items-start gap-2 p-2 rounded-lg border">
                <span className={`mt-1.5 h-2 w-2 rounded-full shrink-0 ${COR_PONTO[e.tipo] ?? "bg-violet-500"}`} />
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-medium break-words">{e.titulo}</p>
                  <p className="text-xs text-muted-foreground">{e.detalhe}</p>
                  <div className="flex gap-1 flex-wrap mt-1">
                    {e.acao && (
                      <Badge className={`text-[10px] ${STATUS_ACAO_COLORS[e.acao.status] || ""}`}>
                        {STATUS_ACAO_LABELS[e.acao.status] || e.acao.status}
                      </Badge>
                    )}
                    {naoPublico(e) && (
                      <Badge variant="outline" className="text-[10px] gap-1"><Lock className="h-2.5 w-2.5" /> Reservado</Badge>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </SheetContent>
      </Sheet>
    </Card>
  );
};
