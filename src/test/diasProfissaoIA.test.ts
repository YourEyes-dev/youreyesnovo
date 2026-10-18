import { describe, it, expect } from "vitest";
import {
  MAX_CARGOS_POR_CHAMADA, dataValida, montarPrompt, prepararCargos, sanitizarResultados,
} from "../../supabase/functions/_shared/dias-profissao";
import { buscarDiaProfissaoDaEmpresa, normalizarCargo, type DiaProfissaoEmpresa } from "@/lib/diasProfissao";
import { calcularCelebracoes, montarEventosCalendario, type PessoaCelebravel } from "@/lib/celebracoes";

describe("prepararCargos", () => {
  it("tira vazios e repetidos, normaliza espaços e limita a quantidade", () => {
    expect(prepararCargos(["  Motorista ", "motorista", "", "Analista   de RH", 5, null])).toEqual(["Motorista", "Analista de RH"]);
    const muitos = Array.from({ length: 80 }, (_, i) => `Cargo ${i}`);
    expect(prepararCargos(muitos)).toHaveLength(MAX_CARGOS_POR_CHAMADA);
    expect(prepararCargos("não é lista")).toEqual([]);
    expect(prepararCargos(["x".repeat(300)])[0]).toHaveLength(80);
  });
  it("o prompt lista os cargos numerados", () => {
    expect(montarPrompt(["A", "B"])).toBe("Cargos da empresa:\n1. A\n2. B");
  });
});

describe("dataValida", () => {
  it("rejeita datas impossíveis e aceita 29/02", () => {
    expect(dataValida(2, 29)).toBe(true);
    expect(dataValida(2, 30)).toBe(false);
    expect(dataValida(4, 31)).toBe(false);
    expect(dataValida(13, 1)).toBe(false);
    expect(dataValida(0, 10)).toBe(false);
    expect(dataValida("7", 25)).toBe(false);
    expect(dataValida(7.5, 25)).toBe(false);
    expect(dataValida(7, 25)).toBe(true);
  });
});

describe("sanitizarResultados: nada da IA vale sem validação", () => {
  const cargos = ["Motorista", "Analista de RH", "Coordenador Interno"];

  it("mantém na ordem enviada e aceita data válida", () => {
    const r = sanitizarResultados(cargos, {
      resultados: [
        { cargo: "Analista de RH", profissao: "Profissional de RH", nome_data: "Dia do Profissional de RH", mes: 12, dia: 3, confianca: "media", base: "Data consagrada" },
        { cargo: "motorista", profissao: "Motorista", nome_data: "Dia do Motorista", mes: 7, dia: 25, confianca: "alta", base: "Lei 13.103/2015" },
      ],
    });
    expect(r.map((x) => x.cargo)).toEqual(cargos);
    expect(r[0]).toMatchObject({ mes: 7, dia: 25, confianca: "alta", nome_data: "Dia do Motorista" });
    expect(r[1]).toMatchObject({ mes: 12, dia: 3, confianca: "media" });
  });

  it("cargo que a IA não devolveu ou sem data vira 'sem data conhecida'", () => {
    const r = sanitizarResultados(cargos, { resultados: [{ cargo: "Coordenador Interno", profissao: null, nome_data: null, mes: null, dia: null }] });
    expect(r[2]).toMatchObject({ mes: null, dia: null, nome_data: null });
    expect(r[0]).toMatchObject({ mes: null, dia: null }); // não veio
  });

  it("data impossível, sem nome da data ou com tipo errado é descartada", () => {
    const r = sanitizarResultados(["A", "B", "C"], {
      resultados: [
        { cargo: "A", nome_data: "Dia do A", mes: 2, dia: 31, confianca: "alta" },
        { cargo: "B", nome_data: "", mes: 5, dia: 5, confianca: "alta" },
        { cargo: "C", nome_data: "Dia do C", mes: "5", dia: "5", confianca: "alta" },
      ],
    });
    expect(r.every((x) => x.mes === null && x.dia === null)).toBe(true);
  });

  it("cargo que não foi pedido é ignorado e confiança inválida cai para baixa", () => {
    const r = sanitizarResultados(["Motorista"], {
      resultados: [
        { cargo: "Presidente", nome_data: "Dia X", mes: 1, dia: 1, confianca: "alta" },
        { cargo: "Motorista", nome_data: "Dia do Motorista", mes: 7, dia: 25, confianca: "certeza absoluta" },
      ],
    });
    expect(r).toHaveLength(1);
    expect(r[0].confianca).toBe("baixa");
  });

  it("lixo no lugar do JSON não quebra", () => {
    expect(sanitizarResultados(["A"], null)[0].mes).toBeNull();
    expect(sanitizarResultados(["A"], { resultados: "x" })[0].mes).toBeNull();
    expect(sanitizarResultados(["A"], { resultados: [null, 3, "a"] })[0].mes).toBeNull();
  });
});

describe("catálogo da empresa sobre o catálogo padrão", () => {
  const aprovado: DiaProfissaoEmpresa = { cargo_chave: normalizarCargo("Analista de RH"), status: "aprovado", nome_data: "Dia do Profissional de RH", mes: 12, dia: 3 };

  it("normaliza acento, caixa e espaços", () => {
    expect(normalizarCargo("  Técnico   de Segurança ")).toBe("tecnico de seguranca");
  });

  it("aprovado vale; sem decisão cai no catálogo padrão; sem nenhum dos dois é nulo", () => {
    expect(buscarDiaProfissaoDaEmpresa("analista de rh", [aprovado])).toEqual({ mes: 12, dia: 3, nome: "Dia do Profissional de RH" });
    expect(buscarDiaProfissaoDaEmpresa("Técnico de Segurança do Trabalho", [aprovado])?.mes).toBe(11);
    expect(buscarDiaProfissaoDaEmpresa("Cargo Inventado Xyz", [aprovado])).toBeNull();
  });

  it("rejeitado desliga até o que o catálogo padrão casaria", () => {
    const rejeitado: DiaProfissaoEmpresa = { cargo_chave: normalizarCargo("Técnico de Segurança do Trabalho"), status: "rejeitado", nome_data: null, mes: null, dia: null };
    expect(buscarDiaProfissaoDaEmpresa("Técnico de Segurança do Trabalho", [rejeitado])).toBeNull();
  });

  it("integra com as celebrações: cargo aprovado pela IA aparece na lista e no calendário, rejeitado some", () => {
    const pessoa = (id: string, cargo: string): PessoaCelebravel => ({ id, nome_completo: id, data_nascimento: null, data_admissao: null, cargo });
    const pessoas = [pessoa("a", "Analista de RH"), pessoa("b", "Técnico de Segurança do Trabalho")];
    const hoje = new Date(2026, 10, 20); // 20/11, perto de 03/12 e 27/11
    const rejeitado: DiaProfissaoEmpresa = { cargo_chave: normalizarCargo("Técnico de Segurança do Trabalho"), status: "rejeitado", nome_data: null, mes: null, dia: null };

    const sem = calcularCelebracoes(pessoas, { dias_antecedencia_acao: 30 }, hoje, []);
    expect(sem.map((c) => c.nome)).toEqual(["Dia do Técnico de Segurança do Trabalho"]);

    const com = calcularCelebracoes(pessoas, { dias_antecedencia_acao: 30 }, hoje, [aprovado, rejeitado]);
    expect(com.map((c) => c.nome)).toEqual(["Dia do Profissional de RH"]);

    const cal = montarEventosCalendario({
      pessoas, config: null, acoes: [], rituais: [], datas: [], diasProfissao: [aprovado],
      de: new Date(2026, 11, 1), ate: new Date(2026, 11, 31),
    });
    expect(cal.map((e) => e.titulo)).toContain("Dia do Profissional de RH");
  });
});
