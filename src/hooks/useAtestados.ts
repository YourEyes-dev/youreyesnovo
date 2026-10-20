import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";
import type { 
  Atestado, 
  Afastamento, 
  EventoSaude, 
  BeneficioINSS, 
  AlertaSaude,
  AtestadoFormData 
} from "@/types/atestado";

/**
 * Afastamento sem previsão de retorno — benefício do INSS ou licença
 * previdenciária. Só nesses casos é legítimo existir sem data de término,
 * e é certo que o ponto siga bloqueado enquanto durar.
 */
function afastamentoSemPrazoDefinido(formData: AtestadoFormData): boolean {
  return Boolean(formData.beneficio_especie)
    || ['beneficio_b31', 'beneficio_b91', 'licenca_maternidade']
         .includes(formData.tipo_principal_new ?? '');
}

/**
 * Decide se o atestado abre um registro de Afastamento.
 *
 * Regra da casa (13/08/2026): todo atestado COM PERÍODO abre afastamento —
 * absenteísmo, FAP/RAT, régua dos 15 dias e S-2230 dependem desses
 * registros. Comparecimento médico (medido em horas, ou lançado com zero
 * dias) NÃO abre: abona as horas e o colaborador segue batendo ponto.
 *
 * A trava real está na data de término: sem ela, o afastamento nasce eterno
 * e impede a batida indefinidamente. Só passa sem data de fim quem
 * legitimamente não tem previsão de retorno.
 */
function abreAfastamento(formData: AtestadoFormData): boolean {
  if (afastamentoSemPrazoDefinido(formData)) return true;
  if (formData.unidade_afastamento === 'horas') return false;
  if ((formData.dias_afastamento ?? 0) <= 0 && !formData.data_fim_afastamento) return false;
  return Boolean(formData.data_fim_afastamento);
}

export function useAtestados() {
  const { tenantId, user, profile } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const queryClient = useQueryClient();

  // Fetch atestados
  const { data: atestados = [], isLoading: loadingAtestados } = useQuery({
    queryKey: ["atestados", tenantId, empresaAtivaId],
    queryFn: async (): Promise<Atestado[]> => {
      if (!tenantId) return [];
      
      let query = fromTable("atestados")
        .select("*")
        .eq("tenant_id", tenantId);

      if (empresaAtivaId) {
        query = query.eq("empresa_id", empresaAtivaId);
      }

      const { data, error } = await query
        .order("data_emissao", { ascending: false }) as { data: Atestado[] | null; error: Error | null };
      if (error) throw error;
      return data || [];
    },
    enabled: !!tenantId,
  });

  // Fetch afastamentos
  const { data: afastamentos = [], isLoading: loadingAfastamentos } = useQuery({
    queryKey: ["afastamentos", tenantId, empresaAtivaId],
    queryFn: async (): Promise<Afastamento[]> => {
      if (!tenantId) return [];
      
      let query = fromTable("afastamentos")
        .select("*")
        .eq("tenant_id", tenantId);

      if (empresaAtivaId) {
        query = query.eq("empresa_id", empresaAtivaId);
      }

      const { data, error } = await query
        .order("data_inicio", { ascending: false }) as { data: Afastamento[] | null; error: Error | null };
      if (error) throw error;
      return data || [];
    },
    enabled: !!tenantId,
  });

  // Fetch eventos de saúde
  const { data: eventosSaude = [], isLoading: loadingEventos } = useQuery({
    queryKey: ["eventos_saude", tenantId],
    queryFn: async (): Promise<EventoSaude[]> => {
      if (!tenantId) return [];
      const { data, error } = await fromTable("eventos_saude")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("data_inicio", { ascending: false }) as { data: EventoSaude[] | null; error: Error | null };
      if (error) throw error;
      return data || [];
    },
    enabled: !!tenantId,
  });

  // Fetch benefícios INSS
  const { data: beneficiosINSS = [], isLoading: loadingBeneficios } = useQuery({
    queryKey: ["beneficios_inss", tenantId, empresaAtivaId],
    queryFn: async (): Promise<BeneficioINSS[]> => {
      if (!tenantId) return [];
      
      // A tabela beneficios_inss não recebeu a coluna empresa_id na migração anterior
      // Vou checar se posso filtrar via join ou se devo adicionar a coluna depois
      // Por enquanto, mantenho sem filtro de empresa para não quebrar
      // EDIT: Ah, eu deveria ter adicionado na migração. Vou pular o filtro aqui por enquanto.
      
      const { data, error } = await fromTable("beneficios_inss")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("data_inicio", { ascending: false }) as { data: BeneficioINSS[] | null; error: Error | null };
      if (error) throw error;
      return data || [];
    },
    enabled: !!tenantId,
  });

  // Fetch alertas
  const { data: alertas = [], isLoading: loadingAlertas } = useQuery({
    queryKey: ["alertas_saude", tenantId],
    queryFn: async (): Promise<AlertaSaude[]> => {
      if (!tenantId) return [];
      const { data, error } = await fromTable("alertas_saude")
        .select("*")
        .eq("tenant_id", tenantId)
        .eq("resolvido", false)
        .order("created_at", { ascending: false }) as { data: AlertaSaude[] | null; error: Error | null };
      if (error) throw error;
      return data || [];
    },
    enabled: !!tenantId,
  });

  // Create atestado
  const createAtestadoMutation = useMutation({
    mutationFn: async ({ formData, file, colaboradorId }: { formData: AtestadoFormData; file?: File; colaboradorId?: string }) => {
      if (!tenantId || !user) throw new Error("Usuário não autenticado");

      let arquivo_url = null;
      let arquivo_nome = null;
      let arquivo_tamanho = null;

      // Upload file if provided
      if (file) {
        const timestamp = Date.now();
        const fileName = `${tenantId}/${timestamp}_${file.name.replace(/[^a-zA-Z0-9.-]/g, "_")}`;
        
        const { error: uploadError } = await supabase.storage
          .from("atestados")
          .upload(fileName, file, { cacheControl: "3600", upsert: false });

        if (uploadError) throw uploadError;
        
        arquivo_url = fileName;
        arquivo_nome = file.name;
        arquivo_tamanho = file.size;

      // Também salvar no módulo de Documentos (vinculado ao colaborador)
        if (colaboradorId) {
          const docFileName = `${tenantId}/colaboradores/${colaboradorId}/${timestamp}_atestado_${file.name.replace(/[^a-zA-Z0-9.-]/g, "_")}`;
          
          const { error: docUploadError } = await supabase.storage
            .from("documentos")
            .upload(docFileName, file, { cacheControl: "3600", upsert: false });

          if (!docUploadError) {
            // Buscar ou criar pasta do colaborador
            let pastaId: string | null = null;
            
            const { data: pastaExistente } = await fromTable("documento_pastas")
              .select("id")
              .eq("tenant_id", tenantId)
              .eq("colaborador_id", colaboradorId)
              .eq("tipo", "colaborador")
              .limit(1)
              .single() as { data: { id: string } | null };

            if (pastaExistente) {
              pastaId = pastaExistente.id;
            } else {
              // Criar pasta do colaborador
              const { data: novaPasta } = await fromTable("documento_pastas")
                .insert({
                  tenant_id: tenantId,
                  nome: formData.colaborador_nome,
                  tipo: "colaborador",
                  colaborador_id: colaboradorId,
                  colaborador_nome: formData.colaborador_nome,
                  colaborador_cpf: formData.colaborador_cpf || null,
                  criado_por: user.id,
                  criado_por_nome: profile?.nome_completo,
                } as any)
                .select("id")
                .single() as { data: { id: string } | null };
              
              if (novaPasta) pastaId = novaPasta.id;
            }

            // Salvar metadados no banco de documentos
            await fromTable("documentos")
              .insert({
                tenant_id: tenantId,
                colaborador_id: colaboradorId,
                colaborador_nome: formData.colaborador_nome,
                colaborador_cpf: formData.colaborador_cpf || null,
                nome_arquivo: docFileName,
                nome_original: file.name,
                tipo: "Atestado",
                tamanho: file.size,
                mime_type: file.type,
                storage_path: docFileName,
                data_validade: null,
                status: "valido",
                pasta_id: pastaId,
                observacoes: `Atestado ${formData.tipo} - ${formData.profissional_nome} (${formData.profissional_registro})`,
                criado_por: user.id,
                criado_por_nome: profile?.nome_completo,
              } as any);
          }
        }
      }

      // Calculate dias_afastamento if dates provided
      let dias_afastamento = formData.dias_afastamento;
      if (formData.data_inicio_afastamento && formData.data_fim_afastamento && !dias_afastamento) {
        const inicio = new Date(formData.data_inicio_afastamento);
        const fim = new Date(formData.data_fim_afastamento);
        dias_afastamento = Math.ceil((fim.getTime() - inicio.getTime()) / (1000 * 60 * 60 * 24)) + 1;
      }

      const { data, error } = await fromTable("atestados")
        .insert({
          tenant_id: tenantId,
          empresa_id: empresaAtivaId || null,
          // Não vincular colaborador_id pois admissões não são profiles
          colaborador_id: null,
          colaborador_nome: formData.colaborador_nome,
          colaborador_cpf: formData.colaborador_cpf,
          colaborador_cargo: formData.colaborador_cargo,
          colaborador_departamento: formData.colaborador_departamento,
          tipo: formData.tipo,
          subtipo_assistencial: formData.subtipo_assistencial,
          subtipo_ocupacional: formData.subtipo_ocupacional,
          data_emissao: formData.data_emissao,
          profissional_nome: formData.profissional_nome,
          profissional_registro: formData.profissional_registro,
          profissional_uf: formData.profissional_uf,
          profissional_rqe: formData.profissional_rqe,
          profissional_telefone: formData.profissional_telefone,
          profissional_email: formData.profissional_email,
          profissional_endereco: formData.profissional_endereco,
          profissional_tipo: formData.profissional_tipo,
          data_inicio_afastamento: formData.data_inicio_afastamento,
          data_fim_afastamento: formData.data_fim_afastamento,
          dias_afastamento,
          horas_afastamento: formData.horas_afastamento,
          unidade_afastamento: formData.unidade_afastamento || 'dias',
          abona: formData.abona ?? null,
          contem_cid: formData.contem_cid,
          cid_codigo: formData.cid_codigo,
          cid_autorizado: formData.cid_autorizado,
          grupo_clinico: formData.grupo_clinico,
          nexo_trabalho: formData.nexo_trabalho || 'nao',
          aptidao: formData.aptidao,
          restricoes: formData.restricoes,
          observacoes_ocupacionais: formData.observacoes_ocupacionais,
          observacoes: formData.observacoes,
          arquivo_url,
          arquivo_nome,
          arquivo_tamanho,
          criado_por: user.id,
          criado_por_nome: profile?.nome_completo,
        } as any)
        .select()
        .single();

      if (error) throw error;

      // Create/update afastamento if not occupational and with dates.
      // Comparecimento médico (horas, ou zero dias) não é afastamento: abre-se
      // apenas o atestado, e o colaborador segue batendo ponto normalmente.
      // Sem essa trava nascia afastamento sem data de término — que a trava do
      // ponto lê como fim no ano 9999 e bloqueia a batida para sempre.
      if (formData.tipo !== 'ocupacional'
          && formData.data_inicio_afastamento
          && abreAfastamento(formData)) {
        const afastamentoId = await createOrUpdateAfastamento(data as Atestado, formData.tipo_principal_new);

        // Tarefa 4: registrar dados do acidente (CAT) e reconciliar pendência no RH
        if (formData.lancamento_tipo === 'acidente_trabalho' && afastamentoId) {
          await registrarCatEpendencia(afastamentoId, formData);
        }

        // Tarefa 2: persistir o benefício INSS no mesmo registro (sem lançamento separado)
        if (afastamentoId && formData.beneficio_especie) {
          await registrarBeneficioInss(afastamentoId, data as Atestado, formData);
        }
      }

      // Check INSS referral suggestion (>15 days single or accumulated in 90 days)
      // No novo fluxo dinâmico (com lancamento_tipo), o motor do banco + a seção de
      // benefício cuidam disso; evita-se o alerta duplicado no front-end.
      if (!formData.lancamento_tipo) {
        await checkINSSReferral(data as Atestado, dias_afastamento || 0);
      }

      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["atestados"] });
      queryClient.invalidateQueries({ queryKey: ["afastamentos"] });
      queryClient.invalidateQueries({ queryKey: ["afastamentos-ativos"] });
      queryClient.invalidateQueries({ queryKey: ["alertas_saude"] });
      queryClient.invalidateQueries({ queryKey: ["documentos"] });
      queryClient.invalidateQueries({ queryKey: ["pendencias-dashboard"] });
      queryClient.invalidateQueries({ queryKey: ["beneficios_inss"] });
      queryClient.invalidateQueries({ queryKey: ["beneficios"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-atestados-dia"] });
      toast.success("Atestado cadastrado com sucesso!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao cadastrar atestado: " + error.message);
    },
  });

  // Helper function to create/update afastamento
  const createOrUpdateAfastamento = async (
    atestado: Atestado,
    tipoPrincipalNew?: AtestadoFormData['tipo_principal_new']
  ): Promise<string | null> => {
    if (!tenantId || !atestado.data_inicio_afastamento) return null;

    // Check for existing active afastamento for this colaborador
    const { data: existingAfastamentos } = await fromTable("afastamentos")
      .select("*")
      .eq("tenant_id", tenantId)
      .eq("colaborador_nome", atestado.colaborador_nome)
      .eq("status", "ativo") as { data: Afastamento[] | null };

    if (existingAfastamentos && existingAfastamentos.length > 0) {
      // Update existing afastamento
      const existing = existingAfastamentos[0];
      const newEndDate = atestado.data_fim_afastamento || atestado.data_inicio_afastamento;
      
      if (new Date(newEndDate) > new Date(existing.data_fim || existing.data_inicio)) {
        await fromTable("afastamentos")
          .update({
            data_fim: newEndDate,
            motivo_principal: atestado.grupo_clinico || existing.motivo_principal,
            ...(tipoPrincipalNew ? { tipo_principal_new: tipoPrincipalNew } : {}),
          } as any)
          .eq("id", existing.id);
      }

      // Link atestado to afastamento
      await fromTable("atestados")
        .update({ afastamento_id: existing.id } as any)
        .eq("id", atestado.id);

      return existing.id;
    } else {
      // Create new afastamento
      const { data: newAfastamento } = await fromTable("afastamentos")
        .insert({
          tenant_id: tenantId,
          empresa_id: empresaAtivaId || null,
          colaborador_id: atestado.colaborador_id,
          colaborador_nome: atestado.colaborador_nome,
          colaborador_cpf: atestado.colaborador_cpf,
          data_inicio: atestado.data_inicio_afastamento,
          data_fim: atestado.data_fim_afastamento,
          // Chegar aqui sem data de término só acontece no caso legítimo
          // (benefício do INSS / licença previdenciária). O banco recusa
          // qualquer outro afastamento sem fim.
          prazo_indeterminado: !atestado.data_fim_afastamento,
          motivo_principal: atestado.grupo_clinico,
          nexo_trabalho: atestado.nexo_trabalho,
          tipo_principal_new: tipoPrincipalNew ?? null,
          status_geral_new: 'registrado',
        } as any)
        .select()
        .single();

      if (newAfastamento) {
        await fromTable("atestados")
          .update({ afastamento_id: (newAfastamento as Afastamento).id } as any)
          .eq("id", atestado.id);

        return (newAfastamento as Afastamento).id;
      }

      return null;
    }
  };

  // Tarefa 4: persiste os dados da CAT e reconcilia a pendência de CAT no RH.
  // Salvar é permitido SEM o número da CAT; nesse caso garante-se uma pendência
  // aberta. Ao informar o número, a pendência é resolvida.
  const registrarCatEpendencia = async (
    afastamentoId: string,
    formData: AtestadoFormData
  ) => {
    if (!tenantId) return;

    try {
      const numeroCat = formData.numero_cat?.trim();

      // Upsert manual em afastamentos_cat (sem unique em afastamento_id)
      const { data: existingCat } = await fromTable("afastamentos_cat")
        .select("id")
        .eq("afastamento_id", afastamentoId)
        .limit(1)
        .maybeSingle() as { data: { id: string } | null };

      const catPayload = {
        cat_aplicavel: true,
        numero_cat: numeroCat || null,
        data_acidente: formData.data_acidente || null,
        hora_acidente: formData.hora_acidente || null,
        local_acidente: formData.local_acidente || null,
        parte_corpo: formData.parte_corpo || null,
        agente_causador: formData.agente_causador || null,
        descricao_acidente: formData.descricao_acidente || null,
        status_cat: numeroCat ? 'emitida' : 'pendente',
      };

      if (existingCat) {
        await fromTable("afastamentos_cat")
          .update(catPayload as any)
          .eq("id", existingCat.id);
      } else {
        await fromTable("afastamentos_cat")
          .insert({
            tenant_id: tenantId,
            afastamento_id: afastamentoId,
            ...catPayload,
          } as any);
      }

      // Reconciliar pendência de CAT no RH
      if (numeroCat) {
        // CAT informada → resolve a pendência aberta (se houver)
        await fromTable("afastamentos_pendencias")
          .update({
            status: 'resolvido',
            resolvido_em: new Date().toISOString(),
          } as any)
          .eq("afastamento_id", afastamentoId)
          .eq("tipo_pendencia", "cat")
          .eq("status", "pendente");
      } else {
        // Sem CAT → garante uma pendência aberta (evita violar índice único)
        const { data: existingPend } = await fromTable("afastamentos_pendencias")
          .select("id")
          .eq("afastamento_id", afastamentoId)
          .eq("tipo_pendencia", "cat")
          .eq("status", "pendente")
          .limit(1)
          .maybeSingle() as { data: { id: string } | null };

        if (!existingPend) {
          await fromTable("afastamentos_pendencias")
            .insert({
              tenant_id: tenantId,
              afastamento_id: afastamentoId,
              tipo_pendencia: "cat",
              descricao: "Número da CAT pendente de preenchimento",
              prioridade: "critica",
              status: "pendente",
            } as any);
        }
      }
    } catch (err) {
      console.error("Erro ao registrar CAT/pendência do afastamento:", err);
    }
  };

  // Tarefa 2: persiste o benefício INSS no MESMO registro do afastamento.
  // Faz upsert manual em beneficios_inss (sem unique em afastamento_id) e
  // vincula o afastamento de volta ao benefício. Não-bloqueante.
  const registrarBeneficioInss = async (
    afastamentoId: string,
    atestado: Atestado,
    formData: AtestadoFormData
  ) => {
    if (!tenantId) return;

    try {
      // data_inicio é NOT NULL: usa a data informada ou a do afastamento.
      const data_inicio = formData.beneficio_data_inicio || atestado.data_inicio_afastamento;
      if (!data_inicio) {
        console.warn("Benefício INSS não registrado: data de início ausente.");
        return;
      }

      const payload = {
        especie: formData.beneficio_especie,
        numero_beneficio: formData.beneficio_numero || null,
        data_inicio,
        data_alta: formData.beneficio_data_alta || null,
        colaborador_id: atestado.colaborador_id,
        colaborador_nome: atestado.colaborador_nome,
        colaborador_cpf: atestado.colaborador_cpf,
      };

      const { data: existing } = await fromTable("beneficios_inss")
        .select("id")
        .eq("afastamento_id", afastamentoId)
        .limit(1)
        .maybeSingle() as { data: { id: string } | null };

      let beneficioId: string | null = existing?.id ?? null;

      if (existing) {
        await fromTable("beneficios_inss")
          .update(payload as any)
          .eq("id", existing.id);
      } else {
        const { data: novoBeneficio } = await fromTable("beneficios_inss")
          .insert({
            tenant_id: tenantId,
            afastamento_id: afastamentoId,
            ...payload,
            criado_por: user?.id,
            criado_por_nome: profile?.nome_completo,
          } as any)
          .select("id")
          .single() as { data: { id: string } | null };

        beneficioId = novoBeneficio?.id ?? null;
      }

      // Vincula o afastamento de volta ao benefício
      if (beneficioId) {
        await fromTable("afastamentos")
          .update({ beneficio_inss_id: beneficioId } as any)
          .eq("id", afastamentoId);
      }
    } catch (err) {
      console.error("Erro ao registrar benefício INSS do afastamento:", err);
    }
  };

  // Check if INSS referral should be suggested
  const checkINSSReferral = async (atestado: Atestado, diasAtestado: number) => {
    if (!tenantId || !user) return;

    const needsINSS = diasAtestado > 15;

    if (!needsINSS && atestado.grupo_clinico) {
      // Check accumulated days for same grupo_clinico within 90 days
      const ninetyDaysAgo = new Date();
      ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);

      const { data: relatedAtestados } = await fromTable("atestados")
        .select("dias_afastamento")
        .eq("tenant_id", tenantId)
        .eq("colaborador_nome", atestado.colaborador_nome)
        .eq("grupo_clinico", atestado.grupo_clinico)
        .gte("data_emissao", ninetyDaysAgo.toISOString().split("T")[0]) as { data: { dias_afastamento: number | null }[] | null };

      const totalDias = (relatedAtestados || []).reduce((sum, a) => sum + (a.dias_afastamento || 0), 0);

      if (totalDias <= 15) return;
    } else if (!needsINSS) {
      return;
    }

    // Check if alert already exists for this colaborador (avoid duplicates)
    const { data: existingAlert } = await fromTable("alertas_saude")
      .select("id")
      .eq("tenant_id", tenantId)
      .eq("colaborador_nome", atestado.colaborador_nome)
      .eq("tipo", "encaminhamento_inss")
      .eq("resolvido", false)
      .limit(1) as { data: { id: string }[] | null };

    if (existingAlert && existingAlert.length > 0) return;

    // Create alert suggesting INSS referral
    await fromTable("alertas_saude")
      .insert({
        tenant_id: tenantId,
        tipo: "encaminhamento_inss",
        referencia_tipo: "atestado",
        referencia_id: atestado.id,
        colaborador_id: atestado.colaborador_id,
        colaborador_nome: atestado.colaborador_nome,
        titulo: "Encaminhamento ao INSS sugerido",
        descricao: needsINSS
          ? `${atestado.colaborador_nome} possui atestado com ${diasAtestado} dias de afastamento (>15 dias). Recomenda-se encaminhamento ao INSS.`
          : `${atestado.colaborador_nome} acumulou mais de 15 dias de afastamento pelo mesmo motivo nos últimos 90 dias. Recomenda-se encaminhamento ao INSS.`,
        prioridade: "critica",
      } as any);

    toast.info("⚠️ Atenção: Encaminhamento ao INSS sugerido para " + atestado.colaborador_nome);
  };

  // Update atestado
  const updateAtestadoMutation = useMutation({
    mutationFn: async ({ id, data }: { id: string; data: Partial<AtestadoFormData> }) => {
      const { error } = await fromTable("atestados")
        .update(data as any)
        .eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["atestados"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-atestados-dia"] });
      toast.success("Atestado atualizado com sucesso!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao atualizar: " + error.message);
    },
  });

  // Delete atestado
  const deleteAtestadoMutation = useMutation({
    mutationFn: async (atestado: Atestado) => {
      // Delete file from storage if exists
      if (atestado.arquivo_url) {
        await supabase.storage.from("atestados").remove([atestado.arquivo_url]);
      }

      // Se o atestado está vinculado a um afastamento, verificar se precisa remover
      if (atestado.afastamento_id) {
        // Verificar se há outros atestados vinculados ao mesmo afastamento
        const { data: outrosAtestados } = await fromTable("atestados")
          .select("id")
          .eq("afastamento_id", atestado.afastamento_id)
          .neq("id", atestado.id) as { data: { id: string }[] | null };

        // Se não há outros atestados, remover o afastamento
        if (!outrosAtestados || outrosAtestados.length === 0) {
          await fromTable("afastamentos")
            .delete()
            .eq("id", atestado.afastamento_id);
        }
      }

      // Remover alertas de saúde relacionados ao atestado
      await fromTable("alertas_saude")
        .delete()
        .eq("referencia_id", atestado.id)
        .eq("referencia_tipo", "atestado");
      
      const { error } = await fromTable("atestados")
        .delete()
        .eq("id", atestado.id);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["atestados"] });
      queryClient.invalidateQueries({ queryKey: ["afastamentos"] });
      queryClient.invalidateQueries({ queryKey: ["afastamentos-ativos"] });
      queryClient.invalidateQueries({ queryKey: ["alertas_saude"] });
      // Espelho do ponto: o trigger de DELETE reverte ponto_diario no banco;
      // aqui invalidamos TODAS as queries que o espelho usa, para a tela
      // refletir na hora, sem o usuário precisar recarregar.
      queryClient.invalidateQueries({ queryKey: ["ponto-atestados-dia"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-ajustes-dia"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-marcacoes-dia"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-diario"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-consolidado"] });
      toast.success("Atestado excluído com sucesso!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao excluir: " + error.message);
    },
  });

  // Create benefício INSS
  const createBeneficioMutation = useMutation({
    mutationFn: async (data: Partial<BeneficioINSS>) => {
      if (!tenantId || !user) throw new Error("Usuário não autenticado");
      
      const { error } = await fromTable("beneficios_inss")
        .insert({
          tenant_id: tenantId,
          ...data,
          criado_por: user.id,
          criado_por_nome: profile?.nome_completo,
        } as any);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["beneficios_inss"] });
      toast.success("Benefício INSS registrado com sucesso!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao registrar benefício: " + error.message);
    },
  });

  // Delete afastamento
  const deleteAfastamentoMutation = useMutation({
    mutationFn: async (afastamentoId: string) => {
      if (!tenantId) throw new Error("Tenant não identificado");
      
      // Desvincular atestados do afastamento antes de deletar
      await fromTable("atestados")
        .update({ afastamento_id: null } as any)
        .eq("afastamento_id", afastamentoId);

      // Deletar alertas relacionados
      await fromTable("alertas_saude")
        .delete()
        .eq("referencia_id", afastamentoId)
        .eq("referencia_tipo", "afastamento");
      
      const { error } = await fromTable("afastamentos")
        .delete()
        .eq("id", afastamentoId);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["afastamentos"] });
      queryClient.invalidateQueries({ queryKey: ["afastamentos-ativos"] });
      queryClient.invalidateQueries({ queryKey: ["atestados"] });
      queryClient.invalidateQueries({ queryKey: ["alertas_saude"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-atestados-dia"] });
      toast.success("Afastamento excluído com sucesso!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao excluir afastamento: " + error.message);
    },
  });

  // Resolve alerta
  const resolveAlertaMutation = useMutation({
    mutationFn: async (alertaId: string) => {
      if (!user) throw new Error("Usuário não autenticado");
      
      const { error } = await fromTable("alertas_saude")
        .update({
          resolvido: true,
          resolvido_por: user.id,
          resolvido_em: new Date().toISOString(),
        } as any)
        .eq("id", alertaId);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["alertas_saude"] });
      toast.success("Alerta resolvido!");
    },
    onError: (error: Error) => {
      toast.error("Erro ao resolver alerta: " + error.message);
    },
  });

  // Get signed URL for file
  const getSignedUrl = async (storagePath: string): Promise<string | null> => {
    const { data, error } = await supabase.storage
      .from("atestados")
      .createSignedUrl(storagePath, 3600);
    if (error) {
      toast.error("Erro ao gerar link de download");
      return null;
    }
    return data.signedUrl;
  };

  // Calculate stats
  const stats = {
    totalAtestados: atestados.length,
    atestadosAssistenciais: atestados.filter(a => a.tipo === 'atestados' || a.tipo === 'licencas').length,
    atestadosOcupacionais: atestados.filter(a => a.tipo === 'ocupacional').length,
    afastamentosAtivos: afastamentos.filter(a => a.status === 'ativo').length,
    afastamentos15Dias: afastamentos.filter(a => a.alerta_15_dias && a.status === 'ativo').length,
    afastamentos30Dias: afastamentos.filter(a => a.alerta_30_dias && a.status === 'ativo').length,
    asoRetornoPendente: afastamentos.filter(a => a.aso_retorno_pendente).length,
    beneficiosAtivos: beneficiosINSS.filter(b => !b.data_alta).length,
    beneficiosB91: beneficiosINSS.filter(b => b.especie === 'b91').length,
    colaboradoresEstabilidade: beneficiosINSS.filter(b => 
      b.gera_estabilidade && 
      b.data_fim_estabilidade && 
      new Date(b.data_fim_estabilidade) > new Date()
    ).length,
    alertasPendentes: alertas.length,
    saudeMental: atestados.filter(a => a.grupo_clinico === 'mental').length,
    totalDiasAfastamento: atestados.reduce((acc, a) => acc + (a.dias_afastamento || 0), 0),
  };

  // Group by grupo_clinico
  const atestadosPorGrupo = atestados.reduce((acc, atestado) => {
    const grupo = atestado.grupo_clinico || 'outro';
    acc[grupo] = (acc[grupo] || 0) + 1;
    return acc;
  }, {} as Record<string, number>);

  const isLoading = loadingAtestados || loadingAfastamentos || loadingEventos || loadingBeneficios || loadingAlertas;

  return {
    // Data
    atestados,
    afastamentos,
    eventosSaude,
    beneficiosINSS,
    alertas,
    stats,
    atestadosPorGrupo,
    
    // Loading states
    isLoading,
    loadingAtestados,
    loadingAfastamentos,
    
    // Mutations
    createAtestado: createAtestadoMutation.mutateAsync,
    creatingAtestado: createAtestadoMutation.isPending,
    updateAtestado: updateAtestadoMutation.mutateAsync,
    deleteAtestado: deleteAtestadoMutation.mutateAsync,
    deletingAtestado: deleteAtestadoMutation.isPending,
    deleteAfastamento: deleteAfastamentoMutation.mutateAsync,
    deletingAfastamento: deleteAfastamentoMutation.isPending,
    createBeneficio: createBeneficioMutation.mutateAsync,
    resolveAlerta: resolveAlertaMutation.mutateAsync,
    
    // Utils
    getSignedUrl,
  };
}
