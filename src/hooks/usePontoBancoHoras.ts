import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";
import { handleMutationError } from "@/lib/toastError";

export interface BancoHoras {
  id: string;
  tenant_id: string;
  colaborador_id: string;
  colaborador_nome: string;
  colaborador_cpf: string | null;
  tipo: string;
  competencia: string;
  saldo_anterior_minutos: number;
  creditos_minutos: number;
  debitos_minutos: number;
  compensados_minutos: number;
  saldo_atual_minutos: number;
  convertido_extras: boolean;
  prazo_compensacao: string | null;
  observacoes: string | null;
  created_at: string;
}

/**
 * Número OFICIAL do banco de horas de uma competência (RN — fonte única).
 * Competência fechada devolve a fotografia gravada (Súmula 338); competência
 * aberta devolve a apuração de agora somada aos lançamentos manuais e
 * compensações. `divergencia_min` diz o quanto a fotografia da tabela
 * envelheceu — é o que permite avisar em vez de imprimir dois papéis
 * discordantes.
 */
export interface BancoHorasOficial {
  colaborador_cpf: string | null;
  colaborador_nome: string | null;
  empresa_id: string | null;
  saldo_anterior_min: number;
  creditos_min: number;
  debitos_min: number;
  compensados_min: number;
  saldo_atual_min: number;
  fonte: "aberta" | "fechada";
  divergencia_min: number;
  apurado_em: string | null;
}

export interface BancoHorasMovimentacao {
  id: string;
  tenant_id: string;
  banco_horas_id: string;
  colaborador_cpf: string;
  data_referencia: string;
  tipo: string;
  minutos: number;
  descricao: string | null;
  origem?: string | null;
  created_at: string;
}

export function usePontoBancoHoras() {
  const { tenantId, user } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const queryClient = useQueryClient();

  const useBancoHorasPorCompetencia = (competencia: string) => {
    return useQuery({
      queryKey: ["ponto-banco-horas", tenantId, competencia, empresaAtivaId],
      queryFn: async (): Promise<BancoHoras[]> => {
        if (!tenantId) return [];
        let query = fromTable("ponto_banco_horas")
          .select("*")
          .eq("tenant_id", tenantId)
          .eq("competencia", competencia);
        if (empresaAtivaId) query = query.eq("empresa_id", empresaAtivaId);
        const { data, error } = await query.order("colaborador_nome") as { data: BancoHoras[] | null; error: Error | null };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId,
    });
  };

  /**
   * A fonte única do banco de horas. Todo documento oficial da competência
   * (espelho, cartão ponto, relatório de banco de horas) tem de sair daqui:
   * antes, o espelho recalculava na hora e o relatório lia a tabela, e os
   * dois podiam imprimir números diferentes para o mesmo colaborador.
   */
  const useBancoHorasOficial = (competencia: string) => {
    return useQuery({
      queryKey: ["ponto-banco-horas-oficial", tenantId, competencia, empresaAtivaId],
      queryFn: async (): Promise<BancoHorasOficial[]> => {
        if (!tenantId) return [];
        const { data, error } = await (supabase.rpc as any)("ponto_banco_horas_oficial", {
          p_tenant_id: tenantId,
          p_competencia: competencia,
          p_empresa_id: empresaAtivaId || null,
        });
        if (error) throw error;
        return (data || []) as BancoHorasOficial[];
      },
      enabled: !!tenantId && !!competencia,
    });
  };

  const useMovimentacoes = (bancoHorasId: string | null) => {
    return useQuery({
      queryKey: ["ponto-bh-movimentacoes", bancoHorasId],
      queryFn: async (): Promise<BancoHorasMovimentacao[]> => {
        if (!bancoHorasId) return [];
        const { data, error } = await fromTable("ponto_banco_horas_movimentacoes")
          .select("*")
          .eq("banco_horas_id", bancoHorasId)
          .order("data_referencia", { ascending: false }) as { data: BancoHorasMovimentacao[] | null; error: Error | null };
        if (error) throw error;
        return data || [];
      },
      enabled: !!bancoHorasId,
    });
  };

  const adicionarMovimentacaoMutation = useMutation({
    mutationFn: async ({
      bancoHorasId,
      colaboradorCpf,
      dataReferencia,
      tipo,
      minutos,
      descricao,
    }: {
      bancoHorasId: string;
      colaboradorCpf: string;
      dataReferencia: string;
      tipo: string;
      minutos: number;
      descricao?: string;
    }) => {
      if (!tenantId) throw new Error("Não autenticado");

      // Insert movimentação
      const { error: movError } = await fromTable("ponto_banco_horas_movimentacoes")
        .insert({
          tenant_id: tenantId,
          banco_horas_id: bancoHorasId,
          colaborador_cpf: colaboradorCpf,
          data_referencia: dataReferencia,
          tipo,
          minutos,
          descricao,
          created_by: user?.id,
        } as any);
      if (movError) throw movError;

      // Update saldo
      const campo = tipo === "credito" ? "creditos_minutos" : tipo === "debito" ? "debitos_minutos" : "compensados_minutos";
      const { data: bh } = await fromTable("ponto_banco_horas")
        .select("saldo_anterior_minutos, creditos_minutos, debitos_minutos, compensados_minutos")
        .eq("id", bancoHorasId)
        .single() as { data: any };

      if (bh) {
        const newCreditos = (bh.creditos_minutos || 0) + (tipo === "credito" ? minutos : 0);
        const newDebitos = (bh.debitos_minutos || 0) + (tipo === "debito" ? minutos : 0);
        const newCompensados = (bh.compensados_minutos || 0) + (tipo === "compensacao" ? minutos : 0);
        const saldoAtual = (bh.saldo_anterior_minutos || 0) + newCreditos - newDebitos - newCompensados;

        await fromTable("ponto_banco_horas")
          .update({
            creditos_minutos: newCreditos,
            debitos_minutos: newDebitos,
            compensados_minutos: newCompensados,
            saldo_atual_minutos: saldoAtual,
          } as any)
          .eq("id", bancoHorasId);
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ponto-banco-horas"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-bh-movimentacoes"] });
      toast.success("Movimentação registrada!");
    },
    onError: handleMutationError,
  });

  const recalcularSaldo = async (bancoHorasId: string) => {
    const { data: movs } = await fromTable("ponto_banco_horas_movimentacoes")
      .select("tipo, minutos")
      .eq("banco_horas_id", bancoHorasId) as { data: { tipo: string; minutos: number }[] | null };
    const { data: bh } = await fromTable("ponto_banco_horas")
      .select("saldo_anterior_minutos")
      .eq("id", bancoHorasId)
      .single() as { data: any };
    const creditos = (movs || []).filter(m => m.tipo === "credito").reduce((s, m) => s + (m.minutos || 0), 0);
    const debitos = (movs || []).filter(m => m.tipo === "debito").reduce((s, m) => s + (m.minutos || 0), 0);
    const compensados = (movs || []).filter(m => m.tipo === "compensacao").reduce((s, m) => s + (m.minutos || 0), 0);
    const saldoAtual = (bh?.saldo_anterior_minutos || 0) + creditos - debitos - compensados;
    await fromTable("ponto_banco_horas")
      .update({ creditos_minutos: creditos, debitos_minutos: debitos, compensados_minutos: compensados, saldo_atual_minutos: saldoAtual } as any)
      .eq("id", bancoHorasId);
  };

  const editarMovimentacaoMutation = useMutation({
    mutationFn: async ({ id, bancoHorasId, tipo, minutos, data_referencia, descricao }: { id: string; bancoHorasId: string; tipo: string; minutos: number; data_referencia: string; descricao?: string; }) => {
      const { error } = await fromTable("ponto_banco_horas_movimentacoes")
        .update({ tipo, minutos, data_referencia, descricao } as any)
        .eq("id", id);
      if (error) throw error;
      await recalcularSaldo(bancoHorasId);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ponto-banco-horas"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-bh-movimentacoes"] });
      toast.success("Movimentação atualizada!");
    },
    onError: handleMutationError,
  });

  const excluirMovimentacaoMutation = useMutation({
    mutationFn: async ({ id, bancoHorasId }: { id: string; bancoHorasId: string }) => {
      const { error } = await fromTable("ponto_banco_horas_movimentacoes").delete().eq("id", id);
      if (error) throw error;
      await recalcularSaldo(bancoHorasId);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ponto-banco-horas"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-bh-movimentacoes"] });
      toast.success("Movimentação excluída!");
    },
    onError: handleMutationError,
  });

  const criarBancoHorasMutation = useMutation({
    mutationFn: async (dados: Partial<BancoHoras>) => {
      if (!tenantId) throw new Error("Não autenticado");
      const { data, error } = await fromTable("ponto_banco_horas")
        .insert({ ...dados, tenant_id: tenantId, empresa_id: empresaAtivaId || null } as any)
        .select()
        .single();
      if (error) {
        // Chave unica (tenant, colaborador, competencia): o colaborador ja tem
        // um banco nesta competencia. "Erro inesperado" nao dizia isso —
        // a pessoa que so quer ATIVAR o banco de horas do colaborador acaba
        // aqui achando que travou. O banco por competencia ja existe; para
        // MOVIMENTAR use "Movimentar", e para definir o REGIME de compensacao
        // (o instrumento que faz o banco valer) use a aba Config BH.
        if ((error as any)?.code === "23505") {
          throw new Error(
            "Este colaborador já tem banco de horas nesta competência. " +
            "Para lançar crédito ou débito use o botão Movimentar; para definir " +
            "o regime de compensação (individual ou coletivo) use a aba Config BH.",
          );
        }
        throw error;
      }
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ponto-banco-horas"] });
      toast.success("Banco de horas criado!");
    },
    onError: handleMutationError,
  });

  const editarBancoHorasMutation = useMutation({
    mutationFn: async ({
      id,
      tipo,
      competencia,
      saldo_anterior_minutos,
      prazo_compensacao,
      observacoes,
    }: {
      id: string;
      tipo?: string;
      competencia?: string;
      saldo_anterior_minutos?: number;
      prazo_compensacao?: string | null;
      observacoes?: string | null;
    }) => {
      const { data: bh } = await fromTable("ponto_banco_horas")
        .select("saldo_anterior_minutos, creditos_minutos, debitos_minutos, compensados_minutos")
        .eq("id", id)
        .single() as { data: any };
      const novoSaldoAnterior = saldo_anterior_minutos ?? bh?.saldo_anterior_minutos ?? 0;
      const saldoAtual = novoSaldoAnterior + (bh?.creditos_minutos || 0) - (bh?.debitos_minutos || 0) - (bh?.compensados_minutos || 0);
      const payload: any = { saldo_atual_minutos: saldoAtual };
      if (tipo !== undefined) payload.tipo = tipo;
      if (competencia !== undefined) payload.competencia = competencia;
      if (saldo_anterior_minutos !== undefined) payload.saldo_anterior_minutos = saldo_anterior_minutos;
      if (prazo_compensacao !== undefined) payload.prazo_compensacao = prazo_compensacao;
      if (observacoes !== undefined) payload.observacoes = observacoes;
      const { error } = await fromTable("ponto_banco_horas").update(payload).eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ponto-banco-horas"] });
      toast.success("Banco de horas atualizado!");
    },
    onError: handleMutationError,
  });

  const excluirBancoHorasMutation = useMutation({
    mutationFn: async (id: string) => {
      await fromTable("ponto_banco_horas_movimentacoes").delete().eq("banco_horas_id", id);
      const { error } = await fromTable("ponto_banco_horas").delete().eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ponto-banco-horas"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-bh-movimentacoes"] });
      toast.success("Banco de horas excluído!");
    },
    onError: handleMutationError,
  });

  // Apuração automática (on-demand): calcula créditos/débitos a partir do
  // ponto_diario (horas trabalhadas x jornada da escala) e grava no banco de
  // horas da competência, preservando lançamentos manuais.
  const apurarBancoHorasMutation = useMutation({
    mutationFn: async (competencia: string) => {
      if (!tenantId) throw new Error("Não autenticado");
      const { data, error } = await (supabase.rpc as any)("apurar_banco_horas", {
        p_tenant_id: tenantId,
        p_competencia: competencia,
        p_empresa_id: empresaAtivaId || null,
      });
      if (error) throw error;
      const result = data as { success?: boolean; colaboradores?: number; error?: string } | null;
      if (result && result.success !== true) {
        throw new Error(result?.error || "Não foi possível apurar o banco de horas.");
      }
      return result;
    },
    onSuccess: (result) => {
      queryClient.invalidateQueries({ queryKey: ["ponto-banco-horas"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-bh-movimentacoes"] });
      const n = result?.colaboradores ?? 0;
      toast.success(`Banco de horas apurado para ${n} colaborador(es).`);
    },
    onError: handleMutationError,
  });

  // Reapuração automática das competências já fechadas: recalcula todos os
  // registros de banco de horas existentes (afetados por correções de regra de
  // cálculo) e devolve o resumo das diferenças encontradas.
  type ReapuracaoDetalhe = {
    colaborador_nome: string | null;
    colaborador_cpf: string | null;
    competencia: string;
    saldo_antes_minutos: number;
    saldo_depois_minutos: number;
    diferenca_minutos: number;
  };
  type ReapuracaoResultado = {
    success?: boolean;
    registros_processados?: number;
    registros_ajustados?: number;
    detalhes?: ReapuracaoDetalhe[];
    error?: string;
  };

  const reapurarCompetenciasMutation = useMutation({
    mutationFn: async (params?: { desde?: string | null; ate?: string | null }) => {
      if (!tenantId) throw new Error("Não autenticado");
      const { data, error } = await (supabase.rpc as any)("reapurar_banco_horas_competencias", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaAtivaId || null,
        p_desde: params?.desde ?? null,
        p_ate: params?.ate ?? null,
      });
      if (error) throw error;
      const result = data as ReapuracaoResultado | null;
      if (result && result.success !== true) {
        throw new Error(result?.error || "Não foi possível reapurar as competências.");
      }
      return result as ReapuracaoResultado;
    },
    onSuccess: (result) => {
      queryClient.invalidateQueries({ queryKey: ["ponto-banco-horas"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-bh-movimentacoes"] });
      const proc = result?.registros_processados ?? 0;
      const alt = result?.registros_ajustados ?? 0;
      toast.success(`${proc} competência(s) reapurada(s) — ${alt} com saldo ajustado.`);
    },
    onError: handleMutationError,
  });

  return {

    useBancoHorasPorCompetencia,
    useBancoHorasOficial,
    useMovimentacoes,
    adicionarMovimentacao: adicionarMovimentacaoMutation.mutateAsync,
    adicionandoMovimentacao: adicionarMovimentacaoMutation.isPending,
    editarMovimentacao: editarMovimentacaoMutation.mutateAsync,
    editandoMovimentacao: editarMovimentacaoMutation.isPending,
    excluirMovimentacao: excluirMovimentacaoMutation.mutateAsync,
    excluindoMovimentacao: excluirMovimentacaoMutation.isPending,
    criarBancoHoras: criarBancoHorasMutation.mutateAsync,
    criandoBancoHoras: criarBancoHorasMutation.isPending,
    editarBancoHoras: editarBancoHorasMutation.mutateAsync,
    editandoBancoHoras: editarBancoHorasMutation.isPending,
    excluirBancoHoras: excluirBancoHorasMutation.mutateAsync,
    excluindoBancoHoras: excluirBancoHorasMutation.isPending,
    apurarBancoHoras: apurarBancoHorasMutation.mutateAsync,
    apurandoBancoHoras: apurarBancoHorasMutation.isPending,
    reapurarCompetencias: reapurarCompetenciasMutation.mutateAsync,
    reapurandoCompetencias: reapurarCompetenciasMutation.isPending,

  };
}
