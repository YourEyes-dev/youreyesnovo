// ─────────────────────────────────────────────────────────────────────────────
// Mapa Comportamental — comparativo entre reaplicações (RF-015 / RF-030).
//
// Compara o resultado atual com o da aplicação anterior e descreve O QUE MUDOU.
// Regra dura do documento (RF-030): descreve a mudança e NUNCA atribui causa
// nem valor — não diz se a mudança foi boa ou ruim. "Estabilidade também é
// informação" (reaplicação sem mudança). Função pura e determinística.
// ─────────────────────────────────────────────────────────────────────────────

import {
  ARQUETIPO_LABEL, MOTOR_LABEL, MODO_LABEL,
  type MapaResultado, type EixoBinarioResultado,
} from "./mapaComportamental";

export interface ComparativoItem {
  rotulo: string;
  de: string;
  para: string;
}

export interface ComparativoMapa {
  mudou: boolean;
  itens: ComparativoItem[];
  resumo: string;
}

/** Faixa de intensidade em palavra (mesma régua do relatório, RN-006/RN-027). */
function faixa(intensidade: number): string {
  if (intensidade >= 9) return "bem marcada";
  if (intensidade >= 5) return "clara";
  return "equilibrada";
}

function descreveEixo(e: EixoBinarioResultado, ladoA: string, ladoB: string): string {
  if (e.misto || e.ladoPredominante === null) return `equilíbrio entre ${ladoA} e ${ladoB}`;
  const lado = e.ladoPredominante === "A" ? ladoA : ladoB;
  return `${lado} (tendência ${faixa(e.intensidade)})`;
}

/**
 * Monta o comparativo entre o resultado ATUAL e o ANTERIOR. Só lista as
 * dimensões que realmente mudaram. Sem juízo de valor.
 */
export function compararMapas(atual: MapaResultado, anterior: MapaResultado): ComparativoMapa {
  const itens: ComparativoItem[] = [];

  // Arquétipo predominante (primeiro da lista, que é o bruto/predominante).
  const arqAtual = ARQUETIPO_LABEL[atual.arquetipos[0]];
  const arqAnt = ARQUETIPO_LABEL[anterior.arquetipos[0]];
  if (arqAtual !== arqAnt) {
    itens.push({ rotulo: "Arquétipo predominante", de: arqAnt, para: arqAtual });
  }

  // Eixo Foco (Pessoas ↔ Tarefas).
  const focoAtual = descreveEixo(atual.foco, "Pessoas", "Tarefas");
  const focoAnt = descreveEixo(anterior.foco, "Pessoas", "Tarefas");
  if (focoAtual !== focoAnt) {
    itens.push({ rotulo: "Foco", de: focoAnt, para: focoAtual });
  }

  // Eixo Ritmo (Acelerado ↔ Ponderado).
  const ritmoAtual = descreveEixo(atual.ritmo, "Acelerado", "Ponderado");
  const ritmoAnt = descreveEixo(anterior.ritmo, "Acelerado", "Ponderado");
  if (ritmoAtual !== ritmoAnt) {
    itens.push({ rotulo: "Ritmo", de: ritmoAnt, para: ritmoAtual });
  }

  // Motor de decisão (pode ter 1 ou 2 predominantes).
  const motorAtual = atual.motor.predominantes.map((m) => MOTOR_LABEL[m]).join(" e ") || "—";
  const motorAnt = anterior.motor.predominantes.map((m) => MOTOR_LABEL[m]).join(" e ") || "—";
  if (motorAtual !== motorAnt) {
    itens.push({ rotulo: "Motor de decisão", de: motorAnt, para: motorAtual });
  }

  // Modo de contexto.
  const modoAtual = atual.modo.resultado === "misto" ? "Misto" : MODO_LABEL[atual.modo.resultado];
  const modoAnt = anterior.modo.resultado === "misto" ? "Misto" : MODO_LABEL[anterior.modo.resultado];
  if (modoAtual !== modoAnt) {
    itens.push({ rotulo: "Modo de contexto", de: modoAnt, para: modoAtual });
  }

  // Confiabilidade (grau de consistência).
  if (atual.confiabilidade !== anterior.confiabilidade) {
    const rot = (c: "alta" | "baixa") => (c === "alta" ? "consistente" : "pouco consistente");
    itens.push({ rotulo: "Confiabilidade", de: rot(anterior.confiabilidade), para: rot(atual.confiabilidade) });
  }

  const mudou = itens.length > 0;
  const resumo = mudou
    ? "Alguns pontos mudaram desde a última vez. Mudança faz parte — este quadro apenas descreve o que está diferente; não emite juízo sobre a mudança. Vale conversar sobre o que aconteceu no período."
    : "O seu resultado se manteve estável desde a última vez. Estabilidade também é informação: o seu jeito de trabalhar vem se mantendo reconhecível.";

  return { mudou, itens, resumo };
}
