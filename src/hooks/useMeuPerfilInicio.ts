import { useQuery } from "@tanstack/react-query";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "./useAuth";

export type InicioBloco = "pilares" | "indicadores" | "pendencias" | "alertas";

/** Blocos da tela Início que um perfil pode liberar (ordem de exibição). */
export const INICIO_BLOCOS: { id: InicioBloco; label: string; descricao: string }[] = [
  { id: "pilares", label: "Visão geral dos pilares", descricao: "Notas de Organização, Condições, Experiência e Governança da empresa." },
  { id: "indicadores", label: "Indicadores", descricao: "Cartões com colaboradores ativos, admissões, EPIs, documentos, avaliações e metas." },
  { id: "pendencias", label: "Pendências", descricao: "Férias, documentos, ajustes de ponto, desligamentos e demais pendências." },
  { id: "alertas", label: "Alertas críticos", descricao: "Alertas de saúde, EPIs com estoque baixo e outras informações sensíveis." },
];

export const TODOS_BLOCOS: InicioBloco[] = INICIO_BLOCOS.map((b) => b.id);

/**
 * Perfil de acesso principal do usuário logado: nome (para o cabeçalho) e os
 * blocos da tela Início liberados. `blocos = null` → painel completo (perfil
 * legado, ou usuário sem perfil vinculado: nada muda para quem não tem perfil).
 *
 * Consulta separada de `usePerfilPermissions` de propósito: se a coluna
 * `inicio_blocos` ainda não existir no banco (tela publicada antes do script),
 * cai para só o nome e o painel segue completo, sem derrubar as permissões.
 */
export function useMeuPerfilInicio() {
  const { user, tenantId, isSuperAdmin, hasMinimumRole } = useAuth();
  const isOwner = hasMinimumRole("owner") || isSuperAdmin;

  const { data: usuarioBase } = useQuery({
    queryKey: ["meu_usuario_base_id", user?.id, tenantId],
    queryFn: async () => {
      if (!user?.id || !tenantId) return null;
      const { data } = await fromTable("usuarios_base")
        .select("id")
        .eq("auth_user_id", user.id)
        .eq("tenant_id", tenantId)
        .maybeSingle();
      return (data as { id: string } | null) ?? null;
    },
    enabled: !!user?.id && !!tenantId,
    staleTime: 1000,
  });

  const { data, isLoading } = useQuery({
    queryKey: ["meu_perfil_inicio", usuarioBase?.id, tenantId],
    queryFn: async (): Promise<{ nome: string | null; blocos: InicioBloco[] | null }> => {
      const { data: vinc } = await fromTable("usuario_perfil_vinculos")
        .select("perfil_id")
        .eq("usuario_id", usuarioBase!.id)
        .eq("tenant_id", tenantId!)
        .eq("ativo", true)
        .order("is_perfil_principal", { ascending: false })
        .limit(1)
        .maybeSingle();
      const perfilId = (vinc as { perfil_id: string } | null)?.perfil_id;
      if (!perfilId) return { nome: null, blocos: null };

      let res = await fromTable("perfis_acesso").select("nome, inicio_blocos").eq("id", perfilId).maybeSingle();
      if (res.error) res = await fromTable("perfis_acesso").select("nome").eq("id", perfilId).maybeSingle();
      const row = res.data as { nome?: string; inicio_blocos?: string[] | null } | null;
      return {
        nome: row?.nome ?? null,
        blocos: Array.isArray(row?.inicio_blocos)
          ? (row!.inicio_blocos!.filter((b) => (TODOS_BLOCOS as string[]).includes(b)) as InicioBloco[])
          : null,
      };
    },
    enabled: !!usuarioBase?.id && !!tenantId,
    staleTime: 1000,
  });

  return {
    perfilNome: data?.nome ?? null,
    /** Dono e superadmin sempre veem o painel completo. */
    blocos: isOwner ? null : data?.blocos ?? null,
    isLoading: !!usuarioBase?.id && isLoading,
  };
}
