import { describe, it, expect } from "vitest";
import {
  construirIndiceEncerrados,
  colaboradorAtivo,
  type AdmissaoStatusMinima,
} from "@/lib/colaboradorAtivo";

const adm = (o: Partial<AdmissaoStatusMinima>): AdmissaoStatusMinima => ({
  cpf: null,
  nome_completo: null,
  status: "concluido",
  ...o,
});

describe("colaboradorAtivo (lembretes do Início não mostram desligados)", () => {
  it("esconde item cujo CPF bate com um colaborador desligado", () => {
    const idx = construirIndiceEncerrados([
      adm({ cpf: "900.000.001-91", nome_completo: "Ana Souza", status: "desligado" }),
    ]);
    expect(colaboradorAtivo(idx, { cpf: "90000000191", nome: "Ana Souza" })).toBe(false);
  });

  it("esconde item de admissão reprovada", () => {
    const idx = construirIndiceEncerrados([adm({ cpf: "90000000272", status: "reprovado" })]);
    expect(colaboradorAtivo(idx, { cpf: "900.000.002-72" })).toBe(false);
  });

  it("mantém colaborador concluído (ativo)", () => {
    const idx = construirIndiceEncerrados([adm({ cpf: "90000000353", status: "concluido" })]);
    expect(colaboradorAtivo(idx, { cpf: "90000000353" })).toBe(true);
  });

  it("mantém admissão ainda em andamento (documento pendente é pendência legítima)", () => {
    const idx = construirIndiceEncerrados([adm({ cpf: "90000000434", status: "em_andamento" })]);
    expect(colaboradorAtivo(idx, { cpf: "90000000434" })).toBe(true);
  });

  it("CPF desconhecido no índice → mostra (não regride quem não enxerga a base)", () => {
    const idx = construirIndiceEncerrados([]);
    expect(colaboradorAtivo(idx, { cpf: "90000000999", nome: "Fulano" })).toBe(true);
  });

  it("sem CPF: esconde pelo nome só quando o nome é exclusivamente de desligado", () => {
    const idx = construirIndiceEncerrados([
      adm({ nome_completo: "Bruno Lima", status: "desligado" }),
    ]);
    expect(colaboradorAtivo(idx, { nome: "Bruno Lima" })).toBe(false);
  });

  it("sem CPF: NÃO esconde homônimo que ainda está ativo", () => {
    const idx = construirIndiceEncerrados([
      adm({ nome_completo: "Bruno Lima", status: "desligado" }),
      adm({ nome_completo: "Bruno Lima", status: "concluido" }),
    ]);
    expect(colaboradorAtivo(idx, { nome: "Bruno Lima" })).toBe(true);
  });

  it("CPF forte vence o nome: item com CPF ativo aparece mesmo havendo homônimo desligado", () => {
    const idx = construirIndiceEncerrados([
      adm({ cpf: "90000000111", nome_completo: "Carla Dias", status: "concluido" }),
      adm({ cpf: "90000000222", nome_completo: "Carla Dias", status: "desligado" }),
    ]);
    expect(colaboradorAtivo(idx, { cpf: "90000000111", nome: "Carla Dias" })).toBe(true);
    expect(colaboradorAtivo(idx, { cpf: "90000000222", nome: "Carla Dias" })).toBe(false);
  });
});
