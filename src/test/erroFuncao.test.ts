import { describe, it, expect } from "vitest";
import { detalharErroFuncao, mensagemDeErroDaFuncao } from "@/lib/erroFuncao";

// Imita o que o supabase-js devolve: erro com `context` = Response (corpo lido uma vez só).
const respostaDe = (status: number, corpo: unknown) => ({
  status,
  clone: () => ({ json: async () => (corpo instanceof Error ? Promise.reject(corpo) : corpo) }),
});
const erroHttp = (status: number, corpo: unknown) => ({
  name: "FunctionsHttpError",
  message: "Edge Function returned a non-2xx status code",
  context: respostaDe(status, corpo),
});

describe("detalharErroFuncao", () => {
  it("lê o motivo do corpo da resposta (o que `data?.error` nunca via)", async () => {
    expect(await detalharErroFuncao(erroHttp(500, { error: "OPENAI_API_KEY não configurada" }), null)).toEqual({
      status: 500,
      mensagemDoServidor: "OPENAI_API_KEY não configurada",
    });
  });
  it("aceita `message` e usa `data.error` quando existir", async () => {
    expect((await detalharErroFuncao(erroHttp(400, { message: "ruim" }))).mensagemDoServidor).toBe("ruim");
    expect((await detalharErroFuncao(erroHttp(400, {}), { error: "do data" })).mensagemDoServidor).toBe("do data");
  });
  it("corpo ilegível ou ausente não quebra: só o status", async () => {
    expect(await detalharErroFuncao(erroHttp(502, new Error("não é json")))).toEqual({ status: 502 });
    expect(await detalharErroFuncao(undefined)).toEqual({ status: undefined });
    expect(await detalharErroFuncao({ name: "FunctionsFetchError", context: new TypeError("rede") })).toEqual({ status: undefined });
  });
});

describe("mensagemDeErroDaFuncao: cada causa vira uma instrução clara", () => {
  const msg = (e: unknown, d?: unknown) => mensagemDeErroDaFuncao(e, d, "analisar os cargos");

  it("chave da OpenAI ausente", async () => {
    expect(await msg(erroHttp(500, { error: "OPENAI_API_KEY não configurada" }))).toMatch(/chave da IA não está configurada/);
  });
  it("sessão expirada ou sem permissão", async () => {
    expect(await msg(erroHttp(401, { error: "Sessão inválida ou expirada" }))).toMatch(/Entre novamente/);
    expect(await msg(erroHttp(403, { error: "Empresa não identificada" }))).toMatch(/permissão/);
  });
  it("função não publicada neste ambiente", async () => {
    expect(await msg(erroHttp(404, { code: "NOT_FOUND", message: "Requested function was not found" }))).toMatch(/ainda não está disponível/);
  });
  it("limite de uso", async () => {
    expect(await msg(erroHttp(429, {}))).toMatch(/limite de uso/);
  });
  it("sem conexão e relay fora do ar", async () => {
    expect(await msg({ name: "FunctionsFetchError", context: new TypeError("x") })).toMatch(/analisar os cargos.*internet/);
    expect(await msg({ name: "FunctionsRelayError", context: respostaDe(503, {}) })).toMatch(/temporariamente indisponível/);
  });
  it("mensagens já escritas pela função (400 e 502) aparecem como vieram", async () => {
    expect(await msg(erroHttp(502, { error: "O serviço de IA não respondeu. Tente de novo em instantes." }))).toBe(
      "O serviço de IA não respondeu. Tente de novo em instantes.",
    );
    expect(await msg(erroHttp(400, { error: "Envie de 1 a 30 cargos" }))).toBe("Envie de 1 a 30 cargos");
  });
  it("erro 500 sem motivo mostra o código; sem nenhuma informação cai no texto genérico", async () => {
    expect(await msg(erroHttp(500, {}))).toMatch(/código 500/);
    expect(await msg(undefined)).toBe("Não foi possível analisar os cargos agora. Tente de novo em instantes.");
  });
  it("nunca vaza detalhe técnico bruto de erro 500 com mensagem interna", async () => {
    const texto = await msg(erroHttp(500, { error: "TypeError: Cannot read properties of undefined (reading 'x') at file:///src/..." }));
    expect(texto).toMatch(/código 500/);
    expect(texto).not.toMatch(/TypeError|file:\/\//);
  });
});

describe("com um Response real (o que o supabase-js entrega em erro HTTP)", () => {
  it.skipIf(typeof Response === "undefined")("lê o corpo JSON e o status do Response", async () => {
    const erro = {
      name: "FunctionsHttpError",
      context: new Response(JSON.stringify({ error: "OPENAI_API_KEY não configurada" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }),
    };
    expect(await mensagemDeErroDaFuncao(erro, null, "analisar os cargos")).toMatch(/chave da IA não está configurada/);
    // ler duas vezes não pode falhar com "body already used"
    expect((await detalharErroFuncao(erro)).status).toBe(500);
  });
});
