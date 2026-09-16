import { describe, it, expect } from "vitest";
import jsPDF from "jspdf";
import { desenharCartaoPonto } from "@/lib/ponto/cartaoPonto";

const dia = (d: string, extra: Record<string, unknown> = {}) => ({
  dia: d, trabalhado_min: 480, jornada_min: 480, saldo_min: 0,
  protegido: false, equalizacao: false, excedente_retido_min: 0,
  marcacoes: [{ hora: "08:00", origem: "O" as const }, { hora: "17:00", origem: "O" as const }],
  ...extra,
});

const base = (dias: unknown[]) => ({
  incluirBanco: false,
  empregador: { razaoSocial: "Empresa Staging LTDA" },
  empregado: { nome: "Fulano de Teste", cpf: "900.000.001-53", admissao: null },
  competencia: "2026-08",
  dias,
});

describe("cartão de ponto — intervalo pré-assinalado", () => {
  it("desenha sem erro com e sem declaração", () => {
    const doc = new jsPDF();
    desenharCartaoPonto(doc, base([
      dia("2026-08-03"),
      dia("2026-08-04", { intervalo_origem: "pre_assinalado", intervalo_pre_assinalado_min: 60 }),
      dia("2026-08-05", { intervalo_origem: "marcado" }),
    ]) as never);
    expect(doc.output("datauristring").length).toBeGreaterThan(1000);
  });

  /**
   * Regressão do relatório de agosto/2026: a nota do intervalo declarado saía
   * numa linha PRÓPRIA dentro da célula de marcações. Num mês cheio isso
   * dobrava a altura da tabela, estourava o espaço reservado para o rodapé e
   * o bloco de legenda/assinaturas era impresso por cima do resumo de horas.
   *
   * O mês inteiro com declaração em todos os dias tem de continuar cabendo em
   * uma folha — é a mesma condição que garante que nada se sobrepõe.
   */
  it("mês cheio com declaração em todos os dias cabe em uma página", () => {
    const doc = new jsPDF();
    const dias = Array.from({ length: 31 }, (_, i) =>
      dia(`2026-08-${String(i + 1).padStart(2, "0")}`, {
        intervalo_origem: "pre_assinalado",
        intervalo_pre_assinalado_min: 60,
      }),
    );
    desenharCartaoPonto(doc, base(dias) as never);
    expect(doc.getNumberOfPages()).toBe(1);
  });

  it("dia sem batida com declaração não quebra o desenho", () => {
    const doc = new jsPDF();
    desenharCartaoPonto(doc, base([
      dia("2026-08-01", {
        marcacoes: [], trabalhado_min: 0, jornada_min: 0,
        intervalo_origem: "pre_assinalado", intervalo_pre_assinalado_min: 60,
      }),
      dia("2026-08-03", { intervalo_origem: "pre_assinalado", intervalo_pre_assinalado_min: 60 }),
    ]) as never);
    expect(doc.getNumberOfPages()).toBe(1);
  });
});
