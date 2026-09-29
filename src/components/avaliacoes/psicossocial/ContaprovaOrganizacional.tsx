/**
 * Contraprova Organizacional
 * Cruza a percepção dos colaboradores (IPS do questionário) com
 * evidências operacionais de outros módulos do YourEyes:
 *  - Atestados / Afastamentos (saúde)
 *  - Jornada excessiva (ponto)
 *  - Bem-estar (registro contínuo)
 *  - Feedback & Ocorrências
 */
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuthContext } from "@/contexts/AuthContext";
import {
  AlertTriangle,
  CheckCircle2,
  Clock,
  Heart,
  MessageSquare,
  ShieldAlert,
  TrendingDown,
  TrendingUp,
  Minus,
  Info,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Progress } from "@/components/ui/progress";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { cn } from "@/lib/utils";
import type { CampanhaPsicossocial } from "@/types/psicossocial";

interface ContaprovaOrganizacionalProps {
  campanha: CampanhaPsicossocial;
  ips?: number;
}

interface EvidenciaItem {
  modulo: string;
  icone: React.ReactNode;
  titulo: string;
  valor: string | number;
  interpretacao: string;
  tendencia: "positiva" | "negativa" | "neutra" | "alerta";
  corrobora: boolean | null; // true=corrobora risco, false=contradiz, null=neutro
  detalhe?: string;
}

// Faixa de referência para classificar indicadores
function classificarJornada(mediaHorasExtras: number): "positiva" | "negativa" | "alerta" {
  if (mediaHorasExtras < 30) return "positiva";
  if (mediaHorasExtras < 60) return "alerta";
  return "negativa";
}

function classificarAfastamentos(taxa: number): "positiva" | "negativa" | "alerta" {
  if (taxa < 3) return "positiva";
  if (taxa < 8) return "alerta";
  return "negativa";
}

function classificarBemEstar(media: number): "positiva" | "negativa" | "alerta" {
  if (media >= 3.5) return "positiva";
  if (media >= 2.5) return "alerta";
  return "negativa";
}

function classificarOcorrencias(taxa: number): "positiva" | "negativa" | "alerta" {
  if (taxa < 5) return "positiva";
  if (taxa < 15) return "alerta";
  return "negativa";
}

export function ContaprovaOrganizacional({ campanha, ips }: ContaprovaOrganizacionalProps) {
  const { tenantId } = useAuthContext();

  // 1. Atestados / Afastamentos nos últimos 90 dias (período da campanha)
  const { data: dadosAtestados } = useQuery({
    queryKey: ["contraprova-atestados", tenantId, campanha.id],
    queryFn: async () => {
      if (!tenantId) return null;
      const dataRef = campanha.data_inicio || new Date(Date.now() - 90 * 86400000).toISOString().slice(0, 10);

      const [atestadosRes, afastamentosRes, totalColabRes] = await Promise.all([
        fromTable("atestados")
          .select("id, tipo, dias_afastamento, grupo_clinico, created_at")
          .eq("tenant_id", tenantId)
          .gte("created_at", dataRef)
          ,

        fromTable("afastamentos")
          .select("id, status, dias_totais, motivo_principal")
          .eq("tenant_id", tenantId)
          .gte("created_at", dataRef)
          ,

        supabase
          .from("profiles")
          .select("user_id", { count: "exact", head: true })
          .eq("tenant_id", tenantId),
      ]);

      const atestados = atestadosRes.data || [];
      const afastamentos = afastamentosRes.data || [];
      const totalColab = totalColabRes.count || 1;

      const totalAtestados = atestados.length;
      const diasAfastamento = afastamentos.reduce((acc, a) => acc + (a.dias_totais || 0), 0);
      const taxaAfastamento = (afastamentos.filter(a => a.status === "ativo").length / totalColab) * 100;
      const atestadosMentalSaude = atestados.filter(a =>
        a.grupo_clinico === "mental_comportamental"
      ).length;
      // Sem NENHUM registro de saúde no período: ausência de dado não é
      // evidência de ambiente saudável — o indicador precisa aparecer como
      // "sem dados" (neutro), nunca como "contradiz o risco".
      const semRegistrosSaude = atestados.length === 0 && afastamentos.length === 0;

      return { totalAtestados, diasAfastamento, taxaAfastamento, atestadosMentalSaude, totalColab, semRegistrosSaude };
    },
    enabled: !!tenantId,
  });

  // 2. Jornada excessiva — média de HE no período
  const { data: dadosJornada } = useQuery({
    queryKey: ["contraprova-jornada", tenantId, campanha.id],
    queryFn: async () => {
      if (!tenantId) return null;
      const dataRef = campanha.data_inicio || new Date(Date.now() - 90 * 86400000).toISOString().slice(0, 10);

      const { data } = await fromTable("ponto_diario")
        .select("horas_extras_50_minutos, horas_extras_100_minutos, atraso_minutos, status")
        .eq("tenant_id", tenantId)
        .gte("data", dataRef)
        ;

      const registros = data || [];
      if (registros.length === 0) return null;

      const totalHE = registros.reduce((acc, r) =>
        acc + (r.horas_extras_50_minutos || 0) + (r.horas_extras_100_minutos || 0), 0
      );
      const totalAtrasos = registros.reduce((acc, r) => acc + (r.atraso_minutos || 0), 0);
      const faltas = registros.filter(r => r.status === "falta").length;
      const mediaHEPorDia = registros.length > 0 ? totalHE / registros.length : 0;

      return { totalHE, mediaHEPorDia, totalAtrasos, faltas, totalRegistros: registros.length };
    },
    enabled: !!tenantId,
  });

  // 3. Bem-estar — média de scores recentes
  const { data: dadosBemEstar } = useQuery({
    queryKey: ["contraprova-bemestar", tenantId, campanha.id],
    queryFn: async () => {
      if (!tenantId) return null;
      const dataRef = campanha.data_inicio || new Date(Date.now() - 90 * 86400000).toISOString().slice(0, 10);

      const { data } = await supabase
        .from("bem_estar_respostas")
        .select("valor_numerico, eixo, created_at")
        .eq("tenant_id", tenantId)
        .gte("created_at", dataRef)
        .not("valor_numerico", "is", null);

      const registros = data || [];
      if (registros.length === 0) return null;

      const media = registros.reduce((acc, r) => acc + (r.valor_numerico || 0), 0) / registros.length;
      const totalRespostas = registros.length;

      // Por eixo
      const porEixo: Record<string, number[]> = {};
      registros.forEach(r => {
        if (!porEixo[r.eixo]) porEixo[r.eixo] = [];
        if (r.valor_numerico !== null) porEixo[r.eixo].push(r.valor_numerico);
      });

      const mediasPorEixo = Object.entries(porEixo).map(([eixo, valores]) => ({
        eixo,
        media: valores.reduce((a, b) => a + b, 0) / valores.length,
      })).sort((a, b) => a.media - b.media);

      return { media, totalRespostas, mediasPorEixo };
    },
    enabled: !!tenantId,
  });

  // 4. Ocorrências negativas e feedbacks de alinhamento
  const { data: dadosFeedback } = useQuery({
    queryKey: ["contraprova-feedback", tenantId, campanha.id],
    queryFn: async () => {
      if (!tenantId) return null;
      const dataRef = campanha.data_inicio || new Date(Date.now() - 90 * 86400000).toISOString().slice(0, 10);

      const [ocorrenciasRes, feedbacksRes] = await Promise.all([
        fromTable("ocorrencias")
          .select("id, tipo, is_advertencia")
          .eq("tenant_id", tenantId)
          .gte("created_at", dataRef)
          ,

        fromTable("feedbacks")
          .select("id, categoria")
          .eq("tenant_id", tenantId)
          .gte("created_at", dataRef)
          ,
      ]);

      const ocorrencias = ocorrenciasRes.data || [];
      const feedbacks = feedbacksRes.data || [];

      const ocorrenciasNegativas = ocorrencias.filter(o => o.tipo === "negativa").length;
      const advertencias = ocorrencias.filter(o => o.is_advertencia).length;
      const totalOcorrencias = ocorrencias.length;
      const feedbacksAlinhamento = feedbacks.filter(f => f.categoria === "alinhamento").length;
      const feedbacksReconhecimento = feedbacks.filter(f => f.categoria === "reconhecimento").length;
      const semRegistrosFeedback = ocorrencias.length === 0 && feedbacks.length === 0;

      return { ocorrenciasNegativas, advertencias, totalOcorrencias, feedbacksAlinhamento, feedbacksReconhecimento, semRegistrosFeedback };
    },
    enabled: !!tenantId,
  });

  // Construir evidências
  const evidencias: EvidenciaItem[] = [];

  // Atestados
  if (dadosAtestados) {
    if (dadosAtestados.semRegistrosSaude) {
      // Sem dado nenhum: não corrobora nem contradiz — apenas informa a lacuna.
      evidencias.push({
        modulo: "Saúde Organizacional",
        icone: <ShieldAlert className="h-4 w-4" />,
        titulo: "Taxa de Afastamentos",
        valor: "sem dados",
        interpretacao: "Nenhum atestado ou afastamento registrado no período",
        tendencia: "neutra",
        corrobora: null,
        detalhe: "Sem registros no módulo de Saúde Ocupacional para o período — não é possível corroborar nem contradizer o risco percebido.",
      });
    } else {
      const tendencia = classificarAfastamentos(dadosAtestados.taxaAfastamento);
      evidencias.push({
        modulo: "Saúde Organizacional",
        icone: <ShieldAlert className="h-4 w-4" />,
        titulo: "Taxa de Afastamentos",
        valor: `${dadosAtestados.taxaAfastamento.toFixed(1)}%`,
        interpretacao: tendencia === "positiva" ? "Baixa taxa de afastamentos" : tendencia === "alerta" ? "Taxa de afastamentos moderada" : "Alta taxa de afastamentos",
        tendencia: tendencia === "positiva" ? "positiva" : tendencia === "alerta" ? "neutra" : "negativa",
        corrobora: tendencia === "negativa" ? true : tendencia === "alerta" ? null : false,
        detalhe: `${dadosAtestados.totalAtestados} atestados · ${dadosAtestados.diasAfastamento} dias afastados`,
      });
    }

    if (dadosAtestados.atestadosMentalSaude > 0) {
      evidencias.push({
        modulo: "Saúde Organizacional",
        icone: <Heart className="h-4 w-4" />,
        titulo: "Atestados por Saúde Mental",
        valor: dadosAtestados.atestadosMentalSaude,
        interpretacao: dadosAtestados.atestadosMentalSaude >= 3 ? "Volume relevante de afastamentos por saúde mental" : "Ocorrências pontuais de saúde mental",
        tendencia: dadosAtestados.atestadosMentalSaude >= 3 ? "alerta" : "neutra",
        corrobora: dadosAtestados.atestadosMentalSaude >= 3 ? true : null,
        detalhe: "Atestados classificados como Transtornos Mentais e Comportamentais (CID F)",
      });
    }
  }

  // Jornada
  if (dadosJornada) {
    const tendencia = classificarJornada(dadosJornada.mediaHEPorDia);
    evidencias.push({
      modulo: "Jornada & Ponto",
      icone: <Clock className="h-4 w-4" />,
      titulo: "Média de Horas Extras / Dia",
      valor: `${dadosJornada.mediaHEPorDia.toFixed(0)} min/dia`,
      interpretacao: tendencia === "positiva" ? "Jornada dentro do esperado" : tendencia === "alerta" ? "Sinais de sobrecarga moderada" : "Jornada excessiva detectada",
      tendencia: tendencia === "positiva" ? "positiva" : tendencia === "alerta" ? "neutra" : "negativa",
      corrobora: tendencia === "negativa" ? true : tendencia === "alerta" ? null : false,
      detalhe: `${dadosJornada.totalHE} min totais · ${dadosJornada.faltas} faltas registradas`,
    });
  }

  // Bem-estar
  if (dadosBemEstar) {
    const tendencia = classificarBemEstar(dadosBemEstar.media);
    evidencias.push({
      modulo: "Meu Bem-Estar",
      icone: <Heart className="h-4 w-4" />,
      titulo: "Média Bem-Estar (1-5)",
      valor: dadosBemEstar.media.toFixed(1),
      interpretacao: tendencia === "positiva" ? "Autoavaliação de bem-estar positiva" : tendencia === "alerta" ? "Bem-estar moderado — atenção recomendada" : "Autoavaliação de bem-estar baixa",
      tendencia: tendencia === "positiva" ? "positiva" : tendencia === "alerta" ? "neutra" : "negativa",
      corrobora: tendencia === "negativa" ? true : tendencia === "alerta" ? null : false,
      detalhe: `${dadosBemEstar.totalRespostas} registros. Eixo mais crítico: ${dadosBemEstar.mediasPorEixo[0]?.eixo || "—"}`,
    });
  }

  // Feedback / Ocorrências
  if (dadosFeedback) {
    if (dadosFeedback.semRegistrosFeedback) {
      evidencias.push({
        modulo: "Feedback & Ocorrências",
        icone: <MessageSquare className="h-4 w-4" />,
        titulo: "Ocorrências Negativas",
        valor: "sem dados",
        interpretacao: "Nenhuma ocorrência ou feedback registrado no período",
        tendencia: "neutra",
        corrobora: null,
        detalhe: "Sem registros no módulo de Feedback & Ocorrências para o período.",
      });
    } else {
      const tendencia = classificarOcorrencias(dadosFeedback.ocorrenciasNegativas);
      evidencias.push({
        modulo: "Feedback & Ocorrências",
        icone: <MessageSquare className="h-4 w-4" />,
        titulo: "Ocorrências Negativas",
        valor: dadosFeedback.ocorrenciasNegativas,
        interpretacao: tendencia === "positiva" ? "Poucas ocorrências negativas" : tendencia === "alerta" ? "Volume moderado de ocorrências negativas" : "Alto volume de ocorrências negativas",
        tendencia: tendencia === "positiva" ? "positiva" : tendencia === "alerta" ? "neutra" : "negativa",
        corrobora: tendencia === "negativa" ? true : null,
        detalhe: `${dadosFeedback.advertencias} advertências · ${dadosFeedback.feedbacksReconhecimento} reconhecimentos registrados`,
      });
    }
  }

  // Nenhuma evidência carregada ainda
  const carregando = !dadosAtestados && !dadosJornada && !dadosBemEstar && !dadosFeedback;
  const semDados = evidencias.length === 0;

  // Calcular alinhamento geral
  const evidenciasComResultado = evidencias.filter(e => e.corrobora !== null);
  const corroboram = evidenciasComResultado.filter(e => e.corrobora === true).length;
  const alinhamento = evidenciasComResultado.length > 0
    ? Math.round((corroboram / evidenciasComResultado.length) * 100)
    : null;

  const getBadgeTendencia = (t: EvidenciaItem["tendencia"]) => {
    switch (t) {
      case "positiva": return <Badge variant="outline" className="text-[hsl(var(--chart-2))] border-[hsl(var(--chart-2)/0.4)] text-xs">✓ Saudável</Badge>;
      case "alerta": return <Badge variant="outline" className="text-[hsl(var(--chart-5))] border-[hsl(var(--chart-5)/0.4)] text-xs">⚠ Atenção</Badge>;
      case "negativa": return <Badge variant="outline" className="text-destructive border-destructive/40 text-xs">✗ Crítico</Badge>;
      default: return <Badge variant="outline" className="text-muted-foreground text-xs">– Neutro</Badge>;
    }
  };

  return (
    <div className="space-y-4">
      {/* Cabeçalho explicativo */}
      <Alert className="border-blue-200 bg-blue-50/40">
        <Info className="h-4 w-4 text-blue-600" />
        <AlertDescription className="text-sm text-blue-800">
          <strong>Contraprova Organizacional:</strong> Cruza a percepção dos trabalhadores (IPS = {ips ?? "—"})
          com evidências operacionais de outros módulos para validar ou questionar os resultados do questionário.
        </AlertDescription>
      </Alert>

      {/* Indicador de alinhamento geral */}
      {alinhamento !== null && (
        <Card className={cn(
          "border",
          alinhamento >= 60 ? "border-red-200 bg-red-50/30" :
          alinhamento >= 30 ? "border-amber-200 bg-amber-50/30" :
          "border-emerald-200 bg-emerald-50/30"
        )}>
          <CardContent className="pt-4">
            <div className="flex items-center justify-between mb-2">
              <div>
                <p className="font-semibold text-sm">
                  {alinhamento >= 60
                    ? "Evidências corroboram o risco percebido"
                    : alinhamento >= 30
                    ? "Evidências parcialmente alinhadas com a percepção"
                    : "Evidências organizacionais contradizem o risco percebido"}
                </p>
                <p className="text-xs text-muted-foreground mt-0.5">
                  {corroboram} de {evidenciasComResultado.length} indicadores apontam risco real
                </p>
              </div>
              <div className="text-right">
                <span className={cn("text-2xl font-bold",
                  alinhamento >= 60 ? "text-red-600" :
                  alinhamento >= 30 ? "text-amber-600" : "text-emerald-600"
                )}>{alinhamento}%</span>
                <p className="text-xs text-muted-foreground">alinhamento</p>
              </div>
            </div>
            <Progress
              value={alinhamento}
              className="h-2"
            />
          </CardContent>
        </Card>
      )}

      {/* Grid de evidências */}
      {carregando ? (
        <div className="text-center py-8 text-muted-foreground text-sm">
          Carregando evidências dos módulos...
        </div>
      ) : semDados ? (
        <div className="text-center py-8 text-muted-foreground text-sm">
          Nenhuma evidência encontrada no período da campanha.
        </div>
      ) : (
        <div className="grid gap-3">
          {evidencias.map((ev, idx) => (
            <Card key={idx} className={cn(
              "border transition-colors",
              ev.tendencia === "negativa" ? "border-red-100 bg-red-50/20" :
              ev.tendencia === "alerta" ? "border-amber-100 bg-amber-50/20" :
              ev.tendencia === "positiva" ? "border-emerald-100 bg-emerald-50/20" :
              "border-border"
            )}>
              <CardContent className="p-4">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex items-start gap-3 flex-1 min-w-0">
                    <div className={cn("mt-0.5 shrink-0",
                      ev.tendencia === "negativa" ? "text-red-600" :
                      ev.tendencia === "alerta" ? "text-amber-600" :
                      ev.tendencia === "positiva" ? "text-emerald-600" :
                      "text-muted-foreground"
                    )}>
                      {ev.icone}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="text-xs text-muted-foreground">{ev.modulo}</span>
                        <span className="text-xs text-muted-foreground">·</span>
                        <span className="text-sm font-medium">{ev.titulo}</span>
                      </div>
                      <div className="flex items-center gap-2 mt-1">
                        <span className={cn("text-xl font-bold",
                          ev.tendencia === "negativa" ? "text-red-600" :
                          ev.tendencia === "alerta" ? "text-amber-600" :
                          ev.tendencia === "positiva" ? "text-emerald-600" :
                          "text-foreground"
                        )}>
                          {ev.valor}
                        </span>
                        {getBadgeTendencia(ev.tendencia)}
                      </div>
                      <p className="text-sm text-muted-foreground mt-1">{ev.interpretacao}</p>
                      {ev.detalhe && (
                        <p className="text-xs text-muted-foreground mt-0.5 opacity-75">{ev.detalhe}</p>
                      )}
                    </div>
                  </div>

                  {/* Ícone de corroboração */}
                  <div className="shrink-0 mt-1">
                    {ev.corrobora === true ? (
                      <div className="flex flex-col items-center gap-0.5">
                        <TrendingDown className="h-4 w-4 text-red-500" />
                        <span className="text-xs text-red-500 whitespace-nowrap">Corrobora</span>
                        <span className="text-xs text-red-500">risco</span>
                      </div>
                    ) : ev.corrobora === false ? (
                      <div className="flex flex-col items-center gap-0.5">
                        <TrendingUp className="h-4 w-4 text-emerald-500" />
                        <span className="text-xs text-emerald-500 whitespace-nowrap">Contradiz</span>
                        <span className="text-xs text-emerald-500">risco</span>
                      </div>
                    ) : (
                      <div className="flex flex-col items-center gap-0.5">
                        <Minus className="h-4 w-4 text-muted-foreground" />
                        <span className="text-xs text-muted-foreground">Neutro</span>
                      </div>
                    )}
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* Legenda */}
      <Card className="bg-muted/30 border-dashed">
        <CardContent className="pt-3 pb-3">
          <p className="text-xs text-muted-foreground leading-relaxed">
            <strong>Como interpretar:</strong> Quando evidências operacionais <strong>corroboram</strong> o IPS baixo,
            o risco é confirmado. Quando <strong>contradizem</strong>, pode haver viés de percepção ou problema
            localizado em grupos específicos. Ambos os cenários requerem análise aprofundada.
            Os dados são do período da campanha ({campanha.data_inicio?.slice(0, 10)} → {campanha.data_fim?.slice(0, 10)}).
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
