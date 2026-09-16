// Tipos do Módulo Plano de Ação Estratégica

export type AcaoGutPrioridade = 'baixo' | 'medio' | 'urgente' | 'imediato';
export type TarefaStatus = 'nao_iniciada' | 'em_andamento' | 'bloqueada' | 'concluida';
export type AcaoStatus = 'pendente' | 'em_andamento' | 'pausada' | 'concluida' | 'cancelada';
export type AcaoTipo = 'corretiva' | 'preventiva' | 'melhoria';
export type OrigemModulo = 'manual' | 'ergonomia' | 'ouvidoria' | 'epi' | 'ponto' | 'humor' | 'psicossocial' | 'atestados' | 'sst' | 'compliance_sst' | 'compliance' | 'documentos' | 'avaliacoes' | 'estrategia' | 'gro' | 'marketplace';
export type ParticipanteTipo = 'co_responsavel' | 'consulta' | 'validacao' | 'apoio';
export type EvidenciaTipo = 'anexo' | 'foto' | 'documento' | 'comprovante';
export type HistoricoEventoTipo = 
  | 'criacao' 
  | 'edicao' 
  | 'status_alterado' 
  | 'tarefa_concluida' 
  | 'comentario' 
  | 'anexo' 
  | 'responsavel_alterado' 
  | 'encaminhamento';

// Ação Estratégica (5W2H)
export interface PlanoAcao {
  id: string;
  tenant_id: string;
  codigo: string;
  
  // 5W2H
  titulo: string;
  descricao?: string;
  porque?: string;
  onde?: string;
  prazo?: string;
  responsavel_id?: string;
  responsavel_nome?: string;
  como?: string;
  custo_estimado?: number;
  custo_real?: number;
  
  // Origem
  origem_modulo: OrigemModulo;
  origem_id?: string;
  origem_descricao?: string;
  
  // GUT
  gravidade?: number;
  urgencia?: number;
  tendencia?: number;
  pontuacao_gut?: number;
  prioridade: AcaoGutPrioridade;
  
  // Status
  status: AcaoStatus;
  progresso: number;
  
  // Datas
  data_inicio?: string;
  data_conclusao?: string;
  
  // Tipo
  tipo: AcaoTipo;
  exige_evidencia: boolean;
  
  // Tempo
  tempo_estimado_minutos?: number;
  tempo_gasto_minutos: number;
  
  // Metadados
  criado_por?: string;
  criado_por_nome?: string;
  created_at: string;
  updated_at: string;
  
  // Relacionamentos (quando carregados)
  tarefas?: PlanoTarefa[];
  participantes?: PlanoParticipante[];
  comentarios?: PlanoComentario[];
  evidencias?: PlanoEvidencia[];
}

// Tarefa Operacional
export interface PlanoTarefa {
  id: string;
  tenant_id: string;
  acao_id: string;
  
  titulo: string;
  descricao?: string;
  ordem: number;
  
  responsavel_id?: string;
  responsavel_nome?: string;
  
  status: TarefaStatus;
  prazo?: string;
  data_conclusao?: string;
  
  prioridade: AcaoGutPrioridade;
  
  depende_de?: string;
  
  tempo_estimado_minutos?: number;
  tempo_gasto_minutos: number;
  
  observacoes?: string;
  
  concluida_por?: string;
  concluida_por_nome?: string;
  
  created_at: string;
  updated_at: string;
}

// Histórico/Timeline
export interface PlanoHistorico {
  id: string;
  tenant_id: string;
  acao_id?: string;
  tarefa_id?: string;
  
  tipo_evento: HistoricoEventoTipo;
  descricao: string;
  dados_anteriores?: Record<string, unknown>;
  dados_novos?: Record<string, unknown>;
  
  usuario_id?: string;
  usuario_nome?: string;
  
  created_at: string;
}

// Comentário
export interface PlanoComentario {
  id: string;
  tenant_id: string;
  acao_id: string;
  tarefa_id?: string;
  
  conteudo: string;
  mencoes: string[];
  
  autor_id: string;
  autor_nome: string;
  
  created_at: string;
  updated_at: string;
}

// Evidência/Anexo
export interface PlanoEvidencia {
  id: string;
  tenant_id: string;
  acao_id: string;
  tarefa_id?: string;
  
  titulo: string;
  descricao?: string;
  arquivo_url?: string;
  arquivo_nome?: string;
  arquivo_tamanho?: number;
  arquivo_tipo?: string;
  
  tipo: EvidenciaTipo;
  
  enviado_por?: string;
  enviado_por_nome?: string;
  
  created_at: string;
}

// Participante/Co-responsável
export interface PlanoParticipante {
  id: string;
  tenant_id: string;
  acao_id: string;
  
  usuario_id: string;
  usuario_nome: string;
  
  tipo: ParticipanteTipo;
  
  aceito?: boolean;
  data_aceite?: string;
  
  created_at: string;
}

// Controle de Tempo
export interface PlanoTempo {
  id: string;
  tenant_id: string;
  acao_id?: string;
  tarefa_id?: string;
  
  usuario_id: string;
  usuario_nome: string;
  
  inicio: string;
  fim?: string;
  duracao_minutos?: number;
  
  descricao?: string;
  
  created_at: string;
}

// Template de Ação
export interface PlanoTemplate {
  id: string;
  tenant_id: string;
  
  nome: string;
  descricao?: string;
  categoria?: string;
  
  acao_template: Partial<PlanoAcao>;
  tarefas_template: Partial<PlanoTarefa>[];
  
  ativo: boolean;
  uso_count: number;
  
  criado_por?: string;
  criado_por_nome?: string;
  
  created_at: string;
  updated_at: string;
}

// DTOs para criação/atualização
export type CreatePlanoAcaoDTO = Omit<PlanoAcao, 
  'id' | 'tenant_id' | 'codigo' | 'pontuacao_gut' | 'progresso' | 'status' | 'tempo_gasto_minutos' | 'created_at' | 'updated_at' | 'tarefas' | 'participantes' | 'comentarios' | 'evidencias'
>;

export type UpdatePlanoAcaoDTO = Partial<CreatePlanoAcaoDTO> & {
  status?: AcaoStatus;
  progresso?: number;
  data_conclusao?: string;
};

export type CreatePlanoTarefaDTO = Omit<PlanoTarefa, 
  'id' | 'tenant_id' | 'tempo_gasto_minutos' | 'created_at' | 'updated_at'
>;

export type UpdatePlanoTarefaDTO = Partial<CreatePlanoTarefaDTO>;

// Estatísticas
export interface PlanoAcaoStats {
  total: number;
  pendentes: number;
  em_andamento: number;
  atrasadas: number;
  concluidas: number;
  tempo_medio_resolucao_dias?: number;
  por_origem: Partial<Record<OrigemModulo, number>>;
  por_prioridade: Record<AcaoGutPrioridade, number>;
}

// Filtros
export interface PlanoAcaoFilters {
  status?: AcaoStatus[];
  prioridade?: AcaoGutPrioridade[];
  origem_modulo?: OrigemModulo[];
  responsavel_id?: string;
  prazo_inicio?: string;
  prazo_fim?: string;
  busca?: string;
}
