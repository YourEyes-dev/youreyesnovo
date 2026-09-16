import { useState, useMemo } from "react";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command";
import { Check, ChevronsUpDown } from "lucide-react";
import { cn } from "@/lib/utils";
import { motion } from "framer-motion";
import {
  Settings,
  Package,
  Warehouse,
  Plus,
  Edit,
  ToggleLeft,
  ToggleRight,
  MapPin,
  User,
  Building2,
  MoreHorizontal,
  Search,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Separator } from "@/components/ui/separator";
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
  DialogFooter,
} from "@/components/ui/dialog";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
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
import { useEpiConfig } from "@/hooks/useEpiConfig";
import { useEpis } from "@/hooks/useEpis";
import { CATEGORIAS_EPI } from "@/types/epi";
import { useEpiLocais, LOCAL_TIPO_LABELS, type LocalEstoqueTipo } from "@/hooks/useEpiLocais";
import { useFiliais } from "@/hooks/useCadastros";
import { useColaboradores } from "@/hooks/useColaboradores";

interface LocalFormData {
  nome: string;
  tipo: string;
  filial_id: string | null;
  responsavel_nome: string;
  observacoes: string;
}

const emptyForm: LocalFormData = {
  nome: "",
  tipo: "almoxarifado_central",
  filial_id: null,
  responsavel_nome: "",
  observacoes: "",
};

function ResponsavelCombobox({ colaboradores, value, onChange }: {
  colaboradores: { id: string; nome_completo: string; cargo: string }[];
  value: string;
  onChange: (val: string) => void;
}) {
  const [open, setOpen] = useState(false);

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button variant="outline" role="combobox" aria-expanded={open} className="w-full justify-between font-normal">
          {value || "Buscar responsável..."}
          <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-[--radix-popover-trigger-width] p-0" align="start">
        <Command>
          <CommandInput placeholder="Pesquisar colaborador..." />
          <CommandList>
            <CommandEmpty>Nenhum colaborador encontrado.</CommandEmpty>
            <CommandGroup>
              <CommandItem value="__none__" onSelect={() => { onChange(""); setOpen(false); }}>
                <Check className={cn("mr-2 h-4 w-4", !value ? "opacity-100" : "opacity-0")} />
                Nenhum
              </CommandItem>
              {colaboradores.map((c) => (
                <CommandItem key={c.id} value={c.nome_completo} onSelect={() => { onChange(c.nome_completo); setOpen(false); }}>
                  <Check className={cn("mr-2 h-4 w-4", value === c.nome_completo ? "opacity-100" : "opacity-0")} />
                  {c.nome_completo} {c.cargo ? `– ${c.cargo}` : ""}
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}

// Quais categorias exigem o número do CA no cadastro de EPI.
//
// Existia uma regra fixa: TODO item precisava de CA. Está certo para capacete,
// luva e bota — é a NR-06 —, e está errado para uniforme, camiseta e crachá,
// que não têm Certificado de Aprovação e mesmo assim ficavam impedidos de
// entrar no sistema. Em vez de o sistema escolher pelos clientes, cada um
// marca aqui as suas. Categoria nunca marcada continua exigindo.
function CategoriasExigemCaCard() {
  const { tipos, categorias, categoriasLoading, definirExigeCa, definindoExigeCa } = useEpis();

  const linhas = useMemo(() => {
    const daTabela = new Map(categorias.map((c) => [c.nome, c.exige_ca]));
    const dosTipos = tipos
      .filter((t) => t.is_active !== false && t.categoria)
      .map((t) => t.categoria as string);
    // A lista oferecida no cadastro é a união das três fontes — a marcação
    // precisa cobrir exatamente as mesmas opções, senão sobra categoria sem
    // como ser marcada.
    const nomes = [...new Set([...CATEGORIAS_EPI, ...dosTipos, ...categorias.map((c) => c.nome)])].sort();
    return nomes.map((nome) => ({ nome, exigeCa: daTabela.get(nome) ?? true }));
  }, [tipos, categorias]);

  const isentas = linhas.filter((l) => !l.exigeCa).length;

  return (
    <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.05 }}>
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-lg">
            <Package className="w-5 h-5 text-primary" />
            Exigência de CA por Categoria
          </CardTitle>
          <CardDescription>
            O Certificado de Aprovação (CA) é obrigatório para EPI de verdade — capacete, luva, bota.
            Desmarque as categorias que não têm CA, como uniformes e crachás: elas passam a ser
            cadastradas sem número e sem data de validade.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {categoriasLoading ? (
            <p className="text-sm text-muted-foreground">Carregando categorias...</p>
          ) : (
            <>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
                {linhas.map((linha) => (
                  <div
                    key={linha.nome}
                    className="flex items-center justify-between gap-4 p-3 rounded-lg border bg-muted/20"
                  >
                    <div className="min-w-0">
                      <p className="text-sm font-medium truncate">{linha.nome}</p>
                      <p className="text-xs text-muted-foreground">
                        {linha.exigeCa ? "Exige CA e validade" : "Sem CA (uniforme, vestuário)"}
                      </p>
                    </div>
                    <Switch
                      checked={linha.exigeCa}
                      disabled={definindoExigeCa}
                      onCheckedChange={(checked) =>
                        definirExigeCa({ nome: linha.nome, exige_ca: checked })
                      }
                    />
                  </div>
                ))}
              </div>
              <p className="text-xs text-muted-foreground mt-3">
                {isentas === 0
                  ? "Todas as categorias exigem CA."
                  : `${isentas} categoria(s) isenta(s) de CA.`}
              </p>
            </>
          )}
        </CardContent>
      </Card>
    </motion.div>
  );
}

export function EpiConfiguracaoTab() {
  const { usarControleEstoque, toggleControleEstoque, toggling, configLoading } = useEpiConfig();
  const { locais, locaisLoading, criarLocal, criandoLocal, atualizarLocal, atualizandoLocal, toggleAtivoLocal } = useEpiLocais();
  const { filiais } = useFiliais();
  const { colaboradores } = useColaboradores();

  const [showLocalForm, setShowLocalForm] = useState(false);
  const [editingLocal, setEditingLocal] = useState<string | null>(null);
  const [formData, setFormData] = useState<LocalFormData>(emptyForm);
  const [search, setSearch] = useState("");
  const [showInativos, setShowInativos] = useState(false);
  const [confirmToggle, setConfirmToggle] = useState<boolean | null>(null);

  const locaisFiltrados = locais.filter((l) => {
    if (!showInativos && !l.ativo) return false;
    if (search) {
      const s = search.toLowerCase();
      return (
        l.nome.toLowerCase().includes(s) ||
        l.responsavel_nome?.toLowerCase().includes(s) ||
        l.filial?.nome?.toLowerCase().includes(s)
      );
    }
    return true;
  });

  const handleOpenForm = (localId?: string) => {
    if (localId) {
      const local = locais.find((l) => l.id === localId);
      if (local) {
        setFormData({
          nome: local.nome,
          tipo: local.tipo || "almoxarifado_central",
          filial_id: local.filial_id,
          responsavel_nome: local.responsavel_nome || "",
          observacoes: local.observacoes || "",
        });
        setEditingLocal(localId);
      }
    } else {
      setFormData(emptyForm);
      setEditingLocal(null);
    }
    setShowLocalForm(true);
  };

  const handleSaveLocal = async () => {
    if (!formData.nome.trim()) return;

    if (editingLocal) {
      await atualizarLocal({
        id: editingLocal,
        nome: formData.nome,
        tipo: formData.tipo,
        filial_id: formData.filial_id || null,
        responsavel_nome: formData.responsavel_nome || null,
        observacoes: formData.observacoes || null,
      });
    } else {
      await criarLocal({
        nome: formData.nome,
        tipo: formData.tipo,
        filial_id: formData.filial_id || null,
        responsavel_nome: formData.responsavel_nome || null,
        observacoes: formData.observacoes || undefined,
      });
    }
    setShowLocalForm(false);
    setEditingLocal(null);
    setFormData(emptyForm);
  };

  const handleConfirmToggle = async () => {
    if (confirmToggle !== null) {
      await toggleControleEstoque(confirmToggle);
      setConfirmToggle(null);
    }
  };

  const locaisAtivos = locais.filter((l) => l.ativo).length;
  const locaisInativos = locais.filter((l) => !l.ativo).length;

  return (
    <div className="space-y-6">
      {/* RF-EPI-EST-01: Config de Controle de Estoque */}
      <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }}>
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-lg">
              <Settings className="w-5 h-5 text-primary" />
              Configuração Geral do Módulo
            </CardTitle>
            <CardDescription>
              Defina como o módulo de EPI vai funcionar na sua empresa
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="flex items-start justify-between gap-6 p-4 rounded-lg border bg-muted/30">
              <div className="space-y-1.5 flex-1">
                <Label className="text-base font-medium">
                  Usar controle de estoque de EPI?
                </Label>
                <p className="text-sm text-muted-foreground">
                  {usarControleEstoque ? (
                    <>
                      <strong className="text-green-600">✅ Ativado:</strong> Entregas de EPI baixam estoque automaticamente.
                      É necessário manter saldo via compras e movimentações.
                      Alertas de estoque baixo estarão ativos.
                    </>
                  ) : (
                    <>
                      <strong className="text-orange-600">⛔ Desativado:</strong> O fluxo de entrega continua (registro + termo + facial),
                      mas sem exigência de saldo, sem alertas de estoque e sem dashboards de saldo.
                    </>
                  )}
                </p>
              </div>
              <div className="flex items-center gap-3 pt-1">
                <span className="text-sm text-muted-foreground">
                  {usarControleEstoque ? "Ativado" : "Desativado"}
                </span>
                <Switch
                  checked={usarControleEstoque}
                  onCheckedChange={(checked) => setConfirmToggle(checked)}
                  disabled={toggling || configLoading}
                />
              </div>
            </div>
          </CardContent>
        </Card>
      </motion.div>

      <CategoriasExigemCaCard />

      {/* RF-EPI-EST-02: Locais de Estoque */}
      <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }}>
        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <div>
                <CardTitle className="flex items-center gap-2 text-lg">
                  <Warehouse className="w-5 h-5 text-primary" />
                  Locais de Estoque
                </CardTitle>
                <CardDescription>
                  Cadastre almoxarifados, estoques de obra e locais de armazenamento de EPIs
                </CardDescription>
              </div>
              <Button onClick={() => handleOpenForm()}>
                <Plus className="w-4 h-4 mr-2" />
                Novo Local
              </Button>
            </div>
          </CardHeader>
          <CardContent>
            {/* Stats */}
            <div className="grid grid-cols-3 gap-4 mb-4">
              <div className="p-3 rounded-lg border bg-card text-center">
                <p className="text-2xl font-bold">{locais.length}</p>
                <p className="text-xs text-muted-foreground">Total</p>
              </div>
              <div className="p-3 rounded-lg border bg-card text-center">
                <p className="text-2xl font-bold text-green-600">{locaisAtivos}</p>
                <p className="text-xs text-muted-foreground">Ativos</p>
              </div>
              <div className="p-3 rounded-lg border bg-card text-center">
                <p className="text-2xl font-bold text-muted-foreground">{locaisInativos}</p>
                <p className="text-xs text-muted-foreground">Inativos</p>
              </div>
            </div>

            {/* Filters */}
            <div className="flex items-center gap-3 mb-4">
              <div className="relative flex-1 max-w-sm">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                <Input
                  placeholder="Buscar local..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  className="pl-10"
                />
              </div>
              <div className="flex items-center gap-2">
                <Switch
                  id="show-inativos"
                  checked={showInativos}
                  onCheckedChange={setShowInativos}
                />
                <Label htmlFor="show-inativos" className="text-sm cursor-pointer">
                  Mostrar inativos
                </Label>
              </div>
            </div>

            {/* Table */}
            {locaisLoading ? (
              <div className="flex items-center justify-center py-12">
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
              </div>
            ) : locaisFiltrados.length === 0 ? (
              <div className="text-center py-12 text-muted-foreground">
                <Warehouse className="w-12 h-12 mx-auto mb-4 opacity-50" />
                <p className="mb-2">Nenhum local de estoque cadastrado</p>
                <p className="text-sm">Crie locais para organizar onde seus EPIs ficam armazenados.</p>
                <Button variant="outline" className="mt-4" onClick={() => handleOpenForm()}>
                  <Plus className="w-4 h-4 mr-2" />
                  Criar primeiro local
                </Button>
              </div>
            ) : (
              <div className="border rounded-lg overflow-hidden">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Nome</TableHead>
                      <TableHead>Tipo</TableHead>
                      <TableHead>Estabelecimento</TableHead>
                      <TableHead>Responsável</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead className="w-[50px]" />
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {locaisFiltrados.map((local) => (
                      <TableRow key={local.id} className={!local.ativo ? "opacity-50" : ""}>
                        <TableCell>
                          <div className="flex items-center gap-2">
                            <MapPin className="w-4 h-4 text-muted-foreground" />
                            <span className="font-medium">{local.nome}</span>
                          </div>
                        </TableCell>
                        <TableCell>
                          <Badge variant="outline" className="text-xs">
                            {LOCAL_TIPO_LABELS[(local.tipo || "almoxarifado_central") as LocalEstoqueTipo] || local.tipo}
                          </Badge>
                        </TableCell>
                        <TableCell>
                          {local.filial?.nome ? (
                            <div className="flex items-center gap-1 text-sm">
                              <Building2 className="w-3.5 h-3.5 text-muted-foreground" />
                              {local.filial.nome}
                            </div>
                          ) : (
                            <span className="text-muted-foreground">—</span>
                          )}
                        </TableCell>
                        <TableCell>
                          {local.responsavel_nome ? (
                            <div className="flex items-center gap-1 text-sm">
                              <User className="w-3.5 h-3.5 text-muted-foreground" />
                              {local.responsavel_nome}
                            </div>
                          ) : (
                            <span className="text-muted-foreground">—</span>
                          )}
                        </TableCell>
                        <TableCell>
                          <Badge
                            variant={local.ativo ? "default" : "secondary"}
                            className="text-xs"
                          >
                            {local.ativo ? "Ativo" : "Inativo"}
                          </Badge>
                        </TableCell>
                        <TableCell>
                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <Button variant="ghost" size="icon">
                                <MoreHorizontal className="w-4 h-4" />
                              </Button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end">
                              <DropdownMenuItem onClick={() => handleOpenForm(local.id)}>
                                <Edit className="w-4 h-4 mr-2" />
                                Editar
                              </DropdownMenuItem>
                              <DropdownMenuItem
                                onClick={async () => {
                                  await toggleAtivoLocal({ id: local.id, ativo: !local.ativo });
                                }}
                              >
                                {local.ativo ? (
                                  <>
                                    <ToggleLeft className="w-4 h-4 mr-2" />
                                    Inativar
                                  </>
                                ) : (
                                  <>
                                    <ToggleRight className="w-4 h-4 mr-2" />
                                    Reativar
                                  </>
                                )}
                              </DropdownMenuItem>
                            </DropdownMenuContent>
                          </DropdownMenu>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            )}
          </CardContent>
        </Card>
      </motion.div>

      {/* Form Dialog */}
      <Dialog open={showLocalForm} onOpenChange={setShowLocalForm}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {editingLocal ? "Editar Local de Estoque" : "Novo Local de Estoque"}
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-2">
              <Label>Nome do Local *</Label>
              <Input
                placeholder="Ex: Almoxarifado Central, Estoque Obra X"
                value={formData.nome}
                onChange={(e) => setFormData({ ...formData, nome: e.target.value })}
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Tipo</Label>
                <Select
                  value={formData.tipo}
                  onValueChange={(val) => setFormData({ ...formData, tipo: val })}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {Object.entries(LOCAL_TIPO_LABELS).map(([key, label]) => (
                      <SelectItem key={key} value={key}>
                        {label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label>Estabelecimento / Obra</Label>
                <Select
                  value={formData.filial_id || "__none__"}
                  onValueChange={(val) =>
                    setFormData({ ...formData, filial_id: val === "__none__" ? null : val })
                  }
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Selecionar filial" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="__none__">Nenhuma (Matriz)</SelectItem>
                    {filiais.map((f: any) => (
                      <SelectItem key={f.id} value={f.id}>
                        {f.nome}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div className="space-y-2">
              <Label>Responsável pelo Local</Label>
              <ResponsavelCombobox
                colaboradores={colaboradores}
                value={formData.responsavel_nome}
                onChange={(val) => setFormData({ ...formData, responsavel_nome: val })}
              />
            </div>

            <div className="space-y-2">
              <Label>Observações</Label>
              <Textarea
                placeholder="Detalhes adicionais sobre este local..."
                value={formData.observacoes}
                onChange={(e) => setFormData({ ...formData, observacoes: e.target.value })}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowLocalForm(false)}>
              Cancelar
            </Button>
            <Button
              onClick={handleSaveLocal}
              disabled={!formData.nome.trim() || criandoLocal || atualizandoLocal}
            >
              {criandoLocal || atualizandoLocal ? "Salvando..." : editingLocal ? "Salvar" : "Criar"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Confirm toggle dialog */}
      <AlertDialog open={confirmToggle !== null} onOpenChange={() => setConfirmToggle(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {confirmToggle ? "Ativar controle de estoque?" : "Desativar controle de estoque?"}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {confirmToggle ? (
                <>
                  Ao ativar, todas as entregas de EPI passarão a <strong>baixar estoque automaticamente</strong>.
                  Será necessário manter o saldo atualizado via importação de compras e movimentações.
                </>
              ) : (
                <>
                  Ao desativar, o fluxo de entrega continuará funcionando (registro, termo, facial),
                  porém <strong>sem exigir saldo</strong>, sem alertas de estoque baixo e sem dashboards de saldo.
                  Ideal para empresas que estão começando.
                </>
              )}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleConfirmToggle} disabled={toggling}>
              {toggling ? "Salvando..." : "Confirmar"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
