import { describe, it, expect } from "vitest";
import { ESCOPOS_DISPONIVEIS, ESCOPO_APLICADO } from "@/hooks/usePerfisAcesso";

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

  it("os recortes intermediários continuam marcados como não aplicados", () => {
    for (const id of [
      "subordinados_diretos",
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
    }
  });

  it("ESCOPO_APLICADO trata id desconhecido/nulo como não aplicado", () => {
    expect(ESCOPO_APLICADO(undefined)).toBe(false);
    expect(ESCOPO_APLICADO("inexistente")).toBe(false);
    expect(ESCOPO_APLICADO("empresa_inteira")).toBe(true);
  });
});
