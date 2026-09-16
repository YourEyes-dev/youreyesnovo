import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });

    const TEST_EMAIL = "teste@seguramente.com";
    const TEST_PASSWORD = "123456";

    // 1. Create or get auth user
    let userId: string;
    const { data: existingUsers } = await admin.auth.admin.listUsers();
    const existing = existingUsers?.users?.find((u: any) => u.email === TEST_EMAIL);
    
    if (existing) {
      userId = existing.id;
      // Update password
      await admin.auth.admin.updateUserById(userId, { password: TEST_PASSWORD, email_confirm: true });
    } else {
      const { data: newUser, error: createErr } = await admin.auth.admin.createUser({
        email: TEST_EMAIL,
        password: TEST_PASSWORD,
        email_confirm: true,
        user_metadata: { nome_completo: "Usuário Demonstração" },
      });
      if (createErr) throw createErr;
      userId = newUser.user.id;
    }

    // 2. Create or get tenant
    let tenantId: string;
    const { data: existingProfile } = await admin.from("profiles").select("tenant_id").eq("user_id", userId).single();
    
    if (existingProfile?.tenant_id) {
      tenantId = existingProfile.tenant_id;
    } else {
      // Try to find existing tenant by slug first
      const { data: existingTenant } = await admin.from("tenants").select("id").eq("slug", "demo-seguramente").maybeSingle();
      if (existingTenant) {
        tenantId = existingTenant.id;
      } else {
        const { data: tenant, error: tenantErr } = await admin.from("tenants").insert({
          nome: "Seguramente Demonstração Ltda",
          slug: "demo-seguramente",
          plano: "enterprise",
          ativo: true,
        }).select().single();
        if (tenantErr) throw tenantErr;
        tenantId = tenant.id;
      }
    }

    // Always ensure profile exists
    const { error: profErr } = await admin.from("profiles").upsert({
      user_id: userId,
      tenant_id: tenantId,
      nome_completo: "Usuário Demonstração",
      cargo: "Diretor de RH",
      onboarding_concluido: true,
    }, { onConflict: "user_id" });
    if (profErr) console.error("Profile error:", profErr);

    // Always ensure role exists
    await admin.from("user_roles").upsert({
      user_id: userId,
      role: "owner",
    }, { onConflict: "user_id,role" });

    // 3. Create empresa
    const { data: existingEmpresa } = await admin.from("empresa_cadastro").select("id").eq("tenant_id", tenantId).limit(1).maybeSingle();
    let empresaId: string;
    if (existingEmpresa) {
      empresaId = existingEmpresa.id;
    } else {
      const { data: empresa, error: empErr } = await admin.from("empresa_cadastro").insert({
        tenant_id: tenantId,
        razao_social: "Seguramente Demonstração Ltda",
        nome_fantasia: "Seguramente Demo",
        cnpj: "12.345.678/0001-90",
        inscricao_estadual: "123456789",
        cnae_principal: "6201-5/01",
        grau_risco: 2,
        endereco: "Av. Paulista, 1000",
        cidade: "São Paulo",
        estado: "SP",
        cep: "01310-100",
        telefone: "(11) 3000-0000",
        email: "contato@seguramente.com",
        ativo: true,
      }).select().single();
      if (empErr) {
        // Might be duplicate cnpj, try to fetch
        const { data: fallback } = await admin.from("empresa_cadastro").select("id").eq("tenant_id", tenantId).limit(1).maybeSingle();
        if (fallback) {
          empresaId = fallback.id;
        } else {
          throw empErr;
        }
      } else {
        empresaId = empresa.id;
      }
    }

    // 4. Seed employees (admissoes) - 15 employees
    const employees = [
      { nome_completo: "Ana Clara Souza", cpf: "111.222.333-01", email: "ana.souza@demo.com", cargo: "Analista de RH", departamento: "Recursos Humanos", salario: 5500, status: "concluido" },
      { nome_completo: "Bruno Oliveira Santos", cpf: "111.222.333-02", email: "bruno.santos@demo.com", cargo: "Engenheiro de Segurança", departamento: "SST", salario: 9800, status: "concluido" },
      { nome_completo: "Carla Mendes Ferreira", cpf: "111.222.333-03", email: "carla.ferreira@demo.com", cargo: "Gerente Financeiro", departamento: "Financeiro", salario: 12000, status: "concluido" },
      { nome_completo: "Daniel Pereira Lima", cpf: "111.222.333-04", email: "daniel.lima@demo.com", cargo: "Técnico de Segurança", departamento: "SST", salario: 4200, status: "concluido" },
      { nome_completo: "Elena Rodrigues Costa", cpf: "111.222.333-05", email: "elena.costa@demo.com", cargo: "Coordenadora de DP", departamento: "Departamento Pessoal", salario: 7500, status: "concluido" },
      { nome_completo: "Fernando Almeida Neto", cpf: "111.222.333-06", email: "fernando.neto@demo.com", cargo: "Operador de Produção", departamento: "Produção", salario: 3200, status: "concluido" },
      { nome_completo: "Gabriela Torres Silva", cpf: "111.222.333-07", email: "gabriela.silva@demo.com", cargo: "Médica do Trabalho", departamento: "Saúde Ocupacional", salario: 15000, status: "concluido" },
      { nome_completo: "Henrique Barbosa", cpf: "111.222.333-08", email: "henrique.barbosa@demo.com", cargo: "Supervisor de Produção", departamento: "Produção", salario: 6800, status: "concluido" },
      { nome_completo: "Isabela Martins", cpf: "111.222.333-09", email: "isabela.martins@demo.com", cargo: "Assistente Administrativo", departamento: "Administração", salario: 2800, status: "concluido" },
      { nome_completo: "João Victor Ramos", cpf: "111.222.333-10", email: "joao.ramos@demo.com", cargo: "Analista Contábil", departamento: "Contabilidade", salario: 5000, status: "concluido" },
      { nome_completo: "Karen Duarte", cpf: "111.222.333-11", email: "karen.duarte@demo.com", cargo: "Recepcionista", departamento: "Administração", salario: 2500, status: "concluido" },
      { nome_completo: "Lucas Fernandes", cpf: "111.222.333-12", email: "lucas.fernandes@demo.com", cargo: "Auxiliar de Produção", departamento: "Produção", salario: 2600, status: "aguardando_documentos" },
      { nome_completo: "Marina Costa Pinto", cpf: "111.222.333-13", email: "marina.pinto@demo.com", cargo: "Enfermeira do Trabalho", departamento: "Saúde Ocupacional", salario: 6500, status: "concluido" },
      { nome_completo: "Nicolas Araújo", cpf: "111.222.333-14", email: "nicolas.araujo@demo.com", cargo: "Estagiário de TI", departamento: "Tecnologia", salario: 1800, status: "em_analise" },
      { nome_completo: "Patrícia Vieira", cpf: "111.222.333-15", email: "patricia.vieira@demo.com", cargo: "Gestora de Pessoas", departamento: "Recursos Humanos", salario: 8500, status: "concluido" },
    ];

    // Delete existing test data for this tenant first
    await admin.from("admissoes").delete().eq("tenant_id", tenantId);

    const admissaoInserts = employees.map((emp) => ({
      tenant_id: tenantId,
      empresa_id: empresaId,
      ...emp,
      data_admissao: "2024-" + String(Math.floor(Math.random() * 12) + 1).padStart(2, "0") + "-" + String(Math.floor(Math.random() * 28) + 1).padStart(2, "0"),
      tipo_contrato: "CLT",
      jornada_trabalho: "44h semanais",
      data_nascimento: `${1980 + Math.floor(Math.random() * 20)}-${String(Math.floor(Math.random() * 12) + 1).padStart(2, "0")}-${String(Math.floor(Math.random() * 28) + 1).padStart(2, "0")}`,
      estado_civil: ["solteiro", "casado", "divorciado"][Math.floor(Math.random() * 3)],
      genero: emp.nome_completo.endsWith("a") || emp.nome_completo.includes("Elena") || emp.nome_completo.includes("Karen") || emp.nome_completo.includes("Marina") || emp.nome_completo.includes("Patrícia") || emp.nome_completo.includes("Ana") || emp.nome_completo.includes("Carla") || emp.nome_completo.includes("Gabriela") || emp.nome_completo.includes("Isabela") ? "feminino" : "masculino",
      endereco: "Rua das Flores, " + Math.floor(Math.random() * 999 + 1),
      cidade: "São Paulo",
      estado: "SP",
      cep: "01000-" + String(Math.floor(Math.random() * 999)).padStart(3, "0"),
      criado_por: userId,
    }));

    await admin.from("admissoes").insert(admissaoInserts);

    // ═══════════════════════════════════════════════════════════════
    // 5. HUB CONTÁBIL - Competências, Documentos, Guias, Certidões
    // ═══════════════════════════════════════════════════════════════
    
    // Clean existing
    await admin.from("hub_historico").delete().eq("tenant_id", tenantId);
    await admin.from("hub_documentos").delete().eq("tenant_id", tenantId);
    await admin.from("hub_guias").delete().eq("tenant_id", tenantId);
    await admin.from("hub_certidoes").delete().eq("tenant_id", tenantId);
    await admin.from("hub_competencias").delete().eq("tenant_id", tenantId);

    // Competências - últimos 6 meses
    const competencias = [];
    for (let i = 5; i >= 0; i--) {
      const d = new Date();
      d.setMonth(d.getMonth() - i);
      const comp = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
      const status = i === 0 ? "em_preparacao" : i === 1 ? "enviado_contador" : "finalizado";
      competencias.push({
        tenant_id: tenantId,
        competencia: comp,
        status,
        checklist: {
          ponto_fechado: i > 0,
          eventos_confirmados: i > 0,
          rescisoes_revisadas: i > 0,
          ferias_calculadas: i > 0,
          beneficios_atualizados: i > 0,
        },
        data_envio: i > 1 ? `${comp}-05` : null,
        enviado_por: i > 1 ? "Usuário Demonstração" : null,
        data_aprovacao: i > 1 ? `${comp}-08` : null,
        aprovado_por: i > 1 ? "Contador José" : null,
      });
    }
    const { data: compData } = await admin.from("hub_competencias").insert(competencias).select("id, competencia");

    // Documentos para cada competência
    const docTypes = [
      { tipo: "folha_pagamento", desc: "Folha de Pagamento" },
      { tipo: "holerite", desc: "Holerites Individuais" },
      { tipo: "guia_fgts", desc: "Guia FGTS - GFIP" },
      { tipo: "guia_inss", desc: "Guia GPS - INSS" },
      { tipo: "guia_irrf", desc: "Guia DARF - IRRF" },
      { tipo: "resumo_folha", desc: "Resumo da Folha" },
      { tipo: "provisoes", desc: "Provisões 13° e Férias" },
    ];

    const hubDocs: any[] = [];
    const hubGuias: any[] = [];
    
    for (const comp of compData || []) {
      const isRecent = comp.competencia >= new Date().toISOString().slice(0, 7);
      
      for (const dt of docTypes) {
        hubDocs.push({
          tenant_id: tenantId,
          competencia: comp.competencia,
          competencia_id: comp.id,
          tipo: dt.tipo,
          descricao: dt.desc,
          direcao: "envio",
          status: isRecent ? "pendente" : "enviado",
          enviado_por: isRecent ? null : "Usuário Demonstração",
        });
      }

      // Guias
      const guiaItems = [
        { tipo: "FGTS", valor: 8500 + Math.random() * 3000 },
        { tipo: "INSS", valor: 12000 + Math.random() * 5000 },
        { tipo: "IRRF", valor: 3500 + Math.random() * 2000 },
        { tipo: "PIS", valor: 800 + Math.random() * 500 },
      ];
      for (const g of guiaItems) {
        const venc = comp.competencia + "-20";
        hubGuias.push({
          tenant_id: tenantId,
          competencia: comp.competencia,
          competencia_id: comp.id,
          tipo: g.tipo,
          valor: Math.round(g.valor * 100) / 100,
          data_vencimento: venc,
          data_pagamento: isRecent ? null : venc,
          status: isRecent ? "pendente" : "paga",
        });
      }
    }

    await admin.from("hub_documentos").insert(hubDocs);
    await admin.from("hub_guias").insert(hubGuias);

    // Certidões / CNDs
    const certidoes = [
      { tipo: "CND Federal", orgao_emissor: "Receita Federal", data_emissao: "2025-12-01", data_validade: "2026-05-30", numero: "CND-FED-2025-001" },
      { tipo: "CND Estadual", orgao_emissor: "Sefaz SP", data_emissao: "2026-01-15", data_validade: "2026-07-15", numero: "CND-EST-2026-001" },
      { tipo: "CND Municipal", orgao_emissor: "Prefeitura de São Paulo", data_emissao: "2026-02-01", data_validade: "2026-08-01", numero: "CND-MUN-2026-001" },
      { tipo: "CRF FGTS", orgao_emissor: "Caixa Econômica Federal", data_emissao: "2026-02-20", data_validade: "2026-03-22", numero: "CRF-2026-001" },
      { tipo: "CNDT Trabalhista", orgao_emissor: "TST", data_emissao: "2026-01-10", data_validade: "2026-07-10", numero: "CNDT-2026-001" },
      { tipo: "CND Previdenciária", orgao_emissor: "INSS / RFB", data_emissao: "2025-10-01", data_validade: "2026-03-15", numero: "CND-PREV-2025-001" },
    ];

    await admin.from("hub_certidoes").insert(certidoes.map(c => ({ ...c, tenant_id: tenantId })));

    // Histórico
    const historico = [
      { acao: "criado", competencia: competencias[0].competencia, usuario_nome: "Sistema (automático)", perfil: "sistema", descricao: "Competência aberta automaticamente" },
      { acao: "documento_enviado", competencia: competencias[1].competencia, usuario_nome: "Usuário Demonstração", perfil: "rh", descricao: "Folha de pagamento enviada ao contador" },
      { acao: "aprovado", competencia: competencias[2].competencia, usuario_nome: "Contador José", perfil: "contador", descricao: "Competência aprovada pelo contador" },
      { acao: "guia_paga", competencia: competencias[3].competencia, usuario_nome: "Carla Mendes Ferreira", perfil: "financeiro", descricao: "FGTS pago — R$ 9.250,00" },
      { acao: "certidao_renovada", competencia: null, usuario_nome: "Usuário Demonstração", perfil: "rh", descricao: "CND Federal renovada — validade até 30/05/2026" },
    ];
    await admin.from("hub_historico").insert(historico.map(h => ({ ...h, tenant_id: tenantId })));

    // ═══════════════════════════════════════════════════════════════
    // 6. PSICOSSOCIAL - Campanha com respostas e scores
    // ═══════════════════════════════════════════════════════════════
    
    // Clean existing
    await admin.from("questionario_psicossocial_respostas").delete().eq("tenant_id", tenantId);
    await admin.from("questionario_psicossocial_convites").delete().eq("tenant_id", tenantId);
    await admin.from("questionario_psicossocial_campanhas").delete().eq("tenant_id", tenantId);

    // Create campaign - completed
    const radarData = [
      { subject: "Demandas Quantitativas", value: 62, fullMark: 100 },
      { subject: "Demandas Cognitivas", value: 55, fullMark: 100 },
      { subject: "Demandas Emocionais", value: 70, fullMark: 100 },
      { subject: "Autonomia", value: 75, fullMark: 100 },
      { subject: "Clareza de Papel", value: 80, fullMark: 100 },
      { subject: "Reconhecimento", value: 58, fullMark: 100 },
      { subject: "Relacionamentos", value: 82, fullMark: 100 },
      { subject: "Recuperação", value: 45, fullMark: 100 },
      { subject: "Sentido do Trabalho", value: 88, fullMark: 100 },
      { subject: "Sinais Precoces", value: 38, fullMark: 100 },
    ];

    const { data: campanha1 } = await admin.from("questionario_psicossocial_campanhas").insert({
      tenant_id: tenantId,
      nome: "Avaliação Psicossocial — 1º Semestre 2026",
      descricao: "Campanha semestral obrigatória de avaliação dos riscos psicossociais conforme NR-01 atualizada.",
      tipo: "ordinaria",
      instrumento: "sipro",
      periodicidade: "semestral",
      status: "encerrada",
      data_inicio: "2026-01-15",
      data_fim: "2026-02-15",
      anonimo: true,
      permite_identificacao_voluntaria: false,
      total_respostas: 11,
      ips_score: 65,
      ips_classificacao: "estavel",
      irps_score: 58,
      ibo_score: 52,
      ibd_score: 72,
      irec_score: 45,
      icop_score: 78,
      inot_score: null,
      radar_data: radarData,
      criado_por: userId,
      criado_por_nome: "Usuário Demonstração",
    }).select().single();

    // Create campaign 2 - active
    const { data: campanha2 } = await admin.from("questionario_psicossocial_campanhas").insert({
      tenant_id: tenantId,
      nome: "Avaliação Psicossocial — Pós-Reestruturação",
      descricao: "Campanha extraordinária após reestruturação do setor de Produção.",
      tipo: "extraordinaria",
      instrumento: "sipro",
      status: "ativa",
      data_inicio: "2026-03-01",
      data_fim: "2026-03-31",
      anonimo: true,
      permite_identificacao_voluntaria: false,
      total_respostas: 3,
      motivo_extraordinaria: "Reestruturação do setor de Produção com fusão de equipes",
      escopo: "departamento",
      escopo_valores: ["Produção"],
      ips_score: 48,
      ips_classificacao: "atencao",
      radar_data: [
        { subject: "Demandas Quantitativas", value: 42, fullMark: 100 },
        { subject: "Demandas Cognitivas", value: 50, fullMark: 100 },
        { subject: "Demandas Emocionais", value: 38, fullMark: 100 },
        { subject: "Autonomia", value: 55, fullMark: 100 },
        { subject: "Clareza de Papel", value: 35, fullMark: 100 },
        { subject: "Reconhecimento", value: 40, fullMark: 100 },
        { subject: "Relacionamentos", value: 60, fullMark: 100 },
        { subject: "Recuperação", value: 52, fullMark: 100 },
        { subject: "Sentido do Trabalho", value: 65, fullMark: 100 },
        { subject: "Sinais Precoces", value: 55, fullMark: 100 },
      ],
      criado_por: userId,
      criado_por_nome: "Usuário Demonstração",
    }).select().single();

    // Convites for campaign 1 (concluded)
    if (campanha1) {
      const convitesData = employees.filter(e => e.status === "concluido").map((emp, i) => ({
        tenant_id: tenantId,
        campanha_id: campanha1.id,
        colaborador_nome: emp.nome_completo,
        colaborador_cpf: emp.cpf,
        colaborador_cargo: emp.cargo,
        colaborador_departamento: emp.departamento,
        token: `demo-token-${i + 1}-${Date.now()}`,
        status: i < 11 ? "concluido" : "pendente",
        concluido_em: i < 11 ? "2026-02-10T14:30:00Z" : null,
        enviado_em: "2026-01-15T08:00:00Z",
      }));
      await admin.from("questionario_psicossocial_convites").insert(convitesData);

      // Anonymous responses (11 responses)
      const respostas: any[] = [];
      const departamentos = ["Recursos Humanos", "SST", "Financeiro", "Produção", "Saúde Ocupacional", "Administração", "Contabilidade", "Departamento Pessoal"];
      
      for (let i = 0; i < 11; i++) {
        const ipsBase = 55 + Math.floor(Math.random() * 25);
        respostas.push({
          tenant_id: tenantId,
          campanha_id: campanha1.id,
          identificacao_voluntaria: false,
          concluido_em: `2026-02-${String(Math.floor(Math.random() * 10) + 5).padStart(2, "0")}T${String(Math.floor(Math.random() * 8) + 8).padStart(2, "0")}:${String(Math.floor(Math.random() * 60)).padStart(2, "0")}:00Z`,
          tempo_resposta_segundos: 300 + Math.floor(Math.random() * 600),
          respostas: generateSiproRespostas(),
          indicadores: {
            IPS: ipsBase,
            IRP_S: 50 + Math.floor(Math.random() * 30),
            IBO_S: 40 + Math.floor(Math.random() * 35),
            IBD_S: 60 + Math.floor(Math.random() * 25),
            IREC_S: 35 + Math.floor(Math.random() * 30),
            ICOP_S: 70 + Math.floor(Math.random() * 20),
            INOT_S: null,
            radar: radarData.map(r => ({
              ...r,
              value: Math.max(10, r.value + Math.floor(Math.random() * 20) - 10),
            })),
          },
        });
      }
      await admin.from("questionario_psicossocial_respostas").insert(respostas);
    }

    // ═══════════════════════════════════════════════════════════════
    // 7. ATESTADOS - some medical certificates
    // ═══════════════════════════════════════════════════════════════
    await admin.from("atestados").delete().eq("tenant_id", tenantId);
    
    const atestados = [
      { colaborador_nome: "Fernando Almeida Neto", colaborador_cpf: "111.222.333-06", data_emissao: "2026-02-10", tipo: "assistencial", dias_afastamento: 3, profissional_nome: "Dr. Ricardo Lopes", profissional_registro: "CRM-SP 123456", grupo_clinico: "osteomuscular", cid_codigo: "M54.5" },
      { colaborador_nome: "Isabela Martins", colaborador_cpf: "111.222.333-09", data_emissao: "2026-03-01", tipo: "assistencial", dias_afastamento: 1, profissional_nome: "Dra. Amanda Reis", profissional_registro: "CRM-SP 654321", grupo_clinico: "respiratorio", cid_codigo: "J06.9" },
      { colaborador_nome: "Ana Clara Souza", colaborador_cpf: "111.222.333-01", data_emissao: "2026-01-20", tipo: "ocupacional", subtipo_ocupacional: "admissional", profissional_nome: "Dra. Gabriela Torres Silva", profissional_registro: "CRM-SP 789012", aptidao: "apto" },
      { colaborador_nome: "Bruno Oliveira Santos", colaborador_cpf: "111.222.333-02", data_emissao: "2026-02-15", tipo: "ocupacional", subtipo_ocupacional: "periodico", profissional_nome: "Dra. Gabriela Torres Silva", profissional_registro: "CRM-SP 789012", aptidao: "apto" },
      { colaborador_nome: "Henrique Barbosa", colaborador_cpf: "111.222.333-08", data_emissao: "2026-03-05", tipo: "assistencial", dias_afastamento: 5, profissional_nome: "Dr. Paulo Mendes", profissional_registro: "CRM-SP 112233", grupo_clinico: "mental", cid_codigo: "F41.1" },
    ];

    await admin.from("atestados").insert(atestados.map(a => ({
      ...a,
      tenant_id: tenantId,
      empresa_id: empresaId,
      data_inicio_afastamento: a.dias_afastamento ? a.data_emissao : null,
      contem_cid: !!a.cid_codigo,
    })));

    // ═══════════════════════════════════════════════════════════════
    // 8. OCORRÊNCIAS
    // ═══════════════════════════════════════════════════════════════
    await admin.from("ocorrencias").delete().eq("tenant_id", tenantId);
    
    const ocorrencias = [
      { colaborador_nome: "Fernando Almeida Neto", colaborador_cpf: "111.222.333-06", tipo: "advertencia_verbal", data_ocorrencia: "2026-01-15", descricao: "Atraso reincidente sem justificativa", gravidade: "leve", status: "registrada", departamento: "Produção" },
      { colaborador_nome: "Henrique Barbosa", colaborador_cpf: "111.222.333-08", tipo: "advertencia_escrita", data_ocorrencia: "2026-02-20", descricao: "Não utilização de EPI obrigatório na área de produção", gravidade: "media", status: "formalizada", departamento: "Produção" },
      { colaborador_nome: "Karen Duarte", colaborador_cpf: "111.222.333-11", tipo: "elogio", data_ocorrencia: "2026-03-01", descricao: "Excelente atendimento ao visitante institucional", gravidade: "positiva", status: "registrada", departamento: "Administração" },
    ];

    await admin.from("ocorrencias").insert(ocorrencias.map(o => ({ ...o, tenant_id: tenantId, empresa_id: empresaId, registrado_por: userId, registrado_por_nome: "Usuário Demonstração" })));

    // ═══════════════════════════════════════════════════════════════
    // 9. PONTO - recent time clock entries
    // ═══════════════════════════════════════════════════════════════
    await admin.from("ponto_diario").delete().eq("tenant_id", tenantId);
    await admin.from("ponto_marcacoes").delete().eq("tenant_id", tenantId);

    // ═══════════════════════════════════════════════════════════════
    // 10. BEM-ESTAR respostas
    // ═══════════════════════════════════════════════════════════════
    await admin.from("bem_estar_respostas").delete().eq("tenant_id", tenantId);
    
    const eixos = ["emocional", "fisico", "social", "proposito", "financeiro"];
    const bemEstarRespostas: any[] = [];
    for (let day = 0; day < 30; day++) {
      const d = new Date();
      d.setDate(d.getDate() - day);
      const dateStr = d.toISOString();
      for (const eixo of eixos.slice(0, Math.floor(Math.random() * 3) + 2)) {
        bemEstarRespostas.push({
          tenant_id: tenantId,
          user_id: userId,
          eixo,
          tipo: "pulso",
          valor_numerico: Math.floor(Math.random() * 3) + 3,
          created_at: dateStr,
        });
      }
    }
    await admin.from("bem_estar_respostas").insert(bemEstarRespostas);

    // ═══════════════════════════════════════════════════════════════
    // 11. PDIs
    // ═══════════════════════════════════════════════════════════════
    await admin.from("pdi_metas").delete().eq("tenant_id", tenantId);
    await admin.from("pdis").delete().eq("tenant_id", tenantId);

    const { data: pdi1 } = await admin.from("pdis").insert({
      tenant_id: tenantId,
      colaborador_id: "111.222.333-01",
      colaborador_nome: "Ana Clara Souza",
      titulo: "PDI — Desenvolvimento Liderança",
      descricao: "Desenvolvimento de competências de liderança para promoção a Coordenadora de RH",
      periodo: "semestral",
      data_inicio: "2026-01-01",
      data_fim: "2026-06-30",
      status: "ativo",
      progresso: 45,
      criado_por_nome: "Usuário Demonstração",
    }).select().single();

    if (pdi1) {
      await admin.from("pdi_metas").insert([
        { tenant_id: tenantId, pdi_id: pdi1.id, titulo: "Curso de Liderança", descricao: "Concluir curso de gestão de equipes", categoria: "competencia", status: "em_andamento", progresso: 70, peso: 2, data_inicio: "2026-01-01", data_fim: "2026-03-31" },
        { tenant_id: tenantId, pdi_id: pdi1.id, titulo: "Mentoria com Gestora", descricao: "Sessões quinzenais de mentoria com Patrícia Vieira", categoria: "comportamento", status: "em_andamento", progresso: 50, peso: 1, data_inicio: "2026-01-01", data_fim: "2026-06-30" },
        { tenant_id: tenantId, pdi_id: pdi1.id, titulo: "Projeto de Engajamento", descricao: "Liderar projeto de engajamento no setor de RH", categoria: "resultado", status: "nao_iniciada", progresso: 0, peso: 2, data_inicio: "2026-04-01", data_fim: "2026-06-30" },
      ]);
    }

    // ═══════════════════════════════════════════════════════════════
    // 12. AVALIAÇÃO DE DESEMPENHO
    // ═══════════════════════════════════════════════════════════════
    await admin.from("avaliacao_respostas").delete().eq("tenant_id", tenantId);
    await admin.from("avaliacao_ciclos").delete().eq("tenant_id", tenantId);
    // Templates might be shared, skip deletion

    // ═══════════════════════════════════════════════════════════════
    // 13. 9BOX
    // ═══════════════════════════════════════════════════════════════
    await admin.from("avaliacao_9box").delete().eq("tenant_id", tenantId);
    
    const nineBox = [
      { colaborador_id: "111.222.333-01", colaborador_nome: "Ana Clara Souza", desempenho: 4, potencial: 4, quadrante: "Estrela" },
      { colaborador_id: "111.222.333-02", colaborador_nome: "Bruno Oliveira Santos", desempenho: 5, potencial: 3, quadrante: "Alto Desempenho" },
      { colaborador_id: "111.222.333-03", colaborador_nome: "Carla Mendes Ferreira", desempenho: 4, potencial: 5, quadrante: "Futuro Líder" },
      { colaborador_id: "111.222.333-05", colaborador_nome: "Elena Rodrigues Costa", desempenho: 3, potencial: 3, quadrante: "Mantenedor" },
      { colaborador_id: "111.222.333-06", colaborador_nome: "Fernando Almeida Neto", desempenho: 2, potencial: 2, quadrante: "Questionável" },
      { colaborador_id: "111.222.333-07", colaborador_nome: "Gabriela Torres Silva", desempenho: 5, potencial: 5, quadrante: "Estrela" },
      { colaborador_id: "111.222.333-08", colaborador_nome: "Henrique Barbosa", desempenho: 3, potencial: 4, quadrante: "Enigma" },
      { colaborador_id: "111.222.333-15", colaborador_nome: "Patrícia Vieira", desempenho: 5, potencial: 4, quadrante: "Alto Desempenho" },
    ];

    await admin.from("avaliacao_9box").insert(nineBox.map(n => ({
      ...n, tenant_id: tenantId, data_avaliacao: "2026-02-01",
      avaliador_id: userId, avaliador_nome: "Usuário Demonstração",
    })));

    // ═══════════════════════════════════════════════════════════════
    // 14. AFASTAMENTOS
    // ═══════════════════════════════════════════════════════════════
    await admin.from("afastamentos").delete().eq("tenant_id", tenantId);

    await admin.from("afastamentos").insert([
      { tenant_id: tenantId, empresa_id: empresaId, colaborador_nome: "Fernando Almeida Neto", colaborador_cpf: "111.222.333-06", data_inicio: "2026-02-10", data_fim: "2026-02-12", status: "encerrado", motivo_principal: "osteomuscular", dias_totais: 3 },
      { tenant_id: tenantId, empresa_id: empresaId, colaborador_nome: "Henrique Barbosa", colaborador_cpf: "111.222.333-08", data_inicio: "2026-03-05", data_fim: null, status: "em_andamento", motivo_principal: "mental", dias_totais: 8 },
    ]);

    // ═══════════════════════════════════════════════════════════════
    // 15. ALERTAS DE SAÚDE
    // ═══════════════════════════════════════════════════════════════
    await admin.from("alertas_saude").delete().eq("tenant_id", tenantId);

    await admin.from("alertas_saude").insert([
      { tenant_id: tenantId, colaborador_nome: "Henrique Barbosa", tipo: "afastamento_prolongado", titulo: "Afastamento > 7 dias — Henrique Barbosa", descricao: "Colaborador afastado por transtorno de ansiedade há 8 dias. Avaliar necessidade de encaminhamento ao INSS.", prioridade: "alta", referencia_id: "mock", referencia_tipo: "afastamento" },
      { tenant_id: tenantId, colaborador_nome: "Fernando Almeida Neto", tipo: "recidiva", titulo: "Recidiva osteomuscular — Fernando Almeida", descricao: "Segundo atestado por problema osteomuscular em 90 dias. Considerar avaliação ergonômica do posto.", prioridade: "media", referencia_id: "mock", referencia_tipo: "atestado" },
    ]);

    return new Response(JSON.stringify({
      success: true,
      message: "Usuário de teste criado com sucesso!",
      data: {
        userId,
        tenantId,
        empresaId,
        email: TEST_EMAIL,
        modulosSemeados: [
          "Auth + Profile + Tenant",
          "Empresa",
          "Admissões (15 colaboradores)",
          "Hub Contábil (6 competências + documentos + guias + certidões)",
          "Psicossocial (2 campanhas + 11 respostas anônimas)",
          "Atestados (5)",
          "Ocorrências (3)",
          "Bem-Estar (30 dias)",
          "PDIs (1 com 3 metas)",
          "9Box (8 avaliações)",
          "Afastamentos (2)",
          "Alertas de Saúde (2)",
        ],
      },
    }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (error) {
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// Helper: generate realistic SIPRO responses (10 eixos × 5 perguntas)
function generateSiproRespostas() {
  const eixos = [
    "demandas_quantitativas", "demandas_cognitivas", "demandas_emocionais",
    "autonomia", "clareza_papel", "reconhecimento",
    "relacionamentos", "recuperacao", "sentido_trabalho", "sinais_precoces"
  ];
  const respostas: Record<string, number[]> = {};
  for (const eixo of eixos) {
    respostas[eixo] = Array.from({ length: 5 }, () => Math.floor(Math.random() * 5));
  }
  return respostas;
}
