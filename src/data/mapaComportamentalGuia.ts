// ─────────────────────────────────────────────────────────────────────────────
// Mapa Comportamental — Biblioteca do Guia do Líder (Anexo B)
//
// Conteúdo curado dos quatro perfis + camadas complementares. É o insumo do
// RF-007 e o ativo que dá valor ao módulo. Escrito em TENDÊNCIA/PREFERÊNCIA,
// nunca em capacidade ou limitação (RN-010). Cada perfil abre com a frase de
// enquadramento: "este é um mapa de estilo, não uma medida de competência".
//
// Biblioteca FIXA (padrão YourEyes) nesta fase — edição pelo cliente (RF-017)
// fica para uma evolução.
// ─────────────────────────────────────────────────────────────────────────────

import type { Arquetipo } from "@/data/instrumentos/mapaComportamental";

export const GUIA_ENQUADRAMENTO =
  "Este é um mapa de estilo, não uma medida de competência. Use a orientação abaixo para adaptar a sua liderança — não para rotular a pessoa. Não existe perfil melhor nem pior.";

export interface BlocoGuia {
  chave: string;
  titulo: string;
  texto: string;
}

export interface PerfilGuia {
  arquetipo: Arquetipo;
  subtitulo: string; // eixo (ex.: "Tarefas + Acelerado")
  blocos: BlocoGuia[];
}

const BLOCOS_ORDEM: { chave: string; titulo: string }[] = [
  { chave: "trabalha", titulo: "Como essa pessoa costuma trabalhar" },
  { chave: "feedback", titulo: "Como dar feedback" },
  { chave: "motiva", titulo: "O que motiva" },
  { chave: "desmotiva", titulo: "O que desmotiva e desgasta" },
  { chave: "conforto", titulo: "Zona de conforto" },
  { chave: "delegar", titulo: "Como delegar" },
  { chave: "cobrar", titulo: "Como cobrar prazo" },
  { chave: "pressao", titulo: "Em conflito e sob pressão" },
  { chave: "precisa", titulo: "O que esse perfil precisa de você" },
  { chave: "erros", titulo: "Erros comuns de liderança com esse perfil" },
  { chave: "atritos", titulo: "Como ele enxerga os outros perfis" },
];

type BlocoTextos = Record<string, string>;

function montaPerfil(arquetipo: Arquetipo, subtitulo: string, textos: BlocoTextos): PerfilGuia {
  return {
    arquetipo,
    subtitulo,
    blocos: BLOCOS_ORDEM.map((b) => ({ chave: b.chave, titulo: b.titulo, texto: textos[b.chave] })),
  };
}

export const GUIA_PERFIS: Record<Arquetipo, PerfilGuia> = {
  pioneiro: montaPerfil("pioneiro", "Tarefas + Acelerado", {
    trabalha:
      "Vai direto ao resultado, decide rápido, tolera bem risco e incerteza. Prefere autonomia a instrução detalhada.",
    feedback:
      "Seja direto e comece pelo ponto. Rodeio soa como falta de confiança. Traga o impacto concreto do comportamento, não a percepção. Conversa curta funciona melhor que longa.",
    motiva: "Desafio novo, autonomia real, responsabilidade visível e resultado mensurável.",
    desmotiva: "Processo que trava sem explicação, microgestão, reunião longa sem decisão.",
    conforto:
      "Acomoda-se quando tudo vira execução repetida e não há terreno novo. Tirá-lo de lá: dar um problema ainda não resolvido, não mais volume do mesmo.",
    delegar:
      "Combine o resultado e o prazo, e deixe o caminho aberto. Detalhe excessivo é ignorado. Defina pontos de checagem — poucos e combinados.",
    cobrar: "Cobrança direta funciona. O que gera resistência é cobrar o método em vez do resultado.",
    pressao:
      "Tende a acelerar e a atropelar quem é mais lento. Conduza trazendo o custo do atropelo, não o desconforto que causou.",
    precisa: "Espaço para decidir e alguém que segure o ritmo quando ele estiver custando qualidade.",
    erros:
      "Confundir pressa com descompromisso; controlar demais e perder o engajamento; não dar feedback por achar que “ele aguenta”.",
    atritos: "Com o Guardião, por ritmo. Com o Estrategista, por profundidade de análise.",
  }),
  conector: montaPerfil("conector", "Pessoas + Acelerado", {
    trabalha:
      "Mobiliza gente, comunica bem, circula entre áreas e destrava por relação. Ritmo rápido, foco disperso.",
    feedback:
      "Comece pela relação e pelo que reconhece nele. Crítica seca soa como rejeição pessoal. Seja específico sobre o comportamento e deixe claro que a relação continua.",
    motiva: "Reconhecimento público, trabalho com pessoas, variedade, projetos de visibilidade.",
    desmotiva: "Isolamento, tarefa longa e solitária, ambiente sem interação, ser ignorado.",
    conforto:
      "Acomoda-se na popularidade, evitando conversa difícil para não desgastar relação. Tirá-lo de lá: dar responsabilidade que exija dizer não.",
    delegar:
      "Explique o porquê e quem será impactado. Combine marcos de acompanhamento, porque o foco tende a dispersar.",
    cobrar: "Cobrança em público desmonta. Cobre em privado, ligando o prazo ao impacto nas pessoas.",
    pressao:
      "Tende a suavizar e evitar o confronto direto, às vezes adiando o problema. Conduza nomeando o assunto com clareza e segurança.",
    precisa: "Reconhecimento explícito e ajuda para fechar o que começou.",
    erros:
      "Confundir comunicação com entrega; achar que não precisa de feedback porque está sempre bem com todos; sobrecarregá-lo de demandas sociais.",
    atritos: "Com o Estrategista, por excesso de análise. Com o Pioneiro, por disputa de espaço.",
  }),
  guardiao: montaPerfil("guardiao", "Pessoas + Ponderado", {
    trabalha:
      "Constante, confiável, atento ao grupo. Sustenta rotina e processo. Prefere estabilidade e prazo para assimilar mudança.",
    feedback:
      "Conversa privada, tom calmo, tempo para a pessoa responder. Contextualize antes de apontar. Feedback público, mesmo positivo, pode constranger.",
    motiva: "Pertencimento, segurança, reconhecimento da consistência, sentir que o trabalho ajuda alguém.",
    desmotiva: "Mudança sem aviso, clima de conflito, cobrança agressiva, sensação de deslealdade.",
    conforto:
      "É o perfil que mais se acomoda, justamente porque a estabilidade é o que ele valoriza. Tirá-lo de lá: mudança em passos combinados, com apoio explícito — nunca por empurrão.",
    delegar:
      "Dê contexto completo, o padrão esperado e tempo de preparação. Mudança de última hora derruba a entrega.",
    cobrar: "Cobrança direta e dura trava. Combine prazos com antecedência e acompanhe sem pressa artificial.",
    pressao:
      "Tende a se calar e absorver. O silêncio não é concordância. Pergunte diretamente e dê espaço de resposta.",
    precisa: "Previsibilidade, aviso antecipado de mudança e reconhecimento de que constância também é entrega.",
    erros:
      "Interpretar o silêncio como alinhamento; deixá-lo de fora das mudanças por ser “tranquilo”; confundir estabilidade com falta de ambição.",
    atritos: "Com o Pioneiro, por ritmo e por mudança sem aviso.",
  }),
  estrategista: montaPerfil("estrategista", "Tarefas + Ponderado", {
    trabalha:
      "Analisa antes de agir, busca rigor e consistência, enxerga risco que os outros não veem. Precisa entender o porquê antes de se comprometer.",
    feedback:
      "Traga fatos e exemplos concretos. Feedback genérico é descartado. Dê tempo para ele processar e volte depois — a primeira reação raramente é a conclusão.",
    motiva: "Problema complexo, qualidade técnica reconhecida, autonomia intelectual, ver o próprio raciocínio ser usado.",
    desmotiva: "Decisão sem fundamento, mudança sem explicação, ter que executar algo que considera errado.",
    conforto:
      "Acomoda-se no aprofundamento sem fim, analisando em vez de entregar. Tirá-lo de lá: prazo firme e critério de “bom o suficiente” combinado.",
    delegar:
      "Explique o objetivo e o critério de qualidade. Ele vai desenhar o caminho. Combine um ponto de corte, senão o refino não acaba.",
    cobrar: "Cobre o corte, não o esforço. Funciona combinar com antecedência o que é suficiente.",
    pressao: "Tende a se fechar e a buscar argumento. Conduza pelo mérito técnico, não pelo tom.",
    precisa: "Justificativa das decisões e reconhecimento do rigor, não só da velocidade.",
    erros:
      "Tratar a pergunta como resistência; pedir decisão imediata sem contexto; cobrar velocidade sem negociar o nível de qualidade.",
    atritos: "Com o Pioneiro, por velocidade. Com o Conector, por informalidade.",
  }),
};

// Camadas complementares — ajustam a orientação e evitam que o Guia vire
// horóscopo de quatro caixas (Anexo B.5).
export interface CamadaGuia {
  chave: string;
  titulo: string;
  texto: string;
}

export const GUIA_CAMADAS_MOTOR: CamadaGuia[] = [
  { chave: "racional", titulo: "Motor Racional", texto: "Traga dado e raciocínio; explique o critério da decisão antes de pedir adesão." },
  { chave: "relacional", titulo: "Motor Relacional", texto: "Traga o impacto nas pessoas; cuide do como antes do quê." },
  { chave: "pragmatico", titulo: "Motor Pragmático", texto: "Traga o próximo passo concreto; contexto longo perde a pessoa." },
];

export const GUIA_CAMADAS_MODO: CamadaGuia[] = [
  { chave: "constante", titulo: "Modo Constante", texto: "Suporta bem prazo apertado e mudança de rota; cuidado com sobrecarga por parecer que aguenta sempre." },
  { chave: "cadenciado", titulo: "Modo Cadenciado", texto: "Rende mais com previsibilidade; avise mudanças com antecedência e evite cobrança em público." },
  { chave: "intensidade_baixa", titulo: "Intensidade baixa em um eixo", texto: "A pessoa transita entre os dois lados. Trate como flexibilidade e não force a orientação de um único perfil." },
];
