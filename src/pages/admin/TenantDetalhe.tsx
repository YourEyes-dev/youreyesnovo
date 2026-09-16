import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useSuperAdmin } from '@/hooks/useSuperAdmin';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { ArrowLeft, Building2, Users, LayoutDashboard, Shield } from 'lucide-react';
import { Skeleton } from '@/components/ui/skeleton';
import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useParceiros, PARCEIRO_TIPO_LABEL } from '@/hooks/useParceiros';
import { Handshake } from 'lucide-react';

// Origem comercial da empresa (Programa de Parceiros): quem indicou e quem implanta.
function ParceiroOrigemCard({ tenantId }: { tenantId: string }) {
  const { tenants, parceiros, vincularTenant } = useParceiros();
  const t = tenants.find((x) => x.id === tenantId);
  const NENHUM = '__nenhum__';
  const elegiveis = parceiros.filter((p) => p.status === 'ativo' || p.status === 'pendente' || p.id === t?.parceiro_id || p.id === t?.implantador_parceiro_id);
  return (
    <Card data-testid="tenant-parceiro-origem">
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base"><Handshake className="w-4 h-4 text-primary" />Parceiro de origem e implantação</CardTitle>
      </CardHeader>
      <CardContent className="grid gap-4 md:grid-cols-2">
        <div>
          <p className="text-xs text-muted-foreground mb-1">Quem indicou esta empresa</p>
          <Select value={t?.parceiro_id ?? NENHUM} disabled={!t}
            onValueChange={(v) => vincularTenant.mutate({ tenantId, parceiroId: v === NENHUM ? null : v, implantadorId: t?.implantador_parceiro_id ?? null })}>
            <SelectTrigger><SelectValue placeholder="Carregando…" /></SelectTrigger>
            <SelectContent>
              <SelectItem value={NENHUM}>— sem parceiro (veio direto) —</SelectItem>
              {elegiveis.map((p) => <SelectItem key={p.id} value={p.id}>{p.nome} · {PARCEIRO_TIPO_LABEL[p.tipo_parceiro]}</SelectItem>)}
            </SelectContent>
          </Select>
          {t?.originado_em && <p className="text-xs text-muted-foreground mt-1">Origem registrada em {new Date(t.originado_em).toLocaleDateString('pt-BR')}</p>}
        </div>
        <div>
          <p className="text-xs text-muted-foreground mb-1">Quem faz a implantação</p>
          <Select value={t?.implantador_parceiro_id ?? NENHUM} disabled={!t}
            onValueChange={(v) => vincularTenant.mutate({ tenantId, parceiroId: t?.parceiro_id ?? null, implantadorId: v === NENHUM ? null : v })}>
            <SelectTrigger><SelectValue placeholder="Carregando…" /></SelectTrigger>
            <SelectContent>
              <SelectItem value={NENHUM}>— a própria casa —</SelectItem>
              {elegiveis.filter((p) => p.tipo_parceiro !== 'indicador').map((p) => <SelectItem key={p.id} value={p.id}>{p.nome} · {PARCEIRO_TIPO_LABEL[p.tipo_parceiro]}</SelectItem>)}
            </SelectContent>
          </Select>
          <p className="text-xs text-muted-foreground mt-1">O implantador recebe o valor de setup configurado em Parceiros › Níveis e remuneração.</p>
        </div>
      </CardContent>
    </Card>
  );
}

export default function TenantDetalhe() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { tenants, getTenantUsers } = useSuperAdmin();
  const [users, setUsers] = useState<any[]>([]);
  const [loadingUsers, setLoadingUsers] = useState(true);

  const tenant = tenants.find(t => t.id === id);

  useEffect(() => {
    async function loadUsers() {
      if (id) {
        try {
          const data = await getTenantUsers(id);
          setUsers(data || []);
        } catch (error) {
          console.error("Erro ao carregar usuários:", error);
        } finally {
          setLoadingUsers(false);
        }
      }
    }
    loadUsers();
  }, [id, getTenantUsers]);

  if (!tenant && !loadingUsers) {
    return (
      <div className="p-8 text-center">
        <h2 className="text-2xl font-bold">Empresa não encontrada</h2>
        <Button onClick={() => navigate('/admin')} className="mt-4">
          <ArrowLeft className="w-4 h-4 mr-2" /> Voltar ao Painel
        </Button>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background p-4 md:p-6">
      <div className="max-w-[1200px] mx-auto space-y-6">
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" onClick={() => navigate('/admin')}>
            <ArrowLeft className="w-5 h-5" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold flex items-center gap-2">
              <Building2 className="w-6 h-6 text-primary" />
              {tenant?.nome || <Skeleton className="h-8 w-48" />}
            </h1>
            <p className="text-sm text-muted-foreground">
              Detalhes da empresa e gestão de acessos
            </p>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <Card>
            <CardHeader className="flex flex-row items-center justify-between pb-2">
              <CardTitle className="text-sm font-medium">Plano Atual</CardTitle>
              <Shield className="w-4 h-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold capitalize">{tenant?.plano_atual ?? tenant?.plano ?? '...'}</div>
              <p className="text-xs text-muted-foreground mt-1">Tenant ID: {id}</p>
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="flex flex-row items-center justify-between pb-2">
              <CardTitle className="text-sm font-medium">Total de Usuários</CardTitle>
              <Users className="w-4 h-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{tenant?.total_usuarios ?? '...'}</div>
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="flex flex-row items-center justify-between pb-2">
              <CardTitle className="text-sm font-medium">Status</CardTitle>
              <LayoutDashboard className="w-4 h-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              {tenant ? (
                <Badge className={tenant.ativo ? "bg-emerald-500/10 text-emerald-600" : ""}>
                  {tenant.ativo ? "Ativa" : "Inativa"}
                </Badge>
              ) : <Skeleton className="h-6 w-20" />}
            </CardContent>
          </Card>
        </div>

        {id && <ParceiroOrigemCard tenantId={id} />}

        <Card>
          <CardHeader>
            <CardTitle>Usuários Vinculados</CardTitle>
          </CardHeader>
          <CardContent>
            {loadingUsers ? (
              <div className="space-y-2">
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-10 w-full" />
              </div>
            ) : users.length === 0 ? (
              <p className="text-center py-8 text-muted-foreground">Nenhum usuário encontrado para esta empresa.</p>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Nome</TableHead>
                    <TableHead>E-mail</TableHead>
                    <TableHead>Função</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {users.map((user) => (
                    <TableRow key={user.id}>
                      <TableCell className="font-medium">{user.nome_completo || 'Sem nome'}</TableCell>
                      <TableCell>{user.email}</TableCell>
                      <TableCell>
                        <Badge variant="outline" className="capitalize">
                          {user.user_roles?.[0]?.role || 'Sem role'}
                        </Badge>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
