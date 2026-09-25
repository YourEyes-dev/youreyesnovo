import { useState, useCallback, useEffect } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  ChevronRight,
  ChevronDown,
  Folder,
  FolderOpen,
  Building2,
  Building,
  Users,
  User,
  Calendar,
  FileText,
  Plus,
  MoreHorizontal,
  Pencil,
  Trash2,
  FolderPlus,
  Scale,
  FileCheck,
  Award,
  Shield,
  Heart,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import type { DocumentoPastaNode, DocumentoItem } from "@/types/documentoPasta";

const iconMap: Record<string, React.ComponentType<{ className?: string }>> = {
  Building2,
  Building,
  Users,
  User,
  Calendar,
  FileText,
  Folder,
  FolderOpen,
  Scale,
  FileCheck,
  Award,
  Shield,
  Heart,
};

interface PastaTreeViewProps {
  tree: DocumentoPastaNode[];
  selectedPastaId: string | null;
  onSelectPasta: (pasta: DocumentoPastaNode | null) => void;
  onCreateSubfolder: (parentId: string) => void;
  onRenamePasta: (pasta: DocumentoPastaNode) => void;
  onDeletePasta: (pastaId: string) => void;
  onDropDocument?: (documentoId: string, pastaDestinoId: string) => void;
  expandAllSignal?: { expand: boolean; key: number };
}

export function PastaTreeView({
  tree,
  selectedPastaId,
  onSelectPasta,
  onCreateSubfolder,
  onRenamePasta,
  onDeletePasta,
  onDropDocument,
  expandAllSignal,
}: PastaTreeViewProps) {
  return (
    <div className="space-y-1">
      {tree.map((node) => (
        <PastaNode
            key={node.id}
            node={node}
            level={0}
            selectedPastaId={selectedPastaId}
            onSelectPasta={onSelectPasta}
            onCreateSubfolder={onCreateSubfolder}
            onRenamePasta={onRenamePasta}
            onDeletePasta={onDeletePasta}
            onDropDocument={onDropDocument}
            expandAllSignal={expandAllSignal}
          />
      ))}
    </div>
  );
}

interface PastaNodeProps {
  node: DocumentoPastaNode;
  level: number;
  selectedPastaId: string | null;
  onSelectPasta: (pasta: DocumentoPastaNode | null) => void;
  onCreateSubfolder: (parentId: string) => void;
  onRenamePasta: (pasta: DocumentoPastaNode) => void;
  onDeletePasta: (pastaId: string) => void;
  onDropDocument?: (documentoId: string, pastaDestinoId: string) => void;
  expandAllSignal?: { expand: boolean; key: number };
}

function PastaNode({
  node,
  level,
  selectedPastaId,
  onSelectPasta,
  onCreateSubfolder,
  onRenamePasta,
  onDeletePasta,
  onDropDocument,
  expandAllSignal,
}: PastaNodeProps) {
  const isVirtual = !!node.isVirtual;
  const [expanded, setExpanded] = useState(level < 2 && !isVirtual);

  useEffect(() => {
    if (expandAllSignal && expandAllSignal.key > 0) {
      setExpanded(expandAllSignal.expand);
    }
  }, [expandAllSignal]);
  const [isDragOver, setIsDragOver] = useState(false);
  
  const hasChildren = node.children.length > 0;
  const hasDocuments = node.documentos.length > 0;
  const isSelected = selectedPastaId === node.id;
  
  const IconComponent = node.icone && iconMap[node.icone] 
    ? iconMap[node.icone] 
    : expanded ? FolderOpen : Folder;

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(false);
  }, []);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(false);
    
    const documentoId = e.dataTransfer.getData("documentoId");
    if (documentoId && onDropDocument) {
      onDropDocument(documentoId, node.id);
    }
  }, [node.id, onDropDocument]);

  const totalDocs = node.documentos.length;
  const vencidos = node.documentos.filter(d => d.status === "vencido").length;
  const vencendo = node.documentos.filter(d => d.status === "vencendo").length;

  return (
    <div>
      <div
        className={cn(
          "flex items-center gap-1 px-2 py-1.5 rounded-lg cursor-pointer transition-colors group",
          isSelected && "bg-primary/10 text-primary",
          isDragOver && "bg-primary/20 ring-2 ring-primary/50",
          isVirtual && "bg-muted/30 text-muted-foreground italic",
          !isSelected && !isDragOver && !isVirtual && "hover:bg-muted/50",
          !isSelected && !isDragOver && isVirtual && "hover:bg-muted/50"
        )}
        style={{ paddingLeft: `${level * 16 + 8}px` }}
        onClick={() => isVirtual ? setExpanded(!expanded) : onSelectPasta(node)}
        onDragOver={isVirtual ? undefined : handleDragOver}
        onDragLeave={isVirtual ? undefined : handleDragLeave}
        onDrop={isVirtual ? undefined : handleDrop}
      >
        {/* Expand/Collapse button */}
        <button
          className="p-0.5 hover:bg-muted rounded"
          onClick={(e) => {
            e.stopPropagation();
            setExpanded(!expanded);
          }}
        >
          {hasChildren || hasDocuments ? (
            expanded ? (
              <ChevronDown className="w-4 h-4 text-muted-foreground" />
            ) : (
              <ChevronRight className="w-4 h-4 text-muted-foreground" />
            )
          ) : (
            <span className="w-4" />
          )}
        </button>

        {/* Icon */}
        <IconComponent className={cn(
          "w-4 h-4",
          node.tipo === "root" && "text-primary",
          node.tipo === "unidade" && "text-primary/80",
          node.tipo === "colaborador" && "text-success",
          node.tipo === "ano" && "text-warning",
          node.tipo === "mes" && "text-primary/70",
          node.tipo === "categoria" && "text-warning",
        )} />

        {/* Name */}
        <span className="flex-1 text-sm truncate font-medium">
          {node.nome}
        </span>

        {/* Badge counts */}
        {totalDocs > 0 && (
          <div className="flex items-center gap-1">
            {vencidos > 0 && (
              <Badge variant="destructive" className="text-[10px] px-1.5 py-0">
                {vencidos}
              </Badge>
            )}
            {vencendo > 0 && (
              <Badge variant="outline" className="text-[10px] px-1.5 py-0 border-warning text-warning">
                {vencendo}
              </Badge>
            )}
            <Badge variant="secondary" className="text-[10px] px-1.5 py-0">
              {totalDocs}
            </Badge>
          </div>
        )}

        {/* Actions menu — desabilitado em nós virtuais (agrupadores A-Z) */}
        {!isVirtual && (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                variant="ghost"
                size="icon"
                className="h-6 w-6 opacity-0 group-hover:opacity-100"
                onClick={(e) => e.stopPropagation()}
              >
                <MoreHorizontal className="w-3.5 h-3.5" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-48">
              <DropdownMenuItem onClick={() => onCreateSubfolder(node.id)}>
                <FolderPlus className="w-4 h-4 mr-2" />
                Nova Subpasta
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => onRenamePasta(node)}>
                <Pencil className="w-4 h-4 mr-2" />
                Renomear
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                className="text-destructive"
                onClick={() => onDeletePasta(node.id)}
              >
                <Trash2 className="w-4 h-4 mr-2" />
                Excluir
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </div>

      {/* Children */}
      <AnimatePresence>
        {expanded && (hasChildren || hasDocuments) && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.2 }}
          >
            {node.children.map((child) => (
              <PastaNode
                key={child.id}
                node={child}
                level={level + 1}
                selectedPastaId={selectedPastaId}
                onSelectPasta={onSelectPasta}
                onCreateSubfolder={onCreateSubfolder}
                onRenamePasta={onRenamePasta}
                onDeletePasta={onDeletePasta}
                onDropDocument={onDropDocument}
                expandAllSignal={expandAllSignal}
              />
            ))}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
