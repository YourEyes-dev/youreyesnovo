import { describe, it, expect, vi, beforeEach } from "vitest";

const createSignedUrl = vi.fn();
vi.mock("@/integrations/supabase/client", () => ({
  supabase: { storage: { from: vi.fn(() => ({ createSignedUrl })) } },
}));

import { urlDaEvidenciaEpi, BUCKET_EVIDENCIA_EPI } from "@/lib/epiEvidencia";
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
