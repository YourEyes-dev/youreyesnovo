import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "./useAuth";
import { toast } from "sonner";

const TABELA = "mapa_comportamental_contestacoes";

export type ContestacaoStatus = "aberta" | "em_analise" | "resolvida";

export interface Contestacao {
  id: string;
  mapa_id: string | null;
  auth_user_id: string | null;
  colaborador_nome: string | null;
  colaborador_cpf: string | null;
  texto: string;
  solicitou_reaplicacao: boolean;
  status: ContestacaoStatus;
  resposta: string | null;
  resolvido_por_nome: string | null;
  resolvido_em: string | null;
  created_at: string;
}

/** As contestações que o próprio titular abriu (por auth_user_id ou CPF, via RLS). */
export function useMinhasContestacoes() {
  const { tenantId, user } = useAuth();
  return useQuery({
    queryKey: ["mapa-contestacoes", "minhas", tenantId, user?.id],
    queryFn: async (): Promise<Contestacao[]> => {
      const { data, error } = await fromTable(TABELA)
        .select("*")
        .order("created_at", { ascending: false });
      if (error) throw error;
      // RLS já restringe ao próprio titular + (quem tem o módulo). Aqui filtramos
      // para o que é do próprio usuário, para a tela "Meu Mapa".
      return ((data ?? []) as Contestacao[]).filter((c) => c.auth_user_id === user?.id);
    },
    enabled: !!tenantId && !!user?.id,
  });
}

/** Abrir uma contestação do próprio mapa. Identidade carimbada no servidor. */
export function useCriarContestacao() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: { mapaId: string | null; texto: string; solicitouReaplicacao: boolean }) => {
      const { error } = await fromTable(TABELA).insert({
        mapa_id: input.mapaId,
        texto: input.texto,
        solicitou_reaplicacao: input.solicitouReaplicacao,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["mapa-contestacoes"] });
      toast.success("Contestação registrada. O RH vai analisar.");
    },
    onError: (e: Error) => toast.error("Não foi possível registrar", { description: e.message }),
  });
}

/** Lista de contestações do tenant (gestor/RH) — para análise na Governança. */
export function useContestacoes(enabled: boolean) {
  const { tenantId } = useAuth();
  return useQuery({
    queryKey: ["mapa-contestacoes", "tenant", tenantId],
    queryFn: async (): Promise<Contestacao[]> => {
      const { data, error } = await fromTable(TABELA)
        .select("*")
        .order("created_at", { ascending: false });
      if (error) throw error;
      return (data ?? []) as Contestacao[];
    },
    enabled: !!tenantId && enabled,
  });
}

/** Resolver (ou marcar em análise) uma contestação — gestor/RH. */
export function useResolverContestacao() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: { id: string; status: ContestacaoStatus; resposta?: string }) => {
      const patch: Record<string, unknown> = { status: input.status };
      if (input.resposta !== undefined) patch.resposta = input.resposta;
      const { error } = await fromTable(TABELA).update(patch).eq("id", input.id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["mapa-contestacoes"] });
      toast.success("Contestação atualizada.");
    },
    onError: (e: Error) => toast.error("Não foi possível atualizar", { description: e.message }),
  });
}
