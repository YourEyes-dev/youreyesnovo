/**
 * Motor de alertas de vencimento das férias (RF-009 do YE-DP-FERIAS-001).
 *
 * A varredura vive no banco (ferias_alertas_varrer): gera alerta em
 * D-90/60/30, sinaliza o dobro (art. 137) ao vencer o concessivo e, no
 * crítico, cria a ação no Plano de Ação. Aqui só disparamos a varredura,
 * lemos os alertas e geramos a ação sob demanda para os não-críticos.
 */
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useTenant } from "@/hooks/useTenant";
import { toast } from "sonner";

export interface FeriasAlerta {
  id: string;
  empresa_id: string | null;
  colaborador_nome: string | null;
  colaborador_cpf: string | null;
  aquisitivo_fim: string | null;
  concessivo_fim: string | null;
  dias_para_vencer: number | null;
  tipo: "concessivo_a_vencer" | "risco_dobro";
  faixa: "d90" | "d60" | "d30" | "vencido";
  severidade: "media" | "alta" | "critica";
  titulo: string;
  descricao: string | null;
  custo_estimado: number | null;
  plano_acao_id: string | null;
  resolvido: boolean;
}

export function useFeriasAlertas() {
  const { tenantId } = useTenant();
  const qc = useQueryClient();

  const alertasQuery = useQuery({
    queryKey: ["ferias-alertas", tenantId],
    enabled: !!tenantId,
    queryFn: async (): Promise<FeriasAlerta[]> => {
      const { data, error } = await fromTable("ferias_alertas")
        .select("*")
        .eq("tenant_id", tenantId)
        .eq("resolvido", false)
        .order("dias_para_vencer", { ascending: true });
      if (error) throw error;
      return (data || []) as FeriasAlerta[];
    },
  });

  // Dispara a varredura no banco (sob demanda). O agendamento diario faz o
  // mesmo sozinho; aqui e o "Atualizar agora".
  const varrer = useMutation({
    mutationFn: async (): Promise<number> => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const rpc = (supabase as any).rpc.bind(supabase);
      const { data, error } = await rpc("ferias_alertas_varrer", { p_tenant: tenantId });
      if (error) throw error;
      return Number(data ?? 0);
    },
    onSuccess: (novos) => {
      qc.invalidateQueries({ queryKey: ["ferias-alertas", tenantId] });
      toast.success(novos > 0 ? `${novos} novo(s) alerta(s) de vencimento.` : "Alertas atualizados.");
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : "Erro ao atualizar alertas"),
  });

  // Converte um alerta em ação no Plano de Ação (sob demanda, para os não
  // críticos — o crítico já nasce com ação).
  const gerarAcao = useMutation({
    mutationFn: async (alertaId: string): Promise<string | null> => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const rpc = (supabase as any).rpc.bind(supabase);
      const { data, error } = await rpc("ferias_alerta_gerar_acao", { p_alerta_id: alertaId });
      if (error) throw error;
      return (data as string) ?? null;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["ferias-alertas", tenantId] });
      toast.success("Ação criada no Plano de Ação.");
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : "Erro ao criar a ação"),
  });

  return {
    alertas: alertasQuery.data ?? [],
    isLoading: alertasQuery.isLoading,
    varrer,
    gerarAcao,
  };
}
