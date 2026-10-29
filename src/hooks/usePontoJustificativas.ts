import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";

export type TipoAbono = "sim" | "nao" | "configuravel";

/** correcao_batida = corrige horário (trabalho, nunca abona);
 *  ausencia = declaração/atestado (sempre com anexo);
 *  null = lançamento do RH (folga, day off...), fora do app. */
export type NaturezaJustificativa = "correcao_batida" | "ausencia" | null;

export interface PontoJustificativa {
  id: string;
  tenant_id: string;
  empresa_id: string | null;
  nome: string;
  descricao: string | null;
  horas_abono: number;
  requer_anexo: boolean;
  ativo: boolean;
  ordem: number;
  /** Regra de abono automático aplicada na aprovação do ajuste. */
  tipo_abono: TipoAbono;
  /** Código estável (justificativas padrão do sistema). */
  codigo: string | null;
  /** true = justificativa padrão do sistema (não pode ser excluída). */
  sistema: boolean;
  /** Citação legal quando o abono é obrigatório por lei (art. 473 CLT).
   *  Preenchido => abono travado em "sim", linha não editável/excluível. */
  base_legal: string | null;
  /** Natureza da justificativa (Fase 2 do Ponto). */
  natureza: NaturezaJustificativa;
  /** true = o colaborador pode escolher no app novo (exige natureza). */
  aparece_no_app: boolean;
  created_at: string;
  updated_at: string;
}

export function usePontoJustificativas() {
  const { tenantId, user, hasMinimumRole } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const qc = useQueryClient();
  const podeGerenciar = hasMinimumRole("admin");

  const list = useQuery({
    queryKey: ["ponto-justificativas", tenantId],
    queryFn: async (): Promise<PontoJustificativa[]> => {
      if (!tenantId) return [];
      const { data, error } = await fromTable("ponto_justificativas")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("ordem", { ascending: true })
        .order("nome", { ascending: true });
      if (error) throw error;
      return (data || []) as PontoJustificativa[];
    },
    enabled: !!tenantId,
  });

  const upsert = useMutation({
    mutationFn: async (j: Partial<PontoJustificativa> & { nome: string; horas_abono: number }) => {
      if (!tenantId || !user) throw new Error("Não autenticado");
      const payload: any = {
        tenant_id: tenantId,
        nome: j.nome.trim(),
        descricao: j.descricao?.trim() || null,
        horas_abono: Number(j.horas_abono) || 0,
        requer_anexo: !!j.requer_anexo,
        ativo: j.ativo !== false,
        ordem: j.ordem ?? 0,
        tipo_abono: (j.tipo_abono as TipoAbono) || "nao",
        natureza: j.natureza ?? null,
        // sem natureza não pode aparecer no app (CHECK no banco)
        aparece_no_app: j.natureza ? !!j.aparece_no_app : false,
      };
      if (j.id) {
        // NÃO sobrescreve empresa_id de uma justificativa existente: as padrão
        // do sistema são semeadas com empresa_id NULL e devem continuar assim
        // (senão o "Restaurar padrões" não as encontra e cria duplicatas).
        const { error } = await fromTable("ponto_justificativas").update(payload).eq("id", j.id);
        if (error) throw error;
      } else {
        const { error } = await fromTable("ponto_justificativas")
          .insert({ ...payload, empresa_id: empresaAtivaId || null, created_by: user.id });
        if (error) throw error;
      }
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["ponto-justificativas"] });
      toast.success("Justificativa salva!");
    },
    onError: (e: any) => toast.error(e.message || "Erro ao salvar."),
  });

  const remove = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await fromTable("ponto_justificativas").delete().eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["ponto-justificativas"] });
      toast.success("Justificativa removida.");
    },
    onError: (e: any) => toast.error(e.message || "Erro ao remover."),
  });

  const restaurarPadroes = useMutation({
    mutationFn: async () => {
      if (!tenantId) throw new Error("Não autenticado");
      const { error } = await (supabase.rpc as any)("seed_justificativas_padrao", { p_tenant_id: tenantId });
      if (error) throw error;
      // Catálogo do app novo (APP_* + ausências). Idempotente; checa o tenant no banco.
      const rpc = supabase.rpc as unknown as (fn: string, args: Record<string, unknown>) => Promise<{ error: Error | null }>;
      const { error: errApp } = await rpc("seed_justificativas_app", { p_tenant: tenantId });
      if (errApp) throw errApp;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["ponto-justificativas"] });
      toast.success("Justificativas padrão restauradas!");
    },
    onError: (e: any) => toast.error(e.message || "Erro ao restaurar padrões."),
  });

  return {
    justificativas: list.data || [],
    loading: list.isLoading,
    podeGerenciar,
    salvar: upsert.mutateAsync,
    salvando: upsert.isPending,
    remover: remove.mutateAsync,
    restaurarPadroes: restaurarPadroes.mutateAsync,
    restaurando: restaurarPadroes.isPending,
  };
}
