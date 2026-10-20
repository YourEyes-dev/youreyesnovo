import { useState, useEffect, useRef } from 'react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Loader2, Building2, Save, Shield, Users, TrendingUp, Clock, Target, Upload, ArrowLeft, Layers, Brain, ClipboardCheck, ImageIcon } from 'lucide-react';
import { useEmpresaCadastro } from '@/hooks/useEmpresaCadastro';
import { EmpresaDadosBasicos } from '@/components/empresa/EmpresaDadosBasicos';
import { EmpresaEnquadramentoLegal } from '@/components/empresa/EmpresaEnquadramentoLegal';
import { EmpresaObrigacoesInclusao } from '@/components/empresa/EmpresaObrigacoesInclusao';
import { EmpresaIndicadores } from '@/components/empresa/EmpresaIndicadores';
import { EmpresaJornadaCondicoes } from '@/components/empresa/EmpresaJornadaCondicoes';
import { EmpresaFeriadoTabelaField } from '@/components/empresa/EmpresaFeriadoTabelaField';

import { EmpresaObrigacoesTab } from '@/components/empresa/EmpresaObrigacoesTab';
import { EmpresaImportExport } from '@/components/empresa/EmpresaImportExport';
import { EmpresaList } from '@/components/empresa/EmpresaList';
import { EmpresaAIContext } from '@/components/empresa/EmpresaAIContext';
import { EmpresaCadastroChecklist } from '@/components/empresa/EmpresaCadastroChecklist';
import { EmpresaLogoTab } from '@/components/configuracoes/EmpresaLogoTab';
import { GruposEconomicosManager } from '@/components/empresa/GruposEconomicosManager';
import { useGruposEconomicos } from '@/hooks/useGruposEconomicos';
import { useAuth } from '@/hooks/useAuth';
import type { EmpresaCadastro } from '@/types/empresa';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';

type ViewMode = 'list' | 'edit' | 'new';

const NAV_STATE_KEY = 'empresa-nav-state:v1';

export default function Empresa() {
  // Restaura viewMode/selectedEmpresaId/activeTab da última visita
  const restoredNav = (() => {
    try {
      const raw = sessionStorage.getItem(NAV_STATE_KEY);
      if (raw) return JSON.parse(raw) as { viewMode: ViewMode; selectedEmpresaId: string | null; activeTab: string };
    } catch { /* ignore */ }
    return null;
  })();

  const [viewMode, setViewMode] = useState<ViewMode>(restoredNav?.viewMode || 'list');
  const [selectedEmpresaId, setSelectedEmpresaId] = useState<string | null>(restoredNav?.selectedEmpresaId || null);
  const [activeTab, setActiveTab] = useState(restoredNav?.activeTab || 'dados');
  const { user, profile } = useAuth();

  // Persiste o estado de navegação para que voltar à página restaure a empresa em edição e a aba atual
  useEffect(() => {
    try {
      sessionStorage.setItem(NAV_STATE_KEY, JSON.stringify({ viewMode, selectedEmpresaId, activeTab }));
    } catch { /* ignore */ }
  }, [viewMode, selectedEmpresaId, activeTab]);

  const TABS = ['dados', 'logo', 'enquadramento', 'inclusao', 'indicadores', 'jornada', 'obrigacoes', 'ai', 'checklist'];
  const currentTabIndex = TABS.indexOf(activeTab);
  const isFirstTab = currentTabIndex === 0;
  const isLastTab = currentTabIndex === TABS.length - 1;

  const handleNextTab = () => { if (!isLastTab) setActiveTab(TABS[currentTabIndex + 1]); };
  const handlePrevTab = () => { if (!isFirstTab) setActiveTab(TABS[currentTabIndex - 1]); };

  const {
    empresas,
    isLoadingList,
    cadastro,
    isLoading,
    upsertCadastro,
    toggleAtivoEmpresa,
    deleteEmpresa,
    cliente,
    obrigacoes,
  } = useEmpresaCadastro(viewMode === 'edit' ? selectedEmpresaId : undefined);

  const { grupos } = useGruposEconomicos();

  // Matrizes for filial selector
  const matrizes = empresas
    .filter(e => e.ativo && (e as any).tipo_unidade !== 'filial')
    .map(e => ({
      id: e.id,
      razao_social: e.razao_social,
      cnpj: e.cnpj,
      grupo_economico_id: (e as any).grupo_economico_id,
    }));

  const [formData, setFormData] = useState<Partial<EmpresaCadastro>>({});
  const [hasChanges, setHasChanges] = useState(false);
  const [rascunhoRestaurado, setRascunhoRestaurado] = useState(false);
  const savingRef = useRef(false);
  const createdIdRef = useRef<string | null>(null);

  // Chave do rascunho — isolada por usuário e por empresa (ou "new")
  const draftKey = user?.id
    ? `empresa-draft:${user.id}:${selectedEmpresaId || 'new'}`
    : null;

  useEffect(() => {
    const docClean = cliente?.cnpj?.replace(/\D/g, '') || '';
    const onboardingIsCnpj = docClean.length === 14;
    const onboardingIsCpf = docClean.length === 11;

    // Tenta restaurar rascunho local primeiro
    const tryLoadDraft = (): Partial<EmpresaCadastro> | null => {
      if (!draftKey) return null;
      try {
        const raw = localStorage.getItem(draftKey);
        if (!raw) return null;
        const parsed = JSON.parse(raw);
        if (parsed && typeof parsed === 'object' && parsed.data) {
          return parsed.data as Partial<EmpresaCadastro>;
        }
      } catch {
        /* ignore */
      }
      return null;
    };

    if (viewMode === 'edit' && cadastro) {
      const base: Partial<EmpresaCadastro> = {
        ...cadastro,
        razao_social: cadastro.razao_social || cliente?.nome_empresa || '',
        cnpj: (cadastro.cnpj || (onboardingIsCnpj ? cliente?.cnpj : '') || '').replace(/\D/g, ''),
        cpf: (cadastro.cpf || (onboardingIsCpf ? cliente?.cnpj : '') || '').replace(/\D/g, ''),
        email: cadastro.email || cliente?.poc_email || user?.email || '',
        telefone: cadastro.telefone || cliente?.poc_telefone || profile?.telefone || '',
        total_colaboradores: cadastro.total_colaboradores || cliente?.quantidade_colaboradores || 0,
        tipo_pessoa: cadastro.tipo_pessoa || (onboardingIsCpf ? 'pf' : 'pj'),
        endereco: cadastro.endereco || cliente?.endereco || '',
      };
      const draft = tryLoadDraft();
      if (draft && !rascunhoRestaurado) {
        setFormData({ ...base, ...draft });
        setRascunhoRestaurado(true);
        // Toast removido para evitar confusão se o usuário acabou de salvar
      } else if (!rascunhoRestaurado) {
        setFormData(base);
      }
    }

    if (viewMode === 'new') {
      const base: Partial<EmpresaCadastro> = cliente
        ? {
            razao_social: cliente.nome_empresa || '',
            cnpj: (onboardingIsCnpj ? cliente.cnpj : '').replace(/\D/g, ''),
            cpf: (onboardingIsCpf ? cliente.cnpj : '').replace(/\D/g, ''),
            email: cliente.poc_email || user?.email || '',
            telefone: cliente.poc_telefone || profile?.telefone || '',
            total_colaboradores: cliente.quantidade_colaboradores || 0,
            tipo_pessoa: onboardingIsCpf ? 'pf' : 'pj',
            endereco: cliente.endereco || '',
          }
        : {
            // Campos devem vir vazios para novo cadastro manual
            email: '',
            telefone: '',
          };
      const draft = tryLoadDraft();
      if (draft && !rascunhoRestaurado) {
        setFormData({ ...base, ...draft });
        setRascunhoRestaurado(true);
      } else if (!rascunhoRestaurado) {
        setFormData(base);
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cadastro, viewMode, cliente, user, profile, selectedEmpresaId]);

  // Salva o rascunho local sempre que houver conteúdo significativo no formulário.
  // Não depende mais de hasChanges — assim, mesmo dados restaurados continuam persistidos
  // e mudanças vindas de efeitos internos (ex.: auto-cálculo PCD) também são guardadas.
  useEffect(() => {
    if (viewMode === 'list') return;
    if (!draftKey) return;
    // Só persiste se houver algo relevante (evita gravar objeto vazio)
    const temConteudo = formData && Object.keys(formData).some((k) => {
      const v = (formData as any)[k];
      return v !== undefined && v !== null && v !== '' && v !== 0 && v !== false;
    });
    if (!temConteudo) return;
    const t = setTimeout(() => {
      try {
        localStorage.setItem(draftKey, JSON.stringify({ data: formData, ts: Date.now() }));
      } catch { /* ignore */ }
    }, 300);
    return () => clearTimeout(t);
  }, [formData, viewMode, draftKey]);

  // Flush síncrono ao desmontar ou trocar de aba do navegador — garante que nada se perca
  useEffect(() => {
    const flush = () => {
      if (viewMode === 'list' || !draftKey) return;
      try {
        localStorage.setItem(draftKey, JSON.stringify({ data: formData, ts: Date.now() }));
      } catch { /* ignore */ }
    };
    window.addEventListener('beforeunload', flush);
    window.addEventListener('pagehide', flush);
    return () => {
      flush();
      window.removeEventListener('beforeunload', flush);
      window.removeEventListener('pagehide', flush);
    };
  }, [formData, viewMode, draftKey]);

  const clearDraft = () => {
    if (draftKey) {
      try { localStorage.removeItem(draftKey); } catch { /* ignore */ }
    }
  };

  const handleChange = (updates: Partial<EmpresaCadastro>) => {
    setFormData((prev) => ({ ...prev, ...updates }));
    setHasChanges(true);
  };

  const handleSave = async () => {
    // Trava de re-entrância: evita inserts duplicados em duplo-clique / re-render
    if (savingRef.current || upsertCadastro.isPending) return;

    // Validações mínimas antes de qualquer gravação
    const razao = (formData.razao_social || '').trim();
    if (!razao) {
      toast.error('Informe a Razão Social / Nome antes de salvar.');
      return;
    }
    const tipo = formData.tipo_pessoa || 'pj';
    if (tipo === 'pj' && (!formData.cnpj || !formData.cnpj.trim())) {
      toast.error('O CNPJ é obrigatório para Pessoa Jurídica.');
      return;
    }
    if (tipo === 'pf' && (!formData.cpf || !formData.cpf.trim())) {
      toast.error('O CPF é obrigatório para Pessoa Física.');
      return;
    }

    // Se já criamos nessa sessão (createdIdRef), força update em vez de novo insert
    // A logo é gravada na hora pela aba Logo; o formulário nunca a regrava, senão
    // um valor velho (cadastro carregado ou rascunho) desfaria um envio recente.
    const { logo_url: _logoFora, ...formSemLogo } = formData;
    const payload: Partial<EmpresaCadastro> = createdIdRef.current && !selectedEmpresaId
      ? { ...formSemLogo, id: createdIdRef.current as any }
      : formSemLogo;

    savingRef.current = true;
    try {
      const saved: any = await upsertCadastro.mutateAsync(payload);
      clearDraft();
      setHasChanges(false);
      setRascunhoRestaurado(false);
      if (viewMode === 'new' && saved?.id) {
        createdIdRef.current = saved.id;
        setSelectedEmpresaId(saved.id);
        setViewMode('edit');
      }
      toast.success('Alterações salvas com sucesso!');
    } catch (error: any) {
      toast.error('Erro ao salvar: ' + (error?.message || 'Erro desconhecido'));
    } finally {
      savingRef.current = false;
    }
  };

  const handleEdit = (id: string) => {
    createdIdRef.current = null;
    setSelectedEmpresaId(id);
    setViewMode('edit');
    setHasChanges(false);
    setRascunhoRestaurado(false);
  };

  const handleNew = () => {
    createdIdRef.current = null;
    setSelectedEmpresaId(null);
    setFormData({
      email: '',
      telefone: '',
    });
    setViewMode('new');
    setHasChanges(false);
    setRascunhoRestaurado(false);
    
    // Clear draft when starting a brand new registration to avoid restoring 
    // data from a previous "new" registration that wasn't properly cleaned up
    const newDraftKey = user?.id ? `empresa-draft:${user.id}:new` : null;
    if (newDraftKey) {
      try {
        localStorage.removeItem(newDraftKey);
      } catch { /* ignore */ }
    }
  };

  const handleToggleAtivo = (id: string, ativo: boolean) => {
    toggleAtivoEmpresa.mutate({ id, ativo }, {
      onSuccess: () => toast.success(ativo ? 'Empresa ativada' : 'Empresa inativada'),
      onError: (err: Error) => toast.error('Erro: ' + err.message),
    });
  };

  const handleDeleteEmpresa = async (id: string, nome: string) => {
    const { confirm } = await import('@/components/ui/confirm-dialog');
    const ok = await confirm({
      title: 'Excluir Empresa?',
      description: `Tem certeza que deseja excluir a empresa "${nome}"?`,
      confirmLabel: 'Excluir',
      cancelLabel: 'Cancelar',
      variant: 'destructive',
      requiredWord: 'EXCLUIR',
    });
    if (!ok) return;
    deleteEmpresa.mutate(id, {
      onSuccess: () => toast.success(`Empresa "${nome}" excluída.`),
      onError: (err: Error) => toast.error(err.message || 'Não foi possível excluir.'),
    });
  };

  const handleDescartarRascunho = () => {
    clearDraft();
    setRascunhoRestaurado(false);
    setHasChanges(false);
    toast.success('Rascunho descartado.');
    // força recarregar dados base
    if (viewMode === 'edit' && selectedEmpresaId) {
      const id = selectedEmpresaId;
      setSelectedEmpresaId(null);
      setTimeout(() => setSelectedEmpresaId(id), 0);
    } else {
      setFormData({});
    }
  };

  const handleBack = () => {
    createdIdRef.current = null;
    setViewMode('list');
    setSelectedEmpresaId(null);
    setActiveTab('dados');
    setHasChanges(false);
    setRascunhoRestaurado(false);
    try { sessionStorage.removeItem(NAV_STATE_KEY); } catch { /* ignore */ }
  };

  // LIST VIEW
  if (viewMode === 'list') {
    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <Building2 className="w-7 h-7 text-primary" />
            Empresas
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            Gerencie o cadastro de todas as empresas do grupo
          </p>
        </div>

        <div className="bg-primary/5 border border-primary/20 rounded-lg p-4 flex items-start gap-3">
          <div className="bg-primary/10 rounded-full p-2 mt-0.5 shrink-0">
            <Building2 className="w-5 h-5 text-primary" />
          </div>
          <div>
            <p className="text-sm font-medium text-foreground">
              Sistema Multiempresa
            </p>
            <p className="text-sm text-muted-foreground mt-1">
              Aqui você visualiza e gerencia todas as empresas cadastradas no sistema. 
              O YourEyes é <strong>multiempresa</strong> — você pode cadastrar quantas empresas precisar 
              (matrizes, filiais e estabelecimentos) e alternar entre elas pelo seletor no cabeçalho.
            </p>
          </div>
        </div>
        <EmpresaList
          empresas={empresas}
          isLoading={isLoadingList}
          onEdit={handleEdit}
          onNew={handleNew}
          onToggleAtivo={handleToggleAtivo}
          onDelete={handleDeleteEmpresa}
          onBatchDelete={async (items) => {
            const failed: { nome: string; error: string }[] = [];
            let ok = 0;
            for (const it of items) {
              try {
                await deleteEmpresa.mutateAsync(it.id);
                ok++;
              } catch (e: any) {
                failed.push({ nome: it.nome, error: e?.message || 'Erro desconhecido' });
              }
            }
            return { ok, failed };
          }}
          grupos={grupos}
          obrigacoes={obrigacoes}
        />
      </div>
    );
  }


  // EDIT/NEW VIEW
  const isFormLoading = viewMode === 'edit' && isLoading;

  if (isFormLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="w-8 h-8 animate-spin text-primary" />
      </div>
    );
  }

  const _tipoPessoa = formData.tipo_pessoa || 'pj';
  const camposMinimosOk = !!(formData.razao_social || '').trim() &&
    ((_tipoPessoa === 'pj' && !!(formData.cnpj || '').trim()) ||
     (_tipoPessoa === 'pf' && !!(formData.cpf || '').trim()));

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" onClick={handleBack} data-testid="btn-voltar-empresa">
            <ArrowLeft className="w-5 h-5" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
              <Building2 className="w-7 h-7 text-primary" />
              {viewMode === 'new' ? 'Nova Empresa' : 'Editar Empresa'}
            </h1>
            <p className="text-sm text-muted-foreground mt-1">
              {viewMode === 'new'
                ? 'Preencha os dados para cadastrar uma nova empresa'
                : formData.razao_social || 'Cadastro da Empresa'}
            </p>
          </div>
        </div>
        <Button
          onClick={handleSave}
          disabled={!hasChanges || upsertCadastro.isPending || !camposMinimosOk}
          title={!camposMinimosOk ? 'Preencha Razão Social/Nome e CNPJ ou CPF para salvar.' : ''}
        >
          {upsertCadastro.isPending ? (
            <Loader2 className="w-4 h-4 mr-2 animate-spin" />
          ) : (
            <Save className="w-4 h-4 mr-2" />
          )}
          Salvar
        </Button>
      </div>

      {/* Aviso de salvamento manual */}
      <div className={`rounded-lg border px-4 py-2 flex items-center justify-between gap-3 ${hasChanges || rascunhoRestaurado ? 'border-amber-500/30 bg-amber-500/5' : 'border-primary/20 bg-primary/5'}`}>
        <p className="text-xs text-muted-foreground">
          {upsertCadastro.isPending ? (
            <span className="flex items-center gap-1.5">
              <Loader2 className="w-3 h-3 animate-spin text-primary" />
              Salvando alterações...
            </span>
          ) : (hasChanges || rascunhoRestaurado) ? (
            <span>⚠️ Você tem alterações não salvas ou rascunho restaurado. Clique em <strong>Salvar</strong> para gravar no banco de dados.</span>
          ) : (
            <span>✅ Tudo salvo no banco de dados.</span>
          )}
        </p>
      </div>

      {/* Tabs */}
      <Tabs value={activeTab} onValueChange={setActiveTab} className="w-full">
        <TabsList className="grid w-full grid-cols-4 md:grid-cols-9">
          <TabsTrigger value="dados" className="text-xs" data-testid="tab-dados">
            <Building2 className="w-3.5 h-3.5 mr-1 hidden sm:inline" />
            Dados
          </TabsTrigger>
          <TabsTrigger value="logo" className="text-xs" data-testid="tab-logo">
            <ImageIcon className="w-3.5 h-3.5 mr-1 hidden sm:inline" />
            Logo
          </TabsTrigger>
          <TabsTrigger value="enquadramento" className="text-xs" data-testid="tab-enquadramento">
            <Shield className="w-3.5 h-3.5 mr-1 hidden sm:inline" />
            Enquadramento
          </TabsTrigger>
          <TabsTrigger value="inclusao" className="text-xs">
            <Users className="w-3.5 h-3.5 mr-1 hidden sm:inline" />
            Inclusão
          </TabsTrigger>
          <TabsTrigger value="indicadores" className="text-xs">
            <TrendingUp className="w-3.5 h-3.5 mr-1 hidden sm:inline" />
            Indicadores
          </TabsTrigger>
          <TabsTrigger value="jornada" className="text-xs">
            <Clock className="w-3.5 h-3.5 mr-1 hidden sm:inline" />
            Jornada
          </TabsTrigger>
          <TabsTrigger value="obrigacoes" className="text-xs">
            <Target className="w-3.5 h-3.5 mr-1 hidden sm:inline" />
            Obrigações
          </TabsTrigger>
          <TabsTrigger value="ai" className="text-xs">
            <Brain className="w-3.5 h-3.5 mr-1 hidden sm:inline" />
            Contexto I.A.
          </TabsTrigger>
          <TabsTrigger value="checklist" className="text-xs" data-testid="tab-checklist">
            <ClipboardCheck className="w-3.5 h-3.5 mr-1 hidden sm:inline" />
            Checklist
          </TabsTrigger>
        </TabsList>

        <Card className="mt-4">
          <TabsContent value="dados" className="mt-0">
            <CardHeader>
              <CardTitle className="text-lg">Dados Básicos da Empresa</CardTitle>
              <CardDescription>Informações de identificação e localização</CardDescription>
            </CardHeader>
            <CardContent>
              <EmpresaDadosBasicos
                data={formData}
                onChange={handleChange}
                matrizes={matrizes}
                currentEmpresaId={viewMode === 'edit' ? selectedEmpresaId : undefined}
              />
            </CardContent>
          </TabsContent>

          <TabsContent value="logo" className="mt-0" data-testid="conteudo-logo">
            <CardHeader>
              <CardTitle className="text-lg">Logo da Empresa</CardTitle>
              <CardDescription>Identidade visual usada nos documentos gerados (PDF, relatórios, laudos)</CardDescription>
            </CardHeader>
            <CardContent>
              <EmpresaLogoTab
                empresaId={viewMode === 'edit' ? (cadastro?.id ?? selectedEmpresaId) : null}
                logoUrl={formData.logo_url ?? cadastro?.logo_url}
                onChange={(url) => setFormData((prev) => ({ ...prev, logo_url: url }))}
              />
            </CardContent>
          </TabsContent>

          <TabsContent value="enquadramento" className="mt-0">
            <CardHeader>
              <CardTitle className="text-lg">Enquadramento Legal</CardTitle>
              <CardDescription>CNAE, Grau de Risco, SESMT e CIPA</CardDescription>
            </CardHeader>
            <CardContent>
              <EmpresaEnquadramentoLegal data={formData} onChange={handleChange} />
            </CardContent>
          </TabsContent>

          <TabsContent value="inclusao" className="mt-0">
            <CardHeader>
              <CardTitle className="text-lg">Obrigações de Inclusão</CardTitle>
              <CardDescription>Cotas PCD e Jovem Aprendiz</CardDescription>
            </CardHeader>
            <CardContent>
              <EmpresaObrigacoesInclusao data={formData} onChange={handleChange} />
            </CardContent>
          </TabsContent>

          <TabsContent value="indicadores" className="mt-0">
            <CardHeader>
              <CardTitle className="text-lg">Indicadores Previdenciários</CardTitle>
              <CardDescription>FAP e TAC</CardDescription>
            </CardHeader>
            <CardContent>
              <EmpresaIndicadores data={formData} onChange={handleChange} />
            </CardContent>
          </TabsContent>

          <TabsContent value="jornada" className="mt-0">
            <CardHeader>
              <CardTitle className="text-lg">Jornada e Condições Especiais</CardTitle>
              <CardDescription>Turnos, escalas e condições especiais de trabalho</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <EmpresaJornadaCondicoes data={formData} onChange={handleChange} />
              <EmpresaFeriadoTabelaField
                empresaId={viewMode === 'edit' ? (cadastro?.id ?? null) : null}
                cidade={formData.cidade}
                uf={formData.estado}
              />
            </CardContent>

          </TabsContent>

          <TabsContent value="obrigacoes" className="mt-0">
            <CardHeader>
              <CardTitle className="text-lg">Obrigações Detectadas</CardTitle>
              <CardDescription>
                Obrigações legais identificadas automaticamente a partir do cadastro
              </CardDescription>
            </CardHeader>
            <CardContent>
              <EmpresaObrigacoesTab 
                cadastro={viewMode === 'edit' ? cadastro : null} 
                onTabChange={setActiveTab}
              />
            </CardContent>
          </TabsContent>

          <TabsContent value="ai" className="mt-0">
            <CardHeader>
              <CardTitle className="text-lg">Contexto para Inteligência Artificial</CardTitle>
              <CardDescription>
                Configure as informações que guiarão a I.A. nas sugestões para esta empresa
              </CardDescription>
            </CardHeader>
            <CardContent>
              <EmpresaAIContext data={formData} onChange={handleChange} />
            </CardContent>
          </TabsContent>

          <TabsContent value="checklist" className="mt-0">
            <CardHeader>
              <CardTitle className="text-lg">Checklist do Cadastro</CardTitle>
              <CardDescription>
                Acompanhe o que ainda falta preencher — destaque para os campos obrigatórios pendentes.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <EmpresaCadastroChecklist data={formData} onGoToTab={setActiveTab} />
            </CardContent>
          </TabsContent>

        </Card>
        {/* Bottom navigation */}
        <div className="flex items-center justify-between pt-2">
          <Button
            variant="outline"
            onClick={handlePrevTab}
            disabled={isFirstTab}
            className="gap-2"
          >
            ← Anterior
          </Button>
          <div className="flex items-center gap-2">
            {!isLastTab ? (
              <Button variant="outline" onClick={handleNextTab} className="gap-2">
                Próxima aba →
              </Button>
            ) : null}
            <Button
              onClick={handleSave}
              disabled={!hasChanges || upsertCadastro.isPending || !camposMinimosOk}
              title={!camposMinimosOk ? 'Preencha Razão Social/Nome e CNPJ ou CPF para salvar.' : ''}
              className="gap-2"
            >
              {upsertCadastro.isPending ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <Save className="w-4 h-4" />
              )}
              Salvar
            </Button>
          </div>
        </div>
      </Tabs>
    </div>
  );
}
