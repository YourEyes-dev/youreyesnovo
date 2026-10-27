import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { useColaboradoresEncerrados } from "./useColaboradoresEncerrados";
import { colaboradorAtivo, type IndiceEncerrados } from "@/lib/colaboradorAtivo";

export interface PendenciaItem {
  id: string;
  label: string;
  sublabel?: string;
  acao: string;
}

export interface PendenciaGroup {
  key: string;
  title: string;
  count: number;
  items: PendenciaItem[];
  path: string;
  priority: "high" | "medium" | "low";
}

export function usePendencias() {
  const { tenantId } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  // Índice de colaboradores encerrados (desligados/reprovados): os lembretes do
  // Início não podem apontar para quem já saiu. As linhas desses módulos
  // permanecem após o desligamento, então o filtro de "ativo" é feito aqui.
  const { indice } = useColaboradoresEncerrados();

  return useQuery({
    queryKey: ["pendencias-dashboard", tenantId, empresaAtivaId, indiceChave(indice)],
    queryFn: async (): Promise<PendenciaGroup[]> => {
      if (!tenantId) return [];

      const empresaFilter = empresaAtivaId ? { empresa_id: empresaAtivaId } : {};

      // Documentos de admissão: filtramos NO BANCO as admissões encerradas
      // (desligado/reprovado) pelo join, e escopamos pela empresa ativa via
      // admissoes.empresa_id (a tabela de documentos não tem empresa_id).
      let docQuery = supabase
        .from("admissao_documentos")
        .select("id, nome, admissao_id, status, admissoes!inner(nome_completo, status, empresa_id)")
        .eq("tenant_id", tenantId)
        .eq("status", "pendente")
        .not("admissoes.status", "in", "(desligado,reprovado)");
      if (empresaAtivaId) docQuery = docQuery.eq("admissoes.empresa_id", empresaAtivaId);

      const [feriasRes, docRes, ajustesRes, avalRes, desligRes, impEmpRes, afastPendRes, alertaSaudeRes] = await Promise.all([
        // Férias pendentes de aprovação
        supabase
          .from("ferias_solicitacoes")
          .select("id, colaborador_nome, colaborador_cpf, data_inicio, data_fim, dias_solicitados, status")
          .eq("tenant_id", tenantId)
          .eq("status", "pendente")
          .match(empresaFilter)
          .order("created_at", { ascending: false })
          .limit(50),

        // Documentos de admissão pendentes (apenas de admissões ativas/em andamento)
        docQuery.limit(50),

        // Ajustes de ponto pendentes
        supabase
          .from("ponto_ajustes")
          .select("id, colaborador_nome, colaborador_cpf, tipo_ajuste, data_referencia, motivo, status")
          .eq("tenant_id", tenantId)
          .eq("status", "pendente")
          .match(empresaFilter)
          .order("created_at", { ascending: false })
          .limit(50),

        // Avaliações pendentes
        supabase
          .from("avaliacao_respostas")
          .select("id, avaliado_nome, tipo_avaliador, status, ciclo_id")
          .eq("tenant_id", tenantId)
          .eq("status", "pendente")
          .order("created_at", { ascending: false })
          .limit(50),

        // Desligamentos em andamento (aqui o desligado APARECE de propósito:
        // a pendência é concluir o processo de desligamento).
        supabase
          .from("admissoes")
          .select("id, nome_completo, cargo, data_desligamento, motivo_desligamento, status")
          .eq("tenant_id", tenantId)
          .eq("status", "desligado")
          .match(empresaFilter)
          .order("updated_at", { ascending: false })
          .limit(50),

        // Pendências de importação de empresas (duplicidades de CNPJ)
        (supabase as any)
          .from("empresa_import_pendencias")
          .select("id, cnpj, razao_social_planilha, razao_social_existente, linha_planilha, arquivo_nome, motivo")
          .eq("tenant_id", tenantId)
          .eq("status", "pendente")
          .order("created_at", { ascending: false })
          .limit(50),

        // Pendências de afastamentos / CAT
        (() => {
          let q = (supabase as any)
            .from("afastamentos_pendencias")
            .select("id, tipo_pendencia, descricao, prioridade, status, afastamentos!inner(colaborador_nome, colaborador_cpf, empresa_id, tenant_id)")
            .eq("tenant_id", tenantId)
            .eq("status", "pendente");
          if (empresaAtivaId) q = q.eq("afastamentos.empresa_id", empresaAtivaId);
          return q.order("created_at", { ascending: false }).limit(50);
        })(),

        // Alertas de saúde não resolvidos (ex.: estabilidade vencendo, encaminhamento INSS).
        // alertas_saude não tem coluna colaborador_cpf — o filtro de ativo cai no nome.
        (supabase as any)
          .from("alertas_saude")
          .select("id, tipo, titulo, descricao, colaborador_nome, prioridade, resolvido")
          .eq("tenant_id", tenantId)
          .eq("resolvido", false)
          .order("created_at", { ascending: false })
          .limit(50),
      ]);

      // Esconde, dos lembretes, quem já não é colaborador ativo. Documentos já
      // vêm filtrados do banco; os demais módulos são filtrados aqui (ligam ao
      // colaborador por CPF/nome, não por FK de admissão).
      const ativo = (ref: { cpf?: string | null; nome?: string | null }) => colaboradorAtivo(indice, ref);

      const ferias = (feriasRes.data || []).filter((f: any) => ativo({ cpf: f.colaborador_cpf, nome: f.colaborador_nome }));
      const docs = docRes.data || [];
      const ajustes = (ajustesRes.data || []).filter((a: any) => ativo({ cpf: a.colaborador_cpf, nome: a.colaborador_nome }));
      const avals = (avalRes.data || []).filter((a: any) => ativo({ nome: a.avaliado_nome }));
      const desligs = desligRes.data || [];
      const impEmps = (impEmpRes as any).data || [];
      const afastPends = ((afastPendRes as any).data || []).filter((r: any) => ativo({ cpf: r.afastamentos?.colaborador_cpf, nome: r.afastamentos?.colaborador_nome }));
      const alertasSaude = ((alertaSaudeRes as any).data || []).filter((a: any) => ativo({ nome: a.colaborador_nome }));

      const tipoAvaliadorLabel: Record<string, string> = {
        gestor: "Avaliação do Gestor",
        auto: "Autoavaliação",
        par: "Avaliação de Par",
        cliente_interno: "Avaliação de Cliente Interno",
      };

      const tipoPendenciaLabel: Record<string, string> = {
        cat: "CAT pendente",
        inss: "Encaminhamento INSS",
        s2210: "Evento eSocial S-2210",
        s2230: "Evento eSocial S-2230",
        aso_retorno: "ASO de retorno",
        ntep: "Análise NTEP",
        entrevista_retorno: "Entrevista de retorno",
        revisao_sst: "Revisão SST",
      };

      return [
        {
          key: "ferias",
          title: "Férias pendentes",
          count: ferias.length,
          path: "/ferias",
          priority: "high" as const,
          items: ferias.map((f) => ({
            id: f.id,
            label: f.colaborador_nome,
            sublabel: `${f.dias_solicitados} dias • ${f.data_inicio} a ${f.data_fim}`,
            acao: "Aprovar ou recusar solicitação de férias",
          })),
        },
        {
          key: "documentos",
          title: "Documentos pendentes",
          count: docs.length,
          path: "/documentos",
          priority: "high" as const,
          items: docs.map((d: any) => ({
            id: d.id,
            label: d.nome,
            sublabel: d.admissoes?.nome_completo || "Colaborador",
            acao: "Solicitar envio ou aprovar documento",
          })),
        },
        {
          key: "ajustes",
          title: "Ajustes de ponto",
          count: ajustes.length,
          path: "/ponto",
          priority: "medium" as const,
          items: ajustes.map((a) => ({
            id: a.id,
            label: a.colaborador_nome,
            sublabel: `${a.tipo_ajuste} • ${a.data_referencia}`,
            acao: "Aprovar ou recusar ajuste de ponto",
          })),
        },
        {
          key: "avaliacoes",
          title: "Avaliações pendentes",
          count: avals.length,
          path: "/avaliacoes",
          priority: "low" as const,
          items: avals.map((a) => ({
            id: a.id,
            label: a.avaliado_nome,
            sublabel: tipoAvaliadorLabel[a.tipo_avaliador] || a.tipo_avaliador,
            acao: "Responder avaliação de desempenho",
          })),
        },
        {
          key: "desligamentos",
          title: "Desligamentos",
          count: desligs.length,
          path: "/colaboradores",
          priority: "medium" as const,
          items: desligs.map((d) => ({
            id: d.id,
            label: d.nome_completo,
            sublabel: `${d.cargo || "—"} • ${d.motivo_desligamento || "Sem motivo informado"}`,
            acao: "Concluir processo de desligamento",
          })),
        },
        {
          key: "importacao_empresas",
          title: "Importação de empresas (duplicidades)",
          count: impEmps.length,
          path: "/empresa?tab=importar",
          priority: "medium" as const,
          items: impEmps.map((p: any) => ({
            id: p.id,
            label: `CNPJ ${p.cnpj} — ${p.razao_social_planilha || "sem razão social"}`,
            sublabel: p.motivo === 'cnpj_repetido_planilha'
              ? `Repetido na planilha${p.arquivo_nome ? ` • ${p.arquivo_nome}` : ''}${p.linha_planilha ? ` • linha ${p.linha_planilha}` : ''}`
              : `Já cadastrado como "${p.razao_social_existente || '—'}"${p.arquivo_nome ? ` • ${p.arquivo_nome}` : ''}${p.linha_planilha ? ` • linha ${p.linha_planilha}` : ''}`,
            acao: "Revisar duplicidade na importação de empresas",
          })),
        },
        {
          key: "afastamentos",
          title: "Afastamentos / CAT",
          count: afastPends.length,
          path: "/atestados",
          priority: "high" as const,
          items: afastPends.map((r: any) => ({
            id: r.id,
            label: r.afastamentos?.colaborador_nome || "Colaborador",
            sublabel: tipoPendenciaLabel[r.tipo_pendencia] || r.tipo_pendencia,
            acao: "Tratar pendência do afastamento",
          })),
        },
        {
          key: "alertas_saude",
          title: "Alertas de Saúde",
          count: alertasSaude.length,
          path: "/atestados",
          priority: "high" as const,
          items: alertasSaude.map((a: any) => ({
            id: a.id,
            label: a.colaborador_nome || "Colaborador",
            sublabel: a.titulo || a.descricao || a.tipo,
            acao: "Revisar alerta de saúde",
          })),
        },
      ];
    },
    enabled: !!tenantId,
    staleTime: 1000 * 60 * 3,
  });
}

/** Chave estável do índice para o queryKey (reconsulta quando a lista de encerrados muda). */
function indiceChave(indice: IndiceEncerrados): string {
  return `${indice.cpfsEncerrados.size}:${indice.nomesEncerrados.size}:${indice.cpfsAtivos.size}:${indice.nomesAtivos.size}`;
}
