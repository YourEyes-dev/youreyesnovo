import { describe, it, expect } from "vitest";
import {
  calcularCelebracoes,
  indexarAcoes,
  payloadAcaoDaCelebracao,
  pessoaReservada,
  proximaOcorrencia,
  type PessoaCelebravel,
} from "@/lib/celebracoes";
import type { CulturaAcao } from "@/types/cultura";

const pessoa = (o: Partial<PessoaCelebravel>): PessoaCelebravel => ({
  id: "p1",
  nome_completo: "Ana Souza",
  data_nascimento: null,
  data_admissao: null,
  cargo: null,
  ...o,
});

describe("calcularCelebracoes", () => {
  it("CA-003: 5 anos em janeiro aparece com 5 quando consultado em dezembro", () => {
    const r = calcularCelebracoes(
      [pessoa({ data_admissao: "2021-01-10" })],
      { dias_antecedencia_acao: 30 },
      new Date(2025, 11, 20),
    );
    expect(r).toHaveLength(1);
    expect(r[0].anos).toBe(5);
    expect(r[0].data.getFullYear()).toBe(2026);
  });

  it("aniversário de hoje aparece com 0 dia, mesmo depois da meia-noite", () => {
    const r = calcularCelebracoes(
      [pessoa({ data_nascimento: "1990-10-18" })],
      null,
      new Date(2026, 9, 18, 15, 30),
    );
    expect(r).toHaveLength(1);
    expect(r[0].diasRestantes).toBe(0);
  });

  it("CA-001: tipo desligado na configuração não gera item", () => {
    const base = [pessoa({ data_admissao: "2020-10-20", data_nascimento: "1990-10-20" })];
    const hoje = new Date(2026, 9, 18);
    const r = calcularCelebracoes(base, { tempo_casa_ativo: false }, hoje);
    expect(r.map((c) => c.tipo)).toEqual(["aniversario"]);
  });

  it("CA-002: a janela segue dias_antecedencia_acao", () => {
    const base = [pessoa({ data_nascimento: "1990-10-30" })]; // 12 dias à frente
    const hoje = new Date(2026, 9, 18);
    expect(calcularCelebracoes(base, { dias_antecedencia_acao: 10 }, hoje)).toHaveLength(0);
    expect(calcularCelebracoes(base, { dias_antecedencia_acao: 12 }, hoje)).toHaveLength(1);
  });

  it("não celebra tempo de casa com menos de 1 ano", () => {
    const r = calcularCelebracoes([pessoa({ data_admissao: "2026-10-20" })], null, new Date(2026, 9, 18));
    expect(r).toHaveLength(0);
  });

  it("dia da profissão: uma linha por data, não uma por pessoa", () => {
    const r = calcularCelebracoes(
      [
        pessoa({ id: "a", cargo: "Técnico de Segurança do Trabalho" }),
        pessoa({ id: "b", nome_completo: "Bruno", cargo: "Técnico de Segurança do Trabalho" }),
      ],
      { dias_antecedencia_acao: 60 },
      new Date(2026, 9, 18),
    );
    expect(r.filter((c) => c.tipo === "dia_profissao")).toHaveLength(1);
  });
});

describe("proximaOcorrencia", () => {
  it("29/02 cai em 28/02 em ano não bissexto", () => {
    const d = proximaOcorrencia(2, 29, new Date(2026, 0, 10));
    expect([d.getMonth(), d.getDate()]).toEqual([1, 28]);
  });
  it("29/02 se mantém em ano bissexto", () => {
    const d = proximaOcorrencia(2, 29, new Date(2028, 0, 10));
    expect([d.getMonth(), d.getDate()]).toEqual([1, 29]);
  });
});

describe("trava de duplicidade (RN-004)", () => {
  const acao = (o: Partial<CulturaAcao>) =>
    ({ id: "x", tipo: "aniversario", titulo: "t", colaborador_nome: "Ana Souza", data_referencia: "2026-10-20", status: "pendente", ...o }) as CulturaAcao;

  it("celebração com ação existente é reconhecida pela chave", () => {
    const [c] = calcularCelebracoes([pessoa({ data_nascimento: "1990-10-20" })], null, new Date(2026, 9, 18));
    expect(indexarAcoes([acao({})]).has(c.chave)).toBe(true);
  });

  it("ação cancelada não conta como tratada", () => {
    const [c] = calcularCelebracoes([pessoa({ data_nascimento: "1990-10-20" })], null, new Date(2026, 9, 18));
    expect(indexarAcoes([acao({ status: "cancelada" })]).has(c.chave)).toBe(false);
  });

  it("dia da profissão: a ação criada é reconhecida na rodada seguinte", () => {
    const [c] = calcularCelebracoes(
      [pessoa({ cargo: "Técnico de Segurança do Trabalho" })],
      { dias_antecedencia_acao: 60 },
      new Date(2026, 9, 18),
    );
    const p = payloadAcaoDaCelebracao(c);
    const criada = acao({ tipo: "dia_profissao", titulo: p.titulo!, colaborador_nome: null, data_referencia: p.data_referencia! });
    expect(indexarAcoes([criada]).has(c.chave)).toBe(true);
  });
});

describe("pessoaReservada (RN-006)", () => {
  const prefs = [{ colaborador_id: "p1", colaborador_nome: "Ana Souza", tipo_reconhecimento: "reservado" }];
  it("casa por id", () => expect(pessoaReservada(prefs, "p1", "Outro Nome")).toBe(true));
  it("casa por nome quando não há id", () => expect(pessoaReservada(prefs, undefined, " ana souza ")).toBe(true));
  it("público/tanto faz não restringe", () =>
    expect(pessoaReservada([{ ...prefs[0], tipo_reconhecimento: "publico" }], "p1", "Ana Souza")).toBe(false));
});
