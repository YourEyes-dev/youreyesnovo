// Types for Atestados module

export type AfastamentoTipo = 'ocupacional' | 'licencas' | 'atestados';

export type AfastamentoSubtipoOcupacional = 
  | 'admissional'
  | 'periodico'
  | 'retorno_trabalho'
  | 'mudanca_risco'
  | 'demissional';

export type AfastamentoSubtipoLicencas = 
  | 'casamento'
  | 'falecimento'
  | 'militar'
  | 'sindical'
  | 'outras_licencas';

export type AfastamentoSubtipoAtestados = 
  | 'maternidade'
  | 'paternidade'
  | 'acidente_trabalho'
  | 'doenca_trabalho'
  | 'acidente_nao_trabalho'
  | 'doenca_nao_trabalho'
  | 'prorrogacao'
  | 'aborto_nao_criminoso'
  | 'aposentadoria_invalidez'
  | 'suspensao_contrato'
  | 'outros_motivos';

// Novo conceito de UI: tipo de lançamento (Tarefa 1)
export type LancamentoTipo =
  | 'atestado_medico'
  | 'acidente_trabalho'
  | 'afastamento_inss'
  | 'licenca_legal'
  | 'licenca_nr'
  | 'declaracao_comparecimento';

// Enum afastamento_tipo_principal (já existe no banco)
export type AfastamentoTipoPrincipal =
  | 'doenca_comum'
  | 'doenca_ocupacional'
  | 'acidente_tipico'
  | 'acidente_trajeto'
  | 'atestado_odontologico'
  | 'comparecimento'
  | 'licenca_maternidade'
  | 'licenca_paternidade'
  | 'aborto_nao_criminoso'
  | 'beneficio_b31'
  | 'beneficio_b91'
  | 'reabilitacao_b92'
  | 'auxilio_acidente_b94'
  | 'licenca_nao_remunerada'
  | 'suspensao_disciplinar'
  | 'falta_justificada_legal'
  | 'mandato_sindical'
  | 'determinacao_judicial_legal'
  | 'licenca_adocao'
  | 'outro_cct_act_politica_interna';

// Manter compatibilidade com interfaces antigas enquanto refatoramos
export type AtestadoTipo = AfastamentoTipo;
export type AtestadoSubtipoAssistencial = AfastamentoSubtipoLicencas | AfastamentoSubtipoAtestados;
export type AtestadoSubtipoOcupacional = AfastamentoSubtipoOcupacional;

export type GrupoClinico = 
  | 'mental'
  | 'osteomuscular'
  | 'respiratorio'
  | 'cardiovascular'
  | 'digestivo'
  | 'dermatologico'
  | 'neurologico'
  | 'infeccioso'
  | 'oncologico'
  | 'endocrino'
  | 'outro';

export type NexoTrabalho = 'nao' | 'em_analise' | 'sim';

export type AptidaoOcupacional = 
  | 'apto'
  | 'apto_com_restricoes'
  | 'inapto_temporario'
  | 'inapto';

export type BeneficioINSSEspecie = 'b31' | 'b91';

export type AfastamentoStatus = 'ativo' | 'encerrado' | 'beneficio_inss';

export type EventoSaudeStatus = 'aberto' | 'em_acompanhamento' | 'encerrado';

// Main interfaces
export interface Atestado {
  id: string;
  tenant_id: string;
  colaborador_id: string | null;
  colaborador_nome: string;
  colaborador_cpf: string | null;
  colaborador_cargo: string | null;
  colaborador_departamento: string | null;
  
  tipo: AtestadoTipo;
  subtipo_assistencial: AtestadoSubtipoAssistencial | null;
  subtipo_ocupacional: AtestadoSubtipoOcupacional | null;
  
  data_emissao: string;
  profissional_nome: string;
  profissional_registro: string;
  profissional_tipo: string | null;
  profissional_uf: string | null;
  profissional_rqe: string | null;
  profissional_telefone: string | null;
  profissional_email: string | null;
  profissional_endereco: string | null;
  
  data_inicio_afastamento: string | null;
  data_fim_afastamento: string | null;
  dias_afastamento: number | null;
  horas_afastamento: number | null;
  unidade_afastamento: string;
  
  contem_cid: boolean;
  cid_codigo: string | null;
  cid_autorizado: boolean | null;
  grupo_clinico: GrupoClinico | null;
  nexo_trabalho: NexoTrabalho;
  
  aptidao: AptidaoOcupacional | null;
  restricoes: string | null;
  observacoes_ocupacionais: string | null;
  
  arquivo_url: string | null;
  arquivo_nome: string | null;
  arquivo_tamanho: number | null;
  /** Bucket do arquivo: 'atestados' (padrão) ou 'ponto-ajustes-anexos' (ausência aprovada pelo ponto). */
  arquivo_bucket?: string | null;
  /** Pedido de ajuste de ponto cuja aprovação lançou este atestado. */
  ajuste_id?: string | null;
  
  evento_saude_id: string | null;
  afastamento_id: string | null;
  
  observacoes: string | null;
  criado_por: string | null;
  criado_por_nome: string | null;
  created_at: string;
  updated_at: string;
}

export interface Afastamento {
  id: string;
  tenant_id: string;
  colaborador_id: string | null;
  colaborador_nome: string;
  colaborador_cpf: string | null;
  
  data_inicio: string;
  data_fim: string | null;
  dias_totais: number;
  
  status: AfastamentoStatus;
  motivo_principal: GrupoClinico | null;
  nexo_trabalho: NexoTrabalho;
  
  alerta_15_dias: boolean;
  alerta_30_dias: boolean;
  aso_retorno_pendente: boolean;
  aso_retorno_id: string | null;
  
  evento_saude_id: string | null;
  beneficio_inss_id: string | null;
  
  observacoes: string | null;
  created_at: string;
  updated_at: string;
}

export interface EventoSaude {
  id: string;
  tenant_id: string;
  colaborador_id: string | null;
  colaborador_nome: string;
  colaborador_cpf: string | null;
  
  codigo: string;
  titulo: string;
  descricao: string | null;
  
  grupo_clinico_principal: GrupoClinico | null;
  nexo_trabalho: NexoTrabalho;
  status: EventoSaudeStatus;
  
  data_inicio: string;
  data_fim: string | null;
  
  total_atestados: number;
  total_dias_afastamento: number;
  
  observacoes: string | null;
  criado_por: string | null;
  criado_por_nome: string | null;
  created_at: string;
  updated_at: string;
}

export interface BeneficioINSS {
  id: string;
  tenant_id: string;
  colaborador_id: string | null;
  colaborador_nome: string;
  colaborador_cpf: string | null;
  
  numero_beneficio: string | null;
  especie: BeneficioINSSEspecie;
  data_inicio: string;
  data_fim: string | null;
  data_alta: string | null;
  
  gera_estabilidade: boolean;
  data_fim_estabilidade: string | null;
  
  evento_saude_id: string | null;
  afastamento_id: string | null;
  
  arquivo_url: string | null;
  arquivo_nome: string | null;
  
  observacoes: string | null;
  criado_por: string | null;
  criado_por_nome: string | null;
  created_at: string;
  updated_at: string;
}

export interface AlertaSaude {
  id: string;
  tenant_id: string;
  
  tipo: string;
  referencia_tipo: string;
  referencia_id: string;
  
  colaborador_id: string | null;
  colaborador_nome: string;
  
  titulo: string;
  descricao: string | null;
  prioridade: 'baixa' | 'media' | 'alta' | 'critica';
  
  lido: boolean;
  resolvido: boolean;
  resolvido_por: string | null;
  resolvido_em: string | null;
  
  acao_gerada_id: string | null;
  
  created_at: string;
}

// Form data types
export interface AtestadoFormData {
  colaborador_nome: string;
  colaborador_cpf?: string;
  colaborador_cargo?: string;
  colaborador_departamento?: string;
  
  tipo: AtestadoTipo;
  subtipo_assistencial?: AtestadoSubtipoAssistencial;
  subtipo_ocupacional?: AtestadoSubtipoOcupacional;
  /** Declaração de comparecimento: decisão de abonar (quando a regra da empresa
   *  é "configurável"). Ignorado quando a regra é sim/não. */
  abona?: boolean | null;
  
  data_emissao: string;
  profissional_nome: string;
  profissional_registro: string;
  profissional_tipo?: string;
  profissional_uf?: string;
  profissional_rqe?: string;
  profissional_telefone?: string;
  profissional_email?: string;
  profissional_endereco?: string;
  
  data_inicio_afastamento?: string;
  data_fim_afastamento?: string;
  dias_afastamento?: number;
  horas_afastamento?: number;
  unidade_afastamento?: string;
  
  contem_cid?: boolean;
  cid_codigo?: string;
  cid_autorizado?: boolean;
  grupo_clinico?: GrupoClinico;
  nexo_trabalho?: NexoTrabalho;
  
  aptidao?: AptidaoOcupacional;
  restricoes?: string;
  observacoes_ocupacionais?: string;
  
  observacoes?: string;
  evento_saude_id?: string;

  // Tarefa 1: tipo de lançamento e mapeamento para o motor de inteligência
  lancamento_tipo?: LancamentoTipo;
  tipo_principal_new?: AfastamentoTipoPrincipal;

  // Tarefa 4: dados do acidente de trabalho (CAT)
  numero_cat?: string;
  data_acidente?: string;
  hora_acidente?: string;
  local_acidente?: string;
  parte_corpo?: string;
  agente_causador?: string;
  descricao_acidente?: string;

  // Tarefa 2: benefício INSS no mesmo lançamento (>15 dias ou Afastamento INSS)
  beneficio_especie?: BeneficioINSSEspecie;
  beneficio_numero?: string;
  beneficio_data_inicio?: string;
  beneficio_data_alta?: string;
}

// Extracted data from AI
export interface AtestadoExtractedData {
  colaborador_nome?: string;
  colaborador_cpf?: string;
  profissional_nome?: string;
  profissional_registro?: string;
  profissional_uf?: string;
  profissional_rqe?: string;
  profissional_telefone?: string;
  profissional_email?: string;
  profissional_endereco?: string;
  data_emissao?: string;
  dias_afastamento?: number;
  horas_afastamento?: number;
  unidade_afastamento?: 'dias' | 'horas';
  data_inicio_afastamento?: string;
  data_fim_afastamento?: string;
  contem_cid?: boolean;
  cid_codigo?: string;
  cid_autorizado?: boolean;
  observacoes?: string;
}

// Labels
export const AFASTAMENTO_TIPO_LABELS: Record<AfastamentoTipo, string> = {
  ocupacional: 'Ocupacional (ASO)',
  licencas: 'Licenças',
  atestados: 'Atestados Médicos',
};

// Tarefa 1: labels e mapeamentos do tipo de lançamento
export const LANCAMENTO_TIPO_LABELS: Record<LancamentoTipo, string> = {
  atestado_medico: 'Atestado Médico',
  acidente_trabalho: 'Acidente de Trabalho',
  afastamento_inss: 'Afastamento INSS',
  licenca_legal: 'Licença Legal',
  licenca_nr: 'Licença Não Remunerada',
  declaracao_comparecimento: 'Declaração de comparecimento',
};

export const LANCAMENTO_TIPO_PRINCIPAL_OPCOES: Record<
  LancamentoTipo,
  { value: AfastamentoTipoPrincipal; label: string }[]
> = {
  atestado_medico: [
    { value: 'doenca_comum', label: 'Doença comum' },
    { value: 'atestado_odontologico', label: 'Odontológico' },
  ],
  acidente_trabalho: [
    { value: 'acidente_tipico', label: 'Acidente típico' },
    { value: 'acidente_trajeto', label: 'Acidente de trajeto' },
    { value: 'doenca_ocupacional', label: 'Doença ocupacional' },
  ],
  afastamento_inss: [
    { value: 'beneficio_b31', label: 'B31 - Auxílio-doença' },
    { value: 'beneficio_b91', label: 'B91 - Acidentário' },
    { value: 'reabilitacao_b92', label: 'B92 - Reabilitação' },
    { value: 'auxilio_acidente_b94', label: 'B94 - Auxílio-acidente' },
  ],
  licenca_legal: [
    { value: 'licenca_maternidade', label: 'Maternidade' },
    { value: 'licenca_paternidade', label: 'Paternidade' },
    { value: 'licenca_adocao', label: 'Adoção' },
    { value: 'falta_justificada_legal', label: 'Falta justificada legal' },
    { value: 'mandato_sindical', label: 'Mandato sindical' },
    { value: 'determinacao_judicial_legal', label: 'Determinação judicial' },
  ],
  licenca_nr: [
    { value: 'licenca_nao_remunerada', label: 'Licença não remunerada' },
  ],
  declaracao_comparecimento: [
    { value: 'comparecimento', label: 'Comparecimento a consulta/exame' },
  ],
};

export const LANCAMENTO_TIPO_TO_ATESTADO_TIPO: Record<LancamentoTipo, AtestadoTipo> = {
  atestado_medico: 'atestados',
  acidente_trabalho: 'atestados',
  afastamento_inss: 'atestados',
  licenca_legal: 'licencas',
  licenca_nr: 'licencas',
  declaracao_comparecimento: 'atestados',
};

// Mapeia o tipo_principal_new (motor) de volta para um subtipo_assistencial
// (coluna em atestados, enum atestado_subtipo_assistencial) — mantém um rótulo
// legível nas listagens que ainda usam subtipo_assistencial. Best-effort.
export const TIPO_PRINCIPAL_TO_SUBTIPO_ASSISTENCIAL: Record<AfastamentoTipoPrincipal, string> = {
  doenca_comum: 'doenca_nao_trabalho',
  doenca_ocupacional: 'doenca_trabalho',
  acidente_tipico: 'acidente_trabalho',
  acidente_trajeto: 'acidente_trabalho',
  atestado_odontologico: 'odontologico',
  comparecimento: 'comparecimento',
  licenca_maternidade: 'maternidade',
  licenca_paternidade: 'paternidade',
  aborto_nao_criminoso: 'aborto_nao_criminoso',
  beneficio_b31: 'doenca_nao_trabalho',
  beneficio_b91: 'acidente_trabalho',
  reabilitacao_b92: 'outros_motivos',
  auxilio_acidente_b94: 'outros_motivos',
  licenca_nao_remunerada: 'outras_licencas',
  suspensao_disciplinar: 'outros_motivos',
  falta_justificada_legal: 'outras_licencas',
  mandato_sindical: 'sindical',
  determinacao_judicial_legal: 'outras_licencas',
  licenca_adocao: 'adocao',
  outro_cct_act_politica_interna: 'outros_motivos',
};

export const SUBTIPO_OCUPACIONAL_LABELS: Record<string, string> = {
  admissional: 'Admissional',
  periodico: 'Periódico',
  retorno_trabalho: 'Retorno ao trabalho',
  mudanca_risco: 'Mudança de risco ocupacional',
  demissional: 'Demissional',
};

export const SUBTIPO_LICENCAS_LABELS: Record<AfastamentoSubtipoLicencas, string> = {
  casamento: 'Licença Casamento',
  falecimento: 'Licença Falecimento',
  militar: 'Licença Serviço Militar',
  sindical: 'Licença Mandato Sindical',
  outras_licencas: 'Outras Licenças',
};

export const SUBTIPO_ATESTADOS_LABELS: Record<string, string> = {
  comparecimento: 'Declaração de comparecimento',
  maternidade: 'Licença-Maternidade',
  paternidade: 'Licença-Paternidade',
  adocao: 'Licença-Adoção',
  acidente_trabalho: 'Acidente / Doença do trabalho',
  acidente_nao_trabalho: 'Acidente / Doença não relacionada ao trabalho',
  prorrogacao: 'Prorrogação de afastamento / licença',
  aborto_nao_criminoso: 'Aborto não criminoso',
  aposentadoria_invalidez: 'Aposentadoria por invalidez',
  suspensao_contrato: 'Suspensão Contrato de Trabalho (476-A)',
  outros_motivos: 'Outros motivos de afastamento',
};

// Aliases para compatibilidade
export const ATESTADO_TIPO_LABELS = AFASTAMENTO_TIPO_LABELS;
export const SUBTIPO_ASSISTENCIAL_LABELS = { ...SUBTIPO_LICENCAS_LABELS, ...SUBTIPO_ATESTADOS_LABELS };

export const GRUPO_CLINICO_LABELS: Record<GrupoClinico, string> = {
  mental: 'Saúde Mental',
  osteomuscular: 'Osteomuscular',
  respiratorio: 'Respiratório',
  cardiovascular: 'Cardiovascular',
  digestivo: 'Digestivo',
  dermatologico: 'Dermatológico',
  neurologico: 'Neurológico',
  infeccioso: 'Infeccioso',
  oncologico: 'Oncológico',
  endocrino: 'Endócrino',
  outro: 'Outro',
};

export const NEXO_TRABALHO_LABELS: Record<NexoTrabalho, string> = {
  nao: 'Não',
  em_analise: 'Em Análise',
  sim: 'Sim',
};

export const APTIDAO_LABELS: Record<AptidaoOcupacional, string> = {
  apto: 'Apto',
  apto_com_restricoes: 'Apto com Restrições',
  inapto_temporario: 'Inapto Temporário',
  inapto: 'Inapto',
};

export const BENEFICIO_ESPECIE_LABELS: Record<BeneficioINSSEspecie, string> = {
  b31: 'B31 - Auxílio Doença Comum',
  b91: 'B91 - Auxílio Doença Acidentário',
};

export const AFASTAMENTO_STATUS_LABELS: Record<AfastamentoStatus, string> = {
  ativo: 'Ativo',
  encerrado: 'Encerrado',
  beneficio_inss: 'Benefício INSS',
};

export const EVENTO_SAUDE_STATUS_LABELS: Record<EventoSaudeStatus, string> = {
  aberto: 'Aberto',
  em_acompanhamento: 'Em Acompanhamento',
  encerrado: 'Encerrado',
};

// Colors
export const GRUPO_CLINICO_COLORS: Record<GrupoClinico, string> = {
  mental: 'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200',
  osteomuscular: 'bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200',
  respiratorio: 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200',
  cardiovascular: 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200',
  digestivo: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200',
  dermatologico: 'bg-pink-100 text-pink-800 dark:bg-pink-900 dark:text-pink-200',
  neurologico: 'bg-indigo-100 text-indigo-800 dark:bg-indigo-900 dark:text-indigo-200',
  infeccioso: 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200',
  oncologico: 'bg-gray-100 text-gray-800 dark:bg-gray-800 dark:text-gray-200',
  endocrino: 'bg-teal-100 text-teal-800 dark:bg-teal-900 dark:text-teal-200',
  outro: 'bg-slate-100 text-slate-800 dark:bg-slate-800 dark:text-slate-200',
};

export const APTIDAO_COLORS: Record<AptidaoOcupacional, string> = {
  apto: 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200',
  apto_com_restricoes: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200',
  inapto_temporario: 'bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200',
  inapto: 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200',
};
