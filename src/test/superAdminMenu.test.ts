import { describe, it, expect } from "vitest";
import {
  SUPER_ADMIN_MENU, SUPER_ADMIN_ITENS, localizarItemDoMenu, rotaDaAbaLegada,
} from "@/components/admin/superadmin/superAdminMenu";

// O menu do Painel Super Admin é a fonte da verdade da casca e do painel:
// estes testes garantem que ele continua coerente (ids e rotas únicos, toda
// aba antiga com destino) e que a rota atual encontra o item certo.

describe("menu do Painel Super Admin", () => {
  it("tem ids e rotas únicos, sem área vazia", () => {
    const ids = SUPER_ADMIN_ITENS.map((i) => i.id);
    const rotas = SUPER_ADMIN_ITENS.map((i) => i.path);
    expect(new Set(ids).size).toBe(ids.length);
    expect(new Set(rotas).size).toBe(rotas.length);
    for (const area of SUPER_ADMIN_MENU) expect(area.items.length).toBeGreaterThan(0);
    for (const item of SUPER_ADMIN_ITENS) expect(item.path.startsWith("/admin")).toBe(true);
  });

  it("localiza o item pela rota exata (com ou sem barra final)", () => {
    expect(localizarItemDoMenu("/admin")?.item.id).toBe("visao-geral");
    expect(localizarItemDoMenu("/admin/")?.item.id).toBe("visao-geral");
    expect(localizarItemDoMenu("/admin/empresas")?.item.id).toBe("empresas");
    expect(localizarItemDoMenu("/admin/marketye")?.area.id).toBe("produtos");
    expect(localizarItemDoMenu("/admin/qa")?.item.id).toBe("qa");
  });

  it("mantém o item ativo nas páginas filhas (detalhe de empresa, docs do QA)", () => {
    expect(localizarItemDoMenu("/admin/tenants/abc-123")?.item.id).toBe("empresas");
    expect(localizarItemDoMenu("/admin/tenants/abc-123/assinatura")?.item.id).toBe("empresas");
    expect(localizarItemDoMenu("/admin/qa/docs")?.item.id).toBe("qa");
    expect(localizarItemDoMenu("/admin/qa/runner")?.item.id).toBe("qa");
  });

  it("não marca nada para rotas fora do painel ou desconhecidas", () => {
    expect(localizarItemDoMenu("/")).toBeUndefined();
    expect(localizarItemDoMenu("/admin/nao-existe")).toBeUndefined();
    // "/admin/controle-clientes" é a Central de Controle de Clientes; não pode ser
    // confundida com um vizinho de nome parecido
    expect(localizarItemDoMenu("/admin/controle-clientes-x")).toBeUndefined();
    // o endereço antigo saiu do menu (virou redirecionamento)
    expect(localizarItemDoMenu("/admin/youreyes")).toBeUndefined();
  });

  it("converte toda aba antiga (?aba=) para uma rota que existe no menu", () => {
    const abasAntigas = ["overview", "tenants", "usuarios", "leads", "landing", "psicossocial", "situacao", "precos", "parceiros", "marketye", "empresa"];
    for (const aba of abasAntigas) {
      const rota = rotaDaAbaLegada(aba);
      expect(rota, aba).toBeDefined();
      expect(localizarItemDoMenu(rota!), aba).toBeDefined();
    }
    expect(rotaDaAbaLegada("marketye")).toBe("/admin/marketye");
    expect(rotaDaAbaLegada("empresa")).toBe("/admin/dados-youreyes");
    expect(rotaDaAbaLegada(null)).toBeUndefined();
    expect(rotaDaAbaLegada("inventada")).toBeUndefined();
  });
});
