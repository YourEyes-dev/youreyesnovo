/**
 * Tipos de usuário com acesso amplo ao tenant: aparecem em qualquer empresa,
 * independentemente de vínculo com uma empresa específica.
 *
 * Fonte ÚNICA usada pelas telas de Usuários e de Perfis para decidir se um
 * usuário "pertence à empresa filtrada" — evita listas divergentes espalhadas.
 */
export const TIPOS_USUARIO_GLOBAIS = [
  "proprietario",
  "owner",
  "administrador",
  "rh_dp",
  "corporativo_multiempresa",
  "suporte_autorizado",
  "auditor",
] as const;

export function isTipoUsuarioGlobal(tipo?: string | null): boolean {
  return !!tipo && (TIPOS_USUARIO_GLOBAIS as readonly string[]).includes(tipo);
}
