import { useState, useMemo } from "react";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { ScrollArea } from "@/components/ui/scroll-area";
import {
  User, Building2, Link2, History, AlertTriangle, CheckCircle2,
  Plus, Trash2, Shield, Ban, RotateCcw, Loader2, Pencil, Save, X,
  Mail, Send, XCircle, Key, ChevronsUpDown, Check, Search, ShieldCheck,
  Eye, EyeOff, Copy, RefreshCw,
} from "lucide-react";
import {
  UsuarioBase, UsuarioVinculo, TIPO_USUARIO_LABELS, VINCULO_STATUS_LABELS,
  STATUS_LABELS, useUsuarios, calcularQualidade,
} from "@/hooks/useUsuarios";
import { UsuarioStatusBadge } from "./UsuarioStatusBadge";
import { QualidadeScoreIndicator } from "./QualidadeScoreIndicator";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";
import { toast } from "sonner";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { CpfInput } from "@/components/ui/cpf-input";
import { cleanCpf, formatCpf } from "@/lib/cpf";
import { mapTipoUsuarioToAppRole } from "@/lib/userRoleMap";
import { mensagemDaFuncao } from "@/lib/supabaseFunctions";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { cn } from "@/lib/utils";
import { usePerfisAcesso, type PerfilAcesso } from "@/hooks/usePerfisAcesso";

function EmpresaSearchSelect({ empresas, value, onChange }: { empresas: any[]; value: string; onChange: (v: string) => void }) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");

  const filtered = useMemo(() => {
    if (!search.trim()) return empresas;
    const q = search.toLowerCase();
    return empresas.filter((e: any) => {
      const nome = (e.nome_fantasia || e.razao_social || "").toLowerCase();
      const cnpj = (e.cnpj || "").replace(/\D/g, "");
      return nome.includes(q) || cnpj.includes(q) || (e.cnpj || "").includes(q);
    });
  }, [empresas, search]);

  const selected = empresas.find((e: any) => e.id === value);

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button variant="outline" role="combobox" aria-expanded={open}
          className="w-full h-8 justify-between font-normal text-sm">
          {selected ? (
            <span>
              {selected.razao_social}
              {selected.nome_fantasia && selected.nome_fantasia !== selected.razao_social && (
                <span className="text-muted-foreground ml-1 font-normal">
                  ({selected.nome_fantasia})
                </span>
              )}
            </span>
          ) : "Buscar empresa…"}
          <ChevronsUpDown className="ml-2 h-3.5 w-3.5 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-[--radix-popover-trigger-width] p-0" align="start">
        <div className="flex items-center border-b px-3 py-2">
          <Search className="h-3.5 w-3.5 text-muted-foreground mr-2 shrink-0" />
          <input
            className="flex-1 bg-transparent text-sm outline-none placeholder:text-muted-foreground"
            placeholder="Buscar por nome ou CNPJ…"
            value={search}
            onChange={e => setSearch(e.target.value)}
            autoFocus
          />
        </div>
        <div className="max-h-52 overflow-y-auto p-1">
          {filtered.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-4">Nenhuma empresa encontrada</p>
          ) : (
            filtered.map((e: any) => (
              <button
                key={e.id}
                className={cn(
                  "w-full flex items-start gap-2 rounded-md px-2 py-1.5 text-left text-sm hover:bg-accent transition-colors",
                  value === e.id && "bg-accent"
                )}
                onClick={() => { onChange(e.id); setOpen(false); setSearch(""); }}
              >
                <Check className={cn("h-3.5 w-3.5 mt-0.5 shrink-0", value === e.id ? "opacity-100 text-primary" : "opacity-0")} />
                <div className="flex flex-col gap-0">
                  <span className="font-medium leading-tight">
                    {e.razao_social}
                    {e.nome_fantasia && e.nome_fantasia !== e.razao_social && (
                      <span className="text-muted-foreground ml-1.5 font-normal">
                        ({e.nome_fantasia})
                      </span>
                    )}
                  </span>
                  {e.cnpj && (
                    <span className="text-xs text-muted-foreground leading-tight">
                      CNPJ: {e.cnpj.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5")}
                    </span>
                  )}
                </div>
              </button>
            ))
          )}
        </div>
      </PopoverContent>
    </Popover>
  );
}

interface Props {
  usuario: UsuarioBase;
  open: boolean;
  onOpenChange: (v: boolean) => void;
}

type Tab = "dados" | "vinculos" | "logs";

export function UsuarioDetalheDialog({ usuario, open, onOpenChange }: Props) {
  const { tenantId } = useAuth();
  const { updateStatus, updateUsuario, createVinculo, encerrarVinculo } = useUsuarios();
  const { perfis, vincularPerfil, desvincularPerfil } = usePerfisAcesso();
  const [tab, setTab] = useState<Tab>("dados");

  // Perfil de acesso vinculado ao usuário
  const { data: perfilVinculos = [], refetch: refetchPerfilVinculos } = useQuery({
    queryKey: ["usuario-perfil-vinculo", usuario.id, tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data, error } = await fromTable("usuario_perfil_vinculos")
        .select("*, perfil:perfil_id(id,nome,cor,icone,nivel_risco,descricao)")
        .eq("tenant_id", tenantId)
        .eq("usuario_id", usuario.id)
        .eq("ativo", true)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return data || [];
    },
    enabled: open && !!tenantId && !!usuario.id,
  });

  const perfilAtual = perfilVinculos.length > 0 ? perfilVinculos[0] : null;
  const perfilAtualObj = perfilAtual?.perfil as PerfilAcesso | null;
  const perfisAtivos = perfis.filter(p => p.ativo);

  // Edição
  const [editando, setEditando] = useState(false);
  const [editForm, setEditForm] = useState({
    nome_completo: usuario.nome_completo,
    email_principal: usuario.email_principal || "",
    cpf: usuario.cpf || "",
    nome_social: usuario.nome_social || "",
    telefone_principal: usuario.telefone_principal || "",
    cargo_funcao: usuario.cargo_funcao || "",
    matricula: usuario.matricula || "",
    data_nascimento: usuario.data_nascimento || "",
    tipo_usuario: usuario.tipo_usuario || "",
    observacoes: usuario.observacoes || "",
    perfil_acesso_id: perfilAtualObj?.id || "",
  });

  // Bloqueio
  const [motivoBloqueio, setMotivoBloqueio] = useState("");
  const [showBloqueioForm, setShowBloqueioForm] = useState(false);

  // Definir senha
  const [showSenhaForm, setShowSenhaForm] = useState(false);
  const [novaSenha, setNovaSenha] = useState("");
  const [mostrarSenha, setMostrarSenha] = useState(true);
  const queryClient = useQueryClient();

  const gerarSenhaAleatoria = () => {
    const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789";
    let senha = "";
    for (let i = 0; i < 10; i++) senha += chars[Math.floor(Math.random() * chars.length)];
    setNovaSenha(senha);
    setMostrarSenha(true);
  };

  const copiarSenha = async () => {
    if (!novaSenha) return;
    try {
      await navigator.clipboard.writeText(novaSenha);
      toast.success("Senha copiada!");
    } catch {
      toast.error("Não foi possível copiar");
    }
  };

  const setPasswordMutation = useMutation({
    mutationFn: async () => {
      if (novaSenha.length < 6) {
        throw new Error("Senha deve ter no mínimo 6 caracteres");
      }

      if (usuario.auth_user_id) {
        const { data, error } = await supabase.functions.invoke("manage-tenant-users", {
          body: { action: "set_password", userId: usuario.auth_user_id, password: novaSenha, emailReal: usuario.email_principal },
        });
        if (error || data?.error) throw new Error(await mensagemDaFuncao(error, data));
        return { mode: "updated" as const };
      }

      const appRole = mapTipoUsuarioToAppRole(usuario.tipo_usuario);
      const { data: provisionData, error: provisionError } = await supabase.functions.invoke("invite-tenant-user", {
        body: {
          email: usuario.email_principal,
          nomeCompleto: usuario.nome_completo,
          role: appRole,
          method: "password",
          password: novaSenha,
        },
      });

      if (provisionError || (provisionData as any)?.error) {
        throw new Error(await mensagemDaFuncao(provisionError, provisionData));
      }

      const createdAuthUserId = (provisionData as any)?.userId as string | undefined;
      if (!createdAuthUserId) {
        throw new Error("Falha ao criar acesso no sistema para este usuário.");
      }

      const { error: syncError } = await fromTable("usuarios_base")
        .update({
          auth_user_id: createdAuthUserId,
          email_validado: true,
          status: "ativo",
          convite_aceito_em: new Date().toISOString(),
        })
        .eq("id", usuario.id);

      if (syncError) throw new Error(syncError.message);
      return { mode: "provisioned" as const };
    },
    onSuccess: (result) => {
      toast.success(
        result.mode === "provisioned"
          ? "Acesso criado e senha definida com sucesso!"
          : "Senha definida com sucesso! O usuário já pode fazer login."
      );
      setShowSenhaForm(false);
      setNovaSenha("");
      queryClient.invalidateQueries({ queryKey: ["tenant-users"] });
      queryClient.invalidateQueries({ queryKey: ["usuarios"] });
    },
    onError: (err: Error) => toast.error(err.message),
  });
  // Novo vínculo
  const [addingVinculo, setAddingVinculo] = useState(false);
  const [novaEmpresaId, setNovaEmpresaId] = useState("");
  const [novoTipo, setNovoTipo] = useState("gestor");
  const [novoContexto, setNovoContexto] = useState("");
  const [buscaVinculo, setBuscaVinculo] = useState("");


  // Fetch vinculos reactively so they update after mutations
  const { data: vinculosFresh = [], isFetched: vinculosFetched } = useQuery({
    queryKey: ['usuario-vinculos', usuario.id],
    queryFn: async () => {
      const PAGE = 1000;
      let from = 0;
      const acc: UsuarioVinculo[] = [];

      for (let i = 0; i < 50; i++) {
        const { data, error } = await (supabase as any)
          .from('usuario_vinculos')
          .select('*, empresa:empresa_id(razao_social, nome_fantasia, cnpj)')
          .eq('usuario_id', usuario.id)
          .order('created_at', { ascending: false })
          .range(from, from + PAGE - 1);

        if (error) throw error;

        const chunk = (data || []) as UsuarioVinculo[];
        acc.push(...chunk);

        if (chunk.length < PAGE) break;
        from += PAGE;
      }

      return acc;
    },
    enabled: open && !!usuario.id,
  });

  const vinculos = vinculosFetched
    ? vinculosFresh
    : (((usuario as any).vinculos || []) as UsuarioVinculo[]);
  const vinculosAtivos = vinculos.filter(v => v.status === "ativo");
  const { score, pct } = calcularQualidade(usuario, vinculos);

  const convitePendente = ["pendente_convite", "convite_enviado", "aguardando_ativacao"].includes(usuario.status);

  const { data: empresas = [] } = useQuery({
    queryKey: ["empresas-lista", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const PAGE = 1000;
      let from = 0;
      const acc: any[] = [];
      for (let i = 0; i < 50; i++) {
        const { data } = await fromTable("empresa_cadastro")
          .select("id, razao_social, nome_fantasia, cnpj")
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

  const { data: logs = [] } = useQuery({
    queryKey: ["usuario-audit", usuario.id],
    queryFn: async () => {
      const { data } = await fromTable("usuario_audit_log")
        .select("*")
        .eq("usuario_id", usuario.id)
        .order("created_at", { ascending: false })
        .limit(50);
      return data || [];
    },
    enabled: open && tab === "logs",
  });

  function fmt(d?: string) {
    if (!d) return "—";
    try { return format(new Date(d), "dd/MM/yyyy HH:mm", { locale: ptBR }); }
    catch { return d; }
  }

  function fmtDate(d?: string) {
    if (!d) return "—";
    try { return format(new Date(d), "dd/MM/yyyy", { locale: ptBR }); }
    catch { return d; }
  }

  async function handleSalvarEdicao() {
    const { tipo_usuario, perfil_acesso_id, data_nascimento, ...rest } = editForm;
    await updateUsuario.mutateAsync({
      id: usuario.id,
      ...rest,
      data_nascimento: data_nascimento || null,
      ...(tipo_usuario ? { tipo_usuario: tipo_usuario as import("@/hooks/useUsuarios").UsuarioTipo } : {}),
    });

    // Gerenciar vínculo de perfil de acesso
    const perfilAnteriorId = perfilAtualObj?.id || "";
    if (perfil_acesso_id !== perfilAnteriorId) {
      // Desvincular perfil anterior se existir
      if (perfilAtual?.id) {
        await desvincularPerfil.mutateAsync(perfilAtual.id);
      }
      // Vincular novo perfil se selecionado
      if (perfil_acesso_id) {
        await vincularPerfil.mutateAsync({
          usuario_id: usuario.id,
          perfil_id: perfil_acesso_id,
          is_perfil_principal: true,
        });
      }
      await refetchPerfilVinculos();
      queryClient.invalidateQueries({ queryKey: ["usuarios"] });
      queryClient.invalidateQueries({ queryKey: ["usuario_perfil_vinculos"] });
      // A listagem usa outra chave para os mesmos vínculos; sem isto a coluna
      // Perfil de Acesso segue vazia até recarregar a página.
      queryClient.invalidateQueries({ queryKey: ["usuarios-perfil-vinculos-lista"] });
    }

    setEditando(false);
  }

  async function handleBloqueio() {
    await updateStatus.mutateAsync({ id: usuario.id, status: "bloqueado", justificativa: motivoBloqueio });
    setShowBloqueioForm(false);
    setMotivoBloqueio("");
  }

  async function handleReativar() {
    await updateStatus.mutateAsync({ id: usuario.id, status: "ativo" });
  }

  async function handleEnviarConvite() {
    try {
      if (usuario.auth_user_id) {
        const { data, error } = await supabase.functions.invoke("manage-tenant-users", {
          body: { action: "resend_invite", userId: usuario.auth_user_id },
        });
        if (error) throw new Error(await mensagemDaFuncao(error, data));
        if (data?.error) throw new Error(data.error);

        await updateStatus.mutateAsync({ id: usuario.id, status: "convite_enviado" });
        toast.success("Convite enviado com sucesso!");
        return;
      }

      const appRole = mapTipoUsuarioToAppRole(usuario.tipo_usuario);
      const { data: provisionData, error: provisionError } = await supabase.functions.invoke("invite-tenant-user", {
        body: {
          email: usuario.email_principal,
          nomeCompleto: usuario.nome_completo,
          role: appRole,
          method: "invite",
        },
      });

      if (provisionError || (provisionData as any)?.error) {
        throw new Error(await mensagemDaFuncao(provisionError, provisionData));
      }

      const createdAuthUserId = (provisionData as any)?.userId as string | undefined;
      if (!createdAuthUserId) {
        throw new Error("Falha ao criar acesso no sistema para este usuário.");
      }

      const { error: syncError } = await fromTable("usuarios_base")
        .update({
          auth_user_id: createdAuthUserId,
          status: "convite_enviado",
          convite_enviado_em: new Date().toISOString(),
        })
        .eq("id", usuario.id);

      if (syncError) throw new Error(syncError.message);

      queryClient.invalidateQueries({ queryKey: ["usuarios"] });
      queryClient.invalidateQueries({ queryKey: ["tenant-users"] });
      toast.success("Acesso criado e convite enviado com sucesso!");
    } catch (e: any) {
      toast.error(e?.message || "Não foi possível enviar o convite.");
    }
  }

  async function handleCancelarConvite() {
    await updateStatus.mutateAsync({ id: usuario.id, status: "rascunho" });
    toast.success("Convite cancelado.");
  }

  async function handleAddVinculo() {
    if (!novaEmpresaId) { toast.error("Selecione a empresa"); return; }
    await createVinculo.mutateAsync({
      usuario_id: usuario.id,
      empresa_id: novaEmpresaId,
      tipo_vinculo: novoTipo as any,
      contexto_operacional: novoContexto,
      status: "ativo",
      data_inicio: new Date().toISOString().split("T")[0],
    });
    queryClient.invalidateQueries({ queryKey: ['usuario-vinculos', usuario.id] });
    setAddingVinculo(false);
    setNovaEmpresaId(""); setNovoTipo("gestor"); setNovoContexto("");
  }

  async function handleVincularTodas() {
    if (!tenantId) { toast.error("Tenant não identificado"); return; }
    const idsExistentes = new Set(
      vinculos.filter(v => v.status === "ativo").map((v: any) => v.empresa_id)
    );
    const pendentes = empresas.filter((e: any) => !idsExistentes.has(e.id));
    if (pendentes.length === 0) {
      toast.info("Todas as empresas já estão vinculadas a este usuário.");
      return;
    }
    const hoje = new Date().toISOString().split("T")[0];
    const toastId = toast.loading(`Vinculando ${pendentes.length} empresa(s)…`);
    const CHUNK = 500;
    let ok = 0;
    try {
      for (let i = 0; i < pendentes.length; i += CHUNK) {
        const slice = pendentes.slice(i, i + CHUNK).map((emp: any) => ({
          tenant_id: tenantId,
          usuario_id: usuario.id,
          empresa_id: emp.id,
          tipo_vinculo: novoTipo as any,
          contexto_operacional: novoContexto,
          status: "ativo",
          data_inicio: hoje,
        }));
        const { error, data } = await (supabase as any)
          .from("usuario_vinculos")
          .insert(slice)
          .select("id");
        if (error) throw error;
        ok += (data || slice).length;
      }
      queryClient.invalidateQueries({ queryKey: ['usuario-vinculos', usuario.id] });
      queryClient.invalidateQueries({ queryKey: ['usuarios'] });
      toast.success(`${ok} empresa(s) vinculada(s) com sucesso.`, { id: toastId });
    } catch (e: any) {
      toast.error(`Falha ao vincular: ${e?.message || e}`, { id: toastId });
    }
    setAddingVinculo(false);
    setNovaEmpresaId(""); setNovoTipo("gestor"); setNovoContexto("");
  }


  const isBloqueado = usuario.status === "bloqueado" || usuario.status === "suspenso";

  const tabs: { key: Tab; label: string; icon: React.ElementType }[] = [
    { key: "dados", label: "Dados", icon: User },
    { key: "vinculos", label: `Vínculos (${vinculos.length})`, icon: Link2 },
    { key: "logs", label: "Histórico", icon: History },
  ];

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl w-[95vw] max-h-[92vh] overflow-hidden flex flex-col p-0">

        {/* Header */}
        <div className="px-6 pt-6 pb-4 shrink-0 border-b">
          <DialogHeader className="sr-only">
            <DialogTitle>Detalhes do Usuário</DialogTitle>
            <DialogDescription>Gerencie os dados, vínculos e histórico do usuário</DialogDescription>
          </DialogHeader>

          <div className="flex items-start gap-4">
            <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
              {usuario.foto_url
                ? <img src={usuario.foto_url} className="w-12 h-12 rounded-full object-cover" alt="" />
                : <User className="w-6 h-6 text-primary" />
              }
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <h2 className="font-semibold text-lg truncate">{usuario.nome_completo}</h2>
                {usuario.nome_social && (
                  <span className="text-sm text-muted-foreground">({usuario.nome_social})</span>
                )}
                <UsuarioStatusBadge status={usuario.status} />
              </div>
              <p className="text-sm text-muted-foreground">{usuario.email_principal}</p>
              <div className="flex items-center gap-3 mt-1.5 flex-wrap">
                {perfilAtualObj ? (
                  <span className="inline-flex items-center gap-1.5 text-xs text-muted-foreground">
                    <span className="w-2.5 h-2.5 rounded-full shrink-0" style={{ backgroundColor: perfilAtualObj.cor || "#6366f1" }} />
                    {perfilAtualObj.nome}
                  </span>
                ) : (
                  <span className="text-xs text-amber-600">
                    Sem perfil de acesso · tipo de usuário:{" "}
                    {TIPO_USUARIO_LABELS[usuario.tipo_usuario] || usuario.tipo_usuario}
                  </span>
                )}

                <span className="text-muted-foreground/40">•</span>
                <span className="text-xs text-muted-foreground">{vinculosAtivos.length} vínculo(s) ativo(s)</span>
                <span className="text-muted-foreground/40">•</span>
                <QualidadeScoreIndicator score={score} pct={pct} />
              </div>
            </div>
          </div>

          {/* Ações de status — separadas do header para não colidir com o X */}
          <div className="flex gap-2 flex-wrap">
            {convitePendente && (
              <>
                <Button size="sm" variant="outline" className="text-primary border-primary/30 hover:bg-primary/10"
                  onClick={handleEnviarConvite} disabled={updateStatus.isPending}>
                  <Send className="w-3 h-3 mr-1" />
                  {usuario.status === "convite_enviado" ? "Reenviar" : "Enviar convite"}
                </Button>
                <Button size="sm" variant="ghost" className="text-muted-foreground"
                  onClick={handleCancelarConvite} disabled={updateStatus.isPending}>
                  <XCircle className="w-3 h-3 mr-1" /> Cancelar
                </Button>
              </>
            )}
            {!convitePendente && (
              isBloqueado ? (
                <Button size="sm" variant="outline" onClick={handleReativar} disabled={updateStatus.isPending}>
                  <RotateCcw className="w-3 h-3 mr-1" /> Reativar
                </Button>
              ) : (
                <Button size="sm" variant="outline"
                  className="text-destructive border-destructive/30 hover:bg-destructive/10"
                  onClick={() => setShowBloqueioForm(true)}>
                  <Ban className="w-3 h-3 mr-1" /> Bloquear
                </Button>
              )
            )}
          </div>

          {/* Bloqueio form */}
          {showBloqueioForm && (
            <div className="mt-3 p-3 border border-destructive/20 rounded-lg bg-destructive/5 space-y-2">
              <p className="text-sm font-medium text-destructive">Justificativa do bloqueio (opcional)</p>
              <Textarea rows={2} value={motivoBloqueio} onChange={e => setMotivoBloqueio(e.target.value)}
                placeholder="Informe o motivo…" className="text-sm" />
              <div className="flex gap-2">
                <Button size="sm" variant="destructive" onClick={handleBloqueio} disabled={updateStatus.isPending}>
                  {updateStatus.isPending && <Loader2 className="w-3 h-3 mr-1 animate-spin" />} Confirmar bloqueio
                </Button>
                <Button size="sm" variant="ghost" onClick={() => setShowBloqueioForm(false)}>Cancelar</Button>
              </div>
            </div>
          )}

          {/* Alerta convite pendente */}
          {convitePendente && (
            <div className="mt-3">
              <div className="flex gap-2 items-center p-2.5 bg-primary/5 border border-primary/20 rounded-lg text-sm text-primary">
                <Mail className="w-4 h-4 shrink-0" />
                <span className="flex-1">
                  {usuario.status === "pendente_convite"
                    ? "Este usuário ainda não recebeu o convite de ativação."
                    : "Aguardando ativação pelo usuário."}
                </span>
              </div>
            </div>
          )}

          {/* Definir senha provisória - disponível para qualquer status */}
          {!isBloqueado && (
            <div className="mt-3 space-y-2">
              {!showSenhaForm ? (
                <Button size="sm" variant="outline" className="text-xs h-7 gap-1 border-primary/30 text-primary hover:bg-primary/10"
                  onClick={() => setShowSenhaForm(true)}>
                  <Key className="w-3 h-3" /> Definir senha provisória
                </Button>
              ) : (
                <div className="p-3 border border-primary/20 rounded-lg bg-primary/5 space-y-2">
                  <p className="text-sm font-medium">Definir senha de acesso</p>
                  <p className="text-xs text-muted-foreground">O usuário poderá fazer login imediatamente com esta senha e alterá-la depois.</p>
                  <div className="relative">
                    <Input
                      type={mostrarSenha ? "text" : "password"}
                      value={novaSenha}
                      onChange={e => setNovaSenha(e.target.value)}
                      placeholder="Mínimo 6 caracteres"
                      className="text-sm pr-20 font-mono"
                    />
                    <div className="absolute right-1 top-1/2 -translate-y-1/2 flex items-center gap-0.5">
                      <Button
                        type="button"
                        size="icon"
                        variant="ghost"
                        className="h-7 w-7"
                        onClick={() => setMostrarSenha(v => !v)}
                        title={mostrarSenha ? "Ocultar" : "Mostrar"}
                      >
                        {mostrarSenha ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
                      </Button>
                      <Button
                        type="button"
                        size="icon"
                        variant="ghost"
                        className="h-7 w-7"
                        onClick={copiarSenha}
                        disabled={!novaSenha}
                        title="Copiar senha"
                      >
                        <Copy className="w-3.5 h-3.5" />
                      </Button>
                    </div>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    <Button size="sm" onClick={() => setPasswordMutation.mutate()}
                      disabled={setPasswordMutation.isPending || novaSenha.length < 6}>
                      {setPasswordMutation.isPending && <Loader2 className="w-3 h-3 mr-1 animate-spin" />}
                      <Key className="w-3 h-3 mr-1" /> Confirmar senha
                    </Button>
                    <Button size="sm" variant="outline" onClick={gerarSenhaAleatoria} type="button">
                      <RefreshCw className="w-3 h-3 mr-1" /> Gerar senha
                    </Button>
                    <Button size="sm" variant="ghost" onClick={() => { setShowSenhaForm(false); setNovaSenha(""); }}>
                      Cancelar
                    </Button>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Alerta duplicidade */}
          {usuario.alerta_duplicidade && (
            <div className="mt-3 flex gap-2 items-center p-2.5 bg-destructive/10 border border-destructive/20 rounded-lg text-sm text-destructive">
              <AlertTriangle className="w-4 h-4 shrink-0" />
              <span>Possível duplicidade detectada: <strong>{usuario.duplicidade_nivel}</strong></span>
            </div>
          )}

          {/* Tabs */}
          <div className="flex gap-1 mt-4">
            {tabs.map(t => (
              <button
                key={t.key}
                onClick={() => setTab(t.key)}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md text-sm transition-colors ${
                  tab === t.key
                    ? "bg-primary text-primary-foreground"
                    : "text-muted-foreground hover:bg-muted"
                }`}
              >
                <t.icon className="w-3.5 h-3.5" />
                {t.label}
              </button>
            ))}
          </div>
        </div>

        {/* Content — scrollable */}
        <div className="flex-1 min-h-0 overflow-y-auto overscroll-contain">
          <div className="px-6 py-4">

            {/* ── Tab: Dados ── */}
            {tab === "dados" && (
              <div className="space-y-4">

                {/* Cabeçalho com botão editar */}
                <div className="flex items-center justify-between">
                  <p className="text-sm font-medium text-muted-foreground uppercase tracking-wide">Informações</p>
                  {!editando ? (
                    <Button size="sm" variant="outline" onClick={() => {
                      setEditForm({
                        nome_completo: usuario.nome_completo,
                        email_principal: usuario.email_principal || "",
                        cpf: usuario.cpf || "",
                        nome_social: usuario.nome_social || "",
                        telefone_principal: usuario.telefone_principal || "",
                        cargo_funcao: usuario.cargo_funcao || "",
                        matricula: usuario.matricula || "",
                        data_nascimento: usuario.data_nascimento || "",
                        tipo_usuario: usuario.tipo_usuario || "",
                        observacoes: usuario.observacoes || "",
                        perfil_acesso_id: perfilAtualObj?.id || "",
                      });
                      setEditando(true);
                    }}>
                      <Pencil className="w-3.5 h-3.5 mr-1" /> Editar
                    </Button>
                  ) : (
                    <div className="flex gap-2">
                      <Button size="sm" onClick={handleSalvarEdicao} disabled={updateUsuario.isPending}>
                        {updateUsuario.isPending
                          ? <Loader2 className="w-3.5 h-3.5 mr-1 animate-spin" />
                          : <Save className="w-3.5 h-3.5 mr-1" />
                        } Salvar
                      </Button>
                      <Button size="sm" variant="ghost" onClick={() => setEditando(false)}>
                        <X className="w-3.5 h-3.5 mr-1" /> Cancelar
                      </Button>
                    </div>
                  )}
                </div>

                {editando ? (
                  /* Form de edição */
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div className="sm:col-span-2 space-y-1.5">
                      <Label>Nome Completo *</Label>
                      <Input value={editForm.nome_completo}
                        onChange={e => setEditForm(f => ({ ...f, nome_completo: e.target.value }))} />
                    </div>
                    <div className="sm:col-span-2 space-y-1.5">
                      <Label>E-mail *</Label>
                      <Input type="email" value={editForm.email_principal} placeholder="email@exemplo.com"
                        onChange={e => setEditForm(f => ({ ...f, email_principal: e.target.value }))} />
                    </div>
                    <div className="space-y-1.5">
                      <Label>CPF</Label>
                      <CpfInput value={editForm.cpf}
                        onChange={v => setEditForm(f => ({ ...f, cpf: cleanCpf(v) }))} />
                    </div>
                    <div className="space-y-1.5">
                      <Label>Perfil de acesso (permissões)</Label>
                      <Select value={editForm.perfil_acesso_id} onValueChange={v => setEditForm(f => ({ ...f, perfil_acesso_id: v }))}>
                        <SelectTrigger>
                          <SelectValue placeholder="Selecione um perfil…" />
                        </SelectTrigger>
                        <SelectContent>
                          {perfisAtivos.map(p => (
                            <SelectItem key={p.id} value={p.id}>
                              <div className="flex items-center gap-2">
                                <span className="w-2.5 h-2.5 rounded-full shrink-0" style={{ backgroundColor: p.cor || "#6366f1" }} />
                                {p.nome}
                              </div>
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      {editForm.perfil_acesso_id && (() => {
                        const sel = perfisAtivos.find(p => p.id === editForm.perfil_acesso_id);
                        return sel?.descricao ? (
                          <p className="text-[11px] text-muted-foreground mt-1">{sel.descricao}</p>
                        ) : null;
                      })()}
                    </div>
                    <div className="space-y-1.5">
                      <Label>Nome Social</Label>
                      <Input value={editForm.nome_social} placeholder="Como prefere ser chamado(a)"
                        onChange={e => setEditForm(f => ({ ...f, nome_social: e.target.value }))} />
                    </div>
                    <div className="space-y-1.5">
                      <Label>Matrícula / Código Interno</Label>
                      <Input value={editForm.matricula} placeholder="EMP-0042"
                        onChange={e => setEditForm(f => ({ ...f, matricula: e.target.value }))} />
                    </div>
                    <div className="space-y-1.5">
                      <Label>Telefone / WhatsApp</Label>
                      <Input value={editForm.telefone_principal} placeholder="(11) 99000-0000"
                        onChange={e => setEditForm(f => ({ ...f, telefone_principal: e.target.value }))} />
                    </div>
                    <div className="space-y-1.5">
                      <Label>Cargo / Função</Label>
                      <Input value={editForm.cargo_funcao} placeholder="Analista de RH"
                        onChange={e => setEditForm(f => ({ ...f, cargo_funcao: e.target.value }))} />
                    </div>
                    <div className="space-y-1.5">
                      <Label>Data de Nascimento</Label>
                      <Input type="date" value={editForm.data_nascimento}
                        onChange={e => setEditForm(f => ({ ...f, data_nascimento: e.target.value }))} />
                    </div>
                    <div className="sm:col-span-2 space-y-1.5">
                      <Label>Observações</Label>
                      <Textarea rows={2} value={editForm.observacoes} placeholder="Informações internas…"
                        onChange={e => setEditForm(f => ({ ...f, observacoes: e.target.value }))} />
                    </div>
                  </div>
                ) : (
                  /* Visualização */
                  <>
                    <div className="grid grid-cols-2 gap-x-6 gap-y-3 text-sm">
                      {[
                        ["CPF", usuario.cpf ? formatCpf(usuario.cpf) : "—"],
                        ["Telefone", usuario.telefone_principal || "—"],
                        ["Nascimento", usuario.data_nascimento ? fmtDate(usuario.data_nascimento) : "—"],
                        ["Cargo/Função", usuario.cargo_funcao || "—"],
                        ["Nome Social", usuario.nome_social || "—"],
                        ["Matrícula", usuario.matricula || "—"],
                        ["E-mail validado", usuario.email_validado ? "✅ Sim" : "⚠️ Não"],
                        ["Telefone validado", usuario.telefone_validado ? "✅ Sim" : "⚠️ Não"],
                        ["2FA", usuario.autenticacao_2fa ? "✅ Ativo" : "Não ativado"],
                        ["Último acesso", fmt(usuario.ultimo_acesso_em)],
                        ["Primeiro acesso", fmt(usuario.primeiro_acesso_em)],
                        ["Cadastrado em", fmt(usuario.created_at)],
                        ["Cadastrado por", usuario.criado_por_nome || "—"],
                        ["Convite enviado", fmt(usuario.convite_enviado_em)],
                        ["Convite expira", usuario.convite_expira_em ? fmtDate(usuario.convite_expira_em) : "—"],
                      ].map(([label, val]) => (
                        <div key={label as string}>
                          <span className="text-muted-foreground text-xs">{label}</span>
                          <p className="font-medium mt-0.5">{val}</p>
                        </div>
                      ))}
                    </div>

                    {usuario.observacoes && (
                      <div className="p-3 bg-muted/40 rounded-lg text-sm">
                        <span className="text-muted-foreground block mb-1 text-xs">Observações</span>
                        {usuario.observacoes}
                      </div>
                    )}

                    {usuario.sugestao_tipo_ia && (
                      <div className="flex items-center gap-2 p-3 bg-primary/5 border border-primary/20 rounded-lg text-sm text-primary">
                        <Shield className="w-4 h-4 shrink-0" />
                        Sugestão IA: tipo <strong>{TIPO_USUARIO_LABELS[usuario.sugestao_tipo_ia]}</strong>
                      </div>
                    )}
                  </>
                )}

                <Separator />

                {/* Cadastro Completo */}
                <div>
                  <p className="text-sm font-medium mb-2">Cadastro Completo</p>
                  <QualidadeScoreIndicator score={score} pct={pct} />
                  <div className="mt-2 flex flex-wrap gap-1.5">
                    {[
                      { ok: !!usuario.nome_completo, label: "Nome" },
                      { ok: !!usuario.email_principal, label: "E-mail" },
                      { ok: !!usuario.cpf, label: "CPF" },
                      { ok: !!usuario.telefone_principal, label: "Telefone" },
                      { ok: !!usuario.data_nascimento, label: "Nascimento" },
                      { ok: !!usuario.cargo_funcao, label: "Cargo" },
                      { ok: !!usuario.foto_url, label: "Foto" },
                      { ok: vinculosAtivos.length > 0, label: "Vínculo ativo" },
                    ].map(({ ok, label }) => (
                      <span key={label} className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs border ${
                        ok ? "bg-primary/10 text-primary border-primary/30" : "bg-muted text-muted-foreground border-muted"
                      }`}>
                        {ok ? <CheckCircle2 className="w-3 h-3" /> : <span className="w-3 h-3 text-center">○</span>}
                        {label}
                      </span>
                    ))}
                  </div>
                </div>
              </div>
            )}

            {/* ── Tab: Vínculos ── */}
            {tab === "vinculos" && (
              <div className="space-y-3">
                <div className="flex justify-between items-center gap-2 flex-wrap">
                  <p className="text-sm font-medium">Empresas vinculadas</p>
                  <Button size="sm" variant="outline" onClick={() => setAddingVinculo(true)}>
                    <Plus className="w-3.5 h-3.5 mr-1" /> Adicionar vínculo
                  </Button>
                </div>

                {vinculos.length > 0 && (
                  <div className="relative">
                    <Search className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
                    <Input
                      value={buscaVinculo}
                      onChange={e => setBuscaVinculo(e.target.value)}
                      placeholder="Buscar empresa vinculada por nome ou CNPJ…"
                      className="h-8 pl-8 text-sm"
                    />
                  </div>
                )}


                {addingVinculo && (
                  <div className="p-3 border rounded-lg bg-muted/30 space-y-3">
                    <p className="text-sm font-medium">Novo vínculo</p>
                    <div className="grid grid-cols-2 gap-2">
                      <div className="col-span-2 space-y-1">
                        <Label className="text-xs">Empresa *</Label>
                        <EmpresaSearchSelect
                          empresas={empresas}
                          value={novaEmpresaId}
                          onChange={setNovaEmpresaId}
                        />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs">Papel na empresa</Label>
                        <Select defaultValue="gestor" onValueChange={setNovoTipo}>
                          <SelectTrigger className="h-8"><SelectValue /></SelectTrigger>
                          <SelectContent>
                            {Object.entries(TIPO_USUARIO_LABELS).map(([k, v]) => (
                              <SelectItem key={k} value={k}>{v}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs">Contexto</Label>
                        <Input className="h-8" value={novoContexto}
                          onChange={e => setNovoContexto(e.target.value)} placeholder="Ex: SST, RH…" />
                      </div>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      <Button size="sm" onClick={handleAddVinculo} disabled={createVinculo.isPending}>
                        {createVinculo.isPending && <Loader2 className="w-3 h-3 mr-1 animate-spin" />} Salvar
                      </Button>
                      <Button
                        size="sm"
                        variant="secondary"
                        onClick={handleVincularTodas}
                        disabled={createVinculo.isPending}
                        title="Vincula este usuário a todas as empresas do tenant com o papel selecionado"
                      >
                        {createVinculo.isPending
                          ? <Loader2 className="w-3 h-3 mr-1 animate-spin" />
                          : <Building2 className="w-3.5 h-3.5 mr-1" />}
                        Vincular todas as empresas ({empresas.length})
                      </Button>
                      <Button size="sm" variant="ghost" onClick={() => setAddingVinculo(false)}>Cancelar</Button>
                    </div>
                  </div>
                )}

                {vinculos.length === 0 ? (
                  <p className="text-sm text-muted-foreground text-center py-8">Nenhum vínculo cadastrado</p>
                ) : (
                  <>
                    {(() => {
                      const q = buscaVinculo.trim().toLowerCase();
                      const qDigits = q.replace(/\D/g, "");
                      const filtrados = !q ? vinculos : vinculos.filter((v: any) => {
                        const emp = v.empresa || {};
                        const nome = `${emp.razao_social || ""} ${emp.nome_fantasia || ""}`.toLowerCase();
                        const cnpj = (emp.cnpj || "").replace(/\D/g, "");
                        return nome.includes(q) || (qDigits && cnpj.includes(qDigits));
                      });
                      if (filtrados.length === 0) {
                        return <p className="text-sm text-muted-foreground text-center py-8">Nenhum vínculo encontrado para "{buscaVinculo}"</p>;
                      }
                      return ["ativo", "pendente", "suspenso", "revogado", "encerrado", "expirado"].map(statusGrupo => {
                        const grupo = filtrados.filter(v => v.status === statusGrupo);

                      if (grupo.length === 0) return null;
                      return (
                        <div key={statusGrupo}>
                          <p className="text-xs text-muted-foreground uppercase tracking-wide mb-2">
                            {VINCULO_STATUS_LABELS[statusGrupo as any]} ({grupo.length})
                          </p>
                          {grupo.map(v => {
                            const emp = (v as any).empresa;
                            return (
                              <div key={v.id} className="flex items-start gap-3 p-3 border rounded-lg mb-2">
                                <Building2 className="w-4 h-4 text-muted-foreground mt-0.5 shrink-0" />
                                <div className="flex-1 min-w-0">
                                  <div className="flex items-center gap-2 flex-wrap">
                                    <span className="font-medium text-sm">
                                      {emp?.nome_fantasia || emp?.razao_social || "Empresa"}
                                    </span>
                                    {emp?.cnpj && (
                                      <span className="text-xs text-muted-foreground font-mono">
                                        {emp.cnpj}
                                      </span>
                                    )}
                                    <span className={`text-xs px-1.5 py-0.5 rounded-full border ${
                                      v.status === "ativo"
                                        ? "bg-primary/10 text-primary border-primary/30"
                                        : "bg-muted text-muted-foreground border-muted"
                                    }`}>
                                      {VINCULO_STATUS_LABELS[v.status]}
                                    </span>
                                  </div>
                                  <p className="text-xs text-muted-foreground mt-0.5">
                                    {TIPO_USUARIO_LABELS[v.tipo_vinculo]}
                                    {v.contexto_operacional && ` · ${v.contexto_operacional}`}
                                  </p>
                                  <p className="text-xs text-muted-foreground">
                                    Início: {fmtDate(v.data_inicio)}
                                    {v.data_fim && ` · Fim: ${fmtDate(v.data_fim)}`}
                                    {v.aprovado_por_nome && ` · Aprovado por: ${v.aprovado_por_nome}`}
                                  </p>
                                  {v.observacoes && (
                                    <p className="text-xs text-muted-foreground italic mt-0.5">{v.observacoes}</p>
                                  )}
                                </div>
                                {v.status === "ativo" && (
                                  <Button size="sm" variant="ghost"
                                    className="text-destructive hover:bg-destructive/10 shrink-0"
                                    disabled={encerrarVinculo.isPending}
                                    onClick={() => encerrarVinculo.mutateAsync({ id: v.id, usuario_id: usuario.id })}>
                                    {encerrarVinculo.isPending ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Trash2 className="w-3.5 h-3.5" />}
                                  </Button>
                                )}
                              </div>
                            );
                          })}
                        </div>
                      );
                    })})()}
                  </>

                )}
              </div>
            )}

            {/* ── Tab: Logs ── */}
            {tab === "logs" && (
              <div className="space-y-2">
                {logs.length === 0 ? (
                  <p className="text-sm text-muted-foreground text-center py-8">Nenhum registro de auditoria</p>
                ) : (
                  logs.map((log: any) => (
                    <div key={log.id} className="flex gap-3 text-sm border-l-2 border-muted pl-3 py-1.5">
                      <div className="flex-1">
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className="font-medium capitalize">{log.acao.replace(/_/g, " ")}</span>
                          <Badge variant="outline" className="text-xs">{log.objeto}</Badge>
                        </div>
                        {log.executor_nome && (
                          <p className="text-xs text-muted-foreground">por {log.executor_nome}</p>
                        )}
                        <p className="text-xs text-muted-foreground">{fmt(log.created_at)}</p>
                        {log.valor_novo && typeof log.valor_novo === "object" && log.valor_novo.justificativa && (
                          <p className="text-xs text-muted-foreground italic mt-0.5">
                            "{log.valor_novo.justificativa}"
                          </p>
                        )}
                      </div>
                    </div>
                  ))
                )}
              </div>
            )}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
