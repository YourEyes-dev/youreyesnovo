import { useEffect, useState } from "react";
import { useCadastroLivre } from "@/hooks/useCadastroLivre";
import { Link } from "react-router-dom";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Loader2, ArrowLeft, ArrowRight, Search, CheckCircle2, Mail, MessageCircle, Eye, EyeOff } from "lucide-react";
import { PhoneInput } from "@/components/ui/phone-input";
import { Checkbox } from "@/components/ui/checkbox";
import { formatCnpj, cleanCnpj, buscarCnpj, type BrasilApiCnpjResponse } from "@/lib/brasilapi";
import { Logo } from "@/components/ui/Logo";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
  FormDescription,
} from "@/components/ui/form";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { passwordSchema } from "@/lib/passwordPolicy";
import { PasswordStrength } from "@/components/auth/PasswordStrength";

const formatCpf = (value: string): string => {
  const n = value.replace(/\D/g, "");
  if (n.length <= 3) return n;
  if (n.length <= 6) return `${n.slice(0, 3)}.${n.slice(3)}`;
  if (n.length <= 9) return `${n.slice(0, 3)}.${n.slice(3, 6)}.${n.slice(6)}`;
  return `${n.slice(0, 3)}.${n.slice(3, 6)}.${n.slice(6, 9)}-${n.slice(9, 11)}`;
};

const registerSchema = z.object({
  tipoPessoa: z.enum(["pj", "pf"]),
  documento: z.string().min(1, "Documento é obrigatório"),
  tenantNome: z.string().min(2, "Nome da empresa deve ter pelo menos 2 caracteres").max(100),
  tenantSlug: z
    .string()
    .min(3, "Identificador deve ter pelo menos 3 caracteres")
    .max(50)
    .regex(/^[a-z0-9-]+$/, "Apenas letras minúsculas, números e hífen"),
  nomeCompleto: z.string().min(3, "Nome deve ter pelo menos 3 caracteres").max(100),
  email: z.string().email("E-mail inválido").max(255),
  whatsapp: z.string().min(10, "WhatsApp inválido").max(15),
  senha: passwordSchema,
  confirmarSenha: z.string(),
}).refine((data) => {
  const clean = data.documento.replace(/\D/g, "");
  if (data.tipoPessoa === "pj") return clean.length === 14;
  return clean.length === 11;
}, {
  message: "Documento inválido",
  path: ["documento"],
}).refine((data) => {
  const clean = data.whatsapp.replace(/\D/g, "");
  return clean.length === 10 || clean.length === 11;
}, {
  message: "WhatsApp inválido",
  path: ["whatsapp"],
}).refine((data) => data.senha === data.confirmarSenha, {
  message: "As senhas não conferem",
  path: ["confirmarSenha"],
});

type RegisterFormData = z.infer<typeof registerSchema>;

export default function Register() {
  // Porta livre fechada: quem cai aqui vai para os planos do site (a empresa
  // nasce pelo checkout). Quando a casa reabrir a porta (período de teste), a
  // tela volta a funcionar sem mudança de código.
  const { livre: cadastroLivre, carregando: portaCarregando } = useCadastroLivre();
  useEffect(() => {
    if (!portaCarregando && !cadastroLivre) {
      toast.info("O cadastro de empresa é feito pela contratação de um plano.", { description: "Escolha o plano ideal e a sua conta é criada na sequência." });
      window.location.replace(`${import.meta.env.BASE_URL.replace(/\/$/, "")}/#planos`);
    }
  }, [portaCarregando, cadastroLivre]);
  const [step, setStep] = useState(1);
  const [submitting, setSubmitting] = useState(false);
  const [showSuccessDialog, setShowSuccessDialog] = useState(false);
  const [buscandoCnpj, setBuscandoCnpj] = useState(false);
  const [cnpjData, setCnpjData] = useState<BrasilApiCnpjResponse | null>(null);
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [aceitaTermos, setAceitaTermos] = useState(false);
  const [aceitaPrivacidade, setAceitaPrivacidade] = useState(false);

  const form = useForm<RegisterFormData>({
    resolver: zodResolver(registerSchema),
    defaultValues: {
      tipoPessoa: "pj",
      documento: "",
      tenantNome: "",
      tenantSlug: "",
      nomeCompleto: "",
      email: "",
      whatsapp: "",
      senha: "",
      confirmarSenha: "",
    },
    mode: "onChange",
  });

  const tipoPessoa = form.watch("tipoPessoa");

  const handleBuscarCnpj = async () => {
    const doc = form.getValues("documento");
    const clean = cleanCnpj(doc);
    if (clean.length !== 14) {
      toast.error("Digite um CNPJ válido com 14 dígitos");
      return;
    }
    setBuscandoCnpj(true);
    try {
      const resultado = await buscarCnpj(doc);
      if (resultado) {
        setCnpjData(resultado);
        const nome = resultado.razao_social || resultado.nome_fantasia || "";
        form.setValue("tenantNome", nome);
        form.setValue("tenantSlug", generateSlug(nome));
        toast.success("Dados do CNPJ carregados!");
      } else {
        setCnpjData(null);
        toast.error("CNPJ não encontrado na base de dados");
      }
    } catch {
      setCnpjData(null);
      toast.error("Erro ao buscar CNPJ");
    } finally {
      setBuscandoCnpj(false);
    }
  };

  const extractEdgeFunctionErrorMessage = async (error: unknown): Promise<string | null> => {
    if (!error || typeof error !== "object") return null;

    const fnError = error as {
      message?: string;
      context?: {
        json?: () => Promise<{ error?: string }>;
      };
    };

    if (fnError.context?.json) {
      try {
        const body = await fnError.context.json();
        if (typeof body?.error === "string" && body.error.trim()) {
          return body.error;
        }
      } catch {
        // ignore json parse failures
      }
    }

    return typeof fnError.message === "string" ? fnError.message : null;
  };

  const onSubmit = async (data: RegisterFormData) => {
    setSubmitting(true);
    try {
      const cleanDoc = data.documento.replace(/\D/g, "");

      // 1. Create auth user with Supabase (sends verification email)
      // Use published app URL to avoid localhost links in confirmation emails
      const appUrl = "https://youreyes.com.br";
      const { data: authData, error: authError } = await supabase.auth.signUp({
        email: data.email,
        password: data.senha,
        options: {
          emailRedirectTo: appUrl,
        },
      });

      if (authError) {
        if (authError.message.includes("already registered")) {
          toast.error("Este e-mail já está cadastrado", { description: "Tente fazer login ou use outro e-mail." });
        } else {
          toast.error("Erro ao criar conta", { description: authError.message });
        }
        return;
      }

      if (!authData.user) {
        toast.error("Erro ao criar conta");
        return;
      }

      // Detect repeated signup (Supabase returns fake user with empty identities)
      if (!authData.user.identities || authData.user.identities.length === 0) {
        toast.error("Este e-mail já está cadastrado", { description: "Tente fazer login ou use outro e-mail." });
        return;
      }

      // 2. Call onboarding-signup to create tenant + profile + owner role
      const { error: fnError } = await supabase.functions.invoke("onboarding-signup", {
        body: {
          tenantNome: data.tenantNome,
          tenantSlug: data.tenantSlug,
          nomeCompleto: data.nomeCompleto,
          tipoPessoa: data.tipoPessoa,
          documento: cleanDoc,
          userId: authData.user.id,
          email: data.email,
          telefone: data.whatsapp,
          // Address from CNPJ lookup if available
          endereco: cnpjData?.logradouro || null,
          numero: cnpjData?.numero || null,
          complemento: cnpjData?.complemento || null,
          bairro: cnpjData?.bairro || null,
          cidade: cnpjData?.municipio || null,
          estado: cnpjData?.uf || null,
          cep: cnpjData?.cep || null,
        },
      });

      if (fnError) {
        console.error("onboarding-signup error:", fnError);

        const errorMessage = await extractEdgeFunctionErrorMessage(fnError);
        
        // User may have been deleted server-side (cleanup), so signOut can fail — ignore
        try { await supabase.auth.signOut(); } catch { /* user already deleted */ }

        if (errorMessage?.includes("já cadastrado")) {
          toast.error("Documento já cadastrado", { description: errorMessage });
        } else {
          toast.error("Não foi possível concluir o cadastro", {
            description: errorMessage || "Tente novamente em instantes.",
          });
        }
        return;
      }

      // Sign out so user must verify email first
      await supabase.auth.signOut();

      setShowSuccessDialog(true);
    } catch (err) {
      console.error("Register error:", err);
      toast.error("Erro ao enviar cadastro", { description: "Tente novamente mais tarde." });
    } finally {
      setSubmitting(false);
    }
  };

  const handleNextStep = async () => {
    const isValid = await form.trigger(["documento", "tenantNome", "tenantSlug"]);
    if (isValid) {
      setStep(2);
    }
  };

  const generateSlug = (name: string) => {
    return name
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9\s-]/g, "")
      .replace(/\s+/g, "-")
      .replace(/-+/g, "-")
      .substring(0, 50);
  };

  const handleDocumentoChange = (value: string) => {
    if (tipoPessoa === "pj") {
      form.setValue("documento", formatCnpj(value), { shouldValidate: true });
    } else {
      form.setValue("documento", formatCpf(value), { shouldValidate: true });
    }
  };

  return (
    <div className="space-y-5">
      {/* Mobile header */}
      <div className="lg:hidden flex items-center justify-center mb-6">
        <Logo size="lg" showText={false} />
      </div>

      <div className="text-center">
        <h1 className="text-2xl font-bold">Cadastre sua empresa</h1>
        <p className="text-muted-foreground mt-1">
          {step === 1
            ? "Primeiro, informe os dados da sua empresa"
            : "Agora, informe seus dados e crie sua senha"}
        </p>
      </div>

      {/* Progress indicator */}
      <div className="flex items-center gap-2">
        <div className={`flex-1 h-1 rounded-full ${step >= 1 ? "bg-primary" : "bg-muted"}`} />
        <div className={`flex-1 h-1 rounded-full ${step >= 2 ? "bg-primary" : "bg-muted"}`} />
      </div>

      <Form {...form}>
        <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
          {step === 1 && (
            <>
              <FormField
                control={form.control}
                name="tipoPessoa"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Tipo de Pessoa *</FormLabel>
                    <Select
                      value={field.value}
                      onValueChange={(val) => {
                        field.onChange(val);
                        form.setValue("documento", "");
                        if (val === "pf") setCnpjData(null);
                      }}
                    >
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        <SelectItem value="pj">Pessoa Jurídica (CNPJ)</SelectItem>
                        <SelectItem value="pf">Pessoa Física (CPF)</SelectItem>
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="documento"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>{tipoPessoa === "pj" ? "CNPJ" : "CPF"} *</FormLabel>
                    <FormControl>
                      <div className="flex gap-2">
                        <Input
                          placeholder={tipoPessoa === "pj" ? "00.000.000/0000-00" : "000.000.000-00"}
                          value={field.value}
                          onChange={(e) => handleDocumentoChange(e.target.value)}
                          maxLength={tipoPessoa === "pj" ? 18 : 14}
                        />
                        {tipoPessoa === "pj" && (
                          <Button
                            type="button"
                            variant="outline"
                            size="icon"
                            onClick={handleBuscarCnpj}
                            disabled={buscandoCnpj}
                            title="Buscar dados do CNPJ"
                          >
                            {buscandoCnpj ? (
                              <Loader2 className="h-4 w-4 animate-spin" />
                            ) : (
                              <Search className="h-4 w-4" />
                            )}
                          </Button>
                        )}
                      </div>
                    </FormControl>
                    {tipoPessoa === "pj" && (
                      <FormDescription>Clique na lupa para preencher automaticamente</FormDescription>
                    )}
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="tenantNome"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Nome da Empresa *</FormLabel>
                    <FormControl>
                      <Input
                        placeholder="Minha Empresa LTDA"
                        {...field}
                        onChange={(e) => {
                          field.onChange(e);
                          const currentSlug = form.getValues("tenantSlug");
                          if (!currentSlug || currentSlug === generateSlug(field.value)) {
                            form.setValue("tenantSlug", generateSlug(e.target.value));
                          }
                        }}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="tenantSlug"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Identificador da Empresa *</FormLabel>
                    <FormControl>
                      <div className="flex">
                        <span className="inline-flex items-center px-3 rounded-l-md border border-r-0 border-input bg-muted text-muted-foreground text-sm">
                          youreyes.com.br/
                        </span>
                        <Input className="rounded-l-none" placeholder="minha-empresa" {...field} />
                      </div>
                    </FormControl>
                    <FormDescription>Este será o endereço da sua empresa no sistema</FormDescription>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <Button type="button" className="w-full" onClick={handleNextStep}>
                Continuar
                <ArrowRight className="w-4 h-4 ml-2" />
              </Button>
            </>
          )}

          {step === 2 && (
            <>
              <FormField
                control={form.control}
                name="nomeCompleto"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Seu Nome Completo *</FormLabel>
                    <FormControl>
                      <Input placeholder="João da Silva" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="email"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>E-mail *</FormLabel>
                    <FormControl>
                      <Input
                        type="email"
                        placeholder="seu@email.com"
                        autoComplete="email"
                        {...field}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="whatsapp"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel className="flex items-center gap-1.5">
                      <MessageCircle className="w-3.5 h-3.5" />
                      WhatsApp *
                    </FormLabel>
                    <FormControl>
                      <PhoneInput
                        value={field.value}
                        onChange={(val) => form.setValue("whatsapp", val, { shouldValidate: true })}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="senha"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Senha *</FormLabel>
                    <FormControl>
                      <div className="relative">
                        <Input
                          type={showPassword ? "text" : "password"}
                          placeholder="Mínimo 12 caracteres"
                          autoComplete="new-password"
                          {...field}
                        />
                        <button
                          type="button"
                          className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                          onClick={() => setShowPassword(!showPassword)}
                          tabIndex={-1}
                        >
                          {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                        </button>
                      </div>
                    </FormControl>
                    <PasswordStrength value={field.value || ""} className="mt-2" />
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="confirmarSenha"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Confirmar Senha *</FormLabel>
                    <FormControl>
                      <div className="relative">
                        <Input
                          type={showConfirmPassword ? "text" : "password"}
                          placeholder="Repita a senha"
                          autoComplete="new-password"
                          {...field}
                        />
                        <button
                          type="button"
                          className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                          onClick={() => setShowConfirmPassword(!showConfirmPassword)}
                          tabIndex={-1}
                        >
                          {showConfirmPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                        </button>
                      </div>
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <div className="space-y-3">
                <label className="flex items-start gap-2 cursor-pointer">
                  <Checkbox
                    checked={aceitaTermos}
                    onCheckedChange={(v) => setAceitaTermos(v === true)}
                    className="mt-0.5"
                  />
                  <span className="text-sm text-muted-foreground">
                    Li e aceito os{" "}
                    <Link to="/termos-de-uso" target="_blank" className="text-primary font-medium hover:underline">
                      Termos de Uso
                    </Link>
                  </span>
                </label>

                <label className="flex items-start gap-2 cursor-pointer">
                  <Checkbox
                    checked={aceitaPrivacidade}
                    onCheckedChange={(v) => setAceitaPrivacidade(v === true)}
                    className="mt-0.5"
                  />
                  <span className="text-sm text-muted-foreground">
                    Li e aceito a{" "}
                    <Link to="/politica-de-privacidade" target="_blank" className="text-primary font-medium hover:underline">
                      Política de Privacidade
                    </Link>
                  </span>
                </label>
              </div>

              <div className="flex gap-2">
                <Button
                  type="button"
                  variant="outline"
                  className="flex-1"
                  onClick={() => setStep(1)}
                >
                  <ArrowLeft className="w-4 h-4 mr-2" />
                  Voltar
                </Button>
                <Button type="submit" className="flex-1" disabled={submitting || !aceitaTermos || !aceitaPrivacidade}>
                  {submitting ? (
                    <>
                      <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                      Criando conta...
                    </>
                  ) : (
                    "Criar Conta"
                  )}
                </Button>
              </div>
            </>
          )}
        </form>
      </Form>

      <div className="text-center">
        <p className="text-sm text-muted-foreground">
          Já tem uma conta?{" "}
          <Link to="/login" className="text-primary font-medium hover:underline">
            Fazer login
          </Link>
        </p>
      </div>

      {/* Success Dialog — Verify Email */}
      <Dialog open={showSuccessDialog} onOpenChange={() => {}}>
        <DialogContent className="sm:max-w-md" onPointerDownOutside={(e) => e.preventDefault()}>
          <DialogHeader className="text-center items-center">
            <div className="mx-auto bg-primary/10 rounded-full p-3 mb-2">
              <Mail className="w-8 h-8 text-primary" />
            </div>
            <DialogTitle className="text-xl">Verifique seu e-mail</DialogTitle>
            <DialogDescription className="text-center">
              Enviamos um link de confirmação para o e-mail informado. Clique no link para ativar sua conta e acessar o sistema.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4 py-2">
            <div className="flex items-start gap-3 p-3 bg-accent/50 rounded-lg">
              <CheckCircle2 className="w-5 h-5 text-primary shrink-0 mt-0.5" />
              <div>
                <p className="text-sm font-medium">Conta criada com sucesso</p>
                <p className="text-xs text-muted-foreground mt-0.5">
                  Sua empresa e conta de acesso foram configuradas. Basta confirmar o e-mail para começar.
                </p>
              </div>
            </div>

            <p className="text-xs text-muted-foreground text-center">
              Não recebeu o e-mail? Verifique a pasta de spam ou lixo eletrônico.
            </p>
          </div>

          <Button className="w-full" asChild>
            <Link to="/login">Ir para a tela de login</Link>
          </Button>
        </DialogContent>
      </Dialog>
    </div>
  );
}
