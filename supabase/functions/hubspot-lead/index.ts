// Supabase Edge Function: hubspot-lead — cria/atualiza o contato no HubSpot.
//
// Chamada pelo navegador ao concluir o diagnóstico do site, sem login
// (verify_jwt = false), em text/plain. O token do HubSpot vive só aqui.
// A proteção de ambiente é a origem (ver _shared/site-lead.ts).
//
// Secrets (Project Settings → Edge Functions → Secrets):
//   HUBSPOT_PRIVATE_APP_TOKEN  obrigatório — token de um Private App do
//                              HubSpot com os escopos
//                              crm.objects.contacts.read e .write.
//   SITE_HOSTS_PERMITIDOS      opcional — hosts aceitos (padrão: produção).
//
// LGPD: grava só o que a pessoa digitou (nome, e-mail, empresa, cargo,
// WhatsApp), o porte, o ÍNDICE agregado do diagnóstico e a origem da
// campanha. As respostas individuais do questionário não são aceitas aqui:
// qualquer campo fora da lista é ignorado.
//
// Upsert por e-mail: PATCH /contacts/{email}?idProperty=email; se o contato
// não existe (404), POST cria. Se o HubSpot recusar alguma propriedade
// personalizada (ex.: opção de enum que não existe), tenta de novo só com
// as nativas — o contato não se perde por causa de um campo.
// Nunca devolve erro que quebre a tela: responde 200 com { enviado }.
import {
  corsHeaders, dominioEmail, EMAIL_RE, hostDaChamada, hostPermitido, json,
  lerCorpo, telefoneE164, texto,
} from "../_shared/site-lead.ts";

const API = "https://api.hubapi.com/crm/v3/objects/contacts";

/** Formulários aceitos e o sinal de intenção que cada um grava. */
const FORMULARIOS: Record<string, string> = {
  "site-diagnostico-psicossocial": "fez_diagnostico",
};

const ANGULOS = new Set(["sst", "jornada", "documentos", "pessoas", "dho", "estrategia"]);

/** Faixa de porte → número (limite superior da faixa, preserva a faixa em
 *  qualquer corte de ICP; "500 ou mais" vira 500). */
const PORTE_NUMERO: Record<string, number> = {
  ate_19: 19,
  "20_99": 99,
  "100_499": 499,
  "500_mais": 500,
};

const NATIVAS = new Set(["email", "firstname", "lastname", "company", "jobtitle", "phone", "numberofemployees"]);

type Props = Record<string, string>;

async function chamar(token: string, metodo: "PATCH" | "POST", url: string, properties: Props) {
  const r = await fetch(url, {
    method: metodo,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ properties }),
    signal: AbortSignal.timeout(8000),
  });
  const corpo = await r.json().catch(() => ({}));
  return { status: r.status, ok: r.ok, corpo: corpo as Record<string, unknown> };
}

async function upsert(token: string, email: string, properties: Props) {
  const urlEmail = `${API}/${encodeURIComponent(email)}?idProperty=email`;
  let r = await chamar(token, "PATCH", urlEmail, properties);
  if (r.status === 404) {
    r = await chamar(token, "POST", API, properties);
    // Corrida: outro envio criou o contato entre o PATCH e o POST.
    if (r.status === 409) r = await chamar(token, "PATCH", urlEmail, properties);
  }
  return r;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "Método não permitido" }, 405);

  const host = hostDaChamada(req);
  if (!hostPermitido(host)) {
    console.log(`[hubspot-lead] ignorado: host não permitido (${host || "sem origem"})`);
    return json(req, { enviado: false, motivo: "host_nao_permitido" });
  }

  const token = (Deno.env.get("HUBSPOT_PRIVATE_APP_TOKEN") ?? "").trim();
  if (!token) {
    console.warn(
      "[hubspot-lead] NÃO ENVIADO: falta o secret HUBSPOT_PRIVATE_APP_TOKEN neste projeto " +
        "(Project Settings → Edge Functions → Secrets).",
    );
    return json(req, { enviado: false, motivo: "sem_configuracao" });
  }

  const c = await lerCorpo(req);
  if (!c) return json(req, { enviado: false, motivo: "corpo_invalido" }, 400);

  const formulario = texto(c.formulario, 80);
  const sinal = FORMULARIOS[formulario];
  const email = texto(c.email, 320).toLowerCase();
  const nome = texto(c.nome, 200);
  // Só envia se a pessoa forneceu os dados no formulário (LGPD).
  if (!sinal || !EMAIL_RE.test(email) || !nome) {
    return json(req, { enviado: false, motivo: "dados_insuficientes" }, 400);
  }

  const [primeiro, ...resto] = nome.split(/\s+/);
  const props: Props = { email, firstname: primeiro };
  if (resto.length) props.lastname = resto.join(" ");
  const empresa = texto(c.empresa, 300);
  if (empresa) props.company = empresa;
  const cargo = texto(c.cargo, 200);
  if (cargo) props.jobtitle = cargo;
  const tel = telefoneE164(c.telefone);
  if (tel) props.phone = `+${tel}`;
  const porte = PORTE_NUMERO[texto(c.porte, 20)];
  if (porte) props.numberofemployees = String(porte);

  props.ye_sinal_intencao = sinal;
  const score = Number(c.score);
  if (c.score !== undefined && c.score !== null && Number.isFinite(score)) {
    props.ye_diagnostico_score = String(Math.max(0, Math.min(100, Math.round(score))));
  }
  const angulo = texto(c.angulo_dor, 20);
  if (ANGULOS.has(angulo)) props.ye_angulo_dor = angulo;
  const fonte = texto(c.fonte_origem, 500);
  if (fonte) props.ye_fonte_origem = fonte;

  try {
    let r = await upsert(token, email, props);
    let soNativas = false;
    if (r.status === 400) {
      console.warn("[hubspot-lead] HubSpot recusou propriedade personalizada; reenviando só as nativas:",
        JSON.stringify(r.corpo?.message ?? r.corpo).slice(0, 500));
      const nativas: Props = {};
      for (const [k, v] of Object.entries(props)) if (NATIVAS.has(k)) nativas[k] = v;
      r = await upsert(token, email, nativas);
      soNativas = true;
    }
    if (!r.ok) {
      console.error(`[hubspot-lead] falhou (${r.status}) para @${dominioEmail(email)}:`,
        JSON.stringify(r.corpo?.message ?? r.corpo).slice(0, 500));
      return json(req, { enviado: false, motivo: "hubspot_recusou", status: r.status });
    }
    console.log(
      `[hubspot-lead] contato ${String(r.corpo?.id ?? "?")} gravado (@${dominioEmail(email)}) ` +
        `angulo=${props.ye_angulo_dor ?? "-"} score=${props.ye_diagnostico_score ?? "-"} soNativas=${soNativas}`,
    );
    return json(req, { enviado: true, contato_id: r.corpo?.id ?? null, so_nativas: soNativas });
  } catch (e) {
    console.error("[hubspot-lead] falha de rede:", (e as Error).message);
    return json(req, { enviado: false, motivo: "falha_rede" });
  }
});
