import { describe, it, expect } from "vitest";
import { calcularMapa, type MapaRespostas } from "@/data/instrumentos/mapaComportamental";
import { compararMapas } from "@/data/instrumentos/mapaComportamentalComparativo";

// Helpers para montar respostas cheias de um lado.
function todos(valor: number, motor: number): MapaRespostas {
  const r: MapaRespostas = {};
  for (let i = 1; i <= 28; i++) r[String(i)] = valor;
  for (let i = 13; i <= 18; i++) r[String(i)] = motor; // motor 1..3
  return r;
}

describe("compararMapas", () => {
  it("resultado idêntico → não mudou, resumo de estabilidade, sem itens", () => {
    const a = calcularMapa(todos(2, 1));
    const b = calcularMapa(todos(2, 1));
    const c = compararMapas(a, b);
    expect(c.mudou).toBe(false);
    expect(c.itens).toHaveLength(0);
    expect(c.resumo.toLowerCase()).toContain("estável");
  });

  it("arquétipo diferente → lista o item Arquétipo predominante", () => {
    // Todos lado A (Pessoas/Acelerado...) vs todos lado B (Tarefas/Ponderado...)
    const a = calcularMapa(todos(-2, 2)); // motor relacional
    const b = calcularMapa(todos(2, 1)); // motor racional
    const c = compararMapas(a, b);
    expect(c.mudou).toBe(true);
    const rotulos = c.itens.map((i) => i.rotulo);
    expect(rotulos).toContain("Arquétipo predominante");
    expect(rotulos).toContain("Motor de decisão");
  });

  it("nunca usa linguagem de valor (melhor/pior/evoluiu/regrediu)", () => {
    const a = calcularMapa(todos(-2, 2));
    const b = calcularMapa(todos(2, 1));
    const texto = [compararMapas(a, b).resumo, compararMapas(b, b).resumo].join(" ").toLowerCase();
    for (const termo of ["melhor", "pior", "melhorou", "piorou", "evoluiu", "regrediu", "avançou", "caiu"]) {
      expect(texto, `termo de valor proibido: ${termo}`).not.toContain(termo);
    }
  });

  it("só lista dimensões que realmente mudaram", () => {
    // Mesmo arquétipo/eixos/modo, muda só o motor (racional -> pragmático).
    const a = calcularMapa(todos(2, 1));
    const b = calcularMapa(todos(2, 3));
    const c = compararMapas(a, b);
    expect(c.itens.map((i) => i.rotulo)).toEqual(["Motor de decisão"]);
  });
});
