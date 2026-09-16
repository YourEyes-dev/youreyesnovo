import { useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuthContext } from "@/contexts/AuthContext";
import { useTenant } from "@/hooks/useTenant";
import { supabase } from "@/integrations/supabase/client";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Separator } from "@/components/ui/separator";
import { Badge } from "@/components/ui/badge";
import { toast } from "sonner";
import { User, Mail, Briefcase, Building2, Shield, KeyRound, Camera, ArrowLeft } from "lucide-react";
import { useQueryClient } from "@tanstack/react-query";
import { MeusComprovantesPonto } from "@/components/ponto/MeusComprovantesPonto";

export default function MeuPerfil() {
  const { profile, user, isSuperAdmin, refetch } = useAuthContext() as any;
  const { tenant } = useTenant();
  const queryClient = useQueryClient();
  const navigate = useNavigate();

  const [nomeCompleto, setNomeCompleto] = useState(profile?.nome_completo || "");
  const [saving, setSaving] = useState(false);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Password change
  const [senhaAtual, setSenhaAtual] = useState("");
  const [novaSenha, setNovaSenha] = useState("");
  const [confirmaSenha, setConfirmaSenha] = useState("");
  const [savingPwd, setSavingPwd] = useState(false);

  const getInitials = (name: string) =>
    name.split(" ").map((n) => n[0]).join("").substring(0, 2).toUpperCase();

  const handleSaveProfile = async () => {
    if (!profile?.user_id) return;
    setSaving(true);
    try {
      const { error } = await supabase
        .from("profiles")
        .update({ nome_completo: nomeCompleto })
        .eq("user_id", profile.user_id);
      if (error) throw error;
      // Sync com usuarios_base (tela de Configurações > Usuários)
      await (supabase as any)
        .from("usuarios_base")
        .update({ nome_completo: nomeCompleto })
        .eq("auth_user_id", profile.user_id);
      toast.success("Perfil atualizado com sucesso!");
      queryClient.invalidateQueries({ queryKey: ["profile"] });
      queryClient.invalidateQueries({ queryKey: ["usuarios"] });
      refetch?.();
    } catch (err: any) {
      toast.error(err.message || "Erro ao atualizar perfil");
    } finally {
      setSaving(false);
    }
  };

  const handleAvatarUpload = async (file: File) => {
    if (!profile?.user_id) return;
    if (!file.type.startsWith("image/")) {
      toast.error("Selecione um arquivo de imagem.");
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      toast.error("A imagem deve ter no máximo 5MB.");
      return;
    }
    setUploadingAvatar(true);
    try {
      const ext = file.name.split(".").pop()?.toLowerCase() || "jpg";
      const path = `${profile.user_id}/avatar-${Date.now()}.${ext}`;
      const { error: upErr } = await supabase.storage
        .from("avatars")
        .upload(path, file, { upsert: true, cacheControl: "3600" });
      if (upErr) throw upErr;
      const { data: pub } = supabase.storage.from("avatars").getPublicUrl(path);
      const publicUrl = pub.publicUrl;
      const { error: updErr } = await supabase
        .from("profiles")
        .update({ avatar_url: publicUrl })
        .eq("user_id", profile.user_id);
      if (updErr) throw updErr;
      await (supabase as any)
        .from("usuarios_base")
        .update({ foto_url: publicUrl })
        .eq("auth_user_id", profile.user_id);
      toast.success("Foto atualizada!");
      queryClient.invalidateQueries({ queryKey: ["profile"] });
      queryClient.invalidateQueries({ queryKey: ["usuarios"] });
      refetch?.();
    } catch (err: any) {
      toast.error(err.message || "Erro ao enviar foto");
    } finally {
      setUploadingAvatar(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  };

  const handleChangePassword = async () => {
    if (!novaSenha || !confirmaSenha) {
      toast.error("Preencha a nova senha e a confirmação");
      return;
    }
    if (novaSenha !== confirmaSenha) {
      toast.error("As senhas não coincidem");
      return;
    }
    if (novaSenha.length < 6) {
      toast.error("A senha deve ter no mínimo 6 caracteres");
      return;
    }
    setSavingPwd(true);
    try {
      const { error } = await supabase.auth.updateUser({ password: novaSenha });
      if (error) throw error;
      toast.success("Senha alterada com sucesso!");
      setSenhaAtual("");
      setNovaSenha("");
      setConfirmaSenha("");
    } catch (err: any) {
      toast.error(err.message || "Erro ao alterar senha");
    } finally {
      setSavingPwd(false);
    }
  };

  return (
    <div className="max-w-2xl mx-auto space-y-6 p-6">
      {/* Header */}
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight flex items-center gap-2">
            <User className="h-6 w-6 text-primary" />
            Meu Perfil
          </h1>
          <p className="text-muted-foreground text-sm mt-1">
            Gerencie suas informações pessoais e segurança da conta
          </p>
        </div>
        <Button variant="outline" size="sm" onClick={() => navigate("/")} className="gap-2">
          <ArrowLeft className="h-4 w-4" />
          Voltar
        </Button>
      </div>

      {/* Avatar + info básica */}
      <Card>
        <CardContent className="pt-6">
          <div className="flex items-center gap-6">
            <div className="relative">
              <Avatar className="h-20 w-20">
                <AvatarImage src={profile?.avatar_url || ""} />
                <AvatarFallback className="bg-primary text-primary-foreground text-2xl font-bold">
                  {profile?.nome_completo ? getInitials(profile.nome_completo) : "U"}
                </AvatarFallback>
              </Avatar>
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={(e) => {
                  const f = e.target.files?.[0];
                  if (f) handleAvatarUpload(f);
                }}
              />
              <button
                type="button"
                disabled={uploadingAvatar}
                className="absolute bottom-0 right-0 bg-card border border-border rounded-full p-1.5 shadow-sm hover:bg-muted transition-colors disabled:opacity-50"
                title={uploadingAvatar ? "Enviando..." : "Alterar foto"}
                onClick={() => fileInputRef.current?.click()}
              >
                <Camera className="h-3.5 w-3.5 text-muted-foreground" />
              </button>
            </div>
            <div className="space-y-1">
              <p className="text-xl font-semibold">{profile?.nome_completo || "—"}</p>
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <Briefcase className="h-3.5 w-3.5" />
                {profile?.cargo || "Colaborador"}
              </div>
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <Building2 className="h-3.5 w-3.5" />
                {tenant?.nome || "—"}
              </div>
              {isSuperAdmin && (
                <Badge className="mt-1 gap-1 bg-primary/10 text-primary border-primary/20">
                  <Shield className="h-3 w-3" />
                  Super Admin
                </Badge>
              )}
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Informações da conta */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <User className="h-4 w-4 text-primary" />
            Informações da Conta
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="nome">Nome Completo</Label>
            <Input
              id="nome"
              value={nomeCompleto}
              onChange={(e) => setNomeCompleto(e.target.value)}
              placeholder="Seu nome completo"
            />
          </div>

          <div className="space-y-2">
            <Label>E-mail</Label>
            <div className="flex items-center gap-2 px-3 py-2 rounded-md bg-muted/50 border border-border text-sm text-muted-foreground">
              <Mail className="h-4 w-4 shrink-0" />
              {user?.email || (profile as any)?.email || "—"}
            </div>
            <p className="text-xs text-muted-foreground">O e-mail não pode ser alterado por aqui. Contate o administrador.</p>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Cargo</Label>
              <div className="px-3 py-2 rounded-md bg-muted/50 border border-border text-sm text-muted-foreground">
                {profile?.cargo || "—"}
              </div>
            </div>
            <div className="space-y-2">
              <Label>Departamento</Label>
              <div className="px-3 py-2 rounded-md bg-muted/50 border border-border text-sm text-muted-foreground">
                {(profile as any)?.departamento || "—"}
              </div>
            </div>
          </div>

          <Button onClick={handleSaveProfile} disabled={saving} className="w-full sm:w-auto">
            {saving ? "Salvando..." : "Salvar Alterações"}
          </Button>
        </CardContent>
      </Card>

      {/* Alterar Senha */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <KeyRound className="h-4 w-4 text-primary" />
            Alterar Senha
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="nova-senha">Nova Senha</Label>
            <Input
              id="nova-senha"
              type="password"
              value={novaSenha}
              onChange={(e) => setNovaSenha(e.target.value)}
              placeholder="Mínimo 6 caracteres"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="confirma-senha">Confirmar Nova Senha</Label>
            <Input
              id="confirma-senha"
              type="password"
              value={confirmaSenha}
              onChange={(e) => setConfirmaSenha(e.target.value)}
              placeholder="Repita a nova senha"
            />
          </div>
          <Button
            onClick={handleChangePassword}
            disabled={savingPwd || !novaSenha || !confirmaSenha}
            variant="outline"
            className="w-full sm:w-auto"
          >
            {savingPwd ? "Alterando..." : "Alterar Senha"}
          </Button>
        </CardContent>
      </Card>

      {/* Comprovantes das próprias batidas (Portaria MTP 671/2021). O cartão
          não aparece para quem não tem CPF vinculado à conta. */}
      <MeusComprovantesPonto />
    </div>
  );
}
