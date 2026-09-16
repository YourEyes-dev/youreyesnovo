// Estrutura de diretórios da documentação de testes YourEyes.
// Espelha a estrutura de menu do sistema (AppSidebar): pasta = módulo, subpasta = item de menu.

export interface YourEyesSubmodulo {
  id: string;
  label: string;
  path: string;
}

export interface YourEyesModulo {
  id: string;
  label: string;
  itens: YourEyesSubmodulo[];
}

export const YOUREYES_MODULOS: YourEyesModulo[] = [
  {
    id: "estrutura-organizacional",
    label: "Estrutura Organizacional",
    itens: [
      { id: "empresa", label: "Empresa", path: "/empresa" },
      { id: "filiais", label: "Estabelecimentos / Obras", path: "/cadastros/filiais" },
      { id: "departamentos", label: "Departamentos", path: "/cadastros/departamentos" },
      { id: "cargos", label: "Cargos", path: "/cadastros/cargos" },
      { id: "colaboradores", label: "Colaboradores", path: "/colaboradores" },
      { id: "terceiros", label: "Prestadores de Serviços", path: "/terceiros" },
      { id: "organograma", label: "Organograma", path: "/estrategia?tab=organograma" },
    ],
  },
  {
    id: "planejamento-gestao",
    label: "Planejamento & Gestão",
    itens: [
      { id: "identidade-estrategica", label: "Identidade Estratégica", path: "/estrategia?tab=cultura" },
      { id: "planejamento-estrategico", label: "Planejamento Estratégico", path: "/estrategia" },
      { id: "metas", label: "Metas", path: "/metas" },
      { id: "plano-acao", label: "Plano de Ação", path: "/plano-acao" },
    ],
  },
  {
    id: "pessoas-cultura",
    label: "Pessoas & Cultura",
    itens: [
      { id: "onboarding", label: "Onboarding", path: "/onboarding-rh" },
      { id: "contratos-experiencia", label: "Contratos de Experiência", path: "/contratos-experiencia" },
      { id: "cultura-celebracoes", label: "Cultura & Celebrações", path: "/cultura-celebracoes" },
      { id: "mural-interno", label: "Mural Interno", path: "/feed" },
      { id: "bem-estar", label: "Meu Bem-Estar", path: "/felicidade" },
      { id: "feedback-desenvolvimento", label: "Feedback & Desenvolvimento", path: "/feedback-ocorrencias" },
      { id: "ouvidoria", label: "Ouvidoria", path: "/ouvidoria" },
    ],
  },
  {
    id: "desenvolvimento-performance",
    label: "Desenvolvimento & Performance",
    itens: [
      { id: "aprendizado-competencias", label: "Aprendizado & Competências", path: "/aprendizado-papeis" },
      { id: "trilhas", label: "Trilhas", path: "/trilhas" },
      { id: "avaliacoes", label: "Avaliações", path: "/avaliacoes" },
      { id: "pdi", label: "PDI", path: "/pdi" },
    ],
  },
  {
    id: "jornada-rotina",
    label: "Jornada & Rotina",
    itens: [
      { id: "ponto", label: "Ponto", path: "/ponto" },
      { id: "analise-jornada", label: "Análise de Jornada", path: "/analise-jornada" },
      { id: "ferias", label: "Férias", path: "/ferias" },
      { id: "afastamentos", label: "Afastamentos", path: "/atestados" },
      { id: "saude-ocupacional", label: "Saúde Ocupacional (ASO)", path: "/saude-ocupacional" },
      { id: "beneficios", label: "Benefícios", path: "/financeiro/beneficios" },
    ],
  },
  {
    id: "saude-seguranca",
    label: "Saúde & Segurança",
    itens: [
      { id: "compliance-sst", label: "Compliance SST", path: "/compliance-sst" },
      { id: "psicossocial", label: "Psicossocial", path: "/psicossocial" },
      { id: "ergonomia", label: "Ergonomia", path: "/ergonomia" },
      { id: "epis", label: "EPIs", path: "/epis" },
      { id: "incidentes-acidentes", label: "Incidentes & Acidentes", path: "/incidentes-acidentes" },
    ],
  },
  {
    id: "documentos-governanca",
    label: "Documentos & Governança",
    itens: [
      { id: "documentos", label: "Documentos", path: "/documentos" },
      { id: "hub-contabil", label: "Hub Contábil", path: "/hub-contabil" },
    ],
  },
  {
    id: "financeiro",
    label: "Financeiro",
    itens: [{ id: "financeiro", label: "Financeiro", path: "/financeiro" }],
  },
  {
    id: "rede-parceiros",
    label: "MarketYE",
    itens: [{ id: "marketplace", label: "MarketYE (marketplace de serviços)", path: "/marketplace" }],
  },
  {
    id: "academia",
    label: "Academia",
    itens: [{ id: "academia", label: "Academia", path: "/academia" }],
  },
  {
    id: "sistema",
    label: "Sistema",
    itens: [
      { id: "suporte", label: "Suporte", path: "/suporte" },
      { id: "configuracoes", label: "Configurações", path: "/configuracoes" },
    ],
  },
];

export function getModuloLabel(id?: string | null): string {
  if (!id) return "Geral";
  return YOUREYES_MODULOS.find((m) => m.id === id)?.label || id;
}

export function getSubmoduloLabel(moduloId?: string | null, submoduloId?: string | null): string | null {
  if (!moduloId || !submoduloId) return null;
  const modulo = YOUREYES_MODULOS.find((m) => m.id === moduloId);
  return modulo?.itens.find((i) => i.id === submoduloId)?.label || submoduloId;
}

export const DIAS_SEMANA = [
  { valor: 0, label: "Dom" },
  { valor: 1, label: "Seg" },
  { valor: 2, label: "Ter" },
  { valor: 3, label: "Qua" },
  { valor: 4, label: "Qui" },
  { valor: 5, label: "Sex" },
  { valor: 6, label: "Sáb" },
];

export const PERIODICIDADES = [
  { valor: "diaria", label: "Diária" },
  { valor: "semanal", label: "Semanal" },
  { valor: "quinzenal", label: "Quinzenal" },
  { valor: "mensal", label: "Mensal" },
] as const;

export type Periodicidade = (typeof PERIODICIDADES)[number]["valor"];

export function descreverAgendamento(agente: {
  periodicidade: string;
  dias_semana?: number[] | null;
  dia_mes?: number | null;
  horario?: string | null;
}): string {
  const hora = (agente.horario || "06:00").slice(0, 5);
  const dias = (agente.dias_semana || [])
    .map((d) => DIAS_SEMANA.find((x) => x.valor === d)?.label)
    .filter(Boolean)
    .join(", ");

  switch (agente.periodicidade) {
    case "diaria":
      return `Diária às ${hora}`;
    case "semanal":
      return `Semanal · ${dias || "Seg"} às ${hora}`;
    case "quinzenal":
      return `Quinzenal · ${dias || "Seg"} às ${hora}`;
    case "mensal":
      return `Mensal · dia ${agente.dia_mes || 1} às ${hora}`;
    default:
      return hora;
  }
}
