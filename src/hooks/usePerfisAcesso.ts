import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "./useAuth";
import { toast } from "sonner";

export interface PerfilTemplate {
  id: string;
  nome: string;
  descricao?: string;
  icone?: string;
  cor?: string;
  tipo_usuario_sugerido?: string;
  modulos_padrao: ModuloPadrao[];
  ativo: boolean;
  criado_em: string;
}

export interface ModuloPadrao {
  modulo: string;
  acoes: string[];
  escopo: string;
  recurso?: string;
}

export interface PerfilAcesso {
  id: string;
  tenant_id: string;
  nome: string;
  descricao?: string;
  icone?: string;
  cor: string;
  template_origem_id?: string;
  tipo: "padrao_sistema" | "clonado" | "personalizado";
  ativo: boolean;
  permite_acumulo: boolean;
  expira_em?: string;
  nivel_risco?: "normal" | "elevado" | "critico";
  is_perfil_assistido?: boolean;
  total_usuarios: number;
  criado_por?: string;
  criado_por_nome?: string;
  created_at: string;
  updated_at: string;
  // joined
  permissoes?: PerfilPermissao[];
}

export interface PerfilPermissao {
  id: string;
  perfil_id: string;
  tenant_id: string;
  modulo: string;
  recurso?: string;
  acao: string;
  escopo: string;
  ativo: boolean;
  is_sensivel: boolean;
  requer_2fa: boolean;
  observacao?: string;
  created_at: string;
}

export interface PerfilExcecao {
  id: string;
  tenant_id: string;
  usuario_id: string;
  empresa_id?: string;
  tipo: "adicionar" | "revogar";
  modulo: string;
  recurso?: string;
  acao: string;
  escopo: string;
  ativo: boolean;
  justificativa?: string;
  expira_em?: string;
  criado_por?: string;
  criado_por_nome?: string;
  created_at: string;
}

export interface UsuarioPerfilVinculo {
  id: string;
  tenant_id: string;
  usuario_id: string;
  empresa_id?: string;
  perfil_id: string;
  ativo: boolean;
  is_perfil_principal?: boolean;
  atribuido_por?: string;
  atribuido_por_nome?: string;
  expira_em?: string;
  observacao?: string;
  created_at: string;
  // joined
  perfil?: PerfilAcesso;
  usuario?: { nome_completo: string; email_principal: string; foto_url?: string };
}

export interface PerfilAuditLog {
  id: string;
  tenant_id: string;
  perfil_id?: string;
  acao: string;
  descricao?: string;
  dados_anteriores?: unknown;
  dados_novos?: unknown;
  realizado_por?: string;
  realizado_por_nome?: string;
  created_at: string;
}

export const MODULOS_SISTEMA = [
  // Estrutura Organizacional
  { id: "empresa", label: "Empresa", grupo: "Estrutura Organizacional" },
  { id: "filiais", label: "Estabelecimentos / Obras", grupo: "Estrutura Organizacional" },
  { id: "departamentos", label: "Departamentos", grupo: "Estrutura Organizacional" },
  { id: "cargos", label: "Cargos", grupo: "Estrutura Organizacional" },
  { id: "colaboradores", label: "Colaboradores", grupo: "Estrutura Organizacional" },
  { id: "terceiros", label: "Prestadores de Serviços", grupo: "Estrutura Organizacional" },
  { id: "organograma", label: "Organograma", grupo: "Estrutura Organizacional" },

  // Planejamento & Gestão
  { id: "identidade_estrategica", label: "Identidade Estratégica", grupo: "Planejamento & Gestão" },
  { id: "planejamento_estrategico", label: "Planejamento Estratégico", grupo: "Planejamento & Gestão" },
  { id: "metas", label: "Metas", grupo: "Planejamento & Gestão" },
  { id: "plano_acao", label: "Plano de Ação", grupo: "Planejamento & Gestão" },

  // Pessoas & Cultura
  { id: "onboarding", label: "Onboarding", grupo: "Pessoas & Cultura" },
  { id: "contratos_experiencia", label: "Contratos de Experiência", grupo: "Pessoas & Cultura" },
  { id: "cultura_celebracoes", label: "Cultura & Celebrações", grupo: "Pessoas & Cultura" },
  { id: "feed", label: "Mural Interno", grupo: "Pessoas & Cultura" },
  { id: "bem_estar", label: "Meu Bem-Estar", grupo: "Pessoas & Cultura" },
  { id: "feedback", label: "Feedback & Desenvolvimento", grupo: "Pessoas & Cultura" },
  { id: "ouvidoria", label: "Ouvidoria", grupo: "Pessoas & Cultura" },

  // Desenvolvimento & Performance
  { id: "aprendizado", label: "Aprendizado & Competências", grupo: "Desenvolvimento & Performance" },
  { id: "trilhas", label: "Trilhas", grupo: "Desenvolvimento & Performance" },
  { id: "avaliacoes", label: "Avaliações", grupo: "Desenvolvimento & Performance" },
  { id: "pdi", label: "PDI", grupo: "Desenvolvimento & Performance" },

  // Jornada & Rotina
  { id: "ponto", label: "Ponto", grupo: "Jornada & Rotina" },
  { id: "analise_jornada", label: "Análise de Jornada", grupo: "Jornada & Rotina" },
  { id: "ferias", label: "Férias", grupo: "Jornada & Rotina" },
  { id: "atestados", label: "Atestados", grupo: "Jornada & Rotina" },
  { id: "beneficios", label: "Benefícios", grupo: "Jornada & Rotina" },

  // Saúde & Segurança
  { id: "sst", label: "Compliance SST", grupo: "Saúde & Segurança" },
  { id: "psicossocial", label: "Psicossocial", grupo: "Saúde & Segurança" },
  { id: "ergonomia", label: "Ergonomia", grupo: "Saúde & Segurança" },
  { id: "epi", label: "EPIs", grupo: "Saúde & Segurança" },
  { id: "incidentes", label: "Incidentes & Acidentes", grupo: "Saúde & Segurança" },

  // Documentos & Governança
  { id: "documentos", label: "Documentos", grupo: "Documentos & Governança" },
  { id: "hub_contabil", label: "Hub Contábil", grupo: "Documentos & Governança" },

  // Financeiro
  { id: "financeiro", label: "Financeiro", grupo: "Financeiro" },

  // MarketYE (marketplace de serviços; o id "marketplace" fica, pois está gravado em perfil_permissoes.modulo)
  { id: "marketplace", label: "MarketYE", grupo: "MarketYE" },

  // Academia
  { id: "academia", label: "Academia", grupo: "Academia" },

  // Sistema
  { id: "usuarios", label: "Usuários", grupo: "Sistema" },
  { id: "perfis_acesso", label: "Perfis & Acessos", grupo: "Sistema" },
  { id: "configuracoes", label: "Configurações", grupo: "Sistema" },
  { id: "suporte", label: "Suporte", grupo: "Sistema" },
  { id: "auditoria", label: "Auditoria do Sistema", grupo: "Sistema" },
];

export const ACOES_DISPONIVEIS = [
  { id: "visualizar", label: "Visualizar", sensivel: false },
  { id: "criar", label: "Criar", sensivel: false },
  { id: "editar", label: "Editar", sensivel: false },
  { id: "excluir", label: "Excluir", sensivel: false },
  { id: "inativar", label: "Inativar/Arquivar", sensivel: false },
  { id: "exportar", label: "Exportar", sensivel: false },
  { id: "importar", label: "Importar", sensivel: false },
  { id: "aprovar", label: "Aprovar", sensivel: false },
  { id: "assinar", label: "Assinar", sensivel: false },
  { id: "compartilhar", label: "Compartilhar", sensivel: false },
  { id: "parametrizar", label: "Parametrizar", sensivel: false },
  { id: "administrar", label: "Administrar", sensivel: true },
  { id: "acessar_sensivel", label: "Dados Sensíveis", sensivel: true },
  { id: "acessar_anonimizado", label: "Dados Anonimizados", sensivel: false },
  { id: "ver_indicadores", label: "Indicadores Agregados", sensivel: false },
  { id: "ver_individual", label: "Dados Individualizados", sensivel: true },
];

export const ESCOPOS_DISPONIVEIS = [
  { id: "proprio_usuario", label: "Próprio usuário" },
  { id: "subordinados_diretos", label: "Subordinados diretos" },
  { id: "equipe_direta_indireta", label: "Equipe direta e indireta" },
  { id: "setor", label: "Setor" },
  { id: "unidade", label: "Unidade" },
  { id: "estabelecimento", label: "Estabelecimento/Obra" },
  { id: "empresa_inteira", label: "Empresa inteira" },
  { id: "grupo_economico", label: "Grupo econômico" },
  { id: "multiplas_empresas", label: "Múltiplas empresas" },
  { id: "carteira_clientes", label: "Carteira de clientes" },
  { id: "customizado", label: "Customizado" },
];

// Combos que geram alerta de risco
export const COMBOS_RISCO = [
  { modulos: ["auditoria", "financeiro", "administrar"], label: "Acúmulo crítico: auditoria + financeiro + administrar" },
  { modulos: ["psicossocial", "ver_individual", "exportar"], label: "Dados psicossociais individuais com exportação" },
  { modulos: ["ouvidoria", "ver_individual"], label: "Visualização individual de ouvidoria" },
];

export function calcularNivelRisco(permissoes: Partial<PerfilPermissao>[]): "normal" | "elevado" | "critico" {
  const acoesAtivas = new Set(permissoes.filter((p) => p.ativo !== false).map((p) => p.acao));
  const modulosAtivos = new Set(permissoes.filter((p) => p.ativo !== false).map((p) => p.modulo));
  const hasSensivel = ACOES_DISPONIVEIS.filter((a) => a.sensivel).some((a) => acoesAtivas.has(a.id));
  const hasAdm = acoesAtivas.has("administrar");
  const hasFinanceiro = modulosAtivos.has("financeiro");
  const hasPsico = modulosAtivos.has("psicossocial");
  const hasOuvidoria = modulosAtivos.has("ouvidoria");
  const hasAuditoria = modulosAtivos.has("auditoria");

  if (hasSensivel && (hasFinanceiro || hasPsico || hasOuvidoria) && hasAdm) return "critico";
  if (hasSensivel || hasAuditoria || (hasAdm && (hasFinanceiro || hasPsico))) return "elevado";
  return "normal";
}

async function logAuditPerfil(
  tenantId: string,
  perfilId: string | null,
  acao: string,
  descricao: string,
  dadosAnteriores?: unknown,
  dadosNovos?: unknown,
  realizadoPorNome?: string
) {
  try {
    await fromTable("perfil_audit_log").insert({
      tenant_id: tenantId,
      perfil_id: perfilId,
      acao,
      descricao,
      dados_anteriores: dadosAnteriores || null,
      dados_novos: dadosNovos || null,
      realizado_por_nome: realizadoPorNome,
    });
  } catch { /* non-blocking */ }
}

export function usePerfisAcesso() {
  const { tenantId, profile, user } = useAuth();
  const qc = useQueryClient();

  // Templates do sistema
  const { data: templates = [], isLoading: loadingTemplates } = useQuery({
    queryKey: ["perfil_templates"],
    queryFn: async (): Promise<PerfilTemplate[]> => {
      const { data, error } = await fromTable("perfil_templates")
        .select("*")
        .eq("ativo", true)
        .order("nome");
      if (error) throw error;
      return (data || []).map((t: any) => ({
        ...t,
        modulos_padrao: Array.isArray(t.modulos_padrao) ? t.modulos_padrao : [],
      }));
    },
    staleTime: 1000 * 60 * 30,
  });

  // Perfis do tenant
  const { data: perfis = [], isLoading: loadingPerfis } = useQuery({
    queryKey: ["perfis_acesso", tenantId],
    queryFn: async (): Promise<PerfilAcesso[]> => {
      if (!tenantId) return [];
      const { data, error } = await fromTable("perfis_acesso")
        .select("*, permissoes:perfil_permissoes(*)")
        .eq("tenant_id", tenantId)
        .order("nome");
      if (error) throw error;
      return (data || []) as PerfilAcesso[];
    },
    enabled: !!tenantId,
  });

  // Vínculos (usuário ↔ perfil)
  const { data: vinculos = [], isLoading: loadingVinculos } = useQuery({
    queryKey: ["usuario_perfil_vinculos", tenantId],
    queryFn: async (): Promise<UsuarioPerfilVinculo[]> => {
      if (!tenantId) return [];
      const { data, error } = await fromTable("usuario_perfil_vinculos")
        .select("*, perfil:perfil_id(id,nome,cor,icone,nivel_risco), usuario:usuario_id(nome_completo,email_principal,foto_url)")
        .eq("tenant_id", tenantId)
        .eq("ativo", true)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return (data || []) as UsuarioPerfilVinculo[];
    },
    enabled: !!tenantId,
  });

  // Logs de auditoria de perfis
  const { data: auditLogs = [], isLoading: loadingAuditLogs } = useQuery({
    queryKey: ["perfil_audit_log", tenantId],
    queryFn: async (): Promise<PerfilAuditLog[]> => {
      if (!tenantId) return [];
      const { data, error } = await fromTable("perfil_audit_log")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("created_at", { ascending: false })
        .limit(100);
      if (error) throw error;
      return (data || []) as PerfilAuditLog[];
    },
    enabled: !!tenantId,
  });

  const invalidate = () => {
    qc.invalidateQueries({ queryKey: ["perfis_acesso"] });
    qc.invalidateQueries({ queryKey: ["usuario_perfil_vinculos"] });
    // A listagem de Usuários lê os mesmos vínculos sob outra chave
    // ("usuarios-perfil-vinculos-lista"). Sem invalidar aqui, ela continua
    // servindo cache antigo e a coluna Perfil de Acesso aparece vazia até
    // alguém recarregar a página.
    qc.invalidateQueries({ queryKey: ["usuarios-perfil-vinculos-lista"] });
    qc.invalidateQueries({ queryKey: ["perfil_audit_log"] });
    qc.invalidateQueries({ queryKey: ["meu_perfil_vinculo"] });
    qc.invalidateQueries({ queryKey: ["minhas_perfil_permissoes"] });
  };

  // CRUD Perfis
  const createPerfil = useMutation({
    mutationFn: async (payload: Partial<PerfilAcesso> & { permissoes?: Partial<PerfilPermissao>[] }) => {
      if (!tenantId) throw new Error("Sem tenant");
      const { permissoes, ...perfilData } = payload;
      // Sanitize empty strings to null for timestamp/date fields
      if ('expira_em' in perfilData && !perfilData.expira_em) perfilData.expira_em = undefined;
      const nivelRisco = calcularNivelRisco(permissoes || []);
      const { data, error } = await fromTable("perfis_acesso")
        .insert({ ...perfilData, expira_em: perfilData.expira_em || null, nivel_risco: nivelRisco, tenant_id: tenantId, criado_por: user?.id, criado_por_nome: profile?.nome_completo })
        .select().single();
      if (error) throw error;
      if (permissoes?.length) {
        const perms = permissoes.map((p) => {
          const { id: _, created_at: __, updated_at: ___, ...pClean } = p as any;
          return {
            ...pClean,
            perfil_id: data.id,
            tenant_id: tenantId,
            is_sensivel: ACOES_DISPONIVEIS.find((a) => a.id === p.acao)?.sensivel || false,
          };
        });
        await fromTable("perfil_permissoes").insert(perms);
      }
      await logAuditPerfil(tenantId, data.id, "criacao", `Perfil "${data.nome}" criado`, null, perfilData, profile?.nome_completo);
      return data as PerfilAcesso;
    },
    onSuccess: () => { invalidate(); toast.success("Perfil criado com sucesso!"); },
    onError: (e: any) => toast.error("Erro ao criar perfil: " + e.message),
  });

  const updatePerfil = useMutation({
    mutationFn: async ({ id, permissoes, ...payload }: Partial<PerfilAcesso> & { id: string; permissoes?: Partial<PerfilPermissao>[] }) => {
      const { data: before } = await fromTable("perfis_acesso").select("*").eq("id", id).single();
      
      // Sanitize empty strings to null for timestamp/date fields
      const sanitizedPayload = { ...payload };
      if ('expira_em' in sanitizedPayload && !sanitizedPayload.expira_em) sanitizedPayload.expira_em = null as any;
      
      const nivelRisco = permissoes !== undefined ? calcularNivelRisco(permissoes) : undefined;
      const updatePayload = nivelRisco ? { ...sanitizedPayload, nivel_risco: nivelRisco } : sanitizedPayload;
      
      // Update basic profile info
      const { error: updateError } = await fromTable("perfis_acesso").update(updatePayload).eq("id", id);
      if (updateError) throw updateError;
      
      // Update permissions if provided
      if (permissoes !== undefined) {
        // Use a more robust approach for updating permissions
        try {
          // 1. Delete all existing permissions first to ensure clean state
          // Using supabase directly for more predictable behavior in delete
          const { error: deleteError } = await supabase
            .from("perfil_permissoes")
            .delete()
            .eq("perfil_id", id);
            
          if (deleteError) {
            console.error("Erro ao deletar permissões anteriores:", deleteError);
            throw deleteError;
          }
          
          if (permissoes.length > 0) {
            const permsToInsert = permissoes.map((p) => {
              // Ensure we don't send any fields that might cause primary key or metadata conflicts
              // We only want the core configuration fields
              return {
                perfil_id: id,
                tenant_id: tenantId!,
                modulo: p.modulo!,
                acao: p.acao as any,
                escopo: (p.escopo as any) || 'empresa_inteira',
                ativo: p.ativo !== false,
                is_sensivel: ACOES_DISPONIVEIS.find((a) => a.id === p.acao)?.sensivel || false,
                recurso: p.recurso || null,
              };
            });

            // 2. Insert new permissions
            const { error: insertError } = await supabase
              .from("perfil_permissoes")
              .insert(permsToInsert);
              
            if (insertError) {
              console.error("Erro ao inserir novas permissões:", insertError);
              throw insertError;
            }
          }
        } catch (error) {
          console.error("Falha crítica no sincronismo de permissões:", error);
          throw error;
        }
      }
      
      await logAuditPerfil(tenantId!, id, "edicao", `Perfil "${before?.nome}" editado`, before, updatePayload, profile?.nome_completo);
    },
    onSuccess: () => { 
      invalidate(); 
      toast.success("Perfil atualizado com sucesso!"); 
    },
    onError: (e: any) => {
      console.error("Erro ao atualizar perfil:", e);
      toast.error("Erro ao atualizar perfil: " + (e.message || "Ocorreu um erro inesperado"));
    },
  });

  const togglePerfilStatus = useMutation({
    mutationFn: async ({ id, ativo }: { id: string; ativo: boolean }) => {
      const { error } = await fromTable("perfis_acesso").update({ ativo }).eq("id", id);
      if (error) throw error;
      await logAuditPerfil(tenantId!, id, ativo ? "ativacao" : "inativacao", `Perfil ${ativo ? "ativado" : "inativado"}`, null, { ativo }, profile?.nome_completo);
    },
    onSuccess: () => { invalidate(); toast.success("Status atualizado!"); },
    onError: (e: any) => toast.error("Erro: " + e.message),
  });

  const clonarTemplate = useMutation({
    mutationFn: async (template: PerfilTemplate) => {
      if (!tenantId) throw new Error("Sem tenant");
      const { data, error } = await fromTable("perfis_acesso")
        .insert({
          tenant_id: tenantId,
          nome: template.nome,
          descricao: template.descricao,
          icone: template.icone,
          cor: template.cor,
          template_origem_id: template.id,
          tipo: "clonado",
          criado_por: user?.id,
          criado_por_nome: profile?.nome_completo,
        })
        .select().single();
      if (error) throw error;
      if (template.modulos_padrao?.length) {
        const perms = template.modulos_padrao.flatMap((m) =>
          m.acoes.map((acao) => ({
            perfil_id: data.id,
            tenant_id: tenantId,
            modulo: m.modulo,
            recurso: m.recurso || null,
            acao,
            escopo: m.escopo,
            is_sensivel: ACOES_DISPONIVEIS.find((a) => a.id === acao)?.sensivel || false,
          }))
        );
        await fromTable("perfil_permissoes").insert(perms);
      }
      await logAuditPerfil(tenantId, data.id, "clonagem", `Template "${template.nome}" clonado como perfil`, null, { template_id: template.id }, profile?.nome_completo);
      return data;
    },
    onSuccess: () => { invalidate(); toast.success("Template clonado como perfil!"); },
    onError: (e: any) => toast.error("Erro ao clonar: " + e.message),
  });

  // Vínculos
  const vincularPerfil = useMutation({
    mutationFn: async (payload: {
      usuario_id: string;
      perfil_id: string;
      empresa_id?: string;
      observacao?: string;
      expira_em?: string;
      is_perfil_principal?: boolean;
    }) => {
      if (!tenantId) throw new Error("Sem tenant");
      const { data, error } = await fromTable("usuario_perfil_vinculos")
        .insert({ ...payload, tenant_id: tenantId, atribuido_por: user?.id, atribuido_por_nome: profile?.nome_completo })
        .select().single();
      if (error) throw error;
      await logAuditPerfil(tenantId, payload.perfil_id, "vinculacao", `Perfil vinculado ao usuário`, null, payload, profile?.nome_completo);
      return data;
    },
    onSuccess: () => { invalidate(); toast.success("Perfil vinculado ao usuário!"); },
    onError: (e: any) => toast.error("Erro: " + e.message),
  });

  const desvincularPerfil = useMutation({
    mutationFn: async (vinculoId: string) => {
      const { error } = await fromTable("usuario_perfil_vinculos").update({ ativo: false }).eq("id", vinculoId);
      if (error) throw error;
      await logAuditPerfil(tenantId!, null, "desvinculacao", `Vínculo de perfil removido`, null, { vinculo_id: vinculoId }, profile?.nome_completo);
    },
    onSuccess: () => { invalidate(); toast.success("Vínculo removido!"); },
    onError: (e: any) => toast.error("Erro: " + e.message),
  });

  return {
    templates, loadingTemplates,
    perfis, loadingPerfis,
    vinculos, loadingVinculos,
    auditLogs, loadingAuditLogs,
    createPerfil, updatePerfil, togglePerfilStatus, clonarTemplate,
    vincularPerfil, desvincularPerfil,
  };
}
