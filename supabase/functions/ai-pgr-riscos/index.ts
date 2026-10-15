import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

const RISCOS_VALIDOS = [
  "fisico", "quimico", "biologico", "ergonomico",
  "psicossocial", "acidente", "altura", "espaco_confinado",
  "eletrico", "maquinas", "ambiental"
];

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const json = (body: unknown, status = 200) =>
      new Response(JSON.stringify(body), {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });

    // Autenticação: o tenant vem do usuário logado, nunca do corpo da requisição.
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) return json({ error: "Não autenticado" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) return json({ error: "Não autenticado" }, 401);

    const { empresa_id, tenant_id: bodyTenantId } = await req.json();
    if (!empresa_id) return json({ error: "empresa_id é obrigatório" }, 400);

    const admin = createClient(supabaseUrl, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: isSuper } = await admin.rpc("is_superadmin", { _user_id: userData.user.id });

    let tenant_id: string | null = null;
    if (isSuper === true && bodyTenantId) {
      tenant_id = bodyTenantId;
    } else {
      const { data: profile } = await admin
        .from("profiles")
        .select("tenant_id")
        .eq("user_id", userData.user.id)
        .maybeSingle();
      tenant_id = profile?.tenant_id ?? null;
      if (bodyTenantId && bodyTenantId !== tenant_id) return json({ error: "Acesso negado" }, 403);
    }
    if (!tenant_id) return json({ error: "Tenant não identificado" }, 403);

    const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
    if (!OPENAI_API_KEY) throw new Error("OPENAI_API_KEY não configurada");

    // A empresa precisa pertencer ao tenant do usuário.
    const { data: empresa } = await admin
      .from("empresa_cadastro")
      .select("id")
      .eq("id", empresa_id)
      .eq("tenant_id", tenant_id)
      .maybeSingle();
    if (!empresa) return json({ error: "Empresa não encontrada" }, 404);

    // Leituras pelo cliente do usuário: a RLS (tenant e perfil de acesso) também vale aqui.
    const supabase = userClient;

    // Buscar PGR cadastrado no Compliance SST
    const { data: pgr, error: pgrError } = await supabase
      .from("sst_documentos")
      .select("id, arquivo_url, arquivo_nome, analise_ia, profissional_responsavel, data_emissao")
      .eq("tenant_id", tenant_id)
      .eq("empresa_id", empresa_id)
      .eq("tipo", "pgr")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (pgrError) throw pgrError;

    // Tentar também sem empresa_id (PGR geral do tenant)
    let documento = pgr;
    if (!documento) {
      const { data: pgrTenant } = await supabase
        .from("sst_documentos")
        .select("id, arquivo_url, arquivo_nome, analise_ia, profissional_responsavel, data_emissao")
        .eq("tenant_id", tenant_id)
        .is("empresa_id", null)
        .eq("tipo", "pgr")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      documento = pgrTenant;
    }

    if (!documento) {
      return new Response(JSON.stringify({
        found: false,
        message: "Nenhum PGR encontrado no Compliance SST para esta empresa.",
        riscos: []
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Se já tem análise de IA com riscos, usar o cache
    if (documento.analise_ia?.riscos_identificados?.length > 0) {
      const riscosCache = documento.analise_ia.riscos_identificados
        .filter((r: string) => RISCOS_VALIDOS.includes(r));
      
      if (riscosCache.length > 0) {
        return new Response(JSON.stringify({
          found: true,
          pgr_nome: documento.arquivo_nome,
          pgr_data: documento.data_emissao,
          riscos: riscosCache,
          from_cache: true,
        }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // Baixar o PDF do PGR para extrair texto
    let pdfText = "";
    if (documento.arquivo_url) {
      try {
        const pdfResponse = await fetch(documento.arquivo_url);
        if (pdfResponse.ok) {
          const pdfBuffer = await pdfResponse.arrayBuffer();
          // Converter para base64 para enviar ao GPT-4o Vision se necessário
          // Por enquanto, enviar metadados + análise textual via GPT
          pdfText = `Documento: ${documento.arquivo_nome}\nTamanho: ${pdfBuffer.byteLength} bytes\nURL: ${documento.arquivo_url}`;
        }
      } catch (_e) {
        console.warn("Não foi possível baixar o PDF, usando metadados");
      }
    }

    // Usar IA para identificar riscos com base nos metadados disponíveis
    const prompt = `Você é um especialista em Segurança do Trabalho. Analise as informações abaixo de um PGR (Programa de Gerenciamento de Riscos) e identifique quais categorias de riscos ocupacionais estão presentes.

Informações do PGR:
- Nome do arquivo: ${documento.arquivo_nome || "PGR da empresa"}
- Responsável técnico: ${documento.profissional_responsavel || "Não informado"}
- Data de emissão: ${documento.data_emissao || "Não informada"}
${pdfText ? `\nDados adicionais:\n${pdfText}` : ""}

${documento.analise_ia ? `\nAnálise prévia disponível:\n${JSON.stringify(documento.analise_ia, null, 2)}` : ""}

Com base nestas informações e no contexto de um PGR brasileiro (NR-01), identifique quais dos seguintes riscos ocupacionais provavelmente estão presentes:

- fisico: Ruído, vibração, temperatura extrema, radiação
- quimico: Poeiras, fumos, névoas, gases, vapores, substâncias químicas
- biologico: Vírus, bactérias, fungos, parasitas, agentes biológicos
- ergonomico: Esforço físico intenso, posturas inadequadas, repetitividade, monotonia
- psicossocial: Estresse, pressão excessiva, assédio, jornada excessiva
- acidente: Quedas, cortes, esmagamentos, explosões, riscos mecânicos
- altura: Atividades acima de 2 metros (NR-35)
- espaco_confinado: Locais com entrada/saída limitada (NR-33)
- eletrico: Instalações elétricas energizadas (NR-10)
- maquinas: Operação de máquinas e equipamentos perigosos (NR-12)
- ambiental: Geração de resíduos, efluentes, emissões atmosféricas

Retorne APENAS um JSON com o array de riscos identificados. Exemplo: {"riscos": ["fisico", "quimico", "ergonomico"]}

Seja conservador e inclua apenas riscos que sejam razoavelmente esperados com base nas informações disponíveis.`;

    const aiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: "Você é um especialista em SST. Responda sempre em JSON válido." },
          { role: "user", content: prompt }
        ],
        response_format: { type: "json_object" },
        temperature: 0.3,
      }),
    });

    if (!aiResponse.ok) {
      const errText = await aiResponse.text();
      throw new Error(`OpenAI error ${aiResponse.status}: ${errText}`);
    }

    const aiData = await aiResponse.json();
    const content = aiData.choices?.[0]?.message?.content || "{}";
    
    let riscos: string[] = [];
    try {
      const parsed = JSON.parse(content);
      riscos = (parsed.riscos || []).filter((r: string) => RISCOS_VALIDOS.includes(r));
    } catch (_e) {
      console.error("Erro ao parsear resposta da IA:", content);
    }

    // Cachear os riscos identificados na análise do documento
    if (riscos.length > 0) {
      await admin
        .from("sst_documentos")
        .update({
          analise_ia: {
            ...(documento.analise_ia || {}),
            riscos_identificados: riscos,
            riscos_extraidos_em: new Date().toISOString(),
          }
        })
        .eq("id", documento.id)
        .eq("tenant_id", tenant_id);
    }

    return new Response(JSON.stringify({
      found: true,
      pgr_nome: documento.arquivo_nome,
      pgr_data: documento.data_emissao,
      riscos,
      from_cache: false,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error) {
    console.error("Erro em ai-pgr-riscos:", error);
    return new Response(JSON.stringify({
      error: error instanceof Error ? error.message : "Erro desconhecido"
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
