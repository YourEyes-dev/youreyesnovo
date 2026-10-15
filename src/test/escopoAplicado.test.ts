import { describe, it, expect } from "vitest";
import { ESCOPOS_DISPONIVEIS, ESCOPO_APLICADO, MODULOS_COM_SUBORDINADOS } from "@/hooks/usePerfisAcesso";

/**
 * Trava de honestidade: hoje o filtro de dados (perfil_permite_modulo) só
 * distingue "próprio usuário" de "mais que isso" — todo escopo que não é
 * `proprio_usuario` libera a empresa ativa inteira. Portanto SÓ estes dois
 * podem ser marcados como aplicados. Virar `aplicado: true` em qualquer outro
 * sem implementar o filtro real volta a prometer um recorte que não acontece
 * (risco de LGPD). Este teste quebra de propósito se isso for feito sem querer.
 */
describe("ESCOPO_APLICADO — só o que o filtro de dados honra hoje", () => {
  const aplicadosEsperados = ["proprio_usuario", "empresa_inteira"];

  it("exatamente 'proprio_usuario' e 'empresa_inteira' estão aplicados", () => {
    const aplicados = ESCOPOS_DISPONIVEIS.filter((e) => e.aplicado).map((e) => e.id).sort();
    expect(aplicados).toEqual([...aplicadosEsperados].sort());
  });

  it("os recortes ainda sem filtro continuam não aplicados (sem módulo)", () => {
    for (const id of [
      "equipe_direta_indireta",
      "setor",
      "unidade",
      "estabelecimento",
      "grupo_economico",
      "multiplas_empresas",
      "carteira_clientes",
      "customizado",
    ]) {
      expect(ESCOPO_APLICADO(id)).toBe(false);
      expect(ESCOPO_APLICADO(id, "ferias")).toBe(false);
    }
  });

  it("subordinados_diretos é aplicado SÓ nos módulos liberados", () => {
    // sem módulo ou módulo não liberado → não aplicado
    expect(ESCOPO_APLICADO("subordinados_diretos")).toBe(false);
    expect(ESCOPO_APLICADO("subordinados_diretos", "ponto")).toBe(false);
    // módulo liberado (ferias) → aplicado
    expect(MODULOS_COM_SUBORDINADOS.has("ferias")).toBe(true);
    expect(ESCOPO_APLICADO("subordinados_diretos", "ferias")).toBe(true);
    // todo módulo listado como liberado realmente retorna true
    for (const m of MODULOS_COM_SUBORDINADOS) {
      expect(ESCOPO_APLICADO("subordinados_diretos", m)).toBe(true);
    }
  });

  it("próprio/empresa valem sempre; id desconhecido/nulo não", () => {
    expect(ESCOPO_APLICADO(undefined)).toBe(false);
    expect(ESCOPO_APLICADO("inexistente")).toBe(false);
    expect(ESCOPO_APLICADO("empresa_inteira")).toBe(true);
    expect(ESCOPO_APLICADO("empresa_inteira", "ponto")).toBe(true);
    expect(ESCOPO_APLICADO("proprio_usuario", "ferias")).toBe(true);
  });
});
