import { useQuery, useMutation, useQueryClient, keepPreviousData } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { supabasePublic } from "@/lib/supabasePublic";
import { useAuthContext } from "@/contexts/AuthContext";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";
import { type CampanhaPsicossocial,
  type ConvitePsicossocial,
  type RespostaPsicossocial,
  type NovaCampanha,
  type GerarConvitesInput,
  type EstatisticasCampanha,
  type EstatisticasMultiCampanha,
  type EstatisticaCampanhaResumo,
  type GrupoEstatistica,
  type IndicadoresPsicossociais,
  type RadarDimensao,
  type InstrumentoPsicossocial,
  calcularIPSClassificacao,
  isEntrevistaInstrumento,
} from "@/types/psicossocial";
import {
  calcularIPSInstrumento,
  calcularIRPS,
  getDimensoesByInstrumento,
  getLabelNivelIRPS,
  calcularIndicePonderado,
  PESOS_IRPS,
  PESOS_IBO,
  PESOS_IBD,
  PESOS_IREC,
  PESOS_ICOP,
  PESOS_INOT,
} from "@/data/instrumentos";
import { BLOCOS_DINAMICOS } from "@/types/psicossocial";
import type { DimensaoInstrumento } from "@/data/instrumentos";

// Gerar token único
function gerarToken(): string {
  return crypto.randomUUID().replace(/-/g, '').slice(0, 12).toUpperCase();
}

interface ContagemParticipacaoCampanhaInput {
  temGHE: boolean;
  isEntrevistaGuiada: boolean;
  elegiveisGHE: number;
  totalConvites: number;
  totalParticipacoes: number;
  totalRespostas: number;
  totalEntrevistas: number;
  colaboradoresAtivos: number;
  concluidosConvites: number;
  respondidosParticipacoes: number;
  entrevistasConcluidas: number;
}

export function calcularContagemParticipacaoCampanha({
  temGHE,
  isEntrevistaGuiada,
  elegiveisGHE,
  totalConvites,
  totalParticipacoes,
  totalRespostas,
  totalEntrevistas,
  colaboradoresAtivos,
  concluidosConvites,
  respondidosParticipacoes,
  entrevistasConcluidas,
}: ContagemParticipacaoCampanhaInput): { concluidos: number; total: number } {
  const respostasEfetivas = isEntrevistaGuiada
    ? Math.max(totalRespostas, entrevistasConcluidas)
    : totalRespostas;

  const concluidos = temGHE
    ? respostasEfetivas
    : Math.max(respostasEfetivas, concluidosConvites, respondidosParticipacoes);
  const total = temGHE
    ? Math.max(elegiveisGHE, respostasEfetivas)
    : Math.max(totalConvites, totalParticipacoes, totalRespostas, totalEntrevistas, colaboradoresAtivos);

  return { concluidos, total };
}

/**
 * Calcular indicadores psicossociais a partir das respostas.
 *
 * SIPRO: usa calcularIRPS() — escala 1-5, fórmula ((média-1)/4)×100, quanto maior = maior risco.
 * Demais: usa calcularIPSInstrumento() — escala 0-4, quanto maior = melhor condição.
 *
 * blocosDinamicos: IDs dos blocos CET ativos na campanha (ex: ['cet_noturno']).
 * Exclusivos do SIPRO — adicionam dimensões ao cálculo e habilitam INOT-S.
 */
export function calcularIndicadores(
  respostas: Record<string, number>,
  instrumento: InstrumentoPsicossocial = 'sipro',
  blocosDinamicos?: string[]
): IndicadoresPsicossociais {
  const validKeys = ['copsoq', 'copsoq2br', 'hse', 'proart', 'sipro'] as const;
  type ValidKey = typeof validKeys[number];
  const instrumentoKey: ValidKey = validKeys.includes(instrumento as ValidKey)
    ? instrumento as ValidKey
    : 'sipro';
  const dimensoesBase = getDimensoesByInstrumento(instrumentoKey);

  if (instrumento === 'sipro') {
    // ── Injetar dimensões CET quando blocos estão ativos ───────────────────
    const dimensoesCET: DimensaoInstrumento[] = (blocosDinamicos && blocosDinamicos.length > 0)
      ? BLOCOS_DINAMICOS
          .filter(b => blocosDinamicos.includes(b.id))
          .map(b => ({
            id: b.id,
            nome: b.titulo,
            tipo: 'risco' as const,
            descricao: b.descricao,
            normas: b.perguntas[0]?.mapeamento ?? ['NR-01', 'ISO 45003'],
            perguntas: b.perguntas.map(p => ({
              id: p.id,
              texto: p.texto,
              invertida: p.invertida ?? false,
              peso: 1,
              dimensao: b.id,
            })),
          }))
      : [];

    const dimensoes = [...dimensoesBase, ...dimensoesCET];

    // ── SIPRO: modelo estatístico próprio ──────────────────────────────────
    const resultado = calcularIRPS(respostas, dimensoes);

    const radar: RadarDimensao[] = dimensoes.map(dim => ({
      subject: dim.nome,
      value: resultado.porDimensao[dim.id]?.score ?? 0,
      fullMark: 100,
    }));

    const nivelIrpsMap: Record<string, 'baixo' | 'moderado' | 'alto' | 'critico'> = {
      favoravel: 'baixo',
      atencao: 'moderado',
      moderado: 'alto',
      elevado: 'critico',
    };

    const detalhes = dimensoes.map(dim => ({
      bloco: dim.nome,
      media: resultado.porDimensao[dim.id]?.score ?? 0,
      nivel: (nivelIrpsMap[resultado.porDimensao[dim.id]?.nivel ?? 'atencao'] ?? 'moderado') as 'baixo' | 'moderado' | 'alto' | 'critico',
    }));

    const irps = calcularIndicePonderado(resultado.porDimensao, PESOS_IRPS);
    const iboS = calcularIndicePonderado(resultado.porDimensao, PESOS_IBO);
    const ibdS = calcularIndicePonderado(resultado.porDimensao, PESOS_IBD);
    const irecS = calcularIndicePonderado(resultado.porDimensao, PESOS_IREC);
    const icopS = calcularIndicePonderado(resultado.porDimensao, PESOS_ICOP);

    // INOT-S: calculado somente quando bloco cet_noturno está ativo
    const inotS = (blocosDinamicos?.includes('cet_noturno'))
      ? calcularIndicePonderado(resultado.porDimensao, PESOS_INOT)
      : undefined;

    let classificacao: ReturnType<typeof calcularIPSClassificacao>;
    if (irps <= 25) classificacao = 'saudavel';
    else if (irps <= 50) classificacao = 'estavel';
    else if (irps <= 75) classificacao = 'atencao';
    else if (irps <= 90) classificacao = 'risco';
    else classificacao = 'critico';

    return {
      IPS: 100 - irps, // IPS = Índice de Proteção (alto = saudável)
      IPS_classificacao: classificacao,
      IRP_S: irps,
      IBO_S: iboS,
      IBD_S: ibdS,
      IREC_S: irecS,
      ICOP_S: icopS,
      INOT_S: inotS,
      detalhes,
      radar,
    };
  }

  // ── Instrumentos padrão: COPSOQ, HSE, PROART (sem suporte a CET) ──────────
  const { ips, porDimensao } = calcularIPSInstrumento(respostas, dimensoesBase);
  const classificacao = calcularIPSClassificacao(ips);

  const nivelMap: Record<string, 'baixo' | 'moderado' | 'alto' | 'critico'> = {
    otimo: 'baixo',
    bom: 'moderado',
    atencao: 'alto',
    critico: 'critico',
  };

  const detalhes = dimensoesBase.map(dim => ({
    bloco: dim.nome,
    media: porDimensao[dim.id]?.score ?? 50,
    nivel: (nivelMap[porDimensao[dim.id]?.nivel ?? 'moderado'] ?? 'moderado') as 'baixo' | 'moderado' | 'alto' | 'critico',
  }));

  const radar: RadarDimensao[] = dimensoesBase.map(dim => ({
    subject: dim.nome,
    value: porDimensao[dim.id]?.score ?? 50,
    fullMark: 100,
  }));

  return {
    IPS: ips,
    IPS_classificacao: classificacao,
    // B1 (corrigido): instrumentos padrão não têm os sub-índices próprios do
    // SIPRO. Expõe o risco geral = 100 - IPS (alto=pior), coerente com a escala
    // de risco desses campos. Antes gravava = IPS (saúde) sob nome de risco.
    IRP_S: 100 - ips,
    IBO_S: 100 - ips,
    IBD_S: 100 - ips,
    IREC_S: 100 - ips,
    ICOP_S: 100 - ips,
    detalhes,
    radar,
  };
}


export function usePsicossocial() {
  const { tenantId, user, profile } = useAuthContext();
  const { empresaAtivaId } = useEmpresaAtiva();
  const queryClient = useQueryClient();

  // ==================== CAMPANHAS ====================

  // Buscar todas as campanhas (filtradas por empresa ativa)
  const { data: campanhas = [], isLoading: isLoadingCampanhas, refetch: refetchCampanhas } = useQuery({
    queryKey: ["psicossocial-campanhas", tenantId, empresaAtivaId],
    queryFn: async (): Promise<CampanhaPsicossocial[]> => {
      if (!tenantId) return [];

      let query = supabase
        .from("questionario_psicossocial_campanhas")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("created_at", { ascending: false });

      if (empresaAtivaId) {
        query = query.eq("empresa_id", empresaAtivaId);
      }

      const { data, error } = await query;

      if (error) throw error;
      return (data || []).map(c => ({
        ...c,
        radar_data: c.radar_data as unknown as RadarDimensao[] | undefined,
        situacoes_trabalho: (c as any).situacoes_trabalho as unknown as import("@/types/psicossocial").SituacaoTrabalhoCampanha[] | undefined,
      })) as unknown as CampanhaPsicossocial[];
    },
    enabled: !!tenantId,
    // Mantém os dados anteriores enquanto a queryKey muda (empresa/tenant
    // assentando após o login). Sem isto, isLoading voltava a true a cada
    // troca de chave e o PsicossocialDashboard caía no early-return do spinner
    // — desmontando QUALQUER diálogo aberto (era o que fechava o formulário de
    // "Nova Campanha" segundos depois de abrir). Com placeholderData o spinner
    // só aparece no 1º carregamento; trocas seguintes não desmontam a tela.
    placeholderData: keepPreviousData,
  });

  // Criar nova campanha
  const criarCampanha = useMutation({
    mutationFn: async (dados: NovaCampanha): Promise<CampanhaPsicossocial> => {
      if (!tenantId || !user) throw new Error("Usuário não autenticado");

      const { data, error } = await supabase
        .from("questionario_psicossocial_campanhas")
        .insert({
          tenant_id: tenantId,
          empresa_id: empresaAtivaId || null,
          nome: dados.nome,
          descricao: dados.descricao,
          tipo: dados.tipo || 'regular',
          instrumento: dados.instrumento || 'copsoq',
          tipo_instrumento: dados.tipo_instrumento || 'questionario',
          periodicidade: dados.periodicidade,
          data_inicio: dados.data_inicio,
          data_fim: dados.data_fim,
          anonimo: dados.anonimo,
          permite_identificacao_voluntaria: dados.permite_identificacao_voluntaria ?? true,
          mensagem_institucional: dados.mensagem_institucional,
          politica_uso_dados: dados.politica_uso_dados,
          departamentos_ids: dados.departamentos_ids,
          cargos_ids: dados.cargos_ids,
          ghe_ids: dados.ghe_ids ?? [],
          blocos_dinamicos: dados.blocos_dinamicos,
          situacoes_trabalho: dados.situacoes_trabalho ?? [],
          motivo_extraordinaria: dados.motivo_extraordinaria,
          evento_gatilho_tipo: dados.evento_gatilho_tipo,
          evento_gatilho_id: dados.evento_gatilho_id,
          campanha_anterior_id: dados.campanha_anterior_id,
          criado_por: user.id,
          criado_por_nome: profile?.nome_completo,
          status: 'rascunho',
          token_publico: Array.from(crypto.getRandomValues(new Uint8Array(12)))
            .map(b => b.toString(16).padStart(2, '0'))
            .join(''),
        } as any)
        .select()
        .single();

      if (error) throw error;
      return {
        ...data,
        radar_data: (data as any).radar_data as unknown as RadarDimensao[] | undefined,
        situacoes_trabalho: (data as any).situacoes_trabalho as unknown as import("@/types/psicossocial").SituacaoTrabalhoCampanha[] | undefined,
      } as unknown as CampanhaPsicossocial;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["psicossocial-campanhas"] });
      toast.success("Campanha criada com sucesso!");
    },
    onError: (error) => {
      toast.error(`Erro ao criar campanha: ${error.message}`);
    },
  });

  // Atualizar status da campanha
  // GAP 1: Ao encerrar, dispara exportação automática para GRO
  const atualizarStatusCampanha = useMutation({
    mutationFn: async ({ id, status }: { id: string; status: CampanhaPsicossocial['status'] }) => {
      const { error } = await supabase
        .from("questionario_psicossocial_campanhas")
        .update({ status })
        .eq("id", id);

      if (error) throw error;

      // GAP 1 — Auto-export GRO ao encerrar campanha
      if (status === 'encerrada') {
        try {
          // Buscar dados completos da campanha para exportar
          const { data: campanha } = await fromTable("questionario_psicossocial_campanhas")
            .select("*")
            .eq("id", id)
            .single();

          const minRespostas =isEntrevistaInstrumento(campanha.tipo_instrumento) ? 1 : 5;
          if (campanha?.radar_data && (campanha.total_respostas ?? 0) >= minRespostas) {
            const situacoes = campanha.situacoes_trabalho ?? [];

            if (situacoes.length > 0) {
              // Verificar se já foi exportado
              const { data: logExist } = await fromTable("gro_exportacoes_log")
                .select("id")
                .eq("campanha_id", id)
                .maybeSingle();

              if (!logExist) {
                const { psicossocialDimensaoParaGRO } = await import("@/types/gro");
                const isSipro = campanha.instrumento === 'sipro';
                const radar = campanha.radar_data as { subject: string; value: number }[];

                const dimensoesCriticas = radar.filter(d => {
                  const risco = isSipro ? d.value : 100 - d.value;
                  return risco >= 35;
                });

                if (dimensoesCriticas.length > 0) {
                  const riscos = situacoes.flatMap((sit: { setorNome: string; funcaoNome: string }) =>
                    dimensoesCriticas.map((d: { subject: string; value: number }) => ({
                      tenant_id: campanha.tenant_id,
                      empresa_id: campanha.empresa_id ?? null,
                      subtipo: 'psicossocial' as const,
                      fonte: 'psicossocial' as const,
                      titulo: `${d.subject} — ${sit.funcaoNome} (${sit.setorNome})`,
                      descricao: `Exportação automática ao encerrar campanha "${campanha.nome}". Dimensão: ${d.subject}. Score: ${d.value}%.`,
                      dimensao_psicossocial: d.subject,
                      score_dimensao: d.value,
                      // Fase 0.1: severidade do catálogo + nível da matriz única (não do score)
                      ...psicossocialDimensaoParaGRO(d.subject, d.value, isSipro),
                      campanha_id: id,
                      setor: sit.setorNome,
                      cargo: sit.funcaoNome,
                      base_normativa: ['NR-01', 'NR-17', 'ISO 45003'],
                      status_gro: 'identificado' as const,
                      ativo: true,
                    }))
                  );

                  await fromTable("gro_riscos").insert(riscos);

                  // Registrar log de exportação
                  await fromTable("gro_exportacoes_log").insert({
                    tenant_id: campanha.tenant_id,
                    campanha_id: id,
                    riscos_gerados: riscos.length,
                    status: 'sucesso',
                  });
                }
              }
            }
          }
        } catch (exportErr) {
          // Não falhar o encerramento se a exportação der erro
          console.warn('[GAP-1] Auto-export GRO falhou:', exportErr);
        }
      }
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ["psicossocial-campanhas"] });
      if (variables.status === 'encerrada') {
        toast.success("Campanha encerrada! Riscos exportados automaticamente ao GRO.");
      } else {
        toast.success("Status atualizado!");
      }
    },
    onError: (error) => {
      toast.error(`Erro ao atualizar: ${error.message}`);
    },
  });

  // Editar campanha existente
  const editarCampanha = useMutation({
    mutationFn: async ({ id, dados }: { id: string; dados: Partial<NovaCampanha> }): Promise<CampanhaPsicossocial> => {
      if (!tenantId) throw new Error("Tenant não identificado");

      const { data, error } = await supabase
        .from("questionario_psicossocial_campanhas")
        .update({
          nome: dados.nome,
          descricao: dados.descricao,
          tipo: dados.tipo,
          instrumento: dados.instrumento,
          periodicidade: dados.periodicidade,
          data_inicio: dados.data_inicio,
          data_fim: dados.data_fim,
          anonimo: dados.anonimo,
          permite_identificacao_voluntaria: dados.permite_identificacao_voluntaria,
          mensagem_institucional: dados.mensagem_institucional,
          politica_uso_dados: dados.politica_uso_dados,
          departamentos_ids: dados.departamentos_ids,
          cargos_ids: dados.cargos_ids,
          ghe_ids: dados.ghe_ids,
          blocos_dinamicos: dados.blocos_dinamicos,
          situacoes_trabalho: dados.situacoes_trabalho as any,
          motivo_extraordinaria: dados.motivo_extraordinaria,
          evento_gatilho_tipo: dados.evento_gatilho_tipo,
          evento_gatilho_id: dados.evento_gatilho_id,
          campanha_anterior_id: dados.campanha_anterior_id,
          updated_at: new Date().toISOString(),
        } as any)
        .eq("id", id)
        .select()
        .single();

      if (error) throw error;
      return {
        ...data,
        radar_data: (data as any).radar_data as unknown as RadarDimensao[] | undefined,
        situacoes_trabalho: (data as any).situacoes_trabalho as unknown as import("@/types/psicossocial").SituacaoTrabalhoCampanha[] | undefined,
      } as unknown as CampanhaPsicossocial;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["psicossocial-campanhas"] });
      toast.success("Campanha atualizada com sucesso!");
    },
    onError: (error) => {
      toast.error(`Erro ao atualizar campanha: ${error.message}`);
    },
  });

  // ==================== CONVITES ====================

  // Buscar convites de uma campanha
  const buscarConvites = async (campanhaId: string): Promise<ConvitePsicossocial[]> => {
    const { data, error } = await supabase
      .from("questionario_psicossocial_convites")
      .select("*")
      .eq("campanha_id", campanhaId)
      .order("created_at", { ascending: false });

    if (error) throw error;
    return (data || []) as ConvitePsicossocial[];
  };

  // Hook para convites de uma campanha específica
  const useConvitesCampanha = (campanhaId?: string) => {
    return useQuery({
      queryKey: ["psicossocial-convites", campanhaId],
      queryFn: () => buscarConvites(campanhaId!),
      enabled: !!campanhaId,
    });
  };

  // Gerar convites para colaboradores
  const gerarConvites = useMutation({
    mutationFn: async (input: GerarConvitesInput): Promise<ConvitePsicossocial[]> => {
      if (!tenantId) throw new Error("Tenant não identificado");

      // Buscar a campanha para pegar o tenant_id
      const { data: campanha, error: erroC } = await supabase
        .from("questionario_psicossocial_campanhas")
        .select("tenant_id")
        .eq("id", input.campanha_id)
        .single();

      if (erroC) throw erroC;

      const convites = input.colaboradores.map(colab => ({
        tenant_id: campanha.tenant_id,
        campanha_id: input.campanha_id,
        colaborador_id: colab.id || null,
        colaborador_nome: colab.nome,
        colaborador_cpf: colab.cpf || null,
        colaborador_cargo: colab.cargo || null,
        colaborador_departamento: colab.departamento || null,
        token: gerarToken(),
        status: 'pendente' as const,
        enviado_via: input.enviado_via || 'link',
        enviado_em: new Date().toISOString(),
      }));

      const { data, error } = await supabase
        .from("questionario_psicossocial_convites")
        .insert(convites)
        .select();

      if (error) throw error;
      return (data || []) as ConvitePsicossocial[];
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ["psicossocial-convites", variables.campanha_id] });
      toast.success("Convites gerados com sucesso!");
    },
    onError: (error) => {
      toast.error(`Erro ao gerar convites: ${error.message}`);
    },
  });

  // ==================== RESPOSTAS ====================

  // Buscar respostas de uma campanha
  const buscarRespostas = async (campanhaId: string): Promise<RespostaPsicossocial[]> => {
    const { data, error } = await supabase
      .from("questionario_psicossocial_respostas")
      .select("*")
      .eq("campanha_id", campanhaId)
      .order("created_at", { ascending: false });

    if (error) throw error;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return (data || []).map((item: any) => ({
      ...item,
      respostas: item.respostas as Record<string, number>,
      indicadores: item.indicadores as IndicadoresPsicossociais | undefined,
    })) as RespostaPsicossocial[];
  };

  // Hook para respostas de uma campanha
  const useRespostasCampanha = (campanhaId?: string) => {
    return useQuery({
      queryKey: ["psicossocial-respostas", campanhaId],
      queryFn: () => buscarRespostas(campanhaId!),
      enabled: !!campanhaId,
    });
  };

  // ==================== ESTATÍSTICAS ====================

  // Calcular estatísticas de uma campanha
  const calcularEstatisticas = async (campanhaId: string): Promise<EstatisticasCampanha> => {
    // Universo elegível: colaboradores ativos da empresa (admissões concluídas, não inativos).
    // É a base correta para Pendentes e Taxa de Adesão em campanhas anônimas de Link Geral,
    // que não têm convites nominais.
    let elegiveisQuery = supabase
      .from("admissoes")
      .select("id", { count: "exact", head: true })
      .eq("tenant_id", tenantId)
      .eq("status", "concluido")
      .or("inativo.is.null,inativo.eq.false");
    if (empresaAtivaId) elegiveisQuery = elegiveisQuery.eq("empresa_id", empresaAtivaId);

    const [convites, respostas, participacoesRes, entrevistasRes, campanhaRes, elegiveisRes] = await Promise.all([
      buscarConvites(campanhaId),
      buscarRespostas(campanhaId),
      supabase
        .from("psicossocial_participacoes")
        .select("id,respondido")
        .eq("campanha_id", campanhaId),
      supabase
        .from("psicossocial_entrevistas")
        .select("id,status,resumo_ia")
        .eq("campanha_id", campanhaId),
      supabase
        .from("questionario_psicossocial_campanhas")
        .select("tipo_instrumento, ghe_ids")
        .eq("id", campanhaId)
        .single(),
      elegiveisQuery,
    ]);

    const colaboradoresAtivos = elegiveisRes.count ?? 0;
    const campanhaData = campanhaRes.data as { tipo_instrumento?: string; ghe_ids?: string[] } | null;

    // ── Universo via GHE ──────────────────────────────────────────────
    // Quando a campanha está vinculada a um/mais GHE, o universo elegível
    // (denominador da taxa) deve ser o nº de funcionários DESSES GHE, e não
    // o quadro inteiro da empresa. GHE agrupa cargos (psicossocial_ghe_cargos);
    // o colaborador pertence ao GHE pelo cargo que ocupa em admissoes.
    // Como ninguém está em mais de um GHE, a soma é direta (sem dedupe).
    const gheIds = (campanhaData?.ghe_ids || []) as string[];
    const temGHE = gheIds.length > 0;
    let elegiveisGHE = 0;
    if (temGHE) {
      const { data: ghePairsData } = await supabase
        .from("psicossocial_ghe_cargos")
        .select("cargo_id, departamento_id")
        .in("ghe_id", gheIds);
      const ghePairs = (ghePairsData || []) as { cargo_id: string | null; departamento_id: string | null }[];

      const cargoIds = Array.from(new Set(ghePairs.map(p => p.cargo_id).filter(Boolean) as string[]));
      const deptoIds = Array.from(new Set(ghePairs.map(p => p.departamento_id).filter(Boolean) as string[]));

      const [cargosRes, deptosRes] = await Promise.all([
        cargoIds.length > 0
          ? supabase.from("cargos").select("id, nome").in("id", cargoIds)
          : Promise.resolve({ data: [] as { id: string; nome: string }[] }),
        deptoIds.length > 0
          ? supabase.from("departamentos").select("id, nome").in("id", deptoIds)
          : Promise.resolve({ data: [] as { id: string; nome: string }[] }),
      ]);
      const cargosMap = Object.fromEntries(((cargosRes.data || []) as { id: string; nome: string }[]).map(c => [c.id, c.nome]));
      const deptosMap = Object.fromEntries(((deptosRes.data || []) as { id: string; nome: string }[]).map(d => [d.id, d.nome]));

      // Conjunto de chaves "cargo|departamento" normalizadas
      const pairsKey = new Set(
        ghePairs.map(p => {
          const c = p.cargo_id ? (cargosMap[p.cargo_id] || "") : "";
          const d = p.departamento_id ? (deptosMap[p.departamento_id] || "") : "";
          return `${c.trim().toLowerCase()}|${d.trim().toLowerCase()}`;
        })
      );

      // Denominador: admissões ativas da empresa cujo (cargo|depto) pertence ao GHE
      let admQuery = supabase
        .from("admissoes")
        .select("cargo, departamento, status, inativo")
        .eq("tenant_id", tenantId)
        .or("inativo.is.null,inativo.eq.false");
      if (empresaAtivaId) admQuery = admQuery.eq("empresa_id", empresaAtivaId);
      const { data: admData } = await admQuery;
      elegiveisGHE = ((admData || []) as { cargo: string | null; departamento: string | null }[]).filter(a => {
        const key = `${(a.cargo || "").trim().toLowerCase()}|${(a.departamento || "").trim().toLowerCase()}`;
        return pairsKey.has(key);
      }).length;

    }

    const participacoes = (participacoesRes.data || []) as Array<{ id: string; respondido: boolean | null }>;
    const entrevistas = (entrevistasRes.data || []) as Array<{ id: string; status: string | null; resumo_ia: any }>;


    // Convites individuais (campanhas com distribuição nominal — modelo legado)
    const totalConvites = convites.length;
    const iniciados = convites.filter(c => c.status === 'iniciado').length;
    const concluidosConvites = convites.filter(c => c.status === 'concluido').length;
    const expirados = convites.filter(c => c.status === 'expirado').length;

    // Participações (modelo atual: Link Geral / link individual via psicossocial_participacoes)
    const totalParticipacoes = participacoes.length;
    const respondidosParticipacoes = participacoes.filter(p => p.respondido).length;

    // Entrevistas guiadas por IA (modelo qualitativo)
    const totalEntrevistas = entrevistas.length;
    const entrevistasConcluidas = entrevistas.filter(e => e.status === 'concluida').length;

    // Fonte de verdade para "concluídas" = respostas reais salvas (cobre Link Geral anônimo)
    const totalRespostas = respostas.length;
    // "Concluídos" e "Total elegível" dependem do escopo da campanha:
    // • Com GHE vinculado → denominador = funcionários do GHE; concluídos = total de
    //   respostas da campanha (toda resposta é de alguém do GHE, por construção).
    // • Sem GHE → comportamento legado: convites nominais ou quadro ativo da empresa
    //   (Link Geral anônimo). O max() cobre haver mais respostas que cadastros ativos.
    const isEntrevistaGuiada =isEntrevistaInstrumento(campanhaRes.data?.tipo_instrumento);
    const { concluidos, total } = calcularContagemParticipacaoCampanha({
      temGHE,
      isEntrevistaGuiada,
      elegiveisGHE,
      totalConvites,
      totalParticipacoes,
      totalRespostas,
      totalEntrevistas,
      colaboradoresAtivos,
      concluidosConvites,
      respondidosParticipacoes,
      entrevistasConcluidas,
    });
    // Pendentes = quem ainda não respondeu dentro do universo elegível
    const pendentes = Math.max(0, total - concluidos);

    const MINIMO_ANONIMATO = isEntrevistaGuiada ? 1 : 5;
    // Para entrevista guiada, as respostas vivem em `psicossocial_entrevistas` (concluídas).
    // Para questionários, contam as respostas reais salvas.
    const respostasEfetivas = isEntrevistaGuiada
      ? Math.max(totalRespostas, entrevistasConcluidas)
      : totalRespostas;
    const anonimato_garantido = respostasEfetivas >= MINIMO_ANONIMATO;

    // IPS médio agregado (só exibido com anonimato garantido)
    const respostasComIPS = respostas.filter(r => r.indicadores?.IPS !== undefined);
    let ips: number | undefined;
    let radar: RadarDimensao[] | undefined;

    if (anonimato_garantido && respostasComIPS.length > 0) {
      ips = Math.round(
        respostasComIPS.reduce((acc, r) => acc + (r.indicadores?.IPS ?? 0), 0) / respostasComIPS.length
      );

      // Agregar radar por dimensão (média de todas respostas)
      const allRadar = respostasComIPS
        .map(r => r.indicadores?.radar)
        .filter((r): r is RadarDimensao[] => Array.isArray(r) && r.length > 0);

      if (allRadar.length > 0) {
        const subjects = allRadar[0].map(d => d.subject);
        radar = subjects.map(subject => ({
          subject: subject,
          value: Math.round(
            allRadar.reduce((acc, r) => {
              const found = r.find(d => d.subject === subject);
              return acc + (found?.value ?? 50);
            }, 0) / allRadar.length
          ),
          fullMark: 100,
        }));
      }
    }

    // ── Entrevista guiada: agregar IPS/radar a partir de `resumo_ia.riscos` ──
    // O instrumento é SIPRO/IRP-S (maior = pior). Convertemos prob*sev (1-25)
    // para escala 0-100 e usamos a média como score de risco.
    if (anonimato_garantido && isEntrevistaGuiada && (ips === undefined || !radar || radar.length === 0)) {
      const entrevistasConcl = entrevistas.filter(e => e.status === 'concluida' && e.resumo_ia);
      const riscoAcc = new Map<string, { soma: number; n: number }>();
      for (const e of entrevistasConcl) {
        const riscos = (e.resumo_ia?.riscos ?? []) as Array<{
          risco_nome?: string; presente?: boolean; probabilidade?: number; severidade?: number;
        }>;
        for (const r of riscos) {
          if (!r.risco_nome) continue;
          // Inclui riscos ausentes com score baixo (P=1/S=1 gravados pelo finalize),
          // garantindo radar completo dos 13 fatores e IPS calculável mesmo em
          // campanhas saudáveis (sem riscos presentes).
          const prob = Number(r.probabilidade) || (r.presente === false ? 1 : 0);
          const sev = Number(r.severidade) || (r.presente === false ? 1 : 0);
          const score = Math.min(100, Math.max(0, prob * sev * 4));
          const acc = riscoAcc.get(r.risco_nome) ?? { soma: 0, n: 0 };
          acc.soma += score;
          acc.n += 1;
          riscoAcc.set(r.risco_nome, acc);
        }
      }
      if (riscoAcc.size > 0) {
        const radarFromEntrevistas: RadarDimensao[] = Array.from(riscoAcc.entries()).map(([subject, { soma, n }]) => ({
          subject,
          value: Math.round(soma / n),
          fullMark: 100,
        }));
        const riscoMedio = Math.round(
          radarFromEntrevistas.reduce((a, b) => a + b.value, 0) / radarFromEntrevistas.length
        );
        radar = radarFromEntrevistas;
        // B2 (corrigido): stats.ips é SAÚDE (alto=melhor) para TODOS os
        // instrumentos. A entrevista usa 100 - risco médio, alinhado a
        // useEntrevistasGuiadasAggregates e usePsicossocialResultadosGHE (que já
        // faziam 100 - risco). O radar segue em risco e é normalizado na exibição.
        ips = 100 - riscoMedio;
      }
    }


    // ── Agregação por Departamento e Cargo (via convite vinculado ao CPF) ──
    // ISO 45003: só expõe grupos com ≥5 respostas (anonimato).
    const conviteIndex = new Map(convites.map(c => [c.id, c]));
    const grupos = (campo: 'colaborador_departamento' | 'colaborador_cargo') => {
      const acc = new Map<string, number[]>();
      for (const r of respostas) {
        const conv = r.convite_id ? conviteIndex.get(r.convite_id) : null;
        const nome = (conv?.[campo] as string | null | undefined)?.trim() || 'Não informado';
        const ipsR = r.indicadores?.IPS;
        if (typeof ipsR !== 'number') continue;
        const arr = acc.get(nome) ?? [];
        arr.push(ipsR);
        acc.set(nome, arr);
      }
      return Array.from(acc.entries())
        .map(([nome, ipsArr]) => {
          const anon = ipsArr.length >= MINIMO_ANONIMATO;
          const ipsMed = anon ? Math.round(ipsArr.reduce((a, b) => a + b, 0) / ipsArr.length) : undefined;
          return {
            nome,
            total: ipsArr.length,
            ips: ipsMed,
            ips_classificacao: ipsMed !== undefined ? calcularIPSClassificacao(ipsMed) : undefined,
            anonimato_garantido: anon,
          };
        })
        .sort((a, b) => b.total - a.total);
    };

    const por_departamento = grupos('colaborador_departamento');
    const por_cargo = grupos('colaborador_cargo');

    return {
      total_convites: total,
      pendentes,
      iniciados,
      concluidos,
      expirados,
      taxa_participacao: total > 0 ? (concluidos / total) * 100 : 0,
      anonimato_garantido,
      ips,
      ips_classificacao: ips !== undefined ? calcularIPSClassificacao(ips) : undefined,
      radar,
      por_departamento,
      por_cargo,
    };
  };

  // ── Estatísticas agregadas de N campanhas ─────────────────────────────────
  //
  // Estratégia (deliberada):
  // • Números de participação (universo elegível, GHE, pendentes) reaproveitam
  //   `calcularEstatisticas` por campanha e são SOMADOS. O denominador vira
  //   "oportunidades de resposta" (pessoa × campanha), que é o que faz sentido
  //   quando o mesmo quadro é convidado várias vezes ao longo do tempo.
  // • IPS e radar são RECALCULADOS a partir das respostas brutas de todas as
  //   campanhas — nunca média das médias. Assim uma campanha com 40 respostas
  //   pesa 8× mais que uma com 5, como deve ser.
  // • Anonimato (ISO 45003): exige o mínimo em CADA campanha do recorte E no
  //   agregado. Somar duas campanhas de 3 respostas não "libera" análise.
  const calcularEstatisticasMulti = async (
    campanhaIds: string[],
  ): Promise<EstatisticasMultiCampanha> => {
    const ids = Array.from(new Set(campanhaIds.filter(Boolean)));
    if (ids.length === 0) throw new Error("Nenhuma campanha selecionada");

    const metaMap = new Map(campanhas.map(c => [c.id, c]));

    const [statsPorCampanha, respostasPorCampanha] = await Promise.all([
      Promise.all(ids.map(id => calcularEstatisticas(id))),
      Promise.all(ids.map(id => buscarRespostas(id))),
    ]);

    // ── Resumo por campanha (aba comparativo) ────────────────────────────────
    const por_campanha: EstatisticaCampanhaResumo[] = ids.map((id, i) => {
      const meta = metaMap.get(id);
      const s = statsPorCampanha[i];
      const comIPS = respostasPorCampanha[i].filter(r => typeof r.indicadores?.IPS === "number");
      return {
        campanha_id: id,
        nome: meta?.nome ?? "Campanha",
        instrumento: meta?.instrumento,
        tipo_instrumento: meta?.tipo_instrumento,
        data_inicio: meta?.data_inicio,
        data_fim: meta?.data_fim,
        respostas_com_ips: comIPS.length,
        concluidos: s.concluidos,
        total: s.total_convites,
        taxa_participacao: s.taxa_participacao,
        anonimato_garantido: s.anonimato_garantido,
        ips: s.ips,
        ips_classificacao: s.ips_classificacao,
      };
    });

    // ── Homogeneidade de instrumento ─────────────────────────────────────────
    const instrumentos = new Set(por_campanha.map(c => c.instrumento || "copsoq"));
    const instrumento_homogeneo = instrumentos.size <= 1;
    const instrumento_comum = instrumento_homogeneo
      ? (por_campanha[0]?.instrumento as InstrumentoPsicossocial | undefined)
      : undefined;

    // ── Anonimato ────────────────────────────────────────────────────────────
    const campanhas_sem_anonimato = por_campanha
      .filter(c => !c.anonimato_garantido)
      .map(c => c.nome);
    const todasRespostas = respostasPorCampanha.flat();
    const respostasComIPS = todasRespostas.filter(r => typeof r.indicadores?.IPS === "number");
    const minimoAgregado = por_campanha.every(c => isEntrevistaInstrumento(c.tipo_instrumento)) ? 1 : 5;
    const totalRespostasEfetivas = Math.max(
      todasRespostas.length,
      statsPorCampanha.reduce((a, s) => a + s.concluidos, 0),
    );
    const anonimato_garantido =
      campanhas_sem_anonimato.length === 0 && totalRespostasEfetivas >= minimoAgregado;

    // ── Participação somada ──────────────────────────────────────────────────
    const total_convites = statsPorCampanha.reduce((a, s) => a + s.total_convites, 0);
    const concluidos = statsPorCampanha.reduce((a, s) => a + s.concluidos, 0);
    const pendentes = statsPorCampanha.reduce((a, s) => a + s.pendentes, 0);
    const iniciados = statsPorCampanha.reduce((a, s) => a + s.iniciados, 0);
    const expirados = statsPorCampanha.reduce((a, s) => a + s.expirados, 0);

    // ── IPS e radar ponderados por resposta ──────────────────────────────────
    let ips: number | undefined;
    let radar: RadarDimensao[] | undefined;

    if (anonimato_garantido && respostasComIPS.length > 0) {
      ips = Math.round(
        respostasComIPS.reduce((acc, r) => acc + (r.indicadores?.IPS ?? 0), 0) / respostasComIPS.length,
      );

      // Radar: média por dimensão sobre TODAS as respostas que contêm aquela
      // dimensão. Instrumentos diferentes têm dimensões diferentes, então o
      // denominador é por dimensão (não o total geral) para não diluir.
      const acc = new Map<string, { soma: number; n: number }>();
      for (const r of respostasComIPS) {
        const dims = r.indicadores?.radar;
        if (!Array.isArray(dims)) continue;
        for (const d of dims) {
          const cur = acc.get(d.subject) ?? { soma: 0, n: 0 };
          cur.soma += d.value;
          cur.n += 1;
          acc.set(d.subject, cur);
        }
      }
      if (acc.size > 0) {
        radar = Array.from(acc.entries()).map(([subject, { soma, n }]) => ({
          subject,
          value: Math.round(soma / n),
          fullMark: 100,
        }));
      }
    } else if (anonimato_garantido) {
      // Sem respostas brutas com IPS (ex.: entrevistas guiadas, cujo score vem
      // de resumo_ia). Cai para média das campanhas ponderada por concluídos.
      const comIps = por_campanha.filter(c => typeof c.ips === "number" && c.concluidos > 0);
      const pesoTotal = comIps.reduce((a, c) => a + c.concluidos, 0);
      if (pesoTotal > 0) {
        ips = Math.round(comIps.reduce((a, c) => a + (c.ips ?? 0) * c.concluidos, 0) / pesoTotal);
      }
      // Radar equivalente, dimensão a dimensão, ponderado por concluídos.
      const acc = new Map<string, { soma: number; n: number }>();
      statsPorCampanha.forEach((s, i) => {
        const peso = por_campanha[i].concluidos || 0;
        if (!s.radar || peso <= 0) return;
        for (const d of s.radar) {
          const cur = acc.get(d.subject) ?? { soma: 0, n: 0 };
          cur.soma += d.value * peso;
          cur.n += peso;
          acc.set(d.subject, cur);
        }
      });
      if (acc.size > 0) {
        radar = Array.from(acc.entries()).map(([subject, { soma, n }]) => ({
          subject,
          value: Math.round(soma / n),
          fullMark: 100,
        }));
      }
    }

    // ── Agregação por departamento/cargo ─────────────────────────────────────
    // Recombina os grupos das campanhas ponderando pelo nº de respostas de
    // cada grupo. Reaplica o mínimo de anonimato sobre o total consolidado.
    const mesclarGrupos = (chave: "por_departamento" | "por_cargo"): GrupoEstatistica[] => {
      const acc = new Map<string, { soma: number; n: number }>();
      for (const s of statsPorCampanha) {
        for (const g of s[chave] ?? []) {
          if (typeof g.ips !== "number") continue;
          const cur = acc.get(g.nome) ?? { soma: 0, n: 0 };
          cur.soma += g.ips * g.total;
          cur.n += g.total;
          acc.set(g.nome, cur);
        }
      }
      return Array.from(acc.entries())
        .map(([nome, { soma, n }]) => {
          const anon = n >= minimoAgregado;
          const media = anon ? Math.round(soma / n) : undefined;
          return {
            nome,
            total: n,
            ips: media,
            ips_classificacao: media !== undefined ? calcularIPSClassificacao(media) : undefined,
            anonimato_garantido: anon,
          };
        })
        .sort((a, b) => b.total - a.total);
    };

    return {
      total_convites,
      pendentes,
      iniciados,
      concluidos,
      expirados,
      taxa_participacao: total_convites > 0 ? (concluidos / total_convites) * 100 : 0,
      anonimato_garantido,
      ips,
      ips_classificacao: ips !== undefined ? calcularIPSClassificacao(ips) : undefined,
      radar,
      por_departamento: mesclarGrupos("por_departamento"),
      por_cargo: mesclarGrupos("por_cargo"),
      campanhas_incluidas: ids.length,
      por_campanha,
      instrumento_homogeneo,
      instrumento_comum,
      campanhas_sem_anonimato,
    };
  };

  /** Estatísticas de 1..N campanhas. Passe um array de IDs. */
  const useEstatisticasCampanhas = (campanhaIds: string[]) => {
    const chave = [...campanhaIds].sort().join(",");
    return useQuery({
      queryKey: ["psicossocial-estatisticas-multi", chave],
      queryFn: () => calcularEstatisticasMulti(campanhaIds),
      enabled: campanhaIds.length > 0,
      staleTime: 0,
      refetchOnMount: "always",
      refetchOnWindowFocus: true,
      refetchInterval: 60_000,
    });
  };

  // Hook para estatísticas
  const useEstatisticasCampanha = (campanhaId?: string) => {
    return useQuery({
      queryKey: ["psicossocial-estatisticas", campanhaId],
      queryFn: () => calcularEstatisticas(campanhaId!),
      enabled: !!campanhaId,
      // Respostas anônimas chegam pela rota pública sem invalidar cache do dashboard,
      // então sempre revalidamos ao montar / focar para refletir o real.
      staleTime: 0,
      refetchOnMount: "always",
      refetchOnWindowFocus: true,
      refetchInterval: 60_000,
    });
  };

  // ==================== FUNÇÕES PÚBLICAS (SEM AUTH) ====================
  // Usam supabasePublic para evitar conflito de RLS com usuário logado

  // Buscar campanha por token_publico (link geral anônimo) - SECURITY DEFINER
  const buscarCampanhaPorTokenPublico = async (token: string): Promise<CampanhaPsicossocial | null> => {
    const { data, error } = await supabasePublic
      .rpc('buscar_campanha_por_token_publico', { p_token: token });

    if (error || !data || (data as any[]).length === 0) return null;
    const row = (data as any[])[0];
    return {
      id: row.campanha_id,
      tenant_id: row.tenant_id,
      nome: row.campanha_nome,
      descricao: row.campanha_descricao,
      status: row.campanha_status,
      tipo: 'regular',
      instrumento: (row.campanha_instrumento || 'sipro') as InstrumentoPsicossocial,
      data_inicio: row.campanha_data_inicio,
      data_fim: row.campanha_data_fim,
      anonimo: row.campanha_anonimo,
      mensagem_institucional: row.campanha_mensagem_institucional,
      politica_uso_dados: row.campanha_politica_uso_dados,
      blocos_dinamicos: row.campanha_blocos_dinamicos,
      created_at: '',
      updated_at: '',
    } as CampanhaPsicossocial;
  };

  // Salvar resposta anônima via token_publico da campanha - SECURITY DEFINER
  const salvarRespostaAnonimaCampanha = async (
    tokenPublico: string,
    campanha: CampanhaPsicossocial,
    respostas: Record<string, number>,
    tempoSegundos: number,
  ): Promise<void> => {
    const instrumento = (campanha.instrumento || 'sipro') as InstrumentoPsicossocial;
    const blocosDinamicos = (campanha.blocos_dinamicos as string[] | undefined) ?? [];
    const indicadores = calcularIndicadores(respostas, instrumento, blocosDinamicos);

    const { error } = await supabasePublic
      .rpc('salvar_resposta_anonima_campanha', {
        p_token_publico: tokenPublico,
        p_respostas: JSON.parse(JSON.stringify(respostas)),
        p_indicadores: JSON.parse(JSON.stringify(indicadores)),
        p_tempo_segundos: tempoSegundos,
        p_user_agent: navigator.userAgent,
      });

    if (error) throw error;
  };

  // Buscar convite por token (público) - via security definer function (legado - convites individuais)
  const buscarConvitePorToken = async (token: string): Promise<ConvitePsicossocial & { campanha: CampanhaPsicossocial } | null> => {
    const { data, error } = await supabasePublic
      .rpc('buscar_convite_por_token', { p_token: token });

    if (error || !data || data.length === 0) return null;
    
    const row = data[0];
    // Reconstruct the nested shape expected by consumers
    const convite = {
      id: row.id,
      tenant_id: row.tenant_id,
      campanha_id: row.campanha_id,
      colaborador_id: row.colaborador_id,
      colaborador_nome: row.colaborador_nome,
      colaborador_cpf: row.colaborador_cpf,
      colaborador_cargo: row.colaborador_cargo,
      colaborador_departamento: row.colaborador_departamento,
      token: row.token,
      status: row.status,
      enviado_via: row.enviado_via,
      enviado_em: row.enviado_em,
      iniciado_em: row.iniciado_em,
      concluido_em: row.concluido_em,
      created_at: row.created_at,
      campanha: {
        id: row.campanha_id,
        nome: row.campanha_nome,
        descricao: row.campanha_descricao,
        tipo: row.campanha_tipo,
        status: row.campanha_status,
        instrumento: (row.campanha_instrumento || 'sipro') as InstrumentoPsicossocial,
        data_inicio: row.campanha_data_inicio,
        data_fim: row.campanha_data_fim,
        anonimo: row.campanha_anonimo,
        permite_identificacao_voluntaria: row.campanha_permite_identificacao_voluntaria,
        mensagem_institucional: row.campanha_mensagem_institucional,
        politica_uso_dados: row.campanha_politica_uso_dados,
        blocos_dinamicos: row.campanha_blocos_dinamicos,
      } as CampanhaPsicossocial,
    } as ConvitePsicossocial & { campanha: CampanhaPsicossocial };

    return convite;
  };

  // Atualizar status do convite (público) - via security definer function
  const atualizarConvitePublico = async (token: string, status: ConvitePsicossocial['status']) => {
    const { error } = await supabasePublic
      .rpc('atualizar_convite_por_token', { p_token: token, p_status: status });

    if (error) throw error;
  };

  // Salvar resposta (público) - via security definer function
  const salvarRespostaPublica = async (
    convite: ConvitePsicossocial & { campanha?: CampanhaPsicossocial },
    respostas: Record<string, number>,
    tempoSegundos: number,
    identificacaoVoluntaria: boolean = false
  ): Promise<void> => {
    const instrumento = (convite.campanha?.instrumento || 'copsoq') as InstrumentoPsicossocial;
    const indicadores = calcularIndicadores(respostas, instrumento);

    const { error } = await supabasePublic
      .rpc('salvar_resposta_psicossocial', {
        p_token: convite.token,
        p_respostas: JSON.parse(JSON.stringify(respostas)),
        p_indicadores: JSON.parse(JSON.stringify(indicadores)),
        p_identificacao_voluntaria: identificacaoVoluntaria,
        p_tempo_segundos: tempoSegundos,
        p_user_agent: navigator.userAgent,
      });

    if (error) throw error;
  };

  // ==================== STATS GERAIS ====================

  const campanhasAtivas = campanhas.filter(c => c.status === 'ativa').length;

  return {
    // Campanhas
    campanhas,
    campanhasAtivas,
    isLoadingCampanhas,
    refetchCampanhas,
    criarCampanha,
    editarCampanha,
    atualizarStatusCampanha,

    // Convites
    useConvitesCampanha,
    gerarConvites,

    // Respostas
    useRespostasCampanha,

    // Estatísticas
    useEstatisticasCampanha,
    useEstatisticasCampanhas,

    // Funções públicas
    buscarConvitePorToken,
    atualizarConvitePublico,
    salvarRespostaPublica,
    buscarCampanhaPorTokenPublico,
    salvarRespostaAnonimaCampanha,
    calcularIndicadores,
  };
}
