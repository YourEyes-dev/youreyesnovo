/**
 * Helper para acessar tabelas do Supabase que não estão no schema auto-gerado.
 * 
 * Uso:
 *   import { fromTable } from "@/integrations/supabase/untypedClient";
 *   const { data } = await fromTable("nome_tabela").select("*").eq("tenant_id", tenantId);
 * 
 * Isso substitui o pattern `(supabase as any).from("tabela")` ou `supabase.from("tabela" as never)`
 * de forma centralizada e rastreável.
 */
import { supabase } from "./client";

/**
 * Acessa uma tabela do Supabase que não está no schema tipado.
 * Retorna o query builder padrão do Supabase sem erros de tipo.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function fromTable(table: string): any {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (supabase as any).from(table);
}

/**
 * Chama uma função (RPC) que ainda não consta no schema tipado gerado —
 * por exemplo funções criadas fora das migrations.
 */
export function rpcUntyped(
  fn: string,
  args?: Record<string, unknown>,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
): Promise<{ data: any; error: any }> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (supabase as any).rpc(fn, args);
}
