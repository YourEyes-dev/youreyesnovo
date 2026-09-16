import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";
import {
  calcularFolhaMensal,
  calcularFerias,
  calcular13,
  calcularRescisao,
  calcularProvisao,
  TABELA_INSS_2025,
  TETO_INSS_2025,
  TABELA_IRRF_2025,
  DEDUCAO_DEPENDENTE_IRRF_2025,
  MATRIZ_VINCULOS_PADRAO,
  type VinculoConfig,
} from "@/lib/folha/calculos";
import { traduzirErro13 } from "@/lib/decimoTerceiroErros";

export function useFolhaCalculo() {
  const { tenantId, user, profile } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const queryClient = useQueryClient();

  // ======== RUBRICAS ========
  const useRubricas = () =>
    useQuery({
      queryKey: ["folha-rubricas", tenantId],
      queryFn: async () => {
        if (!tenantId) return [];
        const { data, error } = await fromTable("folha_rubricas")
          .select("*")
          .eq("tenant_id", tenantId)
          .order("prioridade_calculo") as { data: any[] | null; error: any };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId,
    });

  const criarRubricaMutation = useMutation({
    mutationFn: async (dados: any) => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      const { data, error } = await fromTable("folha_rubricas")
        .insert({ ...dados, tenant_id: tenantId } as any)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["folha-rubricas"] });
      toast.success("Rubrica criada!");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const atualizarRubricaMutation = useMutation({
    mutationFn: async ({ id, ...dados }: any) => {
      const { data, error } = await fromTable("folha_rubricas")
        .update(dados as any)
        .eq("id", id)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["folha-rubricas"] });
      toast.success("Rubrica atualizada!");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  // ======== TABELAS LEGAIS ========
  const useTabelasINSS = () =>
    useQuery({
      queryKey: ["folha-tabelas-inss", tenantId],
      queryFn: async () => {
        if (!tenantId) return [];
        const { data, error } = await fromTable("folha_tabelas_inss")
          .select("*")
          .eq("tenant_id", tenantId)
          .order("vigencia_inicio", { ascending: false }) as { data: any[] | null; error: any };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId,
    });

  const useTabelasIRRF = () =>
    useQuery({
      queryKey: ["folha-tabelas-irrf", tenantId],
      queryFn: async () => {
        if (!tenantId) return [];
        const { data, error } = await fromTable("folha_tabelas_irrf")
          .select("*")
          .eq("tenant_id", tenantId)
          .order("vigencia_inicio", { ascending: false }) as { data: any[] | null; error: any };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId,
    });

  // ======== VÍNCULOS CONFIG ========
  const useVinculosConfig = () =>
    useQuery({
      queryKey: ["folha-vinculos-config", tenantId],
      queryFn: async () => {
        if (!tenantId) return MATRIZ_VINCULOS_PADRAO;
        const { data, error } = await fromTable("folha_vinculos_config")
          .select("*")
          .eq("tenant_id", tenantId) as { data: any[] | null; error: any };
        if (error) throw error;
        return (data && data.length > 0) ? data as VinculoConfig[] : MATRIZ_VINCULOS_PADRAO;
      },
      enabled: !!tenantId,
    });

  // ======== LANÇAMENTOS ========
  const useLancamentos = (periodoId?: string) =>
    useQuery({
      queryKey: ["folha-lancamentos", tenantId, periodoId],
      queryFn: async () => {
        if (!tenantId || !periodoId) return [];
        const { data, error } = await fromTable("folha_lancamentos")
          .select("*")
          .eq("tenant_id", tenantId)
          .eq("periodo_id", periodoId)
          .order("created_at") as { data: any[] | null; error: any };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId && !!periodoId,
    });

  const criarLancamentoMutation = useMutation({
    mutationFn: async (dados: any) => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      const { data, error } = await fromTable("folha_lancamentos")
        .insert({ ...dados, tenant_id: tenantId } as any)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["folha-lancamentos"] });
      toast.success("Lançamento criado!");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  // ======== MEMÓRIA DE CÁLCULO ========
  const useMemoriaCalculo = (periodoId?: string, colaboradorId?: string) =>
    useQuery({
      queryKey: ["folha-memoria-calculo", periodoId, colaboradorId],
      queryFn: async () => {
        if (!tenantId || !periodoId) return null;
        let query = fromTable("folha_memoria_calculo")
          .select("*")
          .eq("tenant_id", tenantId)
          .eq("periodo_id", periodoId);
        if (colaboradorId) query = query.eq("colaborador_id", colaboradorId);
        const { data, error } = await query as { data: any[] | null; error: any };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId && !!periodoId,
    });

  // ======== PROVISÕES ========
  const useProvisoes = (competencia?: string) =>
    useQuery({
      queryKey: ["folha-provisoes", tenantId, competencia],
      queryFn: async () => {
        if (!tenantId) return [];
        let query = fromTable("folha_provisoes")
          .select("*")
          .eq("tenant_id", tenantId);
        if (competencia) query = query.eq("competencia", competencia);
        const { data, error } = await query.order("colaborador_nome") as { data: any[] | null; error: any };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId,
    });

  // ======== FÉRIAS CÁLCULO ========
  const useFeriasCalculo = () =>
    useQuery({
      queryKey: ["folha-ferias-calculo", tenantId],
      queryFn: async () => {
        if (!tenantId) return [];
        const { data, error } = await fromTable("folha_ferias_calculo")
          .select("*")
          .eq("tenant_id", tenantId)
          .order("created_at", { ascending: false }) as { data: any[] | null; error: any };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId,
    });

  const criarFeriasCalculoMutation = useMutation({
    mutationFn: async (dados: any) => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      // Calcular
      const resultado = calcularFerias({
        remuneracaoBase: dados.remuneracao_base,
        mediaVariaveis: dados.media_variaveis || 0,
        diasGozo: dados.dias_gozo,
        diasAbono: dados.dias_abono || 0,
        emDobro: dados.em_dobro || false,
        dependentesIRRF: dados.dependentes_irrf || 0,
      });

      const prazoLegal = new Date(dados.data_inicio_gozo);
      prazoLegal.setDate(prazoLegal.getDate() - 2);

      // Campos que servem ao cálculo mas não são colunas da tabela ficam de
      // fora do insert; a memória da média entra dentro de memoria_calculo,
      // para o valor se reproduzir depois (art. 142 / RNF-008).
      const { dependentes_irrf, media_memoria, ...colunas } = dados;

      const { data, error } = await fromTable("folha_ferias_calculo")
        .insert({
          ...colunas,
          ...resultado,
          prazo_legal: prazoLegal.toISOString().split("T")[0],
          memoria_calculo: {
            ...resultado,
            dependentes_irrf: dependentes_irrf || 0,
            media_variaveis: media_memoria || null,
          },
          tenant_id: tenantId,
        } as any)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["folha-ferias-calculo"] });
      toast.success("Férias calculadas!");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  // ======== 13º CÁLCULO ========
  const use13Calculo = (ano?: number) =>
    useQuery({
      queryKey: ["folha-13-calculo", tenantId, ano],
      queryFn: async () => {
        if (!tenantId) return [];
        let query = fromTable("folha_13_calculo")
          .select("*")
          .eq("tenant_id", tenantId);
        if (ano) query = query.eq("ano", ano);
        const { data, error } = await query.order("colaborador_nome") as { data: any[] | null; error: any };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId,
    });

  const criar13CalculoMutation = useMutation({
    mutationFn: async (dados: any) => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      const resultado = calcular13({
        remuneracaoBase: dados.remuneracao_base,
        mediaVariaveis: dados.media_variaveis || 0,
        mesesTrabalhados: dados.meses_trabalhados,
        parcela: dados.parcela,
        valorPrimeiraParcela: dados.valor_primeira_parcela || 0,
        dependentesIRRF: dados.dependentes_irrf || 0,
      });

      // Campos que servem ao cálculo mas não são colunas da tabela ficam de
      // fora do insert; as memórias de avos e média entram dentro de
      // memoria_calculo, para o valor se reproduzir depois (RNF-001/007).
      const { dependentes_irrf, apuracao_memoria, ...colunas } = dados;

      const { data, error } = await fromTable("folha_13_calculo")
        .insert({
          ...colunas,
          ...resultado,
          memoria_calculo: {
            ...resultado,
            dependentes_irrf: dependentes_irrf || 0,
            apuracao: apuracao_memoria || null,
          },
          tenant_id: tenantId,
        } as any)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["folha-13-calculo"] });
      toast.success("13º calculado!");
    },
    // O banco tem travas que impedem gravar coisa errada (parcela repetida,
    // encargos na 1ª parcela, cálculo já fechado). Elas voltavam em inglês,
    // com nome de índice; aqui viram instrução do que fazer na tela.
    onError: (e: unknown) => toast.error(traduzirErro13(e)),
  });

  // ======== RESCISÕES ========
  const useRescisoes = () =>
    useQuery({
      queryKey: ["folha-rescisoes", tenantId],
      queryFn: async () => {
        if (!tenantId) return [];
        const { data, error } = await fromTable("folha_rescisoes")
          .select("*")
          .eq("tenant_id", tenantId)
          .order("created_at", { ascending: false }) as { data: any[] | null; error: any };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId,
    });

  const criarRescisaoMutation = useMutation({
    mutationFn: async (dados: any) => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      const resultado = calcularRescisao({
        salarioBase: dados.salario_base || dados.salario || 0,
        dataAdmissao: dados.data_admissao,
        dataDesligamento: dados.data_desligamento,
        tipoRescisao: dados.tipo_rescisao,
        avisoTipo: dados.aviso_tipo || "indenizado",
        diasAvisoPrevio: dados.dias_aviso || 30,
        feriasPeriodosVencidos: dados.ferias_periodos_vencidos || 0,
        dependentesIRRF: dados.dependentes_irrf || 0,
      });

      const prazoLegal = new Date(dados.data_desligamento);
      prazoLegal.setDate(prazoLegal.getDate() + 10);

      const { data, error } = await fromTable("folha_rescisoes")
        .insert({
          tenant_id: tenantId,
          colaborador_id: dados.colaborador_id,
          colaborador_nome: dados.colaborador_nome,
          colaborador_cpf: dados.colaborador_cpf,
          admissao_id: dados.admissao_id,
          tipo_vinculo: dados.tipo_vinculo,
          tipo_rescisao: dados.tipo_rescisao,
          data_desligamento: dados.data_desligamento,
          data_aviso: dados.data_aviso,
          aviso_tipo: dados.aviso_tipo,
          dias_aviso: dados.dias_aviso,
          motivo: dados.motivo,
          ...resultado,
          prazo_legal: prazoLegal.toISOString().split("T")[0],
          memoria_calculo: resultado.detalhes,
        } as any)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["folha-rescisoes"] });
      toast.success("Rescisão calculada!");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const atualizarRescisaoMutation = useMutation({
    mutationFn: async ({ id, ...dados }: any) => {
      const { data, error } = await fromTable("folha_rescisoes")
        .update(dados as any)
        .eq("id", id)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["folha-rescisoes"] });
      toast.success("Rescisão atualizada!");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  // ======== LOTES ========
  const useLotes = () =>
    useQuery({
      queryKey: ["folha-lotes", tenantId],
      queryFn: async () => {
        if (!tenantId) return [];
        const { data, error } = await fromTable("folha_lotes")
          .select("*")
          .eq("tenant_id", tenantId)
          .order("created_at", { ascending: false }) as { data: any[] | null; error: any };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId,
    });

  // ======== HISTÓRICO ========
  const useHistorico = (periodoId?: string) =>
    useQuery({
      queryKey: ["folha-historico", tenantId, periodoId],
      queryFn: async () => {
        if (!tenantId) return [];
        let query = fromTable("folha_historico")
          .select("*")
          .eq("tenant_id", tenantId);
        if (periodoId) query = query.eq("periodo_id", periodoId);
        const { data, error } = await query.order("created_at", { ascending: false }).limit(100) as { data: any[] | null; error: any };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId,
    });

  // Funções de cálculo expostas
  return {
    // Queries
    useRubricas,
    useTabelasINSS,
    useTabelasIRRF,
    useVinculosConfig,
    useLancamentos,
    useMemoriaCalculo,
    useProvisoes,
    useFeriasCalculo,
    use13Calculo,
    useRescisoes,
    useLotes,
    useHistorico,

    // Mutations
    criarRubrica: criarRubricaMutation.mutateAsync,
    criandoRubrica: criarRubricaMutation.isPending,
    atualizarRubrica: atualizarRubricaMutation.mutateAsync,
    criarLancamento: criarLancamentoMutation.mutateAsync,
    criarFeriasCalculo: criarFeriasCalculoMutation.mutateAsync,
    criandoFerias: criarFeriasCalculoMutation.isPending,
    criar13Calculo: criar13CalculoMutation.mutateAsync,
    criando13: criar13CalculoMutation.isPending,
    criarRescisao: criarRescisaoMutation.mutateAsync,
    criandoRescisao: criarRescisaoMutation.isPending,
    atualizarRescisao: atualizarRescisaoMutation.mutateAsync,

    // Cálculos puros (client-side)
    calcularFolhaMensal,
    calcularFerias,
    calcular13,
    calcularRescisao,
    calcularProvisao,
  };
}
