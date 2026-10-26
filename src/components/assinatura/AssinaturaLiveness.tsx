import { useState } from "react";
import { Card } from "@/components/ui/card";
import { Loader2 } from "lucide-react";
import { LivenessDetection, type LivenessResultado } from "@/components/epi/entrega/LivenessDetection";
import { persistirFramesDaEvidencia } from "@/lib/assinaturaEvidencia";

/**
 * ASS-0001 — FASE 0: wrapper reutilizável da verificação de presença que PERSISTE
 * a evidência num bucket privado.
 *
 * Roda o LivenessDetection que já existe (não reimplementa nada do liveness) e, ao
 * terminar, sobe os frames capturados para o bucket privado `assinatura-evidencias`
 * e devolve os CAMINHOS gravados (framesRefs), não os data URLs. Assim o chamador
 * guarda só a referência da evidência (para a trilha), nunca a imagem no payload.
 *
 * NÃO toca o EPI: reaproveita o componente e o detector existentes.
 */
export interface AssinaturaLivenessResultado extends Omit<LivenessResultado, "frames"> {
  /** Caminhos dos frames no bucket privado (para ligar à trilha da assinatura). */
  framesRefs: string[];
}

export interface AssinaturaLivenessProps {
  /** Empresa dona da evidência (primeiro nível do caminho; a política RLS confere). */
  tenantId: string;
  /** Módulo/fluxo que colheu a evidência (ex.: 'advertencia', 'epi'). */
  contexto: string;
  /** Id/token do documento/ato ao qual a evidência pertence. */
  referenciaId: string;
  onComplete: (data: AssinaturaLivenessResultado) => void;
  onError?: (error: string) => void;
}

export function AssinaturaLiveness({
  tenantId,
  contexto,
  referenciaId,
  onComplete,
  onError,
}: AssinaturaLivenessProps) {
  const [persistindo, setPersistindo] = useState(false);

  const aoConcluir = async (data: LivenessResultado) => {
    setPersistindo(true);
    let framesRefs: string[] = [];
    try {
      framesRefs = await persistirFramesDaEvidencia({
        tenantId,
        contexto,
        referenciaId,
        frames: data.frames ?? [],
      });
    } catch (e) {
      console.error("[AssinaturaLiveness] falha ao persistir evidência:", e);
      onError?.("Não foi possível guardar a evidência da verificação.");
    }
    const { frames: _descartado, ...resto } = data;
    void _descartado;
    setPersistindo(false);
    onComplete({ ...resto, framesRefs });
  };

  if (persistindo) {
    return (
      <Card className="mx-auto max-w-sm p-6">
        <div className="flex flex-col items-center gap-3 text-center">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
          <p className="text-sm text-muted-foreground">Guardando a evidência da verificação...</p>
        </div>
      </Card>
    );
  }

  return <LivenessDetection onComplete={aoConcluir} onError={onError} />;
}
