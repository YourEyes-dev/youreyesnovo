import { describe, it, expect } from "vitest";
import { mascararPii, moduloDaRota } from "@/lib/telemetriaErros";

// O mascaramento definitivo é do servidor, mas este aqui é a primeira barreira:
// o que ele deixar passar sai do navegador do cliente. Por isso tem teste.

describe("mascaramento de dado pessoal na telemetria", () => {
  it("tira CPF, e-mail, telefone e segredo da mensagem", () => {
    const texto = mascararPii(
      "Falha ao salvar 900.000.012-34 de maria.silva@empresa.com.br, fone (46) 99123-4567, token=abc123",
    );
    expect(texto).toContain("[cpf]");
    expect(texto).toContain("[email]");
    expect(texto).toContain("[telefone]");
    expect(texto).toContain("[oculto]");
    expect(texto).not.toContain("900.000.012-34");
    expect(texto).not.toContain("maria.silva");
    expect(texto).not.toContain("abc123");
  });

  it("pega CPF sem pontuação e CNPJ", () => {
    expect(mascararPii("cpf 90000001234 aqui")).toContain("[cpf]");
    expect(mascararPii("cnpj 12.345.678/0001-90")).toContain("[cnpj]");
  });

  it("não estraga mensagem técnica sem dado pessoal", () => {
    const texto = "TypeError: x is not a function at salvarAjuste (ponto.tsx:42)";
    expect(mascararPii(texto)).toBe(texto);
  });

  it("aponta o módulo pela primeira parte da rota", () => {
    expect(moduloDaRota("/ponto/ajustes")).toBe("ponto");
    expect(moduloDaRota("/admin/controle-clientes")).toBe("admin");
    expect(moduloDaRota("/")).toBe("inicio");
  });
});
