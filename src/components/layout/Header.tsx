import { useState } from "react";
import { Bell, ChevronDown, LogOut, Menu, User, Settings, Shield, Smile, Store } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";

import { useAuthContext } from "@/contexts/AuthContext";
import { useTenant } from "@/hooks/useTenant";
import { useNavigate } from "react-router-dom";
import { EmpresaSelector } from "@/components/layout/EmpresaSelector";

import { useHumorDiario } from "@/hooks/useHumorDiario";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import type { AppRole } from "@/types/database";

const roleLabels: Record<string, string> = {
  superadmin: "Super Admin",
  owner: "Proprietário",
  admin: "Administrador",
  manager: "Gestor",
  user: "Colaborador",
};

function getRoleLabel(roles: AppRole[]): string {
  const hierarchy: AppRole[] = ["superadmin", "owner", "admin", "manager", "user"];
  for (const r of hierarchy) {
    if (roles.includes(r)) return roleLabels[r] || r;
  }
  return "Administrador";
}

interface HeaderProps {
  onMenuToggle?: () => void;
  isMobile?: boolean;
  isSidebarCollapsed?: boolean;
  onSidebarToggle?: () => void;
}


export const Header = ({ onMenuToggle, isMobile, isSidebarCollapsed, onSidebarToggle }: HeaderProps) => {
  const { profile, signOut, isSuperAdmin, user, roles, parceiroId, especialistaId } = useAuthContext();
  const { tenant } = useTenant();
  const { humorHoje } = useHumorDiario();
  const navigate = useNavigate();

  const handleSignOut = async () => {
    await signOut();
    navigate("/login");
  };

  const getInitials = (name: string) => {
    return name
      .split(" ")
      .map((n) => n[0])
      .join("")
      .substring(0, 2)
      .toUpperCase();
  };

  return (
    <header className="h-16 border-b border-border px-4 md:px-6 flex items-center justify-between sticky top-0 z-30" style={{ background: 'linear-gradient(135deg, hsl(215 65% 12%) 0%, hsl(207 90% 39%) 50%, hsl(152 66% 39%) 100%)' }}>
      <div className="flex items-center gap-2">
        {isMobile ? (
          <Button variant="ghost" size="icon" onClick={onMenuToggle} className="mr-1 text-white hover:bg-white/15">
            <Menu className="w-5 h-5" />
          </Button>
        ) : (
          <Button 
            variant="ghost" 
            size="icon" 
            onClick={onSidebarToggle} 
            className="text-white/80 hover:text-white hover:bg-white/15 transition-all"
            title={isSidebarCollapsed ? "Expandir menu" : "Recolher menu"}
          >
            <Menu className="w-5 h-5" />
          </Button>
        )}
      </div>


      {/* Actions */}
      <div className="flex items-center gap-2 md:gap-4">
        {/* Super Admin indicator */}
        {isSuperAdmin && (
          <Button
            variant="outline"
            size="sm"
            onClick={() => navigate("/admin")}
            className="hidden md:flex items-center gap-2 bg-white text-primary border-white hover:bg-white/90 hover:text-primary font-semibold shadow-sm"
          >
            <Shield className="w-4 h-4" />
            Super Admin
          </Button>
        )}

        {/* MarketYE (marketplace de serviços) - acesso global; antigo "Rede de Parceiros".
            Laranja da paleta (--brand-orange), para se destacar do azul do cabeçalho. */}
        <Tooltip>
          <TooltipTrigger asChild>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => window.open(`${import.meta.env.BASE_URL.replace(/\/$/, "")}/marketplace`, "_blank", "noopener,noreferrer")}
              className="flex items-center gap-2 bg-[hsl(var(--brand-orange))] text-white hover:bg-[hsl(var(--brand-orange)/0.85)] hover:text-white font-semibold shadow-sm"
            >
              <Store className="w-5 h-5" />
              <span className="hidden lg:inline text-sm font-medium" data-testid="header-marketye">MarketYE</span>
            </Button>
          </TooltipTrigger>
          <TooltipContent>MarketYE — marketplace de serviços</TooltipContent>
        </Tooltip>

        {/* Empresa Selector */}
        <EmpresaSelector />



        {/* Humor indicator - always clickable to change */}
        <Tooltip>
          <TooltipTrigger asChild>
            <button
              onClick={() => {
                const today = new Date().toISOString().split("T")[0];
                localStorage.removeItem(`humor_morning_${user?.id}_${today}`);
                localStorage.removeItem(`humor_lastshown_${user?.id}`);
                window.dispatchEvent(new Event("humor-reopen"));
              }}
              className="text-white/70 hover:text-white transition-colors"
            >
              {humorHoje ? (
                <span className="text-xl select-none">{humorHoje.emoji}</span>
              ) : (
                <Smile className="w-5 h-5" />
              )}
            </button>
          </TooltipTrigger>
          <TooltipContent>
            {humorHoje ? `Humor: ${humorHoje.humor} — clique para alterar` : "Registrar humor do dia"}
          </TooltipContent>
        </Tooltip>

        {/* Notifications */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon" className="relative text-white/80 hover:text-white hover:bg-white/15">
              <Bell className="w-5 h-5" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-80">
            <DropdownMenuLabel>Notificações</DropdownMenuLabel>
            <DropdownMenuSeparator />
            <div className="flex flex-col items-center justify-center py-8 text-center">
              <Bell className="w-8 h-8 text-muted-foreground/20 mb-2" />
              <p className="text-sm text-muted-foreground">Nenhuma notificação</p>
            </div>
          </DropdownMenuContent>
        </DropdownMenu>

        {/* User Menu */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" className="flex items-center gap-2 md:gap-3 pl-2 pr-2 md:pr-3 hover:bg-white/15">
              <Avatar className="h-8 w-8">
                <AvatarImage src={profile?.avatar_url || ""} />
                <AvatarFallback className="bg-primary text-primary-foreground text-sm">
                  {profile?.nome_completo ? getInitials(profile.nome_completo) : "U"}
                </AvatarFallback>
              </Avatar>
              <div className="hidden md:block text-left">
                <p className="text-sm font-medium text-white">
                  {profile?.nome_completo?.split(" ")[0] || "Usuário"}
                </p>
                <p className="text-xs text-white/70">
                  {profile?.cargo || (isSuperAdmin ? "Super Admin" : getRoleLabel(roles))}
                </p>
              </div>
              <ChevronDown className="w-4 h-4 text-white/70 hidden md:block" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-48">
            <DropdownMenuLabel>
              {profile?.nome_completo || "Minha Conta"}
            </DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuItem onClick={() => navigate("/meu-perfil")}>
              <User className="w-4 h-4 mr-2" />
              Perfil
            </DropdownMenuItem>
            {parceiroId && (
              <DropdownMenuItem onClick={() => navigate("/parceiro")}>
                <Store className="w-4 h-4 mr-2" />
                Área do Parceiro
              </DropdownMenuItem>
            )}
            {especialistaId && (
              <DropdownMenuItem onClick={() => navigate("/marketye/portal")}>
                <Store className="w-4 h-4 mr-2" />
                Portal do Especialista (MarketYE)
              </DropdownMenuItem>
            )}
            <DropdownMenuSeparator />
            <DropdownMenuItem onClick={handleSignOut} className="text-destructive">
              <LogOut className="w-4 h-4 mr-2" />
              Sair
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </header>
  );
};
