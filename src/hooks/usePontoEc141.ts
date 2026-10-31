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
