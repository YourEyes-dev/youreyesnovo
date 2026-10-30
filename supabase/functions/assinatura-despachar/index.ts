// =====================================================================
// assinatura-despachar — chamada pelo pg_cron (assinatura_disparar_lembretes),
// uma vez por dia. Sem usuário: a porta é o cabeçalho x-assinatura-segredo, que
// tem de ser igual a app_config.assinatura_despachar_segredo (lido aqui com a
// chave de serviço). Sem segredo configurado, recusa tudo.
//
//   1. expira as solicitações vencidas (D+10, sem aceite tácito);
//   2. manda os lembretes devidos (D+2, D+5, D+8) — só pendentes, com e-mail e
//      colaborador ativo (assinatura_lembretes_devidos); cada lembrete leva um
//      link NOVO (o anterior deixa de valer);
//   3. esvazia a fila do lote (status na_fila), até 3 tentativas com espera
//      crescente (o lote em si é a Fatia 2).
// Respeita o limite do Resend (~2 e-mails por segundo).
// =====================================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'
import { enviarConvite } from '../_shared/assinatura-envio.ts'

const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { 'Content-Type': 'application/json' } })

const esperar = (ms: number) => new Promise((r) => setTimeout(r, ms))

function iguais(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let d = 0
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return d === 0
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Método não permitido' }, 405)
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: cfg } = await admin.from('app_config').select('valor').eq('chave', 'assinatura_despachar_segredo').maybeSingle()
  const segredo = String(cfg?.valor || '')
  const recebido = String(req.headers.get('x-assinatura-segredo') || '')
  if (!segredo || !iguais(segredo, recebido)) return json({ error: 'Não autorizado' }, 401)

  const resultado = { expiradas: 0, lembretes: 0, lembretes_falhos: 0, fila: 0, fila_falhos: 0 }
  try {
    const { data: exp } = await admin.rpc('assinatura_expirar_vencidas')
    resultado.expiradas = Number(exp) || 0

    const { data: devidos } = await admin.rpc('assinatura_lembretes_devidos', { p_limite: 300 })
    for (const d of (devidos || []) as Array<{ solicitacao_id: string }>) {
      const { data: sol } = await admin.from('assinatura_solicitacoes').select('*').eq('id', d.solicitacao_id).maybeSingle()
      if (!sol) continue
      const r = await enviarConvite(admin, sol, 'lembrete')
      if (r.emailEnviado) resultado.lembretes++
      else resultado.lembretes_falhos++
      await esperar(600)
    }

    const agora = new Date().toISOString()
    const { data: fila } = await admin.from('assinatura_solicitacoes')
      .select('*')
      .eq('status', 'na_fila')
      .or(`envio_proxima_em.is.null,envio_proxima_em.lte.${agora}`)
      .order('created_at')
      .limit(100)
    for (const sol of fila || []) {
      const r = await enviarConvite(admin, sol, 'solicitacao', { manterFila: true })
      if (r.emailEnviado) resultado.fila++
      else resultado.fila_falhos++
      await esperar(600)
    }
    return json({ ok: true, ...resultado })
  } catch (e) {
    console.error('[assinatura-despachar]', e)
    return json({ ok: false, erro: 'erro_interno', ...resultado }, 500)
  }
})
