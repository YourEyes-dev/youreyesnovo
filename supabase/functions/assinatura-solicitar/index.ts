// =====================================================================
// assinatura-solicitar — o RH envia um documento para assinatura eletrônica.
// Primeiro uso: Espelho de Ponto (contexto 'ponto_espelho').
//
// Exige usuário logado (JWT conferido no Auth) da MESMA empresa do espelho e
// com Ponto/Colaboradores (assinatura_rh_pode_gerir, avaliada com o login dele).
//
// acao 'enviar'   { espelho_id, pdf_base64, link_base }
//   1. confere espelho, competência fechada e e-mail do colaborador (sem e-mail
//      o link não assina — decisão da fundadora);
//   2. sobe o PDF para o bucket privado assinaturas-documentos e calcula o
//      SHA-256 AQUI no servidor (o navegador não manda hash);
//   3. cria a solicitação (assinatura_criar_solicitacao) — se falhar, apaga o PDF;
//   4. gera o token, manda o e-mail e devolve o link UMA vez (para copiar).
// acao 'reenviar' { solicitacao_id, link_base? } — novo token + novo e-mail.
// acao 'enviar_aditivo_ec141' { aditivo_id, pdf_base64, link_base } — aditivo
//   individual de alteração de horário da EC 141/2026 (contexto
//   'ponto_ec141_aditivo'): mesmo fluxo (PDF congelado + hash no servidor,
//   solicitação, token e e-mail); o PDF é montado pela tela a partir do texto
//   do aditivo (ponto_ec141_aditivos.texto), que vai também no snapshot.
// "Copiar link de novo" e "cancelar" são RPCs que a tela chama direto
// (assinatura_rh_novo_link, assinatura_cancelar).
// =====================================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'
import { autenticar, respostaDeErro, HttpError } from '../_shared/auth.ts'
import { sha256Hex, mascararEmail } from '../_shared/otp.ts'
import { enviarConvite, linkBaseSeguro } from '../_shared/assinatura-envio.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
}

const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

const BUCKET = 'assinaturas-documentos'
const MAX_PDF = 8 * 1024 * 1024

function base64ParaBytes(b64: string): Uint8Array {
  const limpo = b64.includes(',') ? b64.slice(b64.indexOf(',') + 1) : b64
  const bin = atob(limpo)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

const soDigitos = (v: unknown) => String(v ?? '').replace(/\D/g, '')
const cpfFormatado = (d: string) => `${d.slice(0, 3)}.${d.slice(3, 6)}.${d.slice(6, 9)}-${d.slice(9)}`

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Método não permitido' }, 405)

  try {
    const u = await autenticar(req)
    const admin = u.admin
    const userClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } }, auth: { persistSession: false } },
    )
    const body = await req.json().catch(() => ({}))
    const acao = String(body?.acao || 'enviar')

    const podeGerir = async (cpf: string) => {
      const { data, error } = await userClient.rpc('assinatura_rh_pode_gerir', { p_tenant: u.tenantId, p_cpf: cpf })
      if (error || data !== true) throw new HttpError(403, 'Seu acesso não permite enviar espelho para assinatura.')
    }

    if (acao === 'reenviar') {
      const { data: sol } = await admin.from('assinatura_solicitacoes')
        .select('*').eq('id', body?.solicitacao_id).eq('tenant_id', u.tenantId).maybeSingle()
      if (!sol) throw new HttpError(404, 'Solicitação não encontrada')
      await podeGerir(sol.colaborador_cpf)
      if (!['enviado', 'visualizado', 'na_fila'].includes(sol.status)) {
        return json({ ok: false, erro: 'solicitacao_inativa', status: sol.status }, 409)
      }
      if (body?.link_base) sol.link_base = linkBaseSeguro(body.link_base)
      const r = await enviarConvite(admin, sol, 'solicitacao')
      return json({ ok: r.ok, solicitacao_id: sol.id, link: r.link, email_enviado: r.emailEnviado, email_erro: r.emailErro })
    }

    if (acao === 'enviar_aditivo_ec141') {
      const { data: ad } = await admin.from('ponto_ec141_aditivos')
        .select('id, tenant_id, empresa_id, colaborador_id, colaborador_cpf, colaborador_nome, vigencia_inicio, texto, variaveis, modelo_versao, status, solicitacao_id')
        .eq('id', body?.aditivo_id).eq('tenant_id', u.tenantId).maybeSingle()
      if (!ad) throw new HttpError(404, 'Aditivo não encontrado nesta empresa')
      if (ad.status === 'cancelado') return json({ ok: false, erro: 'aditivo_cancelado' }, 409)
      const cpfAd = soDigitos(ad.colaborador_cpf)
      if (!cpfAd) return json({ ok: false, erro: 'sem_cpf', mensagem: 'O colaborador não tem CPF na atribuição da escala.' }, 422)
      await podeGerir(cpfAd)

      const { data: admsAd } = await admin.from('admissoes')
        .select('id, email, celular, status')
        .eq('tenant_id', u.tenantId)
        .in('cpf', [cpfAd, cpfFormatado(cpfAd)])
        .order('created_at', { ascending: false })
      const admAd = (admsAd || []).find((a: { status: string }) => a.status === 'concluido') || (admsAd || [])[0]
      const emailAd = String(admAd?.email || '').trim()
      if (!emailAd) {
        return json({
          ok: false,
          erro: 'sem_email',
          mensagem: 'O colaborador não tem e-mail cadastrado. Sem e-mail o link não pode ser assinado: colha a assinatura em papel.',
        }, 422)
      }

      const bytesAd = base64ParaBytes(String(body?.pdf_base64 || ''))
      if (bytesAd.byteLength === 0 || bytesAd.byteLength > MAX_PDF) throw new HttpError(400, 'PDF ausente ou grande demais')
      if (new TextDecoder().decode(bytesAd.slice(0, 5)) !== '%PDF-') throw new HttpError(400, 'O arquivo enviado não é um PDF')
      const shaAd = await sha256Hex(bytesAd)
      const idAd = crypto.randomUUID()
      const caminhoAd = `${u.tenantId}/ponto_ec141_aditivo/${idAd}/original.pdf`
      const { error: upErrAd } = await admin.storage.from(BUCKET)
        .upload(caminhoAd, bytesAd, { contentType: 'application/pdf', upsert: false })
      if (upErrAd) throw new HttpError(500, 'Não foi possível guardar o PDF: ' + upErrAd.message)

      const { data: profAd } = await admin.from('profiles').select('nome_completo').eq('user_id', u.userId).maybeSingle()
      const { data: criadaAd, error: errCriarAd } = await admin.rpc('assinatura_criar_solicitacao', {
        p_dados: {
          id: idAd, tenant_id: u.tenantId, empresa_id: ad.empresa_id, contexto: 'ponto_ec141_aditivo',
          documento_ref_tabela: 'ponto_ec141_aditivos', documento_ref_id: ad.id, referencia: ad.vigencia_inicio,
          colaborador_id: ad.colaborador_id, colaborador_cpf: cpfAd, colaborador_nome: ad.colaborador_nome,
          email: emailAd, celular: admAd?.celular || null,
          original_path: caminhoAd, original_sha256: shaAd, original_bytes: bytesAd.byteLength,
          dados_snapshot: { texto: ad.texto, variaveis: ad.variaveis, modelo_versao: ad.modelo_versao },
          enviado_por: u.userId, enviado_por_nome: profAd?.nome_completo || null,
          canais: ['email'], link_base: linkBaseSeguro(body?.link_base), lote_id: body?.lote_id || null,
        },
      })
      if (errCriarAd || !criadaAd?.ok) {
        await admin.storage.from(BUCKET).remove([caminhoAd])
        return json({ ok: false, erro: criadaAd?.erro || errCriarAd?.message || 'nao_criada', solicitacao_id: criadaAd?.solicitacao_id }, 409)
      }
      await admin.from('ponto_ec141_aditivos')
        .update({ status: 'enviado', solicitacao_id: idAd, atualizado_em: new Date().toISOString() })
        .eq('id', ad.id)

      const { data: solAd } = await admin.from('assinatura_solicitacoes').select('*').eq('id', idAd).single()
      const rAd = await enviarConvite(admin, solAd, 'solicitacao')
      return json({
        ok: true, solicitacao_id: idAd, link: rAd.link, email_enviado: rAd.emailEnviado, email_erro: rAd.emailErro,
        destino: mascararEmail(emailAd), original_sha256: shaAd,
      })
    }

    if (acao !== 'enviar') throw new HttpError(400, 'Ação desconhecida')

    // 1) Espelho, competência e contato -------------------------------------
    const { data: esp } = await admin.from('ponto_espelhos')
      .select('id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, competencia, status, ciencia_origem')
      .eq('id', body?.espelho_id).eq('tenant_id', u.tenantId).maybeSingle()
    if (!esp) throw new HttpError(404, 'Espelho não encontrado nesta empresa')
    const cpf = soDigitos(esp.colaborador_cpf)
    await podeGerir(cpf)

    const { data: adms } = await admin.from('admissoes')
      .select('id, email, celular, status, data_desligamento')
      .eq('tenant_id', u.tenantId)
      .in('cpf', [cpf, cpfFormatado(cpf)])
      .order('created_at', { ascending: false })
    const adm = (adms || []).find((a: { status: string }) => a.status === 'concluido') || (adms || [])[0]
    const email = String(adm?.email || '').trim()
    if (!email) {
      return json({
        ok: false,
        erro: 'sem_email',
        mensagem: 'O colaborador não tem e-mail cadastrado. Sem e-mail o link não pode ser assinado: use a ciência em papel (ou o app, quando disponível).',
      }, 422)
    }

    // 2) PDF congelado + hash no servidor ------------------------------------
    const bytes = base64ParaBytes(String(body?.pdf_base64 || ''))
    if (bytes.byteLength === 0 || bytes.byteLength > MAX_PDF) throw new HttpError(400, 'PDF ausente ou grande demais')
    if (new TextDecoder().decode(bytes.slice(0, 5)) !== '%PDF-') throw new HttpError(400, 'O arquivo enviado não é um PDF')
    const sha = await sha256Hex(bytes)
    const id = crypto.randomUUID()
    const caminho = `${u.tenantId}/ponto_espelho/${id}/original.pdf`
    const { error: upErr } = await admin.storage.from(BUCKET)
      .upload(caminho, bytes, { contentType: 'application/pdf', upsert: false })
    if (upErr) throw new HttpError(500, 'Não foi possível guardar o PDF: ' + upErr.message)

    const { data: prof } = await admin.from('profiles').select('nome_completo').eq('user_id', u.userId).maybeSingle()

    // 3) Solicitação ----------------------------------------------------------
    const { data: criada, error: errCriar } = await admin.rpc('assinatura_criar_solicitacao', {
      p_dados: {
        id, tenant_id: u.tenantId, empresa_id: esp.empresa_id, contexto: 'ponto_espelho',
        documento_ref_tabela: 'ponto_espelhos', documento_ref_id: esp.id, referencia: esp.competencia,
        colaborador_id: esp.colaborador_id, colaborador_cpf: cpf, colaborador_nome: esp.colaborador_nome,
        email, celular: adm?.celular || null,
        original_path: caminho, original_sha256: sha, original_bytes: bytes.byteLength,
        enviado_por: u.userId, enviado_por_nome: prof?.nome_completo || null,
        canais: ['email'], link_base: linkBaseSeguro(body?.link_base), lote_id: body?.lote_id || null,
      },
    })
    if (errCriar || !criada?.ok) {
      await admin.storage.from(BUCKET).remove([caminho])
      return json({ ok: false, erro: criada?.erro || errCriar?.message || 'nao_criada', solicitacao_id: criada?.solicitacao_id }, 409)
    }

    // 4) Token + e-mail -------------------------------------------------------
    const { data: sol } = await admin.from('assinatura_solicitacoes').select('*').eq('id', id).single()
    const r = await enviarConvite(admin, sol, 'solicitacao')
    return json({
      ok: true,
      solicitacao_id: id,
      link: r.link,
      email_enviado: r.emailEnviado,
      email_erro: r.emailErro,
      destino: mascararEmail(email),
      original_sha256: sha,
    })
  } catch (e) {
    return respostaDeErro(e, corsHeaders)
  }
})
