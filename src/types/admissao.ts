export type AdmissaoStatus = 
  | 'rascunho'
  | 'aguardando_documentos'
  | 'em_analise'
  | 'aprovado'
  | 'reprovado'
  | 'concluido'
  | 'desligado';

export type DocumentoStatus = 'pendente' | 'enviado' | 'aprovado' | 'rejeitado';

export interface DocumentoAdmissao {
  id: string;
  nome: string;
  tipo: string;
  obrigatorio: boolean;
  status: DocumentoStatus;
  arquivo?: File;
  arquivo_url?: string;
  arquivo_nome?: string;
  urlPreview?: string;
  dataEnvio?: Date;
  observacao?: string;
}

export interface DadosPessoais {
  nomeCompleto: string;
  cpf: string;
  rg: string;
  dataNascimento: string;
  estadoCivil: string;
  genero: string;
  nacionalidade: string;
  naturalidade: string;
  nomeMae: string;
  nomePai: string;
}

export interface DadosContato {
  email: string;
  telefone: string;
  celular: string;
  endereco: string;
  numero: string;
  complemento: string;
  bairro: string;
  cidade: string;
  estado: string;
  cep: string;
}

export interface DadosProfissionais {
  cargo: string;
  cargo_id?: string | null;
  departamento: string;
  filial: string;
  dataAdmissao: string;
  tipoContrato: string;
  jornadaTrabalho: string;
  salario: string;
  gestorImediato: string;
  centroCusto: string;
  cbo?: string;
}

export interface DadosBancarios {
  banco: string;
  agencia: string;
  conta: string;
  tipoConta: string;
  chavePix: string;
}

export interface HistoricoAprovacao {
  id: string;
  etapa: string;
  status: 'pendente' | 'aprovado' | 'rejeitado';
  responsavel: string;
  dataAcao?: Date;
  observacao?: string;
}

export interface Admissao {
  id: string;
  dadosPessoais: DadosPessoais;
  dadosContato: DadosContato;
  dadosProfissionais: DadosProfissionais;
  dadosBancarios: DadosBancarios;
  documentos: DocumentoAdmissao[];
  status: AdmissaoStatus;
  historicoAprovacao: HistoricoAprovacao[];
  dataCriacao: Date;
  dataAtualizacao: Date;
  criadoPor: string;
  fotoUrl?: string;
  onboardingToken?: string | null;
  onboarding_status?: string;
}

export const DOCUMENTOS_OBRIGATORIOS: Omit<DocumentoAdmissao, 'id' | 'status'>[] = [
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
