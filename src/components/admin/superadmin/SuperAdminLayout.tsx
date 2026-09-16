import { Link, Outlet, useLocation, useNavigate } from "react-router-dom";
import { Shield, Plus, ArrowLeft, ChevronRight } from "lucide-react";
import {
  Sidebar, SidebarContent, SidebarFooter, SidebarGroup, SidebarGroupContent, SidebarGroupLabel,
  SidebarHeader, SidebarInset, SidebarMenu, SidebarMenuButton, SidebarMenuItem, SidebarProvider,
  SidebarRail, SidebarTrigger, useSidebar,
} from "@/components/ui/sidebar";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { SUPER_ADMIN_MENU, localizarItemDoMenu, type SuperAdminMenuItem } from "./superAdminMenu";

// Casca do Painel Super Admin: menu lateral agrupado por área (Painel,
// Clientes, Comercial e marketing, Produtos, A YourEyes, Qualidade e
// suporte) + barra superior com o caminho atual e o atalho "Nova Empresa".
// Todas as rotas /admin/* abrem dentro dela (ver App.tsx), então o menu
// permanece à vista ao trocar de seção — inclusive nas páginas que já
// tinham endereço próprio (QA, Blog, Contratos, Manual, Controle de Clientes).

function ItemDoMenu({ item, ativo }: { item: SuperAdminMenuItem; ativo: boolean }) {
  const { isMobile, setOpenMobile } = useSidebar();
  const Icon = item.icon;
  return (
    <SidebarMenuItem>
      <SidebarMenuButton asChild isActive={ativo} tooltip={item.label}>
        <Link
          to={item.path}
          data-testid={`menu-admin-${item.id}`}
          onClick={() => { if (isMobile) setOpenMobile(false); }}
        >
          <Icon />
          <span>{item.label}</span>
        </Link>
      </SidebarMenuButton>
    </SidebarMenuItem>
  );
}

export function SuperAdminLayout() {
  const location = useLocation();
  const navigate = useNavigate();
  const atual = localizarItemDoMenu(location.pathname);

  return (
    <SidebarProvider>
      <Sidebar collapsible="icon" className="print:hidden">
        <SidebarHeader className="border-b border-sidebar-border">
          <SidebarMenu>
            <SidebarMenuItem>
              <SidebarMenuButton asChild size="lg" tooltip="Painel Super Admin">
                <Link to="/admin" data-testid="menu-admin-inicio">
                  <div className="flex aspect-square size-8 items-center justify-center rounded-lg bg-sidebar-primary text-sidebar-primary-foreground">
                    <Shield className="size-4" />
                  </div>
                  <div className="grid flex-1 text-left text-sm leading-tight">
                    <span className="truncate font-semibold">Super Admin</span>
                    <span className="truncate text-xs opacity-70">YourEyes · operação da casa</span>
                  </div>
                </Link>
              </SidebarMenuButton>
            </SidebarMenuItem>
          </SidebarMenu>
        </SidebarHeader>

        <SidebarContent>
          {SUPER_ADMIN_MENU.map((area) => (
            <SidebarGroup key={area.id}>
              <SidebarGroupLabel>{area.label}</SidebarGroupLabel>
              <SidebarGroupContent>
                <SidebarMenu>
                  {area.items.map((item) => (
                    <ItemDoMenu key={item.id} item={item} ativo={atual?.item.id === item.id} />
                  ))}
                </SidebarMenu>
              </SidebarGroupContent>
            </SidebarGroup>
          ))}
        </SidebarContent>

        <SidebarFooter className="border-t border-sidebar-border">
          <SidebarMenu>
            <SidebarMenuItem>
              <SidebarMenuButton asChild tooltip="Voltar ao sistema">
                <Link to="/" data-testid="menu-admin-voltar">
                  <ArrowLeft />
                  <span>Voltar ao sistema</span>
                </Link>
              </SidebarMenuButton>
            </SidebarMenuItem>
          </SidebarMenu>
        </SidebarFooter>
        <SidebarRail />
      </Sidebar>

      <SidebarInset className="min-w-0">
        <header className="flex h-14 shrink-0 items-center gap-2 border-b bg-background px-3 md:px-4 print:hidden">
          <SidebarTrigger className="-ml-1" title="Mostrar ou esconder o menu" />
          <Separator orientation="vertical" className="mr-1 h-5" />
          <nav aria-label="Caminho" className="flex min-w-0 items-center gap-1 text-sm">
            <Shield className="hidden h-4 w-4 shrink-0 text-primary sm:block" />
            <span className="hidden text-muted-foreground sm:inline">Super Admin</span>
            {atual && (
              <>
                <ChevronRight className="hidden h-4 w-4 shrink-0 text-muted-foreground sm:block" />
                <span className="hidden text-muted-foreground md:inline">{atual.area.label}</span>
                <ChevronRight className="hidden h-4 w-4 shrink-0 text-muted-foreground md:block" />
                <span className="truncate font-medium" data-testid="admin-secao-atual">{atual.item.label}</span>
              </>
            )}
          </nav>
          <div className="ml-auto flex items-center gap-2">
            <Button size="sm" onClick={() => navigate("/admin/empresas?nova=1")} data-testid="admin-nova-empresa">
              <Plus className="h-4 w-4 md:mr-2" />
              <span className="hidden md:inline">Nova Empresa</span>
            </Button>
          </div>
        </header>
        <Outlet />
      </SidebarInset>
    </SidebarProvider>
  );
}
