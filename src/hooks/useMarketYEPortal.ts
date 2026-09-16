// MarketYE — portal restrito do especialista (fora do sistema, sem tenant).
// Todo o portal vem de uma RPC (marketye_meu_portal); toda escrita vai por
// função SQL. Tabelas novas fora de types.ts: acesso via `sb = supabase as any`.
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";
import { toast } from "sonner";
import type { MarketYEMensagem } from "./useMarketYE";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const sb = supabase as any;

export interface PortalPerfil {
  id: string;
  nome_completo: string;
  email: string;
  telefone: string | null;
  cpf_cnpj: string | null;
  tipo_pessoa: "pf" | "pj";
  foto_url: string | null;
  bio: string | null;
  formacao_academica: string | null;
  registro_profissional: string | null;
  conselho: string | null;
  uf_registro: string | null;
  registro_validade: string | null;
  certificacoes: string[] | null;
  especialidades: string[] | null;
  areas_atuacao: string[] | null;
  modalidades_atendimento: string[];
  cidade: string | null;
  estado: string | null;
  atende_remoto: boolean;
  raio_atendimento_km: number;
  disponibilidade: Record<string, unknown>;
  politicas: string | null;
  site_url: string | null;
  video_url: string | null;
  status: "pendente" | "ativo" | "suspenso" | "bloqueado";
  selo_verificado: boolean;
  nota_media: number;
  total_avaliacoes: number;
  total_servicos_executados: number;
  moderacao_resultado: "aprovado" | "rejeitado" | null;
  moderacao_motivo: string | null;
  excluido_em: string | null;
  consentimento_versao: string | null;
  parceiro_id: string | null;
  pais: string;
  moeda: string;
  created_at: string;
}

export interface PortalAnuncio {
  id: string;
  categoria_id: string | null;
  categoria_nome: string | null;
  categoria_slug: string | null;
  exige_registro: boolean | null;
  nome: string;
  descricao: string;
  base_legal: string | null;
  modalidade: "presencial" | "online" | "hibrido";
  publico_alvo: string | null;
  preco_referencia: number | null;
  tipo_preco: string;
  preco_minimo: number | null;
  preco_maximo: number | null;
  duracao_estimada_minutos: number | null;
  tags: string[];
  obrigacao_legal: string[];
  prazo_tipico: string | null;
  politica_cancelamento: string | null;
  status: "rascunho" | "publicado" | "pausado" | "removido";
  publicado_em: string | null;
  gerado_por_ia: boolean;
  promocao_percentual: number | null;
  promocao_inicio: string | null;
  promocao_fim: string | null;
  promocao_descricao: string | null;
  midia: unknown[];
  moeda: string;
  created_at: string;
}

export interface PortalLead {
  id: string;
  status: string;
  created_at: string;
  contato_liberado: boolean;
  primeira_resposta_em: string | null;
  ultima_mensagem_em: string | null;
  servico_nome: string | null;
  empresa_nome: string | null;
  origem_modulo: string | null;
  obrigacao_legal: string | null;
  cupom_codigo: string | null;
  ganho_em: string | null;
  reputacao_empresa: { media: number | null; total: number } | null;
  ultima_mensagem: string | null;
  avaliei: boolean;
}

export interface PortalDados {
  perfil: PortalPerfil;
  reputacao: {
    saude_score: number; saude_cor: string; media_90d: number | null; avaliacoes_90d: number; clientes_unicos_total: number; taxa_resposta_90d: number | null;
    tempo_resposta_mediano_min: number | null; taxa_cancelamento_90d: number | null; ocorrencias_90d: number; servicos_concluidos_total: number; nivel: string;
    nivel_desde: string; nivel_aviso_em: string | null; nivel_aviso_motivo: string | null; abaixo_piso: boolean; protegido_ate: string | null; calculado_em: string;
  } | null;
  nivel: { atual: string; proximo: string | null; requisitos_proximo: Record<string, number> | null; aviso_em: string | null; aviso_motivo: string | null; ordem: string[] };
  completude: number;
  anuncios: PortalAnuncio[];
  leads: PortalLead[];
  metricas: { leads_30d: number; leads_ganhos_30d: number; sem_resposta: number; avaliacoes: number };
  avaliacoes: { id: string; nota_geral: number; comentario: string | null; created_at: string; resposta: string | null; criterios: Record<string, number>; pontualidade: number | null; clareza: number | null; aderencia_escopo: number | null; profissionalismo: number | null }[];
  consentimentos: { id: string; tipo: string; versao: string; aceito_em: string; origem: string | null }[];
  termos_pendentes: { tipo: string; versao: string }[];
  contestacoes: { id: string; decisao_tipo: string; referencia_id: string | null; motivo: string; status: string; resposta: string | null; created_at: string; analisado_em: string | null; trilha: unknown[] }[];
  ocorrencias: { id: string; tipo: string; descricao: string | null; created_at: string; reflexo_visibilidade: boolean }[];
  cupons: { id: string; codigo: string; descricao: string | null; desconto_percentual: number; validade: string | null; limite_uso: number | null; usos: number; ativo: boolean }[];
  destaques: { id: string; tipo: string; inicio: string; fim: string; ativo: boolean }[];
  autonomia_eventos: number;
  termos_versoes: Record<string, string>;
  parceiro: { id: string } | null;
}

export const TERMO_LABEL: Record<string, string> = {
  termos_especialista: "Termos do Especialista",
  privacidade_nao_usuario: "Política de Privacidade (especialista)",
  codigo_etica: "Código de Ética e Conduta",
};

function extrairErro(e: unknown): string {
  if (e && typeof e === "object" && "message" in e) return String((e as { message: string }).message).replace(/^.*?:\s*/, "");
  return e instanceof Error ? e.message : "Algo deu errado";
}

export function useMarketYEPortal() {
  const { user, especialistaId } = useAuth();
  const qc = useQueryClient();
  const rpc = async (fn: string, args: Record<string, unknown> = {}) => {
    const { data, error } = await sb.rpc(fn, args);
    if (error) throw error;
    return data;
  };
  const invalidar = () => {
    qc.invalidateQueries({ queryKey: ["marketye-portal"] });
    qc.invalidateQueries({ queryKey: ["marketye-mensagens"] });
  };

  const portal = useQuery({
    queryKey: ["marketye-portal", user?.id],
    queryFn: () => rpc("marketye_meu_portal") as Promise<PortalDados | null>,
    enabled: !!user && !!especialistaId,
    // Conversa nova aberta por uma empresa precisa aparecer sem a pessoa
    // recarregar a página: a consulta padrão do app não reconsulta ao voltar à
    // aba nem por tempo, e o portal ficava mostrando a lista antiga.
    refetchInterval: 30000,
    refetchOnWindowFocus: true,
  });

  const salvarPerfil = useMutation({
    mutationFn: (dados: Record<string, unknown>) => rpc("marketye_meu_perfil_salvar", { _dados: dados }),
    onSuccess: () => { toast.success("Perfil salvo."); invalidar(); },
    onError: (e) => toast.error(extrairErro(e)),
  });
  const salvarAnuncio = useMutation({
    mutationFn: (dados: Record<string, unknown>) => rpc("marketye_anuncio_salvar", { _dados: dados }) as Promise<{ id: string }>,
    onSuccess: () => { toast.success("Anúncio salvo."); invalidar(); },
    onError: (e) => toast.error(extrairErro(e)),
  });
  const publicarAnuncio = useMutation({
    mutationFn: (id: string) => rpc("marketye_anuncio_publicar", { p_id: id }),
    onSuccess: () => { toast.success("Anúncio publicado: já aparece na vitrine das empresas."); invalidar(); },
    onError: (e) => toast.error(extrairErro(e), { duration: 8000 }),
  });
  const statusAnuncio = useMutation({
    mutationFn: (v: { id: string; status: "pausado" | "removido" | "rascunho" }) => rpc("marketye_anuncio_status", { p_id: v.id, p_status: v.status }),
    onSuccess: invalidar,
    onError: (e) => toast.error(extrairErro(e)),
  });
  const salvarCupom = useMutation({
    mutationFn: (dados: Record<string, unknown>) => rpc("marketye_cupom_salvar", { _dados: dados }),
    onSuccess: () => { toast.success("Cupom salvo."); invalidar(); },
    onError: (e) => toast.error(extrairErro(e)),
  });
  const aceitarTermos = useMutation({
    mutationFn: (v: { tipo: string; versao?: string }) => rpc("marketye_aceitar_termos", { p_tipo: v.tipo, p_versao: v.versao ?? null, p_user_agent: navigator.userAgent }),
    onSuccess: () => { toast.success("Aceite registrado com data e versão."); invalidar(); },
    onError: (e) => toast.error(extrairErro(e)),
  });
  const enviarMensagem = useMutation({
    mutationFn: (v: { lead_id: string; texto: string }) => rpc("marketye_lead_mensagem", { p_lead_id: v.lead_id, p_texto: v.texto }),
    onSuccess: invalidar,
    onError: (e) => toast.error(extrairErro(e)),
  });
  const statusLead = useMutation({
    mutationFn: (v: { lead_id: string; status: "ganho" | "perdido" | "encerrado"; motivo?: string }) => rpc("marketye_lead_status", { p_lead_id: v.lead_id, p_status: v.status, p_motivo: v.motivo ?? null }),
    onSuccess: invalidar,
    onError: (e) => toast.error(extrairErro(e)),
  });
  const avaliarEmpresa = useMutation({
    mutationFn: (v: { lead_id: string; notas: Record<string, number>; comentario?: string }) => rpc("marketye_avaliar", { p_ref_tipo: "lead", p_ref_id: v.lead_id, p_notas: v.notas, p_comentario: v.comentario ?? null }),
    onSuccess: () => { toast.success("Avaliação da empresa enviada."); invalidar(); },
    onError: (e) => toast.error(extrairErro(e)),
  });
  const responderAvaliacao = useMutation({
    mutationFn: (v: { id: string; resposta: string }) => rpc("marketye_avaliacao_responder", { p_avaliacao_id: v.id, p_resposta: v.resposta }),
    onSuccess: () => { toast.success("Resposta publicada."); invalidar(); },
    onError: (e) => toast.error(extrairErro(e)),
  });
  const contestar = useMutation({
    mutationFn: (v: { tipo: string; referencia_id?: string | null; motivo: string }) => rpc("marketye_contestar", { p_tipo: v.tipo, p_referencia_id: v.referencia_id ?? null, p_motivo: v.motivo, p_evidencias: [] }),
    onSuccess: () => { toast.success("Contestação aberta. Uma pessoa da YourEyes vai analisar e responder aqui."); invalidar(); },
    onError: (e) => toast.error(extrairErro(e)),
  });
  const exportar = async () => rpc("marketye_exportar_meus_dados");
  const excluir = useMutation({
    mutationFn: (confirmacao: string) => rpc("marketye_excluir_meu_perfil", { p_confirmacao: confirmacao }),
    onSuccess: () => toast.success("Perfil removido da vitrine e anonimizado."),
    onError: (e) => toast.error(extrairErro(e)),
  });
  const contato = async (leadId: string) => rpc("marketye_lead_contato", { p_lead_id: leadId }) as Promise<{ liberado: boolean; empresa?: string; solicitante?: string; email?: string; telefone?: string }>;

  return { portal, salvarPerfil, salvarAnuncio, publicarAnuncio, statusAnuncio, salvarCupom, aceitarTermos, enviarMensagem, statusLead, avaliarEmpresa, responderAvaliacao, contestar, exportar, excluir, contato };
}

export function usePortalMensagens(leadId: string | null) {
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

// Geração assistida por IA (anúncio a partir de poucos campos, preço sugerido,
// rascunho de resposta a lead, interpretação de busca em linguagem natural).
export async function marketyeIA<T = Record<string, unknown>>(tipo: "gerar_anuncio" | "sugerir_preco" | "rascunho_resposta" | "interpretar_busca" | "resumo_avaliacoes" | "sugerir_parametros" | "gerar_bio", dados: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke("ai-marketye", { body: { tipo, dados } });
  if (error) {
    const ctx = (error as { context?: Response }).context;
    if (ctx && typeof ctx.json === "function") { try { const b = await ctx.json(); if (b?.error) throw new Error(String(b.error)); } catch (e) { if (e instanceof Error && e.message) throw e; } }
    throw new Error(error.message || "A IA não respondeu");
  }
  if (data?.error) throw new Error(String(data.error));
  return data as T;
}
