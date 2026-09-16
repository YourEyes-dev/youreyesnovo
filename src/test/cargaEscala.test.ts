import { describe, it, expect } from "vitest";
import {
  calcularJornadasFixa,
  intervaloDia,
  minutosDia,
  type DiaConfigCarga,
} from "@/lib/ponto/cargaEscala";

const dia = (
  entrada: string,
  saida: string,
  extra: Partial<DiaConfigCarga> = {},
): DiaConfigCarga => ({
  trabalha: true,
  tem_almoco: false,
  entrada,
  saida,
  inicio_almoco: "12:00",
  fim_almoco: "13:00",
  ...extra,
});

const folga: DiaConfigCarga = {
  trabalha: false, tem_almoco: false,
  entrada: "08:00", inicio_almoco: "12:00", fim_almoco: "13:00", saida: "17:00",
};

/**
 * A escala real que motivou a correção: segunda a quinta das 08:00 às 18:00,
 * sexta das 08:00 às 17:00, o almoço NÃO é batido (`tem_almoco: false`) e sim
 * declarado por pré-assinalação de 60 minutos.
 *
 * Jornada devida: 9h de segunda a quinta e 8h na sexta = 44h/semana, que é
 * exatamente o teto do art. 7º, XIII da Constituição.
 */
const escalaDoCliente = (): Record<string, DiaConfigCarga> => ({
  segunda: dia("08:00", "18:00"),
  terca:   dia("08:00", "18:00"),
  quarta:  dia("08:00", "18:00"),
  quinta:  dia("08:00", "18:00"),
  sexta:   dia("08:00", "17:00"),
  sabado:  folga,
  domingo: folga,
});

describe("carga da escala fixa — intervalo declarado", () => {
  /**
   * Regressão da tela de escalas: sem enxergar a declaração, a soma era das
   * janelas cruas — 10h/dia, 49h/semana — e a tela acendia alarme vermelho de
   * estouro da CLT numa escala que fecha certinho em 44h. Pior: gravava 588
   * em `jornada_diaria_minutos`, o número que o motor de apuração usa como
   * referência quando o dia não está coberto por `dias_config`.
   */
  it("a escala de 44h é anunciada como 44h, não como 49h", () => {
    const { semanal, diaria, diasTrab } = calcularJornadasFixa(escalaDoCliente(), 60);
    expect(semanal).toBe(44 * 60);
    expect(diaria).toBe(528);
    expect(diasTrab).toBe(5);
  });

  it("sem declaração, a janela crua continua valendo (é o que está contratado)", () => {
    const { semanal, diaria } = calcularJornadasFixa(escalaDoCliente());
    expect(semanal).toBe(49 * 60);
    expect(diaria).toBe(588);
  });

  it("segunda a quinta valem 9h e a sexta 8h", () => {
    expect(minutosDia(dia("08:00", "18:00"), 60)).toBe(9 * 60);
    expect(minutosDia(dia("08:00", "17:00"), 60)).toBe(8 * 60);
  });

  it("almoço batido manda: a declaração não desconta duas vezes", () => {
    const batido = dia("08:00", "17:00", {
      tem_almoco: true, inicio_almoco: "12:00", fim_almoco: "13:00",
    });
    expect(minutosDia(batido, 60)).toBe(8 * 60);
    expect(intervaloDia(batido, 60)).toBe(60);
  });

  it("dia de folga não soma jornada nem intervalo", () => {
    expect(minutosDia(folga, 60)).toBe(0);
    expect(intervaloDia(folga, 60)).toBe(0);
  });

  it("o intervalo mostrado no dia é o declarado quando não há almoço batido", () => {
    expect(intervaloDia(dia("08:00", "18:00"), 60)).toBe(60);
    expect(intervaloDia(dia("08:00", "18:00"))).toBe(0);
  });

  it("declaração maior que a janela não produz jornada negativa", () => {
    expect(minutosDia(dia("08:00", "08:30"), 60)).toBe(0);
  });
});
