import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { SuperAdminLayout } from "@/components/admin/superadmin/SuperAdminLayout";
import { SUPER_ADMIN_MENU, SUPER_ADMIN_ITENS } from "@/components/admin/superadmin/superAdminMenu";

// Casca do Painel Super Admin: menu lateral agrupado por área, caminho na
// barra superior e conteúdo da rota dentro dela.

function montar(rota: string) {
  return render(
    <MemoryRouter initialEntries={[rota]}>
      <Routes>
        <Route element={<SuperAdminLayout />}>
          <Route path="/admin" element={<div>conteudo-visao-geral</div>} />
          <Route path="/admin/tenants/:id" element={<div>conteudo-detalhe-empresa</div>} />
          <Route path="/admin/:secao" element={<div>conteudo-secao</div>} />
        </Route>
      </Routes>
    </MemoryRouter>,
  );
}

describe("SuperAdminLayout", () => {
  it("mostra todas as áreas e todos os itens do menu, com o endereço certo", () => {
    montar("/admin");
    for (const area of SUPER_ADMIN_MENU) {
      // o rótulo da área aberta também aparece no caminho da barra superior
      expect(screen.getAllByText(area.label).length).toBeGreaterThanOrEqual(1);
    }
    for (const item of SUPER_ADMIN_ITENS) {
      const link = screen.getByTestId(`menu-admin-${item.id}`);
      expect(link).toHaveAttribute("href", item.path);
      expect(link).toHaveTextContent(item.label);
    }
    expect(screen.getByText("conteudo-visao-geral")).toBeInTheDocument();
    expect(screen.getByTestId("admin-nova-empresa")).toBeInTheDocument();
  });

  it("marca o item ativo e escreve o caminho da seção aberta", () => {
    montar("/admin/marketye");
    expect(screen.getByTestId("admin-secao-atual")).toHaveTextContent("MarketYE");
    expect(screen.getByTestId("menu-admin-marketye")).toHaveAttribute("data-active", "true");
    expect(screen.getByTestId("menu-admin-visao-geral")).toHaveAttribute("data-active", "false");
    expect(screen.getByText("conteudo-secao")).toBeInTheDocument();
  });

  it("mantém Empresas ativo ao abrir o detalhe de uma empresa", () => {
    montar("/admin/tenants/abc-123");
    expect(screen.getByTestId("admin-secao-atual")).toHaveTextContent("Empresas");
    expect(screen.getByTestId("menu-admin-empresas")).toHaveAttribute("data-active", "true");
    expect(screen.getByText("conteudo-detalhe-empresa")).toBeInTheDocument();
  });
});
