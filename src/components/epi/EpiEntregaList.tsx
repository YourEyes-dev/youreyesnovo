import { useState, useMemo } from "react";
import { motion } from "framer-motion";
import { format, isWithinInterval, startOfDay, endOfDay } from "date-fns";
import { ptBR } from "date-fns/locale";
import {
  RotateCcw,
  User,
  Calendar,
  Package,
  Search,
  X,
  CalendarIcon,
  Wrench,
  Trash2,
  ArchiveRestore,
} from "lucide-react";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
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
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Calendar as CalendarComponent } from "@/components/ui/calendar";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { cn } from "@/lib/utils";
import type { EpiEntrega, EpiCompleto, EntregaStatus } from "@/types/epi";
import { ENTREGA_STATUS_LABELS, ENTREGA_STATUS_COLORS } from "@/types/epi";

type DestinoType = "manutencao" | "descarte" | "estoque";

interface EpiEntregaListProps {
  entregas: (EpiEntrega & { epi: EpiCompleto })[];
  isLoading?: boolean;
  onDevolucao?: (entregaId: string, observacoes?: string, destino?: DestinoType) => Promise<void>;
}

export function EpiEntregaList({
  entregas,
  isLoading,
  onDevolucao,
}: EpiEntregaListProps) {
  const [filtroColaborador, setFiltroColaborador] = useState("");
  const [filtroEpi, setFiltroEpi] = useState<string>("all");
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const [dataInicio, setDataInicio] = useState<Date | undefined>();
  const [dataFim, setDataFim] = useState<Date | undefined>();
  const [devolucaoModal, setDevolucaoModal] = useState<{
    open: boolean;
    entregaId: string;
    colaborador: string;
  }>({ open: false, entregaId: "", colaborador: "" });
  const [observacoes, setObservacoes] = useState("");
  const [destino, setDestino] = useState<DestinoType>("estoque");
  const [processando, setProcessando] = useState(false);

  // Obter lista única de EPIs para o filtro
  const episUnicos = useMemo(() => {
    const map = new Map<string, string>();
    entregas.forEach((entrega) => {
      if (entrega.epi?.tipo?.nome) {
        map.set(entrega.epi.tipo.id, entrega.epi.tipo.nome);
      }
    });
    return Array.from(map.entries()).map(([id, nome]) => ({ id, nome }));
  }, [entregas]);

  const filtered = useMemo(() => {
    return entregas.filter((entrega) => {
      // Filtro por colaborador
      if (filtroColaborador) {
        const nomeColaborador = entrega.colaborador_nome.toLowerCase();
        const cpfColaborador = entrega.colaborador_cpf || "";
        if (
          !nomeColaborador.includes(filtroColaborador.toLowerCase()) &&
          !cpfColaborador.includes(filtroColaborador)
        ) {
          return false;
        }
      }

      // Filtro por EPI
      if (filtroEpi && filtroEpi !== "all") {
        if (entrega.epi?.tipo?.id !== filtroEpi) {
          return false;
        }
      }

      // Filtro por status
      if (statusFilter !== "all" && entrega.status !== statusFilter) {
        return false;
      }

      // Filtro por período
      if (dataInicio || dataFim) {
        const dataEntrega = new Date(entrega.data_entrega);

        if (dataInicio && dataFim) {
          if (
            !isWithinInterval(dataEntrega, {
              start: startOfDay(dataInicio),
              end: endOfDay(dataFim),
            })
          ) {
            return false;
          }
        } else if (dataInicio) {
          if (dataEntrega < startOfDay(dataInicio)) {
            return false;
          }
        } else if (dataFim) {
          if (dataEntrega > endOfDay(dataFim)) {
            return false;
          }
        }
      }

      return true;
    });
  }, [entregas, filtroColaborador, filtroEpi, statusFilter, dataInicio, dataFim]);

  const limparFiltros = () => {
    setFiltroColaborador("");
    setFiltroEpi("all");
    setStatusFilter("all");
    setDataInicio(undefined);
    setDataFim(undefined);
  };

  const temFiltrosAtivos =
    filtroColaborador ||
    (filtroEpi && filtroEpi !== "all") ||
    statusFilter !== "all" ||
    dataInicio ||
    dataFim;

  const handleDevolucao = async () => {
    if (!onDevolucao) return;
    setProcessando(true);
    try {
      await onDevolucao(devolucaoModal.entregaId, observacoes, destino);
      setDevolucaoModal({ open: false, entregaId: "", colaborador: "" });
      setObservacoes("");
      setDestino("estoque");
    } finally {
      setProcessando(false);
    }
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Filtros */}
      <div className="flex flex-col gap-4 p-5 bg-card border rounded-xl shadow-sm">
        <div className="flex items-center gap-2 mb-1">
          <Search className="h-4 w-4 text-primary" />
          <h3 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground">Filtros de Busca</h3>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-12 gap-4">
          <div className="md:col-span-5">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Pesquisar por nome ou CPF do colaborador..."
                value={filtroColaborador}
                onChange={(e) => setFiltroColaborador(e.target.value)}
                className="pl-10 h-10 border-muted-foreground/20 focus-visible:ring-primary"
              />
            </div>
          </div>
          <div className="md:col-span-4">
            <Select value={filtroEpi} onValueChange={setFiltroEpi}>
              <SelectTrigger className="h-10 border-muted-foreground/20">
                <div className="flex items-center gap-2 overflow-hidden">
                  <Package className="h-4 w-4 text-muted-foreground shrink-0" />
                  <SelectValue placeholder="Todos os EPIs" />
                </div>
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Todos os tipos de EPI</SelectItem>
                {episUnicos.map((epi) => (
                  <SelectItem key={epi.id} value={epi.id}>
                    {epi.nome}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="md:col-span-3">
            <Select value={statusFilter} onValueChange={setStatusFilter}>
              <SelectTrigger className="h-10 border-muted-foreground/20">
                <div className="flex items-center gap-2">
                  <RotateCcw className="h-4 w-4 text-muted-foreground shrink-0" />
                  <SelectValue placeholder="Status" />
                </div>
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Todos os Status</SelectItem>
                <SelectItem value="ativa">🟢 Em Uso (Ativas)</SelectItem>
                <SelectItem value="devolvido">🔵 Devolvidas</SelectItem>
                <SelectItem value="extraviado">🔴 Extraviadas</SelectItem>
                <SelectItem value="recusado">🟠 Recusadas</SelectItem>
                <SelectItem value="vencido">🟠 Vencidas</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>

        {/* Filtro por período */}
        <div className="flex flex-col sm:flex-row gap-4 items-end">
          <div className="flex-1 sm:flex-initial">
            <label className="text-sm font-medium text-muted-foreground mb-1.5 block">
              Data inicial
            </label>
            <Popover>
              <PopoverTrigger asChild>
                <Button
                  variant="outline"
                  className={cn(
                    "w-full sm:w-[180px] justify-start text-left font-normal",
                    !dataInicio && "text-muted-foreground"
                  )}
                >
                  <CalendarIcon className="mr-2 h-4 w-4" />
                  {dataInicio
                    ? format(dataInicio, "dd/MM/yyyy", { locale: ptBR })
                    : "Selecionar"}
                </Button>
              </PopoverTrigger>
              <PopoverContent className="w-auto p-0" align="start">
                <CalendarComponent
                  mode="single"
                  selected={dataInicio}
                  onSelect={setDataInicio}
                  disabled={(date) => (dataFim ? date > dataFim : false)}
                  initialFocus
                  className={cn("p-3 pointer-events-auto")}
                />
              </PopoverContent>
            </Popover>
          </div>

          <div className="flex-1 sm:flex-initial">
            <label className="text-sm font-medium text-muted-foreground mb-1.5 block">
              Data final
            </label>
            <Popover>
              <PopoverTrigger asChild>
                <Button
                  variant="outline"
                  className={cn(
                    "w-full sm:w-[180px] justify-start text-left font-normal",
                    !dataFim && "text-muted-foreground"
                  )}
                >
                  <CalendarIcon className="mr-2 h-4 w-4" />
                  {dataFim
                    ? format(dataFim, "dd/MM/yyyy", { locale: ptBR })
                    : "Selecionar"}
                </Button>
              </PopoverTrigger>
              <PopoverContent className="w-auto p-0" align="start">
                <CalendarComponent
                  mode="single"
                  selected={dataFim}
                  onSelect={setDataFim}
                  disabled={(date) => (dataInicio ? date < dataInicio : false)}
                  initialFocus
                  className={cn("p-3 pointer-events-auto")}
                />
              </PopoverContent>
            </Popover>
          </div>

          {temFiltrosAtivos && (
            <Button variant="ghost" onClick={limparFiltros} className="gap-2">
              <X className="h-4 w-4" />
              Limpar filtros
            </Button>
          )}
        </div>
      </div>

      {/* Contador de resultados */}
      {temFiltrosAtivos && (
        <p className="text-sm text-muted-foreground">
          Exibindo {filtered.length} de {entregas.length} entregas
        </p>
      )}

      {entregas.length === 0 ? (
        <div className="text-center py-12 text-muted-foreground">
          <User className="w-12 h-12 mx-auto mb-4 opacity-50" />
          <p>Nenhuma entrega registrada</p>
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-12 text-muted-foreground">
          <Search className="w-12 h-12 mx-auto mb-4 opacity-50" />
          <p>Nenhuma entrega encontrada com os filtros aplicados</p>
          <Button variant="link" onClick={limparFiltros} className="mt-2">
            Limpar filtros
          </Button>
        </div>
      ) : (
        <div className="border rounded-lg overflow-hidden">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Colaborador</TableHead>
                <TableHead>EPI</TableHead>
                <TableHead className="text-center">Qtd</TableHead>
                <TableHead>Data Entrega</TableHead>
                <TableHead>Devolução Prevista</TableHead>
                <TableHead>Motivo</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="w-[100px]"></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {filtered.map((entrega, index) => (
                <motion.tr
                  key={entrega.id}
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ delay: index * 0.02 }}
                  className="border-b transition-colors hover:bg-muted/50"
                >
                  <TableCell>
                    <div>
                      <p className="font-medium">{entrega.colaborador_nome}</p>
                      {entrega.colaborador_cargo && (
                        <p className="text-xs text-muted-foreground">
                          {entrega.colaborador_cargo}
                          {entrega.colaborador_departamento &&
                            ` - ${entrega.colaborador_departamento}`}
                        </p>
                      )}
                    </div>
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <Package className="w-4 h-4 text-muted-foreground" />
                      <span>{entrega.epi.tipo.nome}</span>
                      {entrega.epi.tamanho && (
                        <Badge variant="outline" className="text-xs">
                          {entrega.epi.tamanho}
                        </Badge>
                      )}
                    </div>
                  </TableCell>
                  <TableCell className="text-center">
                    {entrega.quantidade}
                  </TableCell>
                  <TableCell>
                    {format(new Date(entrega.data_entrega), "dd/MM/yyyy", {
                      locale: ptBR,
                    })}
                  </TableCell>
                  <TableCell>
                    {entrega.data_devolucao_prevista ? (
                      <div className="flex items-center gap-1">
                        <Calendar className="w-4 h-4 text-muted-foreground" />
                        {format(
                          new Date(entrega.data_devolucao_prevista),
                          "dd/MM/yyyy",
                          { locale: ptBR }
                        )}
                      </div>
                    ) : (
                      "-"
                    )}
                  </TableCell>
                  <TableCell className="text-muted-foreground">
                    {entrega.motivo_entrega || "-"}
                  </TableCell>
                  <TableCell>
                    <Badge className={ENTREGA_STATUS_COLORS[entrega.status]}>
                      {ENTREGA_STATUS_LABELS[entrega.status]}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    {entrega.status === "ativa" && onDevolucao && (
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() =>
                          setDevolucaoModal({
                            open: true,
                            entregaId: entrega.id,
                            colaborador: entrega.colaborador_nome,
                          })
                        }
                      >
                        <RotateCcw className="w-4 h-4 mr-1" />
                        Devolver
                      </Button>
                    )}
                  </TableCell>
                </motion.tr>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      <Dialog
        open={devolucaoModal.open}
        onOpenChange={(open) =>
          setDevolucaoModal({ ...devolucaoModal, open })
        }
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Registrar Devolução</DialogTitle>
          </DialogHeader>
          <div className="py-4 space-y-4">
            <p className="text-sm text-muted-foreground">
              Registrar devolução do EPI de{" "}
              <strong>{devolucaoModal.colaborador}</strong>
            </p>
            <div className="space-y-2">
              <Label>Destino do EPI</Label>
              <div className="grid grid-cols-3 gap-2">
                <Button
                  type="button"
                  variant={destino === "estoque" ? "default" : "outline"}
                  size="sm"
                  className="gap-1.5"
                  onClick={() => setDestino("estoque")}
                >
                  <ArchiveRestore className="w-4 h-4" />
                  Estoque
                </Button>
                <Button
                  type="button"
                  variant={destino === "manutencao" ? "default" : "outline"}
                  size="sm"
                  className="gap-1.5"
                  onClick={() => setDestino("manutencao")}
                >
                  <Wrench className="w-4 h-4" />
                  Manutenção
                </Button>
                <Button
                  type="button"
                  variant={destino === "descarte" ? "default" : "outline"}
                  size="sm"
                  className="gap-1.5"
                  onClick={() => setDestino("descarte")}
                >
                  <Trash2 className="w-4 h-4" />
                  Descarte
                </Button>
              </div>
              {destino === "manutencao" && (
                <p className="text-xs text-muted-foreground bg-muted/50 p-2 rounded">
                  O EPI será enviado ao local "Em Manutenção" e ficará disponível para transferência quando reparado.
                </p>
              )}
              {destino === "descarte" && (
                <p className="text-xs text-muted-foreground bg-muted/50 p-2 rounded">
                  O EPI será descartado e não retornará ao estoque.
                </p>
              )}
            </div>
            <div className="space-y-2">
              <Label>Observações *</Label>
              <Textarea
                value={observacoes}
                onChange={(e) => setObservacoes(e.target.value)}
                placeholder="Descreva o estado do EPI e motivo da devolução (obrigatório)..."
                className={cn(!observacoes.trim() && "border-destructive/50")}
              />
              {!observacoes.trim() && (
                <p className="text-xs text-destructive">
                  Informe o estado do EPI e o motivo da devolução para manter a rastreabilidade conforme NR-06.
                </p>
              )}
            </div>
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() =>
                setDevolucaoModal({ open: false, entregaId: "", colaborador: "" })
              }
            >
              Cancelar
            </Button>
            <Button onClick={handleDevolucao} disabled={processando || !observacoes.trim()}>
              {processando ? "Processando..." : "Confirmar Devolução"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
