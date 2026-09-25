import { useState, useMemo } from "react";
import {
  Eye,
  AlertTriangle,
  CheckCircle2,
  XCircle,
  Clock,
  TrendingUp,
  Users,
  FileWarning,
  Activity,
  RefreshCw,
  ChevronDown,
  ChevronUp,
  Info,
  Lock,
} from "lucide-react";
import { Link } from "react-router-dom";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useTenant } from "@/hooks/useTenant";
import { useTenantFeatures } from "@/hooks/useTenantFeatures";

/**
 * Sinais que dependem de um módulo que pode não estar no plano do cliente.
 * Quando o plano não inclui o módulo, o sinal aparece como "ative o módulo X"
 * em vez de um valor — vira gancho de upsell, sem alarme falso.
 */
const MODULO_POR_INDICADOR: Record<string, { feature: string; nome: string }> = {
  ocorrencias: { feature: "mod.cultura", nome: "Feedback & Ocorrências" },
  denuncias: { feature: "mod.cultura", nome: "Ouvidoria" },
  horas_excessivas: { feature: "mod.ponto", nome: "Ponto" },
};

interface IndicadorDeteccao {
  id: string;
  titulo: string;
  descricao: string;
  fator_nr01: string;
  fonte_dados: string;
  icone: React.ElementType;
  valor: number | null;
  limiar_atencao: number;
  limiar_critico: number;
  unidade: string;
  invertido?: boolean; // true = menor é pior
  status: "normal" | "atencao" | "critico" | "sem_dados";
  detalhe?: string;
  /** Preenchido quando o módulo-fonte do sinal não está no plano do cliente. */
  bloqueado?: { modulo: string; feature: string };
}

export function ChecklistDeteccaoObservavel() {
  const { tenantId } = useTenant();
  const { features, planGatingActive } = useTenantFeatures();
  const [expandido, setExpandido] = useState(false);

  // Buscar dados de múltiplas fontes do sistema
  const { data: dadosSistema, isLoading, refetch } = useQuery({
    queryKey: ["checklist-deteccao-observavel", tenantId],
    queryFn: async () => {
      if (!tenantId) return null;

      const agora = new Date();
      const tres_meses = new Date(agora);
      tres_meses.setMonth(tres_meses.getMonth() - 3);
      const seis_meses = new Date(agora);
      seis_meses.setMonth(seis_meses.getMonth() - 6);

      // Buscar dados em paralelo
      const [
        admissoes,
        desligamentos,
        atestados,
        afastamentos,
        ocorrencias,
        pontoData,
        ouvidoria,
      ] = await Promise.all([
        // Admissões nos últimos 6 meses (para calcular turnover)
        supabase
          .from("admissoes")
          .select("id, status, created_at", { count: "exact" })
          .eq("tenant_id", tenantId)
          .eq("status", "concluido")
          .gte("created_at", seis_meses.toISOString()),

        // Desligamentos nos últimos 6 meses
        supabase
          .from("admissoes")
          .select("id, status, data_desligamento", { count: "exact" })
          .eq("tenant_id", tenantId)
          .eq("status", "desligado")
          .gte("data_desligamento", seis_meses.toISOString()),

        // Atestados nos últimos 3 meses
        supabase
          .from("atestados")
          .select("id, dias_afastamento, grupo_clinico, data_emissao", { count: "exact" })
          .eq("tenant_id", tenantId)
          .gte("data_emissao", tres_meses.toISOString()),

        // Afastamentos ativos ou recentes
        supabase
          .from("afastamentos")
          .select("id, dias_totais, motivo_principal, status")
          .eq("tenant_id", tenantId)
          .in("status", ["ativo", "beneficio_inss"]),

        // Ocorrências (advertências)
        supabase
          .from("ocorrencias")
          .select("id, tipo, created_at", { count: "exact" })
          .eq("tenant_id", tenantId)
          .gte("created_at", tres_meses.toISOString()),

        // Horas extras via ponto
        supabase
          .from("ponto_diario")
          .select("id, horas_trabalhadas, status")
          .eq("tenant_id", tenantId)
          .gte("data", tres_meses.toISOString()),

        // Denúncias — buscar ocorrências com tipo negativo como proxy
        supabase
          .from("ocorrencias")
          .select("id, created_at", { count: "exact" })
          .eq("tenant_id", tenantId)
          .eq("tipo", "negativa")
          .gte("created_at", tres_meses.toISOString()),
      ]);

      // Total de colaboradores ativos
      const { count: totalColaboradores } = await supabase
        .from("admissoes")
        .select("id", { count: "exact", head: true })
        .eq("tenant_id", tenantId)
        .eq("status", "concluido");

      const total = totalColaboradores || 1;

      // Calcular taxa de turnover
      const desligCount = desligamentos.count || 0;
      const taxaTurnover = total > 0 ? Math.round((desligCount / total) * 100) : 0;

      // Atestados por transtorno mental (grupo_clinico = 'mental')
      const atestadosMentais = (atestados.data || []).filter(
        (a) => a.grupo_clinico === "mental"
      ).length;
      const taxaAtestadosMentais = total > 0
        ? Math.round((atestadosMentais / total) * 100)
        : 0;

      // Total dias de afastamento por saúde mental
      const diasAfastamentoMental = (afastamentos.data || [])
        .filter((a) => a.motivo_principal === "mental")
        .reduce((sum, a) => sum + (a.dias_totais || 0), 0);

      // Ocorrências (conflitos, advertências)
      const totalOcorrencias = ocorrencias.count || 0;

      // Denúncias
      const totalDenuncias = ouvidoria.count || 0;

      // Horas extras excessivas (>10h trabalhadas)
      const diasHoraExcessiva = (pontoData.data || []).filter((p) => {
        if (!p.horas_trabalhadas) return false;
        // horas_trabalhadas é interval string, ex "09:00:00"
        const parts = String(p.horas_trabalhadas).split(":");
        const hours = parseInt(parts[0] || "0");
        return hours >= 10;
      }).length;

      return {
        taxaTurnover,
        desligamentos: desligCount,
        totalColaboradores: total,
        atestadosMentais,
        taxaAtestadosMentais,
        diasAfastamentoMental,
        totalOcorrencias,
        totalDenuncias,
        diasHoraExcessiva,
        totalAtestados: atestados.count || 0,
      };
    },
    enabled: !!tenantId,
    staleTime: 5 * 60 * 1000,
  });

  const indicadores: IndicadorDeteccao[] = useMemo(() => {
    if (!dadosSistema) return [];

    const calcularStatus = (
      valor: number | null,
      limiarAtencao: number,
      limiarCritico: number,
      invertido?: boolean
    ): IndicadorDeteccao["status"] => {
      if (valor === null) return "sem_dados";
      if (invertido) {
        if (valor <= limiarCritico) return "critico";
        if (valor <= limiarAtencao) return "atencao";
        return "normal";
      }
      if (valor >= limiarCritico) return "critico";
      if (valor >= limiarAtencao) return "atencao";
      return "normal";
    };

    const base: IndicadorDeteccao[] = [
      {
        id: "turnover",
        titulo: "Taxa de Turnover (6m)",
        descricao: "Percentual de desligamentos em relação ao quadro ativo nos últimos 6 meses",
        fator_nr01: "R01, R02, R04",
        fonte_dados: "Admissões/Desligamentos",
        icone: Users,
        valor: dadosSistema.taxaTurnover,
        limiar_atencao: 10,
        limiar_critico: 20,
        unidade: "%",
        status: calcularStatus(dadosSistema.taxaTurnover, 10, 20),
        detalhe: `${dadosSistema.desligamentos} desligamento(s) de ${dadosSistema.totalColaboradores} colaboradores`,
      },
      {
        id: "atestados_mentais",
        titulo: "Atestados por Transtorno Mental (3m)",
        descricao: "Percentual de colaboradores com atestados por CID F (transtornos mentais)",
        fator_nr01: "R01, R03, R09, R10",
        fonte_dados: "Gestão de Atestados",
        icone: FileWarning,
        valor: dadosSistema.taxaAtestadosMentais,
        limiar_atencao: 3,
        limiar_critico: 8,
        unidade: "%",
        status: calcularStatus(dadosSistema.taxaAtestadosMentais, 3, 8),
        detalhe: `${dadosSistema.atestadosMentais} atestado(s) mental(is) de ${dadosSistema.totalAtestados} total`,
      },
      {
        id: "afastamento_mental",
        titulo: "Dias de Afastamento — Saúde Mental",
        descricao: "Total de dias de afastamento por motivos de saúde mental (ativos)",
        fator_nr01: "R09, R10, R13",
        fonte_dados: "Gestão de Afastamentos",
        icone: Activity,
        valor: dadosSistema.diasAfastamentoMental,
        limiar_atencao: 15,
        limiar_critico: 60,
        unidade: "dias",
        status: calcularStatus(dadosSistema.diasAfastamentoMental, 15, 60),
      },
      {
        id: "ocorrencias",
        titulo: "Ocorrências Disciplinares (3m)",
        descricao: "Total de advertências e ocorrências nos últimos 3 meses — pode indicar conflitos",
        fator_nr01: "R01, R05, R07",
        fonte_dados: "Gestão de Ocorrências",
        icone: AlertTriangle,
        valor: dadosSistema.totalOcorrencias,
        limiar_atencao: 5,
        limiar_critico: 15,
        unidade: "ocorrências",
        status: calcularStatus(dadosSistema.totalOcorrencias, 5, 15),
      },
      {
        id: "denuncias",
        titulo: "Denúncias e Reclamações (3m)",
        descricao: "Total de denúncias e reclamações na ouvidoria — sinalizador de assédio/violência",
        fator_nr01: "R01, R08",
        fonte_dados: "Ouvidoria",
        icone: AlertTriangle,
        valor: dadosSistema.totalDenuncias,
        limiar_atencao: 2,
        limiar_critico: 5,
        unidade: "registros",
        status: calcularStatus(dadosSistema.totalDenuncias, 2, 5),
      },
      {
        id: "horas_excessivas",
        titulo: "Dias com Jornada Excessiva (3m)",
        descricao: "Dias com 10+ horas trabalhadas — indica sobrecarga e fadiga",
        fator_nr01: "R09, R10, R13",
        fonte_dados: "Ponto Eletrônico",
        icone: Clock,
        valor: dadosSistema.diasHoraExcessiva,
        limiar_atencao: 20,
        limiar_critico: 50,
        unidade: "dias",
        status: calcularStatus(dadosSistema.diasHoraExcessiva, 20, 50),
      },
    ];

    // Sinais cujo módulo-fonte não está no plano viram "ative o módulo X":
    // status vira 'sem_dados' (não conta como crítico/atenção — sem alarme
    // falso) e ganham o rótulo de bloqueio. Fail-open: sem leitura de plano,
    // nada é bloqueado.
    return base.map((ind) => {
      const dep = MODULO_POR_INDICADOR[ind.id];
      if (dep && planGatingActive && !features.has(dep.feature)) {
        return { ...ind, status: "sem_dados" as const, bloqueado: { modulo: dep.nome, feature: dep.feature } };
      }
      return ind;
    });
  }, [dadosSistema, features, planGatingActive]);

  const contadores = useMemo(() => {
    return {
      critico: indicadores.filter((i) => i.status === "critico").length,
      atencao: indicadores.filter((i) => i.status === "atencao").length,
      normal: indicadores.filter((i) => i.status === "normal").length,
      semDados: indicadores.filter((i) => i.status === "sem_dados").length,
    };
  }, [indicadores]);

  const scorePct = useMemo(() => {
    const comDados = indicadores.filter((i) => i.status !== "sem_dados");
    if (comDados.length === 0) return null;
    const normais = comDados.filter((i) => i.status === "normal").length;
    return Math.round((normais / comDados.length) * 100);
  }, [indicadores]);

  const statusBadge = (status: IndicadorDeteccao["status"]) => {
    switch (status) {
      case "normal":
        return <Badge variant="outline" className="text-emerald-600 border-emerald-300 bg-emerald-50"><CheckCircle2 className="h-3 w-3 mr-1" />Normal</Badge>;
      case "atencao":
        return <Badge variant="outline" className="text-amber-600 border-amber-300 bg-amber-50"><AlertTriangle className="h-3 w-3 mr-1" />Atenção</Badge>;
      case "critico":
        return <Badge variant="destructive" className="gap-1"><XCircle className="h-3 w-3" />Crítico</Badge>;
      case "sem_dados":
        return <Badge variant="secondary" className="gap-1"><Info className="h-3 w-3" />Sem dados</Badge>;
    }
  };

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-violet-100">
              <Eye className="h-5 w-5 text-violet-600" />
            </div>
            <div>
              <CardTitle className="text-lg">Checklist de Detecção Observável</CardTitle>
              <CardDescription>
                Cruzamento automático de dados do sistema para identificar sinais de risco psicossocial (NR-01)
              </CardDescription>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {scorePct !== null && (
              <TooltipProvider>
                <Tooltip>
                  <TooltipTrigger>
                    <Badge
                      variant="outline"
                      className={
                        scorePct >= 80
                          ? "text-emerald-600 border-emerald-300 bg-emerald-50"
                          : scorePct >= 50
                          ? "text-amber-600 border-amber-300 bg-amber-50"
                          : "text-red-600 border-red-300 bg-red-50"
                      }
                    >
                      {scorePct}% OK
                    </Badge>
                  </TooltipTrigger>
                  <TooltipContent>
                    Percentual de indicadores dentro da normalidade
                  </TooltipContent>
                </Tooltip>
              </TooltipProvider>
            )}
            <Button
              variant="ghost"
              size="icon"
              className="h-8 w-8"
              onClick={() => refetch()}
              disabled={isLoading}
            >
              <RefreshCw className={`h-4 w-4 ${isLoading ? "animate-spin" : ""}`} />
            </Button>
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Resumo */}
        <div className="grid grid-cols-4 gap-3">
          <div className="text-center p-3 rounded-lg bg-red-50 border border-red-200">
            <p className="text-2xl font-bold text-red-600">{contadores.critico}</p>
            <p className="text-xs text-red-600">Crítico</p>
          </div>
          <div className="text-center p-3 rounded-lg bg-amber-50 border border-amber-200">
            <p className="text-2xl font-bold text-amber-600">{contadores.atencao}</p>
            <p className="text-xs text-amber-600">Atenção</p>
          </div>
          <div className="text-center p-3 rounded-lg bg-emerald-50 border border-emerald-200">
            <p className="text-2xl font-bold text-emerald-600">{contadores.normal}</p>
            <p className="text-xs text-emerald-600">Normal</p>
          </div>
          <div className="text-center p-3 rounded-lg bg-muted border">
            <p className="text-2xl font-bold text-muted-foreground">{contadores.semDados}</p>
            <p className="text-xs text-muted-foreground">Sem dados</p>
          </div>
        </div>

        {/* Indicadores prioritários (críticos/atenção sempre visíveis) */}
        <div className="space-y-2">
          {indicadores
            .filter((i) => i.status === "critico" || i.status === "atencao")
            .map((ind) => (
              <IndicadorCard key={ind.id} indicador={ind} statusBadge={statusBadge} />
            ))}
        </div>

        {/* Indicadores normais/sem dados (colapsável) */}
        <Collapsible open={expandido} onOpenChange={setExpandido}>
          <CollapsibleTrigger asChild>
            <Button variant="ghost" className="w-full gap-2 text-muted-foreground">
              {expandido ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
              {expandido ? "Ocultar" : "Ver todos"} os indicadores ({indicadores.filter(i => i.status === "normal" || i.status === "sem_dados").length})
            </Button>
          </CollapsibleTrigger>
          <CollapsibleContent className="space-y-2 pt-2">
            {indicadores
              .filter((i) => i.status === "normal" || i.status === "sem_dados")
              .map((ind) => (
                <IndicadorCard key={ind.id} indicador={ind} statusBadge={statusBadge} />
              ))}
          </CollapsibleContent>
        </Collapsible>
      </CardContent>
    </Card>
  );
}

function IndicadorCard({
  indicador,
  statusBadge,
}: {
  indicador: IndicadorDeteccao;
  statusBadge: (s: IndicadorDeteccao["status"]) => React.ReactNode;
}) {
  const Icon = indicador.icone;
  return (
    <div
      className={`flex items-center gap-4 p-3 rounded-lg border ${
        indicador.status === "critico"
          ? "border-red-200 bg-red-50/50"
          : indicador.status === "atencao"
          ? "border-amber-200 bg-amber-50/50"
          : "border-border bg-muted/30"
      }`}
    >
      <div className="flex-shrink-0">
        <Icon className="h-5 w-5 text-muted-foreground" />
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 flex-wrap">
          <p className="font-medium text-sm">{indicador.titulo}</p>
          {indicador.bloqueado ? (
            <Badge variant="outline" className="gap-1 text-muted-foreground">
              <Lock className="h-3 w-3" /> Módulo inativo
            </Badge>
          ) : (
            statusBadge(indicador.status)
          )}
        </div>
        <p className="text-xs text-muted-foreground mt-0.5">{indicador.descricao}</p>
        {indicador.detalhe && (
          <p className="text-xs text-muted-foreground/70 mt-0.5">{indicador.detalhe}</p>
        )}
        <div className="flex items-center gap-3 mt-1">
          <Badge variant="secondary" className="text-[10px] h-4 px-1.5">
            Fatores: {indicador.fator_nr01}
          </Badge>
          <span className="text-[10px] text-muted-foreground">Fonte: {indicador.fonte_dados}</span>
        </div>
      </div>
      <div className="flex-shrink-0 text-right">
        {indicador.bloqueado ? (
          <Link
            to="/meu-plano"
            className="text-xs font-medium text-primary hover:underline leading-tight inline-block"
            title={`Este sinal usa o módulo ${indicador.bloqueado.modulo}, que não está no plano atual.`}
          >
            Ative o módulo
            <br />
            {indicador.bloqueado.modulo}
          </Link>
        ) : (
          <>
            <p className="text-lg font-bold">
              {indicador.valor !== null ? indicador.valor : "—"}
            </p>
            <p className="text-[10px] text-muted-foreground">{indicador.unidade}</p>
          </>
        )}
      </div>
    </div>
  );
}