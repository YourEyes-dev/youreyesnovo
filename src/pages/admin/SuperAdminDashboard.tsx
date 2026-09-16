import type { ComponentType } from "react";
import { Link, Navigate, useLocation, useSearchParams } from "react-router-dom";
import { ChevronRight } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { LandingLeadsTable } from "@/components/admin/LandingLeadsTable";
import { SuperAdminOverview } from "@/components/admin/superadmin/SuperAdminOverview";
import { LeadsCRMKanban } from "@/components/admin/superadmin/LeadsCRMKanban";
import { TenantsStatusPanel, UsuariosGlobalPanel } from "@/components/admin/superadmin/PanelTenantsUsuarios";
import { TenantsPanel } from "@/components/admin/superadmin/TenantsPanel";
import { PsicossocialSuperAdminPanel } from "@/components/admin/superadmin/PsicossocialSuperAdminPanel";
import { PrecosAddonsPanel } from "@/components/admin/superadmin/PrecosAddonsPanel";
import { ParceirosPanel } from "@/components/admin/superadmin/ParceirosPanel";
import { YourEyesEmpresaPanel } from "@/components/admin/superadmin/YourEyesEmpresaPanel";
import { MarketYEAdminPanel } from "@/components/admin/superadmin/MarketYEAdminPanel";
import { SUPER_ADMIN_MENU, localizarItemDoMenu, rotaDaAbaLegada } from "@/components/admin/superadmin/superAdminMenu";

// Painel Super Admin. Antes era uma tela única com onze abas lado a lado;
// agora cada seção tem endereço próprio (/admin/<secao>) e é escolhida pelo
// menu lateral agrupado por área (SuperAdminLayout). Esta página só resolve
// qual seção renderizar a partir da rota. As páginas que já tinham endereço
// próprio (QA, Blog, Contratos, Manual, Controle de Clientes) continuam com
// seus componentes; o roteador as atende antes de cair aqui.

/** Cartões de atalho por área, mostrados na Visão geral (útil no celular, onde o menu fica recolhido). */
function AreasDoPainel() {
  const areas = SUPER_ADMIN_MENU.filter((a) => a.id !== "painel");
  return (
    <section className="space-y-3" data-testid="admin-areas">
      <div>
        <h2 className="text-lg font-semibold">Áreas do painel</h2>
        <p className="text-sm text-muted-foreground">O mesmo agrupamento do menu lateral, para chegar rápido em cada seção.</p>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
        {areas.map((area) => (
          <Card key={area.id} data-testid={`admin-area-${area.id}`}>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">{area.label}</CardTitle>
              <CardDescription>{area.descricao}</CardDescription>
            </CardHeader>
            <CardContent>
              <ul className="space-y-1">
                {area.items.map((item) => {
                  const Icon = item.icon;
                  return (
                    <li key={item.id}>
                      <Link
                        to={item.path}
                        className="flex items-center gap-2 rounded-md px-2 py-1.5 text-sm transition-colors hover:bg-muted"
                      >
                        <Icon className="w-4 h-4 text-primary shrink-0" />
                        <span className="flex-1">{item.label}</span>
                        <ChevronRight className="w-4 h-4 text-muted-foreground shrink-0" />
                      </Link>
                    </li>
                  );
                })}
              </ul>
            </CardContent>
          </Card>
        ))}
      </div>
    </section>
  );
}

function VisaoGeral() {
  return (
    <div className="space-y-8">
      <SuperAdminOverview />
      <AreasDoPainel />
    </div>
  );
}

// Seções que abrem dentro do painel: rota → componente. Cada rota daqui
// precisa existir também no menu (superAdminMenu.ts), que dá título e descrição.
const SECOES: Record<string, ComponentType> = {
  "/admin": VisaoGeral,
  "/admin/situacao": TenantsStatusPanel,
  "/admin/empresas": TenantsPanel,
  "/admin/usuarios": UsuariosGlobalPanel,
  "/admin/leads": LeadsCRMKanban,
  "/admin/landing": LandingLeadsTable,
  "/admin/precos": PrecosAddonsPanel,
  "/admin/parceiros": ParceirosPanel,
  "/admin/psicossocial": PsicossocialSuperAdminPanel,
  "/admin/marketye": MarketYEAdminPanel,
  "/admin/dados-youreyes": YourEyesEmpresaPanel,
};

export default function SuperAdminDashboard() {
  const location = useLocation();
  const [searchParams] = useSearchParams();

  // Endereço antigo (/admin?aba=x) → rota nova equivalente.
  const rotaLegada = rotaDaAbaLegada(searchParams.get("aba"));
  if (rotaLegada) return <Navigate to={rotaLegada} replace />;

  const rota = location.pathname.replace(/\/+$/, "") || "/";
  const Secao = SECOES[rota];
  const atual = localizarItemDoMenu(rota);
  if (!Secao || !atual) return <Navigate to="/admin" replace />;

  const Icon = atual.item.icon;
  return (
    <div className="w-full max-w-[1600px] mx-auto p-4 md:p-6 space-y-6" data-testid="admin-secao">
      <div>
        <h1 className="text-2xl md:text-3xl font-bold flex items-center gap-2" data-testid="admin-secao-titulo">
          <Icon className="w-7 h-7 text-primary" />
          {atual.item.label}
        </h1>
        <p className="text-sm text-muted-foreground mt-1">{atual.item.descricao}</p>
      </div>
      <Secao />
    </div>
  );
}
