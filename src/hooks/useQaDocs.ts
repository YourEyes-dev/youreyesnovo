import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "./useAuth";
import { toast } from "sonner";
import { handleMutationError } from "@/lib/toastError";
import { montarArvore } from "@/types/qa";
import type { QaModulo, QaCasoTeste } from "@/types/qa";

/**
 * Diretório de documentação de testes (superadmin).
 * Tabelas globais, sem tenant: é infraestrutura de QA do produto.
 */
export function useQaDocs(moduloId?: string | null) {
  const { user } = useAuth();
  const qc = useQueryClient();

  const { data: modulos = [], isLoading: carregandoArvore } = useQuery({
    queryKey: ["qa_modulos"],
    queryFn: async () => {
      const { data, error } = await fromTable("qa_modulos")
        .select("*")
        .order("prioridade_doc", { ascending: true })
        .order("ordem", { ascending: true });
      if (error) throw error;
      return (data || []) as QaModulo[];
    },
  });

  const arvore = montarArvore(modulos);

  const { data: casos = [], isLoading: carregandoCasos } = useQuery({
    queryKey: ["qa_casos", moduloId],
    enabled: !!moduloId,
    queryFn: async () => {
      const { data, error } = await fromTable("qa_casos_teste")
        .select("*")
        .eq("modulo_id", moduloId)
        .order("codigo", { ascending: true, nullsFirst: false })
        .order("created_at", { ascending: true });
      if (error) throw error;
      return (data || []) as QaCasoTeste[];
    },
  });

  /**
   * Contagem de casos por módulo, para exibir na árvore.
   *
   * A leitura é PAGINADA de propósito. A API corta a resposta em 1.000 linhas
   * por padrão, e a documentação já passou disso — o efeito era silencioso e
   * enganoso: os módulos cujas linhas caíam fora da primeira página ficavam
   * com contagem zero e PERDIAM o número na árvore (o caso que apareceu em
   * Férias e em Usuários & Permissões). Zero por truncamento parece "módulo
   * sem casos", que é justamente a leitura errada. Buscar até a página vir
   * incompleta mantém a contagem certa por mais que a documentação cresça.
   */
  const { data: contagem = {} } = useQuery({
    queryKey: ["qa_casos_contagem"],
    queryFn: async () => {
      const PAGINA = 1000;
      const mapa: Record<string, number> = {};

      for (let inicio = 0; ; inicio += PAGINA) {
        const { data, error } = await fromTable("qa_casos_teste")
          .select("modulo_id")
          .order("id", { ascending: true })
          .range(inicio, inicio + PAGINA - 1);
        if (error) throw error;

        const linhas = (data || []) as { modulo_id: string }[];
        linhas.forEach((r) => {
          mapa[r.modulo_id] = (mapa[r.modulo_id] || 0) + 1;
        });

        if (linhas.length < PAGINA) break;
      }

      return mapa;
    },
  });

  const invalidar = () => {
    qc.invalidateQueries({ queryKey: ["qa_casos"] });
    qc.invalidateQueries({ queryKey: ["qa_casos_contagem"] });
  };

  const salvarCasoMut = useMutation({
    mutationFn: async (caso: Partial<QaCasoTeste> & { modulo_id: string; titulo: string }) => {
      const payload = { ...caso, created_by: caso.created_by ?? user?.id ?? null };
      if (caso.id) {
        const { id, created_at, updated_at, ...resto } = payload as Record<string, unknown> & { id: string };
        const { error } = await fromTable("qa_casos_teste").update(resto).eq("id", id);
        if (error) throw error;
        return id;
      }
      const { data, error } = await fromTable("qa_casos_teste").insert(payload).select("id").single();
      if (error) throw error;
      return (data as { id: string }).id;
    },
    onSuccess: (_, vars) => {
      invalidar();
      toast.success(vars.id ? "Caso de teste salvo." : "Caso de teste criado.");
    },
    onError: handleMutationError,
  });

  const excluirCasoMut = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await fromTable("qa_casos_teste").delete().eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => {
      invalidar();
      toast.success("Caso de teste excluído.");
    },
    onError: handleMutationError,
  });

  return {
    arvore,
    modulos,
    casos,
    contagem,
    carregandoArvore,
    carregandoCasos,
    salvarCaso: salvarCasoMut.mutateAsync,
    salvando: salvarCasoMut.isPending,
    excluirCaso: excluirCasoMut.mutateAsync,
  };
}
