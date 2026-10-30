// =====================================================================
// Envio do link de assinatura (convite e lembrete), compartilhado entre
// assinatura-solicitar (envio individual, imediato) e assinatura-despachar
// (fila do lote e lembretes do pg_cron).
//
// O token é gerado NO BANCO (256 bits) a cada envio e só o hash fica guardado;
// por isso cada e-mail leva um link novo e os anteriores deixam de valer.
// =====================================================================
import { EMAIL, competenciaBr, dataCurtaBr } from './assinatura-textos.ts'
import { enviarEmailAssinatura } from './resend.ts'

// deno-lint-ignore no-explicit-any
type SupabaseLike = any

/** Onde o link abre. Só endereços da casa; qualquer outro cai na produção. */
export function linkBaseSeguro(base?: string | null): string {
  const b = String(base || '').trim()
  const ok = /^https:\/\/(www\.)?youreyes\.com\.br\/$/.test(b)
    || /^https:\/\/youreyes-dev\.github\.io\/youreyesnovo\/(teste|homologacao)\/$/.test(b)
    || /^https:\/\/[a-z0-9-]+\.vercel\.app\/$/.test(b)
    || /^http:\/\/localhost:\d+\/$/.test(b)
  return ok ? b : 'https://youreyes.com.br/'
}

export function montarLink(base: string | null | undefined, token: string): string {
  return `${linkBaseSeguro(base)}assinar/${token}`
}

export interface ResultadoConvite {
  ok: boolean
  token?: string
  link?: string
  emailEnviado: boolean
  emailErro?: string
}

/**
 * Gera token novo, monta o link e manda o e-mail (convite ou lembrete).
 * Registra o resultado no banco (assinatura_registrar_envio). Não lança.
 */
export async function enviarConvite(
  admin: SupabaseLike,
  // deno-lint-ignore no-explicit-any
  sol: Record<string, any>,
  tipo: 'solicitacao' | 'lembrete',
  opts: { manterFila?: boolean } = {},
): Promise<ResultadoConvite> {
  const { data: tok, error: errTok } = await admin.rpc('assinatura_emitir_token', {
    p_solicitacao_id: sol.id, p_ator: 'sistema', p_ator_id: null, p_motivo: tipo,
  })
  if (errTok || !tok?.ok) {
    return { ok: false, emailEnviado: false, emailErro: errTok?.message || tok?.erro || 'token_nao_gerado' }
  }
  const token = tok.token as string
  const link = montarLink(sol.link_base, token)
  const nome = String(sol.colaborador_nome || '').split(' ')[0] || 'colaborador(a)'
  const comp = competenciaBr(sol.referencia)
  const prazo = sol.expira_em ? dataCurtaBr(sol.expira_em) : ''

  let emailEnviado = false
  let emailErro: string | undefined
  if (sol.email) {
    const props = tipo === 'lembrete'
      ? { assunto: EMAIL.lembreteAssunto(comp), titulo: EMAIL.lembreteTitulo, mensagem: EMAIL.lembreteMensagem(nome, comp, prazo) }
      : { assunto: EMAIL.conviteAssunto(comp), titulo: EMAIL.conviteTitulo, mensagem: EMAIL.conviteMensagem(nome, comp, prazo) }
    const r = await enviarEmailAssinatura(sol.email, {
      ...props, actionUrl: link, actionLabel: EMAIL.botaoAbrir, rodape: EMAIL.rodape,
    })
    emailEnviado = r.ok
    emailErro = r.erro
  } else {
    emailErro = 'sem_email'
  }

  await admin.rpc('assinatura_registrar_envio', {
    p_solicitacao_id: sol.id,
    p_tipo: tipo,
    p_ok: emailEnviado,
    p_erro: emailErro ?? null,
    p_manter_fila: !!opts.manterFila,
    p_dados: { canal: 'email' },
  })

  return { ok: true, token, link, emailEnviado, emailErro }
}
