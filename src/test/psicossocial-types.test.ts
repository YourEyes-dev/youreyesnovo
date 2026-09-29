import { describe, it, expect } from "vitest";
import {
  calcularIPSClassificacao,
  calcularIRPSClassificacao,
  getIPSColor,
  getIPSBgColor,
  getIPSLabel,
  getIRPSColor,
  getIRPSBgColor,
  getIRPSLabel,
  INSTRUMENTOS,
  ESCALA_RESPOSTAS,
  BLOCOS_PSICOSSOCIAL,
  getMinimoRespostas,
  isEntrevistaInstrumento,
  MINIMO_ANONIMATO_PADRAO,
} from "@/types/psicossocial";

describe("calcularIPSClassificacao (types)", () => {
  const cases: [number, string][] = [
    [100, "saudavel"],
    [80, "saudavel"],
    [79, "estavel"],
    [65, "estavel"],
    [64, "atencao"],
    [50, "atencao"],
    [49, "risco"],
    [35, "risco"],
    [34, "critico"],
    [0, "critico"],
  ];

  cases.forEach(([score, expected]) => {
    it(`${score} → ${expected}`, () => {
      expect(calcularIPSClassificacao(score)).toBe(expected);
    });
  });
});

describe("calcularIRPSClassificacao (espelhado do IPS)", () => {
  const cases: [number, string][] = [
    [0, "saudavel"],
    [20, "saudavel"],
    [21, "estavel"],
    [35, "estavel"],
    [36, "atencao"],
    [50, "atencao"],
    [51, "risco"],
    [65, "risco"],
    [66, "critico"],
    [100, "critico"],
  ];

  cases.forEach(([score, expected]) => {
    it(`${score} → ${expected}`, () => {
      expect(calcularIRPSClassificacao(score)).toBe(expected);
    });
  });
});

describe("getIPSColor", () => {
  it("retorna classe CSS para cada classificação", () => {
    expect(getIPSColor("saudavel")).toContain("emerald");
    expect(getIPSColor("estavel")).toContain("blue");
    expect(getIPSColor("atencao")).toContain("amber");
    expect(getIPSColor("risco")).toContain("orange");
    expect(getIPSColor("critico")).toContain("red");
  });
});

describe("getIPSBgColor", () => {
  it("retorna background para cada classificação", () => {
    expect(getIPSBgColor("saudavel")).toContain("bg-");
    expect(getIPSBgColor("critico")).toContain("bg-");
  });
});

describe("getIPSLabel", () => {
  it("retorna label em português", () => {
    expect(getIPSLabel("saudavel")).toBe("Ambiente Saudável");
    expect(getIPSLabel("critico")).toBe("Risco Crítico");
  });
});

describe("getIRPSColor", () => {
  it("retorna classe CSS para cada classificação IRP-S", () => {
    expect(getIRPSColor("saudavel")).toContain("emerald");
    expect(getIRPSColor("estavel")).toContain("blue");
    expect(getIRPSColor("atencao")).toContain("amber");
    expect(getIRPSColor("risco")).toContain("orange");
    expect(getIRPSColor("critico")).toContain("red");
  });
});

describe("getIRPSBgColor", () => {
  it("retorna background para cada classificação IRP-S", () => {
    expect(getIRPSBgColor("saudavel")).toContain("bg-");
    expect(getIRPSBgColor("critico")).toContain("bg-");
  });
});

describe("getIRPSLabel", () => {
  it("retorna label em português para IRP-S", () => {
    expect(getIRPSLabel("saudavel")).toBe("Ambiente Saudável");
    expect(getIRPSLabel("critico")).toBe("Risco Crítico");
  });
});

describe("INSTRUMENTOS config", () => {
  it("tem pelo menos COPSOQ e HSE", () => {
    const ids = INSTRUMENTOS.map(i => i.id);
    expect(ids).toContain("copsoq");
    expect(ids).toContain("hse");
  });

  it("COPSOQ tem 43 perguntas", () => {
    const copsoq = INSTRUMENTOS.find(i => i.id === "copsoq")!;
    expect(copsoq.totalPerguntas).toBe(43);
  });

  it("HSE tem 36 perguntas", () => {
    const hse = INSTRUMENTOS.find(i => i.id === "hse")!;
    expect(hse.totalPerguntas).toBe(36);
  });
});

describe("ESCALA_RESPOSTAS", () => {
  it("tem 5 opções de 0 a 4", () => {
    expect(ESCALA_RESPOSTAS.length).toBe(5);
    expect(ESCALA_RESPOSTAS[0].valor).toBe(0);
    expect(ESCALA_RESPOSTAS[4].valor).toBe(4);
  });

  it("cada opção tem label e emoji", () => {
    for (const op of ESCALA_RESPOSTAS) {
      expect(op.label).toBeTruthy();
      expect(op.emoji).toBeTruthy();
    }
  });
});

describe("BLOCOS_PSICOSSOCIAL", () => {
  it("tem blocos definidos", () => {
    expect(BLOCOS_PSICOSSOCIAL.length).toBeGreaterThan(0);
  });

  it("cada bloco tem perguntas com id e texto", () => {
    for (const bloco of BLOCOS_PSICOSSOCIAL) {
      expect(bloco.id).toBeTruthy();
      expect(bloco.titulo).toBeTruthy();
      expect(bloco.perguntas.length).toBeGreaterThan(0);
      for (const p of bloco.perguntas) {
        expect(p.id).toBeTruthy();
        expect(p.texto).toBeTruthy();
      }
    }
  });

  it("IDs de perguntas são únicos", () => {
    const ids = BLOCOS_PSICOSSOCIAL.flatMap(b => b.perguntas.map(p => p.id));
    const unique = new Set(ids);
    expect(unique.size).toBe(ids.length);
  });
});

describe("getMinimoRespostas — trava de anonimato por tipo de instrumento", () => {
  it("questionário exige o mínimo padrão (5 respondentes)", () => {
    expect(MINIMO_ANONIMATO_PADRAO).toBe(5);
    expect(getMinimoRespostas({ tipo_instrumento: "questionario" })).toBe(5);
  });

  it("entrevista guiada e coletiva liberam a partir de 1 resposta", () => {
    expect(getMinimoRespostas({ tipo_instrumento: "entrevista_guiada" })).toBe(1);
    expect(getMinimoRespostas({ tipo_instrumento: "entrevista_coletiva" })).toBe(1);
  });

  it("sem campanha ou tipo desconhecido, aplica o mínimo padrão", () => {
    expect(getMinimoRespostas(null)).toBe(5);
    expect(getMinimoRespostas(undefined)).toBe(5);
    expect(getMinimoRespostas({})).toBe(5);
  });

  it("isEntrevistaInstrumento reconhece guiada e coletiva, e só elas", () => {
    expect(isEntrevistaInstrumento("entrevista_guiada")).toBe(true);
    expect(isEntrevistaInstrumento("entrevista_coletiva")).toBe(true);
    expect(isEntrevistaInstrumento("questionario")).toBe(false);
    expect(isEntrevistaInstrumento(null)).toBe(false);
    expect(isEntrevistaInstrumento(undefined)).toBe(false);
  });
});
