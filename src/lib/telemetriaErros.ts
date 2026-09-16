import { supabase } from '@/integrations/supabase/client';

// Telemetria de erro do YourEyes — o lado da tela.
//
// Três regras que mandam neste arquivo:
//  1. NUNCA atrapalhar quem está trabalhando: toda falha daqui é engolida.
//     Telemetria que derruba a tela é pior que telemetria nenhuma.
//  2. NUNCA mandar dado pessoal. O mascaramento definitivo acontece no
//     servidor (mascarar_pii), mas mascaramos aqui também: o que não sai do
//     navegador não pode vazar no caminho.
//  3. NUNCA gravar direto na tabela: a única porta é a função
//     registrar_evento_erro, que exige sessão e limita a vazão.

const MAX_MIGALHAS = 15;
// Ruído conhecido que não é defeito: requisição cancelada quando o usuário
// sai da tela antes de a resposta chegar (main.tsx já silencia essas).
const RUIDO_CONHECIDO = /AbortError|signal is aborted without reason|ResizeObserver loop/i;
const JANELA_REPETICAO_MS = 30_000;

type Migalha = string;

const migalhas: Migalha[] = [];
const enviadosRecentemente = new Map<string, number>();

/** Mascaramento de véspera: CPF, CNPJ, e-mail, telefone e segredos. */
export function mascararPii(texto: string): string {
  if (!texto) return texto;
  return texto
    .replace(/("?(senha|password|token|authorization|api[_-]?key|secret|chave)"?\s*[:=]\s*"?)([^",&}\s]+)/gi, '$1[oculto]')
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, '[email]')
    .replace(/\b\d{2}\.?\d{3}\.?\d{3}\/?\d{4}-?\d{2}\b/g, '[cnpj]')
    .replace(/\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b/g, '[cpf]')
    .replace(/(\+?55\s?)?\(?\d{2}\)?\s?9?\d{4}[-\s]?\d{4}\b/g, '[telefone]')
    .replace(/\b\d{11,}\b/g, '[numero]');
}

/** Registra um passo do usuário, para reconstruir o caminho até o erro. */
export function deixarMigalha(texto: string) {
  try {
    const hora = new Date().toISOString().slice(11, 19);
    migalhas.push(`${hora} ${mascararPii(texto).slice(0, 160)}`);
    if (migalhas.length > MAX_MIGALHAS) migalhas.shift();
  } catch {
    /* migalha nunca quebra a tela */
  }
}

/** Nome do módulo a partir da rota — é como a Central agrupa por área. */
export function moduloDaRota(caminho: string): string {
  const primeiro = caminho.split('?')[0].split('/').filter(Boolean)[0];
  return primeiro ? primeiro : 'inicio';
}

type Evento = {
  mensagem: string;
  stack?: string;
  tipo?: string;
  acao?: string;
  severidade?: 'critica' | 'alta' | 'media' | 'baixa';
};

/**
 * Manda o erro para a Central. Nunca lança: em qualquer problema, desiste
 * em silêncio (no máximo um aviso no console do navegador).
 */
export async function registrarErro(evento: Evento): Promise<void> {
  try {
    const mensagem = mascararPii(String(evento.mensagem ?? '')).slice(0, 2000);
    if (!mensagem) return;
    if (RUIDO_CONHECIDO.test(mensagem) || RUIDO_CONHECIDO.test(evento.tipo ?? '')) return;

    // O mesmo erro repetido em looping vira UM envio por janela.
    const chave = `${evento.tipo ?? 'erro'}|${mensagem}`;
    const agora = Date.now();
    const visto = enviadosRecentemente.get(chave);
    if (visto && agora - visto < JANELA_REPETICAO_MS) return;
    enviadosRecentemente.set(chave, agora);

    // Sem sessão o servidor recusa de qualquer forma; poupamos a viagem.
    const { data: sessao } = await supabase.auth.getSession();
    if (!sessao?.session) return;

    const caminho = typeof window !== 'undefined' ? window.location.pathname : '';
    await supabase.rpc('registrar_evento_erro', {
      p_evento: {
        mensagem,
        stack: mascararPii(String(evento.stack ?? '')).slice(0, 8000),
        tipo: evento.tipo ?? 'erro',
        modulo: moduloDaRota(caminho),
        rota: caminho,
        acao: evento.acao ?? null,
        severidade: evento.severidade ?? 'media',
        origem: 'frontend',
        ambiente: import.meta.env.MODE ?? 'desconhecido',
        versao_app: import.meta.env.VITE_APP_VERSION ?? null,
        navegador_os: typeof navigator !== 'undefined' ? navigator.userAgent.slice(0, 200) : null,
        breadcrumbs: [...migalhas],
        ocorrido_em: new Date().toISOString(),
      },
    });
  } catch (e) {
    if (import.meta.env.DEV) console.warn('[telemetria] não foi possível registrar o erro', e);
  }
}

let instalado = false;

/** Liga a captura global de erros da tela. Chamar uma vez, no boot. */
export function instalarCapturaDeErros() {
  if (instalado || typeof window === 'undefined') return;
  instalado = true;

  window.addEventListener('error', (evento) => {
    const erro = (evento as ErrorEvent).error;
    void registrarErro({
      mensagem: (evento as ErrorEvent).message || erro?.message || 'Erro sem mensagem',
      stack: erro?.stack,
      tipo: erro?.name || 'Error',
      severidade: 'alta',
    });
  });

  window.addEventListener('unhandledrejection', (evento) => {
    const motivo = (evento as PromiseRejectionEvent).reason;
    const mensagem = typeof motivo === 'string' ? motivo : motivo?.message;
    void registrarErro({
      mensagem: mensagem || 'Promessa rejeitada sem motivo',
      stack: typeof motivo === 'object' ? motivo?.stack : undefined,
      tipo: (typeof motivo === 'object' && motivo?.name) || 'UnhandledRejection',
      severidade: 'alta',
    });
  });

  // Caminho do usuário: clique em botão/link e troca de tela.
  window.addEventListener('click', (evento) => {
    const alvo = (evento.target as HTMLElement | null)?.closest('button, a, [role="button"]');
    if (alvo) deixarMigalha(`clicou em "${(alvo.textContent || alvo.getAttribute('aria-label') || 'elemento').trim()}"`);
  }, { capture: true });
}
