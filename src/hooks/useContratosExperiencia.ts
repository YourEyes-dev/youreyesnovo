import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";
import { addDays, differenceInDays, format, parseISO } from "date-fns";

export interface ContratoExperiencia {
  id: string;
  tenant_id: string;
  empresa_id: string | null;
  admissao_id: string | null;
  colaborador_nome: string;
  colaborador_cpf: string;
  cargo: string | null;
  departamento: string | null;
  filial: string | null;
  gestor_imediato: string | null;
  salario: number | null;
  jornada_trabalho: string | null;
  data_admissao: string;
  duracao_primeiro_periodo: number;
  data_fim_primeiro_periodo: string;
  prorrogado: boolean;
  duracao_prorrogacao: number | null;
  data_inicio_prorrogacao: string | null;
  data_fim_prorrogacao: string | null;
  data_prorrogacao_registro: string | null;
  prorrogado_por: string | null;
  prorrogado_por_nome: string | null;
  clausula_assecuratoria: boolean;
  status: string;
  data_efetivacao: string | null;
  efetivado_por: string | null;
  efetivado_por_nome: string | null;
  data_encerramento: string | null;
  tipo_encerramento: string | null;
  motivo_encerramento: string | null;
  encerrado_por: string | null;
  encerrado_por_nome: string | null;
  alerta_15_dias_enviado: boolean;
  alerta_7_dias_enviado: boolean;
  alerta_2_dias_enviado: boolean;
  observacoes: string | null;
  created_at: string;
  updated_at: string;
}

// ========== REGRAS DE NEGÓCIO ==========

const MAX_DIAS_EXPERIENCIA = 90;

export function validarProrrogacao(contrato: ContratoExperiencia): {
  permitido: boolean;
  motivo?: string;
  diasDisponiveis: number;
} {
  if (contrato.prorrogado) {
    return { permitido: false, motivo: "Contrato já foi prorrogado uma vez. Limite de uma prorrogação (CLT art. 445).", diasDisponiveis: 0 };
  }
  if (contrato.status !== "em_experiencia") {
    return { permitido: false, motivo: "Contrato não está em período de experiência ativo.", diasDisponiveis: 0 };
  }
  const diasUsados = contrato.duracao_primeiro_periodo;
  const diasDisponiveis = MAX_DIAS_EXPERIENCIA - diasUsados;
  if (diasDisponiveis <= 0) {
    return { permitido: false, motivo: "O limite de 90 dias já foi alcançado no primeiro período.", diasDisponiveis: 0 };
  }
  return { permitido: true, diasDisponiveis };
}

export function calcularDataFim(dataInicio: string, dias: number): string {
  return format(addDays(parseISO(dataInicio), dias - 1), "yyyy-MM-dd");
}

export function getDataFimAtual(contrato: ContratoExperiencia): string {
  return contrato.prorrogado && contrato.data_fim_prorrogacao
    ? contrato.data_fim_prorrogacao
    : contrato.data_fim_primeiro_periodo;
}

export function getDiasRestantes(contrato: ContratoExperiencia): number {
  const dataFim = getDataFimAtual(contrato);
  return differenceInDays(parseISO(dataFim), new Date());
}

export function getPeriodoAtual(contrato: ContratoExperiencia): string {
  if (contrato.status === "efetivado") return "Efetivado";
  if (contrato.status === "encerrado") return "Encerrado";
  if (contrato.status === "vencido_automatico") return "Vencido (indeterminado)";
  return contrato.prorrogado ? "2º Período" : "1º Período";
}

export function getDuracaoTotal(contrato: ContratoExperiencia): number {
  return contrato.duracao_primeiro_periodo + (contrato.duracao_prorrogacao || 0);
}

// ========== HOOK ==========

export function useContratosExperiencia() {
  const { tenantId, user, profile } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const queryClient = useQueryClient();

  const contratosQuery = useQuery({
    queryKey: ["contratos-experiencia", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      // Lê pela visão com o salário mascarado por "pode ver salário" do perfil (as escritas seguem na tabela).
      let query = fromTable("contratos_experiencia_segura")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("created_at", { ascending: false });
      if (empresaAtivaId) query = query.eq("empresa_id", empresaAtivaId);
      const { data, error } = await query as { data: any[] | null; error: any };
      if (error) throw error;
      return (data || []) as ContratoExperiencia[];
    },
    enabled: !!tenantId,
  });

  const historicoQuery = (contratoId: string) =>
    useQuery({
      queryKey: ["contratos-experiencia-historico", contratoId],
      queryFn: async () => {
        const { data, error } = await fromTable("contratos_experiencia_historico")
          .select("*")
          .eq("contrato_id", contratoId)
          .order("created_at", { ascending: false }) as { data: any[] | null; error: any };
        if (error) throw error;
        return data || [];
      },
      enabled: !!contratoId,
    });

  async function registrarHistorico(contratoId: string, acao: string, descricao: string, dados?: any) {
    await fromTable("contratos_experiencia_historico")
      .insert({
        tenant_id: tenantId,
        contrato_id: contratoId,
        acao,
        descricao,
        dados: dados || null,
        usuario_id: user?.id,
        usuario_nome: profile?.nome_completo || user?.email,
      } as any);
  }

  // Criar contrato
  const criarContratoMutation = useMutation({
    mutationFn: async (dados: Partial<ContratoExperiencia> & {
      colaborador_nome: string;
      colaborador_cpf: string;
      data_admissao: string;
      duracao_primeiro_periodo: number;
    }) => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      
      // Validar duração
      if (dados.duracao_primeiro_periodo > MAX_DIAS_EXPERIENCIA) {
        throw new Error(`Duração máxima do contrato de experiência é ${MAX_DIAS_EXPERIENCIA} dias (CLT art. 445).`);
      }

      const dataFim = calcularDataFim(dados.data_admissao, dados.duracao_primeiro_periodo);

      const { data, error } = await fromTable("contratos_experiencia")
        .insert({
          ...dados,
          tenant_id: tenantId,
          empresa_id: empresaAtivaId || dados.empresa_id || null,
          data_fim_primeiro_periodo: dataFim,
          status: "em_experiencia",
        } as any)
        .select()
        .single();
      if (error) throw error;

      await registrarHistorico((data as any).id, "criacao",
        `Contrato de experiência criado. Período: ${dados.duracao_primeiro_periodo} dias. Término: ${dataFim}.`);

      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["contratos-experiencia"] });
      toast.success("Contrato de experiência criado!");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  // Prorrogar
  const prorrogarMutation = useMutation({
    mutationFn: async ({ id, duracao_prorrogacao }: { id: string; duracao_prorrogacao: number }) => {
      // Buscar contrato atual
      const { data: contrato } = await fromTable("contratos_experiencia_segura")
        .select("*")
        .eq("id", id)
        .single() as { data: ContratoExperiencia | null };

      if (!contrato) throw new Error("Contrato não encontrado");

      const validacao = validarProrrogacao(contrato);
      if (!validacao.permitido) throw new Error(validacao.motivo);
      if (duracao_prorrogacao > validacao.diasDisponiveis) {
        throw new Error(`Prorrogação máxima permitida: ${validacao.diasDisponiveis} dias (limite de 90 dias no total).`);
      }

      const dataInicioProrr = addDays(parseISO(contrato.data_fim_primeiro_periodo), 1);
      const dataFimProrr = calcularDataFim(format(dataInicioProrr, "yyyy-MM-dd"), duracao_prorrogacao);

      const { data, error } = await fromTable("contratos_experiencia")
        .update({
          prorrogado: true,
          duracao_prorrogacao,
          data_inicio_prorrogacao: format(dataInicioProrr, "yyyy-MM-dd"),
          data_fim_prorrogacao: dataFimProrr,
          data_prorrogacao_registro: new Date().toISOString(),
          prorrogado_por: user?.id,
          prorrogado_por_nome: profile?.nome_completo || user?.email,
          status: "em_experiencia_2_periodo",
          alerta_15_dias_enviado: false,
          alerta_7_dias_enviado: false,
          alerta_2_dias_enviado: false,
        } as any)
        .eq("id", id)
        .select()
        .single();
      if (error) throw error;

      await registrarHistorico(id, "prorrogacao",
        `Contrato prorrogado por ${duracao_prorrogacao} dias. Novo término: ${dataFimProrr}. Total: ${contrato.duracao_primeiro_periodo + duracao_prorrogacao} dias.`);

      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["contratos-experiencia"] });
      toast.success("Contrato prorrogado com sucesso!");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  // Efetivar
  const efetivarMutation = useMutation({
    mutationFn: async ({ id, data_efetivacao }: { id: string; data_efetivacao?: string }) => {
      const dataEfetivacao = data_efetivacao || format(new Date(), "yyyy-MM-dd");

      const { data, error } = await fromTable("contratos_experiencia")
        .update({
          status: "efetivado",
          data_efetivacao: dataEfetivacao,
          efetivado_por: user?.id,
          efetivado_por_nome: profile?.nome_completo || user?.email,
        } as any)
        .eq("id", id)
        .select()
        .single();
      if (error) throw error;

      // Atualizar admissão para prazo indeterminado
      const contrato = data as any;
      if (contrato.admissao_id) {
        await supabase
          .from("admissoes")
          .update({ tipo_contrato: "clt", tipo_vinculo: "CLT_PRAZO_INDETERMINADO" })
          .eq("id", contrato.admissao_id);
      }

      await registrarHistorico(id, "efetivacao",
        `Colaborador efetivado em ${dataEfetivacao}. Vínculo convertido para prazo indeterminado.`);

      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["contratos-experiencia"] });
      queryClient.invalidateQueries({ queryKey: ["colaboradores"] });
      queryClient.invalidateQueries({ queryKey: ["colaboradores-list"] });
      toast.success("Colaborador efetivado com sucesso!");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  // Encerrar
  const encerrarMutation = useMutation({
    mutationFn: async ({
      id,
      tipo_encerramento,
      motivo_encerramento,
      data_encerramento,
    }: {
      id: string;
      tipo_encerramento: string;
      motivo_encerramento?: string;
      data_encerramento?: string;
    }) => {
      const dataEnc = data_encerramento || format(new Date(), "yyyy-MM-dd");

      const { data, error } = await fromTable("contratos_experiencia")
        .update({
          status: "encerrado",
          data_encerramento: dataEnc,
          tipo_encerramento,
          motivo_encerramento: motivo_encerramento || null,
          encerrado_por: user?.id,
          encerrado_por_nome: profile?.nome_completo || user?.email,
        } as any)
        .eq("id", id)
        .select()
        .single();
      if (error) throw error;

      const tiposLabel: Record<string, string> = {
        termino_normal: "Término normal do contrato de experiência",
        rescisao_antecipada_empregador: "Rescisão antecipada pelo empregador",
        rescisao_antecipada_empregado: "Rescisão antecipada pelo empregado",
      };

      await registrarHistorico(id, "encerramento",
        `Contrato encerrado: ${tiposLabel[tipo_encerramento] || tipo_encerramento}. Data: ${dataEnc}.${motivo_encerramento ? ` Motivo: ${motivo_encerramento}` : ""}`);

      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["contratos-experiencia"] });
      toast.success("Contrato encerrado!");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  // Métricas
  const contratos = contratosQuery.data || [];
  const emExperiencia = contratos.filter(c => c.status === "em_experiencia" || c.status === "em_experiencia_2_periodo");
  const vencendo15Dias = emExperiencia.filter(c => {
    const dias = getDiasRestantes(c);
    return dias >= 0 && dias <= 15;
  });
  const vencendo7Dias = emExperiencia.filter(c => {
    const dias = getDiasRestantes(c);
    return dias >= 0 && dias <= 7;
  });
  const vencendo30Dias = emExperiencia.filter(c => {
    const dias = getDiasRestantes(c);
    return dias >= 0 && dias <= 30;
  });

  return {
    contratos,
    isLoading: contratosQuery.isLoading,
    emExperiencia,
    vencendo15Dias,
    vencendo7Dias,
    vencendo30Dias,
    useHistorico: historicoQuery,

    criarContrato: criarContratoMutation.mutateAsync,
    criando: criarContratoMutation.isPending,
    prorrogar: prorrogarMutation.mutateAsync,
    prorrogando: prorrogarMutation.isPending,
    efetivar: efetivarMutation.mutateAsync,
    efetivando: efetivarMutation.isPending,
    encerrar: encerrarMutation.mutateAsync,
    encerrando: encerrarMutation.isPending,
  };
}
