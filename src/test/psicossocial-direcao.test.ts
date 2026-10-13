import { describe, it, expect } from "vitest";
import {
  instrumentoDeRisco,
  normalizarParaIPS,
  radarParaIPS,
} from "@/lib/psicossocial-direcao";

/**
 * Contrato da padronização: régua única de SAÚDE (IPS, alto = melhor).
 * SIPRO e entrevistas gravam o radar bruto em RISCO (alto = pior) e precisam
 * ser invertidos na leitura; COPSOQ/HSE/PROART já estão em saúde.
 */
describe("psicossocial — direção única (saúde, alto = melhor)", () => {
  it("identifica instrumentos de risco (SIPRO e entrevistas)", () => {
    expect(instrumentoDeRisco("sipro")).toBe(true);
    expect(instrumentoDeRisco("copsoq", "entrevista_guiada")).toBe(true);
    expect(instrumentoDeRisco(null, "entrevista_coletiva")).toBe(true);
  });

  it("não marca instrumentos de saúde como risco", () => {
    expect(instrumentoDeRisco("copsoq")).toBe(false);
    expect(instrumentoDeRisco("copsoq2br")).toBe(false);
    expect(instrumentoDeRisco("hse")).toBe(false);
    expect(instrumentoDeRisco("proart")).toBe(false);
    expect(instrumentoDeRisco("copsoq", "questionario")).toBe(false);
  });

  it("normaliza valor bruto para saúde: inverte risco, mantém saúde", () => {
    // SIPRO (risco bruto 80 = ruim) -> saúde 20
    expect(normalizarParaIPS(80, "sipro")).toBe(20);
    // COPSOQ (saúde bruta 80 = bom) -> mantém 80
    expect(normalizarParaIPS(80, "copsoq")).toBe(80);
    // entrevista (risco bruto 30) -> saúde 70
    expect(normalizarParaIPS(30, "copsoq", "entrevista_guiada")).toBe(70);
  });

  it("normaliza o radar inteiro preservando os demais campos", () => {
    const radar = [
      { subject: "Demandas", value: 90, fullMark: 100 },
      { subject: "Controle", value: 40, fullMark: 100 },
    ];
    const sipro = radarParaIPS(radar, "sipro");
    expect(sipro.map((d) => d.value)).toEqual([10, 60]);
    expect(sipro[0].subject).toBe("Demandas");
    expect(sipro[0].fullMark).toBe(100);

    const copsoq = radarParaIPS(radar, "copsoq");
    expect(copsoq.map((d) => d.value)).toEqual([90, 40]);
  });

  it("é idempotente em dupla aplicação apenas para instrumentos de saúde", () => {
    const radar = [{ subject: "X", value: 70, fullMark: 100 }];
    // saúde: normalizar duas vezes não muda
    expect(radarParaIPS(radarParaIPS(radar, "copsoq"), "copsoq")[0].value).toBe(70);
    // risco: duas inversões voltam ao bruto (por isso NUNCA normalizar duas vezes)
    expect(radarParaIPS(radarParaIPS(radar, "sipro"), "sipro")[0].value).toBe(70);
  });

  it("trata radar nulo/vazio sem quebrar", () => {
    expect(radarParaIPS(null, "sipro")).toEqual([]);
    expect(radarParaIPS(undefined, "copsoq")).toEqual([]);
  });
});
