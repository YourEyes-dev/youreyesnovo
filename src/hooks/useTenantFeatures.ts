import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { useAuthContext } from '@/contexts/AuthContext';
import { featureForPath, planNameForPath } from '@/lib/planFeatures';

/**
 * Lê, de uma vez, quais funcionalidades (feature_key) o plano da empresa
 * logada libera — via a função read-only entitlement_my_features().
 *
 * À PROVA DE FALHA: se a consulta falhar OU vier vazia (empresa sem
 * assinatura), `planGatingActive` fica false e o menu mostra TUDO. O cadeado
 * por plano só age quando temos certeza do que a empresa tem.
 */
export function useTenantFeatures() {
  const { user } = useAuthContext();

  const { data, isLoading, isError } = useQuery({
    queryKey: ['tenant-features'],
    enabled: !!user,
    staleTime: 5 * 60 * 1000,
    queryFn: async (): Promise<string[]> => {
      const { data, error } = await (supabase as any).rpc('entitlement_my_features');
      if (error) throw error;
      return (data as string[]) || [];
    },
  });

  const features = new Set<string>(data ?? []);
  // Só aplica cadeado quando a leitura deu certo E retornou algo (todo plano
  // real libera ao menos os módulos do Starter). Vazio/erro => mostra tudo.
  const planGatingActive = !isLoading && !isError && features.size > 0;

  return { features, planGatingActive, isLoading };
}

/**
 * Diz se um caminho do menu está FORA do plano da empresa logada (cadeado).
 * Super Admin nunca vê cadeado; planos internos (tester/early_adopter) têm
 * todas as funcionalidades, então também não veem. À prova de falha: se o
 * gating não está ativo (erro/sem assinatura), nada é cadeado.
 */
export function usePlanLock() {
  const { isSuperAdmin } = useAuthContext();
  const { features, planGatingActive } = useTenantFeatures();

  const isLocked = (path?: string): boolean => {
    if (!path || isSuperAdmin || !planGatingActive) return false;
    const feature = featureForPath(path);
    if (!feature) return false;
    return !features.has(feature);
  };

  return { isLocked, planNameForPath };
}
