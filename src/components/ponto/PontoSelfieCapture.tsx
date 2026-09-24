import { useState, useRef, useCallback, useEffect } from "react";
import { Camera, RefreshCw, CheckCircle2, AlertCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";

interface PontoSelfieCaptureProps {
  selfieFile: File | null;
  selfiePreview: string | null;
  onChange: (file: File | null, preview: string | null) => void;
  /**
   * Quando a empresa exige selfie no registro (padrão). Só nesse caso a câmera
   * abre sozinha ao montar — evitando o pedido de permissão a cada abertura
   * quando a selfie é opcional.
   */
  obrigatoria?: boolean;
}

export function PontoSelfieCapture({ selfieFile, selfiePreview, onChange, obrigatoria = true }: PontoSelfieCaptureProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [stream, setStream] = useState<MediaStream | null>(null);
  const [isCameraOpen, setIsCameraOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const startCamera = useCallback(async () => {
    try {
      setError(null);

      // Verificar contexto seguro (HTTPS é obrigatório, exceto localhost)
      if (typeof window !== "undefined" && !window.isSecureContext) {
        setError("A câmera só funciona em conexões seguras (HTTPS). Abra o link diretamente no navegador.");
        return;
      }

      // Verificar suporte do navegador
      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        setError(
          "Seu navegador não suporta acesso à câmera. Abra este link no Chrome, Safari ou Firefox (não use o navegador interno do WhatsApp/Instagram)."
        );
        return;
      }

      // Tentar com facingMode primeiro; se falhar, tentar sem restrição
      let mediaStream: MediaStream;
      try {
        mediaStream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "user", width: { ideal: 640 }, height: { ideal: 480 } },
          audio: false,
        });
      } catch (innerErr: any) {
        if (innerErr?.name === "OverconstrainedError" || innerErr?.name === "NotFoundError") {
          mediaStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
        } else {
          throw innerErr;
        }
      }

      setStream(mediaStream);
      setIsCameraOpen(true);
      setTimeout(() => {
        if (videoRef.current) {
          videoRef.current.srcObject = mediaStream;
          videoRef.current.play().catch(() => {});
        }
      }, 100);
    } catch (err: any) {
      console.error("[PontoSelfieCapture] getUserMedia error:", err);
      const name = err?.name || "";
      let msg = "Não foi possível acessar a câmera.";
      if (name === "NotAllowedError" || name === "PermissionDeniedError") {
        msg =
          "Permissão da câmera negada. Toque no cadeado/ícone na barra de endereço e permita o uso da câmera, depois tente novamente.";
      } else if (name === "NotFoundError" || name === "DevicesNotFoundError") {
        msg = "Nenhuma câmera foi encontrada neste dispositivo.";
      } else if (name === "NotReadableError" || name === "TrackStartError") {
        msg = "A câmera está sendo usada por outro aplicativo. Feche os outros apps e tente novamente.";
      } else if (name === "SecurityError") {
        msg = "Acesso à câmera bloqueado por questões de segurança. Abra o link em uma aba normal do navegador.";
      } else if (err?.message) {
        msg = `Não foi possível acessar a câmera: ${err.message}`;
      }
      setError(msg);
    }
  }, []);

  const stopCamera = useCallback(() => {
    stream?.getTracks().forEach(t => t.stop());
    setStream(null);
    setIsCameraOpen(false);
  }, [stream]);

  // Auto-abre a câmera ao montar apenas quando a selfie é obrigatória (se ainda
  // não há selfie capturada). Selfie opcional não abre a câmera sozinha — a
  // pessoa toca em "Abrir câmera" se quiser, e o navegador não pede permissão à
  // toa a cada abertura do link.
  useEffect(() => {
    if (obrigatoria && !selfieFile && !isCameraOpen && !stream) {
      startCamera();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [obrigatoria]);

  // Cleanup ao desmontar
  useEffect(() => {
    return () => {
      stream?.getTracks().forEach(t => t.stop());
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const capturePhoto = useCallback(() => {
    if (!videoRef.current || !canvasRef.current) return;
    const video = videoRef.current;
    const canvas = canvasRef.current;
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.drawImage(video, 0, 0);
    canvas.toBlob(
      blob => {
        if (!blob) return;
        const file = new File([blob], `ponto-selfie-${Date.now()}.jpg`, { type: "image/jpeg" });
        const preview = URL.createObjectURL(blob);
        onChange(file, preview);
        stopCamera();
      },
      "image/jpeg",
      0.85
    );
  }, [onChange, stopCamera]);

  const retake = useCallback(() => {
    if (selfiePreview) URL.revokeObjectURL(selfiePreview);
    onChange(null, null);
    startCamera();
  }, [selfiePreview, onChange, startCamera]);

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h4 className="font-medium text-sm text-foreground">📸 Selfie de Verificação</h4>
        <Badge variant={selfieFile ? "default" : "secondary"} className="text-[10px] px-1.5 py-0">
          {selfieFile ? "✓ Capturada" : obrigatoria ? "Obrigatória" : "Opcional"}
        </Badge>
      </div>

      {error && (
        <div className="flex items-center gap-2 text-xs text-destructive bg-destructive/10 p-2 rounded-md">
          <AlertCircle className="h-4 w-4 shrink-0" />
          {error}
        </div>
      )}

      {selfiePreview ? (
        <div className="space-y-2">
          <div className="relative rounded-lg overflow-hidden border">
            <img src={selfiePreview} alt="Selfie de ponto" className="w-full max-h-[200px] object-cover" />
            <div className="absolute top-2 right-2">
              <CheckCircle2 className="h-5 w-5 text-green-500 drop-shadow" />
            </div>
          </div>
          <Button type="button" variant="outline" size="sm" onClick={retake} className="w-full text-xs">
            <RefreshCw className="h-3.5 w-3.5 mr-1.5" />
            Tirar novamente
          </Button>
        </div>
      ) : isCameraOpen ? (
        <div className="space-y-2">
          <div className="relative rounded-lg overflow-hidden border bg-black">
            <video ref={videoRef} autoPlay playsInline muted className="w-full max-h-[200px] object-cover" style={{ transform: "scaleX(-1)" }} />
          </div>
          <div className="flex gap-2">
            <Button type="button" onClick={capturePhoto} className="flex-1 text-xs">
              <Camera className="h-3.5 w-3.5 mr-1.5" />
              Capturar
            </Button>
            <Button type="button" variant="outline" size="sm" onClick={stopCamera} className="text-xs">
              Cancelar
            </Button>
          </div>
          <canvas ref={canvasRef} className="hidden" />
        </div>
      ) : (
        <Button type="button" variant="outline" onClick={startCamera} className="w-full text-xs">
          <Camera className="h-4 w-4 mr-1.5" />
          Abrir câmera para selfie
        </Button>
      )}
    </div>
  );
}
