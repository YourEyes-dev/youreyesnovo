import { describe, it, expect } from "vitest";
import { calcularCompletude, type CompletudeInput } from "@/lib/completudeFuncao";

// ============================================================
// Testes de tabela-verdade — completude de função (O1-A)
// ============================================================

const vazio: CompletudeInput = {
  objetivoDefinido: false,
  atividades: 0,
  competencias: 0,
  atividadesComPop: 0,
  episVinculados: 0,
  manualGerado: false,
};

describe("calcularCompletude", () => {
  it("função totalmente vazia: 0% e nenhum item concluído", () => {
    const r = calcularCompletude(vazio);
    expect(r.total).toBe(6); // sem perfil ideal (Onda 3 omitida)
    expect(r.concluidos).toBe(0);
    expect(r.percentual).toBe(0);
    expect(r.completo).toBe(false);
  });

  it("função totalmente preenchida: 100% e completo", () => {
    const r = calcularCompletude({
      objetivoDefinido: true,
      atividades: 5,
      competencias: 3,
      atividadesComPop: 5,
      episVinculados: 2,
      manualGerado: true,
    });
    expect(r.concluidos).toBe(6);
    expect(r.percentual).toBe(100);
    expect(r.completo).toBe(true);
  });

  it("POPs só concluem quando TODAS as atividades têm POP", () => {
    const parcial = calcularCompletude({ ...vazio, atividades: 4, atividadesComPop: 3 });
    const pops = parcial.itens.find((i) => i.chave === "pops")!;
    expect(pops.concluido).toBe(false);
    expect(pops.detalhe).toBe("3 de 4");

    const total = calcularCompletude({ ...vazio, atividades: 4, atividadesComPop: 4 });
    expect(total.itens.find((i) => i.chave === "pops")!.concluido).toBe(true);
  });

  it("POPs ficam pendentes quando não há atividades (sem divisão por zero)", () => {
    const r = calcularCompletude({ ...vazio, atividades: 0, atividadesComPop: 0 });
    const pops = r.itens.find((i) => i.chave === "pops")!;
    expect(pops.concluido).toBe(false);
    expect(pops.detalhe).toBe("0 de 0");
    expect(Number.isNaN(r.percentual)).toBe(false);
  });

  it("clampa atividadesComPop acima do total de atividades", () => {
    const r = calcularCompletude({ ...vazio, atividades: 2, atividadesComPop: 9 });
    const pops = r.itens.find((i) => i.chave === "pops")!;
    expect(pops.detalhe).toBe("2 de 2");
    expect(pops.concluido).toBe(true);
  });

  it("percentual arredonda (1 de 6 => 17%)", () => {
    const r = calcularCompletude({ ...vazio, objetivoDefinido: true });
    expect(r.concluidos).toBe(1);
    expect(r.percentual).toBe(17); // 16.66 -> 17
  });

  it("perfil ideal é omitido quando undefined", () => {
    const r = calcularCompletude(vazio);
    expect(r.itens.some((i) => i.chave === "perfil_ideal")).toBe(false);
    expect(r.total).toBe(6);
  });

  it("perfil ideal entra na conta quando informado (Onda 3)", () => {
    const semPerfil = calcularCompletude({
      objetivoDefinido: true, atividades: 1, competencias: 1,
      atividadesComPop: 1, episVinculados: 1, manualGerado: true,
    });
    expect(semPerfil.percentual).toBe(100);

    const comPerfilPendente = calcularCompletude({
      objetivoDefinido: true, atividades: 1, competencias: 1,
      atividadesComPop: 1, episVinculados: 1, manualGerado: true,
      perfilIdealDefinido: false,
    });
    expect(comPerfilPendente.total).toBe(7);
    expect(comPerfilPendente.concluidos).toBe(6);
    expect(comPerfilPendente.completo).toBe(false);

    const comPerfilOk = calcularCompletude({
      objetivoDefinido: true, atividades: 1, competencias: 1,
      atividadesComPop: 1, episVinculados: 1, manualGerado: true,
      perfilIdealDefinido: true,
    });
    expect(comPerfilOk.total).toBe(7);
    expect(comPerfilOk.completo).toBe(true);
  });

  it("valores negativos são tratados como zero", () => {
    const r = calcularCompletude({ ...vazio, atividades: -3, competencias: -1, episVinculados: -5 });
    expect(r.itens.find((i) => i.chave === "atividades")!.detalhe).toBe("0");
    expect(r.itens.find((i) => i.chave === "atividades")!.concluido).toBe(false);
  });
});
