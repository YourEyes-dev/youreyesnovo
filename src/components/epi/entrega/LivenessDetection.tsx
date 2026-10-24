import { useState, useRef, useEffect, useCallback } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { CheckCircle, AlertCircle, Loader2, ShieldCheck, ShieldAlert } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import type { FaceLandmarker } from "@mediapipe/tasks-vision";
import { carregarDetector, VERSAO_DO_DETECTOR } from "@/lib/liveness/detector";
import {
  criarDetectorDeAcao, giroDaCabeca, pontuacaoDePiscar,
  type AcaoDePresenca, type DetectorDeAcao,
} from "@/lib/liveness/analise";

interface LivenessAction {
  type: AcaoDePresenca;
  label: string;
  instruction: string;
}

const ALL_ACTIONS: LivenessAction[] = [
  { type: "blink", label: "Piscar", instruction: "Pisque os olhos" },
  { type: "turn_left", label: "Esquerda", instruction: "Vire a cabeça para a sua esquerda" },
  { type: "turn_right", label: "Direita", instruction: "Vire a cabeça para a sua direita" },
];

/** Tempo para cumprir cada ação antes de oferecer nova tentativa. */
const TEMPO_POR_ACAO_MS = 10_000;
/** Tentativas esgotadas por ação antes de oferecer a confirmação manual. */
const TENTATIVAS_ATE_MANUAL = 2;

export interface DetalheDeAcao {
  tipo: AcaoDePresenca;
  /** Como a ação foi confirmada: pela detecção automática ou pelo botão. */
  confirmada_por: "automatica" | "manual";
  detectado_em: string;
  /** Valor que sustentou a detecção (giro ou fechamento dos olhos); vazio no modo manual. */
  pontuacao?: number;
}

/** Tentativa que esgotou o tempo: os picos medidos servem para calibrar os limiares. */
export interface TentativaSemSucesso {
  tipo: AcaoDePresenca;
  /** Maior |giro| visto na tentativa (0 a 1). */
  pico_giro: number;
  /** Maior fechamento médio dos olhos visto na tentativa (0 a 1). */
  pico_piscar: number;
}

export interface LivenessResultado {
  actions: string[];
  timestamps: string[];
  frames?: string[];
  /**
   * 'face-landmarker' SÓ quando TODAS as ações foram detectadas automaticamente.
   * Qualquer confirmação manual rebaixa o resultado para 'manual' (não verificado).
   */
  metodo: "face-landmarker" | "manual";
  versao_do_detector?: string;
  detalhes: DetalheDeAcao[];
  tentativas_sem_sucesso: TentativaSemSucesso[];
}

interface LivenessDetectionProps {
  onComplete: (data: LivenessResultado) => void;
  onError?: (error: string) => void;
}

export function LivenessDetection({ onComplete, onError }: LivenessDetectionProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const streamRef = useRef<MediaStream | null>(null);

  const [cameraReady, setCameraReady] = useState(false);
  const [cameraError, setCameraError] = useState<string | null>(null);
  const [detector, setDetector] = useState<FaceLandmarker | null>(null);
  const [detectorFalhou, setDetectorFalhou] = useState(false);
  const [rostoVisivel, setRostoVisivel] = useState(false);
  const [dica, setDica] = useState<string | null>(null);
  const [tentativas, setTentativas] = useState(0);
  const [modoManual, setModoManual] = useState(false);
  const [feito, setFeito] = useState<string | null>(null);

  const [actions, setActions] = useState<LivenessAction[]>([]);
  const [currentActionIndex, setCurrentActionIndex] = useState(0);
  const [completedActions, setCompletedActions] = useState<string[]>([]);

  // O laço de detecção roda fora do ciclo do React: o que ele lê vive em refs.
  const indiceRef = useRef(0);
  const acoesRef = useRef<LivenessAction[]>([]);
  const detalhesRef = useRef<DetalheDeAcao[]>([]);
  const framesRef = useRef<string[]>([]);
  const acaoDetectorRef = useRef<DetectorDeAcao | null>(null);
  const quadroPendenteRef = useRef<string | null>(null);
  const inicioDaAcaoRef = useRef(0);
  const ocupadoRef = useRef(false);
  const concluidoRef = useRef(false);
  const tentativasRef = useRef(0);
  const picoGiroRef = useRef(0);
  const picoPiscarRef = useRef(0);
  const semSucessoRef = useRef<TentativaSemSucesso[]>([]);

  // 3 ações em ordem aleatória (a ordem muda a cada entrega).
  useEffect(() => {
    const embaralhadas = [...ALL_ACTIONS].sort(() => Math.random() - 0.5);
    acoesRef.current = embaralhadas;
    setActions(embaralhadas);
  }, []);

  // Carrega o detector (modelo hospedado no próprio site).
  useEffect(() => {
    let ativo = true;
    carregarDetector()
      .then((d) => { if (ativo) setDetector(d); })
      .catch(() => { if (ativo) setDetectorFalhou(true); });
    return () => { ativo = false; };
  }, []);

  const captureFrame = useCallback((): string | null => {
    const video = videoRef.current;
    const canvas = canvasRef.current;
    if (!video || !canvas) return null;
    canvas.width = video.videoWidth || 640;
    canvas.height = video.videoHeight || 480;
    const ctx = canvas.getContext("2d");
    if (!ctx) return null;
    ctx.drawImage(video, 0, 0);
    return canvas.toDataURL("image/jpeg", 0.7);
  }, []);

  const pararCamera = useCallback(() => {
    streamRef.current?.getTracks().forEach((t) => t.stop());
  }, []);

  const startCamera = useCallback(async () => {
    try {
      const mediaStream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "user", width: 640, height: 480 },
      });
      streamRef.current = mediaStream;
      if (videoRef.current) videoRef.current.srcObject = mediaStream;
      setCameraReady(true);
      setCameraError(null);
    } catch {
      const msg = "Não foi possível acessar a câmera. Verifique as permissões.";
      setCameraError(msg);
      onError?.(msg);
    }
  }, [onError]);

  useEffect(() => {
    startCamera();
    return () => pararCamera();
  }, [startCamera, pararCamera]);

  const iniciarAcao = useCallback((indice: number) => {
    const acao = acoesRef.current[indice];
    acaoDetectorRef.current = acao ? criarDetectorDeAcao(acao.type) : null;
    quadroPendenteRef.current = null;
    inicioDaAcaoRef.current = performance.now();
    picoGiroRef.current = 0;
    picoPiscarRef.current = 0;
    tentativasRef.current = 0;
    setTentativas(0);
    setDica(null);
  }, []);

  // Registra uma ação cumprida (automática ou manual) e avança.
  const registrarAcao = useCallback((acao: LivenessAction, detalhe: Omit<DetalheDeAcao, "tipo">) => {
    if (ocupadoRef.current || concluidoRef.current) return;
    ocupadoRef.current = true;

    const frame = quadroPendenteRef.current ?? captureFrame();
    if (frame) framesRef.current.push(frame);
    detalhesRef.current.push({ tipo: acao.type, ...detalhe });
    setCompletedActions((prev) => [...prev, acao.type]);
    setFeito(acao.label);

    setTimeout(() => {
      setFeito(null);
      const ultimo = indiceRef.current === acoesRef.current.length - 1;
      if (ultimo) {
        concluidoRef.current = true;
        pararCamera();
        const detalhes = detalhesRef.current;
        const tudoAutomatico = detalhes.every((d) => d.confirmada_por === "automatica");
        onComplete({
          actions: detalhes.map((d) => d.tipo),
          timestamps: detalhes.map((d) => d.detectado_em),
          frames: framesRef.current,
          metodo: tudoAutomatico ? "face-landmarker" : "manual",
          versao_do_detector: tudoAutomatico ? VERSAO_DO_DETECTOR : undefined,
          detalhes,
          tentativas_sem_sucesso: semSucessoRef.current,
        });
        return;
      }
      indiceRef.current += 1;
      setCurrentActionIndex(indiceRef.current);
      iniciarAcao(indiceRef.current);
      ocupadoRef.current = false;
    }, 800);
  }, [captureFrame, iniciarAcao, onComplete, pararCamera]);

  // Primeira ação, assim que a lista existe.
  useEffect(() => {
    if (actions.length > 0) iniciarAcao(0);
  }, [actions, iniciarAcao]);

  // Laço de detecção: um quadro por vez, sem acumular trabalho.
  useEffect(() => {
    if (!detector || !cameraReady || modoManual) return;
    let rafId = 0;
    let ultimoTempoDeVideo = -1;
    let ativo = true;

    const laco = () => {
      if (!ativo) return;
      const video = videoRef.current;
      const acaoAtual = acoesRef.current[indiceRef.current];
      const analisador = acaoDetectorRef.current;
      if (video && video.readyState >= 2 && video.currentTime !== ultimoTempoDeVideo && acaoAtual && analisador
          && !ocupadoRef.current && !concluidoRef.current) {
        ultimoTempoDeVideo = video.currentTime;
        try {
          const r = detector.detectForVideo(video, performance.now());
          const malha = r.faceLandmarks?.[0];
          const amostra = {
            rosto: !!malha,
            giro: malha ? giroDaCabeca(malha) : null,
            piscar: pontuacaoDePiscar(r.faceBlendshapes?.[0]?.categories),
          };
          setRostoVisivel(amostra.rosto);
          if (amostra.giro !== null) picoGiroRef.current = Math.max(picoGiroRef.current, Math.abs(amostra.giro));
          if (amostra.piscar) picoPiscarRef.current = Math.max(picoPiscarRef.current, amostra.piscar.media);
          const res = analisador.processar(amostra);
          setDica(res.dica ?? null);
          if (res.capturar) quadroPendenteRef.current = captureFrame();
          if (res.concluida) {
            registrarAcao(acaoAtual, {
              confirmada_por: "automatica",
              detectado_em: new Date().toISOString(),
              pontuacao: Math.round(res.pontuacao * 1000) / 1000,
            });
          } else if (performance.now() - inicioDaAcaoRef.current > TEMPO_POR_ACAO_MS) {
            // Tempo esgotado: nova tentativa; depois de algumas, oferece o modo manual.
            semSucessoRef.current.push({
              tipo: acaoAtual.type,
              pico_giro: Math.round(picoGiroRef.current * 1000) / 1000,
              pico_piscar: Math.round(picoPiscarRef.current * 1000) / 1000,
            });
            picoGiroRef.current = 0;
            picoPiscarRef.current = 0;
            tentativasRef.current += 1;
            setTentativas(tentativasRef.current);
            acaoDetectorRef.current = criarDetectorDeAcao(acaoAtual.type);
            quadroPendenteRef.current = null;
            inicioDaAcaoRef.current = performance.now();
          }
        } catch {
          // Um quadro ruim não derruba a verificação.
        }
      }
      rafId = requestAnimationFrame(laco);
    };
    rafId = requestAnimationFrame(laco);
    return () => { ativo = false; cancelAnimationFrame(rafId); };
  }, [detector, cameraReady, modoManual, captureFrame, registrarAcao]);

  const confirmarManual = () => {
    const acao = acoesRef.current[indiceRef.current];
    if (!acao) return;
    registrarAcao(acao, { confirmada_por: "manual", detectado_em: new Date().toISOString() });
  };

  const currentAction = actions[currentActionIndex];
  const carregandoModelo = !detector && !detectorFalhou;
  const podeOferecerManual = detectorFalhou || tentativas >= TENTATIVAS_ATE_MANUAL;
  const emManual = modoManual || detectorFalhou;

  if (cameraError) {
    return (
      <Card className="p-6">
        <div className="flex flex-col items-center gap-4 text-center">
          <AlertCircle className="h-12 w-12 text-destructive" />
          <p className="text-muted-foreground">{cameraError}</p>
          <Button onClick={startCamera}>Tentar Novamente</Button>
        </div>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <div className="text-center">
        <h3 className="text-lg font-semibold">Verificação de Presença</h3>
        <p className="text-sm text-muted-foreground">
          {emManual
            ? "Complete as ações abaixo e confirme cada uma"
            : "Faça as ações pedidas olhando para a câmera"}
        </p>
      </div>

      {/* Indicador de progresso */}
      <div className="flex justify-center gap-2">
        {actions.map((_, index) => (
          <div
            key={index}
            className={`h-2 w-8 rounded-full transition-colors ${
              index < currentActionIndex ? "bg-green-500" : index === currentActionIndex ? "bg-primary" : "bg-muted"
            }`}
          />
        ))}
      </div>

      {/* Vídeo da câmera (espelhado só na exibição: o quadro analisado é o bruto) */}
      <div className="relative mx-auto overflow-hidden rounded-xl bg-black" style={{ maxWidth: 400 }}>
        <video ref={videoRef} autoPlay playsInline muted className="aspect-video w-full transform scale-x-[-1]" />

        {cameraReady && !emManual && detector && (
          <div className={`absolute top-2 right-2 flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium ${
            rostoVisivel ? "bg-green-500/90 text-white" : "bg-red-500/90 text-white animate-pulse"
          }`}>
            {rostoVisivel
              ? (<><ShieldCheck className="h-3.5 w-3.5" />Rosto detectado</>)
              : (<><ShieldAlert className="h-3.5 w-3.5" />Nenhum rosto</>)}
          </div>
        )}

        {(!cameraReady || (carregandoModelo && !modoManual)) && (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 bg-black/60 text-white">
            <Loader2 className="h-8 w-8 animate-spin" />
            {cameraReady && carregandoModelo && <span className="text-xs">Preparando a verificação...</span>}
          </div>
        )}
      </div>

      {detectorFalhou && (
        <div className="mx-auto flex max-w-sm items-center gap-2 rounded-md bg-amber-50 p-3 text-xs text-amber-700 dark:bg-amber-950/30 dark:text-amber-400">
          <AlertCircle className="h-4 w-4 shrink-0" />
          <span>Não foi possível carregar a detecção automática. A confirmação será manual e ficará registrada como não verificada.</span>
        </div>
      )}

      {/* Instrução atual */}
      <AnimatePresence mode="wait">
        {currentAction && (
          <motion.div
            key={currentAction.type}
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -20 }}
            className="text-center"
          >
            <Card className="mx-auto max-w-sm p-6">
              <p className="mb-2 text-xl font-medium">{currentAction.instruction}</p>

              {feito ? (
                <p className="mb-3 flex items-center justify-center gap-1.5 text-sm font-medium text-green-600">
                  <CheckCircle className="h-4 w-4" /> {feito} confirmado
                </p>
              ) : (
                !emManual && dica && <p className="mb-3 text-sm font-medium text-destructive">{dica}</p>
              )}

              {!emManual && !feito && tentativas > 0 && (
                <p className="mb-3 text-xs text-muted-foreground">
                  Não consegui confirmar. Tente de novo, com o rosto bem iluminado e de frente.
                </p>
              )}

              {emManual && (
                <Button onClick={confirmarManual} disabled={!cameraReady || !!feito} size="lg" className="w-full">
                  <CheckCircle className="mr-2 h-4 w-4" />
                  Ação Realizada
                </Button>
              )}

              {!emManual && podeOferecerManual && !feito && (
                <Button variant="outline" size="sm" className="mt-2 w-full" onClick={() => setModoManual(true)}>
                  Confirmar manualmente (ficará como não verificado)
                </Button>
              )}
            </Card>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Ações completadas */}
      {completedActions.length > 0 && (
        <div className="flex justify-center gap-2">
          {completedActions.map((action, index) => (
            <div
              key={index}
              className="flex items-center gap-1 rounded-full bg-green-100 px-3 py-1 text-sm text-green-700 dark:bg-green-900 dark:text-green-300"
            >
              <CheckCircle className="h-3 w-3" />
              {ALL_ACTIONS.find((a) => a.type === action)?.label}
            </div>
          ))}
        </div>
      )}

      <canvas ref={canvasRef} className="hidden" />
    </div>
  );
}
