// =====================================================================
// TEXTOS DA ASSINATURA ELETRÔNICA — arquivo ÚNICO para a revisão jurídica.
//
// Tudo o que o colaborador lê (tela /assinar, e-mails) e o que vai impresso no
// manifesto de evidências sai daqui. A advogada revisa ESTE arquivo; ao mudar
// um texto, suba VERSAO_TEXTOS_ASSINATURA (o manifesto registra a versão).
//
// Regras (fundadora, 30/10/2026):
//   - não prometer "juridicamente válido";
//   - falar em "assinatura eletrônica com evidências (MP 2.200-2/2001, art. 10, §2º)";
//   - não citar número de artigo da Portaria 671 em texto novo.
//
// Usado pela tela (src/lib/assinaturaTextos.ts reexporta) e pelas funções de
// borda. Sem dependência de Deno nem do navegador: só constantes e funções puras.
// =====================================================================

export const VERSAO_TEXTOS_ASSINATURA = "assinatura-textos-v1-2026-10-30";

export const NOME_DA_ASSINATURA = "Assinatura eletrônica com evidências";
export const BASE_LEGAL_ASSINATURA = "MP 2.200-2/2001, art. 10, §2º";

/** Linha curta que aparece na tela, no e-mail e no manifesto. */
export const LINHA_BASE_LEGAL =
  `${NOME_DA_ASSINATURA} (${BASE_LEGAL_ASSINATURA}).`;

// ── Tela /assinar ────────────────────────────────────────────────────
export const TELA = {
  titulo: "Espelho de Ponto para sua ciência",
  introducao:
    "A empresa disponibilizou o seu espelho de ponto do mês para você conferir. Leia o documento com atenção antes de responder.",
  marcarLido: "Li o espelho de ponto deste mês.",
  pedirCpf: "Para confirmar que é você, informe o seu CPF.",
  pedirCodigo: (destino: string) =>
    `Enviamos um código de 6 dígitos para ${destino}. Ele vale por 10 minutos.`,
  semEmail:
    "Não há e-mail cadastrado para enviar o código de confirmação. Procure o RH: a ciência pode ser dada no aplicativo ou em papel.",
  provaDeVidaTitulo: "Confirmação de presença",
  provaDeVidaTexto:
    "Para proteger você contra assinatura feita por outra pessoa, pedimos uma verificação rápida pela câmera. As imagens servem só para provar a sua identidade neste documento (LGPD, art. 11, II, \"g\") e são guardadas com acesso restrito.",
  recusarCamera: "Não quero usar a câmera",
  recusarCameraAviso:
    "Você pode continuar sem a câmera. A sua resposta será registrada só com o CPF e o código enviado ao seu e-mail, e o registro indicará \"sem prova de vida (recusou câmera)\".",
  decisaoTitulo: "Sua resposta",
  decisoes: {
    assinado: {
      rotulo: "Concordo e assino",
      declaracao:
        "Declaro que conferi o espelho de ponto deste mês e que as marcações representam a minha jornada no período.",
    },
    assinado_com_ressalva: {
      rotulo: "Assino com ressalva",
      declaracao:
        "Declaro que conferi o espelho de ponto deste mês e assino com a ressalva abaixo.",
      campo: "Descreva a ressalva (obrigatório)",
    },
    contestado: {
      rotulo: "Não concordo / contesto",
      declaracao:
        "Declaro que NÃO concordo com o espelho de ponto deste mês, pelo motivo abaixo. Esta resposta não é assinatura de concordância.",
      campo: "Descreva o motivo (obrigatório)",
    },
  },
  rodape: LINHA_BASE_LEGAL,
  linkInvalido: "Link inválido",
  linkInvalidoTexto:
    "Este link não é válido ou foi substituído por um mais recente. Use o último e-mail recebido ou procure o RH.",
  expirado: "Prazo encerrado",
  expiradoTexto:
    "O prazo para responder por este link terminou. Procure o RH para receber um novo envio.",
  cancelado: "Envio cancelado",
  canceladoTexto: "Este envio foi cancelado pela empresa. Procure o RH.",
  concluidoAssinado: "Resposta registrada. Obrigado!",
  concluidoTexto:
    "A sua resposta foi registrada com data, hora e evidências. Uma via foi enviada para o seu e-mail.",
  bloqueado:
    "Muitas tentativas com CPF incorreto. Por segurança, este link ficou bloqueado por 24 horas. Procure o RH.",
} as const;

// ── E-mails ──────────────────────────────────────────────────────────
export const EMAIL = {
  conviteAssunto: (competencia: string) => `Espelho de ponto ${competencia} para sua ciência`,
  conviteTitulo: "Seu espelho de ponto está disponível",
  conviteMensagem: (nome: string, competencia: string, prazo: string) =>
    `Olá, ${nome}. O seu espelho de ponto de ${competencia} está disponível para conferência. ` +
    `Abra pelo botão abaixo, confira e registre a sua resposta até ${prazo}. ` +
    `Por segurança, o documento não vai anexado a este e-mail.`,
  lembreteAssunto: (competencia: string) => `Lembrete: espelho de ponto ${competencia} aguardando sua resposta`,
  lembreteTitulo: "Seu espelho de ponto ainda aguarda resposta",
  lembreteMensagem: (nome: string, competencia: string, prazo: string) =>
    `Olá, ${nome}. O seu espelho de ponto de ${competencia} ainda aguarda a sua resposta (prazo: ${prazo}). ` +
    `Use o botão abaixo: os links de e-mails anteriores deixam de valer.`,
  codigoAssunto: "Seu código para confirmar a assinatura",
  codigoTitulo: "Código de confirmação",
  codigoMensagem: (codigo: string) =>
    `Seu código é ${codigo}. Ele vale por 10 minutos e só pode ser usado uma vez. Se não foi você que pediu, ignore este e-mail.`,
  viaAssunto: (competencia: string) => `Sua via do espelho de ponto ${competencia}`,
  viaTitulo: "Sua resposta foi registrada",
  viaMensagem: (nome: string, competencia: string, decisao: string) =>
    `Olá, ${nome}. Registramos a sua resposta ao espelho de ponto de ${competencia}: ${decisao}. ` +
    `Pelo botão abaixo você pode ver e guardar a sua via.`,
  botaoAbrir: "Abrir o espelho",
  botaoVia: "Ver minha via",
  rodape: LINHA_BASE_LEGAL,
} as const;

// ── Manifesto de evidências (última página do PDF assinado) ───────────
export const MANIFESTO = {
  titulo: "Manifesto de evidências da assinatura",
  subtitulo: LINHA_BASE_LEGAL,
  decisoes: {
    assinado: "Concordou e assinou",
    assinado_com_ressalva: "Assinou com ressalva",
    contestado: "Não concordou (contestação)",
  } as Record<string, string>,
  semProvaDeVida: "Sem prova de vida (recusou câmera): identificação por CPF e código enviado ao e-mail.",
  comProvaDeVida: "Prova de vida por câmera, após consentimento.",
  notaIntegridade:
    "O código de integridade (SHA-256) do documento original foi calculado no envio e conferido novamente no momento da assinatura. Qualquer alteração no arquivo muda esse código.",
  notaRodape:
    "Hora registrada pelo servidor. Endereço IP e navegador obtidos pelo servidor, não informados pelo signatário.",
} as const;

/** "dd/MM/aaaa" de uma data ISO, no horário de Brasília (UTC-3). */
export function dataCurtaBr(iso: string): string {
  const d = new Date(Date.parse(iso) - 3 * 3600 * 1000);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${p(d.getUTCDate())}/${p(d.getUTCMonth() + 1)}/${d.getUTCFullYear()}`;
}

/** "10/2026" a partir de "2026-10". */
export function competenciaBr(competencia: string | null | undefined): string {
  const [a, m] = String(competencia || "").split("-");
  return a && m ? `${m}/${a}` : String(competencia || "");
}
