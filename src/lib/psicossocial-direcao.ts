/**
 * psicossocial-direcao.ts — Fonte ÚNICA da direção do score psicossocial.
 * ─────────────────────────────────────────────────────────────────────────────
 * Régua única de EXIBIÇÃO do módulo: IPS "saúde" (0-100, ALTO = MELHOR).
 *
 * Problema que esta função resolve: instrumentos diferentes gravam o radar/score
 * BRUTO em direções opostas —
 *   - SIPRO e entrevistas  → orientado a RISCO (alto = pior) = escala IRP-S;
 *   - COPSOQ / HSE / PROART → orientado a SAÚDE (alto = melhor) = escala IPS.
 * A conversão `isSipro ? 100 - x : x` estava duplicada em ~15 lugares, cada um
 * decidindo a direção por conta própria. Aqui ela vira uma coisa só.
 *
 * IMPORTANTE: o índice por-resposta `indicadores.IPS` e seu agregado
 * `stats.ips` JÁ são saúde (alto=melhor) para todos os instrumentos — NÃO
 * passar esses valores por aqui. Use estas funções para o RADAR bruto
 * (`radar_data`/`stats.radar`) e para a coluna persistida `ips_score`, que
 * seguem a direção nativa do instrumento.
 */
import { isEntrevistaInstrumento } from "@/types/psicossocial";

/** Instrumentos cujo radar/score BRUTO é orientado a risco (alto = pior). */
export function instrumentoDeRisco(
  instrumento?: string | null,
  tipoInstrumento?: string | null,
): boolean {
  return instrumento === "sipro" || isEntrevistaInstrumento(tipoInstrumento);
}

/**
 * Converte um valor BRUTO (0-100) para a régua única de saúde (alto = melhor).
 * Para instrumentos de risco inverte (100 - raw); para os demais mantém.
 */
export function normalizarParaIPS(
  raw: number,
  instrumento?: string | null,
  tipoInstrumento?: string | null,
): number {
  return instrumentoDeRisco(instrumento, tipoInstrumento) ? 100 - raw : raw;
}

/**
 * Converte um radar BRUTO para a régua de saúde (alto = melhor), preservando
 * os demais campos de cada ponto. Use ao exibir `radar_data`/`stats.radar`.
 */
export function radarParaIPS<T extends { value: number }>(
  radar: T[] | null | undefined,
  instrumento?: string | null,
  tipoInstrumento?: string | null,
): T[] {
  if (!radar) return [];
  if (!instrumentoDeRisco(instrumento, tipoInstrumento)) return radar;
  return radar.map((d) => ({ ...d, value: 100 - d.value }));
}
