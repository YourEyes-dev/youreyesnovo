import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuthContext } from "@/contexts/AuthContext";
import { toast } from "sonner";
import type { ParceiroTipo, ParceiroStatus } from "@/hooks/useParceiros";

// Área do Parceiro — tudo vem de UMA função (parceiro_meu_portal), que só
// devolve o que é do próprio parceiro e nunca dado de pessoa física.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const sb = supabase as any;

export type Estagio = "lead" | "proposta" | "contrato" | "implantacao" | "go_live" | "ativo" | "churn";
export const ESTAGIO_LABEL: Record<Estagio, string> = {
  lead: "Lead", proposta: "Proposta", contrato: "Contrato", implantacao: "Implantação",
  go_live: "Go-live", ativo: "Ativo", churn: "Churn",
};

export interface CarteiraItem {
  tipo: "empresa" | "lead";
  id: string;
  nome: string;
  plano: string | null;
  mrr_cents: number;
  estagio: Estagio;
  papel: "origem" | "implantacao" | "origem+implantacao";
  proximo_passo: string;
  comissao_mes_cents: number;
  aviso: string | null;
  ciclo_fim: string | null;
  desde: string | null;
}

export interface PortalParceiroDados {
  parceiro: {
    id: string; codigo: string; nome: string; tipo_parceiro: ParceiroTipo; status: ParceiroStatus;
    cidade: string | null; uf: string | null; parceiro_desde: string; trilha: string;
    email: string | null; telefone: string | null; endereco?: string | null; pix_chave: string | null; marketplace_profissional_id: string | null;
  };
  nivel: { nome: string | null; percentual: number; bonus_renovacao: number | null };
  proximo_nivel: { nome: string; mrr_minimo_cents: number; percentual: number } | null;
  kpis: {
    mrr_cents: number; comissao_mes_cents: number; ganho_acumulado_cents: number;
    clientes_ativos: number; em_implantacao: number;
    leads_90d: number; propostas_90d: number; contratos_90d: number; fecha_dia: number; paga_dia: number;
  };
  links: { id: string; codigo: string; campanha: string; ativo: boolean; cliques: number; leads: number }[];
  carteira: CarteiraItem[];
  extrato: { competencia: string; base_cents: number; percentual: number | null; valor_cents: number; status: string; tipo: string; pago_em: string | null }[];
  renovacoes: { nome: string; ciclo_fim: string; bonus_cents: number }[];
  historico?: { competencia: string; mrr_cents: number }[];
  contrato?: { versao_vigente: number | null; titulo_vigente: string | null; versao_aceita: number | null; aceito_em: string | null; pendente: boolean; aguardando_aprovacao?: boolean; assinatura_token?: string | null; assinatura_id?: string | null };
  situacao?: { status: ParceiroStatus; motivo: string | null; aprovado_em: string | null; criado_em: string; trilha: string | null };
}

const KEY = ["parceiro", "portal"];

export function useParceiroPortal() {
  const { user, parceiroId } = useAuthContext();
  const qc = useQueryClient();

  const portal = useQuery({
    queryKey: [...KEY, user?.id],
    enabled: !!user && !!parceiroId,
    queryFn: async (): Promise<PortalParceiroDados | null> => {
      const { data, error } = await sb.rpc("parceiro_meu_portal_com_contrato");
      if (error) throw error;
      return (data as PortalParceiroDados) ?? null;
    },
  });

  const salvarPerfil = useMutation({
    mutationFn: async (dados: Record<string, unknown>) => {
      const { error } = await sb.rpc("parceiro_meu_perfil_salvar", { _dados: dados });
      if (error) throw error;
    },
    onSuccess: () => { qc.invalidateQueries({ queryKey: KEY }); toast.success("Dados salvos"); },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : "Não foi possível salvar"),
  });

  return { dados: portal.data ?? null, isLoading: portal.isLoading, isError: portal.isError, refetch: portal.refetch, salvarPerfil };
}

export function formatarReais(cents: number | null | undefined): string {
  return (Number(cents || 0) / 100).toLocaleString("pt-BR", { style: "currency", currency: "BRL", maximumFractionDigits: 0 });
}

export function linkPublico(codigo: string): string {
  const base = (import.meta.env.VITE_APP_URL as string | undefined) || window.location.origin;
  return `${base.replace(/\/$/, "")}/?ref=${codigo}`;
}
// Link direto para contratar: cai no site já na seção de planos, com a origem registrada.
export function linkContratar(codigo: string): string {
  return `${linkPublico(codigo)}#planos`;
}
