import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";

/**
 * Diz se o usuário logado pode ver salário (perfil com "pode ver salário").
 *
 * A trava REAL é no servidor (a view admissoes_segura mascara o valor, o RLS
 * esconde os registros de folha, e um trigger impede alteração indevida). Este
 * hook é para a TELA: mostrar "Sem permissão" em vez de um campo vazio e
 * desabilitar a edição do salário. Em dúvida/carregando, assume true — quem
 * manda é o servidor, então um "true" aqui nunca revela o valor que a view já
 * devolveu como nulo.
 */
export function usePodeVerSalario(): boolean {
  const { tenantId } = useAuth();
  const { data } = useQuery({
    queryKey: ["pode_ver_salario", tenantId],
    enabled: !!tenantId,
    staleTime: 60_000,
    queryFn: async () => {
      const { data, error } = await (supabase as any).rpc("pode_ver_salario", {
        p_tenant_id: tenantId,
      });
      if (error) return true;
      return data === true;
    },
  });
  return data ?? true;
}
