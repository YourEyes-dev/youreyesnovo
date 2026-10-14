import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Loader2, Sparkles, AlertTriangle, UserCheck, Search, ShieldCheck, Building2, Layers, Check, X, ListChecks } from "lucide-react";
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { useUsuarios, TIPO_USUARIO_LABELS, UsuarioTipo, calcularQualidade } from "@/hooks/useUsuarios";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";
import { toast } from "sonner";
import { cleanCpf, formatCpf, validateCpf } from "@/lib/cpf";
import { CpfInput } from "@/components/ui/cpf-input";
import { mapTipoUsuarioToAppRole } from "@/lib/userRoleMap";
import { mensagemDaFuncao } from "@/lib/supabaseFunctions";
import { useGruposEconomicos } from "@/hooks/useGruposEconomicos";

const schemaEtapa1 = z.object({
  nome_completo: z.string().min(3, "Nome obrigatório"),
  nome_social: z.string().optional(),
  email_principal: z.string().email("E-mail inválido"),
  cpf: z.string().optional(),
  telefone_principal: z.string().optional(),
  cargo_funcao: z.string().optional(),
  matricula: z.string().optional(),
  data_nascimento: z.string().optional(),
  tipo_usuario: z.string(),
  perfil_acesso_id: z.string().optional(),
  empresa_id: z.string().optional(),
  tipo_vinculo: z.string(),
  contexto_operacional: z.string().optional(),
  observacoes: z.string().optional(),
});

const schemaEtapa2 = z.object({
  nome_completo: z.string().min(3, "Nome obrigatório"),
  nome_social: z.string().optional(),
  email_principal: z.string().email("E-mail inválido"),
  cpf: z.string().optional(),
  telefone_principal: z.string().optional(),
  cargo_funcao: z.string().optional(),
  matricula: z.string().optional(),
  data_nascimento: z.string().optional(),
  tipo_usuario: z.string(),
  perfil_acesso_id: z.string().optional(),
  empresa_id: z.string().min(1, "Selecione uma empresa"),
  tipo_vinculo: z.string(),
  contexto_operacional: z.string().optional(),
  observacoes: z.string().optional(),
});

// Union type for form (uses the looser schema for typing)
const schema = schemaEtapa1;

type FormData = z.infer<typeof schema>;

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
}

interface ColaboradorEncontrado {
  id: string;
  nome_completo: string;
  email: string;
  cpf: string;
  celular?: string;
  cargo: string;
  data_nascimento?: string;
  empresa_id?: string;
}

export function NovoUsuarioDialog({ open, onOpenChange }: Props) {
  const { tenantId } = useAuth();
  const queryClient = useQueryClient();
  const { createUsuario, createVinculo, usuarios } = useUsuarios();
  const { grupos } = useGruposEconomicos();
  const [etapa, setEtapa] = useState<1 | 2 | 3>(1);
  const [alertaDuplicidade, setAlertaDuplicidade] = useState<string | null>(null);
  const [novoUsuarioId, setNovoUsuarioId] = useState<string | null>(null);
  const [buscandoCpf, setBuscandoCpf] = useState(false);
  const [colaboradorEncontrado, setColaboradorEncontrado] = useState<ColaboradorEncontrado | null>(null);
  const [dadosReaproveitados, setDadosReaproveitados] = useState(false);
  // Modo de vínculo: empresa individual, múltiplas empresas, ou grupo econômico
  const [modoVinculo, setModoVinculo] = useState<"empresa" | "multiplas" | "grupo">("empresa");
  const [grupoSelecionadoId, setGrupoSelecionadoId] = useState<string>("");
  const [empresasSelecionadas, setEmpresasSelecionadas] = useState<string[]>([]);
  const [empresaPopoverOpen, setEmpresaPopoverOpen] = useState(false);
  const [emailEnviado, setEmailEnviado] = useState<boolean>(true);
  const [emailErro, setEmailErro] = useState<string | null>(null);

  const { data: empresas = [] } = useQuery({
    queryKey: ["empresas-lista-grupo", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const PAGE = 1000;
      let from = 0;
      const acc: any[] = [];
      for (let i = 0; i < 50; i++) {
        const { data } = await fromTable("empresa_cadastro")
          .select("id, razao_social, nome_fantasia, cnpj, grupo_economico_id")
          .eq("tenant_id", tenantId)
          .order("razao_social")
          .range(from, from + PAGE - 1);
        const chunk = data || [];
        acc.push(...chunk);
        if (chunk.length < PAGE) break;
        from += PAGE;
      }
      return acc;
    },

    enabled: !!tenantId,
  });

  // Perfis de acesso do tenant
  const { data: perfisAcesso = [] } = useQuery({
    queryKey: ["perfis-acesso-select", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data } = await fromTable("perfis_acesso")
        .select("id, nome, cor, tipo_usuario_sugerido, descricao")
        .eq("tenant_id", tenantId)
        .eq("ativo", true)
        .order("nome");
      return data || [];
    },
    enabled: !!tenantId,
  });

  const { register, handleSubmit, watch, setValue, reset, trigger, getValues, formState: { errors } } = useForm<FormData>({
    resolver: zodResolver(schemaEtapa1),
    defaultValues: { tipo_usuario: "gestor", tipo_vinculo: "gestor" },
  });

  const watchedValues = watch();

  function verificarDuplicidade(email: string, cpf?: string) {
    const emailLower = (email || "").toLowerCase();
    const cpfClean = cpf ? cleanCpf(cpf) : "";
    const duplicado = usuarios.find(u =>
      (!!emailLower && (u.email_principal || "").toLowerCase() === emailLower) ||
      (!!cpfClean && u.cpf && cleanCpf(u.cpf) === cpfClean)
    );
    if (duplicado) {
      setAlertaDuplicidade(`Possível duplicidade: "${duplicado.nome_completo}" já cadastrado com este e-mail/CPF.`);
    } else {
      setAlertaDuplicidade(null);
    }
  }

  async function buscarColaboradorPorCpf(cpf: string) {
    const cleaned = cleanCpf(cpf);
    if (!tenantId || cleaned.length !== 11 || !validateCpf(cleaned)) return;

    // Primeiro verifica se já existe como usuário
    const usuarioExistente = usuarios.find(u => u.cpf && cleanCpf(u.cpf) === cleaned);
    if (usuarioExistente) {
      setAlertaDuplicidade(`Usuário "${usuarioExistente.nome_completo}" já está cadastrado com este CPF.`);
      return;
    }

    setBuscandoCpf(true);
    try {
      const { data } = await supabase
        .from("admissoes")
        .select("id, nome_completo, email, cpf, celular, cargo, data_nascimento, empresa_id")
        .eq("tenant_id", tenantId)
        .eq("cpf", cleaned)
        .maybeSingle();

      if (data) {
        setColaboradorEncontrado(data as ColaboradorEncontrado);
      } else {
        setColaboradorEncontrado(null);
        setDadosReaproveitados(false);
      }
    } catch (e) {
      // silencioso
    } finally {
      setBuscandoCpf(false);
    }
  }

  function aplicarDadosColaborador() {
    if (!colaboradorEncontrado) return;
    setValue("nome_completo", colaboradorEncontrado.nome_completo);
    setValue("email_principal", colaboradorEncontrado.email || "");
    setValue("telefone_principal", colaboradorEncontrado.celular || "");
    setValue("cargo_funcao", colaboradorEncontrado.cargo || "");
    if (colaboradorEncontrado.data_nascimento) {
      setValue("data_nascimento", colaboradorEncontrado.data_nascimento);
    }
    if (colaboradorEncontrado.empresa_id) {
      setValue("empresa_id", colaboradorEncontrado.empresa_id);
    }
    setDadosReaproveitados(true);
    toast.success("Dados do colaborador aplicados ao cadastro!");
  }

  async function handleProximo() {
    // Validate only etapa 1 fields
    const valid = await trigger(["nome_completo", "email_principal"]);
    if (!valid) return;
    const data = getValues();
    verificarDuplicidade(data.email_principal, data.cpf);
    setEtapa(2);
  }

  async function handleCriarUsuario() {
    const data = getValues();

    // Validar modo de vínculo
    if (modoVinculo === "empresa") {
      const parsed = schemaEtapa2.safeParse(data);
      if (!parsed.success) {
        const firstError = parsed.error.errors[0];
        toast.error(firstError?.message || "Preencha todos os campos obrigatórios");
        return;
      }
    } else if (modoVinculo === "multiplas") {
      if (empresasSelecionadas.length === 0) {
        toast.error("Selecione ao menos uma empresa");
        return;
      }
    } else {
      if (!grupoSelecionadoId) {
        toast.error("Selecione um grupo econômico");
        return;
      }
    }

    try {
      const appRole = mapTipoUsuarioToAppRole(data.tipo_usuario);
      const { data: authData, error: authError } = await supabase.functions.invoke("invite-tenant-user", {
        body: {
          email: data.email_principal,
          nomeCompleto: data.nome_completo,
          role: appRole,
          method: "invite",
        },
      });

      // Em falha non-2xx o supabase-js embrulha tudo em "Edge Function returned
      // a non-2xx status code" e guarda o motivo real em error.context. Sem
      // extrair esse corpo, o usuário vê sempre a mesma mensagem genérica — e o
      // motivo verdadeiro (e-mail já em outra organização, sem permissão, falha
      // no link de convite) nunca aparece na tela.
      if (authError || (authData as any)?.error) {
        throw new Error(await mensagemDaFuncao(authError, authData));
      }

      const authUserId = (authData as any)?.userId as string | undefined;
      if (!authUserId) throw new Error("Não foi possível provisionar o acesso no sistema.");

      const inviteSent = (authData as any)?.inviteSent === true;
      const inviteErr = (authData as any)?.emailError as string | null | undefined;
      setEmailEnviado(inviteSent);
      setEmailErro(inviteErr ?? null);

      const jaExistia = (authData as any)?.alreadyExists === true;
      if (jaExistia) {
        toast.info("Usuário já existente no sistema — vinculando às empresas selecionadas.");
      }

      // auth_user_id é UNIQUE globalmente em usuarios_base — buscar sem filtro de tenant
      // para evitar violação de unique constraint em retries ou usuários cross-tenant.
      const { data: usuarioExistenteGlobal } = await fromTable("usuarios_base")
        .select("*")
        .eq("auth_user_id", authUserId)
        .maybeSingle();

      let usuario: any;
      if (usuarioExistenteGlobal) {
        if (usuarioExistenteGlobal.tenant_id !== tenantId) {
          throw new Error(
            "Este e-mail já está vinculado a outra organização no sistema. Use um e-mail diferente ou contate o suporte."
          );
        }
        usuario = usuarioExistenteGlobal;
        if (jaExistia) {
          toast.info("Usuário já existente — vinculando às empresas selecionadas.");
        }
      } else {
        usuario = await createUsuario.mutateAsync({
          nome_completo: data.nome_completo,
          nome_social: data.nome_social || undefined,
          email_principal: data.email_principal,
          cpf: data.cpf ? cleanCpf(data.cpf) : undefined,
          telefone_principal: data.telefone_principal,
          cargo_funcao: data.cargo_funcao,
          matricula: data.matricula || undefined,
          data_nascimento: data.data_nascimento || undefined,
          tipo_usuario: data.tipo_usuario as UsuarioTipo,
          observacoes: data.observacoes,
          auth_user_id: authUserId,
          status: jaExistia ? "ativo" : "convite_enviado",
          convite_enviado_em: jaExistia ? undefined : new Date().toISOString(),
          qualidade_score: "incompleto",
          qualidade_pct: 0,
        });
      }

      if (modoVinculo === "empresa") {
        await createVinculo.mutateAsync({
          usuario_id: usuario.id,
          empresa_id: data.empresa_id!,
          tipo_vinculo: data.tipo_vinculo as UsuarioTipo,
          contexto_operacional: data.contexto_operacional,
          status: "ativo",
          data_inicio: new Date().toISOString().split("T")[0],
        });
      } else if (modoVinculo === "multiplas") {
        for (const empId of empresasSelecionadas) {
          await createVinculo.mutateAsync({
            usuario_id: usuario.id,
            empresa_id: empId,
            tipo_vinculo: data.tipo_vinculo as UsuarioTipo,
            contexto_operacional: data.contexto_operacional,
            status: "ativo",
            data_inicio: new Date().toISOString().split("T")[0],
          });
        }
      } else {
        const empresasDoGrupo = empresas.filter((e: any) => e.grupo_economico_id === grupoSelecionadoId);
        if (empresasDoGrupo.length === 0) {
          toast.error("Nenhuma empresa encontrada neste grupo econômico");
          return;
        }
        for (const emp of empresasDoGrupo) {
          await createVinculo.mutateAsync({
            usuario_id: usuario.id,
            empresa_id: emp.id,
            tipo_vinculo: data.tipo_vinculo as UsuarioTipo,
            contexto_operacional: data.contexto_operacional,
            status: "ativo",
            data_inicio: new Date().toISOString().split("T")[0],
          });
        }
      }

      // Vincular perfil de acesso se selecionado
      if (data.perfil_acesso_id) {
        const { error: vincError } = await fromTable("usuario_perfil_vinculos")
          .insert({
            tenant_id: tenantId,
            usuario_id: usuario.id,
            perfil_id: data.perfil_acesso_id,
            ativo: true,
            is_perfil_principal: true,
            atribuido_por_nome: "Sistema (cadastro)",
          });
        if (vincError) {
          console.error("Erro ao vincular perfil de acesso:", vincError);
          toast.error("Usuário criado, mas falhou ao vincular o perfil de acesso: " + vincError.message);
        }
      }

      // O vínculo era gravado corretamente, mas nenhuma query era invalidada:
      // a listagem seguia com o cache anterior e a coluna Perfil de Acesso
      // aparecia vazia para o usuário recém-criado até recarregar a página.
      queryClient.invalidateQueries({ queryKey: ["usuarios"] });
      queryClient.invalidateQueries({ queryKey: ["usuario_perfil_vinculos"] });
      queryClient.invalidateQueries({ queryKey: ["usuarios-perfil-vinculos-lista"] });
      queryClient.invalidateQueries({ queryKey: ["usuario_vinculos"] });

      setNovoUsuarioId(usuario.id);
      setEtapa(3);
    } catch (e: any) {
      const msg = e?.message || "falha inesperada";
      if (msg.includes("usuarios_base_auth_user_id_key") || msg.includes("duplicate key") && msg.includes("auth_user_id")) {
        toast.error("Este e-mail já está vinculado a outra organização no sistema. Use um e-mail diferente ou contate o suporte.");
      } else if (msg.includes("usuarios_base") && msg.includes("email")) {
        toast.error("Já existe um usuário com este e-mail nesta organização.");
      } else {
        toast.error("Erro ao cadastrar: " + msg);
      }
    }
  }

  function handleFechar() {
    reset();
    setEtapa(1);
    setNovoUsuarioId(null);
    setAlertaDuplicidade(null);
    setColaboradorEncontrado(null);
    setDadosReaproveitados(false);
    setModoVinculo("empresa");
    setGrupoSelecionadoId("");
    setEmpresasSelecionadas([]);
    onOpenChange(false);
  }

  function handleClose() {
    reset();
    setEtapa(1);
    setNovoUsuarioId(null);
    setAlertaDuplicidade(null);
    setColaboradorEncontrado(null);
    setDadosReaproveitados(false);
    setModoVinculo("empresa");
    setGrupoSelecionadoId("");
    setEmpresasSelecionadas([]);
    onOpenChange(false);
  }

  const isLoading = createUsuario.isPending || createVinculo.isPending;

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="max-w-xl max-h-[90vh] overflow-hidden flex flex-col">
        <DialogHeader className="shrink-0">
          <DialogTitle className="flex items-center gap-2">
            {etapa === 1 && "Novo Usuário — Dados Básicos"}
            {etapa === 2 && "Novo Usuário — Vínculo & Revisão"}
            {etapa === 3 && "Usuário cadastrado!"}
          </DialogTitle>
          <DialogDescription>
            {etapa === 1 && "Preencha os dados de identidade do usuário"}
            {etapa === 2 && "Defina o vínculo com a empresa e revise os dados"}
            {etapa === 3 && "O usuário foi criado com sucesso"}
          </DialogDescription>
          {/* Progress */}
          <div className="flex gap-1 mt-2">
            {[1, 2, 3].map(s => (
              <div key={s} className={`h-1 flex-1 rounded-full transition-all ${s <= etapa ? "bg-primary" : "bg-muted"}`} />
            ))}
          </div>
        </DialogHeader>

        <form onSubmit={e => e.preventDefault()} className="flex-1 overflow-y-auto min-h-0">
          <div className="p-1 space-y-4">

            {/* ── ETAPA 1 ── */}
            {etapa === 1 && (
              <>
                {alertaDuplicidade && (
                  <div className="flex gap-2 items-start p-3 bg-destructive/10 border border-destructive/20 rounded-lg text-sm text-destructive">
                    <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" />
                    {alertaDuplicidade}
                  </div>
                )}

                {/* Banner: colaborador encontrado */}
                {colaboradorEncontrado && !dadosReaproveitados && (
                  <div className="flex flex-col gap-2 p-3 bg-primary/8 border border-primary/20 rounded-lg text-sm">
                    <div className="flex items-start gap-2">
                      <UserCheck className="w-4 h-4 text-primary shrink-0 mt-0.5" />
                      <div className="flex-1">
                        <p className="font-medium text-primary">Colaborador encontrado na base!</p>
                        <p className="text-muted-foreground text-xs mt-0.5">
                          {colaboradorEncontrado.nome_completo} — {colaboradorEncontrado.cargo}
                        </p>
                        {colaboradorEncontrado.email && (
                          <p className="text-muted-foreground text-xs">{colaboradorEncontrado.email}</p>
                        )}
                      </div>
                    </div>
                    <Button type="button" size="sm" variant="outline" onClick={aplicarDadosColaborador}
                      className="self-start text-primary border-primary/30 hover:bg-primary/10">
                      Reaproveitar dados do colaborador
                    </Button>
                  </div>
                )}

                {dadosReaproveitados && (
                  <div className="flex gap-2 items-center p-2.5 bg-primary/5 border border-primary/20 rounded-lg text-xs text-primary">
                    <Sparkles className="w-3.5 h-3.5 shrink-0" />
                    Dados do colaborador aplicados. Complete os campos restantes se necessário.
                  </div>
                )}

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">

                  {/* Linha 1: CPF (full width) — dispara lookup ao preencher */}
                  <div className="sm:col-span-2 space-y-1.5">
                    <Label className="flex items-center gap-1.5">
                      CPF
                      {buscandoCpf && <Loader2 className="w-3 h-3 animate-spin text-muted-foreground" />}
                      {colaboradorEncontrado && !buscandoCpf && <UserCheck className="w-3 h-3 text-primary" />}
                    </Label>
                    <CpfInput
                      value={watchedValues.cpf || ""}
                      onChange={(v) => {
                        setValue("cpf", v);
                        buscarColaboradorPorCpf(v);
                      }}
                      onBlur={() => verificarDuplicidade(watchedValues.email_principal, watchedValues.cpf)}
                      placeholder="000.000.000-00"
                    />
                  </div>

                  {/* Linha 2: Nome Completo (full width) */}
                  <div className="sm:col-span-2 space-y-1.5">
                    <Label>Nome Completo *</Label>
                    <Input {...register("nome_completo")} placeholder="Maria da Silva Santos" />
                    {errors.nome_completo && <p className="text-xs text-destructive">{errors.nome_completo.message}</p>}
                  </div>

                  {/* Linha 3: Nome Social + Matrícula */}
                  <div className="space-y-1.5">
                    <Label>Nome Social <span className="text-muted-foreground font-normal">(opcional)</span></Label>
                    <Input {...register("nome_social")} placeholder="Como prefere ser chamado(a)" />
                  </div>

                  <div className="space-y-1.5">
                    <Label>Matrícula / Código Interno</Label>
                    <Input {...register("matricula")} placeholder="EMP-0042" />
                  </div>

                  {/* Linha 4: E-mail (full width) */}
                  <div className="sm:col-span-2 space-y-1.5">
                    <Label>E-mail *</Label>
                    <Input {...register("email_principal")} type="email" placeholder="maria@empresa.com"
                      onBlur={e => verificarDuplicidade(e.target.value, watchedValues.cpf)} />
                    {errors.email_principal && <p className="text-xs text-destructive">{errors.email_principal.message}</p>}
                  </div>

                  {/* Linha 4: Data de Nascimento + Cargo/Função */}
                  <div className="space-y-1.5">
                    <Label>Data de Nascimento</Label>
                    <Input {...register("data_nascimento")} type="date" />
                  </div>

                  <div className="space-y-1.5">
                    <Label>Cargo / Função</Label>
                    <Input {...register("cargo_funcao")} placeholder="Analista de RH" />
                  </div>

                  {/* Linha 5: Telefone */}
                  <div className="space-y-1.5">
                    <Label>Telefone / WhatsApp</Label>
                    <Input {...register("telefone_principal")} placeholder="(11) 99000-0000" />
                  </div>

                  {/* Perfil de Acesso (full width) */}
                  <div className="sm:col-span-2 space-y-1.5">
                    <Label className="flex items-center gap-1.5">
                      <ShieldCheck className="w-3.5 h-3.5" />
                      Perfil de acesso (permissões)
                    </Label>

                    <Select
                      value={watchedValues.perfil_acesso_id || ""}
                      onValueChange={perfilId => {
                        setValue("perfil_acesso_id", perfilId);
                        const perfil = perfisAcesso.find((p: any) => p.id === perfilId);
                        if (perfil?.tipo_usuario_sugerido) {
                          // Map perfil tipo_usuario_sugerido to valid DB enum values
                          const tipoMap: Record<string, string> = {
                            admin: "administrador",
                            sst: "tecnico_seguranca",
                            financeiro: "gestor",
                            consultor: "consultor_externo",
                          };
                          const tipoMapped = tipoMap[perfil.tipo_usuario_sugerido] || perfil.tipo_usuario_sugerido;
                          setValue("tipo_usuario", tipoMapped);
                          setValue("tipo_vinculo", tipoMapped);
                        }
                      }}
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Selecione um perfil de acesso" />
                      </SelectTrigger>
                      <SelectContent>
                        {perfisAcesso.map((p: any) => (
                          <SelectItem key={p.id} value={p.id}>
                            <span className="flex items-center gap-2">
                              <span className="w-2 h-2 rounded-full shrink-0" style={{ backgroundColor: p.cor || 'hsl(var(--muted))' }} />
                              {p.nome}
                            </span>
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <p className="text-xs text-muted-foreground">
                      Define o nível de acesso e permissões deste usuário no sistema.
                      Se nenhum perfil for selecionado, o perfil{" "}
                      <strong>Colaborador (padrão)</strong> é aplicado
                      automaticamente — auto-serviço apenas: a pessoa vê o
                      próprio ponto, atestados e holerites, sem acesso a dados
                      de outros colaboradores.
                    </p>
                  </div>

                  {/* Linha 6: Observações (full width) */}
                  <div className="sm:col-span-2 space-y-1.5">
                    <Label>Observações</Label>
                    <Textarea {...register("observacoes")} rows={2} placeholder="Informações internas…" />
                  </div>
                </div>
              </>
            )}

            {/* ── ETAPA 2 ── */}
            {etapa === 2 && (
              <div className="space-y-4">
                {alertaDuplicidade && (
                  <div className="flex gap-2 items-start p-3 bg-destructive/10 border border-destructive/20 rounded-lg text-sm text-destructive">
                    <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" />
                    {alertaDuplicidade}
                    <span className="font-medium">Deseja continuar mesmo assim?</span>
                  </div>
                )}

                {!watchedValues.perfil_acesso_id && (
                  <div className="flex gap-2 items-start p-3 bg-amber-500/10 border border-amber-500/30 rounded-lg text-sm">
                    <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5 text-amber-600" />
                    <span>
                      <strong>Sem perfil de acesso selecionado.</strong> A pessoa
                      entrará com o perfil <strong>Colaborador (padrão)</strong>:
                      auto-serviço apenas (próprio ponto, atestados e holerites),
                      sem acesso a dados de outros colaboradores. Volte à etapa
                      anterior se ela precisar de mais acesso.
                    </span>
                  </div>
                )}

                {/* Resumo */}
                <div className="p-3 bg-muted/40 rounded-lg text-sm space-y-1">
                  <p><span className="text-muted-foreground">Nome:</span> {watchedValues.nome_completo}</p>
                  <p><span className="text-muted-foreground">E-mail:</span> {watchedValues.email_principal}</p>
                  {watchedValues.cpf && (
                    <p><span className="text-muted-foreground">CPF:</span> {formatCpf(watchedValues.cpf)}</p>
                  )}
                  <p><span className="text-muted-foreground">Tipo de usuário (natureza):</span> {TIPO_USUARIO_LABELS[watchedValues.tipo_usuario as UsuarioTipo] || watchedValues.tipo_usuario}</p>
                  <p>
                    <span className="text-muted-foreground">Perfil de acesso (permissões):</span>{" "}
                    {perfisAcesso.find((p: any) => p.id === watchedValues.perfil_acesso_id)?.nome
                      || "Colaborador (padrão)"}
                  </p>
                  {dadosReaproveitados && (
                    <p className="flex items-center gap-1 text-primary text-xs mt-1">
                      <UserCheck className="w-3 h-3" /> Dados reaproveitados do cadastro de colaborador
                    </p>
                  )}
                </div>


                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">

                  {/* Toggle: empresa ou grupo */}
                  <div className="sm:col-span-2 space-y-1.5">
                    <Label>Tipo de Vínculo *</Label>
                    <div className="grid grid-cols-3 gap-2">
                      <button
                        type="button"
                        onClick={() => { setModoVinculo("empresa"); setGrupoSelecionadoId(""); setEmpresasSelecionadas([]); }}
                        className={`flex items-center gap-1.5 justify-center p-2.5 rounded-lg border text-xs font-medium transition-all ${
                          modoVinculo === "empresa"
                            ? "border-primary bg-primary/10 text-primary"
                            : "border-border bg-muted/30 text-muted-foreground hover:border-primary/40"
                        }`}
                      >
                        <Building2 className="w-4 h-4" />
                        Uma empresa
                      </button>
                      <button
                        type="button"
                        onClick={() => { setModoVinculo("multiplas"); setValue("empresa_id", ""); setGrupoSelecionadoId(""); }}
                        className={`flex items-center gap-1.5 justify-center p-2.5 rounded-lg border text-xs font-medium transition-all ${
                          modoVinculo === "multiplas"
                            ? "border-primary bg-primary/10 text-primary"
                            : "border-border bg-muted/30 text-muted-foreground hover:border-primary/40"
                        }`}
                      >
                        <ListChecks className="w-4 h-4" />
                        Múltiplas
                      </button>
                      <button
                        type="button"
                        onClick={() => { setModoVinculo("grupo"); setValue("empresa_id", ""); setEmpresasSelecionadas([]); }}
                        className={`flex items-center gap-1.5 justify-center p-2.5 rounded-lg border text-xs font-medium transition-all ${
                          modoVinculo === "grupo"
                            ? "border-primary bg-primary/10 text-primary"
                            : "border-border bg-muted/30 text-muted-foreground hover:border-primary/40"
                        }`}
                      >
                        <Layers className="w-4 h-4" />
                        Grupo
                      </button>
                    </div>
                  </div>

                  {/* Empresa individual */}
                  {modoVinculo === "empresa" && (
                    <div className="sm:col-span-2 space-y-1.5">
                      <Label>Empresa para vincular *</Label>
                      <Select
                        value={watchedValues.empresa_id || ""}
                        onValueChange={v => setValue("empresa_id", v)}
                      >
                        <SelectTrigger>
                          <SelectValue placeholder="Selecione a empresa" />
                        </SelectTrigger>
                        <SelectContent>
                          {empresas.map((e: any) => (
                            <SelectItem key={e.id} value={e.id}>
                              <div className="flex flex-col gap-0.5 py-0.5">
                                <span className="font-medium leading-tight">
                                  {e.razao_social}
                                  {e.nome_fantasia && e.nome_fantasia !== e.razao_social && (
                                    <span className="text-muted-foreground ml-1.5 font-normal">
                                      ({e.nome_fantasia})
                                    </span>
                                  )}
                                </span>
                                {e.cnpj && (
                                  <span className="text-xs text-muted-foreground font-normal leading-tight">
                                    CNPJ: {e.cnpj.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5")}
                                  </span>
                                )}
                              </div>
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      {errors.empresa_id && <p className="text-xs text-destructive">{errors.empresa_id.message}</p>}
                    </div>
                  )}

                  {/* Múltiplas empresas (busca por nome/CNPJ) */}
                  {modoVinculo === "multiplas" && (
                    <div className="sm:col-span-2 space-y-1.5">
                      <Label>Empresas para vincular *</Label>
                      <Popover open={empresaPopoverOpen} onOpenChange={setEmpresaPopoverOpen}>
                        <PopoverTrigger asChild>
                          <Button
                            type="button"
                            variant="outline"
                            role="combobox"
                            className="w-full justify-between font-normal"
                          >
                            <span className="truncate">
                              {empresasSelecionadas.length === 0
                                ? "Buscar por nome ou CNPJ..."
                                : `${empresasSelecionadas.length} empresa(s) selecionada(s)`}
                            </span>
                            <Search className="w-4 h-4 opacity-50 shrink-0" />
                          </Button>
                        </PopoverTrigger>
                        <PopoverContent className="w-[--radix-popover-trigger-width] p-0" align="start">
                          <Command
                            filter={(value, search) => {
                              // value contém "razao|fantasia|cnpj"
                              const term = search.toLowerCase().replace(/\D/g, "");
                              const text = value.toLowerCase();
                              if (text.includes(search.toLowerCase())) return 1;
                              if (term && text.replace(/\D/g, "").includes(term)) return 1;
                              return 0;
                            }}
                          >
                            <CommandInput placeholder="Pesquisar nome ou CNPJ..." />
                            <CommandList className="max-h-64">
                              <CommandEmpty>Nenhuma empresa encontrada.</CommandEmpty>
                              <CommandGroup>
                                {empresas.map((e: any) => {
                                  const checked = empresasSelecionadas.includes(e.id);
                                  const cnpjFmt = e.cnpj
                                    ? e.cnpj.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5")
                                    : "";
                                  return (
                                    <CommandItem
                                      key={e.id}
                                      value={`${e.razao_social || ""}|${e.nome_fantasia || ""}|${e.cnpj || ""}`}
                                      onSelect={() => {
                                        setEmpresasSelecionadas(prev =>
                                          prev.includes(e.id) ? prev.filter(x => x !== e.id) : [...prev, e.id]
                                        );
                                      }}
                                      className="flex items-start gap-2"
                                    >
                                      <div className={`mt-0.5 w-4 h-4 rounded border flex items-center justify-center shrink-0 ${checked ? "bg-primary border-primary" : "border-input"}`}>
                                        {checked && <Check className="w-3 h-3 text-primary-foreground" />}
                                      </div>
                                      <div className="flex flex-col gap-0.5 min-w-0">
                                        <span className="font-medium leading-tight truncate">
                                          {e.razao_social}
                                          {e.nome_fantasia && e.nome_fantasia !== e.razao_social && (
                                            <span className="text-muted-foreground ml-1.5 font-normal">({e.nome_fantasia})</span>
                                          )}
                                        </span>
                                        {cnpjFmt && (
                                          <span className="text-xs text-muted-foreground leading-tight">CNPJ: {cnpjFmt}</span>
                                        )}
                                      </div>
                                    </CommandItem>
                                  );
                                })}
                              </CommandGroup>
                            </CommandList>
                            <div className="flex items-center justify-between gap-2 border-t p-2">
                              <button
                                type="button"
                                className="text-xs text-muted-foreground hover:text-foreground"
                                onClick={() => setEmpresasSelecionadas(empresas.map((e: any) => e.id))}
                              >
                                Selecionar todas
                              </button>
                              <button
                                type="button"
                                className="text-xs text-muted-foreground hover:text-foreground"
                                onClick={() => setEmpresasSelecionadas([])}
                              >
                                Limpar
                              </button>
                            </div>
                          </Command>
                        </PopoverContent>
                      </Popover>
                      {empresasSelecionadas.length > 0 && (
                        <div className="flex flex-wrap gap-1.5 pt-1">
                          {empresasSelecionadas.slice(0, 6).map(id => {
                            const emp = empresas.find((e: any) => e.id === id);
                            if (!emp) return null;
                            return (
                              <Badge key={id} variant="secondary" className="gap-1 pr-1">
                                <span className="truncate max-w-[180px]">{emp.razao_social || emp.nome_fantasia}</span>
                                <button
                                  type="button"
                                  onClick={() => setEmpresasSelecionadas(prev => prev.filter(x => x !== id))}
                                  className="rounded hover:bg-muted-foreground/20 p-0.5"
                                >
                                  <X className="w-3 h-3" />
                                </button>
                              </Badge>
                            );
                          })}
                          {empresasSelecionadas.length > 6 && (
                            <Badge variant="outline">+{empresasSelecionadas.length - 6}</Badge>
                          )}
                        </div>
                      )}
                    </div>
                  )}

                  {/* Grupo econômico */}
                  {modoVinculo === "grupo" && (
                    <div className="sm:col-span-2 space-y-1.5">
                      <Label>Grupo Econômico *</Label>
                      <Select
                        value={grupoSelecionadoId}
                        onValueChange={setGrupoSelecionadoId}
                      >
                        <SelectTrigger>
                          <SelectValue placeholder="Selecione o grupo econômico" />
                        </SelectTrigger>
                        <SelectContent>
                          {grupos.filter((g: any) => g.ativo).map((g: any) => (
                            <SelectItem key={g.id} value={g.id}>
                              <span className="flex items-center gap-2">
                                <Layers className="w-3.5 h-3.5 text-muted-foreground" />
                                {g.nome}
                              </span>
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      {grupoSelecionadoId && (
                        <p className="text-xs text-muted-foreground">
                          O usuário será vinculado a{" "}
                          <span className="font-medium text-primary">
                            {empresas.filter((e: any) => e.grupo_economico_id === grupoSelecionadoId).length}
                          </span>{" "}
                          empresa(s) deste grupo.
                        </p>
                      )}
                    </div>
                  )}

                  <div className="sm:col-span-2 space-y-1.5">
                    <Label className="flex items-center justify-between">
                      <span>Papel {modoVinculo === "grupo" ? "no Grupo" : "nesta Empresa"}</span>
                      {watchedValues.tipo_vinculo === watchedValues.tipo_usuario && (
                        <span className="text-xs text-muted-foreground font-normal">
                          herdado do tipo de usuário
                        </span>
                      )}
                    </Label>
                    <Select
                      value={watchedValues.tipo_vinculo || "gestor"}
                      onValueChange={v => setValue("tipo_vinculo", v)}
                    >
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {Object.entries(TIPO_USUARIO_LABELS).map(([k, v]) => (
                          <SelectItem key={k} value={k}>{v}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <p className="text-xs text-muted-foreground">
                      Como esta pessoa atua. Pode ser diferente do perfil global.
                    </p>
                  </div>
                  <div className="space-y-1.5">
                    <Label>Contexto Operacional</Label>
                    <Input {...register("contexto_operacional")} placeholder="Ex: SST, RH, Clínica…" />
                  </div>
                </div>
              </div>
            )}

            {/* ── ETAPA 3 ── */}
            {etapa === 3 && (
              <div className="py-6 text-center space-y-4">
                <div className="w-16 h-16 rounded-full bg-primary/10 flex items-center justify-center mx-auto">
                  <Sparkles className="w-8 h-8 text-primary" />
                </div>
                <div>
                  <h3 className="font-semibold text-lg">{watchedValues.nome_completo}</h3>
                  <p className="text-sm text-muted-foreground">{watchedValues.email_principal}</p>
                </div>
                <div className="flex flex-wrap justify-center gap-2">
                  <Badge variant="secondary">Usuário criado</Badge>
                  {modoVinculo === "grupo" ? (
                    <Badge variant="secondary">
                      {empresas.filter((e: any) => e.grupo_economico_id === grupoSelecionadoId).length} vínculos criados (grupo)
                    </Badge>
                  ) : (
                    <Badge variant="secondary">Vínculo ativo</Badge>
                  )}
                  <Badge variant="secondary">Acesso no Auth criado</Badge>
                  {dadosReaproveitados && <Badge variant="outline" className="text-primary border-primary/30">Dados reaproveitados</Badge>}
                </div>
                {emailEnviado ? (
                  <p className="text-sm text-muted-foreground">
                    O convite de acesso foi enviado para o e-mail informado. Caso não chegue em alguns minutos, peça ao usuário para verificar a caixa de spam.
                  </p>
                ) : (
                  <div className="text-sm text-left p-3 rounded-lg border border-destructive/30 bg-destructive/10 text-destructive">
                    <p className="font-medium mb-1">⚠️ O e-mail de convite não pôde ser enviado automaticamente.</p>
                    <p className="text-xs">
                      O usuário foi criado, mas você precisa reenviar o convite manualmente pela lista de usuários.
                      {emailErro ? <> Detalhe: <span className="font-mono">{emailErro}</span></> : null}
                    </p>
                  </div>
                )}
              </div>
            )}
          </div>
        </form>

        {/* Footer */}
        <div className="shrink-0 border-t pt-4 flex justify-between gap-3">
          {etapa < 3 && (
            <Button type="button" variant="outline" onClick={() => etapa > 1 ? setEtapa(etapa === 2 ? 1 : 2) : handleClose()}>
              {etapa === 1 ? "Cancelar" : "Voltar"}
            </Button>
          )}
          <Button
            type="button"
            className={etapa === 3 ? "w-full" : "ml-auto"}
            disabled={isLoading}
            onClick={etapa === 1 ? handleProximo : etapa === 2 ? handleCriarUsuario : handleFechar}
          >
            {isLoading && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
            {etapa === 1 && "Próximo"}
            {etapa === 2 && "Criar Usuário"}
            {etapa === 3 && "Fechar"}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
