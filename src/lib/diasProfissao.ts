// Mapeamento de profissões/funções para seus dias comemorativos
// Fonte: calendário brasileiro oficial de dias profissionais

export const DIAS_PROFISSAO: Record<string, { mes: number; dia: number; nome: string }> = {
  // Segurança do Trabalho
  "técnico de segurança do trabalho": { mes: 11, dia: 27, nome: "Dia do Técnico de Segurança do Trabalho" },
  "engenheiro de segurança": { mes: 12, dia: 11, nome: "Dia do Engenheiro" },
  "engenheiro de segurança do trabalho": { mes: 12, dia: 11, nome: "Dia do Engenheiro" },
  "engenheiro": { mes: 12, dia: 11, nome: "Dia do Engenheiro" },
  "engenheiro civil": { mes: 12, dia: 11, nome: "Dia do Engenheiro" },

  // Saúde
  "médico": { mes: 10, dia: 18, nome: "Dia do Médico" },
  "médico do trabalho": { mes: 10, dia: 18, nome: "Dia do Médico" },
  "enfermeiro": { mes: 5, dia: 12, nome: "Dia do Enfermeiro" },
  "enfermeiro do trabalho": { mes: 5, dia: 12, nome: "Dia do Enfermeiro" },
  "técnico de enfermagem": { mes: 5, dia: 12, nome: "Dia do Enfermeiro" },
  "fisioterapeuta": { mes: 10, dia: 13, nome: "Dia do Fisioterapeuta" },
  "fonoaudiólogo": { mes: 12, dia: 9, nome: "Dia do Fonoaudiólogo" },
  "nutricionista": { mes: 8, dia: 31, nome: "Dia do Nutricionista" },
  "psicólogo": { mes: 8, dia: 27, nome: "Dia do Psicólogo" },
  "farmacêutico": { mes: 1, dia: 20, nome: "Dia do Farmacêutico" },
  "dentista": { mes: 10, dia: 25, nome: "Dia do Dentista" },

  // RH e Gestão
  "analista de rh": { mes: 6, dia: 3, nome: "Dia do Profissional de RH" },
  "gerente de rh": { mes: 6, dia: 3, nome: "Dia do Profissional de RH" },
  "coordenador de rh": { mes: 6, dia: 3, nome: "Dia do Profissional de RH" },
  "assistente de rh": { mes: 6, dia: 3, nome: "Dia do Profissional de RH" },
  "administrador": { mes: 9, dia: 9, nome: "Dia do Administrador" },
  "secretário": { mes: 9, dia: 30, nome: "Dia da Secretária" },
  "secretária": { mes: 9, dia: 30, nome: "Dia da Secretária" },

  // Contabilidade e Finanças
  "contador": { mes: 9, dia: 22, nome: "Dia do Contador" },
  "analista financeiro": { mes: 9, dia: 22, nome: "Dia do Contador" },
  "economista": { mes: 8, dia: 13, nome: "Dia do Economista" },

  // TI
  "programador": { mes: 9, dia: 13, nome: "Dia do Programador" },
  "desenvolvedor": { mes: 9, dia: 13, nome: "Dia do Programador" },
  "analista de sistemas": { mes: 9, dia: 13, nome: "Dia do Programador" },
  "analista de ti": { mes: 9, dia: 13, nome: "Dia do Programador" },

  // Jurídico
  "advogado": { mes: 8, dia: 11, nome: "Dia do Advogado" },

  // Comunicação
  "jornalista": { mes: 4, dia: 7, nome: "Dia do Jornalista" },
  "publicitário": { mes: 2, dia: 1, nome: "Dia do Publicitário" },
  "designer": { mes: 11, dia: 5, nome: "Dia do Designer" },

  // Educação
  "professor": { mes: 10, dia: 15, nome: "Dia do Professor" },
  "pedagogo": { mes: 10, dia: 15, nome: "Dia do Professor" },

  // Operacional
  "motorista": { mes: 7, dia: 25, nome: "Dia do Motorista" },
  "eletricista": { mes: 10, dia: 17, nome: "Dia do Eletricista" },
  "mecânico": { mes: 12, dia: 5, nome: "Dia do Mecânico" },
  "soldador": { mes: 5, dia: 29, nome: "Dia do Soldador" },
  "bombeiro civil": { mes: 7, dia: 2, nome: "Dia do Bombeiro" },
  "porteiro": { mes: 6, dia: 9, nome: "Dia do Porteiro" },
  "zelador": { mes: 2, dia: 11, nome: "Dia do Zelador" },

  // Ambiental
  "biólogo": { mes: 9, dia: 3, nome: "Dia do Biólogo" },
  "engenheiro ambiental": { mes: 6, dia: 5, nome: "Dia do Meio Ambiente" },

  // Assistente Social
  "assistente social": { mes: 5, dia: 15, nome: "Dia do Assistente Social" },

  // Vendas
  "vendedor": { mes: 10, dia: 1, nome: "Dia do Vendedor" },
  "corretor": { mes: 8, dia: 27, nome: "Dia do Corretor" },

  // Logística
  "almoxarife": { mes: 11, dia: 15, nome: "Dia do Almoxarife" },

  // Ergonomia
  "ergonomista": { mes: 8, dia: 12, nome: "Dia do Ergonomista" },
};

/**
 * Busca o dia da profissão com base no cargo/função do colaborador.
 * Faz match parcial case-insensitive.
 */
export function buscarDiaProfissao(cargo: string): { mes: number; dia: number; nome: string } | null {
  const cargoLower = cargo.toLowerCase().trim();

  // Primeiro tenta match exato
  if (DIAS_PROFISSAO[cargoLower]) return DIAS_PROFISSAO[cargoLower];

  // Depois tenta match parcial (o cargo contém a chave ou vice-versa)
  for (const [key, value] of Object.entries(DIAS_PROFISSAO)) {
    if (cargoLower.includes(key) || key.includes(cargoLower)) {
      return value;
    }
  }

  return null;
}

// ---------------------------------------------------------------------------
// Catálogo da empresa: dias de profissão que a IA sugeriu e uma pessoa aprovou
// (ou rejeitou), ou que foram informados à mão. Vale por cima do catálogo acima.
// ---------------------------------------------------------------------------

export interface DiaProfissaoEmpresa {
  /** cargo normalizado por `normalizarCargo` */
  cargo_chave: string;
  status: "aprovado" | "rejeitado";
  nome_data: string | null;
  mes: number | null;
  dia: number | null;
}

/** Chave estável do cargo: minúsculas, sem acento e sem espaços repetidos. */
export function normalizarCargo(cargo: string): string {
  return cargo
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Dia da profissão do cargo, na ordem: decisão da empresa (aprovado vale; rejeitado
 * desliga, mesmo que o catálogo padrão casasse por engano) e, sem decisão, o catálogo padrão.
 */
export function buscarDiaProfissaoDaEmpresa(
  cargo: string,
  catalogo: readonly DiaProfissaoEmpresa[] = [],
): { mes: number; dia: number; nome: string } | null {
  const chave = normalizarCargo(cargo);
  const decisao = catalogo.find((c) => c.cargo_chave === chave);
  if (decisao) {
    if (decisao.status === "aprovado" && decisao.mes && decisao.dia && decisao.nome_data) {
      return { mes: decisao.mes, dia: decisao.dia, nome: decisao.nome_data };
    }
    return null;
  }
  return buscarDiaProfissao(cargo);
}
