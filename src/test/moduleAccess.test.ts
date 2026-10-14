import { describe, it, expect } from "vitest";
import {
  getModulosForPath,
  getModuloForPath,
  PATH_TO_MODULOS,
  PATH_TO_MODULO,
} from "@/lib/moduleAccess";
import { MODULOS_SISTEMA } from "@/hooks/usePerfisAcesso";

/**
 * Regressão do caso "faltou acesso": um perfil novo (ex.: Gerente de Operações)
 * marca módulos granulares no editor (empresa, filiais, cargos, ponto, ferias,
 * metas…), mas a trava só checava o id grosso/legado — então marcar esses
 * módulos não liberava a tela. O mapa agora aceita AMBOS os ids por rota.
 */
describe("moduleAccess — rota aceita módulo granular e o legado", () => {
  // Rota → módulo granular que o editor grava e que ANTES era ignorado pela trava.
  const casosGranular: Array<[string, string]> = [
    ["/empresa", "empresa"],
    ["/cadastros/filiais", "filiais"],
    ["/cadastros/departamentos", "departamentos"],
    ["/cadastros/cargos", "cargos"],
    ["/ponto", "ponto"],
    ["/ferias", "ferias"],
    ["/analise-jornada", "analise_jornada"],
    ["/metas", "metas"],
    ["/contratos-experiencia", "contratos_experiencia"],
    ["/onboarding-rh", "onboarding"],
    ["/cultura-celebracoes", "cultura_celebracoes"],
    ["/feed", "feed"],
    ["/terceiros", "terceiros"],
    ["/aprendizado-papeis", "aprendizado"],
    ["/documentos", "documentos"],
    ["/usuarios", "usuarios"],
  ];

  it.each(casosGranular)(
    "%s é liberada pelo módulo granular '%s'",
    (rota, moduloGranular) => {
      expect(getModulosForPath(rota)).toContain(moduloGranular);
    }
  );

  // Rota → módulo grosso/legado que perfis ANTIGOS já usam; não pode sumir.
  const casosLegado: Array<[string, string]> = [
    ["/empresa", "configuracoes"],
    ["/cadastros/cargos", "configuracoes"],
    ["/ponto", "colaboradores"],
    ["/ferias", "colaboradores"],
    ["/metas", "avaliacoes"],
    ["/contratos-experiencia", "admissoes"],
    ["/cultura-celebracoes", "bem_estar"],
    ["/documentos", "configuracoes"],
    ["/usuarios", "configuracoes"],
  ];

  it.each(casosLegado)(
    "%s continua liberada pelo módulo legado '%s' (sem regressão)",
    (rota, moduloLegado) => {
      expect(getModulosForPath(rota)).toContain(moduloLegado);
    }
  );

  it("getModuloForPath devolve o módulo legado (primeiro da lista)", () => {
    expect(getModuloForPath("/empresa")).toBe("configuracoes");
    expect(getModuloForPath("/ponto")).toBe("colaboradores");
    expect(getModuloForPath("/metas")).toBe("avaliacoes");
  });

  it("match por prefixo preserva a lista da rota-base", () => {
    expect(getModulosForPath("/financeiro/beneficios")).toContain("beneficios");
    // sub-rota não mapeada cai na rota-base por prefixo
    expect(getModulosForPath("/colaboradores/123")).toContain("colaboradores");
  });

  it("rota sem mapeamento devolve null (trava bloqueia)", () => {
    expect(getModulosForPath("/rota-inexistente")).toBeNull();
  });

  it("PATH_TO_MODULO (achatado) = primeiro id de cada lista", () => {
    for (const [rota, modulos] of Object.entries(PATH_TO_MODULOS)) {
      expect(PATH_TO_MODULO[rota]).toBe(modulos[0]);
    }
  });

  it("todo módulo granular citado no mapa existe no editor (MODULOS_SISTEMA)", () => {
    const idsEditor = new Set(MODULOS_SISTEMA.map((m) => m.id));
    // ids legados que o editor não lista como módulo próprio (são buckets de rota)
    const legadosConhecidos = new Set(["admissoes"]);
    const desconhecidos = new Set<string>();
    for (const modulos of Object.values(PATH_TO_MODULOS)) {
      for (const m of modulos) {
        if (!idsEditor.has(m) && !legadosConhecidos.has(m)) desconhecidos.add(m);
      }
    }
    expect([...desconhecidos]).toEqual([]);
  });
});
