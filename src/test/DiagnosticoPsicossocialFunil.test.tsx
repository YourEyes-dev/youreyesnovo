import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

vi.mock("@/integrations/supabase/client", () => ({
  supabase: { from: () => ({ insert: () => Promise.resolve({ error: null }) }) },
}));

import { DiagnosticoPsicossocial } from "@/components/site/DiagnosticoPsicossocial";
import { __reiniciarPixelParaTeste, iniciarMetaPixel } from "@/lib/metaConversions";

describe("DiagnosticoPsicossocial — eventos de funil na tela", () => {
  let fbq: ReturnType<typeof vi.fn>;
  beforeEach(() => {
    sessionStorage.clear();
    __reiniciarPixelParaTeste();
    fbq = vi.fn();
    window.fbq = fbq as unknown as Window["fbq"];
    vi.stubGlobal("fetch", vi.fn(() => Promise.resolve(new Response("{}"))));
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    delete window.fbq;
    __reiniciarPixelParaTeste();
  });

  const funil = () =>
    fbq.mock.calls.filter((c) => c[0] === "trackCustom").map((c) => [c[1], c[2]]);

  it("numera as 11 etapas, marca início e contato, e não repete ao voltar", () => {
    iniciarMetaPixel("www.youreyes.com.br");
    render(<MemoryRouter><DiagnosticoPsicossocial /></MemoryRouter>);

    fireEvent.click(screen.getByText("20 a 99"));
    fireEvent.click(screen.getByText("Serviços / Escritório"));
    for (let i = 0; i < 8; i++) fireEvent.click(screen.getByText("Não"));
    // Volta uma pergunta e responde de novo: não duplica a etapa 10.
    fireEvent.click(screen.getByText("Voltar"));
    fireEvent.click(screen.getByText("Sim, e temos documento que comprova"));

    const c = funil();
    expect(c[0]).toEqual(["DiagnosticoIniciado", {}]);
    const etapas = c.filter((x) => x[0] === "DiagnosticoEtapa").map((x) => (x[1] as { etapa: number }).etapa);
    expect(etapas).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    expect(c.filter((x) => x[0] === "DiagnosticoContato")).toHaveLength(1);
    expect(JSON.stringify(c)).not.toMatch(/"nao"|"sim"|20_99|Escrit/);
  });

  it("sem o site público ativo (app logado/teste) a tela não manda nada ao Pixel", () => {
    render(<MemoryRouter><DiagnosticoPsicossocial /></MemoryRouter>);
    fireEvent.click(screen.getByText("20 a 99"));
    fireEvent.click(screen.getByText("Serviços / Escritório"));
    expect(fbq).not.toHaveBeenCalled();
  });
});
