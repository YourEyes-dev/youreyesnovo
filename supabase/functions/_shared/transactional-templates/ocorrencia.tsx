/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import {
  Img,
  Body, Container, Head, Heading, Hr, Html, Preview, Section, Text,
} from 'npm:@react-email/components@0.0.22'
import { LOGO_EMAIL_URL } from '../marca.ts'

interface Props {
  colaborador?: string
  tipo?: string
  descricao?: string
  dataOcorrencia?: string
}

export const OcorrenciaEmail = ({ colaborador, tipo, descricao, dataOcorrencia }: Props) => (
  <Html lang="pt-BR" dir="ltr">
    <Head />
    <Preview>Ocorrência registrada — {tipo || ''}</Preview>
    <Body style={main}>
      <Container style={container}>
        <Section style={logoSection}><Img src={LOGO_EMAIL_URL} alt="YourEyes" width="64" height="64" style={{ margin: '0 auto', display: 'block' }} /></Section>
        <Hr style={divider} />
        <Heading style={h1}>🔔 Ocorrência Registrada</Heading>
        {colaborador && <Text style={text}><strong>Colaborador:</strong> {colaborador}</Text>}
        {tipo && <Text style={text}><strong>Tipo:</strong> {tipo}</Text>}
        {dataOcorrencia && <Text style={text}><strong>Data:</strong> {dataOcorrencia}</Text>}
        {descricao && <Text style={text}>{descricao}</Text>}
        <Text style={text}>Acesse a plataforma para registrar ações corretivas.</Text>
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
const brand = { fontSize: '11px', color: '#b3b3b3', textAlign: 'center' as const, margin: '8px 0 0' }
