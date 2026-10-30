// =====================================================================
// assinatura-documento — a página pública /assinar/:token conversa com isto.
// O colaborador NÃO está logado: quem prova a identidade é o CPF (conferido
// aqui no servidor, 5 tentativas), o código de uso único enviado ao e-mail
// (10 min, 5 tentativas) e a prova de vida (ou a recusa registrada da câmera).
//
// Toda ação manda { token, acao, ... } no CORPO (não na URL, para não ir a log).
// IP, navegador e hora vêm dos cabeçalhos desta requisição (origemDaRequisicao),
// nunca do corpo, e seguem para o banco como "origem" (só aceita com a chave
// de serviço — ver assinatura_origem_efetiva).
//
// Ações: abrir | cpf | documento | otp_enviar | otp_validar | consentimento |
//        evidencia | responder | via
//
// Ao responder (assinar/ressalva): rebaixa o PDF congelado, CONFERE o hash,
// anexa o manifesto de evidências (pdf-lib), grava assinado.pdf no bucket
// privado e uma cópia em Documentos, e chama assinatura_concluir (uma
// transação). Se a conclusão falhar, apaga o que subiu.
// =====================================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'
import { origemDaRequisicao, selarAssinatura } from '../_shared/selar-assinatura.ts'
import { gerarCodigoOtp, hashOtp, sha256Hex, mascararEmail, mascararCpf } from '../_shared/otp.ts'
import { enviarEmailAssinatura } from '../_shared/resend.ts'
import { anexarManifesto } from '../_shared/manifesto-pdf.ts'
import { montarLink } from '../_shared/assinatura-envio.ts'
import { EMAIL, MANIFESTO, competenciaBr } from '../_shared/assinatura-textos.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
}
const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

const BUCKET_DOC = 'assinaturas-documentos'
const BUCKET_EVID = 'assinatura-evidencias'
const ATIVOS = ['enviado', 'visualizado']
const ASSINADOS = ['assinado', 'assinado_com_ressalva']

const soDigitos = (v: unknown) => String(v ?? '').replace(/\D/g, '')

function dataUrlParaBytes(d: string): Uint8Array | null {
  const m = /^data:image\/(jpeg|jpg|png|webp);base64,(.+)$/.exec(String(d || ''))
  if (!m) return null
  const bin = atob(m[2])
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

// deno-lint-ignore no-explicit-any
type Sol = Record<string, any>

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Método não permitido' }, 405)

  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  try {
    const body = await req.json().catch(() => ({}))
    const token = String(body?.token || '')
    const acao = String(body?.acao || '')
    if (!/^[0-9a-f]{64}$/.test(token)) return json({ ok: false, erro: 'link_invalido' }, 404)

    const o = origemDaRequisicao(req)
    const origem = { ip: o.ip, user_agent: o.userAgent, assinado_em: o.assinadoEm }

    const urlAssinada = async (bucket: string, caminho: string | null) => {
      if (!caminho) return null
      const { data } = await admin.storage.from(bucket).createSignedUrl(caminho, 300)
      return data?.signedUrl ?? null
    }
    const resumo = (s: Sol, empresa?: string | null) => {
      const a = s.autenticacao || {}
      return {
        status: s.status,
        primeiro_nome: String(s.colaborador_nome || '').split(' ')[0] || null,
        empresa: empresa ?? null,
        referencia: s.referencia,
        competencia_br: competenciaBr(s.referencia),
        expira_em: s.expira_em,
        tem_email: !!s.email,
        email_mascarado: mascararEmail(s.email),
        bloqueado: !!(s.bloqueado_ate && new Date(s.bloqueado_ate) > new Date()),
        etapas: {
          cpf: !!a.cpf_validado,
          codigo: !!a.otp_validado_em,
          consentimento: !!s.consentimento_id,
          prova_vida: !!a.prova_vida,
          sem_prova_vida: !!a.sem_prova_vida,
        },
      }
    }

    // ── abrir ───────────────────────────────────────────────────────────
    if (acao === 'abrir') {
      const { data, error } = await admin.rpc('assinatura_abrir', { p_token: token, p_origem: origem })
      if (error || !data?.ok) return json({ ok: false, erro: 'link_invalido' }, 404)
      // O documento só aparece depois do CPF conferido (não vaza por link encaminhado).
      return json({ ok: true, ...resumo(data.solicitacao, data.empresa) })
    }

    const { data: sol } = await admin.rpc('assinatura_por_token', { p_token: token })
    if (!sol) return json({ ok: false, erro: 'link_invalido' }, 404)
    const aut = sol.autenticacao || {}

    // ── via (depois de assinado) ────────────────────────────────────────
    if (acao === 'via') {
      if (!ASSINADOS.includes(sol.status)) return json({ ok: false, erro: 'sem_via', status: sol.status }, 409)
      if (soDigitos(body?.cpf) !== soDigitos(sol.colaborador_cpf)) return json({ ok: false, erro: 'cpf_nao_confere' }, 403)
      return json({ ok: true, url: await urlAssinada(BUCKET_DOC, sol.assinado_path) })
    }

    if (!ATIVOS.includes(sol.status)) return json({ ok: false, erro: 'solicitacao_inativa', status: sol.status }, 409)

    // ── cpf ─────────────────────────────────────────────────────────────
    if (acao === 'cpf') {
      const { data } = await admin.rpc('assinatura_cpf_conferir', {
        p_solicitacao_id: sol.id, p_cpf: soDigitos(body?.cpf), p_origem: origem,
      })
      if (!data?.ok) return json({ ok: false, erro: data?.erro || 'cpf_nao_confere', restantes: data?.restantes }, 403)
      return json({ ok: true, url_documento: await urlAssinada(BUCKET_DOC, sol.original_path), email_mascarado: mascararEmail(sol.email) })
    }

    // Daqui em diante, só com o CPF conferido.
    if (!aut.cpf_validado) return json({ ok: false, erro: 'cpf_primeiro' }, 403)

    if (acao === 'documento') {
      return json({ ok: true, url_documento: await urlAssinada(BUCKET_DOC, sol.original_path) })
    }

    // ── código de uso único ─────────────────────────────────────────────
    if (acao === 'otp_enviar') {
      if (!sol.email) return json({ ok: false, erro: 'sem_email' }, 422)
      const codigo = gerarCodigoOtp(6)
      const { data: reg } = await admin.rpc('assinatura_otp_registrar', {
        p_solicitacao_id: sol.id, p_codigo_hash: await hashOtp(sol.id, codigo),
        p_canal: 'email', p_destino_mascarado: mascararEmail(sol.email),
      })
      if (!reg?.ok) return json({ ok: false, erro: reg?.erro || 'codigo_nao_gerado' }, 429)
      const r = await enviarEmailAssinatura(sol.email, {
        assunto: EMAIL.codigoAssunto, titulo: EMAIL.codigoTitulo, mensagem: EMAIL.codigoMensagem(codigo),
        codigo, rodape: EMAIL.rodape,
      })
      if (!r.ok) {
        await admin.rpc('assinatura_evento', { p_solicitacao_id: sol.id, p_tipo: 'otp_email_falhou', p_ator: 'sistema', p_dados: { erro: String(r.erro).slice(0, 200) } })
        return json({ ok: false, erro: 'email_falhou' }, 502)
      }
      return json({ ok: true, destino: mascararEmail(sol.email) })
    }

    if (acao === 'otp_validar') {
      const { data } = await admin.rpc('assinatura_otp_validar', {
        p_solicitacao_id: sol.id, p_codigo_hash: await hashOtp(sol.id, String(body?.codigo || '')), p_origem: origem,
      })
      if (!data?.ok) return json({ ok: false, erro: data?.erro || 'codigo_nao_confere', restantes: data?.restantes }, 403)
      return json({ ok: true })
    }

    if (!aut.otp_validado_em) return json({ ok: false, erro: 'codigo_primeiro' }, 403)

    // ── consentimento (ou recusa da câmera) ─────────────────────────────
    if (acao === 'consentimento') {
      const { data } = await admin.rpc('assinatura_registrar_consentimento', {
        p_solicitacao_id: sol.id,
        p_dados: {
          recusou: !!body?.recusou,
          versao_texto: String(body?.versao_texto || ''),
          finalidade: String(body?.finalidade || ''),
          origem,
        },
      })
      if (!data?.ok) return json({ ok: false, erro: data?.erro || 'consentimento_nao_registrado' }, 400)
      return json({ ok: true, sem_prova_vida: !!data.sem_prova_vida })
    }

    // ── prova de vida: quadros sobem por aqui (o colaborador é anônimo) ──
    if (acao === 'evidencia') {
      const quadros: string[] = Array.isArray(body?.frames) ? body.frames.slice(0, 6) : []
      if (quadros.length === 0) return json({ ok: false, erro: 'evidencia_incompleta' }, 400)
      const refs: string[] = []
      const agora = Date.now()
      for (let i = 0; i < quadros.length; i++) {
        const bytes = dataUrlParaBytes(quadros[i])
        if (!bytes || bytes.byteLength > 1_500_000) continue
        const caminho = `${sol.tenant_id}/${sol.contexto}/${sol.id}/quadro-${agora}-${i + 1}.jpg`
        const { error } = await admin.storage.from(BUCKET_EVID).upload(caminho, bytes, { contentType: 'image/jpeg', upsert: false })
        if (!error) refs.push(caminho)
      }
      if (refs.length === 0) return json({ ok: false, erro: 'evidencia_incompleta' }, 400)
      const { data } = await admin.rpc('assinatura_registrar_evidencia', {
        p_solicitacao_id: sol.id,
        p_dados: {
          frames_refs: refs,
          metodo_liveness: String(body?.metodo_liveness || 'face-landmarker'),
          versao_detector: body?.versao_detector ? String(body.versao_detector) : null,
          liveness_data: body?.liveness_data ?? null,
          origem,
        },
      })
      if (!data?.ok) {
        await admin.storage.from(BUCKET_EVID).remove(refs)
        return json({ ok: false, erro: data?.erro || 'evidencia_nao_registrada' }, 400)
      }
      return json({ ok: true, quadros: refs.length })
    }

    // ── responder ───────────────────────────────────────────────────────
    if (acao === 'responder') {
      const decisao = String(body?.decisao || '') as 'assinado' | 'assinado_com_ressalva' | 'contestado'
      if (!['assinado', 'assinado_com_ressalva', 'contestado'].includes(decisao)) {
        return json({ ok: false, erro: 'decisao_invalida' }, 400)
      }
      const texto = String(body?.texto || '').trim() || null
      const geo = body?.geolocalizacao && typeof body.geolocalizacao.lat === 'number'
        ? { lat: Number(body.geolocalizacao.lat), lng: Number(body.geolocalizacao.lng), precisao: Number(body.geolocalizacao.precisao || 0) }
        : null
      const quando = new Date().toISOString()
      const origemFinal = { ...origem, assinado_em: quando }
      const shaTexto = texto ? await sha256Hex(texto) : ''
      const cpf = soDigitos(sol.colaborador_cpf)
      const provaCodigo = String(aut.otp_evento_id || aut.login_user_id || '')
      const selo = await selarAssinatura({
        conteudo: sol.original_sha256,
        assinatura: [cpf, decisao, shaTexto, provaCodigo].join('|'),
        quando,
        id: sol.id,
      })

      const subidos: Array<[string, string]> = []
      let concluirDados: Record<string, unknown> = {
        solicitacao_id: sol.id, decisao, texto, origem: origemFinal, selo, geolocalizacao: geo,
      }

      if (decisao !== 'contestado') {
        // Rebaixa o PDF congelado e confere o hash: assina-se o que foi enviado.
        const { data: arq, error: errArq } = await admin.storage.from(BUCKET_DOC).download(sol.original_path)
        if (errArq || !arq) return json({ ok: false, erro: 'original_indisponivel' }, 500)
        const original = new Uint8Array(await arq.arrayBuffer())
        if ((await sha256Hex(original)) !== sol.original_sha256) {
          await admin.rpc('assinatura_evento', { p_solicitacao_id: sol.id, p_tipo: 'documento_alterado', p_ator: 'sistema', p_dados: {} })
          return json({ ok: false, erro: 'documento_alterado' }, 409)
        }
        const { data: emp } = await admin.from('empresa_cadastro').select('razao_social, nome_fantasia').eq('id', sol.empresa_id).maybeSingle()
        const final = await anexarManifesto(original, {
          documentoTitulo: `Espelho de Ponto ${competenciaBr(sol.referencia)}`,
          empresa: emp?.razao_social || emp?.nome_fantasia || null,
          colaboradorNome: sol.colaborador_nome || '',
          cpfMascarado: mascararCpf(cpf),
          referencia: competenciaBr(sol.referencia),
          decisao, texto,
          originalSha256: sol.original_sha256,
          assinadoEmIso: quando,
          ip: origem.ip, navegador: origem.user_agent, geolocalizacao: geo,
          canalCodigo: aut.otp_canal || null, destinoCodigoMascarado: aut.otp_destino || null,
          semProvaDeVida: !!aut.sem_prova_vida,
          metodoProvaDeVida: aut.prova_vida?.metodo_liveness || null,
          versaoDetector: aut.prova_vida?.versao_detector || null,
          versaoConsentimento: aut.consentimento_versao || null,
          solicitacaoId: sol.id, eventoCodigoId: aut.otp_evento_id || null,
          consentimentoId: sol.consentimento_id || null, selo,
        })
        const shaFinal = await sha256Hex(final)
        const caminhoAssinado = `${sol.tenant_id}/${sol.contexto}/${sol.id}/assinado.pdf`
        const { error: e1 } = await admin.storage.from(BUCKET_DOC).upload(caminhoAssinado, final, { contentType: 'application/pdf', upsert: false })
        if (e1) return json({ ok: false, erro: 'falha_ao_guardar' }, 500)
        subidos.push([BUCKET_DOC, caminhoAssinado])
        const nomeArquivo = `Espelho de Ponto assinado - ${sol.colaborador_nome} - ${sol.referencia}.pdf`
        const seguro = nomeArquivo.replace(/[^a-zA-Z0-9._-]/g, '_')
        const caminhoDoc = `${sol.tenant_id}/colaboradores/${sol.colaborador_id || 'sem-id'}/${Date.now()}_${seguro}`
        const { error: e2 } = await admin.storage.from('documentos').upload(caminhoDoc, final, { contentType: 'application/pdf', upsert: false })
        if (e2) {
          await admin.storage.from(BUCKET_DOC).remove([caminhoAssinado])
          return json({ ok: false, erro: 'falha_ao_guardar' }, 500)
        }
        subidos.push(['documentos', caminhoDoc])
        concluirDados = {
          ...concluirDados,
          assinado_path: caminhoAssinado, assinado_sha256: shaFinal, assinado_bytes: final.byteLength,
          documento_storage_path: caminhoDoc, nome_arquivo: nomeArquivo,
        }
      }

      const { data: fim, error: errFim } = await admin.rpc('assinatura_concluir', { p_dados: concluirDados })
      if (errFim || !fim?.ok) {
        for (const [b, c] of subidos) await admin.storage.from(b).remove([c])
        return json({ ok: false, erro: fim?.erro || 'nao_concluido', detalhe: errFim?.message }, 409)
      }

      // Via do trabalhador: link para a mesma página (nunca o PDF anexado).
      if (sol.email) {
        const nome = String(sol.colaborador_nome || '').split(' ')[0] || ''
        const r = await enviarEmailAssinatura(sol.email, {
          assunto: EMAIL.viaAssunto(competenciaBr(sol.referencia)),
          titulo: EMAIL.viaTitulo,
          mensagem: EMAIL.viaMensagem(nome, competenciaBr(sol.referencia), MANIFESTO.decisoes[decisao] || decisao),
          actionUrl: montarLink(sol.link_base, token), actionLabel: EMAIL.botaoVia, rodape: EMAIL.rodape,
        })
        await admin.rpc('assinatura_registrar_envio', {
          p_solicitacao_id: sol.id, p_tipo: 'via', p_ok: r.ok, p_erro: r.erro ?? null, p_manter_fila: false, p_dados: {},
        })
      }
      return json({ ok: true, status: fim.status })
    }

    return json({ ok: false, erro: 'acao_desconhecida' }, 400)
  } catch (e) {
    console.error('[assinatura-documento]', e)
    return json({ ok: false, erro: 'erro_interno' }, 500)
  }
})
