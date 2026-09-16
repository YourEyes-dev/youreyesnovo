/**
 * Férias coletivas (RF-007 / arts. 139-141). O banco valida os limites
 * (mín. 10 dias, máx. 2 períodos/ano por setor), abre os comunicados com o
 * prazo de 15 dias e trata o art. 140 (novatos proporcionais). Aqui: listar,
 * programar, listar afetados, e gerar/arquivar os comunicados.
 */
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useTenant } from "@/hooks/useTenant";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";

export interface FeriasColetiva {
  id: string;
  empresa_id: string | null;
  ano: number;
  departamento: string;
  p1_inicio: string;
  p1_fim: string;
  p2_inicio: string | null;
  p2_fim: string | null;
  estado: "rascunho" | "programado" | "comunicado" | "concluido" | "cancelado";
  observacao: string | null;
}

export interface ColetivaAfetado {
  colaborador_cpf: string;
  colaborador_nome: string;
  data_admissao: string;
  meses_de_casa: number;
  art_140: boolean;
  dias_proporcionais: number;
}

export interface ColetivaComunicado {
  id: string;
  destino: "mte" | "sindicato" | "empregados";
  prazo_limite: string;
  status: "pendente" | "gerado" | "protocolado";
  documento_id: string | null;
}

export interface NovaColetiva {
  departamento: string;
  ano: number;
  p1_inicio: string;
  p1_fim: string;
  p2_inicio?: string | null;
  p2_fim?: string | null;
  observacao?: string;
}

export function useFeriasColetivas() {
  const { tenantId } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();
  const qc = useQueryClient();

  const coletivasQuery = useQuery({
    queryKey: ["ferias-coletivas", tenantId, empresaAtivaId],
    enabled: !!tenantId,
    queryFn: async (): Promise<FeriasColetiva[]> => {
      let q = fromTable("ferias_coletivas").select("*").eq("tenant_id", tenantId);
      if (empresaAtivaId) q = q.eq("empresa_id", empresaAtivaId);
      const { data, error } = await q.order("created_at", { ascending: false });
      if (error) throw error;
      return (data || []) as FeriasColetiva[];
    },
  });

  const programar = useMutation({
    mutationFn: async (nova: NovaColetiva): Promise<string> => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      const { data, error } = await fromTable("ferias_coletivas")
        .insert({
          tenant_id: tenantId,
          empresa_id: empresaAtivaId || null,
          ano: nova.ano,
          departamento: nova.departamento,
          p1_inicio: nova.p1_inicio,
          p1_fim: nova.p1_fim,
          p2_inicio: nova.p2_inicio || null,
          p2_fim: nova.p2_fim || null,
          observacao: nova.observacao || null,
          estado: "rascunho",
        } as Record<string, unknown>)
        .select("id")
        .single();
      if (error) throw error;
      // Abre os comunicados (MTE, sindicato, empregados) com prazo de 15 dias.
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const rpc = (supabase as any).rpc.bind(supabase);
      await rpc("ferias_coletiva_abrir_comunicados", { p_coletiva: (data as { id: string }).id });
      return (data as { id: string }).id;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["ferias-coletivas", tenantId] });
      toast.success("Férias coletivas programadas e comunicados abertos.");
    },
    onError: (e: unknown) => {
      const msg = e instanceof Error ? e.message : "Erro ao programar";
      // As validações do banco chegam como mensagem amigável (art. 139).
      toast.error(msg);
    },
  });

  const useAfetados = (coletivaId: string | null) =>
    useQuery({
      queryKey: ["ferias-coletiva-afetados", coletivaId],
      enabled: !!coletivaId,
      queryFn: async (): Promise<ColetivaAfetado[]> => {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const rpc = (supabase as any).rpc.bind(supabase);
        const { data, error } = await rpc("ferias_coletiva_afetados", { p_coletiva: coletivaId });
        if (error) throw error;
        return (data || []) as ColetivaAfetado[];
      },
    });

  const useComunicados = (coletivaId: string | null) =>
    useQuery({
      queryKey: ["ferias-coletiva-comunicados", coletivaId],
      enabled: !!coletivaId,
      queryFn: async (): Promise<ColetivaComunicado[]> => {
        const { data, error } = await fromTable("ferias_coletivas_comunicados")
          .select("*")
          .eq("coletiva_id", coletivaId)
          .order("destino", { ascending: true });
        if (error) throw error;
        return (data || []) as ColetivaComunicado[];
      },
    });

  return {
    coletivas: coletivasQuery.data ?? [],
    isLoading: coletivasQuery.isLoading,
    programar,
    useAfetados,
    useComunicados,
    qc,
  };
}
