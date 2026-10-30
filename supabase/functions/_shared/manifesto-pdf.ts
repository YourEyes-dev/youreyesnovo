// =====================================================================
// Manifesto de evidências: a ÚLTIMA página do PDF assinado.
//
// Recebe o PDF original (o congelado no envio, já conferido pelo hash) e
// devolve um PDF novo = original + 1 página com as evidências da assinatura.
// O PDF original não é regerado nem alterado: as páginas são copiadas como
// estão. O hash do PDF final é calculado depois por quem chama e guardado no
// banco (não cabe dentro do próprio arquivo).
//
// Textos: ./assinatura-textos.ts (arquivo único da revisão jurídica).
// Fonte padrão Helvetica (WinAnsi): acentos do português ok; nada de emoji.
// =====================================================================
import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from 'npm:pdf-lib@1.17.1'
import { MANIFESTO, VERSAO_TEXTOS_ASSINATURA } from './assinatura-textos.ts'

export interface DadosManifesto {
  documentoTitulo: string
  empresa: string | null
  colaboradorNome: string
  cpfMascarado: string
  referencia: string
  decisao: 'assinado' | 'assinado_com_ressalva' | 'contestado'
  texto?: string | null
  originalSha256: string
  /** Hora do servidor (ISO UTC com ms) — a mesma usada no selo. */
  assinadoEmIso: string
  ip: string | null
  navegador: string | null
  geolocalizacao?: { lat?: number; lng?: number; precisao?: number } | null
  canalCodigo: string | null
  destinoCodigoMascarado: string | null
  semProvaDeVida: boolean
  metodoProvaDeVida?: string | null
  versaoDetector?: string | null
  versaoConsentimento?: string | null
  solicitacaoId: string
  eventoCodigoId?: string | null
  consentimentoId?: string | null
  /** Selo sha256 calculado pela borda (o banco confere que é o mesmo da trilha). */
  selo: string
}

const AZUL = rgb(0.06, 0.17, 0.33)
const CINZA = rgb(0.35, 0.38, 0.45)

function quebrar(texto: string, fonte: PDFFont, tamanho: number, largura: number): string[] {
  const linhas: string[] = []
  for (const paragrafo of String(texto || '').split(/\r?\n/)) {
    let atual = ''
    for (const palavra of paragrafo.split(/\s+/).filter(Boolean)) {
      const tentativa = atual ? `${atual} ${palavra}` : palavra
      if (fonte.widthOfTextAtSize(tentativa, tamanho) <= largura) {
        atual = tentativa
      } else {
        if (atual) linhas.push(atual)
        // Palavra maior que a linha (ex.: hash): corta em pedaços.
        let resto = palavra
        while (fonte.widthOfTextAtSize(resto, tamanho) > largura && resto.length > 1) {
          let n = resto.length
          while (n > 1 && fonte.widthOfTextAtSize(resto.slice(0, n), tamanho) > largura) n--
          linhas.push(resto.slice(0, n))
          resto = resto.slice(n)
        }
        atual = resto
      }
    }
    linhas.push(atual)
  }
  return linhas
}

/** Hora de Brasília (UTC-3) formatada a partir do ISO UTC. */
function horaBrasilia(iso: string): string {
  const d = new Date(Date.parse(iso) - 3 * 3600 * 1000)
  const p = (n: number) => String(n).padStart(2, '0')
  return `${p(d.getUTCDate())}/${p(d.getUTCMonth() + 1)}/${d.getUTCFullYear()} ${p(d.getUTCHours())}:${p(d.getUTCMinutes())}:${p(d.getUTCSeconds())}`
}

/** Remove caracteres fora do WinAnsi (a fonte padrão não os desenha). */
function limpar(t: string | null | undefined): string {
  return String(t ?? '').replace(/[^\x20-\x7E\xA0-\xFF–—‘’“”•…\n]/g, '?')
}

export async function anexarManifesto(original: Uint8Array, d: DadosManifesto): Promise<Uint8Array> {
  const pdf = await PDFDocument.load(original, { updateMetadata: false })
  const fonte = await pdf.embedFont(StandardFonts.Helvetica)
  const negrito = await pdf.embedFont(StandardFonts.HelveticaBold)
  const largura = 595.28
  const altura = 841.89
  const margem = 48
  const util = largura - 2 * margem
  let pagina: PDFPage = pdf.addPage([largura, altura])
  let y = altura - margem

  const novaPaginaSePreciso = (espaco: number) => {
    if (y - espaco < margem + 30) {
      pagina = pdf.addPage([largura, altura])
      y = altura - margem
    }
  }
  const escrever = (t: string, opt: { tam?: number; f?: PDFFont; cor?: ReturnType<typeof rgb>; espaco?: number } = {}) => {
    const tam = opt.tam ?? 9.5
    const f = opt.f ?? fonte
    for (const linha of quebrar(limpar(t), f, tam, util)) {
      novaPaginaSePreciso(tam + 4)
      pagina.drawText(linha, { x: margem, y, size: tam, font: f, color: opt.cor ?? rgb(0.1, 0.1, 0.12) })
      y -= tam + 3.5
    }
    y -= opt.espaco ?? 2
  }
  const campo = (rotulo: string, valor: string | null | undefined) => {
    escrever(`${rotulo}: ${valor && String(valor).trim() ? valor : '-'}`)
  }

  // Faixa do título
  pagina.drawRectangle({ x: 0, y: altura - 70, width: largura, height: 70, color: AZUL })
  pagina.drawText(limpar(MANIFESTO.titulo), { x: margem, y: altura - 38, size: 15, font: negrito, color: rgb(1, 1, 1) })
  pagina.drawText(limpar(MANIFESTO.subtitulo), { x: margem, y: altura - 56, size: 9, font: fonte, color: rgb(0.85, 0.89, 0.95) })
  y = altura - 96

  escrever('Documento', { f: negrito, tam: 11, cor: AZUL })
  campo('Documento', d.documentoTitulo)
  campo('Empresa', d.empresa)
  campo('Referência', d.referencia)
  campo('Código SHA-256 do documento original', d.originalSha256)
  escrever(MANIFESTO.notaIntegridade, { tam: 8, cor: CINZA, espaco: 8 })

  escrever('Signatário e decisão', { f: negrito, tam: 11, cor: AZUL })
  campo('Nome', d.colaboradorNome)
  campo('CPF (conferido no servidor)', d.cpfMascarado)
  campo('Decisão', MANIFESTO.decisoes[d.decisao] || d.decisao)
  if (d.texto && d.texto.trim()) campo(d.decisao === 'contestado' ? 'Motivo' : 'Ressalva', d.texto)
  y -= 6

  escrever('Evidências', { f: negrito, tam: 11, cor: AZUL })
  campo('Data e hora (UTC)', d.assinadoEmIso)
  campo('Data e hora (Brasília)', horaBrasilia(d.assinadoEmIso))
  campo('Endereço IP', d.ip)
  campo('Navegador', d.navegador)
  const geo = d.geolocalizacao && typeof d.geolocalizacao.lat === 'number'
    ? `${d.geolocalizacao.lat?.toFixed(5)}, ${d.geolocalizacao.lng?.toFixed(5)} (precisão ${Math.round(d.geolocalizacao.precisao ?? 0)} m, informada pelo aparelho)`
    : 'não informada'
  campo('Geolocalização', geo)
  campo('Código de confirmação', d.canalCodigo ? `${d.canalCodigo} ${d.destinoCodigoMascarado || ''}`.trim() : null)
  campo('Prova de vida', d.semProvaDeVida
    ? MANIFESTO.semProvaDeVida
    : `${MANIFESTO.comProvaDeVida} Método: ${d.metodoProvaDeVida || '-'}; detector: ${d.versaoDetector || '-'}.`)
  campo('Versão do consentimento', d.semProvaDeVida ? 'não se aplica' : d.versaoConsentimento)
  y -= 6

  escrever('Identificadores', { f: negrito, tam: 11, cor: AZUL })
  campo('Solicitação', d.solicitacaoId)
  campo('Evento do código', d.eventoCodigoId)
  campo('Consentimento', d.consentimentoId)
  campo('Selo da assinatura (SHA-256)', d.selo)
  campo('Versão dos textos', VERSAO_TEXTOS_ASSINATURA)
  y -= 4
  escrever(MANIFESTO.notaRodape, { tam: 8, cor: CINZA })

  return await pdf.save({ useObjectStreams: false })
}
