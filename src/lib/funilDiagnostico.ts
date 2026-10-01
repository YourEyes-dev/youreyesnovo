/**
 * Funil do diagnóstico do site — eventos do Pixel para saber ONDE o visitante
 * para: não vê a seção, vê e não começa, começa e desiste em qual etapa, ou
 * chega ao formulário e não envia.
 *
 * Eventos (só Pixel; nada vai pelo servidor/CAPI):
 *  - ViewContent { content_name: 'diagnostico' } — a seção aparece na tela
 *    pela 1ª vez na sessão;
 *  - DiagnosticoIniciado — primeira resposta (porte);
 *  - DiagnosticoEtapa { etapa, total } — cada etapa concluída (porte, setor,
 *    as 8 perguntas, contato enviado);
 *  - DiagnosticoContato — chegou ao passo do formulário de contato.
 * Todos levam utm_campaign quando a visita veio de campanha.
 *
 * Cada evento sai UMA vez por sessão (sessionStorage): voltar e responder de
 * novo não duplica. Só sai onde o Pixel roda (site público, produção — ver
 * iniciarMetaPixel); fora dele nada é enviado nem marcado.
 *
 * LGPD: nunca vai o conteúdo das respostas — só o número da etapa.
 */
import { trackPixelEvento } from "@/lib/metaConversions";
import { lerOrigemGuardada } from "@/lib/siteOrigem";

const CHAVE = "ye_funil_diagnostico";

function lerEnviados(): Set<string> {
  try {
    const raw = window.sessionStorage.getItem(CHAVE);
    return new Set(raw ? (JSON.parse(raw) as string[]) : []);
  } catch {
    return new Set();
  }
}

function marcar(enviados: Set<string>, id: string) {
  enviados.add(id);
  try {
    window.sessionStorage.setItem(CHAVE, JSON.stringify([...enviados]));
  } catch {
    /* sem armazenamento: dedup só na memória desta chamada */
  }
}

function comCampanha(params: Record<string, string | number>) {
  const camp = lerOrigemGuardada()?.utm_campaign;
  return camp ? { ...params, utm_campaign: camp } : params;
}

/** Dispara uma vez por sessão. Devolve true se o evento saiu agora. */
function umaVez(id: string, nome: string, params: Record<string, string | number>, personalizado: boolean): boolean {
  try {
    const enviados = lerEnviados();
    if (enviados.has(id)) return false;
    // Só marca se saiu de fato: fora do site público/produção nada é marcado.
    if (!trackPixelEvento(nome, comCampanha(params), personalizado)) return false;
    marcar(enviados, id);
    return true;
  } catch {
    return false;
  }
}

export const funilDiagnostico = {
  visivel: () => umaVez("view", "ViewContent", { content_name: "diagnostico" }, false),
  iniciado: () => umaVez("inicio", "DiagnosticoIniciado", {}, true),
  etapa: (etapa: number, total: number) =>
    umaVez(`etapa_${etapa}`, "DiagnosticoEtapa", { etapa, total }, true),
  contato: () => umaVez("contato", "DiagnosticoContato", {}, true),
};
