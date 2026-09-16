import { useEffect, useMemo, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import {
  Plus, Search, MoreVertical, UserPlus, Eye, Power, Rocket, Edit, Trash2, AlertTriangle, Loader2, CreditCard,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useSuperAdmin, TenantWithStats } from "@/hooks/useSuperAdmin";
import { TenantForm } from "@/components/admin/TenantForm";
import { TenantOwnerForm } from "@/components/admin/TenantOwnerForm";
import { PromoverContaRaizModal } from "@/components/admin/PromoverContaRaizModal";
import { EmpresasPromociveisPanel } from "@/components/admin/superadmin/EmpresasPromociveisPanel";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import { toast } from "sonner";

// Seção "Empresas" do Painel Super Admin: lista das empresas (matrizes com
// filiais agrupadas), busca, ações por empresa (editar, detalhes, assinatura,
// criar owner, promover a conta-raiz, ativar/desativar, excluir) e, abaixo,
// as empresas promovíveis. O atalho "Nova Empresa" da barra superior chega
// aqui como ?nova=1 e abre o formulário de cadastro.
export function TenantsPanel() {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const { tenants, isLoading, createTenant, updateTenant, toggleTenant, deleteTenant, isCreatingTenant, isUpdatingTenant } = useSuperAdmin();

  const [searchTerm, setSearchTerm] = useState("");
  const [showTenantForm, setShowTenantForm] = useState(false);
  const [showEditForm, setShowEditForm] = useState(false);
  const [showOwnerForm, setShowOwnerForm] = useState(false);
  const [selectedTenant, setSelectedTenant] = useState<TenantWithStats | null>(null);
  const [showSpinoff, setShowSpinoff] = useState(false);
  const [spinoffTenant, setSpinoffTenant] = useState<TenantWithStats | null>(null);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [deleteConfirmationText, setDeleteConfirmationText] = useState("");
  const [isDeleting, setIsDeleting] = useState(false);

  // Atalho da barra superior: /admin/empresas?nova=1 abre o cadastro e limpa o parâmetro.
  useEffect(() => {
    if (searchParams.get("nova") !== "1") return;
    setShowTenantForm(true);
    const proximos = new URLSearchParams(searchParams);
    proximos.delete("nova");
    setSearchParams(proximos, { replace: true });
  }, [searchParams, setSearchParams]);

  const filteredTenants = tenants.filter((t) =>
    t.nome.toLowerCase().includes(searchTerm.toLowerCase()) ||
    t.slug.toLowerCase().includes(searchTerm.toLowerCase())
  );

  // Conta empresas derivadas (total - principal) por tenant para saber se "Promover" faz sentido
  const { data: empresasAll = [] } = useQuery({
    queryKey: ["superadmin-empresas-all"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("superadmin_list_all_empresas");
      if (error) throw error;
      return (data ?? []) as Array<{ tenant_id: string; total_empresas_tenant: number }>;
    },
  });
  const derivadasPorTenant = useMemo(() => {
    const map = new Map<string, number>();
    for (const e of empresasAll) {
      const total = Number(e.total_empresas_tenant) || 0;
      map.set(e.tenant_id, Math.max(0, total - 1));
    }
    return map;
  }, [empresasAll]);

  const handleToggleTenant = async (tenant: TenantWithStats) => {
    try {
      await toggleTenant({ id: tenant.id, ativo: !tenant.ativo });
      toast.success(tenant.ativo ? "Empresa desativada" : "Empresa ativada");
    } catch { toast.error("Erro ao alterar status"); }
  };

  const handleDeleteTenant = async () => {
    if (!selectedTenant || deleteConfirmationText !== "EXCLUIR") return;

    try {
      setIsDeleting(true);
      await deleteTenant(selectedTenant.id);
      toast.success("Empresa excluída permanentemente");
      setShowDeleteConfirm(false);
      setSelectedTenant(null);
      setDeleteConfirmationText("");
    } catch (e) {
      toast.error(e instanceof Error && e.message ? e.message : "Erro ao excluir empresa");
    } finally {
      setIsDeleting(false);
    }
  };

  return (
    <div className="space-y-8" data-testid="admin-empresas">
      <Card>
        <CardHeader className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
          <div>
            <CardTitle>Empresas Cadastradas</CardTitle>
            <CardDescription>Principais empresas (Matrizes) e suas filiais agrupadas.</CardDescription>
          </div>
          <div className="flex items-center gap-2">
            <div className="relative w-full md:w-64">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input placeholder="Buscar empresa ou CNPJ..." value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)} className="pl-9" />
            </div>
            <Button size="sm" onClick={() => setShowTenantForm(true)} data-testid="admin-empresas-nova">
              <Plus className="w-4 h-4 mr-2" />Nova Empresa
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="text-center py-8">Carregando...</div>
          ) : filteredTenants.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground">Nenhuma empresa</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Empresa</TableHead>
                  <TableHead>CNPJ</TableHead>
                  <TableHead>Plano</TableHead>
                  <TableHead className="text-center">Usuários</TableHead>
                  <TableHead className="text-center">Colab.</TableHead>
                  <TableHead>Criado</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="w-12"></TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredTenants.map((tenant) => (
                  <TableRow key={tenant.id}>
                    <TableCell className="font-medium">{tenant.nome}</TableCell>
                    <TableCell><code className="text-xs bg-muted px-2 py-1 rounded">{tenant.cnpj || "—"}</code></TableCell>
                    <TableCell><Badge variant="outline" className="capitalize">{tenant.plano_atual ?? tenant.plano}</Badge></TableCell>
                    <TableCell className="text-center">{tenant.total_usuarios}</TableCell>
                    <TableCell className="text-center">{tenant.total_colaboradores}</TableCell>
                    <TableCell className="text-xs">{format(new Date(tenant.created_at), "dd/MM/yy", { locale: ptBR })}</TableCell>
                    <TableCell>
                      {tenant.ativo
                        ? <Badge className="bg-emerald-500/10 text-emerald-600 border-emerald-500/20">Ativa</Badge>
                        : <Badge variant="destructive">Inativa</Badge>}
                    </TableCell>
                    <TableCell>
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <Button variant="ghost" size="icon"><MoreVertical className="w-4 h-4" /></Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          <DropdownMenuItem onClick={() => { setSelectedTenant(tenant); setShowEditForm(true); }}>
                            <Edit className="w-4 h-4 mr-2" />Editar empresa
                          </DropdownMenuItem>
                          <DropdownMenuItem onClick={() => navigate(`/admin/tenants/${tenant.id}`)}>
                            <Eye className="w-4 h-4 mr-2" />Ver detalhes
                          </DropdownMenuItem>
                          <DropdownMenuItem onClick={() => navigate(`/admin/tenants/${tenant.id}/assinatura`)}>
                            <CreditCard className="w-4 h-4 mr-2" />Assinatura e teste
                          </DropdownMenuItem>
                          <DropdownMenuItem onClick={() => { setSelectedTenant(tenant); setShowOwnerForm(true); }}>
                            <UserPlus className="w-4 h-4 mr-2" />Criar usuário owner
                          </DropdownMenuItem>
                          {(derivadasPorTenant.get(tenant.id) ?? 0) > 0 && (
                            <DropdownMenuItem onClick={() => { setSpinoffTenant(tenant); setShowSpinoff(true); }}>
                              <Rocket className="w-4 h-4 mr-2" />Promover empresa a Conta-Raiz
                            </DropdownMenuItem>
                          )}

                          <DropdownMenuItem onClick={() => handleToggleTenant(tenant)}>
                            <Power className="w-4 h-4 mr-2" />{tenant.ativo ? "Desativar" : "Ativar"}
                          </DropdownMenuItem>

                          <DropdownMenuItem
                            onClick={() => { setSelectedTenant(tenant); setShowDeleteConfirm(true); }}
                            className="text-destructive focus:text-destructive"
                          >
                            <Trash2 className="w-4 h-4 mr-2" />Excluir empresa
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <div className="pt-8 border-t">
        <EmpresasPromociveisPanel />
      </div>

      {/* Modais */}
      <Dialog open={showTenantForm} onOpenChange={setShowTenantForm}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Nova Empresa</DialogTitle>
            <DialogDescription>Cadastre a empresa e o administrador principal</DialogDescription>
          </DialogHeader>
          {showTenantForm && (
            <TenantForm
              key={`tenant-form-${showTenantForm}`}
              onSubmit={async (data) => {
                try {
                  const result = await createTenant(data);
                  toast.success(result.inviteSent ? "Empresa criada! Convite enviado." : "Empresa criada com sucesso!");
                  setShowTenantForm(false);
                } catch (e) { toast.error(e instanceof Error && e.message ? e.message : "Erro"); }
              }}
              isLoading={isCreatingTenant}
              onCancel={() => setShowTenantForm(false)}
            />
          )}
        </DialogContent>
      </Dialog>

      <Dialog open={showEditForm} onOpenChange={setShowEditForm}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Editar Empresa</DialogTitle>
            <DialogDescription>Atualize os dados da empresa</DialogDescription>
          </DialogHeader>
          {showEditForm && selectedTenant && (
            <TenantForm
              initialData={{
                nome: selectedTenant.nome,
                slug: selectedTenant.slug,
                email: selectedTenant.email,
                telefone: selectedTenant.telefone,
                cnpj: selectedTenant.cnpj,
              }}
              onSubmit={async (data) => {
                try {
                  await updateTenant({
                    id: selectedTenant.id,
                    nome: data.nome,
                    slug: data.slug,
                    email: data.email,
                    telefone: data.telefone,
                    cnpj: data.cnpj,
                  });
                  toast.success("Empresa atualizada com sucesso!");
                  setShowEditForm(false);
                  setSelectedTenant(null);
                } catch (e) {
                  toast.error(e instanceof Error && e.message ? e.message : "Erro ao atualizar empresa");
                }
              }}
              isLoading={isUpdatingTenant}
              onCancel={() => {
                setShowEditForm(false);
                setSelectedTenant(null);
              }}
            />
          )}
        </DialogContent>
      </Dialog>

      <Dialog open={showOwnerForm} onOpenChange={setShowOwnerForm}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Adicionar Administrador - {selectedTenant?.nome}</DialogTitle>
            <DialogDescription>Crie um novo usuário administrador</DialogDescription>
          </DialogHeader>
          {selectedTenant && (
            <TenantOwnerForm
              tenantId={selectedTenant.id}
              onSuccess={() => { setShowOwnerForm(false); setSelectedTenant(null); }}
              onCancel={() => { setShowOwnerForm(false); setSelectedTenant(null); }}
            />
          )}
        </DialogContent>
      </Dialog>

      {spinoffTenant && (
        <PromoverContaRaizModal
          open={showSpinoff}
          onOpenChange={(v) => { setShowSpinoff(v); if (!v) setSpinoffTenant(null); }}
          tenantId={spinoffTenant.id}
          tenantNome={spinoffTenant.nome}
        />
      )}

      <Dialog open={showDeleteConfirm} onOpenChange={setShowDeleteConfirm}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2 text-destructive">
              <AlertTriangle className="w-5 h-5" />
              Ação Irreversível
            </DialogTitle>
            <DialogDescription className="space-y-4 pt-2">
              <p className="font-semibold text-foreground">
                Você está prestes a excluir permanentemente a empresa <span className="underline">{selectedTenant?.nome}</span>.
              </p>
              <div className="bg-destructive/10 p-3 rounded-md border border-destructive/20 text-destructive text-xs">
                <p className="font-bold mb-1 uppercase">Aviso Crítico:</p>
                <ul className="list-disc ml-4 space-y-1">
                  <li>Todos os usuários vinculados perderão acesso.</li>
                  <li>Todas as empresas dependentes (filiais) serão removidas.</li>
                  <li>Dados de colaboradores, ponto, financeiro e SST serão apagados.</li>
                  <li>Esta ação NÃO pode ser desfeita.</li>
                </ul>
              </div>
              <div className="space-y-2 pt-2">
                <Label htmlFor="confirm-delete">Para confirmar, digite <strong>EXCLUIR</strong> abaixo:</Label>
                <Input
                  id="confirm-delete"
                  placeholder="Digite EXCLUIR"
                  value={deleteConfirmationText}
                  onChange={(e) => setDeleteConfirmationText(e.target.value.toUpperCase())}
                  className="border-destructive/30 focus-visible:ring-destructive"
                />
              </div>
            </DialogDescription>
          </DialogHeader>
          <div className="flex justify-end gap-2 pt-4">
            <Button variant="outline" onClick={() => { setShowDeleteConfirm(false); setDeleteConfirmationText(""); }}>
              Cancelar
            </Button>
            <Button
              variant="destructive"
              onClick={handleDeleteTenant}
              disabled={deleteConfirmationText !== "EXCLUIR" || isDeleting}
            >
              {isDeleting && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
              Excluir Permanentemente
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
