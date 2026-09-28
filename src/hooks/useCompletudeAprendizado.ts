import { useQuery } from "@tanstack/react-query";
import { useAuth } from "@/hooks/useAuth";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { calcularCompletude, type CompletudeResultado } from "@/lib/completudeFuncao";

interface CargoMini {
  id: string;
  objetivo_funcao?: string | null;
}

/**
 * Completude por cargo para o módulo Aprendizado & Papéis (O1-A).
 * Faz as contagens tenant-wide uma vez e devolve um mapa cargo_id -> resultado.
 * Somente leitura; a lógica de pontuação vive na função pura `calcularCompletude`.
 */
export function useCompletudeCargos(cargos: CargoMini[]): {
  completudePorCargo: Record<string, CompletudeResultado>;
  isLoading: boolean;
} {
  const { tenantId } = useAuth();

  const contar = (rows: { cargo_id: string }[] | null | undefined) => {
    const m: Record<string, number> = {};
    (rows || []).forEach((r) => { m[r.cargo_id] = (m[r.cargo_id] || 0) + 1; });
    return m;
  };

  const { data: atividades = {}, isLoading: l1 } = useQuery({
    queryKey: ["completude_atividades", tenantId],
    queryFn: async () => {
      const { data } = await fromTable("funcao_atividades").select("cargo_id").eq("tenant_id", tenantId!) as { data: { cargo_id: string }[] | null };
      return contar(data);
    },
    enabled: !!tenantId,
  });

  const { data: competencias = {}, isLoading: l2 } = useQuery({
    queryKey: ["completude_competencias", tenantId],
    queryFn: async () => {
      const { data } = await fromTable("funcao_competencias").select("cargo_id").eq("tenant_id", tenantId!) as { data: { cargo_id: string }[] | null };
      return contar(data);
    },
    enabled: !!tenantId,
  });

  const { data: epis = {}, isLoading: l3 } = useQuery({
    queryKey: ["completude_epis", tenantId],
    queryFn: async () => {
      const { data } = await fromTable("funcao_epi_vinculacoes").select("cargo_id").eq("tenant_id", tenantId!) as { data: { cargo_id: string }[] | null };
      return contar(data);
    },
    enabled: !!tenantId,
  });

  // POPs: contamos atividades DISTINTAS com POP por cargo (funcao_pops tem cargo_id + atividade_id).
  const { data: popsPorCargo = {}, isLoading: l4 } = useQuery({
    queryKey: ["completude_pops", tenantId],
    queryFn: async () => {
      const { data } = await fromTable("funcao_pops").select("cargo_id, atividade_id").eq("tenant_id", tenantId!) as { data: { cargo_id: string; atividade_id: string | null }[] | null };
      const sets: Record<string, Set<string>> = {};
      (data || []).forEach((r) => {
        if (!r.atividade_id) return;
        (sets[r.cargo_id] ||= new Set()).add(r.atividade_id);
      });
      const m: Record<string, number> = {};
      Object.entries(sets).forEach(([cargoId, set]) => { m[cargoId] = set.size; });
      return m;
    },
    enabled: !!tenantId,
  });

  const { data: manuaisPorCargo = {}, isLoading: l5 } = useQuery({
    queryKey: ["completude_manuais", tenantId],
    queryFn: async () => {
      const { data } = await fromTable("manuais_gerados").select("tipo, referencia_id").eq("tenant_id", tenantId!).eq("tipo", "funcao") as { data: { tipo: string; referencia_id: string | null }[] | null };
      const m: Record<string, boolean> = {};
      (data || []).forEach((r) => { if (r.referencia_id) m[r.referencia_id] = true; });
      return m;
    },
    enabled: !!tenantId,
  });

  const completudePorCargo: Record<string, CompletudeResultado> = {};
  for (const cargo of cargos) {
    completudePorCargo[cargo.id] = calcularCompletude({
      objetivoDefinido: !!(cargo.objetivo_funcao && cargo.objetivo_funcao.trim()),
      atividades: atividades[cargo.id] || 0,
      competencias: competencias[cargo.id] || 0,
      atividadesComPop: popsPorCargo[cargo.id] || 0,
      episVinculados: epis[cargo.id] || 0,
      manualGerado: !!manuaisPorCargo[cargo.id],
    });
  }

  return {
    completudePorCargo,
    isLoading: l1 || l2 || l3 || l4 || l5,
  };
}
