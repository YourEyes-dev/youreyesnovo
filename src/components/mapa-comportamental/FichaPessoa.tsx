import { ArrowLeft, BookOpen } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { ResultadoMapa } from "./ResultadoMapa";
import { useVerMapa } from "@/hooks/useMapaComportamentalTime";
import { ARQUETIPO_LABEL, type Arquetipo } from "@/data/instrumentos/mapaComportamental";
import { GUIA_PERFIS } from "@/data/mapaComportamentalGuia";

interface Props {
  mapaId: string;
  nome?: string | null;
  onVoltar: () => void;
}

export function FichaPessoa({ mapaId, nome, onVoltar }: Props) {
  const { data: ficha, isLoading, error } = useVerMapa(mapaId);

  const primario = (ficha?.arquetipo?.split("-")[0] ?? null) as Arquetipo | null;
  const guia = primario && GUIA_PERFIS[primario] ? GUIA_PERFIS[primario] : null;

  return (
    <div className="space-y-4">
      <Button variant="ghost" size="sm" className="gap-1" onClick={onVoltar}>
        <ArrowLeft className="w-4 h-4" /> Voltar ao time
      </Button>

      {nome && <h3 className="text-lg font-semibold">{nome}</h3>}

      {isLoading ? (
        <Skeleton className="h-64 max-w-2xl mx-auto" />
      ) : error || !ficha?.resultado ? (
        <Alert>
          <AlertDescription>Não foi possível abrir este mapa (ou ainda não há resultado).</AlertDescription>
        </Alert>
      ) : (
        <>
          <ResultadoMapa resultado={ficha.resultado} concluidoEm={ficha.concluido_em} />

          {guia && (
            <Card className="max-w-2xl mx-auto">
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-base">
                  <BookOpen className="w-4 h-4" /> Como liderar um {ARQUETIPO_LABEL[guia.arquetipo]}
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                {guia.blocos
                  .filter((b) => ["feedback", "motiva", "delegar", "cobrar", "precisa"].includes(b.chave))
                  .map((b) => (
                    <div key={b.chave} className="border-l-2 border-indigo-200 pl-3">
                      <p className="text-sm font-semibold">{b.titulo}</p>
                      <p className="text-sm text-muted-foreground mt-0.5">{b.texto}</p>
                    </div>
                  ))}
                <p className="text-xs text-muted-foreground">
                  Orientação de estilo para adaptar a sua liderança — não é medida de competência. Veja a
                  aba Guia do Líder para o conteúdo completo.
                </p>
              </CardContent>
            </Card>
          )}
        </>
      )}
    </div>
  );
}
