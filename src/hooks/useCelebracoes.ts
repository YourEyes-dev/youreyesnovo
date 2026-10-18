import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { calcularCelebracoes, type Celebracao, type PessoaCelebravel } from "@/lib/celebracoes";
import { useDiasProfissao } from "@/hooks/useDiasProfissao";
import type { CulturaConfig } from "@/types/cultura";

interface Opcoes {
  /** Cultura exige empresa ativa (RN-001); o Mural aceita o tenant inteiro. */
  exigirEmpresa?: boolean;
}

/**
 * Celebrações detectadas (aniversário, tempo de casa, dia da profissão) já
 * filtradas pela Configuração do módulo. Fonte única para Cultura e Mural.
 */
export function useCelebracoes({ exigirEmpresa = false }: Opcoes = {}) {
  const { tenantId } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const habilitado = !!tenantId && (!exigirEmpresa || !!empresaAtivaId);

  const { data: pessoas = [], isLoading: carregandoPessoas } = useQuery({
    queryKey: ["celebracoes-pessoas", tenantId, empresaAtivaId],
    queryFn: async (): Promise<PessoaCelebravel[]> => {
      let query = fromTable("admissoes")
        .select("id, nome_completo, data_nascimento, data_admissao, cargo")
        .eq("tenant_id", tenantId)
        .eq("status", "concluido");
      if (empresaAtivaId) query = query.eq("empresa_id", empresaAtivaId);
      const { data, error } = await query;
      if (error) throw error;
      return (data || []) as PessoaCelebravel[];
    },
    enabled: habilitado,
  });

  // mesma chave de useCultura: o cache é compartilhado e salvar a config atualiza as duas telas
  const { data: config = null, isLoading: carregandoConfig } = useQuery({
    queryKey: ["cultura-config", tenantId],
    queryFn: async () => {
      const { data, error } = await fromTable("cultura_config")
        .select("*")
        .eq("tenant_id", tenantId)
        .maybeSingle();
      if (error) throw error;
      return data as CulturaConfig | null;
    },
    enabled: !!tenantId,
  });

  // decisões da empresa sobre o dia da profissão (IA aprovada, rejeitada ou manual)
  const { registros: diasProfissao } = useDiasProfissao();

  const celebracoes: Celebracao[] = useMemo(
    () => (habilitado ? calcularCelebracoes(pessoas, config, new Date(), diasProfissao) : []),
    [habilitado, pessoas, config, diasProfissao],
  );

  return {
    celebracoes,
    pessoas,
    config,
    diasProfissao,
    janelaDias: config?.dias_antecedencia_acao ?? 30,
    isLoading: carregandoPessoas || carregandoConfig,
  };
}
