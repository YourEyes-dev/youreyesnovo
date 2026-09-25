// Tipos do Módulo Cadastro de Empresa

export interface EmpresaCadastro {
  id: string;
  tenant_id: string;
  
  // Dados Básicos
  razao_social: string | null;
  nome_fantasia: string | null;
  tipo_pessoa: 'pf' | 'pj';
  cnpj: string | null;
  cpf: string | null;
  cei: string | null;
  caepf: string | null;
  inscricao_estadual: string | null;
  inscricao_municipal: string | null;
  endereco: string | null;
  numero: string | null;
  complemento: string | null;
  bairro: string | null;
  cidade: string | null;
  estado: string | null;
  cep: string | null;
  telefone: string | null;
  email: string | null;
  website: string | null;
  
  // CNAE e Grau de Risco
  cnae_principal: string | null;
  cnae_descricao: string | null;
  cnaes_secundarios: CnaeSecundario[];
  grau_risco: number | null;
  grau_risco_ajustado: number | null;
  grau_risco_justificativa: string | null;
  
  // SESMT
  sesmt_obrigatorio: boolean;
  sesmt_situacao: 'proprio' | 'terceirizado' | 'inexistente';
  sesmt_profissionais: SesmtProfissional[];
  
  // CIPA
  cipa_obrigatoria: boolean;
  cipa_situacao: 'nao_constituida' | 'em_implantacao' | 'ativa';
  cipa_data_mandato_inicio: string | null;
  cipa_data_mandato_fim: string | null;
  cipa_membros: CipaMembro[];
  
  // PCD
  pcd_obrigatoria: boolean;
  pcd_quantidade_exigida: number;
  pcd_quantidade_atual: number;
  pcd_percentual_exigido: number | null;
  
  // Jovem Aprendiz
  aprendiz_obrigatorio: boolean;
  aprendiz_quantidade_minima: number;
  aprendiz_quantidade_maxima: number;
  aprendiz_quantidade_atual: number;
  
  // FAP
  fap_atual: number | null;
  fap_historico: FapHistorico[];
  fap_classificacao: string | null;
  
  // TAC
  tac_possui: boolean;
  tac_detalhes: TacDetalhe[];
  
  // Jornada
  jornada_padrao: string | null;
  turnos: Turno[];
  possui_terceiro_turno: boolean;
  possui_escalas_especiais: boolean;
  // Controle de jornada (Ponto). Desligado, a empresa NÃO gera falta por dia
  // sem marcação e some do seletor do módulo de Ponto. CLT art. 74, §2º:
  // obrigatório acima de 20 trabalhadores no estabelecimento, facultativo
  // abaixo. A edição só é liberada quando o plano do cliente inclui o módulo
  // de Ponto (feature mod.ponto).
  usa_controle_ponto: boolean;
  // Sinalização automática (rotina do banco) de que o estabelecimento passou
  // de 20 trabalhadores e é OBRIGADO ao controle de jornada. Somente leitura.
  controle_ponto_obrigatorio: boolean;
  
  // Condições Especiais
  trabalho_altura: boolean;
  espaco_confinado: boolean;
  insalubridade: boolean;
  periculosidade: boolean;
  aposentadoria_especial: boolean;
  condicoes_especiais_detalhes: Record<string, string>;
  
  // Hierarquia e Grupo
  grupo_economico_id: string | null;
  tipo_unidade: 'matriz' | 'filial';
  matriz_id: string | null;
  ai_context: string | null;
  logo_url: string | null;

  total_colaboradores: number;
  ativo: boolean;
  atualizado_por: string | null;
  created_at: string;
  updated_at: string;
}

export interface CnaeSecundario {
  codigo: string;
  descricao: string;
}

export interface SesmtProfissional {
  tipo: string;
  nome: string;
  registro: string;
}

export interface CipaMembro {
  nome: string;
  funcao: string;
  tipo: 'titular' | 'suplente';
}

export interface FapHistorico {
  ano: number;
  valor: number;
}

export interface TacDetalhe {
  numero: string;
  orgao_emissor: string;
  data_assinatura?: string;
  obrigacoes: string;
  prazo: string;
  penalidades: string;
  status: string;
  arquivado?: boolean;
  arquivado_em?: string;
  motivo_arquivamento?: string;
}

export interface Turno {
  nome: string;
  horario_inicio: string;
  horario_fim: string;
}

export interface EmpresaObrigacao {
  id: string;
  tenant_id: string;
  empresa_id: string | null;
  categoria: string;
  subcategoria: string | null;
  titulo: string;
  descricao: string | null;
  base_legal: string | null;
  status: 'pendente' | 'conforme' | 'nao_conforme' | 'em_adequacao' | 'nao_aplicavel';
  criticidade: 'baixa' | 'media' | 'alta' | 'critica';
  prazo_sugerido: string | null;
  responsavel_sugerido: string | null;
  acao_gerada_id: string | null;
  origem: string;
  origem_campo: string | null;
  ativo: boolean;
  created_at: string;
  updated_at: string;
}

// Obrigações automáticas por bloco do cadastro
export interface ObrigacaoTemplate {
  titulo: string;
  descricao: string;
  categoria: string;
  subcategoria: string;
  base_legal: string;
  criticidade: 'baixa' | 'media' | 'alta' | 'critica';
  origem_campo: string;
  condicao: (cadastro: EmpresaCadastro) => boolean;
}

export const OBRIGACOES_TEMPLATES: ObrigacaoTemplate[] = [
  // CIPA
  {
    titulo: 'Constituir CIPA',
    descricao: 'A empresa é obrigada a constituir CIPA conforme NR-05 e não possui CIPA ativa.',
    categoria: 'sst',
    subcategoria: 'cipa',
    base_legal: 'NR-05',
    criticidade: 'alta',
    origem_campo: 'cipa_situacao',
    condicao: (c) => c.cipa_obrigatoria && c.cipa_situacao === 'nao_constituida',
  },
  {
    titulo: 'Realizar eleição da CIPA',
    descricao: 'CIPA em implantação requer eleição formal dos membros.',
    categoria: 'sst',
    subcategoria: 'cipa',
    base_legal: 'NR-05',
    criticidade: 'media',
    origem_campo: 'cipa_situacao',
    condicao: (c) => c.cipa_obrigatoria && c.cipa_situacao === 'em_implantacao',
  },
  {
    titulo: 'Renovar mandato da CIPA',
    descricao: 'O mandato da CIPA está próximo do vencimento ou já vencido.',
    categoria: 'sst',
    subcategoria: 'cipa',
    base_legal: 'NR-05',
    criticidade: 'alta',
    origem_campo: 'cipa_data_mandato_fim',
    condicao: (c) => {
      if (!c.cipa_data_mandato_fim) return false;
      const fim = new Date(c.cipa_data_mandato_fim);
      const hoje = new Date();
      const diff = (fim.getTime() - hoje.getTime()) / (1000 * 60 * 60 * 24);
      return diff < 90;
    },
  },
  // SESMT
  {
    titulo: 'Contratar/Adequar SESMT',
    descricao: 'SESMT é obrigatório mas não está constituído.',
    categoria: 'sst',
    subcategoria: 'sesmt',
    base_legal: 'NR-04',
    criticidade: 'critica',
    origem_campo: 'sesmt_situacao',
    condicao: (c) => c.sesmt_obrigatorio && c.sesmt_situacao === 'inexistente',
  },
  // PCD
  {
    titulo: 'Plano de adequação da cota PCD',
    descricao: 'A empresa está em déficit no cumprimento da cota de PCD.',
    categoria: 'legal',
    subcategoria: 'pcd',
    base_legal: 'Lei 8.213/91, Art. 93',
    criticidade: 'alta',
    origem_campo: 'pcd_quantidade_atual',
    condicao: (c) => !!c.pcd_obrigatoria && (
      (c.pcd_quantidade_exigida || 0) === 0 ||
      (c.pcd_quantidade_atual || 0) < (c.pcd_quantidade_exigida || 0)
    ),
  },
  // FAP
  {
    titulo: 'Plano de redução do FAP',
    descricao: 'FAP elevado indica alta acidentalidade. Necessário plano de ação.',
    categoria: 'financeira',
    subcategoria: 'fap',
    base_legal: 'Lei 10.666/03',
    criticidade: 'media',
    origem_campo: 'fap_atual',
    condicao: (c) => (c.fap_atual ?? 0) > 1.5,
  },
  // TAC
  {
    titulo: 'Cumprir obrigações do TAC',
    descricao: 'Empresa possui TAC ativo com obrigações a cumprir.',
    categoria: 'legal',
    subcategoria: 'tac',
    base_legal: 'TAC',
    criticidade: 'critica',
    origem_campo: 'tac_possui',
    condicao: (c) => c.tac_possui,
  },
  // Grau de Risco
  {
    titulo: 'Avaliar impacto do grau de risco elevado',
    descricao: 'Grau de risco 3 ou 4 requer medidas preventivas adicionais.',
    categoria: 'sst',
    subcategoria: 'grau_risco',
    base_legal: 'NR-04',
    criticidade: 'media',
    origem_campo: 'grau_risco',
    condicao: (c) => (c.grau_risco ?? 0) >= 3,
  },
  // Condições especiais
  {
    titulo: 'Implantar treinamento de trabalho em altura',
    descricao: 'Atividades em altura requerem treinamento obrigatório.',
    categoria: 'sst',
    subcategoria: 'condicoes_especiais',
    base_legal: 'NR-35',
    criticidade: 'alta',
    origem_campo: 'trabalho_altura',
    condicao: (c) => c.trabalho_altura,
  },
  {
    titulo: 'Treinamento de espaço confinado',
    descricao: 'Atividades em espaço confinado requerem treinamento e procedimentos.',
    categoria: 'sst',
    subcategoria: 'condicoes_especiais',
    base_legal: 'NR-33',
    criticidade: 'alta',
    origem_campo: 'espaco_confinado',
    condicao: (c) => c.espaco_confinado,
  },
  {
    titulo: 'Revisar laudos de insalubridade',
    descricao: 'Condições de insalubridade requerem laudos técnicos atualizados.',
    categoria: 'legal',
    subcategoria: 'condicoes_especiais',
    base_legal: 'NR-15',
    criticidade: 'media',
    origem_campo: 'insalubridade',
    condicao: (c) => c.insalubridade,
  },
  {
    titulo: 'Revisar laudos de periculosidade',
    descricao: 'Condições de periculosidade requerem laudos técnicos atualizados.',
    categoria: 'legal',
    subcategoria: 'condicoes_especiais',
    base_legal: 'NR-16',
    criticidade: 'media',
    origem_campo: 'periculosidade',
    condicao: (c) => c.periculosidade,
  },
  // Jornada
  {
    titulo: 'Avaliar impacto do 3º turno',
    descricao: 'Trabalho noturno requer avaliações específicas de saúde e ergonomia.',
    categoria: 'sst',
    subcategoria: 'jornada',
    base_legal: 'NR-17, CLT Art. 73',
    criticidade: 'media',
    origem_campo: 'possui_terceiro_turno',
    condicao: (c) => c.possui_terceiro_turno,
  },
  // Jovem Aprendiz
  {
    titulo: 'Contratar jovem aprendiz',
    descricao: 'Empresa abaixo da cota mínima de aprendizes.',
    categoria: 'legal',
    subcategoria: 'aprendiz',
    base_legal: 'CLT Art. 429',
    criticidade: 'media',
    origem_campo: 'aprendiz_quantidade_atual',
    condicao: (c) => c.aprendiz_obrigatorio && c.aprendiz_quantidade_atual < c.aprendiz_quantidade_minima,
  },
];
