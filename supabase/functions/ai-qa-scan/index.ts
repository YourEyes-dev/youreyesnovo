import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

interface ScanResult {
  categoria: string;
  severidade: "critico" | "alto" | "medio" | "baixo" | "info";
  titulo: string;
  descricao: string;
  sugestao: string;
  modulo: string;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const { categoria } = await req.json();
    const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    if (!OPENAI_API_KEY) throw new Error("OPENAI_API_KEY não configurada");

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const findings: ScanResult[] = [];

    // ═══════════════════════════════════════════════════
    // 1. DADOS & INTEGRIDADE
    // ═══════════════════════════════════════════════════
    if (categoria === "dados" || categoria === "todos") {
      // Check tenants integrity
      const { data: tenants, error: tErr } = await supabase.from("tenants").select("id, nome, ativo");
      if (tErr) {
        findings.push({ categoria: "dados", severidade: "critico", titulo: "Falha ao consultar tenants", descricao: tErr.message, sugestao: "Verificar RLS e permissões da tabela tenants", modulo: "Tenants" });
      } else {
        // Check for orphan profiles (profiles without valid tenant)
        const tenantIds = (tenants || []).map(t => t.id);
        const { data: profiles, error: pErr } = await supabase.from("profiles").select("id, tenant_id, nome_completo");
        if (!pErr && profiles) {
          const orphans = profiles.filter(p => p.tenant_id && !tenantIds.includes(p.tenant_id));
          if (orphans.length > 0) {
            findings.push({ categoria: "dados", severidade: "alto", titulo: `${orphans.length} perfis órfãos detectados`, descricao: `Existem perfis vinculados a tenants que não existem mais: ${orphans.slice(0, 5).map(o => o.nome_completo).join(", ")}`, sugestao: "Verificar e remover ou reatribuir os perfis órfãos. Ir em Supabase > profiles e filtrar por tenant_id inválido.", modulo: "Perfis" });
          } else {
            findings.push({ categoria: "dados", severidade: "info", titulo: "Integridade de perfis OK", descricao: `Todos os ${profiles.length} perfis estão vinculados a tenants válidos`, sugestao: "", modulo: "Perfis" });
          }
        }

        // Check for tenants without any users
        for (const tenant of (tenants || [])) {
          const { count } = await supabase.from("profiles").select("id", { count: "exact", head: true }).eq("tenant_id", tenant.id);
          if ((count || 0) === 0) {
            findings.push({ categoria: "dados", severidade: "medio", titulo: `Tenant "${tenant.nome}" sem usuários`, descricao: `O tenant ${tenant.nome} não possui nenhum perfil vinculado`, sugestao: "Criar pelo menos um usuário owner para este tenant ou remover o tenant se não for mais necessário.", modulo: "Tenants" });
          }
        }

        // Check admissoes with missing required data
        const { data: admissoes } = await supabase.from("admissoes").select("id, nome_completo, cpf, email, cargo, status, tenant_id");
        if (admissoes) {
          const incomplete = admissoes.filter(a => !a.cpf || !a.email || !a.cargo);
          if (incomplete.length > 0) {
            findings.push({ categoria: "dados", severidade: "medio", titulo: `${incomplete.length} admissões com dados incompletos`, descricao: `Admissões sem CPF, email ou cargo: ${incomplete.slice(0, 3).map(a => a.nome_completo).join(", ")}`, sugestao: "Revisar e completar os dados obrigatórios das admissões no módulo Colaboradores.", modulo: "Admissão" });
          }
        }
      }

      // Check atestados integrity
      const { data: atestados } = await supabase.from("atestados").select("id, colaborador_nome, profissional_nome, profissional_registro, dias_afastamento, data_emissao");
      if (atestados) {
        const noDoc = atestados.filter(a => !a.profissional_registro);
        if (noDoc.length > 0) {
          findings.push({ categoria: "dados", severidade: "medio", titulo: `${noDoc.length} atestados sem registro profissional`, descricao: "Atestados sem número de registro do profissional de saúde", sugestao: "Completar o campo de registro profissional nos atestados para compliance.", modulo: "Saúde" });
        }
        findings.push({ categoria: "dados", severidade: "info", titulo: `${atestados.length} atestados no sistema`, descricao: "Total de atestados cadastrados", sugestao: "", modulo: "Saúde" });
      }

      // Check plano_acoes
      const { data: acoes } = await supabase.from("plano_acoes").select("id, status, progresso, data_conclusao");
      if (acoes) {
        const atrasadas = acoes.filter(a => a.status === "atrasada");
        if (atrasadas.length > 0) {
          findings.push({ categoria: "dados", severidade: "medio", titulo: `${atrasadas.length} ações atrasadas no Plano de Ação`, descricao: "Existem ações com prazo vencido", sugestao: "Revisar o Plano de Ação global e atualizar prazos ou concluir ações pendentes.", modulo: "Plano de Ação" });
        }
        const concluidas100 = acoes.filter(a => a.status === "concluida" && a.progresso < 100);
        if (concluidas100.length > 0) {
          findings.push({ categoria: "dados", severidade: "baixo", titulo: `${concluidas100.length} ações concluídas com progresso < 100%`, descricao: "Inconsistência entre status e progresso", sugestao: "Atualizar o progresso das ações marcadas como concluídas para 100%.", modulo: "Plano de Ação" });
        }
      }
    }

    // ═══════════════════════════════════════════════════
    // 2. SEGURANÇA & RLS
    // ═══════════════════════════════════════════════════
    if (categoria === "seguranca" || categoria === "todos") {
      // Test anonymous access to sensitive tables
      const anonClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY") || "");
      
      const sensitiveTables = ["profiles", "admissoes", "atestados", "user_roles", "superadmins", "plano_acoes"];
      for (const table of sensitiveTables) {
        try {
          const { data, error } = await anonClient.from(table).select("id").limit(1);
          if (!error && data && data.length > 0) {
            findings.push({ categoria: "seguranca", severidade: "critico", titulo: `Tabela "${table}" acessível anonimamente`, descricao: `A tabela ${table} permite leitura sem autenticação`, sugestao: `Revisar as políticas RLS da tabela "${table}". Remover policies com USING(true) para SELECT. Adicionar verificação de auth.uid().`, modulo: "RLS" });
          } else if (error && error.code === "PGRST301") {
            findings.push({ categoria: "seguranca", severidade: "info", titulo: `Tabela "${table}" protegida por RLS ✓`, descricao: "Acesso anônimo corretamente bloqueado", sugestao: "", modulo: "RLS" });
          }
        } catch { /* ignore */ }
      }

      // Check superadmins table
      const { data: superadmins } = await supabase.from("superadmins").select("id, email, ativo");
      if (superadmins) {
        const inativos = superadmins.filter(s => !s.ativo);
        if (inativos.length > 0) {
          findings.push({ categoria: "seguranca", severidade: "baixo", titulo: `${inativos.length} superadmins inativos`, descricao: "Existem registros de superadmin desativados", sugestao: "Considerar remover superadmins inativos para manter a tabela limpa.", modulo: "Auth" });
        }
        findings.push({ categoria: "seguranca", severidade: "info", titulo: `${superadmins.filter(s => s.ativo).length} superadmins ativos`, descricao: "Total de administradores globais", sugestao: "", modulo: "Auth" });
      }

      // Check user_roles distribution
      const { data: roles } = await supabase.from("user_roles").select("role");
      if (roles) {
        const roleCounts: Record<string, number> = {};
        roles.forEach(r => { roleCounts[r.role] = (roleCounts[r.role] || 0) + 1; });
        findings.push({ categoria: "seguranca", severidade: "info", titulo: "Distribuição de roles", descricao: Object.entries(roleCounts).map(([r, c]) => `${r}: ${c}`).join(", "), sugestao: "", modulo: "Auth" });
        
        const owners = roleCounts["owner"] || 0;
        const admins = roleCounts["admin"] || 0;
        if (owners + admins > roles.length * 0.5) {
          findings.push({ categoria: "seguranca", severidade: "medio", titulo: "Alta concentração de roles privilegiadas", descricao: `${owners + admins} de ${roles.length} usuários têm role owner/admin (>50%)`, sugestao: "Revisar se todos os owners/admins realmente precisam de permissões elevadas. Princípio do menor privilégio.", modulo: "Auth" });
        }
      }
    }

    // ═══════════════════════════════════════════════════
    // 3. EDGE FUNCTIONS
    // ═══════════════════════════════════════════════════
    if (categoria === "edge_functions" || categoria === "todos") {
      const edgeFunctions = [
        "onboarding-signup", "extract-atestado", "ai-plano-acao", "ai-ouvidoria",
        "ai-chat", "ai-psicossocial-analise", "ai-sst-analise", "ai-feedback",
        "ai-pdi-smart", "ai-nf-ocr", "ai-nf-match", "ai-pgr-riscos"
      ];

      for (const fn of edgeFunctions) {
        try {
          const resp = await fetch(`${SUPABASE_URL}/functions/v1/${fn}`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Authorization": `Bearer ${Deno.env.get("SUPABASE_ANON_KEY") || ""}`,
            },
            body: JSON.stringify({ test: true }),
          });
          
          if (resp.status === 500) {
            const text = await resp.text();
            findings.push({ categoria: "edge_functions", severidade: "alto", titulo: `Edge Function "${fn}" retornou 500`, descricao: `Erro interno: ${text.slice(0, 200)}`, sugestao: `Verificar logs da edge function "${fn}" no Supabase Dashboard. Possível falta de variável de ambiente ou erro de código.`, modulo: "Edge Functions" });
          } else if (resp.status === 404) {
            await resp.text();
            findings.push({ categoria: "edge_functions", severidade: "alto", titulo: `Edge Function "${fn}" não encontrada (404)`, descricao: "A função não está deployada", sugestao: `Verificar se o arquivo supabase/functions/${fn}/index.ts existe e se o deploy foi realizado.`, modulo: "Edge Functions" });
          } else {
            await resp.text();
            findings.push({ categoria: "edge_functions", severidade: "info", titulo: `Edge Function "${fn}" respondendo ✓`, descricao: `Status: ${resp.status}`, sugestao: "", modulo: "Edge Functions" });
          }
        } catch (e) {
          findings.push({ categoria: "edge_functions", severidade: "critico", titulo: `Edge Function "${fn}" inacessível`, descricao: `Erro de conexão: ${(e as Error).message}`, sugestao: "Verificar se a edge function está deployada e acessível.", modulo: "Edge Functions" });
        }
      }
      }

      // Check WhatsApp Connectivity
      try {
        const resp = await fetch(`${SUPABASE_URL}/functions/v1/psicossocial-whatsapp-otp`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${Deno.env.get("SUPABASE_ANON_KEY") || ""}`,
          },
          body: JSON.stringify({ action: "status" }),
        });
        const data = await resp.json();
        if (data?.status?.message === "WhatsApp disconnected") {
          findings.push({ 
            categoria: "edge_functions", 
            severidade: "critico", 
            titulo: "WhatsApp Desconectado", 
            descricao: "A instância do WhatsApp no gateway está desconectada. Os OTPs psicossociais não estão sendo enviados.", 
            sugestao: "Reconectar a instância do WhatsApp no gateway (QR Code) e verificar se o chip está ativo.", 
            modulo: "Psicossocial" 
          });
        } else if (!resp.ok) {
          findings.push({ 
            categoria: "edge_functions", 
            severidade: "alto", 
            titulo: "Erro ao checar status do WhatsApp", 
            descricao: data?.erro || "Erro desconhecido", 
            sugestao: "Verificar chaves WHATSAPI_TOKEN e WHATSAPI_BASE_URL nas secrets.", 
            modulo: "Psicossocial" 
          });
        } else {
          findings.push({ 
            categoria: "edge_functions", 
            severidade: "info", 
            titulo: "WhatsApp Conectado ✓", 
            descricao: "Instância do WhatsApp está operacional.", 
            sugestao: "", 
            modulo: "Psicossocial" 
          });
        }
      } catch (e) {
        findings.push({ categoria: "edge_functions", severidade: "medio", titulo: "Falha na verificação de status do WhatsApp", descricao: (e as Error).message, sugestao: "Tentar novamente mais tarde.", modulo: "Psicossocial" });
      }

    // ═══════════════════════════════════════════════════
    // 4. MÓDULOS ESPECÍFICOS
    // ═══════════════════════════════════════════════════
    if (categoria === "modulos" || categoria === "todos") {
      // Psicossocial - check campanhas
      const { data: campanhas } = await supabase.from("questionario_psicossocial_campanhas").select("id, nome, status, instrumento, total_convidados, total_respostas");
      if (campanhas) {
        findings.push({ categoria: "modulos", severidade: "info", titulo: `${campanhas.length} campanhas psicossociais`, descricao: `Ativas: ${campanhas.filter(c => c.status === "ativa").length}, Finalizadas: ${campanhas.filter(c => c.status === "finalizada").length}`, sugestao: "", modulo: "Psicossocial" });
        
        const baixaAdesao = campanhas.filter(c => c.status === "ativa" && c.total_convidados > 0 && (c.total_respostas / c.total_convidados) < 0.3);
        if (baixaAdesao.length > 0) {
          findings.push({ categoria: "modulos", severidade: "medio", titulo: `${baixaAdesao.length} campanhas com baixa adesão (<30%)`, descricao: baixaAdesao.map(c => `"${c.nome}": ${c.total_respostas}/${c.total_convidados}`).join(", "), sugestao: "Considerar reenviar convites ou estender o prazo das campanhas com baixa participação.", modulo: "Psicossocial" });
        }
      }

      // Check EPIs
      const { data: epis } = await supabase.from("epis").select("id, nome, quantidade_estoque, estoque_minimo");
      if (epis) {
        const abaixoMinimo = epis.filter(e => e.quantidade_estoque < (e.estoque_minimo || 0));
        if (abaixoMinimo.length > 0) {
          findings.push({ categoria: "modulos", severidade: "medio", titulo: `${abaixoMinimo.length} EPIs abaixo do estoque mínimo`, descricao: abaixoMinimo.slice(0, 5).map(e => `${e.nome}: ${e.quantidade_estoque}/${e.estoque_minimo}`).join(", "), sugestao: "Repor estoque dos EPIs listados no módulo de EPIs.", modulo: "EPIs" });
        }
      }

      // Check afastamentos
      const { data: afastamentos } = await supabase.from("afastamentos").select("id, colaborador_nome, status, dias_totais, aso_retorno_pendente");
      if (afastamentos) {
        const asosPendentes = afastamentos.filter(a => a.aso_retorno_pendente);
        if (asosPendentes.length > 0) {
          findings.push({ categoria: "modulos", severidade: "alto", titulo: `${asosPendentes.length} ASOs de retorno pendentes`, descricao: `Colaboradores com afastamento ≥30 dias sem ASO de retorno: ${asosPendentes.slice(0, 3).map(a => a.colaborador_nome).join(", ")}`, sugestao: "Agendar ASO de retorno para os colaboradores listados. Obrigatório por NR-07.", modulo: "Saúde" });
        }
      }

      // Check documentos de admissão pendentes
      const { data: admDocs } = await supabase.from("admissao_documentos").select("id, status, admissao_id, nome");
      if (admDocs) {
        const pendentes = admDocs.filter(d => d.status === "pendente");
        if (pendentes.length > 0) {
          findings.push({ categoria: "modulos", severidade: "medio", titulo: `${pendentes.length} documentos de admissão pendentes`, descricao: "Documentos aguardando envio ou aprovação", sugestao: "Verificar os documentos pendentes no módulo de Admissão e cobrar os colaboradores.", modulo: "Admissão" });
        }
      }

      // Check ponto_alertas
      const { data: pontoAlertas } = await supabase.from("ponto_alertas").select("id, tipo, severidade, resolvido").eq("resolvido", false);
      if (pontoAlertas && pontoAlertas.length > 0) {
        const criticos = pontoAlertas.filter(a => a.severidade === "critica");
        findings.push({ categoria: "modulos", severidade: criticos.length > 0 ? "alto" : "medio", titulo: `${pontoAlertas.length} alertas de ponto não resolvidos`, descricao: `${criticos.length} críticos (interjornada), ${pontoAlertas.length - criticos.length} outros`, sugestao: "Verificar os alertas de ponto no módulo de Ponto Eletrônico e tratar as irregularidades.", modulo: "Ponto" });
      }
    }

    // ═══════════════════════════════════════════════════
    // 5. IA ANALYSIS - Send findings to OpenAI for summary
    // ═══════════════════════════════════════════════════
    let aiSummary = "";
    if (findings.length > 0) {
      try {
        const aiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${OPENAI_API_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model: "gpt-4o-mini",
            messages: [
              {
                role: "system",
                content: `Você é um especialista em QA e segurança de sistemas SaaS de RH. Analise os findings da varredura e forneça:
1. Um resumo executivo (2-3 frases)
2. As 3 ações mais urgentes
3. Uma nota de saúde do sistema (0-100)

Responda em português do Brasil. Seja direto e prático.`
              },
              {
                role: "user",
                content: `Findings da varredura (categoria: ${categoria}):\n\n${JSON.stringify(findings, null, 2)}`
              }
            ],
            max_tokens: 1000,
          }),
        });

        if (aiResponse.ok) {
          const aiData = await aiResponse.json();
          aiSummary = aiData.choices?.[0]?.message?.content || "";
        }
      } catch (e) {
        console.error("AI analysis error:", e);
        aiSummary = "Análise de IA indisponível no momento.";
      }
    }

    return new Response(JSON.stringify({
      success: true,
      categoria,
      timestamp: new Date().toISOString(),
      total_findings: findings.length,
      criticos: findings.filter(f => f.severidade === "critico").length,
      altos: findings.filter(f => f.severidade === "alto").length,
      medios: findings.filter(f => f.severidade === "medio").length,
      baixos: findings.filter(f => f.severidade === "baixo").length,
      info: findings.filter(f => f.severidade === "info").length,
      findings,
      ai_summary: aiSummary,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (e) {
    console.error("QA scan error:", e);
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
