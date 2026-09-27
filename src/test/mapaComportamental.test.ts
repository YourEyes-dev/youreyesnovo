import { describe, it, expect } from "vitest";
import {
  calcularMapa,
  MAPA_ITENS,
  MAPA_TOTAL_ITENS,
  MAPA_INSTRUMENTO_VERSAO,
  instrumentoDefinicaoSnapshot,
  type MapaRespostas,
  type ItemAB,
} from "@/data/instrumentos/mapaComportamental";

// Helpers para montar respostas.
// A/B: -2/-1 = lado A (bem/um pouco), 1/2 = lado B (um pouco/bem).
function respostasBase(overrides: Partial<Record<number, number>> = {}): MapaRespostas {
  const r: MapaRespostas = {};
  // Foco: forte lado B (Tarefas)
  for (const id of [1, 2, 3, 4, 5, 6]) r[String(id)] = 2;
  // Ritmo: forte lado A (Acelerado)
  for (const id of [7, 8, 9, 10, 11, 12]) r[String(id)] = -2;
  // Motor: todos racional (1)
  for (const id of [13, 14, 15, 16, 17, 18]) r[String(id)] = 1;
  // Modo: forte lado A (Constante)
  for (const id of [19, 20, 21, 22, 23, 24]) r[String(id)] = -2;
  // Controles coerentes com as bases:
  // 25 (controle de 1, Foco): base é Tarefas(B) → responder lado B
  r["25"] = 2;
  // 26 (controle de 7, Ritmo): base é Acelerado(A) → responder lado A
  r["26"] = -2;
  // 27 (controle de 13, Motor): base é Racional → lado B (racional)
  r["27"] = 2;
  // 28 (controle de 19, Modo): base é Constante(A) → responder lado A
  r["28"] = -2;
  for (const [k, v] of Object.entries(overrides)) r[k] = v as number;
  return r;
}

describe("instrumento", () => {
  it("tem exatamente 28 itens, ids 1..28 sem lacuna", () => {
    expect(MAPA_ITENS).toHaveLength(MAPA_TOTAL_ITENS);
    const ids = MAPA_ITENS.map((i) => i.id).sort((a, b) => a - b);
    expect(ids).toEqual(Array.from({ length: 28 }, (_, i) => i + 1));
  });

  it("snapshot de definição reflete a versão e os 28 itens", () => {
    const snap = instrumentoDefinicaoSnapshot();
    expect(snap.versao).toBe(MAPA_INSTRUMENTO_VERSAO);
    expect(snap.total_itens).toBe(28);
    expect(snap.itens).toHaveLength(28);
  });

  it("cada item de controle aponta o item base", () => {
    const controles = MAPA_ITENS.filter(
      (i): i is ItemAB => i.tipo === "ab" && i.controleDe != null,
    );
    expect(controles.map((c) => c.controleDe).sort((a, b) => (a ?? 0) - (b ?? 0))).toEqual([1, 7, 13, 19]);
  });
});

describe("arquétipo", () => {
  it("Tarefas + Acelerado = Pioneiro", () => {
    const r = calcularMapa(respostasBase());
    expect(r.arquetipos[0]).toBe("pioneiro");
    expect(r.arquetipoMisto).toBe(false);
  });

  it("Pessoas + Ponderado = Guardião", () => {
    const over: Record<number, number> = {};
    for (const id of [1, 2, 3, 4, 5, 6]) over[id] = -2; // Pessoas
    for (const id of [7, 8, 9, 10, 11, 12]) over[id] = 2; // Ponderado
    const r = calcularMapa(respostasBase(over));
    expect(r.arquetipos[0]).toBe("guardiao");
  });

  it("Tarefas + Ponderado = Estrategista", () => {
    const over: Record<number, number> = {};
    for (const id of [7, 8, 9, 10, 11, 12]) over[id] = 2; // Ponderado (Foco fica Tarefas)
    const r = calcularMapa(respostasBase(over));
    expect(r.arquetipos[0]).toBe("estrategista");
  });

  it("Pessoas + Acelerado = Conector", () => {
    const over: Record<number, number> = {};
    for (const id of [1, 2, 3, 4, 5, 6]) over[id] = -2; // Pessoas
    const r = calcularMapa(respostasBase(over));
    expect(r.arquetipos[0]).toBe("conector");
  });
});

describe("perfil misto (RN-004)", () => {
  it("empate/quase-empate no eixo Foco apresenta dois arquétipos vizinhos", () => {
    const over: Record<number, number> = {};
    // Foco perto do zero: 3 itens lado A, 3 lado B, mesma intensidade → diferença 0
    over[1] = -2; over[2] = -1; over[3] = -1;
    over[4] = 2; over[5] = 1; over[6] = 1;
    // controle de foco deixa incompleto para não interferir
    const base = respostasBase(over);
    delete base["25"];
    const r = calcularMapa(base);
    expect(r.foco.misto).toBe(true);
    expect(r.arquetipos.length).toBe(2);
    // Ritmo é Acelerado → vizinhos são Pioneiro (Tarefas) e Conector (Pessoas)
    expect(r.arquetipos).toEqual(expect.arrayContaining(["pioneiro", "conector"]));
  });
});

describe("motor de decisão", () => {
  it("motor claro quando um domina", () => {
    const r = calcularMapa(respostasBase());
    expect(r.motor.predominantes).toEqual(["racional"]);
  });

  it("motor duplo no empate", () => {
    const r = calcularMapa(
      respostasBase({ 13: 1, 14: 1, 15: 1, 16: 2, 17: 2, 18: 2 }), // 3 racional, 3 relacional
    );
    expect(r.motor.predominantes.length).toBe(2);
    expect(r.motor.predominantes).toEqual(expect.arrayContaining(["racional", "relacional"]));
  });
});

describe("índice de consistência (RN-005)", () => {
  it("respostas coerentes → alta confiabilidade, 0 divergências", () => {
    const r = calcularMapa(respostasBase());
    expect(r.indiceConsistencia).toBe(0);
    expect(r.confiabilidade).toBe("alta");
  });

  it("dois ou mais pares divergentes → baixa confiabilidade", () => {
    // Inverte os controles de Foco e Ritmo em relação às bases.
    const r = calcularMapa(respostasBase({ 25: -2, 26: 2 }));
    expect(r.indiceConsistencia).toBeGreaterThanOrEqual(2);
    expect(r.confiabilidade).toBe("baixa");
    expect(r.motivoBaixaConfiabilidade).toContain("Respostas de controle divergentes.");
  });

  it("um único par divergente ainda é alta confiabilidade", () => {
    const r = calcularMapa(respostasBase({ 25: -2 }));
    expect(r.indiceConsistencia).toBe(1);
    expect(r.confiabilidade).toBe("alta");
  });
});

describe("validações de tempo e padrão", () => {
  it("tempo abaixo do mínimo marca baixa confiabilidade", () => {
    const r = calcularMapa(respostasBase(), { tempoTotalSegundos: 30 });
    expect(r.confiabilidade).toBe("baixa");
    expect(r.motivoBaixaConfiabilidade).toContain("Tempo de resposta abaixo do mínimo.");
  });

  it("mesma resposta em todos os itens marca baixa confiabilidade", () => {
    const r: MapaRespostas = {};
    for (let id = 1; id <= 12; id++) r[String(id)] = 2;
    for (let id = 13; id <= 18; id++) r[String(id)] = 2; // motor: precisa ser 1..3; 2 é válido
    for (let id = 19; id <= 28; id++) r[String(id)] = 2;
    const res = calcularMapa(r);
    expect(res.motivoBaixaConfiabilidade).toContain("Padrão de resposta idêntico em todos os itens.");
    expect(res.confiabilidade).toBe("baixa");
  });
});

describe("modo de contexto", () => {
  it("predominância A = Constante", () => {
    expect(calcularMapa(respostasBase()).modo.resultado).toBe("constante");
  });
  it("predominância B = Cadenciado", () => {
    const over: Record<number, number> = {};
    for (const id of [19, 20, 21, 22, 23, 24]) over[id] = 2;
    expect(calcularMapa(respostasBase(over)).modo.resultado).toBe("cadenciado");
  });
});

describe("assinatura", () => {
  it("compõe arquétipo + motor + modo", () => {
    const r = calcularMapa(respostasBase());
    expect(r.assinatura).toBe("Pioneiro-Racional, Modo Constante");
  });
});
