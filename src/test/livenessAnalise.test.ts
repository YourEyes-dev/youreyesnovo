import { describe, it, expect } from "vitest";
import {
  giroDaCabeca, pontuacaoDePiscar, criarDetectorDeAcao, LIMIARES,
  INDICE_NARIZ, INDICE_BORDA_A, INDICE_BORDA_B,
  type Amostra, type Ponto,
} from "@/lib/liveness/analise";

/** Malha mínima: nariz e as duas bordas do rosto em x. */
function malha(noseX: number, bordaA = 0.3, bordaB = 0.7): Ponto[] {
  const m: Ponto[] = Array.from({ length: 468 }, () => ({ x: 0.5, y: 0.5 }));
  m[INDICE_NARIZ] = { x: noseX, y: 0.5 };
  m[INDICE_BORDA_A] = { x: bordaA, y: 0.5 };
  m[INDICE_BORDA_B] = { x: bordaB, y: 0.5 };
  return m;
}

const frente: Amostra = { rosto: true, giro: 0, piscar: { media: 0.05, minimo: 0.05 } };
const olhosFechados: Amostra = { rosto: true, giro: 0, piscar: { media: 0.9, minimo: 0.85 } };
const giro = (g: number): Amostra => ({ rosto: true, giro: g, piscar: { media: 0.05, minimo: 0.05 } });
const rodar = (d: ReturnType<typeof criarDetectorDeAcao>, quadros: Amostra[]) => quadros.map((q) => d.processar(q));

describe("giroDaCabeca", () => {
  it("rosto de frente dá giro perto de zero", () => {
    expect(giroDaCabeca(malha(0.5))).toBeCloseTo(0, 5);
  });
  it("nariz para a direita da imagem dá giro positivo (virou para a ESQUERDA do usuário)", () => {
    expect(giroDaCabeca(malha(0.62))).toBeGreaterThan(0.3);
  });
  it("nariz para a esquerda da imagem dá giro negativo", () => {
    expect(giroDaCabeca(malha(0.38))).toBeLessThan(-0.3);
  });
  it("não depende de qual índice fica de cada lado", () => {
    expect(giroDaCabeca(malha(0.62, 0.7, 0.3))).toBeCloseTo(giroDaCabeca(malha(0.62, 0.3, 0.7))!, 5);
  });
  it("devolve null sem pontos ou com rosto degenerado", () => {
    expect(giroDaCabeca([])).toBeNull();
    expect(giroDaCabeca(malha(0.5, 0.5, 0.5))).toBeNull();
  });
});

describe("pontuacaoDePiscar", () => {
  it("lê os dois olhos e guarda o menos fechado como mínimo", () => {
    const p = pontuacaoDePiscar([
      { categoryName: "eyeBlinkLeft", score: 0.9 },
      { categoryName: "eyeBlinkRight", score: 0.3 },
    ]);
    expect(p?.media).toBeCloseTo(0.6, 5);
    expect(p?.minimo).toBeCloseTo(0.3, 5);
  });
  it("devolve null quando faltam os blendshapes", () => {
    expect(pontuacaoDePiscar(undefined)).toBeNull();
    expect(pontuacaoDePiscar([{ categoryName: "jawOpen", score: 1 }])).toBeNull();
  });
});

describe("piscar", () => {
  it("aberto, fechado e aberto de novo conclui, e a foto vale no primeiro quadro fechado", () => {
    const d = criarDetectorDeAcao("blink");
    const r = rodar(d, [frente, frente, frente, olhosFechados, olhosFechados, frente]);
    expect(r[3].capturar).toBe(true);
    expect(r[4].capturar).toBe(false);
    expect(r.slice(0, 5).every((x) => !x.concluida)).toBe(true);
    expect(r[5].concluida).toBe(true);
    expect(r[5].pontuacao).toBeGreaterThan(0.8);
  });
  it("olhos estreitos (basal alto, 0,28 como no retrato real) piscam normalmente", () => {
    const d = criarDetectorDeAcao("blink");
    const estreito: Amostra = { rosto: true, giro: 0, piscar: { media: 0.28, minimo: 0.27 } };
    const r = rodar(d, [estreito, estreito, estreito, estreito, olhosFechados, olhosFechados, estreito]);
    expect(r[r.length - 1].concluida).toBe(true);
  });
  it("olhos estreitos só apertados um pouco (sem fechar de verdade) não valem", () => {
    const d = criarDetectorDeAcao("blink");
    const estreito: Amostra = { rosto: true, giro: 0, piscar: { media: 0.28, minimo: 0.27 } };
    const apertou: Amostra = { rosto: true, giro: 0, piscar: { media: 0.5, minimo: 0.5 } };
    const r = rodar(d, [estreito, estreito, estreito, estreito, apertou, apertou, estreito]);
    expect(r.some((x) => x.concluida)).toBe(false);
  });
  it("basal ainda mais alto (0,34, acima do limiar fixo antigo) também consegue piscar", () => {
    const d = criarDetectorDeAcao("blink");
    const muitoEstreito: Amostra = { rosto: true, giro: 0, piscar: { media: 0.34, minimo: 0.33 } };
    const r = rodar(d, [muitoEstreito, muitoEstreito, muitoEstreito, muitoEstreito, olhosFechados, olhosFechados, muitoEstreito]);
    expect(r[r.length - 1].concluida).toBe(true);
  });
  it("começar de olhos fechados não vale", () => {
    const d = criarDetectorDeAcao("blink");
    const r = rodar(d, [olhosFechados, olhosFechados, frente, frente]);
    expect(r.some((x) => x.concluida)).toBe(false);
  });
  it("fechar só um olho (piscadela) não vale", () => {
    const d = criarDetectorDeAcao("blink");
    const umOlho: Amostra = { rosto: true, giro: 0, piscar: { media: 0.55, minimo: 0.1 } };
    const r = rodar(d, [frente, frente, frente, umOlho, umOlho, frente]);
    expect(r.some((x) => x.concluida)).toBe(false);
  });
  it("olho fechado por tempo demais não é piscar", () => {
    const d = criarDetectorDeAcao("blink");
    const longo = Array.from({ length: LIMIARES.QUADROS_FECHADO_MAX + 3 }, () => olhosFechados);
    const r = rodar(d, [frente, frente, frente, ...longo, frente]);
    expect(r.some((x) => x.concluida)).toBe(false);
  });
  it("sem rosto no meio do piscar zera o progresso", () => {
    const d = criarDetectorDeAcao("blink");
    const semRosto: Amostra = { rosto: false, giro: null, piscar: null };
    const r = rodar(d, [frente, frente, olhosFechados, semRosto, frente]);
    expect(r.some((x) => x.concluida)).toBe(false);
  });
});

describe("virar a cabeça", () => {
  const sustentar = (g: number, n: number) => Array.from({ length: n }, () => giro(g));

  it("virar para a esquerda do usuário (giro positivo) conclui depois de sustentar", () => {
    const d = criarDetectorDeAcao("turn_left");
    const r = rodar(d, [...sustentar(0, 3), ...sustentar(0.45, LIMIARES.QUADROS_VIRADA)]);
    const ultimo = r[r.length - 1];
    expect(ultimo.concluida).toBe(true);
    expect(ultimo.capturar).toBe(true);
  });
  it("virar para a direita do usuário (giro negativo) conclui", () => {
    const d = criarDetectorDeAcao("turn_right");
    const r = rodar(d, [...sustentar(0, 3), ...sustentar(-0.45, LIMIARES.QUADROS_VIRADA)]);
    expect(r[r.length - 1].concluida).toBe(true);
  });
  it("virar para o lado errado não conclui e orienta o usuário", () => {
    const d = criarDetectorDemais("turn_left");
    const r = rodar(d, [...sustentar(0, 3), ...sustentar(-0.5, LIMIARES.QUADROS_VIRADA + 2)]);
    expect(r.some((x) => x.concluida)).toBe(false);
    expect(r.some((x) => x.dica === "Vire para o outro lado")).toBe(true);
  });
  it("virada rápida demais, sem sustentar, não conclui", () => {
    const d = criarDetectorDemais("turn_left");
    const r = rodar(d, [...sustentar(0, 3), giro(0.5), giro(0.5), giro(0)]);
    expect(r.some((x) => x.concluida)).toBe(false);
  });
  it("já começar com a cabeça virada não vale: é preciso partir de frente", () => {
    const d = criarDetectorDemais("turn_left");
    const r = rodar(d, sustentar(0.5, 10));
    expect(r.some((x) => x.concluida)).toBe(false);
    expect(r[r.length - 1].dica).toMatch(/de frente/);
  });
  it("sem rosto pede para posicionar o rosto", () => {
    const d = criarDetectorDemais("turn_left");
    const r = d.processar({ rosto: false, giro: null, piscar: null });
    expect(r.dica).toMatch(/rosto/);
  });
});

// Alias com nome claro para os casos acima.
function criarDetectorDemais(tipo: "turn_left" | "turn_right") {
  return criarDetectorDeAcao(tipo);
}
