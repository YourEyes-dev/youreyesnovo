// ============================================================
// Completude de uma função (cargo) — módulo Aprendizado & Papéis
// ------------------------------------------------------------
// Função PURA e testável: recebe as contagens/flags já apuradas pelo
// front e devolve o checklist do "o que falta" + o percentual.
// Não faz I/O; a busca dos dados fica na camada de UI.
//
// O item "Perfil ideal" (Onda 3) só entra na conta quando o chamador
// passa `perfilIdealDefinido` como boolean; enquanto vier `undefined`,
// ele é omitido para que 100% continue alcançável antes da Onda 3.
// ============================================================

export interface CompletudeInput {
  /** cargo.objetivo_funcao preenchido. */
  objetivoDefinido: boolean;
  /** nº de funcao_atividades do cargo. */
  atividades: number;
  /** nº de funcao_competencias do cargo. */
  competencias: number;
  /** nº de atividades do cargo que já possuem ao menos um POP. */
  atividadesComPop: number;
  /** nº de EPIs vinculados ao cargo (funcao_epi_vinculacoes). */
  episVinculados: number;
  /** existe manual gerado (manuais_gerados) para o cargo. */
  manualGerado: boolean;
  /**
   * Perfil comportamental ideal definido (Onda 3). `undefined` => item
   * ainda não aplicável (não conta). boolean => entra no checklist.
   */
  perfilIdealDefinido?: boolean;
}

export interface CompletudeItem {
  chave: "objetivo" | "atividades" | "competencias" | "pops" | "epis" | "perfil_ideal" | "manual";
  label: string;
  concluido: boolean;
  /** texto curto de apoio (ex.: "3 de 5" para POPs). */
  detalhe?: string;
  /** aba do FuncaoDetail para onde levar ao clicar (quando aplicável). */
  aba?: string;
}

export interface CompletudeResultado {
  itens: CompletudeItem[];
  concluidos: number;
  total: number;
  /** 0–100, arredondado. */
  percentual: number;
  completo: boolean;
}

export function calcularCompletude(input: CompletudeInput): CompletudeResultado {
  const atividades = Math.max(0, input.atividades);
  const competencias = Math.max(0, input.competencias);
  const atividadesComPop = Math.max(0, Math.min(input.atividadesComPop, atividades));
  const episVinculados = Math.max(0, input.episVinculados);

  const itens: CompletudeItem[] = [
    {
      chave: "objetivo",
      label: "Objetivo definido",
      concluido: !!input.objetivoDefinido,
    },
    {
      chave: "atividades",
      label: "Atividades cadastradas",
      concluido: atividades >= 1,
      detalhe: `${atividades}`,
      aba: "atividades",
    },
    {
      chave: "competencias",
      label: "Competências cadastradas",
      concluido: competencias >= 1,
      detalhe: `${competencias}`,
      aba: "competencias",
    },
    {
      // POPs só faz sentido havendo atividades; sem atividades fica pendente.
      chave: "pops",
      label: "POPs das atividades",
      concluido: atividades > 0 && atividadesComPop >= atividades,
      detalhe: `${atividadesComPop} de ${atividades}`,
      aba: "atividades",
    },
    {
      chave: "epis",
      label: "EPIs vinculados",
      concluido: episVinculados >= 1,
      detalhe: `${episVinculados}`,
      aba: "epis",
    },
  ];

  // Perfil ideal (Onda 3) — só entra quando o chamador informa o estado.
  if (typeof input.perfilIdealDefinido === "boolean") {
    itens.push({
      chave: "perfil_ideal",
      label: "Perfil ideal definido",
      concluido: input.perfilIdealDefinido,
      aba: "perfil",
    });
  }

  itens.push({
    chave: "manual",
    label: "Manual gerado",
    concluido: !!input.manualGerado,
  });

  const total = itens.length;
  const concluidos = itens.filter((i) => i.concluido).length;
  const percentual = total > 0 ? Math.round((concluidos / total) * 100) : 0;

  return {
    itens,
    concluidos,
    total,
    percentual,
    completo: concluidos === total,
  };
}
