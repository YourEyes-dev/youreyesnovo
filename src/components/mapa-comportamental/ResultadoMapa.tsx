import { Sparkles, RefreshCw, Info, AlertTriangle } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Alert, AlertDescription } from "@/components/ui/alert";
import {
  ARQUETIPO_LABEL,
  MOTOR_LABEL,
  MODO_LABEL,
  type MapaResultado,
  type Arquetipo,
  type Motor,
} from "@/data/instrumentos/mapaComportamental";

// Descrições em linguagem de tendência/preferência — nunca de capacidade (RN-010).
const ARQUETIPO_RESUMO: Record<Arquetipo, string> = {
  pioneiro:
    "Tende a ir direto ao resultado, decide rápido e lida bem com risco e novidade. Costuma render mais com autonomia e um problema novo pela frente.",
  conector:
    "Tende a mobilizar pessoas, comunicar com facilidade e destravar por relação. Costuma render mais com variedade, interação e visibilidade.",
  guardiao:
    "Tende à constância e à confiabilidade, sustentando rotina e cuidando do grupo. Costuma render mais com estabilidade e previsibilidade.",
  estrategista:
    "Tende a analisar antes de agir, buscar rigor e enxergar riscos. Costuma render mais com problemas complexos e autonomia intelectual.",
};

const MOTOR_RESUMO: Record<Motor, string> = {
  racional: "Ao decidir e convencer, recorre primeiro a dados, lógica e evidência.",
  relacional: "Ao decidir e convencer, recorre primeiro ao propósito e ao impacto nas pessoas.",
  pragmatico: "Ao decidir e convencer, recorre primeiro ao retorno prático e aos próximos passos.",
};

const MODO_RESUMO: Record<"constante" | "cadenciado" | "misto", string> = {
  constante: "Costuma manter o desempenho estável diante de pressão e mudança de rota.",
  cadenciado: "Costuma render mais quando o ritmo é previsível e dá para planejar.",
  misto: "Transita entre um ritmo constante e um ritmo cadenciado, conforme o contexto.",
};

interface Props {
  resultado: MapaResultado;
  concluidoEm?: string | null;
  onRefazer?: () => void;
}

export function ResultadoMapa({ resultado, concluidoEm, onRefazer }: Props) {
  const baixa = resultado.confiabilidade === "baixa";

  return (
    <div className="max-w-2xl mx-auto space-y-4">
      <Card className="overflow-hidden">
        <div className="bg-gradient-to-br from-indigo-500 via-violet-500 to-fuchsia-600 p-6 text-white">
          <div className="flex items-center gap-2 text-white/90 text-sm mb-1">
            <Sparkles className="w-4 h-4" /> A sua assinatura comportamental
          </div>
          <h2 className="text-2xl font-bold">{resultado.assinatura}</h2>
          {concluidoEm && (
            <p className="text-white/80 text-xs mt-1">
              Respondido em {new Date(concluidoEm).toLocaleDateString("pt-BR")}
            </p>
          )}
        </div>
      </Card>

      <Alert>
        <Info className="h-4 w-4" />
        <AlertDescription>
          Este é um mapa de <strong>estilo</strong>, não uma medida de competência. Não existe perfil
          melhor nem pior — só formas diferentes de trabalhar.
        </AlertDescription>
      </Alert>

      {baixa && (
        <Alert variant="destructive">
          <AlertTriangle className="h-4 w-4" />
          <AlertDescription>
            As respostas ficaram pouco consistentes, então este resultado é apenas indicativo e não
            alimenta indicadores. Se quiser, refaça com calma para um retrato mais fiel.
            {resultado.motivoBaixaConfiabilidade.length > 0 && (
              <span className="block mt-1 text-xs opacity-80">
                {resultado.motivoBaixaConfiabilidade.join(" ")}
              </span>
            )}
          </AlertDescription>
        </Alert>
      )}

      {/* Arquétipo(s) */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">
            {resultado.arquetipoMisto ? "Perfil misto" : "O seu arquétipo"}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          {resultado.arquetipos.map((a) => (
            <div key={a}>
              <Badge variant="secondary" className="mb-1">{ARQUETIPO_LABEL[a]}</Badge>
              <p className="text-sm text-muted-foreground">{ARQUETIPO_RESUMO[a]}</p>
            </div>
          ))}
          {resultado.arquetipoMisto && (
            <p className="text-xs text-muted-foreground">
              A sua pontuação ficou equilibrada entre dois estilos — trate isso como flexibilidade, não
              como indefinição.
            </p>
          )}
        </CardContent>
      </Card>

      {/* Eixos com intensidade (RN-006) */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Como isso se compõe</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <EixoBarra
            titulo="Foco"
            ladoAEsq="Pessoas"
            ladoBDir="Tarefas"
            pontosA={resultado.foco.pontosA}
            pontosB={resultado.foco.pontosB}
            misto={resultado.foco.misto}
          />
          <EixoBarra
            titulo="Ritmo"
            ladoAEsq="Acelerado"
            ladoBDir="Ponderado"
            pontosA={resultado.ritmo.pontosA}
            pontosB={resultado.ritmo.pontosB}
            misto={resultado.ritmo.misto}
          />
          <div>
            <p className="text-sm font-medium">Motor de decisão</p>
            <div className="flex flex-wrap gap-1 mt-1">
              {resultado.motor.predominantes.map((m) => (
                <Badge key={m} variant="outline">{MOTOR_LABEL[m]}</Badge>
              ))}
            </div>
            <p className="text-xs text-muted-foreground mt-1">
              {resultado.motor.predominantes.map((m) => MOTOR_RESUMO[m]).join(" ")}
            </p>
          </div>
          <div>
            <p className="text-sm font-medium">
              Modo de contexto: {resultado.modo.resultado === "misto" ? "Misto" : MODO_LABEL[resultado.modo.resultado]}
            </p>
            <p className="text-xs text-muted-foreground mt-1">{MODO_RESUMO[resultado.modo.resultado]}</p>
          </div>
        </CardContent>
      </Card>

      {/* Reflexão guiada (RF-006 / jornada passo 5) */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Para refletir</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm text-muted-foreground">
          <p>• Em que situações do seu trabalho esse jeito costuma render mais?</p>
          <p>• O que costuma te desgastar — e como você lida com isso hoje?</p>
          <p>• O que observar em quem trabalha de um jeito diferente do seu?</p>
        </CardContent>
      </Card>

      {onRefazer && (
        <div className="flex justify-center">
          <Button variant="outline" onClick={onRefazer} className="gap-1">
            <RefreshCw className="w-4 h-4" /> Refazer o meu mapa
          </Button>
        </div>
      )}
    </div>
  );
}

function EixoBarra({
  titulo,
  ladoAEsq,
  ladoBDir,
  pontosA,
  pontosB,
  misto,
}: {
  titulo: string;
  ladoAEsq: string;
  ladoBDir: string;
  pontosA: number;
  pontosB: number;
  misto: boolean;
}) {
  const total = pontosA + pontosB || 1;
  const pctA = Math.round((pontosA / total) * 100);
  return (
    <div>
      <div className="flex items-center justify-between text-sm">
        <span className="font-medium">{titulo}</span>
        {misto && <span className="text-xs text-muted-foreground">equilibrado (flexível)</span>}
      </div>
      <div className="mt-1 h-3 w-full rounded-full bg-muted overflow-hidden flex">
        <div className="h-full bg-indigo-500/70" style={{ width: `${pctA}%` }} />
        <div className="h-full bg-fuchsia-500/70" style={{ width: `${100 - pctA}%` }} />
      </div>
      <div className="flex items-center justify-between text-xs text-muted-foreground mt-1">
        <span>{ladoAEsq}</span>
        <span>{ladoBDir}</span>
      </div>
    </div>
  );
}
