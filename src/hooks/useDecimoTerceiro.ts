/**
 * Apuração do 13º salário (RF-001 / RF-002 / CA-001 / CA-002 do YE-DP-13-001).
 *
 * Chama a apuração do banco (`decimo_terceiro_apurar`), que:
 *   • conta os avos da Lei 4.090/1962 — 1/12 por mês, fração de 15 dias —
 *     a partir da admissão, das faltas injustificadas do ponto e do
 *     afastamento previdenciário;
 *   • soma a média das variáveis do ano pelas rubricas marcadas como
 *     integrantes do 13º no cadastro de rubricas;
 *   • devolve as duas MEMÓRIAS — mês a mês e competência a competência —
 *     que são o que torna o valor reproduzível e auditável depois.
 *
 * Somente leitura: nada é gravado pela apuração.
 */
import { useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useTenant } from "@/hooks/useTenant";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";

export interface AvosMes {
  mes: number;
  dias_vinculo: number;
  faltas: number;
  dias_inss: number;
  dias_computados: number;
  conta: boolean;
}

export interface MemoriaAvos {
  avos: number;
  admissao: string | null;
  desligamento: string | null;
  tem_ponto: boolean;
  afastamento_regra: string;
  dias_empregador: number;
  parametros_vigencia: string;
  fundamento: string;
  meses: AvosMes[];
  avisos: string[];
}

export interface MemoriaMediaCompetencia {
  competencia: string;
  valor: number;
}

export interface MemoriaMediaRubrica {
  codigo: string | null;
  descricao: string;
  valor: number;
}

export interface MemoriaMedia {
  media: number;
  total: number;
  meses_divisor: number;
  meses_com_valor: number;
  divisor_regra: string;
  rubricas_marcadas: number;
  janela_inicio: string;
  janela_fim: string;
  parametros_vigencia: string;
  fundamento: string;
  competencias: MemoriaMediaCompetencia[];
  rubricas: MemoriaMediaRubrica[];
  avisos: string[];
}

export interface Apuracao13 {
  ano: number;
  avos: number;
  remuneracao_base: number;
  media_variaveis: number;
  base_integral: number;
  base_proporcional: number;
  apurado_em: string;
  memoria_avos: MemoriaAvos;
  memoria_media: MemoriaMedia;
  avisos: string[];
}

export interface Apurar13Params {
  cpf: string;
  ano: number;
  salario?: number;
}

const MESES = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];

export function nomeMes(mes: number): string {
  return MESES[mes - 1] ?? String(mes);
}

export function useDecimoTerceiro() {
  const { tenantId } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();
  const [apurando, setApurando] = useState(false);

  const apurar = useCallback(
    async (p: Apurar13Params): Promise<Apuracao13 | null> => {
      if (!tenantId) return null;
      setApurando(true);
      try {
        // A função é nova: ainda não está no schema tipado gerado pelo Supabase.
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const rpc = (supabase as any).rpc.bind(supabase);
        const { data, error } = await rpc("decimo_terceiro_apurar", {
          p_tenant: tenantId,
          p_cpf: p.cpf,
          p_ano: p.ano,
          p_salario: p.salario ?? null,
          p_empresa: empresaAtivaId || null,
        });
        if (error) throw error;
        const bruto = (data || {}) as Record<string, unknown>;
        return {
          ano: Number(bruto.ano ?? p.ano),
          avos: Number(bruto.avos ?? 0),
          remuneracao_base: Number(bruto.remuneracao_base ?? 0),
          media_variaveis: Number(bruto.media_variaveis ?? 0),
          base_integral: Number(bruto.base_integral ?? 0),
          base_proporcional: Number(bruto.base_proporcional ?? 0),
          apurado_em: String(bruto.apurado_em ?? ""),
          memoria_avos: (bruto.memoria_avos as MemoriaAvos) ?? ({ meses: [], avisos: [] } as unknown as MemoriaAvos),
          memoria_media: (bruto.memoria_media as MemoriaMedia) ?? ({ competencias: [], rubricas: [], avisos: [] } as unknown as MemoriaMedia),
          avisos: (bruto.avisos as string[]) ?? [],
        };
      } finally {
        setApurando(false);
      }
    },
    [tenantId, empresaAtivaId],
  );

  return { apurar, apurando };
}

/** Frase curta que explica de onde saíram os avos, para a tela e para a memória. */
export function descreverAvos(a: Apuracao13): string {
  const contados = a.memoria_avos.meses?.filter(m => m.conta).map(m => nomeMes(m.mes)) ?? [];
  if (contados.length === 0) return "Nenhum mês do ano fechou 15 dias de trabalho.";
  return `${a.avos}/12 avos — meses que fecharam 15 dias: ${contados.join(", ")}.`;
}

/** Frase curta que explica de onde saiu a média das variáveis. */
export function descreverMedia13(a: Apuracao13): string {
  const m = a.memoria_media;
  const total = (m.total ?? 0).toLocaleString("pt-BR", { minimumFractionDigits: 2 });
  const divisor =
    m.divisor_regra === "doze_avos" ? "12 avos"
      : m.divisor_regra === "meses_com_valor" ? `${m.meses_divisor} mês(es) com valor`
        : `${m.meses_divisor} avo(s) apurado(s)`;
  return `Soma de R$ ${total} nas competências ${m.janela_inicio} a ${m.janela_fim}, dividida por ${divisor}.`;
}


/* ── Processamento em lote (Entrega 2) ────────────────────────────────
 * A folha de dezembro de uma empresa inteira não cabe num modal aberto
 * colaborador a colaborador (RNF-008). O lote roda no banco: apura,
 * calcula os encargos e grava, pulando quem já tem cálculo vivo.
 */
export interface ResultadoLote {
  lote_id: string;
  ano: number;
  parcela: number;
  prazo_legal: string;
  criados: number;
  ja_existiam: number;
  sem_avo: number;
  total_liquido: number;
  erros: { colaborador: string; erro: string }[];
}

export function useDecimoTerceiroLote() {
  const { tenantId } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();
  const [processando, setProcessando] = useState(false);

  const processar = useCallback(
    async (ano: number, parcela: 1 | 2): Promise<ResultadoLote | null> => {
      if (!tenantId) return null;
      setProcessando(true);
      try {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const rpc = (supabase as any).rpc.bind(supabase);
        const { data, error } = await rpc("decimo_terceiro_lote", {
          p_tenant: tenantId,
          p_ano: ano,
          p_parcela: parcela,
          p_empresa: empresaAtivaId || null,
        });
        if (error) throw error;
        const b = (data || {}) as Record<string, unknown>;
        if (b.erro) throw new Error(String(b.erro));
        return {
          lote_id: String(b.lote_id ?? ""),
          ano: Number(b.ano ?? ano),
          parcela: Number(b.parcela ?? parcela),
          prazo_legal: String(b.prazo_legal ?? ""),
          criados: Number(b.criados ?? 0),
          ja_existiam: Number(b.ja_existiam ?? 0),
          sem_avo: Number(b.sem_avo ?? 0),
          total_liquido: Number(b.total_liquido ?? 0),
          erros: (b.erros as { colaborador: string; erro: string }[]) ?? [],
        };
      } finally {
        setProcessando(false);
      }
    },
    [tenantId, empresaAtivaId],
  );

  return { processar, processando };
}

/** Frase de resultado do lote, para o toast e para a tela. */
export function descreverLote(r: ResultadoLote): string {
  const partes = [`${r.criados} cálculo(s) gerado(s)`];
  if (r.ja_existiam > 0) partes.push(`${r.ja_existiam} já existia(m)`);
  if (r.sem_avo > 0) partes.push(`${r.sem_avo} sem avo no ano`);
  if (r.erros.length > 0) partes.push(`${r.erros.length} com erro`);
  return partes.join(" · ");
}

/* ── Configuração do 13º por empresa ──────────────────────────────────
 * Onde as duas leituras legítimas do adiantamento (Lei 4.749/1965) e o
 * método da média das horas extras (Súmula 347 do TST) ficam à escolha
 * da empresa, em vez de decididos por quem escreveu o código.
 */
export interface Config13 {
  media_divisor: string;
  media_inclui_protegidas: boolean;
  media_horas_extras: string;
  divisor_horas_mes: number;
  afastamento_regra: string;
  afastamento_dias_empregador: number;
  adiantamento_base: string;
  parametros_vigencia_inicio: string;
}

export const CONFIG13_PADRAO: Config13 = {
  media_divisor: "avos_apurados",
  media_inclui_protegidas: false,
  media_horas_extras: "fisica",
  divisor_horas_mes: 220,
  afastamento_regra: "previdenciario_suspende",
  afastamento_dias_empregador: 15,
  adiantamento_base: "proporcional_apurado",
  parametros_vigencia_inicio: "2026-01-01",
};

export function useDecimoTerceiroConfig() {
  const { tenantId } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();
  const [salvando, setSalvando] = useState(false);

  const carregar = useCallback(async (): Promise<Config13> => {
    if (!tenantId) return CONFIG13_PADRAO;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const from = (supabase as any).from.bind(supabase);
    const { data } = await from("decimo_terceiro_config")
      .select("*")
      .eq("tenant_id", tenantId)
      .order("empresa_id", { nullsFirst: false })
      .limit(1)
      .maybeSingle();
    if (!data) return CONFIG13_PADRAO;
    return { ...CONFIG13_PADRAO, ...(data as Partial<Config13>) };
  }, [tenantId]);

  const salvar = useCallback(
    async (c: Config13) => {
      if (!tenantId) throw new Error("Empresa não identificada");
      setSalvando(true);
      try {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const from = (supabase as any).from.bind(supabase);
        const { data: existente } = await from("decimo_terceiro_config")
          .select("id")
          .eq("tenant_id", tenantId)
          .limit(1)
          .maybeSingle();
        const linha = { ...c, tenant_id: tenantId, empresa_id: empresaAtivaId || null };
        const { error } = existente
          ? await from("decimo_terceiro_config").update(linha).eq("id", existente.id)
          : await from("decimo_terceiro_config").insert(linha);
        if (error) throw error;
      } finally {
        setSalvando(false);
      }
    },
    [tenantId, empresaAtivaId],
  );

  return { carregar, salvar, salvando };
}


/* ── Provisão, conciliação e adiantamento nas férias (Entrega 4) ──────
 * Provisão por regime de competência: o custo do 13º nasce 1/12 por mês,
 * não em dezembro. E o botão "adiantar 13º" da programação de férias,
 * que era órfão, passa a gerar a 1ª parcela (Lei 4.749/1965, art. 2º §2º).
 */
export interface ResultadoProvisao {
  competencia: string;
  provisionados: number;
  revertidos: number;
  total_provisionado: number;
}

export interface Conciliacao13 {
  ano: number;
  provisionado: number;
  pago: number;
  diferenca: number;
  situacao: string;
  por_competencia: { competencia: string; provisionado: number; colaboradores: number }[];
}

export interface ResultadoAdiantamentoFerias {
  ano: number;
  adiantamentos_gerados: number;
  ja_existiam: number;
  pedidos_fora_de_janeiro: number;
  avisos: { colaborador: string; aviso?: string; erro?: string }[];
}

export function useDecimoTerceiroContabil() {
  const { tenantId } = useTenant();
  const [ocupado, setOcupado] = useState(false);

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const rpc = () => (supabase as any).rpc.bind(supabase);

  const provisionar = useCallback(async (competencia: string): Promise<ResultadoProvisao | null> => {
    if (!tenantId) return null;
    setOcupado(true);
    try {
      const { data, error } = await rpc()("decimo_terceiro_provisionar", {
        p_competencia: competencia, p_tenant: tenantId,
      });
      if (error) throw error;
      const b = (data || {}) as Record<string, unknown>;
      if (b.erro) throw new Error(String(b.erro));
      return {
        competencia: String(b.competencia ?? competencia),
        provisionados: Number(b.provisionados ?? 0),
        revertidos: Number(b.revertidos ?? 0),
        total_provisionado: Number(b.total_provisionado ?? 0),
      };
    } finally { setOcupado(false); }
  }, [tenantId]);

  const conciliar = useCallback(async (ano: number): Promise<Conciliacao13 | null> => {
    if (!tenantId) return null;
    const { data, error } = await rpc()("decimo_terceiro_conciliar_provisao", {
      p_tenant: tenantId, p_ano: ano,
    });
    if (error) throw error;
    const b = (data || {}) as Record<string, unknown>;
    return {
      ano: Number(b.ano ?? ano),
      provisionado: Number(b.provisionado ?? 0),
      pago: Number(b.pago ?? 0),
      diferenca: Number(b.diferenca ?? 0),
      situacao: String(b.situacao ?? ""),
      por_competencia: (b.por_competencia as Conciliacao13["por_competencia"]) ?? [],
    };
  }, [tenantId]);

  const adiantarNasFerias = useCallback(
    async (ano: number): Promise<ResultadoAdiantamentoFerias | null> => {
      if (!tenantId) return null;
      setOcupado(true);
      try {
        const { data, error } = await rpc()("decimo_terceiro_adiantamento_nas_ferias", {
          p_tenant: tenantId, p_ano: ano,
        });
        if (error) throw error;
        const b = (data || {}) as Record<string, unknown>;
        if (b.erro) throw new Error(String(b.erro));
        return {
          ano: Number(b.ano ?? ano),
          adiantamentos_gerados: Number(b.adiantamentos_gerados ?? 0),
          ja_existiam: Number(b.ja_existiam ?? 0),
          pedidos_fora_de_janeiro: Number(b.pedidos_fora_de_janeiro ?? 0),
          avisos: (b.avisos as ResultadoAdiantamentoFerias["avisos"]) ?? [],
        };
      } finally { setOcupado(false); }
    }, [tenantId]);

  return { provisionar, conciliar, adiantarNasFerias, ocupado };
}
