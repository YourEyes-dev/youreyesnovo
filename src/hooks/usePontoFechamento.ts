import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";
import { handleMutationError } from "@/lib/toastError";
import { arquivarDocumento } from "@/utils/arquivarDocumento";

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
  /** colaborador_eletronica | papel_digitalizado | rh_legado; nula = sem ciência. */
  ciencia_origem?: string | null;
  arquivo_url?: string | null;
  empresa_id?: string | null;
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
            // SEM `status` de propósito: no refechamento a linha já existe e
            // pode ter a ciência do colaborador (confirmado/ressalva/assinado).
            // Mandar status "gerado" aqui apagava essa ciência. Linha nova
            // nasce "gerado" pelo padrão da coluna.
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
   * Quem reabre é o SERVIDOR (ponto_reabrir_competencia, PONTO-358): arquiva
   * todos os espelhos da competência no histórico (versão anterior), retira os
   * que ainda não têm ciência (serão gerados de novo no próximo fechamento) e
   * mantém os que já têm ciência do colaborador. Antes a tela apagava espelhos
   * pelo navegador, sem histórico.
   */
  const reabrirPeriodoMutation = useMutation({
    mutationFn: async ({ competencia, motivo }: { competencia: string; motivo?: string }) => {
      if (!tenantId || !user) throw new Error("Não autenticado");
      const { data, error } = await (supabase.rpc as any)("ponto_reabrir_competencia", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaAtivaId || null,
        p_competencia: competencia,
        p_motivo: motivo || "",
        p_por: user.id,
        p_por_nome: profile?.nome_completo || null,
      });
      if (error) throw error;
      const res = (data || {}) as { ok?: boolean; erro?: string };
      if (!res.ok) {
        const MSG: Record<string, string> = {
          motivo_obrigatorio: "Informe o motivo da reabertura.",
          competencia_sem_fechamento: "Esta competência ainda não foi fechada.",
          competencia_nao_esta_fechada: "Esta competência não está fechada.",
          sem_alcada_para_reabrir: "Seu acesso não permite reabrir competência (só gestão).",
        };
        throw new Error(MSG[res.erro || ""] || res.erro || "Não foi possível reabrir.");
      }
      return res;
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

  /**
   * "Registrar ciência em papel": o colaborador assinou o espelho IMPRESSO e o
   * RH anexa a digitalização. O papel vai para Documentos (pasta do
   * colaborador) e o servidor grava a ciência como papel_digitalizado — quem
   * deu a ciência foi o colaborador; quem registrou fica só na trilha.
   * Substitui o antigo "Confirmar", que gravava o id do RH como se fosse a
   * ciência do trabalhador.
   */
  const registrarCienciaPapelMutation = useMutation({
    mutationFn: async ({
      espelho,
      arquivo,
      ressalva,
    }: {
      espelho: PontoEspelho;
      arquivo: File;
      ressalva?: string;
    }) => {
      if (!tenantId || !user) throw new Error("Não autenticado");
      if (!arquivo) throw new Error("Anexe o papel assinado (PDF ou foto).");
      const extensao = (arquivo.name.split(".").pop() || "pdf").toLowerCase();
      const arquivado = await arquivarDocumento({
        tenantId,
        empresaId: empresaAtivaId,
        userId: user.id,
        userNome: profile?.nome_completo || "Sistema",
        file: arquivo,
        fileName: `Espelho de Ponto assinado (papel) - ${espelho.colaborador_nome} - ${espelho.competencia}.${extensao}`,
        mimeType: arquivo.type || "application/pdf",
        tipo: "Espelho de Ponto assinado",
        observacoes: `Ciência do espelho de ponto ${espelho.competencia} em papel, digitalizada.`,
        colaboradorId: espelho.colaborador_id || null,
        colaboradorNome: espelho.colaborador_nome,
        colaboradorCpf: espelho.colaborador_cpf,
        subpastaColaborador: "Vida Funcional",
      });
      if (!arquivado?.id) throw new Error("Não foi possível guardar o papel em Documentos.");

      const { data, error } = await (supabase.rpc as any)("ponto_espelho_registrar_ciencia_papel", {
        p_espelho_id: espelho.id,
        p_documento_id: arquivado.id,
        p_ressalva: ressalva?.trim() || null,
      });
      if (error) throw error;
      const res = (data || {}) as { ok?: boolean; erro?: string };
      if (!res.ok) {
        const MSG: Record<string, string> = {
          anexo_obrigatorio: "Anexe o papel assinado.",
          anexo_de_outro_colaborador: "O papel anexado é de outro colaborador.",
          espelho_ja_tem_ciencia: "Este espelho já tem ciência registrada.",
          sem_permissao: "Seu acesso não permite registrar ciência de espelho.",
          espelho_de_outra_empresa: "Este espelho é de outra empresa.",
        };
        throw new Error(MSG[res.erro || ""] || res.erro || "Não foi possível registrar.");
      }
      return res;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ponto-espelhos"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-fechamento-pendencias"] });
      toast.success("Ciência em papel registrada e papel guardado em Documentos.");
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

    registrarCienciaPapel: registrarCienciaPapelMutation.mutateAsync,
    registrandoCienciaPapel: registrarCienciaPapelMutation.isPending,
  };
}
