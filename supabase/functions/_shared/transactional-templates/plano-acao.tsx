/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import {
  Img,
  Body, Button, Container, Head, Heading, Hr, Html, Preview, Section, Text,
} from 'npm:@react-email/components@0.0.22'
import { LOGO_EMAIL_URL } from '../marca.ts'

interface Props {
  titulo?: string
  responsavel?: string
  prazo?: string
  prioridade?: string
  descricao?: string
  actionUrl?: string
}

export const PlanoAcaoEmail = ({ titulo, responsavel, prazo, prioridade, descricao, actionUrl }: Props) => (
  <Html lang="pt-BR" dir="ltr">
    <Head />
    <Preview>Plano de Ação: {titulo || 'Nova ação atribuída'}</Preview>
    <Body style={main}>
      <Container style={container}>
        <Section style={logoSection}><Img src={LOGO_EMAIL_URL} alt="YourEyes" width="64" height="64" style={{ margin: '0 auto', display: 'block' }} /></Section>
        <Hr style={divider} />
        <Heading style={h1}>📌 Nova Ação Atribuída</Heading>
        {titulo && <Text style={text}><strong>Ação:</strong> {titulo}</Text>}
        {responsavel && <Text style={text}><strong>Responsável:</strong> {responsavel}</Text>}
        {prazo && <Text style={text}><strong>Prazo:</strong> {prazo}</Text>}
        {prioridade && <Text style={text}><strong>Prioridade:</strong> {prioridade}</Text>}
        {descricao && <Text style={text}>{descricao}</Text>}
        {actionUrl && (
          <Section style={buttonContainer}>
            <Button style={button} href={actionUrl}>Ver Plano de Ação</Button>
          </Section>
        )}
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
const buttonContainer = { textAlign: 'center' as const, margin: '24px 0' }
const button = { backgroundColor: 'hsl(262, 52%, 50%)', color: '#ffffff', fontSize: '14px', fontWeight: '600' as const, borderRadius: '10px', padding: '14px 28px', textDecoration: 'none' }
const brand = { fontSize: '11px', color: '#b3b3b3', textAlign: 'center' as const, margin: '8px 0 0' }
