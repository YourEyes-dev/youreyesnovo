import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";
import { handleMutationError } from "@/lib/toastError";
import { format } from "date-fns";

export interface PontoFechamento {
  id: string;
  tenant_id: string;
  empresa_id: string | null;
  competencia: string;
  data_fechamento: string | null;
  status: string;
  fechado_por: string | null;
  fechado_por_nome: string | null;
  total_colaboradores: number;
  total_horas_normais_minutos: number;
  total_horas_extras_minutos: number;
  total_adicional_noturno_minutos: number;
  total_faltas: number;
  total_atrasos: number;
  observacoes: string | null;
  created_at: string;
}

export interface PontoEspelho {
  id: string;
  tenant_id: string;
  colaborador_id: string;
  colaborador_nome: string;
  colaborador_cpf: string;
  competencia: string;
  total_horas_normais_minutos: number;
  total_horas_extras_50_minutos: number;
  total_horas_extras_100_minutos: number;
  total_adicional_noturno_minutos: number;
  total_faltas: number;
  total_atrasos_minutos: number;
  total_dsr: number;
  banco_horas_saldo_minutos: number;
  // Campos vindos da apuração (ponto_saldo_dias_competencia). Os de cima,
  // de HE 50/100 e adicional noturno, permanecem para não quebrar espelho
  // já emitido, mas a consolidação atual não os preenche.
  total_trabalhado_minutos?: number | null;
  total_jornada_prevista_minutos?: number | null;
  total_creditos_minutos?: number | null;
  total_debitos_minutos?: number | null;
  total_dias_trabalhados?: number | null;
  total_dias_protegidos?: number | null;
  total_excedente_retido_minutos?: number | null;
  dia_equalizacao?: string | null;
  status: string;
  ressalva_texto: string | null;
  data_confirmacao: string | null;
  created_at: string | null;
}

export function usePontoFechamento() {
  const { tenantId, user, profile } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const queryClient = useQueryClient();

  const useFechamentos = () => {
    return useQuery({
      queryKey: ["ponto-fechamentos", tenantId, empresaAtivaId],
      queryFn: async (): Promise<PontoFechamento[]> => {
        if (!tenantId) return [];
        let query = fromTable("ponto_fechamentos")
          .select("*")
          .eq("tenant_id", tenantId);
        if (empresaAtivaId) query = query.eq("empresa_id", empresaAtivaId);
        const { data, error } = await query.order("competencia", { ascending: false }) as { data: PontoFechamento[] | null; error: Error | null };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId,
    });
  };

  const useEspelhos = (competencia: string) => {
    return useQuery({
      queryKey: ["ponto-espelhos", tenantId, empresaAtivaId, competencia],
      queryFn: async (): Promise<PontoEspelho[]> => {
        if (!tenantId) return [];
        // Por empresa, como a listagem de fechamentos logo acima: o
        // espelho é da empresa que fechou, não do tenant inteiro.
        let query = fromTable("ponto_espelhos")
          .select("*")
          .eq("tenant_id", tenantId)
          .eq("competencia", competencia);
        if (empresaAtivaId) query = query.eq("empresa_id", empresaAtivaId);
        const { data, error } = await query
          .order("colaborador_nome") as { data: PontoEspelho[] | null; error: Error | null };
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId && !!competencia,
    });
  };

  const fecharPeriodoMutation = useMutation({
    mutationFn: async ({ competencia, observacoes }: { competencia: string; observacoes?: string }) => {
      if (!tenantId || !user) throw new Error("Não autenticado");

      // PORTÃO DO FECHAMENTO (PONTO-387/388): o banco recusa fechar a
      // competência com pendência crítica aberta — ajuste pendente de
      // aprovação, dia incompleto sem tratamento ou espelho sem ciência do
      // colaborador (Súmula 338 do TST). Fechar por cima manda dado errado
      // para a folha e, depois de fechada, a competência não se mexe.
      const { error: portaoErr } = await (supabase.rpc as any)(
        "ponto_fechar_competencia_verificar",
        {
          p_tenant_id: tenantId,
          p_empresa_id: empresaAtivaId || null,
          p_competencia: competencia,
        }
      );
      if (portaoErr) {
        throw new Error(
          "Não é possível fechar esta competência: há pendências que precisam ser tratadas antes. " +
            "Veja a lista em \"Pendências que impedem o fechamento\". " +
            `(Detalhe técnico: ${portaoErr.message})`
        );
      }

      // A MESMA fonte da pré-visualização que aparece acima do botão:
      // ponto_espelho_resumo_empresa já vem filtrada pela empresa
      // selecionada na barra do topo. Antes daqui saía uma leitura de
      // ponto_diario só por tenant — o fechamento pegava os
      // colaboradores de TODAS as empresas e ainda carimbava cada um com
      // a empresa da vez. Fechava e reatribuía gente que não era dela.
      const { data: resumoRows, error: resumoErr } = await (supabase.rpc as any)(
        "ponto_espelho_resumo_empresa",
        {
          p_tenant_id: tenantId,
          p_empresa_id: empresaAtivaId || null,
          p_competencia: competencia,
        }
      );
      if (resumoErr) throw resumoErr;

      const linhas = (resumoRows || []) as any[];
      if (linhas.length === 0) {
        throw new Error(
          "Nenhum colaborador desta empresa tem ponto apurado nesta competência."
        );
      }

      const somar = (campo: string) =>
        linhas.reduce((acc, l) => acc + (Number(l[campo]) || 0), 0);

      // Atraso não é apurado pelo modelo atual (o saldo é em minutos, não
      // em ocorrências). Fica no que já estava gravado em vez de afirmar
      // zero — ver a nota de HE 50/100 no espelho.
      const { data: fechamento, error: fechError } = await fromTable("ponto_fechamentos")
        .upsert({
          tenant_id: tenantId,
          empresa_id: empresaAtivaId || null,
          competencia,
          data_fechamento: new Date().toISOString(),
          status: "fechado",
          fechado_por: user.id,
          fechado_por_nome: profile?.nome_completo,
          total_colaboradores: linhas.length,
          total_horas_normais_minutos: somar("total_trabalhado_min"),
          total_horas_extras_minutos: somar("total_creditos_min"),
          total_faltas: somar("total_faltas"),
          observacoes,
        } as never, { onConflict: "tenant_id,empresa_id,competencia" })
        .select()
        .single();

      if (fechError) throw fechError;

      // Um espelho por colaborador da empresa. Os totais vêm da APURAÇÃO,
      // não das colunas de ponto_diario: as de HE 50/100, adicional
      // noturno e atraso deixaram de ser preenchidas quando a
      // consolidação foi reescrita, e somá-las zerava o espelho inteiro.
      for (const l of linhas) {
        await fromTable("ponto_espelhos")
          .upsert({
            tenant_id: tenantId,
            empresa_id: empresaAtivaId || null,
            fechamento_id: (fechamento as any).id,
            colaborador_id: l.colaborador_id,
            colaborador_nome: l.colaborador_nome,
            colaborador_cpf: l.colaborador_cpf,
            competencia,
            total_horas_normais_minutos: Number(l.total_trabalhado_min) || 0,
            total_trabalhado_minutos: Number(l.total_trabalhado_min) || 0,
            total_jornada_prevista_minutos: Number(l.total_jornada_prevista_min) || 0,
            total_creditos_minutos: Number(l.total_creditos_min) || 0,
            total_debitos_minutos: Number(l.total_debitos_min) || 0,
            // RN28: crédito do banco vira HE 50% (jornada normal) e HE 100%
            // (domingo/feriado trabalhado). Débito não gera hora extra.
            total_horas_extras_50_minutos: Number(l.he_50_min) || 0,
            total_horas_extras_100_minutos: Number(l.he_100_min) || 0,
            total_atrasos_minutos: Number(l.atrasos_min) || 0,
            banco_horas_saldo_minutos: Number(l.saldo_banco_min ?? l.saldo_min) || 0,
            total_faltas: Number(l.total_faltas) || 0,
            total_dias_trabalhados: Number(l.dias_trabalhados) || 0,
            total_dias_protegidos: Number(l.dias_protegidos) || 0,
            total_excedente_retido_minutos: Number(l.excedente_retido_min) || 0,
            dia_equalizacao: l.dia_equalizacao || null,
            status: "gerado",
          } as never, { onConflict: "tenant_id,colaborador_cpf,competencia" });
      }


      // RN29 — o resultado positivo do ciclo já foi pago como hora extra
      // (HE 50/100) no espelho, então não pode transitar para o mês
      // seguinte: só o saldo negativo é transferido. A regra roda no banco
      // (SECURITY DEFINER), que também grava o Saldo Anterior da
      // competência seguinte — origem única e rastreável do número.
      const { error: rn29Err } = await (supabase.rpc as any)(
        "ponto_fechar_competencia_banco",
        {
          p_tenant_id: tenantId,
          p_empresa_id: empresaAtivaId || null,
          p_competencia: competencia,
        }
      );
      if (rn29Err) throw rn29Err;


      return fechamento;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ponto-banco-horas"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-fechamentos"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-espelhos"] });
      toast.success("Período fechado com sucesso!");
    },
    onError: (e: Error) => toast.error("Erro ao fechar período: " + e.message),
  });

  /**
   * Reabertura de competência já fechada. O fechamento não é definitivo:
   * quando a apuração sai errada, o RH precisa corrigir e fechar de novo.
   * Os espelhos ainda não assinados (gerado/enviado) são descartados para
   * não conviverem dois documentos com números diferentes; os já
   * confirmados ou com ressalva permanecem como prova do que foi aceito.
   */
  const reabrirPeriodoMutation = useMutation({
    mutationFn: async ({ competencia, motivo }: { competencia: string; motivo?: string }) => {
      if (!tenantId || !user) throw new Error("Não autenticado");

      let del = fromTable("ponto_espelhos")
        .delete()
        .eq("tenant_id", tenantId)
        .eq("competencia", competencia)
        .in("status", ["gerado", "enviado"]);
      if (empresaAtivaId) del = del.eq("empresa_id", empresaAtivaId);
      const { error: delErr } = await del;
      if (delErr) throw delErr;

      let upd = fromTable("ponto_fechamentos")
        .update({
          status: "aberto",
          data_fechamento: null,
          fechado_por: null,
          fechado_por_nome: null,
          observacoes: motivo
            ? `Reaberto em ${format(new Date(), "dd/MM/yyyy HH:mm")} por ${profile?.nome_completo || "usuário"}: ${motivo}`
            : null,
        } as any)
        .eq("tenant_id", tenantId)
        .eq("competencia", competencia);
      if (empresaAtivaId) upd = upd.eq("empresa_id", empresaAtivaId);
      const { error } = await upd;
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ponto-fechamentos"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-espelhos"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-espelhos-preview"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-fechamento-pendencias"] });
      toast.success("Período reaberto — pode corrigir e fechar novamente.");
    },
    onError: (e: Error) => toast.error("Erro ao reabrir período: " + e.message),
  });

  const confirmarEspelhoMutation = useMutation({
    mutationFn: async ({ espelhoId, ressalva }: { espelhoId: string; ressalva?: string }) => {
      if (!user) throw new Error("Não autenticado");
      const { error } = await fromTable("ponto_espelhos")
        .update({
          status: ressalva ? "ressalva" : "confirmado",
          ressalva_texto: ressalva || null,
          data_confirmacao: new Date().toISOString(),
          confirmado_por: user.id,
        } as any)
        .eq("id", espelhoId);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ponto-espelhos"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-fechamento-pendencias"] });
      toast.success("Espelho confirmado!");
    },
    onError: handleMutationError,
  });

  return {
    useFechamentos,
    useEspelhos,
    fecharPeriodo: fecharPeriodoMutation.mutateAsync,
    fechandoPeriodo: fecharPeriodoMutation.isPending,
    reabrirPeriodo: reabrirPeriodoMutation.mutateAsync,
    reabrindoPeriodo: reabrirPeriodoMutation.isPending,

    confirmarEspelho: confirmarEspelhoMutation.mutateAsync,
    confirmandoEspelho: confirmarEspelhoMutation.isPending,
  };
}
