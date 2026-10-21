import { useState, useCallback } from "react";
import { motion } from "framer-motion";
import {
  DollarSign,
  Plus,
  Users,
  TrendingUp,
  AlertTriangle,
  CheckCircle,
  Clock,
  Heart,
  Utensils,
  Bus,
  Shield,
  MoreHorizontal,
  FileText,
  ChevronsUpDown,
  Check,
  Package,
  Pencil,
  Trash2,
  FileCode,
  Sun,
  Gift,
  PiggyBank,
  Calculator,
  Settings2,
  Scale,
  Bell,
  TableProperties,
} from "lucide-react";
import { FolhaCCTTab } from "@/components/financeiro/FolhaCCTTab";
import { FolhaESocialTab } from "@/components/financeiro/FolhaESocialTab";
import { FolhaAlertasTab } from "@/components/financeiro/FolhaAlertasTab";
import TabelasFiscaisTab from "@/components/financeiro/TabelasFiscaisTab";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Input } from "@/components/ui/input";
import { CompetenciaInput } from "@/components/ui/competencia-input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command";
import { Switch } from "@/components/ui/switch";
import { cn } from "@/lib/utils";
import { toast } from "sonner";
import {
  useFinanceiro,
  CATEGORIA_BENEFICIO,
  STATUS_FOLHA,
  type BeneficioTipo,
  type FolhaPeriodo,
} from "@/hooks/useFinanceiro";
import { useColaboradores } from "@/hooks/useColaboradores";
import { HoleriteDetail } from "@/components/financeiro/HoleriteDetail";
import { RubricasTab } from "@/components/financeiro/RubricasTab";
import { FeriasTab } from "@/components/financeiro/FeriasTab";
import { DecimoTerceiroTab } from "@/components/financeiro/DecimoTerceiroTab";
import { RescisaoTab } from "@/components/financeiro/RescisaoTab";
import { ProvisoesTab } from "@/components/financeiro/ProvisoesTab";
import { TabelasLegaisTab } from "@/components/financeiro/TabelasLegaisTab";
import type { FolhaItem } from "@/hooks/useFinanceiro";
import { formatDateBR } from "@/lib/dataLocal";

// ==========================================
// SUB-COMPONENTS
// ==========================================

// -- Benefícios Tab --
export const BeneficiosTab = () => {
  const {
    useBeneficiosTipos,
    useBeneficiosColaboradores,
    criarBeneficioTipo,
    criandoBeneficioTipo,
    atualizarBeneficioTipo,
    vincularBeneficio,
    vinculandoBeneficio,
    atualizarBeneficioColab,
  } = useFinanceiro();

  const { data: tipos = [], isLoading: loadingTipos } = useBeneficiosTipos();
  const { data: vinculos = [], isLoading: loadingVinculos } = useBeneficiosColaboradores();
  const { colaboradores } = useColaboradores();

  const [showTipoModal, setShowTipoModal] = useState(false);
  const [showVinculoModal, setShowVinculoModal] = useState(false);
  const [comboOpen, setComboOpen] = useState(false);
  const [editingTipoId, setEditingTipoId] = useState<string | null>(null);

  const emptyTipoForm = {
    nome: "",
    categoria: "alimentacao",
    descricao: "",
    valor_padrao: 0,
    tipo_desconto: "fixo",
    valor_desconto_fixo: 0,
    percentual_desconto: 0,
  };

  const [tipoForm, setTipoForm] = useState(emptyTipoForm);

  const [vinculoForm, setVinculoForm] = useState({
    beneficio_tipo_id: "",
    colaborador_id: "",
    colaborador_nome: "",
    colaborador_cpf: "",
    valor: 0,
    valor_desconto: 0,
    data_inicio: new Date().toISOString().split("T")[0],
  });

  const handleCriarTipo = async () => {
    if (!tipoForm.nome) return toast.error("Informe o nome do benefício");
    if (editingTipoId) {
      await atualizarBeneficioTipo({ id: editingTipoId, ...tipoForm });
    } else {
      await criarBeneficioTipo(tipoForm);
    }
    setShowTipoModal(false);
    setEditingTipoId(null);
    setTipoForm(emptyTipoForm);
  };

  const handleEditarTipo = (tipo: BeneficioTipo) => {
    setEditingTipoId(tipo.id);
    setTipoForm({
      nome: tipo.nome,
      categoria: tipo.categoria,
      descricao: tipo.descricao || "",
      valor_padrao: tipo.valor_padrao ?? 0,
      tipo_desconto: tipo.tipo_desconto || "fixo",
      valor_desconto_fixo: tipo.valor_desconto_fixo ?? 0,
      percentual_desconto: tipo.percentual_desconto ?? 0,
    });
    setShowTipoModal(true);
  };

  const handleToggleAtivo = async (tipo: BeneficioTipo) => {
    await atualizarBeneficioTipo({ id: tipo.id, ativo: !tipo.ativo });
  };

  const handleVincular = async () => {
    if (!vinculoForm.beneficio_tipo_id || !vinculoForm.colaborador_nome)
      return toast.error("Selecione o benefício e o colaborador");
    await vincularBeneficio(vinculoForm);
    setShowVinculoModal(false);
    setVinculoForm({ beneficio_tipo_id: "", colaborador_id: "", colaborador_nome: "", colaborador_cpf: "", valor: 0, valor_desconto: 0, data_inicio: new Date().toISOString().split("T")[0] });
  };

  const categoriaIcon: Record<string, React.ElementType> = {
    alimentacao: Utensils,
    saude: Heart,
    transporte: Bus,
    seguro: Shield,
    outros: Package,
  };

  const ativos = vinculos.filter((v) => v.status === "ativo");
  const totalMensal = ativos.reduce((sum, v) => sum + (v.valor || 0), 0);
  const totalDescontos = ativos.reduce((sum, v) => sum + (v.valor_desconto || 0), 0);

  return (
    <div className="space-y-6">
      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <div className="p-2 rounded-lg bg-primary/10"><Package className="w-5 h-5 text-primary" /></div>
            <div><p className="text-2xl font-bold">{tipos.filter(t => t.ativo).length}</p><p className="text-xs text-muted-foreground">Tipos Cadastrados</p></div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <div className="p-2 rounded-lg bg-success/10"><Users className="w-5 h-5 text-success" /></div>
            <div><p className="text-2xl font-bold">{ativos.length}</p><p className="text-xs text-muted-foreground">Vínculos Ativos</p></div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <div className="p-2 rounded-lg bg-info/10"><DollarSign className="w-5 h-5 text-info" /></div>
            <div><p className="text-2xl font-bold">R$ {totalMensal.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</p><p className="text-xs text-muted-foreground">Custo Mensal</p></div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <div className="p-2 rounded-lg bg-warning/10"><TrendingUp className="w-5 h-5 text-warning" /></div>
            <div><p className="text-2xl font-bold">R$ {totalDescontos.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</p><p className="text-xs text-muted-foreground">Descontos Totais</p></div>
          </CardContent>
        </Card>
      </div>

      {/* Actions */}
      <div className="flex gap-2">
        <Button className="gradient-primary shadow-glow" onClick={() => setShowTipoModal(true)}>
          <Plus className="w-4 h-4 mr-2" />Novo Benefício
        </Button>
        <Button variant="outline" onClick={() => setShowVinculoModal(true)}>
          <Users className="w-4 h-4 mr-2" />Vincular Colaborador
        </Button>
      </div>

      {/* Tipos de Benefícios */}
      <div>
        <h3 className="text-lg font-semibold mb-3">Tipos de Benefícios</h3>
        {loadingTipos ? (
          <p className="text-muted-foreground text-sm">Carregando...</p>
        ) : tipos.length === 0 ? (
          <Card><CardContent className="p-8 text-center text-muted-foreground">Nenhum benefício cadastrado. Clique em "Novo Benefício" para começar.</CardContent></Card>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
            {tipos.map((tipo, i) => {
              const cat = CATEGORIA_BENEFICIO[tipo.categoria] || CATEGORIA_BENEFICIO.outros;
              const Icon = categoriaIcon[tipo.categoria] || Package;
              const vinculosDoTipo = vinculos.filter(v => v.beneficio_tipo_id === tipo.id && v.status === "ativo");
              return (
                <motion.div key={tipo.id} initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.05 }}>
                  <Card className="hover:border-primary/30 transition-colors">
                    <CardContent className="p-5">
                      <div className="flex items-start justify-between mb-3">
                        <div className="flex items-center gap-3">
                          <div className="p-2 rounded-lg bg-primary/10"><Icon className="w-5 h-5 text-primary" /></div>
                          <div>
                            <h4 className="font-semibold">{tipo.nome}</h4>
                            <Badge className={cn("text-xs mt-1", cat.color)}>{cat.label}</Badge>
                          </div>
                        </div>
                        <div className="flex items-center gap-1">
                          <Badge variant={tipo.ativo ? "default" : "secondary"}>{tipo.ativo ? "Ativo" : "Inativo"}</Badge>
                          <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => handleEditarTipo(tipo)} title="Editar">
                            <Pencil className="w-3.5 h-3.5" />
                          </Button>
                          <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive hover:text-destructive" onClick={() => handleToggleAtivo(tipo)} title={tipo.ativo ? "Desativar" : "Ativar"}>
                            {tipo.ativo ? <Trash2 className="w-3.5 h-3.5" /> : <CheckCircle className="w-3.5 h-3.5 text-success" />}
                          </Button>
                        </div>
                      </div>
                      {tipo.descricao && <p className="text-sm text-muted-foreground mb-3">{tipo.descricao}</p>}
                      <div className="flex items-center justify-between text-sm">
                        <span className="text-muted-foreground">Valor padrão:</span>
                        <span className="font-medium">R$ {tipo.valor_padrao?.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</span>
                      </div>
                      <div className="flex items-center justify-between text-sm mt-1">
                        <span className="text-muted-foreground">Colaboradores:</span>
                        <span className="font-medium">{vinculosDoTipo.length}</span>
                      </div>
                    </CardContent>
                  </Card>
                </motion.div>
              );
            })}
          </div>
        )}
      </div>

      {/* Vínculos Ativos */}
      <div>
        <h3 className="text-lg font-semibold mb-3">Colaboradores com Benefícios</h3>
        {loadingVinculos ? (
          <p className="text-muted-foreground text-sm">Carregando...</p>
        ) : ativos.length === 0 ? (
          <Card><CardContent className="p-8 text-center text-muted-foreground">Nenhum benefício vinculado.</CardContent></Card>
        ) : (
          <div className="bg-card border rounded-xl overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-muted/50 text-muted-foreground">
                  <tr>
                    <th className="text-left p-3 font-medium">Colaborador</th>
                    <th className="text-left p-3 font-medium">Benefício</th>
                    <th className="text-right p-3 font-medium">Valor</th>
                    <th className="text-right p-3 font-medium">Desconto</th>
                    <th className="text-left p-3 font-medium">Início</th>
                    <th className="text-center p-3 font-medium">Status</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border">
                  {ativos.map((v) => (
                    <tr key={v.id} className="hover:bg-muted/30 transition-colors">
                      <td className="p-3 font-medium">{v.colaborador_nome}</td>
                      <td className="p-3">{v.beneficio_tipo?.nome || "—"}</td>
                      <td className="p-3 text-right">R$ {v.valor?.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</td>
                      <td className="p-3 text-right">R$ {v.valor_desconto?.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</td>
                      <td className="p-3">{formatDateBR(v.data_inicio)}</td>
                      <td className="p-3 text-center"><Badge className="bg-success/10 text-success text-xs">Ativo</Badge></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </div>

      {/* Modal Novo Tipo */}
      <Dialog open={showTipoModal} onOpenChange={(open) => { setShowTipoModal(open); if (!open) { setEditingTipoId(null); setTipoForm(emptyTipoForm); } }}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{editingTipoId ? "Editar Benefício" : "Novo Tipo de Benefício"}</DialogTitle>
            <DialogDescription>{editingTipoId ? "Altere os dados do benefício" : "Cadastre um novo benefício para a empresa"}</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Nome *</Label>
                <Input value={tipoForm.nome} onChange={e => setTipoForm(p => ({ ...p, nome: e.target.value }))} placeholder="Ex: Vale Alimentação" />
              </div>
              <div className="space-y-2">
                <Label>Categoria</Label>
                <Select value={tipoForm.categoria} onValueChange={v => setTipoForm(p => ({ ...p, categoria: v }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="alimentacao">Alimentação</SelectItem>
                    <SelectItem value="saude">Saúde</SelectItem>
                    <SelectItem value="transporte">Transporte</SelectItem>
                    <SelectItem value="seguro">Seguro</SelectItem>
                    <SelectItem value="outros">Outros</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div className="space-y-2">
              <Label>Descrição</Label>
              <Textarea value={tipoForm.descricao} onChange={e => setTipoForm(p => ({ ...p, descricao: e.target.value }))} placeholder="Descrição opcional" rows={2} />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Valor Padrão (R$)</Label>
                <Input type="number" step="0.01" value={tipoForm.valor_padrao} onChange={e => setTipoForm(p => ({ ...p, valor_padrao: Number(e.target.value) }))} />
              </div>
              <div className="space-y-2">
                <Label>Desconto Fixo (R$)</Label>
                <Input type="number" step="0.01" value={tipoForm.valor_desconto_fixo} onChange={e => setTipoForm(p => ({ ...p, valor_desconto_fixo: Number(e.target.value) }))} />
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowTipoModal(false)}>Cancelar</Button>
            <Button className="gradient-primary" onClick={handleCriarTipo} disabled={criandoBeneficioTipo}>
              {criandoBeneficioTipo ? "Salvando..." : editingTipoId ? "Salvar Alterações" : "Criar Benefício"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Modal Vincular */}
      <Dialog open={showVinculoModal} onOpenChange={setShowVinculoModal}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Vincular Benefício a Colaborador</DialogTitle>
            <DialogDescription>Selecione o benefício e o colaborador</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-2">
              <Label>Benefício *</Label>
              <Select value={vinculoForm.beneficio_tipo_id} onValueChange={v => {
                const tipo = tipos.find(t => t.id === v);
                setVinculoForm(p => ({ ...p, beneficio_tipo_id: v, valor: tipo?.valor_padrao || 0, valor_desconto: tipo?.valor_desconto_fixo || 0 }));
              }}>
                <SelectTrigger><SelectValue placeholder="Selecione..." /></SelectTrigger>
                <SelectContent>
                  {tipos.filter(t => t.ativo).map(t => <SelectItem key={t.id} value={t.id}>{t.nome}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Colaborador *</Label>
              <Popover open={comboOpen} onOpenChange={setComboOpen}>
                <PopoverTrigger asChild>
                  <Button variant="outline" role="combobox" className="w-full justify-between font-normal">
                    {vinculoForm.colaborador_nome || "Selecione..."}
                    <ChevronsUpDown className="ml-2 h-4 w-4 opacity-50" />
                  </Button>
                </PopoverTrigger>
                <PopoverContent className="w-full p-0" align="start">
                  <Command>
                    <CommandInput placeholder="Buscar..." />
                    <CommandList>
                      <CommandEmpty>Nenhum encontrado.</CommandEmpty>
                      <CommandGroup>
                        {colaboradores.map(c => (
                          <CommandItem key={c.id} value={c.nome_completo} onSelect={() => {
                            setVinculoForm(p => ({ ...p, colaborador_id: c.id, colaborador_nome: c.nome_completo, colaborador_cpf: c.cpf }));
                            setComboOpen(false);
                          }}>
                            <Check className={cn("mr-2 h-4 w-4", vinculoForm.colaborador_id === c.id ? "opacity-100" : "opacity-0")} />
                            {c.nome_completo}
                          </CommandItem>
                        ))}
                      </CommandGroup>
                    </CommandList>
                  </Command>
                </PopoverContent>
              </Popover>
            </div>
            <div className="grid grid-cols-3 gap-4">
              <div className="space-y-2">
                <Label>Valor (R$)</Label>
                <Input type="number" step="0.01" value={vinculoForm.valor} onChange={e => setVinculoForm(p => ({ ...p, valor: Number(e.target.value) }))} />
              </div>
              <div className="space-y-2">
                <Label>Desconto (R$)</Label>
                <Input type="number" step="0.01" value={vinculoForm.valor_desconto} onChange={e => setVinculoForm(p => ({ ...p, valor_desconto: Number(e.target.value) }))} />
              </div>
              <div className="space-y-2">
                <Label>Início</Label>
                <Input type="date" value={vinculoForm.data_inicio} onChange={e => setVinculoForm(p => ({ ...p, data_inicio: e.target.value }))} />
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowVinculoModal(false)}>Cancelar</Button>
            <Button className="gradient-primary" onClick={handleVincular} disabled={vinculandoBeneficio}>
              {vinculandoBeneficio ? "Vinculando..." : "Vincular"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};

// -- Folha Tab --
const FolhaTab = () => {
  const { useFolhaPeriodos, criarPeriodo, criandoPeriodo, atualizarPeriodo, useFolhaItens, criarFolhaItem, criandoFolhaItem } = useFinanceiro();
  const { colaboradores } = useColaboradores();
  const { data: periodos = [], isLoading } = useFolhaPeriodos();

  const [showNovoPeriodo, setShowNovoPeriodo] = useState(false);
  const [competencia, setCompetencia] = useState("");
  const [periodoSelecionado, setPeriodoSelecionado] = useState<string | null>(null);
  const [holeriteItem, setHoleriteItem] = useState<FolhaItem | null>(null);
  const [holeriteCompetencia, setHoleriteCompetencia] = useState("");
  const { data: itens = [] } = useFolhaItens(periodoSelecionado || undefined);

  const handleCriarPeriodo = async () => {
    if (!competencia) return toast.error("Informe a competência (YYYY-MM)");
    await criarPeriodo({ competencia });
    setShowNovoPeriodo(false);
    setCompetencia("");
  };

  const handleGerarPrevia = async (periodoId: string) => {
    // Generate items for all employees
    for (const colab of colaboradores) {
      const admissao = colab as any;
      await criarFolhaItem({
        periodo_id: periodoId,
        colaborador_id: colab.id,
        colaborador_nome: colab.nome_completo,
        colaborador_cpf: colab.cpf,
        cargo: colab.cargo,
        departamento: colab.departamento,
        salario_base: admissao.salario || 0,
        total_proventos: admissao.salario || 0,
        total_descontos: 0,
        total_liquido: admissao.salario || 0,
        status: "calculado",
      });
    }
    await atualizarPeriodo({ id: periodoId, status: "previa" } as any);
    toast.success("Prévia gerada com sucesso!");
  };

  const formatCompetencia = (comp: string) => {
    const [y, m] = comp.split("-");
    const meses = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"];
    return `${meses[Number(m) - 1]}/${y}`;
  };

  return (
    <div className="space-y-6">
      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <div className="p-2 rounded-lg bg-primary/10"><FileText className="w-5 h-5 text-primary" /></div>
            <div><p className="text-2xl font-bold">{periodos.length}</p><p className="text-xs text-muted-foreground">Períodos</p></div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <div className="p-2 rounded-lg bg-warning/10"><Clock className="w-5 h-5 text-warning" /></div>
            <div><p className="text-2xl font-bold">{periodos.filter(p => p.status === "aberto").length}</p><p className="text-xs text-muted-foreground">Em Aberto</p></div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <div className="p-2 rounded-lg bg-success/10"><CheckCircle className="w-5 h-5 text-success" /></div>
            <div><p className="text-2xl font-bold">{periodos.filter(p => p.status === "fechado").length}</p><p className="text-xs text-muted-foreground">Fechados</p></div>
          </CardContent>
        </Card>
      </div>

      <div className="flex gap-2">
        <Button className="gradient-primary shadow-glow" onClick={() => setShowNovoPeriodo(true)}>
          <Plus className="w-4 h-4 mr-2" />Novo Período
        </Button>
      </div>

      {/* Períodos */}
      {isLoading ? (
        <p className="text-muted-foreground text-sm">Carregando...</p>
      ) : periodos.length === 0 ? (
        <Card><CardContent className="p-8 text-center text-muted-foreground">Nenhum período criado. Clique em "Novo Período" para iniciar a folha.</CardContent></Card>
      ) : (
        <div className="space-y-4">
          {periodos.map((p, i) => {
            const statusConf = STATUS_FOLHA[p.status] || STATUS_FOLHA.aberto;
            const isSelected = periodoSelecionado === p.id;
            return (
              <motion.div key={p.id} initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.05 }}>
                <Card className={cn("cursor-pointer hover:border-primary/30 transition-colors", isSelected && "border-primary ring-1 ring-primary/20")} onClick={() => setPeriodoSelecionado(isSelected ? null : p.id)}>
                  <CardContent className="p-5">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-4">
                        <div className="p-2 rounded-lg bg-primary/10"><FileText className="w-5 h-5 text-primary" /></div>
                        <div>
                          <h4 className="font-semibold text-lg">{formatCompetencia(p.competencia)}</h4>
                          <p className="text-sm text-muted-foreground">{p.total_colaboradores} colaboradores</p>
                        </div>
                      </div>
                      <div className="flex items-center gap-3">
                        <div className="text-right">
                          <p className="text-sm text-muted-foreground">Líquido</p>
                          <p className="font-bold">R$ {p.total_liquido?.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</p>
                        </div>
                        <Badge className={cn("text-xs", statusConf.color)}>{statusConf.label}</Badge>
                        {p.status === "aberto" && (
                          <Button size="sm" variant="outline" onClick={(e) => { e.stopPropagation(); handleGerarPrevia(p.id); }}>
                            Gerar Prévia
                          </Button>
                        )}
                      </div>
                    </div>

                    {/* Itens expanded */}
                    {isSelected && itens.length > 0 && (
                      <div className="mt-4 pt-4 border-t">
                        <div className="overflow-x-auto">
                          <table className="w-full text-sm">
                            <thead className="bg-muted/50 text-muted-foreground">
                              <tr>
                                <th className="text-left p-2 font-medium">Colaborador</th>
                                <th className="text-left p-2 font-medium">Cargo</th>
                                <th className="text-right p-2 font-medium">Salário Base</th>
                                <th className="text-right p-2 font-medium">Proventos</th>
                                <th className="text-right p-2 font-medium">Descontos</th>
                                <th className="text-right p-2 font-medium">Líquido</th>
                                <th className="text-center p-2 font-medium">Status</th>
                              </tr>
                            </thead>
                            <tbody className="divide-y divide-border">
                              {itens.map(item => {
                                const isFerias = item.observacoes?.includes("Férias");
                                return (
                                <tr key={item.id} className="hover:bg-muted/30 cursor-pointer" onClick={(e) => { e.stopPropagation(); setHoleriteItem(item); setHoleriteCompetencia(p.competencia); }}>
                                  <td className="p-2 font-medium text-primary underline underline-offset-2">
                                    <div className="flex items-center gap-2">
                                      {item.colaborador_nome}
                                      {isFerias && <Badge className="bg-amber-100 text-amber-800 text-[10px] px-1.5 py-0">Férias</Badge>}
                                    </div>
                                  </td>
                                  <td className="p-2 text-muted-foreground">{item.cargo || "—"}</td>
                                  <td className="p-2 text-right">R$ {item.salario_base?.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</td>
                                  <td className="p-2 text-right text-success">R$ {item.total_proventos?.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</td>
                                  <td className="p-2 text-right text-destructive">R$ {item.total_descontos?.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</td>
                                  <td className="p-2 text-right font-bold">R$ {item.total_liquido?.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</td>
                                  <td className="p-2 text-center"><Badge variant="secondary" className="text-xs">{item.status}</Badge></td>
                                </tr>
                                );
                              })}
                            </tbody>
                          </table>
                        </div>
                      </div>
                    )}
                    {isSelected && itens.length === 0 && (
                      <div className="mt-4 pt-4 border-t text-center text-sm text-muted-foreground">
                        Nenhum item neste período. Gere a prévia para popular.
                      </div>
                    )}
                  </CardContent>
                </Card>
              </motion.div>
            );
          })}
        </div>
      )}

      {/* Modal Novo Período */}
      <Dialog open={showNovoPeriodo} onOpenChange={setShowNovoPeriodo}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Novo Período de Folha</DialogTitle>
            <DialogDescription>Informe a competência</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-2">
              <Label>Competência (mês/ano) *</Label>
              <CompetenciaInput value={competencia} onChange={setCompetencia} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowNovoPeriodo(false)}>Cancelar</Button>
            <Button className="gradient-primary" onClick={handleCriarPeriodo} disabled={criandoPeriodo}>
              {criandoPeriodo ? "Criando..." : "Criar"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Holerite Detail Modal */}
      <HoleriteDetail
        open={!!holeriteItem}
        onClose={() => setHoleriteItem(null)}
        item={holeriteItem}
        competencia={holeriteCompetencia}
      />
    </div>
  );
};

// -- Dashboard Tab --
const DashboardTab = () => {
  const { useFolhaPeriodos, useBeneficiosTipos, useBeneficiosColaboradores } = useFinanceiro();
  const { data: periodos = [] } = useFolhaPeriodos();
  const { data: tipos = [] } = useBeneficiosTipos();
  const { data: vinculos = [] } = useBeneficiosColaboradores();

  const ativos = vinculos.filter(v => v.status === "ativo");
  const ultimoPeriodo = periodos[0];
  const totalBeneficios = ativos.reduce((s, v) => s + (v.valor || 0), 0);

  // Agrupamento por categoria
  const porCategoria: Record<string, number> = {};
  ativos.forEach(v => {
    const tipo = tipos.find(t => t.id === v.beneficio_tipo_id);
    const cat = tipo?.categoria || "outros";
    porCategoria[cat] = (porCategoria[cat] || 0) + (v.valor || 0);
  });

  return (
    <div className="space-y-6">
      {/* KPIs */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <Card className="border-l-4 border-l-primary">
          <CardContent className="p-5">
            <p className="text-sm text-muted-foreground">Última Folha</p>
            <p className="text-2xl font-bold mt-1">
              {ultimoPeriodo ? `R$ ${ultimoPeriodo.total_liquido?.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}` : "—"}
            </p>
            <p className="text-xs text-muted-foreground mt-1">
              {ultimoPeriodo ? `Competência ${ultimoPeriodo.competencia}` : "Nenhum período"}
            </p>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-success">
          <CardContent className="p-5">
            <p className="text-sm text-muted-foreground">Custo Benefícios/mês</p>
            <p className="text-2xl font-bold mt-1">R$ {totalBeneficios.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</p>
            <p className="text-xs text-muted-foreground mt-1">{ativos.length} vínculos ativos</p>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-warning">
          <CardContent className="p-5">
            <p className="text-sm text-muted-foreground">Períodos Abertos</p>
            <p className="text-2xl font-bold mt-1">{periodos.filter(p => p.status !== "fechado").length}</p>
            <p className="text-xs text-muted-foreground mt-1">Requerem atenção</p>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-info">
          <CardContent className="p-5">
            <p className="text-sm text-muted-foreground">Tipos de Benefícios</p>
            <p className="text-2xl font-bold mt-1">{tipos.filter(t => t.ativo).length}</p>
            <p className="text-xs text-muted-foreground mt-1">Cadastrados</p>
          </CardContent>
        </Card>
      </div>

      {/* Custos por Categoria */}
      <Card>
        <CardHeader><CardTitle className="text-lg">Custos por Categoria de Benefício</CardTitle></CardHeader>
        <CardContent>
          {Object.keys(porCategoria).length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-4">Nenhum benefício vinculado ainda.</p>
          ) : (
            <div className="space-y-3">
              {Object.entries(porCategoria).sort((a, b) => b[1] - a[1]).map(([cat, valor]) => {
                const conf = CATEGORIA_BENEFICIO[cat] || CATEGORIA_BENEFICIO.outros;
                const pct = totalBeneficios > 0 ? (valor / totalBeneficios) * 100 : 0;
                return (
                  <div key={cat} className="space-y-1">
                    <div className="flex items-center justify-between text-sm">
                      <span className="font-medium">{conf.label}</span>
                      <span className="text-muted-foreground">R$ {valor.toLocaleString("pt-BR", { minimumFractionDigits: 2 })} ({pct.toFixed(0)}%)</span>
                    </div>
                    <div className="h-2 bg-muted rounded-full overflow-hidden">
                      <div className="h-full bg-primary rounded-full transition-all" style={{ width: `${pct}%` }} />
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Histórico de Períodos */}
      <Card>
        <CardHeader><CardTitle className="text-lg">Histórico de Folha</CardTitle></CardHeader>
        <CardContent>
          {periodos.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-4">Nenhum período criado.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-muted/50 text-muted-foreground">
                  <tr>
                    <th className="text-left p-3 font-medium">Competência</th>
                    <th className="text-right p-3 font-medium">Bruto</th>
                    <th className="text-right p-3 font-medium">Descontos</th>
                    <th className="text-right p-3 font-medium">Líquido</th>
                    <th className="text-center p-3 font-medium">Colaboradores</th>
                    <th className="text-center p-3 font-medium">Status</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border">
                  {periodos.map(p => {
                    const sc = STATUS_FOLHA[p.status] || STATUS_FOLHA.aberto;
                    return (
                      <tr key={p.id} className="hover:bg-muted/30">
                        <td className="p-3 font-medium">{p.competencia}</td>
                        <td className="p-3 text-right">R$ {p.total_bruto?.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</td>
                        <td className="p-3 text-right text-destructive">R$ {p.total_descontos?.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</td>
                        <td className="p-3 text-right font-bold">R$ {p.total_liquido?.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}</td>
                        <td className="p-3 text-center">{p.total_colaboradores}</td>
                        <td className="p-3 text-center"><Badge className={cn("text-xs", sc.color)}>{sc.label}</Badge></td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
};

// ==========================================
// MAIN PAGE
// ==========================================
const Financeiro = ({ defaultTab = "dashboard" }: { defaultTab?: string }) => {
  const [activeTab, setActiveTab] = useState(defaultTab);

  return (
    <div className="space-y-6">
      <motion.div initial={{ opacity: 0, y: -20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4 }}>
        <h1 className="text-2xl font-bold text-foreground">Módulo Financeiro</h1>
        <p className="text-muted-foreground">Folha de pagamento, benefícios e controle financeiro do RH</p>
      </motion.div>

      <Tabs value={activeTab} onValueChange={setActiveTab} className="space-y-6">
        <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }}>
          <TabsList className="bg-muted/50 flex-wrap h-auto gap-1">
            <TabsTrigger id="tab-folha-dashboard" value="dashboard">
              <TrendingUp className="w-4 h-4 mr-2" />Painel
            </TabsTrigger>
            <TabsTrigger id="tab-folha-folha" value="folha">
              <FileText className="w-4 h-4 mr-2" />Folha
            </TabsTrigger>
            <TabsTrigger id="tab-folha-rubricas" value="rubricas">
              <FileCode className="w-4 h-4 mr-2" />Rubricas
            </TabsTrigger>
            <TabsTrigger id="tab-folha-ferias" value="ferias">
              <Sun className="w-4 h-4 mr-2" />Férias
            </TabsTrigger>
            <TabsTrigger id="tab-folha-13salario" value="13salario">
              <Gift className="w-4 h-4 mr-2" />13º
            </TabsTrigger>
            <TabsTrigger id="tab-folha-rescisao" value="rescisao">
              <Calculator className="w-4 h-4 mr-2" />Rescisão
            </TabsTrigger>
            <TabsTrigger id="tab-folha-provisoes" value="provisoes">
              <PiggyBank className="w-4 h-4 mr-2" />Provisões
            </TabsTrigger>
            <TabsTrigger id="tab-folha-beneficios" value="beneficios">
              <Heart className="w-4 h-4 mr-2" />Benefícios
            </TabsTrigger>
            <TabsTrigger id="tab-folha-tabelas" value="tabelas">
              <Settings2 className="w-4 h-4 mr-2" />Tabelas
            </TabsTrigger>
            <TabsTrigger id="tab-folha-cct" value="cct">
              <Scale className="w-4 h-4 mr-2" />CCT
            </TabsTrigger>
            <TabsTrigger id="tab-folha-esocial" value="esocial">
              <FileCode className="w-4 h-4 mr-2" />eSocial
            </TabsTrigger>
             <TabsTrigger id="tab-folha-alertas" value="alertas">
              <Bell className="w-4 h-4 mr-2" />Alertas
            </TabsTrigger>
            <TabsTrigger id="tab-folha-tabelas-fiscais" value="tabelas-fiscais">
              <TableProperties className="w-4 h-4 mr-2" />Tab. Fiscais
            </TabsTrigger>
          </TabsList>
        </motion.div>

        <TabsContent value="dashboard"><DashboardTab /></TabsContent>
        <TabsContent value="folha"><FolhaTab /></TabsContent>
        <TabsContent value="rubricas"><RubricasTab /></TabsContent>
        <TabsContent value="ferias"><FeriasTab /></TabsContent>
        <TabsContent value="13salario"><DecimoTerceiroTab /></TabsContent>
        <TabsContent value="rescisao"><RescisaoTab /></TabsContent>
        <TabsContent value="provisoes"><ProvisoesTab /></TabsContent>
        <TabsContent value="beneficios"><BeneficiosTab /></TabsContent>
        <TabsContent value="tabelas"><TabelasLegaisTab /></TabsContent>
        <TabsContent value="cct"><FolhaCCTTab /></TabsContent>
        <TabsContent value="esocial"><FolhaESocialTab /></TabsContent>
        <TabsContent value="alertas"><FolhaAlertasTab /></TabsContent>
        <TabsContent value="tabelas-fiscais"><TabelasFiscaisTab /></TabsContent>
      </Tabs>
    </div>
  );
};

export default Financeiro;
