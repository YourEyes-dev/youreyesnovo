import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { autenticar, HttpError, respostaDeErro } from "../_shared/auth.ts";
import pdf from "npm:pdf-parse@1.1.1/lib/pdf-parse.js";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

// ─── Shared rules injected into every prompt ─────────────────────────────────

const REGRAS_FUNDAMENTAIS = `
REGRAS FUNDAMENTAIS (INVIOLÁVEIS):
1. Nunca invente informação.
2. Nunca complete lacunas com suposições.
3. Nunca transforme texto genérico em ação específica.
4. Só extraia algo se houver evidência textual clara no documento.
5. Se a informação estiver ambígua, incompleta ou sem contexto suficiente, marque como "não conclusivo".
6. Não misture conteúdos de seções diferentes.
7. Não criar alertas irreais, duplicados ou sem nexo com SST.
8. Não tratar introduções, textos legais genéricos, objetivos do documento, definições normativas ou textos padrão como ações.
9. Não considerar assinaturas, rodapés, cabeçalhos, índice, sumário, numeração de páginas e textos repetidos como conteúdo analítico.
10. A extração deve ser conservadora: é melhor deixar de extrair do que extrair errado.

EXEMPLOS INVÁLIDOS DE AÇÃO (NUNCA extrair):
- "promover segurança"
- "seguir a legislação"
- "observar a norma"
- "zelar pela saúde do trabalhador"
- textos conceituais ou genéricos sem execução definida

EXEMPLOS VÁLIDOS DE AÇÃO (extrair apenas se textualmente presente):
- realizar dosimetria de ruído no setor X
- implementar proteção coletiva na máquina Y
- realizar exame audiométrico periódico para função Z
- revisar inventário de riscos até data específica
- treinar trabalhadores expostos ao risco X

PARA CADA ALERTA, DADO DE ATENÇÃO OU AÇÃO, incluir:
- titulo_curto
- descricao_objetiva (baseada em trecho real do documento)
- categoria
- prioridade: alta | media | baixa
- setor/função/GHE relacionado (se houver)
- trecho_fonte: citação literal do documento entre aspas (se possível)
- justificativa_da_classificacao

CRITÉRIO FINAL:
- Se não houver base textual suficiente → não extrair.
- Se o texto for genérico → não transformar em ação.
- Se a informação for ambígua → marcar como não conclusivo.
- A precisão é mais importante que a quantidade.`;

const FORMATO_SAIDA = (tipo: string) => `
## FORMATO DE SAÍDA OBRIGATÓRIO

Retorne a análise SEMPRE nesta estrutura em Markdown:

# 📋 ANÁLISE SST — ${tipo}

## 1. METADADOS DO DOCUMENTO
- **Tipo:** 
- **Empresa:** 
- **CNPJ:** 
- **Unidade/Estabelecimento:** 
- **Data de Emissão:** 
- **Vigência:** 
- **Responsável Técnico:** 
- **Cargo/Função do Responsável:** 
- **Número de Registro Profissional:** 

---

## 2. ALERTAS

### 🔴 CRÍTICOS
> Risco legal, vida do trabalhador, obrigação crítica não cumprida.
Para cada alerta crítico:
**[titulo_curto]**
- Descrição: [descricao_objetiva]
- Setor/Função/GHE: [se houver]
- Trecho-fonte: "[citação do documento]"
- Prioridade: Alta
- Justificativa: [justificativa_da_classificacao]

### 🟠 TÉCNICOS
> Incongruências técnicas, lacunas metodológicas.
[mesma estrutura]

### 🟡 ATENÇÃO
> Pontos que merecem acompanhamento preventivo.
[mesma estrutura]

Se não houver alertas em alguma categoria, escreva: "Nenhum alerta identificado nesta categoria com base no conteúdo disponível."

---

## 3. DADOS DE ATENÇÃO
> Pontos relevantes para acompanhamento, sem configurar alerta crítico imediato. Ex: setores com maior concentração de riscos, funções expostas, exames previstos, medidas preventivas existentes, EPIs, GHEs.

Para cada item:
**[titulo_curto]**
- Descrição: [descricao_objetiva]
- Setor/Função/GHE: [se houver]
- Categoria: [tipo de dado]

---

## 4. AÇÕES
> SOMENTE ações com verbo executável explícito no documento (plano de ação, cronograma, recomendação objetiva, medida corretiva/preventiva com obrigação operacional claramente identificável).
> NÃO incluir descrições de risco, textos conceituais ou obrigações genéricas.

Para cada ação:
**[titulo_curto]**
- Descrição: [descricao_objetiva]
- Setor/Função/GHE: [se houver]
- Prazo: [se mencionado no documento — deixar em branco se não houver]
- Responsável: [se mencionado no documento — deixar em branco se não houver]
- Trecho-fonte: "[citação do documento]"
- Prioridade: Alta | Média | Baixa

---

## 5. INCONSISTÊNCIAS DOCUMENTAIS
> Apenas quando há evidência de contradição, omissão técnica grave ou dado inconsistente no próprio documento.

---

## 6. ITENS NÃO CONCLUSIVOS
> Informações presentes no documento mas sem contexto suficiente para classificação definitiva.

---

⚠️ **AVISO LEGAL:** Análise gerada por IA como ferramenta auxiliar. Não substitui parecer de profissional habilitado (Médico do Trabalho, Engenheiro de Segurança). Todas as conclusões devem ser validadas por profissional competente.`;

// ─── Prompt metadata type ────────────────────────────────────────────────────

interface PromptMeta {
  tipo: string;
  nome: string;
  empresa: string;
  profissional: string;
  hasPdf: boolean;
  paginas: string;
}

// ─── Document-specific prompt builders ───────────────────────────────────────

function buildPCMSOPrompt(meta: PromptMeta): string {
  return `Você é um analisador técnico de documentos SST, especializado em PCMSO (NR-07).
Sua função é ler o conteúdo do documento e extrair APENAS informações objetivas, rastreáveis e tecnicamente coerentes com o texto.

${REGRAS_FUNDAMENTAIS}

---

## TRATAMENTO ESPECÍFICO — PCMSO
Priorizar extração de:
- Exames admissionais, periódicos, retorno ao trabalho, mudança de risco, demissional
- Exames complementares previstos (audiometria, espirometria, hemograma, etc.)
- Relação entre riscos ocupacionais e monitoramento de saúde
- Periodicidades dos exames
- Grupos ocupacionais monitorados (GHEs)
- Encaminhamentos e recomendações clínicas ocupacionais expressas no documento
- Inconsistências entre risco descrito e exame previsto
- Médico responsável e CRM

ALERTAS VÁLIDOS para PCMSO:
- Ausência de exame obrigatório para risco identificado
- Periodicidade incorreta ou inadequada perante NR-07
- Exame periódico previsto e não realizado (quando há evidência textual)
- Trabalhador exposto a agente sem monitoramento médico correspondente
- PCMSO desatualizado (vigência vencida)
- Ausência de médico coordenador ou CRM não informado

ALERTAS INVÁLIDOS para PCMSO:
- Texto genérico sobre importância dos exames
- Citação de NR sem implicação prática identificada
- Frase descritiva sem consequência clara

${FORMATO_SAIDA("PCMSO")}

**Arquivo:** ${meta.nome}
${meta.empresa ? `**Empresa:** ${meta.empresa}` : ""}
${meta.profissional ? `**Médico Responsável:** ${meta.profissional}` : ""}
**Páginas:** ${meta.paginas}
${meta.hasPdf ? "CONTEÚDO COMPLETO FORNECIDO ABAIXO — use EXCLUSIVAMENTE dados reais. Cite trechos literais. NUNCA invente." : "Conteúdo não extraído (PDF escaneado ou protegido). Indique itens que necessitam verificação manual pelo profissional responsável."}`;
}

function buildLTCATPrompt(meta: PromptMeta): string {
  return `Você é um analisador técnico de documentos SST, especializado em LTCAT (Decreto 3.048/99, NR-15, NR-16).
Sua função é ler o conteúdo do documento e extrair APENAS informações objetivas, rastreáveis e tecnicamente coerentes com o texto.

${REGRAS_FUNDAMENTAIS}

---

## TRATAMENTO ESPECÍFICO — LTCAT
Priorizar extração de:
- Agentes nocivos identificados (físicos, químicos, biológicos)
- Habitualidade, permanência e exposição descritas no documento
- Setores e funções analisados
- Intensidade/concentração quando houver dados de medição documentados
- Conclusão sobre enquadramento para aposentadoria especial (por função)
- Metodologia de avaliação utilizada
- Necessidade de avaliações quantitativas mencionadas
- Dados que impactem insalubridade, periculosidade ou aposentadoria especial, se expressamente presentes
- Responsável técnico, ART e habilitação

ALERTAS VÁLIDOS para LTCAT:
- Ausência de avaliação quantitativa para agente com limite de tolerância definido (ex: ruído sem NEN/dose)
- Conclusão de "não geração" de aposentadoria especial sem medição comprovada
- EPI citado como eliminador de risco para ruído acima de 85 dB(A) — violação Tema 555 STF
- Agente LINACH Grupo 1 sem avaliação qualitativa adequada
- Falta de assinatura de Engenheiro de Segurança ou Médico do Trabalho (Técnico de Segurança não pode assinar LTCAT)
- Laudo desatualizado ou sem data de emissão
- Falta de ART vinculada ao documento

${FORMATO_SAIDA("LTCAT")}

**Arquivo:** ${meta.nome}
${meta.empresa ? `**Empresa:** ${meta.empresa}` : ""}
${meta.profissional ? `**Responsável Técnico:** ${meta.profissional}` : ""}
**Páginas:** ${meta.paginas}
${meta.hasPdf ? "CONTEÚDO COMPLETO FORNECIDO ABAIXO — use EXCLUSIVAMENTE dados reais. Cite trechos literais. NUNCA invente." : "Conteúdo não extraído (PDF escaneado ou protegido). Indique itens que necessitam verificação manual pelo profissional responsável."}`;
}

function buildPGRPrompt(meta: PromptMeta): string {
  return `Você é um analisador técnico de documentos SST, especializado em PGR (NR-01).
Sua função é ler o conteúdo do documento e extrair APENAS informações objetivas, rastreáveis e tecnicamente coerentes com o texto.

${REGRAS_FUNDAMENTAIS}

---

## TRATAMENTO ESPECÍFICO — PGR
Priorizar extração de:
- Inventário de riscos: setores, ambientes, GHEs
- Cargos/funções e perigos ocupacionais associados
- Agentes físicos, químicos, biológicos, ergonômicos e de acidentes identificados
- Medidas de prevenção e controle existentes (EPC, EPI, administrativas)
- Plano de ação e cronograma — SOMENTE se explicitamente presentes no documento com verbos executáveis
- Avaliações qualitativas e quantitativas realizadas ou previstas
- Responsável técnico e habilitação

ALERTAS VÁLIDOS para PGR:
- Risco classificado como médio/alto sem plano de ação correspondente
- Ausência de avaliação quantitativa para agente com limite de tolerância definido
- GHE sem medida de controle definida
- Ausência de Inventário de Riscos ou Plano de Ação (itens obrigatórios pela NR-01)
- Falta de assinatura de profissional habilitado
- Programa desatualizado (vigência vencida)
- Risco identificado sem medida de controle suficiente

AÇÕES DO PGR — REGRA CRÍTICA:
Extrair SOMENTE itens que constem explicitamente no Plano de Ação ou Cronograma do documento.
A ação deve conter um VERBO NO INFINITIVO indicando o que deve ser feito.
Exemplos VÁLIDOS: "Realizar dosimetria de ruído no setor de produção", "Instalar proteção coletiva na prensa", "Revisar inventário de riscos até 30/06/2025".
Exemplos INVÁLIDOS: "Gerenciar riscos", "Manter condições adequadas de trabalho", "Seguir NR-01", "Promover segurança".

${FORMATO_SAIDA("PGR")}

**Arquivo:** ${meta.nome}
${meta.empresa ? `**Empresa:** ${meta.empresa}` : ""}
${meta.profissional ? `**Responsável Técnico:** ${meta.profissional}` : ""}
**Páginas:** ${meta.paginas}
${meta.hasPdf ? "CONTEÚDO COMPLETO FORNECIDO ABAIXO — use EXCLUSIVAMENTE dados reais. Cite trechos literais. NUNCA invente." : "Conteúdo não extraído (PDF escaneado ou protegido). Indique itens que necessitam verificação manual pelo profissional responsável."}`;
}

function buildGenericPrompt(meta: PromptMeta): string {
  return `Você é um analisador técnico de documentos de Saúde e Segurança do Trabalho (SST).
Sua função é ler o conteúdo do documento e extrair APENAS informações objetivas, rastreáveis e tecnicamente coerentes com o texto.

${REGRAS_FUNDAMENTAIS}

---

## TRATAMENTO — DOCUMENTO SST
Classifique o tipo de documento primeiro (PGR, PCMSO, LTCAT, ASO, Laudo Ergonômico, AET, PPP ou outro).
Em seguida, extraia conforme aplicável:
- Riscos ocupacionais identificados
- Medidas de controle existentes
- Exames e monitoramentos previstos
- Plano de ação ou cronograma (SOMENTE se explicitamente presente com verbos executáveis)
- Dados de vigência e responsável técnico

${FORMATO_SAIDA(meta.tipo)}

**Arquivo:** ${meta.nome}
${meta.empresa ? `**Empresa:** ${meta.empresa}` : ""}
${meta.profissional ? `**Responsável Técnico:** ${meta.profissional}` : ""}
**Páginas:** ${meta.paginas}
${meta.hasPdf ? "CONTEÚDO COMPLETO FORNECIDO ABAIXO — use EXCLUSIVAMENTE dados reais. Cite trechos literais. NUNCA invente." : "Conteúdo não extraído (PDF escaneado ou protegido). Indique itens que necessitam verificação manual pelo profissional responsável."}`;
}

function getSystemPrompt(meta: PromptMeta): string {
  const tipoNorm = meta.tipo.toUpperCase().trim();
  if (tipoNorm.includes("PCMSO")) return buildPCMSOPrompt(meta);
  if (tipoNorm.includes("LTCAT")) return buildLTCATPrompt(meta);
  if (tipoNorm.includes("PGR")) return buildPGRPrompt(meta);
  return buildGenericPrompt(meta);
}

// ─── Main handler ────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Login conferido e empresa lida do cadastro do usuário.
    const { tenantId } = await autenticar(req);

    const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
    if (!OPENAI_API_KEY) throw new Error("OPENAI_API_KEY não configurada");

    const { documento_tipo, documento_nome, empresa_emissora, profissional_responsavel, arquivo_url } = await req.json();

    // O arquivo é baixado com a chave de serviço (ignora o RLS do storage). Por isso só
    // aceita caminho da PRÓPRIA empresa: os uploads de SST gravam `<tenant>/sst/...`.
    if (arquivo_url && (typeof arquivo_url !== "string" || arquivo_url.includes("..") || !arquivo_url.startsWith(`${tenantId}/`))) {
      throw new HttpError(403, "Arquivo não pertence à sua empresa");
    }

    let pdfText: string | null = null;
    let pdfPageCount = 0;

    if (arquivo_url) {
      try {
        const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
        const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
        const supabaseAdmin = createClient(supabaseUrl, supabaseKey);

        const { data: fileData, error: fileError } = await supabaseAdmin.storage
          .from("documentos")
          .download(arquivo_url);

        if (fileError) {
          console.error("Erro ao baixar arquivo:", fileError.message);
        } else if (fileData) {
          const arrayBuffer = await fileData.arrayBuffer();
          const buffer = new Uint8Array(arrayBuffer);
          console.log(`PDF baixado: ${(buffer.length / 1024 / 1024).toFixed(2)} MB`);

          try {
            const pdfData = await pdf(buffer);
            pdfText = pdfData.text;
            pdfPageCount = pdfData.numpages || 0;
            console.log(`PDF extraído: ${pdfPageCount} páginas, ${pdfText.length} chars`);
          } catch (pdfErr) {
            console.error("Erro ao extrair texto do PDF:", pdfErr);
          }
        }
      } catch (downloadErr) {
        console.error("Erro ao processar arquivo:", downloadErr);
      }
    }

    const hasPdfContent = pdfText && pdfText.trim().length > 100;

    const meta: PromptMeta = {
      tipo: documento_tipo || "Documento SST",
      nome: documento_nome,
      empresa: empresa_emissora || "",
      profissional: profissional_responsavel || "",
      hasPdf: !!hasPdfContent,
      paginas: pdfPageCount ? String(pdfPageCount) : "N/A",
    };

    const systemPrompt = getSystemPrompt(meta);

    // Truncate PDF text to stay within token limits (~4 chars per token)
    const MAX_PDF_CHARS = 280000;
    let truncatedPdfText = pdfText;
    let wasTruncated = false;
    if (hasPdfContent && pdfText!.length > MAX_PDF_CHARS) {
      truncatedPdfText = pdfText!.substring(0, MAX_PDF_CHARS);
      wasTruncated = true;
      console.log(`PDF truncado de ${pdfText!.length} para ${MAX_PDF_CHARS} chars`);
    }

    let userMessage = "";
    if (hasPdfContent) {
      const truncNote = wasTruncated
        ? `\n\n⚠️ NOTA: O documento possui ${pdfPageCount} páginas. O conteúdo foi parcialmente truncado por limite de processamento. Analise o conteúdo disponível e indique que a análise é parcial.`
        : "";
      userMessage = `## CONTEÚDO DO DOCUMENTO (${pdfPageCount} páginas)\n\n---\n${truncatedPdfText}\n---${truncNote}\n\nCom base no conteúdo acima, realize a extração técnica seguindo TODAS as seções da estrutura obrigatória. Seja conservador: não invente, não suponha, não transforme texto genérico em ação. Use OBRIGATORIAMENTE formatação Markdown com as seções definidas.`;
    } else {
      userMessage = `O conteúdo do documento "${documento_nome}" do tipo ${documento_tipo} não pôde ser extraído (possivelmente PDF escaneado ou protegido). ${empresa_emissora ? `Empresa: ${empresa_emissora}.` : ""} Gere a análise sinalizando todos os itens que precisam ser verificados manualmente pelo profissional responsável. Não invente dados.`;
    }

    const tipoNorm = documento_tipo?.toUpperCase?.() || "";
    const promptType = tipoNorm.includes("PCMSO") ? "PCMSO" : tipoNorm.includes("LTCAT") ? "LTCAT" : tipoNorm.includes("PGR") ? "PGR" : "genérico";
    console.log(`Enviando para OpenAI. Tipo: ${documento_tipo}. Prompt: ${promptType}. PDF: ${hasPdfContent ? `${(truncatedPdfText?.length || 0)} chars${wasTruncated ? " (truncado)" : ""}` : "não disponível"}`);

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userMessage },
        ],
        stream: true,
        temperature: 0.1,
        max_tokens: 16000,
      }),
    });

    if (!response.ok) {
      const t = await response.text();
      console.error("OpenAI API error:", response.status, t);

      if (response.status === 429) {
        return new Response(JSON.stringify({ error: "Limite de requisições excedido. Tente novamente em alguns minutos." }), {
          status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      return new Response(JSON.stringify({ error: `Erro na API OpenAI: ${response.status}` }), {
        status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(response.body, {
      headers: { ...corsHeaders, "Content-Type": "text/event-stream" },
    });
  } catch (e) {
    return respostaDeErro(e, corsHeaders);
  }
});
