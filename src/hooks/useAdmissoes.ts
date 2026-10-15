import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { fromTable } from '@/integrations/supabase/untypedClient';
import {
  AdmissaoRow,
  AdmissaoInsert,
  AdmissaoUpdate,
  AdmissaoCompleta,
  AdmissaoFormData,
  AdmissaoDocumentoRow,
  AdmissaoDocumentoInsert,
  AdmissaoDocumentoUpdate,
  AdmissaoWorkflowRow,
  AdmissaoWorkflowInsert,
  AdmissaoWorkflowUpdate,
  AdmissaoHistoricoInsert,
  AdmissaoStatus,
  DocumentoStatus,
  WorkflowStatus,
  DOCUMENTOS_OBRIGATORIOS,
  DEFAULT_WORKFLOW_STEPS,
} from '@/types/database';
import { useAuth } from './useAuth';
import { useEmpresaAtiva } from '@/contexts/EmpresaAtivaContext';
import { toast } from 'sonner';
import { buildSafeStorageFileName } from '@/utils/storagePath';

export function useAdmissoes() {
  const queryClient = useQueryClient();
  const { tenantId, user, profile } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();

  // Fetch all admissões for the tenant
  const {
    data: admissoes = [],
    isLoading,
    error,
    refetch,
  } = useQuery({
    queryKey: ['admissoes', tenantId, empresaAtivaId],
    queryFn: async (): Promise<AdmissaoCompleta[]> => {
      if (!tenantId) return [];

      // Fetch admissões with pagination to bypass Supabase 1000-row default limit
      const PAGE = 1000;
      const admissoesData: any[] = [];
      let from = 0;
      for (let i = 0; i < 100; i++) {
        // Leitura pela VIEW mascarada: o salário vem nulo para perfis sem
        // "pode ver salário" (mascaramento no servidor). Escritas seguem na
        // tabela admissoes (mutations abaixo).
        let q = fromTable('admissoes_segura')
          .select('*')
          .eq('tenant_id', tenantId);
        if (empresaAtivaId) q = q.eq('empresa_id', empresaAtivaId);
        const { data, error: admissoesError } = await q
          .order('created_at', { ascending: false })
          .order('id')
          .range(from, from + PAGE - 1);
        if (admissoesError) throw admissoesError;
        const chunk = data || [];
        admissoesData.push(...chunk);
        if (chunk.length < PAGE) break;
        from += PAGE;
      }
      if (!admissoesData.length) return [];


      // Fetch related data for all admissões
      const admissaoIds = admissoesData.map(a => a.id);

      const [documentosRes, workflowRes, historicoRes] = await Promise.all([
        supabase
          .from('admissao_documentos')
          .select('*')
          .in('admissao_id', admissaoIds)
          .order('created_at', { ascending: true }),
        supabase
          .from('admissao_workflow')
          .select('*')
          .in('admissao_id', admissaoIds)
          .order('ordem', { ascending: true }),
        supabase
          .from('admissao_historico')
          .select('*')
          .in('admissao_id', admissaoIds)
          .order('created_at', { ascending: false }),
      ]);

      // Garantir arrays vazios se houver erro
      const documentosData = documentosRes.data || [];
      const workflowData = workflowRes.data || [];
      const historicoData = historicoRes.data || [];

      // Map related data to each admissão
      return admissoesData.map(admissao => ({
        ...admissao,
        documentos: documentosData.filter(d => d.admissao_id === admissao.id),
        workflow: workflowData.filter(w => w.admissao_id === admissao.id),
        historico: historicoData.filter(h => h.admissao_id === admissao.id),
      }));
    },
    enabled: !!tenantId,
  });

  // Create new admissão
  const criarAdmissao = useMutation({
    mutationFn: async (dados: AdmissaoFormData): Promise<AdmissaoCompleta> => {
      if (!tenantId || !user) throw new Error('Usuário não autenticado');

      // Insert admissão
      const { data: admissao, error: admissaoError } = await supabase
        .from('admissoes')
        .insert({
          tenant_id: tenantId,
          empresa_id: empresaAtivaId || null,
          criado_por: user.id,
          status: 'rascunho' as AdmissaoStatus,
          ...dados,
        })
        .select()
        .single();

      if (admissaoError) throw admissaoError;

      // Insert default documents (idempotente: upsert em (admissao_id, nome)).
      // Antes era .insert() puro — se este fluxo rodasse duas vezes para a
      // mesma admissão (duplo clique, retry, re-render), inseria os
      // documentos obrigatórios de novo e dobrava a lista (18 no lugar de 9).
      // O upsert, ancorado no índice único admissao_documentos_admissao_nome_uidx,
      // não recria o que já existe.
      const documentosToInsert: AdmissaoDocumentoInsert[] = DOCUMENTOS_OBRIGATORIOS.map(doc => ({
        admissao_id: admissao.id,
        tenant_id: tenantId,
        nome: doc.nome,
        tipo: doc.tipo,
        obrigatorio: doc.obrigatorio,
        status: 'pendente' as DocumentoStatus,
      }));

      const { data: documentos, error: docsError } = await supabase
        .from('admissao_documentos')
        .upsert(documentosToInsert, { onConflict: 'admissao_id,nome', ignoreDuplicates: true })
        .select();

      if (docsError) throw docsError;

      // Insert default workflow steps
      const workflowToInsert: AdmissaoWorkflowInsert[] = DEFAULT_WORKFLOW_STEPS.map((step, index) => ({
        admissao_id: admissao.id,
        tenant_id: tenantId,
        etapa: step.etapa,
        ordem: step.ordem,
        status: (index === 0 ? 'aprovado' : 'pendente') as WorkflowStatus,
        responsavel_nome: index === 0 ? 'Sistema' : 'Pendente',
        data_acao: index === 0 ? new Date().toISOString() : null,
      }));

      const { data: workflow, error: workflowError } = await supabase
        .from('admissao_workflow')
        .insert(workflowToInsert)
        .select();

      if (workflowError) throw workflowError;

      // Insert history entry
      const historicoEntry: AdmissaoHistoricoInsert = {
        admissao_id: admissao.id,
        tenant_id: tenantId,
        acao: 'Admissão criada',
        descricao: `Nova admissão criada para ${dados.nome_completo}`,
        usuario_id: user.id,
        usuario_nome: profile?.nome_completo || user.email || 'Sistema',
      };

      const { data: historico, error: historicoError } = await supabase
        .from('admissao_historico')
        .insert(historicoEntry)
        .select();

      if (historicoError) throw historicoError;

      return {
        ...admissao,
        documentos: documentos || [],
        workflow: workflow || [],
        historico: historico || [],
      };
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admissoes', tenantId, empresaAtivaId] });
    },
  });

  // Update admissão
  const atualizarAdmissao = useMutation({
    mutationFn: async ({
      id,
      dados,
    }: {
      id: string;
      dados: Partial<AdmissaoFormData>;
    }): Promise<AdmissaoRow> => {
      if (!tenantId || !user) throw new Error('Usuário não autenticado');

      const { data, error } = await supabase
        .from('admissoes')
        .update(dados as AdmissaoUpdate)
        .eq('id', id)
        .eq('tenant_id', tenantId)
        .select()
        .single();

      if (error) throw error;

      // Add history entry
      await supabase.from('admissao_historico').insert({
        admissao_id: id,
        tenant_id: tenantId,
        acao: 'Admissão atualizada',
        descricao: 'Dados da admissão foram atualizados',
        usuario_id: user.id,
        usuario_nome: profile?.nome_completo || user.email || 'Sistema',
      });

      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admissoes', tenantId, empresaAtivaId] });
    },
  });

  // Update status
  const atualizarStatus = useMutation({
    mutationFn: async ({
      id,
      status,
    }: {
      id: string;
      status: AdmissaoStatus;
    }): Promise<AdmissaoRow> => {
      if (!tenantId || !user) throw new Error('Usuário não autenticado');

      const { data, error } = await supabase
        .from('admissoes')
        .update({ status })
        .eq('id', id)
        .eq('tenant_id', tenantId)
        .select()
        .single();

      if (error) throw error;

      // Add history entry
      await supabase.from('admissao_historico').insert({
        admissao_id: id,
        tenant_id: tenantId,
        acao: 'Status atualizado',
        descricao: `Status alterado para ${status}`,
        usuario_id: user.id,
        usuario_nome: profile?.nome_completo || user.email || 'Sistema',
      });

      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admissoes', tenantId, empresaAtivaId] });
    },
  });

  // Update document
  const atualizarDocumento = useMutation({
    mutationFn: async ({
      documentoId,
      dados,
    }: {
      documentoId: string;
      dados: Partial<AdmissaoDocumentoUpdate>;
    }): Promise<AdmissaoDocumentoRow> => {
      if (!tenantId) throw new Error('Tenant não encontrado');

      const { data, error } = await supabase
        .from('admissao_documentos')
        .update(dados)
        .eq('id', documentoId)
        .eq('tenant_id', tenantId)
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admissoes', tenantId, empresaAtivaId] });
    },
  });

  // Approve/reject workflow step
  const atualizarWorkflow = useMutation({
    mutationFn: async ({
      workflowId,
      admissaoId,
      aprovado,
      observacao,
    }: {
      workflowId: string;
      admissaoId: string;
      aprovado: boolean;
      observacao?: string;
    }): Promise<AdmissaoWorkflowRow> => {
      if (!tenantId || !user) throw new Error('Usuário não autenticado');

      const status: WorkflowStatus = aprovado ? 'aprovado' : 'rejeitado';

      const { data, error } = await supabase
        .from('admissao_workflow')
        .update({
          status,
          observacao,
          data_acao: new Date().toISOString(),
          responsavel_id: user.id,
          responsavel_nome: profile?.nome_completo || user.email || 'Sistema',
        })
        .eq('id', workflowId)
        .eq('tenant_id', tenantId)
        .select()
        .single();

      if (error) throw error;

      // Check if all steps are approved/rejected and update admission status
      const { data: allWorkflow } = await supabase
        .from('admissao_workflow')
        .select('status')
        .eq('admissao_id', admissaoId);

      if (allWorkflow) {
        const todasAprovadas = allWorkflow.every(w => w.status === 'aprovado');
        const algumaRejeitada = allWorkflow.some(w => w.status === 'rejeitado');

        let novoStatus: AdmissaoStatus | null = null;
        if (todasAprovadas) novoStatus = 'concluido';
        else if (algumaRejeitada) novoStatus = 'reprovado';
        else novoStatus = 'em_analise';

        if (novoStatus) {
          await supabase
            .from('admissoes')
            .update({ status: novoStatus })
            .eq('id', admissaoId);
        }
      }

      // Add history entry
      await supabase.from('admissao_historico').insert({
        admissao_id: admissaoId,
        tenant_id: tenantId,
        acao: aprovado ? 'Etapa aprovada' : 'Etapa rejeitada',
        descricao: observacao || `Etapa ${aprovado ? 'aprovada' : 'rejeitada'}`,
        usuario_id: user.id,
        usuario_nome: profile?.nome_completo || user.email || 'Sistema',
      });

      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admissoes', tenantId, empresaAtivaId] });
    },
  });

  // Delete admissão
  const excluirAdmissao = useMutation({
    mutationFn: async (id: string): Promise<void> => {
      if (!tenantId) throw new Error('Tenant não encontrado');

      const { error } = await supabase
        .from('admissoes')
        .delete()
        .eq('id', id)
        .eq('tenant_id', tenantId);

      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admissoes', tenantId] });
    },
  });

  // Get single admissão by ID
  const buscarAdmissao = (id: string): AdmissaoCompleta | undefined => {
    return admissoes.find(a => a.id === id);
  };

  // Upload document file
  const uploadDocumento = async (
    admissaoId: string,
    documentoId: string,
    file: File
  ): Promise<string> => {
    if (!tenantId || !user) throw new Error('Tenant ou usuário não encontrado');

    // O documento pertence ao tenant DA ADMISSÃO — que pode diferir do
    // tenant principal do usuário logado (gestores vinculados/multi-conta).
    // Usar o tenant errado aqui gravava docs invisíveis para a equipe.
    const { data: admissaoTenant } = await supabase
      .from('admissoes')
      .select('tenant_id')
      .eq('id', admissaoId)
      .single();
    const docTenantId = admissaoTenant?.tenant_id || tenantId;

    const safeFileName = buildSafeStorageFileName(documentoId, file.name);
    const filePath = `${docTenantId}/admissoes/${admissaoId}/${safeFileName}`;

    const { error: uploadError } = await supabase.storage
      .from('documentos')
      .upload(filePath, file, { upsert: true });

    if (uploadError) throw uploadError;

    // Update document record with the file path (not public URL since bucket is private)
    await atualizarDocumento.mutateAsync({
      documentoId,
      dados: {
        arquivo_url: filePath, // Store path, we'll generate signed URL when viewing
        arquivo_nome: file.name,
        arquivo_tamanho: file.size,
        status: 'enviado',
        data_envio: new Date().toISOString(),
      },
    });

    // === SINCRONIZAÇÃO COM MÓDULO DOCUMENTOS ===
    // Buscar dados da admissão
    const { data: admissaoData, error: admissaoError } = await supabase
      .from('admissoes')
      .select('nome_completo, cpf')
      .eq('id', admissaoId)
      .single();

    if (admissaoError) {
      console.error('Erro ao buscar dados da admissão para sincronização:', admissaoError);
    }

    // Buscar dados do documento da admissão
    const { data: documentoData, error: docError } = await supabase
      .from('admissao_documentos')
      .select('nome, tipo')
      .eq('id', documentoId)
      .single();

    if (docError) {
      console.error('Erro ao buscar dados do documento para sincronização:', docError);
    }

    // Verificar se já existe documento com mesmo storage_path para evitar duplicação
    const { data: existingDoc } = await supabase
      .from('documentos')
      .select('id')
      .eq('storage_path', filePath)
      .eq('tenant_id', docTenantId)
      .maybeSingle();

    // Inserir na tabela documentos somente se não existir
    if (!existingDoc && admissaoData && documentoData) {
      const { error: insertError } = await supabase.from('documentos').insert({
        tenant_id: docTenantId,
        // Em admissão a pessoa ainda pode não existir como colaborador. Quando
        // já existir, a trigger documento_resolver_dono_e_pasta resolve o dono
        // pelo CPF e arquiva na pasta "Admissão" dela; concluída a admissão, a
        // reconciliação cobre o que ficou para trás (ADM-101/102/103).
        colaborador_id: null,
        colaborador_nome: admissaoData.nome_completo,
        colaborador_cpf: admissaoData.cpf,
        nome_arquivo: filePath,
        nome_original: file.name,
        tipo: documentoData.nome, // Ex: "RG", "CPF", "CTPS"
        tamanho: file.size,
        mime_type: file.type,
        storage_path: filePath,
        data_validade: null,
        status: 'valido',
        observacoes: 'Documento da admissão',
        criado_por: user.id,
        criado_por_nome: profile?.nome_completo || user.email || 'Sistema',
      });

      if (insertError) {
        console.error('Erro ao sincronizar documento com módulo documentos:', insertError);
      }
    }

    // === VALIDAÇÃO PÓS-UPLOAD ===
    // Confirma que o documento ficou persistido com arquivo e status 'enviado'
    const { data: verifyDoc, error: verifyError } = await supabase
      .from('admissao_documentos')
      .select('id, status, arquivo_url, arquivo_nome')
      .eq('id', documentoId)
      .maybeSingle();

    if (verifyError) {
      console.error('[uploadDocumento] Falha na verificação pós-upload:', verifyError);
      throw new Error('Não foi possível confirmar a persistência do documento. Tente novamente.');
    }

    if (!verifyDoc || verifyDoc.status !== 'enviado' || !verifyDoc.arquivo_url) {
      console.error('[uploadDocumento] Documento ainda pendente após upload:', verifyDoc);
      throw new Error(
        "Documento enviado ao storage, mas o registro não foi atualizado para 'enviado'. Tente novamente."
      );
    }

    return filePath;
  };

  // Remove document from admission and documents module
  const removerDocumento = async (
    documentoId: string,
    storagePath: string
  ): Promise<void> => {
    if (!tenantId) throw new Error('Tenant não encontrado');

    // Remove file from storage
    if (storagePath) {
      await supabase.storage
        .from('documentos')
        .remove([storagePath]);

      // Remove from documentos table (sincronização)
      await supabase
        .from('documentos')
        .delete()
        .eq('storage_path', storagePath)
        .eq('tenant_id', tenantId);
    }

    // Update admissao_documentos to clear file data
    await atualizarDocumento.mutateAsync({
      documentoId,
      dados: {
        arquivo_url: null,
        arquivo_nome: null,
        arquivo_tamanho: null,
        status: 'pendente',
        data_envio: null,
      },
    });
  };

  // Get signed URL for viewing a document
  const getDocumentoUrl = async (filePath: string): Promise<string | null> => {
    if (!filePath) return null;
    
    // If it's already a full URL (legacy), return as-is
    if (filePath.startsWith('http')) return filePath;

    const { data, error } = await supabase.storage
      .from('documentos')
      .createSignedUrl(filePath, 3600); // 1 hour expiration

    if (error) {
      console.error('Error creating signed URL:', error);
      return null;
    }

    return data.signedUrl;
  };

  return {
    admissoes,
    isLoading,
    error: error?.message || null,
    refetch,
    criarAdmissao: criarAdmissao.mutateAsync,
    atualizarAdmissao: atualizarAdmissao.mutateAsync,
    atualizarStatus: atualizarStatus.mutateAsync,
    atualizarDocumento: atualizarDocumento.mutateAsync,
    atualizarWorkflow: atualizarWorkflow.mutateAsync,
    excluirAdmissao: excluirAdmissao.mutateAsync,
    buscarAdmissao,
    uploadDocumento,
    removerDocumento,
    getDocumentoUrl,
    isPending:
      criarAdmissao.isPending ||
      atualizarAdmissao.isPending ||
      atualizarStatus.isPending ||
      atualizarDocumento.isPending ||
      atualizarWorkflow.isPending ||
      excluirAdmissao.isPending,
  };
}
