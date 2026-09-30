import { describe, it, expect } from "vitest";
import { detectarCpfsConflitantes } from "@/hooks/useColaboradores";

describe("detectarCpfsConflitantes", () => {
  it("acusa CPF igual com nomes diferentes (pessoas distintas, erro de cadastro)", () => {
    const r = detectarCpfsConflitantes([
      { cpf: "111.222.333-44", nome_completo: "Ana Silva" },
      { cpf: "11122233344", nome_completo: "Bruno Souza" },
      { cpf: "111.222.333-44", nome_completo: "Carla Lima" },
    ]);
    expect(r).toHaveLength(1);
    expect(r[0].cpf).toBe("11122233344");
    expect(r[0].nomes.sort()).toEqual(["Ana Silva", "Bruno Souza", "Carla Lima"]);
  });

  it("NÃO acusa quando o mesmo CPF tem o mesmo nome (mesma pessoa, dedup legítima)", () => {
    const r = detectarCpfsConflitantes([
      { cpf: "11122233344", nome_completo: "Ana Silva" },
      { cpf: "111.222.333-44", nome_completo: "ana silva" }, // mesmo nome, caixa diferente
    ]);
    expect(r).toHaveLength(0);
  });

  it("NÃO acusa CPFs distintos", () => {
    const r = detectarCpfsConflitantes([
      { cpf: "11111111111", nome_completo: "Ana" },
      { cpf: "22222222222", nome_completo: "Bruno" },
    ]);
    expect(r).toHaveLength(0);
  });

  it("ignora linhas com CPF vazio ou nome vazio", () => {
    const r = detectarCpfsConflitantes([
      { cpf: "", nome_completo: "Sem CPF A" },
      { cpf: null, nome_completo: "Sem CPF B" },
      { cpf: "33333333333", nome_completo: "" },
      { cpf: "33333333333", nome_completo: null },
    ]);
    expect(r).toHaveLength(0);
  });

  it("reporta mais de um CPF em conflito", () => {
    const r = detectarCpfsConflitantes([
      { cpf: "1", nome_completo: "A" },
      { cpf: "1", nome_completo: "B" },
      { cpf: "2", nome_completo: "C" },
      { cpf: "2", nome_completo: "D" },
    ]);
    expect(r).toHaveLength(2);
  });
});
