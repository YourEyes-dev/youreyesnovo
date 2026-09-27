// ─────────────────────────────────────────────────────────────────────────────
// Mapa Comportamental — Biblioteca do Relatório "Meu Mapa" (Análise RF-020..RF-032)
//
// Diferente da biblioteca do Guia do Líder (que fala com o gestor SOBRE a pessoa),
// esta fala com a PESSOA sobre ela mesma. Toda a redação segue os sete princípios
// do documento:
//   P1 — 2ª pessoa, sempre ("você tende a…", nunca "o Pioneiro tende a…").  (RN-020)
//   P2 — Tendência, nunca capacidade (proibido "você tem dificuldade em…").  (RN-021)
//   P3 — Todo ponto forte vem com o custo dele.                              (RN-022)
//   P4 — Acionável em 48h (ajustes sem curso, sem autorização, sem trocar de cargo).
//   P5 — Sem comparação, sem nota, sem ranking.                             (RN-023)
//   P6 — Termina em ação concreta, não em "reflita".
//   P7 — Curto o bastante para ser lido.                                    (RN-032)
//
// Nenhuma recomendação envolve mudança de cargo, área, equipe, jornada ou
// remuneração (RN-026). Biblioteca FIXA e versionada (RN-030): alterar o conteúdo
// não muda relatórios já emitidos, e a versão é carimbada em cada emissão.
//
// Fonte: documento "YE - Relatório de Mapa Comportamental", Parte 10 (biblioteca) e
// Anexo (relatório completo preenchido, perfil Estrategista).
// ─────────────────────────────────────────────────────────────────────────────

import type { Arquetipo, Modo } from "@/data/instrumentos/mapaComportamental";

/** Versão da biblioteca de conteúdo do relatório (RN-030). */
export const RELATORIO_BIBLIOTECA_VERSAO = "v1";

/** Par condição → ação (seções "onde rende mais" e "o que desgasta"). */
export interface CondicaoAcao {
  condicao: string;
  acao: string;
}

/** Custo do estilo com o sinal de que está sendo pago agora (RN-022, fórmula da seção 7). */
export interface CustoEstilo {
  texto: string;
  sinal: string;
}

export interface ContrapesoDev {
  nome: string;
  porque: string;
  comoTreinar: string;
}

export interface PerfilRelatorio {
  emUmaFrase: string;
  noDiaADia: { reuniao: string; prazo: string; desacordo: string };
  rendeMais: CondicaoAcao[];
  desgasta: CondicaoAcao[];
  precos: CustoEstilo[]; // 3 custos (a tela reduz para 2 quando a intensidade é baixa)
  ajustesImediatos: string[]; // exatamente 3 — "quando X, faça Y" (RN-024)
  contrapesos: ContrapesoDev[]; // 2 — contrapeso do estilo, nunca reforço (RN-025)
  pedidosLider: string[]; // frases prontas para a conversa com o líder
  zonaConforto: { onde: string; saida: string };
  comunicacao: { entrega: string; perde: string; ajuste: string };
  feedback: { comoPedir: string; reacaoHabitual: string };
}

// Como cada arquétipo costuma enxergar os outros três, o atrito provável e o
// ajuste prático (seção 12). Chave = arquétipo do LEITOR; valor = leitura de cada
// um dos outros três.
export interface BlocoOutroPerfil {
  comoTeVe: string;
  atrito: string;
  ajuste: string;
}

// ── Rótulos amigáveis dos outros perfis, descritos pelo eixo (o leitor pode não
//    lembrar o nome do arquétipo do colega). ───────────────────────────────────
export const OUTRO_PERFIL_APRESENTACAO: Record<Arquetipo, string> = {
  pioneiro: "quem é acelerado e focado em tarefa",
  conector: "quem é acelerado e focado em pessoas",
  guardiao: "quem é ponderado e focado em pessoas",
  estrategista: "quem é ponderado e focado em tarefa",
};

export const PERFIL_RELATORIO: Record<Arquetipo, PerfilRelatorio> = {
  pioneiro: {
    emUmaFrase:
      "Você age rápido, decide sem precisar de todas as respostas e se incomoda com o que está parado.",
    noDiaADia: {
      reuniao:
        "Numa reunião, você quer que ela termine em decisão. Quando a conversa gira sem fechar, você tende a puxar o desfecho — o que destrava, e às vezes atropela quem ainda estava formando opinião.",
      prazo:
        "Num prazo apertado, seu instinto é começar logo e ajustar no caminho, em vez de esperar o plano ficar completo.",
      desacordo:
        "Num desacordo, você vai direto ao ponto. Resolve rápido, e de vez em quando resolve antes de ouvir o que faltava.",
    },
    rendeMais: [
      { condicao: "Você tem autonomia sobre o caminho.", acao: "Combine o resultado e o prazo logo no início e deixe claro que o método é seu." },
      { condicao: "O problema é novo e ainda não tem solução pronta.", acao: "Sinalize interesse por esse tipo de desafio — costuma ir para quem levanta a mão." },
      { condicao: "O resultado é visível e mensurável.", acao: "Peça, no começo, como o sucesso vai ser medido; você rende mais com o alvo à vista." },
      { condicao: "O prazo aperta e exige ação.", acao: "Use bem esses momentos, e proteja algum tempo de checagem para a pressa não custar qualidade." },
    ],
    desgasta: [
      { condicao: "Precisa pedir autorização para o que é óbvio.", acao: "Combine antes uma faixa de decisões que você pode tomar sozinho — isso é negociável mais vezes do que parece." },
      { condicao: "A reunião não termina em decisão.", acao: "Peça, no início, que a reunião feche com um encaminhamento claro; ofereça-se para registrar." },
      { condicao: "Faz a mesma coisa pela décima vez.", acao: "Proponha automatizar ou passar adiante a parte repetida, liberando você para o que é novo." },
      { condicao: "O ritmo do time é mais lento que o seu.", acao: "Em vez de acelerar por fora, combine pontos de sincronismo — poucos e marcados." },
    ],
    precos: [
      {
        texto:
          "Você decide antes de ouvir quem tinha a informação que faltava, e a decisão volta.",
        sinal: "As pessoas param de te trazer informação antes da decisão e passam a trazer depois.",
      },
      {
        texto:
          "Você resolve sozinho o que era do time, e o time desaprende a resolver.",
        sinal: "Você percebe que viraram dependentes de você para coisas que já deveriam tocar sozinhos.",
      },
      {
        texto:
          "Sua pressa é lida como falta de consideração por quem pensa mais devagar.",
        sinal: "Alguém mais ponderado começa a ficar em silêncio nas conversas com você.",
      },
    ],
    ajustesImediatos: [
      "Antes de fechar uma decisão que afeta outra área, pergunte a uma pessoa daquela área o que você pode estar deixando de ver. Uma pessoa, uma pergunta — não é comitê.",
      "Em toda decisão que afeta alguém, gaste uma frase explicando por que você chegou ali, não só o que decidiu.",
      "Quando pegar algo que o time poderia resolver, segure o impulso e devolva com um prazo — mesmo que saia mais devagar desta vez.",
    ],
    contrapesos: [
      {
        nome: "Escuta antes da decisão",
        porque: "Sua velocidade já é forte; o ganho está em capturar a informação que só aparece quando você espera meio minuto a mais.",
        comoTreinar: "Em uma decisão por dia, pergunte 'o que estou deixando de ver?' antes de bater o martelo.",
      },
      {
        nome: "Comunicar o raciocínio, não só a conclusão",
        porque: "A conclusão já está pronta na sua cabeça; quem escuta recebe uma ordem sem o caminho.",
        comoTreinar: "Ao passar uma decisão, diga em uma frase como você chegou nela.",
      },
    ],
    pedidosLider: [
      "Me dá o resultado e o prazo, e me deixa escolher o caminho. Se você quiser acompanhar, combinamos dois pontos de checagem.",
      "Quando algo meu precisar de correção, me diz direto e cedo. Rodeio comigo custa mais que a crítica.",
    ],
    zonaConforto: {
      onde: "Resolver cada vez mais rápido o mesmo tipo de problema que você já domina.",
      saida: "O que costuma tirar você de lá é um problema que você ainda não sabe resolver — não mais volume do mesmo.",
    },
    comunicacao: {
      entrega: "Você é claro sobre o que quer. As pessoas sabem onde você quer chegar.",
      perde: "O que costuma se perder é o porquê: como a conclusão já está pronta na sua cabeça, você pula o caminho, e quem escuta recebe uma ordem em vez de um raciocínio.",
      ajuste: "Em toda decisão que afeta outra pessoa, gaste uma frase explicando por que você chegou ali.",
    },
    feedback: {
      comoPedir: "Feedback longo se perde com você. Peça o essencial e o exemplo: 'me diz em uma frase o que mudar e um exemplo de quando aconteceu'.",
      reacaoHabitual: "Sua reação habitual é já querer resolver antes de terminar de ouvir. Vale segurar: 'deixa eu ouvir até o fim e depois eu respondo'.",
    },
  },

  conector: {
    emUmaFrase:
      "Você trabalha através das pessoas, destrava por relação e sente rápido quando o clima muda.",
    noDiaADia: {
      reuniao:
        "Numa reunião, você lê o clima e traz as pessoas junto. Às vezes o entusiasmo ocupa o lugar do combinado concreto, e a reunião termina animada sem que fique claro quem faz o quê.",
      prazo:
        "Num prazo apertado, você mobiliza gente para destravar — e, com várias frentes abertas, corre o risco de dispersar o foco do que era prioridade.",
      desacordo:
        "Num desacordo, seu instinto é preservar a relação. Isso evita brigas, e de vez em quando adia um problema que precisava ser dito na hora.",
    },
    rendeMais: [
      { condicao: "Você trabalha junto com outras pessoas.", acao: "Busque projetos com times e interlocutores; é onde seu jeito rende mais." },
      { condicao: "Há variedade e você pode circular entre áreas.", acao: "Ofereça-se para pontes entre times — você faz isso com naturalidade." },
      { condicao: "Você é reconhecido pelo que fez.", acao: "Peça devolutiva sobre o resultado, não só sobre o esforço; reconhecimento te move." },
      { condicao: "O ambiente tem interação e energia.", acao: "Nos períodos de trabalho solitário, combine checkpoints curtos com alguém para não perder o gás." },
    ],
    desgasta: [
      { condicao: "Fica isolado em uma tarefa longa e solitária.", acao: "Quebre em blocos e combine com alguém um ponto de conversa ao fim de cada bloco." },
      { condicao: "O ambiente está tenso ou em conflito.", acao: "Quando não der para evitar, nomeie o assunto com calma em vez de contornar — contornar te desgasta mais." },
      { condicao: "Você se sente ignorado.", acao: "Peça um espaço fixo de alinhamento em vez de esperar ser lembrado." },
      { condicao: "Precisa fazer algo repetitivo sem contato.", acao: "Junte a tarefa a um momento de troca depois, como recompensa combinada com você mesmo." },
    ],
    precos: [
      {
        texto:
          "Você adia a conversa difícil para não desgastar a relação, e o problema cresce enquanto espera.",
        sinal: "Você tem mais de uma conversa pendente há mais de duas semanas.",
      },
      {
        texto:
          "Você começa mais coisas do que termina, porque o começo é mais animado que o fechamento.",
        sinal: "Há várias frentes suas em 80%, e nenhuma fechada.",
      },
      {
        texto:
          "Às vezes você concorda em público e discorda em particular, e as pessoas percebem.",
        sinal: "Alguém te procura depois da reunião para saber 'o que você achou de verdade'.",
      },
    ],
    ajustesImediatos: [
      "Escolha, por semana, uma conversa difícil que você vem adiando e marque data para ela. Adiar é o seu custo mais caro.",
      "Antes de abrir uma frente nova, feche uma que já esteja perto do fim. Uma entra quando uma sai.",
      "Quando discordar numa reunião, diga ali, mesmo que em uma frase curta — em vez de só no corredor depois.",
    ],
    contrapesos: [
      {
        nome: "Foco em uma coisa até terminar",
        porque: "Você começa com facilidade; o ganho está em levar até o fim antes de abrir a próxima.",
        comoTreinar: "Mantenha, por vez, no máximo três frentes 'em aberto'; só abre a quarta quando fechar uma.",
      },
      {
        nome: "Conversa difícil sem adiar",
        porque: "Adiar preserva a relação no curto prazo e cobra caro no médio.",
        comoTreinar: "Trate a conversa difícil da semana como tarefa com data, não como algo para 'quando der'.",
      },
    ],
    pedidosLider: [
      "Se precisar corrigir algo em mim, prefiro em particular. Em público eu travo, mesmo quando a crítica é justa.",
      "Me ajuda a priorizar quando eu abrir frentes demais — às vezes eu preciso de alguém para me dizer qual fecho primeiro.",
    ],
    zonaConforto: {
      onde: "Na popularidade — ser bem-visto por todos, evitando o desgaste de dizer não.",
      saida: "O que costuma tirar você de lá é uma responsabilidade que exija segurar uma posição impopular.",
    },
    comunicacao: {
      entrega: "Você engaja e traz gente junto. As pessoas saem das conversas com você mais dispostas.",
      perde: "O que costuma se perder é a precisão: o entusiasmo às vezes ocupa o lugar do combinado concreto.",
      ajuste: "Feche toda conversa animada com um combinado explícito: quem faz o quê, até quando.",
    },
    feedback: {
      comoPedir: "Você recebe melhor quando a crítica vem junto do que reconhece em você. Peça assim: 'me diz o que manter e o que ajustar'.",
      reacaoHabitual: "Sua reação habitual é sentir a crítica como distância pessoal. Lembre a si mesmo que é sobre o trabalho, não sobre a relação.",
    },
  },

  guardiao: {
    emUmaFrase:
      "Você é constante, sustenta o que combina e percebe quando alguém do time não está bem.",
    noDiaADia: {
      reuniao:
        "Numa reunião, você tende a ouvir mais do que falar e a concordar para manter o clima. Quando discorda por dentro e não diz, o silêncio é lido como concordância — e depois fica difícil voltar atrás.",
      prazo:
        "Num prazo apertado, você segura a barra com constância. O cuidado é sinalizar antes do limite, porque você tende a absorver mais do que consegue.",
      desacordo:
        "Num desacordo, seu instinto é evitar o embate. Isso preserva o ambiente, e às vezes deixa passar algo que precisava ser dito.",
    },
    rendeMais: [
      { condicao: "Você sabe o que esperar do que vem pela frente.", acao: "Peça o panorama da semana com antecedência; previsibilidade é a sua melhor condição." },
      { condicao: "Você tem tempo de preparação.", acao: "Negocie prazos que incluam o tempo de organizar — você entrega melhor assim." },
      { condicao: "O ambiente é estável.", acao: "Quando o ambiente balançar, apoie-se em uma rotina que você controla para não perder o eixo." },
      { condicao: "Você sente que o trabalho ajuda alguém.", acao: "Torne visível o efeito do que você faz — isso te sustenta nos períodos difíceis." },
    ],
    desgasta: [
      { condicao: "A mudança vem sem aviso.", acao: "Quando acontecer, peça um tempo curto para reorganizar antes de responder; costuma ser aceito." },
      { condicao: "O clima está de conflito.", acao: "Em vez de absorver calado, diga como o clima está te afetando — nomear alivia e informa." },
      { condicao: "A cobrança é agressiva.", acao: "Traga a conversa para o combinado: 'vamos alinhar prazo e o que dá para entregar'." },
      { condicao: "Precisa improvisar sem preparo.", acao: "Peça a informação mínima que falta e o tempo mínimo que precisa — é diferente de dizer que não dá." },
    ],
    precos: [
      {
        texto:
          "Você discorda por dentro e não fala, e depois fica difícil voltar atrás.",
        sinal: "Você saiu de uma reunião pensando 'eu devia ter falado'.",
      },
      {
        texto:
          "Você absorve mais do que consegue e só sinaliza no limite.",
        sinal: "Você percebe que está sustentando várias coisas sozinho e ninguém sabe disso.",
      },
      {
        texto:
          "A busca por estabilidade às vezes segura uma mudança que era necessária.",
        sinal: "Você se pega defendendo o jeito atual mais pela familiaridade do que pelo resultado.",
      },
    ],
    ajustesImediatos: [
      "Quando discordar em uma reunião, diga na hora, mesmo que em uma frase curta. Silêncio é lido como concordância, e depois fica difícil voltar atrás.",
      "Uma vez por semana, sinalize a sua carga antes de chegar ao limite: 'estou perto do meu limite nisso aqui'.",
      "Quando bater a vontade de manter tudo como está, pergunte-se se é pela familiaridade ou pelo resultado — e diga isso em voz alta na conversa.",
    ],
    contrapesos: [
      {
        nome: "Posicionamento em desacordo",
        porque: "Sua constância já é forte; o ganho está em colocar a sua leitura na mesa antes de a decisão fechar.",
        comoTreinar: "Em cada reunião, comprometa-se a dizer ao menos uma discordância, mesmo curta.",
      },
      {
        nome: "Tolerância a mudança sem aviso",
        porque: "A mudança repentina te derruba mais do que precisaria; treinar reduz o desgaste.",
        comoTreinar: "Diante de uma mudança súbita, use um roteiro fixo: reorganizo, pergunto o que falta, sigo.",
      },
    ],
    pedidosLider: [
      "Me avise das mudanças com antecedência, mesmo que ainda não estejam confirmadas. Eu rendo mais quando tenho tempo de reorganizar.",
      "Quando eu ficar quieto numa decisão, me pergunte diretamente o que eu penso — meu silêncio nem sempre é concordância.",
    ],
    zonaConforto: {
      onde: "A rotina que você domina e que funciona bem há tempo.",
      saida: "O que costuma tirar você de lá é uma mudança em passos combinados, com apoio — nunca por empurrão.",
    },
    comunicacao: {
      entrega: "Você é cuidadoso e as pessoas confiam no que você diz. Sua palavra tem peso.",
      perde: "O que costuma se perder é o que você não diz — o silêncio é lido como concordância.",
      ajuste: "Quando discordar, diga em uma frase no momento, e complete depois se precisar.",
    },
    feedback: {
      comoPedir: "Você recebe melhor em conversa privada e com tempo para responder. Peça assim: 'me dá esse retorno com calma, prefiro pensar antes de reagir'.",
      reacaoHabitual: "Sua reação habitual é absorver calado e processar sozinho. Vale dizer o que pensou depois, em vez de guardar.",
    },
  },

  estrategista: {
    emUmaFrase:
      "Você organiza antes de agir, busca entender o porquê e enxerga o risco que os outros não veem.",
    noDiaADia: {
      reuniao:
        "Numa reunião, você costuma falar depois dos outros, quando já formou opinião. Quem fala primeiro às vezes leva a decisão, mesmo com argumento mais fraco.",
      prazo:
        "Num prazo apertado, seu instinto é reduzir o escopo para manter a qualidade, não reduzir a qualidade para caber no prazo.",
      desacordo:
        "Num desacordo, você busca o argumento antes de responder. Isso evita briga desnecessária e, às vezes, faz a resposta chegar quando a decisão já foi tomada.",
    },
    rendeMais: [
      { condicao: "Você tem o contexto completo antes de começar.", acao: "Peça o porquê da tarefa logo na primeira conversa, em vez de descobrir no meio." },
      { condicao: "O problema é complexo e exige método.", acao: "Sinalize interesse nesses projetos; eles costumam ser distribuídos por quem levanta a mão." },
      { condicao: "Existe critério claro do que é uma boa entrega.", acao: "Se não vier, pergunte: 'o que precisa estar pronto para isso estar bom?'." },
      { condicao: "Você tem blocos de tempo sem interrupção.", acao: "Proteja pelo menos duas horas seguidas por dia na agenda." },
    ],
    desgasta: [
      { condicao: "Mudança de rota anunciada em cima da hora.", acao: "Quando acontecer, peça 15 minutos antes de responder. Você decide melhor depois de reorganizar, e esse tempo é negociável mais vezes do que parece." },
      { condicao: "Ter que decidir sem fundamento suficiente.", acao: "Diga qual informação falta e em quanto tempo você consegue obtê-la. É diferente de dizer que não dá para decidir." },
      { condicao: "Cobrança de velocidade sem conversa sobre escopo.", acao: "Responda com a troca: 'consigo nesse prazo entregando assim; para entregar completo preciso de mais X'." },
      { condicao: "Interrupção constante ao longo do dia.", acao: "Concentre as respostas em dois momentos fixos em vez de atender no fluxo." },
    ],
    precos: [
      {
        texto:
          "Você refina depois do ponto em que já estava bom, e a entrega atrasa ou perde a janela em que importava.",
        sinal: "Você está na terceira revisão de algo que já resolvia o problema na primeira.",
      },
      {
        texto:
          "Sua pergunta é lida como resistência, mesmo quando é só pergunta.",
        sinal: "As pessoas começam a te avisar das decisões em vez de te chamar para elas.",
      },
      {
        texto:
          "Você guarda a discordância até ter o argumento completo, e às vezes ele chega tarde.",
        sinal: "Você tem, mais de uma vez, a sensação de 'eu tinha percebido isso antes'.",
      },
    ],
    ajustesImediatos: [
      "Antes de começar qualquer entrega, escreva em uma linha o que é 'bom o suficiente' para ela. Combine isso antes, não durante.",
      "Em reuniões de decisão, fale nos primeiros cinco minutos, mesmo que com uma opinião parcial. Diga que é parcial.",
      "Quando discordar, diga na hora em uma frase e complete depois: 'tenho uma ressalva, te mando estruturada até amanhã'.",
    ],
    contrapesos: [
      {
        nome: "Decisão com informação incompleta",
        porque: "Seu padrão de fundamentação é alto, e em boa parte das decisões do dia a dia o custo de esperar é maior que o custo de errar.",
        comoTreinar: "Escolha uma decisão de baixo risco por semana e decida com metade da informação que você gostaria de ter. Observe o resultado.",
      },
      {
        nome: "Entrega antes da perfeição",
        porque: "Entregar em versões dá retorno mais cedo e evita refinar na direção errada.",
        comoTreinar: "Divida uma entrega grande em duas parciais combinadas com quem vai receber.",
      },
    ],
    pedidosLider: [
      "Quando você me passar uma demanda urgente, me diga qual é o nível de acabamento esperado. Eu tenho a tendência de refinar demais quando não sei onde parar.",
      "Me avise das mudanças com antecedência, mesmo que ainda não estejam confirmadas. Eu rendo mais quando tenho tempo de reorganizar.",
      "Quando eu fizer muitas perguntas, é para entender, não para resistir. Se estiver atrasando a decisão, me diga e eu paro.",
    ],
    zonaConforto: {
      onde: "O aprofundamento sem fim — analisar em vez de entregar.",
      saida: "O que costuma tirar você de lá é um prazo firme com critério de suficiência combinado antes. Não é pressão — é combinado.",
    },
    comunicacao: {
      entrega: "Você é preciso e fundamentado. Quando você afirma alguma coisa, as pessoas sabem que você verificou.",
      perde: "O que costuma se perder é o tempo de quem escuta: nem toda conversa comporta o raciocínio inteiro, e quando ele vem completo a mensagem principal se dilui.",
      ajuste: "Comece pela conclusão e ofereça o caminho: 'minha recomendação é X. Se quiser, te explico como cheguei'.",
    },
    feedback: {
      comoPedir: "Feedback genérico não funciona com você: você precisa do exemplo concreto. Peça assim: 'me dá um exemplo de quando isso aconteceu?'.",
      reacaoHabitual: "Sua reação habitual à crítica é buscar o contra-argumento antes de considerar. De fora parece defesa. Vale dizer: 'deixa eu pensar sobre isso e te respondo'.",
    },
  },
};

// ── Seção 12 — Trabalhando com os outros perfis ──────────────────────────────
// Chave externa = arquétipo do LEITOR. Chave interna = o OUTRO arquétipo.
export const OUTROS_PERFIS: Record<Arquetipo, Partial<Record<Arquetipo, BlocoOutroPerfil>>> = {
  pioneiro: {
    conector: {
      comoTeVe: "Alguém que decide antes de trazer todo mundo junto.",
      atrito: "Você quer resultado, ele quer as pessoas alinhadas. Ele lê sua pressa como atropelo; você lê a articulação dele como demora.",
      ajuste: "Antes de fechar, dê a ele um minuto para dizer quem será impactado — costuma poupar retrabalho depois.",
    },
    guardiao: {
      comoTeVe: "Alguém rápido demais para o conforto dele.",
      atrito: "Você muda de rota com facilidade; ele precisa de aviso e de tempo para reorganizar.",
      ajuste: "Avise as mudanças com alguma antecedência, mesmo que ainda não confirmadas. O aviso vale mais que a velocidade aqui.",
    },
    estrategista: {
      comoTeVe: "Alguém que age antes de fundamentar.",
      atrito: "Você quer decisão; ele quer o porquê. A pergunta dele parece freio para você.",
      ajuste: "Traga o problema com o que você já concluiu e peça o furo que ele enxerga — vira contribuição, não freio.",
    },
  },
  conector: {
    pioneiro: {
      comoTeVe: "Alguém que gasta energia com gente quando era para decidir.",
      atrito: "Ele quer fechar; você quer todo mundo junto. Ele acha que você enrola; você acha que ele atropela.",
      ajuste: "Traga a decisão pronta e diga só depois quem você já alinhou — a articulação vira agilidade aos olhos dele.",
    },
    guardiao: {
      comoTeVe: "Alguém de muita energia e muitas frentes.",
      atrito: "Você abre frentes e muda o clima rápido; ele precisa de estabilidade e de fechamento.",
      ajuste: "Feche o que combinou com ele antes de abrir a próxima frente; previsibilidade é o que constrói confiança aí.",
    },
    estrategista: {
      comoTeVe: "Alguém difícil de entusiasmar.",
      atrito: "Você mobiliza pela energia; ele se convence pelo dado. Seu entusiasmo soa sem base para ele.",
      ajuste: "Traga um número ou um fato junto da ideia — a energia com base ganha o Estrategista.",
    },
  },
  guardiao: {
    pioneiro: {
      comoTeVe: "Alguém tranquilo demais para o ritmo dele.",
      atrito: "Ele muda de rota sem aviso; você precisa de tempo para reorganizar. O que para ele é agilidade, para você é sobressalto.",
      ajuste: "Peça a ele um aviso curto antes das mudanças e diga que isso te faz render mais — costuma ser aceito.",
    },
    conector: {
      comoTeVe: "Alguém constante e reservado.",
      atrito: "Ele traz muita gente e muita frente; você prefere estabilidade e foco.",
      ajuste: "Combine com ele o que fica sob sua responsabilidade e proteja isso do excesso de frentes novas.",
    },
    estrategista: {
      comoTeVe: "Alguém confiável e de ritmo parecido.",
      atrito: "Pouco. O risco é a dupla ficar lenta e nenhum dos dois puxar o fechamento.",
      ajuste: "Combinem quem puxa o prazo, para o cuidado de vocês dois não virar demora.",
    },
  },
  estrategista: {
    pioneiro: {
      comoTeVe: "Alguém que pergunta demais antes de agir.",
      atrito: "Ele quer decisão, você quer fundamento. Ele lê sua pergunta como resistência; você lê a pressa dele como imprudência.",
      ajuste: "Antes de perguntar, diga o que você já concluiu. A pergunta vinda depois de uma conclusão soa como contribuição, não como freio.",
    },
    conector: {
      comoTeVe: "Alguém técnico e difícil de entusiasmar.",
      atrito: "Ele mobiliza pela energia, você se convence pelo dado.",
      ajuste: "Reconheça a intenção antes de apontar o furo: 'gostei da direção, tenho uma dúvida sobre o número'.",
    },
    guardiao: {
      comoTeVe: "Alguém técnico e um pouco distante.",
      atrito: "Pouco — vocês têm ritmos parecidos. O risco é a dupla ficar lenta e ninguém cobrar o fechamento.",
      ajuste: "Combinem quem puxa o prazo.",
    },
  },
};

// ── Seção 11 — Em pressão e em conflito, pelo Modo de Contexto (doc 5.3) ───────
export const PRESSAO_POR_MODO: Record<Modo | "misto", string> = {
  constante:
    "Você mantém o ritmo mesmo quando o cenário muda, e isso faz de você uma referência nos momentos difíceis. O cuidado é outro: quem aguenta sempre costuma receber mais do que consegue sustentar, e o desgaste aparece tarde. Vale aprender a sinalizar antes do limite.",
  cadenciado:
    "Você rende mais quando o ritmo é previsível, e isso não é fragilidade — é a condição em que seu trabalho fica melhor. O que ajuda: pedir antecedência nas mudanças, negociar prazo em vez de absorver em silêncio, e proteger blocos de tempo sem interrupção.",
  misto:
    "Você suporta bem a pressão em alguns contextos e menos em outros. Vale observar quais: o padrão costuma estar no tipo de trabalho, não na intensidade dele.",
};

// ── Camadas do Motor de Decisão (seção 3) ─────────────────────────────────────
export const MOTOR_RELATORIO: Record<"racional" | "relacional" | "pragmatico", string> = {
  racional: "Você se convence por dado, lógica e consistência — e é assim que tenta convencer os outros.",
  relacional: "Você se convence pelo propósito e pelo impacto nas pessoas — e é por aí que mobiliza os outros.",
  pragmatico: "Você se convence pelo retorno prático e pelos próximos passos — e é assim que destrava os outros.",
};

// ── Modo de Contexto — parágrafo curto para a seção 3 ─────────────────────────
export const MODO_RELATORIO: Record<Modo | "misto", string> = {
  constante: "Você tende a manter o desempenho estável diante de pressão e mudança de rota.",
  cadenciado: "Você rende mais quando o ritmo é previsível. Isso não é fragilidade: é a condição em que seu trabalho fica melhor.",
  misto: "Você transita entre um ritmo constante e um cadenciado, conforme o contexto.",
};

// ── Texto de intensidade por faixa (RN-006 / RN-027) ──────────────────────────
export function textoIntensidade(intensidade: number): string {
  if (intensidade >= 9) return "Essa é uma característica bem marcada em você.";
  if (intensidade >= 5) return "Essa é uma tendência clara, mas você transita entre os dois lados.";
  return "Você transita bem entre os dois lados. Isso é flexibilidade, não indefinição.";
}

// ── Texto fixo de abertura (seção 1) e de fechamento (seção 15) ────────────────
export const RELATORIO_ABERTURA = [
  "Este é o seu mapa comportamental. Ele mostra como você tende a trabalhar — não o quanto você é bom no que faz.",
  "Não existe perfil melhor ou pior. Existem jeitos diferentes de chegar ao resultado, cada um com forças e custos próprios.",
  "Este documento é seu. Seu gestor e o RH veem o resultado interpretado, mas ninguém vê o que você marcou em cada pergunta. Você pode consultar a qualquer momento quem acessou o seu mapa.",
  "Ele não é avaliação de desempenho, não é exame psicológico e não é usado para decidir promoção, salário ou desligamento.",
];

export const RELATORIO_SOBRE = [
  "Quem tem acesso ao seu resultado interpretado: seu gestor imediato e o RH. Ninguém acessa as suas respostas individuais.",
  "Este não é um exame psicológico nem uma avaliação de desempenho, e não decide nada sobre a sua carreira.",
];
