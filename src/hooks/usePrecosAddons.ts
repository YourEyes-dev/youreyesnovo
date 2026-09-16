import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { useAuthContext } from '@/contexts/AuthContext';

export interface AddonPreco {
  key: string;
  name: string;
  category: string | null;
  kind: 'module' | 'life';
  unit_price_cents: number;
}

// Catálogo de preços dos add-ons (módulos avulsos + vida extra), para a tela
// de configuração do Super Admin.
export function usePrecosAddons() {
  const queryClient = useQueryClient();
  const { isSuperAdmin } = useAuthContext();

  const { data: itens = [], isLoading, isError } = useQuery({
    queryKey: ['addon-precos'],
    enabled: isSuperAdmin,
    queryFn: async (): Promise<AddonPreco[]> => {
      const { data, error } = await (supabase as any).rpc('superadmin_addon_prices_list');
      if (error) throw error;
      return (data as AddonPreco[]) ?? [];
    },
  });

  const setPrecoMutation = useMutation({
    mutationFn: async ({ featureKey, cents }: { featureKey: string; cents: number }) => {
      const { error } = await (supabase as any).rpc('superadmin_set_addon_price', {
        _feature_key: featureKey,
        _cents: cents,
      });
      if (error) throw error;
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['addon-precos'] }),
  });

  return {
    itens,
    isLoading,
    isError,
    setPreco: setPrecoMutation.mutateAsync,
    isSaving: setPrecoMutation.isPending,
  };
}
