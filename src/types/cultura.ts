export interface CulturaData {
  id: string;
  tenant_id: string;
  titulo: string;
  descricao: string | null;
  tipo: string;
  recorrencia: string;
  mes: number | null;
  dia: number | null;
  data_especifica: string | null;
  ativo: boolean;
  filtro_unidade: string | null;
  filtro_setor: string | null;
  created_at: string;
  updated_at: string;
}

export type AutomacaoModo = "desligado" | "aprovar";
export type TomMensagem = "formal" | "leve";

export interface CulturaPreferencia {
  id: string;
  tenant_id: string;
  colaborador_id: string;
  colaborador_nome: string;
  preferencia_aniversario: string;
  tipo_reconhecimento: string;
  observacoes: string | null;
  created_at: string;
  updated_at: string;
}

export interface CulturaMarco {
  id: string;
  tenant_id: string;
  anos: number;
  tipo_celebracao: string;
  descricao: string | null;
  ativo: boolean;
  created_at: string;
  updated_at: string;
}

export interface CulturaConfig {
  id: string;
  tenant_id: string;
  aniversario_ativo: boolean;
  tempo_casa_ativo: boolean;
  dia_profissao_ativo: boolean;
  dias_antecedencia_acao: number;
  presente_padrao: boolean;
  limite_valor_presente: number | null;
  folga_permitida: boolean;
  responsavel_padrao: string;
  /** desligado | aprovar — a rotina diária só cria ações pendentes; publicar e concluir seguem humanos */
  automacao_aniversario: AutomacaoModo;
  automacao_tempo_casa: AutomacaoModo;
  tom_mensagem: TomMensagem;
  /** meta de cobertura de celebração (%), abaixo dela a tela alerta */
  meta_cobertura: number;
  created_at: string;
  updated_at: string;
}

export interface CulturaAcao {
  id: string;
  tenant_id: string;
  tipo: string;
  titulo: string;
  descricao: string | null;
  colaborador_id: string | null;
  colaborador_nome: string | null;
  data_referencia: string;
  data_execucao: string | null;
  responsavel: string | null;
  responsavel_nome: string | null;
  status: string;
  observacoes: string | null;
  cultura_data_id: string | null;
  /** manual | automatica */
  origem?: string;
  chave_unica?: string | null;
  publicado_em?: string | null;
  created_at: string;
  updated_at: string;
}

export interface CulturaRitual {
  id: string;
  tenant_id: string;
  nome: string;
  descricao: string | null;
  frequencia: string;
  dia_semana: number | null;
  dia_mes: number | null;
  responsavel: string | null;
  responsavel_nome: string | null;
  ativo: boolean;
  ultima_execucao: string | null;
  proxima_execucao: string | null;
  created_at: string;
  updated_at: string;
}

export const TIPO_DATA_LABELS: Record<string, string> = {
  comemorativa: "Comemorativa",
  campanha: "Campanha",
  regional: "Regional",
  interna: "Interna",
};

export const TIPO_ACAO_LABELS: Record<string, string> = {
  aniversario: "Aniversário",
  tempo_casa: "Tempo de Casa",
  dia_profissao: "Dia da Profissão",
  data_configurada: "Data Configurada",
  ritual: "Ritual",
};

export const STATUS_ACAO_LABELS: Record<string, string> = {
  pendente: "Pendente",
  em_andamento: "Em Andamento",
  concluida: "Concluída",
  cancelada: "Cancelada",
};

export const STATUS_ACAO_COLORS: Record<string, string> = {
  pendente: "bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400",
  em_andamento: "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400",
  concluida: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400",
  cancelada: "bg-gray-100 text-gray-500 dark:bg-gray-900/30 dark:text-gray-400",
};

export const FREQUENCIA_LABELS: Record<string, string> = {
  semanal: "Semanal",
  quinzenal: "Quinzenal",
  mensal: "Mensal",
  trimestral: "Trimestral",
};

export const CELEBRACAO_LABELS: Record<string, string> = {
  reconhecimento: "Reconhecimento Público",
  mimo: "Mimo / Presente",
  certificado: "Certificado",
  enfeite: "Decoração da Mesa",
  publico: "Homenagem Pública",
};
