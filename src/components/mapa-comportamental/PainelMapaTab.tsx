import { Users, ShieldAlert, BarChart3 } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { useMapaComportamentalPainel } from "@/hooks/useMapaComportamental";
import { ARQUETIPO_LABEL, type Arquetipo } from "@/data/instrumentos/mapaComportamental";

export function PainelMapaTab() {
  const { data, isLoading, error } = useMapaComportamentalPainel(true);

  if (isLoading) {
    return (
      <div className="grid gap-3 sm:grid-cols-3">
        <Skeleton className="h-28" />
        <Skeleton className="h-28" />
        <Skeleton className="h-28" />
      </div>
    );
  }

  if (error || !data) {
    return (
      <Alert>
        <AlertDescription>Não foi possível carregar o painel agora.</AlertDescription>
      </Alert>
    );
  }

  if (data.suprimido) {
    return (
      <Alert>
        <ShieldAlert className="h-4 w-4" />
        <AlertDescription>
          Ainda não há mapas suficientes para uma visão agregada. Para preservar a privacidade, os
          números por área só aparecem a partir de {data.minimo_respondentes} respondentes válidos.
          {typeof data.total_concluidos === "number" && (
            <span className="block mt-1 text-xs opacity-80">
              Mapas concluídos até agora: {data.total_concluidos}.
            </span>
          )}
        </AlertDescription>
      </Alert>
    );
  }

  const dist = data.distribuicao_arquetipos ?? {};
  const totalDist = Object.values(dist).reduce((a, b) => a + b, 0) || 1;

  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-3">
        <StatCard icon={<Users className="w-5 h-5" />} titulo="Mapas concluídos" valor={String(data.total_concluidos)} />
        <StatCard
          icon={<BarChart3 className="w-5 h-5" />}
          titulo="Consistência média"
          valor={data.consistencia_media == null ? "—" : data.consistencia_media.toFixed(2)}
          hint="0 = respostas totalmente coerentes"
        />
        <StatCard
          icon={<ShieldAlert className="w-5 h-5" />}
          titulo="Baixa confiabilidade"
          valor={String(data.confiabilidade_baixa ?? 0)}
          hint="não entram nos indicadores"
        />
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Distribuição de arquétipos</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          {Object.entries(dist).length === 0 && (
            <p className="text-sm text-muted-foreground">Sem dados de arquétipo ainda.</p>
          )}
          {Object.entries(dist).map(([arq, qt]) => {
            const label = ARQUETIPO_LABEL[arq as Arquetipo] ?? arq;
            const pct = Math.round((qt / totalDist) * 100);
            return (
              <div key={arq}>
                <div className="flex items-center justify-between text-sm mb-1">
                  <span className="flex items-center gap-2">
                    <Badge variant="secondary">{label}</Badge>
                  </span>
                  <span className="text-muted-foreground">{qt} ({pct}%)</span>
                </div>
                <div className="h-2 w-full rounded-full bg-muted overflow-hidden">
                  <div className="h-full bg-violet-500/70" style={{ width: `${pct}%` }} />
                </div>
              </div>
            );
          })}
          <p className="text-xs text-muted-foreground pt-2">
            Leitura de composição do time — orienta o desenvolvimento e a adaptação da gestão. Não é
            critério de admissão, promoção, remuneração, realocação ou desligamento.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}

function StatCard({
  icon,
  titulo,
  valor,
  hint,
}: {
  icon: React.ReactNode;
  titulo: string;
  valor: string;
  hint?: string;
}) {
  return (
    <Card>
      <CardContent className="pt-6">
        <div className="flex items-center gap-2 text-muted-foreground text-sm">
          {icon}
          {titulo}
        </div>
        <div className="text-3xl font-bold mt-2">{valor}</div>
        {hint && <p className="text-xs text-muted-foreground mt-1">{hint}</p>}
      </CardContent>
    </Card>
  );
}
