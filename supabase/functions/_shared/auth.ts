// =====================================================================
// _shared/auth.ts — autenticação única das Edge Functions que chamam IA
//
// Por que existe: várias funções `ai-*` têm `verify_jwt = false` (o gateway
// não confere o login) e usavam a chave de serviço, que ignora o RLS. Duas
// consequências já vistas no código: (1) chamada sem login gastava a chave da
// OpenAI da casa; (2) o `tenantId` vinha do CORPO da requisição, então quem
// soubesse o id de outra empresa lia o contexto dela.
//
// Regras deste arquivo (valem para todo agente e função de IA nova):
//   1) O login é CONFERIDO no Auth (`auth.getUser`), nunca decodificado "na mão".
//      A chave anon (pública) NÃO é login: sem usuário, recusa com 401.
//   2) A empresa (tenant) é SEMPRE derivada do cadastro do usuário
//      (`profiles.tenant_id`). Nenhum `tenantId` do corpo é aceito.
//   3) Funções de operação interna (QA) exigem superadmin.
// =====================================================================

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export class HttpError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export interface Usuario {
  userId: string;
  /** Cliente com chave de serviço. Use SEMPRE filtrando por `tenantId` abaixo. */
  admin: SupabaseClient;
}

export interface UsuarioComEmpresa extends Usuario {
  tenantId: string;
}

function criarClientes(req: Request) {
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) throw new HttpError(401, "Não autenticado");

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !anon || !service) throw new HttpError(500, "Configuração do servidor incompleta");

  const semSessao = { autoRefreshToken: false, persistSession: false };
  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: authHeader } },
    auth: semSessao,
  });
  const admin = createClient(url, service, { auth: semSessao });
  return { userClient, admin };
}

async function conferirUsuario(req: Request): Promise<Usuario> {
  const { userClient, admin } = criarClientes(req);
  const { data, error } = await userClient.auth.getUser();
  // Chave anon (sem usuário) cai aqui: `getUser` não devolve usuário para ela.
  if (error || !data?.user?.id) throw new HttpError(401, "Sessão inválida ou expirada");
  return { userId: data.user.id, admin };
}

/** Exige usuário logado. Não resolve empresa (use quando a função não precisa dela). */
export async function exigirUsuario(req: Request): Promise<Usuario> {
  return await conferirUsuario(req);
}

/** Exige usuário logado E devolve a empresa dele, lida do cadastro (nunca do corpo). */
export async function autenticar(req: Request): Promise<UsuarioComEmpresa> {
  const u = await conferirUsuario(req);
  const { data: profile } = await u.admin
    .from("profiles")
    .select("tenant_id")
    .eq("user_id", u.userId)
    .maybeSingle();
  if (!profile?.tenant_id) throw new HttpError(403, "Empresa não identificada para este usuário");
  return { ...u, tenantId: profile.tenant_id as string };
}

/** Exige superadmin da casa (rotinas internas de QA). */
export async function exigirSuperadmin(req: Request): Promise<Usuario> {
  const u = await conferirUsuario(req);
  const { data: ehSuper } = await u.admin.rpc("is_superadmin", { _user_id: u.userId });
  if (ehSuper !== true) throw new HttpError(403, "Acesso restrito a superadmins");
  return u;
}

/** Converte qualquer erro em Response JSON, respeitando o status de HttpError. */
export function respostaDeErro(e: unknown, corsHeaders: Record<string, string>): Response {
  const status = e instanceof HttpError ? e.status : 500;
  const mensagem = e instanceof Error ? e.message : "Erro desconhecido";
  if (status >= 500) console.error("Error:", e);
  return new Response(JSON.stringify({ error: mensagem }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
