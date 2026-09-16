/**
 * Alertas de vencimento das férias (RF-009). Mostra o que o motor
 * (ferias_alertas_varrer) gerou: D-90/60/30 e risco de dobro, com o custo
 * estimado e o atalho para o Plano de Ação. O crítico já nasce com ação;
 * nos demais, o botão "Gerar ação" a cria sob demanda.
 */
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { RefreshCw, AlertTriangle, CalendarClock, CheckCircle2, ClipboardList } from "lucide-react";
import { useFeriasAlertas, type FeriasAlerta } from "@/hooks/useFeriasAlertas";

const fmtMoeda = (v: number) => v.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
const fmtData = (s: string | null) => (s ? new Date(s + "T12:00:00").toLocaleDateString("pt-BR") : "—");

const sevStyle: Record<FeriasAlerta["severidade"], string> = {
  critica: "bg-destructive/10 text-destructive border-destructive/20",
  alta: "bg-amber-500/10 text-amber-600 border-amber-500/20",
  media: "bg-sky-500/10 text-sky-600 border-sky-500/20",
};

const faixaLabel: Record<FeriasAlerta["faixa"], string> = {
  vencido: "Vencido — dobro",
  d30: "Vence em ≤ 30 dias",
  d60: "Vence em ≤ 60 dias",
  d90: "Vence em ≤ 90 dias",
};

export function FeriasAlertas() {
  const { alertas, isLoading, varrer, gerarAcao } = useFeriasAlertas();

  const criticos = alertas.filter((a) => a.tipo === "risco_dobro");
  const custoTotal = criticos.reduce((s, a) => s + (a.custo_estimado || 0), 0);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <CalendarClock className="w-5 h-5 text-primary" /> Alertas de vencimento
          </h3>
          <p className="text-sm text-muted-foreground">
            Períodos a vencer (D-90/60/30) e vencidos com risco de dobro (art. 137). Atualiza sozinho todo dia.
          </p>
        </div>
        <Button variant="outline" onClick={() => varrer.mutate()} disabled={varrer.isPending}>
          <RefreshCw className={`w-4 h-4 mr-2 ${varrer.isPending ? "animate-spin" : ""}`} />
          Atualizar agora
        </Button>
      </div>

      {criticos.length > 0 && (
        <Card className="border-destructive/30">
          <CardContent className="flex items-center gap-3 py-4">
            <AlertTriangle className="w-5 h-5 text-destructive shrink-0" />
            <div className="text-sm">
              <span className="font-semibold text-destructive">{criticos.length} período(s) vencido(s)</span> —
              passivo estimado de férias em dobro: <span className="font-semibold">{fmtMoeda(custoTotal)}</span>.
              Cada um já tem ação no Plano de Ação.
            </div>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm text-muted-foreground">
            {isLoading ? "Carregando..." : `${alertas.length} alerta(s) aberto(s)`}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {!isLoading && alertas.length === 0 && (
            <p className="text-sm text-muted-foreground py-6 text-center">
              Nenhum período a vencer nos próximos 90 dias. 🎉
            </p>
          )}
          {alertas.map((a) => (
            <div key={a.id} className="flex flex-wrap items-center gap-3 rounded-lg border p-3">
              <Badge variant="outline" className={sevStyle[a.severidade]}>{faixaLabel[a.faixa]}</Badge>
              <div className="flex-1 min-w-[180px]">
                <p className="text-sm font-medium">{a.colaborador_nome || a.colaborador_cpf}</p>
                <p className="text-xs text-muted-foreground">
                  Conceder até {fmtData(a.concessivo_fim)}
                  {a.custo_estimado ? ` · dobro estimado ${fmtMoeda(a.custo_estimado)}` : ""}
                </p>
              </div>
              {a.plano_acao_id ? (
                <span className="text-xs text-success flex items-center gap-1">
                  <CheckCircle2 className="w-3.5 h-3.5" /> No Plano de Ação
                </span>
              ) : (
                <Button size="sm" variant="outline" className="text-xs"
                  onClick={() => gerarAcao.mutate(a.id)} disabled={gerarAcao.isPending}>
                  <ClipboardList className="w-3.5 h-3.5 mr-1" /> Gerar ação
                </Button>
              )}
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  );
}
