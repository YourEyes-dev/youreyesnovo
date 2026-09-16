import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

// Porta livre de cadastro de empresa (sem plano/pagamento). Fechada por
// padrão; a chave vive em app_config e o SuperAdmin liga/desliga em
// Dados da YourEyes › Portas de entrada. Enquanto não carrega, tratamos como
// fechada para não abrir a porta por um piscar de tela.
export function useCadastroLivre() {
  const q = useQuery({
    queryKey: ["portas-entrada", "cadastro-livre"],
    queryFn: async (): Promise<boolean> => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any).rpc("cadastro_empresa_livre_ativo");
      if (error) throw error;
      return data === true;
    },
    staleTime: 5 * 60 * 1000,
  });
  return { livre: q.data === true, carregando: q.isLoading };
}
