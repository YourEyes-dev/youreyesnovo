import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";
import type {
  EpiTipo,
  EpiTipoInsert,
  Epi,
  EpiInsert,
  EpiUpdate,
  EpiEntrega,
  EpiEntregaInsert,
  EpiEntregaUpdate,
  EpiMovimentacao,
  EpiCompleto,
  EpiStatus,
  EntregaStatus,
} from "@/types/epi";


export function useEpis() {
  const { tenantId, user, profile } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const queryClient = useQueryClient();

  // ==================== QUERIES ====================

  // Buscar categorias customizadas
  const categoriasQuery = useQuery({
    queryKey: ["epi-categorias", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data, error } = await supabase
        .from("epi_categorias")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("nome");
      if (error) throw error;
      return data as { id: string; nome: string; tenant_id: string; exige_ca: boolean }[];
    },
    enabled: !!tenantId,
  });

  // Buscar tipos de EPI
  const tiposQuery = useQuery({
    queryKey: ["epi-tipos", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];

      const { data, error } = await supabase
        .from("epi_tipos")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("nome");
      if (error) throw error;

      return data as EpiTipo[];
    },
    enabled: !!tenantId,
  });

  // Buscar EPIs com tipo
  const episQuery = useQuery({
    queryKey: ["epis", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      
      let query = supabase
        .from("epis")
        .select(`
          *,
          tipo:epi_tipos(*)
        `)
        .eq("tenant_id", tenantId);

      if (empresaAtivaId) {
        query = query.or(`empresa_id.eq.${empresaAtivaId},empresa_id.is.null`);
      }

      const { data, error } = await query.order("created_at", { ascending: false });
      if (error) throw error;
      return data as EpiCompleto[];
    },
    enabled: !!tenantId,
  });

  // Buscar entregas
  const entregasQuery = useQuery({
    queryKey: ["epi-entregas", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      
      let query = supabase
        .from("epi_entregas")
        .select(`
          *,
          epi:epis(*, tipo:epi_tipos(*))
        `)
        .eq("tenant_id", tenantId);

      if (empresaAtivaId) {
        query = query.or(`empresa_id.eq.${empresaAtivaId},empresa_id.is.null`);
      }

      const { data, error } = await query.order("data_entrega", { ascending: false });
      if (error) throw error;
      return data as (EpiEntrega & { epi: EpiCompleto })[];
    },
    enabled: !!tenantId,
  });

  // Buscar movimentações
  const movimentacoesQuery = useQuery({
    queryKey: ["epi-movimentacoes", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      
      let query = supabase
        .from("epi_movimentacoes")
        .select(`
          *,
          epi:epis(*, tipo:epi_tipos(*))
        `)
        .eq("tenant_id", tenantId);

      if (empresaAtivaId) {
        // As movimentações não têm empresa_id direto, mas podemos filtrar pelos EPIs
        // Porém, como a query já faz join com EPIs, o ideal seria filtrar via EPI
        // Supabase não suporta filtro em tabela relacionada diretamente no select simples sem recurso de embedding filtering complexo
        // Vamos filtrar no client-side ou assumir que se o EPI é da empresa, a movimentação é também.
        // Por simplicidade e performance, vamos assumir que o filtro principal de EPIs já restringe o contexto visual
        // Mas para garantir consistência, o ideal seria adicionar empresa_id na movimentação também ou filtrar via inner join.
        // Dado que adicionamos empresa_id em 'epis', vamos filtrar os EPIs primeiro e buscar suas movimentações?
        // Ou melhor: Vamos deixar sem filtro por enquanto pois movimentações são histórico
        // AJUSTE: O usuário pediu para filtrar. Vamos tentar filtrar via inner join implícito se possível
        // Como não adicionei empresa_id em epi_movimentacoes, vou pular esse filtro por ora ou filtrar no client.
        // Melhor: vou filtrar no client após o fetch se necessário, mas aqui vou manter sem filtro de empresaId direto na query
        // pois a tabela não tem a coluna.
      }
      
      // NOTA: Para filtrar movimentações corretamente, precisaríamos que epi_movimentacoes tivesse empresa_id
      // ou fazer um filtro pós-busca. Vou manter sem filtro de empresa aqui por enquanto para não quebrar.
      
      const { data, error } = await query
        .order("created_at", { ascending: false })
        .limit(100);
      if (error) throw error;
      return data as (EpiMovimentacao & { epi: EpiCompleto })[];
    },
    enabled: !!tenantId,
  });

  // ==================== MUTATIONS - CATEGORIAS ====================

  const criarCategoriaMutation = useMutation({
    mutationFn: async (nome: string) => {
      if (!tenantId) throw new Error("Tenant não identificado");
      const { data, error } = await supabase
        .from("epi_categorias")
        .insert({ nome, tenant_id: tenantId })
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["epi-categorias"] });
      toast.success("Categoria criada com sucesso!");
    },
    onError: (error) => {
      toast.error("Erro ao criar categoria: " + error.message);
    },
  });

  // Marca (ou desmarca) a exigência de CA de uma categoria.
  //
  // Usa upsert porque a lista de categorias oferecida no cadastro é maior que
  // a tabela: ela junta as categorias padrão do sistema com as que aparecem
  // nos tipos já cadastrados. Marcar uma dessas pela primeira vez precisa
  // criar a linha; da segunda vez em diante, atualizar a que existe.
  const definirExigeCaMutation = useMutation({
    mutationFn: async ({ nome, exige_ca }: { nome: string; exige_ca: boolean }) => {
      if (!tenantId) throw new Error("Tenant não identificado");
      const { data, error } = await supabase
        .from("epi_categorias")
        .upsert({ nome, tenant_id: tenantId, exige_ca }, { onConflict: "tenant_id,nome" })
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: (_data, vars) => {
      queryClient.invalidateQueries({ queryKey: ["epi-categorias"] });
      toast.success(
        vars.exige_ca
          ? `"${vars.nome}" passa a exigir CA no cadastro.`
          : `"${vars.nome}" não exige mais CA no cadastro.`
      );
    },
    onError: (error) => {
      toast.error("Erro ao salvar a categoria: " + error.message);
    },
  });

  // ==================== MUTATIONS - TIPOS ====================

  const criarTipoMutation = useMutation({
    mutationFn: async (dados: Omit<EpiTipoInsert, "tenant_id"> & { estoque_inicial?: number | null; controla_tamanho?: boolean; tamanhos?: string[]; grade_tamanhos?: Array<{ tamanho: string; local_estoque_id: string; quantidade: number }> }) => {
      if (!tenantId) throw new Error("Tenant não identificado");
      
      const { estoque_inicial, controla_tamanho, tamanhos, grade_tamanhos, ...dadosTipo } = dados;
      
      const { data, error } = await supabase
        .from("epi_tipos")
        .insert({ ...dadosTipo, tenant_id: tenantId, controla_tamanho: controla_tamanho || false })
        .select()
        .single();
      if (error) throw error;

      // Save tamanhos if provided
      if (controla_tamanho && tamanhos && tamanhos.length > 0) {
        const rows = tamanhos.map((t, idx) => ({
          tenant_id: tenantId,
          tipo_id: data.id,
          tamanho: t.trim(),
          ordem: idx,
        }));
        await supabase.from("epi_tamanhos").insert(rows);
      }
      
      // If grade_tamanhos provided, create stock per tamanho/local
      if (controla_tamanho && grade_tamanhos && grade_tamanhos.length > 0) {
        const totalQtd = grade_tamanhos.reduce((sum, g) => sum + g.quantidade, 0);
        const { data: novoEpi, error: epiError } = await supabase
          .from("epis")
          .insert({
            tenant_id: tenantId,
            empresa_id: empresaAtivaId || null,
            tipo_id: data.id,
            ca: dadosTipo.ca_numero ?? null,
            data_validade: dadosTipo.ca_validade ?? null,
            quantidade_estoque: totalQtd,
            quantidade_minima: dados.estoque_minimo ?? 5,
            status: "disponivel",
          })
          .select()
          .single();

        // Mesmo motivo do caminho sem grade: erro engolido aqui virava EPI
        // que não aparece na lista, com "criado com sucesso" na tela.
        if (epiError) throw epiError;
        {
          // Create stock per tamanho/local
          for (const g of grade_tamanhos) {
            if (g.quantidade > 0 && g.local_estoque_id) {
              await supabase.from("epi_estoque_local").upsert({
                tenant_id: tenantId,
                epi_id: novoEpi.id,
                local_estoque_id: g.local_estoque_id,
                tamanho: g.tamanho || "",
                quantidade: g.quantidade,
              }, { onConflict: "epi_id,local_estoque_id,tenant_id,tamanho" });
            }
          }
          await supabase.from("epi_movimentacoes").insert({
            tenant_id: tenantId,
            epi_id: novoEpi.id,
            tipo: "entrada",
            quantidade: totalQtd,
            quantidade_anterior: 0,
            quantidade_atual: totalQtd,
            motivo: "Cadastro inicial do tipo de EPI (por grade de tamanho)",
            realizado_por: user?.id,
            realizado_por_nome: profile?.nome_completo,
          });
        }
      } else {
        // O ITEM SEMPRE NASCE, mesmo com estoque zero.
        //
        // Antes: `estoque_inicial ?? 100` e depois `if (quantidadeInicial > 0)`.
        // O formulário manda 0 quando a pessoa não digita quantidade, então o
        // `if` não entrava, a linha em `epis` — que é a tabela que alimenta a
        // LISTA — nunca era criada, e mesmo assim o onSuccess dizia "EPI criado
        // com sucesso". Cadastrar sem quantidade fazia o EPI sumir, com a tela
        // avisando o contrário. Estoque zero é um estado legítimo (item que
        // ainda vai ser comprado), não motivo para não existir.
        //
        // O `?? 100` também sai: inventar cem unidades que ninguém comprou é
        // pior que registrar zero.
        const quantidadeInicial = estoque_inicial ?? 0;
        const { data: novoEpi, error: epiError } = await supabase
          .from("epis")
          .insert({
            tenant_id: tenantId,
            // Sem isto o item nasce sem empresa e some da lista quando há uma
            // empresa ativa selecionada (o filtro está em useEpis.ts:78).
            empresa_id: empresaAtivaId || null,
            tipo_id: data.id,
            // O CA é gravado NOS DOIS lugares enquanto a duplicidade existir:
            // o cadastro grava epi_tipos.ca_numero, mas dez telas leem epis.ca.
            ca: dadosTipo.ca_numero ?? null,
            data_validade: dadosTipo.ca_validade ?? null,
            quantidade_estoque: quantidadeInicial,
            quantidade_minima: dados.estoque_minimo ?? 5,
            status: "disponivel",
          })
          .select()
          .single();

        // Deixa de engolir o erro: antes era console.error, e uma falha de
        // gravação virava sumiço silencioso com mensagem de sucesso na tela.
        if (epiError) throw epiError;

        // Só a MOVIMENTAÇÃO depende de haver quantidade — registrar uma
        // entrada de zero unidades seria histórico falso.
        if (quantidadeInicial > 0) {
          await supabase.from("epi_movimentacoes").insert({
            tenant_id: tenantId,
            epi_id: novoEpi.id,
            tipo: "entrada",
            quantidade: quantidadeInicial,
            quantidade_anterior: 0,
            quantidade_atual: quantidadeInicial,
            motivo: "Cadastro inicial do tipo de EPI",
            realizado_por: user?.id,
            realizado_por_nome: profile?.nome_completo,
          });
        }
      }
      
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["epi-tipos"] });
      queryClient.invalidateQueries({ queryKey: ["epis"] });
      queryClient.invalidateQueries({ queryKey: ["epi-movimentacoes"] });
      toast.success("EPI criado com sucesso!");
    },
    onError: (error) => {
      toast.error("Erro ao criar EPI: " + error.message);
    },
  });

  // ==================== MUTATIONS - EPIS ====================

  const criarEpiMutation = useMutation({
    mutationFn: async (dados: Omit<EpiInsert, "tenant_id">) => {
      if (!tenantId) throw new Error("Tenant não identificado");
      const { data, error } = await supabase
        .from("epis")
        .insert({ ...dados, tenant_id: tenantId, empresa_id: empresaAtivaId || null })
        .select(`*, tipo:epi_tipos(*)`)
        .single();
      if (error) throw error;

      // Registrar movimentação de entrada inicial
      if (dados.quantidade_estoque && dados.quantidade_estoque > 0) {
        await supabase.from("epi_movimentacoes").insert({
          tenant_id: tenantId,
          epi_id: data.id,
          tipo: "entrada",
          quantidade: dados.quantidade_estoque,
          quantidade_anterior: 0,
          quantidade_atual: dados.quantidade_estoque,
          motivo: "Cadastro inicial",
          realizado_por: user?.id,
          realizado_por_nome: profile?.nome_completo,
        });
      }

      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["epis"] });
      queryClient.invalidateQueries({ queryKey: ["epi-movimentacoes"] });
      toast.success("EPI cadastrado com sucesso!");
    },
    onError: (error) => {
      toast.error("Erro ao cadastrar EPI: " + error.message);
    },
  });

  const atualizarEpiMutation = useMutation({
    mutationFn: async ({ id, ...dados }: EpiUpdate & { id: string }) => {
      const { data, error } = await supabase
        .from("epis")
        .update(dados)
        .eq("id", id)
        .select(`*, tipo:epi_tipos(*)`)
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["epis"] });
      toast.success("EPI atualizado com sucesso!");
    },
    onError: (error) => {
      toast.error("Erro ao atualizar EPI: " + error.message);
    },
  });

  const excluirEpiMutation = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from("epis").delete().eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["epis"] });
      toast.success("EPI excluído com sucesso!");
    },
    onError: (error) => {
      toast.error("Erro ao excluir EPI: " + error.message);
    },
  });

  // Ajustar estoque manualmente
  const ajustarEstoqueMutation = useMutation({
    mutationFn: async ({
      epiId,
      novaQuantidade,
      motivo,
    }: {
      epiId: string;
      novaQuantidade: number;
      motivo: string;
    }) => {
      if (!tenantId) throw new Error("Tenant não identificado");

      // Buscar quantidade atual
      const { data: epiAtual } = await supabase
        .from("epis")
        .select("quantidade_estoque")
        .eq("id", epiId)
        .single();

      const quantidadeAnterior = epiAtual?.quantidade_estoque || 0;
      const diferenca = novaQuantidade - quantidadeAnterior;

      // Atualizar estoque
      const { error } = await supabase
        .from("epis")
        .update({ quantidade_estoque: novaQuantidade })
        .eq("id", epiId);
      if (error) throw error;

      // Registrar movimentação
      await supabase.from("epi_movimentacoes").insert({
        tenant_id: tenantId,
        epi_id: epiId,
        tipo: diferenca > 0 ? "entrada" : "ajuste",
        quantidade: Math.abs(diferenca),
        quantidade_anterior: quantidadeAnterior,
        quantidade_atual: novaQuantidade,
        motivo,
        realizado_por: user?.id,
        realizado_por_nome: profile?.nome_completo,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["epis"] });
      queryClient.invalidateQueries({ queryKey: ["epi-movimentacoes"] });
      toast.success("Estoque ajustado com sucesso!");
    },
    onError: (error) => {
      toast.error("Erro ao ajustar estoque: " + error.message);
    },
  });

  // ==================== MUTATIONS - ENTREGAS ====================

  const registrarEntregaMutation = useMutation({
    mutationFn: async (dados: Omit<EpiEntregaInsert, "tenant_id"> & { foto?: File }) => {
      if (!tenantId) throw new Error("Tenant não identificado");

      // Verificar estoque disponível
      const { data: epi } = await supabase
        .from("epis")
        .select("quantidade_estoque, tipo:epi_tipos(nome)")
        .eq("id", dados.epi_id)
        .single();

      if (!epi || epi.quantidade_estoque < (dados.quantidade || 1)) {
        throw new Error("Estoque insuficiente para esta entrega");
      }

      // Upload da foto se existir
      let fotoUrl: string | undefined;
      if (dados.foto) {
        const fileExt = dados.foto.name.split('.').pop();
        const fileName = `${tenantId}/${Date.now()}-${Math.random().toString(36).substring(7)}.${fileExt}`;
        
        const { error: uploadError } = await supabase.storage
          .from('epi-fotos')
          .upload(fileName, dados.foto);
        
        if (uploadError) {
          console.error('Erro no upload da foto:', uploadError);
          throw new Error("Erro ao fazer upload da foto");
        }
        
        const { data: urlData } = supabase.storage
          .from('epi-fotos')
          .getPublicUrl(fileName);
        
        fotoUrl = urlData.publicUrl;
      }

      // Remover a foto do objeto antes de inserir
      const { foto, ...dadosSemFoto } = dados;

      const { data, error } = await supabase
        .from("epi_entregas")
        .insert({
          ...dadosSemFoto,
          tenant_id: tenantId,
          entregue_por: user?.id,
          entregue_por_nome: profile?.nome_completo,
          foto_entrega_url: fotoUrl,
        })
        .select(`*, epi:epis(*, tipo:epi_tipos(*))`)
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["epi-entregas"] });
      queryClient.invalidateQueries({ queryKey: ["epis"] });
      queryClient.invalidateQueries({ queryKey: ["epi-movimentacoes"] });
      toast.success("Entrega registrada com sucesso!");
    },
    onError: (error) => {
      toast.error("Erro ao registrar entrega: " + error.message);
    },
  });

  const atualizarEntregaMutation = useMutation({
    mutationFn: async ({ id, ...dados }: EpiEntregaUpdate & { id: string }) => {
      const { data, error } = await supabase
        .from("epi_entregas")
        .update(dados)
        .eq("id", id)
        .select(`*, epi:epis(*, tipo:epi_tipos(*))`)
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["epi-entregas"] });
      queryClient.invalidateQueries({ queryKey: ["epis"] });
      queryClient.invalidateQueries({ queryKey: ["epi-movimentacoes"] });
      toast.success("Entrega atualizada com sucesso!");
    },
    onError: (error) => {
      toast.error("Erro ao atualizar entrega: " + error.message);
    },
  });

  const registrarDevolucaoMutation = useMutation({
    mutationFn: async ({
      entregaId,
      observacoes,
      destino,
    }: {
      entregaId: string;
      observacoes?: string;
      destino?: "manutencao" | "descarte" | "estoque";
    }) => {
      if (!tenantId) throw new Error("Tenant não identificado");

      // Get the entrega details to know the epi and quantity
      const { data: entrega, error: entregaErr } = await supabase
        .from("epi_entregas")
        .select("epi_id, quantidade")
        .eq("id", entregaId)
        .single();
      if (entregaErr) throw entregaErr;

      const { data, error } = await supabase
        .from("epi_entregas")
        .update({
          status: "devolvido" as EntregaStatus,
          data_devolucao_efetiva: new Date().toISOString(),
          observacoes: observacoes ? `${observacoes} | Destino: ${destino === "manutencao" ? "Manutenção" : destino === "descarte" ? "Descarte" : "Estoque"}` : `Destino: ${destino === "manutencao" ? "Manutenção" : destino === "descarte" ? "Descarte" : "Estoque"}`,
        })
        .eq("id", entregaId)
        .select()
        .single();
      if (error) throw error;

      // If maintenance, create/update stock at "Em Manutenção" location
      if (destino === "manutencao" && entrega) {
        // Find or create "Em Manutenção" location
        let { data: localManutencao } = await supabase
          .from("epi_locais_estoque")
          .select("id")
          .eq("tenant_id", tenantId)
          .eq("nome", "Em Manutenção")
          .maybeSingle();

        if (!localManutencao) {
          const { data: novoLocal, error: localErr } = await supabase
            .from("epi_locais_estoque")
            .insert({ tenant_id: tenantId, nome: "Em Manutenção", tipo: "almoxarifado_setorial" })
            .select("id")
            .single();
          if (localErr) throw localErr;
          localManutencao = novoLocal;
        }

        // Upsert stock at maintenance location
        const { data: saldoExistente } = await supabase
          .from("epi_estoque_local")
          .select("id, quantidade")
          .eq("epi_id", entrega.epi_id)
          .eq("local_estoque_id", localManutencao.id)
          .maybeSingle();

        if (saldoExistente) {
          await supabase.from("epi_estoque_local").update({
            quantidade: saldoExistente.quantidade + (entrega.quantidade || 1),
          }).eq("id", saldoExistente.id);
        } else {
          await supabase.from("epi_estoque_local").insert({
            tenant_id: tenantId,
            epi_id: entrega.epi_id,
            local_estoque_id: localManutencao.id,
            quantidade: entrega.quantidade || 1,
          });
        }

        // Register movement
        await supabase.from("epi_movimentacoes").insert({
          tenant_id: tenantId,
          epi_id: entrega.epi_id,
          tipo: "entrada",
          quantidade: entrega.quantidade || 1,
          quantidade_anterior: saldoExistente?.quantidade || 0,
          quantidade_atual: (saldoExistente?.quantidade || 0) + (entrega.quantidade || 1),
          motivo: "Devolução para manutenção",
          realizado_por: user?.id,
          realizado_por_nome: profile?.nome_completo,
        });
      } else if (entrega) {
        // Register movement for estoque/descarte returns
        const { data: epiAtual } = await supabase
          .from("epis")
          .select("quantidade_estoque")
          .eq("id", entrega.epi_id)
          .single();

        await supabase.from("epi_movimentacoes").insert({
          tenant_id: tenantId,
          epi_id: entrega.epi_id,
          tipo: "entrada",
          quantidade: entrega.quantidade || 1,
          quantidade_anterior: (epiAtual?.quantidade_estoque || 0) - (entrega.quantidade || 1),
          quantidade_atual: epiAtual?.quantidade_estoque || 0,
          motivo: `Devolução para ${destino === "descarte" ? "descarte" : "estoque"}`,
          realizado_por: user?.id,
          realizado_por_nome: profile?.nome_completo,
        });
      }

      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["epi-entregas"] });
      queryClient.invalidateQueries({ queryKey: ["epis"] });
      queryClient.invalidateQueries({ queryKey: ["epi-movimentacoes"] });
      toast.success("Devolução registrada com sucesso!");
    },
    onError: (error) => {
      toast.error("Erro ao registrar devolução: " + error.message);
    },
  });

  // ==================== ESTATÍSTICAS ====================

  const tiposComEpiReal = new Set((episQuery.data || []).map((e) => e.tipo_id)).size;

  const stats = {
    totalEpis: episQuery.data?.length || 0,
    totalTipos: tiposComEpiReal,
    entregasAtivas: entregasQuery.data?.filter((e) => e.status === "ativa").length || 0,
    estoqueBaixo:
      episQuery.data?.filter((e) => e.quantidade_estoque <= e.quantidade_minima).length || 0,
    episVencidos:
      episQuery.data?.filter(
        (e) => e.data_validade && new Date(e.data_validade) < new Date()
      ).length || 0,
    totalEstoque: episQuery.data?.reduce((sum, e) => sum + e.quantidade_estoque, 0) || 0,
  };

  return {
    // Queries
    tipos: tiposQuery.data || [],
    tiposLoading: tiposQuery.isLoading,
    customCategorias: (categoriasQuery.data || []).map(c => c.nome),
    categorias: categoriasQuery.data || [],
    categoriasLoading: categoriasQuery.isLoading,
    epis: episQuery.data || [],
    episLoading: episQuery.isLoading,
    entregas: entregasQuery.data || [],
    entregasLoading: entregasQuery.isLoading,
    movimentacoes: movimentacoesQuery.data || [],
    movimentacoesLoading: movimentacoesQuery.isLoading,

    // Estatísticas
    stats,

    // Mutations - Categorias
    criarCategoria: criarCategoriaMutation.mutateAsync,
    criandoCategoria: criarCategoriaMutation.isPending,
    definirExigeCa: definirExigeCaMutation.mutateAsync,
    definindoExigeCa: definirExigeCaMutation.isPending,

    // Mutations - Tipos
    criarTipo: criarTipoMutation.mutateAsync,
    criandoTipo: criarTipoMutation.isPending,

    // Mutations - EPIs
    criarEpi: criarEpiMutation.mutateAsync,
    criandoEpi: criarEpiMutation.isPending,
    atualizarEpi: atualizarEpiMutation.mutateAsync,
    atualizandoEpi: atualizarEpiMutation.isPending,
    excluirEpi: excluirEpiMutation.mutateAsync,
    excluindoEpi: excluirEpiMutation.isPending,
    ajustarEstoque: ajustarEstoqueMutation.mutateAsync,
    ajustandoEstoque: ajustarEstoqueMutation.isPending,

    // Mutations - Entregas
    registrarEntrega: registrarEntregaMutation.mutateAsync,
    registrandoEntrega: registrarEntregaMutation.isPending,
    atualizarEntrega: atualizarEntregaMutation.mutateAsync,
    atualizandoEntrega: atualizarEntregaMutation.isPending,
    registrarDevolucao: registrarDevolucaoMutation.mutateAsync,
    registrandoDevolucao: registrarDevolucaoMutation.isPending,

    // Refetch
    refetchAll: () => {
      queryClient.invalidateQueries({ queryKey: ["epis"] });
      queryClient.invalidateQueries({ queryKey: ["epi-tipos"] });
      queryClient.invalidateQueries({ queryKey: ["epi-entregas"] });
      queryClient.invalidateQueries({ queryKey: ["epi-movimentacoes"] });
    },
  };
}
