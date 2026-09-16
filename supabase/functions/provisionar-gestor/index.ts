import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { admissao_id } = await req.json();
    if (!admissao_id) {
      return new Response(JSON.stringify({ error: "admissao_id obrigatório" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 1. Buscar admissão (dados de identidade)
    const { data: adm, error: errAdm } = await supabase
      .from("admissoes")
      .select("id, tenant_id, empresa_id, nome_completo, cpf, email")
      .eq("id", admissao_id)
      .maybeSingle();

    if (errAdm || !adm) {
      return new Response(JSON.stringify({ error: "Colaborador não encontrado" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const cpfLimpo = (adm.cpf || "").replace(/\D/g, "");
    if (!cpfLimpo || cpfLimpo.length < 11) {
      return new Response(JSON.stringify({ error: "CPF do colaborador é inválido" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Login existente fica em usuarios_base.email_principal (a tabela
    // admissoes não armazena login). Reaproveita se já houver.
    const { data: ubExistente } = await supabase
      .from("usuarios_base")
      .select("email_principal")
      .eq("tenant_id", adm.tenant_id)
      .eq("cpf", adm.cpf)
      .maybeSingle();

    let login = (ubExistente?.email_principal as string | null) || null;

    // 2. Gerar login se ainda não existir
    if (!login) {
      const { data: gen } = await supabase.rpc("gerar_login_youreyes", {
        p_nome_completo: adm.nome_completo,
      });
      login = gen as string | null;
      if (!login) {
        return new Response(
          JSON.stringify({
            error:
              "Não foi possível gerar login automático (conflito). Defina o login manualmente.",
          }),
          { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
    }

    // 3. Criar (ou recuperar) auth user
    let authUserId: string | null = null;
    const { data: existing } = await supabase.auth.admin.listUsers();
    const found = existing?.users?.find(
      (u) => (u.email || "").toLowerCase() === login!.toLowerCase(),
    );
    if (found) {
      authUserId = found.id;
    } else {
      const { data: created, error: errCreate } = await supabase.auth.admin.createUser({
        email: login,
        password: cpfLimpo,
        email_confirm: true,
        user_metadata: {
          nome_completo: adm.nome_completo,
          origem: "gestor_departamento",
          precisa_redefinir_senha: true,
        },
      });
      if (errCreate || !created.user) {
        return new Response(JSON.stringify({ error: errCreate?.message || "Falha ao criar auth user" }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      authUserId = created.user.id;
    }

    // 4. Garantir usuarios_base com auth_user_id
    const { data: ub } = await supabase
      .from("usuarios_base")
      .select("id, auth_user_id")
      .eq("tenant_id", adm.tenant_id)
      .or(`cpf.eq.${adm.cpf},auth_user_id.eq.${authUserId}`)
      .maybeSingle();

    let usuarioBaseId = ub?.id;
    if (!ub) {
      const { data: inserted } = await supabase
        .from("usuarios_base")
        .insert({
          tenant_id: adm.tenant_id,
          auth_user_id: authUserId,
          nome_completo: adm.nome_completo,
          cpf: adm.cpf,
          email_principal: login,
          tipo_usuario: "gestor",
          status: "ativo",
          origem_cadastro: "gestor_departamento",
        })
        .select("id")
        .single();
      usuarioBaseId = inserted?.id;
    } else if (!ub.auth_user_id) {
      await supabase
        .from("usuarios_base")
        .update({ auth_user_id: authUserId, email_principal: login })
        .eq("id", ub.id);
    }

    // 5. (O login fica em usuarios_base.email_principal — já gravado no
    // passo 4. A tabela admissoes não possui colunas de login/senha.)

    // 6. Vincular perfil "Gestor de Departamento"
    const { data: perfil } = await supabase
      .from("perfis_acesso")
      .select("id")
      .eq("tenant_id", adm.tenant_id)
      .eq("nome", "Gestor de Departamento")
      .maybeSingle();

    if (perfil && usuarioBaseId) {
      const { data: existingVinc } = await supabase
        .from("usuario_perfil_vinculos")
        .select("id")
        .eq("usuario_id", usuarioBaseId)
        .eq("perfil_id", perfil.id)
        .maybeSingle();
      if (!existingVinc) {
        await supabase.from("usuario_perfil_vinculos").insert({
          tenant_id: adm.tenant_id,
          usuario_id: usuarioBaseId,
          perfil_id: perfil.id,
          empresa_id: adm.empresa_id,
          ativo: true,
          is_perfil_principal: false,
        });
      }
    }

    return new Response(
      JSON.stringify({ login, senha_inicial: cpfLimpo, auth_user_id: authUserId }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String((e as Error)?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
