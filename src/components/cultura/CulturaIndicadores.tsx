import { useMemo } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { BarChart3, TrendingUp, Clock, Target } from "lucide-react";
import type { CulturaAcao, CulturaRitual } from "@/types/cultura";
import { differenceInDays, parseISO, isBefore, startOfDay } from "date-fns";
import { ShieldCheck } from "lucide-react";
import { useCelebracoes } from "@/hooks/useCelebracoes";
import { calcularCobertura } from "@/lib/celebracoes";

interface Props {
  acoes: CulturaAcao[];
  rituais: CulturaRitual[];
}

export const CulturaIndicadores = ({ acoes, rituais }: Props) => {
  const { pessoas } = useCelebracoes({ exigirEmpresa: true });
  const cobertura = useMemo(() => calcularCobertura(pessoas, acoes), [pessoas, acoes]);

  const indicadores = useMemo(() => {
    const total = acoes.length;
    const concluidas = acoes.filter(a => a.status === "concluida").length;
    const pendentes = acoes.filter(a => a.status === "pendente").length;
    const canceladas = acoes.filter(a => a.status === "cancelada").length;
    const emAndamento = acoes.filter(a => a.status === "em_andamento").length;

    // Taxa de celebrações realizadas
    const taxaRealizacao = total > 0 ? Math.round((concluidas / total) * 100) : 0;

    // Ações concluídas no prazo (data_execucao <= data_referencia ou sem data_execucao e concluída)
    const concluidasNoPrazo = acoes.filter(a => {
      if (a.status !== "concluida") return false;
      if (!a.data_execucao) return true; // sem data execução = no prazo
      return !isBefore(parseISO(a.data_referencia), parseISO(a.data_execucao));
    }).length;
    const taxaNoPrazo = concluidas > 0 ? Math.round((concluidasNoPrazo / concluidas) * 100) : 0;

    // Ações atrasadas (pendentes com data_referencia no passado)
    const hoje = startOfDay(new Date());
    const atrasadas = acoes.filter(a =>
      (a.status === "pendente" || a.status === "em_andamento") &&
      isBefore(parseISO(a.data_referencia), hoje)
    ).length;

    // Rituais ativos
    const rituaisAtivos = rituais.filter(r => r.ativo).length;
    const totalRituais = rituais.length;

    // Média de dias entre criação e conclusão
    const diasMedio = concluidas > 0
      ? Math.round(
          acoes
            .filter(a => a.status === "concluida" && a.data_execucao)
            .reduce((sum, a) => sum + Math.abs(differenceInDays(parseISO(a.data_execucao!), parseISO(a.created_at))), 0) /
          Math.max(acoes.filter(a => a.status === "concluida" && a.data_execucao).length, 1)
        )
      : 0;

    return {
      total, concluidas, pendentes, canceladas, emAndamento,
      taxaRealizacao, taxaNoPrazo, atrasadas, rituaisAtivos, totalRituais, diasMedio,
    };
  }, [acoes, rituais]);

  const cards = [
    {
      label: "Taxa de Realização",
      value: `${indicadores.taxaRealizacao}%`,
      desc: `${indicadores.concluidas} de ${indicadores.total} ações`,
      icon: Target,
      color: indicadores.taxaRealizacao >= 80 ? "text-emerald-600" : indicadores.taxaRealizacao >= 50 ? "text-amber-600" : "text-red-600",
    },
    {
      label: "Ações no Prazo",
      value: `${indicadores.taxaNoPrazo}%`,
      desc: "Concluídas dentro do prazo",
      icon: Clock,
      color: indicadores.taxaNoPrazo >= 80 ? "text-emerald-600" : "text-amber-600",
    },
    {
      label: "Ações Atrasadas",
      value: indicadores.atrasadas,
      desc: "Pendentes com data passada",
      icon: TrendingUp,
      color: indicadores.atrasadas === 0 ? "text-emerald-600" : "text-red-600",
    },
    {
      label: "Tempo Médio",
      value: `${indicadores.diasMedio}d`,
      desc: "Da criação à conclusão",
      icon: BarChart3,
      color: "text-blue-600",
    },
  ];

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <BarChart3 className="h-4 w-4 text-primary" strokeWidth={1.75} />
          Indicadores Culturais
        </CardTitle>
      </CardHeader>
      <CardContent>
        <div className="mb-4 pb-4 border-b" data-testid="cobertura-celebracao">
          <div className="flex items-center gap-3">
            <ShieldCheck className="h-8 w-8 text-primary shrink-0" strokeWidth={1.5} />
            <div className="min-w-0">
              <div className="flex items-baseline gap-2">
                <span className={`text-3xl font-bold ${cobertura.percentual >= 95 ? "text-emerald-600" : cobertura.percentual >= 70 ? "text-amber-600" : "text-red-600"}`}>
                  {cobertura.percentual}%
                </span>
                <span className="text-sm font-medium">Cobertura de celebração</span>
              </div>
              <p className="text-xs text-muted-foreground">
                {cobertura.cobertas} de {cobertura.total} colaboradores celebrados nos últimos 12 meses (só o registrado aqui)
              </p>
            </div>
          </div>
          {cobertura.semCelebracao.length > 0 && cobertura.total > 0 && (
            <details className="mt-2 text-xs">
              <summary className="cursor-pointer text-muted-foreground">
                Sem celebração há mais de 12 meses: {cobertura.semCelebracao.length} pessoa{cobertura.semCelebracao.length > 1 ? "s" : ""}
              </summary>
              <p className="mt-1 text-muted-foreground">
                {cobertura.semCelebracao.slice(0, 10).map((p) => p.nome_completo).join(", ")}
                {cobertura.semCelebracao.length > 10 && ` e mais ${cobertura.semCelebracao.length - 10}`}
              </p>
            </details>
          )}
        </div>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {cards.map((c) => (
            <div key={c.label} className="text-center">
              <div className={`text-2xl font-bold ${c.color}`}>{c.value}</div>
              <p className="text-xs font-medium text-foreground mt-1">{c.label}</p>
              <p className="text-[10px] text-muted-foreground">{c.desc}</p>
            </div>
          ))}
        </div>

        {/* Breakdown por tipo */}
        <div className="mt-4 pt-4 border-t grid grid-cols-2 md:grid-cols-4 gap-3 text-center">
          <div>
            <p className="text-lg font-semibold text-foreground">{indicadores.pendentes}</p>
            <p className="text-[10px] text-muted-foreground">Pendentes</p>
          </div>
          <div>
            <p className="text-lg font-semibold text-foreground">{indicadores.emAndamento}</p>
            <p className="text-[10px] text-muted-foreground">Em Andamento</p>
          </div>
          <div>
            <p className="text-lg font-semibold text-emerald-600">{indicadores.concluidas}</p>
            <p className="text-[10px] text-muted-foreground">Concluídas</p>
          </div>
          <div>
            <p className="text-lg font-semibold text-muted-foreground">{indicadores.canceladas}</p>
            <p className="text-[10px] text-muted-foreground">Canceladas</p>
          </div>
        </div>
      </CardContent>
    </Card>
  );
};
