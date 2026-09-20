import { useQuery } from '@tanstack/react-query';
import { rpcUntyped } from '@/integrations/supabase/untypedClient';

// Leitura da Central de Controle de Clientes. Tudo cross-tenant, tudo por
// função do servidor que exige superadmin — a tela não monta consulta livre
// sobre as tabelas de evento.

export type SituacaoCliente = 'ok' | 'erro' | 'sem_sinal';

export type ClienteNoRadar = {
  id: string;
  nome: string;
  colaboradores: number;
  situacao: SituacaoCliente;
  erros24h: number;
};

export type Incidente = {
  fingerprint: string;
  titulo: string;
  modulo: string | null;
  severidade: 'critica' | 'alta' | 'media' | 'baixa';
  status: string;
  ocorrencias: number;
  clientesAfetados: number;
  primeiroVisto: string;
  ultimoVisto: string;
};

export type ResumoCentral = {
  erros24h: number | null;
  incidentesAbertos: number | null;
  incidentesCriticos: number | null;
  clientesComErro: number | null;
};

/** Clientes ativos e a situação de cada um nas últimas 24 horas. */
export function useClientesRadar(habilitado: boolean) {
  return useQuery({
    queryKey: ['controle-clientes', 'radar'],
    enabled: habilitado,
    refetchInterval: 60_000,
    queryFn: async (): Promise<ClienteNoRadar[]> => {
      const { data, error } = await rpcUntyped('central_situacao_clientes');
      if (error) throw error;
      const linhas = (data as Array<Record<string, unknown>> | null) ?? [];
      return linhas
        .map((t) => ({
          id: String(t.tenant_id),
          nome: String(t.nome ?? 'Sem nome'),
          colaboradores: Number(t.colaboradores ?? 0),
          situacao: (t.situacao === 'erro' ? 'erro' : 'ok') as SituacaoCliente,
          erros24h: Number(t.erros_24h ?? 0),
        }))
        // Quem está com erro aparece primeiro na lista ao lado do radar.
        .sort((a, b) => b.erros24h - a.erros24h || a.nome.localeCompare(b.nome));
    },
  });
}

/** Incidentes abertos, do mais grave e mais recente para o resto. */
export function useIncidentes() {
  return useQuery({
    queryKey: ['controle-clientes', 'incidentes'],
    refetchInterval: 60_000,
    queryFn: async (): Promise<Incidente[]> => {
      const { data, error } = await rpcUntyped('central_incidentes', { p_limite: 50 });
      if (error) throw error;
      const linhas = (data as Array<Record<string, unknown>> | null) ?? [];
      return linhas.map((i) => ({
        fingerprint: String(i.fingerprint),
        titulo: String(i.titulo ?? ''),
        modulo: (i.modulo as string) ?? null,
        severidade: (i.severidade as Incidente['severidade']) ?? 'media',
        status: String(i.status ?? 'novo'),
        ocorrencias: Number(i.ocorrencias ?? 0),
        clientesAfetados: Number(i.clientes_afetados ?? 0),
        primeiroVisto: String(i.primeiro_visto ?? ''),
        ultimoVisto: String(i.ultimo_visto ?? ''),
      }));
    },
  });
}

/** Números do topo da tela. */
export function useResumoCentral() {
  return useQuery({
    queryKey: ['controle-clientes', 'resumo'],
    refetchInterval: 60_000,
    queryFn: async (): Promise<ResumoCentral> => {
      const { data, error } = await rpcUntyped('central_resumo');
      if (error) throw error;
      const r = (data as Record<string, unknown> | null) ?? {};
      const num = (v: unknown) => (v === undefined || v === null ? null : Number(v));
      return {
        erros24h: num(r.erros_24h),
        incidentesAbertos: num(r.incidentes_abertos),
        incidentesCriticos: num(r.incidentes_criticos),
        clientesComErro: num(r.clientes_com_erro),
      };
    },
  });
}
