import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { fromTable, rpcUntyped } from "@/integrations/supabase/untypedClient";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";

export interface MapaPolitica {
  id: string;
  tenant_id: string;
  versao: number;
  titulo: string;
  texto_politica: string;
  texto_aviso: string;
  publicada: boolean;
  publicada_em: string | null;
  publicada_por_nome: string | null;
  updated_at: string;
}

export interface MapaCampanha {
  id: string;
  tenant_id: string;
  empresa_id: string | null;
  nome: string;
  descricao: string | null;
  publico: { tipo: string; usuario_ids?: string[] };
  status: "rascunho" | "ativa" | "encerrada";
  data_inicio: string | null;
  data_fim: string | null;
  instrumento_versao: number;
  criado_por_nome: string | null;
  created_at: string;
}

export interface Cobertura {
  convidados: number;
  respondidos: number;
  pct: number;
}

export interface CampanhaPendente {
  campanha_id: string;
  nome: string;
  data_fim: string | null;
  participacao_id: string;
}

// ── Política de uso / aviso (RF-001) ─────────────────────────────────────────
export function useMapaComportamentalPolitica() {
  const { tenantId, user, profile } = useAuth();
  const qc = useQueryClient();

  const { data: politica = null, isLoading } = useQuery({
    queryKey: ["mapa-comportamental", "politica", tenantId],
    queryFn: async (): Promise<MapaPolitica | null> => {
      if (!tenantId) return null;
      const { data, error } = await fromTable("mapa_comportamental_politicas")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("versao", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      return (data ?? null) as MapaPolitica | null;
    },
    enabled: !!tenantId,
  });

  const publicar = useMutation({
    mutationFn: async (input: { texto_politica: string; texto_aviso: string }) => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      const agora = new Date().toISOString();
      const base = {
        texto_politica: input.texto_politica,
        texto_aviso: input.texto_aviso,
        publicada: true,
        publicada_em: agora,
        publicada_por: user?.id ?? null,
        publicada_por_nome: profile?.nome_completo ?? null,
      };
      if (politica) {
        const { error } = await fromTable("mapa_comportamental_politicas").update(base).eq("id", politica.id);
        if (error) throw error;
      } else {
        const { error } = await fromTable("mapa_comportamental_politicas").insert({
          tenant_id: tenantId,
          versao: 1,
          ...base,
        });
        if (error) throw error;
      }
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["mapa-comportamental", "politica"] });
      toast.success("Política de uso publicada.");
    },
    onError: (e) => toast.error(`Não foi possível publicar: ${e.message}`),
  });

  return { politica, isLoading, publicar, politicaPublicada: !!politica?.publicada };
}

// ── Campanhas ────────────────────────────────────────────────────────────────
export function useMapaComportamentalCampanhas() {
  const { tenantId, user, profile } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const qc = useQueryClient();

  const { data: campanhas = [], isLoading } = useQuery({
    queryKey: ["mapa-comportamental", "campanhas", tenantId, empresaAtivaId],
    queryFn: async (): Promise<MapaCampanha[]> => {
      if (!tenantId) return [];
      let q = fromTable("mapa_comportamental_campanhas").select("*").eq("tenant_id", tenantId);
      if (empresaAtivaId) q = q.eq("empresa_id", empresaAtivaId);
      const { data, error } = await q.order("created_at", { ascending: false });
      if (error) throw error;
      return (data ?? []) as MapaCampanha[];
    },
    enabled: !!tenantId,
  });

  const criar = useMutation({
    mutationFn: async (input: {
      nome: string;
      descricao?: string;
      publico: { tipo: string; usuario_ids?: string[] };
      data_inicio?: string | null;
      data_fim?: string | null;
    }) => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      const { data, error } = await fromTable("mapa_comportamental_campanhas")
        .insert({
          tenant_id: tenantId,
          empresa_id: empresaAtivaId || null,
          nome: input.nome,
          descricao: input.descricao ?? null,
          publico: input.publico,
          status: "rascunho",
          data_inicio: input.data_inicio ?? null,
          data_fim: input.data_fim ?? null,
          instrumento_versao: 1,
          criado_por: user?.id ?? null,
          criado_por_nome: profile?.nome_completo ?? null,
        })
        .select("id")
        .single();
      if (error) throw error;
      return data.id as string;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["mapa-comportamental", "campanhas"] });
      toast.success("Campanha criada como rascunho.");
    },
    onError: (e) => toast.error(`Erro ao criar campanha: ${e.message}`),
  });

  const mudarStatus = useMutation({
    mutationFn: async (input: { id: string; status: "ativa" | "encerrada" | "rascunho" }) => {
      const { error } = await fromTable("mapa_comportamental_campanhas")
        .update({ status: input.status })
        .eq("id", input.id);
      if (error) throw error;
    },
    onSuccess: (_d, v) => {
      qc.invalidateQueries({ queryKey: ["mapa-comportamental", "campanhas"] });
      toast.success(v.status === "ativa" ? "Campanha ativada." : v.status === "encerrada" ? "Campanha encerrada." : "Campanha reaberta.");
    },
    // A trava RF-001 volta como erro do banco quando falta política publicada.
    onError: (e) => toast.error(e.message.includes("RF-001") || e.message.includes("política")
      ? "Publique a política de uso antes de ativar a campanha."
      : `Erro: ${e.message}`),
  });

  const gerarConvites = useMutation({
    mutationFn: async (campanhaId: string): Promise<number> => {
      const { data, error } = await rpcUntyped("mapa_comportamental_gerar_convites", { p_campanha_id: campanhaId });
      if (error) throw error;
      return (data as number) ?? 0;
    },
    onSuccess: (total) => {
      qc.invalidateQueries({ queryKey: ["mapa-comportamental", "cobertura"] });
      toast.success(`Convites gerados. ${total} colaborador(es) no público.`);
    },
    onError: (e) => toast.error(`Erro ao gerar convites: ${e.message}`),
  });

  return { campanhas, isLoading, criar, mudarStatus, gerarConvites };
}

// ── Cobertura de uma campanha ────────────────────────────────────────────────
export function useCoberturaCampanha(campanhaId: string | null, enabled = true) {
  const { tenantId } = useAuth();
  return useQuery({
    queryKey: ["mapa-comportamental", "cobertura", campanhaId],
    queryFn: async (): Promise<Cobertura> => {
      const { data, error } = await rpcUntyped("mapa_comportamental_cobertura", { p_campanha_id: campanhaId });
      if (error) throw error;
      return (data as Cobertura) ?? { convidados: 0, respondidos: 0, pct: 0 };
    },
    enabled: !!tenantId && !!campanhaId && enabled,
  });
}

// ── Minha campanha pendente (banner no Meu Mapa) ─────────────────────────────
export function useMinhaCampanhaPendente() {
  const { tenantId } = useAuth();
  return useQuery({
    queryKey: ["mapa-comportamental", "campanha-pendente", tenantId],
    queryFn: async (): Promise<CampanhaPendente | null> => {
      const { data, error } = await rpcUntyped("mapa_comportamental_minha_campanha_pendente", {});
      if (error) throw error;
      return (data ?? null) as CampanhaPendente | null;
    },
    enabled: !!tenantId,
  });
}
