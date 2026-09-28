import { describe, it, expect } from "vitest";
import {
  calcularAderencia,
  type MapaPessoaResumo,
  type PerfilIdealCargo,
} from "@/data/instrumentos/aderenciaCargo";

const pessoaBase: MapaPessoaResumo = {
  arquetipos: ["pioneiro"],
  motores: ["racional"],
  modo: "constante",
  confiabilidade: "alta",
};

const idealBase: PerfilIdealCargo = {
  arquetipoIdeal: "pioneiro",
  motorIdeal: ["racional"],
  modoIdeal: "constante",
};

const nivelDe = (r: ReturnType<typeof calcularAderencia>, dim: string) =>
  r.dimensoes.find((d) => d.dimensao === dim)?.nivel;

describe("calcularAderencia — arquétipo (Foco × Ritmo)", () => {
  it("arquétipo igual → flui", () => {
    const r = calcularAderencia(pessoaBase, { ...idealBase, arquetipoIdeal: "pioneiro" });
    expect(nivelDe(r, "arquetipo")).toBe("flui");
  });

  it("arquétipo vizinho (compartilha ritmo) → adapta", () => {
    // pioneiro(tarefas,acelerado) x conector(pessoas,acelerado) — mesmo ritmo
    const r = calcularAderencia(pessoaBase, { ...idealBase, arquetipoIdeal: "conector" });
    expect(nivelDe(r, "arquetipo")).toBe("adapta");
  });

  it("arquétipo vizinho (compartilha foco) → adapta", () => {
    // pioneiro(tarefas,acelerado) x estrategista(tarefas,ponderado) — mesmo foco
    const r = calcularAderencia(pessoaBase, { ...idealBase, arquetipoIdeal: "estrategista" });
    expect(nivelDe(r, "arquetipo")).toBe("adapta");
  });

  it("arquétipo oposto (não compartilha eixo) → energia", () => {
    // pioneiro x guardiao(pessoas,ponderado) — nada em comum
    const r = calcularAderencia(pessoaBase, { ...idealBase, arquetipoIdeal: "guardiao" });
    expect(nivelDe(r, "arquetipo")).toBe("energia");
  });

  it("perfil misto usa o MELHOR encaixe entre os arquétipos da pessoa", () => {
    const misto: MapaPessoaResumo = { ...pessoaBase, arquetipos: ["guardiao", "conector"] };
    // ideal conector: guardiao=vizinho(adapta), conector=igual(flui) → melhor = flui
    const r = calcularAderencia(misto, { ...idealBase, arquetipoIdeal: "conector" });
    expect(nivelDe(r, "arquetipo")).toBe("flui");
  });
});

describe("calcularAderencia — motor", () => {
  it("motor com interseção → flui", () => {
    const r = calcularAderencia({ ...pessoaBase, motores: ["racional", "pragmatico"] }, { ...idealBase, motorIdeal: ["pragmatico"] });
    expect(nivelDe(r, "motor")).toBe("flui");
  });
  it("motor sem interseção → energia", () => {
    const r = calcularAderencia({ ...pessoaBase, motores: ["relacional"] }, { ...idealBase, motorIdeal: ["racional"] });
    expect(nivelDe(r, "motor")).toBe("energia");
  });
});

describe("calcularAderencia — modo", () => {
  it("modo igual → flui", () => {
    const r = calcularAderencia({ ...pessoaBase, modo: "cadenciado" }, { ...idealBase, modoIdeal: "cadenciado" });
    expect(nivelDe(r, "modo")).toBe("flui");
  });
  it("modo misto (de qualquer lado) → adapta", () => {
    expect(nivelDe(calcularAderencia({ ...pessoaBase, modo: "misto" }, { ...idealBase, modoIdeal: "constante" }), "modo")).toBe("adapta");
    expect(nivelDe(calcularAderencia({ ...pessoaBase, modo: "constante" }, { ...idealBase, modoIdeal: "misto" }), "modo")).toBe("adapta");
  });
  it("modo oposto (constante x cadenciado) → energia", () => {
    const r = calcularAderencia({ ...pessoaBase, modo: "constante" }, { ...idealBase, modoIdeal: "cadenciado" });
    expect(nivelDe(r, "modo")).toBe("energia");
  });
});

describe("calcularAderencia — indisponibilidade", () => {
  it("confiabilidade baixa → suprime a aderência", () => {
    const r = calcularAderencia({ ...pessoaBase, confiabilidade: "baixa" }, idealBase);
    expect(r.disponivel).toBe(false);
    expect(r.motivoIndisponivel).toBe("confiabilidade_baixa");
    expect(r.dimensoes).toHaveLength(0);
  });
  it("sem perfil ideal definido → indisponível", () => {
    const r = calcularAderencia(pessoaBase, { arquetipoIdeal: null, motorIdeal: [], modoIdeal: null });
    expect(r.disponivel).toBe(false);
    expect(r.motivoIndisponivel).toBe("sem_perfil_ideal");
  });
  it("sem mapa da pessoa → indisponível", () => {
    const r = calcularAderencia(null, idealBase);
    expect(r.disponivel).toBe(false);
    expect(r.motivoIndisponivel).toBe("sem_mapa");
  });
});

describe("calcularAderencia — nível geral", () => {
  it("tudo alinhado → flui", () => {
    const r = calcularAderencia(pessoaBase, idealBase);
    expect(r.disponivel).toBe(true);
    expect(r.nivelGeral).toBe("flui");
  });
  it("tudo oposto → energia", () => {
    const r = calcularAderencia(
      { arquetipos: ["guardiao"], motores: ["relacional"], modo: "cadenciado", confiabilidade: "alta" },
      { arquetipoIdeal: "pioneiro", motorIdeal: ["racional"], modoIdeal: "constante" },
    );
    expect(r.nivelGeral).toBe("energia");
  });
  it("só um eixo definido no ideal → usa só esse eixo", () => {
    const r = calcularAderencia(pessoaBase, { arquetipoIdeal: "pioneiro", motorIdeal: [], modoIdeal: null });
    expect(r.dimensoes).toHaveLength(1);
    expect(r.nivelGeral).toBe("flui");
  });
});
