import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import {
  construirIndiceEncerrados,
  type IndiceEncerrados,
} from "@/lib/colaboradorAtivo";

const INDICE_VAZIO: IndiceEncerrados = {
  cpfsEncerrados: new Set(),
  cpfsAtivos: new Set(),
  nomesEncerrados: new Set(),
  nomesAtivos: new Set(),
};

/**
 * Índice de colaboradores ENCERRADOS (desligados/reprovados) do tenant e da
 * empresa ativa, para esconder lembretes de quem já saiu (ver
 * `src/lib/colaboradorAtivo.ts`). Lê só cpf + nome + status de `admissoes` (a
 * RLS limita às pessoas que o usuário pode ver; quem não enxerga a base recebe
 * índice vazio = comportamento de antes, sem esconder ninguém por engano).
 */
export function useColaboradoresEncerrados() {
  const { tenantId } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();

  const { data, isLoading } = useQuery({
    queryKey: ["colaboradores-encerrados", tenantId, empresaAtivaId],
    enabled: !!tenantId,
    staleTime: 1000 * 60 * 3,
    queryFn: async (): Promise<IndiceEncerrados> => {
      if (!tenantId) return INDICE_VAZIO;
      // Lê TODAS as admissões (ativos + encerrados) do tenant/empresa: o índice
      // precisa dos dois lados para, ao esconder por nome, não derrubar um
      // homônimo que ainda está ativo. Só 3 colunas leves; a RLS limita às
      // pessoas visíveis ao usuário.
      let q = supabase
        .from("admissoes")
        .select("cpf, nome_completo, status")
        .eq("tenant_id", tenantId);
      if (empresaAtivaId) q = q.eq("empresa_id", empresaAtivaId);
      const { data, error } = await q.limit(10000);
      if (error) throw error;
      return construirIndiceEncerrados(
        (data ?? []).map((a: any) => ({
          cpf: a.cpf ?? null,
          nome_completo: a.nome_completo ?? null,
          status: a.status ?? null,
        })),
      );
    },
  });

  return { indice: data ?? INDICE_VAZIO, isLoading };
}
