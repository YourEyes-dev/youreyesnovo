// Anexos do MarketYE: documentos comprobatórios e foto de perfil do especialista.
//
// O que as políticas do Storage exigem (e que a tela precisa respeitar):
//  * `marketplace-docs` (privado): a PRIMEIRA pasta do caminho é o id do
//    especialista (marketplace_profissionais.id). A política de upload confere
//    `split_part(name,'/',1)` contra os cadastros do usuário logado. Caminho
//    começando pelo id do usuário é recusado — foi exatamente o defeito que
//    deixava o cadastro criado e sem anexos.
//  * `marketplace-fotos` (público): mesma regra de caminho; a vitrine lê a foto
//    por URL pública.
export const BUCKET_DOCS = "marketplace-docs";
export const BUCKET_FOTOS = "marketplace-fotos";

/** Nome de arquivo sem acentos, espaços ou caracteres que o Storage rejeita. */
export function nomeSeguroDeArquivo(nome: string): string {
  const limpo = nome
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^\w.-]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");
  return limpo || "arquivo";
}

export function caminhoDoDocumento(profissionalId: string, categoria: string, nomeArquivo: string, agora: number = Date.now()): string {
  return `${profissionalId}/${categoria}/${agora}-${nomeSeguroDeArquivo(nomeArquivo)}`;
}

export function caminhoDaFoto(profissionalId: string, nomeArquivo: string, agora: number = Date.now()): string {
  return `${profissionalId}/foto_perfil/${agora}-${nomeSeguroDeArquivo(nomeArquivo)}`;
}

/**
 * `marketplace_profissional_documentos.arquivo_url` guardou, nas primeiras
 * versões, a URL "pública" do objeto (que não abre: o bucket é privado) e, a
 * partir da correção de 12/09/2026, o caminho do objeto no bucket. Devolve o
 * caminho nos dois casos, para gerar um link assinado na hora de exibir.
 */
export function caminhoNoBucket(arquivoUrl: string, bucket: string = BUCKET_DOCS): string {
  const marcador = `/${bucket}/`;
  const i = arquivoUrl.indexOf(marcador);
  const bruto = i >= 0 ? arquivoUrl.slice(i + marcador.length) : arquivoUrl;
  const semQuery = bruto.split("?")[0].replace(/^\/+/, "");
  try {
    return decodeURIComponent(semQuery);
  } catch {
    return semQuery;
  }
}
