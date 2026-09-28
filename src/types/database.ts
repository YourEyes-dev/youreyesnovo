// Database types derived from Supabase schema
import { Database } from '@/integrations/supabase/types';

// Table row types
export type Tenant = Database['public']['Tables']['tenants']['Row'];
export type TenantInsert = Database['public']['Tables']['tenants']['Insert'];
export type TenantUpdate = Database['public']['Tables']['tenants']['Update'];

export type Profile = Database['public']['Tables']['profiles']['Row'];
export type ProfileInsert = Database['public']['Tables']['profiles']['Insert'];
export type ProfileUpdate = Database['public']['Tables']['profiles']['Update'];

export type UserRole = Database['public']['Tables']['user_roles']['Row'];
export type UserRoleInsert = Database['public']['Tables']['user_roles']['Insert'];

export type AdmissaoRow = Database['public']['Tables']['admissoes']['Row'];
export type AdmissaoInsert = Database['public']['Tables']['admissoes']['Insert'];
export type AdmissaoUpdate = Database['public']['Tables']['admissoes']['Update'];

export type AdmissaoDocumentoRow = Database['public']['Tables']['admissao_documentos']['Row'];
export type AdmissaoDocumentoInsert = Database['public']['Tables']['admissao_documentos']['Insert'];
export type AdmissaoDocumentoUpdate = Database['public']['Tables']['admissao_documentos']['Update'];

export type AdmissaoWorkflowRow = Database['public']['Tables']['admissao_workflow']['Row'];
export type AdmissaoWorkflowInsert = Database['public']['Tables']['admissao_workflow']['Insert'];
export type AdmissaoWorkflowUpdate = Database['public']['Tables']['admissao_workflow']['Update'];

export type AdmissaoHistoricoRow = Database['public']['Tables']['admissao_historico']['Row'];
export type AdmissaoHistoricoInsert = Database['public']['Tables']['admissao_historico']['Insert'];

// Enum types
export type AdmissaoStatus = Database['public']['Enums']['admissao_status'];
export type DocumentoStatus = Database['public']['Enums']['documento_status'];
export type WorkflowStatus = Database['public']['Enums']['workflow_status'];
export type AppRole = Database['public']['Enums']['app_role'];
export type TenantPlan = Database['public']['Enums']['tenant_plan'];

// Extended types with relations
export interface AdmissaoCompleta extends AdmissaoRow {
  documentos: AdmissaoDocumentoRow[];
  workflow: AdmissaoWorkflowRow[];
  historico: AdmissaoHistoricoRow[];
}

// Form data types for creating/updating admissões
export interface AdmissaoFormData {
  // Dados Pessoais
  nome_completo: string;
  cpf: string;
  rg?: string;
  data_nascimento?: string;
  estado_civil?: string;
  genero?: string;
  nacionalidade?: string;
  naturalidade?: string;
  nome_mae?: string;
  nome_pai?: string;
  
  // Dados de Contato
  email: string;
  telefone?: string;
  celular?: string;
  endereco?: string;
  numero?: string;
  complemento?: string;
  bairro?: string;
  cidade?: string;
  estado?: string;
  cep?: string;
  
  // Dados Profissionais
  cargo: string;
  cargo_id?: string | null;
  departamento?: string;
  filial?: string;
  data_admissao?: string;
  tipo_contrato?: string;
  jornada_trabalho?: string;
  salario?: number;
  gestor_imediato?: string;
  centro_custo?: string;
  cbo?: string;

  // Dados Bancários
  banco?: string;
  agencia?: string;
  conta?: string;
  tipo_conta?: string;
  chave_pix?: string;

  // Exame Admissional
  exame_admissional_data?: string;
  exame_admissional_validade?: string;
  exame_admissional_resultado?: string;
  exame_admissional_clinica?: string;
  exame_admissional_medico?: string;
  exame_admissional_crm?: string;
  exame_admissional_observacoes?: string;
  foto_url?: string;
  onboarding_status?: string;
}

// Status labels and colors
export const STATUS_LABELS: Record<AdmissaoStatus, string> = {
  rascunho: 'Rascunho',
  aguardando_documentos: 'Aguardando Documentos',
  em_analise: 'Em Análise',
  aprovado: 'Aprovado',
  reprovado: 'Reprovado',
  concluido: 'Concluído',
  desligado: 'Desligado',
};

export const STATUS_COLORS: Record<AdmissaoStatus, string> = {
  rascunho: 'bg-muted text-muted-foreground',
  aguardando_documentos: 'bg-warning/10 text-warning',
  em_analise: 'bg-info/10 text-info',
  aprovado: 'bg-success/10 text-success',
  reprovado: 'bg-destructive/10 text-destructive',
  concluido: 'bg-primary/10 text-primary',
  desligado: 'bg-destructive/20 text-destructive',
};

export const DOCUMENTO_STATUS_LABELS: Record<DocumentoStatus, string> = {
  pendente: 'Pendente',
  enviado: 'Enviado',
  aprovado: 'Aprovado',
  rejeitado: 'Rejeitado',
};

export const WORKFLOW_STATUS_LABELS: Record<WorkflowStatus, string> = {
  pendente: 'Pendente',
  aprovado: 'Aprovado',
  rejeitado: 'Rejeitado',
};

// Default workflow steps
export const DEFAULT_WORKFLOW_STEPS = [
  { etapa: 'Cadastro Inicial', ordem: 1 },
  { etapa: 'Análise Documental', ordem: 2 },
  { etapa: 'Aprovação RH', ordem: 3 },
  { etapa: 'Aprovação Final', ordem: 4 },
];

// Required documents list
export const DOCUMENTOS_OBRIGATORIOS = [
  { nome: 'RG', tipo: 'identidade', obrigatorio: true },
  { nome: 'CPF', tipo: 'identidade', obrigatorio: true },
  { nome: 'Comprovante de Residência', tipo: 'endereco', obrigatorio: true },
  { nome: 'Título de Eleitor', tipo: 'identidade', obrigatorio: true },
  { nome: 'Carteira de Trabalho (CTPS)', tipo: 'trabalho', obrigatorio: true },
  { nome: 'Carteira de Reservista', tipo: 'identidade', obrigatorio: false },
  { nome: 'Certidão de Nascimento/Casamento', tipo: 'civil', obrigatorio: true },
  { nome: 'Foto 3x4', tipo: 'foto', obrigatorio: true },
  { nome: 'Comprovante de Escolaridade', tipo: 'formacao', obrigatorio: true },
  { nome: 'Exame Admissional', tipo: 'saude', obrigatorio: true },
  { nome: 'Certificado de Cursos', tipo: 'formacao', obrigatorio: false },
  { nome: 'Certidão de Nascimento dos Filhos', tipo: 'dependentes', obrigatorio: false },
];
