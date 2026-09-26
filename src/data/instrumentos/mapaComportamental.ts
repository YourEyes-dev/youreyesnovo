// ─────────────────────────────────────────────────────────────────────────────
// Mapa Comportamental — Instrumento v1 e algoritmo de apuração (determinístico)
//
// Fonte da verdade: documento "YE - Mapa Comportamental", Anexo A (itens) e A.8
// (algoritmo). O cálculo é DETERMINÍSTICO e AUDITÁVEL — uma função pura, não um
// modelo de linguagem (RN-013). As respostas cruas são guardadas junto do
// resultado, de modo que o mapa pode ser recalculado e auditado a qualquer tempo.
//
// IMPORTANTE (não é instrumento psicodiagnóstico — Premissa P1): é uma ferramenta
// de autopercepção e desenvolvimento. Toda a linguagem é de tendência/preferência,
// nunca de capacidade (RN-010). Não existe perfil melhor nem pior (Premissa P3).
// ─────────────────────────────────────────────────────────────────────────────

export const MAPA_INSTRUMENTO_VERSAO = 1;
export const MAPA_ALGORITMO_VERSAO = "v1";
export const MAPA_TOTAL_ITENS = 28;

/** Eixos e camadas medidos pelo instrumento. */
export type MapaEixo = "foco" | "ritmo" | "motor" | "modo" | "controle";

/** Lados canônicos de um item A/B (o significado, não a posição na tela). */
export type LadoAB = "A" | "B";

/** Motores de decisão (itens 13–18). */
export type Motor = "racional" | "relacional" | "pragmatico";

/** Arquétipos (cruzamento Foco × Ritmo). */
export type Arquetipo = "pioneiro" | "conector" | "guardiao" | "estrategista";

/** Modo de contexto. */
export type Modo = "constante" | "cadenciado";

export interface OpcaoAB {
  lado: LadoAB;
  texto: string;
}

export interface ItemAB {
  id: number;
  eixo: Exclude<MapaEixo, "motor">;
  tipo: "ab";
  enunciado: string;
  /** As duas opções, na ordem canônica A depois B (a tela randomiza a exibição). */
  opcoes: [OpcaoAB, OpcaoAB];
  /** Item de controle: compara com o item base indicado (redação invertida). */
  controleDe?: number;
}

export interface OpcaoMotor {
  motor: Motor;
  texto: string;
}

export interface ItemMotor {
  id: number;
  eixo: "motor";
  tipo: "motor";
  enunciado: string;
  opcoes: OpcaoMotor[];
}

export type MapaItem = ItemAB | ItemMotor;

// ─────────────────────────────────────────────────────────────────────────────
// Significado dos lados por eixo (Anexo A)
//   Foco : A = Pessoas    · B = Tarefas
//   Ritmo: A = Acelerado  · B = Ponderado
//   Modo : A = Constante  · B = Cadenciado
// ─────────────────────────────────────────────────────────────────────────────

// Parte 1 — Foco (Pessoas ou Tarefas)
const FOCO: ItemAB[] = [
  {
    id: 1, eixo: "foco", tipo: "ab",
    enunciado: "Em uma reunião de início de projeto, para onde sua atenção vai primeiro?",
    opcoes: [
      { lado: "A", texto: "Para os papéis das pessoas e o clima do grupo." },
      { lado: "B", texto: "Para as metas, entregas e viabilidade do plano." },
    ],
  },
  {
    id: 2, eixo: "foco", tipo: "ab",
    enunciado: "O que te dá mais sensação de dever cumprido ao fim do dia?",
    opcoes: [
      { lado: "A", texto: "Ter ajudado alguém ou destravado uma relação." },
      { lado: "B", texto: "Ter concluído tarefas difíceis da lista." },
    ],
  },
  {
    id: 3, eixo: "foco", tipo: "ab",
    enunciado: "Um colega pede ajuda enquanto você está no meio de algo concentrado:",
    opcoes: [
      { lado: "A", texto: "Paro e atendo; depois retomo." },
      { lado: "B", texto: "Marco para depois e sigo com o que estava fazendo." },
    ],
  },
  {
    id: 4, eixo: "foco", tipo: "ab",
    enunciado: "Numa decisão em grupo, você tende a:",
    opcoes: [
      { lado: "A", texto: "Buscar uma saída que o grupo sustente junto." },
      { lado: "B", texto: "Defender a opção mais eficiente, mesmo contrariando a maioria." },
    ],
  },
  {
    id: 5, eixo: "foco", tipo: "ab",
    enunciado: "Qual crítica te incomodaria mais receber?",
    opcoes: [
      { lado: "A", texto: "Que você é difícil de conviver." },
      { lado: "B", texto: "Que você entrega pouco." },
    ],
  },
  {
    id: 6, eixo: "foco", tipo: "ab",
    enunciado: "Entre dois projetos com a mesma importância, você escolheria:",
    opcoes: [
      { lado: "A", texto: "O de equipe mais integrada." },
      { lado: "B", texto: "O de maior desafio técnico." },
    ],
  },
];

// Parte 2 — Ritmo (Acelerado ou Ponderado)
const RITMO: ItemAB[] = [
  {
    id: 7, eixo: "ritmo", tipo: "ab",
    enunciado: "Diante de um problema inesperado, sua primeira reação é:",
    opcoes: [
      { lado: "A", texto: "Testar uma solução na prática para ver o que acontece." },
      { lado: "B", texto: "Entender a causa antes de mexer em qualquer coisa." },
    ],
  },
  {
    id: 8, eixo: "ritmo", tipo: "ab",
    enunciado: "Sua relação natural com prazos:",
    opcoes: [
      { lado: "A", texto: "Vários projetos em paralelo, ritmo rápido." },
      { lado: "B", texto: "Um de cada vez, com tempo de revisão." },
    ],
  },
  {
    id: 9, eixo: "ritmo", tipo: "ab",
    enunciado: "Quando um processo engessado atrasa o resultado:",
    opcoes: [
      { lado: "A", texto: "Adapto o caminho para destravar." },
      { lado: "B", texto: "Sigo o processo e registro o problema." },
    ],
  },
  {
    id: 10, eixo: "ritmo", tipo: "ab",
    enunciado: "Com informação incompleta, você prefere:",
    opcoes: [
      { lado: "A", texto: "Decidir com o que tem e corrigir depois." },
      { lado: "B", texto: "Esperar mais clareza antes de decidir." },
    ],
  },
  {
    id: 11, eixo: "ritmo", tipo: "ab",
    enunciado: "Seu estilo de comunicação está mais para:",
    opcoes: [
      { lado: "A", texto: "Direto e enérgico, focado no essencial." },
      { lado: "B", texto: "Estruturado e contextualizado, com os detalhes." },
    ],
  },
  {
    id: 12, eixo: "ritmo", tipo: "ab",
    enunciado: "Quando a estratégia muda de repente:",
    opcoes: [
      { lado: "A", texto: "Já começo a enxergar o novo caminho." },
      { lado: "B", texto: "Preciso entender o motivo antes de me mover." },
    ],
  },
];

// Parte 3 — Motor de Decisão
const MOTOR: ItemMotor[] = [
  {
    id: 13, eixo: "motor", tipo: "motor",
    enunciado: "Para convencer a equipe de uma ideia, você recorre primeiro a:",
    opcoes: [
      { motor: "racional", texto: "Dados, lógica e evidência." },
      { motor: "relacional", texto: "Propósito, impacto nas pessoas e motivação." },
      { motor: "pragmatico", texto: "Retorno prático e passos imediatos." },
    ],
  },
  {
    id: 14, eixo: "motor", tipo: "motor",
    enunciado: "O que mais consome sua energia na rotina:",
    opcoes: [
      { motor: "racional", texto: "Confusão, falta de lógica, informação contraditória." },
      { motor: "relacional", texto: "Clima ruim, relações desgastadas." },
      { motor: "pragmatico", texto: "Burocracia e lentidão." },
    ],
  },
  {
    id: 15, eixo: "motor", tipo: "motor",
    enunciado: "Ao delegar, seu principal critério é:",
    opcoes: [
      { motor: "racional", texto: "Se o método e os critérios ficaram claros." },
      { motor: "relacional", texto: "Se a pessoa se sente segura para fazer." },
      { motor: "pragmatico", texto: "Se o prazo ficou combinado." },
    ],
  },
  {
    id: 16, eixo: "motor", tipo: "motor",
    enunciado: "Ao cometer um erro relevante:",
    opcoes: [
      { motor: "racional", texto: "Analiso a fundo para entender onde a lógica falhou." },
      { motor: "relacional", texto: "Me preocupo com o impacto nos outros e realinho." },
      { motor: "pragmatico", texto: "Corrijo o efeito e sigo em frente." },
    ],
  },
  {
    id: 17, eixo: "motor", tipo: "motor",
    enunciado: "O que mais te faz respeitar um líder:",
    opcoes: [
      { motor: "racional", texto: "Profundidade e coerência de raciocínio." },
      { motor: "relacional", texto: "Escuta e capacidade de desenvolver pessoas." },
      { motor: "pragmatico", texto: "Capacidade de resolver e entregar." },
    ],
  },
  {
    id: 18, eixo: "motor", tipo: "motor",
    enunciado: "Sob forte estresse, sua tendência é:",
    opcoes: [
      { motor: "racional", texto: "Me isolar para reorganizar o pensamento." },
      { motor: "relacional", texto: "Conversar com alguém de confiança." },
      { motor: "pragmatico", texto: "Acelerar para eliminar pendências." },
    ],
  },
];

// Parte 4 — Modo de Contexto (A = Constante · B = Cadenciado)
const MODO: ItemAB[] = [
  {
    id: 19, eixo: "modo", tipo: "ab",
    enunciado: "Quando o dia é interrompido por imprevistos seguidos, você prefere:",
    opcoes: [
      { lado: "A", texto: "Ir reorganizando na hora, mesmo sem saber onde vai parar." },
      { lado: "B", texto: "Parar, redesenhar o plano e só então retomar." },
    ],
  },
  {
    id: 20, eixo: "modo", tipo: "ab",
    enunciado: "Depois de uma crítica dura ao seu trabalho, você costuma:",
    opcoes: [
      { lado: "A", texto: "Voltar à tarefa no mesmo dia e processar depois." },
      { lado: "B", texto: "Processar primeiro e voltar quando estiver resolvido." },
    ],
  },
  {
    id: 21, eixo: "modo", tipo: "ab",
    enunciado: "Você rende mais quando:",
    opcoes: [
      { lado: "A", texto: "A meta está apertada e o prazo pressiona." },
      { lado: "B", texto: "O ritmo é previsível e dá para planejar." },
    ],
  },
  {
    id: 22, eixo: "modo", tipo: "ab",
    enunciado: "Numa discussão que esquentou, você prefere:",
    opcoes: [
      { lado: "A", texto: "Resolver ali, mesmo que o clima fique tenso por um tempo." },
      { lado: "B", texto: "Deixar esfriar e retomar em outro momento." },
    ],
  },
  {
    id: 23, eixo: "modo", tipo: "ab",
    enunciado: "Numa decisão de alto risco, seu jeito natural é:",
    opcoes: [
      { lado: "A", texto: "Decidir com o que tem e assumir o resultado." },
      { lado: "B", texto: "Buscar mais uma validação antes de bater o martelo." },
    ],
  },
  {
    id: 24, eixo: "modo", tipo: "ab",
    enunciado: "Ao longo da semana, sua energia de trabalho:",
    opcoes: [
      { lado: "A", texto: "Segue mais ou menos a mesma, independentemente do dia." },
      { lado: "B", texto: "Varia conforme o tipo de trabalho e o contexto." },
    ],
  },
];

// Itens de controle (redação invertida; comparam com 1, 7, 13 e 19).
// A tela os embaralha entre os demais, sem identificação visível.
const CONTROLE: ItemAB[] = [
  {
    id: 25, eixo: "controle", tipo: "ab", controleDe: 1,
    enunciado: "Ao começar algo novo com um grupo, o que você quer entender primeiro:",
    // Invertido em relação ao item 1 (Foco): aqui A = Tarefas, B = Pessoas.
    opcoes: [
      { lado: "B", texto: "O que precisa ser entregue e em quanto tempo." },
      { lado: "A", texto: "Quem é quem e como as pessoas se relacionam." },
    ],
  },
  {
    id: 26, eixo: "controle", tipo: "ab", controleDe: 7,
    enunciado: "Quando algo dá errado sem aviso, seu primeiro movimento é:",
    // Invertido em relação ao item 7 (Ritmo): aqui A = Ponderado, B = Acelerado.
    opcoes: [
      { lado: "B", texto: "Levantar dados antes de agir." },
      { lado: "A", texto: "Agir e ajustar conforme a resposta." },
    ],
  },
  {
    id: 27, eixo: "controle", tipo: "ab", controleDe: 13,
    enunciado: "Você se sente mais confortável defendendo uma ideia quando tem:",
    // Compara com o Motor (item 13): A = viés Pragmático, B = viés Racional.
    opcoes: [
      { lado: "A", texto: "O argumento prático e o resultado esperado." },
      { lado: "B", texto: "Os números e a fundamentação." },
    ],
  },
  {
    id: 28, eixo: "controle", tipo: "ab", controleDe: 19,
    enunciado: "Diante de uma mudança de rota inesperada, você prefere:",
    // Invertido em relação ao item 19 (Modo): aqui A = Cadenciado, B = Constante.
    opcoes: [
      { lado: "B", texto: "Ter um tempo para reorganizar antes de seguir." },
      { lado: "A", texto: "Seguir ajustando no caminho." },
    ],
  },
];

/** Itens do instrumento, na ordem canônica (1 a 28). */
export const MAPA_ITENS: MapaItem[] = [...FOCO, ...RITMO, ...MOTOR, ...MODO, ...CONTROLE];

export const MAPA_ITENS_POR_ID: Record<number, MapaItem> = Object.fromEntries(
  MAPA_ITENS.map((i) => [i.id, i]),
);

// ─────────────────────────────────────────────────────────────────────────────
// Respostas
//
// Item A/B  → inteiro em {-2,-1,1,2}: negativo = lado A, positivo = lado B,
//             |v| = intensidade (2 = "bem mais", 1 = "um pouco mais"). Sem ponto
//             neutro, de propósito (Anexo A.2).
// Item Motor → 1 = racional, 2 = relacional, 3 = pragmático.
//
// A chave do objeto é o id do item ("1".."28").
// ─────────────────────────────────────────────────────────────────────────────

export type MapaRespostas = Record<string, number>;

export const MOTOR_POR_CODIGO: Record<number, Motor> = {
  1: "racional",
  2: "relacional",
  3: "pragmatico",
};

export const CODIGO_POR_MOTOR: Record<Motor, number> = {
  racional: 1,
  relacional: 2,
  pragmatico: 3,
};

// ─────────────────────────────────────────────────────────────────────────────
// Rótulos
// ─────────────────────────────────────────────────────────────────────────────

export const ARQUETIPO_LABEL: Record<Arquetipo, string> = {
  pioneiro: "Pioneiro",
  conector: "Conector",
  guardiao: "Guardião",
  estrategista: "Estrategista",
};

export const MOTOR_LABEL: Record<Motor, string> = {
  racional: "Racional",
  relacional: "Relacional",
  pragmatico: "Pragmático",
};

export const MODO_LABEL: Record<Modo, string> = {
  constante: "Constante",
  cadenciado: "Cadenciado",
};

// ─────────────────────────────────────────────────────────────────────────────
// Resultado
// ─────────────────────────────────────────────────────────────────────────────

export interface EixoBinarioResultado {
  /** Pontuação do lado A e do lado B (0 a 12). */
  pontosA: number;
  pontosB: number;
  /** Diferença absoluta entre os lados (0 a 12) — a intensidade. */
  intensidade: number;
  /** Lado predominante, ou null quando é misto (diferença ≤ limiar). */
  ladoPredominante: LadoAB | null;
  misto: boolean;
}

export interface MotorResultado {
  contagem: Record<Motor, number>;
  /** Motores predominantes (1 = claro; 2 = motor duplo por empate). */
  predominantes: Motor[];
}

export interface MapaResultado {
  instrumentoVersao: number;
  algoritmoVersao: string;
  // Arquétipo
  arquetipos: Arquetipo[]; // 1 = claro; 2 = perfil misto (vizinhos)
  arquetipoMisto: boolean;
  foco: EixoBinarioResultado; // A = Pessoas · B = Tarefas
  ritmo: EixoBinarioResultado; // A = Acelerado · B = Ponderado
  // Motor
  motor: MotorResultado;
  // Modo de contexto
  modo: { pontosA: number; pontosB: number; resultado: Modo | "misto"; misto: boolean };
  // Confiabilidade
  indiceConsistencia: number; // nº de pares de controle DIVERGENTES (0 a 4)
  confiabilidade: "alta" | "baixa";
  motivoBaixaConfiabilidade: string[];
  // Assinatura legível ("Estrategista-Racional, Modo Constante")
  assinatura: string;
}

/** Limiar de "perfil misto" nos eixos (RN-004: diferença ≤ 2). Parametrizável. */
export const LIMIAR_PERFIL_MISTO = 2;

/** Nº mínimo de segundos de resposta abaixo do qual marca baixa confiabilidade. */
export const TEMPO_MINIMO_SEGUNDOS = 60;

function pontosLado(valor: number | undefined, lado: LadoAB): number {
  // valor: -2/-1 = lado A ; 1/2 = lado B ; magnitude = intensidade
  if (valor == null) return 0;
  if (lado === "A" && valor < 0) return Math.abs(valor);
  if (lado === "B" && valor > 0) return valor;
  return 0;
}

function apurarEixoBinario(respostas: MapaRespostas, ids: number[]): EixoBinarioResultado {
  let pontosA = 0;
  let pontosB = 0;
  for (const id of ids) {
    const v = respostas[String(id)];
    pontosA += pontosLado(v, "A");
    pontosB += pontosLado(v, "B");
  }
  const intensidade = Math.abs(pontosA - pontosB);
  const misto = intensidade <= LIMIAR_PERFIL_MISTO;
  const ladoPredominante: LadoAB | null = misto ? null : pontosA > pontosB ? "A" : "B";
  return { pontosA, pontosB, intensidade, ladoPredominante, misto };
}

/** Lado "vencedor" ignorando o limiar de misto (usado para desempate e assinatura). */
function ladoBruto(e: EixoBinarioResultado): LadoAB {
  if (e.pontosA === e.pontosB) return "A"; // desempate estável determinístico
  return e.pontosA > e.pontosB ? "A" : "B";
}

/**
 * Arquétipo a partir de Foco (A=Pessoas/B=Tarefas) e Ritmo (A=Acelerado/B=Ponderado):
 *   Tarefas + Acelerado = Pioneiro
 *   Pessoas + Acelerado = Conector
 *   Pessoas + Ponderado = Guardião
 *   Tarefas + Ponderado = Estrategista
 */
function arquetipoDe(focoLado: LadoAB, ritmoLado: LadoAB): Arquetipo {
  const tarefas = focoLado === "B";
  const acelerado = ritmoLado === "A";
  if (tarefas && acelerado) return "pioneiro";
  if (!tarefas && acelerado) return "conector";
  if (!tarefas && !acelerado) return "guardiao";
  return "estrategista";
}

function apurarMotor(respostas: MapaRespostas): MotorResultado {
  const contagem: Record<Motor, number> = { racional: 0, relacional: 0, pragmatico: 0 };
  for (let id = 13; id <= 18; id++) {
    const cod = respostas[String(id)];
    const motor = MOTOR_POR_CODIGO[cod as number];
    if (motor) contagem[motor] += 1;
  }
  const max = Math.max(contagem.racional, contagem.relacional, contagem.pragmatico);
  // Motor duplo no empate: apresenta os empatados no topo (até 2).
  const ordem: Motor[] = ["racional", "relacional", "pragmatico"];
  const predominantes = ordem.filter((m) => contagem[m] === max && max > 0).slice(0, 2);
  return { contagem, predominantes };
}

/**
 * Consistência: compara os pares (1‑25, 7‑26, 13‑27, 19‑28), lembrando que os
 * itens de controle têm redação invertida — os lados canônicos já estão
 * declarados nas opções, então basta comparar o polo escolhido em cada item.
 * 2+ pares divergentes → baixa confiabilidade (RN-005).
 */
function contarDivergencias(respostas: MapaRespostas): number {
  let divergencias = 0;

  // Foco: item 1 vs 25 — lado escolhido (A=Pessoas / B=Tarefas)
  divergencias += parDivergeAB(respostas, 1, 25);
  // Ritmo: item 7 vs 26 — (A=Acelerado / B=Ponderado)
  divergencias += parDivergeAB(respostas, 7, 26);
  // Modo: item 19 vs 28 — (A=Constante / B=Cadenciado)
  divergencias += parDivergeAB(respostas, 19, 28);
  // Motor: item 13 vs 27 — 27 só distingue Racional (B) de Pragmático (A).
  divergencias += parDivergeMotor(respostas, 13, 27);

  return divergencias;
}

function ladoDe(valor: number | undefined): LadoAB | null {
  if (valor == null) return null;
  return valor < 0 ? "A" : "B";
}

function parDivergeAB(respostas: MapaRespostas, base: number, controle: number): number {
  const a = ladoDe(respostas[String(base)]);
  const b = ladoDe(respostas[String(controle)]);
  if (a == null || b == null) return 0; // par incompleto não conta como divergência
  return a === b ? 0 : 1;
}

function parDivergeMotor(respostas: MapaRespostas, base: number, controle: number): number {
  const motor = MOTOR_POR_CODIGO[respostas[String(base)] as number];
  const ctrlLado = ladoDe(respostas[String(controle)]); // A = pragmático, B = racional
  if (!motor || ctrlLado == null) return 0;
  if (motor === "relacional") return 0; // o controle não consegue confirmar/negar
  const motorDoControle: Motor = ctrlLado === "A" ? "pragmatico" : "racional";
  return motor === motorDoControle ? 0 : 1;
}

function todosItensIguais(respostas: MapaRespostas): boolean {
  const vals = MAPA_ITENS.map((i) => respostas[String(i.id)]).filter((v) => v != null);
  if (vals.length < MAPA_TOTAL_ITENS) return false;
  return vals.every((v) => v === vals[0]);
}

export interface CalcularMapaOpcoes {
  tempoTotalSegundos?: number;
}

/**
 * Apura o mapa comportamental a partir das respostas cruas. Função pura e
 * determinística (Anexo A.8). Não decide sobre a pessoa — só traduz respostas.
 */
export function calcularMapa(respostas: MapaRespostas, opcoes: CalcularMapaOpcoes = {}): MapaResultado {
  const foco = apurarEixoBinario(respostas, [1, 2, 3, 4, 5, 6]);
  const ritmo = apurarEixoBinario(respostas, [7, 8, 9, 10, 11, 12]);
  const modoEixo = apurarEixoBinario(respostas, [19, 20, 21, 22, 23, 24]);
  const motor = apurarMotor(respostas);

  // Arquétipo pelo lado bruto de cada eixo (desempate determinístico).
  const focoBruto = ladoBruto(foco);
  const ritmoBruto = ladoBruto(ritmo);
  const arquetipoPrincipal = arquetipoDe(focoBruto, ritmoBruto);

  // Perfil misto: quando um dos eixos está dentro do limiar, apresenta o
  // arquétipo vizinho (trocando o lado do eixo indefinido).
  const arquetipos: Arquetipo[] = [arquetipoPrincipal];
  if (foco.misto) {
    const vizinho = arquetipoDe(focoBruto === "A" ? "B" : "A", ritmoBruto);
    if (!arquetipos.includes(vizinho)) arquetipos.push(vizinho);
  }
  if (ritmo.misto) {
    const vizinho = arquetipoDe(focoBruto, ritmoBruto === "A" ? "B" : "A");
    if (!arquetipos.includes(vizinho)) arquetipos.push(vizinho);
  }
  const arquetipoMisto = arquetipos.length > 1;

  // Modo de contexto: predominância de A = Constante; de B = Cadenciado; misto ≤ limiar.
  const modoResultado: Modo | "misto" = modoEixo.misto
    ? "misto"
    : modoEixo.ladoPredominante === "A"
      ? "constante"
      : "cadenciado";

  // Confiabilidade
  const divergencias = contarDivergencias(respostas);
  const motivos: string[] = [];
  if (divergencias >= 2) motivos.push("Respostas de controle divergentes.");
  if (opcoes.tempoTotalSegundos != null && opcoes.tempoTotalSegundos < TEMPO_MINIMO_SEGUNDOS) {
    motivos.push("Tempo de resposta abaixo do mínimo.");
  }
  if (todosItensIguais(respostas)) motivos.push("Padrão de resposta idêntico em todos os itens.");
  const confiabilidade: "alta" | "baixa" = motivos.length > 0 ? "baixa" : "alta";

  // Assinatura legível
  const motorTxt = motor.predominantes.map((m) => MOTOR_LABEL[m]).join("-");
  const arqTxt = arquetipos.map((a) => ARQUETIPO_LABEL[a]).join("-");
  const modoTxt = modoResultado === "misto" ? "Modo Misto" : `Modo ${MODO_LABEL[modoResultado]}`;
  const assinatura = [arqTxt, motorTxt].filter(Boolean).join("-") + `, ${modoTxt}`;

  return {
    instrumentoVersao: MAPA_INSTRUMENTO_VERSAO,
    algoritmoVersao: MAPA_ALGORITMO_VERSAO,
    arquetipos,
    arquetipoMisto,
    foco,
    ritmo,
    motor,
    modo: {
      pontosA: modoEixo.pontosA,
      pontosB: modoEixo.pontosB,
      resultado: modoResultado,
      misto: modoEixo.misto,
    },
    indiceConsistencia: divergencias,
    confiabilidade,
    motivoBaixaConfiabilidade: motivos,
    assinatura,
  };
}

/** Snapshot compacto do instrumento para versionamento/auditoria no banco. */
export function instrumentoDefinicaoSnapshot() {
  return {
    versao: MAPA_INSTRUMENTO_VERSAO,
    algoritmo_versao: MAPA_ALGORITMO_VERSAO,
    total_itens: MAPA_TOTAL_ITENS,
    limiar_perfil_misto: LIMIAR_PERFIL_MISTO,
    tempo_minimo_segundos: TEMPO_MINIMO_SEGUNDOS,
    itens: MAPA_ITENS.map((i) =>
      i.tipo === "ab"
        ? { id: i.id, eixo: i.eixo, tipo: i.tipo, controle_de: i.controleDe ?? null,
            enunciado: i.enunciado, opcoes: i.opcoes }
        : { id: i.id, eixo: i.eixo, tipo: i.tipo, enunciado: i.enunciado, opcoes: i.opcoes },
    ),
  };
}
