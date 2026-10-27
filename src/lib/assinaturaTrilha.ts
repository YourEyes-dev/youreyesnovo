import { rpcUntyped } from "@/integrations/supabase/untypedClient";

/**
 * ASS-0001 — FASE 0: trilha padronizada da assinatura forte.
 *
 * Grava uma linha com tudo o que sustenta a assinatura avançada: signatário/papel,
 * CPF validado, método do liveness + versão do detector, hash, IP/UA/hora (selados
 * pelo servidor), versão do consentimento aceito e as referências dos frames no
 * bucket privado. Helper para a fase 1 ligar nos módulos (Advertência etc.).
 */
export interface RegistrarTrilhaParams {
  tenantId: string;
  contexto: string;
  documentoRef?: string | null;
  signatarioNome?: string | null;
  signatarioPapel?: string | null;
  signatarioCpf?: string | null;
  cpfValidado?: boolean;
  metodoLiveness?: "face-landmarker" | "manual" | null;
  versaoDetector?: string | null;
  /** Conteúdo e assinatura para o servidor SELAR o hash; se ausentes, use hashPreSelado. */
  conteudo?: string | null;
  assinatura?: string | null;
  /** Hash já selado por outra camada do servidor (quando conteúdo/assinatura não vão no payload). */
  hashPreSelado?: string | null;
  versaoConsentimento?: string | null;
  consentimentoId?: string | null;
  /** Caminhos dos frames no bucket privado (de persistirFramesDaEvidencia). */
  framesRefs?: string[];
  livenessData?: unknown;
}

export interface TrilhaRegistrada {
  id: string;
  assinaturaHash: string | null;
  assinadoEm: string;
  ipAddress: string | null;
}

export async function registrarAssinaturaTrilha(
  params: RegistrarTrilhaParams,
): Promise<TrilhaRegistrada | null> {
  const { data, error } = await rpcUntyped("registrar_assinatura_trilha", {
    p_dados: {
      tenant_id: params.tenantId,
      contexto: params.contexto,
      documento_ref: params.documentoRef ?? null,
      signatario_nome: params.signatarioNome ?? null,
      signatario_papel: params.signatarioPapel ?? null,
      signatario_cpf: params.signatarioCpf ?? null,
      cpf_validado: params.cpfValidado ?? false,
      metodo_liveness: params.metodoLiveness ?? null,
      versao_detector: params.versaoDetector ?? null,
      conteudo: params.conteudo ?? null,
      assinatura: params.assinatura ?? null,
      assinatura_hash: params.hashPreSelado ?? null,
      versao_consentimento: params.versaoConsentimento ?? null,
      consentimento_id: params.consentimentoId ?? null,
      frames_refs: params.framesRefs ?? [],
      liveness_data: params.livenessData ?? null,
    },
  });

  if (error || !data) {
    console.error("[assinaturaTrilha] registro falhou:", error);
    return null;
  }
  return {
    id: data.id,
    assinaturaHash: data.assinatura_hash ?? null,
    assinadoEm: data.assinado_em,
    ipAddress: data.ip_address ?? null,
  };
}
