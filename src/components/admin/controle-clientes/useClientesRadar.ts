import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

// Tipos e leitura dos clientes que o radar desenha. Ficam fora do componente
// para o recarregamento em desenvolvimento não reclamar do arquivo misto.

export type SituacaoCliente = 'ok' | 'erro' | 'sem_sinal';

export type ClienteNoRadar = {
  id: string;
  nome: string;
  colaboradores: number;
  situacao: SituacaoCliente;
};

/** Clientes ativos, na forma que o radar consome. */
export function useClientesRadar(habilitado: boolean) {
  return useQuery({
    queryKey: ['controle-clientes', 'radar'],
    enabled: habilitado,
    queryFn: async (): Promise<ClienteNoRadar[]> => {
      const { data, error } = await supabase.rpc('superadmin_tenants_list');
      if (error) throw error;
      const linhas = (data as Array<Record<string, unknown>> | null) ?? [];
      return linhas
        .filter((t) => t.ativo !== false)
        .map((t) => ({
          id: String(t.id),
          nome: String(t.nome ?? 'Sem nome'),
          colaboradores: Number(t.total_colaboradores ?? 0),
          // Sem captura de erro ainda: ninguém pode ser declarado verde.
          situacao: 'sem_sinal' as SituacaoCliente,
        }))
        .sort((a, b) => b.colaboradores - a.colaboradores);
    },
  });
}

