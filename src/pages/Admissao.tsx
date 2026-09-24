import { useState } from 'react';
import { motion } from 'framer-motion';
import { UserPlus, AlertCircle, Loader2 } from 'lucide-react';
import { AdmissaoStats } from '@/components/admissao/AdmissaoStats';
import { AdmissaoList } from '@/components/admissao/AdmissaoList';
import { AdmissaoForm } from '@/components/admissao/AdmissaoForm';
import { AdmissaoDetail } from '@/components/admissao/AdmissaoDetail';
import { supabase } from '@/integrations/supabase/client';

import { useAdmissoes } from '@/hooks/useAdmissoes';
import { useAuthContext } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import { AdmissaoFormData } from '@/types/database';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';

type ViewMode = 'list' | 'new' | 'edit' | 'detail';

export default function Admissao() {
  const [viewMode, setViewMode] = useState<ViewMode>('list');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [deleteId, setDeleteId] = useState<string | null>(null);
  

  const { hasMinimumRole, loading: authLoading } = useAuthContext();
  
  const {
    admissoes,
    isLoading,
    error,
    criarAdmissao,
    atualizarAdmissao,
    atualizarStatus,
    atualizarDocumento,
    atualizarWorkflow,
    excluirAdmissao,
    buscarAdmissao,
    uploadDocumento,
    isPending,
  } = useAdmissoes();

  const selectedAdmissao = selectedId ? buscarAdmissao(selectedId) : null;
  const isAdmin = hasMinimumRole('admin');
  const canManage = hasMinimumRole('manager');

  const handleView = (id: string) => {
    setSelectedId(id);
    setViewMode('detail');
  };

  const handleEdit = (id: string) => {
    if (!canManage) {
      toast.error('Você não tem permissão para editar admissões');
      return;
    }
    setSelectedId(id);
    setViewMode('edit');
  };

  const handleDelete = (id: string) => {
    if (!isAdmin) {
      toast.error('Você não tem permissão para excluir admissões');
      return;
    }
    setDeleteId(id);
  };

  const confirmDelete = async () => {
    if (deleteId) {
      try {
        await excluirAdmissao(deleteId);
        toast.success('Admissão excluída com sucesso');
        setDeleteId(null);
        if (selectedId === deleteId) {
          setSelectedId(null);
          setViewMode('list');
        }
      } catch (error: any) {
        toast.error(error.message || 'Erro ao excluir admissão');
      }
    }
  };


  const handleNew = () => {
    if (!canManage) {
      toast.error('Você não tem permissão para criar admissões');
      return;
    }
    setSelectedId(null);
    setViewMode('new');
  };

  const handleBack = () => {
    setSelectedId(null);
    setViewMode('list');
  };

  const handleSubmitForm = async (dados: {
    dadosPessoais: any;
    dadosContato: any;
    dadosProfissionais: any;
    dadosBancarios: any;
    exameAdmissional?: any;
    documentos?: { id: string; nome: string; tipo: string; obrigatorio: boolean; status: string }[];
    documentosComArquivo?: { documentoId: string; file: File; obrigatorio: boolean }[];
  }) => {
    try {
      // Convert old format to new format
      const formData: AdmissaoFormData = {
        nome_completo: dados.dadosPessoais.nomeCompleto,
        cpf: dados.dadosPessoais.cpf,
        rg: dados.dadosPessoais.rg,
        data_nascimento: dados.dadosPessoais.dataNascimento,
        estado_civil: dados.dadosPessoais.estadoCivil,
        genero: dados.dadosPessoais.genero,
        nacionalidade: dados.dadosPessoais.nacionalidade,
        naturalidade: dados.dadosPessoais.naturalidade,
        nome_mae: dados.dadosPessoais.nomeMae,
        nome_pai: dados.dadosPessoais.nomePai,
        email: dados.dadosContato.email,
        telefone: dados.dadosContato.telefone,
        celular: dados.dadosContato.celular,
        endereco: dados.dadosContato.endereco,
        numero: dados.dadosContato.numero,
        complemento: dados.dadosContato.complemento,
        bairro: dados.dadosContato.bairro,
        cidade: dados.dadosContato.cidade,
        estado: dados.dadosContato.estado,
        cep: dados.dadosContato.cep,
        cargo: dados.dadosProfissionais.cargo,
        departamento: dados.dadosProfissionais.departamento,
        filial: dados.dadosProfissionais.filial,
        data_admissao: dados.dadosProfissionais.dataAdmissao,
        tipo_contrato: dados.dadosProfissionais.tipoContrato,
        jornada_trabalho: dados.dadosProfissionais.jornadaTrabalho,
        salario: dados.dadosProfissionais.salario ? parseFloat(dados.dadosProfissionais.salario.replace(/[^\d,]/g, '').replace(',', '.')) : undefined,
        gestor_imediato: dados.dadosProfissionais.gestorImediato,
        centro_custo: dados.dadosProfissionais.centroCusto,
        cbo: dados.dadosProfissionais.cbo || undefined,
        banco: dados.dadosBancarios.banco,
        agencia: dados.dadosBancarios.agencia,
        conta: dados.dadosBancarios.conta,
        tipo_conta: dados.dadosBancarios.tipoConta,
        chave_pix: dados.dadosBancarios.chavePix,
        // Exame Admissional
        exame_admissional_data: dados.exameAdmissional?.dataExame || undefined,
        exame_admissional_validade: dados.exameAdmissional?.dataValidade || undefined,
        exame_admissional_resultado: dados.exameAdmissional?.resultado || undefined,
        exame_admissional_clinica: dados.exameAdmissional?.clinica || undefined,
        exame_admissional_medico: dados.exameAdmissional?.medico || undefined,
        exame_admissional_crm: dados.exameAdmissional?.crm || undefined,
        exame_admissional_observacoes: dados.exameAdmissional?.observacoes || undefined,
      };

      if (viewMode === 'new') {
        const novaAdmissao = await criarAdmissao(formData);
        toast.success('Admissão criada com sucesso!');
        setSelectedId(novaAdmissao.id);
        setViewMode('detail');

        if (dados.documentos?.length) {
          const docsPadraoPorChave = new Map(
            (novaAdmissao.documentos || []).map((doc) => [`${doc.nome}::${doc.tipo}`, doc])
          );

          const docsParaInserir = dados.documentos
            .filter((doc) => !docsPadraoPorChave.has(`${doc.nome}::${doc.tipo}`))
            .map((doc) => ({
              admissao_id: novaAdmissao.id,
              tenant_id: novaAdmissao.tenant_id,
              nome: doc.nome,
              tipo: doc.tipo,
              obrigatorio: doc.obrigatorio,
              status: 'pendente' as const,
            }));

          if (docsParaInserir.length) {
            const { error: insertDocsError } = await supabase
              .from('admissao_documentos')
              .insert(docsParaInserir);

            if (insertDocsError) throw insertDocsError;
          }

          const { data: syncedDocs, error: syncedDocsError } = await supabase
            .from('admissao_documentos')
            .select('id, nome, tipo')
            .eq('admissao_id', novaAdmissao.id)
            .order('created_at', { ascending: true });

          if (syncedDocsError) throw syncedDocsError;

          // Upload documentos que foram anexados no formulário
          if (dados.documentosComArquivo?.length && syncedDocs) {
            const syncedDocsByKey = new Map(
              syncedDocs.map((doc) => [`${doc.nome}::${doc.tipo}`, doc.id])
            );

            for (const docLocal of dados.documentosComArquivo) {
              const docMeta = dados.documentos.find((doc) => doc.id === docLocal.documentoId);
              if (!docMeta) continue;

              const realDocId = syncedDocsByKey.get(`${docMeta.nome}::${docMeta.tipo}`);
              if (!realDocId) continue;

              try {
                await uploadDocumento(novaAdmissao.id, realDocId, docLocal.file);
              } catch (err) {
                console.error('Erro ao enviar documento:', err);
              }
            }
          }
          
          // Criar processo no Hub Contábil
          try {
            const { data: { user } } = await supabase.auth.getUser();
            const tenantId = user?.app_metadata?.tenant_id;

            if (tenantId) {
              await (supabase as any).from('hub_processos').insert({
                tenant_id: tenantId,
                tipo: 'admissao',
                status: 'pendente',
                prioridade: 'normal',
                titulo: `Admissão: ${dados.dadosPessoais.nomeCompleto}`,
                colaborador_nome: dados.dadosPessoais.nomeCompleto,
                colaborador_cpf: dados.dadosPessoais.cpf,
                origem_modulo: 'admissao',
                origem_registro_id: novaAdmissao.id,
                data_referencia: new Date().toISOString().split('T')[0]
              });
            }
          } catch (hubErr) {
            console.error('Erro ao criar processo no Hub Contábil:', hubErr);
          }

          toast.success('Documentos enviados com sucesso!');
        }
      } else if (viewMode === 'edit' && selectedId) {
        await atualizarAdmissao({ id: selectedId, dados: formData });

        let documentosReaisPorLocalId = new Map<string, string>();
        if (dados.documentos?.length) {
          const { data: admissaoAtual, error: admissaoAtualError } = await supabase
            .from('admissoes')
            .select('tenant_id')
            .eq('id', selectedId)
            .single();

          if (admissaoAtualError) throw admissaoAtualError;

          // Documentos ja persistidos desta admissao. O indice unico e
          // (admissao_id, nome), entao a dedup e por NOME — evita reinserir um
          // documento que ja existe (criado no envio imediato, em outra sessao
          // ou que nao veio carregado no formulario) e estourar o unique.
          const { data: existentes } = await supabase
            .from('admissao_documentos')
            .select('id, nome')
            .eq('admissao_id', selectedId);
          const idPorNome = new Map<string, string>((existentes || []).map((d) => [d.nome, d.id]));

          const docsExistentesReais = dados.documentos.filter((doc) => !doc.id.startsWith('new-doc-'));
          docsExistentesReais.forEach((doc) => documentosReaisPorLocalId.set(doc.id, doc.id));

          const docsNovos = dados.documentos.filter((doc) => doc.id.startsWith('new-doc-'));
          const docsParaInserir = docsNovos
            .filter((doc) => !idPorNome.has(doc.nome))
            .map((doc) => ({
              admissao_id: selectedId,
              tenant_id: admissaoAtual.tenant_id,
              nome: doc.nome,
              tipo: doc.tipo,
              obrigatorio: doc.obrigatorio,
              status: 'pendente' as const,
            }));

          if (docsParaInserir.length) {
            const { data: insertedDocs, error: insertedDocsError } = await supabase
              .from('admissao_documentos')
              .insert(docsParaInserir)
              .select('id, nome');

            if (insertedDocsError) throw insertedDocsError;
            (insertedDocs || []).forEach((d) => idPorNome.set(d.nome, d.id));
          }

          // Todo doc local "new-doc-" aponta para o id real: recem-inserido ou
          // um que ja existia por nome.
          docsNovos.forEach((doc) => {
            const realId = idPorNome.get(doc.nome);
            if (realId) documentosReaisPorLocalId.set(doc.id, realId);
          });
        }

        if (dados.documentosComArquivo?.length) {
          for (const docLocal of dados.documentosComArquivo) {
            const realDocId = documentosReaisPorLocalId.get(docLocal.documentoId);
            if (!realDocId) continue;

            try {
              await uploadDocumento(selectedId, realDocId, docLocal.file);
            } catch (err) {
              console.error('Erro ao enviar documento:', err);
            }
          }
          toast.success('Documentos enviados com sucesso!');
        }

        toast.success('Admissão atualizada com sucesso!');
        setViewMode('detail');
      }
    } catch (error: any) {
      toast.error(error.message || 'Erro ao salvar admissão');
    }
  };

  const handleDocumentUpload = async (documentoId: string, file: File) => {
    if (selectedId) {
      try {
        await uploadDocumento(selectedId, documentoId, file);
        toast.success('Documento enviado com sucesso!');
      } catch (error: any) {
        toast.error(error.message || 'Erro ao enviar documento');
        throw error;
      }
    }
  };
  // Envio imediato (formulário em edição). Documentos do checklist padrão ainda
  // não persistidos chegam com id local "new-doc-N"; o banco espera um uuid, e
  // o UPDATE por esse id quebrava com "invalid input syntax for type uuid".
  // Aqui criamos a linha real (ou reaproveitamos a existente) antes de enviar e
  // devolvemos o uuid para o formulário trocar o id local.
  const handleDocumentUploadImmediate = async (
    documento: { id: string; nome: string; tipo: string; obrigatorio: boolean },
    file: File
  ): Promise<{ realId?: string } | void> => {
    if (!selectedId) return;
    try {
      let realId = documento.id;
      if (documento.id.startsWith('new-doc-')) {
        const { data: admissaoAtual, error: admissaoAtualError } = await supabase
          .from('admissoes').select('tenant_id').eq('id', selectedId).single();
        if (admissaoAtualError) throw admissaoAtualError;

        // Dedup pela chave real do indice unico: (admissao_id, nome). Filtrar
        // tambem por tipo deixaria passar um insert que colide com um nome ja
        // existente de tipo diferente.
        const { data: existente } = await supabase
          .from('admissao_documentos')
          .select('id')
          .eq('admissao_id', selectedId)
          .eq('nome', documento.nome)
          .maybeSingle();

        if (existente?.id) {
          realId = existente.id;
        } else {
          const { data: inserido, error: inseridoError } = await supabase
            .from('admissao_documentos')
            .insert({
              admissao_id: selectedId,
              tenant_id: admissaoAtual.tenant_id,
              nome: documento.nome,
              tipo: documento.tipo,
              obrigatorio: documento.obrigatorio,
              status: 'pendente' as const,
            })
            .select('id')
            .single();
          if (inseridoError) throw inseridoError;
          realId = inserido.id;
        }
      }
      await uploadDocumento(selectedId, realId, file);
      toast.success('Documento enviado com sucesso!');
      return { realId };
    } catch (error: any) {
      toast.error(error.message || 'Erro ao enviar documento');
      throw error;
    }
  };

  const handleDocumentRemove = async (documentoId: string) => {
    try {
      await atualizarDocumento({
        documentoId,
        dados: {
          arquivo_url: null,
          arquivo_nome: null,
          arquivo_tamanho: null,
          status: 'pendente',
          data_envio: null,
        },
      });
      toast.info('Documento removido');
    } catch (error: any) {
      toast.error(error.message || 'Erro ao remover documento');
      throw error;
    }
  };

  const handleDocumentApprove = async (documentoId: string) => {
    try {
      await atualizarDocumento({
        documentoId,
        dados: { status: 'aprovado' },
      });
      toast.success('Documento aprovado!');
    } catch (error: any) {
      toast.error(error.message || 'Erro ao aprovar documento');
    }
  };

  // Reabre um documento já aprovado para substituição (aprovação por engano
  // ou arquivo errado). Volta o status para 'enviado' — o arquivo atual
  // permanece até o admin subir o novo, então cancelar o seletor não deixa o
  // documento sem anexo. O upload do novo arquivo mantém o status 'enviado',
  // exigindo nova aprovação.
  const handleDocumentReplace = async (documentoId: string) => {
    try {
      await atualizarDocumento({
        documentoId,
        dados: { status: 'enviado', data_aprovacao: null, aprovado_por: null },
      });
      toast.info('Documento reaberto — envie o novo arquivo e aprove novamente.');
    } catch (error: any) {
      toast.error(error.message || 'Erro ao reabrir documento');
    }
  };

  const handleDocumentReject = async (documentoId: string, motivo: string) => {
    try {
      await atualizarDocumento({
        documentoId,
        dados: { status: 'rejeitado', observacao: motivo },
      });
      toast.error('Documento rejeitado');
    } catch (error: any) {
      toast.error(error.message || 'Erro ao rejeitar documento');
    }
  };

  const handleAprovarEtapa = async (etapaId: string, observacao?: string) => {
    if (selectedId) {
      try {
        await atualizarWorkflow({
          workflowId: etapaId,
          admissaoId: selectedId,
          aprovado: true,
          observacao,
        });
        toast.success('Etapa aprovada com sucesso!');
      } catch (error: any) {
        toast.error(error.message || 'Erro ao aprovar etapa');
      }
    }
  };

  const handleRejeitarEtapa = async (etapaId: string, observacao: string) => {
    if (selectedId) {
      try {
        await atualizarWorkflow({
          workflowId: etapaId,
          admissaoId: selectedId,
          aprovado: false,
          observacao,
        });
        toast.error('Etapa rejeitada');
      } catch (error: any) {
        toast.error(error.message || 'Erro ao rejeitar etapa');
      }
    }
  };

  // Show loading state
  if (authLoading || isLoading) {
    return (
      <div className="flex items-center justify-center min-h-[400px]">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    );
  }

  // Show error state
  if (error) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[400px] gap-4">
        <Alert variant="destructive" className="max-w-md">
          <AlertCircle className="h-4 w-4" />
          <AlertTitle>Erro ao carregar dados</AlertTitle>
          <AlertDescription>{error}</AlertDescription>
        </Alert>
        <Button onClick={() => window.location.reload()}>
          Tentar novamente
        </Button>
      </div>
    );
  }

  // Transform data for legacy components
  const admissoesFormatted = admissoes.map(a => ({
    id: a.id,
    dadosPessoais: {
      nomeCompleto: a.nome_completo,
      cpf: a.cpf,
      rg: a.rg || '',
      dataNascimento: a.data_nascimento || '',
      estadoCivil: a.estado_civil || '',
      genero: a.genero || '',
      nacionalidade: a.nacionalidade || '',
      naturalidade: a.naturalidade || '',
      nomeMae: a.nome_mae || '',
      nomePai: a.nome_pai || '',
    },
    dadosContato: {
      email: a.email,
      telefone: a.telefone || '',
      celular: a.celular || '',
      endereco: a.endereco || '',
      numero: a.numero || '',
      complemento: a.complemento || '',
      bairro: a.bairro || '',
      cidade: a.cidade || '',
      estado: a.estado || '',
      cep: a.cep || '',
    },
    dadosProfissionais: {
      cargo: a.cargo,
      departamento: a.departamento || '',
      filial: a.filial || '',
      dataAdmissao: a.data_admissao || '',
      tipoContrato: a.tipo_contrato || '',
      jornadaTrabalho: a.jornada_trabalho || '',
      salario: a.salario ? `R$ ${a.salario.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}` : '',
      gestorImediato: a.gestor_imediato || '',
      centroCusto: a.centro_custo || '',
      cbo: (a as any).cbo || '',
    },
    dadosBancarios: {
      banco: a.banco || '',
      agencia: a.agencia || '',
      conta: a.conta || '',
      tipoConta: a.tipo_conta || '',
      chavePix: a.chave_pix || '',
    },
    documentos: (a.documentos || []).map(d => ({
      id: d.id,
      nome: d.nome,
      tipo: d.tipo,
      obrigatorio: d.obrigatorio,
      status: d.status,
      arquivo_url: d.arquivo_url || undefined,
      arquivo_nome: d.arquivo_nome || undefined,
      urlPreview: d.arquivo_url || undefined,
      dataEnvio: d.data_envio ? new Date(d.data_envio) : undefined,
      observacao: d.observacao || undefined,
    })),
    status: a.status,
    historicoAprovacao: (a.workflow || []).map(w => ({
      id: w.id,
      etapa: w.etapa,
      status: w.status,
      responsavel: w.responsavel_nome || 'Pendente',
      dataAcao: w.data_acao ? new Date(w.data_acao) : undefined,
      observacao: w.observacao || undefined,
    })),
    dataCriacao: new Date(a.created_at),
    dataAtualizacao: new Date(a.updated_at),
    criadoPor: a.criado_por || '',
    onboardingToken: (a as any).onboarding_token || null,
  }));

  const selectedAdmissaoFormatted = selectedId 
    ? admissoesFormatted.find(a => a.id === selectedId) 
    : null;

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      className="space-y-6"
    >
      {/* Page Header - only show on list view */}
      {viewMode === 'list' && (
        <>
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-primary/10">
              <UserPlus className="h-6 w-6 text-primary" />
            </div>
            <div>
              <h1 className="text-2xl font-bold text-foreground">Admissão</h1>
              <p className="text-muted-foreground">
                Gerencie o processo de admissão de novos colaboradores
              </p>
            </div>
          </div>

          {/* Stats */}
          <AdmissaoStats admissoes={admissoesFormatted as any} />

          {/* List */}
          <AdmissaoList
            admissoes={admissoesFormatted as any}
            onView={handleView}
            onEdit={handleEdit}
            onDelete={handleDelete}
            onNew={handleNew}
            canApprove={isAdmin}
            onApprove={async (id) => {
              try {
                await atualizarStatus({ id, status: 'aprovado' });
                toast.success('Admissão aprovada com sucesso!');
              } catch (e: any) {
                toast.error(e.message || 'Erro ao aprovar admissão');
              }
            }}
          />
        </>
      )}

      {/* New/Edit Form */}
      {(viewMode === 'new' || viewMode === 'edit') && (
        <div>
          <div className="flex items-center gap-3 mb-6">
            <div className="p-2 rounded-lg bg-primary/10">
              <UserPlus className="h-6 w-6 text-primary" />
            </div>
            <div>
              <h1 className="text-2xl font-bold text-foreground">
                {viewMode === 'new' ? 'Nova Admissão' : 'Editar Admissão'}
              </h1>
              <p className="text-muted-foreground">
                {viewMode === 'new' 
                  ? 'Preencha os dados do novo colaborador' 
                  : 'Atualize os dados do colaborador'}
              </p>
            </div>
          </div>

          <AdmissaoForm
            onSubmit={handleSubmitForm}
            onCancel={handleBack}
            onDocumentUploadImmediate={viewMode === 'edit' ? handleDocumentUploadImmediate : undefined}
            onDocumentRemoveImmediate={viewMode === 'edit' ? handleDocumentRemove : undefined}
            initialData={selectedAdmissaoFormatted ? {
              dadosPessoais: selectedAdmissaoFormatted.dadosPessoais,
              dadosContato: selectedAdmissaoFormatted.dadosContato,
              dadosProfissionais: selectedAdmissaoFormatted.dadosProfissionais,
              dadosBancarios: selectedAdmissaoFormatted.dadosBancarios,
            } : undefined}
          />
        </div>
      )}

      {/* Detail View */}
      {viewMode === 'detail' && selectedAdmissaoFormatted && (
        <AdmissaoDetail
          admissao={selectedAdmissaoFormatted as any}
          onBack={handleBack}
          onEdit={() => setViewMode('edit')}
          onDelete={() => handleDelete(selectedAdmissaoFormatted.id)}
          onDocumentUpload={handleDocumentUpload}
          onDocumentRemove={handleDocumentRemove}
          onDocumentApprove={handleDocumentApprove}
          onDocumentReject={handleDocumentReject}
          onDocumentReplace={handleDocumentReplace}
          onAprovarEtapa={handleAprovarEtapa}
          onRejeitarEtapa={handleRejeitarEtapa}
          isAdmin={isAdmin}
        />
      )}

      {/* Delete Confirmation Dialog */}
      <AlertDialog open={!!deleteId} onOpenChange={() => setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Confirmar exclusão</AlertDialogTitle>
            <AlertDialogDescription>
              Tem certeza que deseja excluir esta admissão? Esta ação não pode ser desfeita.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isPending}>Cancelar</AlertDialogCancel>
            <AlertDialogAction 
              onClick={confirmDelete} 
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
              disabled={isPending}
            >
              {isPending ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
              Excluir
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

    </motion.div>
  );
}
