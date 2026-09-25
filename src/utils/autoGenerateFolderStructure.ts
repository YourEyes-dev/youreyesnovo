import { supabase } from "@/integrations/supabase/client";

interface FolderNode {
  nome: string;
  tipo: string;
  ordem: number;
  icone: string | null;
  children?: FolderNode[];
}

const STANDARD_STRUCTURE: FolderNode[] = [
  {
    nome: "Governança e Administração", tipo: "root", ordem: 0, icone: "Scale",
    children: [
      { nome: "Contrato Social e Estatuto", tipo: "categoria", ordem: 0, icone: "Building2" },
      { nome: "Políticas e Diretrizes", tipo: "categoria", ordem: 1, icone: "Target" },
      { nome: "Licenças e Autorizações", tipo: "categoria", ordem: 2, icone: "FileCheck" },
      { nome: "Certidões", tipo: "categoria", ordem: 3, icone: "Award" },
      { nome: "Registros em Conselhos", tipo: "categoria", ordem: 4, icone: "Shield" },
    ],
  },
  {
    nome: "Sistema de Gestão", tipo: "root", ordem: 1, icone: "BookOpen",
    children: [
      { nome: "Procedimentos e Instruções de Trabalho", tipo: "categoria", ordem: 0, icone: "FileText" },
      { nome: "Registros da Qualidade", tipo: "categoria", ordem: 1, icone: "CheckSquare" },
    ],
  },
  {
    nome: "Gestão de Riscos", tipo: "root", ordem: 2, icone: "AlertTriangle",
    children: [
      { nome: "Inventário de Riscos", tipo: "categoria", ordem: 0, icone: "List" },
      { nome: "Análise de Riscos (APR / HAZOP)", tipo: "categoria", ordem: 1, icone: "Search" },
      { nome: "Planos de Emergência", tipo: "categoria", ordem: 2, icone: "ShieldAlert" },
    ],
  },
  {
    nome: "SST", tipo: "root", ordem: 3, icone: "Shield",
    children: [
      {
        nome: "Programas Legais", tipo: "categoria", ordem: 0, icone: "FileCheck",
        children: [
          { nome: "PGR", tipo: "custom", ordem: 0, icone: null },
          { nome: "PCMSO", tipo: "custom", ordem: 1, icone: null },
          { nome: "LTCAT", tipo: "custom", ordem: 2, icone: null },
        ],
      },
      {
        nome: "Treinamentos", tipo: "categoria", ordem: 1, icone: "GraduationCap",
        children: [
          { nome: "NR-01 — Disposições Gerais e Gerenciamento de Riscos", tipo: "custom", ordem: 0, icone: null },
          { nome: "NR-05 — CIPA", tipo: "custom", ordem: 1, icone: null },
          { nome: "NR-06 — EPIs", tipo: "custom", ordem: 2, icone: null },
        ],
      },
      {
        nome: "Registros e Evidências", tipo: "categoria", ordem: 2, icone: "ClipboardList",
        children: [
          { nome: "CAT — Comunicação de Acidente", tipo: "custom", ordem: 0, icone: null },
          { nome: "Inspeções de Segurança", tipo: "custom", ordem: 1, icone: null },
          { nome: "Permissões de Trabalho", tipo: "custom", ordem: 2, icone: null },
        ],
      },
    ],
  },
  {
    nome: "Cultura Organizacional", tipo: "root", ordem: 4, icone: "Heart",
    children: [
      { nome: "Manual de Cultura", tipo: "categoria", ordem: 0, icone: "FileText" },
      { nome: "Documentos da Cultura", tipo: "categoria", ordem: 1, icone: "FileCheck" },
    ],
  },
  { nome: "Gestão de Pessoas", tipo: "root", ordem: 5, icone: "Users" },
  {
    nome: "Investigação de Incidentes", tipo: "root", ordem: 6, icone: "SearchX",
    children: [
      { nome: "Acidentes de Trabalho", tipo: "categoria", ordem: 0, icone: null },
      { nome: "Quase Acidentes", tipo: "categoria", ordem: 1, icone: null },
      { nome: "Não Conformidades", tipo: "categoria", ordem: 2, icone: null },
    ],
  },
  {
    nome: "Auditorias e Melhoria Contínua", tipo: "root", ordem: 7, icone: "CheckSquare",
    children: [
      { nome: "Auditorias Internas", tipo: "categoria", ordem: 0, icone: "ClipboardCheck" },
      { nome: "Auditorias Externas e Certificações", tipo: "categoria", ordem: 1, icone: "Award" },
      { nome: "Ações Corretivas e Preventivas", tipo: "categoria", ordem: 2, icone: "RefreshCw" },
    ],
  },
];

export async function autoGenerateFolderStructure(
  tenantId: string,
  userId: string,
  userName: string | null,
  empresaId?: string | null
) {
  // Fetch ALL existing folders for this tenant
  let existentesQuery = supabase
    .from("documento_pastas")
    .select("id, nome, pasta_pai_id")
    .eq("tenant_id", tenantId);

  existentesQuery = empresaId
    ? existentesQuery.eq("empresa_id", empresaId)
    : existentesQuery.is("empresa_id", null);

  const { data: existentes } = await existentesQuery;

  const existing = existentes || [];

  // Build a lookup: for a given (nome, pasta_pai_id) -> existing id
  const existingMap = new Map<string, string>();
  for (const p of existing) {
    existingMap.set(`${p.nome}||${p.pasta_pai_id ?? "null"}`, p.id);
  }

  const toInsert: Array<{
    id: string;
    nome: string;
    tipo: string;
    ordem: number;
    icone: string | null;
    pasta_pai_id: string | null;
    filial_id: null;
    colaborador_id: null;
    colaborador_cpf: null;
    colaborador_nome: null;
    ano: null;
    tenant_id: string;
    empresa_id: string | null;
    criado_por: string;
    criado_por_nome: string | null;
  }> = [];

  const processNode = (node: FolderNode, parentId: string | null) => {
    const key = `${node.nome}||${parentId ?? "null"}`;
    let folderId = existingMap.get(key);

    if (!folderId) {
      // Folder doesn't exist — create it
      folderId = crypto.randomUUID();
      toInsert.push({
        id: folderId,
        nome: node.nome,
        tipo: node.tipo,
        ordem: node.ordem,
        icone: node.icone,
        pasta_pai_id: parentId,
        filial_id: null,
        colaborador_id: null,
        colaborador_cpf: null,
        colaborador_nome: null,
        ano: null,
        tenant_id: tenantId,
        empresa_id: empresaId || null,
        criado_por: userId,
        criado_por_nome: userName,
      });
    }

    // Process children using the resolved (existing or new) folderId
    if (node.children) {
      for (const child of node.children) {
        processNode(child, folderId);
      }
    }
  };

  for (const root of STANDARD_STRUCTURE) {
    processNode(root, null);
  }

  if (toInsert.length === 0) return 0;

  const chunkSize = 100;
  for (let i = 0; i < toInsert.length; i += chunkSize) {
    const chunk = toInsert.slice(i, i + chunkSize);
    const { error } = await supabase.from("documento_pastas").insert(chunk);
    if (error) throw error;
  }

  return toInsert.length;
}
