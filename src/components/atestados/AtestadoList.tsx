import { useState } from "react";
import { format, parseISO } from "date-fns";
import { useAfastamentosAtivos } from "@/hooks/useAfastamentosAtivos";
import { AfastadoBadge } from "@/components/shared/AfastadoBadge";
import { ptBR } from "date-fns/locale";
import { motion } from "framer-motion";
import { 
  FileText, 
  Calendar, 
  User, 
  Building2, 
  MoreVertical,
  Download,
  Trash2,
  Eye,
  Pencil,
  Stethoscope
} from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
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
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { 
  Atestado, 
  AtestadoTipo,
  GrupoClinico 
} from "@/types/atestado";
import { 
  AFASTAMENTO_TIPO_LABELS,
  SUBTIPO_LICENCAS_LABELS,
  SUBTIPO_ATESTADOS_LABELS,
  SUBTIPO_OCUPACIONAL_LABELS,
  GRUPO_CLINICO_LABELS,
  GRUPO_CLINICO_COLORS,
  APTIDAO_LABELS,
  APTIDAO_COLORS,
  type AfastamentoTipo
} from "@/types/atestado";

interface AtestadoListProps {
  atestados: Atestado[];
  onDelete: (atestado: Atestado) => Promise<void>;
  onView?: (atestado: Atestado) => void;
  onEdit?: (atestado: Atestado) => void;
  onDownload: (storagePath: string, bucket?: string) => Promise<string | null>;
  deleting?: boolean;
}

export function AtestadoList({ 
  atestados, 
  onDelete, 
  onView,
  onEdit,
  onDownload,
  deleting 
}: AtestadoListProps) {
  const [search, setSearch] = useState("");
  const [tipoFilter, setTipoFilter] = useState<string>("all");
  const [grupoFilter, setGrupoFilter] = useState<string>("all");
  const [deleteTarget, setDeleteTarget] = useState<Atestado | null>(null);
  const { getAfastamento } = useAfastamentosAtivos();

  const filteredAtestados = atestados.filter((atestado) => {
    const matchesSearch = 
      atestado.colaborador_nome.toLowerCase().includes(search.toLowerCase()) ||
      atestado.profissional_nome.toLowerCase().includes(search.toLowerCase());
    
    // Na página de afastamentos (atestados), não mostrar ocupacionais por padrão
    const isAtestadosPage = window.location.pathname.includes('atestados');
    const isOcupacionalPage = window.location.pathname.includes('saude-ocupacional');

    let matchesTipo = true;
    if (tipoFilter === "all") {
      if (isAtestadosPage) {
        matchesTipo = atestado.tipo !== 'ocupacional';
      } else if (isOcupacionalPage) {
        matchesTipo = atestado.tipo === 'ocupacional';
      }
    } else {
      matchesTipo = atestado.tipo === tipoFilter;
    }

    const matchesGrupo = grupoFilter === "all" || atestado.grupo_clinico === grupoFilter;

    return matchesSearch && matchesTipo && matchesGrupo;
  });

  const handleDownload = async (atestado: Atestado) => {
    if (!atestado.arquivo_url) return;
    const url = await onDownload(atestado.arquivo_url, atestado.arquivo_bucket || "atestados");
    if (url) {
      window.open(url, "_blank");
    }
  };

  const handleConfirmDelete = async () => {
    if (deleteTarget) {
      await onDelete(deleteTarget);
      setDeleteTarget(null);
    }
  };

  const getSubtipoLabel = (atestado: Atestado) => {
    if (atestado.tipo === 'licencas' && atestado.subtipo_assistencial) {
      return SUBTIPO_LICENCAS_LABELS[atestado.subtipo_assistencial as keyof typeof SUBTIPO_LICENCAS_LABELS] || 'Licença';
    }
    if (atestado.tipo === 'atestados' && atestado.subtipo_assistencial) {
      return SUBTIPO_ATESTADOS_LABELS[atestado.subtipo_assistencial as keyof typeof SUBTIPO_ATESTADOS_LABELS] || 'Atestado';
    }
    if (atestado.tipo === 'ocupacional' && atestado.subtipo_ocupacional) {
      return SUBTIPO_OCUPACIONAL_LABELS[atestado.subtipo_ocupacional as keyof typeof SUBTIPO_OCUPACIONAL_LABELS] || 'Ocupacional';
    }
    return AFASTAMENTO_TIPO_LABELS[atestado.tipo as AfastamentoTipo] || atestado.tipo;
  };

  const gruposClinicos = [...new Set(atestados.map(a => a.grupo_clinico).filter(Boolean))] as GrupoClinico[];

  if (atestados.length === 0) {
    return (
      <div className="text-center py-12">
        <FileText className="h-12 w-12 text-muted-foreground mx-auto mb-4" />
        <h3 className="text-lg font-medium">Nenhum atestado cadastrado</h3>
        <p className="text-muted-foreground mt-1">
          Clique em "Novo Atestado" para começar
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Filters */}
      <div className="flex flex-col sm:flex-row gap-3">
        <Input
          placeholder="Buscar por colaborador ou profissional..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="flex-1"
        />
        <Select value={tipoFilter} onValueChange={setTipoFilter}>
          <SelectTrigger className="w-full sm:w-[180px]">
            <SelectValue placeholder="Tipo" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Todos os tipos</SelectItem>
            <SelectItem value="atestados">Atestados Médicos</SelectItem>
            <SelectItem value="licencas">Licenças</SelectItem>
            <SelectItem value="ocupacional">Ocupacional</SelectItem>
          </SelectContent>
        </Select>
        <Select value={grupoFilter} onValueChange={setGrupoFilter}>
          <SelectTrigger className="w-full sm:w-[180px]">
            <SelectValue placeholder="Grupo Clínico" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Todos os grupos</SelectItem>
            {gruposClinicos.map((grupo) => (
              <SelectItem key={grupo} value={grupo}>
                {GRUPO_CLINICO_LABELS[grupo]}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {/* List */}
      <div className="space-y-3">
        {filteredAtestados.map((atestado, index) => (
          <motion.div
            key={atestado.id}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: index * 0.03 }}
          >
            <Card className="hover:shadow-lg transition-all duration-300 border-l-4 border-l-primary/30 group overflow-hidden relative">
              <div className="absolute top-0 right-0 w-32 h-32 bg-primary/5 rounded-full -mr-16 -mt-16 transition-all group-hover:scale-110 duration-500" />
              <CardContent className="p-4 md:p-5 relative">
                <div className="flex flex-col sm:flex-row sm:items-start justify-between gap-4">
                  <div className="flex-1 min-w-0 space-y-2">
                    {/* Header */}
                    <div className="flex flex-wrap items-center gap-2">
                      <Badge variant={atestado.tipo === 'atestados' ? 'default' : 'secondary'}>
                        {getSubtipoLabel(atestado)}
                      </Badge>
                      {atestado.grupo_clinico && (
                        <Badge 
                          variant="outline" 
                          className={GRUPO_CLINICO_COLORS[atestado.grupo_clinico]}
                        >
                          {GRUPO_CLINICO_LABELS[atestado.grupo_clinico]}
                        </Badge>
                      )}
                      {atestado.aptidao && (
                        <Badge 
                          variant="outline"
                          className={APTIDAO_COLORS[atestado.aptidao]}
                        >
                          {APTIDAO_LABELS[atestado.aptidao]}
                        </Badge>
                      )}
                    </div>

                    {/* Info */}
                    <div className="flex flex-col sm:flex-row sm:items-center gap-1 sm:gap-4 text-sm">
                      <div className="flex items-center gap-1.5 text-foreground font-medium">
                        <User className="h-4 w-4 text-muted-foreground" />
                        <span className="truncate">{atestado.colaborador_nome}</span>
                        {atestado.tipo !== 'atestados' && (
                          <AfastadoBadge
                            afastamento={getAfastamento({ cpf: atestado.colaborador_cpf, nome: atestado.colaborador_nome })}
                            compact
                            labelOverride={
                              atestado.tipo === 'licencas'
                                ? 'Licença'
                                : atestado.tipo === 'ocupacional'
                                  ? 'Ocupacional'
                                  : undefined
                            }
                          />
                        )}

                      </div>
                      {atestado.colaborador_departamento && (
                        <div className="flex items-center gap-1.5 text-muted-foreground">
                          <Building2 className="h-3.5 w-3.5" />
                          <span className="truncate">{atestado.colaborador_departamento}</span>
                        </div>
                      )}
                    </div>

                    {/* Dates and professional */}
                    <div className="flex flex-col sm:flex-row sm:items-center gap-1 sm:gap-4 text-xs text-muted-foreground">
                      <div className="flex items-center gap-1.5">
                        <Calendar className="h-3.5 w-3.5" />
                        <span>
                          Emissão: {format(parseISO(atestado.data_emissao), "dd/MM/yyyy", { locale: ptBR })}
                        </span>
                      </div>
                      {atestado.dias_afastamento && atestado.dias_afastamento > 0 && (
                        <span className="font-medium text-orange-600 dark:text-orange-400">
                          {atestado.dias_afastamento} dia{atestado.dias_afastamento > 1 ? 's' : ''} de afastamento
                        </span>
                      )}
                      <div className="flex items-center gap-1.5">
                        <Stethoscope className="h-3.5 w-3.5" />
                        <span className="truncate">
                          {atestado.profissional_nome} ({atestado.profissional_registro})
                        </span>
                      </div>
                    </div>
                  </div>

                  {/* Actions */}
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button variant="ghost" size="icon" className="flex-shrink-0 self-end sm:self-auto">
                        <MoreVertical className="h-4 w-4" />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      {onView && (
                        <DropdownMenuItem onClick={() => onView(atestado)}>
                          <Eye className="h-4 w-4 mr-2" />
                          Ver detalhes
                        </DropdownMenuItem>
                      )}
                      {onEdit && (
                        <DropdownMenuItem onClick={() => onEdit(atestado)}>
                          <Pencil className="h-4 w-4 mr-2" />
                          Ver / Editar registro
                        </DropdownMenuItem>
                      )}
                      {atestado.arquivo_url && (
                        <DropdownMenuItem onClick={() => handleDownload(atestado)}>
                          <Download className="h-4 w-4 mr-2" />
                          Baixar arquivo
                        </DropdownMenuItem>
                      )}
                      <DropdownMenuItem 
                        onClick={() => setDeleteTarget(atestado)}
                        className="text-destructive focus:text-destructive"
                      >
                        <Trash2 className="h-4 w-4 mr-2" />
                        Excluir
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>
              </CardContent>
            </Card>
          </motion.div>
        ))}
      </div>

      {filteredAtestados.length === 0 && atestados.length > 0 && (
        <div className="text-center py-8 text-muted-foreground">
          Nenhum atestado encontrado com os filtros aplicados
        </div>
      )}

      {/* Delete confirmation */}
      <AlertDialog open={!!deleteTarget} onOpenChange={() => setDeleteTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Excluir atestado?</AlertDialogTitle>
            <AlertDialogDescription>
              Esta ação não pode ser desfeita. O atestado e seu arquivo serão removidos permanentemente.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction 
              onClick={handleConfirmDelete}
              disabled={deleting}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {deleting ? "Excluindo..." : "Excluir"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
