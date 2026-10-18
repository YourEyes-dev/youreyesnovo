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

import {
  calcularCobertura,
  celebracoesNoIntervalo,
  datasAoRegistrarRitual,
  montarEventosCalendario,
  proximaExecucaoRitual,
} from "@/lib/celebracoes";
import type { CulturaRitual } from "@/types/cultura";

describe("celebracoesNoIntervalo", () => {
  it("cobre um mês inteiro, inclusive datas já passadas", () => {
    const r = celebracoesNoIntervalo(
      [pessoa({ data_nascimento: "1990-10-05" })],
      null,
      new Date(2026, 9, 1),
      new Date(2026, 9, 31),
      new Date(2026, 9, 18),
    );
    expect(r).toHaveLength(1);
    expect(r[0].diasRestantes).toBe(-13);
  });

  it("intervalo que atravessa o ano usa o ano de cada data", () => {
    const r = celebracoesNoIntervalo(
      [pessoa({ data_admissao: "2021-01-10" })],
      null,
      new Date(2025, 11, 20),
      new Date(2026, 0, 20),
    );
    expect(r.map((c) => c.anos)).toEqual([5]);
  });
});

describe("CA-006: calendário e lista mostram os mesmos itens", () => {
  it("mesmo intervalo, mesmas celebrações detectadas", () => {
    const pessoas = [
      pessoa({ id: "a", data_nascimento: "1990-10-20", data_admissao: "2020-10-25" }),
      pessoa({ id: "b", nome_completo: "Bruno", data_nascimento: "1985-11-02" }),
    ];
    const hoje = new Date(2026, 9, 18);
    const lista = calcularCelebracoes(pessoas, { dias_antecedencia_acao: 20 }, hoje).map((c) => c.chave);
    const cal = montarEventosCalendario({
      pessoas, config: { dias_antecedencia_acao: 20 }, acoes: [], rituais: [], datas: [],
      de: hoje, ate: new Date(2026, 10, 7),
    }).map((e) => e.id);
    expect(cal.sort()).toEqual(lista.sort());
  });

  it("ação manual, data configurada e ritual entram nos grupos certos", () => {
    const ev = montarEventosCalendario({
      pessoas: [],
      acoes: [{ id: "x", tipo: "data_configurada", titulo: "Almoço", colaborador_nome: null, data_referencia: "2026-10-10", status: "pendente" } as CulturaAcao],
      rituais: [{ id: "r", nome: "Roda", frequencia: "mensal", ativo: true, ultima_execucao: null, proxima_execucao: "2026-10-12" } as CulturaRitual],
      datas: [{ id: "d", titulo: "Dia do Cliente", ativo: true, mes: 10, dia: 15, data_especifica: null }],
      de: new Date(2026, 9, 1), ate: new Date(2026, 9, 31),
    });
    expect(ev.map((e) => e.grupo)).toEqual(["datas", "rituais", "datas"]);
  });

  it("ação cancelada não aparece", () => {
    const ev = montarEventosCalendario({
      pessoas: [],
      acoes: [{ id: "x", tipo: "data_configurada", titulo: "Almoço", colaborador_nome: null, data_referencia: "2026-10-10", status: "cancelada" } as CulturaAcao],
      rituais: [], datas: [], de: new Date(2026, 9, 1), ate: new Date(2026, 9, 31),
    });
    expect(ev).toHaveLength(0);
  });
});

describe("rituais", () => {
  it("usa a próxima agendada; senão soma a frequência à última", () => {
    expect(proximaExecucaoRitual({ frequencia: "mensal", ultima_execucao: "2026-10-01", proxima_execucao: "2026-10-20" })!.getDate()).toBe(20);
    const d = proximaExecucaoRitual({ frequencia: "semanal", ultima_execucao: "2026-10-01", proxima_execucao: null })!;
    expect([d.getMonth(), d.getDate()]).toEqual([9, 8]);
    expect(proximaExecucaoRitual({ frequencia: "mensal", ultima_execucao: null, proxima_execucao: null })).toBeNull();
  });
  it("registrar realização grava última e próxima", () => {
    expect(datasAoRegistrarRitual("quinzenal", new Date(2026, 9, 18, 14))).toEqual({
      ultima_execucao: "2026-10-18",
      proxima_execucao: "2026-11-01",
    });
  });
});

describe("calcularCobertura", () => {
  const acao = (nome: string, status: string, data: string) =>
    ({ status, colaborador_nome: nome, data_execucao: null, data_referencia: data }) as CulturaAcao;

  it("conta só concluídas dos últimos 12 meses", () => {
    const pessoas = [pessoa({ nome_completo: "Ana" }), pessoa({ id: "b", nome_completo: "Bia" }), pessoa({ id: "c", nome_completo: "Caio" })];
    const c = calcularCobertura(
      pessoas,
      [acao("Ana", "concluida", "2026-03-01"), acao("Bia", "pendente", "2026-03-01"), acao("Caio", "concluida", "2024-01-01")],
      new Date(2026, 9, 18),
    );
    expect(c.cobertas).toBe(1);
    expect(c.percentual).toBe(33);
    expect(c.semCelebracao.map((p) => p.nome_completo)).toEqual(["Bia", "Caio"]);
  });

  it("CA-008: sem colaboradores ou sem ações dá 0% sem erro", () => {
    expect(calcularCobertura([], [], new Date()).percentual).toBe(0);
    expect(calcularCobertura([pessoa({})], [], new Date()).percentual).toBe(0);
  });
});

import { montarAlertas, quantidadeDeVariantes, sugerirMensagem } from "@/lib/celebracoes";

describe("sugerirMensagem", () => {
  it("usa o nome e os anos, e nunca a idade", () => {
    const m = sugerirMensagem({ tipo: "tempo_casa", nome: "Ana", anos: 5 }, "leve");
    expect(m).toContain("Ana");
    expect(m).toContain("5 anos");
    const a = sugerirMensagem({ tipo: "aniversario", nome: "Bruno" }, "formal");
    expect(a).toContain("Bruno");
    expect(a).not.toMatch(/\d+ anos/);
  });
  it("singular em 1 ano e variantes rotacionam", () => {
    expect(sugerirMensagem({ tipo: "tempo_casa", nome: "Ana", anos: 1 }, "leve")).toContain("1 ano ");
    const n = quantidadeDeVariantes("aniversario", "leve");
    expect(sugerirMensagem({ tipo: "aniversario", nome: "X" }, "leve", 0)).toBe(sugerirMensagem({ tipo: "aniversario", nome: "X" }, "leve", n));
  });
});

describe("montarAlertas", () => {
  const hoje = new Date(2026, 9, 18);
  it("alerta de atrasadas só conta pendentes com data vencida (hoje não é atraso)", () => {
    const a = montarAlertas({
      acoes: [
        { status: "pendente", data_referencia: "2026-10-10" },
        { status: "pendente", data_referencia: "2026-10-18" },
        { status: "concluida", data_referencia: "2026-10-01" },
      ],
      cobertura: { total: 10, percentual: 100 },
      metaCobertura: 95,
      hoje,
    });
    expect(a.map((x) => x.id)).toEqual(["atrasadas"]);
  });
  it("alerta de cobertura abaixo da meta, mas não sem colaboradores", () => {
    expect(montarAlertas({ acoes: [], cobertura: { total: 10, percentual: 40 }, metaCobertura: 95, hoje }).map((x) => x.id)).toEqual(["cobertura"]);
    expect(montarAlertas({ acoes: [], cobertura: { total: 0, percentual: 0 }, metaCobertura: 95, hoje })).toEqual([]);
  });
});
