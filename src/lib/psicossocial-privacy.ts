/**
 * psicossocial-privacy.ts
 * ─────────────────────────────────────────────────────────────────────────────
 * Motor de proteção de privacidade para resultados psicossociais.
 *
 * Implementa ISO 45003 §6.1.2 + COPSOQ III guidelines:
 *   - GAP A: verificação de mínimo de respondentes por grupo (setor+função)
 *   - GAP B: agrupamento automático em nível superior quando grupo < mínimo
 *   - GAP C: alerta de privacidade por grupo específico
 *
 * Regra de ouro: "Se pode identificar alguém, não pode mostrar."
 */

import type { SituacaoTrabalhoCampanha } from "@/types/psicossocial";

// ──────────────────────────────────────────────────────────────────────────────
// Constantes
// ──────────────────────────────────────────────────────────────────────────────

/** Mínimo de respondentes para exibição segura por grupo (ISO 45003 / COPSOQ) */
export const MINIMO_RESPONDENTES_GRUPO = 5;

/** Mínimo global da campanha para liberar qualquer análise */
export const MINIMO_ANONIMATO_CAMPANHA = 5;

// ──────────────────────────────────────────────────────────────────────────────
// Tipos
// ──────────────────────────────────────────────────────────────────────────────

export type NivelAgrupamento = 'funcao' | 'setor' | 'empresa';

export interface GrupoAnalise {
  /** Identificador único do grupo (setor+funcao ou setor ou 'empresa') */
  chave: string;
  /** Rótulo exibível */
  label: string;
  /** Nível de agrupamento atual */
  nivel: NivelAgrupamento;
  /** Número de respondentes neste grupo */
  respondentes: number;
  /** Se o grupo tem respondentes suficientes para exibição segura */
  privacidadeGarantida: boolean;
  /** Razão para bloqueio (se não garantida) */
  motivoBloqueio?: string;
  /** Se os dados foram agrupados em nível superior (fallback ativo) */
  agrupamentoAplicado: boolean;
  /** Nível original antes do fallback */
  nivelOriginal?: NivelAgrupamento;
}

export interface ResultadoPrivacidade {
  /** Grupos que podem ser exibidos com segurança */
  gruposDisponiveis: GrupoAnalise[];
  /** Grupos bloqueados por insuficiência */
  gruposBloqueados: GrupoAnalise[];
  /** Se algum agrupamento automático foi aplicado */
  agrupamentoAutomaticoAtivado: boolean;
  /** Nível efetivo da análise (mais alto = mais agregado) */
  nivelEfetivo: NivelAgrupamento;
  /** Resumo para exibição ao usuário */
  resumoPrivacidade: string;
  /**
   * true quando a contagem por grupo veio de uma ESTIMATIVA (distribuição
   * uniforme), não de contagem real. Nesse caso a decisão de privacidade por
   * grupo é uma referência, não uma garantia — a UI deve avisar. (Fase 0.4)
   */
  baseadoEmEstimativa: boolean;
}

/** Contagem de respondentes por par setor+função */
export interface ContagemPorGrupo {
  /** chave = `${setorId}::${funcaoId}` ou `setor::${setorId}` ou `empresa` */
  [chave: string]: number;
}

// ──────────────────────────────────────────────────────────────────────────────
// Funções principais
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Calcula a contagem de respondentes por grupo a partir das respostas brutas.
 * Como as respostas são anônimas (sem vinculação individual), a contagem é
 * estimada dividindo o total de respondentes proporcionalmente entre situações
 * de trabalho. Quando a campanha tem controle nominal, usa a contagem real.
 *
 * @param totalRespondentes Total de respostas concluídas na campanha
 * @param situacoes Situações de trabalho vinculadas à campanha
 * @param contagemReal Contagem real por grupo (se disponível)
 */
export function estimarContagemPorGrupo(
  totalRespondentes: number,
  situacoes: SituacaoTrabalhoCampanha[],
  contagemReal?: ContagemPorGrupo
): ContagemPorGrupo {
  if (contagemReal && Object.keys(contagemReal).length > 0) {
    return contagemReal;
  }

  if (situacoes.length === 0) {
    return { empresa: totalRespondentes };
  }

  // Distribuição uniforme estimada (sem dados reais de segmentação)
  const porGrupo: ContagemPorGrupo = {};
  const porSituacao = Math.floor(totalRespondentes / situacoes.length);
  const resto = totalRespondentes % situacoes.length;

  situacoes.forEach((sit, idx) => {
    const chave = `${sit.setorId}::${sit.funcaoId}`;
    porGrupo[chave] = porSituacao + (idx === 0 ? resto : 0);
  });

  return porGrupo;
}

/**
 * Aplica as regras de privacidade ISO 45003 sobre um conjunto de situações de trabalho.
 *
 * Hierarquia de fallback:
 *   funcao (setor+função) → setor → empresa
 *
 * @param situacoes Situações de trabalho da campanha
 * @param contagemPorGrupo Contagem real ou estimada de respondentes por grupo
 * @param totalCampanha Total de respondentes na campanha
 */
export function aplicarRegrasPrivacidade(
  situacoes: SituacaoTrabalhoCampanha[],
  contagemPorGrupo: ContagemPorGrupo,
  totalCampanha: number,
  opts: { estimado?: boolean } = {},
): ResultadoPrivacidade {
  const grupos: GrupoAnalise[] = [];
  const MIN = MINIMO_RESPONDENTES_GRUPO;
  const estimado = !!opts.estimado;
  const avisoEstimativa =
    " ⚠️ Distribuição por grupo ESTIMADA (as respostas são anônimas e não têm contagem real por Setor+Função). Use como referência — não é garantia de anonimato por grupo. A contagem real por grupo (respostas × convites) é a correção definitiva.";

  if (situacoes.length === 0) {
    // Campanha sem segmentação — usa nível empresa
    const ok = totalCampanha >= MINIMO_ANONIMATO_CAMPANHA;
    const grupo: GrupoAnalise = {
      chave: 'empresa',
      label: 'Empresa (todos os colaboradores)',
      nivel: 'empresa',
      respondentes: totalCampanha,
      privacidadeGarantida: ok,
      motivoBloqueio: ok ? undefined : `Mínimo de ${MIN} respondentes necessário. Atual: ${totalCampanha}.`,
      agrupamentoAplicado: false,
    };
    return {
      gruposDisponiveis: ok ? [grupo] : [],
      gruposBloqueados: ok ? [] : [grupo],
      agrupamentoAutomaticoAtivado: false,
      nivelEfetivo: 'empresa',
      resumoPrivacidade: ok
        ? `Análise liberada — ${totalCampanha} respondentes (nível empresa).`
        : `Dados insuficientes: ${totalCampanha} de ${MIN} respondentes mínimos para garantir anonimato.`,
      // Sem segmentação, o nível empresa usa o total real de respondentes.
      baseadoEmEstimativa: false,
    };
  }

  // ── Nível 1: Setor + Função ──────────────────────────────────────────────
  for (const sit of situacoes) {
    const chaveFunc = `${sit.setorId}::${sit.funcaoId}`;
    const chaveSeto = `setor::${sit.setorId}`;

    const countFunc = contagemPorGrupo[chaveFunc] ?? 0;
    const countSeto = contagemPorGrupo[chaveSeto]
      // Somar todos da mesma função no setor
      ?? Object.entries(contagemPorGrupo)
          .filter(([k]) => k.startsWith(`${sit.setorId}::`))
          .reduce((acc, [, v]) => acc + v, 0);

    if (countFunc >= MIN) {
      // ✅ Nível funcao — seguro
      grupos.push({
        chave: chaveFunc,
        label: `${sit.funcaoNome} — ${sit.setorNome}`,
        nivel: 'funcao',
        respondentes: countFunc,
        privacidadeGarantida: true,
        agrupamentoAplicado: false,
      });
    } else if (countSeto >= MIN) {
      // ⬆️ Fallback para nível setor
      grupos.push({
        chave: chaveSeto,
        label: `${sit.setorNome} (setor completo — agrupamento automático)`,
        nivel: 'setor',
        respondentes: countSeto,
        privacidadeGarantida: true,
        agrupamentoAplicado: true,
        nivelOriginal: 'funcao',
        motivoBloqueio: undefined,
      });
    } else if (totalCampanha >= MIN) {
      // ⬆️⬆️ Fallback para nível empresa
      grupos.push({
        chave: 'empresa',
        label: 'Empresa (agrupamento automático — grupo pequeno)',
        nivel: 'empresa',
        respondentes: totalCampanha,
        privacidadeGarantida: true,
        agrupamentoAplicado: true,
        nivelOriginal: 'funcao',
      });
    } else {
      // 🔴 Bloqueado — nem nível empresa é suficiente
      grupos.push({
        chave: chaveFunc,
        label: `${sit.funcaoNome} — ${sit.setorNome}`,
        nivel: 'funcao',
        respondentes: countFunc,
        privacidadeGarantida: false,
        motivoBloqueio: `Grupo com apenas ${countFunc} respondente(s). Mínimo: ${MIN}. Resultado bloqueado para proteger a confidencialidade.`,
        agrupamentoAplicado: false,
      });
    }
  }

  // Deduplicar grupos (ex: múltiplas funções do mesmo setor que foram elevadas)
  const vistos = new Set<string>();
  const deduplicados = grupos.filter(g => {
    if (vistos.has(g.chave)) return false;
    vistos.add(g.chave);
    return true;
  });

  const disponiveis = deduplicados.filter(g => g.privacidadeGarantida);
  const bloqueados = deduplicados.filter(g => !g.privacidadeGarantida);
  const agrupamentoAtivado = deduplicados.some(g => g.agrupamentoAplicado);

  // Nível efetivo = o mais alto (mais agregado) entre os disponíveis
  const nivelPrioridade: Record<NivelAgrupamento, number> = { funcao: 0, setor: 1, empresa: 2 };
  const nivelEfetivo = disponiveis.reduce<NivelAgrupamento>((acc, g) => {
    return nivelPrioridade[g.nivel] > nivelPrioridade[acc] ? g.nivel : acc;
  }, 'funcao');

  const resumo = buildResumoPrivacidade(disponiveis, bloqueados, agrupamentoAtivado, nivelEfetivo);

  return {
    gruposDisponiveis: disponiveis,
    gruposBloqueados: bloqueados,
    agrupamentoAutomaticoAtivado: agrupamentoAtivado,
    nivelEfetivo,
    resumoPrivacidade: estimado ? resumo + avisoEstimativa : resumo,
    baseadoEmEstimativa: estimado,
  };
}

function buildResumoPrivacidade(
  disponiveis: GrupoAnalise[],
  bloqueados: GrupoAnalise[],
  agrupamento: boolean,
  nivelEfetivo: NivelAgrupamento,
): string {
  const nivelLabel: Record<NivelAgrupamento, string> = {
    funcao: 'função',
    setor: 'setor',
    empresa: 'empresa',
  };

  if (disponiveis.length === 0) {
    return `Dados insuficientes em todos os grupos. Nenhum resultado pode ser exibido para preservar o anonimato dos colaboradores.`;
  }

  const parts: string[] = [];
  parts.push(`${disponiveis.length} grupo(s) disponível(is) para análise no nível ${nivelLabel[nivelEfetivo]}.`);

  if (agrupamento) {
    parts.push(`Agrupamento automático ativado — alguns grupos pequenos foram consolidados em nível superior para garantir confidencialidade (ISO 45003).`);
  }

  if (bloqueados.length > 0) {
    parts.push(`${bloqueados.length} grupo(s) bloqueado(s) por insuficiência de respondentes.`);
  }

  return parts.join(' ');
}

// ──────────────────────────────────────────────────────────────────────────────
// Helpers de UI
// ──────────────────────────────────────────────────────────────────────────────

/** Retorna label amigável para o nível de agrupamento */
export function getNivelAgrupamentoLabel(nivel: NivelAgrupamento): string {
  const map: Record<NivelAgrupamento, string> = {
    funcao: 'Função (setor+função)',
    setor: 'Setor',
    empresa: 'Empresa (todos)',
  };
  return map[nivel];
}

/** Verifica se uma campanha tem situações suficientes para análise segmentada */
export function campanhaTemSegmentacaoSegura(
  totalRespondentes: number,
  situacoes?: SituacaoTrabalhoCampanha[],
): boolean {
  if (!situacoes || situacoes.length === 0) {
    return totalRespondentes >= MINIMO_ANONIMATO_CAMPANHA;
  }
  // Com segmentação, o mínimo deve ser atingido pelo menos ao nível empresa
  return totalRespondentes >= MINIMO_RESPONDENTES_GRUPO;
}
