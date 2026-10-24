import type { FaceLandmarker } from "@mediapipe/tasks-vision";

/**
 * Carrega o detector de rosto (MediaPipe Face Landmarker) UMA vez e o reaproveita.
 *
 * O modelo (~3,7 MB) e os arquivos WASM (~9,5 MB) são servidos pelo PRÓPRIO site
 * (public/mediapipe e a cópia feita pelo vite.config.ts), nunca por CDN de
 * terceiros: a imagem do rosto é dado sensível e o processamento é local. A
 * biblioteca é importada sob demanda, para não pesar no carregamento da tela.
 */
export const VERSAO_DO_DETECTOR = "mediapipe-tasks-vision@0.10.21 / face_landmarker float16 v1";

let promessa: Promise<FaceLandmarker> | null = null;

function base(): string {
  const b = import.meta.env.BASE_URL || "/";
  return b.endsWith("/") ? b : `${b}/`;
}

export function carregarDetector(): Promise<FaceLandmarker> {
  if (promessa) return promessa;
  promessa = (async () => {
    const { FaceLandmarker, FilesetResolver } = await import("@mediapipe/tasks-vision");
    const arquivos = await FilesetResolver.forVisionTasks(`${base()}mediapipe/wasm`);
    const opcoes = (delegate: "GPU" | "CPU") => ({
      baseOptions: { modelAssetPath: `${base()}mediapipe/face_landmarker.task`, delegate },
      runningMode: "VIDEO" as const,
      numFaces: 1,
      outputFaceBlendshapes: true,
    });
    try {
      return await FaceLandmarker.createFromOptions(arquivos, opcoes("GPU"));
    } catch {
      // Aparelhos sem WebGL utilizável caem para o processador.
      return await FaceLandmarker.createFromOptions(arquivos, opcoes("CPU"));
    }
  })();
  // Se falhar, permite tentar de novo em vez de guardar o erro para sempre.
  promessa.catch(() => {
    promessa = null;
  });
  return promessa;
}

/** Começa a baixar o modelo em segundo plano (chame ao abrir o wizard). */
export function precarregarDetector(): void {
  void carregarDetector().catch(() => undefined);
}
