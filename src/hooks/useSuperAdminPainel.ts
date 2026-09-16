import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

export interface SuperAdminGlobalStats {
  tenants: { total: number; ativos: number; novos_30d: number };
  usuarios: { total: number; ativos_7d: number };
  colaboradores: { total: number; novos_30d: number };
  leads: { total: number; novos_7d: number; convertidos: number; em_negociacao: number };
  landing_leads: { total: number; com_diagnostico: number; convertidos: number };
  campanhas_psicossociais: { total: number; ativas: number; finalizadas: number };
}

export function useSuperAdminStats() {
  return useQuery({
    queryKey: ["superadmin", "global-stats"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("superadmin_global_stats");
      if (error) throw error;
      return data as unknown as SuperAdminGlobalStats;
    },
    refetchInterval: 60_000,
  });
}

export function useSuperAdminGrowth(dias = 30) {
  return useQuery({
    queryKey: ["superadmin", "growth", dias],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("superadmin_growth_series", { _dias: dias });
      if (error) throw error;
      return (data as any[]) || [];
    },
  });
}

export function useSuperAdminTenantsStatus() {
  return useQuery({
    queryKey: ["superadmin", "tenants-status"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("superadmin_tenants_status");
      if (error) throw error;
      return (data as any[]) || [];
    },
  });
}

export function useSuperAdminUsuarios(search: string) {
  return useQuery({
    queryKey: ["superadmin", "usuarios-global", search],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("superadmin_usuarios_global", {
        _search: search || null, _limite: 200,
      });
      if (error) throw error;
      return (data as any[]) || [];
    },
  });
}

// ============ LEADS CRM ============
export type LeadStatus = "novo" | "contatado" | "qualificado" | "proposta" | "negociacao" | "convertido" | "perdido";
export type LeadOrigem = "landing_page" | "indicacao" | "prospect_manual" | "linkedin" | "whatsapp" | "evento" | "meta_ads" | "outro";

export interface Lead {
  id: string;
  nome: string;
  email?: string | null;
  telefone?: string | null;
  empresa?: string | null;
  cargo?: string | null;
  origem: LeadOrigem;
  status: LeadStatus;
  valor_estimado?: number | null;
  responsavel_id?: string | null;
  proxima_acao_data?: string | null;
  proxima_acao_descricao?: string | null;
  notas?: string | null;
  tags?: string[];
  ultimo_contato_at?: string | null;
  parceiro_id?: string | null;
  parceiro_link_id?: string | null;
  atribuicao?: 'link' | 'casa' | null;
  implantador_parceiro_id?: string | null;
  cidade?: string | null;
  uf?: string | null;
  created_at: string;
  updated_at: string;
}

export function useLeads() {
  const qc = useQueryClient();

  const query = useQuery({
    queryKey: ["superadmin", "leads"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("leads")
        .select("*")
        .is("deleted_at", null)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return (data || []) as Lead[];
    },
  });

  const createLead = useMutation({
    mutationFn: async (input: Partial<Lead>) => {
      const { data: u } = await supabase.auth.getUser();
      const payload = { ...input, created_by: u.user?.id } as any;
      const { data, error } = await supabase.from("leads").insert(payload).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["superadmin", "leads"] });
      toast.success("Lead criado");
    },
    onError: (e: any) => toast.error(e.message),
  });

  const updateLead = useMutation({
    mutationFn: async ({ id, ...patch }: Partial<Lead> & { id: string }) => {
      const { error } = await supabase.from("leads").update(patch as any).eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["superadmin", "leads"] });
      toast.success("Lead atualizado");
    },
    onError: (e: any) => toast.error(e.message),
  });

  const deleteLead = useMutation({
    mutationFn: async (id: string) => {
      const { error, data } = await supabase
        .from("leads")
        .update({ deleted_at: new Date().toISOString() } as any)
        .eq("id", id)
        .is("deleted_at", null)
        .select("id");
      if (error) throw error;
      if (!data || data.length === 0) {
        throw new Error("Sem permissão para excluir (apenas Super Admin pode excluir leads).");
      }
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["superadmin", "leads"] });
      toast.success("Lead excluído");
    },
    onError: (e: any) => toast.error(e.message),
  });

  return { ...query, createLead, updateLead, deleteLead };
}

export function useLeadInteracoes(leadId: string | null) {
  return useQuery({
    queryKey: ["lead-interacoes", leadId],
    enabled: !!leadId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("lead_interacoes")
        .select("*")
        .eq("lead_id", leadId!)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return data || [];
    },
  });
}

export async function enviarWhatsAppSuperAdmin(params: {
  telefone: string; mensagem: string; lead_id?: string;
}) {
  const { data, error } = await supabase.functions.invoke("superadmin-whatsapp-send", { body: params });
  if (error) throw error;
  return data;
}
