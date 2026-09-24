import { z } from 'zod';
import { cleanCpf, validateCpf } from '@/lib/cpf';
import { User, MapPin, Briefcase, CreditCard, FileText, Stethoscope } from 'lucide-react';

export const STEPS = [
  { id: 1, title: 'Dados Pessoais', description: 'Informações básicas', icon: User },
  { id: 2, title: 'Contato', description: 'Endereço e telefone', icon: MapPin },
  { id: 3, title: 'Profissional', description: 'Cargo e salário', icon: Briefcase },
  { id: 4, title: 'Bancários', description: 'Dados bancários', icon: CreditCard },
  { id: 5, title: 'Exame Admissional', description: 'Dados do exame médico', icon: Stethoscope },
  { id: 6, title: 'Documentos', description: 'Upload de arquivos', icon: FileText },
];

export const dadosPessoaisSchema = z.object({
  nomeCompleto: z.string().min(3, 'Nome deve ter pelo menos 3 caracteres'),
  cpf: z.string()
    .min(11, 'CPF deve ter 11 dígitos')
    .refine((val) => {
      const cleaned = cleanCpf(val);
      return cleaned.length === 11;
    }, 'CPF deve ter 11 dígitos')
    .refine((val) => validateCpf(val), 'CPF inválido - verifique os dígitos'),
  rg: z.string().min(5, 'RG inválido'),
  dataNascimento: z.string().min(1, 'Data de nascimento obrigatória'),
  estadoCivil: z.string().min(1, 'Estado civil obrigatório'),
  genero: z.string().min(1, 'Gênero obrigatório'),
  nacionalidade: z.string().min(1, 'Nacionalidade obrigatória'),
  naturalidade: z.string().min(1, 'Naturalidade obrigatória'),
  nomeMae: z.string().min(3, 'Nome da mãe obrigatório'),
  nomePai: z.string().optional(),
});

export const dadosContatoSchema = z.object({
  email: z.string().email('E-mail inválido'),
  telefone: z.string().optional(),
  celular: z.string().min(10, 'Celular inválido'),
  endereco: z.string().min(3, 'Endereço obrigatório'),
  numero: z.string().min(1, 'Número obrigatório'),
  complemento: z.string().optional(),
  bairro: z.string().min(2, 'Bairro obrigatório'),
  cidade: z.string().min(2, 'Cidade obrigatória'),
  estado: z.string().min(2, 'Estado obrigatório'),
  cep: z.string().min(8, 'CEP inválido').max(9, 'CEP inválido'),
});

export const dadosProfissionaisSchema = z.object({
  cargo: z.string().min(2, 'Cargo obrigatório'),
  departamento: z.string().min(2, 'Departamento obrigatório'),
  filial: z.string().optional(),
  dataAdmissao: z.string().min(1, 'Data de admissão obrigatória'),
  tipoContrato: z.string().min(1, 'Tipo de contrato obrigatório'),
  jornadaTrabalho: z.string().min(1, 'Jornada de trabalho obrigatória'),
  salario: z.string().min(1, 'Salário obrigatório'),
  gestorImediato: z.string().optional(),
  centroCusto: z.string().optional(),
  cbo: z.string().optional(),
});

export const dadosBancariosSchema = z.object({
  // Dados bancários deixaram de ser obrigatórios na admissão (podem ser
  // preenchidos depois). Mantidos como texto opcional — aceitam vazio.
  banco: z.string().optional(),
  agencia: z.string().optional(),
  conta: z.string().optional(),
  tipoConta: z.string().optional(),
  chavePix: z.string().optional(),
});

export const exameAdmissionalSchema = z.object({
  dataExame: z.string().optional(),
  dataValidade: z.string().optional(),
  resultado: z.string().optional(),
  clinica: z.string().optional(),
  medico: z.string().optional(),
  crm: z.string().optional(),
  observacoes: z.string().optional(),
});

export interface DadosExameAdmissional {
  dataExame: string;
  dataValidade: string;
  resultado: string;
  clinica: string;
  medico: string;
  crm: string;
  observacoes: string;
}

export interface UsuarioEncontrado {
  id: string;
  nome_completo: string;
  email_principal: string;
  cpf?: string;
  telefone_principal?: string;
  cargo_funcao?: string;
  data_nascimento?: string;
}

export type AutoSaveStatus = 'idle' | 'saving' | 'saved' | 'error';
