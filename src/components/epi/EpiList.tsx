import { useState } from "react";
import { motion } from "framer-motion";
import {
  Edit,
  Trash2,
  Package,
  AlertTriangle,
  Calendar,
  MoreHorizontal,
  Search,
} from "lucide-react";
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
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
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
import type { EpiCompleto } from "@/types/epi";
import { EPI_STATUS_LABELS, EPI_STATUS_COLORS } from "@/types/epi";
import { formatDateBR } from "@/lib/dataLocal";

interface EpiListProps {
  epis: EpiCompleto[];
  isLoading?: boolean;
  onEdit?: (epi: EpiCompleto) => void;
  onDelete?: (id: string) => Promise<void>;
  onAjustarEstoque?: (epi: EpiCompleto) => void;
}

export function EpiList({
  epis,
  isLoading,
  onEdit,
  onDelete,
  onAjustarEstoque,
}: EpiListProps) {
  const [search, setSearch] = useState("");
  const [deleteId, setDeleteId] = useState<string | null>(null);

  const filtered = epis.filter(
    (epi) =>
      epi.tipo.nome.toLowerCase().includes(search.toLowerCase()) ||
      epi.tipo.categoria?.toLowerCase().includes(search.toLowerCase()) ||
      epi.marca?.toLowerCase().includes(search.toLowerCase()) ||
      epi.modelo?.toLowerCase().includes(search.toLowerCase()) ||
      epi.codigo?.toLowerCase().includes(search.toLowerCase()) ||
      // O campo de busca sempre prometeu "nome, categoria, CA, marca ou
      // modelo" (placeholder abaixo), mas o CA nunca esteve no filtro —
      // procurar pelo número do CA não achava nada.
      epi.ca?.toLowerCase().includes(search.toLowerCase()) ||
      epi.tipo?.ca_numero?.toLowerCase().includes(search.toLowerCase())
  );

  const isVencido = (dataValidade: string | null) => {
    if (!dataValidade) return false;
    return new Date(dataValidade) < new Date();
  };

  const isEstoqueBaixo = (epi: EpiCompleto) => {
    return epi.quantidade_estoque <= epi.quantidade_minima;
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
      <div className="flex flex-col gap-4 p-5 bg-card border rounded-xl shadow-sm">
        <div className="flex items-center gap-2 mb-1">
          <Search className="h-4 w-4 text-primary" />
          <h3 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground">Pesquisa de Estoque</h3>
        </div>
        <div className="relative max-w-2xl">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Buscar por nome, categoria, CA, marca ou modelo..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-10 h-11 border-muted-foreground/20 focus-visible:ring-primary text-base"
          />
        </div>
      </div>

      {filtered.length === 0 ? (
        <div className="text-center py-12 text-muted-foreground">
          <Package className="w-12 h-12 mx-auto mb-4 opacity-50" />
          <p>Nenhum EPI encontrado</p>
        </div>
      ) : (
        <div className="border rounded-lg overflow-hidden">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Categoria</TableHead>
                <TableHead>Nome do EPI</TableHead>
                <TableHead>CA</TableHead>
                <TableHead>Marca / Modelo</TableHead>
                <TableHead>Tamanho</TableHead>
                <TableHead className="text-center">Estoque</TableHead>
                <TableHead>Validade</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="w-[50px]"></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {filtered.map((epi, index) => (
                <motion.tr
                  key={epi.id}
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ delay: index * 0.02 }}
                  className="border-b transition-colors hover:bg-muted/50"
                >
                  <TableCell>
                    {epi.tipo.categoria ? (
                      <Badge variant="secondary" className="text-xs font-normal">
                        {epi.tipo.categoria}
                      </Badge>
                    ) : (
                      <span className="text-muted-foreground">-</span>
                    )}
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <span className="font-medium">{epi.tipo.nome}</span>
                      {epi.codigo && (
                        <Badge variant="outline" className="text-xs">
                          {epi.codigo}
                        </Badge>
                      )}
                    </div>
                  </TableCell>
                  <TableCell className="text-muted-foreground">
                    {/* O cadastro grava o CA em epi_tipos.ca_numero, mas esta
                        lista sempre leu epis.ca — coluna que nenhuma tela
                        escrevia. Por isso o CA aparecia vazio mesmo tendo sido
                        digitado. Lê epis.ca primeiro para preservar as linhas
                        antigas que já o têm preenchido. */}
                    {epi.ca || epi.tipo?.ca_numero || "-"}
                  </TableCell>
                  <TableCell>
                    {epi.marca || "-"}
                    {epi.modelo && <span className="text-muted-foreground"> / {epi.modelo}</span>}
                  </TableCell>
                  <TableCell>{epi.tipo.controla_tamanho ? "Grade" : (epi.tamanho || "-")}</TableCell>
                  <TableCell className="text-center">
                    <div className="flex items-center justify-center gap-1">
                      {isEstoqueBaixo(epi) && (
                        <AlertTriangle className="w-4 h-4 text-orange-500" />
                      )}
                      <span
                        className={
                          isEstoqueBaixo(epi)
                            ? "text-orange-500 font-semibold"
                            : ""
                        }
                      >
                        {epi.quantidade_estoque}
                      </span>
                    </div>
                  </TableCell>
                  <TableCell>
                    {epi.data_validade ? (
                      <div className="flex items-center gap-1">
                        {isVencido(epi.data_validade) && (
                          <Calendar className="w-4 h-4 text-red-500" />
                        )}
                        <span
                          className={
                            isVencido(epi.data_validade)
                              ? "text-red-500 font-semibold"
                              : ""
                          }
                        >
                          {formatDateBR(epi.data_validade, "dd/MM/yyyy")}
                        </span>
                      </div>
                    ) : (
                      "-"
                    )}
                  </TableCell>
                  <TableCell>
                    <Badge className={EPI_STATUS_COLORS[epi.status]}>
                      {EPI_STATUS_LABELS[epi.status]}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    {(onEdit || onAjustarEstoque || onDelete) ? (
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <Button variant="ghost" size="icon">
                            <MoreHorizontal className="w-4 h-4" />
                          </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          {onEdit && (
                            <DropdownMenuItem onClick={() => onEdit(epi)}>
                              <Edit className="w-4 h-4 mr-2" />
                              Editar
                            </DropdownMenuItem>
                          )}
                          {onAjustarEstoque && (
                            <DropdownMenuItem onClick={() => onAjustarEstoque(epi)}>
                              <Package className="w-4 h-4 mr-2" />
                              Ajustar Estoque
                            </DropdownMenuItem>
                          )}
                          {onDelete && (
                            <DropdownMenuItem
                              onClick={() => setDeleteId(epi.id)}
                              className="text-red-600"
                            >
                              <Trash2 className="w-4 h-4 mr-2" />
                              Excluir
                            </DropdownMenuItem>
                          )}
                        </DropdownMenuContent>
                      </DropdownMenu>
                    ) : (
                      <span className="text-xs text-muted-foreground">—</span>
                    )}
                  </TableCell>
                </motion.tr>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      <AlertDialog open={!!deleteId} onOpenChange={() => setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Excluir EPI?</AlertDialogTitle>
            <AlertDialogDescription>
              Esta ação não pode ser desfeita. O EPI e todo seu histórico de
              entregas serão removidos permanentemente.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction
              onClick={async () => {
                if (deleteId && onDelete) {
                  await onDelete(deleteId);
                  setDeleteId(null);
                }
              }}
              className="bg-red-600 hover:bg-red-700"
            >
              Excluir
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
