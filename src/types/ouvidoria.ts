export type TipoManifestacao = 'sugestao' | 'reclamacao' | 'denuncia' | 'elogio' | 'duvida';
export type StatusManifestacao = 'pendente' | 'em_analise' | 'respondido' | 'arquivado';
export type PrioridadeManifestacao = 'baixa' | 'normal' | 'alta' | 'urgente';

export interface AnexoManifestacao {
  nome: string;
  url: string;
  tamanho: number;
  tipo: string;
}

export interface Manifestacao {
  id: string;
  tenant_id: string;
  tipo: TipoManifestacao;
  assunto: string;
  mensagem: string;
  anonimo: boolean;
  autor_id: string | null;
  autor_nome: string | null;
  autor_email: string | null;
  autor_departamento: string | null;
  status: StatusManifestacao;
  prioridade: PrioridadeManifestacao;
  resposta: string | null;
  respondido_por: string | null;
  respondido_por_nome: string | null;
  respondido_em: string | null;
  anexos: AnexoManifestacao[] | null;
  // Preenchidos pelo link público: empresa resolvida pelo CPF (nula quando anônima
  // ou CPF fora do cadastro), origem ('app' | 'link_publico'), CPF do autor e o
  // protocolo de acompanhamento.
  empresa_id: string | null;
  origem: string | null;
  autor_cpf: string | null;
  protocolo: string | null;
  created_at: string;
  updated_at: string;
}

export type ManifestacaoInsert = Omit<Manifestacao, 'id' | 'created_at' | 'updated_at' | 'resposta' | 'respondido_por' | 'respondido_por_nome' | 'respondido_em'>;

export const TIPO_MANIFESTACAO_LABELS: Record<TipoManifestacao, string> = {
  sugestao: 'Sugestão',
  reclamacao: 'Reclamação',
  denuncia: 'Denúncia',
  elogio: 'Elogio',
  duvida: 'Dúvida',
};

export const TIPO_MANIFESTACAO_ICONS: Record<TipoManifestacao, string> = {
  sugestao: '💡',
  reclamacao: '⚠️',
  denuncia: '🚨',
  elogio: '⭐',
  duvida: '❓',
};

export const TIPO_MANIFESTACAO_COLORS: Record<TipoManifestacao, string> = {
  sugestao: 'bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400',
  reclamacao: 'bg-orange-100 text-orange-800 dark:bg-orange-900/30 dark:text-orange-400',
  denuncia: 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400',
  elogio: 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400',
  duvida: 'bg-purple-100 text-purple-800 dark:bg-purple-900/30 dark:text-purple-400',
};

export const STATUS_MANIFESTACAO_LABELS: Record<StatusManifestacao, string> = {
  pendente: 'Pendente',
  em_analise: 'Em Análise',
  respondido: 'Respondido',
  arquivado: 'Arquivado',
};

export const STATUS_MANIFESTACAO_COLORS: Record<StatusManifestacao, string> = {
  pendente: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400',
  em_analise: 'bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400',
  respondido: 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400',
  arquivado: 'bg-gray-100 text-gray-800 dark:bg-gray-900/30 dark:text-gray-400',
};

export const PRIORIDADE_LABELS: Record<PrioridadeManifestacao, string> = {
  baixa: 'Baixa',
  normal: 'Normal',
  alta: 'Alta',
  urgente: 'Urgente',
};

export const PRIORIDADE_COLORS: Record<PrioridadeManifestacao, string> = {
  baixa: 'bg-gray-100 text-gray-800 dark:bg-gray-900/30 dark:text-gray-400',
  normal: 'bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400',
  alta: 'bg-orange-100 text-orange-800 dark:bg-orange-900/30 dark:text-orange-400',
  urgente: 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400',
};
