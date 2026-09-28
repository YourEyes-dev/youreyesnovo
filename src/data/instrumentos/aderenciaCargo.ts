// ─────────────────────────────────────────────────────────────────────────────
// Aderência ao estilo da função — comparação DETERMINÍSTICA entre o mapa
// comportamental de uma pessoa e o "perfil ideal" de um cargo (O3-B).
//
// Enquadramento de DESENVOLVIMENTO (decisão do dono, 09/2026): linguagem de
// TENDÊNCIA, nunca de capacidade ou aptidão. Não é score de "adequação"; é onde
// a pessoa tende a fluir e onde pode precisar de mais apoio/energia. Não serve
// para movimentação, promoção ou desligamento (coerente com RN-010).
//
// Regras:
//  • Confiabilidade baixa no mapa da pessoa → NÃO calcula aderência (suprime).
//  • Sem perfil ideal definido para o cargo → indisponível.
//  • Determinística e pura (espelha o estilo de calcularMapa) — testável.
// ─────────────────────────────────────────────────────────────────────────────

import type { Arquetipo, Motor, Modo } from "./mapaComportamental";

export type NivelAderencia = "flui" | "adapta" | "energia";

export interface PerfilIdealCargo {
  arquetipoIdeal: Arquetipo | null;
  motorIdeal: Motor[]; // subconjunto dos motores esperados
  modoIdeal: Modo | "misto" | null;
}

export interface MapaPessoaResumo {
  arquetipos: Arquetipo[]; // predominante(s) — pode ser misto (vizinhos)
  motores: Motor[]; // motores predominantes
  modo: Modo | "misto";
  confiabilidade: "alta" | "baixa";
}

export interface DimensaoAderencia {
  dimensao: "arquetipo" | "motor" | "modo";
  nivel: NivelAderencia;
  frase: string;
}

export interface AderenciaResultado {
  disponivel: boolean;
  motivoIndisponivel?: "confiabilidade_baixa" | "sem_perfil_ideal" | "sem_mapa";
  dimensoes: DimensaoAderencia[];
  nivelGeral?: NivelAderencia;
  resumoGeral?: string;
}

// Eixos de cada arquétipo (Foco × Ritmo), do próprio instrumento. Dois arquétipos
// que compartilham os dois eixos são iguais; um eixo = vizinhos; nenhum = opostos.
const ARQUETIPO_EIXOS: Record<Arquetipo, { foco: "pessoas" | "tarefas"; ritmo: "acelerado" | "ponderado" }> = {
  pioneiro: { foco: "tarefas", ritmo: "acelerado" },
  conector: { foco: "pessoas", ritmo: "acelerado" },
  guardiao: { foco: "pessoas", ritmo: "ponderado" },
  estrategista: { foco: "tarefas", ritmo: "ponderado" },
};

function relacaoArquetipo(a: Arquetipo, b: Arquetipo): NivelAderencia {
  if (a === b) return "flui";
  const ea = ARQUETIPO_EIXOS[a];
  const eb = ARQUETIPO_EIXOS[b];
  const compartilhados = (ea.foco === eb.foco ? 1 : 0) + (ea.ritmo === eb.ritmo ? 1 : 0);
  return compartilhados >= 1 ? "adapta" : "energia";
}

const PESO: Record<NivelAderencia, number> = { flui: 2, adapta: 1, energia: 0 };

function melhorNivel(niveis: NivelAderencia[]): NivelAderencia {
  return niveis.reduce((melhor, n) => (PESO[n] > PESO[melhor] ? n : melhor), "energia" as NivelAderencia);
}

function aderenciaArquetipo(pessoa: Arquetipo[], ideal: Arquetipo): DimensaoAderencia {
  // Com perfil misto, considera o MELHOR encaixe entre os arquétipos da pessoa.
  const nivel = pessoa.length ? melhorNivel(pessoa.map((a) => relacaoArquetipo(a, ideal))) : "energia";
  const frase =
    nivel === "flui"
      ? "O arquétipo da pessoa flui naturalmente com o esperado para a função."
      : nivel === "adapta"
        ? "O arquétipo é vizinho do esperado — a pessoa tende a se adaptar."
        : "O arquétipo é oposto do esperado — tende a exigir mais energia.";
  return { dimensao: "arquetipo", nivel, frase };
}

function aderenciaMotor(pessoa: Motor[], ideal: Motor[]): DimensaoAderencia {
  const cruza = pessoa.some((m) => ideal.includes(m));
  const nivel: NivelAderencia = cruza ? "flui" : "energia";
  const frase = cruza
    ? "O motor de decisão conversa com o esperado para a função."
    : "O motor de decisão difere do esperado — pode pedir mais energia.";
  return { dimensao: "motor", nivel, frase };
}

function aderenciaModo(pessoa: Modo | "misto", ideal: Modo | "misto"): DimensaoAderencia {
  let nivel: NivelAderencia;
  if (pessoa === ideal) nivel = "flui";
  else if (pessoa === "misto" || ideal === "misto") nivel = "adapta";
  else nivel = "energia"; // constante x cadenciado
  const frase =
    nivel === "flui"
      ? "O modo de contexto coincide com o esperado."
      : nivel === "adapta"
        ? "O modo tem flexibilidade (misto) em relação ao esperado."
        : "O modo é oposto do esperado — tende a exigir mais energia.";
  return { dimensao: "modo", nivel, frase };
}

/**
 * Calcula a aderência de desenvolvimento entre o mapa da pessoa e o perfil ideal
 * do cargo. Pura e determinística. Suprime quando a confiabilidade é baixa.
 */
export function calcularAderencia(
  pessoa: MapaPessoaResumo | null,
  ideal: PerfilIdealCargo | null,
): AderenciaResultado {
  if (!pessoa) return { disponivel: false, motivoIndisponivel: "sem_mapa", dimensoes: [] };
  if (pessoa.confiabilidade === "baixa") {
    return { disponivel: false, motivoIndisponivel: "confiabilidade_baixa", dimensoes: [] };
  }

  const temIdeal = !!ideal && (!!ideal.arquetipoIdeal || (ideal.motorIdeal?.length ?? 0) > 0 || !!ideal.modoIdeal);
  if (!ideal || !temIdeal) {
    return { disponivel: false, motivoIndisponivel: "sem_perfil_ideal", dimensoes: [] };
  }

  const dimensoes: DimensaoAderencia[] = [];
  if (ideal.arquetipoIdeal) dimensoes.push(aderenciaArquetipo(pessoa.arquetipos, ideal.arquetipoIdeal));
  if (ideal.motorIdeal?.length) dimensoes.push(aderenciaMotor(pessoa.motores, ideal.motorIdeal));
  if (ideal.modoIdeal) dimensoes.push(aderenciaModo(pessoa.modo, ideal.modoIdeal));

  const media = dimensoes.reduce((s, d) => s + PESO[d.nivel], 0) / dimensoes.length;
  const nivelGeral: NivelAderencia = media >= 1.5 ? "flui" : media >= 0.75 ? "adapta" : "energia";
  const resumoGeral =
    nivelGeral === "flui"
      ? "No geral, a pessoa tende a fluir no estilo desta função."
      : nivelGeral === "adapta"
        ? "No geral, a pessoa se adapta ao estilo da função, com pontos que pedem apoio."
        : "No geral, o estilo da função tende a exigir mais energia desta pessoa — um bom foco para desenvolvimento e apoio.";

  return { disponivel: true, dimensoes, nivelGeral, resumoGeral };
}

export const NIVEL_ADERENCIA_LABEL: Record<NivelAderencia, string> = {
  flui: "Flui naturalmente",
  adapta: "Adapta-se",
  energia: "Exige mais energia",
};
