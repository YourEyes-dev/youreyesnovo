import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";
import { format } from "date-fns";
import { useEffect } from "react";
import { cleanCpf } from "@/lib/cpf";

// Tipos
export interface PontoMarcacao {
  id: string;
  tenant_id: string;
  colaborador_id: string;
  colaborador_nome: string;
  colaborador_cpf: string;
  data_marcacao: string;
  hora_marcacao: string;
  tipo_marcacao: "entrada" | "saida_almoco" | "retorno_almoco" | "saida" | "batida";
  ip_origem: string | null;
  user_agent: string | null;
  latitude: number | null;
  longitude: number | null;
  dispositivo: string | null;
  hash_marcacao: string;
  marcacao_original: boolean;
  created_at: string;
  created_by: string | null;
}

export interface PontoDiario {
  id: string;
  tenant_id: string;
  empresa_id: string | null;
  colaborador_id: string;
  colaborador_nome: string;
  colaborador_cpf: string;
  data: string;
  entrada: string | null;
  saida_almoco: string | null;
  retorno_almoco: string | null;
  saida: string | null;
  horas_trabalhadas: string | null;
  horas_extras: string | null;
  horas_faltantes: string | null;
  status: "pendente" | "regular" | "atraso" | "falta" | "incompleto" | "ajuste_pendente" | "justificado";
  observacao: string | null;
  tipo_dia: "normal" | "feriado" | "ferias" | "atestado" | "afastamento" | null;
  // Súmula 338/TST: de onde veio o intervalo do dia — batido ("marcado") ou
  // declarado em pré-assinalação ("pre_assinalado"). Metadado de exibição:
  // o motor de saldo não lê.
  intervalo_origem: "marcado" | "pre_assinalado" | null;
  intervalo_pre_assinalado_minutos: number | null;
  feriado_nome: string | null;
  feriado_trabalhado: boolean | null;
  created_at: string;
  updated_at: string;
}

export interface PontoAjuste {
  id: string;
  tenant_id: string;
  ponto_diario_id: string | null;
  colaborador_id: string;
  colaborador_nome: string;
  colaborador_cpf: string;
  data_referencia: string;
  tipo_ajuste: "inclusao" | "correcao" | "justificativa" | "abono";
  tipo_marcacao: "entrada" | "saida_almoco" | "retorno_almoco" | "saida" | "batida" | null;
  hora_original: string | null;
  hora_solicitada: string | null;
  motivo: string;
  status: "pendente" | "aprovado" | "rejeitado";
  aprovado_por: string | null;
  aprovado_por_nome: string | null;
  data_aprovacao: string | null;
  observacao_aprovador: string | null;
  created_at: string;
  created_by: string | null;
  created_by_nome: string | null;
  empresa_id?: string | null;
  anexos?: Array<{ nome: string; url: string; tamanho: number; tipo: string }>;
  justificativa_id?: string | null;
  horas_abonadas?: number | null;
  dia_inteiro?: boolean | null;
  abonar_se_aprovado?: boolean | null;
  observacao?: string | null;
}

export interface PontoAuditLog {
  id: string;
  tenant_id: string;
  tabela_origem: string;
  registro_id: string;
  acao: string;
  dados_anteriores: Record<string, unknown> | null;
  dados_novos: Record<string, unknown> | null;
  usuario_id: string | null;
  usuario_nome: string | null;
  usuario_email: string | null;
  ip_origem: string | null;
  user_agent: string | null;
  created_at: string;
}

export const TIPO_MARCACAO_LABELS: Record<string, string> = {
  entrada: "Entrada",
  saida_almoco: "Saída Almoço",
  retorno_almoco: "Retorno Almoço",
  saida: "Saída",
  batida: "Batida",
};

export const STATUS_PONTO_CONFIG: Record<string, { label: string; color: string }> = {
  pendente: { label: "Pendente", color: "bg-gray-100 text-gray-800" },
  regular: { label: "Regular", color: "bg-green-100 text-green-800" },
  atraso: { label: "Atraso", color: "bg-yellow-100 text-yellow-800" },
  falta: { label: "Falta", color: "bg-red-100 text-red-800" },
  incompleto: { label: "Entrada Registrada", color: "bg-orange-100 text-orange-800" },
  ajuste_pendente: { label: "Ajuste Pendente", color: "bg-blue-100 text-blue-800" },
  justificado: { label: "Justificado", color: "bg-purple-100 text-purple-800" },
};

export function usePonto() {
  const { tenantId, user, profile } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const queryClient = useQueryClient();

  // Buscar ponto diário por data
  const usePontoDiario = (data: Date, dataFim?: Date) => {
    const dataStr = format(data, "yyyy-MM-dd");
    const dataFimStr = dataFim ? format(dataFim, "yyyy-MM-dd") : null;

    // Realtime: ouve mudanças em ponto_marcacoes e ponto_diario
    // para refletir automaticamente aprovações de ajustes no Espelho.
    useEffect(() => {
      if (!tenantId) return;
      const channel = supabase
        .channel(`espelho-realtime-${tenantId}`)
        .on(
          "postgres_changes",
          { event: "*", schema: "public", table: "ponto_marcacoes", filter: `tenant_id=eq.${tenantId}` },
          () => {
            queryClient.invalidateQueries({ queryKey: ["ponto-diario"] });
            queryClient.invalidateQueries({ queryKey: ["ponto-marcacoes"] });
            queryClient.invalidateQueries({ queryKey: ["ponto-marcacoes-dia"] });
            queryClient.invalidateQueries({ queryKey: ["ponto-marcacoes-hoje"] });
          }
        )
        .on(
          "postgres_changes",
          { event: "*", schema: "public", table: "ponto_diario", filter: `tenant_id=eq.${tenantId}` },
          () => {
            queryClient.invalidateQueries({ queryKey: ["ponto-diario"] });
          }
        )
        .subscribe();
      return () => {
        supabase.removeChannel(channel);
      };
    }, [tenantId]);

    return useQuery({
      queryKey: ["ponto-diario", tenantId, dataStr, dataFimStr, empresaAtivaId],
      queryFn: async (): Promise<PontoDiario[]> => {
        if (!tenantId) return [];
        
        let query = fromTable("ponto_diario")
          .select("*")
          .eq("tenant_id", tenantId);

        if (dataFimStr) {
          query = query.gte("data", dataStr).lte("data", dataFimStr);
        } else {
          query = query.eq("data", dataStr);
        }

        // Empresa ativa OU registros sem empresa atribuída (histórico)
        if (empresaAtivaId) {
          query = query.or(`empresa_id.eq.${empresaAtivaId},empresa_id.is.null`);
        }

        const { data: pontos, error } = await query
          .order("data")
          .order("colaborador_nome") as { data: PontoDiario[] | null; error: Error | null };
        
        if (error) throw error;
        return pontos || [];
      },
      enabled: !!tenantId,
    });
  };

  // Buscar marcações do colaborador hoje
  const useMarcacoesHoje = () => {
    const hoje = format(new Date(), "yyyy-MM-dd");
    return useQuery({
      queryKey: ["ponto-marcacoes-hoje", tenantId, hoje, empresaAtivaId],
      queryFn: async (): Promise<PontoMarcacao[]> => {
        if (!tenantId) return [];
        
        let query = fromTable("ponto_marcacoes")
          .select("*")
          .eq("tenant_id", tenantId)
          .eq("data_marcacao", hoje);

        // Empresa ativa OU marcações sem empresa atribuída (histórico)
        if (empresaAtivaId) {
          query = query.or(`empresa_id.eq.${empresaAtivaId},empresa_id.is.null`);
        }

        const { data, error } = await query
          .order("hora_marcacao") as { data: PontoMarcacao[] | null; error: Error | null };
        
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId,
      refetchInterval: 30000,
    });
  };

  // Buscar ajustes (todos status, últimos 90 dias) — mantém histórico para conferência
  const useAjustesPendentes = () => {
    return useQuery({
      queryKey: ["ponto-ajustes-pendentes", tenantId, empresaAtivaId],
      queryFn: async (): Promise<PontoAjuste[]> => {
        if (!tenantId) return [];

        const desde = new Date();
        desde.setDate(desde.getDate() - 90);
        const desdeISO = desde.toISOString();

        // Conjunto de colaboradores da empresa/unidade ativa (fonte da
        // verdade = admissão). Usamos isso para filtrar os ajustes pela
        // empresa REAL do colaborador, não pelo empresa_id gravado no
        // ajuste — que pode ter sido carimbado errado por versões antigas
        // (ajuste criado com a empresa ativa do gestor, não a do colab).
        // Mapa colaborador (admissão.id) -> empresa REAL, de todo o tenant.
        // Resolve a empresa do colaborador pelo cadastro, independente da
        // empresa ativa, para que cada ajuste apareça só na unidade dona do
        // colaborador (e não em todas, como acontecia com empresa_id nulo).
        let empresaDoColab: Map<string, string | null> | null = null;
        // Mapa auxiliar por CPF (dígitos) -> empresa. Necessário porque o
        // colaborador_id gravado no ajuste pode estar defasado (ex.: admissão
        // recriada gera novo id); o CPF é estável e recupera a empresa real.
        let empresaDoCpf: Map<string, string | null> | null = null;
        if (empresaAtivaId) {
          const { data: colabs } = await fromTable("admissoes")
            .select("id, empresa_id, cpf")
            .eq("tenant_id", tenantId) as { data: { id: string; empresa_id: string | null; cpf: string | null }[] | null };
          empresaDoColab = new Map((colabs || []).map((c) => [c.id, c.empresa_id]));
          empresaDoCpf = new Map(
            (colabs || [])
              .map((c) => [cleanCpf(c.cpf || ""), c.empresa_id] as [string, string | null])
              .filter(([cpf]) => cpf.length === 11)
          );
        }

        // PENDENTES: todos do tenant; o filtro por empresa é aplicado
        // abaixo (noEscopo) pela empresa real do colaborador. NÃO
        // filtramos por empresa_id na query porque ajustes legados podem
        // ter empresa_id errado — o casamento por colaborador_id os
        // recupera na unidade certa sem travar ninguém.
        const pendentesQuery = fromTable("ponto_ajustes")
          .select("*")
          .eq("tenant_id", tenantId)
          .eq("status", "pendente");

        // HISTÓRICO (aprovado/rejeitado): janela de 90 dias, mesmo critério
        // de empresa aplicado abaixo.
        const histQuery = fromTable("ponto_ajustes")
          .select("*")
          .eq("tenant_id", tenantId)
          .neq("status", "pendente")
          .gte("created_at", desdeISO);

        const [pendRes, histRes] = await Promise.all([
          pendentesQuery.order("created_at", { ascending: false }) as Promise<{ data: PontoAjuste[] | null; error: Error | null }>,
          histQuery.order("created_at", { ascending: false }) as Promise<{ data: PontoAjuste[] | null; error: Error | null }>,
        ]);

        if (pendRes.error) throw pendRes.error;
        if (histRes.error) throw histRes.error;

        // Filtra pela empresa real do colaborador. Sem empresa ativa
        // (visão consolidada), mostra tudo do tenant.
        const noEscopo = (a: PontoAjuste) => {
          if (!empresaDoColab) return true; // visão consolidada: tudo do tenant
          // Empresa real do colaborador (cadastro). Resolve nesta ordem:
          //  1) pelo colaborador_id (caminho normal);
          //  2) pelo CPF, quando o colaborador_id do ajuste está defasado
          //     (admissão recriada → novo id), evitando que o ajuste suma da
          //     aprovação do gestor;
          //  3) pelo empresa_id gravado no próprio ajuste.
          // NÃO tratamos empresa_id nulo como "aparece em todas".
          const cpfDig = (a.colaborador_cpf || "").replace(/\D/g, "");
          const real = (a.colaborador_id && empresaDoColab.has(a.colaborador_id))
            ? empresaDoColab.get(a.colaborador_id)
            : (cpfDig && empresaDoCpf && empresaDoCpf.has(cpfDig))
              ? empresaDoCpf.get(cpfDig)
              : a.empresa_id;
          return real === empresaAtivaId;
        };

        return [
          ...(pendRes.data || []).filter(noEscopo),
          ...(histRes.data || []).filter(noEscopo),
        ];
      },
      enabled: !!tenantId,
    });
  };

  // Buscar audit log
  const useAuditLog = (limite = 100) => {
    return useQuery({
      queryKey: ["ponto-audit-log", tenantId, limite],
      queryFn: async (): Promise<PontoAuditLog[]> => {
        if (!tenantId) return [];
        
        const { data, error } = await fromTable("ponto_audit_log")
          .select("*")
          .eq("tenant_id", tenantId)
          .order("created_at", { ascending: false })
          .limit(limite) as { data: PontoAuditLog[] | null; error: Error | null };
        
        if (error) throw error;
        return data || [];
      },
      enabled: !!tenantId,
    });
  };

  // Registrar marcação de ponto
  const registrarPontoMutation = useMutation({
    mutationFn: async ({
      colaboradorId,
      colaboradorNome,
      colaboradorCpf,
      tipoMarcacao,
      latitude,
      longitude,
      enderecoGeolocalizacao,
      selfieUrl,
      selfieNome,
    }: {
      colaboradorId: string;
      colaboradorNome: string;
      colaboradorCpf: string;
      tipoMarcacao: "entrada" | "saida_almoco" | "retorno_almoco" | "saida" | "batida";
      latitude?: number;
      longitude?: number;
      enderecoGeolocalizacao?: string;
      selfieUrl?: string;
      selfieNome?: string;
    }) => {
      if (!tenantId || !user) throw new Error("Usuário não autenticado");

      const agora = new Date(new Date().toLocaleString("en-US", { timeZone: "America/Sao_Paulo" }));
      
      const userAgent = navigator.userAgent;
      const dispositivo = /Mobile|Android|iPhone/i.test(userAgent) ? "Mobile" : "Desktop";

      const { data, error } = await fromTable("ponto_marcacoes")
        .insert({
          tenant_id: tenantId,
          empresa_id: empresaAtivaId || null,
          colaborador_id: colaboradorId,
          colaborador_nome: colaboradorNome,
          colaborador_cpf: colaboradorCpf,
          data_marcacao: format(agora, "yyyy-MM-dd"),
          hora_marcacao: format(agora, "HH:mm:ss"),
          tipo_marcacao: tipoMarcacao,
          user_agent: userAgent,
          dispositivo,
          latitude,
          longitude,
          endereco_geolocalizacao: enderecoGeolocalizacao,
          selfie_url: selfieUrl,
          selfie_nome: selfieNome,
          created_by: user.id,
          hash_marcacao: "placeholder",
        } as any)
        .select()
        .single();

      if (error) {
        if (error.code === "23505") {
          throw new Error(`Já existe uma marcação de ${TIPO_MARCACAO_LABELS[tipoMarcacao]} para hoje.`);
        }
        // Parse trigger exceptions for friendly messages
        const msg = error.message || "";
        // Anti-toque-duplo: o banco já devolve a mensagem pronta, com os
        // segundos que faltam. Repassar como está preserva o tempo real.
        if (msg.includes("Não é possível registrar")) {
          throw new Error(msg.replace(/^.*?Não é possível/, "Não é possível"));
        }
        if (msg.includes("Colaborador desligado")) {
          throw new Error("Colaborador desligado. Não é possível registrar ponto.");
        }
        if (msg.includes("Colaborador afastado")) {
          throw new Error("Colaborador afastado. Não é possível registrar ponto durante período de afastamento.");
        }
        if (msg.includes("está fechado")) {
          throw new Error("Período fechado. Não é possível registrar marcações. Solicite reabertura ao RH.");
        }
        throw error;
      }

      // Portaria MTP 671/2021: a marcação gera um COMPROVANTE — recibo do
      // trabalhador com empregador, data/hora, NSR e hash, arquivado e
      // disponibilizado (prazo de 48h). Falha aqui não desfaz a batida: a
      // marcação já está registrada e a vigilância de 48h cobra o comprovante
      // que faltar.
      try {
        await (supabase.rpc as any)("ponto_gerar_comprovante", {
          p_tenant_id: tenantId,
          p_marcacao_id: (data as any)?.id,
        });
      } catch {
        // silencioso de propósito — ver comentário acima
      }

      return data as PontoMarcacao;
    },
    onSuccess: (data, variables) => {
      queryClient.invalidateQueries({ queryKey: ["ponto-marcacoes-hoje"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-diario"] });
      const horaFormatada = data ? String((data as any).hora_marcacao || "").substring(0, 5) : format(new Date(), "HH:mm");
      toast.success(
        `✅ ${TIPO_MARCACAO_LABELS[variables.tipoMarcacao]} registrada às ${horaFormatada}`,
        {
          description: `Comprovante: ${variables.colaboradorNome} — ${format(new Date(), "dd/MM/yyyy")}`,
          duration: 8000,
        }
      );
    },
    onError: (error: Error) => {
      toast.error(error.message);
    },
  });

  // Solicitar ajuste
  const solicitarAjusteMutation = useMutation({
    mutationFn: async ({
      colaboradorId,
      colaboradorNome,
      colaboradorCpf,
      dataReferencia,
      tipoAjuste,
      tipoMarcacao,
      horaOriginal,
      horaSolicitada,
      motivo,
      anexos,
      justificativaId,
      horasAbonadas,
      diaInteiro,
      observacao,
      abonarSeAprovado,
    }: {
      colaboradorId: string;
      colaboradorNome: string;
      colaboradorCpf: string;
      dataReferencia: string;
      tipoAjuste: "inclusao" | "correcao" | "justificativa" | "abono";
      tipoMarcacao?: "entrada" | "saida_almoco" | "retorno_almoco" | "saida" | "batida";
      horaOriginal?: string;
      horaSolicitada?: string;
      motivo: string;
      anexos?: File[];
      justificativaId?: string;
      horasAbonadas?: number;
      diaInteiro?: boolean;
      observacao?: string;
      abonarSeAprovado?: boolean;
    }) => {
      if (!tenantId || !user) throw new Error("Usuário não autenticado");

      // Empresa/unidade vem da ADMISSÃO do colaborador, não da empresa
      // ativa de quem cria. Sem isso, ajustes de colaboradores de outras
      // unidades eram carimbados com a empresa ativa do gestor e
      // apareciam na empresa errada na Folha de Aprovação.
      let empresaIdAjuste: string | null = empresaAtivaId || null;
      if (colaboradorId) {
        const { data: adm } = await fromTable("admissoes")
          .select("empresa_id")
          .eq("id", colaboradorId)
          .maybeSingle() as { data: { empresa_id: string | null } | null };
        if (adm?.empresa_id) empresaIdAjuste = adm.empresa_id;
      }

      // Upload de anexos (se houver)
      const anexosUploaded: Array<{ nome: string; url: string; tamanho: number; tipo: string }> = [];
      if (anexos && anexos.length > 0) {
        for (const file of anexos) {
          const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, "_");
          const path = `${user.id}/${dataReferencia}/${Date.now()}_${safeName}`;
          const { data: up, error: upErr } = await supabase
            .storage.from("ponto-ajustes-anexos").upload(path, file, { contentType: file.type });
          if (upErr) throw upErr;
          anexosUploaded.push({ nome: file.name, url: up.path, tamanho: file.size, tipo: file.type });
        }
      }

      const { data, error } = await fromTable("ponto_ajustes")
        .insert({
          tenant_id: tenantId,
          empresa_id: empresaIdAjuste,
          colaborador_id: colaboradorId,
          colaborador_nome: colaboradorNome,
          colaborador_cpf: colaboradorCpf,
          data_referencia: dataReferencia,
          tipo_ajuste: tipoAjuste,
          tipo_marcacao: tipoMarcacao,
          hora_original: horaOriginal,
          hora_solicitada: horaSolicitada,
          motivo,
          anexos: anexosUploaded,
          justificativa_id: justificativaId || null,
          horas_abonadas: horasAbonadas ?? 0,
          dia_inteiro: diaInteiro ?? false,
          observacao: observacao || null,
          abonar_se_aprovado: abonarSeAprovado ?? false,
          created_by: user.id,
          created_by_nome: profile?.nome_completo,
        } as any)
        .select()
        .single();


      if (error) throw error;
      return data as PontoAjuste;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ponto-ajustes-pendentes"] });
      toast.success("Solicitação de ajuste enviada com sucesso!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao solicitar ajuste: " + error.message);
    },
  });

  // Aprovar/Rejeitar ajuste
  const processarAjusteMutation = useMutation({
    mutationFn: async ({
      ajusteId,
      aprovado,
      observacao,
      multiple,
    }: {
      ajusteId: string;
      aprovado: boolean;
      observacao?: string;
      multiple?: boolean;
    }) => {
      if (!tenantId || !user) throw new Error("Usuário não autenticado");

      // Fluxo transacional no banco: atualiza status, remove marcação
      // original (correção), insere a nova marcação, audita e reconsolida
      // o espelho. Tudo numa única transação — ou completa, ou nada muda.
      const { data, error } = await (supabase.rpc as any)("processar_ajuste_ponto", {
        p_ajuste_id: ajusteId,
        p_aprovado: aprovado,
        p_observacao: observacao ?? null,
      });

      if (error) throw error;

      const result = data as { success?: boolean; error?: string } | null;
      if (result && result.success !== true) {
        throw new Error(result?.error || "Não foi possível processar o ajuste.");
      }

      return result;
    },
    onSuccess: (_, variables) => {
      // Invalida TODAS as queries que alimentam o espelho, para que a
      // marcação recém-aprovada apareça sem precisar de F5. A query
      // "ponto-marcacoes-dia" (coluna "Marcações do dia") faltava aqui,
      // por isso o status mudava na hora mas a batida só surgia após
      // recarregar a página.
      queryClient.invalidateQueries({ queryKey: ["ponto-ajustes-pendentes"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-diario"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-marcacoes"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-marcacoes-dia"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-ajustes-dia"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-marcacoes-hoje"] });
      // A aprovação reapura o banco de horas da competência no backend
      // (processar_ajuste_ponto) — refletir na aba Apuração sem F5.
      queryClient.invalidateQueries({ queryKey: ["ponto-banco-horas"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-bh-movimentacoes"] });
      queryClient.invalidateQueries({ queryKey: ["banco-horas-dias"] });

      if (!variables.multiple) {
        toast.success(`Ajuste ${variables.aprovado ? "aprovado" : "rejeitado"} com sucesso!`);
      }
    },
    onError: (error: Error) => {
      toast.error("Erro ao processar ajuste: " + error.message);
    },
  });

  // Excluir ajuste permanentemente (gestor/RH)
  const excluirAjusteMutation = useMutation({
    mutationFn: async ({ ajusteId }: { ajusteId: string }) => {
      if (!tenantId || !user) throw new Error("Usuário não autenticado");
      const { error } = await fromTable("ponto_ajustes").delete().eq("id", ajusteId);
      if (error) throw error;
      return ajusteId;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ponto-ajustes-pendentes"] });
      toast.success("Ajuste excluído permanentemente.");
    },
    onError: (error: Error) => {
      toast.error("Erro ao excluir ajuste: " + error.message);
    },
  });

  // Retificar marcação (gestor/RH) — a marcação original é imutável:
  // a correção passa pela RPC que registra ajuste + auditoria (Portaria MTP 671/2021).
  const editarMarcacaoMutation = useMutation({
    mutationFn: async ({
      marcacaoId,
      novaHora,
      motivo,
    }: {
      marcacaoId: string;
      novaHora: string;
      motivo: string;
    }) => {
      if (!tenantId || !user) throw new Error("Usuário não autenticado");
      if (!motivo || motivo.trim().length < 10) {
        throw new Error("Justificativa obrigatória (mínimo 10 caracteres)");
      }
      const hora = novaHora.length === 5 ? `${novaHora}:00` : novaHora;
      const { error } = await (supabase as any).rpc("ponto_retificar_marcacao", {
        p_marcacao_id: marcacaoId,
        p_nova_hora: hora,
        p_motivo: motivo.trim(),
      });
      if (error) throw error;
      return marcacaoId;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ponto-marcacoes-dia"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-diario"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-marcacoes"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-ajustes-pendentes"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-saldo-dias"] });
      toast.success("Marcação retificada. Ajuste registrado na trilha de auditoria.");
    },
    onError: (error: Error) => {
      toast.error("Erro ao retificar marcação: " + error.message);
    },
  });

  // Desconsiderar marcação de ponto (gestor/RH) — via RPC autorizado.
  // Correção por acréscimo: a batida NÃO é apagada, fica no acervo marcada como
  // desconsiderada (com motivo e responsável) e sai do cálculo do dia.
  const excluirMarcacaoMutation = useMutation({
    mutationFn: async ({ marcacaoId, motivo }: { marcacaoId: string; motivo?: string }) => {
      const { data, error } = await (supabase as any).rpc("desconsiderar_marcacao_ponto", {
        p_marcacao_id: marcacaoId,
        p_motivo: motivo?.trim() || null,
      });
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ponto-marcacoes-dia"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-diario"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-marcacoes"] });
      toast.success("Marcação desconsiderada (mantida no acervo, fora do cálculo).");
    },
    onError: (error: Error) => {
      toast.error("Erro ao desconsiderar marcação: " + error.message);
    },
  });

  return {
    // Hooks de query
    usePontoDiario,
    useMarcacoesHoje,
    useAjustesPendentes,
    useAuditLog,

    // Mutations
    registrarPonto: registrarPontoMutation.mutateAsync,
    registrandoPonto: registrarPontoMutation.isPending,
    
    solicitarAjuste: solicitarAjusteMutation.mutateAsync,
    solicitandoAjuste: solicitarAjusteMutation.isPending,
    
    processarAjuste: processarAjusteMutation.mutateAsync,
    processandoAjuste: processarAjusteMutation.isPending,

    excluirAjuste: excluirAjusteMutation.mutateAsync,
    excluindoAjuste: excluirAjusteMutation.isPending,

    editarMarcacao: editarMarcacaoMutation.mutateAsync,
    editandoMarcacao: editarMarcacaoMutation.isPending,

    excluirMarcacao: excluirMarcacaoMutation.mutateAsync,
    excluindoMarcacao: excluirMarcacaoMutation.isPending,
  };
}

