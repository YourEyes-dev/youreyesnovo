import { useAuth } from "./useAuth";

/**
 * Permissões de tela do Mapa Comportamental, no molde de useAvaliacaoPermissoes.
 * Mapeia a matriz de permissões da Parte 6 do documento para as abas do MVP:
 *   - Meu Mapa: todos (o colaborador responde e vê o próprio resultado)
 *   - Painel:   gestor e RH (visão de cobertura/composição, com supressão por baixo N)
 *   - Governança/Campanhas: RH/Admin (fatias seguintes)
 *
 * Papéis (userRoleMap): colaborador → user; gestor → manager; RH/admin → admin.
 */
export function useMapaComportamentalPermissoes() {
  const { roles, hasMinimumRole } = useAuth();
  const isRH = hasMinimumRole("admin"); // admin + owner + superadmin
  const isGestor = hasMinimumRole("manager"); // manager, admin, owner
  const isColaborador = hasMinimumRole("user");

  return {
    // Aba "Meu Mapa": qualquer usuário autenticado responde o próprio instrumento.
    podeResponder: isColaborador,
    // Aba "Painel": leitura de composição/cobertura — gestor e RH.
    podeVerPainel: isGestor,
    // Aba "Guia do Líder": orientação por perfil — gestor e RH.
    podeVerGuia: isGestor,
    // Campanhas / Governança — RH/Admin (fatias seguintes).
    podeGerenciarCampanhas: isRH,
    podeVerGovernanca: isRH,
    isRH,
    isGestor,
    isColaborador,
    roles,
  };
}
