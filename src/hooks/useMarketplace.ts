import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useTenant } from "./useTenant";
import { toast } from "sonner";

export interface MarketplaceCategoria {
  id: string;
  nome: string;
  descricao: string | null;
  icone: string | null;
  ordem: number;
  ativo: boolean;
}

export interface MarketplaceProfissional {
  id: string;
  user_id?: string | null;
  tenant_id?: string | null;
  nome_completo: string;
  email?: string | null;
  telefone?: string | null;
  foto_url: string | null;
  bio: string | null;
  formacao_academica: string | null;
  registro_profissional: string;
  conselho: string;
  uf_registro: string | null;
  registro_validade: string | null;
  certificacoes: string[] | null;
  especialidades: string[] | null;
  areas_atuacao: string[] | null;
  modalidades_atendimento: string[] | null;
  cidade: string | null;
  estado: string | null;
  status: string;
  plano: string;
  selo_verificado: boolean;
  nota_media: number;
  total_avaliacoes: number;
  total_servicos_executados: number;
  codigo_afiliado?: string | null;
  created_at: string;
}

export interface MarketplaceServico {
  id: string;
  profissional_id: string;
  categoria_id: string | null;
  nome: string;
  descricao: string;
  base_legal: string | null;
  modalidade: string;
  publico_alvo: string | null;
  evidencia_minima: string | null;
  preco_referencia: number | null;
  duracao_estimada_minutos: number | null;
  ativo: boolean;
  profissional?: MarketplaceProfissional;
  categoria?: MarketplaceCategoria;
}

export interface MarketplaceContratacao {
  id: string;
  tenant_id: string;
  servico_id: string;
  profissional_id: string;
  solicitante_nome: string | null;
  modalidade: string;
  data_agendamento: string | null;
  hora_agendamento: string | null;
  duracao_minutos: number | null;
  status: string;
  observacoes: string | null;
  valor: number | null;
  profissional_confirmou: boolean;
  data_conclusao: string | null;
  created_at: string;
  servico?: MarketplaceServico;
  profissional?: MarketplaceProfissional;
}

export interface MarketplaceFilters {
  categoria_id?: string;
  modalidade?: string;
  busca?: string;
  estado?: string;
  userLat?: number;
  userLng?: number;
  raioKm?: number;
}

const PROF_PUBLIC_COLS = "id, nome_completo, foto_url, bio, formacao_academica, registro_profissional, conselho, uf_registro, registro_validade, certificacoes, especialidades, areas_atuacao, modalidades_atendimento, cidade, estado, status, plano, selo_verificado, nota_media, total_avaliacoes, total_servicos_executados, tem_atestado_capacidade, latitude, longitude, created_at";

export function useMarketplace() {
  const { tenantId } = useTenant();
  const queryClient = useQueryClient();
  const [filters, setFilters] = useState<MarketplaceFilters>({});

  const { data: categorias = [] } = useQuery({
    queryKey: ["marketplace-categorias"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("marketplace_categorias")
        .select("*")
        .eq("ativo", true)
        .order("ordem");
      if (error) throw error;
      return data as MarketplaceCategoria[];
    },
  });

  const { data: servicos = [], isLoading: isLoadingServicos } = useQuery({
    queryKey: ["marketplace-servicos", tenantId, filters],
    queryFn: async () => {
      // Vitrine global: serviços de todos os profissionais ativos, sem filtro de tenant
      const { data: profsAtivos, error: profsError } = await supabase
        .from("marketplace_profissionais")
        .select("id")
        .eq("status", "ativo");

      if (profsError) throw profsError;
      const profissionalIds = (profsAtivos || []).map((p) => p.id);
      if (profissionalIds.length === 0) return [];

      let query = supabase
        .from("marketplace_servicos")
        .select(`*, profissional:marketplace_profissionais(${PROF_PUBLIC_COLS}), categoria:marketplace_categorias(*)`)
        .eq("ativo", true)
        .in("profissional_id", profissionalIds);

      if (filters.categoria_id) {
        query = query.eq("categoria_id", filters.categoria_id);
      }
      if (filters.modalidade) {
        query = query.eq("modalidade", filters.modalidade as "presencial" | "online" | "hibrido");
      }
      if (filters.busca) {
        query = query.or(`nome.ilike.%${filters.busca}%,descricao.ilike.%${filters.busca}%`);
      }

      const { data, error } = await query.order("created_at", { ascending: false });
      if (error) throw error;
      return (data ?? []) as unknown as MarketplaceServico[];
    },
    enabled: true,
  });

  const { data: profissionais = [], isLoading: isLoadingProfissionais } = useQuery({
    queryKey: ["marketplace-profissionais", filters],
    queryFn: async () => {
      // Vitrine global: profissionais aparecem para todas as empresas, sem filtro de tenant
      // If user location is available, use proximity search
      if (filters.userLat && filters.userLng) {
        const { data, error } = await supabase.rpc("buscar_profissionais_proximos_publico", {
          p_lat: filters.userLat,
          p_lon: filters.userLng,
          p_raio_km: filters.raioKm || 500,
        });
        if (error) throw error;
        let results = (data || []) as unknown as (MarketplaceProfissional & { distancia_km: number })[];

        if (filters.estado) {
          results = results.filter((p) => p.estado === filters.estado);
        }
        if (filters.busca) {
          const b = filters.busca.toLowerCase();
          results = results.filter(
            (p) =>
              p.nome_completo.toLowerCase().includes(b) ||
              p.especialidades?.some((e) => e.toLowerCase().includes(b))
          );
        }
        return results;
      }

      // Fallback: normal query (sem filtro de tenant — vitrine global)
      let query = supabase
        .from("marketplace_profissionais")
        .select(PROF_PUBLIC_COLS)
        .eq("status", "ativo");

      if (filters.estado) {
        query = query.eq("estado", filters.estado);
      }
      if (filters.busca) {
        query = query.or(`nome_completo.ilike.%${filters.busca}%,especialidades.cs.{${filters.busca}}`);
      }

      const { data, error } = await query
        .order("tem_atestado_capacidade", { ascending: false })
        .order("nota_media", { ascending: false });
      if (error) throw error;
      return (data ?? []) as unknown as MarketplaceProfissional[];
    },
    enabled: true,
  });

  const { data: contratacoes = [], isLoading: isLoadingContratacoes } = useQuery({
    queryKey: ["marketplace-contratacoes", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data, error } = await supabase
        .from("marketplace_contratacoes")
        .select(`*, servico:marketplace_servicos(*), profissional:marketplace_profissionais(${PROF_PUBLIC_COLS})`)
        .eq("tenant_id", tenantId)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return data as MarketplaceContratacao[];
    },
    enabled: !!tenantId,
  });

  const contratar = useMutation({
    mutationFn: async (data: {
      servico_id: string;
      profissional_id: string;
      modalidade: string;
      data_agendamento?: string;
      hora_agendamento?: string;
      observacoes?: string;
      valor?: number;
    }) => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      const { error } = await supabase.from("marketplace_contratacoes").insert({
        tenant_id: tenantId,
        servico_id: data.servico_id,
        profissional_id: data.profissional_id,
        modalidade: data.modalidade as "presencial" | "online" | "hibrido",
        data_agendamento: data.data_agendamento || null,
        hora_agendamento: data.hora_agendamento || null,
        observacoes: data.observacoes || null,
        valor: data.valor || null,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("Serviço solicitado com sucesso!");
      queryClient.invalidateQueries({ queryKey: ["marketplace-contratacoes"] });
    },
    onError: (err: Error) => toast.error(err.message),
  });

  return {
    categorias,
    servicos,
    profissionais,
    contratacoes,
    filters,
    setFilters,
    contratar,
    isLoadingServicos,
    isLoadingProfissionais,
    isLoadingContratacoes,
  };
}
