import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { useAuthContext } from '@/contexts/AuthContext';

export interface MeuPlanoModulo {
  key: string;
  name: string;
  category: string | null;
  disponivel: boolean;
}

export interface MeuPlanoAddon {
  feature_key: string;
  name: string;
  kind: 'module' | 'life';
  quantity: number;
  unit_price_cents: number;
}

export interface MeuPlano {
  plano: { code: string; name: string; is_public: boolean } | null;
  vidas: {
    used: number;
    limit: number | null;
    is_unlimited: boolean;
    remaining: number | null;
    percent: number | null;
  };
  modulos: MeuPlanoModulo[];
  precos: Record<string, number>; // feature_key -> centavos (itens contratáveis)
  addons: MeuPlanoAddon[];
  valores: { base_cents: number | null; addons_cents: number; total_cents: number | null };
}

// Lê o resumo do plano (plano, vidas, módulos, preços de add-on, add-ons
// contratados e valor mensal) e expõe as ações de contratar/cancelar add-ons.
export function useMeuPlano() {
  const queryClient = useQueryClient();
  const { user } = useAuthContext();

  const { data, isLoading, isError } = useQuery({
    queryKey: ['meu-plano'],
    enabled: !!user,
    staleTime: 60 * 1000,
    queryFn: async (): Promise<MeuPlano | null> => {
      const { data, error } = await (supabase as any).rpc('entitlement_my_plan');
      if (error) throw error;
      return (data as MeuPlano) ?? null;
    },
  });

  const contratarMutation = useMutation({
    mutationFn: async ({ featureKey, quantity }: { featureKey: string; quantity?: number }) => {
      const { error } = await (supabase as any).rpc('my_contratar_addon', {
        _feature_key: featureKey,
        _quantity: quantity ?? 1,
      });
      if (error) throw error;
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['meu-plano'] }),
  });

  const cancelarMutation = useMutation({
    mutationFn: async (featureKey: string) => {
      const { error } = await (supabase as any).rpc('my_cancelar_addon', { _feature_key: featureKey });
      if (error) throw error;
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['meu-plano'] }),
  });

  return {
    plano: data ?? null,
    isLoading,
    isError,
    contratar: contratarMutation.mutateAsync,
    cancelar: cancelarMutation.mutateAsync,
    isMutating: contratarMutation.isPending || cancelarMutation.isPending,
  };
}
