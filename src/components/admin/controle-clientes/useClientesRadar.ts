import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

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
      const { data, error } = await supabase.rpc('central_situacao_clientes');
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
      const { data, error } = await supabase.rpc('central_incidentes', { p_limite: 50 });
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
      const { data, error } = await supabase.rpc('central_resumo');
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

export type EventoDoIncidente = {
  id: string;
  empresa: string;
  ambiente: string;
  origem: string;
  usuarioPseudo: string | null;
  modulo: string | null;
  rota: string | null;
  acao: string | null;
  mensagem: string;
  stack: string | null;
  breadcrumbs: string[];
  versaoApp: string | null;
  navegadorOs: string | null;
  ocorridoEm: string;
};

export type DetalheIncidente = {
  incidente: Record<string, unknown> | null;
  clientes: { tenantId: string | null; nome: string; ocorrencias: number; ultimo: string }[];
  eventos: EventoDoIncidente[];
};

/** Detalhe de um incidente: quem sentiu e os últimos eventos, já mascarados. */
export function useDetalheIncidente(fingerprint: string | null) {
  return useQuery({
    queryKey: ['controle-clientes', 'incidente', fingerprint],
    enabled: Boolean(fingerprint),
    queryFn: async (): Promise<DetalheIncidente> => {
      const { data, error } = await supabase.rpc('central_incidente_detalhe', {
        p_fingerprint: fingerprint as string,
        p_limite: 20,
      });
      if (error) throw error;
      const d = (data as Record<string, unknown> | null) ?? {};
      const clientes = (d.clientes as Array<Record<string, unknown>> | undefined) ?? [];
      const eventos = (d.eventos as Array<Record<string, unknown>> | undefined) ?? [];
      return {
        incidente: (d.incidente as Record<string, unknown>) ?? null,
        clientes: clientes.map((c) => ({
          tenantId: (c.tenant_id as string) ?? null,
          nome: String(c.nome ?? 'Sem empresa vinculada'),
          ocorrencias: Number(c.ocorrencias ?? 0),
          ultimo: String(c.ultimo ?? ''),
        })),
        eventos: eventos.map((e) => ({
          id: String(e.id),
          empresa: String(e.empresa ?? 'Sem empresa vinculada'),
          ambiente: String(e.ambiente ?? ''),
          origem: String(e.origem ?? ''),
          usuarioPseudo: (e.usuario_pseudo as string) ?? null,
          modulo: (e.modulo as string) ?? null,
          rota: (e.rota as string) ?? null,
          acao: (e.acao as string) ?? null,
          mensagem: String(e.mensagem ?? ''),
          stack: (e.stack as string) ?? null,
          breadcrumbs: Array.isArray(e.breadcrumbs) ? (e.breadcrumbs as string[]) : [],
          versaoApp: (e.versao_app as string) ?? null,
          navegadorOs: (e.navegador_os as string) ?? null,
          ocorridoEm: String(e.ocorrido_em ?? ''),
        })),
      };
    },
  });
}
