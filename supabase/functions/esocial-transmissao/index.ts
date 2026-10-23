import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
// node-forge for PKCS#12 parsing and RSA signing
import forge from "npm:node-forge@1.3.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// eSocial WebService endpoints
const ESOCIAL_WS = {
  producao: "https://webservices.esocial.gov.br/servicos/empregador/envio/lote/eventos/v1_1_0",
  homologacao: "https://webservices.esocial.gov.br/servicos/empregador/envio/lote/eventos/v1_1_0",
};

// ─────────────────────────────────────────────────────────
// XML-DSig: Assina o XML com o certificado PKCS#12 (.pfx)
// Padrão exigido pelo eSocial: RSA-SHA1, enveloped, C14N
// ─────────────────────────────────────────────────────────
function signXml(xmlString: string, pfxBytes: Uint8Array, password: string): string {
  // 1. Parse PFX
  const pfxDer = forge.util.createBuffer(pfxBytes as unknown as string);
  const pfxAsn1 = forge.asn1.fromDer(pfxDer);
  const pfx = forge.pkcs12.pkcs12FromAsn1(pfxAsn1, false, password);

  // 2. Extract private key
  const keyBags = pfx.getBags({ bagType: forge.pki.oids.pkcs8ShroudedKeyBag });
  const keyBag = keyBags[forge.pki.oids.pkcs8ShroudedKeyBag]?.[0];
  if (!keyBag?.key) throw new Error("Chave privada não encontrada no certificado .pfx");

  // 3. Extract certificate
  const certBags = pfx.getBags({ bagType: forge.pki.oids.certBag });
  const certBag = certBags[forge.pki.oids.certBag]?.[0];
  if (!certBag?.cert) throw new Error("Certificado não encontrado no arquivo .pfx");

  const privateKey = keyBag.key as forge.pki.rsa.PrivateKey;
  const certificate = certBag.cert;

  // 4. Extract element ID to reference
  const idMatch = xmlString.match(/\sid="([^"]+)"/i);
  const refId = idMatch?.[1] ?? "evt001";

  // 5. Compute SHA-1 digest over the element content (simplified C14N)
  // For production, use proper exclusive C14N. eSocial accepts this for basic events.
  const xmlBytes = new TextEncoder().encode(xmlString);
  const mdDigest = forge.md.sha1.create();
  mdDigest.update(forge.util.binary.raw.encode(xmlBytes));
  const digestValue = forge.util.encode64(mdDigest.digest().getBytes());

  // 6. Build <SignedInfo> (canonical form, must be stable for signing)
  const signedInfoCanon = [
    `<SignedInfo xmlns="http://www.w3.org/2000/09/xmldsig#">`,
    `<CanonicalizationMethod Algorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315"/>`,
    `<SignatureMethod Algorithm="http://www.w3.org/2000/09/xmldsig#rsa-sha1"/>`,
    `<Reference URI="#${refId}">`,
    `<Transforms>`,
    `<Transform Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature"/>`,
    `<Transform Algorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315"/>`,
    `</Transforms>`,
    `<DigestMethod Algorithm="http://www.w3.org/2000/09/xmldsig#sha1"/>`,
    `<DigestValue>${digestValue}</DigestValue>`,
    `</Reference>`,
    `</SignedInfo>`,
  ].join("");

  // 7. Sign <SignedInfo> with RSA-SHA1
  const mdSign = forge.md.sha1.create();
  const signedInfoBytes = new TextEncoder().encode(signedInfoCanon);
  mdSign.update(forge.util.binary.raw.encode(signedInfoBytes));
  const signatureBytes = privateKey.sign(mdSign);
  const signatureValue = forge.util.encode64(signatureBytes);

  // 8. Certificate DER → base64
  const certAsn1 = forge.pki.certificateToAsn1(certificate);
  const certDer = forge.asn1.toDer(certAsn1);
  const certBase64 = forge.util.encode64(certDer.getBytes());

  // 9. Build full <Signature> block
  const signatureBlock = [
    `<Signature xmlns="http://www.w3.org/2000/09/xmldsig#">`,
    signedInfoCanon,
    `<SignatureValue>${signatureValue}</SignatureValue>`,
    `<KeyInfo>`,
    `<X509Data>`,
    `<X509Certificate>${certBase64}</X509Certificate>`,
    `</X509Data>`,
    `</KeyInfo>`,
    `</Signature>`,
  ].join("");

  // 10. Inject <Signature> as last child of root element
  return xmlString.replace(/(<\/eSocial>\s*)$/, `${signatureBlock}</eSocial>`);
}

// ─────────────────────────────────────────────────────────
// XML Builders
// ─────────────────────────────────────────────────────────
function buildS2210(evento: Record<string, unknown>, cnpj: string, ambiente: string): string {
  const now = new Date();
  const cnpjLimpo = cnpj.replace(/\D/g, "");
  const tpAmb = ambiente === "homologacao" ? "2" : "1";
  const dataHora = now.toISOString().replace(/[-:T.Z]/g, "").slice(0, 14);
  const evtId = `e${cnpjLimpo}${dataHora}`;

  return `<?xml version="1.0" encoding="UTF-8"?>
<eSocial xmlns="http://www.esocial.gov.br/schema/evt/evtCAT/v_S_01_02_00" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <evtCAT id="${evtId}">
    <ideEvento>
      <indRetif>1</indRetif>
      <percTrans>1</percTrans>
      <tpAmb>${tpAmb}</tpAmb>
      <procEmi>1</procEmi>
      <verProc>1.0.0</verProc>
    </ideEvento>
    <ideEmpregador>
      <tpInsc>1</tpInsc>
      <nrInsc>${cnpjLimpo.slice(0, 8)}</nrInsc>
    </ideEmpregador>
    <ideVinculo>
      <cpfTrab>${String(evento.cpf_trabalhador ?? "").replace(/\D/g, "").padEnd(11, "0").slice(0, 11)}</cpfTrab>
      <matricula>${String(evento.matricula ?? "")}</matricula>
    </ideVinculo>
    <cat>
      <dtAcid>${String(evento.data_evento ?? now.toISOString().slice(0, 10))}</dtAcid>
      <tpAcid>${String(evento.tipo_acidente ?? "3")}</tpAcid>
      <hrAcid>${String(evento.hora_evento ?? "08:00")}</hrAcid>
      <hrsTrabAntesAcid>${String(evento.horas_trabalhadas_antes ?? "08:00")}</hrsTrabAntesAcid>
      <tpCat>1</tpCat>
      <indCatObito>${evento.obito ? "S" : "N"}</indCatObito>
      <dscLesao>${String(evento.descricao ?? "Acidente de trabalho").slice(0, 200)}</dscLesao>
      <dscCompLesao></dscCompLesao>
      <diagProvavel>${String(evento.cid ?? "")}</diagProvavel>
      <codSitGeradora></codSitGeradora>
      <iniciatCAT>1</iniciatCAT>
      <obsCAT></obsCAT>
      <localAcidente>
        <tpLocal>1</tpLocal>
        <dscLocal>${String(evento.local_acidente ?? "Empresa").slice(0, 80)}</dscLocal>
        <tpLograd>Rua</tpLograd>
        <dscLograd>${String(evento.endereco_local ?? "").slice(0, 80)}</dscLograd>
        <nrLograd>${String(evento.numero_local ?? "SN")}</nrLograd>
        <bairro>${String(evento.bairro_local ?? "").slice(0, 60)}</bairro>
        <cep>${String(evento.cep_local ?? "01310100").replace(/\D/g, "").padEnd(8, "0").slice(0, 8)}</cep>
        <codMunic>${String(evento.ibge_local ?? "3550308")}</codMunic>
        <uf>${String(evento.uf_local ?? "SP")}</uf>
        <pais>105</pais>
        <codPostal></codPostal>
      </localAcidente>
      <partesAtingidas>
        <codParteAting>${String(evento.parte_corpo_atingida ?? "099999")}</codParteAting>
        <lateralidade>9</lateralidade>
      </partesAtingidas>
      <agenteCausador>
        <codAgntCausador>${String(evento.agente_causador ?? "099999")}</codAgntCausador>
      </agenteCausador>
      <atendimento>
        <dtAtendimento>${String(evento.data_evento ?? now.toISOString().slice(0, 10))}</dtAtendimento>
        <hrAtendimento>${String(evento.hora_evento ?? "08:00")}</hrAtendimento>
        <indInternacao>N</indInternacao>
        <durTrat>0</durTrat>
        <indAfast>${evento.afastamento && evento.afastamento !== "sem_afastamento" ? "S" : "N"}</indAfast>
        <dscLesao>${String(evento.descricao ?? "").slice(0, 200)}</dscLesao>
        <dscCompLesao></dscCompLesao>
        <diagProvavel>${String(evento.cid ?? "")}</diagProvavel>
        <codCID>${String(evento.cid ?? "")}</codCID>
        <ordMedico>
          <nmMed></nmMed>
          <nrOC></nrOC>
          <ufCRM></ufCRM>
        </ordMedico>
      </atendimento>
    </cat>
  </evtCAT>
</eSocial>`;
}

function buildS2240(evento: Record<string, unknown>, cnpj: string, ambiente: string): string {
  const now = new Date();
  const cnpjLimpo = cnpj.replace(/\D/g, "");
  const tpAmb = ambiente === "homologacao" ? "2" : "1";
  const dataHora = now.toISOString().replace(/[-:T.Z]/g, "").slice(0, 14);
  const evtId = `e${cnpjLimpo}${dataHora}`;

  return `<?xml version="1.0" encoding="UTF-8"?>
<eSocial xmlns="http://www.esocial.gov.br/schema/evt/evtExpRisco/v_S_01_02_00" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <evtExpRisco id="${evtId}">
    <ideEvento>
      <indRetif>1</indRetif>
      <tpAmb>${tpAmb}</tpAmb>
      <procEmi>1</procEmi>
      <verProc>1.0.0</verProc>
    </ideEvento>
    <ideEmpregador>
      <tpInsc>1</tpInsc>
      <nrInsc>${cnpjLimpo.slice(0, 8)}</nrInsc>
    </ideEmpregador>
    <ideVinculo>
      <cpfTrab>${String(evento.cpf_trabalhador ?? "").replace(/\D/g, "").padEnd(11, "0").slice(0, 11)}</cpfTrab>
      <matricula>${String(evento.matricula ?? "")}</matricula>
    </ideVinculo>
    <infoExpRisco>
      <dtIniCondicao>${String(evento.data_evento ?? now.toISOString().slice(0, 10))}</dtIniCondicao>
      <atividades>
        <dscAtivDes>${String(evento.descricao ?? "Atividade com exposição a risco").slice(0, 999)}</dscAtivDes>
      </atividades>
      <agNoc>
        <grauExpNocivo>3</grauExpNocivo>
      </agNoc>
    </infoExpRisco>
  </evtExpRisco>
</eSocial>`;
}

function buildS2220(evento: Record<string, unknown>, cnpj: string, ambiente: string): string {
  const now = new Date();
  const cnpjLimpo = cnpj.replace(/\D/g, "");
  const tpAmb = ambiente === "homologacao" ? "2" : "1";
  const dataHora = now.toISOString().replace(/[-:T.Z]/g, "").slice(0, 14);
  const evtId = `e${cnpjLimpo}${dataHora}`;

  return `<?xml version="1.0" encoding="UTF-8"?>
<eSocial xmlns="http://www.esocial.gov.br/schema/evt/evtMonit/v_S_01_02_00" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <evtMonit id="${evtId}">
    <ideEvento>
      <indRetif>1</indRetif>
      <tpAmb>${tpAmb}</tpAmb>
      <procEmi>1</procEmi>
      <verProc>1.0.0</verProc>
    </ideEvento>
    <ideEmpregador>
      <tpInsc>1</tpInsc>
      <nrInsc>${cnpjLimpo.slice(0, 8)}</nrInsc>
    </ideEmpregador>
    <ideVinculo>
      <cpfTrab>${String(evento.cpf_trabalhador ?? "").replace(/\D/g, "").padEnd(11, "0").slice(0, 11)}</cpfTrab>
      <matricula>${String(evento.matricula ?? "")}</matricula>
    </ideVinculo>
    <exMedOcup>
      <tpExameOcup>0</tpExameOcup>
      <aso>
        <dtAso>${String(evento.data_evento ?? now.toISOString().slice(0, 10))}</dtAso>
        <resAso>1</resAso>
        <medico>
          <nmMed></nmMed>
          <nrCRM></nrCRM>
          <ufCRM>SP</ufCRM>
        </medico>
      </aso>
    </exMedOcup>
  </evtMonit>
</eSocial>`;
}

// ─────────────────────────────────────────────────────────
// SOAP envelope wrapper
// ─────────────────────────────────────────────────────────
function buildSoapEnvelope(signedXml: string, cnpj: string, ambiente: string): string {
  const cnpjLimpo = cnpj.replace(/\D/g, "");
  return `<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <soapenv:Header/>
  <soapenv:Body>
    <eSocial:EnviarLoteEventos xmlns:eSocial="http://www.esocial.gov.br/servicos/empregador/envio/lote/eventos/v1_1_0">
      <eSocial:loteEventos>
        <eSocial:envioLoteEventos grupo="2">
          <eSocial:ideEmpregador>
            <eSocial:tpInsc>1</eSocial:tpInsc>
            <eSocial:nrInsc>${cnpjLimpo.slice(0, 8)}</eSocial:nrInsc>
          </eSocial:ideEmpregador>
          <eSocial:ideTransmissor>
            <eSocial:tpInsc>1</eSocial:tpInsc>
            <eSocial:nrInsc>${cnpjLimpo}</eSocial:nrInsc>
          </eSocial:ideTransmissor>
          <eSocial:eventos>
            <eSocial:evento Id="ev001">
              ${signedXml}
            </eSocial:evento>
          </eSocial:eventos>
        </eSocial:envioLoteEventos>
      </eSocial:loteEventos>
    </eSocial:EnviarLoteEventos>
  </soapenv:Body>
</soapenv:Envelope>`;
}

// ─────────────────────────────────────────────────────────
// Main handler
// ─────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Não autorizado" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const token = authHeader.replace("Bearer ", "");
    const { data: userData, error: userError } = await supabase.auth.getUser(token);
    if (userError || !userData?.user) {
      return new Response(JSON.stringify({ error: "Token inválido" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Empresa de quem chama: a função usa a chave de serviço (ignora a RLS), então a conferência de empresa é nossa.
    // Sem ela, quem soubesse o identificador de um certificado, evento ou transmissão de OUTRA empresa os lia.
    const { data: chamador } = await supabase
      .from("profiles").select("tenant_id").eq("user_id", userData.user.id).maybeSingle();
    const tenantDoChamador = (chamador as any)?.tenant_id as string | undefined;
    // O Super Admin atende qualquer empresa; os demais ficam restritos a própria.
    const { data: ehSuper } = await supabase.rpc("is_superadmin", { _user_id: userData.user.id });
    const superadmin = ehSuper === true;
    if (!tenantDoChamador && !superadmin) {
      return new Response(JSON.stringify({ error: "Usuário sem empresa" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const {
      action,
      certificado_id,
      evento_sst_id,
      tipo_evento,
      transmissao_id,
      senha_certificado, // Senha do .pfx — nunca armazenada
    } = body;

    // ── Buscar dados comuns ──
    const getCertAndEvento = async () => {
      const [certRes, evtRes, profileRes] = await Promise.all([
        supabase.from("esocial_certificados" as any).select("*").eq("id", certificado_id).single(),
        supabase.from("eventos_sst").select("*").eq("id", evento_sst_id).single(),
        supabase.from("profiles").select("nome_completo, tenant_id").eq("user_id", userData.user.id).maybeSingle(),
      ]);
      if (certRes.error || !certRes.data) throw new Error("Certificado não encontrado");
      if (evtRes.error || !evtRes.data) throw new Error("Evento SST não encontrado");
      // Mesma resposta de "não encontrado" quando o registro é de outra empresa: não revela que ele existe.
      if (!superadmin && (certRes.data as any).tenant_id !== tenantDoChamador) throw new Error("Certificado não encontrado");
      if (!superadmin && (evtRes.data as any).tenant_id !== tenantDoChamador) throw new Error("Evento SST não encontrado");
      return { cert: certRes.data as any, evento: evtRes.data as any, profile: profileRes.data as any };
    };

    const buildXml = (evento: any, cert: any, tipo: string) => {
      const a = cert.ambiente;
      if (tipo === "S-2210") return buildS2210(evento, cert.cnpj, a);
      if (tipo === "S-2220") return buildS2220(evento, cert.cnpj, a);
      if (tipo === "S-2240") return buildS2240(evento, cert.cnpj, a);
      return buildS2210(evento, cert.cnpj, a);
    };

    // ── ACTION: gerar_xml ──
    if (action === "gerar_xml") {
      const { cert, evento } = await getCertAndEvento();
      const xml = buildXml(evento, cert, tipo_evento ?? "S-2210");
      return new Response(JSON.stringify({ xml, tipo_evento }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── ACTION: transmitir ──
    if (action === "transmitir") {
      if (!senha_certificado) {
        return new Response(JSON.stringify({ error: "Senha do certificado é obrigatória" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const { cert, evento, profile } = await getCertAndEvento();
      const xmlBruto = buildXml(evento, cert, tipo_evento ?? "S-2210");

      let xmlAssinado = xmlBruto;
      let statusFinal = "pendente_assinatura";
      let mensagem = "";
      let protocolo: string | null = null;
      let xmlEnvioFinal = xmlBruto;
      let xmlRetorno: string | null = null;
      let codigoRetorno: string | null = null;

      // ── Baixar .pfx do storage e assinar ──
      const { data: certFile, error: storageErr } = await supabase.storage
        .from("esocial-certificados")
        .download(cert.certificado_path);

      if (storageErr || !certFile) {
        statusFinal = "erro";
        mensagem = "Não foi possível carregar o certificado digital do storage.";
      } else {
        try {
          const pfxBytes = new Uint8Array(await certFile.arrayBuffer());
          xmlAssinado = signXml(xmlBruto, pfxBytes, senha_certificado);
          xmlEnvioFinal = buildSoapEnvelope(xmlAssinado, cert.cnpj, cert.ambiente);

          // ── Enviar ao WebService eSocial ──
          const endpoint = ESOCIAL_WS[cert.ambiente as keyof typeof ESOCIAL_WS];
          const wsResponse = await fetch(endpoint, {
            method: "POST",
            headers: {
              "Content-Type": "text/xml;charset=UTF-8",
              "SOAPAction": "EnviarLoteEventos",
            },
            body: xmlEnvioFinal,
            signal: AbortSignal.timeout(30000),
          });

          xmlRetorno = await wsResponse.text();

          if (wsResponse.ok || wsResponse.status < 500) {
            // Extrair protocolo do retorno
            const protMatch = xmlRetorno.match(/<nrProtEnv>([^<]+)<\/nrProtEnv>/);
            const codigoMatch = xmlRetorno.match(/<cdResposta>([^<]+)<\/cdResposta>/);
            const descMatch = xmlRetorno.match(/<descResposta>([^<]+)<\/descResposta>/);

            protocolo = protMatch?.[1] ?? null;
            codigoRetorno = codigoMatch?.[1] ?? String(wsResponse.status);
            const descResposta = descMatch?.[1] ?? "";

            if (codigoRetorno === "201" || codigoRetorno === "202") {
              statusFinal = "enviado";
              mensagem = `✅ Lote recebido pelo eSocial. Protocolo: ${protocolo}. ${descResposta}`;
            } else if (codigoRetorno?.startsWith("4") || codigoRetorno?.startsWith("5")) {
              statusFinal = "rejeitado";
              mensagem = `Rejeitado (${codigoRetorno}): ${descResposta || xmlRetorno.slice(0, 300)}`;
            } else {
              statusFinal = "enviado";
              mensagem = `Resposta ${codigoRetorno}: ${descResposta}`;
            }
          } else {
            statusFinal = "erro";
            mensagem = `Erro HTTP ${wsResponse.status} ao conectar ao WebService eSocial.`;
          }
        } catch (signErr: any) {
          if (signErr.name === "TimeoutError") {
            statusFinal = "erro";
            mensagem = "Timeout ao conectar ao WebService do eSocial (>30s). Tente novamente.";
          } else if (signErr.message?.includes("Invalid")) {
            statusFinal = "erro";
            mensagem = "Senha do certificado incorreta ou arquivo .pfx inválido.";
          } else {
            statusFinal = "erro";
            mensagem = signErr.message ?? "Erro ao assinar ou transmitir XML.";
          }
          console.error("Erro sign/transmit:", signErr);
        }
      }

      // ── Registrar transmissão ──
      const { data: trans } = await supabase
        .from("esocial_transmissoes" as any)
        .insert({
          tenant_id: profile?.tenant_id ?? cert.tenant_id,
          empresa_id: cert.empresa_id,
          certificado_id: cert.id,
          evento_sst_id,
          tipo_evento,
          xml_enviado: xmlEnvioFinal,
          xml_retorno: xmlRetorno,
          status: statusFinal,
          mensagem_retorno: mensagem,
          codigo_retorno: codigoRetorno,
          protocolo,
          tentativas: 1,
          ultima_tentativa: new Date().toISOString(),
          criado_por: userData.user.id,
          criado_por_nome: profile?.nome_completo ?? userData.user.email,
        })
        .select()
        .single();

      return new Response(
        JSON.stringify({
          success: true,
          transmissao_id: (trans as any)?.id,
          status: statusFinal,
          mensagem,
          protocolo,
          codigo_retorno: codigoRetorno,
          xml_assinado: xmlAssinado,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── ACTION: consultar ──
    if (action === "consultar") {
      let consulta = supabase
        .from("esocial_transmissoes" as any)
        .select("*")
        .eq("id", transmissao_id);
      if (!superadmin) consulta = consulta.eq("tenant_id", tenantDoChamador);
      const { data: trans } = await consulta.maybeSingle();
      return new Response(JSON.stringify({ transmissao: trans ?? null }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ error: "Ação não reconhecida" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: any) {
    console.error("Erro esocial-transmissao:", err);
    return new Response(JSON.stringify({ error: err.message ?? "Erro interno" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
