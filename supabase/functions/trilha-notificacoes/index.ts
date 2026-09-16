import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceKey);

    const now = new Date();
    const notifications: {
      tenant_id: string;
      colaborador_id: string;
      colaborador_nome: string;
      trilha_id: string;
      trilha_nome: string;
      tipo: string;
      titulo: string;
      descricao: string;
    }[] = [];

    // 1. Get all active trilhas with prazo_dias set
    const { data: trilhas } = await supabase
      .from("trilhas")
      .select("id, tenant_id, nome, prazo_dias, status")
      .eq("status", "ativa")
      .not("prazo_dias", "is", null);

    if (trilhas && trilhas.length > 0) {
      // 2. Get all in-progress assignments (progresso records)
      const trilhaIds = trilhas.map((t: any) => t.id);
      const { data: progressos } = await supabase
        .from("trilha_progresso")
        .select("trilha_id, colaborador_id, colaborador_nome, tenant_id, status, data_inicio, updated_at")
        .in("trilha_id", trilhaIds);

      if (progressos) {
        // Group by collaborator+trilha to find earliest start
        const grouped: Record<string, { colaborador_id: string; colaborador_nome: string; tenant_id: string; trilha_id: string; earliest_start: string; latest_update: string; all_concluido: boolean; has_em_andamento: boolean }> = {};

        for (const p of progressos) {
          const key = `${p.colaborador_id}_${p.trilha_id}`;
          if (!grouped[key]) {
            grouped[key] = {
              colaborador_id: p.colaborador_id,
              colaborador_nome: p.colaborador_nome,
              tenant_id: p.tenant_id,
              trilha_id: p.trilha_id,
              earliest_start: p.data_inicio || p.updated_at,
              latest_update: p.updated_at,
              all_concluido: p.status === "concluido",
              has_em_andamento: p.status === "em_andamento",
            };
          } else {
            if (p.data_inicio && p.data_inicio < grouped[key].earliest_start) {
              grouped[key].earliest_start = p.data_inicio;
            }
            if (p.updated_at > grouped[key].latest_update) {
              grouped[key].latest_update = p.updated_at;
            }
            if (p.status !== "concluido") grouped[key].all_concluido = false;
            if (p.status === "em_andamento") grouped[key].has_em_andamento = true;
          }
        }

        for (const [, g] of Object.entries(grouped)) {
          if (g.all_concluido) continue; // already finished

          const trilha = trilhas.find((t: any) => t.id === g.trilha_id);
          if (!trilha) continue;

          const startDate = new Date(g.earliest_start);
          const deadlineDate = new Date(startDate.getTime() + trilha.prazo_dias * 86400000);
          const daysUntilDeadline = Math.ceil((deadlineDate.getTime() - now.getTime()) / 86400000);
          const daysSinceUpdate = Math.ceil((now.getTime() - new Date(g.latest_update).getTime()) / 86400000);

          // Deadline approaching (3 days)
          if (daysUntilDeadline <= 3 && daysUntilDeadline > 0) {
            notifications.push({
              tenant_id: g.tenant_id,
              colaborador_id: g.colaborador_id,
              colaborador_nome: g.colaborador_nome,
              trilha_id: g.trilha_id,
              trilha_nome: trilha.nome,
              tipo: "prazo_proximo",
              titulo: `Prazo próximo: ${trilha.nome}`,
              descricao: `Faltam ${daysUntilDeadline} dia(s) para o prazo da trilha "${trilha.nome}". Conclua os módulos pendentes.`,
            });
          }

          // Deadline expired
          if (daysUntilDeadline <= 0) {
            notifications.push({
              tenant_id: g.tenant_id,
              colaborador_id: g.colaborador_id,
              colaborador_nome: g.colaborador_nome,
              trilha_id: g.trilha_id,
              trilha_nome: trilha.nome,
              tipo: "prazo_vencido",
              titulo: `Prazo vencido: ${trilha.nome}`,
              descricao: `O prazo da trilha "${trilha.nome}" expirou há ${Math.abs(daysUntilDeadline)} dia(s). Entre em contato com seu gestor.`,
            });
          }

          // Abandonment (no activity for 14+ days)
          if (daysSinceUpdate >= 14 && g.has_em_andamento) {
            notifications.push({
              tenant_id: g.tenant_id,
              colaborador_id: g.colaborador_id,
              colaborador_nome: g.colaborador_nome,
              trilha_id: g.trilha_id,
              trilha_nome: trilha.nome,
              tipo: "abandono",
              titulo: `Trilha abandonada? ${trilha.nome}`,
              descricao: `Você não acessa a trilha "${trilha.nome}" há ${daysSinceUpdate} dias. Retome para não perder o progresso!`,
            });
          }
        }
      }
    }

    // 3. Also check for collaborators who haven't started assigned trilhas (from atribuicoes)
    const { data: atribuicoes } = await supabase
      .from("trilha_atribuicoes")
      .select("id, tenant_id, trilha_id, colaborador_id, colaborador_nome, created_at");

    if (atribuicoes && atribuicoes.length > 0) {
      for (const attr of atribuicoes) {
        const daysSinceAssigned = Math.ceil((now.getTime() - new Date(attr.created_at).getTime()) / 86400000);
        if (daysSinceAssigned < 7) continue; // wait 7 days before reminding

        // Check if they have any progress
        const { data: prog } = await supabase
          .from("trilha_progresso")
          .select("id")
          .eq("trilha_id", attr.trilha_id)
          .eq("colaborador_id", attr.colaborador_id)
          .limit(1);

        if (!prog || prog.length === 0) {
          const trilha = trilhas?.find((t: any) => t.id === attr.trilha_id);
          const trilhaNome = trilha?.nome || "Trilha atribuída";
          notifications.push({
            tenant_id: attr.tenant_id,
            colaborador_id: attr.colaborador_id,
            colaborador_nome: attr.colaborador_nome,
            trilha_id: attr.trilha_id,
            trilha_nome: trilhaNome,
            tipo: "lembrete_retorno",
            titulo: `Trilha pendente: ${trilhaNome}`,
            descricao: `A trilha "${trilhaNome}" foi atribuída a você há ${daysSinceAssigned} dias e ainda não foi iniciada.`,
          });
        }
      }
    }

    // 4. Deduplicate - don't create if same type+trilha+colaborador already exists today
    const inserted: string[] = [];
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();

    for (const notif of notifications) {
      const { data: existing } = await supabase
        .from("trilha_notificacoes")
        .select("id")
        .eq("colaborador_id", notif.colaborador_id)
        .eq("trilha_id", notif.trilha_id)
        .eq("tipo", notif.tipo)
        .gte("created_at", todayStart)
        .limit(1);

      if (!existing || existing.length === 0) {
        const { error } = await supabase
          .from("trilha_notificacoes")
          .insert(notif);
        if (!error) inserted.push(notif.tipo);
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        checked_trilhas: trilhas?.length || 0,
        notifications_created: inserted.length,
        types: inserted,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
