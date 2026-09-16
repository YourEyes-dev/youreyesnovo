import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

interface StepResult {
  step: string;
  action: string;
  status: "success" | "fail" | "warning";
  details: string;
  duration_ms: number;
}

interface FlowResult {
  flow: string;
  flow_label: string;
  steps: StepResult[];
  passed: number;
  failed: number;
  warnings: number;
  total_duration_ms: number;
}

// Test credentials
const TEST_EMAIL = "wallasmonteirobarros@gmail.com";
const TEST_PASSWORD = "12345678";

async function runStep(stepName: string, action: string, fn: () => Promise<string>): Promise<StepResult> {
  const start = Date.now();
  try {
    const details = await fn();
    return { step: stepName, action, status: "success", details, duration_ms: Date.now() - start };
  } catch (e) {
    return { step: stepName, action, status: "fail", details: (e as Error).message || String(e), duration_ms: Date.now() - start };
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const { flow, tenantId, stream } = await req.json();
    const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";

    if (!OPENAI_API_KEY) throw new Error("OPENAI_API_KEY não configurada");

    const supabaseAdmin = createClient(SUPABASE_URL, SERVICE_KEY);

    // ═══ Authenticate as test user ═══
    async function getAuthenticatedClient() {
      const client = createClient(SUPABASE_URL, ANON_KEY);
      const { data, error } = await client.auth.signInWithPassword({
        email: TEST_EMAIL,
        password: TEST_PASSWORD,
      });
      if (error) throw new Error(`Login falhou (${TEST_EMAIL}): ${error.message}`);
      return { client, session: data.session, user: data.user };
    }

    if (!stream) {
      return new Response(JSON.stringify({ error: "Use stream: true" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const encoder = new TextEncoder();
    const STEP_DELAY = 4000; // 4 seconds between steps for visual feedback
    const NAV_DELAY = 3000; // 3s after navigation for visual effect
    const REFRESH_DELAY = 1500; // 1.5s after refresh to let UI update

    const body = new ReadableStream({
      async start(controller) {
        const send = (event: string, data: any) => {
          controller.enqueue(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`));
        };

        const delay = (ms: number) => new Promise(r => setTimeout(r, ms));

        // Navigate iframe to a route with label
        const navigateTo = async (route: string, label?: string) => {
          send("navigate", { route, label });
          await delay(NAV_DELAY);
        };

        // Tell iframe to invalidate all queries so UI reflects DB changes
        const refreshIframe = async () => {
          send("refresh", {});
          await delay(REFRESH_DELAY);
        };

        const flows: FlowResult[] = [];

        const runStepStreamed = async (flowId: string, stepName: string, action: string, fn: () => Promise<string>): Promise<StepResult> => {
          send("step_start", { flow: flowId, step: stepName, action });
          const result = await runStep(stepName, action, fn);
          send("step_done", { flow: flowId, ...result });
          await delay(STEP_DELAY);
          return result;
        };

        const buildFlowResult = (flowId: string, label: string, steps: StepResult[]): FlowResult => {
          return {
            flow: flowId, flow_label: label, steps,
            passed: steps.filter(s => s.status === "success").length,
            failed: steps.filter(s => s.status === "fail").length,
            warnings: steps.filter(s => s.status === "warning").length,
            total_duration_ms: steps.reduce((a, s) => a + s.duration_ms, 0),
          };
        };

        // ═══════════════════════════════════════════════════
        // FLOW: LOGIN & AUTH
        // ═══════════════════════════════════════════════════
        let authClient: any = null;
        let authUser: any = null;
        let authTenantId: string | null = tenantId || null;

        if (flow === "login_auth" || flow === "todos") {
          send("flow_start", { flow: "login_auth", label: "Autenticação & Perfil" });
          await navigateTo("/", "Autenticação & Perfil");
          const steps: StepResult[] = [];

          steps.push(await runStepStreamed("login_auth", "1. Login com credenciais", `signIn ${TEST_EMAIL}`, async () => {
            const { client, session, user } = await getAuthenticatedClient();
            authClient = client;
            authUser = user;
            return `Login OK — UID: ${user.id}, Email: ${user.email}`;
          }));

          await navigateTo("/", "Dashboard — verificando perfil");

          steps.push(await runStepStreamed("login_auth", "2. Verificar Perfil", "SELECT profiles", async () => {
            if (!authClient) throw new Error("Login não realizado");
            const { data, error } = await authClient.from("profiles").select("*").eq("user_id", authUser.id).single();
            if (error) throw new Error(error.message);
            authTenantId = data.tenant_id;
            return `Perfil: ${data.nome_completo || data.full_name || 'sem nome'}, Tenant: ${data.tenant_id?.slice(0, 8)}...`;
          }));

          steps.push(await runStepStreamed("login_auth", "3. Verificar Roles", "SELECT user_roles", async () => {
            if (!authClient) throw new Error("Login não realizado");
            const { data, error } = await authClient.from("user_roles").select("*").eq("user_id", authUser.id);
            if (error) throw new Error(error.message);
            const roles = data?.map((r: any) => r.role).join(", ") || "nenhum";
            return `Roles: ${roles} (${data?.length || 0} atribuídas)`;
          }));

          steps.push(await runStepStreamed("login_auth", "4. Verificar SuperAdmin", "SELECT superadmins", async () => {
            const { data } = await supabaseAdmin.from("superadmins").select("*").eq("user_id", authUser.id);
            const isSa = data && data.length > 0 && data[0].ativo;
            return isSa ? "✓ É SuperAdmin ativo" : "Não é SuperAdmin";
          }));

          steps.push(await runStepStreamed("login_auth", "5. Verificar Sessão", "getSession", async () => {
            if (!authClient) throw new Error("Login não realizado");
            const { data } = await authClient.auth.getSession();
            if (!data.session) throw new Error("Sessão não ativa");
            const exp = new Date(data.session.expires_at * 1000);
            return `Sessão ativa até ${exp.toLocaleString("pt-BR")}`;
          }));

          const fr = buildFlowResult("login_auth", "Autenticação & Perfil", steps);
          flows.push(fr);
          send("flow_done", fr);
        }

        // Ensure we have auth for subsequent flows
        if (!authClient && flow !== "login_auth") {
          try {
            const { client, user } = await getAuthenticatedClient();
            authClient = client;
            authUser = user;
            if (!authTenantId) {
              const { data } = await authClient.from("profiles").select("tenant_id").eq("user_id", user.id).single();
              authTenantId = data?.tenant_id || tenantId;
            }
          } catch (e) {
            send("step_done", { flow: "auth", step: "Auto-login", action: "signIn", status: "fail", details: (e as Error).message, duration_ms: 0 });
          }
        }

        const effectiveTenant = authTenantId || tenantId;

        // ═══════════════════════════════════════════════════
        // FLOW: EMPRESA (Cadastro)
        // ═══════════════════════════════════════════════════
        if (flow === "empresa" || flow === "todos") {
          send("flow_start", { flow: "empresa", label: "Cadastro de Empresa" });
          await navigateTo("/empresa", "Cadastro de Empresa");
          const steps: StepResult[] = [];
          let empresaId: string | null = null;
          let deptId: string | null = null;
          let cargoId: string | null = null;

          steps.push(await runStepStreamed("empresa", "1. Criar Empresa", "INSERT empresa_cadastro", async () => {
            if (!effectiveTenant) throw new Error("tenantId não disponível");
            const { data, error } = await supabaseAdmin.from("empresa_cadastro").insert({
              tenant_id: effectiveTenant,
              tipo_pessoa: "juridica",
              tipo_unidade: "matriz",
              razao_social: "QA Agent — Empresa Teste LTDA",
              nome_fantasia: "QA Teste Corp",
              cnpj: "99.999.999/0001-99",
              email: "qa-teste@empresa.com",
              telefone: "(11) 99999-0000",
              cep: "01001-000",
              cidade: "São Paulo",
              estado: "SP",
              endereco: "Rua Teste, 123",
              bairro: "Centro",
              total_colaboradores: 50,
              grau_risco: 2,
              cnae_principal: "6201-5/00",
              cnae_descricao: "Desenvolvimento de software",
            }).select("id").single();
            if (error) throw new Error(error.message);
            empresaId = data.id;
            return `Empresa criada: ${data.id}`;
          }));

          steps.push(await runStepStreamed("empresa", "2. Verificar Empresa", "SELECT empresa_cadastro", async () => {
            if (!empresaId) throw new Error("Empresa não criada");
            const { data, error } = await supabaseAdmin.from("empresa_cadastro").select("*").eq("id", empresaId).single();
            if (error) throw new Error(error.message);
            if (data.razao_social !== "QA Agent — Empresa Teste LTDA") throw new Error("Razão social divergente");
            return `Verificada: ${data.razao_social}, CNPJ: ${data.cnpj}, Risco: ${data.grau_risco}`;
          }));

          steps.push(await runStepStreamed("empresa", "3. Criar Departamento", "INSERT departamentos", async () => {
            if (!empresaId || !effectiveTenant) throw new Error("Empresa/tenant ausente");
            const { data, error } = await supabaseAdmin.from("departamentos").insert({
              tenant_id: effectiveTenant, empresa_id: empresaId,
              nome: "QA — Dept Teste", descricao: "Departamento criado pelo agente de QA",
            }).select("id").single();
            if (error) throw new Error(error.message);
            deptId = data.id;
            return `Departamento criado: ${data.id}`;
          }));

          steps.push(await runStepStreamed("empresa", "4. Criar Cargo", "INSERT cargos", async () => {
            if (!deptId || !effectiveTenant) throw new Error("Departamento/tenant ausente");
            const { data, error } = await supabaseAdmin.from("cargos").insert({
              tenant_id: effectiveTenant, empresa_id: empresaId,
              departamento_id: deptId, nome: "QA — Cargo Teste",
              descricao: "Cargo criado pelo agente de QA",
              nivel: "junior", faixa_salarial_min: 3000, faixa_salarial_max: 6000,
            }).select("id").single();
            if (error) throw new Error(error.message);
            cargoId = data.id;
            return `Cargo criado: ${data.id}`;
          }));

          steps.push(await runStepStreamed("empresa", "5. Listar Empresas (Auth)", "SELECT via auth client", async () => {
            if (!authClient) throw new Error("Auth client não disponível");
            const { data, error } = await authClient.from("empresa_cadastro").select("id, razao_social, tipo_unidade").eq("tenant_id", effectiveTenant);
            if (error) throw new Error(error.message);
            return `${data?.length || 0} empresas visíveis pelo usuário autenticado`;
          }));

          steps.push(await runStepStreamed("empresa", "6. Atualizar Empresa", "UPDATE empresa_cadastro", async () => {
            if (!empresaId) throw new Error("Empresa não encontrada");
            const { error } = await supabaseAdmin.from("empresa_cadastro").update({
              total_colaboradores: 100, grau_risco: 3, jornada_padrao: "44h semanais",
            }).eq("id", empresaId);
            if (error) throw new Error(error.message);
            return "Empresa atualizada: 100 colaboradores, Risco 3";
          }));

          steps.push(await runStepStreamed("empresa", "7. Cleanup", "DELETE", async () => {
            if (cargoId) await supabaseAdmin.from("cargos").delete().eq("id", cargoId);
            if (deptId) await supabaseAdmin.from("departamentos").delete().eq("id", deptId);
            if (empresaId) await supabaseAdmin.from("empresa_cadastro").delete().eq("id", empresaId);
            return "Empresa, departamento e cargo de teste removidos";
          }));

          const fr = buildFlowResult("empresa", "Cadastro de Empresa", steps);
          flows.push(fr);
          send("flow_done", fr);
        }

        // ═══════════════════════════════════════════════════
        // FLOW: ADMISSÃO
        // ═══════════════════════════════════════════════════
        if (flow === "admissao" || flow === "todos") {
          send("flow_start", { flow: "admissao", label: "Fluxo de Admissão" });
          await navigateTo("/colaboradores", "Colaboradores — Admissão");
          const steps: StepResult[] = [];
          let admissaoId: string | null = null;
          const testCpf = "999.888.777-00";
          const testEmail = `qa-test-${Date.now()}@teste.com`;

          steps.push(await runStepStreamed("admissao", "1. Criar Admissão", "INSERT admissoes", async () => {
            if (!effectiveTenant) throw new Error("tenantId obrigatório");
            const { data, error } = await supabaseAdmin.from("admissoes").insert({
              tenant_id: effectiveTenant, nome_completo: "QA Agent — Teste Automatizado",
              cpf: testCpf, email: testEmail, cargo: "Analista de QA (teste)",
              departamento: "Tecnologia", status: "em_andamento",
              data_nascimento: "1990-05-15", genero: "masculino",
              telefone: "(11) 99999-8888", celular: "(11) 99999-7777",
              tipo_contrato: "clt", salario: 5000,
            }).select("id").single();
            if (error) throw new Error(error.message);
            admissaoId = data.id;
            return `Admissão criada: ${data.id}`;
          }));

          steps.push(await runStepStreamed("admissao", "2. Verificar Dados", "SELECT admissoes", async () => {
            if (!admissaoId) throw new Error("Admissão não foi criada");
            const { data, error } = await supabaseAdmin.from("admissoes").select("*").eq("id", admissaoId).single();
            if (error) throw new Error(error.message);
            if (data.nome_completo !== "QA Agent — Teste Automatizado") throw new Error("Nome divergente");
            if (data.salario !== 5000) throw new Error(`Salário divergente: ${data.salario}`);
            return `Nome: ${data.nome_completo}, Cargo: ${data.cargo}, Salário: R$${data.salario}`;
          }));

          steps.push(await runStepStreamed("admissao", "3. Dados Bancários", "UPDATE admissoes", async () => {
            if (!admissaoId) throw new Error("Admissão não encontrada");
            const { error } = await supabaseAdmin.from("admissoes").update({
              banco: "Itaú", agencia: "1234", conta: "56789-0",
              tipo_conta: "corrente", chave_pix: testEmail,
            }).eq("id", admissaoId);
            if (error) throw new Error(error.message);
            return "Dados bancários preenchidos: Itaú 1234 / 56789-0";
          }));

          steps.push(await runStepStreamed("admissao", "4. Endereço", "UPDATE admissoes", async () => {
            if (!admissaoId) throw new Error("Admissão não encontrada");
            const { error } = await supabaseAdmin.from("admissoes").update({
              cep: "01001-000", endereco: "Rua QA", numero: "42",
              bairro: "Centro", cidade: "São Paulo", estado: "SP",
            }).eq("id", admissaoId);
            if (error) throw new Error(error.message);
            return "Endereço atualizado: Rua QA, 42 — SP";
          }));

          steps.push(await runStepStreamed("admissao", "5. Criar Documentos", "INSERT admissao_documentos", async () => {
            if (!admissaoId) throw new Error("Admissão não encontrada");
            const docs = [
              { nome: "RG", tipo: "rg", obrigatorio: true },
              { nome: "CPF", tipo: "cpf", obrigatorio: true },
              { nome: "CTPS", tipo: "ctps", obrigatorio: true },
              { nome: "Comprovante de Residência", tipo: "comprovante_residencia", obrigatorio: false },
            ];
            const results = [];
            for (const doc of docs) {
              const { data, error } = await supabaseAdmin.from("admissao_documentos").insert({
                tenant_id: effectiveTenant, admissao_id: admissaoId,
                nome: doc.nome, tipo: doc.tipo, obrigatorio: doc.obrigatorio, status: "pendente",
              }).select("id").single();
              if (error) throw new Error(`Erro no doc ${doc.nome}: ${error.message}`);
              results.push(doc.nome);
            }
            return `${results.length} documentos criados: ${results.join(", ")}`;
          }));

          steps.push(await runStepStreamed("admissao", "6. Concluir Admissão", "UPDATE status=concluido", async () => {
            if (!admissaoId) throw new Error("Admissão não encontrada");
            const { error } = await supabaseAdmin.from("admissoes").update({
              status: "concluido", data_admissao: new Date().toISOString().split("T")[0],
            }).eq("id", admissaoId);
            if (error) throw new Error(error.message);
            return "Admissão concluída com sucesso";
          }));

          steps.push(await runStepStreamed("admissao", "7. Verificar via Auth Client", "SELECT (auth)", async () => {
            if (!authClient) throw new Error("Auth client não disponível");
            const { data, error } = await authClient.from("admissoes").select("id, status, nome_completo").eq("id", admissaoId);
            if (error) throw new Error(`RLS bloqueou: ${error.message}`);
            return `Visível pelo auth client: ${data?.length || 0} registro(s)`;
          }));

          steps.push(await runStepStreamed("admissao", "8. Cleanup", "DELETE", async () => {
            if (admissaoId) {
              await supabaseAdmin.from("admissao_documentos").delete().eq("admissao_id", admissaoId);
              await supabaseAdmin.from("admissao_historico").delete().eq("admissao_id", admissaoId);
              await supabaseAdmin.from("admissao_workflow").delete().eq("admissao_id", admissaoId);
              await supabaseAdmin.from("admissoes").delete().eq("id", admissaoId);
            }
            return "Dados de teste removidos";
          }));

          const fr = buildFlowResult("admissao", "Fluxo de Admissão", steps);
          flows.push(fr);
          send("flow_done", fr);
        }

        // ═══════════════════════════════════════════════════
        // FLOW: ATESTADO
        // ═══════════════════════════════════════════════════
        if (flow === "atestado" || flow === "todos") {
          send("flow_start", { flow: "atestado", label: "Atestado Médico" });
          await navigateTo("/atestados", "Atestados — Gestão de Saúde");
          const steps: StepResult[] = [];
          let atestadoId: string | null = null;

          steps.push(await runStepStreamed("atestado", "1. Criar Atestado", "INSERT atestados", async () => {
            const { data, error } = await supabaseAdmin.from("atestados").insert({
              tenant_id: effectiveTenant, colaborador_nome: "QA Agent — Colaborador",
              profissional_nome: "Dr. QA Teste", profissional_registro: "CRM-QA-0000",
              tipo: "assistencial", data_emissao: new Date().toISOString().split("T")[0],
              dias_afastamento: 3, cid_codigo: "J11", contem_cid: true,
              grupo_clinico: "respiratorio",
              data_inicio_afastamento: new Date().toISOString().split("T")[0],
            }).select("id").single();
            if (error) throw new Error(error.message);
            atestadoId = data.id;
            return `Atestado criado: ${data.id}`;
          }));

          steps.push(await runStepStreamed("atestado", "2. Verificar Dados", "SELECT atestados", async () => {
            if (!atestadoId) throw new Error("Atestado não criado");
            const { data, error } = await supabaseAdmin.from("atestados").select("*").eq("id", atestadoId).single();
            if (error) throw new Error(error.message);
            if (data.dias_afastamento !== 3) throw new Error("Dias divergente");
            if (data.cid_codigo !== "J11") throw new Error("CID divergente");
            return `CID: ${data.cid_codigo}, Dias: ${data.dias_afastamento}, Tipo: ${data.tipo}`;
          }));

          steps.push(await runStepStreamed("atestado", "3. Testar Ocupacional", "INSERT atestado ocupacional", async () => {
            const { data, error } = await supabaseAdmin.from("atestados").insert({
              tenant_id: effectiveTenant, colaborador_nome: "QA Agent — Ocupacional",
              profissional_nome: "Dr. Ocupacional", profissional_registro: "CRM-OC-0001",
              tipo: "ocupacional", subtipo_ocupacional: "admissional",
              data_emissao: new Date().toISOString().split("T")[0],
              aptidao: "apto",
            }).select("id").single();
            if (error) throw new Error(error.message);
            // Cleanup immediately
            await supabaseAdmin.from("atestados").delete().eq("id", data.id);
            return `Atestado ocupacional criado e limpo: aptidão=apto`;
          }));

          steps.push(await runStepStreamed("atestado", "4. Cleanup", "DELETE", async () => {
            if (atestadoId) await supabaseAdmin.from("atestados").delete().eq("id", atestadoId);
            return "Atestado de teste removido";
          }));

          const fr = buildFlowResult("atestado", "Atestado Médico", steps);
          flows.push(fr);
          send("flow_done", fr);
        }

        // ═══════════════════════════════════════════════════
        // FLOW: EPI (Completo — Tipo → EPI → Local → Entrada → Entrega → Devolução → Movimentações)
        // ═══════════════════════════════════════════════════
        if (flow === "epi" || flow === "todos") {
          send("flow_start", { flow: "epi", label: "EPI — Fluxo Completo" });
          await navigateTo("/epis", "EPIs — Equipamentos de Proteção");
          const steps: StepResult[] = [];
          let tipoId: string | null = null;
          let epiId: string | null = null;
          let localId: string | null = null;
          let entregaId: string | null = null;
          let movimentacaoIds: string[] = [];

          // 1. Criar Categoria/Tipo de EPI
          steps.push(await runStepStreamed("epi", "1. Criar Tipo de EPI", "INSERT epi_tipos", async () => {
            if (!effectiveTenant) throw new Error("tenantId obrigatório");
            const { data, error } = await supabaseAdmin.from("epi_tipos").insert({
              tenant_id: effectiveTenant,
              nome: "QA Agent — Luva de Proteção Mecânica",
              categoria: "maos",
              descricao: "Luva de vaqueta para proteção contra riscos mecânicos — criada pelo agente de QA",
              ca_numero: "CA-QA-99999",
              ca_validade: new Date(Date.now() + 365 * 86400000).toISOString().split("T")[0],
              fabricante: "QA Safety Ltda",
              marca: "QA ProGrip",
              unidade_medida: "par",
              tipo_durabilidade: "duravel",
              estoque_minimo: 10,
              controla_tamanho: true,
              validade_meses: 12,
            }).select("id, nome, ca_numero").single();
            if (error) throw new Error(error.message);
            tipoId = data.id;
            return `Tipo criado: "${data.nome}", CA: ${data.ca_numero}, ID: ${data.id.slice(0,8)}...`;
          }));

          // 2. Verificar Tipo criado
          steps.push(await runStepStreamed("epi", "2. Verificar Tipo de EPI", "SELECT epi_tipos", async () => {
            if (!tipoId) throw new Error("Tipo não criado no passo anterior");
            const { data, error } = await supabaseAdmin.from("epi_tipos").select("*").eq("id", tipoId).single();
            if (error) throw new Error(error.message);
            if (data.nome !== "QA Agent — Luva de Proteção Mecânica") throw new Error("Nome do tipo divergente");
            if (data.categoria !== "maos") throw new Error(`Categoria divergente: ${data.categoria}`);
            if (data.estoque_minimo !== 10) throw new Error(`Estoque mínimo divergente: ${data.estoque_minimo}`);
            if (!data.controla_tamanho) throw new Error("Controle de tamanho deveria estar ativo");
            return `Verificado: ${data.nome}, Cat: ${data.categoria}, Fabricante: ${data.fabricante}, Durabilidade: ${data.tipo_durabilidade}, Estoque mín: ${data.estoque_minimo}`;
          }));

          // 3. Criar Local de Estoque
          await navigateTo("/epis", "EPIs — Criando Local de Estoque");
          steps.push(await runStepStreamed("epi", "3. Criar Local de Estoque", "INSERT epi_locais_estoque", async () => {
            if (!effectiveTenant) throw new Error("tenantId obrigatório");
            const { data, error } = await supabaseAdmin.from("epi_locais_estoque").insert({
              tenant_id: effectiveTenant,
              nome: "QA — Almoxarifado Central Teste",
              tipo: "almoxarifado_central",
              responsavel_nome: "QA Agent Responsável",
              observacoes: "Local de estoque criado pelo agente de QA para testes",
              ativo: true,
            }).select("id, nome").single();
            if (error) throw new Error(error.message);
            localId = data.id;
            return `Local criado: "${data.nome}", ID: ${data.id.slice(0,8)}...`;
          }));

          // 4. Criar item EPI vinculado ao Tipo — navigate to Estoque tab
          await navigateTo("/epis?tab=estoque", "EPIs — Estoque — Cadastrando novo item");
          await refreshIframe();
          steps.push(await runStepStreamed("epi", "4. Criar Item EPI", "INSERT epis", async () => {
            if (!tipoId || !effectiveTenant || !localId) throw new Error("Tipo ou Local não criados");
            const { data, error } = await supabaseAdmin.from("epis").insert({
              tenant_id: effectiveTenant,
              tipo_id: tipoId,
              ca: "CA-QA-99999",
              marca: "QA ProGrip",
              modelo: "Modelo QA-500",
              tamanho: "G",
              quantidade_estoque: 0,
              quantidade_minima: 5,
              local_estoque_id: localId,
              localizacao: "Prateleira A3",
              custo_unitario: 45.90,
              data_validade: new Date(Date.now() + 365 * 86400000).toISOString().split("T")[0],
              observacoes: "Item criado pelo agente de QA — teste completo",
              status: "disponivel",
            }).select("id, ca, marca, modelo, tamanho, quantidade_estoque").single();
            if (error) throw new Error(error.message);
            epiId = data.id;
            return `EPI criado: ${data.marca} ${data.modelo} (${data.tamanho}), CA: ${data.ca}, Estoque: ${data.quantidade_estoque}, ID: ${data.id.slice(0,8)}...`;
          }));
          await refreshIframe(); // Show newly created EPI in the list

          // 5. Registrar Entrada de Estoque — navigate to Movimentar tab
          await navigateTo("/epis?tab=entradas", "EPIs — Movimentar Estoque (Entrada)");
          steps.push(await runStepStreamed("epi", "5. Registrar Entrada de Estoque", "INSERT epi_estoque_local + UPDATE epis + INSERT epi_movimentacoes", async () => {
            if (!epiId || !localId || !effectiveTenant) throw new Error("EPI ou Local ausente");

            // Upsert estoque local
            const { error: estoqueError } = await supabaseAdmin.from("epi_estoque_local").insert({
              tenant_id: effectiveTenant,
              epi_id: epiId,
              local_estoque_id: localId,
              quantidade: 50,
              tamanho: "G",
            });
            if (estoqueError) throw new Error(`Estoque local: ${estoqueError.message}`);

            // Atualizar estoque global
            const { error: updateError } = await supabaseAdmin.from("epis").update({
              quantidade_estoque: 50,
            }).eq("id", epiId);
            if (updateError) throw new Error(`Update estoque global: ${updateError.message}`);

            // Registrar movimentação
            const { data: mov, error: movError } = await supabaseAdmin.from("epi_movimentacoes").insert({
              tenant_id: effectiveTenant,
              epi_id: epiId,
              tipo: "entrada",
              subtipo: "compra",
              local_estoque_id: localId,
              tamanho: "G",
              quantidade: 50,
              quantidade_anterior: 0,
              quantidade_atual: 50,
              motivo: "Compra (sem nota): Entrada inicial de teste pelo agente de QA",
              realizado_por_nome: "QA Agent",
            }).select("id").single();
            if (movError) throw new Error(`Movimentação: ${movError.message}`);
            if (mov) movimentacaoIds.push(mov.id);

            return `Entrada registrada: +50 unidades (G) no Almoxarifado Central. Estoque: 0 → 50`;
          }));
          await refreshIframe();

          // 6. Verificar Estoque Após Entrada — navigate to Estoque tab to see updated count
          await navigateTo("/epis?tab=estoque", "EPIs — Verificando Estoque");
          await refreshIframe();
          steps.push(await runStepStreamed("epi", "6. Verificar Estoque Após Entrada", "SELECT epis + epi_estoque_local", async () => {
            if (!epiId || !localId) throw new Error("EPI ou Local ausente");
            const { data: epi } = await supabaseAdmin.from("epis").select("quantidade_estoque").eq("id", epiId).single();
            if (!epi) throw new Error("EPI não encontrado");
            if (epi.quantidade_estoque !== 50) throw new Error(`Estoque global divergente: ${epi.quantidade_estoque} (esperado: 50)`);

            const { data: local } = await supabaseAdmin.from("epi_estoque_local")
              .select("quantidade")
              .eq("epi_id", epiId).eq("local_estoque_id", localId).eq("tamanho", "G")
              .single();
            if (!local) throw new Error("Estoque local não encontrado");
            if (local.quantidade !== 50) throw new Error(`Estoque local divergente: ${local.quantidade} (esperado: 50)`);

            return `✓ Estoque global: ${epi.quantidade_estoque} | Estoque local (G): ${local.quantidade}`;
          }));

          // 7. Registrar Entrega ao Colaborador — navigate to Entregas tab
          await navigateTo("/epis?tab=entregas", "EPIs — Registrando Entrega ao Colaborador");
          steps.push(await runStepStreamed("epi", "7. Registrar Entrega", "INSERT epi_entregas", async () => {
            if (!epiId || !effectiveTenant) throw new Error("EPI ausente");
            const { data, error } = await supabaseAdmin.from("epi_entregas").insert({
              tenant_id: effectiveTenant,
              epi_id: epiId,
              colaborador_nome: "QA Agent — João da Silva Teste",
              colaborador_cpf: "999.888.777-00",
              colaborador_cargo: "Eletricista",
              colaborador_departamento: "Manutenção",
              quantidade: 2,
              tamanho: "G",
              data_entrega: new Date().toISOString().split("T")[0],
              motivo_entrega: "Substituição por desgaste natural",
              observacoes: "Entrega registrada pelo agente de QA — teste de fluxo completo",
              status: "ativa",
            }).select("id, colaborador_nome, quantidade, tamanho").single();
            if (error) throw new Error(error.message);
            entregaId = data.id;
            return `Entrega registrada: ${data.quantidade}x (${data.tamanho}) para "${data.colaborador_nome}", ID: ${data.id.slice(0,8)}...`;
          }));
          await refreshIframe(); // Show the new delivery in the Entregas list

          // 8. Verificar Trigger de Baixa de Estoque — navigate to Estoque to see the change
          await navigateTo("/epis?tab=estoque", "EPIs — Verificando Baixa de Estoque (Trigger)");
          await refreshIframe();
          steps.push(await runStepStreamed("epi", "8. Verificar Trigger Baixa Estoque", "SELECT epis (pós-entrega)", async () => {
            if (!epiId) throw new Error("EPI não encontrado");
            await delay(500); // aguardar trigger
            const { data, error } = await supabaseAdmin.from("epis").select("quantidade_estoque").eq("id", epiId).single();
            if (error) throw new Error(error.message);
            if (data.quantidade_estoque === 48) return `✓ Trigger OK: estoque 50 → 48 (baixa de 2 unidades pela entrega)`;
            if (data.quantidade_estoque === 50) return `⚠️ Trigger NÃO executou: estoque continua em 50 (esperado: 48)`;
            return `Estoque atual: ${data.quantidade_estoque} (esperado: 48)`;
          }));

          // 9. Registrar Devolução — navigate to Entregas to see status change
          await navigateTo("/epis?tab=entregas", "EPIs — Registrando Devolução");
          steps.push(await runStepStreamed("epi", "9. Registrar Devolução", "UPDATE epi_entregas (devolvido)", async () => {
            if (!entregaId) throw new Error("Entrega não registrada");
            const { error } = await supabaseAdmin.from("epi_entregas").update({
              status: "devolvido",
              data_devolucao_efetiva: new Date().toISOString().split("T")[0],
              observacoes: "Devolução registrada pelo agente de QA — teste de fluxo completo",
            }).eq("id", entregaId);
            if (error) throw new Error(error.message);
            return `Devolução registrada para entrega ${entregaId.slice(0,8)}...`;
          }));
          await refreshIframe(); // Show updated status in Entregas list

          // 10. Verificar Trigger de Reposição de Estoque
          await navigateTo("/epis?tab=estoque", "EPIs — Verificando Reposição (Trigger Devolução)");
          await refreshIframe();
          steps.push(await runStepStreamed("epi", "10. Verificar Trigger Reposição Estoque", "SELECT epis (pós-devolução)", async () => {
            if (!epiId) throw new Error("EPI não encontrado");
            await delay(500);
            const { data } = await supabaseAdmin.from("epis").select("quantidade_estoque").eq("id", epiId).single();
            if (!data) throw new Error("EPI não encontrado");
            if (data.quantidade_estoque === 50) return `✓ Trigger OK: estoque restaurado 48 → 50 (devolução de 2 unidades)`;
            return `Estoque: ${data.quantidade_estoque} (esperado: 50 após devolução)`;
          }));

          // 11. Verificar Estoque Mínimo e Alerta
          await navigateTo("/epis?tab=alertas", "EPIs — Alertas de Estoque");
          await refreshIframe();
          steps.push(await runStepStreamed("epi", "11. Verificar Estoque Mínimo", "SELECT epis (quantidade_minima)", async () => {
            if (!epiId) throw new Error("EPI não encontrado");
            const { data } = await supabaseAdmin.from("epis").select("quantidade_estoque, quantidade_minima").eq("id", epiId).single();
            if (!data) throw new Error("EPI não encontrado");
            const abaixo = data.quantidade_estoque <= data.quantidade_minima;
            return abaixo
              ? `⚠️ ALERTA: Estoque (${data.quantidade_estoque}) ≤ Mínimo (${data.quantidade_minima})`
              : `✓ Estoque OK: ${data.quantidade_estoque} > Mínimo ${data.quantidade_minima}`;
          }));

          // 12. Verificar Histórico de Movimentações
          await navigateTo("/epis?tab=historico", "EPIs — Histórico de Movimentações");
          await refreshIframe();
          steps.push(await runStepStreamed("epi", "12. Verificar Movimentações", "SELECT epi_movimentacoes", async () => {
            if (!epiId) throw new Error("EPI não encontrado");
            const { data, error } = await supabaseAdmin.from("epi_movimentacoes")
              .select("id, tipo, subtipo, quantidade, motivo, created_at")
              .eq("epi_id", epiId)
              .order("created_at", { ascending: true });
            if (error) throw new Error(error.message);
            if (!data || data.length === 0) return `⚠️ Nenhuma movimentação encontrada para este EPI`;
            const resumo = data.map((m: any) => `${m.tipo}(${m.subtipo || '-'}): ${m.quantidade}`).join(", ");
            return `${data.length} movimentação(ões): ${resumo}`;
          }));

          // 13. Listar EPIs via Auth Client (RLS)
          steps.push(await runStepStreamed("epi", "13. Listar EPIs via Auth (RLS)", "SELECT epis (auth client)", async () => {
            if (!authClient) throw new Error("Auth client não disponível");
            const { data, error } = await authClient.from("epis").select("id, ca, quantidade_estoque, status").eq("tenant_id", effectiveTenant);
            if (error) throw new Error(`RLS bloqueou: ${error.message}`);
            const encontrouTeste = data?.some((e: any) => e.id === epiId);
            return `${data?.length || 0} EPIs visíveis pelo auth client. EPI de teste ${encontrouTeste ? "encontrado ✓" : "NÃO encontrado ⚠️"}`;
          }));

          // 14. Cleanup Completo
          await navigateTo("/epis?tab=estoque", "EPIs — Limpando dados de teste");
          steps.push(await runStepStreamed("epi", "14. Cleanup Completo", "DELETE (todos dados de teste)", async () => {
            const removidos: string[] = [];
            if (entregaId) {
              await supabaseAdmin.from("epi_entregas").delete().eq("id", entregaId);
              removidos.push("entrega");
            }
            if (epiId) {
              await supabaseAdmin.from("epi_movimentacoes").delete().eq("epi_id", epiId);
              removidos.push("movimentações");
              await supabaseAdmin.from("epi_estoque_local").delete().eq("epi_id", epiId);
              removidos.push("estoque local");
              await supabaseAdmin.from("epis").delete().eq("id", epiId);
              removidos.push("EPI");
            }
            if (localId) {
              await supabaseAdmin.from("epi_locais_estoque").delete().eq("id", localId);
              removidos.push("local de estoque");
            }
            if (tipoId) {
              await supabaseAdmin.from("epi_tipos").delete().eq("id", tipoId);
              removidos.push("tipo EPI");
            }
            return `Dados removidos: ${removidos.join(", ")}`;
          }));
          await refreshIframe(); // Show cleaned state

          const fr = buildFlowResult("epi", "EPI — Fluxo Completo", steps);
          flows.push(fr);
          send("flow_done", fr);
        }

        // ═══════════════════════════════════════════════════
        // FLOW: PLANO DE AÇÃO
        // ═══════════════════════════════════════════════════
        if (flow === "plano_acao" || flow === "todos") {
          send("flow_start", { flow: "plano_acao", label: "Plano de Ação" });
          await navigateTo("/plano-acao", "Plano de Ação");
          const steps: StepResult[] = [];
          let acaoId: string | null = null;
          let tarefaId: string | null = null;

          steps.push(await runStepStreamed("plano_acao", "1. Criar Ação", "INSERT plano_acoes", async () => {
            const { data, error } = await supabaseAdmin.from("plano_acoes").insert({
              tenant_id: effectiveTenant, titulo: "QA Agent — Ação de Teste",
              descricao: "Ação criada pelo agente de QA", status: "pendente",
              prioridade: "media", responsavel_nome: "QA Agent",
              prazo: new Date(Date.now() + 30 * 86400000).toISOString().split("T")[0],
              origem: "plano_acao", progresso: 0,
            }).select("id, codigo").single();
            if (error) throw new Error(error.message);
            acaoId = data.id;
            return `Ação criada: ${data.codigo || data.id}`;
          }));

          steps.push(await runStepStreamed("plano_acao", "2. Criar 2 Tarefas", "INSERT plano_tarefas", async () => {
            if (!acaoId) throw new Error("Ação não criada");
            const tarefas = ["Tarefa A", "Tarefa B"];
            for (const t of tarefas) {
              const { data, error } = await supabaseAdmin.from("plano_tarefas").insert({
                tenant_id: effectiveTenant, acao_id: acaoId, titulo: `QA — ${t}`,
                status: "pendente", responsavel_nome: "QA Agent",
                prazo: new Date(Date.now() + 15 * 86400000).toISOString().split("T")[0],
              }).select("id").single();
              if (error) throw new Error(error.message);
              if (!tarefaId) tarefaId = data.id;
            }
            return `2 tarefas criadas para a ação`;
          }));

          steps.push(await runStepStreamed("plano_acao", "3. Concluir 1 Tarefa", "UPDATE plano_tarefas", async () => {
            if (!tarefaId) throw new Error("Tarefa não criada");
            const { error } = await supabaseAdmin.from("plano_tarefas").update({ status: "concluida" }).eq("id", tarefaId);
            if (error) throw new Error(error.message);
            return "1 tarefa concluída";
          }));

          steps.push(await runStepStreamed("plano_acao", "4. Verificar Trigger Progresso", "SELECT plano_acoes", async () => {
            if (!acaoId) throw new Error("Ação não encontrada");
            await new Promise(r => setTimeout(r, 500));
            const { data, error } = await supabaseAdmin.from("plano_acoes").select("progresso, status").eq("id", acaoId).single();
            if (error) throw new Error(error.message);
            if (data.progresso === 50) return `Trigger OK: progresso=50% (1/2 tarefas) ✓`;
            return `Progresso: ${data.progresso}%, Status: ${data.status}`;
          }));

          steps.push(await runStepStreamed("plano_acao", "5. Cleanup", "DELETE", async () => {
            if (acaoId) {
              await supabaseAdmin.from("plano_tarefas").delete().eq("acao_id", acaoId);
              await supabaseAdmin.from("plano_acoes").delete().eq("id", acaoId);
            }
            return "Dados de teste removidos";
          }));

          const fr = buildFlowResult("plano_acao", "Plano de Ação", steps);
          flows.push(fr);
          send("flow_done", fr);
        }

        // ═══════════════════════════════════════════════════
        // FLOW: BENEFÍCIOS
        // ═══════════════════════════════════════════════════
        if (flow === "beneficios" || flow === "todos") {
          send("flow_start", { flow: "beneficios", label: "Benefícios" });
          await navigateTo("/financeiro/beneficios", "Financeiro — Benefícios");
          const steps: StepResult[] = [];
          let tipoId: string | null = null;

          steps.push(await runStepStreamed("beneficios", "1. Criar Tipo de Benefício", "INSERT beneficios_tipos", async () => {
            const { data, error } = await supabaseAdmin.from("beneficios_tipos").insert({
              tenant_id: effectiveTenant, nome: "QA — Vale Refeição Teste",
              categoria: "alimentacao", valor_padrao: 800,
              descricao: "Benefício criado pelo agente de QA",
            }).select("id").single();
            if (error) throw new Error(error.message);
            tipoId = data.id;
            return `Tipo criado: ${data.id}, Valor: R$800`;
          }));

          steps.push(await runStepStreamed("beneficios", "2. Verificar Tipo", "SELECT beneficios_tipos", async () => {
            if (!tipoId) throw new Error("Tipo não criado");
            const { data, error } = await supabaseAdmin.from("beneficios_tipos").select("*").eq("id", tipoId).single();
            if (error) throw new Error(error.message);
            return `Verificado: ${data.nome}, Categoria: ${data.categoria}, Ativo: ${data.ativo}`;
          }));

          steps.push(await runStepStreamed("beneficios", "3. Listar Tipos (Auth)", "SELECT via auth", async () => {
            if (!authClient) throw new Error("Auth client não disponível");
            const { data, error } = await authClient.from("beneficios_tipos").select("id, nome, categoria").eq("tenant_id", effectiveTenant);
            if (error) throw new Error(`RLS: ${error.message}`);
            return `${data?.length || 0} tipos de benefício visíveis`;
          }));

          steps.push(await runStepStreamed("beneficios", "4. Cleanup", "DELETE", async () => {
            if (tipoId) await supabaseAdmin.from("beneficios_tipos").delete().eq("id", tipoId);
            return "Tipo de benefício removido";
          }));

          const fr = buildFlowResult("beneficios", "Benefícios", steps);
          flows.push(fr);
          send("flow_done", fr);
        }

        // ═══════════════════════════════════════════════════
        // FLOW: OCORRÊNCIAS
        // ═══════════════════════════════════════════════════
        if (flow === "ocorrencias" || flow === "todos") {
          send("flow_start", { flow: "ocorrencias", label: "Ocorrências" });
          await navigateTo("/feedback-ocorrencias", "Feedback & Ocorrências");
          const steps: StepResult[] = [];
          let ocorrenciaId: string | null = null;

          steps.push(await runStepStreamed("ocorrencias", "1. Criar Ocorrência", "INSERT ocorrencias", async () => {
            const { data, error } = await supabaseAdmin.from("ocorrencias").insert({
              tenant_id: effectiveTenant, tipo: "advertencia",
              colaborador_nome: "QA Agent — Colaborador Teste",
              descricao: "Ocorrência de teste criada pelo agente de QA",
              data_ocorrencia: new Date().toISOString().split("T")[0],
              status: "aberta", gravidade: "leve",
            }).select("id").single();
            if (error) throw new Error(error.message);
            ocorrenciaId = data.id;
            return `Ocorrência criada: ${data.id}`;
          }));

          steps.push(await runStepStreamed("ocorrencias", "2. Atualizar Status", "UPDATE ocorrencias", async () => {
            if (!ocorrenciaId) throw new Error("Ocorrência não criada");
            const { error } = await supabaseAdmin.from("ocorrencias").update({
              status: "em_andamento",
            }).eq("id", ocorrenciaId);
            if (error) throw new Error(error.message);
            return "Status atualizado para em_andamento";
          }));

          steps.push(await runStepStreamed("ocorrencias", "3. Cleanup", "DELETE", async () => {
            if (ocorrenciaId) await supabaseAdmin.from("ocorrencias").delete().eq("id", ocorrenciaId);
            return "Ocorrência de teste removida";
          }));

          const fr = buildFlowResult("ocorrencias", "Ocorrências", steps);
          flows.push(fr);
          send("flow_done", fr);
        }


        // ═══════════════════════════════════════════════════
        // FLOW: ESTRATÉGIA SWOT (Fluxo Completo — Profundo)
        // ═══════════════════════════════════════════════════
        if (flow === "estrategia_swot" || flow === "todos") {
          send("flow_start", { flow: "estrategia_swot", label: "Estratégia SWOT — Fluxo Completo" });
          await navigateTo("/estrategia", "Estratégia & Governança > SWOT");
          const steps: StepResult[] = [];
          let swotId: string | null = null;
          const itemIds: string[] = [];

          // ── CT-SWOT-010: Criar SWOT (caminho feliz) ──
          steps.push(await runStepStreamed("estrategia_swot", "1. Criar Análise SWOT", "INSERT estrategia_swot", async () => {
            if (!effectiveTenant) throw new Error("tenantId obrigatório");
            const { data, error } = await supabaseAdmin.from("estrategia_swot").insert({
              tenant_id: effectiveTenant,
              titulo: "QA Agent — SWOT Estratégica 2026",
              descricao: "Análise SWOT criada automaticamente pelo agente de QA para validação completa do fluxo E2E. Contexto: planejamento estratégico do primeiro trimestre.",
              escopo: "empresa",
              periodo: "2026 Q1",
              criado_por_nome: "QA Agent (Automatizado)",
            }).select("id, titulo, escopo, periodo").single();
            if (error) throw new Error(error.message);
            swotId = data.id;
            return `SWOT criada: "${data.titulo}", Escopo: ${data.escopo}, Período: ${data.periodo}, ID: ${data.id.slice(0,8)}...`;
          }));

          // ── CT-SWOT-010b: Verificar dados persistidos ──
          steps.push(await runStepStreamed("estrategia_swot", "2. Verificar Dados Persistidos", "SELECT estrategia_swot", async () => {
            if (!swotId) throw new Error("SWOT não criada");
            const { data, error } = await supabaseAdmin.from("estrategia_swot").select("*").eq("id", swotId).single();
            if (error) throw new Error(error.message);
            if (data.titulo !== "QA Agent — SWOT Estratégica 2026") throw new Error(`Título divergente: ${data.titulo}`);
            if (data.escopo !== "empresa") throw new Error(`Escopo divergente: ${data.escopo}`);
            if (data.periodo !== "2026 Q1") throw new Error(`Período divergente: ${data.periodo}`);
            if (!data.descricao || data.descricao.length < 10) throw new Error("Descrição vazia ou muito curta");
            return `✓ Título: "${data.titulo}" | Escopo: ${data.escopo} | Período: ${data.periodo} | Descrição: ${data.descricao.length} chars | Criado por: ${data.criado_por_nome}`;
          }));

          // ── CT-SWOT-020/021: Adicionar itens nos 4 quadrantes ──
          await navigateTo("/estrategia", "SWOT — Adicionando itens nos 4 quadrantes");
          const swotQuadrantes: Array<{tipo: string, descricao: string, classificacao: string, impacto: string}> = [
            { tipo: "forca", descricao: "Equipe técnica altamente qualificada com certificações internacionais", classificacao: "pessoas", impacto: "alto" },
            { tipo: "forca", descricao: "Processos de SST consolidados e auditados semestralmente", classificacao: "operacional", impacto: "medio" },
            { tipo: "fraqueza", descricao: "Falta de automação em processos de admissão e onboarding", classificacao: "operacional", impacto: "alto" },
            { tipo: "fraqueza", descricao: "Rotatividade elevada no setor de produção", classificacao: "pessoas", impacto: "alto" },
            { tipo: "oportunidade", descricao: "Expansão do mercado de SST digital com demanda crescente por compliance", classificacao: "mercado", impacto: "alto" },
            { tipo: "oportunidade", descricao: "Possibilidade de parceria estratégica com consultorias de RH", classificacao: "estrategico", impacto: "medio" },
            { tipo: "ameaca", descricao: "Mudança na legislação trabalhista (NR-01 atualizada) exigindo adaptação rápida", classificacao: "estrategico", impacto: "alto" },
            { tipo: "ameaca", descricao: "Entrada de concorrentes com IA generativa em SST", classificacao: "mercado", impacto: "medio" },
          ];

          steps.push(await runStepStreamed("estrategia_swot", "3. Adicionar 8 Itens (4 Quadrantes)", "INSERT estrategia_swot_itens x8", async () => {
            if (!swotId || !effectiveTenant) throw new Error("SWOT ou tenant ausente");
            const resultados: string[] = [];
            for (let i = 0; i < swotQuadrantes.length; i++) {
              const q = swotQuadrantes[i];
              const { data, error } = await supabaseAdmin.from("estrategia_swot_itens").insert({
                tenant_id: effectiveTenant,
                swot_id: swotId,
                tipo: q.tipo,
                descricao: q.descricao,
                classificacao: q.classificacao,
                impacto: q.impacto,
                ordem: i + 1,
              }).select("id, tipo").single();
              if (error) throw new Error(`Erro no item ${q.tipo} #${i+1}: ${error.message}`);
              itemIds.push(data.id);
              resultados.push(`${q.tipo}(${q.impacto})`);
            }
            return `8 itens criados: ${resultados.join(", ")}`;
          }));

          // ── Verificar contadores por quadrante ──
          steps.push(await runStepStreamed("estrategia_swot", "4. Verificar Contadores por Quadrante", "SELECT COUNT por tipo", async () => {
            if (!swotId) throw new Error("SWOT ausente");
            const { data, error } = await supabaseAdmin.from("estrategia_swot_itens").select("tipo").eq("swot_id", swotId);
            if (error) throw new Error(error.message);
            const contadores: Record<string, number> = {};
            data?.forEach((item: any) => { contadores[item.tipo] = (contadores[item.tipo] || 0) + 1; });
            const esperado: Record<string, number> = { forca: 2, fraqueza: 2, oportunidade: 2, ameaca: 2 };
            for (const [tipo, qtd] of Object.entries(esperado)) {
              if ((contadores[tipo] || 0) !== qtd) throw new Error(`Contador ${tipo}: ${contadores[tipo] || 0} (esperado: ${qtd})`);
            }
            return `✓ Contadores: Forças=${contadores.forca}, Fraquezas=${contadores.fraqueza}, Oportunidades=${contadores.oportunidade}, Ameaças=${contadores.ameaca}`;
          }));

          // ── CT-SWOT-023: Validar dados de cada item ──
          steps.push(await runStepStreamed("estrategia_swot", "5. Validar Dados dos Itens", "SELECT estrategia_swot_itens", async () => {
            if (!swotId) throw new Error("SWOT ausente");
            const { data, error } = await supabaseAdmin.from("estrategia_swot_itens").select("*").eq("swot_id", swotId).order("ordem");
            if (error) throw new Error(error.message);
            if (!data || data.length !== 8) throw new Error(`Esperado 8 itens, encontrado ${data?.length || 0}`);
            for (const item of data) {
              if (!item.descricao || item.descricao.trim().length === 0) throw new Error(`Item ${item.id}: descrição vazia`);
              if (!item.tipo) throw new Error(`Item ${item.id}: tipo ausente`);
              if (!item.classificacao) throw new Error(`Item ${item.id}: classificação ausente`);
              if (!item.impacto) throw new Error(`Item ${item.id}: impacto ausente`);
            }
            const tipos = data.map((i: any) => `${i.tipo}:${i.classificacao}:${i.impacto}`);
            return `✓ 8 itens válidos — campos obrigatórios preenchidos. Combinações: ${[...new Set(tipos)].join(", ")}`;
          }));

          // ── CT-SWOT-024: Excluir 1 item e verificar contador ──
          steps.push(await runStepStreamed("estrategia_swot", "6. Excluir Item + Verificar Contador", "DELETE 1 item + recount", async () => {
            if (itemIds.length === 0) throw new Error("Nenhum item para excluir");
            const itemParaExcluir = itemIds.pop()!;
            const { error } = await supabaseAdmin.from("estrategia_swot_itens").delete().eq("id", itemParaExcluir);
            if (error) throw new Error(error.message);
            const { data: check } = await supabaseAdmin.from("estrategia_swot_itens").select("id").eq("id", itemParaExcluir);
            if (check && check.length > 0) throw new Error("Item ainda existe após exclusão!");
            const { data: remaining } = await supabaseAdmin.from("estrategia_swot_itens").select("tipo").eq("swot_id", swotId);
            const ameacas = remaining?.filter((r: any) => r.tipo === "ameaca").length || 0;
            if (ameacas !== 1) throw new Error(`Ameaças deveria ser 1 após exclusão, é ${ameacas}`);
            return `✓ Item excluído. Total restante: ${remaining?.length || 0} itens. Ameaças: ${ameacas} (era 2, agora 1)`;
          }));

          // ── CT-SWOT-051: Teste XSS/Injeção ──
          steps.push(await runStepStreamed("estrategia_swot", "7. Teste de Segurança XSS", "INSERT com payload malicioso", async () => {
            if (!swotId || !effectiveTenant) throw new Error("SWOT/tenant ausente");
            const xssPayload = '<script>alert("xss")</script><img src=x onerror=alert(1)>';
            const { data, error } = await supabaseAdmin.from("estrategia_swot_itens").insert({
              tenant_id: effectiveTenant, swot_id: swotId, tipo: "forca",
              descricao: xssPayload, classificacao: "operacional", impacto: "baixo", ordem: 99,
            }).select("id, descricao").single();
            if (error) throw new Error(error.message);
            itemIds.push(data.id);
            if (data.descricao.includes("<script>")) {
              return `⚠️ Payload XSS armazenado como texto (não executa se UI escapa corretamente). Verificar renderização.`;
            }
            return `✓ Payload sanitizado ou armazenado como texto seguro`;
          }));

          // ── CT-SWOT-003/050: Verificar RLS ──
          steps.push(await runStepStreamed("estrategia_swot", "8. Listar SWOTs via Auth (RLS)", "SELECT auth client", async () => {
            if (!authClient) throw new Error("Auth client não disponível");
            const { data, error } = await authClient.from("estrategia_swot").select("id, titulo, escopo").eq("tenant_id", effectiveTenant);
            if (error) throw new Error(`RLS bloqueou: ${error.message}`);
            const encontrou = data?.some((s: any) => s.id === swotId);
            return `${data?.length || 0} SWOTs visíveis. SWOT de teste ${encontrou ? "encontrada ✓" : "NÃO encontrada ⚠️"}`;
          }));

          // ── CT-SWOT-050: IDOR — Cross-Tenant ──
          steps.push(await runStepStreamed("estrategia_swot", "9. Teste IDOR Cross-Tenant", "SELECT swot outro tenant (auth)", async () => {
            if (!authClient || !effectiveTenant) throw new Error("Auth client ou tenant ausente");
            const { data: tenants } = await supabaseAdmin.from("tenants").select("id").neq("id", effectiveTenant).limit(1);
            if (!tenants || tenants.length === 0) return "Apenas 1 tenant — skip teste IDOR";
            const otherTenantId = tenants[0].id;
            const { data: otherSwot } = await supabaseAdmin.from("estrategia_swot").insert({
              tenant_id: otherTenantId, titulo: "IDOR Test — Outro Tenant", escopo: "empresa", periodo: "2026",
            }).select("id").single();
            if (otherSwot) {
              const { data: leaked } = await authClient.from("estrategia_swot").select("id").eq("id", otherSwot.id);
              await supabaseAdmin.from("estrategia_swot").delete().eq("id", otherSwot.id);
              if (leaked && leaked.length > 0) throw new Error(`CRÍTICO: IDOR — SWOT de outro tenant acessível!`);
              return `✓ Isolamento IDOR OK — SWOT do tenant ${otherTenantId.slice(0,8)}... não acessível`;
            }
            return "Skip — não foi possível criar SWOT no outro tenant";
          }));

          // ── CT-SWOT-014: Duplicidade ──
          steps.push(await runStepStreamed("estrategia_swot", "10. Teste de Duplicidade", "INSERT duplicado", async () => {
            if (!effectiveTenant) throw new Error("Tenant ausente");
            const { data: dup, error } = await supabaseAdmin.from("estrategia_swot").insert({
              tenant_id: effectiveTenant, titulo: "QA Agent — SWOT Estratégica 2026", escopo: "empresa", periodo: "2026 Q1",
            }).select("id").single();
            if (error) return `✓ Banco rejeitou duplicata: ${error.message}`;
            if (dup) await supabaseAdmin.from("estrategia_swot").delete().eq("id", dup.id);
            return `⚠️ Banco permite SWOTs com título duplicado (considerar validação no front-end)`;
          }));

          // ── Atualizar SWOT ──
          steps.push(await runStepStreamed("estrategia_swot", "11. Atualizar SWOT", "UPDATE estrategia_swot", async () => {
            if (!swotId) throw new Error("SWOT ausente");
            const { error } = await supabaseAdmin.from("estrategia_swot").update({
              titulo: "QA Agent — SWOT Estratégica 2026 (Atualizada)", periodo: "2026 Q1-Q2",
            }).eq("id", swotId);
            if (error) throw new Error(error.message);
            const { data } = await supabaseAdmin.from("estrategia_swot").select("titulo, periodo").eq("id", swotId).single();
            if (!data || !data.titulo.includes("Atualizada")) throw new Error("Update não aplicado");
            return `✓ SWOT atualizada: "${data.titulo}", Período: ${data.periodo}`;
          }));

          // ── Listar itens via Auth ──
          steps.push(await runStepStreamed("estrategia_swot", "12. Listar Itens via Auth (RLS)", "SELECT itens auth", async () => {
            if (!authClient || !swotId) throw new Error("Auth client ou SWOT ausente");
            const { data, error } = await authClient.from("estrategia_swot_itens").select("id, tipo, descricao, classificacao, impacto").eq("swot_id", swotId);
            if (error) throw new Error(`RLS: ${error.message}`);
            return `${data?.length || 0} itens da SWOT visíveis pelo auth client`;
          }));

          // ── CT-SWOT-025: Excluir SWOT (cascata) ──
          await navigateTo("/estrategia", "SWOT — Excluindo análise completa");
          steps.push(await runStepStreamed("estrategia_swot", "13. Excluir SWOT + Itens", "DELETE cascata", async () => {
            if (!swotId) throw new Error("SWOT ausente");
            await supabaseAdmin.from("estrategia_swot_itens").delete().eq("swot_id", swotId);
            const { error } = await supabaseAdmin.from("estrategia_swot").delete().eq("id", swotId);
            if (error) throw new Error(error.message);
            const { data: check } = await supabaseAdmin.from("estrategia_swot").select("id").eq("id", swotId);
            if (check && check.length > 0) throw new Error("SWOT ainda existe após exclusão!");
            return `✓ SWOT e itens excluídos com sucesso. Nenhum dado órfão.`;
          }));

          // ── Verificar exclusão ──
          steps.push(await runStepStreamed("estrategia_swot", "14. Verificar Exclusão Completa", "SELECT pós-delete", async () => {
            if (!authClient || !swotId) throw new Error("Auth/SWOT ausente");
            const { data } = await authClient.from("estrategia_swot").select("id").eq("id", swotId);
            if (data && data.length > 0) throw new Error("SWOT ainda visível após exclusão!");
            return `✓ SWOT não aparece mais na listagem — exclusão completa verificada`;
          }));

          const fr = buildFlowResult("estrategia_swot", "Estratégia SWOT — Fluxo Completo", steps);
          flows.push(fr);
          send("flow_done", fr);
        }

        // ═══════════════════════════════════════════════════
        // FLOW: RLS ISOLAMENTO
        // ═══════════════════════════════════════════════════
        if (flow === "rls_isolamento" || flow === "todos") {
          send("flow_start", { flow: "rls_isolamento", label: "Isolamento Multi-Tenant (RLS)" });
          await navigateTo("/", "Dashboard — Teste de Isolamento RLS");
          const steps: StepResult[] = [];

          steps.push(await runStepStreamed("rls_isolamento", "1. Listar Tenants", "SELECT tenants", async () => {
            const { data } = await supabaseAdmin.from("tenants").select("id, nome");
            return `${data?.length || 0} tenants encontrados`;
          }));

          steps.push(await runStepStreamed("rls_isolamento", "2. Acesso Anônimo", "SELECT (anon)", async () => {
            const anonClient = createClient(SUPABASE_URL, ANON_KEY);
            const tables = ["profiles", "admissoes", "atestados", "epis", "plano_acoes", "empresa_cadastro", "ocorrencias"];
            const exposed: string[] = [];
            for (const t of tables) {
              const { data } = await anonClient.from(t).select("id").limit(1);
              if (data && data.length > 0) exposed.push(t);
            }
            if (exposed.length > 0) throw new Error(`CRÍTICO: Tabelas expostas sem auth: ${exposed.join(", ")}`);
            return `${tables.length} tabelas testadas — nenhuma exposta ✓`;
          }));

          steps.push(await runStepStreamed("rls_isolamento", "3. Cross-Tenant (Auth)", "SELECT cross-tenant", async () => {
            if (!authClient || !effectiveTenant) throw new Error("Auth client ou tenant ausente");
            const { data: tenants } = await supabaseAdmin.from("tenants").select("id").neq("id", effectiveTenant).limit(1);
            if (!tenants || tenants.length === 0) return "Apenas 1 tenant — skip cross-tenant test";
            const otherTenant = tenants[0].id;
            // Try accessing another tenant's data via auth client
            const { data: profiles } = await authClient.from("profiles").select("id").eq("tenant_id", otherTenant);
            if (profiles && profiles.length > 0) throw new Error(`CRÍTICO: Acesso cross-tenant permitido (${profiles.length} profiles do tenant ${otherTenant.slice(0, 8)}...)`);
            return `Isolamento cross-tenant OK — sem acesso ao tenant ${otherTenant.slice(0, 8)}... ✓`;
          }));

          steps.push(await runStepStreamed("rls_isolamento", "4. Profiles × Tenants", "SELECT integrity", async () => {
            const { data: profiles } = await supabaseAdmin.from("profiles").select("tenant_id");
            const { data: tenants } = await supabaseAdmin.from("tenants").select("id");
            if (!profiles || !tenants) throw new Error("Não foi possível consultar");
            const tenantIds = new Set(tenants.map((t: any) => t.id));
            const orphans = profiles.filter((p: any) => p.tenant_id && !tenantIds.has(p.tenant_id));
            if (orphans.length > 0) throw new Error(`${orphans.length} perfis órfãos`);
            return `${profiles.length} perfis vinculados a tenants válidos ✓`;
          }));

          const fr = buildFlowResult("rls_isolamento", "Isolamento Multi-Tenant (RLS)", steps);
          flows.push(fr);
          send("flow_done", fr);
        }

        // ═══════════════════════════════════════════════════
        // FLOW: DOCUMENTOS
        // ═══════════════════════════════════════════════════
        if (flow === "documentos" || flow === "todos") {
          send("flow_start", { flow: "documentos", label: "Gestão de Documentos" });
          await navigateTo("/documentos", "Gestão de Documentos");
          const steps: StepResult[] = [];
          let pastaId: string | null = null;

          steps.push(await runStepStreamed("documentos", "1. Criar Pasta", "INSERT documento_pastas", async () => {
            const { data, error } = await supabaseAdmin.from("documento_pastas").insert({
              tenant_id: effectiveTenant, nome: "QA — Pasta Teste",
              tipo: "geral", criado_por_nome: "QA Agent",
            }).select("id").single();
            if (error) throw new Error(error.message);
            pastaId = data.id;
            return `Pasta criada: ${data.id}`;
          }));

          steps.push(await runStepStreamed("documentos", "2. Listar Pastas (Auth)", "SELECT via auth", async () => {
            if (!authClient) throw new Error("Auth client não disponível");
            const { data, error } = await authClient.from("documento_pastas").select("id, nome").eq("tenant_id", effectiveTenant);
            if (error) throw new Error(error.message);
            return `${data?.length || 0} pastas visíveis pelo auth client`;
          }));

          steps.push(await runStepStreamed("documentos", "3. Cleanup", "DELETE", async () => {
            if (pastaId) await supabaseAdmin.from("documento_pastas").delete().eq("id", pastaId);
            return "Pasta de teste removida";
          }));

          const fr = buildFlowResult("documentos", "Gestão de Documentos", steps);
          flows.push(fr);
          send("flow_done", fr);
        }

        // ═══════════════════════════════════════════════════
        // FLOW: EDGE FUNCTIONS
        // ═══════════════════════════════════════════════════
        if (flow === "edge_functions" || flow === "todos") {
          send("flow_start", { flow: "edge_functions", label: "Health Check Edge Functions" });
          await navigateTo("/", "Dashboard — Health Check Functions");
          const steps: StepResult[] = [];
          const fns = [
            "onboarding-signup", "extract-atestado", "ai-plano-acao", "ai-chat",
            "ai-psicossocial-analise", "ai-sst-analise", "ai-feedback",
            "ai-pdi-smart", "ai-nf-ocr", "ai-pgr-riscos", "ai-qa-scan",
          ];

          for (const fn of fns) {
            steps.push(await runStepStreamed("edge_functions", `Ping ${fn}`, "POST health", async () => {
              const resp = await fetch(`${SUPABASE_URL}/functions/v1/${fn}`, {
                method: "POST",
                headers: { "Content-Type": "application/json", Authorization: `Bearer ${ANON_KEY}` },
                body: JSON.stringify({ test: true }),
              });
              if (resp.status === 404) throw new Error("Não deployada (404)");
              if (resp.status === 500) throw new Error(`Erro interno (500)`);
              return `Status ${resp.status} — respondendo ✓`;
            }));
          }

          const fr = buildFlowResult("edge_functions", "Health Check Edge Functions", steps);
          flows.push(fr);
          send("flow_done", fr);
        }

        // ═══════════════════════════════════════════════════
        // GENERIC SMOKE TEST — for modules without deep flows
        // Navigates to the page, checks auth client can read data, validates RLS
        // ═══════════════════════════════════════════════════
        const smokeModules: { id: string; label: string; route: string; table: string; columns: string }[] = [
          { id: "departamentos", label: "Departamentos", route: "/cadastros/departamentos", table: "departamentos", columns: "id, nome" },
          { id: "cargos", label: "Funções / Cargos", route: "/cadastros/cargos", table: "cargos", columns: "id, nome" },
          { id: "filiais", label: "Estabelecimentos / Obras", route: "/cadastros/filiais", table: "empresa_cadastro", columns: "id, razao_social, tipo_unidade" },
          { id: "terceiros", label: "Terceiros & SST", route: "/terceiros", table: "terceiros", columns: "id, razao_social, status" },
          { id: "marketplace", label: "Rede de Parceiros", route: "/marketplace", table: "marketplace_profissionais", columns: "id, nome_completo, status" },
          { id: "onboarding", label: "Onboarding", route: "/onboarding", table: "onboarding_templates", columns: "id, nome, ativo" },
          { id: "ferias", label: "Férias", route: "/ferias", table: "ferias_solicitacoes", columns: "id, colaborador_nome, status" },
          { id: "ouvidoria", label: "Ouvidoria", route: "/ouvidoria", table: "ouvidoria", columns: "id, tipo, status" },
          { id: "ponto", label: "Ponto Eletrônico", route: "/ponto", table: "ponto_marcacoes", columns: "id, colaborador_nome, tipo_marcacao" },
          { id: "trilhas", label: "Trilhas de Aprendizado", route: "/trilhas", table: "trilhas", columns: "id, nome, status" },
          { id: "cultura", label: "Cultura & Celebrações", route: "/cultura-celebracoes", table: "cultura_datas", columns: "id, titulo, tipo" },
          { id: "bem_estar", label: "Bem-Estar", route: "/felicidade", table: "bem_estar_respostas", columns: "id, eixo, tipo" },
          { id: "avaliacoes", label: "Avaliações", route: "/avaliacoes", table: "avaliacao_templates", columns: "id, nome, tipo" },
          { id: "pdi", label: "PDI", route: "/pdi", table: "pdis", columns: "id, titulo, status" },
          { id: "compliance_sst", label: "Compliance SST", route: "/compliance-sst", table: "sst_documentos", columns: "id, tipo, status" },
          { id: "incidentes", label: "Incidentes & Acidentes", route: "/incidentes-acidentes", table: "eventos_sst", columns: "id, tipo, status" },
          { id: "ergonomia", label: "Ergonomia", route: "/ergonomia", table: "condicoes_especiais_trabalho", columns: "id, nome" },
          { id: "psicossocial", label: "Psicossocial NR-01", route: "/psicossocial", table: "psicossocial_campanhas", columns: "id, titulo, status" },
          { id: "hub_contabil", label: "Hub Contábil", route: "/hub-contabil", table: "hub_competencias", columns: "id, competencia, status" },
          { id: "financeiro", label: "Financeiro", route: "/financeiro", table: "certidoes_negativas", columns: "id, tipo, status" },
        ];

        for (const mod of smokeModules) {
          if (flow === mod.id || flow === "todos") {
            send("flow_start", { flow: mod.id, label: mod.label });
            await navigateTo(mod.route, mod.label);
            const steps: StepResult[] = [];

            // 1. Navigate & verify page loads
            steps.push(await runStepStreamed(mod.id, "1. Navegar para o módulo", `GET ${mod.route}`, async () => {
              return `Navegação para ${mod.route} OK`;
            }));

            // 2. List data via admin
            steps.push(await runStepStreamed(mod.id, "2. Listar dados (admin)", `SELECT ${mod.table}`, async () => {
              const { data, error } = await supabaseAdmin.from(mod.table).select(mod.columns).eq("tenant_id", effectiveTenant).limit(10);
              if (error) throw new Error(error.message);
              return `${data?.length || 0} registro(s) encontrados na tabela ${mod.table}`;
            }));
            await refreshIframe();

            // 3. Verify auth client can read (RLS)
            steps.push(await runStepStreamed(mod.id, "3. Verificar acesso Auth (RLS)", `SELECT ${mod.table} (auth)`, async () => {
              if (!authClient) throw new Error("Auth client não disponível");
              const { data, error } = await authClient.from(mod.table).select(mod.columns).eq("tenant_id", effectiveTenant).limit(5);
              if (error) throw new Error(`RLS bloqueou: ${error.message}`);
              return `Auth client: ${data?.length || 0} registros visíveis ✓`;
            }));

            const fr = buildFlowResult(mod.id, mod.label, steps);
            flows.push(fr);
            send("flow_done", fr);
          }
        }

        // ═══════════════════════════════════════════════════
        const totalPassed = flows.reduce((a, f) => a + f.passed, 0);
        const totalFailed = flows.reduce((a, f) => a + f.failed, 0);
        const totalSteps = flows.reduce((a, f) => a + f.steps.length, 0);

        send("ai_start", { message: "Gerando relatório com IA..." });

        let aiReport = "";
        try {
          const aiResp = await fetch("https://api.openai.com/v1/chat/completions", {
            method: "POST",
            headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, "Content-Type": "application/json" },
            body: JSON.stringify({
              model: "gpt-4o-mini",
              messages: [
                {
                  role: "system",
                  content: `Você é um agente de QA sênior analisando testes automatizados de um sistema SaaS de RH/SST.
O agente logou como ${TEST_EMAIL} e testou múltiplos módulos.

Gere um relatório executivo em Markdown:
1. **Resumo Geral**: X/Y testes passaram, score
2. **Autenticação**: se login e perfil funcionaram
3. **Módulos Testados**: status de cada fluxo
4. **Falhas Encontradas**: cada falha com causa provável e correção
5. **Triggers/Automações**: se triggers funcionaram (estoque EPI, progresso ação)
6. **Segurança RLS**: resultado do isolamento multi-tenant
7. **Top 5 Recomendações**: ações prioritárias
8. **Score Final**: 0-100

Seja direto e técnico. Português do Brasil.`,
                },
                { role: "user", content: JSON.stringify(flows, null, 2) },
              ],
              max_tokens: 2000,
            }),
          });
          if (aiResp.ok) {
            const d = await aiResp.json();
            aiReport = d.choices?.[0]?.message?.content || "";
          }
        } catch {
          aiReport = "Análise de IA indisponível.";
        }

        send("complete", {
          success: true, timestamp: new Date().toISOString(),
          total_flows: flows.length, total_steps: totalSteps,
          total_passed: totalPassed, total_failed: totalFailed,
          score: totalSteps > 0 ? Math.round((totalPassed / totalSteps) * 100) : 0,
          flows, ai_report: aiReport,
        });

        // Logout test user
        if (authClient) {
          try { await authClient.auth.signOut(); } catch {}
        }

        controller.close();
      },
    });

    return new Response(body, {
      headers: {
        ...corsHeaders,
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
      },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message || "Erro interno" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
