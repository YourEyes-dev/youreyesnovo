import { useState } from "react";
import { Fingerprint, PlayCircle, RotateCcw } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Send } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Eye } from "lucide-react";
import { useMapaComportamental } from "@/hooks/useMapaComportamental";
import { useMinhaCampanhaPendente } from "@/hooks/useMapaComportamentalCampanhas";
import { useMeusAcessos } from "@/hooks/useMapaComportamentalTime";
import { AvisoTratamento, AVISO_TRATAMENTO_VERSAO } from "./AvisoTratamento";
import { ResponderMapa } from "./ResponderMapa";
import { ResultadoMapa } from "./ResultadoMapa";
import type { MapaResultado, MapaRespostas } from "@/data/instrumentos/mapaComportamental";

type Fase = "inicio" | "aviso" | "respondendo" | "resultado";

export function MeuMapaTab() {
  const { mapaAtual, rascunho, isLoading, salvarRascunho, concluir } = useMapaComportamental();
  const { data: campanhaPendente } = useMinhaCampanhaPendente();
  const [fase, setFase] = useState<Fase | null>(null);
  const [resultadoRecem, setResultadoRecem] = useState<MapaResultado | null>(null);
  const [continuando, setContinuando] = useState(false);

  if (isLoading) {
    return (
      <div className="max-w-2xl mx-auto space-y-3">
        <Skeleton className="h-28 w-full" />
        <Skeleton className="h-40 w-full" />
      </div>
    );
  }

  // Resultado recém-concluído tem prioridade.
  if (fase === "resultado" && resultadoRecem) {
    return (
      <ResultadoMapa
        resultado={resultadoRecem}
        onRefazer={() => {
          setResultadoRecem(null);
          setContinuando(false);
          setFase("aviso");
        }}
      />
    );
  }

  if (fase === "aviso") {
    return (
      <AvisoTratamento
        onAceitar={() => setFase("respondendo")}
        onCancelar={() => setFase(null)}
      />
    );
  }

  if (fase === "respondendo") {
    return (
      <ResponderMapa
        respostasIniciais={continuando ? (rascunho?.respostas as MapaRespostas) : undefined}
        onAutosave={(r) => salvarRascunho.mutate(r)}
        onPausar={() => setFase(null)}
        concluindo={concluir.isPending}
        onConcluir={async (respostas, tempo) => {
          const r = await concluir.mutateAsync({
            respostas,
            avisoVersao: AVISO_TRATAMENTO_VERSAO,
            tempoTotalSegundos: tempo,
            campanhaId: campanhaPendente?.campanha_id ?? null,
          });
          setResultadoRecem(r);
          setFase("resultado");
        }}
      />
    );
  }

  // Estado padrão: já tem mapa concluído → mostra; senão, convida a começar.
  if (mapaAtual?.resultado) {
    return (
      <div className="space-y-4">
        <ResultadoMapa
          resultado={mapaAtual.resultado}
          concluidoEm={mapaAtual.concluido_em}
          onRefazer={() => {
            setContinuando(false);
            setFase("aviso");
          }}
        />
        <div className="max-w-2xl mx-auto">
          <MeusAcessos />
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto space-y-4">
      {campanhaPendente && (
        <Alert>
          <Send className="h-4 w-4" />
          <AlertDescription>
            Você foi convidado para a campanha <strong>{campanhaPendente.nome}</strong>
            {campanhaPendente.data_fim
              ? ` (até ${new Date(campanhaPendente.data_fim).toLocaleDateString("pt-BR")})`
              : ""}. Responder é voluntário.
          </AlertDescription>
        </Alert>
      )}
      <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Fingerprint className="w-5 h-5 text-indigo-600" />
          {rascunho ? "Você tem um mapa em andamento" : "Descubra o seu mapa"}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <p className="text-sm text-muted-foreground">
          São 28 perguntas rápidas sobre o seu jeito de trabalhar. Ao final, você vê o seu resultado
          na hora, em linguagem de desenvolvimento — só para você.
        </p>
        <div className="flex flex-wrap gap-3">
          {rascunho ? (
            <>
              <Button
                className="gap-1"
                onClick={() => {
                  setContinuando(true);
                  setFase("respondendo");
                }}
              >
                <PlayCircle className="w-4 h-4" /> Continuar de onde parei
              </Button>
              <Button
                variant="outline"
                className="gap-1"
                onClick={() => {
                  setContinuando(false);
                  setFase("aviso");
                }}
              >
                <RotateCcw className="w-4 h-4" /> Recomeçar
              </Button>
            </>
          ) : (
            <Button className="gap-1" onClick={() => setFase("aviso")}>
              <PlayCircle className="w-4 h-4" /> Começar
            </Button>
          )}
        </div>
      </CardContent>
      </Card>
    </div>
  );
}

// Transparência ao titular: quem acessou o próprio mapa (CA-009 / RF-013).
function MeusAcessos() {
  const { data: acessos = [], isLoading } = useMeusAcessos();
  if (isLoading) return null;
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base">
          <Eye className="w-4 h-4" /> Quem viu o seu mapa
        </CardTitle>
      </CardHeader>
      <CardContent>
        {acessos.length === 0 ? (
          <p className="text-sm text-muted-foreground">Ninguém abriu o seu mapa até agora.</p>
        ) : (
          <ul className="space-y-1 text-sm">
            {acessos.map((a, i) => (
              <li key={i} className="flex items-center justify-between">
                <span>{a.acessado_por_nome ?? "—"}</span>
                <span className="text-muted-foreground text-xs">
                  {new Date(a.acessado_em).toLocaleString("pt-BR")}
                </span>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}
