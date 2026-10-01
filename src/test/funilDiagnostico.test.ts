import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { funilDiagnostico } from "@/lib/funilDiagnostico";
import { __reiniciarPixelParaTeste, iniciarMetaPixel, pausarMetaPixel } from "@/lib/metaConversions";
import { capturarOrigemDaVisita } from "@/lib/siteOrigem";

/** Chamadas feitas ao Pixel depois do init (sem set/init/PageView). */
function chamadasFunil(fbq: ReturnType<typeof vi.fn>) {
  return fbq.mock.calls.filter((c) => c[0] === "track" || c[0] === "trackCustom").filter((c) => c[1] !== "PageView");
}

describe("funil do diagnóstico (Pixel)", () => {
  let fbq: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    sessionStorage.clear();
    __reiniciarPixelParaTeste();
    fbq = vi.fn();
    window.fbq = fbq as unknown as Window["fbq"];
  });
  afterEach(() => {
    delete window.fbq;
    __reiniciarPixelParaTeste();
  });

  it("fora do site público/produção não envia nada (e não marca a etapa)", () => {
    // Pixel nunca iniciado (ex.: app logado, site de teste, localhost).
    expect(iniciarMetaPixel("youreyes-dev.github.io")).toBe(false);
    expect(funilDiagnostico.visivel()).toBe(false);
    expect(funilDiagnostico.iniciado()).toBe(false);
    expect(funilDiagnostico.etapa(1, 11)).toBe(false);
    expect(funilDiagnostico.contato()).toBe(false);
    expect(fbq).not.toHaveBeenCalled();
    expect(sessionStorage.getItem("ye_funil_diagnostico")).toBeNull();
  });

  it("depois de sair do site público (login na mesma aba) não envia nada", () => {
    iniciarMetaPixel("www.youreyes.com.br");
    pausarMetaPixel();
    fbq.mockClear();
    expect(funilDiagnostico.etapa(3, 11)).toBe(false);
    expect(chamadasFunil(fbq)).toHaveLength(0);
  });

  it("cada evento sai uma única vez por sessão", () => {
    iniciarMetaPixel("www.youreyes.com.br");
    expect(funilDiagnostico.visivel()).toBe(true);
    expect(funilDiagnostico.visivel()).toBe(false);
    expect(funilDiagnostico.iniciado()).toBe(true);
    expect(funilDiagnostico.iniciado()).toBe(false);
    for (let n = 1; n <= 11; n++) expect(funilDiagnostico.etapa(n, 11)).toBe(true);
    // Voltar e responder de novo não duplica.
    for (let n = 1; n <= 11; n++) expect(funilDiagnostico.etapa(n, 11)).toBe(false);
    expect(funilDiagnostico.contato()).toBe(true);
    expect(funilDiagnostico.contato()).toBe(false);

    const c = chamadasFunil(fbq);
    expect(c).toHaveLength(1 + 1 + 11 + 1);
    expect(c[0]).toEqual(["track", "ViewContent", { content_name: "diagnostico" }]);
    expect(c[1]).toEqual(["trackCustom", "DiagnosticoIniciado", {}]);
    expect(c[2]).toEqual(["trackCustom", "DiagnosticoEtapa", { etapa: 1, total: 11 }]);
    expect(c[12]).toEqual(["trackCustom", "DiagnosticoEtapa", { etapa: 11, total: 11 }]);
    expect(c[13]).toEqual(["trackCustom", "DiagnosticoContato", {}]);
  });

  it("uma nova sessão volta a contar", () => {
    iniciarMetaPixel("www.youreyes.com.br");
    funilDiagnostico.etapa(2, 11);
    sessionStorage.clear();
    expect(funilDiagnostico.etapa(2, 11)).toBe(true);
  });

  it("leva utm_campaign quando a visita veio de campanha — e nunca respostas", () => {
    capturarOrigemDaVisita("https://www.youreyes.com.br/?utm_source=meta&utm_campaign=sst_nr1#diagnostico");
    iniciarMetaPixel("www.youreyes.com.br");
    funilDiagnostico.etapa(5, 11);
    funilDiagnostico.iniciado();
    const c = chamadasFunil(fbq);
    expect(c[0]).toEqual(["trackCustom", "DiagnosticoEtapa", { etapa: 5, total: 11, utm_campaign: "sst_nr1" }]);
    expect(c[1]).toEqual(["trackCustom", "DiagnosticoIniciado", { utm_campaign: "sst_nr1" }]);
    const params = JSON.stringify(c.map((x) => x[2]));
    expect(params).not.toMatch(/sim|nao|parcial|q_|resposta|porte|setor/);
  });
});
