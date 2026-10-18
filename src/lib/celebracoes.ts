import { differenceInCalendarDays, format, startOfDay } from "date-fns";
import { toDateLocal } from "@/lib/dataLocal";
import { buscarDiaProfissao } from "@/lib/diasProfissao";
import type { CulturaAcao, CulturaConfig, CulturaPreferencia } from "@/types/cultura";

// Fonte única do cálculo de "próximas celebrações". Usada pela tela de Cultura
// e pelo widget de lembretes do Mural, para os dois nunca divergirem.

export type TipoCelebracao = "aniversario" | "tempo_casa" | "dia_profissao";

export interface PessoaCelebravel {
  id: string;
  nome_completo: string;
  data_nascimento: string | null;
  data_admissao: string | null;
  cargo: string | null;
}

export type ConfigCelebracao = Pick<
  CulturaConfig,
  "aniversario_ativo" | "tempo_casa_ativo" | "dia_profissao_ativo" | "dias_antecedencia_acao"
>;

export interface Celebracao {
  /** pessoa + tipo + ano da data celebrada — base da trava de duplicidade (RN-004) */
  chave: string;
  pessoaId?: string;
  nome: string;
  tipo: TipoCelebracao;
  data: Date;
  diasRestantes: number;
  anos?: number;
  cargo?: string;
}

/** Sem configuração salva, mantém o comportamento histórico: tudo ligado, 30 dias. */
export const CONFIG_CELEBRACAO_PADRAO: ConfigCelebracao = {
  aniversario_ativo: true,
  tempo_casa_ativo: true,
  dia_profissao_ativo: true,
  dias_antecedencia_acao: 30,
};

/**
 * Próxima ocorrência (hoje inclusive) de uma data que se repete todo ano.
 * 29/02 cai em 28/02 nos anos não bissextos.
 */
export function proximaOcorrencia(mes: number, dia: number, hoje: Date): Date {
  const base = startOfDay(hoje);
  const noAno = (ano: number) => {
    const d = new Date(ano, mes - 1, dia);
    // 29/02 em ano não bissexto "estoura" para 01/03: volta para 28/02
    return d.getMonth() !== mes - 1 ? new Date(ano, mes - 1, dia - 1) : d;
  };
  const candidata = noAno(base.getFullYear());
  return candidata < base ? noAno(base.getFullYear() + 1) : candidata;
}

export function chaveCelebracao(pessoa: string, tipo: string, ano: number): string {
  return `${tipo}|${pessoa.trim().toLowerCase()}|${ano}`;
}

export function calcularCelebracoes(
  pessoas: PessoaCelebravel[],
  config?: Partial<ConfigCelebracao> | null,
  agora: Date = new Date(),
): Celebracao[] {
  const cfg = { ...CONFIG_CELEBRACAO_PADRAO, ...(config ?? {}) };
  const hoje = startOfDay(agora);
  const janela = Math.max(0, cfg.dias_antecedencia_acao ?? CONFIG_CELEBRACAO_PADRAO.dias_antecedencia_acao);
  const itens: Celebracao[] = [];
  const profissoesVistas = new Set<string>();

  for (const p of pessoas) {
    if (cfg.aniversario_ativo && p.data_nascimento) {
      const nasc = toDateLocal(p.data_nascimento);
      if (nasc && !isNaN(nasc.getTime())) {
        const data = proximaOcorrencia(nasc.getMonth() + 1, nasc.getDate(), hoje);
        const dias = differenceInCalendarDays(data, hoje);
        if (dias <= janela) {
          itens.push({
            chave: chaveCelebracao(p.nome_completo, "aniversario", data.getFullYear()),
            pessoaId: p.id,
            nome: p.nome_completo,
            tipo: "aniversario",
            data,
            diasRestantes: dias,
            cargo: p.cargo || undefined,
          });
        }
      }
    }

    if (cfg.tempo_casa_ativo && p.data_admissao) {
      const adm = toDateLocal(p.data_admissao);
      if (adm && !isNaN(adm.getTime())) {
        const data = proximaOcorrencia(adm.getMonth() + 1, adm.getDate(), hoje);
        const dias = differenceInCalendarDays(data, hoje);
        // anos da DATA CELEBRADA (não do ano corrente): em dezembro, quem faz
        // 5 anos em janeiro aparece com "5"
        const anos = data.getFullYear() - adm.getFullYear();
        if (dias <= janela && anos >= 1) {
          itens.push({
            chave: chaveCelebracao(p.nome_completo, "tempo_casa", data.getFullYear()),
            pessoaId: p.id,
            nome: p.nome_completo,
            tipo: "tempo_casa",
            data,
            diasRestantes: dias,
            anos,
            cargo: p.cargo || undefined,
          });
        }
      }
    }

    if (cfg.dia_profissao_ativo && p.cargo) {
      const prof = buscarDiaProfissao(p.cargo);
      if (prof) {
        const data = proximaOcorrencia(prof.mes, prof.dia, hoje);
        const dias = differenceInCalendarDays(data, hoje);
        const chave = chaveCelebracao(prof.nome, "dia_profissao", data.getFullYear());
        if (dias <= janela && !profissoesVistas.has(chave)) {
          profissoesVistas.add(chave);
          itens.push({
            chave,
            nome: prof.nome,
            tipo: "dia_profissao",
            data,
            diasRestantes: dias,
            cargo: p.cargo,
          });
        }
      }
    }
  }

  return itens.sort((a, b) => a.diasRestantes - b.diasRestantes);
}

/** Chave da ação já existente (qualquer status exceto cancelada) para uma celebração. */
export function chaveDaAcao(a: Pick<CulturaAcao, "tipo" | "colaborador_nome" | "data_referencia" | "titulo">): string | null {
  const data = toDateLocal(a.data_referencia);
  if (!data) return null;
  // dia da profissão não tem pessoa: a ação leva o nome da data ("Dia do Motorista") no título
  const quem = a.tipo === "dia_profissao" ? a.titulo : a.colaborador_nome;
  if (!quem) return null;
  return chaveCelebracao(quem, a.tipo, data.getFullYear());
}

/** Mapa chave → ação, para saber se uma celebração detectada já foi tratada (RN-004). */
export function indexarAcoes(acoes: CulturaAcao[]): Map<string, CulturaAcao> {
  const mapa = new Map<string, CulturaAcao>();
  for (const a of acoes) {
    if (a.status === "cancelada") continue;
    const k = chaveDaAcao(a);
    if (k && !mapa.has(k)) mapa.set(k, a);
  }
  return mapa;
}

export function payloadAcaoDaCelebracao(c: Celebracao): Partial<CulturaAcao> {
  const titulo =
    c.tipo === "aniversario"
      ? `Aniversário de ${c.nome}`
      : c.tipo === "tempo_casa"
      ? `${c.anos} ano${(c.anos ?? 0) > 1 ? "s" : ""} de empresa - ${c.nome}`
      : c.nome;
  return {
    tipo: c.tipo,
    titulo,
    colaborador_nome: c.tipo === "dia_profissao" ? null : c.nome,
    data_referencia: format(c.data, "yyyy-MM-dd"),
    status: "pendente",
  };
}

/**
 * Preferência "reservado": a pessoa não quer reconhecimento público. Casa por
 * id (colaborador_id guarda o id da admissão, ou o nome quando não havia id).
 */
export function pessoaReservada(
  preferencias: Pick<CulturaPreferencia, "colaborador_id" | "colaborador_nome" | "tipo_reconhecimento">[],
  pessoaId: string | undefined,
  nome: string,
): boolean {
  const alvo = nome.trim().toLowerCase();
  return preferencias.some(
    (pf) =>
      pf.tipo_reconhecimento === "reservado" &&
      ((pessoaId && pf.colaborador_id === pessoaId) || pf.colaborador_nome.trim().toLowerCase() === alvo),
  );
}
