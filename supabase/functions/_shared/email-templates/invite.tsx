/// <reference types="npm:@types/react@18.3.1" />

import * as React from 'npm:react@18.3.1'

import {
  Body,
  Button,
  Container,
  Head,
  Heading,
  Hr,
  Html,
  Img,
  Link,
  Preview,
  Section,
  Text,
} from 'npm:@react-email/components@0.0.22'
import { LOGO_EMAIL_URL } from '../marca.ts'


interface InviteEmailProps {
  siteName: string
  siteUrl: string
  confirmationUrl: string
}

export const InviteEmail = ({
  siteName,
  siteUrl,
  confirmationUrl,
}: InviteEmailProps) => (
  <Html lang="pt-BR" dir="ltr">
    <Head />
    <Preview>Você foi convidado(a) para o YourEyes</Preview>
    <Body style={main}>
      <Container style={container}>
        <Section style={logoSection}>
          <Img src={LOGO_EMAIL_URL} alt="YourEyes" width="64" height="64" style={{ margin: '0 auto', display: 'block' }} />
        </Section>
        <Hr style={divider} />
        <Heading style={h1}>Você foi convidado(a)!</Heading>
        <Text style={text}>
          Você recebeu um convite para acessar a plataforma{' '}
          <Link href={siteUrl} style={link}>
            <strong>YourEyes</strong>
          </Link>
          , a solução completa em Saúde e Segurança do Trabalho.
        </Text>
        <Text style={text}>
          Clique no botão abaixo para aceitar o convite e configurar sua conta:
        </Text>
        <Section style={buttonContainer}>
          <Button style={button} href={confirmationUrl}>
            Aceitar Convite
          </Button>
        </Section>
        <Text style={footer}>
          Se você não esperava este convite, pode ignorar este e-mail com segurança.
        </Text>
        <Hr style={divider} />
        <Text style={brand}>
          YourEyes — Plataforma de SST
        </Text>
      </Container>
    </Body>
  </Html>
)

export default InviteEmail

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
const link = { color: 'hsl(262, 52%, 50%)', textDecoration: 'underline' }
const buttonContainer = { textAlign: 'center' as const, margin: '24px 0' }
const button = {
  backgroundColor: 'hsl(262, 52%, 50%)',
  color: '#ffffff',
  fontSize: '14px',
  fontWeight: '600' as const,
  borderRadius: '10px',
  padding: '14px 28px',
  textDecoration: 'none',
}
const footer = { fontSize: '12px', color: '#999999', margin: '24px 0 0' }
const brand = { fontSize: '11px', color: '#b3b3b3', textAlign: 'center' as const, margin: '8px 0 0' }
