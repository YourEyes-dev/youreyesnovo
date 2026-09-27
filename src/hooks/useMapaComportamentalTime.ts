import { useQuery } from "@tanstack/react-query";
import { fromTable, rpcUntyped } from "@/integrations/supabase/untypedClient";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import type { MapaResultado } from "@/data/instrumentos/mapaComportamental";

export interface TimeMembro {
  mapa_id: string;
  nome: string | null;
  arquetipo: string | null;
  confiabilidade: "alta" | "baixa" | null;
  concluido_em: string | null;
}

export interface FichaMapa {
  id: string;
  colaborador_nome: string | null;
  arquetipo: string | null;
  confiabilidade: "alta" | "baixa" | null;
  concluido_em: string | null;
  vence_em: string | null;
  resultado: MapaResultado | null;
}

export interface AcessoMapa {
  acessado_por_nome: string | null;
  acessado_em: string;
}

/** Composição do time (mapas concluídos do tenant/empresa) — gestor/RH. */
export function useMapaTime(enabled: boolean) {
  const { tenantId } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  return useQuery({
    queryKey: ["mapa-comportamental", "time", tenantId, empresaAtivaId],
    queryFn: async (): Promise<TimeMembro[]> => {
      const { data, error } = await rpcUntyped("mapa_comportamental_time", { p_empresa_id: empresaAtivaId || null });
      if (error) throw error;
      return (data ?? []) as TimeMembro[];
    },
    enabled: !!tenantId && enabled,
  });
}

/**
 * Ficha da pessoa: lê o mapa de terceiro via RPC (registra o acesso — RF-013 —
 * e NÃO traz respostas item a item — RN-003).
 */
export function useVerMapa(mapaId: string | null) {
  const { tenantId } = useAuth();
  return useQuery({
    queryKey: ["mapa-comportamental", "ver-mapa", mapaId],
    queryFn: async (): Promise<FichaMapa | null> => {
      const { data, error } = await rpcUntyped("mapa_comportamental_ver_mapa", { p_mapa_id: mapaId });
      if (error) throw error;
      return (data ?? null) as FichaMapa | null;
    },
    enabled: !!tenantId && !!mapaId,
    staleTime: 5 * 60 * 1000, // evita relogar o acesso a cada re-render
  });
}

/**
 * Desdobramento (RF-012 / indicador-chave do doc): quantos mapas viraram ação
 * no Plano de Ação. Conta origem_id distintos das ações com origem no módulo.
 */
export function useDesdobramento(enabled: boolean) {
  const { tenantId } = useAuth();
  return useQuery({
    queryKey: ["mapa-comportamental", "desdobramento", tenantId],
    queryFn: async (): Promise<number> => {
      const { data, error } = await fromTable("plano_acoes")
        .select("origem_id")
        .eq("tenant_id", tenantId)
        .eq("origem_modulo", "mapa_comportamental");
      if (error) throw error;
      const ids = new Set(
        ((data ?? []) as { origem_id: string | null }[])
          .map((r) => r.origem_id)
          .filter((v): v is string => !!v),
      );
      return ids.size;
    },
    enabled: !!tenantId && enabled,
  });
}

/** Quem acessou o meu mapa (transparência ao titular — CA-009). */
export function useMeusAcessos() {
  const { tenantId, user } = useAuth();
  return useQuery({
    queryKey: ["mapa-comportamental", "meus-acessos", tenantId, user?.id],
    queryFn: async (): Promise<AcessoMapa[]> => {
      const { data, error } = await rpcUntyped("mapa_comportamental_meus_acessos", {});
      if (error) throw error;
      return (data ?? []) as AcessoMapa[];
    },
    enabled: !!tenantId && !!user?.id,
  });
}
