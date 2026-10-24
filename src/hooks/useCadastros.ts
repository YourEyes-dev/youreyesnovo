import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useTenant } from "./useTenant";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";

// Types
export interface Departamento {
  id: string;
  tenant_id: string;
  nome: string;
  descricao: string | null;
  responsavel_id: string | null;
  filial_id: string | null;
  gestor_admissao_id: string | null;
  gestor_substituto_admissao_id: string | null;
  substituto_ativo: boolean;
  ativo: boolean;
  created_at: string;
  updated_at: string;
}

export interface Cargo {
  id: string;
  tenant_id: string;
  nome: string;
  descricao: string | null;
  responsabilidade?: string | null;
  departamento_id: string | null;
  nivel: string | null;
  faixa_salarial_min: number | null;
  faixa_salarial_max: number | null;
  periodicidade_exame_meses: number | null;
  exames_obrigatorios: string[] | null;
  requisitos_formacao?: string | null;
  requisitos_experiencia?: string | null;
  interfaces_cargo?: string | null;
  objetivo_funcao?: string | null;
  escopo_geral?: string | null;
  padroes_execucao?: string | null;
  cultura_esperada?: string | null;
  erros_riscos?: string | null;
  criterios_sucesso?: string | null;
  ferramentas_cargo?: string | null;
  subordinacao?: string | null;

  // SST - Condições Especiais
  insalubridade: boolean;
  insalubridade_grau: string | null;
  insalubridade_agente_nocivo: string | null;
  periculosidade: boolean;
  periculosidade_tipo: string | null;
  aposentadoria_especial: boolean;
  aposentadoria_especial_anos: number | null;
  ativo: boolean;
  created_at: string;
  updated_at: string;
  departamento?: Departamento | { id: string; nome: string } | null;
}

export interface Filial {
  id: string;
  tenant_id: string;
  nome: string;
  cnpj: string | null;
  endereco: string | null;
  cidade: string | null;
  estado: string | null;
  cep: string | null;
  telefone: string | null;
  email: string | null;
  responsavel_id: string | null;
  empresa_id: string | null;
  tipo: string;
  cno: string | null;
  ativo: boolean;
  created_at: string;
  updated_at: string;
}

// Departamentos Hook
export function useDepartamentos() {
  const { tenantId } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();
  const queryClient = useQueryClient();

  const { data: departamentos = [], isLoading, error } = useQuery({
    queryKey: ["departamentos", tenantId, empresaAtivaId],
    queryFn: async () => {
      let query = supabase
        .from("departamentos")
        .select("*")
        .eq("tenant_id", tenantId!)
        .order("nome");

      if (empresaAtivaId) query = query.eq("empresa_id", empresaAtivaId);

      const { data, error } = await query;
      if (error) throw error;
      return (data as unknown) as Departamento[];
    },
    enabled: !!tenantId,
  });

  const createDepartamento = useMutation({
    mutationFn: async (departamento: Omit<Departamento, "id" | "tenant_id" | "created_at" | "updated_at">) => {
      const nomeNormalizado = departamento.nome?.trim();
      if (!nomeNormalizado) throw new Error("Nome do departamento é obrigatório");

      const { data, error } = await supabase
        .from("departamentos")
        .insert({ ...departamento, nome: nomeNormalizado, tenant_id: tenantId!, empresa_id: empresaAtivaId || null })
        .select()
        .single();

      if (error) {
        if (error.code === "23505") {
          throw new Error(`Já existe um departamento com o nome "${nomeNormalizado}" nesta empresa.`);
        }
        throw error;
      }
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["departamentos"] });
      toast.success("Departamento criado com sucesso!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao criar departamento: " + error.message);
    },
  });

  const updateDepartamento = useMutation({
    mutationFn: async ({ id, ...updates }: Partial<Departamento> & { id: string }) => {
      const { data, error } = await supabase
        .from("departamentos")
        .update(updates)
        .eq("id", id)
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["departamentos"] });
      toast.success("Departamento atualizado com sucesso!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao atualizar departamento: " + error.message);
    },
  });

  const deleteDepartamento = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from("departamentos")
        .delete()
        .eq("id", id);

      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["departamentos"] });
      toast.success("Departamento excluído com sucesso!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao excluir departamento: " + error.message);
    },
  });

  return {
    departamentos,
    isLoading,
    error,
    createDepartamento,
    updateDepartamento,
    deleteDepartamento,
  };
}

// Cargos Hook
export function useCargos(options?: { skipEmpresaFilter?: boolean }) {
  const { tenantId } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();
  const queryClient = useQueryClient();
  const skipEmpresa = options?.skipEmpresaFilter ?? false;

  const { data: cargos = [], isLoading, error } = useQuery({
    queryKey: ["cargos", tenantId, skipEmpresa ? "all" : empresaAtivaId],
    queryFn: async () => {
      // View mascarada: faixa salarial vem nula para quem não pode ver salário
      // (server-side). Escritas (criar/editar/excluir cargo) seguem na tabela base.
      let query = supabase
        .from("cargos_segura" as any)
        .select(`*, departamento:departamentos(id, nome), responsabilidade`)
        .eq("tenant_id", tenantId!)
        .order("nome");

      if (!skipEmpresa && empresaAtivaId) query = query.eq("empresa_id", empresaAtivaId);

      const { data, error } = await query;
      if (error) throw error;
      return data as (Cargo & { departamento: { id: string; nome: string } | null })[];
    },
    enabled: !!tenantId,
  });

  const createCargo = useMutation({
    mutationFn: async (cargo: Omit<Cargo, "id" | "tenant_id" | "created_at" | "updated_at" | "departamento">) => {
      const nomeNormalizado = cargo.nome?.trim();
      if (!nomeNormalizado) throw new Error("Nome da função é obrigatório");

      const { data, error } = await supabase
        .from("cargos")
        .insert({ ...cargo, nome: nomeNormalizado, tenant_id: tenantId!, empresa_id: empresaAtivaId || null })
        .select()
        .single();

      if (error) {
        if (error.code === "23505") {
          throw new Error(`Já existe uma função com o nome "${nomeNormalizado}" nesta empresa.`);
        }
        throw error;
      }
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["cargos"] });
      toast.success("Função criada com sucesso!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao criar função: " + error.message);
    },
  });

  const updateCargo = useMutation({
    mutationFn: async ({ id, ...updates }: Partial<Cargo> & { id: string }) => {
      const { departamento, ...rest } = updates;
      const { data, error } = await supabase
        .from("cargos")
        .update(rest)
        .eq("id", id)
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["cargos"] });
      toast.success("Função atualizada com sucesso!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao atualizar função: " + error.message);
    },
  });

  const deleteCargo = useMutation({
    mutationFn: async (id: string) => {
      const nome = cargos.find((c) => c.id === id)?.nome?.trim();
      if (!nome) throw new Error("Função não encontrada.");

      // Vínculo cargo↔colaborador é por NOME (não há FK): bloqueia a exclusão
      // se algum colaborador (admissoes / usuarios_base) usa esta função.
      const [adm, usr] = await Promise.all([
        supabase
          .from("admissoes")
          .select("id", { count: "exact", head: true })
          .eq("tenant_id", tenantId!)
          .eq("cargo", nome),
        (supabase.rpc as any)("usuarios_contar_por_cargo", { p_cargo: nome }),
      ]);
      if (adm.error) throw adm.error;
      if (usr.error) throw usr.error;
      const vinculados = (adm.count ?? 0) + (Number(usr.data) || 0);
      if (vinculados > 0) {
        throw new Error(
          `Não é possível excluir a função "${nome}": há ${vinculados} colaborador(es) vinculado(s). Reatribua ou desvincule antes de excluir.`,
        );
      }

      // Confirma que a linha foi realmente removida (evita falso sucesso por RLS).
      const { data, error } = await supabase
        .from("cargos")
        .delete()
        .eq("id", id)
        .select("id");

      if (error) {
        if (error.code === "23503") {
          throw new Error(
            "Não é possível excluir: a função está vinculada a outros registros do sistema.",
          );
        }
        throw error;
      }
      if (!data?.length) {
        throw new Error(
          "A função não foi excluída (verifique permissões) — atualize a página e tente novamente.",
        );
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["cargos"] });
      toast.success("Função excluída com sucesso!");
    },
    onError: (error: Error) => {
      toast.error(error.message);
    },
  });

  return {
    cargos,
    isLoading,
    error,
    createCargo,
    updateCargo,
    deleteCargo,
  };
}

// Filiais Hook
export function useFiliais() {
  const { tenantId } = useTenant();
  const queryClient = useQueryClient();

  const { data: filiais = [], isLoading, error } = useQuery({
    queryKey: ["filiais", tenantId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("filiais")
        .select("*")
        .order("nome");

      if (error) throw error;
      return data as Filial[];
    },
    enabled: !!tenantId,
  });

  const createFilial = useMutation({
    mutationFn: async (filial: Omit<Filial, "id" | "tenant_id" | "created_at" | "updated_at">) => {
      const { data, error } = await supabase
        .from("filiais")
        .insert({ ...filial, tenant_id: tenantId! })
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["filiais"] });
      toast.success("Registro criado com sucesso!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao criar registro: " + error.message);
    },
  });

  const updateFilial = useMutation({
    mutationFn: async ({ id, ...updates }: Partial<Filial> & { id: string }) => {
      const { data, error } = await supabase
        .from("filiais")
        .update(updates)
        .eq("id", id)
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["filiais"] });
      toast.success("Registro atualizado com sucesso!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao atualizar registro: " + error.message);
    },
  });

  const deleteFilial = useMutation({
    mutationFn: async (id: string) => {
      // YOUREYES-149: bloqueia exclusão de estabelecimento/obra com
      // departamentos vinculados (o FK é ON DELETE SET NULL, então o
      // banco deixaria passar e os departamentos ficariam órfãos).
      const { count, error: depError } = await supabase
        .from("departamentos")
        .select("id", { count: "exact", head: true })
        .eq("filial_id", id);

      if (depError) throw depError;
      if ((count ?? 0) > 0) {
        throw new Error(
          `este registro possui ${count} departamento(s) vinculado(s). ` +
          `Edite o(s) departamento(s) e remova o vínculo antes de excluir.`
        );
      }

      const { error } = await supabase
        .from("filiais")
        .delete()
        .eq("id", id);

      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["filiais"] });
      toast.success("Registro excluído com sucesso!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao excluir registro: " + error.message);
    },
  });

  return {
    filiais,
    isLoading,
    error,
    createFilial,
    updateFilial,
    deleteFilial,
  };
}
