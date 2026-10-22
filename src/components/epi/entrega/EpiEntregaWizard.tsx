import { useState, useRef, useMemo, useCallback, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Progress } from "@/components/ui/progress";
import { LivenessDetection } from "./LivenessDetection";
import { PhotoCapture } from "./PhotoCapture";
import { SignatureCapture } from "./SignatureCapture";
import { EpiEntregaRecibo } from "./EpiEntregaRecibo";
import { useColaboradores } from "@/hooks/useColaboradores";
import { useAfastamentosAtivos } from "@/hooks/useAfastamentosAtivos";
import { AfastadoBadge } from "@/components/shared/AfastadoBadge";
import { useAuth } from "@/hooks/useAuth";
import { useDocumentos } from "@/hooks/useDocumentos";
import { useEpiLocais } from "@/hooks/useEpiLocais";
import { useEpiConfig } from "@/hooks/useEpiConfig";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { format, addDays } from "date-fns";
import { Loader2, Download, ArrowLeft, ArrowRight, XCircle, Check, ChevronsUpDown, AlertCircle, User, MapPin } from "lucide-react";
import html2canvas from "html2canvas";
import jsPDF from "jspdf";
import type { EpiTipo, EpiEntrega } from "@/types/epi";
import { BUCKET_EVIDENCIA_EPI } from "@/lib/epiEvidencia";
import { cn } from "@/lib/utils";
import { useEpiTamanhos } from "@/hooks/useEpiTamanhos";
import { Badge } from "@/components/ui/badge";

interface EpiEntregaWizardProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  epiTipos: EpiTipo[];
  onSuccess: () => void;
}

type WizardStep = "form" | "liveness" | "photo" | "signature" | "complete";

interface FormData {
  colaboradorId: string;
  colaboradorNome: string;
  colaboradorCpf: string;
  colaboradorCargo: string;
  colaboradorDepartamento: string;
  epiTipoId: string;
  epiTipo: EpiTipo | null;
  localEstoqueId: string;
  quantidade: number;
  tamanho: string;
  dataEntrega: string;
  dataValidade: string;
  observacoes: string;
}

export function EpiEntregaWizard({
  open,
  onOpenChange,
  epiTipos,
  onSuccess,
}: EpiEntregaWizardProps) {
  const { tenantId, user, profile } = useAuth();
  const { colaboradores, isLoading: colaboradoresLoading } = useColaboradores();
  const { getAfastamento } = useAfastamentosAtivos();
  const { upload: uploadDocumento } = useDocumentos();
  const { locaisAtivos } = useEpiLocais();
  const { usarControleEstoque } = useEpiConfig();
  const { getTamanhosForTipo } = useEpiTamanhos();
  const reciboRef = useRef<HTMLDivElement>(null);
  const [colaboradorPopoverOpen, setColaboradorPopoverOpen] = useState(false);
  const [colaboradorSearch, setColaboradorSearch] = useState("");
  const [step, setStep] = useState<WizardStep>("form");
  
  // Filtrar colaboradores pelo termo de busca
  const filteredColaboradores = useMemo(() => {
    if (!colaboradorSearch) return colaboradores;
    const search = colaboradorSearch.toLowerCase();
    return colaboradores.filter(
      (c) =>
        c.nome_completo.toLowerCase().includes(search) ||
        c.cpf.includes(search)
    );
  }, [colaboradores, colaboradorSearch]);
  const [isLoading, setIsLoading] = useState(false);

  // CT-26: EPIs sugeridos pela matriz de proteção para a função do colaborador
  const [episSugeridos, setEpisSugeridos] = useState<Array<{ epi_tipo_id: string; nome: string; obrigatorio: boolean }>>([]);

  // CT-34: Entregas ativas do colaborador para verificar substituição
  const [entregasAtivas, setEntregasAtivas] = useState<Array<{ id: string; epi_tipo_id: string; epi_tipo_nome: string; data_entrega: string }>>([]);
  const [substituicaoDetectada, setSubstituicaoDetectada] = useState<{ id: string; epi_tipo_nome: string; data_entrega: string } | null>(null);
  // Destino do EPI que está sendo substituído; escolhido a cada vez. Descarte é o
  // padrão porque devolver ao estoque um EPI desgastado seria risco de segurança.
  const [destinoSubstituicao, setDestinoSubstituicao] = useState<"descarte" | "estoque" | "manutencao">("descarte");

  const [showRecusaDialog, setShowRecusaDialog] = useState(false);
  const [formData, setFormData] = useState<FormData>({
    colaboradorId: "",
    colaboradorNome: "",
    colaboradorCpf: "",
    colaboradorCargo: "",
    colaboradorDepartamento: "",
    epiTipoId: "",
    epiTipo: null,
    localEstoqueId: "",
    quantidade: 1,
    tamanho: "",
    dataEntrega: format(new Date(), "yyyy-MM-dd"),
    dataValidade: "",
    observacoes: "",
  });

  // Capture data
  const [livenessData, setLivenessData] = useState<{ actions: string[]; timestamps: string[] } | null>(null);
  const [photoData, setPhotoData] = useState<string | null>(null);
  const [signatureData, setSignatureData] = useState<string | null>(null);
  const [entregaResult, setEntregaResult] = useState<any>(null);
  const [pdfArquivado, setPdfArquivado] = useState(false);

  const steps: WizardStep[] = ["form", "liveness", "photo", "signature", "complete"];
  const stepLabels = {
    form: "Formulário",
    liveness: "Verificação",
    photo: "Foto",
    signature: "Assinatura",
    complete: "Concluído",
  };

  const currentStepIndex = steps.indexOf(step);
  const progress = ((currentStepIndex + 1) / steps.length) * 100;

  const resetWizard = () => {
    setStep("form");
    setFormData({
      colaboradorId: "",
      colaboradorNome: "",
      colaboradorCpf: "",
      colaboradorCargo: "",
      colaboradorDepartamento: "",
      epiTipoId: "",
      epiTipo: null,
      localEstoqueId: "",
      quantidade: 1,
      tamanho: "",
      dataEntrega: format(new Date(), "yyyy-MM-dd"),
      dataValidade: "",
      observacoes: "",
    });
    setLivenessData(null);
    setPhotoData(null);
    setSignatureData(null);
    setEntregaResult(null);
    setPdfArquivado(false);
    setDestinoSubstituicao("descarte");
  };

  const handleClose = () => {
    resetWizard();
    onOpenChange(false);
  };

  // Upload base64 para o bucket PRIVADO da evidência de EPI. Devolve o CAMINHO
  // do arquivo (o primeiro nível é a empresa, exigido pela política de storage);
  // o link de leitura é gerado sob demanda por urlDaEvidenciaEpi. Sem upsert: a
  // evidência não pode ser sobrescrita.
  const uploadToStorage = async (base64Data: string, fileName: string): Promise<string> => {
    const base64 = base64Data.split(",")[1];
    const byteArray = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));

    const { data, error } = await supabase.storage
      .from(BUCKET_EVIDENCIA_EPI)
      .upload(fileName, byteArray, { contentType: "image/png", upsert: false });

    if (error) throw error;
    return data.path;
  };

  // Salvar entrega
  const saveEntrega = async (status: "entregue" | "recusado" = "entregue") => {
    if (!tenantId) {
      toast.error("Tenant não identificado");
      return;
    }

    setIsLoading(true);

    try {
      // CT-39: Verificar se o colaborador ainda está ativo antes de salvar
      const { data: admissaoAtual, error: admissaoError } = await supabase
        .from("admissoes")
        .select("status, data_desligamento")
        .eq("id", formData.colaboradorId)
        .eq("tenant_id", tenantId)
        .single();

      if (admissaoError) throw admissaoError;

      if (admissaoAtual?.status === "desligado" || admissaoAtual?.data_desligamento) {
        toast.error("Entrega bloqueada: colaborador está desligado. Não é possível entregar EPI a colaboradores inativos.");
        return;
      }

      // A tabela epi_entregas referencia `epis.id` (item de estoque),
      // então precisamos resolver o epi_id a partir do tipo selecionado (epi_tipos).
      let epiId: string;
      
      // Buscar EPI existente com estoque suficiente
      const { data: epiRow, error: epiError } = await supabase
        .from("epis")
        .select("id, quantidade_estoque")
        .eq("tipo_id", formData.epiTipoId)
        .order("created_at", { ascending: true })
        .limit(1)
        .maybeSingle();

      if (epiError) throw epiError;
      
      if (epiRow?.id) {
        epiId = epiRow.id;
      } else {
        // Não existe EPI para este tipo, criar um automaticamente
        const { data: newEpi, error: createError } = await supabase
          .from("epis")
          .insert({
            tenant_id: tenantId,
            tipo_id: formData.epiTipoId,
            quantidade_estoque: 1000,
            quantidade_minima: 10,
            status: "disponivel",
          })
          .select("id, quantidade_estoque")
          .single();
        
        if (createError) throw createError;
        epiId = newEpi.id;
      }

      let fotoUrl: string | undefined;
      let assinaturaUrl: string | undefined;
      const signedAt = new Date().toISOString();

      // Upload foto e assinatura se não for recusa
      if (status === "entregue" && photoData && signatureData) {
        const timestamp = Date.now();
        
        fotoUrl = await uploadToStorage(
          photoData,
          `${tenantId}/fotos/${timestamp}-${formData.colaboradorId}.png`
        );
        
        assinaturaUrl = await uploadToStorage(
          signatureData,
          `${tenantId}/assinaturas/${timestamp}-${formData.colaboradorId}.png`
        );
      }

      // Registro da entrega, baixa do estoque (global e do local) e movimentação
      // numa única transação do banco. Se qualquer passo falhar, nada é gravado:
      // não existe mais DELETE de entrega assinada nem baixa em duas etapas (a
      // segunda "otimista" nunca batia, porque o gatilho já tinha baixado o
      // global, e o código então apagava a ficha com o estoque já descontado).
      const { data: entregaGravada, error } = await supabase.rpc("epi_registrar_entrega", {
        p_entrega: {
          tenant_id: tenantId,
          epi_id: epiId,
          colaborador_nome: formData.colaboradorNome,
          colaborador_cpf: formData.colaboradorCpf,
          colaborador_cargo: formData.colaboradorCargo,
          colaborador_departamento: formData.colaboradorDepartamento,
          employee_id: formData.colaboradorId || null,
          quantidade: formData.quantidade,
          data_entrega: formData.dataEntrega,
          data_validade: formData.dataValidade || null,
          status: status === "recusado" ? "extraviado" : "ativa",
          tamanho: formData.tamanho || null,
          foto_entrega_url: fotoUrl ?? null,
          assinatura_url: assinaturaUrl ?? null,
          signed_at: status === "entregue" ? signedAt : null,
          liveness_detected: livenessData !== null,
          liveness_data: livenessData || { actions: [], timestamps: [] },
          // IP e dispositivo reais são gravados pelo servidor (gatilho
          // epi_entrega_origem_pelo_servidor) a partir da requisição; o que o
          // navegador mandasse aqui não valeria como prova.
          user_agent: navigator.userAgent,
          observacoes: status === "recusado"
            ? `RECUSADO: Colaborador recusou assinar. ${formData.observacoes}`
            : formData.observacoes,
          entregue_por: user?.id ?? null,
          entregue_por_nome: profile?.nome_completo ?? null,
        },
        p_local: usarControleEstoque && formData.localEstoqueId ? formData.localEstoqueId : null,
        // Substituição: o EPI anterior é devolvido na mesma transação, com o
        // destino escolhido. Se qualquer parte falhar, nada é gravado.
        p_substitui: substituicaoDetectada && status === "entregue" ? substituicaoDetectada.id : undefined,
        p_destino_substituicao: substituicaoDetectada && status === "entregue" ? destinoSubstituicao : undefined,
      });

      if (error) throw error;
      const data = entregaGravada as unknown as EpiEntrega;

      setEntregaResult({
        ...data,
        // O recibo mostra a foto e a assinatura que já estão na memória; o que
        // fica gravado na entrega é o caminho no bucket privado, não uma URL.
        fotoUrl: photoData ?? undefined,
        assinaturaUrl: signatureData ?? undefined,
        // Hora gravada pelo servidor: é a que consta no hash e no recibo.
        signedAt: data.signed_at ?? signedAt,
      });

      if (status === "entregue") {
        setStep("complete");
        const msg = substituicaoDetectada 
          ? "Entrega registrada e EPI anterior marcado como devolvido!"
          : "Entrega registrada com sucesso!";
        toast.success(msg);
      } else {
        toast.warning("Recusa registrada. Uma advertência foi criada.");
        handleClose();
      }

      onSuccess();
    } catch (error: any) {
      toast.error("Erro ao salvar entrega: " + error.message);
    } finally {
      setIsLoading(false);
    }
  };

  // Handlers de colaborador
  const handleColaboradorChange = (colaboradorId: string) => {
    const colaborador = colaboradores.find((c) => c.id === colaboradorId);
    if (colaborador) {
      setFormData((prev) => ({
        ...prev,
        colaboradorId,
        colaboradorNome: colaborador.nome_completo,
        colaboradorCpf: colaborador.cpf || "",
        colaboradorCargo: colaborador.cargo || "",
        colaboradorDepartamento: colaborador.departamento || "",
      }));

      // CT-26: Buscar EPIs sugeridos pela matriz de proteção para esta função
      if (colaborador.cargo && tenantId) {
        supabase
          .from("funcao_epis")
          .select("epi_tipo_id, obrigatorio, epi_tipo:epi_tipos(id, nome)")
          .eq("tenant_id", tenantId)
          .eq("cargo_id", colaborador.cargo)
          .then(({ data }) => {
            if (data && data.length > 0) {
              setEpisSugeridos(
                data.map((d: any) => ({
                  epi_tipo_id: d.epi_tipo_id,
                  nome: d.epi_tipo?.nome || "—",
                  obrigatorio: d.obrigatorio,
                }))
              );
            } else {
              setEpisSugeridos([]);
            }
          });
      }

      // CT-34: Buscar entregas ativas deste colaborador
      if (tenantId) {
        supabase
          .from("epi_entregas")
          .select("id, epi_id, data_entrega, epi:epis(tipo_id, tipo:epi_tipos(id, nome))")
          .eq("tenant_id", tenantId)
          .eq("employee_id", colaboradorId)
          .eq("status", "ativa")
          .then(({ data }) => {
            if (data) {
              setEntregasAtivas(
                data.map((d: any) => ({
                  id: d.id,
                  epi_tipo_id: d.epi?.tipo_id || "",
                  epi_tipo_nome: d.epi?.tipo?.nome || "EPI",
                  data_entrega: d.data_entrega,
                }))
              );
            } else {
              setEntregasAtivas([]);
            }
          });
      }
    }
  };

  // Handler de EPI
  const handleEpiChange = (epiTipoId: string) => {
    const tipo = epiTipos.find((t) => t.id === epiTipoId);
    if (tipo) {
      const dataValidade = tipo.validade_meses
        ? format(addDays(new Date(formData.dataEntrega), tipo.validade_meses * 30), "yyyy-MM-dd")
        : "";
      
      setFormData((prev) => ({
        ...prev,
        epiTipoId,
        epiTipo: tipo,
        dataValidade,
      }));

      // CT-34: Detectar substituição (entrega ativa do mesmo tipo)
      const entregaExistente = entregasAtivas.find((e) => e.epi_tipo_id === epiTipoId);
      setSubstituicaoDetectada(entregaExistente || null);
    }
  };

  // CT-13: Verificar se o CA do EPI selecionado está vencido
  const isCAVencido = useMemo(() => {
    if (!formData.epiTipo?.ca_validade) return false;
    return new Date(formData.epiTipo.ca_validade) < new Date();
  }, [formData.epiTipo]);

  // CT-32: Verificar se o EPI é irregular (sem CA cadastrado)
  const isEPIIrregular = useMemo(() => {
    if (!formData.epiTipo) return false;
    return !formData.epiTipo.ca_numero;
  }, [formData.epiTipo]);

  // CT-12: Verificar saldo de estoque disponível
  const [saldoDisponivel, setSaldoDisponivel] = useState<number | null>(null);
  const [verificandoSaldo, setVerificandoSaldo] = useState(false);

  useEffect(() => {
    const verificarSaldo = async () => {
      if (!formData.epiTipoId || !tenantId) {
        setSaldoDisponivel(null);
        return;
      }
      setVerificandoSaldo(true);
      try {
        const { data: epiRow } = await supabase
          .from("epis")
          .select("quantidade_estoque")
          .eq("tipo_id", formData.epiTipoId)
          .eq("tenant_id", tenantId)
          .order("created_at", { ascending: true })
          .limit(1)
          .maybeSingle();
        
        setSaldoDisponivel(epiRow?.quantidade_estoque ?? 0);
      } catch {
        setSaldoDisponivel(null);
      } finally {
        setVerificandoSaldo(false);
      }
    };
    verificarSaldo();
  }, [formData.epiTipoId, tenantId]);

  const isSaldoInsuficiente = saldoDisponivel !== null && formData.quantidade > saldoDisponivel;

  // Gerar PDF e retornar como Blob (para arquivamento)
  const generatePDFBlob = useCallback(async (): Promise<Blob | null> => {
    if (!reciboRef.current) return null;

    try {
      const canvas = await html2canvas(reciboRef.current, { scale: 2, useCORS: true });
      const pdf = new jsPDF("p", "mm", "a4");
      const imgData = canvas.toDataURL("image/png");
      const pdfWidth = pdf.internal.pageSize.getWidth();
      const pdfHeight = (canvas.height * pdfWidth) / canvas.width;
      pdf.addImage(imgData, "PNG", 0, 0, pdfWidth, pdfHeight);
      return pdf.output("blob");
    } catch (error) {
      console.error("Erro ao gerar PDF blob:", error);
      return null;
    }
  }, []);

  // Gerar PDF e baixar localmente
  const generatePDF = async () => {
    if (!reciboRef.current) return;

    try {
      const canvas = await html2canvas(reciboRef.current, { scale: 2, useCORS: true });
      const pdf = new jsPDF("p", "mm", "a4");
      const imgData = canvas.toDataURL("image/png");
      const pdfWidth = pdf.internal.pageSize.getWidth();
      const pdfHeight = (canvas.height * pdfWidth) / canvas.width;
      pdf.addImage(imgData, "PNG", 0, 0, pdfWidth, pdfHeight);
      pdf.save(`recibo-epi-${formData.colaboradorNome}-${format(new Date(), "yyyy-MM-dd")}.pdf`);
      toast.success("PDF gerado com sucesso!");
    } catch (error) {
      toast.error("Erro ao gerar PDF");
    }
  };

  // Arquivar PDF no módulo de documentos
  const arquivarPDFDocumentos = useCallback(async () => {
    if (!reciboRef.current || !formData.colaboradorId) return;

    try {
      // Aguardar um momento para garantir que o recibo esteja renderizado
      await new Promise((resolve) => setTimeout(resolve, 500));
      
      const pdfBlob = await generatePDFBlob();
      if (!pdfBlob) {
        console.warn("Não foi possível gerar o PDF para arquivamento");
        return;
      }

      const fileName = `Recibo EPI - ${formData.epiTipo?.nome || "EPI"} - ${format(new Date(formData.dataEntrega), "dd-MM-yyyy")}.pdf`;
      const file = new File([pdfBlob], fileName, { type: "application/pdf" });

      await uploadDocumento({
        file,
        colaboradorNome: formData.colaboradorNome,
        colaboradorCpf: formData.colaboradorCpf,
        colaboradorId: formData.colaboradorId,
        tipo: "Recibo de EPI",
        observacoes: `Entrega de ${formData.quantidade}x ${formData.epiTipo?.nome || "EPI"}${formData.epiTipo?.ca_numero ? ` (CA: ${formData.epiTipo.ca_numero})` : ""}. Assinado digitalmente.`,
      });

      toast.success("Recibo arquivado na pasta do colaborador!");
    } catch (error: any) {
      console.error("Erro ao arquivar PDF:", error);
      // Não exibir erro ao usuário - o documento pode ser gerado manualmente se necessário
    }
  }, [formData, generatePDFBlob, uploadDocumento]);

  // Arquivar PDF automaticamente quando o step muda para "complete"
  useEffect(() => {
    if (step === "complete" && entregaResult && !pdfArquivado) {
      setPdfArquivado(true);
      // Aguardar um pouco para o recibo renderizar antes de arquivar
      const timer = setTimeout(() => {
        arquivarPDFDocumentos();
      }, 1000);
      return () => clearTimeout(timer);
    }
  }, [step, entregaResult, pdfArquivado, arquivarPDFDocumentos]);

  const selectedTamanhos = formData.epiTipoId ? getTamanhosForTipo(formData.epiTipoId) : [];
  const requiresTamanho = selectedTamanhos.length > 0;

  // CT-13/32/12: Bloquear avanço se CA vencido, EPI irregular ou saldo insuficiente
  const canProceedFromForm = 
    formData.colaboradorId && 
    formData.epiTipoId && 
    formData.quantidade > 0 && 
    formData.dataEntrega &&
    (!usarControleEstoque || formData.localEstoqueId) &&
    (!requiresTamanho || formData.tamanho) &&
    !isCAVencido &&
    !isEPIIrregular &&
    !isSaldoInsuficiente;

  return (
    <>
      <Dialog open={open} onOpenChange={handleClose}>
        <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-2xl">
          <DialogHeader>
            <DialogTitle>Nova Entrega de EPI</DialogTitle>
          </DialogHeader>

          {/* Progress bar */}
          <div className="mb-4">
            <div className="mb-2 flex justify-between text-xs text-muted-foreground">
              {steps.map((s, i) => (
                <span
                  key={s}
                  className={i <= currentStepIndex ? "font-medium text-primary" : ""}
                >
                  {stepLabels[s]}
                </span>
              ))}
            </div>
            <Progress value={progress} className="h-2" />
          </div>

          {/* Step content */}
          <div className="min-h-[400px]">
            {step === "form" && (
              <div className="space-y-4">
                {/* Alerta se não houver colaboradores */}
                {!colaboradoresLoading && colaboradores.length === 0 && (
                  <div className="rounded-lg border border-destructive/50 bg-destructive/10 p-4">
                    <div className="flex items-start gap-3">
                      <AlertCircle className="h-5 w-5 text-destructive mt-0.5" />
                      <div>
                        <p className="font-medium text-destructive">Nenhum colaborador cadastrado</p>
                        <p className="text-sm text-muted-foreground mt-1">
                          Para registrar entregas de EPI, é necessário ter colaboradores com admissão concluída. 
                          Acesse o menu "Admissão" para cadastrar novos colaboradores.
                        </p>
                      </div>
                    </div>
                  </div>
                )}

                {/* Seleção de colaborador com busca */}
                <div className="space-y-2">
                  <Label>Colaborador *</Label>
                  <Popover open={colaboradorPopoverOpen} onOpenChange={setColaboradorPopoverOpen}>
                    <PopoverTrigger asChild>
                      <Button
                        variant="outline"
                        role="combobox"
                        aria-expanded={colaboradorPopoverOpen}
                        className="w-full justify-between font-normal"
                        disabled={colaboradores.length === 0}
                      >
                        {formData.colaboradorId ? (
                          <span className="flex items-center gap-2">
                            <User className="h-4 w-4 text-muted-foreground" />
                            {formData.colaboradorNome}
                          </span>
                        ) : (
                          <span className="text-muted-foreground">Buscar colaborador...</span>
                        )}
                        <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
                      </Button>
                    </PopoverTrigger>
                    <PopoverContent className="w-[400px] p-0" align="start">
                      <Command shouldFilter={false}>
                        <CommandInput 
                          placeholder="Buscar por nome ou CPF..." 
                          value={colaboradorSearch}
                          onValueChange={setColaboradorSearch}
                        />
                        <CommandList>
                          <CommandEmpty>Nenhum colaborador encontrado.</CommandEmpty>
                          <CommandGroup>
                            {filteredColaboradores.map((c) => (
                              <CommandItem
                                key={c.id}
                                value={c.id}
                                onSelect={() => {
                                  handleColaboradorChange(c.id);
                                  setColaboradorPopoverOpen(false);
                                  setColaboradorSearch("");
                                }}
                              >
                                <Check
                                  className={cn(
                                    "mr-2 h-4 w-4",
                                    formData.colaboradorId === c.id ? "opacity-100" : "opacity-0"
                                  )}
                                />
                                <div className="flex flex-col">
                                  <div className="flex items-center gap-2">
                                    <span>{c.nome_completo}</span>
                                    <AfastadoBadge afastamento={getAfastamento({ cpf: c.cpf, nome: c.nome_completo })} compact />
                                  </div>
                                  <span className="text-xs text-muted-foreground">
                                    CPF: {c.cpf} {c.cargo && `• ${c.cargo}`}
                                  </span>
                                </div>
                              </CommandItem>
                            ))}
                          </CommandGroup>
                        </CommandList>
                      </Command>
                    </PopoverContent>
                  </Popover>
                </div>

                {/* Dados do colaborador selecionado (somente leitura) */}
                {formData.colaboradorId && (
                  <div className="rounded-lg border bg-muted/50 p-4 space-y-3">
                    <p className="text-sm font-medium text-muted-foreground">Dados do Colaborador</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      <div>
                        <Label className="text-xs text-muted-foreground">Nome Completo</Label>
                        <p className="text-sm font-medium">{formData.colaboradorNome}</p>
                      </div>
                      <div>
                        <Label className="text-xs text-muted-foreground">CPF</Label>
                        <p className="text-sm font-medium">{formData.colaboradorCpf}</p>
                      </div>
                      <div>
                        <Label className="text-xs text-muted-foreground">Cargo</Label>
                        <p className="text-sm font-medium">{formData.colaboradorCargo || "—"}</p>
                      </div>
                      <div>
                        <Label className="text-xs text-muted-foreground">Departamento</Label>
                        <p className="text-sm font-medium">{formData.colaboradorDepartamento || "—"}</p>
                      </div>
                    </div>
                  </div>
                )}

                {/* CT-26: Sugestões de EPI pela Matriz de Proteção */}
                {formData.colaboradorId && episSugeridos.length > 0 && (
                  <div className="rounded-lg border border-primary/30 bg-primary/5 p-3 space-y-2">
                    <p className="text-xs font-medium text-primary flex items-center gap-1.5">
                      <AlertCircle className="h-3.5 w-3.5" />
                      EPIs recomendados pela Matriz de Proteção para esta função:
                    </p>
                    <div className="flex flex-wrap gap-1.5">
                      {episSugeridos.map((s) => (
                        <Badge
                          key={s.epi_tipo_id}
                          variant={s.obrigatorio ? "default" : "secondary"}
                          className="cursor-pointer text-xs"
                          onClick={() => handleEpiChange(s.epi_tipo_id)}
                        >
                          {s.nome} {s.obrigatorio && "★"}
                        </Badge>
                      ))}
                    </div>
                  </div>
                )}

                {/* Seleção de EPI */}
                <div className="space-y-2">
                  <Label>Tipo de EPI *</Label>
                  <Select
                    value={formData.epiTipoId}
                    onValueChange={handleEpiChange}
                  >
                    <SelectTrigger>
                      <SelectValue placeholder="Selecione o EPI" />
                    </SelectTrigger>
                    <SelectContent>
                      {epiTipos.filter(t => t.is_active !== false).map((t) => (
                        <SelectItem key={t.id} value={t.id}>
                          {t.nome}
                          {t.ca_numero && ` (CA: ${t.ca_numero})`}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>

                {/* CT-34: Alerta de substituição — EPI do mesmo tipo já entregue */}
                {substituicaoDetectada && (
                  <div className="rounded-lg border border-amber-500/50 bg-amber-500/10 p-3">
                    <div className="flex items-start gap-2">
                      <AlertCircle className="h-4 w-4 text-amber-600 mt-0.5 shrink-0" />
                      <div>
                        <p className="text-sm font-medium text-amber-700 dark:text-amber-400">
                          Substituição detectada
                        </p>
                        <p className="text-xs text-muted-foreground mt-0.5">
                          Este colaborador já possui uma entrega ativa de <strong>{substituicaoDetectada.epi_tipo_nome}</strong> (entregue em {format(new Date(substituicaoDetectada.data_entrega), "dd/MM/yyyy")}).
                          Ao confirmar, a entrega anterior será devolvida junto com esta. O que fazer com o EPI antigo?
                        </p>
                      </div>
                    </div>
                    <RadioGroup
                      value={destinoSubstituicao}
                      onValueChange={(v) => setDestinoSubstituicao(v as "descarte" | "estoque" | "manutencao")}
                      className="mt-3 gap-2"
                    >
                      <div className="flex items-start gap-2">
                        <RadioGroupItem id="subst-descarte" value="descarte" className="mt-0.5" />
                        <Label htmlFor="subst-descarte" className="text-xs font-normal leading-snug">
                          <strong>Descartar</strong>: desgastado, danificado ou vencido (recomendado).
                        </Label>
                      </div>
                      <div className="flex items-start gap-2">
                        <RadioGroupItem id="subst-manutencao" value="manutencao" className="mt-0.5" />
                        <Label htmlFor="subst-manutencao" className="text-xs font-normal leading-snug">
                          <strong>Enviar para manutenção</strong>: fica no local Em Manutenção.
                        </Label>
                      </div>
                      <div className="flex items-start gap-2">
                        <RadioGroupItem id="subst-estoque" value="estoque" className="mt-0.5" />
                        <Label htmlFor="subst-estoque" className="text-xs font-normal leading-snug">
                          <strong>Voltar ao estoque</strong>: só se estiver em bom estado e puder ser reutilizado.
                        </Label>
                      </div>
                    </RadioGroup>
                  </div>
                )}

                {/* CT-13: Alerta de CA vencido — BLOQUEANTE */}
                {isCAVencido && (
                  <div className="rounded-lg border border-destructive bg-destructive/10 p-4">
                    <div className="flex items-start gap-3">
                      <AlertCircle className="h-5 w-5 text-destructive mt-0.5 shrink-0" />
                      <div>
                        <p className="font-medium text-destructive">CA Vencido — Entrega Bloqueada</p>
                        <p className="text-sm text-muted-foreground mt-1">
                          O Certificado de Aprovação deste EPI expirou em{" "}
                          <strong>{formData.epiTipo?.ca_validade ? format(new Date(formData.epiTipo.ca_validade), "dd/MM/yyyy") : "—"}</strong>.
                          Conforme a NR-06, é proibido entregar EPI com CA vencido. Atualize o CA antes de prosseguir.
                        </p>
                      </div>
                    </div>
                  </div>
                )}

                {/* CT-32: Alerta de EPI irregular (sem CA) — BLOQUEANTE */}
                {isEPIIrregular && !isCAVencido && (
                  <div className="rounded-lg border border-destructive bg-destructive/10 p-4">
                    <div className="flex items-start gap-3">
                      <AlertCircle className="h-5 w-5 text-destructive mt-0.5 shrink-0" />
                      <div>
                        <p className="font-medium text-destructive">EPI sem CA — Entrega Bloqueada</p>
                        <p className="text-sm text-muted-foreground mt-1">
                          Este EPI não possui Certificado de Aprovação (CA) cadastrado. 
                          Conforme a NR-06 (6.2), todo EPI deve possuir CA válido. Cadastre o CA antes de prosseguir.
                        </p>
                      </div>
                    </div>
                  </div>
                )}

                {/* CT-12: Alerta de saldo insuficiente — BLOQUEANTE */}
                {isSaldoInsuficiente && !isCAVencido && !isEPIIrregular && (
                  <div className="rounded-lg border border-orange-500/50 bg-orange-500/10 p-4">
                    <div className="flex items-start gap-3">
                      <AlertCircle className="h-5 w-5 text-orange-600 mt-0.5 shrink-0" />
                      <div>
                        <p className="font-medium text-orange-700 dark:text-orange-400">Saldo Insuficiente — Entrega Bloqueada</p>
                        <p className="text-sm text-muted-foreground mt-1">
                          Estoque disponível: <strong>{saldoDisponivel}</strong> unidade(s). Quantidade solicitada: <strong>{formData.quantidade}</strong>.
                          Reduza a quantidade ou registre uma entrada de estoque antes de prosseguir.
                        </p>
                      </div>
                    </div>
                  </div>
                )}

                {/* Saldo disponível (informativo, quando não bloqueante) */}
                {saldoDisponivel !== null && !isSaldoInsuficiente && formData.epiTipoId && !isCAVencido && !isEPIIrregular && (
                  <p className="text-xs text-muted-foreground">
                    Saldo em estoque: <strong>{saldoDisponivel}</strong> unidade(s)
                  </p>
                )}

                {usarControleEstoque && (
                  <div className="space-y-2">
                    <Label className="flex items-center gap-1.5">
                      <MapPin className="w-4 h-4 text-muted-foreground" />
                      Local de Estoque {usarControleEstoque ? "*" : ""}
                    </Label>
                    <Select
                      value={formData.localEstoqueId}
                      onValueChange={(val) =>
                        setFormData((prev) => ({ ...prev, localEstoqueId: val }))
                      }
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Selecione o local de saída" />
                      </SelectTrigger>
                      <SelectContent>
                        {locaisAtivos.map((local) => (
                          <SelectItem key={local.id} value={local.id}>
                            {local.nome} {local.filial?.nome ? `(${local.filial.nome})` : ""}
                          </SelectItem>
                        ))}
                        {locaisAtivos.length === 0 && (
                          <div className="px-2 py-1.5 text-sm text-muted-foreground">
                            Nenhum local cadastrado. Vá em Config para criar.
                          </div>
                        )}
                      </SelectContent>
                    </Select>
                  </div>
                )}

                {/* Seleção de Tamanho (se EPI controla tamanho) */}
                {formData.epiTipoId && getTamanhosForTipo(formData.epiTipoId).length > 0 && (
                  <div className="space-y-2">
                    <Label>Tamanho *</Label>
                    <Select
                      value={formData.tamanho}
                      onValueChange={(val) =>
                        setFormData((prev) => ({ ...prev, tamanho: val }))
                      }
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Selecione o tamanho" />
                      </SelectTrigger>
                      <SelectContent>
                        {getTamanhosForTipo(formData.epiTipoId).map((t) => (
                          <SelectItem key={t.id} value={t.tamanho}>
                            {t.tamanho}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                )}

                <div className="grid gap-4 sm:grid-cols-3">
                  <div className="space-y-2">
                    <Label>Quantidade *</Label>
                    <Input
                      type="number"
                      min={1}
                      value={formData.quantidade}
                      onChange={(e) =>
                        setFormData((prev) => ({
                          ...prev,
                          quantidade: parseInt(e.target.value) || 1,
                        }))
                      }
                    />
                  </div>

                  <div className="space-y-2">
                    <Label>Data de Entrega *</Label>
                    <Input
                      type="date"
                      value={formData.dataEntrega}
                      onChange={(e) => {
                        const newDate = e.target.value;
                        const tipo = formData.epiTipo;
                        const dataValidade = tipo?.validade_meses
                          ? format(addDays(new Date(newDate), tipo.validade_meses * 30), "yyyy-MM-dd")
                          : "";
                        setFormData((prev) => ({
                          ...prev,
                          dataEntrega: newDate,
                          dataValidade,
                        }));
                      }}
                    />
                  </div>

                  <div className="space-y-2">
                    <Label>Data de Validade</Label>
                    <Input
                      type="date"
                      value={formData.dataValidade}
                      onChange={(e) =>
                        setFormData((prev) => ({ ...prev, dataValidade: e.target.value }))
                      }
                    />
                  </div>
                </div>

                <div className="space-y-2">
                  <Label>Observações</Label>
                  <Textarea
                    placeholder="Observações sobre a entrega..."
                    value={formData.observacoes}
                    onChange={(e) =>
                      setFormData((prev) => ({ ...prev, observacoes: e.target.value }))
                    }
                  />
                </div>

                <div className="flex gap-2 pt-4">
                  <Button
                    variant="destructive"
                    onClick={() => setShowRecusaDialog(true)}
                    disabled={!canProceedFromForm}
                  >
                    <XCircle className="mr-2 h-4 w-4" />
                    Colaborador Recusou
                  </Button>
                  <div className="flex-1" />
                  <Button
                    onClick={() => setStep("liveness")}
                    disabled={!canProceedFromForm}
                  >
                    Próximo
                    <ArrowRight className="ml-2 h-4 w-4" />
                  </Button>
                </div>
              </div>
            )}

            {step === "liveness" && (
              <div className="space-y-4">
                <LivenessDetection
                  onComplete={(data) => {
                    setLivenessData(data);
                    setStep("photo");
                  }}
                />
                <div className="flex gap-2 pt-4">
                  <Button variant="outline" onClick={() => setStep("form")}>
                    <ArrowLeft className="mr-2 h-4 w-4" />
                    Voltar
                  </Button>
                </div>
              </div>
            )}

            {step === "photo" && (
              <div className="space-y-4">
                <PhotoCapture
                  onCapture={(data) => {
                    setPhotoData(data);
                    setStep("signature");
                  }}
                />
                <div className="flex gap-2 pt-4">
                  <Button variant="outline" onClick={() => setStep("liveness")}>
                    <ArrowLeft className="mr-2 h-4 w-4" />
                    Voltar
                  </Button>
                </div>
              </div>
            )}

            {step === "signature" && (
              <div className="space-y-4">
                <SignatureCapture
                  colaboradorNome={formData.colaboradorNome}
                  onCapture={(data) => {
                    setSignatureData(data);
                    saveEntrega("entregue");
                  }}
                />
                {isLoading && (
                  <div className="flex items-center justify-center gap-2 text-muted-foreground">
                    <Loader2 className="h-4 w-4 animate-spin" />
                    Salvando entrega...
                  </div>
                )}
                <div className="flex gap-2 pt-4">
                  <Button variant="outline" onClick={() => setStep("photo")} disabled={isLoading}>
                    <ArrowLeft className="mr-2 h-4 w-4" />
                    Voltar
                  </Button>
                </div>
              </div>
            )}

            {step === "complete" && (
              <div className="space-y-4">
                <div className="rounded-lg border bg-muted/30 p-4">
                  <EpiEntregaRecibo
                    ref={reciboRef}
                    data={{
                      colaboradorNome: formData.colaboradorNome,
                      colaboradorCpf: formData.colaboradorCpf,
                      colaboradorCargo: formData.colaboradorCargo,
                      colaboradorDepartamento: formData.colaboradorDepartamento,
                      epiNome: formData.epiTipo?.nome || "",
                      epiCa: formData.epiTipo?.ca_numero || undefined,
                      epiFabricante: formData.epiTipo?.fabricante || undefined,
                      epiMarca: formData.epiTipo?.marca || undefined,
                      quantidade: formData.quantidade,
                      dataEntrega: formData.dataEntrega,
                      dataValidade: formData.dataValidade,
                      observacoes: formData.observacoes,
                      fotoUrl: entregaResult?.fotoUrl,
                      assinaturaUrl: entregaResult?.assinaturaUrl,
                      signedAt: entregaResult?.signedAt,
                      entregueporNome: profile?.nome_completo,
                    }}
                  />
                </div>

                <div className="flex justify-center gap-2">
                  <Button onClick={generatePDF}>
                    <Download className="mr-2 h-4 w-4" />
                    Baixar PDF
                  </Button>
                  <Button variant="outline" onClick={handleClose}>
                    Fechar
                  </Button>
                </div>
              </div>
            )}
          </div>
        </DialogContent>
      </Dialog>

      {/* Dialog de confirmação de recusa */}
      <AlertDialog open={showRecusaDialog} onOpenChange={setShowRecusaDialog}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Confirmar Recusa</AlertDialogTitle>
            <AlertDialogDescription>
              O colaborador <strong>{formData.colaboradorNome}</strong> está recusando
              assinar o recebimento do EPI. Isso será registrado como advertência no
              sistema de RH.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                setShowRecusaDialog(false);
                saveEntrega("recusado");
              }}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              Confirmar Recusa
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
