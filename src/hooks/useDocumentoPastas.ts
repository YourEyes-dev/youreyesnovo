import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";
import { toast } from "sonner";
import type { 
  DocumentoPasta, 
  DocumentoPastaNode, 
  DocumentoAuditLog,
  DocumentoItem 
} from "@/types/documentoPasta";
import { useFiliais, type Filial } from "./useCadastros";
import { useColaboradores, type Colaborador } from "./useColaboradores";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { autoGenerateFolderStructure } from "@/utils/autoGenerateFolderStructure";
import { criarPastaColaborador, criarPastasColaboradoresEmLote } from "@/utils/criarPastaColaborador";

interface DocumentoRow {
  id: string;
  nome_original: string;
  tipo: string;
  tamanho: number;
  status: string;
  data_validade: string | null;
  storage_path: string;
  created_at: string;
  pasta_id: string | null;
  colaborador_id: string | null;
  colaborador_nome: string;
}

type SubpastaColaborador = "Admissão" | "Vida Funcional" | "Saúde Ocupacional" | "Desligamento";

function inferirSubpastaColaboradorPorTipo(tipo: string): SubpastaColaborador {
  const tipoNormalizado = tipo.toLowerCase();

  if (
    tipoNormalizado.includes("aso") ||
    tipoNormalizado.includes("atestado") ||
    tipoNormalizado.includes("epi") ||
    tipoNormalizado.includes("ordem de serviço") ||
    tipoNormalizado.includes("treinamento nr")
  ) {
    return "Saúde Ocupacional";
  }

  if (tipoNormalizado.includes("deslig")) {
    return "Desligamento";
  }

  if (
    tipoNormalizado.includes("ficha de registro") ||
    tipoNormalizado.includes("contrato") ||
    tipoNormalizado.includes("ctps") ||
    tipoNormalizado.includes("rg") ||
    tipoNormalizado.includes("cpf") ||
    tipoNormalizado.includes("resid") ||
    tipoNormalizado.includes("eleitor") ||
    tipoNormalizado.includes("reservista") ||
    tipoNormalizado.includes("cnh") ||
    tipoNormalizado.includes("certificado")
  ) {
    return "Admissão";
  }

  return "Vida Funcional";
}

export function useDocumentoPastas() {
  const { tenantId, user, profile } = useAuth();
  const { filiais } = useFiliais();
  const { colaboradores } = useColaboradores();
  const { empresaAtivaId } = useEmpresaAtiva();
  const queryClient = useQueryClient();

  // Buscar pastas
  const { data: pastas = [], isLoading: loadingPastas, refetch: refetchPastas } = useQuery({
    queryKey: ["documento-pastas", tenantId, empresaAtivaId],
    queryFn: async (): Promise<DocumentoPasta[]> => {
      if (!tenantId) return [];

      let query = supabase
        .from("documento_pastas")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("ordem", { ascending: true });

      if (empresaAtivaId) {
        query = query.eq("empresa_id", empresaAtivaId);
      }

      const { data, error } = await query;

      if (error) throw error;
      return (data || []) as DocumentoPasta[];
    },
    enabled: !!tenantId,
  });

  // Buscar documentos com pasta_id
  const { data: documentos = [], isLoading: loadingDocs } = useQuery({
    queryKey: ["documentos-com-pasta", tenantId, empresaAtivaId],
    queryFn: async (): Promise<(DocumentoItem & { pasta_id: string | null; colaborador_id: string | null; colaborador_nome: string })[]> => {
      if (!tenantId) return [];

      let query = supabase
        .from("documentos")
        .select("id, nome_original, tipo, tamanho, status, data_validade, storage_path, created_at, pasta_id, colaborador_id, colaborador_nome")
        .eq("tenant_id", tenantId)
        .order("created_at", { ascending: false });

      if (empresaAtivaId) {
        query = query.eq("empresa_id", empresaAtivaId);
      }

      const { data, error } = await query;

      if (error) throw error;

      const documentosMapeados = (data || []).map((d: DocumentoRow) => ({
        id: d.id,
        nome_original: d.nome_original,
        tipo: d.tipo,
        tamanho: d.tamanho,
        status: d.status as 'valido' | 'vencendo' | 'vencido',
        data_validade: d.data_validade,
        storage_path: d.storage_path,
        created_at: d.created_at,
        pasta_id: d.pasta_id,
        colaborador_id: d.colaborador_id,
        colaborador_nome: d.colaborador_nome,
      }));

      return documentosMapeados;
    },
    enabled: !!tenantId,
  });

  // Ids de TODAS as admissões da empresa (qualquer status, inclusive desligados).
  // O módulo Documentos é a evidência de todos que passaram pela empresa — a pasta
  // de um desligado NUNCA pode sumir da árvore (guarda legal: FGTS, eSocial, PCMSO).
  // Usado só para validar "pertence a esta empresa" (o filtro de empresa real é o
  // empresa_id da própria pasta); por isso aqui não se filtra por status.
  const { data: admissaoIdsDaEmpresa = [] } = useQuery({
    queryKey: ["documento-admissao-ids", tenantId, empresaAtivaId],
    queryFn: async (): Promise<string[]> => {
      if (!tenantId) return [];
      let q = supabase.from("admissoes").select("id").eq("tenant_id", tenantId);
      if (empresaAtivaId) q = q.eq("empresa_id", empresaAtivaId);
      const { data, error } = await q;
      if (error) throw error;
      return (data || []).map((a: { id: string }) => a.id);
    },
    enabled: !!tenantId,
  });

  // Buscar auditoria
  const { data: auditLogs = [], isLoading: loadingAudit, refetch: refetchAudit } = useQuery({
    queryKey: ["documento-audit", tenantId],
    queryFn: async (): Promise<DocumentoAuditLog[]> => {
      if (!tenantId) return [];

      const { data, error } = await supabase
        .from("documento_audit_log")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("created_at", { ascending: false })
        .limit(100);

      if (error) throw error;
      return (data || []) as DocumentoAuditLog[];
    },
    enabled: !!tenantId,
  });

  // Sincronizar colaboradores que não possuem pasta
  const syncMissingColaboradores = useMutation({
    mutationFn: async () => {
      if (!tenantId || !user) return 0;

      // Colaboradores que já têm pasta
      const colabsComPasta = new Set(
        pastas.filter(p => p.tipo === "colaborador" && p.colaborador_id).map(p => p.colaborador_id)
      );

      // Colaboradores sem pasta
      const colabsSemPasta = colaboradores.filter((c: Colaborador) => !colabsComPasta.has(c.id));
      if (colabsSemPasta.length === 0) return 0;

      const count = await criarPastasColaboradoresEmLote(
        tenantId,
        colabsSemPasta.map((c: Colaborador) => ({ id: c.id, nome: c.nome_completo, cpf: c.cpf })),
        empresaAtivaId
      );
      return count;
    },
    onSuccess: (count) => {
      if (count && count > 0) {
        queryClient.invalidateQueries({ queryKey: ["documento-pastas"] });
        toast.success(`${count} colaborador(es) sincronizado(s) na estrutura de pastas!`);
      }
    },
    onError: (error: Error) => {
      console.error("Erro ao sincronizar colaboradores:", error);
    },
  });

  // Auto-sync: verificar colaboradores sem pasta quando dados carregam
  const needsSync = pastas.length > 0 && colaboradores.length > 0 && (() => {
    const colabsComPasta = new Set(
      pastas.filter(p => p.tipo === "colaborador" && p.colaborador_id).map(p => p.colaborador_id)
    );
    return colaboradores.some((c: Colaborador) => !colabsComPasta.has(c.id));
  })();

  // Construir árvore hierárquica
  const buildTree = (): DocumentoPastaNode[] => {
    const nodeMap = new Map<string, DocumentoPastaNode>();
    const roots: DocumentoPastaNode[] = [];

    // Criar nós para todas as pastas
    pastas.forEach(pasta => {
      const filial = filiais.find((f: Filial) => f.id === pasta.filial_id);
      nodeMap.set(pasta.id, {
        ...pasta,
        children: [],
        documentos: [],
        filial_nome: filial?.nome,
      });
    });

    // Adicionar documentos às pastas
    documentos.forEach((doc) => {
      const pastaId = doc.pasta_id;
      if (pastaId && nodeMap.has(pastaId)) {
        nodeMap.get(pastaId)!.documentos.push({
          id: doc.id,
          nome_original: doc.nome_original,
          tipo: doc.tipo,
          tamanho: doc.tamanho,
          status: doc.status,
          data_validade: doc.data_validade,
          storage_path: doc.storage_path,
          created_at: doc.created_at,
        });
      }
    });

    // Set de colaboradores válidos da empresa ativa (evita exibir pastas vazadas).
    // Inclui ativos E desligados (via admissaoIdsDaEmpresa): o desligado continua
    // sendo da empresa e sua pasta de documentos não pode ser ocultada.
    const colaboradorIdsValidos = new Set<string>([
      ...colaboradores.map((c: Colaborador) => c.id),
      ...admissaoIdsDaEmpresa,
    ]);

    // Construir hierarquia (excluindo pastas de colaborador que não pertencem à empresa ativa)
    pastas.forEach(pasta => {
      const node = nodeMap.get(pasta.id)!;
      // Bloqueia pastas de colaborador "vazadas" de outra empresa (não as de desligado)
      if (pasta.tipo === "colaborador" && pasta.colaborador_id && !colaboradorIdsValidos.has(pasta.colaborador_id)) {
        return;
      }
      if (pasta.pasta_pai_id && nodeMap.has(pasta.pasta_pai_id)) {
        nodeMap.get(pasta.pasta_pai_id)!.children.push(node);
      } else {
        roots.push(node);
      }
    });

    // Ordenar por ordem, depois alfabeticamente para mesmo nível
    const sortNodes = (nodes: DocumentoPastaNode[]) => {
      nodes.sort((a, b) => {
        const typePriority: Record<string, number> = { root: 0, unidade: 1, ano: 2, mes: 3, categoria: 4, colaborador: 5, custom: 6 };
        const tA = typePriority[a.tipo] ?? 9;
        const tB = typePriority[b.tipo] ?? 9;
        if (tA !== tB) return tA - tB;
        if (a.ordem !== b.ordem) return a.ordem - b.ordem;
        return a.nome.localeCompare(b.nome, 'pt-BR');
      });
      nodes.forEach(node => sortNodes(node.children));
    };
    sortNodes(roots);

    // Agrupar pastas de colaborador alfabeticamente quando houver muitas (> 20)
    const AGRUPAR_LIMIAR = 20;
    const agruparColaboradores = (nodes: DocumentoPastaNode[]) => {
      nodes.forEach(parent => {
        const colabChildren = parent.children.filter(c => c.tipo === "colaborador");
        const outrosChildren = parent.children.filter(c => c.tipo !== "colaborador");
        if (colabChildren.length > AGRUPAR_LIMIAR) {
          const grupos = new Map<string, DocumentoPastaNode[]>();
          colabChildren.forEach(c => {
            const primeira = (c.nome.trim().normalize("NFD").replace(/[\u0300-\u036f]/g, "")[0] || "#").toUpperCase();
            const letra = /[A-Z]/.test(primeira) ? primeira : "#";
            if (!grupos.has(letra)) grupos.set(letra, []);
            grupos.get(letra)!.push(c);
          });
          const virtualNodes: DocumentoPastaNode[] = Array.from(grupos.entries())
            .sort(([a], [b]) => a.localeCompare(b))
            .map(([letra, items]) => ({
              id: `__az__${parent.id}__${letra}`,
              tenant_id: parent.tenant_id,
              nome: `${letra}  •  ${items.length} colaborador${items.length > 1 ? "es" : ""}`,
              tipo: "categoria" as const,
              pasta_pai_id: parent.id,
              filial_id: null,
              colaborador_id: null,
              colaborador_cpf: null,
              colaborador_nome: null,
              ano: null,
              mes: null,
              ordem: 0,
              icone: "Users",
              cor: null,
              criado_por: null,
              criado_por_nome: null,
              created_at: parent.created_at,
              updated_at: parent.updated_at,
              children: items,
              documentos: [],
              isVirtual: true,
              virtualLabel: letra,
              totalDescendantes: items.length,
            }));
          parent.children = [...outrosChildren, ...virtualNodes];
        }
        agruparColaboradores(parent.children);
      });
    };
    agruparColaboradores(roots);

    return roots;
  };

  // Criar pasta
  const createPasta = useMutation({
    mutationFn: async (data: Partial<DocumentoPasta>) => {
      if (!tenantId || !user) throw new Error("Não autenticado");

      const { data: pasta, error } = await supabase
        .from("documento_pastas")
        .insert({
          nome: data.nome || "Nova Pasta",
          tipo: data.tipo || "custom",
          pasta_pai_id: data.pasta_pai_id || null,
          filial_id: data.filial_id || null,
          colaborador_id: data.colaborador_id || null,
          colaborador_cpf: data.colaborador_cpf || null,
          colaborador_nome: data.colaborador_nome || null,
          ano: data.ano || null,
          mes: data.mes || null,
          ordem: data.ordem || 0,
          icone: data.icone || null,
          cor: data.cor || null,
          tenant_id: tenantId,
          empresa_id: empresaAtivaId || null,
          criado_por: user.id,
          criado_por_nome: profile?.nome_completo || null,
        })
        .select()
        .single();

      if (error) throw error;
      return pasta;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["documento-pastas"] });
      toast.success("Pasta criada com sucesso!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao criar pasta: " + error.message);
    },
  });

  // Atualizar pasta
  const updatePasta = useMutation({
    mutationFn: async ({ id, ...data }: Partial<DocumentoPasta> & { id: string }) => {
      const { error } = await supabase
        .from("documento_pastas")
        .update({
          nome: data.nome,
          tipo: data.tipo,
          pasta_pai_id: data.pasta_pai_id,
          filial_id: data.filial_id,
          ordem: data.ordem,
          icone: data.icone,
          cor: data.cor,
        })
        .eq("id", id);

      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["documento-pastas"] });
    },
    onError: (error: Error) => {
      toast.error("Erro ao atualizar pasta: " + error.message);
    },
  });

  // Deletar pasta
  const deletePasta = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from("documento_pastas")
        .delete()
        .eq("id", id);

      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["documento-pastas"] });
      toast.success("Pasta excluída!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao excluir pasta: " + error.message);
    },
  });

  // Mover documento para outra pasta
  const moveDocumento = useMutation({
    mutationFn: async ({
      documentoId,
      documentoNome,
      pastaOrigemId,
      pastaOrigemNome,
      pastaDestinoId,
      pastaDestinoNome,
    }: {
      documentoId: string;
      documentoNome: string;
      pastaOrigemId: string | null;
      pastaOrigemNome: string | null;
      pastaDestinoId: string | null;
      pastaDestinoNome: string | null;
    }) => {
      if (!tenantId || !user) throw new Error("Não autenticado");

      // Atualizar documento
      const { error: updateError } = await supabase
        .from("documentos")
        .update({ pasta_id: pastaDestinoId })
        .eq("id", documentoId);

      if (updateError) throw updateError;

      // Registrar auditoria
      const { error: auditError } = await supabase
        .from("documento_audit_log")
        .insert({
          tenant_id: tenantId,
          documento_id: documentoId,
          documento_nome: documentoNome,
          acao: "move",
          pasta_origem_id: pastaOrigemId,
          pasta_origem_nome: pastaOrigemNome,
          pasta_destino_id: pastaDestinoId,
          pasta_destino_nome: pastaDestinoNome,
          usuario_id: user.id,
          usuario_nome: profile?.nome_completo || null,
          user_agent: navigator.userAgent,
        });

      if (auditError) console.error("Erro ao registrar auditoria:", auditError);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["documentos-com-pasta"] });
      queryClient.invalidateQueries({ queryKey: ["documento-audit"] });
      toast.success("Documento movido!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao mover documento: " + error.message);
    },
  });

  // Inicializar estrutura padrão (idempotente — usa autoGenerateFolderStructure)
  const initializeDefaultStructure = useMutation({
    mutationFn: async (_params?: {
      porte?: string;
      cnae?: string;
      grauRisco?: number;
      numTrabalhadores?: number;
      riscos?: string[];
      atividadeEconomica?: string;
    }) => {
      if (!tenantId || !user) throw new Error("Não autenticado");
      return autoGenerateFolderStructure(tenantId, user.id, profile?.nome_completo || null, empresaAtivaId);
    },
    onSuccess: (count) => {
      queryClient.invalidateQueries({ queryKey: ["documento-pastas"] });
      if (count === 0) {
        // Silencioso quando já está completa
      } else {
        toast.success(`${count} pasta(s) nova(s) adicionada(s) à estrutura.`);
      }
    },
    onError: (error: Error) => {
      toast.error("Erro ao criar estrutura: " + error.message);
    },
  });

  // Criar pasta de mês automaticamente
  const createMonthFolder = async (parentPastaId: string, year: number, month: number) => {
    if (!tenantId || !user) throw new Error("Não autenticado");

    const monthNames = [
      "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
      "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
    ];

    const { data, error } = await supabase
      .from("documento_pastas")
      .insert({
        tenant_id: tenantId,
        empresa_id: empresaAtivaId || null,
        nome: monthNames[month - 1],
        tipo: "mes",
        pasta_pai_id: parentPastaId,
        mes: month,
        ano: year,
        ordem: month,
        criado_por: user.id,
        criado_por_nome: profile?.nome_completo || null,
      })
      .select()
      .single();

    if (error) throw error;
    queryClient.invalidateQueries({ queryKey: ["documento-pastas"] });
    return data;
  };

  return {
    pastas,
    documentos,
    auditLogs,
    loading: !tenantId || loadingPastas || loadingDocs,
    loadingAudit,
    tree: buildTree(),
    needsSync,
    syncColaboradores: syncMissingColaboradores.mutateAsync,
    syncing: syncMissingColaboradores.isPending,
    refetchPastas,
    refetchAudit,
    createPasta: createPasta.mutateAsync,
    updatePasta: updatePasta.mutateAsync,
    deletePasta: deletePasta.mutateAsync,
    moveDocumento: moveDocumento.mutateAsync,
    movingDoc: moveDocumento.isPending,
    initializeDefaultStructure: initializeDefaultStructure.mutateAsync,
    initializing: initializeDefaultStructure.isPending,
    createMonthFolder,
  };
}
