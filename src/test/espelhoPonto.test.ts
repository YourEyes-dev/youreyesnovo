import { describe, it, expect } from "vitest";
import jsPDF from "jspdf";
import { desenharEspelhoPonto } from "@/lib/ponto/cartaoPonto";

const dia = (d: string, extra: Record<string, unknown> = {}) => ({
  dia: d, trabalhado_min: 480, jornada_min: 480, saldo_min: 0,
  protegido: false, equalizacao: false, excedente_retido_min: 0,
  marcacoes: [{ hora: "08:00", origem: "O" as const }, { hora: "12:00", origem: "O" as const },
    { hora: "13:00", origem: "O" as const }, { hora: "17:00", origem: "O" as const }],
  ...extra,
});

const base = (dias: unknown[]) => ({
  incluirBanco: false,
  empregador: { razaoSocial: "Empresa Staging LTDA" },
  empregado: { nome: "Fulano de Teste", cpf: "900.000.001-53", admissao: null },
  competencia: "2026-08",
  dias,
});

describe("espelho de ponto — modelo legal (variante)", () => {
  it("desenha sem erro, incluindo crédito, débito e intervalo pré-assinalado", () => {
    const doc = new jsPDF();
    desenharEspelhoPonto(doc, base([
      dia("2026-08-03", { trabalhado_min: 500, saldo_min: 20 }), // crédito (+)
      dia("2026-08-04", { trabalhado_min: 460, saldo_min: -20 }), // débito (-)
      dia("2026-08-05", {
        marcacoes: [{ hora: "08:00", origem: "O" as const }, { hora: "17:00", origem: "O" as const }],
        intervalo_origem: "pre_assinalado", intervalo_pre_assinalado_min: 60,
      }),
    ]) as never);
    expect(doc.output("datauristring").length).toBeGreaterThan(1000);
  });

  // Mesma garantia do cartão: o mês inteiro cabe em UMA página — as colunas de
  // entrada/saída não podem estourar o espaço reservado para o rodapé.
  it("mês cheio cabe em uma página", () => {
    const doc = new jsPDF();
    const dias = Array.from({ length: 31 }, (_, i) =>
      dia(`2026-08-${String(i + 1).padStart(2, "0")}`, { saldo_min: i % 2 ? 7 : -7 }),
    );
    desenharEspelhoPonto(doc, base(dias) as never);
    expect(doc.getNumberOfPages()).toBe(1);
  });

  it("dia sem batida e dia com 5+ batidas (excedentes) não quebram o desenho", () => {
    const doc = new jsPDF();
    desenharEspelhoPonto(doc, base([
      dia("2026-08-01", { marcacoes: [], trabalhado_min: 0, jornada_min: 0 }),
      dia("2026-08-02", {
        marcacoes: [
          { hora: "08:00", origem: "O" as const }, { hora: "12:00", origem: "O" as const },
          { hora: "13:00", origem: "O" as const }, { hora: "15:00", origem: "A" as const },
          { hora: "15:20", origem: "O" as const }, { hora: "17:30", origem: "O" as const },
        ],
        trabalhado_min: 520, saldo_min: 40,
      }),
    ]) as never);
    expect(doc.getNumberOfPages()).toBe(1);
  });
});
