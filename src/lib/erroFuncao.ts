// Traduz o erro de uma Edge Function (supabase.functions.invoke) numa mensagem que
// uma pessoa de RH entende e sabe o que fazer. Em resposta de erro o supabase-js
// devolve `data = null` e deixa o corpo da resposta em `error.context` (um Response):
// quem lia só `data?.error` nunca via o motivo real.

interface RespostaLike {
  status?: number;
  clone?: () => { json: () => Promise<unknown> };
  json?: () => Promise<unknown>;
}

interface ErroLike {
  name?: string;
  message?: string;
  context?: RespostaLike;
}

export interface DetalheErroFuncao {
  status?: number;
  /** mensagem que a própria função devolveu no corpo ({ error: "..." }) */
  mensagemDoServidor?: string;
}

/** Lê status e mensagem do corpo da resposta de erro, sem nunca lançar. */
export async function detalharErroFuncao(error: unknown, data?: unknown): Promise<DetalheErroFuncao> {
  const e = (error ?? {}) as ErroLike;
  const resp = e.context && typeof e.context === "object" ? e.context : undefined;
  const status = typeof resp?.status === "number" ? resp.status : undefined;

  const doData = (data as { error?: unknown } | null | undefined)?.error;
  if (typeof doData === "string" && doData.trim()) return { status, mensagemDoServidor: doData.trim() };

  try {
    const leitor = resp?.clone ? resp.clone() : resp;
    if (leitor && typeof leitor.json === "function") {
      const corpo = (await leitor.json()) as { error?: unknown; message?: unknown } | null;
      const texto = typeof corpo?.error === "string" ? corpo.error : typeof corpo?.message === "string" ? corpo.message : "";
      if (texto.trim()) return { status, mensagemDoServidor: texto.trim() };
    }
  } catch {
    /* corpo vazio ou que não é JSON: segue só com o status */
  }
  return { status };
}

/**
 * Mensagem para a pessoa, em português claro, dizendo o que aconteceu e o que fazer.
 * `acao` completa a frase ("analisar os cargos").
 */
export async function mensagemDeErroDaFuncao(error: unknown, data?: unknown, acao = "usar a IA"): Promise<string> {
  const { status, mensagemDoServidor } = await detalharErroFuncao(error, data);
  const nome = (error as ErroLike | null | undefined)?.name;
  const m = (mensagemDoServidor ?? "").toLowerCase();

  if (m.includes("openai_api_key") || (m.includes("chave") && m.includes("configurad"))) {
    return "A chave da IA não está configurada neste ambiente. Avise o responsável técnico para cadastrá-la.";
  }
  if (status === 401 || status === 403) {
    return "Sua sessão expirou ou você não tem permissão. Entre novamente e tente de novo.";
  }
  if (status === 404) {
    return "O serviço de IA ainda não está disponível neste ambiente. Avise o responsável técnico.";
  }
  if (status === 429) {
    return "O serviço de IA atingiu o limite de uso agora. Aguarde alguns minutos e tente de novo.";
  }
  if (nome === "FunctionsFetchError") {
    return `Não foi possível conectar ao servidor para ${acao}. Verifique sua internet e tente de novo.`;
  }
  if (nome === "FunctionsRelayError") {
    return "O serviço está temporariamente indisponível. Tente de novo em instantes.";
  }
  // a função devolve mensagens já escritas para pessoas (400 e 502): mostra como veio
  if (mensagemDoServidor && (status === undefined || status < 500 || status === 502)) return mensagemDoServidor;
  if (status && status >= 500) {
    return `O serviço de IA falhou (código ${status}). Tente de novo e, se persistir, avise o suporte.`;
  }
  return `Não foi possível ${acao} agora. Tente de novo em instantes.`;
}
