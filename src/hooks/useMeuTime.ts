import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";

/**
 * Ids das admissões que a pessoa logada gerencia. Duas fontes do cadastro:
 *  - o campo "gestor imediato" do colaborador, igual ao nome da pessoa logada;
 *  - o departamento em que ela é gestora (ou substituta com a substituição ativa).
 * A pessoa logada é ligada à própria admissão pelo CPF do cadastro de usuários.
 * A conta é feita no banco (função meu_time_admissoes), que devolve só os ids da equipe — a tela não lê o cadastro de ninguém.
 */
export function useMeuTime(habilitado: boolean) {
  const { tenantId, user } = useAuth();

  return useQuery({
    queryKey: ["meu-time", tenantId, user?.id],
    enabled: habilitado && !!tenantId && !!user?.id,
    staleTime: 5 * 60 * 1000,
    queryFn: async (): Promise<string[]> => {
      const { data, error } = await (supabase.rpc as any)("meu_time_admissoes");
      if (error) throw error;
      return ((data || []) as string[]).map((x) => String(x));
    },
  });
}
