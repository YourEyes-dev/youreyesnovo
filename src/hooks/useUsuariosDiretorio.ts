import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";

/**
 * Lista de usuarios do sistema para seletores (gestor, responsavel, etc.), como uma lista de ramais.
 * Vem da funcao usuarios_diretorio(): e-mail, CPF, tipo e status so chegam para a propria pessoa e para
 * quem tem acesso amplo a dados de pessoas; os demais recebem so os usuarios ativos (nome, foto, cargo).
 * Use este hook em vez de useUsuarios() sempre que a tela so precisa ESCOLHER uma pessoa.
 */
export interface UsuarioDiretorio {
  id: string;
  nome_completo: string;
  nome_social: string | null;
  foto_url: string | null;
  cargo_funcao: string | null;
  email_principal: string | null;
  cpf: string;
  tipo_usuario: string | null;
  status: string | null;
  auth_user_id: string | null;
}

export function useUsuariosDiretorio() {
  const { tenantId } = useAuth();

  const { data, isLoading, error } = useQuery({
    queryKey: ["usuarios_diretorio", tenantId],
    queryFn: async (): Promise<UsuarioDiretorio[]> => {
      const { data, error } = await (supabase.rpc as any)("usuarios_diretorio");
      if (error) throw error;
      return (data || []) as UsuarioDiretorio[];
    },
    enabled: !!tenantId,
    staleTime: 60_000,
  });

  return { usuarios: data ?? [], isLoading, error };
}
