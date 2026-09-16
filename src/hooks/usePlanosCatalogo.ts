import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export interface PlanoCatalogo {
  code: string;
  name: string;
  tier: number;
  is_public: boolean;
}

// Lê o catálogo de planos direto da tabela public.plans (leitura liberada).
// Fonte da verdade dos planos comerciais + internos — nada de lista fixa no código.
// A tabela ainda não está nos tipos gerados do Supabase, por isso o cast.
export function usePlanosCatalogo() {
  const { data: planos = [], isLoading } = useQuery({
    queryKey: ['planos-catalogo'],
    queryFn: async (): Promise<PlanoCatalogo[]> => {
      const { data, error } = await (supabase as any)
        .from('plans')
        .select('code, name, tier, is_public')
        .eq('status', 'active')
        .order('tier', { ascending: true })
        .order('name', { ascending: true });
      if (error) throw error;
      return (data as PlanoCatalogo[]) || [];
    },
    staleTime: 5 * 60 * 1000,
  });

  return { planos, isLoading };
}
