import { rpcUntyped } from "@/integrations/supabase/untypedClient";

/**
 * ASS-0001 — FASE 0: consentimento LGPD biométrico da assinatura forte.
 *
 * Dado biométrico é sensível (LGPD art. 11) e exige consentimento específico e
 * destacado, com finalidade clara (art. 9º). Esta é a versão vigente do texto e a
 * finalidade padrão. Ao mudar o texto do consentimento, SUBA a versão: a trilha
 * guarda qual versão cada pessoa aceitou.
 */
export const VERSAO_CONSENTIMENTO_BIOMETRICO = "consentimento-biometrico-v1";

/** Finalidade padrão: específica do ato de assinar este documento. */
export const FINALIDADE_CONSENTIMENTO_BIOMETRICO =
  "Confirmar a sua identidade no momento da assinatura deste documento (verificação de presença por câmera).";

export interface RegistrarConsentimentoParams {
  tenantId: string;
  /** Módulo/fluxo (ex.: 'advertencia', 'epi'). */
  contexto: string;
  /** Id/token do documento assinado. */
  documentoRef?: string | null;
  signatarioNome?: string | null;
  signatarioCpf?: string | null;
  /** Finalidade mostrada ao titular; por padrão, a finalidade específica da assinatura. */
  finalidade?: string;
  /** Versão do texto aceito; por padrão, a versão vigente. */
  versaoTexto?: string;
}

export interface ConsentimentoRegistrado {
  id: string;
  versaoTexto: string;
  aceitoEm: string;
  ipAddress: string | null;
}

/**
 * Registra o aceite do consentimento na trilha do servidor (origem IP/UA/hora
 * derivada lá). Deve ser chamado QUANDO o titular aceita, ANTES de ligar a câmera.
 * Devolve o registro (id + versão) para ligar à trilha da assinatura.
 */
export async function registrarConsentimentoBiometrico(
  params: RegistrarConsentimentoParams,
): Promise<ConsentimentoRegistrado | null> {
  const { data, error } = await rpcUntyped("registrar_consentimento_biometrico", {
    p_dados: {
      tenant_id: params.tenantId,
      contexto: params.contexto,
      documento_ref: params.documentoRef ?? null,
      signatario_nome: params.signatarioNome ?? null,
      signatario_cpf: params.signatarioCpf ?? null,
      finalidade: params.finalidade ?? FINALIDADE_CONSENTIMENTO_BIOMETRICO,
      versao_texto: params.versaoTexto ?? VERSAO_CONSENTIMENTO_BIOMETRICO,
      aceito: true,
    },
  });

  if (error || !data) {
    console.error("[assinaturaConsentimento] registro falhou:", error);
    return null;
  }
  return {
    id: data.id,
    versaoTexto: data.versao_texto,
    aceitoEm: data.aceito_em,
    ipAddress: data.ip_address ?? null,
  };
}
