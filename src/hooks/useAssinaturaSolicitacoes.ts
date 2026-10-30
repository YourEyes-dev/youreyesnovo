import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";

/**
 * Solicitações de assinatura eletrônica do Espelho de Ponto (contexto
 * 'ponto_espelho') de uma competência, e as ações do RH: enviar, reenviar,
 * copiar link novo e cancelar.
 *
 * Enviar/reenviar passam pela função de borda assinatura-solicitar (sobe o PDF,
 * calcula o hash no servidor, manda o e-mail). Copiar link e cancelar são RPCs
 * (o servidor confere empresa e perfil).
 */
export interface AssinaturaSolicitacao {
  id: string;
  documento_ref_id: string | null;
  colaborador_cpf: string;
  colaborador_nome: string | null;
  status: string;
  enviado_em: string | null;
  visualizado_em: string | null;
  respondido_em: string | null;
  expira_em: string | null;
  decisao_texto: string | null;
  lembretes_enviados: number;
  envio_erro: string | null;
  cancelado_motivo: string | null;
  assinado_path: string | null;
  documento_id: string | null;
  created_at: string;
  autenticacao: Record<string, unknown> | null;
}

/** Onde o link abre: produção no domínio próprio; os demais ambientes no próprio endereço. */
export function linkBaseAssinatura(): string {
  const host = window.location.hostname;
  const ehProducao = host === "youreyes.com.br" || host.endsWith(".youreyes.com.br");
  const base = import.meta.env.BASE_URL || "/";
  return ehProducao ? "https://youreyes.com.br/" : `${window.location.origin}${base}`;
}

export const linkDeAssinatura = (token: string) => `${linkBaseAssinatura()}assinar/${token}`;

const MENSAGENS: Record<string, string> = {
  sem_email: "O colaborador não tem e-mail cadastrado: o link não pode ser assinado. Use a ciência em papel.",
  ja_existe_ativa: "Este espelho já tem um envio em andamento.",
  competencia_nao_fechada: "Feche a competência antes de enviar o espelho para assinatura.",
  espelho_ja_tem_ciencia: "Este espelho já tem ciência registrada.",
  hash_obrigatorio: "Não foi possível congelar o PDF do espelho.",
  solicitacao_inativa: "Este envio não está mais aberto.",
  sem_permissao: "Seu acesso não permite gerir assinaturas do espelho.",
};

export function mensagemAssinatura(erro?: string | null, fallback = "Não foi possível concluir."): string {
  return (erro && MENSAGENS[erro]) || erro || fallback;
}

/** Chama a função de borda e devolve o corpo JSON mesmo quando o status não é 2xx. */
async function chamarFuncao<T = Record<string, unknown>>(nome: string, body: unknown): Promise<T> {
  const { data, error } = await supabase.functions.invoke(nome, { body });
  if (error) {
    const ctx = (error as { context?: Response }).context;
    if (ctx && typeof ctx.json === "function") {
      try {
        return (await ctx.json()) as T;
      } catch {
        /* sem corpo JSON */
      }
    }
    throw error;
  }
  return data as T;
}

async function blobParaBase64(blob: Blob): Promise<string> {
  const buf = new Uint8Array(await blob.arrayBuffer());
  let bin = "";
  const passo = 0x8000;
  for (let i = 0; i < buf.length; i += passo) {
    bin += String.fromCharCode(...buf.subarray(i, i + passo));
  }
  return btoa(bin);
}

export function useAssinaturaSolicitacoes(competencia: string) {
  const { tenantId } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const qc = useQueryClient();
  const chave = ["assinatura-solicitacoes", "ponto_espelho", tenantId, empresaAtivaId, competencia];

  const consulta = useQuery({
    queryKey: chave,
    enabled: !!tenantId && !!competencia,
    queryFn: async (): Promise<AssinaturaSolicitacao[]> => {
      let q = fromTable("assinatura_solicitacoes")
        .select(
          "id, documento_ref_id, colaborador_cpf, colaborador_nome, status, enviado_em, visualizado_em, respondido_em, expira_em, decisao_texto, lembretes_enviados, envio_erro, cancelado_motivo, assinado_path, documento_id, created_at, autenticacao",
        )
        .eq("tenant_id", tenantId)
        .eq("contexto", "ponto_espelho")
        .eq("referencia", competencia);
      if (empresaAtivaId) q = q.eq("empresa_id", empresaAtivaId);
      const { data, error } = (await q.order("created_at", { ascending: false })) as {
        data: AssinaturaSolicitacao[] | null;
        error: Error | null;
      };
      if (error) throw error;
      return data || [];
    },
  });

  /** A solicitação mais recente de cada espelho. */
  const porEspelho = new Map<string, AssinaturaSolicitacao>();
  (consulta.data || []).forEach((s) => {
    if (s.documento_ref_id && !porEspelho.has(s.documento_ref_id)) porEspelho.set(s.documento_ref_id, s);
  });

  const atualizar = () => {
    qc.invalidateQueries({ queryKey: ["assinatura-solicitacoes"] });
    qc.invalidateQueries({ queryKey: ["ponto-espelhos"] });
    qc.invalidateQueries({ queryKey: ["pendencias-dashboard"] });
  };

  const enviar = useMutation({
    mutationFn: async ({ espelhoId, pdf }: { espelhoId: string; pdf: Blob }) => {
      const r = await chamarFuncao<{
        ok: boolean; erro?: string; mensagem?: string; link?: string;
        email_enviado?: boolean; email_erro?: string; destino?: string;
      }>("assinatura-solicitar", {
        acao: "enviar",
        espelho_id: espelhoId,
        pdf_base64: await blobParaBase64(pdf),
        link_base: linkBaseAssinatura(),
      });
      if (!r?.ok) throw new Error(r?.mensagem || mensagemAssinatura(r?.erro, "Não foi possível enviar."));
      return r;
    },
    onSuccess: atualizar,
    onError: (e: Error) => toast.error(e.message),
  });

  const reenviar = useMutation({
    mutationFn: async (solicitacaoId: string) => {
      const r = await chamarFuncao<{ ok: boolean; erro?: string; link?: string; email_enviado?: boolean; email_erro?: string }>(
        "assinatura-solicitar",
        { acao: "reenviar", solicitacao_id: solicitacaoId, link_base: linkBaseAssinatura() },
      );
      if (!r?.ok) throw new Error(mensagemAssinatura(r?.erro, "Não foi possível reenviar."));
      return r;
    },
    onSuccess: (r) => {
      atualizar();
      toast.success(r.email_enviado ? "E-mail reenviado com um link novo." : "Link novo gerado (o e-mail não saiu: copie o link).");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const novoLink = useMutation({
    mutationFn: async (solicitacaoId: string) => {
      const { data, error } = await (supabase.rpc as any)("assinatura_rh_novo_link", { p_solicitacao_id: solicitacaoId });
      if (error) throw error;
      const r = (data || {}) as { ok?: boolean; erro?: string; token?: string };
      if (!r.ok || !r.token) throw new Error(mensagemAssinatura(r.erro, "Não foi possível gerar o link."));
      return linkDeAssinatura(r.token);
    },
    onSuccess: atualizar,
    onError: (e: Error) => toast.error(e.message),
  });

  const cancelar = useMutation({
    mutationFn: async ({ solicitacaoId, motivo }: { solicitacaoId: string; motivo?: string }) => {
      const { data, error } = await (supabase.rpc as any)("assinatura_cancelar", {
        p_solicitacao_id: solicitacaoId,
        p_motivo: motivo || "cancelado_pelo_rh",
      });
      if (error) throw error;
      const r = (data || {}) as { ok?: boolean; erro?: string };
      if (!r.ok) throw new Error(mensagemAssinatura(r.erro, "Não foi possível cancelar."));
    },
    onSuccess: () => {
      atualizar();
      toast.success("Envio cancelado: o link deixou de valer.");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  /** URL temporária (5 min) do PDF assinado, para o RH conferir. */
  const urlAssinado = async (caminho: string | null) => {
    if (!caminho) return null;
    const { data } = await supabase.storage.from("assinaturas-documentos").createSignedUrl(caminho, 300);
    return data?.signedUrl ?? null;
  };

  return { ...consulta, porEspelho, enviar, reenviar, novoLink, cancelar, urlAssinado };
}
