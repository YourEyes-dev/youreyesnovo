import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";
import { handleMutationError } from "@/lib/toastError";

/** Estados do ciclo de vida da compensação de falta (RQ-047/048). */
export type CompensacaoFaltaStatus =
  | "pendente_autorizacao"
  | "pendente_homologacao"
  | "autorizada"
  | "efetivada"
  | "recusada"
  | "cancelada";

export interface CompensacaoFalta {
  id: string;
  tenant_id: string;
  empresa_id: string | null;
  colaborador_cpf: string;
  colaborador_id: string | null;
  data_falta: string;
  minutos: number;
  acordo_id: string | null;
  regime_id: string | null;
  prazo_compensacao_dias: number | null;
  prazo_ate: string | null;
  status: CompensacaoFaltaStatus;
  motivo: string | null;
  autorizado_por_nome: string | null;
  autorizado_em: string | null;
  homologado_por_nome: string | null;
  homologado_em: string | null;
  ciencia_em: string | null;
  ciencia_por: string | null;
  movimentacao_id: string | null;
  created_at: string;
}

/** Resultado da trava de leitura ponto_falta_compensavel. */
export interface FaltaCompensavel {
  compensavel: boolean;
  competencia: string;
  data_falta: string;
  status_dia: string | null;
  jornada_min: number;
  regime_id: string | null;
  prazo_compensacao_dias: number | null;
  acordo_id: string | null;
  motivos: string[];
}

const ultimoDiaDoMes = (competencia: string) => {
  const [y, m] = competencia.split("-").map(Number);
  const dia = new Date(y, m, 0).getDate(); // m (1-based) com dia 0 => último dia do mês m
  return `${y}-${String(m).padStart(2, "0")}-${String(dia).padStart(2, "0")}`;
};

export function useCompensacaoFalta() {
  const { tenantId } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const qc = useQueryClient();

  const invalidar = () => {
    qc.invalidateQueries({ queryKey: ["ponto-compensacao-falta"] });
    // O débito entra no banco na ciência: recarrega o banco de horas também.
    qc.invalidateQueries({ queryKey: ["ponto-banco-horas"] });
  };

  /** Compensações da competência (por data_falta dentro do mês). */
  const useCompensacoes = (competencia: string) =>
    useQuery({
      queryKey: ["ponto-compensacao-falta", tenantId, competencia, empresaAtivaId],
      queryFn: async (): Promise<CompensacaoFalta[]> => {
        if (!tenantId || !competencia) return [];
        let q = fromTable("ponto_compensacao_falta")
          .select("*")
          .eq("tenant_id", tenantId)
          .gte("data_falta", `${competencia}-01`)
          .lte("data_falta", ultimoDiaDoMes(competencia));
        if (empresaAtivaId) q = q.or(`empresa_id.eq.${empresaAtivaId},empresa_id.is.null`);
        const { data, error } = (await q.order("data_falta", { ascending: false })) as {
          data: CompensacaoFalta[] | null;
          error: Error | null;
        };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId && !!competencia,
    });

  /** Faltas da competência (candidatas a compensação). */
  const useFaltasDaCompetencia = (competencia: string) =>
    useQuery({
      queryKey: ["ponto-faltas-competencia", tenantId, competencia, empresaAtivaId],
      queryFn: async () => {
        if (!tenantId || !competencia) return [] as any[];
        let q = fromTable("ponto_diario")
          .select("data, colaborador_cpf, colaborador_nome, colaborador_id")
          .eq("tenant_id", tenantId)
          .eq("status", "falta")
          .gte("data", `${competencia}-01`)
          .lte("data", ultimoDiaDoMes(competencia));
        if (empresaAtivaId) q = q.eq("empresa_id", empresaAtivaId);
        const { data, error } = (await q.order("data", { ascending: false })) as {
          data: any[] | null;
          error: Error | null;
        };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId && !!competencia,
    });

  /** Trava: a falta do dia é compensável? (somente leitura) */
  const verificarCompensavel = async (
    colaboradorCpf: string,
    data: string
  ): Promise<FaltaCompensavel> => {
    if (!tenantId) throw new Error("Não autenticado");
    const { data: res, error } = await (supabase.rpc as any)("ponto_falta_compensavel", {
      p_tenant_id: tenantId,
      p_colaborador_cpf: colaboradorCpf,
      p_data: data,
    });
    if (error) throw error;
    return res as FaltaCompensavel;
  };

  const registrar = useMutation({
    mutationFn: async (v: { colaboradorCpf: string; data: string; motivo?: string }) => {
      if (!tenantId) throw new Error("Não autenticado");
      const { data: res, error } = await (supabase.rpc as any)("ponto_registrar_compensacao_falta", {
        p_tenant_id: tenantId,
        p_colaborador_cpf: v.colaboradorCpf,
        p_data: v.data,
        p_motivo: v.motivo ?? null,
      });
      if (error) throw error;
      if (res && res.success === false) throw new Error(res.motivo || "Falta não é compensável.");
      return res;
    },
    onSuccess: () => {
      invalidar();
      toast.success("Compensação registrada — aguardando autorização.");
    },
    onError: handleMutationError,
  });

  const autorizar = useMutation({
    mutationFn: async (v: { id: string; nome?: string }) => {
      if (!tenantId) throw new Error("Não autenticado");
      const { data: res, error } = await (supabase.rpc as any)("ponto_autorizar_compensacao_falta", {
        p_tenant_id: tenantId,
        p_id: v.id,
        p_autorizado_por_nome: v.nome ?? null,
      });
      if (error) throw error;
      if (res && res.success === false) throw new Error(res.motivo || "Não foi possível autorizar.");
      return res;
    },
    onSuccess: (res: any) => {
      invalidar();
      toast.success(res?.exige_homologacao ? "Autorizada — aguardando homologação do RH." : "Compensação autorizada.");
    },
    onError: handleMutationError,
  });

  const homologar = useMutation({
    mutationFn: async (v: { id: string; nome?: string }) => {
      if (!tenantId) throw new Error("Não autenticado");
      const { data: res, error } = await (supabase.rpc as any)("ponto_homologar_compensacao_falta", {
        p_tenant_id: tenantId,
        p_id: v.id,
        p_homologado_por_nome: v.nome ?? null,
      });
      if (error) throw error;
      if (res && res.success === false) throw new Error(res.motivo || "Não foi possível homologar.");
      return res;
    },
    onSuccess: () => {
      invalidar();
      toast.success("Compensação homologada pelo RH.");
    },
    onError: handleMutationError,
  });

  const darCiencia = useMutation({
    mutationFn: async (v: { id: string; por?: string }) => {
      if (!tenantId) throw new Error("Não autenticado");
      const { data: res, error } = await (supabase.rpc as any)("ponto_dar_ciencia_compensacao_falta", {
        p_tenant_id: tenantId,
        p_id: v.id,
        p_ciencia_por: v.por ?? null,
      });
      if (error) throw error;
      if (res && res.success === false) throw new Error(res.motivo || "Não foi possível registrar a ciência.");
      return res;
    },
    onSuccess: () => {
      invalidar();
      toast.success("Ciência registrada — débito lançado no banco de horas.");
    },
    onError: handleMutationError,
  });

  const cancelar = useMutation({
    mutationFn: async (v: { id: string; motivo?: string }) => {
      if (!tenantId) throw new Error("Não autenticado");
      const { data: res, error } = await (supabase.rpc as any)("ponto_cancelar_compensacao_falta", {
        p_tenant_id: tenantId,
        p_id: v.id,
        p_motivo: v.motivo ?? null,
      });
      if (error) throw error;
      if (res && res.success === false) throw new Error(res.motivo || "Não foi possível cancelar.");
      return res;
    },
    onSuccess: () => {
      invalidar();
      toast.success("Compensação cancelada.");
    },
    onError: handleMutationError,
  });

  return {
    useCompensacoes,
    useFaltasDaCompetencia,
    verificarCompensavel,
    registrar,
    autorizar,
    homologar,
    darCiencia,
    cancelar,
  };
}
