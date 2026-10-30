/// <reference types="npm:@types/react@18.3.1" />

import * as React from 'npm:react@18.3.1'

import {
  Img,
  Body,
  Container,
  Head,
  Heading,
  Hr,
  Html,
  Preview,
  Section,
  Text,
} from 'npm:@react-email/components@0.0.22'
import { LOGO_EMAIL_URL } from '../marca.ts'

interface ReauthenticationEmailProps {
  token: string
}

export const ReauthenticationEmail = ({ token }: ReauthenticationEmailProps) => (
  <Html lang="pt-BR" dir="ltr">
    <Head />
    <Preview>Seu código de verificação — YourEyes</Preview>
    <Body style={main}>
      <Container style={container}>
        <Section style={logoSection}>
          <Img src={LOGO_EMAIL_URL} alt="YourEyes" width="64" height="64" style={{ margin: '0 auto', display: 'block' }} />
        </Section>
        <Hr style={divider} />
        <Heading style={h1}>Código de verificação</Heading>
        <Text style={text}>Use o código abaixo para confirmar sua identidade:</Text>
        <Text style={codeStyle}>{token}</Text>
        <Text style={footer}>
          Este código expira em breve. Se você não solicitou este código,
          pode ignorar este e-mail com segurança.
        </Text>
        <Hr style={divider} />
        <Text style={brand}>
          YourEyes — Plataforma de SST
        </Text>
      </Container>
    </Body>
  </Html>
)

export default ReauthenticationEmail

const main = { backgroundColor: '#ffffff', fontFamily: "'Inter', Arial, sans-serif" }
const container = { padding: '32px 28px', maxWidth: '480px', margin: '0 auto' }
const logoSection = { textAlign: 'center' as const, marginBottom: '8px' }
const logoText = { fontSize: '24px', fontWeight: 'bold' as const, color: 'hsl(262, 52%, 50%)', margin: '0' }
const divider = { borderColor: '#e8e5f0', margin: '16px 0' }
const h1 = {
  fontSize: '22px',
  fontWeight: 'bold' as const,
  color: 'hsl(260, 20%, 16%)',
  margin: '0 0 16px',
}
const text = {
  fontSize: '14px',
  color: 'hsl(260, 10%, 46%)',
  lineHeight: '1.6',
  margin: '0 0 20px',
}
const codeStyle = {
  fontFamily: 'Courier, monospace',
  fontSize: '28px',
  fontWeight: 'bold' as const,
  color: 'hsl(262, 52%, 50%)',
  margin: '0 0 30px',
  textAlign: 'center' as const,
  letterSpacing: '4px',
}
const footer = { fontSize: '12px', color: '#999999', margin: '24px 0 0' }
const brand = { fontSize: '11px', color: '#b3b3b3', textAlign: 'center' as const, margin: '8px 0 0' }
