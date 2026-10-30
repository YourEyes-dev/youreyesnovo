/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import {
  Img,
  Body, Container, Head, Heading, Hr, Html, Preview, Section, Text,
} from 'npm:@react-email/components@0.0.22'
import { LOGO_EMAIL_URL } from '../marca.ts'

interface Props {
  titulo?: string
  colaborador?: string
  descricao?: string
  prioridade?: string
}

export const AlertaSaudeEmail = ({ titulo, colaborador, descricao, prioridade }: Props) => (
  <Html lang="pt-BR" dir="ltr">
    <Head />
    <Preview>Alerta de Saúde — {titulo || 'Ação necessária'}</Preview>
    <Body style={main}>
      <Container style={container}>
        <Section style={logoSection}><Img src={LOGO_EMAIL_URL} alt="YourEyes" width="64" height="64" style={{ margin: '0 auto', display: 'block' }} /></Section>
        <Hr style={divider} />
        <Heading style={h1}>⚠️ Alerta de Saúde</Heading>
        {titulo && <Text style={text}><strong>Alerta:</strong> {titulo}</Text>}
        {colaborador && <Text style={text}><strong>Colaborador:</strong> {colaborador}</Text>}
        {descricao && <Text style={text}>{descricao}</Text>}
        {prioridade && (
          <Section style={badgeSection}>
            <Text style={prioridade === 'alta' || prioridade === 'critica' ? badgeHigh : badgeNormal}>
              Prioridade: {prioridade.toUpperCase()}
            </Text>
          </Section>
        )}
        <Text style={text}>Acesse a plataforma para mais detalhes e registrar a ação necessária.</Text>
        <Hr style={divider} />
        <Text style={brand}>YourEyes — Inteligência que protege. Visão que antecipa.</Text>
      </Container>
    </Body>
  </Html>
)

const main = { backgroundColor: '#ffffff', fontFamily: "'Inter', Arial, sans-serif" }
const container = { padding: '32px 28px', maxWidth: '480px', margin: '0 auto' }
const logoSection = { textAlign: 'center' as const, marginBottom: '8px' }
const logoText = { fontSize: '24px', fontWeight: 'bold' as const, color: 'hsl(262, 52%, 50%)', margin: '0' }
const divider = { borderColor: '#e8e5f0', margin: '16px 0' }
const h1 = { fontSize: '22px', fontWeight: 'bold' as const, color: 'hsl(260, 20%, 16%)', margin: '0 0 16px' }
const text = { fontSize: '14px', color: 'hsl(260, 10%, 46%)', lineHeight: '1.6', margin: '0 0 12px' }
const badgeSection = { margin: '16px 0' }
const badgeHigh = { display: 'inline-block' as const, backgroundColor: '#fee2e2', color: '#dc2626', padding: '4px 12px', borderRadius: '6px', fontSize: '12px', fontWeight: '600' as const }
const badgeNormal = { display: 'inline-block' as const, backgroundColor: '#fef3c7', color: '#d97706', padding: '4px 12px', borderRadius: '6px', fontSize: '12px', fontWeight: '600' as const }
const brand = { fontSize: '11px', color: '#b3b3b3', textAlign: 'center' as const, margin: '8px 0 0' }
