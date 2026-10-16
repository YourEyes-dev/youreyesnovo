/**
 * Respostas fictícias da EMPRESA DE DEMONSTRAÇÃO (só ambiente de teste).
 *
 * Gera, de forma determinística (semente fixa), as respostas SIPRO das duas
 * campanhas da "Metalúrgica Exemplo Ltda" e calcula os indicadores com o
 * MESMO cálculo da tela (`calcularIndicadores`, o que o questionário usa ao
 * enviar). O resultado vive em
 * supabase/functions/seed-demo-empresa/psicossocial-demo.ts, que a função
 * de semeadura lê.
 *
 * Este teste é a guarda de sincronia: se alguém mudar o cálculo do IPS, ele
 * falha até a fixture ser regenerada (para a demo nunca mostrar número que a
 * tela não calcularia). Para regenerar:
 *   GERAR_DEMO=1 npx vitest run src/test/demoPsicossocialFixture.test.ts
 *
 * Nada aqui é dado real: respondentes não têm nome nem CPF, só o GHE.
 */
import { describe, it, expect } from "vitest";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { calcularIndicadores } from "@/hooks/usePsicossocial";
import { getDimensoesByInstrumento } from "@/data/instrumentos";

const ARQUIVO = resolve(__dirname, "../../supabase/functions/seed-demo-empresa/psicossocial-demo.ts");

/** Conteúdo do módulo TS (a função de semeadura importa este arquivo). */
function moduloTs(fixture: unknown): string {
  return (
    "// GERADO por src/test/demoPsicossocialFixture.test.ts — não edite à mão.\n" +
    "// Regenere com: GERAR_DEMO=1 npx vitest run src/test/demoPsicossocialFixture.test.ts\n" +
    "// Respostas FICTÍCIAS (sem nome nem CPF) da empresa de demonstração.\n" +
    "// deno-fmt-ignore-file\n" +
    "export const DEMO_PSICOSSOCIAL = " + JSON.stringify(fixture) + " as const;\n"
  );
}

/** PRNG determinístico (mulberry32). */
function prng(semente: number) {
  let a = semente >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Perfil de RISCO por GHE e dimensão SIPRO: 0 = ótimo, 1 = péssimo.
 * Cenário de marketing: nem tudo verde, nem tudo crítico.
 *  - Produção: ritmo e demanda altos, pouca autonomia (ponto de atenção);
 *  - Manutenção: sobreaviso puxa demanda/recuperação (risco de burnout);
 *  - Logística: estável, monotonia moderada;
 *  - Administrativo: saudável, com leve boreout (sentido/autonomia).
 */
const PERFIS: Record<string, Record<string, number>> = {
  "DEMO-GHE-PROD": {
    sipro_demandas_quantitativas: 0.68, sipro_demandas_cognitivas: 0.5, sipro_demandas_emocionais: 0.42,
    sipro_autonomia_controle: 0.6, sipro_clareza_papeis: 0.38, sipro_reconhecimento_justica: 0.58,
    sipro_relacionamentos_suporte: 0.4, sipro_sentido_engajamento: 0.4, sipro_recuperacao_equilibrio: 0.55,
    sipro_sinais_precoces: 0.45,
  },
  "DEMO-GHE-MANUT": {
    sipro_demandas_quantitativas: 0.72, sipro_demandas_cognitivas: 0.62, sipro_demandas_emocionais: 0.5,
    sipro_autonomia_controle: 0.35, sipro_clareza_papeis: 0.42, sipro_reconhecimento_justica: 0.5,
    sipro_relacionamentos_suporte: 0.35, sipro_sentido_engajamento: 0.3, sipro_recuperacao_equilibrio: 0.7,
    sipro_sinais_precoces: 0.55,
  },
  "DEMO-GHE-LOG": {
    sipro_demandas_quantitativas: 0.45, sipro_demandas_cognitivas: 0.3, sipro_demandas_emocionais: 0.3,
    sipro_autonomia_controle: 0.45, sipro_clareza_papeis: 0.3, sipro_reconhecimento_justica: 0.42,
    sipro_relacionamentos_suporte: 0.28, sipro_sentido_engajamento: 0.45, sipro_recuperacao_equilibrio: 0.35,
    sipro_sinais_precoces: 0.28,
  },
  "DEMO-GHE-ADM": {
    sipro_demandas_quantitativas: 0.38, sipro_demandas_cognitivas: 0.35, sipro_demandas_emocionais: 0.25,
    sipro_autonomia_controle: 0.3, sipro_clareza_papeis: 0.22, sipro_reconhecimento_justica: 0.3,
    sipro_relacionamentos_suporte: 0.2, sipro_sentido_engajamento: 0.42, sipro_recuperacao_equilibrio: 0.3,
    sipro_sinais_precoces: 0.22,
  },
};

/** Respondentes por GHE em cada campanha (anterior tem menos adesão). */
const DISTRIBUICAO = {
  atual: { "DEMO-GHE-PROD": 16, "DEMO-GHE-MANUT": 8, "DEMO-GHE-LOG": 8, "DEMO-GHE-ADM": 9 },
  anterior: { "DEMO-GHE-PROD": 12, "DEMO-GHE-MANUT": 6, "DEMO-GHE-LOG": 6, "DEMO-GHE-ADM": 7 },
} as const;

/** Campanha anterior: cenário um pouco pior (evolução positiva no Histórico IPS). */
const PIORA_ANTERIOR = 0.08;

export interface RespostaDemo {
  ghe_codigo: string;
  respostas: Record<string, number>;
  indicadores: unknown;
  tempo_resposta_segundos: number;
}

function gerarCampanha(chave: "atual" | "anterior", semente: number): RespostaDemo[] {
  const rnd = prng(semente);
  const dims = getDimensoesByInstrumento("sipro");
  const lista: RespostaDemo[] = [];
  for (const [ghe, qtd] of Object.entries(DISTRIBUICAO[chave])) {
    for (let k = 0; k < qtd; k++) {
      // Cada pessoa tem um "humor" próprio: uns veem tudo melhor, outros pior.
      const pessoa = (rnd() - 0.5) * 0.3;
      const respostas: Record<string, number> = {};
      for (const d of dims) {
        const base = PERFIS[ghe][d.id] ?? 0.4;
        for (const p of d.perguntas) {
          let risco = base + pessoa + (rnd() - 0.5) * 0.35 + (chave === "anterior" ? PIORA_ANTERIOR : 0);
          risco = Math.min(1, Math.max(0, risco));
          const valorRisco = Math.round(risco * 4); // 0..4, alto = pior
          // Pergunta protetora (invertida): alto = melhor.
          respostas[p.id] = (p as { invertida?: boolean }).invertida ? 4 - valorRisco : valorRisco;
        }
      }
      lista.push({
        ghe_codigo: ghe,
        respostas,
        indicadores: JSON.parse(JSON.stringify(calcularIndicadores(respostas, "sipro", []))),
        tempo_resposta_segundos: 420 + Math.round(rnd() * 600),
      });
    }
  }
  return lista;
}

function gerarFixture() {
  return {
    instrumento: "sipro",
    gerado_por: "src/test/demoPsicossocialFixture.test.ts",
    atual: gerarCampanha("atual", 20261002),
    anterior: gerarCampanha("anterior", 20260402),
  };
}

const media = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length;
const ips = (r: RespostaDemo) => (r.indicadores as { IPS: number }).IPS;

describe("fixture psicossocial da empresa de demonstração", () => {
  const fixture = gerarFixture();

  if (process.env.GERAR_DEMO === "1") {
    writeFileSync(ARQUIVO, moduloTs(fixture));
  }

  it("está em sincronia com o cálculo da tela (regenere com GERAR_DEMO=1)", () => {
    expect(existsSync(ARQUIVO)).toBe(true);
    expect(readFileSync(ARQUIVO, "utf8")).toBe(moduloTs(fixture));
  });

  it("~40 respostas na campanha atual, todas as perguntas SIPRO respondidas na escala 0–4", () => {
    const totalPerguntas = getDimensoesByInstrumento("sipro").reduce((s, d) => s + d.perguntas.length, 0);
    expect(fixture.atual.length).toBeGreaterThanOrEqual(38);
    expect(fixture.atual.length).toBeLessThanOrEqual(45);
    for (const r of [...fixture.atual, ...fixture.anterior]) {
      expect(Object.keys(r.respostas)).toHaveLength(totalPerguntas);
      for (const v of Object.values(r.respostas)) expect(v >= 0 && v <= 4).toBe(true);
    }
  });

  it("cenário de marketing: nem tudo verde, nem tudo crítico, e evolução positiva", () => {
    const geral = media(fixture.atual.map(ips));
    const anterior = media(fixture.anterior.map(ips));
    const porGhe = Object.fromEntries(
      Object.keys(PERFIS).map((g) => [g, media(fixture.atual.filter((r) => r.ghe_codigo === g).map(ips))]),
    );
    // Geral em "atenção/estável" (50–79), melhor que a campanha anterior.
    expect(geral).toBeGreaterThanOrEqual(50);
    expect(geral).toBeLessThan(80);
    expect(geral).toBeGreaterThan(anterior + 2);
    // Há GHE pior e GHE melhor (contraste nos painéis Por GHE).
    const valores = Object.values(porGhe);
    expect(Math.max(...valores) - Math.min(...valores)).toBeGreaterThan(8);
    expect(Math.min(...valores)).toBeGreaterThanOrEqual(35); // nada crítico
  });
});
