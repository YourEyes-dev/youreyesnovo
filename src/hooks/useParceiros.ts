import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuthContext } from "@/contexts/AuthContext";
import { toast } from "sonner";
import { sendEmail } from "@/utils/sendEmail";

// Programa de Parceiros — dados para a gestão no SuperAdmin (Onda 1).
// As tabelas ainda não estão em types.ts (regeneradas após aplicar no
// staging), por isso as chamadas passam por `as any`, como em useSuperAdmin.

export type ParceiroTipo = "indicador" | "representante" | "implantador" | "clinica" | "contabilidade";
export type ParceiroTrilha = "indicador" | "representante" | "operador";
export const PARCEIRO_TRILHA_LABEL: Record<ParceiroTrilha, string> = { indicador: "Indicador", representante: "Representante", operador: "Operador" };
export const TRILHA_PADRAO: Record<ParceiroTipo, ParceiroTrilha> = { indicador: "indicador", representante: "representante", implantador: "operador", clinica: "operador", contabilidade: "operador" };
export type ParceiroStatus = "pendente" | "ativo" | "suspenso" | "encerrado";

export const PARCEIRO_TIPO_LABEL: Record<ParceiroTipo, string> = {
  indicador: "Indicador",
  representante: "Representante",
  implantador: "Implantador",
  clinica: "Clínica",
  contabilidade: "Contabilidade",
};

export const PARCEIRO_STATUS_LABEL: Record<ParceiroStatus, string> = {
  pendente: "Pendente",
  ativo: "Ativo",
  suspenso: "Suspenso",
  encerrado: "Encerrado",
};

export interface Parceiro {
  id: string;
  codigo: string;
  nome: string;
  tipo_pessoa: "pf" | "pj";
  documento: string | null;
  tipo_parceiro: ParceiroTipo;
  email: string | null;
  telefone: string | null;
  cidade: string | null;
  uf: string | null;
  cep: string | null;
  raio_atuacao_km: number;
  trilha: ParceiroTrilha;
  nivel_id: string | null;
  nivel_nome: string | null;
  percentual_comissao: number | null;
  status: ParceiroStatus;
  aprovacao: "automatica" | "manual";
  aprovado_em: string | null;
  motivo_recusa: string | null;
  parceiro_desde: string;
  pix_chave: string | null;
  marketplace_profissional_id: string | null;
  observacoes: string | null;
  created_at: string;
  total_clientes: number;
  total_implantacoes: number;
  total_leads: number;
  total_links: number;
  usuarios: string | null;
  contrato?: { versao_vigente: number | null; versao_aceita: number | null; aceito_em: string | null; pendente: boolean } | null;
}

export interface ParceiroDetalhe {
  links: { id: string; codigo: string; campanha: string; ativo: boolean; cliques: number; leads: number }[];
  clientes: { id: string; nome: string; slug: string; ativo: boolean; originado_em: string | null; papel: string; plano: string | null; status_assinatura: string | null }[];
  leads: { id: string; nome: string; empresa: string | null; status: string; atribuicao: string | null; created_at: string }[];
  usuarios: { user_id: string; email: string; papel: string }[];
}

export interface ParceiroTenantResumo {
  id: string;
  nome: string;
  slug: string;
  ativo: boolean;
  parceiro_id: string | null;
  parceiro_nome: string | null;
  implantador_parceiro_id: string | null;
  implantador_nome: string | null;
  originado_em: string | null;
}

export interface ParceiroNivel {
  id?: string;
  trilha: string;
  nome: string;
  ordem: number;
  mrr_minimo_cents: number;
  percentual_link: number;
  percentual_casa: number;
  bonus_renovacao_multiplicador: number;
  setup_participacao_pct?: number;
  mrr_maximo_cents?: number | null;
  beneficios?: string | null;
  ativo: boolean;
}

export interface ParceiroConfigItem {
  chave: string; valor: string; tipo: "numero" | "percentual" | "centavos" | "dias" | "meses" | "texto" | "booleano";
  grupo: string; rotulo: string; descricao: string | null; ordem: number;
}

export interface ParceiroEventoRemuneracao {
  id?: string;
  trilha: string;
  tipo_parceiro: ParceiroTipo;
  evento: "setup_concluido" | "go_live" | "renovacao" | "bonus_retencao_90d" | "fast_start" | "bonus_volume" | "bonus_velocidade" | "decimo_terceiro";
  valor_fixo_cents: number;
  percentual_primeira_mensalidade: number;
  percentual_setup?: number;
  ativo: boolean;
}

export interface ParceiroComissao {
  id: string; parceiro_id: string; parceiro_nome: string; pix_chave: string | null; tenant_nome: string | null;
  competencia: string; tipo: "recorrente" | "bonus_renovacao" | "evento" | "ajuste"; evento: string | null;
  base_cents: number; percentual: number | null; valor_cents: number;
  status: "previsto" | "fechado" | "pago" | "retido"; fechado_em: string | null; pago_em: string | null; observacao: string | null;
}

export interface SugestaoParceiro {
  id: string; nome: string; tipo_parceiro: ParceiroTipo; cidade: string | null; uf: string | null;
  nivel: string | null; clientes: number; motivo: string;
}

const KEY = ["superadmin", "parceiros"];
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const sb = supabase as any;

export function useParceiros() {
  const qc = useQueryClient();
  const { isSuperAdmin } = useAuthContext();
  const invalidar = () => qc.invalidateQueries({ queryKey: KEY });

  const lista = useQuery({
    queryKey: KEY,
    enabled: isSuperAdmin,
    queryFn: async (): Promise<Parceiro[]> => {
      const { data, error } = await sb.rpc("superadmin_parceiros_list");
      if (error) throw error;
      return (data as Parceiro[]) ?? [];
    },
  });

  const tenants = useQuery({
    queryKey: [...KEY, "tenants"],
    enabled: isSuperAdmin,
    queryFn: async (): Promise<ParceiroTenantResumo[]> => {
      const { data, error } = await sb.rpc("superadmin_parceiros_tenants_list");
      if (error) throw error;
      return (data as ParceiroTenantResumo[]) ?? [];
    },
  });

  const niveis = useQuery({
    queryKey: [...KEY, "niveis"],
    enabled: isSuperAdmin,
    queryFn: async (): Promise<ParceiroNivel[]> => {
      const { data, error } = await sb.from("parceiro_niveis").select("*").order("trilha").order("ordem");
      if (error) throw error;
      return (data as ParceiroNivel[]) ?? [];
    },
  });

  const config = useQuery({
    queryKey: [...KEY, "config"],
    enabled: isSuperAdmin,
    queryFn: async (): Promise<ParceiroConfigItem[]> => {
      const { data, error } = await sb.from("parceiro_programa_config").select("*").order("grupo").order("ordem");
      if (error) throw error;
      return (data as ParceiroConfigItem[]) ?? [];
    },
  });

  const eventos = useQuery({
    queryKey: [...KEY, "eventos"],
    enabled: isSuperAdmin,
    queryFn: async (): Promise<ParceiroEventoRemuneracao[]> => {
      const { data, error } = await sb.from("parceiro_eventos_remuneracao").select("*").order("tipo_parceiro").order("evento");
      if (error) throw error;
      return (data as ParceiroEventoRemuneracao[]) ?? [];
    },
  });

  const erro = (e: unknown) => toast.error(e instanceof Error ? e.message : "Não foi possível concluir");

  const salvar = useMutation({
    mutationFn: async (dados: Partial<Parceiro>) => {
      const { data, error } = await sb.rpc("superadmin_parceiro_salvar", { _dados: dados });
      if (error) throw error;
      return data as string;
    },
    onSuccess: () => { invalidar(); toast.success("Parceiro salvo"); },
    onError: erro,
  });

  const mudarStatus = useMutation({
    mutationFn: async (v: { id: string; status: ParceiroStatus; motivo?: string; email?: string | null; nome?: string | null }) => {
      const { error } = await sb.rpc("superadmin_parceiro_status", { _parceiro_id: v.id, _status: v.status, _motivo: v.motivo ?? null });
      if (error) throw error;
      // Avisa o parceiro por e-mail (não bloqueia a operação se o envio falhar)
      if (v.email) {
        const base = ((import.meta.env.VITE_APP_URL as string | undefined) || window.location.origin).replace(/\/$/, "");
        const primeiro = (v.nome || "").split(" ")[0] || "parceiro(a)";
        const conteudo = v.status === "ativo"
          ? { assunto: "Seu cadastro no Programa de Parceiros YourEyes foi aprovado", titulo: `Bem-vindo(a), ${primeiro}!`,
              mensagem: "Seu cadastro foi aprovado pela equipe YourEyes. O próximo passo é assinar eletronicamente o Contrato de Parceria: entre na Área do Parceiro, leia o contrato e assine com selfie e localização. Assim que assinar, seu link de indicação é liberado.",
              actionUrl: `${base}/parceiros/contrato`, actionLabel: "Ler e assinar o contrato" }
          : v.status === "suspenso"
          ? { assunto: "Seu cadastro de parceiro YourEyes foi suspenso", titulo: `Olá, ${primeiro}`,
              mensagem: `Seu cadastro no Programa de Parceiros foi suspenso. ${v.motivo ? `Motivo: ${v.motivo}. ` : ""}Sua carteira fica preservada; fale com a equipe YourEyes para regularizar.`,
              actionUrl: `${base}/parceiros`, actionLabel: "Falar com a YourEyes" }
          : v.status === "encerrado"
          ? { assunto: "Sobre o seu cadastro no Programa de Parceiros YourEyes", titulo: `Olá, ${primeiro}`,
              mensagem: `Seu cadastro no Programa de Parceiros não seguirá adiante. ${v.motivo ? `Motivo: ${v.motivo}. ` : ""}Se quiser conversar sobre isso, fale com a equipe YourEyes.`,
              actionUrl: `${base}/parceiros`, actionLabel: "Falar com a YourEyes" }
          : null;
        if (conteudo) {
          try { await sendEmail({ templateName: "generico", recipientEmail: v.email, templateData: conteudo }); }
          catch (e) { console.error("aviso ao parceiro (nao-fatal):", e); toast.warning("Status atualizado, mas o e-mail de aviso não foi enviado."); }
        }
      }
    },
    onSuccess: () => { invalidar(); toast.success("Status atualizado"); },
    onError: erro,
  });

  const vincularUsuario = useMutation({
    mutationFn: async ({ id, email }: { id: string; email: string }) => {
      const { data, error } = await sb.rpc("superadmin_parceiro_vincular_usuario", { _parceiro_id: id, _email: email });
      if (error) throw error;
      return data as string;
    },
    onSuccess: (r) => { invalidar(); if (r === "ok") toast.success("Usuário vinculado"); else toast.warning(r); },
    onError: erro,
  });

  const desvincularUsuario = useMutation({
    mutationFn: async (userId: string) => {
      const { error } = await sb.rpc("superadmin_parceiro_desvincular_usuario", { _user_id: userId });
      if (error) throw error;
    },
    onSuccess: () => { invalidar(); toast.success("Vínculo removido"); },
    onError: erro,
  });

  const vincularTenant = useMutation({
    mutationFn: async ({ tenantId, parceiroId, implantadorId }: { tenantId: string; parceiroId: string | null; implantadorId: string | null }) => {
      const { error } = await sb.rpc("superadmin_parceiro_vincular_tenant", {
        _tenant_id: tenantId, _parceiro_id: parceiroId, _implantador_id: implantadorId, _manter_ausente: false,
      });
      if (error) throw error;
    },
    onSuccess: () => { invalidar(); qc.invalidateQueries({ queryKey: ['superadmin', 'tenants'] }); toast.success("Empresa vinculada"); },
    onError: erro,
  });

  const criarLink = useMutation({
    mutationFn: async ({ id, campanha }: { id: string; campanha: string }) => {
      const { data, error } = await sb.rpc("superadmin_parceiro_link_criar", { _parceiro_id: id, _campanha: campanha });
      if (error) throw error;
      return data as string;
    },
    onSuccess: (cod) => { invalidar(); toast.success(`Link ${cod} criado`); },
    onError: erro,
  });

  const alternarLink = useMutation({
    mutationFn: async ({ linkId, ativo }: { linkId: string; ativo: boolean }) => {
      const { error } = await sb.rpc("superadmin_parceiro_link_ativo", { _link_id: linkId, _ativo: ativo });
      if (error) throw error;
    },
    onSuccess: () => invalidar(),
    onError: erro,
  });

  const salvarNiveis = useMutation({
    mutationFn: async (itens: ParceiroNivel[]) => {
      const { error } = await sb.rpc("superadmin_parceiro_niveis_salvar", { _itens: itens });
      if (error) throw error;
    },
    onSuccess: () => { invalidar(); toast.success("Níveis salvos"); },
    onError: erro,
  });

  const salvarConfig = useMutation({
    mutationFn: async (itens: { chave: string; valor: string }[]) => {
      const { error } = await sb.rpc("superadmin_parceiro_config_salvar", { _itens: itens });
      if (error) throw error;
    },
    onSuccess: () => { invalidar(); toast.success("Parâmetros do programa salvos"); },
    onError: erro,
  });

  const salvarEventos = useMutation({
    mutationFn: async (itens: ParceiroEventoRemuneracao[]) => {
      const { error } = await sb.rpc("superadmin_parceiro_eventos_salvar", { _itens: itens });
      if (error) throw error;
    },
    onSuccess: () => { invalidar(); toast.success("Remuneração por evento salva"); },
    onError: erro,
  });

  const fecharCompetencia = useMutation({
    mutationFn: async ({ competencia, fechar }: { competencia: string; fechar: boolean }) => {
      const { data, error } = await sb.rpc("parceiro_fechar_competencia", { p_competencia: competencia, p_fechar: fechar });
      if (error) throw error;
      return data as { competencia: string; parceiros: number; recorrentes: number; eventos: number; bonus: number; promocoes: number; fechado: boolean };
    },
    onSuccess: (r) => { qc.invalidateQueries({ queryKey: KEY }); toast.success(`${r.competencia}: ${r.recorrentes} recorrente(s), ${r.eventos} evento(s), ${r.bonus} bônus, ${r.promocoes} promoção(ões)${r.fechado ? " · fechado" : " · prévia"}`); },
    onError: erro,
  });

  const comissaoStatus = useMutation({
    mutationFn: async ({ ids, status, observacao }: { ids: string[]; status: ParceiroComissao["status"]; observacao?: string }) => {
      const { error } = await sb.rpc("superadmin_parceiro_comissao_status", { _ids: ids, _status: status, _observacao: observacao ?? null });
      if (error) throw error;
    },
    onSuccess: () => { qc.invalidateQueries({ queryKey: KEY }); toast.success("Comissões atualizadas"); },
    onError: erro,
  });

  const comissaoAjuste = useMutation({
    mutationFn: async ({ parceiroId, competencia, valorCents, observacao }: { parceiroId: string; competencia: string; valorCents: number; observacao: string }) => {
      const { error } = await sb.rpc("superadmin_parceiro_comissao_ajuste", { _parceiro_id: parceiroId, _competencia: competencia, _valor_cents: valorCents, _observacao: observacao });
      if (error) throw error;
    },
    onSuccess: () => { qc.invalidateQueries({ queryKey: KEY }); toast.success("Ajuste lançado"); },
    onError: erro,
  });

  return {
    fecharCompetencia, comissaoStatus, comissaoAjuste,
    parceiros: lista.data ?? [],
    isLoading: lista.isLoading,
    isError: lista.isError,
    tenants: tenants.data ?? [],
    niveis: niveis.data ?? [],
    eventos: eventos.data ?? [],
    config: config.data ?? [],
    salvarConfig,
    salvar, mudarStatus, vincularUsuario, desvincularUsuario, vincularTenant,
    criarLink, alternarLink, salvarNiveis, salvarEventos,
  };
}

export function useParceiroComissoes(competencia: string | null) {
  const { isSuperAdmin } = useAuthContext();
  return useQuery({
    queryKey: [...KEY, "comissoes", competencia],
    enabled: isSuperAdmin,
    queryFn: async (): Promise<ParceiroComissao[]> => {
      const { data, error } = await sb.rpc("superadmin_parceiro_comissoes_list", { _competencia: competencia ? `${competencia}-01` : null });
      if (error) throw error;
      return (data as ParceiroComissao[]) ?? [];
    },
  });
}

export function useSugestaoParceiros(leadId: string | null) {
  const { isSuperAdmin } = useAuthContext();
  return useQuery({
    queryKey: [...KEY, "sugestao", leadId],
    enabled: isSuperAdmin && !!leadId,
    queryFn: async (): Promise<SugestaoParceiro[]> => {
      const { data, error } = await sb.rpc("parceiros_sugerir_para_lead", { _lead_id: leadId });
      if (error) throw error;
      return (data as SugestaoParceiro[]) ?? [];
    },
  });
}

export async function encaminharLeadAoParceiro(leadId: string, parceiroId: string | null) {
  const { error } = await sb.rpc("superadmin_lead_encaminhar", { _lead_id: leadId, _parceiro_id: parceiroId });
  if (error) throw error;
}

export function useParceiroDetalhe(parceiroId: string | null) {
  return useQuery({
    queryKey: [...KEY, "detalhe", parceiroId],
    enabled: !!parceiroId,
    queryFn: async (): Promise<ParceiroDetalhe> => {
      const { data, error } = await sb.rpc("superadmin_parceiro_detalhe", { _parceiro_id: parceiroId });
      if (error) throw error;
      return data as ParceiroDetalhe;
    },
  });
}

// Lista enxuta para selects fora da aba (detalhe da empresa, Kanban de leads).
export function useParceirosOpcoes() {
  const { isSuperAdmin } = useAuthContext();
  return useQuery({
    queryKey: [...KEY, "opcoes"],
    enabled: isSuperAdmin,
    queryFn: async (): Promise<{ id: string; nome: string; codigo: string; tipo_parceiro: ParceiroTipo; status: ParceiroStatus }[]> => {
      const { data, error } = await sb
        .from("parceiros")
        .select("id, nome, codigo, tipo_parceiro, status")
        .order("nome");
      if (error) throw error;
      return data ?? [];
    },
  });
}

export function linkDoParceiro(codigo: string): string {
  const base = (import.meta.env.VITE_APP_URL as string | undefined) || window.location.origin;
  return `${base.replace(/\/$/, "")}/?ref=${codigo}`;
}
