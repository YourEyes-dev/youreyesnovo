/**
 * Gerador ÚNICO do Espelho de Ponto (e do Cartão Ponto, mesma moldura).
 *
 * Antes havia dois: o PDF legal da aba Relatórios (cartaoPonto.ts) e um PDF
 * simplificado na aba Fechamento, com números e leiaute diferentes. Um
 * colaborador podia receber dois "espelhos" do mesmo mês que não batiam.
 * Agora Relatórios (baixar), Fechamento (baixar) e o envio para assinatura
 * montam o documento por aqui.
 *
 * Fontes (as mesmas do Banco de Horas, para os documentos não discordarem):
 *   - dia a dia: RPC ponto_saldo_dias_competencia;
 *   - batidas: ponto_marcacoes (sem as desconsideradas), com origem O/A;
 *   - totais de banco: RPC ponto_banco_horas_oficial (fonte única), com
 *     fallback na fotografia ponto_banco_horas.
 *
 * Reprodutível: `fixar` grava a data de criação e o identificador do arquivo
 * no próprio PDF, para que dois cliques gerem o mesmo documento.
 */
import jsPDF from "jspdf";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { carregarLogo } from "./pdfMarca";
import {
  desenharCartaoPonto,
  desenharEspelhoPonto,
  type CartaoBanco,
  type CartaoEmpregador,
} from "./cartaoPonto";

export type MarcacaoDia = {
  hora: string;
  tipo: string | null;
  /** RN26 — origem: O = original do colaborador, A = ajuste do RH. */
  origem: "O" | "A";
};

export type DiaEspelho = {
  dia: string;
  entrada: string | null;
  saida: string | null;
  trabalhado_min: number;
  jornada_min: number;
  saldo_min: number;
  protegido: boolean;
  equalizacao: boolean;
  excedente_retido_min: number;
  marcacoes: MarcacaoDia[];
  /** Súmula 338/TST: intervalo declarado (pré-assinalado) em vez de batido. */
  intervalo_origem?: "marcado" | "pre_assinalado" | null;
  intervalo_pre_assinalado_min?: number | null;
  /** Marcação sem par (ou ajuste em aberto): o dia está pendente, não zerado. */
  pendencia?: boolean;
  /** Folga compensatória declarada (débito vem da compensação no banco). */
  folga_compensatoria?: boolean;
  /** Falta convertida em débito do banco (compensação efetivada). */
  falta_compensada?: boolean;
};

export type EspelhoColaborador = {
  nome: string;
  cpf: string;
  dias: DiaEspelho[];
  trabalhado: number;
  previsto: number;
  creditos: number;
  debitos: number;
  saldo: number;
  faltas: number;
  protegidos: number;
  he50: number;
  he100: number;
};

export type AlvoEspelho = { nome: string; cpf: string };

const soDigitos = (v?: string | null) => (v || "").replace(/\D/g, "");

const DIAS_SEMANA = ["DOM", "SEG", "TER", "QUA", "QUI", "SEX", "SAB"];
const ehDomingo = (iso: string) => {
  const [a, m, d] = iso.split("-").map(Number);
  return DIAS_SEMANA[new Date(a, m - 1, d).getDay()] === "DOM";
};

/** Percentual aplicável ao excedente do dia (RN17 / art. 59 CLT). */
export const percentualHE = (d: DiaEspelho) =>
  ehDomingo(d.dia) || d.jornada_min === 0 ? "100%" : "50%";

const dataBr = (iso: string) => {
  const [a, m, d] = iso.split("-");
  return `${d}/${m}/${a}`;
};

const limitesCompetencia = (competencia: string) => {
  const [ano, mes] = competencia.split("-").map(Number);
  const ultimoDia = new Date(ano, mes, 0).getDate();
  return {
    ano,
    mes,
    ultimoDia,
    inicio: `${competencia}-01`,
    fim: `${competencia}-${String(ultimoDia).padStart(2, "0")}`,
  };
};

/**
 * Dia a dia de cada colaborador pedido, já com as batidas, o intervalo
 * pré-assinalado, as pendências, as folgas e as faltas compensadas.
 * `alvos` já vem recortado (filtro e vigência ficam com quem chama).
 */
export async function carregarEspelhoDetalhado(params: {
  tenantId: string;
  competencia: string;
  alvos: AlvoEspelho[];
}): Promise<EspelhoColaborador[]> {
  const { tenantId, competencia } = params;
  const { inicio, fim } = limitesCompetencia(competencia);
  const unicos = Array.from(
    new Map(params.alvos.filter((b) => b.cpf).map((b) => [soDigitos(b.cpf), { ...b, cpf: soDigitos(b.cpf) }])).values(),
  ).sort((a, b) => (a.nome || "").localeCompare(b.nome || "", "pt-BR"));
  if (unicos.length === 0) return [];

  // RN26 — todas as batidas da competência, com origem rastreável. Paginado:
  // o limite padrão do PostgREST (1000 linhas) truncava as últimas batidas.
  const marcacoesMes: any[] = [];
  const PAGINA = 1000;
  for (let offset = 0; ; offset += PAGINA) {
    const { data: pagina, error: errMarc } = (await fromTable("ponto_marcacoes")
      .select("colaborador_cpf, data_marcacao, hora_marcacao, tipo_marcacao, marcacao_original, origem_marcacao")
      .eq("tenant_id", tenantId)
      // Batida desconsiderada sai do cálculo do dia em toda a apuração: o
      // espelho mostra as MESMAS batidas que a conta usou (ela segue no AFD).
      .eq("desconsiderada", false)
      .gte("data_marcacao", inicio)
      .lte("data_marcacao", fim)
      .order("data_marcacao")
      .order("hora_marcacao")
      .range(offset, offset + PAGINA - 1)) as { data: any[] | null; error: any };
    if (errMarc) throw errMarc;
    const linhas = pagina || [];
    marcacoesMes.push(...linhas);
    if (linhas.length < PAGINA) break;
  }

  const intervaloPorCpfDia = new Map<string, { origem: string | null; minutos: number | null }>();
  const pendenciaPorCpfDia = new Set<string>();
  const folgaPorCpfDia = new Set<string>();
  {
    const { data: diarios, error: errDia } = (await fromTable("ponto_diario")
      .select("colaborador_cpf, data, status, tipo_dia, intervalo_origem, intervalo_pre_assinalado_minutos")
      .eq("tenant_id", tenantId)
      .or("intervalo_origem.eq.pre_assinalado,status.in.(incompleto,ajuste_pendente),tipo_dia.eq.folga_compensatoria")
      .gte("data", inicio)
      .lte("data", fim)) as { data: any[] | null; error: any };
    if (errDia) throw errDia;
    (diarios || []).forEach((d: any) => {
      const chave = `${soDigitos(d.colaborador_cpf)}|${d.data}`;
      if (d.intervalo_origem === "pre_assinalado") {
        intervaloPorCpfDia.set(chave, {
          origem: d.intervalo_origem ?? null,
          minutos: d.intervalo_pre_assinalado_minutos ?? null,
        });
      }
      if (d.status === "incompleto" || d.status === "ajuste_pendente") pendenciaPorCpfDia.add(chave);
      if (d.tipo_dia === "folga_compensatoria") folgaPorCpfDia.add(chave);
    });
  }

  // Faltas convertidas em débito do banco (compensação EFETIVADA).
  const faltaCompensadaPorCpfDia = new Set<string>();
  {
    const { data: comps, error: errComp } = (await fromTable("ponto_compensacao_falta")
      .select("colaborador_cpf, data_falta, status")
      .eq("tenant_id", tenantId)
      .eq("status", "efetivada")
      .gte("data_falta", inicio)
      .lte("data_falta", fim)) as { data: any[] | null; error: any };
    if (errComp) throw errComp;
    (comps || []).forEach((c: any) => {
      faltaCompensadaPorCpfDia.add(`${soDigitos(c.colaborador_cpf)}|${c.data_falta}`);
    });
  }

  const porCpfDia = new Map<string, MarcacaoDia[]>();
  marcacoesMes.forEach((m: any) => {
    const chave = `${soDigitos(m.colaborador_cpf)}|${m.data_marcacao}`;
    const lista = porCpfDia.get(chave) || [];
    lista.push({
      hora: String(m.hora_marcacao || "").substring(0, 5),
      tipo: m.tipo_marcacao ?? null,
      // Marcação não original é sempre incluída ("A"), mesmo com rótulo antigo "O".
      origem: m.marcacao_original === false || m.origem_marcacao === "A" ? "A" : "O",
    });
    porCpfDia.set(chave, lista);
  });

  const resultado: EspelhoColaborador[] = [];
  for (const c of unicos) {
    const { data, error } = await (supabase.rpc as any)("ponto_saldo_dias_competencia", {
      p_tenant_id: tenantId,
      p_colaborador_cpf: c.cpf,
      p_competencia: competencia,
    });
    if (error) throw error;

    const dias: DiaEspelho[] = ((data || []) as any[])
      .map((d) => {
        const chave = `${c.cpf}|${String(d.dia)}`;
        return {
          dia: String(d.dia),
          entrada: d.entrada ? String(d.entrada).substring(0, 5) : null,
          saida: d.saida ? String(d.saida).substring(0, 5) : null,
          trabalhado_min: Number(d.trabalhado_min) || 0,
          jornada_min: Number(d.jornada_min) || 0,
          saldo_min: Number(d.saldo_min) || 0,
          protegido: Boolean(d.protegido),
          equalizacao: Boolean(d.equalizacao),
          excedente_retido_min: Number(d.excedente_retido_min) || 0,
          marcacoes: (porCpfDia.get(chave) || []).slice().sort((a, b) => a.hora.localeCompare(b.hora)),
          intervalo_origem: (intervaloPorCpfDia.get(chave)?.origem ?? null) as "marcado" | "pre_assinalado" | null,
          intervalo_pre_assinalado_min: intervaloPorCpfDia.get(chave)?.minutos ?? null,
          pendencia: pendenciaPorCpfDia.has(chave),
          folga_compensatoria: folgaPorCpfDia.has(chave),
          falta_compensada: faltaCompensadaPorCpfDia.has(chave),
        };
      })
      .sort((a, b) => a.dia.localeCompare(b.dia));

    resultado.push({
      nome: c.nome,
      cpf: c.cpf,
      dias,
      trabalhado: dias.reduce((s, d) => s + d.trabalhado_min, 0),
      previsto: dias.reduce((s, d) => s + d.jornada_min, 0),
      creditos: dias.reduce((s, d) => s + (d.saldo_min > 0 ? d.saldo_min : 0), 0),
      debitos: dias.reduce((s, d) => s + (d.saldo_min < 0 ? -d.saldo_min : 0), 0),
      saldo: dias.reduce((s, d) => s + d.saldo_min, 0),
      // Falta compensada em banco não conta como falta (vira débito no banco).
      faltas: dias.filter((d) => !d.protegido && !d.falta_compensada && d.jornada_min > 0 && d.trabalhado_min === 0).length,
      protegidos: dias.filter((d) => d.protegido).length,
      he50: dias.reduce((s, d) => s + (d.saldo_min > 0 && percentualHE(d) === "50%" ? d.saldo_min : 0), 0),
      he100: dias.reduce((s, d) => s + (d.saldo_min > 0 && percentualHE(d) === "100%" ? d.saldo_min : 0), 0),
    });
  }
  return resultado;
}

/** Dados de moldura do documento: empregador, cadastro e banco de horas. */
export interface ContextoEspelho {
  empregador: CartaoEmpregador;
  /** Cadastro do colaborador por CPF (só dígitos). */
  colaboradorPorCpf: Map<string, any>;
  /** Fonte única do banco (ponto_banco_horas_oficial) por CPF. */
  oficialPorCpf: Map<string, any>;
  /** Fotografia ponto_banco_horas por CPF (fallback). */
  bancoPorCpf: Map<string, any>;
}

const formatarCnpj = (v?: string | null) => {
  const d = soDigitos(v);
  if (d.length !== 14) return null;
  return `${d.slice(0, 2)}.${d.slice(2, 5)}.${d.slice(5, 8)}/${d.slice(8, 12)}-${d.slice(12)}`;
};

/** Monta o empregador a partir de uma linha de empresa_cadastro. */
export function empregadorDaEmpresa(emp: any | null | undefined): CartaoEmpregador {
  const e = emp || {};
  return {
    razaoSocial: e.razao_social || e.nome_fantasia || "—",
    cnpj: formatarCnpj(e.cnpj),
    endereco: [e.endereco, e.numero, e.bairro].filter(Boolean).join(", ") || null,
    cidade: e.cidade || null,
    uf: e.estado || null,
  };
}

/** Busca no banco tudo o que a moldura precisa (para quem não tem isso em tela). */
export async function carregarContextoEspelho(params: {
  tenantId: string;
  empresaId: string | null;
  competencia: string;
}): Promise<ContextoEspelho> {
  const { tenantId, empresaId, competencia } = params;

  let empresa: any = null;
  if (empresaId) {
    const { data } = (await fromTable("empresa_cadastro")
      .select("id, razao_social, nome_fantasia, cnpj, endereco, numero, bairro, cidade, estado")
      .eq("tenant_id", tenantId)
      .eq("id", empresaId)
      .maybeSingle()) as { data: any };
    empresa = data;
  }

  const colaboradorPorCpf = new Map<string, any>();
  {
    const { data, error } = await (supabase.rpc as any)("colaboradores_diretorio", {
      p_empresa_id: empresaId ?? null,
    });
    if (error) throw error;
    ((data || []) as any[]).forEach((c) => {
      const cpf = soDigitos(c.cpf);
      if (cpf && !colaboradorPorCpf.has(cpf)) colaboradorPorCpf.set(cpf, c);
    });
  }

  const oficialPorCpf = new Map<string, any>();
  {
    const { data, error } = await (supabase.rpc as any)("ponto_banco_horas_oficial", {
      p_tenant_id: tenantId,
      p_competencia: competencia,
      p_empresa_id: empresaId || null,
    });
    if (error) throw error;
    ((data || []) as any[]).forEach((o) => {
      const cpf = soDigitos(o.colaborador_cpf);
      if (cpf) oficialPorCpf.set(cpf, o);
    });
  }

  const bancoPorCpf = new Map<string, any>();
  {
    let q = fromTable("ponto_banco_horas").select("*").eq("tenant_id", tenantId).eq("competencia", competencia);
    if (empresaId) q = q.eq("empresa_id", empresaId);
    const { data, error } = (await q) as { data: any[] | null; error: any };
    if (error) throw error;
    (data || []).forEach((b: any) => {
      const cpf = soDigitos(b.colaborador_cpf);
      if (cpf && !bancoPorCpf.has(cpf)) bancoPorCpf.set(cpf, b);
    });
  }

  return { empregador: empregadorDaEmpresa(empresa), colaboradorPorCpf, oficialPorCpf, bancoPorCpf };
}

/**
 * Totais do banco impressos no documento. Vêm da FONTE ÚNICA (a mesma do
 * relatório de Banco de Horas): competência fechada devolve a apuração
 * congelada, aberta devolve a de agora. Sem ela, cai na fotografia.
 */
function bancoDoColaborador(c: EspelhoColaborador, ctx: ContextoEspelho): CartaoBanco {
  const of = ctx.oficialPorCpf.get(c.cpf);
  if (of) {
    return {
      saldoAnterior: of.saldo_anterior_min,
      creditos: of.creditos_min,
      debitos: of.debitos_min,
      compensados: of.compensados_min,
      saldoAtual: of.saldo_atual_min,
      temRegime: of.tem_regime !== false,
    };
  }
  const banco = ctx.bancoPorCpf.get(c.cpf);
  return {
    saldoAnterior: banco?.saldo_anterior_minutos ?? 0,
    creditos: c.creditos,
    debitos: c.debitos,
    compensados: banco?.compensados_minutos ?? 0,
    saldoAtual: (banco?.saldo_anterior_minutos ?? 0) + c.saldo - (banco?.compensados_minutos ?? 0),
  };
}

export interface MontarEspelhoParams {
  tenantId: string;
  empresaId: string | null;
  competencia: string;
  alvos: AlvoEspelho[];
  /** "espelho" = modelo legal (padrão); "cartao" = modelo clássico do contador. */
  variante?: "espelho" | "cartao";
  /** false = sem o painel de banco de horas (folha sem banco). */
  incluirBanco?: boolean;
  /** Moldura já carregada pela tela (evita buscar de novo). */
  contexto?: ContextoEspelho;
  /** Texto "emitido em" impresso no documento. */
  emissao?: string;
  /** Data de criação e identificador gravados no PDF (documento reprodutível). */
  fixar?: { criadoEm: Date; fileId?: string };
}

export interface EspelhoMontado {
  doc: jsPDF;
  colaboradores: EspelhoColaborador[];
}

const doisDigitos = (n: number) => String(n).padStart(2, "0");

/** Monta o PDF: uma folha (ou mais, se o mês transbordar) por colaborador. */
export async function montarEspelhoPdf(params: MontarEspelhoParams): Promise<EspelhoMontado> {
  const { tenantId, empresaId, competencia } = params;
  const variante = params.variante ?? "espelho";
  const ctx = params.contexto ?? (await carregarContextoEspelho({ tenantId, empresaId, competencia }));
  const detalhado = await carregarEspelhoDetalhado({ tenantId, competencia, alvos: params.alvos });

  const doc = new jsPDF();
  if (params.fixar) {
    const d = params.fixar.criadoEm;
    doc.setCreationDate(d);
    if (params.fixar.fileId) doc.setFileId(params.fixar.fileId);
  }
  if (detalhado.length === 0) return { doc, colaboradores: [] };

  const logo = await carregarLogo();
  const { ano, mes, ultimoDia } = limitesCompetencia(competencia);
  const periodo = `01/${doisDigitos(mes)}/${ano} a ${ultimoDia}/${doisDigitos(mes)}/${ano}`;
  const agora = params.fixar?.criadoEm ?? new Date();
  const emissao =
    params.emissao ??
    `${doisDigitos(agora.getDate())}/${doisDigitos(agora.getMonth() + 1)}/${agora.getFullYear()} às ${doisDigitos(agora.getHours())}:${doisDigitos(agora.getMinutes())}`;

  const desenhar = variante === "espelho" ? desenharEspelhoPonto : desenharCartaoPonto;
  detalhado.forEach((c, i) => {
    if (i > 0) doc.addPage();
    const col = ctx.colaboradorPorCpf.get(c.cpf);
    desenhar(doc, {
      incluirBanco: params.incluirBanco ?? true,
      empregador: ctx.empregador,
      empregado: {
        nome: c.nome,
        cpf: c.cpf,
        matricula: col?.matricula || null,
        cargo: col?.cargo || null,
        setor: col?.departamento || null,
        admissao: col?.data_admissao ? dataBr(String(col.data_admissao).substring(0, 10)) : null,
        categoria: col?.tipo_contrato || "Mensalista",
        horarios: col?.jornada_trabalho || null,
      },
      periodo,
      emissao,
      dias: c.dias,
      banco: bancoDoColaborador(c, ctx),
      logoDataUrl: logo,
    });
  });

  return { doc, colaboradores: detalhado };
}

/** Identificador estável (32 hex) para o PDF, a partir de um texto. */
export async function idArquivoEstavel(texto: string): Promise<string> {
  const bytes = new TextEncoder().encode(texto);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hash))
    .slice(0, 16)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .toUpperCase();
}
