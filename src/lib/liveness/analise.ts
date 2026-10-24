/**
 * Decisão da verificação de presença: piscar e virar a cabeça.
 *
 * Funções PURAS (sem câmera, sem MediaPipe): recebem o que o detector devolveu
 * em cada quadro e decidem se a ação pedida aconteceu. Ficam separadas para
 * poderem ser testadas com sequências sintéticas.
 *
 * Convenção do giro: lido do QUADRO BRUTO da câmera (sem espelhar). Valor de
 * -1 a 1; positivo quando o nariz se aproxima da borda DIREITA da imagem, o que
 * equivale ao usuário virar a cabeça para a SUA ESQUERDA (a câmera o vê de frente).
 * A exibição espelhada do vídeo (selfie) não muda o quadro bruto.
 */

export type AcaoDePresenca = "blink" | "turn_left" | "turn_right";

export interface Ponto {
  x: number;
  y: number;
  z?: number;
}

export interface Piscar {
  /** Média dos dois olhos, 0 (aberto) a 1 (fechado). */
  media: number;
  /** O olho MENOS fechado: um olho só fechado (piscadela) não vale. */
  minimo: number;
}

/** Um quadro analisado. `rosto` é falso quando o detector não achou ninguém. */
export interface Amostra {
  rosto: boolean;
  giro: number | null;
  piscar: Piscar | null;
}

export interface Resultado {
  concluida: boolean;
  /** Este é o quadro que vale como evidência da ação: capture a foto agora. */
  capturar: boolean;
  /** Valor que sustentou a detecção (giro ou fechamento dos olhos), para a trilha. */
  pontuacao: number;
  /** Orientação ao usuário quando algo está errado (lado contrário, por exemplo). */
  dica?: string;
}

/** Pontos da malha facial do MediaPipe (468 pontos): ponta do nariz e as duas bordas do rosto. */
export const INDICE_NARIZ = 1;
export const INDICE_BORDA_A = 234;
export const INDICE_BORDA_B = 454;

/** Limiares. Valores de partida, calibrados no teste com rosto real (ver docs). */
export const LIMIARES = {
  /** |giro| abaixo disto conta como cabeça de frente (ponto de partida da virada). */
  GIRO_NEUTRO: 0.18,
  /** |giro| a partir de disto conta como virada. */
  GIRO_VIRADA: 0.3,
  QUADROS_NEUTRO: 3,
  QUADROS_VIRADA: 4,
  /**
   * Piscar: os limiares são RELATIVOS ao basal de cada pessoa (a pontuação com os
   * olhos abertos varia: num retrato real de olhos abertos deu 0,28). Valores
   * mínimos absolutos protegem quem tem basal baixo.
   */
  OLHO_FECHADO_MEDIA: 0.5,
  OLHO_FECHADO_MINIMO: 0.35,
  /** Quanto acima do basal a média precisa subir para contar como fechado. */
  SUBIDA_FECHADO_MEDIA: 0.3,
  SUBIDA_FECHADO_MINIMO: 0.15,
  /** Voltou a abrir: abaixo do basal mais esta folga. */
  FOLGA_REABRIR: 0.12,
  /** Quadros com olho "aberto" para fixar o basal. */
  QUADROS_ABERTO: 3,
  /** Acima disto não conta como basal (já está fechando). */
  BASAL_MAXIMO: 0.45,
  /** Olhos fechados por mais quadros que isto não é piscar (é olho fechado). */
  QUADROS_FECHADO_MAX: 20,
} as const;

/** Giro da cabeça de -1 a 1, ou null se faltar ponto ou a face estiver degenerada. */
export function giroDaCabeca(malha: Ponto[]): number | null {
  const nariz = malha[INDICE_NARIZ];
  const a = malha[INDICE_BORDA_A];
  const b = malha[INDICE_BORDA_B];
  if (!nariz || !a || !b) return null;
  // Pelo menor e pelo maior x, para não depender de qual índice cai de cada lado.
  const esquerda = Math.min(a.x, b.x);
  const direita = Math.max(a.x, b.x);
  const largura = direita - esquerda;
  if (largura < 1e-6) return null;
  return ((nariz.x - esquerda) - (direita - nariz.x)) / largura;
}

export interface CategoriaBlendshape {
  categoryName: string;
  score: number;
}

/** Pontuação de piscar a partir dos blendshapes (eyeBlinkLeft / eyeBlinkRight). */
export function pontuacaoDePiscar(categorias: CategoriaBlendshape[] | undefined): Piscar | null {
  if (!categorias) return null;
  const esq = categorias.find((c) => c.categoryName === "eyeBlinkLeft")?.score;
  const dir = categorias.find((c) => c.categoryName === "eyeBlinkRight")?.score;
  if (esq === undefined || dir === undefined) return null;
  return { media: (esq + dir) / 2, minimo: Math.min(esq, dir) };
}

export interface DetectorDeAcao {
  processar(amostra: Amostra): Resultado;
  reiniciar(): void;
}

const SEM_PROGRESSO: Resultado = { concluida: false, capturar: false, pontuacao: 0 };

/** Detector de UMA ação. Cada ação nova pede um detector novo. */
export function criarDetectorDeAcao(tipo: AcaoDePresenca): DetectorDeAcao {
  return tipo === "blink" ? detectorDePiscar() : detectorDeVirada(tipo === "turn_left" ? 1 : -1);
}

function detectorDeVirada(sentido: 1 | -1): DetectorDeAcao {
  let neutro = 0;
  let virado = 0;
  let pronto = false; // viu a cabeça de frente antes de virar
  let contrario = 0;
  return {
    reiniciar() {
      neutro = 0; virado = 0; pronto = false; contrario = 0;
    },
    processar(a) {
      if (!a.rosto || a.giro === null) {
        neutro = 0; virado = 0; pronto = false; contrario = 0;
        return { ...SEM_PROGRESSO, dica: "Posicione seu rosto na câmera" };
      }
      const g = a.giro * sentido; // positivo = no sentido pedido
      if (Math.abs(a.giro) < LIMIARES.GIRO_NEUTRO) {
        neutro += 1; virado = 0; contrario = 0;
        if (neutro >= LIMIARES.QUADROS_NEUTRO) pronto = true;
        return { ...SEM_PROGRESSO, pontuacao: g };
      }
      neutro = 0;
      if (g >= LIMIARES.GIRO_VIRADA) {
        contrario = 0;
        // Só vale se partiu de frente: cabeça já virada ao começar não conta.
        if (!pronto) return { ...SEM_PROGRESSO, pontuacao: g, dica: "Olhe de frente para a câmera primeiro" };
        virado += 1;
        if (virado >= LIMIARES.QUADROS_VIRADA) {
          return { concluida: true, capturar: virado === LIMIARES.QUADROS_VIRADA, pontuacao: g };
        }
        return { ...SEM_PROGRESSO, pontuacao: g };
      }
      virado = 0;
      if (g <= -LIMIARES.GIRO_VIRADA) {
        contrario += 1;
        if (contrario >= LIMIARES.QUADROS_VIRADA) {
          return { ...SEM_PROGRESSO, pontuacao: g, dica: "Vire para o outro lado" };
        }
      } else {
        contrario = 0;
      }
      return { ...SEM_PROGRESSO, pontuacao: g };
    },
  };
}

function detectorDePiscar(): DetectorDeAcao {
  let basal: number | null = null; // pontuação do olho aberto desta pessoa
  let aberto = 0;
  let fechado = 0;
  let picoMedia = 0;
  const zerar = () => { basal = null; aberto = 0; fechado = 0; picoMedia = 0; };
  return {
    reiniciar: zerar,
    processar(a) {
      if (!a.rosto || !a.piscar) {
        zerar();
        return { ...SEM_PROGRESSO, dica: "Posicione seu rosto na câmera" };
      }
      const { media, minimo } = a.piscar;
      const pronto = aberto >= LIMIARES.QUADROS_ABERTO && basal !== null;

      // Ainda sem basal: só quadros de olho aberto o fixam (começar fechado não vale).
      if (!pronto) {
        if (media < LIMIARES.BASAL_MAXIMO) {
          basal = basal === null ? media : Math.min(basal, media);
          aberto += 1;
        } else {
          aberto = 0; basal = null;
        }
        return { ...SEM_PROGRESSO, pontuacao: media };
      }

      const base = basal as number;
      const limiarFechadoMedia = Math.max(LIMIARES.OLHO_FECHADO_MEDIA, base + LIMIARES.SUBIDA_FECHADO_MEDIA);
      const limiarFechadoMinimo = Math.max(LIMIARES.OLHO_FECHADO_MINIMO, base + LIMIARES.SUBIDA_FECHADO_MINIMO);
      const olhosFechados = media >= limiarFechadoMedia && minimo >= limiarFechadoMinimo;

      if (olhosFechados) {
        fechado += 1;
        picoMedia = Math.max(picoMedia, media);
        if (fechado > LIMIARES.QUADROS_FECHADO_MAX) {
          // Olho fechado demais não é piscar: recomeça do zero.
          zerar();
          return { ...SEM_PROGRESSO, pontuacao: media };
        }
        // A foto vale no primeiro quadro de olhos fechados, que é a prova do piscar.
        return { ...SEM_PROGRESSO, capturar: fechado === 1, pontuacao: media };
      }
      if (media < base + LIMIARES.FOLGA_REABRIR && fechado > 0) {
        // Fechou e reabriu: piscou.
        const pico = picoMedia;
        zerar();
        return { concluida: true, capturar: false, pontuacao: pico };
      }
      return { ...SEM_PROGRESSO, pontuacao: media };
    },
  };
}
