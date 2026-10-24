import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useTenant } from "./useTenant";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";

export interface DashboardKPIData {
  colaboradoresAtivos: number;
  admissoesPendentes: number;
  episBaixoEstoque: number;
  documentosPendentes: number;
  avaliacoesPendentes: number;
  metasAtivas: number;
  ouvidoriaPendente: number;
  riscosAtivos: number;
}

export const useDashboardKPIs = () => {
  const { tenant } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();

  return useQuery({
    queryKey: ["dashboard-kpis", tenant?.id, empresaAtivaId],
    queryFn: async (): Promise<DashboardKPIData> => {
      if (!tenant?.id) throw new Error("Tenant não encontrado");

      const empresaFilter = empresaAtivaId ? { empresa_id: empresaAtivaId } : {};

      // Totais de colaboradores/admissões vêm de uma função do banco (só números, sem dado pessoal).
      const contagensP = (supabase.rpc as any)("admissoes_contagens", { p_empresa_id: empresaAtivaId ?? null })
        .then((r: any) => (r?.data ?? {}) as { concluidos?: number; pendentes?: number });

      const [
        colaboradoresRes,
        admissoesRes,
        episRes,
        docsRes,
        avalsRes,
        metasRes,
        ouvidoriaRes,
        riscosRes,
      ] = await Promise.all([
        // Colaboradores ativos (admissões com status concluído)
        contagensP.then((c: any) => ({ count: c.concluidos ?? 0 })),

        // Admissões pendentes
        contagensP.then((c: any) => ({ count: c.pendentes ?? 0 })),

        // EPIs com estoque baixo
        supabase
          .from("epis")
          .select("id, quantidade_estoque, quantidade_minima")
          .eq("tenant_id", tenant.id)
          .match(empresaFilter),

        // Documentos pendentes
        supabase
          .from("admissao_documentos")
          .select("id", { count: "exact", head: true })
          .eq("tenant_id", tenant.id)
          .eq("status", "pendente"),

        // Avaliações pendentes
        supabase
          .from("avaliacao_respostas")
          .select("id", { count: "exact", head: true })
          .eq("tenant_id", tenant.id)
          .eq("status", "pendente"),

        // Metas ativas
        supabase
          .from("metas")
          .select("id", { count: "exact", head: true })
          .eq("tenant_id", tenant.id)
          .eq("status", "em_andamento"),

        // Ouvidoria pendente
        supabase
          .from("ouvidoria")
          .select("id", { count: "exact", head: true })
          .eq("tenant_id", tenant.id)
          .eq("status", "pendente"),

        // Riscos ergonômicos ativos
        supabase
          .from("ergonomia_riscos")
          .select("id", { count: "exact", head: true })
          .eq("tenant_id", tenant.id)
          .eq("ativo", true),
      ]);

      const episData = episRes.data || [];
      const episBaixoEstoque = episData.filter(
        (e) => e.quantidade_estoque <= e.quantidade_minima
      ).length;

      return {
        colaboradoresAtivos: colaboradoresRes.count || 0,
        admissoesPendentes: admissoesRes.count || 0,
        episBaixoEstoque,
        documentosPendentes: docsRes.count || 0,
        avaliacoesPendentes: avalsRes.count || 0,
        metasAtivas: metasRes.count || 0,
        ouvidoriaPendente: ouvidoriaRes.count || 0,
        riscosAtivos: riscosRes.count || 0,
      };
    },
    enabled: !!tenant?.id,
    staleTime: 1000 * 60 * 5,
  });
};
