// Tipos do Módulo de Estratégia e Governança

export type SwotTipo = 'forca' | 'fraqueza' | 'oportunidade' | 'ameaca';
export type SwotClassificacao = 'estrategico' | 'operacional' | 'cultural' | 'pessoas' | 'mercado';
export type SwotImpacto = 'baixo' | 'medio' | 'alto';
export type OceanoQuadrante = 'eliminar' | 'reduzir' | 'elevar' | 'criar';

export interface EstrategiaSwot {
  id: string;
  tenant_id: string;
  titulo: string;
  descricao?: string;
  escopo: string;
  unidade?: string;
  periodo?: string;
  projeto?: string;
  criado_por?: string;
  criado_por_nome?: string;
  created_at: string;
  updated_at: string;
  itens?: SwotItem[];
}

export interface SwotItem {
  id: string;
  tenant_id: string;
  swot_id: string;
  tipo: SwotTipo;
  descricao: string;
  classificacao: SwotClassificacao;
  impacto: SwotImpacto;
  ordem: number;
  created_at: string;
  updated_at: string;
}

export interface EstrategiaOceanoAzul {
  id: string;
  tenant_id: string;
  swot_id?: string;
  titulo: string;
  descricao?: string;
  criado_por?: string;
  criado_por_nome?: string;
  created_at: string;
  updated_at: string;
  itens?: OceanoItem[];
}

export interface OceanoItem {
  id: string;
  tenant_id: string;
  oceano_id: string;
  quadrante: OceanoQuadrante;
  descricao: string;
  swot_item_id?: string;
  ordem: number;
  created_at: string;
}

export interface EstrategiaCultura {
  id: string;
  tenant_id: string;
  missao?: string;
  visao?: string;
  valores: string[];
  principios: string[];
  comportamentos_esperados: string[];
  comportamentos_nao_tolerados: string[];
  // Campos de texto livre do Manual de Cultura (Onda 1)
  proposito?: string;
  carta_boas_vindas?: string;
  tom_de_voz?: string;
  codigo_conduta?: string;
  dress_code?: string;
  modelo_trabalho?: string;
  criado_por?: string;
  criado_por_nome?: string;
  created_at: string;
  updated_at: string;
}

export interface EstrategiaOrganograma {
  id: string;
  tenant_id: string;
  parent_id?: string;
  cargo_id?: string;
  departamento_id?: string;
  titulo: string;
  nome_ocupante?: string;
  colaborador_id?: string;
  tipo: string;
  ordem: number;
  created_at: string;
  updated_at: string;
  colaborador?: { id: string; nome_completo: string; foto_url?: string };
  children?: EstrategiaOrganograma[];
}

// Labels
export const SWOT_TIPO_LABELS: Record<SwotTipo, string> = {
  forca: 'Força',
  fraqueza: 'Fraqueza',
  oportunidade: 'Oportunidade',
  ameaca: 'Ameaça',
};

export const SWOT_CLASSIFICACAO_LABELS: Record<SwotClassificacao, string> = {
  estrategico: 'Estratégico',
  operacional: 'Operacional',
  cultural: 'Cultural',
  pessoas: 'Pessoas',
  mercado: 'Mercado',
};

export const SWOT_IMPACTO_LABELS: Record<SwotImpacto, string> = {
  baixo: 'Baixo',
  medio: 'Médio',
  alto: 'Alto',
};

export const OCEANO_QUADRANTE_LABELS: Record<OceanoQuadrante, string> = {
  eliminar: 'Eliminar',
  reduzir: 'Reduzir',
  elevar: 'Elevar',
  criar: 'Criar',
};
