import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";

/**
 * EC 141/2026 — entrega F1 (marcos legais + escala "vale a partir de").
 *
 * Tudo aqui é leitura das regras que vivem no banco. A transição é MANUAL:
 * os marcos 42h/40h nascem inativos e só o SuperAdmin os ativa. Sem marco
 * ativo, o teto devolvido é o da CF/88 (44h, 220h/mês) e nada muda na tela.
 */

const rpc = (nome: string, args: Record<string, unknown>) =>
  (supabase.rpc as any)(nome, args) as Promise<{ data: any; error: any }>;

export interface TetoLegal {
  codigo: string;
  nome: string;
  vigencia_inicio: string;
  teto_semanal_min: number;
  teto_diario_min: number;
  repousos_semana: number;
  divisor_padrao: number;
  fonte?: string;
  origem: "global" | "conta" | "padrao";
}

export const TETO_CF88: TetoLegal = {
  codigo: "CF88_44H",
  nome: "CF/88 — 44h semanais",
  vigencia_inicio: "1988-10-05",
  teto_semanal_min: 2640,
  teto_diario_min: 480,
  repousos_semana: 1,
  divisor_padrao: 220,
  origem: "padrao",
};

export interface AgendamentoEscala {
  escala_id: string;
  escala_nome: string;
  vigente_a_partir_de: string;
  motivo: string | null;
  marco_codigo: string | null;
  agendado_em: string;
  atual_jornada_diaria_min: number | null;
  atual_carga_semanal_min: number | null;
  nova_jornada_diaria_min: number | null;
  nova_carga_semanal_min: number | null;
}

export interface AvisoTeto {
  codigo: string;
  nivel: "alerta" | "aviso" | "info";
  mensagem: string;
}

export interface ImpactoLinha {
  empresa_id: string | null;
  empresa_nome: string;
  escala_id: string;
  escala_nome: string;
  tipo: string;
  colaboradores: number;
  carga_semanal_atual_min: number | null;
  dias_trabalhados: number | null;
  teto_semanal_min: number;
  acima_do_teto: boolean;
  seis_dias: boolean;
  coletivo_vigente: boolean;
  seis_dias_sem_coletivo: boolean;
  agendamento: { vigente_a_partir_de: string; marco_codigo: string | null; nova_carga_semanal_min: number | null } | null;
}

export interface ImpactoEc141 {
  ok: boolean;
  visivel: boolean;
  previa?: boolean;
  mensagem?: string;
  marco?: TetoLegal & { ativo: boolean };
  linhas?: ImpactoLinha[];
  totais?: {
    escalas: number;
    escalas_acima_teto: number;
    colaboradores_acima_teto: number;
    escalas_6dias_sem_coletivo: number;
    colaboradores_6dias_sem_coletivo: number;
    escalas_com_agendamento: number;
  };
}

export const hojeISO = () => {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
};

/** Dia anterior de uma data YYYY-MM-DD (sem passar por fuso). */
export const diaAnteriorISO = (iso: string) => {
  const [a, m, d] = iso.split("T")[0].split("-").map(Number);
  const dt = new Date(Date.UTC(a, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() - 1);
  return dt.toISOString().slice(0, 10);
};

export const formatarDataBR = (iso?: string | null) => {
  if (!iso) return "-";
  const [a, m, d] = iso.split("T")[0].split("-");
  return `${d}/${m}/${a}`;
};

export const formatarHoras = (min?: number | null) => {
  if (min === null || min === undefined) return "-";
  const h = Math.floor(min / 60);
  const r = min % 60;
  return r ? `${h}h${String(r).padStart(2, "0")}` : `${h}h`;
};

/** Teto legal ATIVO na data (CF/88 enquanto nenhum marco EC 141 for ativado). */
export function useTetoLegal(data?: string) {
  const { tenantId } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const dia = data || hojeISO();
  return useQuery({
    queryKey: ["ponto-teto-legal", tenantId, empresaAtivaId, dia],
    queryFn: async (): Promise<TetoLegal> => {
      const { data: res, error } = await rpc("ponto_teto_legal", {
        p_tenant: tenantId,
        p_empresa: empresaAtivaId || null,
        p_data: dia,
      });
      if (error || !res) return TETO_CF88;
      return res as TetoLegal;
    },
    enabled: !!tenantId,
    staleTime: 5 * 60 * 1000,
  });
}

/** Marcos EC 141 ativos para a conta (para vincular um agendamento a um marco). */
export function useMarcosAtivosConta() {
  const { tenantId } = useAuth();
  return useQuery({
    queryKey: ["ponto-marcos-resolvidos", tenantId],
    queryFn: async (): Promise<Array<TetoLegal & { ativo: boolean }>> => {
      const { data, error } = await rpc("ponto_marcos_resolvidos", { p_tenant: tenantId });
      if (error || !data) return [];
      return (data as any[]).filter((m) => m.ativo && String(m.codigo).startsWith("EC141"));
    },
    enabled: !!tenantId,
    staleTime: 5 * 60 * 1000,
  });
}

/** Alterações de escala agendadas ("vale a partir de"), por escala. */
export function useAgendamentosEscalas() {
  const { tenantId } = useAuth();
  return useQuery({
    queryKey: ["ponto-escalas-agendamentos", tenantId],
    queryFn: async (): Promise<Record<string, AgendamentoEscala>> => {
      const { data, error } = await rpc("ponto_escalas_agendamentos", { p_tenant: tenantId });
      if (error || !data) return {};
      const mapa: Record<string, AgendamentoEscala> = {};
      (data as AgendamentoEscala[]).forEach((a) => {
        mapa[a.escala_id] = a;
      });
      return mapa;
    },
    enabled: !!tenantId,
  });
}

/** Avisos do teto legal por escala (nunca bloqueiam nada). */
export function useAvisosTetoEscalas(escalaIds: string[], datasPorEscala: Record<string, string | undefined> = {}) {
  const chave = escalaIds.map((id) => `${id}:${datasPorEscala[id] || ""}`).join(",");
  return useQuery({
    queryKey: ["ponto-escala-validar-teto", chave],
    queryFn: async (): Promise<Record<string, AvisoTeto[]>> => {
      const mapa: Record<string, AvisoTeto[]> = {};
      const hoje = hojeISO();
      await Promise.all(
        escalaIds.map(async (id) => {
          const datas = [hoje, datasPorEscala[id]].filter(Boolean) as string[];
          const avisos: AvisoTeto[] = [];
          for (const d of datas) {
            const { data, error } = await rpc("ponto_escala_validar_teto", { p_escala_id: id, p_data: d });
            if (error || !data?.ok) continue;
            for (const a of (data.avisos || []) as AvisoTeto[]) {
              if (a.nivel === "info") continue;
              if (!avisos.some((x) => x.codigo === a.codigo && x.mensagem === a.mensagem)) avisos.push(a);
            }
          }
          mapa[id] = avisos;
        }),
      );
      return mapa;
    },
    enabled: escalaIds.length > 0,
  });
}

export function useCancelarAgendamentoEscala() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (escalaId: string) => {
      const { data, error } = await rpc("ponto_escala_cancelar_agendamento", { p_escala_id: escalaId });
      if (error) throw error;
      if (!data?.ok) throw new Error(data?.mensagem || "Não foi possível cancelar o agendamento.");
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ponto-escalas"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-escala-periodos"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-escalas-agendamentos"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-escala-validar-teto"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-ec141-impacto"] });
      toast.success("Agendamento cancelado. A escala voltou aos valores anteriores.");
    },
    onError: (e: Error) => toast.error(e.message),
  });
}

/** Painel de impacto (somente leitura). Para o cliente, só há conteúdo com marco EC 141 ativo. */
export function useImpactoEc141(opts: { tenantId?: string | null; empresaId?: string | null; marco?: string | null; enabled?: boolean } = {}) {
  const { tenantId: tenantLogado } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const tenant = opts.tenantId === undefined ? tenantLogado : opts.tenantId;
  const empresa = opts.empresaId === undefined ? empresaAtivaId || null : opts.empresaId;
  return useQuery({
    queryKey: ["ponto-ec141-impacto", tenant, empresa, opts.marco || null],
    queryFn: async (): Promise<ImpactoEc141> => {
      const { data, error } = await rpc("ponto_ec141_impacto", {
        p_tenant: tenant,
        p_empresa: empresa,
        p_marco_codigo: opts.marco || null,
      });
      if (error || !data) return { ok: false, visivel: false };
      return data as ImpactoEc141;
    },
    enabled: !!tenant && opts.enabled !== false,
  });
}

// ─────────────────────────────────────────────────────────────────────
// EC 141 — entrega F2a: assistente "Migrar para 42h/40h", aditivos e
// cancelamento em lote. A regra vive no banco (ponto_ec141_migracao_*);
// a tela só mostra a prévia, pede a confirmação e chama as mesmas funções.
// ─────────────────────────────────────────────────────────────────────

export type DestinoEc141 = "42" | "40";
export type DestinoColaborador = DestinoEc141 | "manter";

export interface AvisoMigracao {
  nivel: "forte" | "alerta" | "aviso" | "info";
  codigo: string;
  mensagem: string;
}

export interface LinhaMigracao {
  chave: string;
  colaborador_id: string | null;
  colaborador_nome: string | null;
  escala_id: string;
  escala_nome: string;
  destino: DestinoColaborador;
  recomendacao: DestinoEc141;
  tem_coletivo: boolean;
  instrumento_nome: string | null;
  status: "migrar" | "ja_conforme" | "ja_migrado" | "fora_do_assistente" | "nao_migrar" | "conflito";
  modo?: "escala" | "nova_escala";
  requer_confirmacao_8h24: boolean;
  jornada_atual: string | null;
  jornada_nova: string | null;
  carga_antes_min: number | null;
  carga_depois_min: number | null;
  maior_dia_depois_min: number | null;
  avisos: AvisoMigracao[];
}

export interface PreviaMigracao {
  ok: boolean;
  visivel?: boolean;
  erro?: string;
  mensagem?: string | null;
  marco?: TetoLegal & { ativo: boolean };
  vigencia_inicio?: string;
  pode_aplicar?: boolean;
  linhas?: LinhaMigracao[];
  totais?: {
    colaboradores: number;
    migrar: number;
    requer_confirmacao: number;
    ja_conforme: number;
    ja_migrado: number;
    fora_do_assistente: number;
    sem_coletivo: number;
  };
}

export interface MigracaoEc141 {
  id: string;
  empresa_id: string | null;
  marco_codigo: string;
  vigencia_inicio: string;
  destino_padrao: string;
  status: "aplicada" | "cancelada";
  resumo: { migrados?: number; escalas_agendadas?: number; escalas_novas?: number; aditivos?: number } | null;
  acionado_por_email: string | null;
  acionado_em: string;
  cancelado_por_email: string | null;
  cancelado_em: string | null;
  cancelado_motivo: string | null;
  pode_cancelar: boolean;
}

export interface AditivoEc141 {
  id: string;
  migracao_id: string;
  colaborador_nome: string | null;
  colaborador_cpf: string | null;
  vigencia_inicio: string;
  situacao: "pendente_envio" | "aguardando_assinatura" | "assinado" | "contestado" | "cancelado";
  assinatura_status: string | null;
  solicitacao_id: string | null;
  respondido_em: string | null;
}

const invalidarEc141 = (queryClient: ReturnType<typeof useQueryClient>) => {
  ["ponto-escalas", "ponto-escala-periodos", "ponto-escala-atribuicoes", "ponto-escalas-agendamentos",
   "ponto-escala-validar-teto", "ponto-ec141-impacto", "ponto-ec141-migracoes", "ponto-ec141-aditivos",
   "ponto-ec141-previa"].forEach((k) => queryClient.invalidateQueries({ queryKey: [k] }));
};

/** Prévia por colaborador (somente leitura). */
export function usePreviaMigracaoEc141(destino: DestinoEc141, excecoes: Record<string, DestinoColaborador>, enabled = true) {
  const { tenantId } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  return useQuery({
    queryKey: ["ponto-ec141-previa", tenantId, empresaAtivaId, destino, JSON.stringify(excecoes)],
    queryFn: async (): Promise<PreviaMigracao> => {
      const { data, error } = await rpc("ponto_ec141_migracao_previa", {
        p_tenant: tenantId, p_empresa: empresaAtivaId || null, p_destino: destino, p_excecoes: excecoes,
      });
      if (error) return { ok: false, mensagem: error.message };
      return data as PreviaMigracao;
    },
    enabled: !!tenantId && enabled,
  });
}

export function useAplicarMigracaoEc141() {
  const { tenantId } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (args: { destino: DestinoEc141; excecoes: Record<string, DestinoColaborador>; confirmar8h24: boolean }) => {
      const { data, error } = await rpc("ponto_ec141_migracao_aplicar", {
        p_tenant: tenantId, p_empresa: empresaAtivaId || null, p_destino: args.destino,
        p_excecoes: args.excecoes, p_confirmar_8h24: args.confirmar8h24,
      });
      if (error) throw error;
      if (!data?.ok) throw new Error(data?.mensagem || "Não foi possível gravar a migração.");
      return data as { migrados: number; escalas_agendadas?: number; escalas_novas?: number; aditivos?: number; aguardando_confirmacao?: number; mensagem?: string };
    },
    onSuccess: (r) => {
      invalidarEc141(queryClient);
      if (!r.migrados) toast.info(r.mensagem || "Nada a migrar.");
      else toast.success(`${r.migrados} colaborador(es) migrado(s). ${r.aditivos || 0} aditivo(s) para assinatura.`);
    },
    onError: (e: Error) => toast.error(e.message),
  });
}

export function useMigracoesEc141(enabled = true) {
  const { tenantId } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  return useQuery({
    queryKey: ["ponto-ec141-migracoes", tenantId, empresaAtivaId],
    queryFn: async (): Promise<MigracaoEc141[]> => {
      const { data, error } = await rpc("ponto_ec141_migracoes_lista", { p_tenant: tenantId, p_empresa: empresaAtivaId || null });
      if (error || !data) return [];
      return data as MigracaoEc141[];
    },
    enabled: !!tenantId && enabled,
  });
}

export function useCancelarMigracaoEc141() {
  const { tenantId } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (args: { migracaoId?: string; motivo: string }) => {
      const { data, error } = await rpc("ponto_ec141_migracao_cancelar", {
        p_tenant: tenantId, p_empresa: empresaAtivaId || null, p_marco_codigo: null,
        p_motivo: args.motivo, p_migracao_id: args.migracaoId || null,
      });
      if (error) throw error;
      if (!data?.ok) {
        const f = (data?.falhas || [])[0];
        throw new Error(data?.mensagem || f?.mensagem || "Não foi possível cancelar a migração.");
      }
      return data as { migracoes_canceladas: number; colaboradores_restaurados: number; aditivos_cancelados: number };
    },
    onSuccess: (r) => {
      invalidarEc141(queryClient);
      toast.success(`Migração cancelada: ${r.colaboradores_restaurados} colaborador(es) voltaram à escala anterior; ${r.aditivos_cancelados} aditivo(s) cancelado(s).`);
    },
    onError: (e: Error) => toast.error(e.message),
  });
}

export function useAditivosEc141(soPendentes = false, enabled = true) {
  const { tenantId } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  return useQuery({
    queryKey: ["ponto-ec141-aditivos", tenantId, empresaAtivaId, soPendentes],
    queryFn: async (): Promise<AditivoEc141[]> => {
      const { data, error } = await rpc("ponto_ec141_aditivos_lista", {
        p_tenant: tenantId, p_empresa: empresaAtivaId || null, p_so_pendentes: soPendentes,
      });
      if (error || !data) return [];
      return data as AditivoEc141[];
    },
    enabled: !!tenantId && enabled,
  });
}

/** Chama a função de borda e devolve o corpo JSON mesmo quando o status não é 2xx. */
type RespostaBorda = { ok?: boolean; erro?: string; mensagem?: string; link?: string; email_enviado?: boolean; destino?: string };
async function chamarBorda(nome: string, body: unknown): Promise<RespostaBorda> {
  const { data, error } = await supabase.functions.invoke(nome, { body });
  if (error) {
    const ctx = (error as { context?: Response }).context;
    if (ctx && typeof ctx.json === "function") {
      try {
        return (await ctx.json()) as RespostaBorda;
      } catch {
        /* sem corpo JSON */
      }
    }
    throw error;
  }
  return data as RespostaBorda;
}

/** PDF do aditivo a partir do texto gravado no banco (sem dado fixo no código). */
async function pdfDoAditivo(titulo: string, texto: string): Promise<string> {
  const { jsPDF } = await import("jspdf");
  const doc = new jsPDF({ unit: "mm", format: "a4" });
  const margem = 20;
  const largura = doc.internal.pageSize.getWidth() - margem * 2;
  const altura = doc.internal.pageSize.getHeight();
  let y = margem;
  doc.setFont("helvetica", "bold");
  doc.setFontSize(12);
  for (const l of doc.splitTextToSize(titulo, largura)) {
    doc.text(l, margem, y);
    y += 6;
  }
  y += 4;
  doc.setFont("helvetica", "normal");
  doc.setFontSize(10.5);
  for (const par of texto.split("\n")) {
    const linhas = par.trim() === "" ? [""] : doc.splitTextToSize(par, largura);
    for (const l of linhas) {
      if (y > altura - margem) {
        doc.addPage();
        y = margem;
      }
      doc.text(l, margem, y);
      y += 5.2;
    }
  }
  const dataUri = doc.output("datauristring");
  return dataUri.slice(dataUri.indexOf(",") + 1);
}

/** Envia o aditivo para assinatura eletrônica pelo fluxo já existente (assinatura-solicitar). */
export function useEnviarAditivoEc141() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (aditivoId: string) => {
      const { data: docu, error } = await rpc("ponto_ec141_aditivo_documento", { p_aditivo_id: aditivoId });
      if (error || !docu?.ok) throw new Error("Aditivo não encontrado.");
      const pdf = await pdfDoAditivo(docu.titulo, docu.texto);
      const host = window.location.hostname;
      const ehProducao = host === "youreyes.com.br" || host.endsWith(".youreyes.com.br");
      const linkBase = ehProducao ? "https://youreyes.com.br/" : `${window.location.origin}${import.meta.env.BASE_URL || "/"}`;
      const r = await chamarBorda("assinatura-solicitar", {
        acao: "enviar_aditivo_ec141", aditivo_id: aditivoId, pdf_base64: pdf, link_base: linkBase,
      });
      if (!r?.ok) {
        const msg: Record<string, string> = {
          sem_email: "O colaborador não tem e-mail cadastrado: colha a assinatura do aditivo em papel.",
          ja_existe_ativa: "Este aditivo já tem um envio em andamento.",
          aditivo_cancelado: "Este aditivo foi cancelado.",
          sem_cpf: "O colaborador não tem CPF na atribuição da escala.",
        };
        throw new Error(r?.mensagem || (r?.erro ? msg[r.erro] : undefined) || r?.erro || "Não foi possível enviar o aditivo.");
      }
      return r as { link?: string; email_enviado?: boolean; destino?: string };
    },
    onSuccess: (r) => {
      queryClient.invalidateQueries({ queryKey: ["ponto-ec141-aditivos"] });
      toast.success(r.email_enviado ? `Aditivo enviado para assinatura (${r.destino || "e-mail do colaborador"}).` : "Aditivo enviado; o e-mail não saiu — copie o link na lista.");
    },
    onError: (e: Error) => toast.error(e.message),
  });
}

/** Conferência do salvar (mesma regra do gatilho): bloqueios e avisos da EC 141. */
export async function validarSalvarEscalaEc141(escalaId: string | null, dados: Record<string, unknown>, desde?: string | null) {
  const { data, error } = await rpc("ponto_escala_ec141_validar_salvar", {
    p_escala_id: escalaId, p_dados: dados, p_desde: desde || null,
  });
  if (error || !data?.ok) return { bloqueia: false, erros: [] as { mensagem: string }[], avisos: [] as AvisoMigracao[] };
  return data as { bloqueia: boolean; erros: { mensagem: string }[]; avisos: AvisoMigracao[] };
}
