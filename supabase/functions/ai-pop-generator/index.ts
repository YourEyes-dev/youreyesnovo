import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getCompanyContext } from '../_shared/ai-helper.ts';
import { autenticar, respostaDeErro } from '../_shared/auth.ts';

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    // A empresa vem do cadastro do usuário logado, nunca do corpo da requisição.
    const { tenantId, admin } = await autenticar(req);

    const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
    if (!OPENAI_API_KEY) throw new Error("OPENAI_API_KEY não configurada");

    const body = await req.json();
    const {
      funcao_nome, setor, nivel,
      atividade_nome, atividade_descricao,
      frequencia, complexidade, classificacao,
      ferramentas, interfaces, riscos,
      objetivo_pop, pre_requisitos, epi_necessario,
      materiais, sistemas, erros_comuns,
      criterios_qualidade, responsaveis,
      responsavel_direto, consequencia_erro, conteudos_relacionados,
      action, trecho, instrucao,
    } = body;

    // Contexto da empresa do próprio usuário (não bloqueia se falhar)
    let companyContext = "";
    try {
      companyContext = await getCompanyContext(admin, tenantId);
    } catch { /* ignore */ }

    // IA assistida: reescrever/detalhar/simplificar trechos
    if (action === "rewrite") {
      const prompt = `Você é um especialista em procedimentos operacionais padrão (POP).
${instrucao || "Reescreva o trecho abaixo de forma mais clara e profissional:"}

Trecho:
${trecho}

Retorne APENAS o texto reescrito, sem explicações.`;

      const resp = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          messages: [{ role: "user", content: prompt }],
          stream: false,
        }),
      });

      if (!resp.ok) {
        const t = await resp.text();
        console.error("AI error:", resp.status, t);
        if (resp.status === 429) return new Response(JSON.stringify({ error: "Rate limit excedido, tente novamente." }), { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } });
        if (resp.status === 402) return new Response(JSON.stringify({ error: "Créditos insuficientes." }), { status: 402, headers: { ...corsHeaders, "Content-Type": "application/json" } });
        throw new Error("Erro no gateway de IA");
      }

      const data = await resp.json();
      const result = data.choices?.[0]?.message?.content || "";
      return new Response(JSON.stringify({ result }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // Geração completa do POP
    const contexto = `
${companyContext}

CONTEXTO DA FUNÇÃO:
- Função: ${funcao_nome || "Não informado"}
- Setor/Unidade: ${setor || "Não informado"}
- Nível: ${nivel || "Não informado"}

ATIVIDADE:
- Nome: ${atividade_nome}
- Descrição: ${atividade_descricao || "Não informada"}
- Frequência: ${frequencia || "Não informada"}
- Complexidade: ${complexidade || "Não informada"}
- Classificação: ${classificacao || "Não informada"}

MATRIZ DE RESPONSABILIDADE:
- Responsável direto (executante): ${responsavel_direto || "Não informado"}
- Interfaces/Áreas envolvidas: ${interfaces || "Nenhuma"}
- Consequência/risco se falhar: ${consequencia_erro || "Não informado"}

INFORMAÇÕES COMPLEMENTARES:
- Ferramentas vinculadas: ${ferramentas || "Nenhuma"}
- Conteúdos/documentação relacionada: ${conteudos_relacionados || "Nenhum"}
- Riscos relacionados: ${riscos || "Nenhum identificado"}
- Objetivo do POP: ${objetivo_pop || "Padronizar a execução da atividade"}
- Pré-requisitos: ${pre_requisitos || "Não informados"}
- EPI necessário: ${epi_necessario || "Não informado"}
- Materiais/Equipamentos: ${materiais || "Não informados"}
- Sistemas/Ferramentas: ${sistemas || "Não informados"}
- Erros comuns: ${erros_comuns || "Não informados"}
- Critérios de qualidade: ${criterios_qualidade || "Não informados"}
- Responsáveis: ${responsaveis || "Não informados"}
`.trim();

    const systemPrompt = `Você é um especialista em criação de Procedimentos Operacionais Padrão (POP) para empresas brasileiras, com forte conhecimento em SST (Segurança e Saúde do Trabalho).

Gere um POP completo em formato JSON estruturado com os seguintes campos:

{
  "objetivo": "texto do objetivo",
  "escopo": "onde se aplica / quando usar",
  "responsabilidades": {
    "executante": "quem executa",
    "supervisao": "quem supervisiona",
    "interfaces": "quem depende"
  },
  "definicoes": "termos técnicos se necessário",
  "pre_requisitos": ["lista de pré-requisitos"],
  "materiais_ferramentas": ["lista de materiais, ferramentas e sistemas"],
  "epis_sst": "EPIs e requisitos de SST quando aplicável",
  "procedimento_passos": [
    {
      "numero": 1,
      "descricao": "o que fazer",
      "tempo_estimado": "tempo opcional",
      "ponto_atencao": "riscos ou erros críticos"
    }
  ],
  "criterios_qualidade": "como saber que está correto",
  "registros_evidencias": "prints, formulários, anexos necessários",
  "tratamento_nao_conformidades": "o que fazer quando der errado",
  "referencias": "documentos internos, NRs aplicáveis",
  "camada_sst": {
    "riscos_identificados": ["lista de riscos SST da atividade"],
    "controles_recomendados": ["medidas de controle"],
    "nrs_aplicaveis": ["NRs aplicáveis com justificativa breve"],
    "epis_obrigatorios": ["EPIs obrigatórios para esta atividade"],
    "sinalizacao_necessaria": "sinalização de segurança quando aplicável",
    "treinamentos_obrigatorios": ["treinamentos SST necessários"]
  }
}

REGRAS:
- Linguagem clara, objetiva e profissional
- Passos numerados e detalhados
- Incluir pontos de atenção em cada passo crítico
- Considerar a complexidade e classificação da atividade
- Se a atividade for crítica, ser mais detalhado nos pontos de atenção e riscos
- A camada SST deve ser SEMPRE preenchida, mesmo que mínima (ex: ergonomia, postura)
- Considere NRs relevantes: NR-01 (PGR), NR-07 (PCMSO), NR-09, NR-12, NR-17 (Ergonomia), etc.
- Use o contexto da empresa para personalizar riscos e controles
- Retornar APENAS o JSON, sem markdown fences ou explicações`;

    const resp = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        response_format: { type: "json_object" },
        max_tokens: 8000,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: contexto },
        ],
        stream: false,
      }),
    });

    if (!resp.ok) {
      const t = await resp.text();
      console.error("AI error:", resp.status, t);
      if (resp.status === 429) return new Response(JSON.stringify({ error: "Rate limit excedido." }), { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      if (resp.status === 402) return new Response(JSON.stringify({ error: "Créditos insuficientes." }), { status: 402, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      throw new Error("Erro no gateway de IA");
    }

    const data = await resp.json();
    let content = data.choices?.[0]?.message?.content || "";

    // Clean markdown fences
    content = content.replace(/```json\s*/gi, "").replace(/```\s*/g, "").trim();

    let pop;
    try {
      pop = JSON.parse(content);
    } catch {
      console.error("Failed to parse:", content);
      throw new Error("IA retornou formato inválido");
    }

    return new Response(JSON.stringify({ pop }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return respostaDeErro(e, corsHeaders);
  }
});
