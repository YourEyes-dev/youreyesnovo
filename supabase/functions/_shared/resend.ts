// =====================================================================
// Envio de e-mail pelo Resend, para funções de borda que NÃO têm usuário
// logado (link público, rotina agendada). A send-email-resend exige JWT de
// usuário, então quem é chamado pelo pg_cron ou pelo colaborador anônimo
// usa este módulo direto com RESEND_API_KEY.
//
// Sem RESEND_API_KEY configurada, devolve { ok: false, erro } sem lançar:
// quem chama registra "email_falhou" e segue (o RH ainda tem o link).
// =====================================================================
import * as React from 'npm:react@18.3.1'
import { renderAsync } from 'npm:@react-email/components@0.0.22'
import { AssinaturaSolicitadaEmail, type AssinaturaEmailProps } from './transactional-templates/assinatura-solicitada.tsx'

export interface ResultadoEnvio {
  ok: boolean
  id?: string
  erro?: string
}

const REMETENTE_PADRAO = 'YourEyes <noreply@youreyes.com.br>'

export async function enviarEmailResend(params: {
  para: string
  assunto: string
  html: string
  de?: string
}): Promise<ResultadoEnvio> {
  const chave = Deno.env.get('RESEND_API_KEY')
  if (!chave) return { ok: false, erro: 'RESEND_API_KEY não configurada' }
  if (!params.para || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(params.para)) {
    return { ok: false, erro: 'destinatario_invalido' }
  }
  try {
    const resp = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${chave}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: params.de || Deno.env.get('ASSINATURA_EMAIL_REMETENTE') || REMETENTE_PADRAO,
        to: [params.para],
        subject: params.assunto,
        html: params.html,
      }),
    })
    const corpo = await resp.json().catch(() => ({}))
    if (!resp.ok) return { ok: false, erro: `Resend ${resp.status}: ${JSON.stringify(corpo).slice(0, 300)}` }
    return { ok: true, id: (corpo as { id?: string }).id }
  } catch (e) {
    return { ok: false, erro: e instanceof Error ? e.message : String(e) }
  }
}

/** Renderiza o e-mail da assinatura e envia. */
export async function enviarEmailAssinatura(para: string, props: AssinaturaEmailProps): Promise<ResultadoEnvio> {
  const html = await renderAsync(React.createElement(AssinaturaSolicitadaEmail, props))
  return enviarEmailResend({ para, assunto: props.assunto, html })
}
