import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

export type ContratoCategoria = "live" | "aula" | "uso_sistema" | "parceria" | "nda" | "evento" | "outro";
export type ContratoStatus = "pendente" | "assinado" | "expirado" | "revogado";

export interface ContratoAceite {
  id: string;
  titulo: string;
  categoria: ContratoCategoria;
  descricao_publica: string | null;
  corpo_html: string;
  requer_cpf: boolean;
  requer_rg: boolean;
  requer_endereco: boolean;
  requer_telefone: boolean;
  requer_selfie: boolean;
  requer_geolocalizacao: boolean;
  requer_cnpj: boolean;
  requer_razao_social: boolean;
  requer_representante: boolean;
  validade_dias: number | null;
  limite_assinaturas: number | null;
  versao: number;
  ativo: boolean;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface ContratoAssinatura {
  id: string;
  contrato_id: string;
  token: string;
  signatario_nome: string | null;
  signatario_cpf: string | null;
  signatario_email: string | null;
  signatario_telefone: string | null;
  ip_address: string | null;
  geo_lat: number | null;
  geo_lng: number | null;
  hash_documento: string | null;
  link_enviado_em: string | null;
  link_enviado_para: string | null;
  expira_em: string | null;
  assinado_em: string | null;
  status: ContratoStatus;
  signatario_rg: string | null;
  signatario_endereco: string | null;
  assinatura_imagem: string | null;
  selfie_imagem: string | null;
  user_agent: string | null;
  observacoes: string | null;
  signatario_cnpj: string | null;
  signatario_razao_social: string | null;
  signatario_representante: string | null;
  /** Contrato gerado para este signatário (ex.: Contrato de Parceria com as duas partes). Prevalece sobre o modelo. */
  html_assinado?: string | null;
  parceiro_id?: string | null;
  created_at: string;
}

export function useContratosAceite() {
  const qc = useQueryClient();

  const list = useQuery({
    queryKey: ["contratos-aceite"],
    queryFn: async () => {
      const { data, error } = await fromTable("contratos_aceite")
        .select("*")
        .order("created_at", { ascending: false });
      if (error) throw error;
      return (data || []) as ContratoAceite[];
    },
  });

  const createContrato = useMutation({
    mutationFn: async (input: Partial<ContratoAceite>) => {
      const { data: u } = await supabase.auth.getUser();
      const payload = { ...input, created_by: u.user?.id };
      const { data, error } = await fromTable("contratos_aceite").insert(payload).select().single();
      if (error) throw error;
      return data as ContratoAceite;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["contratos-aceite"] });
      toast.success("Contrato criado");
    },
    onError: (e: any) => toast.error(e.message),
  });

  const updateContrato = useMutation({
    mutationFn: async ({ id, ...patch }: Partial<ContratoAceite> & { id: string }) => {
      const { error } = await fromTable("contratos_aceite").update(patch).eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["contratos-aceite"] });
      toast.success("Contrato atualizado");
    },
    onError: (e: any) => toast.error(e.message),
  });

  const deleteContrato = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await fromTable("contratos_aceite").delete().eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["contratos-aceite"] });
      toast.success("Contrato excluído");
    },
    onError: (e: any) => toast.error(e.message),
  });

  return { ...list, createContrato, updateContrato, deleteContrato };
}

export function useAssinaturasContrato(contratoId: string | null) {
  return useQuery({
    queryKey: ["contrato-assinaturas", contratoId],
    enabled: !!contratoId,
    queryFn: async () => {
      const { data, error } = await fromTable("contratos_assinaturas")
        .select("*")
        .eq("contrato_id", contratoId!)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return (data || []) as ContratoAssinatura[];
    },
  });
}

export function useGerarLinkAssinatura() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (params: {
      contrato_id: string;
      validade_dias?: number | null;
      signatario_email?: string;
      signatario_nome?: string;
    }) => {
      const expira_em = params.validade_dias
        ? new Date(Date.now() + params.validade_dias * 86400000).toISOString()
        : null;
      const { data, error } = await fromTable("contratos_assinaturas")
        .insert({
          contrato_id: params.contrato_id,
          signatario_email: params.signatario_email || null,
          signatario_nome: params.signatario_nome || null,
          expira_em,
        })
        .select()
        .single();
      if (error) throw error;
      return data as ContratoAssinatura;
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ["contrato-assinaturas", vars.contrato_id] });
    },
    onError: (e: any) => toast.error(e.message),
  });
}
