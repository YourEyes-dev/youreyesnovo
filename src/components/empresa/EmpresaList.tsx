import { useState, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Building2, Search, Filter, Download, Plus, ToggleLeft, ToggleRight, Edit, Eye, CheckSquare, Square, AlertTriangle, Layers, GitBranch, Upload, FileSpreadsheet, FileText, ChevronDown, Trash2, Users, Clock } from 'lucide-react';
import { formatCnpj } from '@/lib/cnpj';
import { formatCpf } from '@/lib/cpf';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { EmpresaImportExport } from './EmpresaImportExport';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Checkbox } from '@/components/ui/checkbox';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { toast } from 'sonner';
import { exportEmpresasToXlsx, exportEmpresasToPdf } from '@/utils/empresaExport';
import type { EmpresaCadastro } from '@/types/empresa';
import type { GrupoEconomico } from '@/hooks/useGruposEconomicos';
import { useAuthContext } from '@/contexts/AuthContext';
import { usePerfilPermissions } from "@/hooks/usePerfilPermissions";
import { AcaoProtegida } from "@/components/shared/AcaoProtegida";

interface EmpresaListProps {
  empresas: (EmpresaCadastro & { ativo: boolean })[];
  isLoading: boolean;
  onEdit: (id: string) => void;
  onNew: () => void;
  onToggleAtivo: (id: string, ativo: boolean) => void;
  onDelete?: (id: string, nome: string) => void;
  onBatchDelete?: (items: { id: string; nome: string }[]) => Promise<{ ok: number; failed: { nome: string; error: string }[] }>;
  grupos?: GrupoEconomico[];
  obrigacoes?: any[];
}

export function EmpresaList({ empresas, isLoading, onEdit, onNew, onToggleAtivo, onDelete, onBatchDelete, grupos = [], obrigacoes = [] }: EmpresaListProps) {
  const { tenantId } = useAuthContext() as any;
  const { data: counts = {} } = useQuery({
    queryKey: ['empresa_colaboradores_counts', tenantId],
    queryFn: async () => {
      // Usa RPC agregada — evita o limite default de 1000 linhas do Supabase,
      // que estava truncando contagens em tenants com muitos colaboradores.
      const { data, error } = await (supabase as any).rpc('contar_colaboradores_por_empresa', {
        p_tenant_id: tenantId,
      });
      if (error) throw error;
      const map: Record<string, number> = {};
      (data ?? []).forEach((row: { empresa_id: string; total: number }) => {
        if (row.empresa_id) map[row.empresa_id] = Number(row.total) || 0;
      });
      return map;
    },
    enabled: !!tenantId,
  });

  const { hasRole, isSuperAdmin } = useAuthContext() as any;
  const { podeExcluir: perfilPodeExcluir } = usePerfilPermissions();
  // Era `const podeExcluir = true` — liberado para qualquer usuário
  // autenticado, apoiado só na confirmação dupla e na RLS. A confirmação
  // evita o clique errado, não o usuário sem alçada. Passa a consultar o
  // perfil de acesso (recomendação nº 3 do parecer de 07/08). Quem não tem
  // perfil vinculado segue pela hierarquia de papéis, como antes.
  const podeExcluir = perfilPodeExcluir("configuracoes");
  const [search, setSearch] = useState('');
  const [filtroStatus, setFiltroStatus] = useState<string>('todos');
  const [filtroUF, setFiltroUF] = useState<string>('todos');
  const [filtroGrauRisco, setFiltroGrauRisco] = useState<string>('todos');
  const [filtroGrupo, setFiltroGrupo] = useState<string>('todos');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [importOpen, setImportOpen] = useState(false);

  // Stats
  const stats = useMemo(() => {
    const total = empresas.length;
    const ativas = empresas.filter(e => e.ativo).length;
    const inativas = total - ativas;
    const grauAlto = empresas.filter(e => (e.grau_risco ?? 0) >= 3 && e.ativo).length;
    return { total, ativas, inativas, grauAlto };
  }, [empresas]);

  // UFs disponíveis
  const ufs = useMemo(() => {
    const set = new Set(empresas.map(e => e.estado).filter(Boolean) as string[]);
    return Array.from(set).sort();
  }, [empresas]);

  // Filtros
  const filtered = useMemo(() => {
    return empresas.filter(e => {
      if (filtroStatus === 'ativas' && !e.ativo) return false;
      if (filtroStatus === 'inativas' && e.ativo) return false;
      if (filtroUF !== 'todos' && e.estado !== filtroUF) return false;
      if (filtroGrauRisco !== 'todos' && String(e.grau_risco) !== filtroGrauRisco) return false;
      if (filtroGrupo !== 'todos') {
        if (filtroGrupo === '_sem_grupo') {
          if (e.grupo_economico_id) return false;
        } else {
          if (e.grupo_economico_id !== filtroGrupo) return false;
        }
      }
      if (search) {
        // Normaliza para busca tolerante: minúsculas + sem acentos/diacríticos.
        // Assim "grafica" acha "Gráfica", "vere" acha "Verê", etc.
        const norm = (s?: string | null) =>
          (s || '')
            .normalize('NFD')
            .replace(/[\u0300-\u036f]/g, '')
            .toLowerCase()
            .replace(/&/g, ' e ')
            .replace(/[^a-z0-9]+/g, ' ')
            .trim();
        const doc = e.tipo_pessoa === 'pf' ? e.cpf : e.cnpj;
        const docDigits = (doc || '').replace(/\D/g, '');
        const qDigits = search.replace(/\D/g, '');
        // Casa por PALAVRAS (todas precisam existir) em razao social + nome fantasia + cidade.
        const haystack = [e.razao_social, e.nome_fantasia, e.cidade].map(norm).join(' ');
        const tokens = norm(search).split(' ').filter(Boolean);
        const textMatch = tokens.length > 0 && tokens.every(t => haystack.includes(t));
        const docMatch = qDigits.length > 0 && docDigits.includes(qDigits);
        return textMatch || docMatch;
      }
      return true;
    });
  }, [empresas, search, filtroStatus, filtroUF, filtroGrauRisco, filtroGrupo]);

  // Helper: get filiais for a matriz
  const getFiliais = (matrizId: string) =>
    empresas.filter(e => e.matriz_id === matrizId);

  // Helper: get grupo name
  const getGrupoNome = (grupoId: string | null) => {
    if (!grupoId) return null;
    return grupos.find(g => g.id === grupoId)?.nome || null;
  };

  // Selection
  const allSelected = filtered.length > 0 && filtered.every(e => selectedIds.has(e.id));
  const toggleAll = () => {
    if (allSelected) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(filtered.map(e => e.id)));
    }
  };
  const toggleOne = (id: string) => {
    const next = new Set(selectedIds);
    if (next.has(id)) next.delete(id); else next.add(id);
    setSelectedIds(next);
  };

  // Ações em lote
  const handleBatchToggle = (ativo: boolean) => {
    selectedIds.forEach(id => onToggleAtivo(id, ativo));
    setSelectedIds(new Set());
    toast.success(`${selectedIds.size} empresa(s) ${ativo ? 'ativada(s)' : 'inativada(s)'}`);
  };

  const handleBatchDelete = async () => {
    if (!onBatchDelete || selectedIds.size === 0) return;
    const items = filtered
      .filter(e => selectedIds.has(e.id))
      .map(e => ({ id: e.id, nome: e.razao_social || e.nome_fantasia || 'sem nome' }));
    const { confirm } = await import('@/components/ui/confirm-dialog');
    const ok = await confirm({
      title: `Excluir ${items.length} empresa(s)?`,
      description: `Esta ação é irreversível. Empresas com colaboradores ou terceiros vinculados NÃO serão excluídas (a validação de segurança do banco bloqueará).\n\nDigite "EXCLUIR" para confirmar.`,
      confirmLabel: 'Excluir selecionadas',
      cancelLabel: 'Cancelar',
      variant: 'destructive',
      requiredWord: 'EXCLUIR',
    });
    if (!ok) return;
    const result = await onBatchDelete(items);
    setSelectedIds(new Set());
    if (result.ok > 0) toast.success(`${result.ok} empresa(s) excluída(s).`);
    if (result.failed.length > 0) {
      const lista = result.failed.slice(0, 5).map(f => `• ${f.nome}: ${f.error}`).join('\n');
      const extra = result.failed.length > 5 ? `\n…e mais ${result.failed.length - 5}.` : '';
      toast.warning(`${result.failed.length} não excluída(s) (vínculos ativos):\n${lista}${extra}`, { duration: 8000 });
    }
  };

  // Export — completo (todas as etapas do cadastro), em XLSX ou PDF
  const handleExportXlsx = () => {
    if (filtered.length === 0) {
      toast.warning('Nenhuma empresa para exportar com os filtros atuais.');
      return;
    }
    try {
      exportEmpresasToXlsx(filtered, grupos, obrigacoes);
      toast.success(`${filtered.length} empresa(s) exportada(s) em Excel!`);
    } catch (err) {
      console.error(err);
      toast.error('Erro ao gerar planilha.');
    }
  };

  const handleExportPdf = () => {
    if (filtered.length === 0) {
      toast.warning('Nenhuma empresa para exportar com os filtros atuais.');
      return;
    }
    try {
      exportEmpresasToPdf(filtered, grupos, obrigacoes);
      toast.success(`${filtered.length} empresa(s) exportada(s) em PDF!`);
    } catch (err) {
      console.error(err);
      toast.error('Erro ao gerar PDF.');
    }
  };

  const grauRiscoBadge = (grau: number | null) => {
    if (!grau) return <span className="text-muted-foreground text-xs">—</span>;
    const colors: Record<number, string> = {
      1: 'bg-emerald-100 text-emerald-700',
      2: 'bg-blue-100 text-blue-700',
      3: 'bg-amber-100 text-amber-700',
      4: 'bg-red-100 text-red-700',
    };
    return <Badge className={colors[grau] || ''}>{grau}</Badge>;
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="w-8 h-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Stats Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <div className="p-2 rounded-lg bg-primary/10">
              <Building2 className="w-5 h-5 text-primary" />
            </div>
            <div>
              <p className="text-2xl font-bold">{stats.total}</p>
              <p className="text-xs text-muted-foreground">Total</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <div className="p-2 rounded-lg bg-emerald-500/10">
              <ToggleRight className="w-5 h-5 text-emerald-600" />
            </div>
            <div>
              <p className="text-2xl font-bold">{stats.ativas}</p>
              <p className="text-xs text-muted-foreground">Ativas</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <div className="p-2 rounded-lg bg-muted">
              <ToggleLeft className="w-5 h-5 text-muted-foreground" />
            </div>
            <div>
              <p className="text-2xl font-bold">{stats.inativas}</p>
              <p className="text-xs text-muted-foreground">Inativas</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <div className="p-2 rounded-lg bg-amber-500/10">
              <AlertTriangle className="w-5 h-5 text-amber-600" />
            </div>
            <div>
              <p className="text-2xl font-bold">{stats.grauAlto}</p>
              <p className="text-xs text-muted-foreground">GR ≥ 3</p>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Toolbar */}
      <div className="flex flex-col md:flex-row gap-3 items-start md:items-center justify-between">
        <div className="flex flex-wrap gap-2 items-center flex-1">
          <div className="relative w-64">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <Input
              placeholder="Buscar por razão social, nome fantasia ou CNPJ/CPF..."
              value={search}
              onChange={e => setSearch(e.target.value)}
              className="pl-9"
            />
          </div>
          <Select value={filtroStatus} onValueChange={setFiltroStatus}>
            <SelectTrigger className="w-[130px]">
              <SelectValue placeholder="Status" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="todos">Todos</SelectItem>
              <SelectItem value="ativas">Ativas</SelectItem>
              <SelectItem value="inativas">Inativas</SelectItem>
            </SelectContent>
          </Select>
          <Select value={filtroUF} onValueChange={setFiltroUF}>
            <SelectTrigger className="w-[100px]">
              <SelectValue placeholder="UF" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="todos">Todos UF</SelectItem>
              {ufs.map(uf => (
                <SelectItem key={uf} value={uf}>{uf}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select value={filtroGrauRisco} onValueChange={setFiltroGrauRisco}>
            <SelectTrigger className="w-[130px]">
              <SelectValue placeholder="Grau Risco" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="todos">Todos GR</SelectItem>
              <SelectItem value="1">GR 1</SelectItem>
              <SelectItem value="2">GR 2</SelectItem>
              <SelectItem value="3">GR 3</SelectItem>
              <SelectItem value="4">GR 4</SelectItem>
            </SelectContent>
          </Select>
          {grupos.length > 0 && (
            <div className="w-[180px]">
              <Select value={filtroGrupo} onValueChange={setFiltroGrupo}>
                <SelectTrigger>
                  <SelectValue placeholder="Grupo" />
                </SelectTrigger>
                <SelectContent className="max-h-[300px]">
                  <div className="p-2 border-b sticky top-0 bg-popover z-10">
                    <Input
                      placeholder="Pesquisar grupo..."
                      className="h-8 text-xs"
                      onClick={(e) => e.stopPropagation()}
                      onChange={(e) => {
                        // Hack para filtrar as opções manualmente se o shadcn/ui select não suportar busca nativa
                        const search = e.target.value.toLowerCase();
                        const items = document.querySelectorAll('[role="option"]');
                        items.forEach((item) => {
                          const text = item.textContent?.toLowerCase() || '';
                          const isSpecial = text.includes('todos grupos') || text.includes('sem grupo');
                          if (isSpecial || text.includes(search)) {
                            (item as HTMLElement).style.display = 'flex';
                          } else {
                            (item as HTMLElement).style.display = 'none';
                          }
                        });
                      }}
                    />
                  </div>
                  <SelectItem value="todos">Todos Grupos</SelectItem>
                  <SelectItem value="_sem_grupo">Sem grupo</SelectItem>
                  {grupos
                    .filter(g => g.ativo)
                    .sort((a, b) => a.nome.localeCompare(b.nome))
                    .map(g => (
                      <SelectItem key={g.id} value={g.id}>{g.nome}</SelectItem>
                    ))}
                </SelectContent>
              </Select>
            </div>
          )}
        </div>
        <div className="flex gap-2">
          <AcaoProtegida modulo="configuracoes" acao="exportar">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" size="sm">
                <Download className="w-4 h-4 mr-1" />
                Exportar
                <ChevronDown className="w-3 h-3 ml-1" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-56 bg-popover">
              <DropdownMenuItem onClick={handleExportXlsx} className="cursor-pointer">
                <FileSpreadsheet className="w-4 h-4 mr-2 text-emerald-600" />
                <div className="flex flex-col">
                  <span className="font-medium">Exportar como Planilha</span>
                  <span className="text-xs text-muted-foreground">.xlsx — todos os dados</span>
                </div>
              </DropdownMenuItem>
              <DropdownMenuItem onClick={handleExportPdf} className="cursor-pointer">
                <FileText className="w-4 h-4 mr-2 text-red-600" />
                <div className="flex flex-col">
                  <span className="font-medium">Exportar como PDF</span>
                  <span className="text-xs text-muted-foreground">Relatório completo formatado</span>
                </div>
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
          </AcaoProtegida>
          <Button variant="outline" size="sm" onClick={() => setImportOpen(true)}>
            <Upload className="w-4 h-4 mr-1" />
            Importar
          </Button>
          <Button size="sm" onClick={onNew} data-testid="btn-nova-empresa">
            <Plus className="w-4 h-4 mr-1" />
            Nova Empresa
          </Button>
        </div>
      </div>

      <Dialog open={importOpen} onOpenChange={setImportOpen}>
        <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Importar Empresas</DialogTitle>
            <DialogDescription>Importe empresas via Excel/CSV ou baixe o modelo</DialogDescription>
          </DialogHeader>
          <EmpresaImportExport />
        </DialogContent>
      </Dialog>

      {/* Batch actions */}
      {selectedIds.size > 0 && (
        <div className="flex items-center gap-3 p-3 bg-muted/50 rounded-lg border">
          <span className="text-sm font-medium">{selectedIds.size} selecionada(s)</span>
          <Button variant="outline" size="sm" onClick={() => handleBatchToggle(true)} className="text-success hover:text-success hover:bg-success/10 border-success/30">
            <ToggleRight className="w-4 h-4 mr-1" />
            Ativar
          </Button>
          <Button variant="outline" size="sm" onClick={() => handleBatchToggle(false)} className="text-destructive hover:text-destructive hover:bg-destructive/10 border-destructive/30">
            <ToggleLeft className="w-4 h-4 mr-1" />
            Inativar
          </Button>
          {onBatchDelete && (
            <Button variant="outline" size="sm" onClick={handleBatchDelete} className="text-destructive hover:text-destructive hover:bg-destructive/10 border-destructive/30">
              <Trash2 className="w-4 h-4 mr-1" />
              Excluir
            </Button>
          )}
        </div>
      )}

      {/* Table */}
      <Card>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-10">
                <Checkbox checked={allSelected} onCheckedChange={toggleAll} />
              </TableHead>
              <TableHead>Razão Social</TableHead>
              <TableHead>CNPJ/CPF</TableHead>
              <TableHead>Tipo</TableHead>
              <TableHead>Grupo</TableHead>
              <TableHead>CNAE</TableHead>
              <TableHead className="text-center">Colaboradores</TableHead>
              <TableHead className="text-center">GR</TableHead>
              <TableHead>Status</TableHead>
              <TableHead className="text-right">Ações</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {filtered.length === 0 ? (
              <TableRow>
                <TableCell colSpan={9} className="text-center py-10 text-muted-foreground">
                  {empresas.length === 0 ? 'Nenhuma empresa cadastrada' : 'Nenhuma empresa encontrada com os filtros atuais'}
                </TableCell>
              </TableRow>
            ) : (
              filtered.map(emp => (
                <TableRow key={emp.id} className={!emp.ativo ? 'opacity-60' : ''}>
                  <TableCell>
                    <Checkbox
                      checked={selectedIds.has(emp.id)}
                      onCheckedChange={() => toggleOne(emp.id)}
                    />
                  </TableCell>
                  <TableCell
                    className="cursor-pointer group"
                    onClick={() => onEdit(emp.id)}
                    title="Clique para editar"
                  >
                    <div>
                      <p className="font-medium text-sm text-primary group-hover:underline">{emp.razao_social || '(sem razão social)'}</p>
                      {emp.nome_fantasia && (
                        <p className="text-xs text-muted-foreground">{emp.nome_fantasia}</p>
                      )}
                      {emp.cidade && emp.estado && (
                        <p className="text-xs text-muted-foreground">{emp.cidade}/{emp.estado}</p>
                      )}
                      {/* Show filiais count for matrizes */}
                      {emp.tipo_unidade === 'matriz' && (() => {
                        const filiais = getFiliais(emp.id);
                        return filiais.length > 0 ? (
                          <p className="text-xs text-primary mt-0.5">
                            <GitBranch className="w-3 h-3 inline mr-0.5" />
                            {filiais.length} filial(is)
                          </p>
                        ) : null;
                      })()}
                    </div>
                  </TableCell>
                  <TableCell className="text-sm font-mono">
                    {emp.tipo_pessoa === 'pf' 
                      ? (emp.cpf ? formatCpf(emp.cpf) : '—') 
                      : (emp.cnpj ? formatCnpj(emp.cnpj) : '—')}
                  </TableCell>
                  <TableCell>
                    <Badge variant={emp.tipo_unidade === 'matriz' ? 'default' : 'outline'} className="text-xs">
                      {emp.tipo_unidade === 'matriz' ? 'Matriz' : 'Filial'}
                    </Badge>
                    {emp.tipo_unidade === 'filial' && emp.matriz_id && (() => {
                      const matriz = empresas.find(e => e.id === emp.matriz_id);
                      return matriz ? (
                        <p className="text-xs text-muted-foreground mt-0.5 truncate max-w-[120px]">
                          → {matriz.razao_social || matriz.cnpj}
                        </p>
                      ) : null;
                    })()}
                  </TableCell>
                  <TableCell>
                    {(() => {
                      const nome = getGrupoNome(emp.grupo_economico_id);
                      return nome ? (
                        <Badge variant="outline" className="text-xs">
                          <Layers className="w-3 h-3 mr-1" />
                          {nome}
                        </Badge>
                      ) : <span className="text-xs text-muted-foreground">—</span>;
                    })()}
                  </TableCell>
                  <TableCell>
                    <div>
                      <p className="text-sm">{emp.cnae_principal || '—'}</p>
                      {emp.cnae_descricao && (
                        <p className="text-xs text-muted-foreground truncate max-w-[200px]">{emp.cnae_descricao}</p>
                      )}
                    </div>
                  </TableCell>
                  <TableCell className="text-center">
                    <div className="flex flex-col items-center gap-1">
                      <Badge variant="secondary" className="gap-1 px-2">
                        <Users className="w-3 h-3 text-muted-foreground" />
                        {(counts as any)[emp.id] || 0}
                      </Badge>
                      {/* CLT art. 74, §2º: estabelecimento com mais de 20
                          empregados é OBRIGADO a manter controle de jornada.
                          Quem marca isso é a rotina do banco (que conta os
                          vínculos ativos); aqui só se mostra o resultado. */}
                      {(emp as any).controle_ponto_obrigatorio && (
                        <Badge
                          variant="outline"
                          className="border-amber-400 text-amber-800 text-[10px] gap-1"
                          title="Mais de 20 empregados: o controle de jornada é obrigatório neste estabelecimento (CLT art. 74, §2º)."
                        >
                          <Clock className="w-3 h-3" /> ponto obrigatório
                        </Badge>
                      )}
                    </div>
                  </TableCell>
                  <TableCell className="text-center">{grauRiscoBadge(emp.grau_risco)}</TableCell>
                  <TableCell>
                    <Badge className={emp.ativo ? "bg-success/10 text-success border-success/30" : "bg-destructive/10 text-destructive border-destructive/30"}>
                      {emp.ativo ? 'Ativa' : 'Inativa'}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-right">
                    <div className="flex items-center justify-end gap-1">
                      <Button variant="ghost" size="icon" onClick={() => onEdit(emp.id)} title="Editar">
                        <Edit className="w-4 h-4" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon"
                        onClick={() => onToggleAtivo(emp.id, !emp.ativo)}
                        title={emp.ativo ? 'Desativar Empresa' : 'Ativar Empresa'}
                        className={emp.ativo 
                          ? "text-success bg-success/10 hover:text-destructive hover:bg-destructive/10" 
                          : "text-destructive bg-destructive/10 hover:text-success hover:bg-success/10"
                        }
                      >
                        {emp.ativo ? (
                          <ToggleRight className="w-5 h-5" />
                        ) : (
                          <ToggleLeft className="w-5 h-5" />
                        )}
                      </Button>
                      {podeExcluir && onDelete && (
                        <Button
                          variant="ghost"
                          size="icon"
                          onClick={() => onDelete(emp.id, emp.razao_social || emp.nome_fantasia || 'sem nome')}
                          title="Excluir empresa (apenas Administrador Master, sem colaboradores/prestadores)"
                          className="text-destructive hover:bg-destructive/10"
                        >
                          <Trash2 className="w-4 h-4" />
                        </Button>
                      )}
                    </div>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </Card>
    </div>
  );
}
