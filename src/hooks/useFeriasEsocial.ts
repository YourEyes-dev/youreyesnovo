/**
 * eSocial de férias (RF-008): gera, valida e registra os eventos S-2230,
 * S-1200 e S-1210 a partir de um cálculo de férias. O ENVIO real (assinatura
 * + SOAP) é passo seguinte, fora daqui. Sob demanda.
 */
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useTenant } from "@/hooks/useTenant";
import { toast } from "sonner";

export interface EsocialEvento {
  id: string;
  tipo_evento: string;
  status: string;
  competencia: string | null;
  motivo_afastamento: string | null;
  mensagem_retorno: string | null;
  codigo_retorno: string | null;
  xml_enviado: string | null;
}

export function useFeriasEsocial(calculoId: string | null) {
  const { tenantId } = useTenant();
  const qc = useQueryClient();

  const eventosQuery = useQuery({
    queryKey: ["ferias-esocial", calculoId],
    enabled: !!calculoId && !!tenantId,
    queryFn: async (): Promise<EsocialEvento[]> => {
      const { data, error } = await fromTable("esocial_transmissoes")
        .select("*")
        .eq("tenant_id", tenantId)
        .eq("ferias_calculo_id", calculoId)
        .order("tipo_evento", { ascending: true });
      if (error) throw error;
      return (data || []) as EsocialEvento[];
    },
  });

  const gerar = useMutation({
    mutationFn: async (): Promise<number> => {
      if (!calculoId) throw new Error("Cálculo não informado");
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const rpc = (supabase as any).rpc.bind(supabase);
      const { data, error } = await rpc("ferias_esocial_gerar", { p_calculo: calculoId });
      if (error) throw error;
      return Number(data ?? 0);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["ferias-esocial", calculoId] });
      toast.success("Eventos do eSocial gerados (prontos para conferência).");
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : "Erro ao gerar eventos"),
  });

  return { eventos: eventosQuery.data ?? [], isLoading: eventosQuery.isLoading, gerar };
}
