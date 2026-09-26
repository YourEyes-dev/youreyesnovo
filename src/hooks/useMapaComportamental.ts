import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { fromTable, rpcUntyped } from "@/integrations/supabase/untypedClient";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";
import {
  calcularMapa,
  MAPA_INSTRUMENTO_VERSAO,
  MAPA_ALGORITMO_VERSAO,
  type MapaRespostas,
  type MapaResultado,
} from "@/data/instrumentos/mapaComportamental";

const TABELA = "mapa_comportamental_respostas";

export interface MapaRespostaRow {
  id: string;
  tenant_id: string;
  empresa_id: string | null;
  auth_user_id: string | null;
  campanha_id: string | null;
  instrumento_versao: number;
  algoritmo_versao: string;
  status: "rascunho" | "concluido";
  respostas: MapaRespostas;
  resultado: MapaResultado | null;
  arquetipo: string | null;
  indice_consistencia: number | null;
  confiabilidade: "alta" | "baixa" | null;
  aviso_versao: string | null;
  aviso_aceite_em: string | null;
  tempo_total_segundos: number | null;
  concluido_em: string | null;
  vence_em: string | null;
  created_at: string;
  updated_at: string;
}

export interface PainelMapa {
  suprimido: boolean;
  total_concluidos: number;
  minimo_respondentes: number;
  distribuicao_arquetipos: Record<string, number>;
  consistencia_media: number | null;
  confiabilidade_baixa: number;
}

function calcularVenceEm(meses = 24): string {
  const d = new Date();
  d.setMonth(d.getMonth() + meses);
  return d.toISOString().slice(0, 10); // YYYY-MM-DD
}

export function useMapaComportamental() {
  const { tenantId, user } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const qc = useQueryClient();

  // ── Meu último mapa concluído + rascunho em aberto ─────────────────────────
  const { data: meusMapas = [], isLoading } = useQuery({
    queryKey: ["mapa-comportamental", "meus", tenantId, user?.id],
    queryFn: async (): Promise<MapaRespostaRow[]> => {
      if (!tenantId || !user?.id) return [];
      const { data, error } = await fromTable(TABELA)
        .select("*")
        .eq("tenant_id", tenantId)
        .eq("auth_user_id", user.id)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return (data ?? []) as MapaRespostaRow[];
    },
    enabled: !!tenantId && !!user?.id,
  });

  const rascunho = meusMapas.find((m) => m.status === "rascunho") ?? null;
  const mapaAtual = meusMapas.find((m) => m.status === "concluido") ?? null;

  // ── Salvar rascunho (pausa e retomada — RF-004) ────────────────────────────
  const salvarRascunho = useMutation({
    mutationFn: async (respostas: MapaRespostas) => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      if (rascunho) {
        const { error } = await fromTable(TABELA)
          .update({ respostas, updated_at: new Date().toISOString() })
          .eq("id", rascunho.id);
        if (error) throw error;
        return rascunho.id;
      }
      const { data, error } = await fromTable(TABELA)
        .insert({
          empresa_id: empresaAtivaId || null,
          instrumento_versao: MAPA_INSTRUMENTO_VERSAO,
          algoritmo_versao: MAPA_ALGORITMO_VERSAO,
          status: "rascunho",
          respostas,
        })
        .select("id")
        .single();
      if (error) throw error;
      return data.id as string;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["mapa-comportamental", "meus"] }),
    // Silencioso: autosave não deve poluir a tela com toasts.
    onError: (e) => console.error("Falha ao salvar rascunho do mapa:", e.message),
  });

  // ── Concluir (calcula, guarda e devolve o resultado ao titular — RF-005/006)
  const concluir = useMutation({
    mutationFn: async (input: {
      respostas: MapaRespostas;
      avisoVersao: string;
      tempoTotalSegundos: number;
      tempoPorItem?: Record<string, number>;
    }): Promise<MapaResultado> => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      const resultado = calcularMapa(input.respostas, {
        tempoTotalSegundos: input.tempoTotalSegundos,
      });
      const agora = new Date().toISOString();
      const payload = {
        empresa_id: empresaAtivaId || null,
        instrumento_versao: resultado.instrumentoVersao,
        algoritmo_versao: resultado.algoritmoVersao,
        status: "concluido" as const,
        respostas: input.respostas,
        resultado,
        arquetipo: resultado.arquetipos.join("-"),
        indice_consistencia: resultado.indiceConsistencia,
        confiabilidade: resultado.confiabilidade,
        aviso_versao: input.avisoVersao,
        aviso_aceite_em: agora,
        tempo_total_segundos: input.tempoTotalSegundos,
        tempo_por_item: input.tempoPorItem ?? null,
        concluido_em: agora,
        vence_em: calcularVenceEm(24),
      };
      if (rascunho) {
        const { error } = await fromTable(TABELA).update(payload).eq("id", rascunho.id);
        if (error) throw error;
      } else {
        const { error } = await fromTable(TABELA).insert(payload);
        if (error) throw error;
      }
      return resultado;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["mapa-comportamental", "meus"] });
      toast.success("Mapa concluído! Veja o seu resultado.");
    },
    onError: (e) => toast.error(`Não foi possível concluir: ${e.message}`),
  });

  return {
    meusMapas,
    mapaAtual,
    rascunho,
    isLoading,
    salvarRascunho,
    concluir,
  };
}

/**
 * Painel do RH/gestor: agregados com supressão por baixo N (RN-011).
 * Lê via RPC SECURITY DEFINER que confere perfil_permite_modulo internamente.
 */
export function useMapaComportamentalPainel(enabled: boolean) {
  const { tenantId } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();

  return useQuery({
    queryKey: ["mapa-comportamental", "painel", tenantId, empresaAtivaId],
    queryFn: async (): Promise<PainelMapa | null> => {
      const { data, error } = await rpcUntyped("mapa_comportamental_painel", {
        p_empresa_id: empresaAtivaId || null,
      });
      if (error) throw error;
      return (data ?? null) as PainelMapa | null;
    },
    enabled: !!tenantId && enabled,
  });
}
