import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useTenant } from "./useTenant";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import type { IndicatorType } from "@/components/dashboard/IndicatorDetailModal";

interface MonthlyPoint {
  month: string;
  [key: string]: string | number;
}

const MONTH_LABELS = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"];

function getMonthRange(monthsBack: number) {
  const now = new Date();
  const points: { year: number; month: number; label: string }[] = [];
  for (let i = monthsBack - 1; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    points.push({
      year: d.getFullYear(),
      month: d.getMonth(),
      label: MONTH_LABELS[d.getMonth()],
    });
  }
  return points;
}

function startOfMonth(year: number, month: number) {
  return new Date(year, month, 1).toISOString();
}
function endOfMonth(year: number, month: number) {
  return new Date(year, month + 1, 0, 23, 59, 59).toISOString();
}

export function useIndicatorHistory(indicator: IndicatorType, monthsBack = 6) {
  const { tenant } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();

  return useQuery({
    queryKey: ["indicator-history", indicator, tenant?.id, empresaAtivaId, monthsBack],
    queryFn: async (): Promise<MonthlyPoint[]> => {
      if (!tenant?.id) return [];

      const months = getMonthRange(monthsBack);
      const from = startOfMonth(months[0].year, months[0].month);
      const to = endOfMonth(months[months.length - 1].year, months[months.length - 1].month);

      switch (indicator) {
        case "organizacao": {
          // Score based on cargos + departamentos at current time (no historical breakdown needed)
          const [cargosRes, deptRes] = await Promise.all([
            supabase.from("cargos").select("id, created_at").eq("tenant_id", tenant.id).eq("ativo", true),
            supabase.from("departamentos").select("id, created_at").eq("tenant_id", tenant.id).eq("ativo", true),
          ]);
          const cargos = cargosRes.data || [];
          const depts = deptRes.data || [];
          return months.map((m) => {
            const cutoff = endOfMonth(m.year, m.month);
            const cargosCount = cargos.filter(c => c.created_at <= cutoff).length;
            const deptsCount = depts.filter(d => d.created_at <= cutoff).length;
            const score = Math.min(100, Math.round(
              (cargosCount > 0 ? 25 : 0) + (deptsCount > 0 ? 25 : 0) +
              (cargosCount >= 5 ? 25 : cargosCount * 5) + (deptsCount >= 3 ? 25 : deptsCount * 8)
            ));
            return { month: m.label, score };
          });
        }

        case "condicoes": {
          const [nr17Res] = await Promise.all([
            supabase.from("ergonomia_itens_nr17").select("id, status, created_at").eq("tenant_id", tenant.id),
          ]);
          const nr17 = nr17Res.data || [];
          return months.map((m) => {
            const cutoff = endOfMonth(m.year, m.month);
            const itens = nr17.filter(i => i.created_at <= cutoff);
            const atendidos = itens.filter(i => i.status === "atendido").length;
            const parciais = itens.filter(i => i.status === "parcial").length;
            const score = itens.length > 0
              ? Math.round(((atendidos + parciais * 0.5) / itens.length) * 100)
              : 0;
            return { month: m.label, score };
          });
        }

        case "experiencia": {
          const humorRes = await supabase
            .from("humor_diario")
            .select("id, humor, data")
            .eq("tenant_id", tenant.id)
            .gte("data", from.split("T")[0]);

          const humores = humorRes.data || [];
          return months.map((m) => {
            const mStart = startOfMonth(m.year, m.month).split("T")[0];
            const mEnd = endOfMonth(m.year, m.month).split("T")[0];
            const mHumor = humores.filter(h => h.data >= mStart && h.data <= mEnd);
            const positivo = mHumor.filter(h => ["bem", "animado", "motivado"].includes(h.humor)).length;
            const score = mHumor.length > 0
              ? Math.round((positivo / mHumor.length) * 100)
              : 0;
            return { month: m.label, score };
          });
        }

        case "governanca": {
          const acoesRes = await supabase.from("ergonomia_acoes").select("id, status, created_at").eq("tenant_id", tenant.id);
          const acoes = acoesRes.data || [];
          return months.map((m) => {
            const cutoff = endOfMonth(m.year, m.month);
            const mAcoes = acoes.filter(a => a.created_at <= cutoff);
            const concluidas = mAcoes.filter(a => a.status === "concluida").length;
            const score = mAcoes.length > 0
              ? Math.round((concluidas / mAcoes.length) * 100)
              : 0;
            return { month: m.label, score };
          });
        }

        case "admissoes": {
          const res = await (supabase.rpc as any)("admissoes_historico_status", { p_empresa_id: empresaAtivaId ?? null, p_de: from, p_ate: to });
          const data = res.data || [];
          return months.map((m) => {
            const s = startOfMonth(m.year, m.month);
            const e = endOfMonth(m.year, m.month);
            const mData = data.filter(d => d.created_at >= s && d.created_at <= e);
            return {
              month: m.label,
              concluidas: mData.filter(d => d.status === "concluido").length,
              pendentes: mData.filter(d => d.status !== "concluido" && d.status !== "reprovado").length,
            };
          });
        }

        case "nr17": {
          const res = await supabase.from("ergonomia_itens_nr17").select("id, status, created_at").eq("tenant_id", tenant.id);
          const data = res.data || [];
          return months.map((m) => {
            const cutoff = endOfMonth(m.year, m.month);
            const items = data.filter(d => d.created_at <= cutoff);
            return {
              month: m.label,
              atendidos: items.filter(i => i.status === "atendido").length,
              parciais: items.filter(i => i.status === "parcial").length,
              naoAtendidos: items.filter(i => i.status === "nao_atendido").length,
            };
          });
        }

        case "epis": {
          const res = await supabase.from("epis").select("id, status, created_at").eq("tenant_id", tenant.id).match(empresaAtivaId ? { empresa_id: empresaAtivaId } : {});
          const data = res.data || [];
          return months.map((m) => {
            const cutoff = endOfMonth(m.year, m.month);
            const items = data.filter(d => d.created_at <= cutoff);
            return {
              month: m.label,
              disponiveis: items.filter(i => i.status === "disponivel").length,
              total: items.length,
            };
          });
        }

        case "humor": {
          const res = await supabase.from("humor_diario").select("id, humor, data").eq("tenant_id", tenant.id).gte("data", from.split("T")[0]);
          const data = res.data || [];
          return months.map((m) => {
            const mStart = startOfMonth(m.year, m.month).split("T")[0];
            const mEnd = endOfMonth(m.year, m.month).split("T")[0];
            const mData = data.filter(d => d.data >= mStart && d.data <= mEnd);
            return {
              month: m.label,
              positivo: mData.filter(h => ["bem", "animado", "motivado"].includes(h.humor)).length,
              neutro: mData.filter(h => ["neutro", "normal"].includes(h.humor)).length,
              negativo: mData.filter(h => ["mal", "estressado", "triste", "ansioso"].includes(h.humor)).length,
            };
          });
        }

        case "ouvidoria": {
          const res = await supabase.from("ouvidoria").select("id, status, created_at").eq("tenant_id", tenant.id).gte("created_at", from);
          const data = res.data || [];
          return months.map((m) => {
            const s = startOfMonth(m.year, m.month);
            const e = endOfMonth(m.year, m.month);
            const mData = data.filter(d => d.created_at >= s && d.created_at <= e);
            return {
              month: m.label,
              recebidas: mData.length,
              resolvidas: mData.filter(d => d.status === "resolvida").length,
              pendentes: mData.filter(d => d.status === "pendente").length,
            };
          });
        }

        case "acoes": {
          const res = await supabase.from("ergonomia_acoes").select("id, status, created_at").eq("tenant_id", tenant.id).gte("created_at", from);
          const data = res.data || [];
          return months.map((m) => {
            const s = startOfMonth(m.year, m.month);
            const e = endOfMonth(m.year, m.month);
            const mData = data.filter(d => d.created_at >= s && d.created_at <= e);
            return {
              month: m.label,
              concluidas: mData.filter(d => d.status === "concluida").length,
              emAndamento: mData.filter(d => d.status === "em_andamento").length,
              pendentes: mData.filter(d => d.status === "pendente").length,
            };
          });
        }

        case "riscos": {
          const res = await supabase.from("ergonomia_riscos").select("id, ativo, created_at").eq("tenant_id", tenant.id);
          const data = res.data || [];
          return months.map((m) => {
            const cutoff = endOfMonth(m.year, m.month);
            const items = data.filter(d => d.created_at <= cutoff);
            return {
              month: m.label,
              ativos: items.filter(d => d.ativo).length,
              total: items.length,
            };
          });
        }

        default:
          return months.map((m) => ({ month: m.label, valor: 0 }));
      }
    },
    enabled: !!tenant?.id,
    staleTime: 1000 * 60 * 5,
  });
}
