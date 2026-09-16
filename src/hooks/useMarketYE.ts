// MarketYE — vitrine (lado da empresa cliente) e moderação (superadmin).
// As tabelas/funções novas ainda não estão em types.ts (regeneradas depois
// de aplicar no staging), por isso as chamadas passam por `sb = supabase as any`,
// como em useParceiros. Toda escrita vai por função SQL (RN-021).
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";
import { toast } from "sonner";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const sb = supabase as any;

export interface MarketYECategoria {
  id: string;
  nome: string;
  slug: string | null;
  icone: string | null;
  ordem: number;
  pai_id: string | null;
  obrigacao_legal: string[];
  exige_registro: boolean;
  aliases: string[];
  filhas?: MarketYECategoria[];
}

export interface MarketYEProfissionalResumo {
  id: string;
  nome_completo: string;
  foto_url: string | null;
  bio: string | null;
  cidade: string | null;
  estado: string | null;
  selo_verificado: boolean;
  nota_media: number;
  total_avaliacoes: number;
  total_servicos_executados: number;
  atende_remoto: boolean;
  conselho: string | null;
  registro_profissional: string | null;
  especialidades: string[] | null;
  modalidades_atendimento: string[] | null;
  tipo_pessoa: "pf" | "pj";
  video_url: string | null;
  saude_score: number;
  saude_cor: "verde" | "amarelo" | "vermelho" | "cinza";
  nivel: string;
  clientes_unicos: number;
  tempo_resposta_mediano_min: number | null;
  taxa_resposta_90d: number | null;
  novato: boolean;
}

export interface MarketYEAnuncio {
  servico_id: string;
  nome: string;
  descricao: string;
  base_legal: string | null;
  modalidade: "presencial" | "online" | "hibrido";
  preco_referencia: number | null;
  tipo_preco: "hora" | "visita" | "pacote" | "mensal" | "sob_orcamento";
  preco_minimo: number | null;
  preco_maximo: number | null;
  moeda: string;
  duracao_estimada_minutos: number | null;
  tags: string[];
  obrigacao_legal: string[];
  prazo_tipico: string | null;
  midia: unknown[];
  promocao_ativa: boolean;
  promocao_percentual: number | null;
  promocao_descricao: string | null;
  tem_cupom: boolean;
  categoria_id: string | null;
  categoria_nome: string | null;
  categoria_slug: string | null;
  profissional: MarketYEProfissionalResumo;
  distancia_km: number | null;
  remoto: boolean;
  patrocinado: boolean;
  abaixo_piso: boolean;
  score: number;
  fatores: Record<string, number>;
}

export interface MarketYEFiltros {
  q?: string;
  categoria_id?: string;
  categoria_slug?: string;
  modalidade?: string;
  uf?: string;
  cidade?: string;
  somente_remoto?: boolean;
  preco_max?: number;
  nota_min?: number;
  selo?: boolean;
  nivel_min?: string;
  lat?: number;
  lng?: number;
  raio_km?: number;
  obrigacoes?: string[];
  ignorar_uf_padrao?: boolean;
  limite?: number;
}

export interface MarketYEBuscaResultado {
  total: number;
  resultados: MarketYEAnuncio[];
  relaxamentos: string[];
  filtros_aplicados: Record<string, unknown>;
  categorias_adjacentes: { id: string; nome: string; slug: string }[];
  oferta_insuficiente: boolean;
}

export interface MarketYELead {
  id: string;
  tenant_id: string;
  profissional_id: string;
  servico_id: string | null;
  status: "novo" | "respondido" | "qualificado" | "ganho" | "perdido" | "encerrado";
  contato_liberado: boolean;
  primeira_resposta_em: string | null;
  ultima_mensagem_em: string | null;
  ganho_em: string | null;
  origem_modulo: string | null;
  obrigacao_legal: string | null;
  cupom_codigo: string | null;
  created_at: string;
  profissional?: { id: string; nome_completo: string; foto_url: string | null; conselho: string | null; nota_media: number; selo_verificado: boolean } | null;
  servico?: { id: string; nome: string } | null;
}

export interface MarketYEMensagem {
  id: string;
  lead_id: string;
  autor_tipo: "cliente" | "especialista" | "sistema";
  texto: string;
  mascarada: boolean;
  sinal_saida: boolean;
  created_at: string;
}

export const NIVEL_LABEL: Record<string, string> = { novo: "Novo", bronze: "Bronze", prata: "Prata", ouro: "Ouro", top: "Especialista Top" };
export const SAUDE_LABEL: Record<string, string> = { verde: "Atendimento em dia", amarelo: "Atendimento pede atenção", vermelho: "Atendimento precisa melhorar", cinza: "Ainda sem histórico" };
export const LEAD_STATUS_LABEL: Record<string, string> = {
  novo: "Aguardando resposta", respondido: "Em conversa", qualificado: "Contato liberado", ganho: "Serviço combinado", perdido: "Não fechou", encerrado: "Encerrada",
};

export function formatarPreco(a: Pick<MarketYEAnuncio, "preco_referencia" | "tipo_preco" | "preco_minimo" | "preco_maximo" | "moeda">): string {
  const fmt = (v: number) => new Intl.NumberFormat("pt-BR", { style: "currency", currency: a.moeda || "BRL" }).format(v);
  if (a.tipo_preco === "sob_orcamento" || a.preco_referencia == null) {
    if (a.preco_minimo != null && a.preco_maximo != null) return `${fmt(a.preco_minimo)} a ${fmt(a.preco_maximo)}`;
    return "Sob orçamento";
  }
  const sufixo: Record<string, string> = { hora: "/hora", visita: "/visita", pacote: " (pacote)", mensal: "/mês", sob_orcamento: "" };
  return `${fmt(a.preco_referencia)}${sufixo[a.tipo_preco] ?? ""}`;
}

function extrairErro(e: unknown): string {
  if (e && typeof e === "object" && "message" in e) return String((e as { message: string }).message).replace(/^.*?:\s*/, "");
  return e instanceof Error ? e.message : "Algo deu errado";
}

export function useMarketYECategorias() {
  return useQuery({
    queryKey: ["marketye-categorias"],
    queryFn: async () => {
      const { data, error } = await sb.from("marketplace_categorias").select("id, nome, slug, icone, ordem, pai_id, obrigacao_legal, exige_registro, aliases").eq("ativo", true).order("ordem");
      if (error) throw error;
      const todas = (data ?? []) as MarketYECategoria[];
      const raizes = todas.filter((c) => !c.pai_id).map((c) => ({ ...c, filhas: todas.filter((f) => f.pai_id === c.id) }));
      return { todas, raizes };
    },
    staleTime: 5 * 60 * 1000,
  });
}

export function useMarketYEBusca(filtros: MarketYEFiltros, enabled = true) {
  const { user } = useAuth();
  return useQuery({
    queryKey: ["marketye-busca", filtros],
    queryFn: async () => {
      const { data, error } = await sb.rpc("marketye_buscar", { p_filtros: filtros });
      if (error) throw error;
      return data as MarketYEBuscaResultado;
    },
    enabled: enabled && !!user,
    staleTime: 30 * 1000,
  });
}

export function useMarketYELeads() {
  const { tenantId, user } = useAuth();
  return useQuery({
    queryKey: ["marketye-leads", tenantId],
    queryFn: async () => {
      const { data, error } = await sb
        .from("marketplace_leads")
        .select("*, profissional:marketplace_profissionais(id, nome_completo, foto_url, conselho, nota_media, selo_verificado), servico:marketplace_servicos(id, nome)")
        .eq("tenant_id", tenantId)
        .order("ultima_mensagem_em", { ascending: false, nullsFirst: false });
      if (error) throw error;
      return (data ?? []) as MarketYELead[];
    },
    enabled: !!tenantId && !!user,
    // Resposta do especialista muda a lista (situação, última mensagem):
    // reconsulta por tempo e ao voltar à aba, como no portal do especialista.
    refetchInterval: 30000,
    refetchOnWindowFocus: true,
  });
}

export function useMarketYEMensagens(leadId: string | null) {
  return useQuery({
    queryKey: ["marketye-mensagens", leadId],
    queryFn: async () => {
      const { data, error } = await sb.from("marketplace_lead_mensagens").select("id, lead_id, autor_tipo, texto, mascarada, sinal_saida, created_at").eq("lead_id", leadId).order("created_at");
      if (error) throw error;
      return (data ?? []) as MarketYEMensagem[];
    },
    enabled: !!leadId,
    refetchInterval: leadId ? 15000 : false,
  });
}

export function useMarketYEAcoes() {
  const qc = useQueryClient();
  const invalidar = () => {
    qc.invalidateQueries({ queryKey: ["marketye-leads"] });
    qc.invalidateQueries({ queryKey: ["marketye-mensagens"] });
    qc.invalidateQueries({ queryKey: ["marketye-portal"] });
  };
  const rpc = async (fn: string, args: Record<string, unknown>) => {
    const { data, error } = await sb.rpc(fn, args);
    if (error) throw error;
    return data;
  };

  const abrirLead = useMutation({
    mutationFn: (v: { profissional_id: string; servico_id?: string | null; mensagem: string; origem_modulo?: string | null; origem_id?: string | null; obrigacao?: string | null }) =>
      rpc("marketye_abrir_lead", { p_profissional_id: v.profissional_id, p_servico_id: v.servico_id ?? null, p_mensagem: v.mensagem, p_origem_modulo: v.origem_modulo ?? null, p_origem_id: v.origem_id ?? null, p_obrigacao: v.obrigacao ?? null }),
    onSuccess: (d: { reaproveitado?: boolean }) => { toast.success(d?.reaproveitado ? "Mensagem enviada na conversa já aberta." : "Contato enviado ao especialista."); invalidar(); },
    onError: (e) => toast.error(extrairErro(e)),
  });
  const enviarMensagem = useMutation({
    mutationFn: (v: { lead_id: string; texto: string }) => rpc("marketye_lead_mensagem", { p_lead_id: v.lead_id, p_texto: v.texto }),
    onSuccess: invalidar,
    onError: (e) => toast.error(extrairErro(e)),
  });
  const liberarContato = useMutation({
    mutationFn: (leadId: string) => rpc("marketye_lead_liberar_contato", { p_lead_id: leadId }),
    onSuccess: () => { toast.success("Contato liberado."); invalidar(); },
    onError: (e) => toast.error(extrairErro(e)),
  });
  const mudarStatus = useMutation({
    mutationFn: (v: { lead_id: string; status: "ganho" | "perdido" | "encerrado"; motivo?: string }) => rpc("marketye_lead_status", { p_lead_id: v.lead_id, p_status: v.status, p_motivo: v.motivo ?? null }),
    onSuccess: invalidar,
    onError: (e) => toast.error(extrairErro(e)),
  });
  const avaliar = useMutation({
    mutationFn: (v: { ref_tipo: "lead" | "contratacao"; ref_id: string; notas: Record<string, number>; comentario?: string }) =>
      rpc("marketye_avaliar", { p_ref_tipo: v.ref_tipo, p_ref_id: v.ref_id, p_notas: v.notas, p_comentario: v.comentario ?? null }),
    onSuccess: () => { toast.success("Avaliação enviada."); invalidar(); qc.invalidateQueries({ queryKey: ["marketye-busca"] }); },
    onError: (e) => toast.error(extrairErro(e)),
  });
  const registrarBusca = useMutation({
    mutationFn: (v: { categoria_id?: string | null; uf?: string | null; cidade?: string | null; termos?: string | null; resultados: number; avisar?: boolean; email?: string | null }) =>
      rpc("marketye_registrar_busca", { p_categoria_id: v.categoria_id ?? null, p_uf: v.uf ?? null, p_cidade: v.cidade ?? null, p_termos: v.termos ?? null, p_resultados: v.resultados, p_avisar: v.avisar ?? false, p_email: v.email ?? null }),
    onError: () => { /* sinal de captação; silêncio se falhar */ },
  });
  const contato = async (leadId: string) => rpc("marketye_lead_contato", { p_lead_id: leadId }) as Promise<{ liberado: boolean; nome?: string; email?: string; telefone?: string; site_url?: string; empresa?: string; solicitante?: string }>;
  const vincularDocumento = useMutation({
    mutationFn: (v: { lead_id: string; documento_id: string; tipo?: string }) => rpc("marketye_lead_vincular_documento", { p_lead_id: v.lead_id, p_documento_id: v.documento_id, p_tipo: v.tipo ?? "proposta" }),
    onSuccess: () => { toast.success("Documento arquivado e vinculado à conversa."); invalidar(); },
    onError: (e) => toast.error(extrairErro(e)),
  });

  return { abrirLead, enviarMensagem, liberarContato, mudarStatus, avaliar, registrarBusca, contato, vincularDocumento };
}

// ---------------------------------------------------------------------
// Moderação (superadmin)
// ---------------------------------------------------------------------
export function useMarketYEModeracao(ativo: boolean) {
  const qc = useQueryClient();
  const rpc = async (fn: string, args: Record<string, unknown> = {}) => {
    const { data, error } = await sb.rpc(fn, args);
    if (error) throw error;
    return data;
  };
  const invalidar = () => {
    qc.invalidateQueries({ queryKey: ["marketye-moderacao"] });
    qc.invalidateQueries({ queryKey: ["marketye-contestacoes"] });
    qc.invalidateQueries({ queryKey: ["marketye-painel"] });
    qc.invalidateQueries({ queryKey: ["marketye-busca"] });
  };
  const fila = useQuery({ queryKey: ["marketye-moderacao", "pendente"], queryFn: () => rpc("marketye_moderacao_fila", { p_status: "pendente" }), enabled: ativo });
  const suspensos = useQuery({ queryKey: ["marketye-moderacao", "suspenso"], queryFn: () => rpc("marketye_moderacao_fila", { p_status: "suspenso" }), enabled: ativo });
  const contestacoes = useQuery({ queryKey: ["marketye-contestacoes"], queryFn: () => rpc("marketye_contestacoes_fila"), enabled: ativo });
  const painel = useQuery({ queryKey: ["marketye-painel"], queryFn: () => rpc("marketye_painel_liquidez"), enabled: ativo });
  const transparencia = useQuery({ queryKey: ["marketye-transparencia"], queryFn: () => rpc("marketye_transparencia", { p_ano: null }), enabled: ativo });
  const especialistasAtivos = useQuery({
    queryKey: ["marketye-especialistas-ativos"],
    queryFn: async () => {
      const { data, error } = await sb.from("marketplace_profissionais").select("id, nome_completo, cidade, estado").eq("status", "ativo").order("nome_completo");
      if (error) throw error;
      return (data ?? []) as { id: string; nome_completo: string; cidade: string | null; estado: string | null }[];
    },
    enabled: ativo,
  });
  const config = useQuery({
    queryKey: ["marketye-config"],
    queryFn: async () => {
      const { data, error } = await sb.from("marketplace_config").select("chave, versao, valor, descricao, vigente, criado_em").eq("vigente", true).order("chave");
      if (error) throw error;
      return (data ?? []) as { chave: string; versao: number; valor: unknown; descricao: string | null; vigente: boolean; criado_em: string }[];
    },
    enabled: ativo,
  });

  const moderar = useMutation({
    mutationFn: (v: { id: string; resultado: "aprovado" | "rejeitado"; motivo?: string; selo?: boolean }) =>
      rpc("marketye_moderar_especialista", { p_id: v.id, p_resultado: v.resultado, p_motivo: v.motivo ?? null, p_selo: v.selo ?? true }),
    onSuccess: (_d, v) => { toast.success(v.resultado === "aprovado" ? "Especialista aprovado: já aparece na vitrine." : "Cadastro rejeitado com motivo; o especialista pode contestar."); invalidar(); },
    onError: (e) => toast.error(extrairErro(e)),
  });
  const situacao = useMutation({
    mutationFn: (v: { id: string; situacao: "ativo" | "suspenso" | "pendente"; motivo?: string }) => rpc("marketye_especialista_situacao", { p_id: v.id, p_situacao: v.situacao, p_motivo: v.motivo ?? null }),
    onSuccess: () => { toast.success("Situação atualizada."); invalidar(); },
    onError: (e) => toast.error(extrairErro(e)),
  });
  const decidirContestacao = useMutation({
    mutationFn: (v: { id: string; resultado: "em_analise" | "deferida" | "indeferida"; resposta: string }) => rpc("marketye_contestacao_decidir", { p_id: v.id, p_resultado: v.resultado, p_resposta: v.resposta }),
    onSuccess: () => { toast.success("Decisão registrada com trilha."); invalidar(); },
    onError: (e) => toast.error(extrairErro(e)),
  });
  const decidirDenuncia = useMutation({
    mutationFn: (v: { id: string; status: "em_analise" | "procedente" | "improcedente" | "resolvida"; acao?: string }) => rpc("marketye_denuncia_decidir", { p_id: v.id, p_status: v.status, p_acao: v.acao ?? null }),
    onSuccess: () => { toast.success("Denúncia atualizada."); invalidar(); qc.invalidateQueries({ queryKey: ["marketplace-denuncias"] }); },
    onError: (e) => toast.error(extrairErro(e)),
  });
  const criarDestaque = useMutation({
    mutationFn: (v: { profissional_id: string; servico_id?: string | null; tipo: "categoria" | "regiao" | "topo"; categoria_id?: string | null; uf?: string | null; inicio: string; fim: string; valor?: number | null }) =>
      rpc("marketye_destaque_criar", { p_profissional_id: v.profissional_id, p_servico_id: v.servico_id ?? null, p_tipo: v.tipo, p_categoria_id: v.categoria_id ?? null, p_uf: v.uf ?? null, p_inicio: v.inicio, p_fim: v.fim, p_valor: v.valor ?? null }),
    onSuccess: () => { toast.success("Destaque criado (rotulado como Patrocinado)."); invalidar(); },
    onError: (e) => toast.error(extrairErro(e)),
  });
  const salvarConfig = useMutation({
    mutationFn: (v: { chave: string; valor: unknown; descricao?: string }) => rpc("marketye_config_salvar", { p_chave: v.chave, p_valor: v.valor, p_descricao: v.descricao ?? null, p_jurisdicao: "BR" }),
    onSuccess: () => { toast.success("Nova versão do parâmetro gravada."); qc.invalidateQueries({ queryKey: ["marketye-config"] }); invalidar(); },
    onError: (e) => toast.error(extrairErro(e)),
  });

  return { fila, suspensos, contestacoes, painel, transparencia, config, especialistasAtivos, moderar, situacao, decidirContestacao, decidirDenuncia, criarDestaque, salvarConfig };
}
