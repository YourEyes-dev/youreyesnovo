import { useState } from "react";
import { BookOpen, Info, Compass } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import { ARQUETIPO_LABEL, type Arquetipo } from "@/data/instrumentos/mapaComportamental";
import {
  GUIA_PERFIS,
  GUIA_ENQUADRAMENTO,
  GUIA_CAMADAS_MOTOR,
  GUIA_CAMADAS_MODO,
} from "@/data/mapaComportamentalGuia";

const ORDEM: Arquetipo[] = ["pioneiro", "conector", "guardiao", "estrategista"];

export function GuiaLiderTab() {
  const [arquetipo, setArquetipo] = useState<Arquetipo>("pioneiro");
  const perfil = GUIA_PERFIS[arquetipo];

  return (
    <div className="space-y-4">
      <Alert>
        <Info className="h-4 w-4" />
        <AlertDescription>{GUIA_ENQUADRAMENTO}</AlertDescription>
      </Alert>

      <div className="flex items-center gap-2 flex-wrap">
        <BookOpen className="w-5 h-5 text-indigo-600" />
        <span className="font-medium mr-2">Orientação por perfil:</span>
        {ORDEM.map((a) => (
          <Button
            key={a}
            size="sm"
            variant={a === arquetipo ? "default" : "outline"}
            onClick={() => setArquetipo(a)}
          >
            {ARQUETIPO_LABEL[a]}
          </Button>
        ))}
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            {ARQUETIPO_LABEL[perfil.arquetipo]}
            <Badge variant="secondary">{perfil.subtitulo}</Badge>
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {perfil.blocos.map((b) => (
            <div key={b.chave} className="border-l-2 border-indigo-200 pl-3">
              <p className="text-sm font-semibold">{b.titulo}</p>
              <p className="text-sm text-muted-foreground mt-0.5">{b.texto}</p>
            </div>
          ))}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <Compass className="w-4 h-4" /> Camadas complementares
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="text-xs text-muted-foreground">
            O Motor de Decisão e o Modo de Contexto ajustam a orientação acima — é isso que evita que o
            Guia vire horóscopo de quatro caixas.
          </p>
          <div>
            <p className="text-sm font-semibold mb-1">Pelo Motor de Decisão</p>
            <div className="space-y-2">
              {GUIA_CAMADAS_MOTOR.map((c) => (
                <div key={c.chave} className="text-sm">
                  <span className="font-medium">{c.titulo}:</span>{" "}
                  <span className="text-muted-foreground">{c.texto}</span>
                </div>
              ))}
            </div>
          </div>
          <div>
            <p className="text-sm font-semibold mb-1">Pelo Modo de Contexto e intensidade</p>
            <div className="space-y-2">
              {GUIA_CAMADAS_MODO.map((c) => (
                <div key={c.chave} className="text-sm">
                  <span className="font-medium">{c.titulo}:</span>{" "}
                  <span className="text-muted-foreground">{c.texto}</span>
                </div>
              ))}
            </div>
          </div>
        </CardContent>
      </Card>

      <p className={cn("text-xs text-muted-foreground text-center")}>
        Regra de redação: tudo em termos de tendência e preferência, nunca de capacidade. Nenhuma
        recomendação de promoção, desligamento ou mudança compulsória de função.
      </p>
    </div>
  );
}
