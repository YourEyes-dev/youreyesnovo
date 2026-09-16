import { useState, useEffect, useMemo, useRef } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Loader2, ShieldAlert, Zap, Clock, User, Camera, Trash2 } from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { CpfInput } from "@/components/ui/cpf-input";
import { PhoneInput } from "@/components/ui/phone-input";
import { useDepartamentos, useCargos, useFiliais } from "@/hooks/useCadastros";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { toast } from "sonner";
import { useQueryClient } from "@tanstack/react-query";
import { validateCpf, cleanCpf } from "@/lib/cpf";
import { EmpresaAtivaBanner } from "@/components/ui/empresa-ativa-banner";
import { CargoComboboxField } from "@/components/colaboradores/CargoComboboxField";
import { GestorComboboxField } from "@/components/colaboradores/GestorComboboxField";
import { useStorageImageUrl } from "@/hooks/useStorageImageUrl";
import { CBOAutocomplete, normalizeCBO } from "@/components/cbo/CBOAutocomplete";
import { DOCUMENTOS_OBRIGATORIOS, type DocumentoStatus } from "@/types/database";

const TIPOS_VINCULO = [
  { value: "clt", label: "Empregado CLT" },
  { value: "temporario", label: "Temporário" },
  { value: "aprendiz", label: "Aprendiz" },
  { value: "estagiario", label: "Estagiário" },
  { value: "intermitente", label: "Intermitente" },
];

const formSchema = z.object({
  nome_completo: z.string().min(3, "Nome deve ter pelo menos 3 caracteres"),
  cpf: z.string()
    .min(11, "CPF deve ter 11 dígitos")
    .refine((val) => cleanCpf(val).length === 11, "CPF deve ter 11 dígitos")
    .refine((val) => validateCpf(val), "CPF inválido - verifique os dígitos"),
  email: z.string().trim().email("Email inválido").optional().or(z.literal("")),
  celular: z.string().optional(),
  tipo_contrato: z.string().min(1, "Selecione o tipo de vínculo"),
  cargo: z.string().min(1, "Selecione um cargo"),
  departamento: z.string().optional(),
  estabelecimento: z.string().optional(),
  centro_custo: z.string().optional(),
  gestor_imediato: z.string().optional(),
  data_admissao: z.string().min(1, "Data de admissão é obrigatória"),
  matricula_esocial: z.string().optional(),
  cbo: z.string().optional(),
  foto_url: z.string().optional(),
  bate_ponto: z.boolean().default(true),
  // Art. 62 da CLT: enquadramento que DISPENSA o controle de jornada.
  art62_inciso: z.string().optional(),
  art62_documento: z.string().optional(),
  teletrabalho_modalidade: z.string().optional(),
});

type FormData = z.infer<typeof formSchema>;

export interface ColaboradorEditData {
  id: string;
  nome_completo: string;
  cpf: string;
  email: string;
  celular: string | null;
  tipo_contrato: string | null;
  cargo: string;
  departamento: string | null;
  filial: string | null;
  centro_custo: string | null;
  gestor_imediato: string | null;
  data_admissao: string | null;
  matricula_esocial?: string | null;
  cbo?: string | null;
  foto_url?: string | null;
  bate_ponto?: boolean | null;
  art62_inciso?: string | null;
  art62_documento?: string | null;
  teletrabalho_modalidade?: string | null;
}

interface ColaboradorFormProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSuccess?: () => void;
  colaborador?: ColaboradorEditData | null;
}

export function ColaboradorForm({ open, onOpenChange, onSuccess, colaborador }: ColaboradorFormProps) {
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isUploading, setIsUploading] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const { tenantId, user } = useAuth();
  const queryClient = useQueryClient();
  const { departamentos } = useDepartamentos();
  const { cargos } = useCargos();
  const { filiais } = useFiliais();
  const { empresaAtivaId } = useEmpresaAtiva();

  const isEditMode = !!colaborador;

  const departamentosOptions = departamentos.filter(
    (d) => typeof d?.nome === "string" && d.nome.trim().length > 0,
  );
  const estabelecimentosOptions = filiais.filter(
    (f) => typeof f?.nome === "string" && f.nome.trim().length > 0 &&
      (!empresaAtivaId || f.empresa_id === empresaAtivaId),
  );

  const form = useForm<FormData>({
    resolver: zodResolver(formSchema),
    defaultValues: {
      nome_completo: "",
      cpf: "",
      email: "",
      celular: "",
      tipo_contrato: "clt",
      cargo: "",
      departamento: "",
      estabelecimento: "",
      centro_custo: "",
      gestor_imediato: "",
      data_admissao: new Date().toISOString().split("T")[0],
      matricula_esocial: "",
      cbo: "",
      foto_url: "",
      bate_ponto: true,
      art62_inciso: "nenhum",
      art62_documento: "",
      teletrabalho_modalidade: "nao_se_aplica",
    },
  });
  const resolvedPhotoUrl = useStorageImageUrl(form.watch("foto_url"), "documentos");

  useEffect(() => {
    if (open && colaborador) {
      form.reset({
        nome_completo: colaborador.nome_completo || "",
        cpf: colaborador.cpf || "",
        email: colaborador.email || "",
        celular: colaborador.celular || "",
        tipo_contrato: colaborador.tipo_contrato || "clt",
        cargo: colaborador.cargo || "",
        departamento: colaborador.departamento || "",
        estabelecimento: colaborador.filial || "",
        centro_custo: colaborador.centro_custo || "",
        gestor_imediato: colaborador.gestor_imediato || "",
        data_admissao: colaborador.data_admissao || "",
        matricula_esocial: colaborador.matricula_esocial || "",
        cbo: colaborador.cbo || "",
        foto_url: colaborador.foto_url || "",
        bate_ponto: colaborador.bate_ponto !== false,
        art62_inciso: colaborador.art62_inciso || "nenhum",
        art62_documento: colaborador.art62_documento || "",
        teletrabalho_modalidade: colaborador.teletrabalho_modalidade || "nao_se_aplica",
      });
    } else if (open && !colaborador) {
      form.reset({
        nome_completo: "",
        cpf: "",
        email: "",
        celular: "",
        tipo_contrato: "clt",
        cargo: "",
        departamento: "",
        estabelecimento: "",
        centro_custo: "",
        gestor_imediato: "",
        data_admissao: new Date().toISOString().split("T")[0],
        matricula_esocial: "",
        cbo: "",
        foto_url: "",
        bate_ponto: true,
      art62_inciso: "nenhum",
      art62_documento: "",
      teletrabalho_modalidade: "nao_se_aplica",
      });
    }
  }, [open, colaborador, form]);

  const handleUploadPhoto = async (file: File) => {
    if (!tenantId) return;
    setIsUploading(true);
    try {
      const fileExt = file.name.split('.').pop();
      const fileName = `${tenantId}/${Math.random()}.${fileExt}`;
      const filePath = `colaboradores/fotos/${fileName}`;

      const { error: uploadError } = await supabase.storage
        .from("documentos")
        .upload(filePath, file, {
          cacheControl: '3600',
          upsert: true
        });

      if (uploadError) throw uploadError;

      form.setValue("foto_url", filePath);
      toast.success("Foto carregada com sucesso!");
    } catch (error) {
      console.error("Erro no upload:", error);
      toast.error("Erro ao carregar foto");
    } finally {
      setIsUploading(false);
    }
  };

  const onSubmit = async (data: FormData) => {
    if (!tenantId) {
      toast.error("Erro: Tenant não identificado");
      return;
    }
    setIsSubmitting(true);
    try {
      if (isEditMode && colaborador) {
        const payload = {
          nome_completo: data.nome_completo,
          cpf: cleanCpf(data.cpf),
          email: data.email?.trim() || null,
          celular: data.celular || null,
          tipo_contrato: data.tipo_contrato,
          cargo: data.cargo,
          departamento: data.departamento || null,
          filial: data.estabelecimento || null,
          centro_custo: data.centro_custo || null,
          gestor_imediato: data.gestor_imediato || null,
          data_admissao: data.data_admissao,
          matricula_esocial: data.matricula_esocial || null,
          cbo: normalizeCBO(data.cbo) || null,
          foto_url: data.foto_url || null,
          bate_ponto: data.bate_ponto,
          art62_inciso: data.art62_inciso && data.art62_inciso !== "nenhum" ? data.art62_inciso : null,
          art62_documento: data.art62_documento?.trim() || null,
          teletrabalho_modalidade:
            data.teletrabalho_modalidade && data.teletrabalho_modalidade !== "nao_se_aplica"
              ? data.teletrabalho_modalidade
              : null,
        };

        const { data: updatedRow, error } = await supabase
          .from("admissoes")
          .update(payload)
          .eq("id", colaborador.id)
          .eq("tenant_id", tenantId)
          .select("id, centro_custo, gestor_imediato, matricula_esocial, cbo")
          .maybeSingle();

        if (error) {
          if (error.code === "23505") {
            toast.error("CPF ou email já cadastrado para outro colaborador");
          } else {
            throw error;
          }
          return;
        }

        if (!updatedRow) {
          throw new Error("Seu perfil não conseguiu confirmar a atualização deste colaborador. Verifique a permissão de edição e tente novamente.");
        }

        const persistedCbo = normalizeCBO(updatedRow.cbo);
        if (
          (updatedRow.centro_custo ?? null) !== (payload.centro_custo ?? null) ||
          (updatedRow.gestor_imediato ?? null) !== (payload.gestor_imediato ?? null) ||
          (updatedRow.matricula_esocial ?? null) !== (payload.matricula_esocial ?? null) ||
          persistedCbo !== normalizeCBO(payload.cbo)
        ) {
          throw new Error("Os dados não foram persistidos corretamente. Tente salvar novamente.");
        }

        toast.success("Colaborador atualizado com sucesso!");
      } else {
        const { data: insertData, error } = await supabase.from("admissoes").insert({
          tenant_id: tenantId,
          nome_completo: data.nome_completo,
          cpf: cleanCpf(data.cpf),
          email: data.email?.trim() || null,
          celular: data.celular || null,
          tipo_contrato: data.tipo_contrato,
          cargo: data.cargo,
          departamento: data.departamento || null,
          filial: data.estabelecimento || null,
          centro_custo: data.centro_custo || null,
          gestor_imediato: data.gestor_imediato || null,
          data_admissao: data.data_admissao,
          empresa_id: empresaAtivaId || null,
          status: "concluido",
          criado_por: user?.id,
          matricula_esocial: data.matricula_esocial || null,
          cbo: normalizeCBO(data.cbo) || null,
          foto_url: data.foto_url || null,
          bate_ponto: data.bate_ponto,
          art62_inciso: data.art62_inciso && data.art62_inciso !== "nenhum" ? data.art62_inciso : null,
          art62_documento: data.art62_documento?.trim() || null,
          teletrabalho_modalidade:
            data.teletrabalho_modalidade && data.teletrabalho_modalidade !== "nao_se_aplica"
              ? data.teletrabalho_modalidade
              : null,
        }).select("id").single();

        if (error) {
          if (error.code === "23505") {
            toast.error("CPF ou email já cadastrado");
          } else {
            throw error;
          }
          return;
        }

        // Create collaborator folder in Documents module
        if (insertData?.id) {
          try {
            await supabase.from("admissao_documentos").insert(
              DOCUMENTOS_OBRIGATORIOS.map((doc) => ({
                admissao_id: insertData.id,
                tenant_id: tenantId,
                nome: doc.nome,
                tipo: doc.tipo,
                obrigatorio: doc.obrigatorio,
                status: "pendente" as DocumentoStatus,
              }))
            );

            const { criarPastaColaborador } = await import("@/utils/criarPastaColaborador");
            await criarPastaColaborador({
              tenantId,
              colaboradorId: insertData.id,
              colaboradorNome: data.nome_completo,
              colaboradorCpf: cleanCpf(data.cpf),
              empresaId: empresaAtivaId || null,
            });
          } catch { /* non-blocking */ }
        }

        toast.success("Colaborador cadastrado com sucesso!");
      }

      queryClient.invalidateQueries({ queryKey: ["colaboradores"] });
      queryClient.invalidateQueries({ queryKey: ["colaboradores-list"] });
      form.reset();
      onOpenChange(false);
      onSuccess?.();
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : JSON.stringify(error);
      console.error("Erro ao salvar colaborador:", errMsg, error);
      toast.error(isEditMode ? `Erro ao atualizar colaborador: ${errMsg}` : `Erro ao cadastrar colaborador: ${errMsg}`);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[95vw] max-w-xl max-h-[92vh] flex flex-col gap-0 p-0 overflow-hidden">

        {/* Header fixo */}
        <div className="px-6 pt-5 pb-4 border-b shrink-0">
          <DialogHeader>
            <DialogTitle>{isEditMode ? "Editar Colaborador" : "Novo Colaborador"}</DialogTitle>
            <DialogDescription className="text-sm">
              {isEditMode
                ? "Atualize os dados do colaborador."
                : "Preencha os dados para cadastrar um novo colaborador."}
            </DialogDescription>
          </DialogHeader>
          <div className="mt-3">
            <EmpresaAtivaBanner />
          </div>
        </div>

        {/* Corpo scrollável */}
        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="flex flex-col flex-1 min-h-0">
            <div className="flex-1 overflow-y-auto px-6 py-4 space-y-4">

              {/* Foto */}
              <div className="flex flex-col items-center justify-center space-y-3 pb-4">
                <Avatar className="h-24 w-24 border-2 border-primary/10">
                  <AvatarImage src={resolvedPhotoUrl || ""} />
                  <AvatarFallback className="bg-primary/5 text-primary text-2xl">
                    <User className="h-12 w-12" />
                  </AvatarFallback>
                </Avatar>
                <div className="flex gap-2">
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    className="h-8 gap-1.5"
                    onClick={() => fileInputRef.current?.click()}
                    disabled={isUploading}
                  >
                    {isUploading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Camera className="h-3.5 w-3.5" />}
                    {form.watch("foto_url") ? "Alterar Foto" : "Adicionar Foto"}
                  </Button>
                  {form.watch("foto_url") && (
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      className="h-8 gap-1.5 text-destructive hover:text-destructive hover:bg-destructive/10"
                      onClick={() => form.setValue("foto_url", "")}
                      disabled={isUploading}
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </Button>
                  )}
                </div>
                <input
                  type="file"
                  ref={fileInputRef}
                  className="hidden"
                  accept="image/*"
                  onChange={(e) => {
                    const file = e.target.files?.[0];
                    if (file) handleUploadPhoto(file);
                  }}
                />
              </div>

              {/* Nome */}
              <FormField
                control={form.control}
                name="nome_completo"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Nome Completo *</FormLabel>
                    <FormControl>
                      <Input placeholder="João da Silva" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              {/* CPF | Celular */}
              <div className="grid grid-cols-2 gap-3">
                <FormField
                  control={form.control}
                  name="cpf"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>CPF *</FormLabel>
                      <FormControl>
                        <CpfInput value={field.value} onChange={field.onChange} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                <FormField
                  control={form.control}
                  name="celular"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Celular</FormLabel>
                      <FormControl>
                        <PhoneInput value={field.value} onChange={field.onChange} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>

              {/* Email */}
              <FormField
                control={form.control}
                name="email"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Email</FormLabel>
                    <FormControl>
                      <Input type="email" placeholder="email@empresa.com" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              {/* Tipo Vínculo | Data Admissão | Centro de Custo */}
              <div className="grid grid-cols-2 gap-3">
                <FormField
                  control={form.control}
                  name="tipo_contrato"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Tipo de Vínculo *</FormLabel>
                      <Select onValueChange={field.onChange} value={field.value}>
                        <FormControl>
                          <SelectTrigger>
                            <SelectValue placeholder="Selecione" />
                          </SelectTrigger>
                        </FormControl>
                        <SelectContent>
                          {TIPOS_VINCULO.map((tipo) => (
                            <SelectItem key={tipo.value} value={tipo.value}>
                              {tipo.label}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                <FormField
                  control={form.control}
                  name="data_admissao"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Data de Admissão *</FormLabel>
                      <FormControl>
                        <Input type="date" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>

              {/* Bate ponto */}
              <FormField
                control={form.control}
                name="bate_ponto"
                render={({ field }) => {
                  const tipo = (form.watch("tipo_contrato") || "").toLowerCase();
                  const naoCLT = ["pj", "prolabore", "pro_labore", "terceiro", "terceirizado", "autonomo"].includes(tipo);
                  return (
                    <FormItem className="flex items-center justify-between rounded-md border p-3">
                      <div className="space-y-0.5">
                        <FormLabel className="text-sm">Bate ponto eletrônico</FormLabel>
                        <p className="text-xs text-muted-foreground">
                          {naoCLT
                            ? "Vínculos PJ/terceiros normalmente não batem ponto. Ative apenas se houver acordo específico."
                            : "Define se este colaborador aparece no módulo de Ponto Eletrônico."}
                        </p>
                      </div>
                      <FormControl>
                        <Switch checked={field.value} onCheckedChange={field.onChange} />
                      </FormControl>
                    </FormItem>
                  );
                }}
              />


              {/* Art. 62 da CLT — dispensa de controle de jornada.
                  A regra de quem fica dispensado vive no banco
                  (ponto_art62_dispensa): teletrabalho por JORNADA continua
                  controlado mesmo com inciso marcado. Aqui só se declara o
                  enquadramento e o documento que o sustenta. */}
              <div className="rounded-md border p-3 space-y-3">
                <div>
                  <FormLabel className="text-sm">Dispensa de controle de jornada (art. 62 da CLT)</FormLabel>
                  <p className="text-xs text-muted-foreground">
                    Quem se enquadra no art. 62 não marca ponto — e, por isso, não pode receber
                    falta por não marcar. Deixe em "não se enquadra" quando houver dúvida: a
                    dispensa é exceção e precisa de documento que a sustente.
                  </p>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <FormField
                    control={form.control}
                    name="art62_inciso"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>Enquadramento</FormLabel>
                        <Select onValueChange={field.onChange} value={field.value}>
                          <FormControl>
                            <SelectTrigger><SelectValue placeholder="Não se enquadra" /></SelectTrigger>
                          </FormControl>
                          <SelectContent>
                            <SelectItem value="nenhum">Não se enquadra (marca ponto)</SelectItem>
                            <SelectItem value="I">I — atividade externa incompatível com controle</SelectItem>
                            <SelectItem value="II">II — cargo de gestão / confiança</SelectItem>
                            <SelectItem value="III">III — teletrabalho por produção ou tarefa</SelectItem>
                          </SelectContent>
                        </Select>
                        <FormMessage />
                      </FormItem>
                    )}
                  />

                  <FormField
                    control={form.control}
                    name="teletrabalho_modalidade"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>Teletrabalho</FormLabel>
                        <Select onValueChange={field.onChange} value={field.value}>
                          <FormControl>
                            <SelectTrigger><SelectValue placeholder="Não se aplica" /></SelectTrigger>
                          </FormControl>
                          <SelectContent>
                            <SelectItem value="nao_se_aplica">Não se aplica</SelectItem>
                            <SelectItem value="jornada">Por jornada (continua marcando ponto)</SelectItem>
                            <SelectItem value="producao">Por produção ou tarefa</SelectItem>
                          </SelectContent>
                        </Select>
                        <FormMessage />
                      </FormItem>
                    )}
                  />
                </div>

                <FormField
                  control={form.control}
                  name="art62_documento"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Documento que sustenta o enquadramento</FormLabel>
                      <FormControl>
                        <Input placeholder="Ex: contrato de trabalho, cláusula 5ª; aditivo de teletrabalho" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                {form.watch("teletrabalho_modalidade") === "jornada" &&
                  (form.watch("art62_inciso") || "nenhum") !== "nenhum" && (
                  <div className="rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
                    Teletrabalho <strong>por jornada</strong> continua sujeito ao controle de ponto
                    (Lei 14.442/2022), mesmo com o inciso marcado. O sistema mantém este
                    colaborador marcando ponto — o enquadramento fica registrado, mas não dispensa.
                  </div>
                )}
              </div>

              {/* Estabelecimento | Departamento */}
              <div className="grid grid-cols-2 gap-3">
                <FormField
                  control={form.control}
                  name="estabelecimento"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Estabelecimento / Obra</FormLabel>
                      <Select onValueChange={field.onChange} value={field.value}>
                        <FormControl>
                          <SelectTrigger>
                            <SelectValue placeholder="Selecione" />
                          </SelectTrigger>
                        </FormControl>
                        <SelectContent>
                          {estabelecimentosOptions.map((est) => (
                            <SelectItem key={est.id} value={est.nome.trim()}>
                              {est.nome}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                <FormField
                  control={form.control}
                  name="departamento"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Departamento</FormLabel>
                      <Select onValueChange={field.onChange} value={field.value}>
                        <FormControl>
                          <SelectTrigger>
                            <SelectValue placeholder="Selecione" />
                          </SelectTrigger>
                        </FormControl>
                        <SelectContent>
                          {departamentosOptions.map((dept) => (
                            <SelectItem key={dept.id} value={dept.nome.trim()}>
                              {dept.nome}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>

              {/* Função — linha inteira */}
              <FormField
                control={form.control}
                name="cargo"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Cargo *</FormLabel>
                    <FormControl>
                      <CargoComboboxField
                        value={field.value}
                        onChange={field.onChange}
                        disabled={isSubmitting}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              {/* SST Conditions Banner - inherited from cargo */}
              {(() => {
                const cargoSelecionado = cargos.find(c => c.nome === form.watch("cargo"));
                if (!cargoSelecionado || (!cargoSelecionado.insalubridade && !cargoSelecionado.periculosidade && !cargoSelecionado.aposentadoria_especial)) return null;
                return (
                  <div className="rounded-lg border border-amber-500/30 bg-amber-500/5 p-3 space-y-2">
                    <p className="text-xs font-semibold text-foreground flex items-center gap-1.5">
                      <ShieldAlert className="w-3.5 h-3.5" />
                      Condições Especiais (herdadas da função)
                    </p>
                    <div className="flex flex-wrap gap-1.5">
                      {cargoSelecionado.insalubridade && (
                        <span className="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-destructive/10 text-destructive font-medium">
                          <ShieldAlert className="w-3 h-3" />
                          Insalubridade {cargoSelecionado.insalubridade_grau === 'minimo' ? '10%' : cargoSelecionado.insalubridade_grau === 'medio' ? '20%' : '40%'}
                        </span>
                      )}
                      {cargoSelecionado.periculosidade && (
                        <span className="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-amber-500/10 text-amber-700 dark:text-amber-400 font-medium">
                          <Zap className="w-3 h-3" />
                          Periculosidade 30%
                        </span>
                      )}
                      {cargoSelecionado.aposentadoria_especial && (
                        <span className="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-blue-500/10 text-blue-700 dark:text-blue-400 font-medium">
                          <Clock className="w-3 h-3" />
                          Apos. Especial {cargoSelecionado.aposentadoria_especial_anos}a
                        </span>
                      )}
                    </div>
                    {cargoSelecionado.insalubridade && cargoSelecionado.periculosidade && (
                      <p className="text-[11px] text-muted-foreground">
                        ⚖️ Será aplicado o adicional mais vantajoso (art. 193, §2º CLT)
                      </p>
                    )}
                  </div>
                );
              })()}

              {/* Gestor Imediato — linha inteira */}
              <FormField
                control={form.control}
                name="gestor_imediato"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Gestor Imediato</FormLabel>
                    <FormControl>
                      <GestorComboboxField
                        value={field.value || ""}
                        onChange={field.onChange}
                        disabled={isSubmitting}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              {/* Centro de Custo | Matrícula eSocial */}
              <div className="grid grid-cols-2 gap-3">
                <FormField
                  control={form.control}
                  name="centro_custo"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Centro de Custo</FormLabel>
                      <FormControl>
                        <Input placeholder="Ex: CC-001" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                <FormField
                  control={form.control}
                  name="matricula_esocial"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Matrícula eSocial</FormLabel>
                      <FormControl>
                        <Input placeholder="Ex: 00123456789" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>

              {/* CBO — Classificação Brasileira de Ocupações */}
              <FormField
                control={form.control}
                name="cbo"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>CBO — Ocupação</FormLabel>
                    <FormControl>
                      <CBOAutocomplete
                        value={field.value || null}
                        onChange={(codigo) => field.onChange(codigo || "")}
                        disabled={isSubmitting}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

            </div>

            {/* Footer fixo */}
            <div className="flex justify-end gap-3 px-6 py-4 border-t bg-background shrink-0">
              <Button
                type="button"
                variant="outline"
                onClick={() => onOpenChange(false)}
                disabled={isSubmitting}
              >
                Cancelar
              </Button>
              <Button type="submit" disabled={isSubmitting}>
                {isSubmitting && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
                {isEditMode ? "Salvar Alterações" : "Cadastrar"}
              </Button>
            </div>
          </form>
        </Form>

      </DialogContent>
    </Dialog>
  );
}
