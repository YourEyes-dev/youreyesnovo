import { useState, useEffect, useRef, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { toast } from 'sonner';
import { useDepartamentos, useFiliais } from '@/hooks/useCadastros';
import { useEmpresaAtiva } from '@/contexts/EmpresaAtivaContext';
import { GestorComboboxField } from '@/components/colaboradores/GestorComboboxField';
import { CBOAutocomplete } from '@/components/cbo/CBOAutocomplete';
import { motion, AnimatePresence } from 'framer-motion';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { 
  User, 
  MapPin, 
  Briefcase, 
  CreditCard, 
  FileText, 
  ChevronLeft, 
  ChevronRight,
  Save,
  Send,
  Stethoscope,
  Cloud,
  CloudOff,
  Loader2 as Loader2Icon,
  CheckCircle2,
  AlertCircle,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { CpfInput } from '@/components/ui/cpf-input';
import { PhoneInput } from '@/components/ui/phone-input';
import { CepInput } from '@/components/ui/cep-input';
import { EnderecoData } from '@/lib/viacep';
import { AdmissaoFormSteps } from './AdmissaoFormSteps';
import { DocumentUpload } from './DocumentUpload';
import { 
  DadosPessoais, 
  DadosContato, 
  DadosProfissionais, 
  DadosBancarios,
  DocumentoAdmissao,
  DOCUMENTOS_OBRIGATORIOS
} from '@/types/admissao';
import { cn } from '@/lib/utils';
import { validateCpf, cleanCpf } from '@/lib/cpf';

import {
  STEPS,
  dadosPessoaisSchema,
  dadosContatoSchema,
  dadosProfissionaisSchema,
  dadosBancariosSchema,
  exameAdmissionalSchema,
  type DadosExameAdmissional,
  type UsuarioEncontrado,
  type AutoSaveStatus,
} from './admissao-form/schemas';


interface AdmissaoFormProps {
  onSubmit: (dados: {
    dadosPessoais: DadosPessoais;
    dadosContato: DadosContato;
    dadosProfissionais: DadosProfissionais;
    dadosBancarios: DadosBancarios;
    exameAdmissional?: DadosExameAdmissional;
    documentos?: DocumentoAdmissao[];
    documentosComArquivo?: { documentoId: string; file: File; obrigatorio: boolean }[];
  }) => void;
  onCancel: () => void;
  onAutoSave?: (dados: {
    dadosPessoais: Partial<DadosPessoais>;
    dadosContato: Partial<DadosContato>;
    dadosProfissionais: Partial<DadosProfissionais>;
    dadosBancarios: Partial<DadosBancarios>;
    exameAdmissional?: Partial<DadosExameAdmissional>;
  }) => Promise<void>;
  onDocumentUploadImmediate?: (documento: DocumentoAdmissao, file: File) => Promise<{ realId?: string } | void>;
  onDocumentRemoveImmediate?: (documentoId: string) => Promise<void>;
  initialData?: {
    dadosPessoais?: Partial<DadosPessoais>;
    dadosContato?: Partial<DadosContato>;
    dadosProfissionais?: Partial<DadosProfissionais>;
    dadosBancarios?: Partial<DadosBancarios>;
    exameAdmissional?: Partial<DadosExameAdmissional>;
    documentos?: Array<Partial<DocumentoAdmissao> & { id: string; nome: string; tipo: string; obrigatorio: boolean; status: any }>;
  };
}


export function AdmissaoForm({ onSubmit, onCancel, onAutoSave, onDocumentUploadImmediate, onDocumentRemoveImmediate, initialData }: AdmissaoFormProps) {
  const [currentStep, setCurrentStep] = useState(1);
  const { departamentos } = useDepartamentos();
  const { filiais } = useFiliais();
  const { empresaAtivaId } = useEmpresaAtiva();
  const { tenantId } = useAuth();
  const [buscandoCpf, setBuscandoCpf] = useState(false);
  const [usuarioEncontrado, setUsuarioEncontrado] = useState<UsuarioEncontrado | null>(null);
  const [dadosReaproveitados, setDadosReaproveitados] = useState(false);

  const departamentosOptions = departamentos.filter(
    (d) => typeof d?.nome === 'string' && d.nome.trim().length > 0,
  );
  const estabelecimentosOptions = filiais.filter(
    (f) => typeof f?.nome === 'string' && f.nome.trim().length > 0 &&
      (!empresaAtivaId || f.empresa_id === empresaAtivaId),
  );
  const [documentos, setDocumentos] = useState<DocumentoAdmissao[]>(
    initialData?.documentos && initialData.documentos.length > 0
      ? (initialData.documentos as DocumentoAdmissao[])
      : DOCUMENTOS_OBRIGATORIOS.map((doc, index) => ({
          ...doc,
          id: `new-doc-${index}`,
          status: 'pendente',
        }))
  );

  // Form for step 1 - Dados Pessoais
  const formPessoais = useForm<DadosPessoais>({
    resolver: zodResolver(dadosPessoaisSchema),
    defaultValues: initialData?.dadosPessoais || {
      nomeCompleto: '',
      cpf: '',
      rg: '',
      dataNascimento: '',
      estadoCivil: '',
      genero: '',
      nacionalidade: 'Brasileira',
      naturalidade: '',
      nomeMae: '',
      nomePai: '',
    },
  });

  // Form for step 2 - Dados de Contato
  const formContato = useForm<DadosContato>({
    resolver: zodResolver(dadosContatoSchema),
    defaultValues: initialData?.dadosContato || {
      email: '',
      telefone: '',
      celular: '',
      endereco: '',
      numero: '',
      complemento: '',
      bairro: '',
      cidade: '',
      estado: '',
      cep: '',
    },
  });

  // Form for step 3 - Dados Profissionais
  const defaultProfissionais = {
    cargo: '',
    departamento: '',
    filial: '',
    dataAdmissao: '',
    tipoContrato: 'CLT',
    jornadaTrabalho: '44h semanais',
    salario: '',
    gestorImediato: '',
    centroCusto: '',
    cbo: '',
  };
  const formProfissionais = useForm<DadosProfissionais>({
    resolver: zodResolver(dadosProfissionaisSchema),
    defaultValues: initialData?.dadosProfissionais ? {
      ...defaultProfissionais,
      ...initialData.dadosProfissionais,
      // Ensure Select fields don't have empty strings
      tipoContrato: initialData.dadosProfissionais.tipoContrato || 'CLT',
      jornadaTrabalho: initialData.dadosProfissionais.jornadaTrabalho || '44h semanais',
    } : defaultProfissionais,
  });

  // Form for step 4 - Dados Bancários
  // Form for step 4 - Dados Bancários
  const defaultBancarios = {
    banco: '',
    agencia: '',
    conta: '',
    tipoConta: 'corrente',
    chavePix: '',
  };
  const formBancarios = useForm<DadosBancarios>({
    resolver: zodResolver(dadosBancariosSchema),
    defaultValues: initialData?.dadosBancarios ? {
      ...defaultBancarios,
      ...initialData.dadosBancarios,
      tipoConta: initialData.dadosBancarios.tipoConta || 'corrente',
    } : defaultBancarios,
  });

  // Form for step 5 - Exame Admissional
  const formExame = useForm<DadosExameAdmissional>({
    resolver: zodResolver(exameAdmissionalSchema),
    defaultValues: initialData?.exameAdmissional || {
      dataExame: '',
      dataValidade: '',
      resultado: '',
      clinica: '',
      medico: '',
      crm: '',
      observacoes: '',
    },
  });

  // ===== AUTO-SAVE LOGIC =====
  const [autoSaveStatus, setAutoSaveStatus] = useState<AutoSaveStatus>('idle');
  const autoSaveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastSavedRef = useRef<string>('');
  const hasUserInteracted = useRef(false);
  const mountedRef = useRef(false);

  const getAllFormData = useCallback(() => ({
    dadosPessoais: formPessoais.getValues(),
    dadosContato: formContato.getValues(),
    dadosProfissionais: formProfissionais.getValues(),
    dadosBancarios: formBancarios.getValues(),
    exameAdmissional: formExame.getValues(),
  }), [formPessoais, formContato, formProfissionais, formBancarios, formExame]);

  // Initialize lastSavedRef with initial data to prevent saving on mount
  useEffect(() => {
    const initialHash = JSON.stringify(getAllFormData());
    lastSavedRef.current = initialHash;
    // Mark as mounted after a short delay to skip initial renders
    const t = setTimeout(() => { mountedRef.current = true; }, 1000);
    return () => clearTimeout(t);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const performAutoSave = useCallback(async () => {
    if (!onAutoSave || !hasUserInteracted.current) return;
    const data = getAllFormData();
    const dataHash = JSON.stringify(data);
    if (dataHash === lastSavedRef.current) return;

    try {
      setAutoSaveStatus('saving');
      await onAutoSave(data);
      lastSavedRef.current = dataHash;
      setAutoSaveStatus('saved');
      setTimeout(() => setAutoSaveStatus((s) => s === 'saved' ? 'idle' : s), 3000);
    } catch {
      setAutoSaveStatus('error');
      setTimeout(() => setAutoSaveStatus((s) => s === 'error' ? 'idle' : s), 5000);
    }
  }, [onAutoSave, getAllFormData]);

  const scheduleAutoSave = useCallback(() => {
    if (!onAutoSave || !mountedRef.current) return;
    hasUserInteracted.current = true;
    if (autoSaveTimerRef.current) clearTimeout(autoSaveTimerRef.current);
    autoSaveTimerRef.current = setTimeout(performAutoSave, 3000);
  }, [onAutoSave, performAutoSave]);

  // Subscribe to form changes once. Using watch(callback) avoids resetting
  // the debounce timer on every parent re-render (which happens whenever
  // react-query invalidates and refetches `admissoes`, wiping the 3s timer
  // before it can ever fire and silently dropping auto-saves).
  useEffect(() => {
    const subs = [
      formPessoais.watch(() => scheduleAutoSave()),
      formContato.watch(() => scheduleAutoSave()),
      formProfissionais.watch(() => scheduleAutoSave()),
      formBancarios.watch(() => scheduleAutoSave()),
      formExame.watch(() => scheduleAutoSave()),
    ];
    return () => {
      subs.forEach((s) => s.unsubscribe());
      if (autoSaveTimerRef.current) clearTimeout(autoSaveTimerRef.current);
    };
  }, [formPessoais, formContato, formProfissionais, formBancarios, formExame, scheduleAutoSave]);

  // ── CPF lookup: busca usuário existente ──────────────────────────────────────
  const buscarUsuarioPorCpf = useCallback(async (cpf: string) => {
    if (!tenantId || cpf.length !== 11) return;
    setBuscandoCpf(true);
    try {
      const { data } = await (supabase as any)
        .from('usuarios_base')
        .select('id, nome_completo, email_principal, cpf, telefone_principal, cargo_funcao, data_nascimento')
        .eq('tenant_id', tenantId)
        .eq('cpf', cpf)
        .maybeSingle();
      if (data) {
        setUsuarioEncontrado(data as UsuarioEncontrado);
      } else {
        setUsuarioEncontrado(null);
        setDadosReaproveitados(false);
      }
    } catch {
      // silencioso
    } finally {
      setBuscandoCpf(false);
    }
  }, [tenantId]);

  const aplicarDadosUsuario = useCallback(() => {
    if (!usuarioEncontrado) return;
    if (usuarioEncontrado.nome_completo) formPessoais.setValue('nomeCompleto', usuarioEncontrado.nome_completo);
    if (usuarioEncontrado.data_nascimento) formPessoais.setValue('dataNascimento', usuarioEncontrado.data_nascimento);
    if (usuarioEncontrado.email_principal) formContato.setValue('email', usuarioEncontrado.email_principal);
    if (usuarioEncontrado.telefone_principal) formContato.setValue('celular', usuarioEncontrado.telefone_principal);
    if (usuarioEncontrado.cargo_funcao) formProfissionais.setValue('cargo', usuarioEncontrado.cargo_funcao);
    setDadosReaproveitados(true);
    toast.success('Dados do usuário aplicados ao cadastro!');
  }, [usuarioEncontrado, formPessoais, formContato, formProfissionais]);

  const getCurrentStepErrors = (): string[] => {
    const formByStep: Record<number, any> = {
      1: formPessoais, 2: formContato, 3: formProfissionais, 4: formBancarios, 5: formExame,
    };
    const form = formByStep[currentStep];
    if (!form) return [];
    const errs = form.formState.errors || {};
    return Object.values(errs)
      .map((e: any) => e?.message)
      .filter((m: any): m is string => typeof m === 'string' && m.length > 0);
  };

  const validateCurrentStep = async (): Promise<boolean> => {
    switch (currentStep) {
      case 1:
        return formPessoais.trigger();
      case 2:
        return formContato.trigger();
      case 3:
        return formProfissionais.trigger();
      case 4:
        return formBancarios.trigger();
      case 5:
        return formExame.trigger();
      default:
        return true;
    }
  };

  const handleNext = async () => {
    const isValid = await validateCurrentStep();
    if (isValid && currentStep < 6) {
      setCurrentStep(currentStep + 1);
      return;
    }
    if (!isValid) {
      const errors = getCurrentStepErrors();
      const stepTitle = STEPS[currentStep - 1]?.title || `Etapa ${currentStep}`;
      const detail = errors.slice(0, 3).join(' • ');
      toast.error(
        `Preencha os campos obrigatórios em "${stepTitle}" antes de avançar.`,
        { description: detail || 'Há campos obrigatórios pendentes nesta etapa.' }
      );
    }
  };

  const handlePrevious = () => {
    if (currentStep > 1) {
      setCurrentStep(currentStep - 1);
    }
  };

  const handleDocumentUpload = async (documentoId: string, file: File) => {
    const previousDocumentos = documentos;
    const documentoAlvo = previousDocumentos.find(doc => doc.id === documentoId);
    const nextDocumentos: DocumentoAdmissao[] = previousDocumentos.map(doc =>
      doc.id === documentoId
        ? {
            ...doc,
            arquivo: file,
            arquivo_nome: file.name,
            status: 'enviado' as const,
            dataEnvio: new Date(),
          }
        : doc
    );

    setDocumentos(nextDocumentos);

    if (onDocumentUploadImmediate && documentoAlvo) {
      try {
        const resultado = await onDocumentUploadImmediate(documentoAlvo, file);
        // Documento novo (id local "new-doc-N") vira uma linha real no banco na
        // hora do envio imediato. Trocamos o id local pelo UUID recebido para
        // que ações seguintes (remover/aprovar/substituir) não voltem a mandar
        // "new-doc-N" onde o banco espera um uuid.
        const realId = resultado?.realId;
        if (realId && realId !== documentoId) {
          setDocumentos(prev =>
            prev.map(doc => (doc.id === documentoId ? { ...doc, id: realId } : doc))
          );
        }
      } catch (error) {
        setDocumentos(previousDocumentos);
        throw error;
      }
    }
  };

  const handleDocumentRemove = async (documentoId: string) => {
    const previousDocumentos = documentos;
    const nextDocumentos: DocumentoAdmissao[] = previousDocumentos.map(doc =>
      doc.id === documentoId
        ? {
            ...doc,
            arquivo: undefined,
            arquivo_url: undefined,
            arquivo_nome: undefined,
            status: 'pendente' as const,
            dataEnvio: undefined,
          }
        : doc
    );

    setDocumentos(nextDocumentos);

    if (onDocumentRemoveImmediate) {
      try {
        await onDocumentRemoveImmediate(documentoId);
      } catch (error) {
        setDocumentos(previousDocumentos);
        throw error;
      }
    }
  };

  const handleToggleObrigatorio = (documentoId: string, obrigatorio: boolean) => {
    setDocumentos(prev => prev.map(doc =>
      doc.id === documentoId
        ? { ...doc, obrigatorio }
        : doc
    ));
  };

  const handleFinalSubmit = async () => {
    // Validar TODAS as etapas obrigatórias antes de enviar
    const results = await Promise.all([
      formPessoais.trigger(),
      formContato.trigger(),
      formProfissionais.trigger(),
      formBancarios.trigger(),
      formExame.trigger(),
    ]);
    const stepsLabels = ['Dados Pessoais', 'Contato', 'Profissional', 'Bancários', 'Exame Admissional'];
    const stepsForms = [formPessoais, formContato, formProfissionais, formBancarios, formExame];
    const invalidIndex = results.findIndex((ok) => !ok);
    if (invalidIndex !== -1) {
      const form = stepsForms[invalidIndex];
      const msgs = Object.values(form.formState.errors || {})
        .map((e: any) => e?.message)
        .filter((m: any): m is string => typeof m === 'string');
      toast.error(
        `Não foi possível enviar: complete a etapa "${stepsLabels[invalidIndex]}".`,
        { description: msgs.slice(0, 3).join(' • ') || 'Há campos obrigatórios pendentes.' }
      );
      setCurrentStep(invalidIndex + 1);
      return;
    }

    // Coletar documentos que possuem arquivos locais para upload
    const docsComArquivo = documentos
      .filter(doc => doc.arquivo instanceof File)
      .map(doc => ({
        documentoId: doc.id,
        file: doc.arquivo as File,
        obrigatorio: doc.obrigatorio,
      }));

    onSubmit({
      dadosPessoais: formPessoais.getValues(),
      dadosContato: formContato.getValues(),
      dadosProfissionais: formProfissionais.getValues(),
      dadosBancarios: formBancarios.getValues(),
      exameAdmissional: formExame.getValues(),
      documentos,
      documentosComArquivo: docsComArquivo.length > 0 ? docsComArquivo : undefined,
    });
  };

  const renderStepContent = () => {
    switch (currentStep) {
      case 1:
        return (
          <motion.div
            key="step1"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            className="space-y-6"
          >
            {/* Banner: usuário encontrado */}
            {usuarioEncontrado && !dadosReaproveitados && (
              <div className="flex flex-col gap-2 p-3 bg-primary/5 border border-primary/20 rounded-lg text-sm mb-2">
                <div className="flex items-start gap-2">
                  <span className="text-primary font-medium">👤 Usuário encontrado na base!</span>
                </div>
                <p className="text-xs text-muted-foreground">
                  {usuarioEncontrado.nome_completo}
                  {usuarioEncontrado.cargo_funcao ? ` — ${usuarioEncontrado.cargo_funcao}` : ''}
                </p>
                <button
                  type="button"
                  onClick={aplicarDadosUsuario}
                  className="self-start text-xs font-medium text-primary underline hover:no-underline"
                >
                  Reaproveitar dados deste usuário →
                </button>
              </div>
            )}
            {dadosReaproveitados && (
              <div className="flex gap-2 items-center p-2.5 bg-primary/5 border border-primary/20 rounded-lg text-xs text-primary mb-2">
                ✓ Dados do usuário aplicados. Complete os campos específicos de colaborador.
              </div>
            )}

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <Label htmlFor="cpf" className="flex items-center gap-1.5">
                  CPF *
                  {buscandoCpf && <span className="text-xs text-muted-foreground">(buscando…)</span>}
                  {usuarioEncontrado && !buscandoCpf && <span className="text-xs text-primary">✓ encontrado</span>}
                </Label>
                <CpfInput 
                  id="cpf"
                  value={formPessoais.watch('cpf')}
                  onChange={(value) => {
                    formPessoais.setValue('cpf', value, { shouldValidate: true });
                    if (value.length === 11) buscarUsuarioPorCpf(value);
                  }}
                  onValidChange={(isValid) => {
                    if (isValid) buscarUsuarioPorCpf(formPessoais.getValues('cpf'));
                  }}
                />
                {formPessoais.formState.errors.cpf && (
                  <p className="text-xs text-destructive mt-1">{formPessoais.formState.errors.cpf.message}</p>
                )}
              </div>

              <div className="md:col-span-1">
                <Label htmlFor="nomeCompleto">Nome Completo *</Label>
                <Input 
                  id="nomeCompleto"
                  {...formPessoais.register('nomeCompleto')}
                  placeholder="Nome completo do colaborador"
                />
                {formPessoais.formState.errors.nomeCompleto && (
                  <p className="text-xs text-destructive mt-1">{formPessoais.formState.errors.nomeCompleto.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="rg">RG *</Label>
                <Input 
                  id="rg"
                  {...formPessoais.register('rg')}
                  placeholder="00.000.000-0"
                />
                {formPessoais.formState.errors.rg && (
                  <p className="text-xs text-destructive mt-1">{formPessoais.formState.errors.rg.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="dataNascimento">Data de Nascimento *</Label>
                <Input 
                  id="dataNascimento"
                  type="date"
                  {...formPessoais.register('dataNascimento')}
                />
                {formPessoais.formState.errors.dataNascimento && (
                  <p className="text-xs text-destructive mt-1">{formPessoais.formState.errors.dataNascimento.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="genero">Gênero *</Label>
                <Select 
                  value={formPessoais.watch('genero')}
                  onValueChange={(value) => formPessoais.setValue('genero', value)}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Selecione" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="masculino">Masculino</SelectItem>
                    <SelectItem value="feminino">Feminino</SelectItem>
                    <SelectItem value="outro">Outro</SelectItem>
                    <SelectItem value="prefiro_nao_informar">Prefiro não informar</SelectItem>
                  </SelectContent>
                </Select>
                {formPessoais.formState.errors.genero && (
                  <p className="text-xs text-destructive mt-1">{formPessoais.formState.errors.genero.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="estadoCivil">Estado Civil *</Label>
                <Select 
                  value={formPessoais.watch('estadoCivil')}
                  onValueChange={(value) => formPessoais.setValue('estadoCivil', value)}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Selecione" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="solteiro">Solteiro(a)</SelectItem>
                    <SelectItem value="casado">Casado(a)</SelectItem>
                    <SelectItem value="divorciado">Divorciado(a)</SelectItem>
                    <SelectItem value="viuvo">Viúvo(a)</SelectItem>
                    <SelectItem value="uniao_estavel">União Estável</SelectItem>
                  </SelectContent>
                </Select>
                {formPessoais.formState.errors.estadoCivil && (
                  <p className="text-xs text-destructive mt-1">{formPessoais.formState.errors.estadoCivil.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="nacionalidade">Nacionalidade *</Label>
                <Input 
                  id="nacionalidade"
                  {...formPessoais.register('nacionalidade')}
                  placeholder="Brasileira"
                />
                {formPessoais.formState.errors.nacionalidade && (
                  <p className="text-xs text-destructive mt-1">{formPessoais.formState.errors.nacionalidade.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="naturalidade">Naturalidade *</Label>
                <Input 
                  id="naturalidade"
                  {...formPessoais.register('naturalidade')}
                  placeholder="Cidade - UF"
                />
                {formPessoais.formState.errors.naturalidade && (
                  <p className="text-xs text-destructive mt-1">{formPessoais.formState.errors.naturalidade.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="nomeMae">Nome da Mãe *</Label>
                <Input 
                  id="nomeMae"
                  {...formPessoais.register('nomeMae')}
                  placeholder="Nome completo da mãe"
                />
                {formPessoais.formState.errors.nomeMae && (
                  <p className="text-xs text-destructive mt-1">{formPessoais.formState.errors.nomeMae.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="nomePai">Nome do Pai</Label>
                <Input 
                  id="nomePai"
                  {...formPessoais.register('nomePai')}
                  placeholder="Nome completo do pai (opcional)"
                />
              </div>
            </div>
          </motion.div>
        );

      case 2:
        return (
          <motion.div
            key="step2"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            className="space-y-6"
          >
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="md:col-span-2">
                <Label htmlFor="email">E-mail *</Label>
                <Input 
                  id="email"
                  type="email"
                  {...formContato.register('email')}
                  placeholder="email@exemplo.com"
                />
                {formContato.formState.errors.email && (
                  <p className="text-xs text-destructive mt-1">{formContato.formState.errors.email.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="celular">Celular *</Label>
                <PhoneInput 
                  id="celular"
                  value={formContato.watch('celular')}
                  onChange={(value) => formContato.setValue('celular', value, { shouldValidate: true })}
                />
                {formContato.formState.errors.celular && (
                  <p className="text-xs text-destructive mt-1">{formContato.formState.errors.celular.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="telefone">Telefone Fixo</Label>
                <PhoneInput 
                  id="telefone"
                  value={formContato.watch('telefone')}
                  onChange={(value) => formContato.setValue('telefone', value)}
                />
              </div>

              <div>
                <Label htmlFor="cep">CEP *</Label>
                <CepInput 
                  id="cep"
                  value={formContato.watch('cep')}
                  onChange={(value) => formContato.setValue('cep', value, { shouldValidate: true })}
                  onAddressFound={(endereco: EnderecoData) => {
                    formContato.setValue('endereco', endereco.logradouro, { shouldValidate: true });
                    formContato.setValue('bairro', endereco.bairro, { shouldValidate: true });
                    formContato.setValue('cidade', endereco.cidade, { shouldValidate: true });
                    formContato.setValue('estado', endereco.estado, { shouldValidate: true });
                  }}
                />
                {formContato.formState.errors.cep && (
                  <p className="text-xs text-destructive mt-1">{formContato.formState.errors.cep.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="estado">Estado *</Label>
                <Select 
                  value={formContato.watch('estado')}
                  onValueChange={(value) => formContato.setValue('estado', value)}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Selecione" />
                  </SelectTrigger>
                  <SelectContent>
                    {['AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO'].map(uf => (
                      <SelectItem key={uf} value={uf}>{uf}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                {formContato.formState.errors.estado && (
                  <p className="text-xs text-destructive mt-1">{formContato.formState.errors.estado.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="cidade">Cidade *</Label>
                <Input 
                  id="cidade"
                  {...formContato.register('cidade')}
                  placeholder="Nome da cidade"
                />
                {formContato.formState.errors.cidade && (
                  <p className="text-xs text-destructive mt-1">{formContato.formState.errors.cidade.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="bairro">Bairro *</Label>
                <Input 
                  id="bairro"
                  {...formContato.register('bairro')}
                  placeholder="Nome do bairro"
                />
                {formContato.formState.errors.bairro && (
                  <p className="text-xs text-destructive mt-1">{formContato.formState.errors.bairro.message}</p>
                )}
              </div>

              <div className="md:col-span-2">
                <Label htmlFor="endereco">Endereço *</Label>
                <Input 
                  id="endereco"
                  {...formContato.register('endereco')}
                  placeholder="Rua, Avenida, etc"
                />
                {formContato.formState.errors.endereco && (
                  <p className="text-xs text-destructive mt-1">{formContato.formState.errors.endereco.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="numero">Número *</Label>
                <Input 
                  id="numero"
                  {...formContato.register('numero')}
                  placeholder="123"
                />
                {formContato.formState.errors.numero && (
                  <p className="text-xs text-destructive mt-1">{formContato.formState.errors.numero.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="complemento">Complemento</Label>
                <Input 
                  id="complemento"
                  {...formContato.register('complemento')}
                  placeholder="Apto, Bloco, etc"
                />
              </div>
            </div>
          </motion.div>
        );

      case 3:
        return (
          <motion.div
            key="step3"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            className="space-y-6"
          >
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {/* Estabelecimento / Obra */}
              <div>
                <Label htmlFor="filial">Estabelecimento / Obra</Label>
                <Select 
                  value={formProfissionais.watch('filial')}
                  onValueChange={(value) => formProfissionais.setValue('filial', value)}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Selecione" />
                  </SelectTrigger>
                  <SelectContent>
                    {estabelecimentosOptions.length > 0 ? (
                      estabelecimentosOptions.map((est) => (
                        <SelectItem key={est.id} value={est.nome.trim()}>
                          {est.nome}
                        </SelectItem>
                      ))
                    ) : (
                      <SelectItem value="_none" disabled>Nenhum estabelecimento cadastrado</SelectItem>
                    )}
                  </SelectContent>
                </Select>
                {formProfissionais.formState.errors.filial && (
                  <p className="text-xs text-destructive mt-1">{formProfissionais.formState.errors.filial.message}</p>
                )}
              </div>

              {/* Departamento — do banco */}
              <div>
                <Label htmlFor="departamento">Departamento *</Label>
                <Select 
                  value={formProfissionais.watch('departamento')}
                  onValueChange={(value) => formProfissionais.setValue('departamento', value)}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Selecione" />
                  </SelectTrigger>
                  <SelectContent>
                    {departamentosOptions.length > 0 ? (
                      departamentosOptions.map((dept) => (
                        <SelectItem key={dept.id} value={dept.nome.trim()}>
                          {dept.nome}
                        </SelectItem>
                      ))
                    ) : (
                      <SelectItem value="_none" disabled>Nenhum departamento cadastrado</SelectItem>
                    )}
                  </SelectContent>
                </Select>
                {formProfissionais.formState.errors.departamento && (
                  <p className="text-xs text-destructive mt-1">{formProfissionais.formState.errors.departamento.message}</p>
                )}
              </div>

              {/* Data de Admissão | Tipo de Vínculo */}
              <div>
                <Label htmlFor="dataAdmissao">Data de Admissão *</Label>
                <Input 
                  id="dataAdmissao"
                  type="date"
                  {...formProfissionais.register('dataAdmissao')}
                />
                {formProfissionais.formState.errors.dataAdmissao && (
                  <p className="text-xs text-destructive mt-1">{formProfissionais.formState.errors.dataAdmissao.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="tipoContrato">Tipo de Vínculo *</Label>
                <Select 
                  value={formProfissionais.watch('tipoContrato')}
                  onValueChange={(value) => formProfissionais.setValue('tipoContrato', value)}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Selecione" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="clt">CLT – Prazo Indeterminado</SelectItem>
                    <SelectItem value="contrato_experiencia">CLT – Contrato de Experiência</SelectItem>
                    <SelectItem value="prolabore">Pró-labore (Sócio)</SelectItem>
                    <SelectItem value="estagiario">Estagiário</SelectItem>
                    <SelectItem value="temporario">Temporário</SelectItem>
                    <SelectItem value="autonomo">Autônomo</SelectItem>
                  </SelectContent>
                </Select>
                {formProfissionais.formState.errors.tipoContrato && (
                  <p className="text-xs text-destructive mt-1">{formProfissionais.formState.errors.tipoContrato.message}</p>
                )}
              </div>

              {/* Bloco específico para Contrato de Experiência */}
              {formProfissionais.watch('tipoContrato') === 'contrato_experiencia' && (
                <div className="col-span-full rounded-lg border border-primary/30 bg-primary/5 p-4 space-y-3">
                  <div className="flex items-center gap-2 text-sm font-semibold text-primary">
                    <AlertCircle className="w-4 h-4" />
                    Contrato de Experiência (CLT art. 445)
                  </div>
                  <p className="text-xs text-muted-foreground">
                    Ao concluir esta admissão, um contrato de experiência será criado automaticamente no módulo de Contratos de Experiência, 
                    usando as configurações da empresa (duração do período, cláusula assecuratória, etc.). 
                    Você poderá gerar o documento, enviar para assinatura e acompanhar prazos por lá.
                  </p>
                  <ul className="text-xs text-muted-foreground list-disc pl-5 space-y-0.5">
                    <li>Duração máxima: 90 dias (pode ser dividido em 2 períodos)</li>
                    <li>Apenas uma prorrogação é permitida</li>
                    <li>Alertas automáticos de vencimento serão ativados</li>
                  </ul>
                </div>
              )}

              {/* Jornada | Salário */}
              <div>
                <Label htmlFor="jornadaTrabalho">Jornada de Trabalho *</Label>
                <Select 
                  value={formProfissionais.watch('jornadaTrabalho')}
                  onValueChange={(value) => formProfissionais.setValue('jornadaTrabalho', value)}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Selecione" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="44h semanais">44h semanais</SelectItem>
                    <SelectItem value="40h semanais">40h semanais</SelectItem>
                    <SelectItem value="30h semanais">30h semanais</SelectItem>
                    <SelectItem value="20h semanais">20h semanais</SelectItem>
                    <SelectItem value="Flexível">Flexível</SelectItem>
                  </SelectContent>
                </Select>
                {formProfissionais.formState.errors.jornadaTrabalho && (
                  <p className="text-xs text-destructive mt-1">{formProfissionais.formState.errors.jornadaTrabalho.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="salario">Salário *</Label>
                <Input 
                  id="salario"
                  {...formProfissionais.register('salario')}
                  placeholder="R$ 0.000,00"
                  onChange={(e) => {
                    let value = e.target.value.replace(/\D/g, "");
                    if (value === "") {
                      formProfissionais.setValue('salario', "", { shouldValidate: true });
                      return;
                    }
                    const amount = (parseInt(value) / 100).toFixed(2);
                    const formatted = new Intl.NumberFormat('pt-BR', {
                      style: 'currency',
                      currency: 'BRL',
                    }).format(parseFloat(amount));
                    formProfissionais.setValue('salario', formatted, { shouldValidate: true });
                  }}
                />
                {formProfissionais.formState.errors.salario && (
                  <p className="text-xs text-destructive mt-1">{formProfissionais.formState.errors.salario.message}</p>
                )}
              </div>

              {/* Centro de Custo */}
              <div>
                <Label htmlFor="centroCusto">Centro de Custo</Label>
                <Input 
                  id="centroCusto"
                  {...formProfissionais.register('centroCusto')}
                  placeholder="Ex: RH-001 (opcional)"
                />
              </div>
            </div>

            {/* Função — linha inteira */}
            <div>
              <Label htmlFor="cargo">Cargo *</Label>
              <Input 
                id="cargo"
                {...formProfissionais.register('cargo')}
                placeholder="Ex: Analista de RH"
              />
              {formProfissionais.formState.errors.cargo && (
                <p className="text-xs text-destructive mt-1">{formProfissionais.formState.errors.cargo.message}</p>
              )}
            </div>

            {/* CBO — Classificação Brasileira de Ocupações */}
            <div>
              <Label>CBO — Ocupação (opcional)</Label>
              <CBOAutocomplete
                value={formProfissionais.watch('cbo') || ''}
                onChange={(codigo) => formProfissionais.setValue('cbo', codigo || '', { shouldValidate: false })}
              />
              <p className="text-xs text-muted-foreground mt-1">
                Vincule a função à Classificação Brasileira de Ocupações (CBO). Aceita código com ou sem traço.
              </p>
            </div>

            {/* Gestor Imediato — linha inteira, combobox com busca */}
            <div>
              <Label>Gestor Imediato *</Label>
              <GestorComboboxField
                value={formProfissionais.watch('gestorImediato') || ''}
                onChange={(val) => formProfissionais.setValue('gestorImediato', val, { shouldValidate: true })}
              />
              {formProfissionais.formState.errors.gestorImediato && (
                <p className="text-xs text-destructive mt-1">{formProfissionais.formState.errors.gestorImediato.message}</p>
              )}
            </div>
          </motion.div>
        );

      case 4:
        return (
          <motion.div
            key="step4"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            className="space-y-6"
          >
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <Label htmlFor="banco">Banco *</Label>
                <Select 
                  value={formBancarios.watch('banco')}
                  onValueChange={(value) => formBancarios.setValue('banco', value)}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Selecione" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Banco do Brasil">Banco do Brasil</SelectItem>
                    <SelectItem value="Caixa Econômica">Caixa Econômica</SelectItem>
                    <SelectItem value="Itaú">Itaú</SelectItem>
                    <SelectItem value="Bradesco">Bradesco</SelectItem>
                    <SelectItem value="Santander">Santander</SelectItem>
                    <SelectItem value="Nubank">Nubank</SelectItem>
                    <SelectItem value="Inter">Inter</SelectItem>
                    <SelectItem value="C6 Bank">C6 Bank</SelectItem>
                    <SelectItem value="Sicoob">Sicoob</SelectItem>
                    <SelectItem value="Sicredi">Sicredi</SelectItem>
                  </SelectContent>
                </Select>
                {formBancarios.formState.errors.banco && (
                  <p className="text-xs text-destructive mt-1">{formBancarios.formState.errors.banco.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="tipoConta">Tipo de Conta *</Label>
                <Select 
                  value={formBancarios.watch('tipoConta')}
                  onValueChange={(value) => formBancarios.setValue('tipoConta', value)}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Selecione" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="corrente">Conta Corrente</SelectItem>
                    <SelectItem value="poupanca">Poupança</SelectItem>
                    <SelectItem value="salario">Conta Salário</SelectItem>
                  </SelectContent>
                </Select>
                {formBancarios.formState.errors.tipoConta && (
                  <p className="text-xs text-destructive mt-1">{formBancarios.formState.errors.tipoConta.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="agencia">Agência *</Label>
                <Input 
                  id="agencia"
                  {...formBancarios.register('agencia')}
                  placeholder="0000-0"
                />
                {formBancarios.formState.errors.agencia && (
                  <p className="text-xs text-destructive mt-1">{formBancarios.formState.errors.agencia.message}</p>
                )}
              </div>

              <div>
                <Label htmlFor="conta">Conta *</Label>
                <Input 
                  id="conta"
                  {...formBancarios.register('conta')}
                  placeholder="00000-0"
                />
                {formBancarios.formState.errors.conta && (
                  <p className="text-xs text-destructive mt-1">{formBancarios.formState.errors.conta.message}</p>
                )}
              </div>

              <div className="md:col-span-2">
                <Label htmlFor="chavePix">Chave PIX (opcional)</Label>
                <Input 
                  id="chavePix"
                  {...formBancarios.register('chavePix')}
                  placeholder="CPF, e-mail, telefone ou chave aleatória"
                />
              </div>
            </div>
          </motion.div>
        );

      case 5:
        return (
          <motion.div
            key="step5"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            className="space-y-6"
          >
            <div className="bg-muted/50 rounded-lg p-4 border border-border mb-4">
              <div className="flex items-center gap-2">
                <Stethoscope className="h-5 w-5 text-primary" />
                <div>
                  <h4 className="font-medium text-foreground">Exame Admissional</h4>
                  <p className="text-sm text-muted-foreground">
                    Informações sobre o exame médico ocupacional de admissão
                  </p>
                </div>
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <Label htmlFor="dataExame">Data do Exame</Label>
                <Input 
                  id="dataExame"
                  type="date"
                  {...formExame.register('dataExame')}
                />
              </div>

              <div>
                <Label htmlFor="dataValidade">Validade do Exame</Label>
                <Input 
                  id="dataValidade"
                  type="date"
                  {...formExame.register('dataValidade')}
                />
                <p className="text-xs text-muted-foreground mt-1">
                  A periodicidade varia conforme o cargo e riscos ocupacionais
                </p>
              </div>

              <div>
                <Label htmlFor="resultado">Resultado</Label>
                <Select 
                  value={formExame.watch('resultado')}
                  onValueChange={(value) => formExame.setValue('resultado', value)}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Selecione o resultado" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="apto">Apto</SelectItem>
                    <SelectItem value="inapto">Inapto</SelectItem>
                    <SelectItem value="apto_com_restricoes">Apto com Restrições</SelectItem>
                    <SelectItem value="pendente">Pendente</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div>
                <Label htmlFor="clinica">Clínica / Hospital</Label>
                <Input 
                  id="clinica"
                  {...formExame.register('clinica')}
                  placeholder="Nome da clínica ou hospital"
                />
              </div>

              <div>
                <Label htmlFor="medico">Médico Responsável</Label>
                <Input 
                  id="medico"
                  {...formExame.register('medico')}
                  placeholder="Nome do médico"
                />
              </div>

              <div>
                <Label htmlFor="crm">CRM</Label>
                <Input 
                  id="crm"
                  {...formExame.register('crm')}
                  placeholder="Ex: CRM/SP 123456"
                />
              </div>

              <div className="md:col-span-2">
                <Label htmlFor="observacoes">Observações</Label>
                <Textarea 
                  id="observacoes"
                  {...formExame.register('observacoes')}
                  placeholder="Observações sobre o exame, restrições, recomendações, etc."
                  rows={3}
                />
              </div>
            </div>
          </motion.div>
        );

      case 6:
        return (
          <motion.div
            key="step6"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
          >
            <DocumentUpload
              documentos={documentos}
              onUpload={handleDocumentUpload}
              onRemove={handleDocumentRemove}
              onToggleObrigatorio={handleToggleObrigatorio}
              editableObrigatorio={true}
            />
          </motion.div>
        );

      default:
        return null;
    }
  };

  return (
    <div className="space-y-8">
      {/* Steps indicator */}
      <AdmissaoFormSteps 
        steps={STEPS} 
        currentStep={currentStep}
        onStepClick={(step) => (onAutoSave || step < currentStep) && setCurrentStep(step)}
        allowFreeNavigation={!!onAutoSave}
      />

      {/* Step content */}
      <div className="bg-card rounded-xl border border-border p-6">
        <div className="flex items-center gap-3 mb-6">
          {(() => {
            const StepIcon = STEPS[currentStep - 1].icon;
            return <StepIcon className="h-6 w-6 text-primary" />;
          })()}
          <div>
            <h2 className="text-xl font-semibold text-foreground">
              {STEPS[currentStep - 1].title}
            </h2>
            <p className="text-sm text-muted-foreground">
              {STEPS[currentStep - 1].description}
            </p>
          </div>
        </div>

        <AnimatePresence mode="wait">
          {renderStepContent()}
        </AnimatePresence>
      </div>

      {/* Navigation buttons */}
      <div className="flex items-center justify-between">
        <Button
          variant="outline"
          onClick={currentStep === 1 ? onCancel : handlePrevious}
        >
          <ChevronLeft className="h-4 w-4 mr-1" />
          {currentStep === 1 ? 'Cancelar' : 'Voltar'}
        </Button>

        {/* Auto-save status indicator */}
        {onAutoSave && (
          <div className="flex items-center gap-2 text-xs text-muted-foreground">
            {autoSaveStatus === 'saving' && (
              <>
                <Loader2Icon className="h-3.5 w-3.5 animate-spin" />
                <span>Salvando rascunho...</span>
              </>
            )}
            {autoSaveStatus === 'saved' && (
              <>
                <CheckCircle2 className="h-3.5 w-3.5 text-primary" />
                <span className="text-primary">Rascunho salvo</span>
              </>
            )}
            {autoSaveStatus === 'error' && (
              <>
                <CloudOff className="h-3.5 w-3.5 text-destructive" />
                <span className="text-destructive">Erro ao salvar</span>
              </>
            )}
            {autoSaveStatus === 'idle' && (
              <>
                <Cloud className="h-3.5 w-3.5" />
                <span>Salvamento automático ativo</span>
              </>
            )}
          </div>
        )}

        <div className="flex gap-2">
          {currentStep === 6 ? (
            <>
              <Button variant="outline" onClick={handleFinalSubmit}>
                <Save className="h-4 w-4 mr-1" />
                Salvar Rascunho
              </Button>
              <Button onClick={handleFinalSubmit}>
                <Send className="h-4 w-4 mr-1" />
                Enviar para Aprovação
              </Button>
            </>
          ) : (
            <Button onClick={handleNext}>
              Próximo
              <ChevronRight className="h-4 w-4 ml-1" />
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}
