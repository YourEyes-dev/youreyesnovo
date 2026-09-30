import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import {
  anguloDaCampanha,
  capturarOrigemDaVisita,
  extrairOrigemDaUrl,
  fonteOrigemTexto,
  hostDeProducao,
  lerOrigemGuardada,
} from "@/lib/siteOrigem";
import { montarCorpoHubspot } from "@/lib/hubspotLead";
import {
  __reiniciarPixelParaTeste,
  iniciarMetaPixel,
  META_PIXEL_ID,
  montarFbc,
  pausarMetaPixel,
  trackConversion,
} from "@/lib/metaConversions";

const URL_ANUNCIO =
  "https://www.youreyes.com.br/?utm_source=meta&utm_medium=paid&utm_campaign=sst_nr1_teste&utm_content=video1&fbclid=ABC123#diagnostico";

describe("siteOrigem — hosts de produção (Pixel)", () => {
  it("aceita só youreyes.com.br e www.youreyes.com.br", () => {
    expect(hostDeProducao("youreyes.com.br")).toBe(true);
    expect(hostDeProducao("www.youreyes.com.br")).toBe(true);
    expect(hostDeProducao("WWW.YOUREYES.COM.BR")).toBe(true);
    expect(hostDeProducao("youreyes-dev.github.io")).toBe(false);
    expect(hostDeProducao("seguramente.lovable.app")).toBe(false);
    expect(hostDeProducao("lovable.dev")).toBe(false);
    expect(hostDeProducao("localhost")).toBe(false);
    expect(hostDeProducao("youreyes.com.br.evil.com")).toBe(false);
    expect(hostDeProducao("")).toBe(false);
  });
});

describe("siteOrigem — UTMs", () => {
  beforeEach(() => sessionStorage.clear());

  it("lê a query antes do hash (padrão dos anúncios)", () => {
    const o = extrairOrigemDaUrl(URL_ANUNCIO);
    expect(o).toMatchObject({
      utm_source: "meta",
      utm_medium: "paid",
      utm_campaign: "sst_nr1_teste",
      utm_content: "video1",
      fbclid: "ABC123",
    });
  });

  it("tolera a query colada depois do hash (#diagnostico?utm_...)", () => {
    const o = extrairOrigemDaUrl("https://www.youreyes.com.br/#diagnostico?utm_source=x&utm_campaign=jornada");
    expect(o.utm_source).toBe("x");
    expect(o.utm_campaign).toBe("jornada");
  });

  it("guarda a PRIMEIRA visita com campanha e não sobrescreve depois", () => {
    const primeira = capturarOrigemDaVisita(URL_ANUNCIO);
    expect(primeira.utm_campaign).toBe("sst_nr1_teste");
    expect(primeira.landing_url).not.toContain("#");
    expect(primeira.fbclid_em).toBeTypeOf("number");

    const segunda = capturarOrigemDaVisita("https://www.youreyes.com.br/?utm_source=google&utm_campaign=outra");
    expect(segunda.utm_campaign).toBe("sst_nr1_teste");
    expect(lerOrigemGuardada()?.utm_source).toBe("meta");
  });

  it("navegação sem UTM não apaga a origem guardada", () => {
    capturarOrigemDaVisita(URL_ANUNCIO);
    const depois = capturarOrigemDaVisita("https://www.youreyes.com.br/#planos");
    expect(depois.utm_source).toBe("meta");
  });

  it("visita orgânica não grava nada", () => {
    expect(capturarOrigemDaVisita("https://www.youreyes.com.br/")).toEqual({});
    expect(lerOrigemGuardada()).toBeNull();
  });
});

describe("siteOrigem — ângulo de dor e fonte", () => {
  it("mapeia utm_campaign para os valores do HubSpot", () => {
    expect(anguloDaCampanha("sst")).toBe("sst");
    expect(anguloDaCampanha("dor_NR1_psicossocial")).toBe("sst");
    expect(anguloDaCampanha("epi_vencido")).toBe("sst");
    expect(anguloDaCampanha("jornada_horas_extras")).toBe("jornada");
    expect(anguloDaCampanha("documentos_admissao")).toBe("documentos");
    expect(anguloDaCampanha("dor_doc")).toBe("documentos");
    expect(anguloDaCampanha("pessoas_turnover")).toBe("pessoas");
    expect(anguloDaCampanha("cultura_clima")).toBe("pessoas");
    expect(anguloDaCampanha("dho_pdi")).toBe("dho");
    expect(anguloDaCampanha("descoberta_estrategia")).toBe("estrategia");
    expect(anguloDaCampanha("remarketing_geral")).toBeNull();
    expect(anguloDaCampanha("")).toBeNull();
    expect(anguloDaCampanha(undefined)).toBeNull();
  });

  it("monta ye_fonte_origem como utm_source / utm_campaign / utm_content", () => {
    expect(fonteOrigemTexto({ utm_source: "meta", utm_campaign: "sst", utm_content: "v1" })).toBe("meta / sst / v1");
    expect(fonteOrigemTexto({ utm_source: "meta", utm_campaign: "sst" })).toBe("meta / sst / -");
    expect(fonteOrigemTexto({})).toBe("");
    expect(fonteOrigemTexto(null)).toBe("");
  });
});

describe("hubspotLead — corpo enviado ao servidor (LGPD)", () => {
  it("leva só dados do formulário, índice agregado e origem — nunca respostas", () => {
    const corpo = montarCorpoHubspot({
      email: "  Fulana@Empresa.com.br ",
      nome: " Fulana de Tal ",
      empresa: "Empresa Staging LTDA",
      cargo: "",
      telefone: "(46) 99999-0000",
      porte: "20_99",
      score: 63,
      formulario: "site-diagnostico-psicossocial",
      origem: { utm_source: "meta", utm_campaign: "sst_nr1", utm_content: "v2" },
    });
    expect(corpo.email).toBe("fulana@empresa.com.br");
    expect(corpo.nome).toBe("Fulana de Tal");
    expect(corpo.cargo).toBeUndefined();
    expect(corpo.telefone).toBe("46999990000");
    expect(corpo.score).toBe(63);
    expect(corpo.angulo_dor).toBe("sst");
    expect(corpo.fonte_origem).toBe("meta / sst_nr1 / v2");
    const texto = JSON.stringify(corpo);
    expect(texto).not.toMatch(/respostas|q_inventario|q_canal|dimensoes/);
  });
});

describe("metaConversions — Pixel e servidor com o mesmo event_id", () => {
  const fetchMock = vi.fn(() => Promise.resolve(new Response("{}")));

  beforeEach(() => {
    sessionStorage.clear();
    fetchMock.mockClear();
    vi.stubGlobal("fetch", fetchMock);
    document.cookie = "_fbc=; expires=Thu, 01 Jan 1970 00:00:00 GMT";
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    delete window.fbq;
    __reiniciarPixelParaTeste();
  });

  it("sem Pixel (fora da produção) não quebra e ainda chama o servidor", () => {
    delete window.fbq;
    const id = trackConversion("Lead", { email: "a@b.com.br", phone: "46 99999-0000", url: URL_ANUNCIO });
    expect(id).toBeTruthy();
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("o event_id do Pixel é o mesmo enviado ao servidor", () => {
    const fbq = vi.fn();
    window.fbq = fbq;
    iniciarMetaPixel("www.youreyes.com.br");
    fbq.mockClear();
    const id = trackConversion("Lead", { email: "A@B.com.br ", phone: "(46) 99999-0000", url: URL_ANUNCIO });
    expect(fbq).toHaveBeenCalledWith("track", "Lead", {}, { eventID: id });
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toMatch(/\/functions\/v1\/meta-capi$/);
    // Requisição simples: sem preflight de CORS, keepalive ligado.
    expect((init.headers as Record<string, string>)["Content-Type"]).toMatch(/^text\/plain/);
    expect(init.keepalive).toBe(true);
    const corpo = JSON.parse(String(init.body));
    expect(corpo.event_id).toBe(id);
    expect(corpo.event_name).toBe("Lead");
    expect(corpo.email).toBe("a@b.com.br");
    expect(corpo.phone).toBe("46999990000");
    expect(corpo.event_source_url).toBe(URL_ANUNCIO);
  });

  it("Pixel que lança erro não impede o envio ao servidor", () => {
    window.fbq = () => {
      throw new Error("bloqueado");
    };
    iniciarMetaPixel("www.youreyes.com.br");
    expect(() => trackConversion("Lead", {})).not.toThrow();
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("sem cookie _fbc, monta o fbc pelo fbclid da chegada", () => {
    capturarOrigemDaVisita(URL_ANUNCIO);
    expect(montarFbc()).toMatch(/^fb\.1\.\d+\.ABC123$/);
  });
});

describe("metaConversions — Pixel só no site público", () => {
  beforeEach(() => {
    delete window.fbq;
    delete window._fbq;
    __reiniciarPixelParaTeste();
    document.querySelectorAll('script[src*="fbevents"]').forEach((el) => el.remove());
    vi.stubGlobal("fetch", vi.fn(() => Promise.resolve(new Response("{}"))));
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    delete window.fbq;
    delete window._fbq;
    __reiniciarPixelParaTeste();
  });

  it("fora do host de produção não carrega nada", () => {
    expect(iniciarMetaPixel("youreyes-dev.github.io")).toBe(false);
    expect(iniciarMetaPixel("seguramente.lovable.app")).toBe(false);
    expect(iniciarMetaPixel()).toBe(false); // jsdom = localhost
    expect(window.fbq).toBeUndefined();
    expect(document.querySelector('script[src*="fbevents"]')).toBeNull();
  });

  it("em produção: autoConfig desligado ANTES do init, sem PageView de rota, e PageView explícito", () => {
    expect(iniciarMetaPixel("www.youreyes.com.br")).toBe(true);
    const fbq = window.fbq!;
    expect(fbq.disablePushState).toBe(true);
    const fila = (fbq.queue as unknown[][]).map((a) => Array.from(a));
    expect(fila).toEqual([
      ["set", "autoConfig", false, META_PIXEL_ID],
      ["init", META_PIXEL_ID],
      ["track", "PageView"],
    ]);
    expect(document.querySelectorAll('script[src*="fbevents"]').length).toBe(1);
  });

  it("depois de sair do site público (ex.: login na mesma aba) nada vai para o Pixel", () => {
    iniciarMetaPixel("www.youreyes.com.br");
    pausarMetaPixel();
    const fbq = window.fbq!;
    const antes = (fbq.queue as unknown[]).length;
    trackConversion("Lead", { email: "a@b.com.br" });
    const fila = (fbq.queue as unknown[][]).map((a) => Array.from(a));
    expect(fila[antes - 1]).toEqual(["consent", "revoke"]);
    expect(fila.length).toBe(antes); // nenhum track depois da pausa
  });

  it("voltar ao site público reativa sem recarregar a biblioteca", () => {
    iniciarMetaPixel("www.youreyes.com.br");
    pausarMetaPixel();
    iniciarMetaPixel("www.youreyes.com.br");
    const fila = (window.fbq!.queue as unknown[][]).map((a) => Array.from(a));
    expect(fila.slice(-2)).toEqual([["consent", "grant"], ["track", "PageView"]]);
    expect(fila.filter((a) => a[0] === "init").length).toBe(1);
    expect(document.querySelectorAll('script[src*="fbevents"]').length).toBe(1);
  });
});
