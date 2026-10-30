/// <reference types="npm:@types/react@18.3.1" />
// E-mails da assinatura eletrônica (convite, lembrete, código e via).
// Os TEXTOS vêm de ../assinatura-textos.ts (arquivo único da revisão jurídica);
// aqui fica só o leiaute. Nunca anexa o documento: só o botão com o link.
import * as React from 'npm:react@18.3.1'
import {
  Img, Body, Button, Container, Head, Heading, Hr, Html, Preview, Section, Text,
} from 'npm:@react-email/components@0.0.22'
import { LOGO_EMAIL_URL } from '../marca.ts'

export interface AssinaturaEmailProps {
  assunto: string
  titulo: string
  mensagem: string
  /** Código de uso único em destaque (só no e-mail de código). */
  codigo?: string
  actionUrl?: string
  actionLabel?: string
  rodape?: string
}

export const AssinaturaSolicitadaEmail = ({
  assunto, titulo, mensagem, codigo, actionUrl, actionLabel, rodape,
}: AssinaturaEmailProps) => (
  <Html lang="pt-BR" dir="ltr">
    <Head />
    <Preview>{assunto}</Preview>
    <Body style={main}>
      <Container style={container}>
        <Section style={logoSection}><Img src={LOGO_EMAIL_URL} alt="YourEyes" width="64" height="64" style={{ margin: '0 auto', display: 'block' }} /></Section>
        <Hr style={divider} />
        <Heading style={h1}>{titulo}</Heading>
        <Text style={text}>{mensagem}</Text>
        {codigo && <Text style={codigoStyle}>{codigo}</Text>}
        {actionUrl && (
          <Section style={buttonContainer}>
            <Button style={button} href={actionUrl}>{actionLabel || 'Abrir'}</Button>
          </Section>
        )}
        <Hr style={divider} />
        {rodape && <Text style={brand}>{rodape}</Text>}
        <Text style={brand}>YourEyes — Inteligência que protege. Visão que antecipa.</Text>
      </Container>
    </Body>
  </Html>
)

const main = { backgroundColor: '#ffffff', fontFamily: "'Inter', Arial, sans-serif" }
const container = { padding: '32px 28px', maxWidth: '480px', margin: '0 auto' }
const logoSection = { textAlign: 'center' as const, marginBottom: '8px' }
const divider = { borderColor: '#e8e5f0', margin: '16px 0' }
const h1 = { fontSize: '22px', fontWeight: 'bold' as const, color: 'hsl(260, 20%, 16%)', margin: '0 0 16px' }
const text = { fontSize: '14px', color: 'hsl(260, 10%, 46%)', lineHeight: '1.6', margin: '0 0 20px' }
const codigoStyle = { fontSize: '32px', fontWeight: 'bold' as const, letterSpacing: '8px', textAlign: 'center' as const, color: 'hsl(260, 20%, 16%)', margin: '8px 0 20px' }
const buttonContainer = { textAlign: 'center' as const, margin: '24px 0' }
const button = { backgroundColor: 'hsl(262, 52%, 50%)', color: '#ffffff', fontSize: '14px', fontWeight: '600' as const, borderRadius: '10px', padding: '14px 28px', textDecoration: 'none' }
const brand = { fontSize: '11px', color: '#b3b3b3', textAlign: 'center' as const, margin: '8px 0 0' }
