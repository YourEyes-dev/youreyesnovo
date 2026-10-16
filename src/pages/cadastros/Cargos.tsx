import { useState, useEffect } from "react";
import { motion } from "framer-motion";
import { Plus, Pencil, Trash2, Briefcase, Search, Upload, ShieldAlert, Zap, Clock } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ImportPlanilhaModal } from "@/components/import/ImportPlanilhaModal";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from "@/components/ui/table";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Separator } from "@/components/ui/separator";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useCargos, useDepartamentos, Cargo } from "@/hooks/useCadastros";
import { useSyncCadastros } from "@/hooks/useSyncCadastros";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Checkbox } from "@/components/ui/checkbox";
import { ChevronsUpDown, X } from "lucide-react";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useTenant } from "@/hooks/useTenant";
import { usePodeVerSalario } from "@/hooks/usePodeVerSalario";
import { cn } from "@/lib/utils";

const NIVEIS = [
  { value: "estagiario", label: "Estagiário" },
  { value: "junior", label: "Júnior" },
  { value: "pleno", label: "Pleno" },
  { value: "senior", label: "Sênior" },
  { value: "especialista", label: "Especialista" },
  { value: "coordenador", label: "Coordenador" },
  { value: "gerente", label: "Gerente" },
  { value: "diretor", label: "Diretor" },
];

const GRAUS_INSALUBRIDADE = [
  { value: "minimo", label: "Mínimo (10%)" },
  { value: "medio", label: "Médio (20%)" },
  { value: "maximo", label: "Máximo (40%)" },
];

const TIPOS_PERICULOSIDADE = [
  { value: "inflamaveis", label: "Inflamáveis" },
  { value: "eletricidade", label: "Eletricidade" },
  { value: "explosivos", label: "Explosivos" },
  { value: "radiacao", label: "Radiações Ionizantes" },
  { value: "outros", label: "Outros (NR-16)" },
];

const ANOS_APOSENTADORIA = [
  { value: "15", label: "15 anos" },
  { value: "20", label: "20 anos" },
  { value: "25", label: "25 anos" },
];

type FormData = {
  nome: string;
  descricao: string;
  departamento_id: string | null;
  nivel: string | null;
  faixa_salarial_min: number | null;
  faixa_salarial_max: number | null;
  periodicidade_exame_meses: number | null;
  exames_obrigatorios: string[] | null;
  insalubridade: boolean;
  insalubridade_grau: string | null;
  insalubridade_agente_nocivo: string | null;
  periculosidade: boolean;
  periculosidade_tipo: string | null;
  aposentadoria_especial: boolean;
  aposentadoria_especial_anos: number | null;
  ativo: boolean;
};

const defaultFormData: FormData = {
  nome: "",
  descricao: "",
  departamento_id: null,
  nivel: null,
  faixa_salarial_min: null,
  faixa_salarial_max: null,
  periodicidade_exame_meses: 12,
  exames_obrigatorios: ['Clínico Geral'],
  insalubridade: false,
  insalubridade_grau: null,
  insalubridade_agente_nocivo: null,
  periculosidade: false,
  periculosidade_tipo: null,
  aposentadoria_especial: false,
  aposentadoria_especial_anos: null,
  ativo: true,
};

export default function Cargos() {
  const { cargos, isLoading, createCargo, updateCargo, deleteCargo } = useCargos();
  const { departamentos } = useDepartamentos();
  const { sincronizar } = useSyncCadastros();
  const { tenantId } = useTenant();
  const podeVerSalario = usePodeVerSalario();
  const queryClient = useQueryClient();
  const [searchTerm, setSearchTerm] = useState("");
  const [isFormOpen, setIsFormOpen] = useState(false);
  const [isDeleteOpen, setIsDeleteOpen] = useState(false);
  const [isImportOpen, setIsImportOpen] = useState(false);
  const [selectedCargo, setSelectedCargo] = useState<Cargo | null>(null);
  const [formData, setFormData] = useState<FormData>({ ...defaultFormData });
  const [departamentoIds, setDepartamentoIds] = useState<string[]>([]);
  const [depPopoverOpen, setDepPopoverOpen] = useState(false);

  // Carrega vínculos cargo→departamentos para badges na tabela e edição
  const { data: cargoDepLinks = [] } = useQuery({
    queryKey: ["cargo_departamentos", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data, error } = await fromTable("cargo_departamentos")
        .select("cargo_id, departamento_id")
        .eq("tenant_id", tenantId);
      if (error) throw error;
      return (data || []) as Array<{ cargo_id: string; departamento_id: string }>;
    },
    enabled: !!tenantId,
  });

  const depsByCargo = new Map<string, string[]>();
  cargoDepLinks.forEach((l) => {
    const arr = depsByCargo.get(l.cargo_id) || [];
    arr.push(l.departamento_id);
    depsByCargo.set(l.cargo_id, arr);
  });

  useEffect(() => {
    sincronizar();
  }, [sincronizar]);

  const handleImportSuccess = () => {
    queryClient.invalidateQueries({ queryKey: ["cargos"] });
    queryClient.invalidateQueries({ queryKey: ["departamentos"] });
  };

  const filteredCargos = cargos.filter((cargo) =>
    cargo.nome.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const handleOpenCreate = () => {
    setSelectedCargo(null);
    setFormData({ ...defaultFormData });
    setDepartamentoIds([]);
    setIsFormOpen(true);
  };

  const handleOpenEdit = (cargo: Cargo) => {
    setSelectedCargo(cargo);
    setFormData({
      nome: cargo.nome,
      descricao: cargo.descricao || "",
      departamento_id: cargo.departamento_id,
      nivel: cargo.nivel,
      faixa_salarial_min: cargo.faixa_salarial_min,
      faixa_salarial_max: cargo.faixa_salarial_max,
      periodicidade_exame_meses: cargo.periodicidade_exame_meses || 12,
      exames_obrigatorios: cargo.exames_obrigatorios || ['Clínico Geral'],
      insalubridade: cargo.insalubridade || false,
      insalubridade_grau: cargo.insalubridade_grau,
      insalubridade_agente_nocivo: cargo.insalubridade_agente_nocivo,
      periculosidade: cargo.periculosidade || false,
      periculosidade_tipo: cargo.periculosidade_tipo,
      aposentadoria_especial: cargo.aposentadoria_especial || false,
      aposentadoria_especial_anos: cargo.aposentadoria_especial_anos,
      ativo: cargo.ativo,
    });
    // Carrega vínculos da junção; se vazio, faz fallback para o departamento principal
    const links = depsByCargo.get(cargo.id) || [];
    const initial = links.length ? links : (cargo.departamento_id ? [cargo.departamento_id] : []);
    setDepartamentoIds(initial);
    setIsFormOpen(true);
  };

  const handleOpenDelete = (cargo: Cargo) => {
    setSelectedCargo(cargo);
    setIsDeleteOpen(true);
  };

  const syncCargoDepartamentos = async (cargoId: string) => {
    if (!tenantId) return;
    // Apaga vínculos antigos e insere os atuais
    await fromTable("cargo_departamentos").delete().eq("cargo_id", cargoId);
    if (departamentoIds.length > 0) {
      const rows = departamentoIds.map((dep_id) => ({
        tenant_id: tenantId,
        cargo_id: cargoId,
        departamento_id: dep_id,
      }));
      const { error } = await fromTable("cargo_departamentos").insert(rows);
      if (error) throw error;
    }
    queryClient.invalidateQueries({ queryKey: ["cargo_departamentos", tenantId] });
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    // Departamento principal = primeiro selecionado (mantém compatibilidade)
    const principal = departamentoIds[0] || null;
    const payload = { ...formData, departamento_id: principal };
    let cargoId: string;
    if (selectedCargo) {
      await updateCargo.mutateAsync({ id: selectedCargo.id, ...payload });
      cargoId = selectedCargo.id;
    } else {
      const created = await createCargo.mutateAsync(payload);
      cargoId = (created as any)?.id;
    }
    if (cargoId) await syncCargoDepartamentos(cargoId);
    setIsFormOpen(false);
  };

  const handleDelete = async () => {
    if (selectedCargo) {
      await deleteCargo.mutateAsync(selectedCargo.id);
      setIsDeleteOpen(false);
    }
  };

  const formatCurrency = (value: number | null) => {
    if (value === null) return "-";
    return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value);
  };

  const getNivelLabel = (nivel: string | null) => {
    if (!nivel) return "-";
    return NIVEIS.find((n) => n.value === nivel)?.label || nivel;
  };

  const hasCondicoesEspeciais = (cargo: Cargo) =>
    cargo.insalubridade || cargo.periculosidade || cargo.aposentadoria_especial;

  return (
    <div className="space-y-6">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4"
      >
        <div>
          <h1 className="text-2xl font-bold text-foreground">Cargos</h1>
          <p className="text-muted-foreground">
            Gerencie as cargos da sua empresa
          </p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={() => setIsImportOpen(true)} className="gap-2">
            <Upload className="w-4 h-4" />
            Importar Planilha
          </Button>
          <Button onClick={handleOpenCreate} className="gap-2">
            <Plus className="w-4 h-4" />
            Novo Cargo
          </Button>
        </div>
      </motion.div>

      {/* Search */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.1 }}
        className="relative"
      >
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
        <Input
          placeholder="Buscar cargos..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="pl-10 max-w-sm"
        />
      </motion.div>

      {/* Table */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.2 }}
        className="rounded-lg border bg-card"
      >
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Nome</TableHead>
              <TableHead>Departamentos</TableHead>
              <TableHead>Nível</TableHead>
              <TableHead>Faixa Salarial</TableHead>
              <TableHead>Condições Especiais</TableHead>
              <TableHead>Status</TableHead>
              <TableHead className="text-right">Ações</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {isLoading ? (
              <TableRow>
                <TableCell colSpan={7} className="text-center py-8">Carregando...</TableCell>
              </TableRow>
            ) : filteredCargos.length === 0 ? (
              <TableRow>
                <TableCell colSpan={7} className="text-center py-8">
                  <div className="flex flex-col items-center gap-2">
                    <Briefcase className="w-8 h-8 text-muted-foreground" />
                    <p className="text-muted-foreground">
                      {searchTerm ? "Nenhuma cargo encontrada" : "Nenhuma cargo cadastrada"}
                    </p>
                  </div>
                </TableCell>
              </TableRow>
            ) : (
              filteredCargos.map((cargo) => (
                <TableRow key={cargo.id}>
                  <TableCell className="font-medium">{cargo.nome}</TableCell>
                  <TableCell className="text-muted-foreground">
                    {(() => {
                      const ids = depsByCargo.get(cargo.id) || (cargo.departamento_id ? [cargo.departamento_id] : []);
                      if (ids.length === 0) return "-";
                      const nomes = ids
                        .map((id) => departamentos.find((d) => d.id === id)?.nome)
                        .filter(Boolean) as string[];
                      if (nomes.length === 0) return "-";
                      return (
                        <div className="flex flex-wrap gap-1">
                          {nomes.slice(0, 3).map((n) => (
                            <Badge key={n} variant="secondary" className="text-xs font-normal">{n}</Badge>
                          ))}
                          {nomes.length > 3 && (
                            <Badge variant="outline" className="text-xs font-normal">+{nomes.length - 3}</Badge>
                          )}
                        </div>
                      );
                    })()}
                  </TableCell>
                  <TableCell>{getNivelLabel(cargo.nivel)}</TableCell>
                  <TableCell className="text-muted-foreground">
                    {!podeVerSalario
                      ? <span className="italic">Sem permissão</span>
                      : cargo.faixa_salarial_min || cargo.faixa_salarial_max
                        ? `${formatCurrency(cargo.faixa_salarial_min)} - ${formatCurrency(cargo.faixa_salarial_max)}`
                        : "-"}
                  </TableCell>
                  <TableCell>
                    {hasCondicoesEspeciais(cargo) ? (
                      <TooltipProvider>
                        <div className="flex gap-1">
                          {cargo.insalubridade && (
                            <Tooltip>
                              <TooltipTrigger>
                                <Badge variant="destructive" className="gap-1 text-xs">
                                  <ShieldAlert className="w-3 h-3" />
                                  Insalubre
                                </Badge>
                              </TooltipTrigger>
                              <TooltipContent>
                                Grau {GRAUS_INSALUBRIDADE.find(g => g.value === cargo.insalubridade_grau)?.label || cargo.insalubridade_grau}
                                {cargo.insalubridade_agente_nocivo && ` • ${cargo.insalubridade_agente_nocivo}`}
                              </TooltipContent>
                            </Tooltip>
                          )}
                          {cargo.periculosidade && (
                            <Tooltip>
                              <TooltipTrigger>
                                <Badge className="gap-1 text-xs bg-amber-600 hover:bg-amber-700">
                                  <Zap className="w-3 h-3" />
                                  Periculoso
                                </Badge>
                              </TooltipTrigger>
                              <TooltipContent>
                                {TIPOS_PERICULOSIDADE.find(t => t.value === cargo.periculosidade_tipo)?.label || cargo.periculosidade_tipo}
                              </TooltipContent>
                            </Tooltip>
                          )}
                          {cargo.aposentadoria_especial && (
                            <Tooltip>
                              <TooltipTrigger>
                                <Badge variant="secondary" className="gap-1 text-xs">
                                  <Clock className="w-3 h-3" />
                                  Apos. Esp.
                                </Badge>
                              </TooltipTrigger>
                              <TooltipContent>
                                Enquadramento: {cargo.aposentadoria_especial_anos} anos
                              </TooltipContent>
                            </Tooltip>
                          )}
                        </div>
                      </TooltipProvider>
                    ) : (
                      <span className="text-muted-foreground text-sm">—</span>
                    )}
                  </TableCell>
                  <TableCell>
                    <Badge variant={cargo.ativo ? "default" : "secondary"}>
                      {cargo.ativo ? "Ativo" : "Inativo"}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-2">
                      <Button variant="ghost" size="icon" onClick={() => handleOpenEdit(cargo)}>
                        <Pencil className="w-4 h-4" />
                      </Button>
                      <Button variant="ghost" size="icon" onClick={() => handleOpenDelete(cargo)}>
                        <Trash2 className="w-4 h-4 text-destructive" />
                      </Button>
                    </div>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </motion.div>

      {/* Form Dialog */}
      <Dialog open={isFormOpen} onOpenChange={setIsFormOpen}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{selectedCargo ? "Editar Cargo" : "Novo Cargo"}</DialogTitle>
            <DialogDescription>
              {selectedCargo ? "Edite as informações da cargo" : "Preencha os dados do novo cargo"}
            </DialogDescription>
          </DialogHeader>
          <form onSubmit={handleSubmit}>
            <Tabs defaultValue="geral" className="w-full">
              <TabsList className="grid w-full grid-cols-2">
                <TabsTrigger value="geral">Dados Gerais</TabsTrigger>
                <TabsTrigger value="sst" className="gap-1">
                  <ShieldAlert className="w-3.5 h-3.5" />
                  Condições Especiais (SST)
                </TabsTrigger>
              </TabsList>

              <TabsContent value="geral" className="space-y-4 mt-4">
                <div className="space-y-2">
                  <Label htmlFor="nome">Nome *</Label>
                  <Input
                    id="nome"
                    value={formData.nome}
                    onChange={(e) => setFormData({ ...formData, nome: e.target.value })}
                    placeholder="Ex: Analista de RH"
                    required
                  />
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Departamentos</Label>
                    <Popover open={depPopoverOpen} onOpenChange={setDepPopoverOpen}>
                      <PopoverTrigger asChild>
                        <Button
                          type="button"
                          variant="outline"
                          role="combobox"
                          className={cn(
                            "w-full justify-between font-normal h-auto min-h-10 py-2",
                            departamentoIds.length === 0 && "text-muted-foreground"
                          )}
                        >
                          <div className="flex flex-wrap gap-1 items-center">
                            {departamentoIds.length === 0 ? (
                              <span>Selecione um ou mais...</span>
                            ) : (
                              departamentoIds.map((id) => {
                                const dep = departamentos.find((d) => d.id === id);
                                if (!dep) return null;
                                return (
                                  <Badge key={id} variant="secondary" className="gap-1 text-xs font-normal">
                                    {dep.nome}
                                    <span
                                      role="button"
                                      tabIndex={0}
                                      className="ml-0.5 rounded-sm hover:bg-muted-foreground/20 p-0.5 cursor-pointer"
                                      onClick={(e) => {
                                        e.stopPropagation();
                                        setDepartamentoIds((prev) => prev.filter((x) => x !== id));
                                      }}
                                    >
                                      <X className="w-3 h-3" />
                                    </span>
                                  </Badge>
                                );
                              })
                            )}
                          </div>
                          <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
                        </Button>
                      </PopoverTrigger>
                      <PopoverContent className="w-[var(--radix-popover-trigger-width)] p-0" align="start">
                        <div className="max-h-[260px] overflow-y-auto p-1">
                          {departamentos.length === 0 ? (
                            <p className="text-sm text-muted-foreground p-3 text-center">
                              Nenhum departamento cadastrado
                            </p>
                          ) : (
                            departamentos.map((dep) => {
                              const checked = departamentoIds.includes(dep.id);
                              return (
                                <label
                                  key={dep.id}
                                  className="flex items-center gap-2 px-2 py-1.5 text-sm rounded hover:bg-accent cursor-pointer"
                                >
                                  <Checkbox
                                    checked={checked}
                                    onCheckedChange={(v) => {
                                      setDepartamentoIds((prev) =>
                                        v ? [...prev, dep.id] : prev.filter((x) => x !== dep.id)
                                      );
                                    }}
                                  />
                                  <span>{dep.nome}</span>
                                </label>
                              );
                            })
                          )}
                        </div>
                      </PopoverContent>
                    </Popover>
                    <p className="text-xs text-muted-foreground">
                      O primeiro selecionado será considerado o departamento principal.
                    </p>
                  </div>
                  <div className="space-y-2">
                    <Label>Nível</Label>
                    <Select
                      value={formData.nivel || "none"}
                      onValueChange={(value) => setFormData({ ...formData, nivel: value === "none" ? null : value })}
                    >
                      <SelectTrigger><SelectValue placeholder="Selecione..." /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="none">Nenhum</SelectItem>
                        {NIVEIS.map((nivel) => (
                          <SelectItem key={nivel.value} value={nivel.value}>{nivel.label}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Salário Mínimo</Label>
                    <Input
                      type={podeVerSalario ? "number" : "text"}
                      value={podeVerSalario ? (formData.faixa_salarial_min || "") : "Sem permissão"}
                      disabled={!podeVerSalario}
                      onChange={(e) => setFormData({ ...formData, faixa_salarial_min: e.target.value ? Number(e.target.value) : null })}
                      placeholder="R$ 0,00"
                      className={!podeVerSalario ? "italic text-muted-foreground" : undefined}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Salário Máximo</Label>
                    <Input
                      type={podeVerSalario ? "number" : "text"}
                      value={podeVerSalario ? (formData.faixa_salarial_max || "") : "Sem permissão"}
                      disabled={!podeVerSalario}
                      onChange={(e) => setFormData({ ...formData, faixa_salarial_max: e.target.value ? Number(e.target.value) : null })}
                      placeholder="R$ 0,00"
                      className={!podeVerSalario ? "italic text-muted-foreground" : undefined}
                    />
                  </div>
                </div>

                <div className="space-y-2">
                  <Label>Descrição</Label>
                  <Textarea
                    value={formData.descricao}
                    onChange={(e) => setFormData({ ...formData, descricao: e.target.value })}
                    placeholder="Descreva as responsabilidades da cargo..."
                    rows={3}
                  />
                </div>

                <div className="flex items-center justify-between">
                  <Label>Ativo</Label>
                  <Switch
                    checked={formData.ativo}
                    onCheckedChange={(checked) => setFormData({ ...formData, ativo: checked })}
                  />
                </div>
              </TabsContent>

              <TabsContent value="sst" className="space-y-6 mt-4">
                <div className="rounded-lg border border-amber-500/30 bg-amber-500/5 p-3">
                  <p className="text-sm text-muted-foreground">
                    <strong className="text-foreground">Base Técnica SST:</strong> As condições abaixo devem ser fundamentadas em PGR, LTCAT ou laudos técnicos (NR-15/NR-16). 
                    Os adicionais serão herdados automaticamente pelos colaboradores vinculados a esta cargo.
                  </p>
                </div>

                {/* Insalubridade */}
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <ShieldAlert className="w-4 h-4 text-destructive" />
                      <Label className="text-base font-semibold">Insalubridade</Label>
                    </div>
                    <Switch
                      checked={formData.insalubridade}
                      onCheckedChange={(checked) => setFormData({
                        ...formData,
                        insalubridade: checked,
                        ...(!checked && { insalubridade_grau: null, insalubridade_agente_nocivo: null }),
                      })}
                    />
                  </div>

                  {formData.insalubridade && (
                    <div className="pl-6 space-y-3 border-l-2 border-destructive/30">
                      <div className="space-y-2">
                        <Label>Grau de Insalubridade *</Label>
                        <Select
                          value={formData.insalubridade_grau || ""}
                          onValueChange={(value) => setFormData({ ...formData, insalubridade_grau: value })}
                        >
                          <SelectTrigger><SelectValue placeholder="Selecione o grau..." /></SelectTrigger>
                          <SelectContent>
                            {GRAUS_INSALUBRIDADE.map((g) => (
                              <SelectItem key={g.value} value={g.value}>{g.label}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="space-y-2">
                        <Label>Agente Nocivo (NR-15)</Label>
                        <Input
                          value={formData.insalubridade_agente_nocivo || ""}
                          onChange={(e) => setFormData({ ...formData, insalubridade_agente_nocivo: e.target.value })}
                          placeholder="Ex: Ruído contínuo acima de 85dB"
                        />
                      </div>
                    </div>
                  )}
                </div>

                <Separator />

                {/* Periculosidade */}
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <Zap className="w-4 h-4 text-amber-500" />
                      <Label className="text-base font-semibold">Periculosidade</Label>
                    </div>
                    <Switch
                      checked={formData.periculosidade}
                      onCheckedChange={(checked) => setFormData({
                        ...formData,
                        periculosidade: checked,
                        ...(!checked && { periculosidade_tipo: null }),
                      })}
                    />
                  </div>

                  {formData.periculosidade && (
                    <div className="pl-6 space-y-3 border-l-2 border-amber-500/30">
                      <div className="space-y-2">
                        <Label>Tipo de Periculosidade *</Label>
                        <Select
                          value={formData.periculosidade_tipo || ""}
                          onValueChange={(value) => setFormData({ ...formData, periculosidade_tipo: value })}
                        >
                          <SelectTrigger><SelectValue placeholder="Selecione o tipo..." /></SelectTrigger>
                          <SelectContent>
                            {TIPOS_PERICULOSIDADE.map((t) => (
                              <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                      <p className="text-xs text-muted-foreground">Adicional fixo de 30% sobre o salário base (art. 193 da CLT).</p>
                    </div>
                  )}
                </div>

                <Separator />

                {/* Aposentadoria Especial */}
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <Clock className="w-4 h-4 text-blue-500" />
                      <Label className="text-base font-semibold">Aposentadoria Especial</Label>
                    </div>
                    <Switch
                      checked={formData.aposentadoria_especial}
                      onCheckedChange={(checked) => setFormData({
                        ...formData,
                        aposentadoria_especial: checked,
                        ...(!checked && { aposentadoria_especial_anos: null }),
                      })}
                    />
                  </div>

                  {formData.aposentadoria_especial && (
                    <div className="pl-6 space-y-3 border-l-2 border-blue-500/30">
                      <div className="space-y-2">
                        <Label>Enquadramento Previdenciário *</Label>
                        <Select
                          value={formData.aposentadoria_especial_anos?.toString() || ""}
                          onValueChange={(value) => setFormData({ ...formData, aposentadoria_especial_anos: Number(value) })}
                        >
                          <SelectTrigger><SelectValue placeholder="Selecione..." /></SelectTrigger>
                          <SelectContent>
                            {ANOS_APOSENTADORIA.map((a) => (
                              <SelectItem key={a.value} value={a.value}>{a.label}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                      <p className="text-xs text-muted-foreground">
                        Registrado para informação ao eSocial (S-2240) e controle previdenciário.
                      </p>
                    </div>
                  )}
                </div>

                {/* Aviso de prevalência */}
                {formData.insalubridade && formData.periculosidade && (
                  <>
                    <Separator />
                    <div className="rounded-lg border border-primary/30 bg-primary/5 p-4">
                      <div className="flex gap-2">
                        <ShieldAlert className="w-5 h-5 text-primary flex-shrink-0 mt-0.5" />
                        <div>
                          <p className="text-sm font-semibold text-foreground">Regra de Prevalência (Art. 193, §2º CLT)</p>
                          <p className="text-sm text-muted-foreground mt-1">
                            Quando houver exposição simultânea, o sistema calculará ambos os adicionais e aplicará automaticamente 
                            o mais vantajoso ao trabalhador, vedada a cumulatividade. O registro técnico e legal da decisão será mantido.
                          </p>
                        </div>
                      </div>
                    </div>
                  </>
                )}
              </TabsContent>
            </Tabs>

            <DialogFooter className="mt-6">
              <Button type="button" variant="outline" onClick={() => setIsFormOpen(false)}>Cancelar</Button>
              <Button type="submit" disabled={createCargo.isPending || updateCargo.isPending}>
                {selectedCargo ? "Salvar" : "Criar"}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Delete Confirmation */}
      <AlertDialog open={isDeleteOpen} onOpenChange={setIsDeleteOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Excluir Cargo</AlertDialogTitle>
            <AlertDialogDescription>
              Tem certeza que deseja excluir a cargo "{selectedCargo?.nome}"? Esta ação não pode ser desfeita.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDelete}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              Excluir
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Import Modal */}
      <ImportPlanilhaModal
        open={isImportOpen}
        onOpenChange={setIsImportOpen}
        onSuccess={handleImportSuccess}
        titulo="Importar Cargos e Colaboradores"
        descricao="Importe uma planilha para criar cargos, departamentos e colaboradores automaticamente"
      />
    </div>
  );
}
