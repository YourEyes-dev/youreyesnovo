import { useMemo, useState } from "react";
import { Users, ChevronRight, ShieldAlert } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { useMapaTime, type TimeMembro } from "@/hooks/useMapaComportamentalTime";
import { FichaPessoa } from "./FichaPessoa";
import { ARQUETIPO_LABEL, type Arquetipo } from "@/data/instrumentos/mapaComportamental";

export function MapaTimeTab() {
  const { data: membros = [], isLoading } = useMapaTime(true);
  const [selecionado, setSelecionado] = useState<TimeMembro | null>(null);

  const distribuicao = useMemo(() => {
    const acc: Record<string, number> = {};
    for (const m of membros) {
      const primario = m.arquetipo?.split("-")[0] ?? "indefinido";
      acc[primario] = (acc[primario] ?? 0) + 1;
    }
    return acc;
  }, [membros]);

  if (selecionado) {
    return (
      <FichaPessoa
        mapaId={selecionado.mapa_id}
        nome={selecionado.nome}
        onVoltar={() => setSelecionado(null)}
      />
    );
  }

  if (isLoading) {
    return (
      <div className="space-y-3">
        <Skeleton className="h-20" />
        <Skeleton className="h-40" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <Alert>
        <ShieldAlert className="h-4 w-4" />
        <AlertDescription>
          Leitura de composição para orientar o desenvolvimento e adaptar a gestão. Não é critério de
          admissão, promoção, remuneração, realocação ou desligamento. Abrir a ficha de alguém registra
          o acesso, que a pessoa pode consultar.
        </AlertDescription>
      </Alert>

      {membros.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          Ainda não há mapas concluídos para exibir.
        </p>
      ) : (
        <>
          <Card>
            <CardHeader>
              <CardTitle className="text-base flex items-center gap-2">
                <Users className="w-4 h-4" /> Composição ({membros.length} mapa(s))
              </CardTitle>
            </CardHeader>
            <CardContent className="flex flex-wrap gap-2">
              {Object.entries(distribuicao).map(([arq, qt]) => (
                <Badge key={arq} variant="secondary">
                  {ARQUETIPO_LABEL[arq as Arquetipo] ?? arq}: {qt}
                </Badge>
              ))}
            </CardContent>
          </Card>

          <div className="space-y-2">
            {membros.map((m) => {
              const primario = m.arquetipo?.split("-")[0] as Arquetipo | undefined;
              return (
                <button
                  key={m.mapa_id}
                  type="button"
                  onClick={() => setSelecionado(m)}
                  className="w-full flex items-center justify-between gap-3 rounded-lg border border-input p-3 text-left hover:bg-accent transition-colors"
                >
                  <div className="min-w-0">
                    <p className="font-medium truncate">{m.nome ?? "—"}</p>
                    <p className="text-xs text-muted-foreground">
                      {m.concluido_em ? new Date(m.concluido_em).toLocaleDateString("pt-BR") : ""}
                      {m.confiabilidade === "baixa" ? " · baixa confiabilidade" : ""}
                    </p>
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    {m.arquetipo && (
                      <Badge variant="outline">
                        {primario && ARQUETIPO_LABEL[primario] ? ARQUETIPO_LABEL[primario] : m.arquetipo}
                      </Badge>
                    )}
                    <ChevronRight className="w-4 h-4 text-muted-foreground" />
                  </div>
                </button>
              );
            })}
          </div>
        </>
      )}
    </div>
  );
}
