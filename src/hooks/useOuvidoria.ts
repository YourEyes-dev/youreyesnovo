import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useTenant } from "./useTenant";
import { useAuth } from "./useAuth";
import { toast } from "sonner";
import type { Manifestacao, TipoManifestacao, StatusManifestacao, PrioridadeManifestacao } from "@/types/ouvidoria";

interface AnexoData {
  nome: string;
  url: string;
  tamanho: number;
  tipo: string;
  [key: string]: string | number; // Index signature for JSON compatibility
}

interface CriarManifestacaoData {
  tipo: TipoManifestacao;
  assunto: string;
  mensagem: string;
  anonimo: boolean;
  anexos?: File[];
}

interface ResponderManifestacaoData {
  id: string;
  resposta: string;
  status?: StatusManifestacao;
}

interface AtualizarStatusData {
  id: string;
  status: StatusManifestacao;
  prioridade?: PrioridadeManifestacao;
}

export function useOuvidoria() {
  const queryClient = useQueryClient();
  const { tenantId } = useTenant();
  const { user, profile } = useAuth();

  // Buscar manifestações (usuários veem apenas as suas, managers veem todas)
  const manifestacoesQuery = useQuery({
    queryKey: ["ouvidoria", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];

      const { data, error } = await supabase
        .from("ouvidoria")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("created_at", { ascending: false });

      if (error) throw error;
      return data as unknown as Manifestacao[];
    },
    enabled: !!tenantId,
  });

  // Upload de anexos
  const uploadAnexos = async (files: File[], manifestacaoId: string): Promise<AnexoData[]> => {
    const anexosUploadados: AnexoData[] = [];
    const userId = user?.id || "anonimo";

    for (const file of files) {
      const fileExt = file.name.split(".").pop();
      const fileName = `${userId}/${manifestacaoId}/${Date.now()}-${Math.random().toString(36).substring(7)}.${fileExt}`;

      const { error: uploadError } = await supabase.storage
        .from("ouvidoria-anexos")
        .upload(fileName, file);

      if (uploadError) {
        console.error("Erro ao fazer upload:", uploadError);
        continue;
      }

      anexosUploadados.push({
        nome: file.name,
        url: fileName,
        tamanho: file.size,
        tipo: file.type,
      });
    }

    return anexosUploadados;
  };

  // Criar nova manifestação (com roteamento automático)
  const criarManifestacaoMutation = useMutation({
    mutationFn: async (data: CriarManifestacaoData) => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      if (!user && !data.anonimo) throw new Error("Usuário não autenticado");

      // Buscar roteamento configurado para o tipo
      let responsavelId: string | null = null;
      let responsavelNome: string | null = null;
      let departamentoDestino: string | null = null;

      const { data: roteamento } = await supabase
        .from("ouvidoria_roteamento")
        .select("*")
        .eq("tenant_id", tenantId)
        .eq("tipo_manifestacao", data.tipo)
        .eq("ativo", true)
        .maybeSingle();

      if (roteamento) {
        responsavelId = roteamento.responsavel_id;
        responsavelNome = roteamento.responsavel_nome;
        departamentoDestino = roteamento.departamento_responsavel;
      }

      const manifestacao = {
        tenant_id: tenantId,
        tipo: data.tipo,
        assunto: data.assunto,
        mensagem: data.mensagem,
        anonimo: data.anonimo,
        autor_id: data.anonimo ? null : user?.id,
        autor_nome: data.anonimo ? null : profile?.nome_completo,
        autor_email: data.anonimo ? null : user?.email,
        autor_departamento: data.anonimo ? null : profile?.cargo,
        status: "pendente" as StatusManifestacao,
        prioridade: "normal" as PrioridadeManifestacao,
        anexos: [] as AnexoData[],
        responsavel_id: responsavelId,
        responsavel_nome: responsavelNome,
        departamento_destino: departamentoDestino,
      };

      const { data: result, error } = await supabase
        .from("ouvidoria")
        .insert(manifestacao)
        .select()
        .single();

      if (error) throw error;

      // Se há anexos, fazer upload e atualizar a manifestação
      if (data.anexos && data.anexos.length > 0) {
        const anexosUploadados = await uploadAnexos(data.anexos, result.id);

        if (anexosUploadados.length > 0) {
          const { error: updateError } = await supabase
            .from("ouvidoria")
            .update({ anexos: anexosUploadados })
            .eq("id", result.id);

          if (updateError) {
            console.error("Erro ao atualizar anexos:", updateError);
          }
        }
      }

      return result;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ouvidoria"] });
      toast.success("Manifestação enviada com sucesso!");
    },
    onError: (error) => {
      console.error("Erro ao criar manifestação:", error);
      toast.error("Erro ao enviar manifestação");
    },
  });

  // Responder manifestação
  const responderManifestacaoMutation = useMutation({
    mutationFn: async (data: ResponderManifestacaoData) => {
      if (!user) throw new Error("Usuário não autenticado");

      const { error } = await supabase
        .from("ouvidoria")
        .update({
          resposta: data.resposta,
          status: data.status || "respondido",
          respondido_por: user.id,
          respondido_por_nome: profile?.nome_completo,
          respondido_em: new Date().toISOString(),
        })
        .eq("id", data.id);

      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ouvidoria"] });
      toast.success("Resposta enviada com sucesso!");
    },
    onError: (error) => {
      console.error("Erro ao responder manifestação:", error);
      toast.error("Erro ao enviar resposta");
    },
  });

  // Atualizar status/prioridade
  const atualizarStatusMutation = useMutation({
    mutationFn: async (data: AtualizarStatusData) => {
      const updateData: { status: StatusManifestacao; prioridade?: PrioridadeManifestacao } = {
        status: data.status,
      };

      if (data.prioridade) {
        updateData.prioridade = data.prioridade;
      }

      const { error } = await supabase
        .from("ouvidoria")
        .update(updateData)
        .eq("id", data.id);

      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ouvidoria"] });
      toast.success("Status atualizado!");
    },
    onError: (error) => {
      console.error("Erro ao atualizar status:", error);
      toast.error("Erro ao atualizar status");
    },
  });

  // Deletar manifestação
  const deletarManifestacaoMutation = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from("ouvidoria")
        .delete()
        .eq("id", id);

      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ouvidoria"] });
      toast.success("Manifestação removida!");
    },
    onError: (error) => {
      console.error("Erro ao deletar manifestação:", error);
      toast.error("Erro ao remover manifestação");
    },
  });

  const manifestacoesFinais = manifestacoesQuery.data || [];

  // Estatísticas
  const stats = {
    total: manifestacoesFinais.length,
    pendentes: manifestacoesFinais.filter((m) => m.status === "pendente").length,
    emAnalise: manifestacoesFinais.filter((m) => m.status === "em_analise").length,
    respondidas: manifestacoesFinais.filter((m) => m.status === "respondido").length,
    anonimas: manifestacoesFinais.filter((m) => m.anonimo).length,
  };

  return {
    manifestacoes: manifestacoesFinais,
    manifestacoesLoading: manifestacoesQuery.isLoading,
    
    criarManifestacao: criarManifestacaoMutation.mutateAsync,
    criandoManifestacao: criarManifestacaoMutation.isPending,
    
    responderManifestacao: responderManifestacaoMutation.mutateAsync,
    respondendoManifestacao: responderManifestacaoMutation.isPending,
    
    atualizarStatus: atualizarStatusMutation.mutateAsync,
    atualizandoStatus: atualizarStatusMutation.isPending,
    
    deletarManifestacao: deletarManifestacaoMutation.mutateAsync,
    deletandoManifestacao: deletarManifestacaoMutation.isPending,
    
    stats,
  };
}
