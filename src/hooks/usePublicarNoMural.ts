import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";

export interface PublicarNoMuralArgs {
  conteudo: string;
  tipo: "aniversario" | "tempo_casa" | "anuncio";
  /** ação cultural a marcar como publicada */
  acaoId?: string;
}

/** Publica no Mural, como a pessoa logada, um texto que ela mesma revisou. */
export function usePublicarNoMural() {
  const { tenantId, user, profile } = useAuth();
  const qc = useQueryClient();

  return async ({ conteudo, tipo, acaoId }: PublicarNoMuralArgs) => {
    if (!tenantId || !user || !profile) throw new Error("Usuário não autenticado");
    const { error } = await fromTable("feed_posts").insert({
      tenant_id: tenantId,
      autor_id: user.id,
      autor_nome: profile.nome_completo,
      autor_avatar: profile.avatar_url,
      tipo,
      conteudo,
    });
    if (error) { toast.error("Erro ao publicar no Mural"); throw error; }
    if (acaoId) {
      await fromTable("cultura_acoes").update({ publicado_em: new Date().toISOString() }).eq("id", acaoId);
      qc.invalidateQueries({ queryKey: ["cultura-acoes"] });
    }
    qc.invalidateQueries({ queryKey: ["feed-posts"] });
    toast.success("Publicado no Mural!");
  };
}
