/**
 * Tipos da Entidade Unificada de Risco GRO
 * Consolida riscos Ergonômicos (Físicos) + Psicossociais
 * Conformidade: NR-1 (GRO), NR-17, ISO 45003
 */
import { resolverFatorPorSubject } from "@/data/catalogoRiscosPsicossociais";
import { scoreToProb15, nivelGRO15, sevFallbackFromScore, type Sev15 } from "@/lib/groPsicossocial15";

export type GROSubtipo = 'fisico' | 'psicossocial';
export type GROFonte = 'aep' | 'questionario' | 'ia' | 'observacao' | 'manual' | 'psicossocial';
export type GROProbabilidade = 'muito_baixa' | 'baixa' | 'moderada' | 'alta' | 'muito_alta';
export type GROSeveridade = 'leve' | 'moderada' | 'grave' | 'gravissima';
export type GRONivelRisco = 'baixo' | 'medio' | 'alto' | 'critico';
export type GROStatusCiclo = 'identificado' | 'avaliado' | 'controlado' | 'monitorado' | 'revisado';

export interface GRORisco {
  id: string;
  tenant_id: string;
  empresa_id?: string | null;

  subtipo: GROSubtipo;
  fonte: GROFonte;

  titulo: string;
  descricao?: string | null;
  perigo_identificado?: string | null;

  setor?: string | null;
  cargo?: string | null;
  atividade?: string | null;
  unidade?: string | null;

  trabalhadores_expostos?: number | null;
  grupos_expostos?: string[] | null;

  probabilidade: GROProbabilidade;
  severidade: GROSeveridade;
  nivel_risco: GRONivelRisco;

  medidas_existentes?: string[] | null;
  medidas_recomendadas?: string[] | null;

  campanha_id?: string | null;
  analise_ergonomia_id?: string | null;
  ergonomia_risco_id?: string | null;

  base_normativa?: string[] | null;
  dimensao_psicossocial?: string | null;
  score_dimensao?: number | null;

  acao_id?: string | null;
  status_gro: GROStatusCiclo;
  ativo: boolean;

  // GAP 3: Reavaliação obrigatória pós-ação
  necessita_reavaliacao?: boolean;
  reavaliacao_motivo?: string | null;
  reavaliacao_solicitada_em?: string | null;

  created_at: string;
  updated_at: string;
}

export interface NovoGRORisco {
  empresa_id?: string | null;
  subtipo: GROSubtipo;
  fonte: GROFonte;
  titulo: string;
  descricao?: string;
  perigo_identificado?: string;
  setor?: string;
  cargo?: string;
  atividade?: string;
  unidade?: string;
  trabalhadores_expostos?: number;
  grupos_expostos?: string[];
  probabilidade: GROProbabilidade;
  severidade: GROSeveridade;
  medidas_existentes?: string[];
  medidas_recomendadas?: string[];
  campanha_id?: string;
  analise_ergonomia_id?: string;
  ergonomia_risco_id?: string;
  base_normativa?: string[];
  dimensao_psicossocial?: string;
  score_dimensao?: number;
}

// Labels e Cores
export const GRO_SUBTIPO_LABELS: Record<GROSubtipo, string> = {
  fisico: 'Ergonômico / Físico',
  psicossocial: 'Psicossocial',
};

export const GRO_SUBTIPO_COLORS: Record<GROSubtipo, string> = {
  fisico: 'bg-blue-100 text-blue-800 border-blue-200',
  psicossocial: 'bg-purple-100 text-purple-800 border-purple-200',
};

export const GRO_FONTE_LABELS: Record<GROFonte, string> = {
  aep: 'AEP',
  questionario: 'Questionário',
  ia: 'Análise IA',
  observacao: 'Observação Direta',
  manual: 'Registro Manual',
  psicossocial: 'Módulo Psicossocial',
};

export const GRO_PROBABILIDADE_LABELS: Record<GROProbabilidade, string> = {
  muito_baixa: 'Muito Baixa',
  baixa: 'Baixa',
  moderada: 'Moderada',
  alta: 'Alta',
  muito_alta: 'Muito Alta',
};

export const GRO_SEVERIDADE_LABELS: Record<GROSeveridade, string> = {
  leve: 'Leve',
  moderada: 'Moderada',
  grave: 'Grave',
  gravissima: 'Gravíssima',
};

export const GRO_NIVEL_RISCO_LABELS: Record<GRONivelRisco, string> = {
  baixo: 'Risco Baixo',
  medio: 'Risco Médio',
  alto: 'Risco Alto',
  critico: 'Risco Crítico',
};

export const GRO_NIVEL_RISCO_COLORS: Record<GRONivelRisco, string> = {
  baixo: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  medio: 'bg-amber-50 text-amber-700 border-amber-200',
  alto: 'bg-orange-50 text-orange-700 border-orange-200',
  critico: 'bg-red-50 text-red-700 border-red-200',
};

export const GRO_STATUS_LABELS: Record<GROStatusCiclo, string> = {
  identificado: 'Identificado',
  avaliado: 'Avaliado',
  controlado: 'Controlado',
  monitorado: 'Monitorado',
  revisado: 'Revisado',
};

export const GRO_STATUS_COLORS: Record<GROStatusCiclo, string> = {
  identificado: 'bg-gray-100 text-gray-700 border-gray-200',
  avaliado: 'bg-blue-50 text-blue-700 border-blue-200',
  controlado: 'bg-amber-50 text-amber-700 border-amber-200',
  monitorado: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  revisado: 'bg-purple-50 text-purple-700 border-purple-200',
};

/**
 * Calcula o nível de risco com base em probabilidade e severidade.
 * Espelha a lógica do trigger SQL `calcular_nivel_gro_risco`.
 */
export function calcularNivelGRO(prob: GROProbabilidade, sev: GROSeveridade): GRONivelRisco {
  if (['alta', 'muito_alta'].includes(prob) && ['grave', 'gravissima'].includes(sev)) return 'critico';
  if (['alta', 'muito_alta'].includes(prob) && sev === 'moderada') return 'alto';
  if (prob === 'moderada' && ['grave', 'gravissima'].includes(sev)) return 'alto';
  if (['baixa', 'muito_baixa'].includes(prob) && ['grave', 'gravissima'].includes(sev)) return 'medio';
  if (prob === 'moderada' && sev === 'moderada') return 'medio';
  if (['alta', 'muito_alta'].includes(prob) && sev === 'leve') return 'medio';
  return 'baixo';
}

/**
 * Converte score de dimensão psicossocial para probabilidade GRO.
 * SIPRO: score alto = maior risco.
 */
export function scoreToProbabilidade(score: number, isSipro = true): GROProbabilidade {
  const risco = isSipro ? score : 100 - score;
  if (risco >= 75) return 'muito_alta';
  if (risco >= 55) return 'alta';
  if (risco >= 35) return 'moderada';
  if (risco >= 20) return 'baixa';
  return 'muito_baixa';
}

export function scoreToProbabilidadeLabel(score: number, isSipro = true): string {
  return GRO_PROBABILIDADE_LABELS[scoreToProbabilidade(score, isSipro)];
}

export function scoreToSeveridade(score: number, isSipro = true): GROSeveridade {
  const risco = isSipro ? score : 100 - score;
  if (risco >= 75) return 'gravissima';
  if (risco >= 55) return 'grave';
  if (risco >= 35) return 'moderada';
  return 'leve';
}

/**
 * Converte a severidade FIXA do catálogo (1-5) para o enum de 4 níveis do
 * GRO corporativo. 1 e 2 colapsam em 'leve'; 5 vira 'gravissima'.
 */
export function severidadeCatalogoToGRO(sev: number): GROSeveridade {
  if (sev >= 5) return 'gravissima';
  if (sev === 4) return 'grave';
  if (sev === 3) return 'moderada';
  return 'leve';
}

/**
 * Fase 0.1 — Fonte única do risco psicossocial ao exportar para o GRO.
 *
 * Usa a MESMA metodologia do inventário psicossocial (groPsicossocial15 +
 * catálogo de riscos), eliminando a divergência em que o GRO derivava a
 * severidade do score:
 *   - probabilidade: VARIÁVEL, derivada do score (scoreToProbabilidade);
 *   - severidade: FIXA do catálogo (severidadePadrao do fator), não do score;
 *   - nivel_risco: matriz P×S única (nivelGRO15), com TRIVIAL mapeado para
 *     'baixo' porque o GRO corporativo (compartilhado com a ergonomia)
 *     trabalha em 4 níveis.
 *
 * Fator fora do catálogo cai no fallback por score (sevFallbackFromScore),
 * para nunca quebrar a exportação.
 */
export function psicossocialDimensaoParaGRO(
  subject: string,
  score: number,
  isSipro = true,
): { probabilidade: GROProbabilidade; severidade: GROSeveridade; nivel_risco: GRONivelRisco } {
  const risco = isSipro ? score : 100 - score;
  const prob15 = scoreToProb15(risco);
  const fator = resolverFatorPorSubject(subject);
  const sev15: Sev15 = fator ? (fator.severidadePadrao as Sev15) : sevFallbackFromScore(risco);
  const nivel15 = nivelGRO15(prob15, sev15);
  return {
    probabilidade: scoreToProbabilidade(score, isSipro),
    severidade: severidadeCatalogoToGRO(sev15),
    nivel_risco: nivel15 === 'trivial' ? 'baixo' : nivel15,
  };
}
