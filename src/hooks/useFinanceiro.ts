import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { useAuth } from "./useAuth";
import { toast } from "sonner";
import { handleMutationError } from "@/lib/toastError";

// Types
export interface BeneficioTipo {
  id: string;
  tenant_id: string;
  nome: string;
  categoria: string;
  descricao: string | null;
  valor_padrao: number;
  tipo_desconto: string;
  percentual_desconto: number;
  valor_desconto_fixo: number;
  ativo: boolean;
  created_at: string;
  updated_at: string;
}

export interface BeneficioColaborador {
  id: string;
  tenant_id: string;
  beneficio_tipo_id: string;
  colaborador_id: string;
  colaborador_nome: string;
  colaborador_cpf: string | null;
  valor: number;
  valor_desconto: number;
  data_inicio: string;
  data_fim: string | null;
  status: string;
  motivo_cancelamento: string | null;
  observacoes: string | null;
  created_at: string;
  updated_at: string;
  // joined
  beneficio_tipo?: BeneficioTipo;
}

export interface FolhaPeriodo {
  id: string;
  tenant_id: string;
  competencia: string;
  status: string;
  data_abertura: string | null;
  data_fechamento: string | null;
  total_bruto: number;
  total_descontos: number;
  total_liquido: number;
  total_colaboradores: number;
  observacoes: string | null;
  fechado_por_nome: string | null;
  created_at: string;
  updated_at: string;
}

export interface FolhaItem {
  id: string;
  tenant_id: string;
  periodo_id: string;
  colaborador_id: string;
  colaborador_nome: string;
  colaborador_cpf: string | null;
  cargo: string | null;
  departamento: string | null;
  salario_base: number;
  total_proventos: number;
  total_descontos: number;
  total_liquido: number;
  status: string;
  observacoes: string | null;
  created_at: string;
  updated_at: string;
}

export interface FolhaEvento {
  id: string;
  tenant_id: string;
  folha_item_id: string;
  tipo: string;
  codigo: string | null;
  descricao: string;
  referencia: string | null;
  valor: number;
  origem: string;
  created_at: string;
}

export const CATEGORIA_BENEFICIO: Record<string, { label: string; color: string }> = {
  alimentacao: { label: "Alimentação", color: "bg-orange-100 text-orange-800" },
  saude: { label: "Saúde", color: "bg-red-100 text-red-800" },
  transporte: { label: "Transporte", color: "bg-blue-100 text-blue-800" },
  seguro: { label: "Seguro", color: "bg-purple-100 text-purple-800" },
  outros: { label: "Outros", color: "bg-gray-100 text-gray-800" },
};

export const STATUS_FOLHA: Record<string, { label: string; color: string }> = {
  aberto: { label: "Aberto", color: "bg-blue-100 text-blue-800" },
  previa: { label: "Prévia", color: "bg-yellow-100 text-yellow-800" },
  conferencia: { label: "Conferência", color: "bg-orange-100 text-orange-800" },
  fechado: { label: "Fechado", color: "bg-green-100 text-green-800" },
};

export function useFinanceiro() {
  const { tenantId, user, profile } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const queryClient = useQueryClient();

  // ========== BENEFÍCIOS TIPOS ==========
  const useBeneficiosTipos = () =>
    useQuery({
      queryKey: ["beneficios-tipos", tenantId],
      queryFn: async (): Promise<BeneficioTipo[]> => {
        if (!tenantId) return [];
        const { data, error } = await fromTable("beneficios_tipos")
          .select("*")
          .eq("tenant_id", tenantId)
          .order("nome") as { data: BeneficioTipo[] | null; error: Error | null };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId,
    });

  const criarBeneficioTipoMutation = useMutation({
    mutationFn: async (dados: Partial<BeneficioTipo>) => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      const { data, error } = await fromTable("beneficios_tipos")
        .insert({ ...dados, tenant_id: tenantId } as any)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["beneficios-tipos"] });
      toast.success("Benefício criado com sucesso!");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const atualizarBeneficioTipoMutation = useMutation({
    mutationFn: async ({ id, ...dados }: Partial<BeneficioTipo> & { id: string }) => {
      const { data, error } = await fromTable("beneficios_tipos")
        .update(dados as any)
        .eq("id", id)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["beneficios-tipos"] });
      toast.success("Benefício atualizado!");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  // ========== BENEFÍCIOS COLABORADORES ==========
  const useBeneficiosColaboradores = () =>
    useQuery({
    queryKey: ["beneficios-colaboradores", tenantId, empresaAtivaId],
    queryFn: async (): Promise<BeneficioColaborador[]> => {
      if (!tenantId) return [];
      
      // View mascarada: valor/valor_desconto vêm nulos para quem não pode ver
      // salário (server-side). Escritas seguem na tabela base (mutations abaixo).
      let query = fromTable("beneficios_colaboradores_segura")
        .select("*, beneficios_tipos(*)")
        .eq("tenant_id", tenantId);

      if (empresaAtivaId) {
        query = query.eq("empresa_id", empresaAtivaId);
      }

      const { data, error } = await query
        .order("colaborador_nome") as { data: any[] | null; error: Error | null };
        if (error) throw error;
        return (data || []).map((d: any) => ({
          ...d,
          beneficio_tipo: d.beneficios_tipos,
        }));
      },
      enabled: !!tenantId,
    });

  const vincularBeneficioMutation = useMutation({
    mutationFn: async (dados: Partial<BeneficioColaborador>) => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      const { data, error } = await fromTable("beneficios_colaboradores")
        .insert({ ...dados, tenant_id: tenantId, empresa_id: empresaAtivaId || null } as any)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["beneficios-colaboradores"] });
      toast.success("Benefício vinculado ao colaborador!");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const atualizarBeneficioColabMutation = useMutation({
    mutationFn: async ({ id, ...dados }: Partial<BeneficioColaborador> & { id: string }) => {
      const { data, error } = await fromTable("beneficios_colaboradores")
        .update(dados as any)
        .eq("id", id)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["beneficios-colaboradores"] });
      toast.success("Benefício atualizado!");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  // ========== FOLHA PERÍODOS ==========
  const useFolhaPeriodos = () =>
    useQuery({
      queryKey: ["folha-periodos", tenantId],
      queryFn: async (): Promise<FolhaPeriodo[]> => {
        if (!tenantId) return [];
        const { data, error } = await fromTable("folha_periodos")
          .select("*")
          .eq("tenant_id", tenantId)
          .order("competencia", { ascending: false }) as { data: FolhaPeriodo[] | null; error: Error | null };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId,
    });

  const criarPeriodoMutation = useMutation({
    mutationFn: async (dados: { competencia: string; observacoes?: string }) => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      const { data, error } = await fromTable("folha_periodos")
        .insert({ ...dados, tenant_id: tenantId } as any)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["folha-periodos"] });
      toast.success("Período criado com sucesso!");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const atualizarPeriodoMutation = useMutation({
    mutationFn: async ({ id, ...dados }: Partial<FolhaPeriodo> & { id: string }) => {
      const { data, error } = await fromTable("folha_periodos")
        .update(dados as any)
        .eq("id", id)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["folha-periodos"] });
      toast.success("Período atualizado!");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  // ========== FOLHA ITENS ==========
  const useFolhaItens = (periodoId?: string) =>
    useQuery({
      queryKey: ["folha-itens", tenantId, periodoId],
      queryFn: async (): Promise<FolhaItem[]> => {
        if (!tenantId || !periodoId) return [];
        const { data, error } = await fromTable("folha_itens")
          .select("*")
          .eq("tenant_id", tenantId)
          .eq("periodo_id", periodoId)
          .order("colaborador_nome") as { data: FolhaItem[] | null; error: Error | null };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId && !!periodoId,
    });

  const criarFolhaItemMutation = useMutation({
    mutationFn: async (dados: Partial<FolhaItem>) => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      const { data, error } = await fromTable("folha_itens")
        .insert({ ...dados, tenant_id: tenantId } as any)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["folha-itens"] });
      toast.success("Item da folha criado!");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  return {
    // Benefícios Tipos
    useBeneficiosTipos,
    criarBeneficioTipo: criarBeneficioTipoMutation.mutateAsync,
    criandoBeneficioTipo: criarBeneficioTipoMutation.isPending,
    atualizarBeneficioTipo: atualizarBeneficioTipoMutation.mutateAsync,

    // Benefícios Colaboradores
    useBeneficiosColaboradores,
    vincularBeneficio: vincularBeneficioMutation.mutateAsync,
    vinculandoBeneficio: vincularBeneficioMutation.isPending,
    atualizarBeneficioColab: atualizarBeneficioColabMutation.mutateAsync,

    // Folha Períodos
    useFolhaPeriodos,
    criarPeriodo: criarPeriodoMutation.mutateAsync,
    criandoPeriodo: criarPeriodoMutation.isPending,
    atualizarPeriodo: atualizarPeriodoMutation.mutateAsync,

    // Folha Itens
    useFolhaItens,
    criarFolhaItem: criarFolhaItemMutation.mutateAsync,
    criandoFolhaItem: criarFolhaItemMutation.isPending,
  };
}
