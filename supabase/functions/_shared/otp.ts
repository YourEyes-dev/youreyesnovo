// =====================================================================
// Código de uso único (OTP) da assinatura eletrônica.
//
// - Gerado com crypto.getRandomValues (gerador criptográfico), sem viés de
//   módulo (amostragem por rejeição). Nunca Math.random.
// - O banco guarda só o hash: sha256("<solicitacao_id>:<codigo>"). O id da
//   solicitação funciona como sal: o mesmo código em duas solicitações gera
//   hashes diferentes.
// - Mascaramento de e-mail e celular para a trilha e para a tela.
// =====================================================================

/** Código numérico de `digitos` dígitos (padrão 6), uniforme. */
export function gerarCodigoOtp(digitos = 6): string {
  const limite = 10 ** digitos;
  // Maior múltiplo de `limite` que cabe em 2^32: acima dele, descarta (sem viés).
  const teto = Math.floor(0x100000000 / limite) * limite;
  const buf = new Uint32Array(1);
  for (;;) {
    crypto.getRandomValues(buf);
    if (buf[0] < teto) return String(buf[0] % limite).padStart(digitos, "0");
  }
}

export async function sha256Hex(texto: string | Uint8Array): Promise<string> {
  const bytes = typeof texto === "string" ? new TextEncoder().encode(texto) : texto;
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Hash que o banco guarda/compara (nunca o código em claro). */
export function hashOtp(solicitacaoId: string, codigo: string): Promise<string> {
  return sha256Hex(`${solicitacaoId}:${String(codigo || "").replace(/\D/g, "")}`);
}

/** j***@e***.com.br */
export function mascararEmail(email: string | null | undefined): string {
  const e = String(email || "").trim();
  const [usuario, dominio] = e.split("@");
  if (!usuario || !dominio) return "";
  const partes = dominio.split(".");
  const primeiro = partes.shift() || "";
  return `${usuario[0]}***@${primeiro[0] || ""}***${partes.length ? "." + partes.join(".") : ""}`;
}

/** (**) *****-1234 */
export function mascararCelular(celular: string | null | undefined): string {
  const d = String(celular || "").replace(/\D/g, "");
  if (d.length < 4) return "";
  return `(**) *****-${d.slice(-4)}`;
}

/** ***.***.***-12 */
export function mascararCpf(cpf: string | null | undefined): string {
  const d = String(cpf || "").replace(/\D/g, "");
  if (d.length !== 11) return "***";
  return `***.***.***-${d.slice(-2)}`;
}
