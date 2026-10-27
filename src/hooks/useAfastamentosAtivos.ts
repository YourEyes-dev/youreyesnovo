import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";

export interface AfastamentoAtivo {
  colaborador_nome: string;
  colaborador_cpf: string | null;
  colaborador_id: string | null;
  status: string;
  data_inicio: string;
  data_fim: string | null;
  motivo_principal: string | null;
}

/**
 * Retorna os afastamentos ativos (status 'ativo' ou 'beneficio_inss') do tenant, via afastamentos_ativos_resumo().
 * O motivo só vem preenchido para quem tem Atestados ou SST (dado de saúde, LGPD art. 11).
 * Usado para exibir alertas em qualquer tela que mencione um colaborador afastado.
 */
export function useAfastamentosAtivos() {
  const { tenantId } = useAuth();

  const { data: afastamentosAtivos = [], isLoading } = useQuery({
    queryKey: ["afastamentos-ativos", tenantId],
    queryFn: async () => {
      // A função do banco devolve QUEM está afastado e as datas a quem tem módulo de pessoas, e o MOTIVO (grupo clínico,
      // inclusive saúde mental) só a quem tem Atestados ou SST amplo. Quem só tem autosserviço recebe lista vazia.
      const { data, error } = await (supabase.rpc as any)("afastamentos_ativos_resumo");

      if (error) throw error;
      return (data || []) as AfastamentoAtivo[];
    },
    enabled: !!tenantId,
    staleTime: 60_000, // cache 1 min
  });

  /** Verifica se um colaborador está afastado pelo CPF */
  const isAfastadoByCpf = (cpf: string | null | undefined): AfastamentoAtivo | undefined => {
    if (!cpf) return undefined;
    const cleaned = cpf.replace(/\D/g, "");
    return afastamentosAtivos.find(a => a.colaborador_cpf?.replace(/\D/g, "") === cleaned);
  };

  /** Verifica se um colaborador está afastado pelo nome */
  const isAfastadoByNome = (nome: string | null | undefined): AfastamentoAtivo | undefined => {
    if (!nome) return undefined;
    return afastamentosAtivos.find(a => a.colaborador_nome?.toLowerCase() === nome.toLowerCase());
  };

  /** Verifica se um colaborador está afastado pelo ID (user_id / colaborador_id) */
  const isAfastadoById = (id: string | null | undefined): AfastamentoAtivo | undefined => {
    if (!id) return undefined;
    return afastamentosAtivos.find(a => a.colaborador_id === id);
  };

  /** Verifica por CPF, nome ou ID — retorna o primeiro match */
  const getAfastamento = (opts: { cpf?: string | null; nome?: string | null; id?: string | null }): AfastamentoAtivo | undefined => {
    return isAfastadoByCpf(opts.cpf) || isAfastadoByNome(opts.nome) || isAfastadoById(opts.id);
  };

  return {
    afastamentosAtivos,
    isLoading,
    isAfastadoByCpf,
    isAfastadoByNome,
    isAfastadoById,
    getAfastamento,
  };
}
