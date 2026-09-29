/**
 * Envio do lead do site para o HubSpot — sempre pelo SERVIDOR.
 *
 * O navegador só chama a Edge Function `hubspot-lead`; o token do HubSpot
 * vive como secret lá (HUBSPOT_PRIVATE_APP_TOKEN) e nunca chega ao front.
 *
 * LGPD: vai só o que a pessoa digitou no formulário (nome, empresa, cargo,
 * e-mail, WhatsApp), o porte da empresa, o ÍNDICE agregado do diagnóstico e
 * a origem da campanha. As respostas individuais do questionário NÃO saem
 * daqui — o tipo abaixo nem tem campo para elas.
 *
 * Fire-and-forget: nunca lança e nunca é aguardado pela tela. Mesmo formato
 * de chamada do `meta-capi` (text/plain, sem preflight, keepalive).
 */

import { anguloDaCampanha, fonteOrigemTexto, type OrigemVisita } from "@/lib/siteOrigem";

const HUBSPOT_URL = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/hubspot-lead`;

export interface LeadHubspot {
  email: string;
  nome: string;
  empresa?: string | null;
  cargo?: string | null;
  telefone?: string | null;
  /** Faixa de porte do diagnóstico (ate_19, 20_99, 100_499, 500_mais). */
  porte?: string | null;
  /** Índice agregado 0–100 do diagnóstico. Nunca as respostas. */
  score?: number | null;
  /** Identifica o formulário de origem (ex.: site-diagnostico-psicossocial). */
  formulario: string;
  origem?: OrigemVisita | null;
}

/** Monta o corpo enviado à função (exportado para teste). */
export function montarCorpoHubspot(lead: LeadHubspot) {
  const o = lead.origem ?? {};
  return {
    email: lead.email.trim().toLowerCase(),
    nome: lead.nome.trim(),
    empresa: lead.empresa?.trim() || undefined,
    cargo: lead.cargo?.trim() || undefined,
    telefone: lead.telefone?.replace(/\D/g, "") || undefined,
    porte: lead.porte || undefined,
    score: typeof lead.score === "number" ? lead.score : undefined,
    formulario: lead.formulario,
    angulo_dor: anguloDaCampanha(o.utm_campaign) ?? undefined,
    fonte_origem: fonteOrigemTexto(o) || undefined,
    utm: {
      utm_source: o.utm_source,
      utm_medium: o.utm_medium,
      utm_campaign: o.utm_campaign,
      utm_content: o.utm_content,
      utm_term: o.utm_term,
    },
    pagina: typeof window !== "undefined" ? window.location.href : undefined,
  };
}

export function enviarLeadHubspot(lead: LeadHubspot): void {
  try {
    void fetch(HUBSPOT_URL, {
      method: "POST",
      headers: { "Content-Type": "text/plain;charset=UTF-8" },
      keepalive: true,
      body: JSON.stringify(montarCorpoHubspot(lead)),
    }).catch((e) => console.warn("[hubspot] envio do lead falhou:", e));
  } catch (e) {
    console.warn("[hubspot] envio do lead falhou:", e);
  }
}
