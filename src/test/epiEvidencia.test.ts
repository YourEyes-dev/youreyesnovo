import { describe, it, expect, vi, beforeEach } from "vitest";

const createSignedUrl = vi.fn();
vi.mock("@/integrations/supabase/client", () => ({
  supabase: { storage: { from: vi.fn(() => ({ createSignedUrl })) } },
}));

import { urlDaEvidenciaEpi, BUCKET_EVIDENCIA_EPI, evidenciaFaltandoNaEntrega, tipoDaImagem } from "@/lib/epiEvidencia";
import { supabase } from "@/integrations/supabase/client";

describe("urlDaEvidenciaEpi", () => {
  beforeEach(() => vi.clearAllMocks());

  it("devolve null quando não há referência", async () => {
    expect(await urlDaEvidenciaEpi(null)).toBeNull();
    expect(await urlDaEvidenciaEpi("")).toBeNull();
    expect(createSignedUrl).not.toHaveBeenCalled();
  });

  it("mantém a URL pública das fichas antigas", async () => {
    const antiga = "https://x.supabase.co/storage/v1/object/public/epi-signatures/t/fotos/a.png";
    expect(await urlDaEvidenciaEpi(antiga)).toBe(antiga);
    expect(createSignedUrl).not.toHaveBeenCalled();
  });

  it("gera link assinado de curta duração para o caminho do bucket privado", async () => {
    createSignedUrl.mockResolvedValue({ data: { signedUrl: "https://assinada" }, error: null });
    expect(await urlDaEvidenciaEpi("t/fotos/a.png", 120)).toBe("https://assinada");
    expect(supabase.storage.from).toHaveBeenCalledWith(BUCKET_EVIDENCIA_EPI);
    expect(createSignedUrl).toHaveBeenCalledWith("t/fotos/a.png", 120);
  });

  it("devolve null se o storage recusar (sem acesso)", async () => {
    createSignedUrl.mockResolvedValue({ data: null, error: new Error("negado") });
    expect(await urlDaEvidenciaEpi("t/fotos/a.png")).toBeNull();
  });
});

describe("evidenciaFaltandoNaEntrega", () => {
  it("entrega assinada sem a assinatura é barrada, mesmo com a foto", () => {
    expect(evidenciaFaltandoNaEntrega("entregue", "data:image/png;base64,AAA", null)).toMatch(/assinatura/);
    expect(evidenciaFaltandoNaEntrega("entregue", "data:image/png;base64,AAA", "")).toMatch(/assinatura/);
  });

  it("entrega assinada sem a foto é barrada", () => {
    expect(evidenciaFaltandoNaEntrega("entregue", null, "data:image/png;base64,BBB")).toMatch(/foto/);
  });

  it("com foto e assinatura está tudo certo", () => {
    expect(evidenciaFaltandoNaEntrega("entregue", "data:image/png;base64,AAA", "data:image/png;base64,BBB")).toBeNull();
  });

  it("a recusa de assinatura não exige foto nem assinatura", () => {
    expect(evidenciaFaltandoNaEntrega("recusado", null, null)).toBeNull();
  });
});

describe("tipoDaImagem", () => {
  it("lê o tipo do data URL e assume png quando não há", () => {
    expect(tipoDaImagem("data:image/jpeg;base64,AAA")).toBe("image/jpeg");
    expect(tipoDaImagem("data:image/png;base64,AAA")).toBe("image/png");
    expect(tipoDaImagem("sem-prefixo")).toBe("image/png");
  });
});
