import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";
import { format } from "date-fns";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { datasAoRegistrarRitual } from "@/lib/celebracoes";
import type { CulturaData, CulturaAcao, CulturaRitual, CulturaConfig, CulturaMarco, CulturaPreferencia } from "@/types/cultura";

export function useCultura() {
  const { tenantId } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const qc = useQueryClient();

  // --- Datas configuráveis ---
  const { data: datas = [], isLoading: isLoadingDatas } = useQuery({
    queryKey: ["cultura-datas", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      let query = supabase
        .from("cultura_datas")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("mes", { ascending: true });
      if (empresaAtivaId) query = query.eq("empresa_id", empresaAtivaId);
      const { data, error } = await query;
      if (error) throw error;
      return data as CulturaData[];
    },
    enabled: !!tenantId,
  });

  const createData = async (payload: Partial<CulturaData>) => {
    if (!tenantId) return;
    const { error } = await supabase.from("cultura_datas").insert({ ...payload, tenant_id: tenantId, empresa_id: empresaAtivaId || null } as any);
    if (error) { toast.error("Erro ao criar data"); throw error; }
    toast.success("Data criada!");
    qc.invalidateQueries({ queryKey: ["cultura-datas"] });
  };

  const deleteData = async (id: string) => {
    const { error } = await supabase.from("cultura_datas").delete().eq("id", id);
    if (error) { toast.error("Erro ao excluir"); throw error; }
    toast.success("Data removida");
    qc.invalidateQueries({ queryKey: ["cultura-datas"] });
  };

  // --- Ações ---
  const { data: acoes = [], isLoading: isLoadingAcoes } = useQuery({
    queryKey: ["cultura-acoes", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      let query = supabase
        .from("cultura_acoes")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("data_referencia", { ascending: true });
      if (empresaAtivaId) query = query.eq("empresa_id", empresaAtivaId);
      const { data, error } = await query;
      if (error) throw error;
      return data as CulturaAcao[];
    },
    enabled: !!tenantId,
  });

  const createAcao = async (payload: Partial<CulturaAcao>) => {
    if (!tenantId) return;
    const { error } = await supabase.from("cultura_acoes").insert({ ...payload, tenant_id: tenantId, empresa_id: empresaAtivaId || null } as any);
    if (error) { toast.error("Erro ao criar ação"); throw error; }
    toast.success("Ação criada!");
    qc.invalidateQueries({ queryKey: ["cultura-acoes"] });
  };

  const updateAcaoStatus = async (id: string, status: string) => {
    const { error } = await supabase.from("cultura_acoes").update({ status }).eq("id", id);
    if (error) { toast.error("Erro ao atualizar"); throw error; }
    toast.success("Status atualizado");
    qc.invalidateQueries({ queryKey: ["cultura-acoes"] });
  };

  /**
   * Celebrar em 1 toque: cria a ação já concluída (ou conclui a existente).
   * Devolve a função que desfaz — o chamador oferece o "Desfazer" por alguns segundos.
   */
  const parabenizar = async (payload: Partial<CulturaAcao>, existente?: CulturaAcao): Promise<() => Promise<void>> => {
    if (!tenantId) return async () => {};
    const hoje = format(new Date(), "yyyy-MM-dd");
    const refrescar = () => qc.invalidateQueries({ queryKey: ["cultura-acoes"] });
    if (existente) {
      const { error } = await supabase
        .from("cultura_acoes")
        .update({ status: "concluida", data_execucao: hoje })
        .eq("id", existente.id);
      if (error) { toast.error("Erro ao celebrar"); throw error; }
      refrescar();
      return async () => {
        await supabase
          .from("cultura_acoes")
          .update({ status: existente.status, data_execucao: existente.data_execucao })
          .eq("id", existente.id);
        refrescar();
      };
    }
    const { data, error } = await fromTable("cultura_acoes")
      .insert({ ...payload, status: "concluida", data_execucao: hoje, tenant_id: tenantId, empresa_id: empresaAtivaId || null })
      .select("id")
      .single();
    if (error) { toast.error("Erro ao celebrar"); throw error; }
    refrescar();
    return async () => {
      await supabase.from("cultura_acoes").delete().eq("id", data.id);
      refrescar();
    };
  };

  const deleteAcao = async (id: string) => {
    const { error } = await supabase.from("cultura_acoes").delete().eq("id", id);
    if (error) { toast.error("Erro ao excluir"); throw error; }
    toast.success("Ação removida");
    qc.invalidateQueries({ queryKey: ["cultura-acoes"] });
  };

  // --- Rituais ---
  const { data: rituais = [], isLoading: isLoadingRituais } = useQuery({
    queryKey: ["cultura-rituais", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      let query = supabase
        .from("cultura_rituais")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("nome");
      if (empresaAtivaId) query = query.eq("empresa_id", empresaAtivaId);
      const { data, error } = await query;
      if (error) throw error;
      return data as CulturaRitual[];
    },
    enabled: !!tenantId,
  });

  const createRitual = async (payload: Partial<CulturaRitual>) => {
    if (!tenantId) return;
    const { error } = await supabase.from("cultura_rituais").insert({ ...payload, tenant_id: tenantId, empresa_id: empresaAtivaId || null } as any);
    if (error) { toast.error("Erro ao criar ritual"); throw error; }
    toast.success("Ritual criado!");
    qc.invalidateQueries({ queryKey: ["cultura-rituais"] });
  };

  const toggleRitual = async (id: string, ativo: boolean) => {
    const { error } = await supabase.from("cultura_rituais").update({ ativo }).eq("id", id);
    if (error) { toast.error("Erro"); throw error; }
    qc.invalidateQueries({ queryKey: ["cultura-rituais"] });
  };

  const deleteRitual = async (id: string) => {
    const { error } = await supabase.from("cultura_rituais").delete().eq("id", id);
    if (error) { toast.error("Erro ao excluir"); throw error; }
    toast.success("Ritual removido");
    qc.invalidateQueries({ queryKey: ["cultura-rituais"] });
  };

  const registrarRealizacaoRitual = async (r: CulturaRitual) => {
    const { error } = await supabase
      .from("cultura_rituais")
      .update(datasAoRegistrarRitual(r.frequencia))
      .eq("id", r.id);
    if (error) { toast.error("Erro ao registrar realização"); throw error; }
    toast.success("Realização registrada");
    qc.invalidateQueries({ queryKey: ["cultura-rituais"] });
  };

  // --- Config ---
  const { data: config } = useQuery({
    queryKey: ["cultura-config", tenantId],
    queryFn: async () => {
      if (!tenantId) return null;
      const { data, error } = await supabase
        .from("cultura_config")
        .select("*")
        .eq("tenant_id", tenantId)
        .maybeSingle();
      if (error) throw error;
      return data as CulturaConfig | null;
    },
    enabled: !!tenantId,
  });

  const saveConfig = async (payload: Partial<CulturaConfig>) => {
    if (!tenantId) return;
    if (config?.id) {
      const { error } = await supabase.from("cultura_config").update(payload as any).eq("id", config.id);
      if (error) { toast.error("Erro"); throw error; }
    } else {
      const { error } = await supabase.from("cultura_config").insert({ ...payload, tenant_id: tenantId } as any);
      if (error) { toast.error("Erro"); throw error; }
    }
    toast.success("Configuração salva!");
    qc.invalidateQueries({ queryKey: ["cultura-config"] });
  };

  // --- Marcos ---
  const { data: marcos = [] } = useQuery({
    queryKey: ["cultura-marcos", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data, error } = await supabase
        .from("cultura_marcos")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("anos");
      if (error) throw error;
      return data as CulturaMarco[];
    },
    enabled: !!tenantId,
  });

  const createMarco = async (payload: Partial<CulturaMarco>) => {
    if (!tenantId) return;
    const { error } = await supabase.from("cultura_marcos").insert({ ...payload, tenant_id: tenantId } as any);
    if (error) { toast.error("Erro ao criar marco"); throw error; }
    toast.success("Marco criado!");
    qc.invalidateQueries({ queryKey: ["cultura-marcos"] });
  };

  // --- Preferências ---
  const { data: preferencias = [] } = useQuery({
    queryKey: ["cultura-preferencias", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data, error } = await supabase
        .from("cultura_preferencias")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("colaborador_nome");
      if (error) throw error;
      return data as CulturaPreferencia[];
    },
    enabled: !!tenantId,
  });

  const createPreferencia = async (payload: Partial<CulturaPreferencia>) => {
    if (!tenantId) return;
    const { error } = await supabase.from("cultura_preferencias").insert({ ...payload, tenant_id: tenantId } as any);
    if (error) { toast.error("Erro ao salvar preferência"); throw error; }
    toast.success("Preferência salva!");
    qc.invalidateQueries({ queryKey: ["cultura-preferencias"] });
  };

  const deletePreferencia = async (id: string) => {
    const { error } = await supabase.from("cultura_preferencias").delete().eq("id", id);
    if (error) { toast.error("Erro ao excluir"); throw error; }
    toast.success("Preferência removida");
    qc.invalidateQueries({ queryKey: ["cultura-preferencias"] });
  };

  // Stats
  const acoesPendentes = acoes.filter(a => a.status === "pendente").length;
  const acoesConcluidas = acoes.filter(a => a.status === "concluida").length;
  const rituaisAtivos = rituais.filter(r => r.ativo).length;
  const datasAtivas = datas.filter(d => d.ativo).length;

  return {
    datas, isLoadingDatas, createData, deleteData,
    acoes, isLoadingAcoes, createAcao, updateAcaoStatus, deleteAcao, parabenizar,
    rituais, isLoadingRituais, createRitual, toggleRitual, deleteRitual, registrarRealizacaoRitual,
    config, saveConfig,
    marcos, createMarco,
    preferencias, createPreferencia, deletePreferencia,
    acoesPendentes, acoesConcluidas, rituaisAtivos, datasAtivas,
  };
}
