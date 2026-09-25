import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import type { PerfilAcesso } from "@/hooks/usePerfisAcesso";
import {
  MoreVertical, Pencil, Copy, Power, Users, ShieldCheck,
  User, UserCheck, DollarSign, HardHat, Briefcase, ClipboardList,
  Lock, AlertTriangle, ShieldAlert, Eye,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";

const ICON_MAP: Record<string, React.ElementType> = {
  ShieldCheck, User, UserCheck, Users, DollarSign, HardHat, Briefcase, ClipboardList, Lock,
};

const RISCO_CONFIG = {
  normal: { label: "Normal", class: "text-emerald-600 border-emerald-200 bg-emerald-50 dark:bg-emerald-950/30", icon: null },
  elevado: { label: "Elevado", class: "text-amber-600 border-amber-200 bg-amber-50 dark:bg-amber-950/30", icon: AlertTriangle },
  critico: { label: "Crítico", class: "text-red-600 border-red-200 bg-red-50 dark:bg-red-950/30", icon: ShieldAlert },
};

interface PerfilCardProps {
  perfil: PerfilAcesso;
  onEdit: (perfil: PerfilAcesso) => void;
  onClone: (perfil: PerfilAcesso) => void;
  onToggleStatus: (id: string, ativo: boolean) => void;
  onVerVinculos: (perfil: PerfilAcesso) => void;
  onSimular?: (perfil: PerfilAcesso) => void;
  /**
   * Contagem de usuários calculada ao vivo a partir dos vínculos ativos.
   * Quando informada, tem prioridade sobre o campo armazenado
   * `perfil.total_usuarios`, que pode estar defasado (o contador do banco
   * derivava por causa de gatilho duplicado/incremental).
   */
  usuariosCount?: number;
}

export function PerfilCard({ perfil, onEdit, onClone, onToggleStatus, onVerVinculos, onSimular, usuariosCount }: PerfilCardProps) {
  const Icon = perfil.icone ? (ICON_MAP[perfil.icone] || ShieldCheck) : ShieldCheck;
  const totalUsuarios = usuariosCount ?? perfil.total_usuarios ?? 0;
  const modulosCount = perfil.permissoes
    ? new Set(perfil.permissoes.map((p) => p.modulo)).size
    : 0;
  const permSensiveis = perfil.permissoes?.filter((p) => (p as any).is_sensivel).length || 0;
  const risco = perfil.nivel_risco || "normal";
  const riscoConfig = RISCO_CONFIG[risco];
  const RiscoIcon = riscoConfig.icon;
  const expirado = perfil.expira_em && new Date(perfil.expira_em) < new Date();

  return (
    <Card className={cn(
      "relative transition-all duration-200 hover:shadow-md border group",
      !perfil.ativo && "opacity-60",
      risco === "critico" && "border-red-200 dark:border-red-800/50",
      risco === "elevado" && "border-amber-200 dark:border-amber-800/50",
    )}>
      {/* Barra de risco */}
      {risco !== "normal" && (
        <div className={cn("h-0.5 w-full rounded-t-xl", risco === "critico" ? "bg-red-400" : "bg-amber-400")} />
      )}
      <CardHeader className="pb-2">
        <div className="flex items-start justify-between gap-2">
          <div className="flex items-center gap-3">
            <div
              className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0"
              style={{ backgroundColor: (perfil.cor || "#6366f1") + "22", border: `1.5px solid ${perfil.cor || "#6366f1"}44` }}
            >
              <Icon className="w-5 h-5" style={{ color: perfil.cor || "#6366f1" }} />
            </div>
            <div className="min-w-0">
              <p className="font-semibold text-foreground text-[14px] leading-tight truncate">{perfil.nome}</p>
              <div className="flex items-center gap-1 flex-wrap mt-0.5">
                <Badge
                  variant="outline"
                  className="text-[10px] px-1.5 py-0 h-4"
                  style={{ color: perfil.cor || "#6366f1", borderColor: (perfil.cor || "#6366f1") + "55" }}
                >
                  {perfil.tipo === "clonado" ? "Clonado" : perfil.tipo === "padrao_sistema" ? "Padrão" : "Personalizado"}
                </Badge>
                {!perfil.ativo && <Badge variant="outline" className="text-[10px] px-1.5 py-0 h-4 text-muted-foreground">Inativo</Badge>}
                {perfil.is_perfil_assistido && <Badge variant="outline" className="text-[10px] px-1.5 py-0 h-4 text-muted-foreground">Assistido</Badge>}
                {expirado && <Badge variant="outline" className="text-[10px] px-1.5 py-0 h-4 text-red-600 border-red-200">Expirado</Badge>}
              </div>
            </div>
          </div>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon" className="h-7 w-7 opacity-0 group-hover:opacity-100 transition-opacity">
                <MoreVertical className="w-4 h-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onClick={() => onEdit(perfil)}>
                <Pencil className="w-4 h-4 mr-2" /> Editar permissões
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => onClone(perfil)}>
                <Copy className="w-4 h-4 mr-2" /> Duplicar
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => onVerVinculos(perfil)}>
                <Users className="w-4 h-4 mr-2" /> Gerenciar usuários
              </DropdownMenuItem>
              {onSimular && (
                <DropdownMenuItem onClick={() => onSimular(perfil)}>
                  <Eye className="w-4 h-4 mr-2" /> Simular acesso
                </DropdownMenuItem>
              )}
              <DropdownMenuSeparator />
              <DropdownMenuItem
                onClick={() => onToggleStatus(perfil.id, !perfil.ativo)}
                className={perfil.ativo ? "text-destructive" : "text-emerald-600"}
              >
                <Power className="w-4 h-4 mr-2" />
                {perfil.ativo ? "Desativar" : "Ativar"}
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </CardHeader>
      <CardContent className="pt-0 space-y-2">
        {perfil.descricao && (
          <p className="text-[12px] text-muted-foreground line-clamp-2">{perfil.descricao}</p>
        )}

        {/* Risco badge */}
        {risco !== "normal" && (
          <div className={cn("flex items-center gap-1 text-[11px] px-2 py-1 rounded-md border", riscoConfig.class)}>
            {RiscoIcon && <RiscoIcon className="w-3 h-3 flex-shrink-0" />}
            <span>Risco {riscoConfig.label}</span>
            {permSensiveis > 0 && <span className="ml-auto">{permSensiveis} perm. sensíveis</span>}
          </div>
        )}

        {/* Expiração */}
        {perfil.expira_em && (
          <p className={cn("text-[11px]", expirado ? "text-red-500" : "text-muted-foreground")}>
            {expirado ? "Expirou em" : "Expira em"}: {format(new Date(perfil.expira_em), "dd/MM/yyyy", { locale: ptBR })}
          </p>
        )}

        <div className="flex items-center justify-between pt-1 border-t border-border/50">
          <Tooltip>
            <TooltipTrigger asChild>
              <button
                onClick={() => onVerVinculos(perfil)}
                className="flex items-center gap-1.5 text-[12px] text-muted-foreground hover:text-foreground transition-colors"
              >
                <Users className="w-3.5 h-3.5" />
                <span>{totalUsuarios} usuário{totalUsuarios !== 1 ? "s" : ""}</span>
              </button>
            </TooltipTrigger>
            <TooltipContent>Usuários com este perfil</TooltipContent>
          </Tooltip>
          <span className="text-[11px] text-muted-foreground/60">
            {modulosCount} módulo{modulosCount !== 1 ? "s" : ""}
          </span>
        </div>
      </CardContent>
    </Card>
  );
}
