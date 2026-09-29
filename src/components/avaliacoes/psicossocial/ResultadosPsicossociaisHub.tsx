import { useMemo, useState } from "react";
import { isEntrevistaInstrumento } from "@/types/psicossocial";
import { Card, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Badge } from "@/components/ui/badge";
import { LineChart, Users, Flame, MessagesSquare } from "lucide-react";
import { ResultadosPorGHEPanel } from "./ResultadosPorGHEPanel";
import { RadaresPsicossocialSection } from "./RadaresPsicossocialSection";
import { IPSHistoricoChart } from "./IPSHistoricoChart";
import { useEntrevistasGuiadasAggregates } from "@/hooks/useEntrevistasGuiadasAggregates";
import type { CampanhaPsicossocial } from "@/types/psicossocial";

interface Props {
  campanhas: CampanhaPsicossocial[];
}

const SUB_TABS = [
  { value: "ghe", label: "Por GHE", icon: Users, desc: "Resultados agrupados por Grupo Homogêneo de Exposição." },
  { value: "burnout", label: "Burnout & Boreout", icon: Flame, desc: "Indicadores de esgotamento e desengajamento." },
  { value: "historico", label: "Histórico IPS", icon: LineChart, desc: "Evolução do Índice Psicossocial ao longo do tempo." },
];

export function ResultadosPsicossociaisHub({ campanhas }: Props) {
  const [tab, setTab] = useState<string>("ghe");
  const current = SUB_TABS.find((t) => t.value === tab) ?? SUB_TABS[0];

  // Mescla agregados das entrevistas guiadas (resumo_ia) nas campanhas correspondentes,
  // promovendo ips_score / radar_data / total_respostas para que apareçam nos mesmos
  // filtros e gráficos dos questionários.
  const campanhasEntrevistaIds = useMemo(
    () => campanhas.filter(c =>isEntrevistaInstrumento((c as any).tipo_instrumento)).map(c => c.id),
    [campanhas]
  );
  const { agregadosPorCampanha } = useEntrevistasGuiadasAggregates(campanhasEntrevistaIds);

  const campanhasEnriquecidas = useMemo<CampanhaPsicossocial[]>(() => {
    if (agregadosPorCampanha.size === 0) return campanhas;
    return campanhas.map((c) => {
      const agg = agregadosPorCampanha.get(c.id);
      if (!agg) return c;
      return {
        ...c,
        ips_score: agg.ips_score ?? c.ips_score,
        radar_data: agg.radar_data.length > 0 ? agg.radar_data : c.radar_data,
        total_respostas: agg.total_concluidas || c.total_respostas,
      } as CampanhaPsicossocial;
    });
  }, [campanhas, agregadosPorCampanha]);

  const totalEntrevistas = agregadosPorCampanha.size;

  return (
    <div className="space-y-4">
      <Card className="border-purple-200/60 bg-gradient-to-r from-purple-50/60 to-fuchsia-50/40">
        <CardHeader className="pb-2">
          <CardTitle className="text-base font-semibold text-purple-900 flex items-center gap-2 flex-wrap">
            📊 Resultados Psicossociais
            {totalEntrevistas > 0 && (
              <Badge variant="outline" className="text-[10px] bg-white/70 border-purple-200 text-purple-700 gap-1">
                <MessagesSquare className="h-3 w-3" />
                {totalEntrevistas} entrevista{totalEntrevistas > 1 ? "s" : ""} guiada{totalEntrevistas > 1 ? "s" : ""} incluída{totalEntrevistas > 1 ? "s" : ""}
              </Badge>
            )}
          </CardTitle>
          <p className="text-sm text-muted-foreground">
            Tudo o que o gestor tático precisa para enxergar o clima psicossocial em um só lugar.
            Questionários e entrevistas guiadas aparecem no mesmo filtro.
          </p>
        </CardHeader>
      </Card>

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList className="grid grid-cols-1 sm:grid-cols-3 h-auto bg-muted/60 p-1">
          {SUB_TABS.map((t) => {
            const Icon = t.icon;
            return (
              <TabsTrigger
                key={t.value}
                value={t.value}
                className="flex items-center gap-2 data-[state=active]:bg-white data-[state=active]:shadow-sm py-2"
              >
                <Icon className="h-4 w-4" />
                <span className="text-sm font-medium">{t.label}</span>
              </TabsTrigger>
            );
          })}
        </TabsList>

        <p className="text-xs text-muted-foreground mt-2 px-1">{current.desc}</p>

        <TabsContent value="ghe" className="mt-4">
          <ResultadosPorGHEPanel />
        </TabsContent>

        <TabsContent value="burnout" className="mt-4">
          <RadaresPsicossocialSection campanhas={campanhasEnriquecidas} />
        </TabsContent>

        <TabsContent value="historico" className="mt-4">
          <IPSHistoricoChart campanhas={campanhasEnriquecidas} />
        </TabsContent>
      </Tabs>
    </div>
  );
}
