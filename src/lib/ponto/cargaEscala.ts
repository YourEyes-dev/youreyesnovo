/**
 * Carga da escala fixa — a conta que a tela de escalas mostra e grava.
 *
 * Mora fora do componente para poder ser testada: é ela que decide o TOTAL de
 * cada dia, a CARGA CALCULADA da semana e o `jornada_diaria_minutos` gravado
 * na escala — e esse último é o que o motor de apuração usa como referência
 * quando a escala não tem configuração por dia.
 *
 * A regra é uma só: o intervalo intrajornada NÃO integra a jornada (CLT art.
 * 71, §2º). Ele pode chegar por dois caminhos, e os dois valem:
 *   · BATIDO — a janela de almoço declarada no próprio dia (`tem_almoco`);
 *   · DECLARADO — pré-assinalação (Súmula 338, III do TST; Portaria MTP
 *     671/2021), quando o intervalo existe mas não é registrado.
 *
 * Enxergar só o primeiro foi o que fez uma escala de 44h/semana ser anunciada
 * como 49h, com alarme vermelho de estouro da CLT, enquanto a folha calculava
 * as 44h corretas.
 */

export type DiaConfigCarga = {
  trabalha: boolean;
  tem_almoco: boolean;
  entrada: string;
  inicio_almoco: string;
  fim_almoco: string;
  saida: string;
};

export const DIAS_KEYS_CARGA = [
  "segunda", "terca", "quarta", "quinta", "sexta", "sabado", "domingo",
] as const;

const toMin = (s: string) => {
  const [h, m] = String(s || "0:0").split(":").map(Number);
  return (Number.isFinite(h) ? h : 0) * 60 + (Number.isFinite(m) ? m : 0);
};

/** Minutos de JORNADA do dia: a janela menos o intervalo que couber. */
export function minutosDia(c: DiaConfigCarga | undefined, intervaloDeclarado = 0): number {
  if (!c?.trabalha) return 0;
  if (c.tem_almoco) {
    return Math.max(
      0,
      (toMin(c.inicio_almoco) - toMin(c.entrada)) + (toMin(c.saida) - toMin(c.fim_almoco)),
    );
  }
  return Math.max(0, toMin(c.saida) - toMin(c.entrada) - Math.max(0, intervaloDeclarado));
}

/** Minutos de INTERVALO do dia — batido ou declarado. */
export function intervaloDia(c: DiaConfigCarga | undefined, intervaloDeclarado = 0): number {
  if (!c?.trabalha) return 0;
  if (c.tem_almoco) return Math.max(0, toMin(c.fim_almoco) - toMin(c.inicio_almoco));
  return Math.max(0, intervaloDeclarado);
}

/** Carga semanal, jornada média diária e quantidade de dias trabalhados. */
export function calcularJornadasFixa(
  dc: Record<string, DiaConfigCarga>,
  intervaloDeclarado = 0,
): { semanal: number; diaria: number; diasTrab: number } {
  let semanal = 0;
  let diasTrab = 0;
  DIAS_KEYS_CARGA.forEach((d) => {
    const min = minutosDia(dc?.[d], intervaloDeclarado);
    if (min > 0) {
      semanal += min;
      diasTrab++;
    }
  });
  return { semanal, diaria: diasTrab > 0 ? Math.round(semanal / diasTrab) : 0, diasTrab };
}
