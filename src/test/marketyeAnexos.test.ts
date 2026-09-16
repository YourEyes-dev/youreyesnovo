import { describe, it, expect } from "vitest";
import { BUCKET_DOCS, caminhoDaFoto, caminhoDoDocumento, caminhoNoBucket, nomeSeguroDeArquivo } from "@/lib/marketyeAnexos";

// As políticas do Storage conferem a PRIMEIRA pasta do caminho contra o id do
// especialista. Estes testes travam esse formato: foi a causa de os anexos do
// cadastro não subirem (o caminho começava pelo id do usuário).

describe("anexos do MarketYE", () => {
  it("monta o caminho do documento começando pelo id do especialista", () => {
    const c = caminhoDoDocumento("11111111-2222-3333-4444-555555555555", "documento_pessoal", "RG frente.pdf", 1700000000000);
    expect(c).toBe("11111111-2222-3333-4444-555555555555/documento_pessoal/1700000000000-RG_frente.pdf");
    expect(c.split("/")[0]).toBe("11111111-2222-3333-4444-555555555555");
  });

  it("monta o caminho da foto na pasta foto_perfil do especialista", () => {
    const c = caminhoDaFoto("abc", "minha foto.JPG", 5);
    expect(c).toBe("abc/foto_perfil/5-minha_foto.JPG");
  });

  it("limpa acentos, espaços e caracteres que o Storage rejeita", () => {
    expect(nomeSeguroDeArquivo("Certidão (2026) — final.pdf")).toBe("Certidao_2026_final.pdf");
    expect(nomeSeguroDeArquivo("   ")).toBe("arquivo");
    expect(nomeSeguroDeArquivo("ok-nome.v2.png")).toBe("ok-nome.v2.png");
  });

  it("recupera o caminho no bucket a partir da URL antiga ou do caminho novo", () => {
    const antiga = "https://projeto.supabase.co/storage/v1/object/public/marketplace-docs/user-1/prof-1/formacao/1-diploma.pdf";
    expect(caminhoNoBucket(antiga, BUCKET_DOCS)).toBe("user-1/prof-1/formacao/1-diploma.pdf");
    expect(caminhoNoBucket("prof-1/formacao/2-diploma.pdf")).toBe("prof-1/formacao/2-diploma.pdf");
    expect(caminhoNoBucket("https://x/storage/v1/object/public/marketplace-docs/p/cat/a%20b.pdf?token=1")).toBe("p/cat/a b.pdf");
  });
});
