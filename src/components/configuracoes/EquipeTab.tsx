import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { mensagemDaFuncao } from "@/lib/supabaseFunctions";
import { useTenant } from "@/hooks/useTenant";
import { useAuthContext } from "@/contexts/AuthContext";
import { toast } from "sonner";
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from "@/components/ui/dialog";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from "@/components/ui/table";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import {
  UserPlus, Mail, Key, Loader2, Users, Shield, MoreHorizontal, Pencil, Trash2, RefreshCw, CheckCircle2, Clock,
} from "lucide-react";

interface TenantUser {
  user_id: string;
  nome_completo: string | null;
  email: string;
  roles: string[];
  confirmed: boolean;
  last_sign_in: string | null;
}

const ROLE_LABELS: Record<string, string> = {
  owner: "Owner",
  admin: "Administrador",
  manager: "Gestor",
  user: "Usuário",
};

const ROLE_COLORS: Record<string, string> = {
  owner: "bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300",
  admin: "bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-300",
  manager: "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300",
  user: "bg-muted text-muted-foreground",
};

export function EquipeTab() {
  const { tenantId } = useTenant();
  const { hasMinimumRole, user } = useAuthContext();
  const queryClient = useQueryClient();

  // Invite dialog
  const [open, setOpen] = useState(false);
  const [nome, setNome] = useState("");
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<string>("user");
  const [method, setMethod] = useState<"invite" | "password">("password");
  const [password, setPassword] = useState("");

  // Edit role dialog
  const [editUser, setEditUser] = useState<TenantUser | null>(null);
  const [editRole, setEditRole] = useState<string>("user");

  // Remove dialog
  const [removeUser, setRemoveUser] = useState<TenantUser | null>(null);

  const isOwner = hasMinimumRole("owner");

  // ─── LIST USERS (via edge function for email/status) ───
  const { data: users = [], isLoading } = useQuery({
    queryKey: ["tenant-users", tenantId],
    queryFn: async (): Promise<TenantUser[]> => {
      const { data, error } = await supabase.functions.invoke("manage-tenant-users", {
        body: { action: "list" },
      });
      if (error) throw new Error(error.message);
      if (data?.error) {
        if (data.error === "Invalid token" || data.error === "Missing Authorization") {
          toast.error("Sessão expirada. Faça login novamente.");
        }
        throw new Error(data.error);
      }
      return data?.users || [];
    },
    enabled: !!tenantId,
    retry: false,
  });

  // ─── INVITE / CREATE USER ───
  const inviteMutation = useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.functions.invoke("invite-tenant-user", {
        body: { email, nomeCompleto: nome, role, method, password: method === "password" ? password : undefined },
      });
      // non-2xx guarda o motivo real em error.context; sem extrair, toda falha
      // vira a mesma "Edge Function returned a non-2xx status code".
      if (error || data?.error) throw new Error(await mensagemDaFuncao(error, data));
      return data;
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ["tenant-users"] });
      toast.success(data?.inviteSent ? "Convite enviado por e-mail!" : "Usuário criado com sucesso!");
      resetForm();
    },
    onError: (err: Error) => toast.error(err.message || "Erro ao convidar usuário"),
  });

  // ─── UPDATE ROLE ───
  const updateRoleMutation = useMutation({
    mutationFn: async ({ userId, newRole }: { userId: string; newRole: string }) => {
      const { data, error } = await supabase.functions.invoke("manage-tenant-users", {
        body: { action: "update_role", userId, newRole },
      });
      if (error) throw new Error(error.message);
      if (data?.error) throw new Error(data.error);
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["tenant-users"] });
      toast.success("Perfil atualizado com sucesso!");
      setEditUser(null);
    },
    onError: (err: Error) => toast.error(err.message),
  });

  // ─── REMOVE USER ───
  const removeMutation = useMutation({
    mutationFn: async (userId: string) => {
      const { data, error } = await supabase.functions.invoke("manage-tenant-users", {
        body: { action: "remove", userId },
      });
      if (error) throw new Error(error.message);
      if (data?.error) throw new Error(data.error);
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["tenant-users"] });
      toast.success("Usuário removido do tenant.");
      setRemoveUser(null);
    },
    onError: (err: Error) => toast.error(err.message),
  });

  // ─── RESEND INVITE ───
  const resendMutation = useMutation({
    mutationFn: async (userId: string) => {
      const { data, error } = await supabase.functions.invoke("manage-tenant-users", {
        body: { action: "resend_invite", userId },
      });
      if (error) throw new Error(error.message);
      if (data?.error) throw new Error(data.error);
      return data;
    },
    onSuccess: () => toast.success("Convite reenviado com sucesso!"),
    onError: (err: Error) => toast.error(err.message),
  });

  const resetForm = () => {
    setNome(""); setEmail(""); setRole("user"); setMethod("password"); setPassword(""); setOpen(false);
  };

  const isSelf = (userId: string) => user?.id === userId;
  const isTargetOwner = (u: TenantUser) => u.roles.includes("owner");

  return (
    <>
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between w-full">
            <div>
              <CardTitle className="flex items-center gap-2">
                <Users className="h-5 w-5" /> Equipe
              </CardTitle>
              <CardDescription>Gerencie os usuários com acesso ao sistema</CardDescription>
            </div>
          <Dialog open={open} onOpenChange={setOpen}>
            <DialogTrigger asChild>
              <Button size="sm" className="gap-2">
                <UserPlus className="h-4 w-4" /> Adicionar Usuário
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Adicionar Usuário</DialogTitle>
                <DialogDescription>Convide um novo membro para sua equipe</DialogDescription>
              </DialogHeader>
              <div className="space-y-4 py-2">
                <div className="space-y-2">
                  <Label>Nome Completo</Label>
                  <Input value={nome} onChange={(e) => setNome(e.target.value)} placeholder="Nome do colaborador" />
                </div>
                <div className="space-y-2">
                  <Label>E-mail</Label>
                  <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="email@empresa.com" />
                </div>
                <div className="space-y-2">
                  {/* Papel (admin/gestor/usuário) não é o Perfil de Acesso da
                      tela de Perfis — o parecer de 07/08 pediu rótulos
                      distintos para os dois conceitos. */}
                  <Label>Papel na plataforma</Label>
                  <Select value={role} onValueChange={setRole}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {isOwner && <SelectItem value="admin">Administrador</SelectItem>}
                      <SelectItem value="manager">Gestor</SelectItem>
                      <SelectItem value="user">Usuário</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-3">
                  <Label>Método de Acesso</Label>
                  <RadioGroup value={method} onValueChange={(v) => setMethod(v as "invite" | "password")} className="flex gap-4">
                    <div className="flex items-center gap-2">
                      <RadioGroupItem value="invite" id="m-invite" />
                      <Label htmlFor="m-invite" className="flex items-center gap-1.5 cursor-pointer">
                        <Mail className="h-4 w-4" /> Convite por e-mail
                      </Label>
                    </div>
                    <div className="flex items-center gap-2">
                      <RadioGroupItem value="password" id="m-password" />
                      <Label htmlFor="m-password" className="flex items-center gap-1.5 cursor-pointer">
                        <Key className="h-4 w-4" /> Criar com senha
                      </Label>
                    </div>
                  </RadioGroup>
                </div>
                {method === "password" && (
                  <div className="space-y-2">
                    <Label>Senha Temporária</Label>
                    <Input type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Mínimo 6 caracteres" />
                  </div>
                )}
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={resetForm}>Cancelar</Button>
                <Button
                  onClick={() => inviteMutation.mutate()}
                  disabled={inviteMutation.isPending || !nome.trim() || !email.trim() || (method === "password" && password.length < 6)}
                >
                  {inviteMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : method === "invite" ? <Mail className="h-4 w-4 mr-2" /> : <UserPlus className="h-4 w-4 mr-2" />}
                  {method === "invite" ? "Enviar Convite" : "Criar Usuário"}
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
          </div>
        </CardHeader>

        <CardContent>
          {isLoading ? (
            <div className="flex justify-center py-8">
              <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
            </div>
          ) : users.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground">
              <Shield className="h-10 w-10 mx-auto mb-3 opacity-40" />
              <p>Nenhum usuário encontrado.</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Nome</TableHead>
                    <TableHead>E-mail</TableHead>
                    <TableHead>Perfil</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead className="w-12"></TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {users.map((u) => (
                    <TableRow key={u.user_id}>
                      <TableCell className="font-medium">{u.nome_completo || "—"}</TableCell>
                      <TableCell className="text-muted-foreground text-sm">{u.email}</TableCell>
                      <TableCell>
                        <div className="flex gap-1.5 flex-wrap">
                          {u.roles.map((r) => (
                            <Badge key={r} variant="outline" className={ROLE_COLORS[r] || ""}>
                              {ROLE_LABELS[r] || r}
                            </Badge>
                          ))}
                        </div>
                      </TableCell>
                      <TableCell>
                        {u.confirmed ? (
                          <Badge variant="outline" className="bg-emerald-50 text-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-400 gap-1">
                            <CheckCircle2 className="h-3 w-3" /> Ativo
                          </Badge>
                        ) : (
                          <Badge variant="outline" className="bg-orange-50 text-orange-700 dark:bg-orange-900/20 dark:text-orange-400 gap-1">
                            <Clock className="h-3 w-3" /> Pendente
                          </Badge>
                        )}
                      </TableCell>
                      <TableCell>
                        {!isSelf(u.user_id) && !isTargetOwner(u) && (
                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <Button variant="ghost" size="icon" className="h-8 w-8">
                                <MoreHorizontal className="h-4 w-4" />
                              </Button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end">
                              <DropdownMenuItem onClick={() => { setEditUser(u); setEditRole(u.roles.find(r => r !== "owner") || "user"); }}>
                                <Pencil className="h-4 w-4 mr-2" /> Editar Perfil
                              </DropdownMenuItem>
                              {!u.confirmed && (
                                <DropdownMenuItem onClick={() => resendMutation.mutate(u.user_id)} disabled={resendMutation.isPending}>
                                  <RefreshCw className="h-4 w-4 mr-2" /> Reenviar Convite
                                </DropdownMenuItem>
                              )}
                              <DropdownMenuSeparator />
                              <DropdownMenuItem className="text-destructive" onClick={() => setRemoveUser(u)}>
                                <Trash2 className="h-4 w-4 mr-2" /> Remover
                              </DropdownMenuItem>
                            </DropdownMenuContent>
                          </DropdownMenu>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Edit Role Dialog */}
      <Dialog open={!!editUser} onOpenChange={(v) => !v && setEditUser(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Editar papel na plataforma</DialogTitle>
            <DialogDescription>Altere o papel de {editUser?.nome_completo} (administrador, gestor ou usuário)</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-2">
              <Label>Novo papel</Label>
              <Select value={editRole} onValueChange={setEditRole}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {isOwner && <SelectItem value="admin">Administrador</SelectItem>}
                  <SelectItem value="manager">Gestor</SelectItem>
                  <SelectItem value="user">Usuário</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditUser(null)}>Cancelar</Button>
            <Button
              onClick={() => editUser && updateRoleMutation.mutate({ userId: editUser.user_id, newRole: editRole })}
              disabled={updateRoleMutation.isPending}
            >
              {updateRoleMutation.isPending && <Loader2 className="h-4 w-4 animate-spin mr-2" />}
              Salvar
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Remove User Confirmation */}
      <AlertDialog open={!!removeUser} onOpenChange={(v) => !v && setRemoveUser(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remover Usuário</AlertDialogTitle>
            <AlertDialogDescription>
              Tem certeza que deseja remover <strong>{removeUser?.nome_completo}</strong> ({removeUser?.email}) do sistema?
              Esta ação não pode ser desfeita.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
              onClick={() => removeUser && removeMutation.mutate(removeUser.user_id)}
            >
              {removeMutation.isPending && <Loader2 className="h-4 w-4 animate-spin mr-2" />}
              Remover
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
