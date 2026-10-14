/**
 * Helper central para construir URLs de Edge Functions do Supabase
 * baseado nas variáveis de ambiente do Vite.
 *
 * Uso:
 *   const url = getSupabaseFunctionUrl("ai-chat");
 *   // -> https://<project>.supabase.co/functions/v1/ai-chat
 */

export function getSupabaseFunctionUrl(functionName: string): string {
  const baseUrl = import.meta.env.VITE_SUPABASE_URL;

  if (!baseUrl) {
    console.warn(
      `[getSupabaseFunctionUrl] VITE_SUPABASE_URL não está definido. Verifique o arquivo .env do ambiente.`
    );
    throw new Error("VITE_SUPABASE_URL não configurado");
  }

  const normalized = baseUrl.replace(/\/$/, "");
  return `${normalized}/functions/v1/${functionName}`;
}

/**
 * Extrai a mensagem REAL de uma edge function que falhou.
 *
 * O supabase-js embrulha qualquer resposta non-2xx em "Edge Function returned
 * a non-2xx status code" e guarda o corpo original em `error.context`. Como as
 * funções deste projeto respondem { error: "motivo" }, jogar fora o corpo
 * transforma toda falha — permissão, e-mail duplicado em outra organização,
 * link de convite — na mesma mensagem genérica, e o diagnóstico vira caça ao
 * log. Sempre passe o erro por aqui antes de exibir ao usuário.
 */
export async function mensagemDaFuncao(error: any, data?: any): Promise<string> {
  if (data?.error) return String(data.error);
  try {
    const ctx = error?.context;
    if (ctx && typeof ctx.clone === "function") {
      const corpo = await ctx.clone().json().catch(() => null);
      if (corpo?.error) return String(corpo.error);
      const texto = await ctx.clone().text().catch(() => "");
      if (texto) return texto.slice(0, 300);
    }
  } catch {
    // corpo ilegível — cai na mensagem genérica abaixo
  }
  return error?.message || "Falha ao chamar a função";
}

/**
 * Retorna o Project ID do Supabase configurado para o ambiente atual.
 */
export function getSupabaseProjectId(): string {
  const projectId = import.meta.env.VITE_SUPABASE_PROJECT_ID;

  if (!projectId) {
    console.warn(
      `[getSupabaseProjectId] VITE_SUPABASE_PROJECT_ID não está definido. Verifique o arquivo .env do ambiente.`
    );
    throw new Error("VITE_SUPABASE_PROJECT_ID não configurado");
  }

  return projectId;
}
