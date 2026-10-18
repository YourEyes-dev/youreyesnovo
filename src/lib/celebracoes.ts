import { addDays, addMonths, differenceInCalendarDays, format, startOfDay } from "date-fns";
import { toDateLocal } from "@/lib/dataLocal";
import { buscarDiaProfissao } from "@/lib/diasProfissao";
import type { CulturaAcao, CulturaConfig, CulturaData, CulturaPreferencia, CulturaRitual, TomMensagem } from "@/types/cultura";

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
/** Data de uma comemoração anual num ano específico; 29/02 cai em 28/02 nos anos não bissextos. */
export function dataNoAno(mes: number, dia: number, ano: number): Date {
  const d = new Date(ano, mes - 1, dia);
  // 29/02 em ano não bissexto "estoura" para 01/03: volta para 28/02
  return d.getMonth() !== mes - 1 ? new Date(ano, mes - 1, dia - 1) : d;
}

/** Próxima ocorrência (hoje inclusive) de uma data que se repete todo ano. */
export function proximaOcorrencia(mes: number, dia: number, hoje: Date): Date {
  const base = startOfDay(hoje);
  const candidata = dataNoAno(mes, dia, base.getFullYear());
  return candidata < base ? dataNoAno(mes, dia, base.getFullYear() + 1) : candidata;
}

export function chaveCelebracao(pessoa: string, tipo: string, ano: number): string {
  return `${tipo}|${pessoa.trim().toLowerCase()}|${ano}`;
}

/**
 * Celebrações com data entre `de` e `ate` (inclusive), respeitando só os tipos
 * ligados na Configuração — a janela de dias fica por conta de quem chama.
 * `diasRestantes` é relativo a `referencia` (negativo = já passou).
 */
export function celebracoesNoIntervalo(
  pessoas: PessoaCelebravel[],
  config: Partial<ConfigCelebracao> | null | undefined,
  de: Date,
  ate: Date,
  referencia: Date = new Date(),
): Celebracao[] {
  const cfg = { ...CONFIG_CELEBRACAO_PADRAO, ...(config ?? {}) };
  const ini = startOfDay(de);
  const fim = startOfDay(ate);
  const ref = startOfDay(referencia);
  const itens: Celebracao[] = [];
  const profissoesVistas = new Set<string>();

  for (let ano = ini.getFullYear(); ano <= fim.getFullYear(); ano++) {
    const dentro = (d: Date) => d >= ini && d <= fim;

    for (const p of pessoas) {
      if (cfg.aniversario_ativo && p.data_nascimento) {
        const nasc = toDateLocal(p.data_nascimento);
        if (nasc && !isNaN(nasc.getTime())) {
          const data = dataNoAno(nasc.getMonth() + 1, nasc.getDate(), ano);
          if (dentro(data)) {
            itens.push({
              chave: chaveCelebracao(p.nome_completo, "aniversario", ano),
              pessoaId: p.id,
              nome: p.nome_completo,
              tipo: "aniversario",
              data,
              diasRestantes: differenceInCalendarDays(data, ref),
              cargo: p.cargo || undefined,
            });
          }
        }
      }

      if (cfg.tempo_casa_ativo && p.data_admissao) {
        const adm = toDateLocal(p.data_admissao);
        if (adm && !isNaN(adm.getTime())) {
          const data = dataNoAno(adm.getMonth() + 1, adm.getDate(), ano);
          // anos da DATA CELEBRADA (não do ano corrente): em dezembro, quem faz
          // 5 anos em janeiro aparece com "5"
          const anos = ano - adm.getFullYear();
          if (dentro(data) && anos >= 1) {
            itens.push({
              chave: chaveCelebracao(p.nome_completo, "tempo_casa", ano),
              pessoaId: p.id,
              nome: p.nome_completo,
              tipo: "tempo_casa",
              data,
              diasRestantes: differenceInCalendarDays(data, ref),
              anos,
              cargo: p.cargo || undefined,
            });
          }
        }
      }

      if (cfg.dia_profissao_ativo && p.cargo) {
        const prof = buscarDiaProfissao(p.cargo);
        if (prof) {
          const data = dataNoAno(prof.mes, prof.dia, ano);
          const chave = chaveCelebracao(prof.nome, "dia_profissao", ano);
          if (dentro(data) && !profissoesVistas.has(chave)) {
            profissoesVistas.add(chave);
            itens.push({
              chave,
              nome: prof.nome,
              tipo: "dia_profissao",
              data,
              diasRestantes: differenceInCalendarDays(data, ref),
              cargo: p.cargo,
            });
          }
        }
      }
    }
  }

  return itens.sort((a, b) => a.data.getTime() - b.data.getTime());
}

/** Próximas celebrações: de hoje até hoje + janela de dias da Configuração. */
export function calcularCelebracoes(
  pessoas: PessoaCelebravel[],
  config?: Partial<ConfigCelebracao> | null,
  agora: Date = new Date(),
): Celebracao[] {
  const cfg = { ...CONFIG_CELEBRACAO_PADRAO, ...(config ?? {}) };
  const hoje = startOfDay(agora);
  const janela = Math.max(0, cfg.dias_antecedencia_acao ?? CONFIG_CELEBRACAO_PADRAO.dias_antecedencia_acao);
  return celebracoesNoIntervalo(pessoas, cfg, hoje, addDays(hoje, janela), hoje);
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
    origem: "manual",
    // mesma chave da rotina diária no banco: o índice único impede a segunda ação
    chave_unica: c.chave,
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

// ---------------------------------------------------------------- Rituais

const PERIODO_RITUAL: Record<string, (d: Date) => Date> = {
  semanal: (d) => addDays(d, 7),
  quinzenal: (d) => addDays(d, 14),
  mensal: (d) => addMonths(d, 1),
  trimestral: (d) => addMonths(d, 3),
};

/** Data da próxima realização: a agendada, ou a última somada à frequência. */
export function proximaExecucaoRitual(r: Pick<CulturaRitual, "frequencia" | "ultima_execucao" | "proxima_execucao">): Date | null {
  const prox = toDateLocal(r.proxima_execucao);
  if (prox) return prox;
  const ult = toDateLocal(r.ultima_execucao);
  const soma = PERIODO_RITUAL[r.frequencia];
  return ult && soma ? soma(ult) : null;
}

/** Datas gravadas ao registrar que o ritual foi realizado hoje. */
export function datasAoRegistrarRitual(frequencia: string, hoje: Date = new Date()) {
  const base = startOfDay(hoje);
  const soma = PERIODO_RITUAL[frequencia];
  return {
    ultima_execucao: format(base, "yyyy-MM-dd"),
    proxima_execucao: soma ? format(soma(base), "yyyy-MM-dd") : null,
  };
}

// ---------------------------------------------------------------- Cobertura

export interface CoberturaCelebracao {
  total: number;
  cobertas: number;
  /** 0–100; 0 quando não há colaboradores (sem divisão por zero) */
  percentual: number;
  semCelebracao: PessoaCelebravel[];
}

/**
 * Cobertura: % de colaboradores com ao menos uma celebração CONCLUÍDA nos
 * últimos 12 meses. Mede se a empresa cuidou da pessoa, não se ela "engajou".
 * Só enxerga o que foi registrado no sistema.
 */
export function calcularCobertura(
  pessoas: PessoaCelebravel[],
  acoes: Pick<CulturaAcao, "status" | "colaborador_nome" | "data_execucao" | "data_referencia">[],
  agora: Date = new Date(),
): CoberturaCelebracao {
  const limite = addMonths(startOfDay(agora), -12);
  const celebrados = new Set<string>();
  for (const a of acoes) {
    if (a.status !== "concluida" || !a.colaborador_nome) continue;
    const quando = toDateLocal(a.data_execucao || a.data_referencia);
    if (quando && quando >= limite) celebrados.add(a.colaborador_nome.trim().toLowerCase());
  }
  const semCelebracao = pessoas.filter((p) => !celebrados.has(p.nome_completo.trim().toLowerCase()));
  const total = pessoas.length;
  const cobertas = total - semCelebracao.length;
  return { total, cobertas, percentual: total > 0 ? Math.round((cobertas / total) * 100) : 0, semCelebracao };
}

// ---------------------------------------------------------------- Calendário

export type GrupoEvento = "pessoas" | "datas" | "rituais";

export interface EventoCalendario {
  id: string;
  grupo: GrupoEvento;
  /** define a cor: aniversario | tempo_casa | dia_profissao | acao | data | ritual */
  tipo: string;
  titulo: string;
  data: Date;
  detalhe?: string;
  acao?: CulturaAcao;
  celebracao?: Celebracao;
  ritual?: CulturaRitual;
}

export const GRUPO_LABELS: Record<"todos" | GrupoEvento, string> = {
  todos: "Tudo",
  pessoas: "Pessoas",
  datas: "Datas",
  rituais: "Rituais",
};

/**
 * Tudo que cai entre `de` e `ate`: celebrações detectadas, ações, datas
 * configuradas e rituais. Mesma fonte das Próximas Celebrações (CA-006).
 */
export function montarEventosCalendario(args: {
  pessoas: PessoaCelebravel[];
  config?: Partial<ConfigCelebracao> | null;
  acoes: CulturaAcao[];
  rituais: CulturaRitual[];
  datas: Pick<CulturaData, "id" | "titulo" | "ativo" | "mes" | "dia" | "data_especifica">[];
  de: Date;
  ate: Date;
}): EventoCalendario[] {
  const { pessoas, config, acoes, rituais, datas } = args;
  const ini = startOfDay(args.de);
  const fim = startOfDay(args.ate);
  const eventos: EventoCalendario[] = [];

  const detectadas = celebracoesNoIntervalo(pessoas, config, ini, fim);
  const tratadas = indexarAcoes(acoes);
  const chavesDetectadas = new Set(detectadas.map((c) => c.chave));

  for (const c of detectadas) {
    eventos.push({
      id: c.chave,
      grupo: c.tipo === "dia_profissao" ? "datas" : "pessoas",
      tipo: c.tipo,
      titulo: c.nome,
      data: c.data,
      detalhe:
        c.tipo === "tempo_casa" ? `${c.anos} ano${(c.anos ?? 0) > 1 ? "s" : ""} de empresa` : c.tipo === "aniversario" ? "Aniversário" : "Dia da Profissão",
      acao: tratadas.get(c.chave),
      celebracao: c,
    });
  }

  // Ações sem celebração detectada correspondente (manuais, datas configuradas, rituais)
  for (const a of acoes) {
    if (a.status === "cancelada") continue;
    const k = chaveDaAcao(a);
    if (k && chavesDetectadas.has(k)) continue;
    const data = toDateLocal(a.data_referencia);
    if (!data || data < ini || data > fim) continue;
    eventos.push({
      id: `acao-${a.id}`,
      grupo: a.tipo === "ritual" ? "rituais" : a.colaborador_nome ? "pessoas" : "datas",
      tipo: "acao",
      titulo: a.colaborador_nome || a.titulo,
      data,
      detalhe: a.titulo,
      acao: a,
    });
  }

  for (const d of datas) {
    if (!d.ativo) continue;
    const fixa = toDateLocal(d.data_especifica);
    const candidatas = fixa
      ? [fixa]
      : d.mes && d.dia
      ? Array.from({ length: fim.getFullYear() - ini.getFullYear() + 1 }, (_, i) => dataNoAno(d.mes!, d.dia!, ini.getFullYear() + i))
      : [];
    for (const data of candidatas) {
      if (data >= ini && data <= fim) {
        eventos.push({ id: `data-${d.id}-${data.getFullYear()}`, grupo: "datas", tipo: "data", titulo: d.titulo, data, detalhe: "Data configurada" });
      }
    }
  }

  for (const r of rituais) {
    if (!r.ativo) continue;
    const data = proximaExecucaoRitual(r);
    if (data && data >= ini && data <= fim) {
      eventos.push({ id: `ritual-${r.id}`, grupo: "rituais", tipo: "ritual", titulo: r.nome, data, detalhe: "Ritual", ritual: r });
    }
  }

  return eventos.sort((a, b) => a.data.getTime() - b.data.getTime());
}

// ---------------------------------------------------------------- Mensagem sugerida

const FRASES: Record<TomMensagem, { aniversario: string[]; tempo_casa: string[]; dia_profissao: string[] }> = {
  leve: {
    aniversario: [
      "🎂 Hoje é dia de festa! Parabéns, {nome}! Que seu novo ciclo venha com muita saúde, alegria e conquistas. A equipe toda manda um abraço!",
      "🎉 Feliz aniversário, {nome}! Obrigado por fazer parte do nosso time. Que o seu dia seja tão especial quanto você é para nós!",
    ],
    tempo_casa: [
      "🏆 {anos} de casa! Parabéns, {nome}! Obrigado por cada dia de dedicação e por construir esta história com a gente.",
      "🎊 {nome} completa {anos} de empresa hoje! Sua trajetória inspira o time. Parabéns e muito obrigado!",
    ],
    dia_profissao: [
      "🌟 Hoje é o {nome}! Nosso reconhecimento a todos os profissionais que fazem a diferença no dia a dia da empresa. Parabéns!",
    ],
  },
  formal: {
    aniversario: [
      "Hoje celebramos o aniversário de {nome}. Em nome de toda a empresa, desejamos saúde, realizações e um excelente novo ciclo.",
    ],
    tempo_casa: [
      "{nome} completa hoje {anos} de empresa. Registramos nosso agradecimento pela dedicação e pelo compromisso ao longo dessa trajetória.",
    ],
    dia_profissao: [
      "Hoje é o {nome}. Registramos nosso reconhecimento aos profissionais que contribuem diariamente para os resultados da empresa.",
    ],
  },
};

/**
 * Texto-base para o gestor/RH editar antes de publicar. É sugestão: nunca
 * traz idade nem ano de nascimento (RN-007) e a pessoa que decide publicar é humana.
 * `variante` escolhe entre as frases do tom, para não repetir sempre a mesma.
 */
export function sugerirMensagem(
  c: Pick<Celebracao, "tipo" | "nome" | "anos">,
  tom: TomMensagem = "leve",
  variante = 0,
): string {
  const opcoes = FRASES[tom][c.tipo];
  const frase = opcoes[variante % opcoes.length];
  const anos = c.anos ? `${c.anos} ano${c.anos > 1 ? "s" : ""}` : "";
  return frase.replace("{nome}", c.nome).replace("{anos}", anos);
}

export function quantidadeDeVariantes(tipo: TipoCelebracao, tom: TomMensagem): number {
  return FRASES[tom][tipo].length;
}

// ---------------------------------------------------------------- Alertas

export interface AlertaCultura {
  id: "atrasadas" | "cobertura";
  titulo: string;
  descricao: string;
}

/** Alertas que merecem virar ação no Plano de Ação (fecha o ciclo: medir → agir). */
export function montarAlertas(args: {
  acoes: Pick<CulturaAcao, "status" | "data_referencia">[];
  cobertura: Pick<CoberturaCelebracao, "total" | "percentual">;
  metaCobertura: number;
  hoje?: Date;
}): AlertaCultura[] {
  const hoje = startOfDay(args.hoje ?? new Date());
  const alertas: AlertaCultura[] = [];
  const atrasadas = args.acoes.filter((a) => {
    if (a.status !== "pendente" && a.status !== "em_andamento") return false;
    const ref = toDateLocal(a.data_referencia);
    return !!ref && ref < hoje;
  }).length;
  if (atrasadas > 0) {
    alertas.push({
      id: "atrasadas",
      titulo: `${atrasadas} celebraç${atrasadas > 1 ? "ões" : "ão"} atrasada${atrasadas > 1 ? "s" : ""}`,
      descricao: `Há ${atrasadas} ação${atrasadas > 1 ? "ões" : ""} cultural${atrasadas > 1 ? "is" : ""} pendente${atrasadas > 1 ? "s" : ""} com a data já vencida. Pessoas deixaram de ser lembradas no dia certo.`,
    });
  }
  if (args.cobertura.total > 0 && args.cobertura.percentual < args.metaCobertura) {
    alertas.push({
      id: "cobertura",
      titulo: `Cobertura de celebração em ${args.cobertura.percentual}% (meta ${args.metaCobertura}%)`,
      descricao: `Só ${args.cobertura.percentual}% dos colaboradores foram celebrados nos últimos 12 meses; a meta da empresa é ${args.metaCobertura}%.`,
    });
  }
  return alertas;
}

// ---------------------------------------------------------------- Time do gestor

export function somenteDigitos(valor: string | null | undefined): string {
  return (valor ?? "").replace(/\D/g, "");
}

/** CPF como costuma estar gravado (com e sem máscara), para buscar sem depender do formato. */
export function variantesDeCpf(cpf: string | null | undefined): string[] {
  const d = somenteDigitos(cpf);
  if (d.length !== 11) return [];
  return [d, `${d.slice(0, 3)}.${d.slice(3, 6)}.${d.slice(6, 9)}-${d.slice(9)}`];
}

/** Escapa % e _ para usar o nome num ILIKE sem curinga (comparação exata sem diferenciar maiúsculas). */
export function escaparParaIlike(nome: string): string {
  return nome.trim().replace(/[\\%_]/g, (c) => `\\${c}`);
}

/** Celebrações de pessoas do time do gestor (o dia da profissão não é de ninguém em particular). */
export function celebracoesDoTime(celebracoes: Celebracao[], idsDoTime: ReadonlySet<string>): Celebracao[] {
  return celebracoes.filter((c) => c.tipo !== "dia_profissao" && !!c.pessoaId && idsDoTime.has(c.pessoaId));
}
