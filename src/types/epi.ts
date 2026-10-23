import type { Database } from "@/integrations/supabase/types";

// Enums
export type EpiStatus = Database["public"]["Enums"]["epi_status"];
export type EntregaStatus = Database["public"]["Enums"]["entrega_status"];

// Tipos de tabela
export type EpiTipo = Database["public"]["Tables"]["epi_tipos"]["Row"] & {
  // Campos adicionados pela migração
  categoria?: string | null;
  ca_numero?: string | null;
  ca_validade?: string | null;
  marca?: string | null;
  fabricante?: string | null;
  estoque_minimo?: number | null;
  quantidade_estoque?: number | null;
  is_active?: boolean | null;
  unidade_medida?: string | null;
  tipo_durabilidade?: string | null;
  periodicidade_troca_dias?: number | null;
};
export type EpiTipoInsert = Database["public"]["Tables"]["epi_tipos"]["Insert"];

export type Epi = Database["public"]["Tables"]["epis"]["Row"];
export type EpiInsert = Database["public"]["Tables"]["epis"]["Insert"];
export type EpiUpdate = Database["public"]["Tables"]["epis"]["Update"];

export type EpiEntrega = Database["public"]["Tables"]["epi_entregas"]["Row"] & {
  // Campos adicionados pela migração
  assinatura_url?: string | null;
  ip_address?: string | null;
  user_agent?: string | null;
  signed_at?: string | null;
  liveness_detected?: boolean | null;
  liveness_data?: LivenessDataEpi | null;
  data_validade?: string | null;
  employee_id?: string | null;
};
export type EpiEntregaInsert = Database["public"]["Tables"]["epi_entregas"]["Insert"];
export type EpiEntregaUpdate = Database["public"]["Tables"]["epi_entregas"]["Update"];

export type EpiMovimentacao = Database["public"]["Tables"]["epi_movimentacoes"]["Row"];

// Tipos estendidos
export interface EpiCompleto extends Epi {
  tipo: EpiTipo;
  entregas?: EpiEntrega[];
}

export interface EpiEntregaCompleta extends EpiEntrega {
  epi: EpiCompleto;
}

// Labels e cores
export const EPI_STATUS_LABELS: Record<EpiStatus, string> = {
  disponivel: "Disponível",
  em_uso: "Em Uso",
  danificado: "Danificado",
  vencido: "Vencido",
  descartado: "Descartado",
};

export const EPI_STATUS_COLORS: Record<EpiStatus, string> = {
  disponivel: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300",
  em_uso: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-300",
  danificado: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-300",
  vencido: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-300",
  descartado: "bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-300",
};

export const ENTREGA_STATUS_LABELS: Record<EntregaStatus, string> = {
  ativa: "Ativa",
  devolvido: "Devolvido",
  extraviado: "Extraviado",
  vencido: "Vencido",
};

export const ENTREGA_STATUS_COLORS: Record<EntregaStatus, string> = {
  ativa: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300",
  devolvido: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-300",
  extraviado: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-300",
  vencido: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-300",
};

// Categorias de EPI (agrupamentos)
export const CATEGORIAS_EPI = [
  "Proteção da Cabeça",
  "Proteção Auditiva",
  "Proteção Respiratória",
  "Proteção Visual",
  "Proteção Facial",
  "Proteção das Mãos",
  "Proteção dos Pés",
  "Proteção contra Quedas",
  "Proteção do Tronco",
  "Sinalização e Visibilidade",
  "Outros",
] as const;

export type CategoriaEpi = typeof CATEGORIAS_EPI[number];

// Unidades de medida
export const UNIDADES_MEDIDA = [
  { value: "unidade", label: "Unidade" },
  { value: "par", label: "Par" },
  { value: "caixa", label: "Caixa" },
  { value: "pacote", label: "Pacote" },
  { value: "rolo", label: "Rolo" },
  { value: "kit", label: "Kit" },
] as const;

// Tipos de durabilidade
export const TIPOS_DURABILIDADE = [
  { value: "duravel", label: "Durável" },
  { value: "descartavel", label: "Descartável" },
] as const;

// Tipos de EPI padrão (para seed inicial)
export const TIPOS_EPI_PADRAO = [
  { nome: "Capacete de Segurança", descricao: "Proteção para a cabeça", categoria: "Proteção da Cabeça", validade_meses: 60 },
  { nome: "Óculos de Proteção", descricao: "Proteção ocular", categoria: "Proteção Visual", validade_meses: 24 },
  { nome: "Protetor Auricular", descricao: "Proteção auditiva tipo plug", categoria: "Proteção Auditiva", validade_meses: 12 },
  { nome: "Abafador de Ruído", descricao: "Proteção auditiva tipo concha", categoria: "Proteção Auditiva", validade_meses: 24 },
  { nome: "Luvas de Segurança", descricao: "Proteção para as mãos", categoria: "Proteção das Mãos", validade_meses: 6 },
  { nome: "Botina de Segurança", descricao: "Proteção para os pés", categoria: "Proteção dos Pés", validade_meses: 12 },
  { nome: "Cinto de Segurança", descricao: "Proteção contra quedas", categoria: "Proteção contra Quedas", validade_meses: 24 },
  { nome: "Máscara Respiratória PFF2", descricao: "Proteção respiratória descartável", categoria: "Proteção Respiratória", validade_meses: 6 },
  { nome: "Respirador Semi-Facial", descricao: "Proteção respiratória reutilizável", categoria: "Proteção Respiratória", validade_meses: 12 },
  { nome: "Avental de Segurança", descricao: "Proteção do tronco", categoria: "Proteção do Tronco", validade_meses: 12 },
  { nome: "Protetor Facial", descricao: "Proteção facial completa", categoria: "Proteção Facial", validade_meses: 24 },
  { nome: "Colete Refletivo", descricao: "Sinalização de alta visibilidade", categoria: "Sinalização e Visibilidade", validade_meses: 24 },
];

// Motivos de entrega padrão
export const MOTIVOS_ENTREGA = [
  "Admissão",
  "Substituição por Desgaste",
  "Substituição por Dano",
  "Substituição por Perda",
  "Vencimento do EPI anterior",
  "Mudança de Função",
  "Treinamento",
  "Outro",
];

// Payload da edição de um EPI: cada bloco vai para a sua tabela
export interface EpiEdicaoPayload {
  epi: {
    ca: string | null;
    codigo: string | null;
    marca: string | null;
    modelo: string | null;
    data_fabricacao: string | null;
    data_validade: string | null;
    quantidade_minima: number;
    custo_unitario: number | null;
    localizacao: string | null;
    observacoes: string | null;
  };
  tipo: {
    nome: string;
    categoria: string | null;
    unidade_medida: string | null;
    tipo_durabilidade: string | null;
    periodicidade_troca_dias: number | null;
    marca: string | null;
    fabricante: string | null;
    ca_numero: string | null;
    ca_validade: string | null;
  };
}

/**
 * O que a verificação de presença grava em epi_entregas.liveness_data.
 * `metodo` = 'face-landmarker' só quando TODAS as ações foram detectadas
 * automaticamente no aparelho; 'manual' quando houve confirmação por botão;
 * 'nenhum' quando não houve verificação. As fotos ficam no bucket privado
 * (`frames_paths`); fichas antigas podem trazer `frames` em base64.
 */
export interface LivenessDataEpi {
  metodo?: "face-landmarker" | "manual" | "nenhum";
  versao_do_detector?: string | null;
  actions?: string[];
  timestamps?: string[];
  detalhes?: { tipo: string; confirmada_por: "automatica" | "manual"; detectado_em: string; pontuacao: number | null }[];
  tentativas_sem_sucesso?: { tipo: string; pico_giro: number; pico_piscar: number }[];
  frames_paths?: string[];
  frames?: string[];
}
