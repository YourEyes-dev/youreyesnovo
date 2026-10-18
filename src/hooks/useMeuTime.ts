import { useQuery } from "@tanstack/react-query";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";
import { escaparParaIlike, variantesDeCpf } from "@/lib/celebracoes";

/**
 * Ids das admissões que a pessoa logada gerencia. Duas fontes do cadastro:
 *  - o campo "gestor imediato" do colaborador, igual ao nome da pessoa logada;
 *  - o departamento em que ela é gestora (ou substituta com a substituição ativa).
 * A pessoa logada é ligada à própria admissão pelo CPF do cadastro de usuários.
 */
export function useMeuTime(habilitado: boolean) {
  const { tenantId, user, profile } = useAuth();

  return useQuery({
    queryKey: ["meu-time", tenantId, user?.id],
    enabled: habilitado && !!tenantId && !!user?.id,
    staleTime: 5 * 60 * 1000,
    queryFn: async (): Promise<string[]> => {
      const { data: me } = await fromTable("usuarios_base")
        .select("cpf, nome_completo")
        .eq("auth_user_id", user!.id)
        .maybeSingle();
      const nome: string = (me?.nome_completo || profile?.nome_completo || "").trim();

      const cpfs = variantesDeCpf(me?.cpf);
      let meuAdmissaoId: string | null = null;
      if (cpfs.length) {
        const { data } = await fromTable("admissoes").select("id").eq("tenant_id", tenantId).in("cpf", cpfs).limit(1);
        meuAdmissaoId = data?.[0]?.id ?? null;
      }

      const ids = new Set<string>();

      if (nome) {
        const { data } = await fromTable("admissoes")
          .select("id")
          .eq("tenant_id", tenantId)
          .eq("status", "concluido")
          .ilike("gestor_imediato", escaparParaIlike(nome));
        (data || []).forEach((r: { id: string }) => ids.add(r.id));
      }

      if (meuAdmissaoId) {
        const { data: deptos } = await fromTable("departamentos")
          .select("nome")
          .eq("tenant_id", tenantId)
          .or(`gestor_admissao_id.eq.${meuAdmissaoId},and(substituto_ativo.eq.true,gestor_substituto_admissao_id.eq.${meuAdmissaoId})`);
        const nomes = (deptos || []).map((d: { nome: string }) => d.nome);
        if (nomes.length) {
          const { data } = await fromTable("admissoes")
            .select("id")
            .eq("tenant_id", tenantId)
            .eq("status", "concluido")
            .in("departamento", nomes);
          (data || []).forEach((r: { id: string }) => ids.add(r.id));
        }
        ids.delete(meuAdmissaoId); // ninguém é gestor de si mesmo
      }

      return [...ids];
    },
  });
}
