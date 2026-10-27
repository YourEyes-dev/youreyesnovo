-- SEG/ISOL-005 — documento_audit_logs nasceu em PRODUÇÃO fora das migrations e
-- entrou no repo por IF NOT EXISTS (20261026203446_arquivar_documento_servidor)
-- SEM isolamento. No banco efêmero do CI (história completa do zero) ela nasce
-- com tenant_id e RLS DESLIGADO -> exposição direta entre tenants, que o caso
-- ISOL-005 acusa (regressão: passou -> falhou).
--
-- Conserto = mesma cerca das irmãs de trilha de assinatura
-- (assinaturas_trilha, consentimentos_assinatura): RLS LIGADO + leitura só do
-- próprio tenant. A gravação é feita exclusivamente pela RPC
-- public.arquivar_documento_servidor (SECURITY DEFINER), que ignora RLS, então a
-- trilha permanece imutável e insert-only (sem política de INSERT/UPDATE/DELETE).
--
-- Idempotente: ENABLE é no-op se já ligado; DROP+CREATE recria a política.

SET lock_timeout = '10s';

ALTER TABLE public.documento_audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "documento_audit_logs_leitura_tenant" ON public.documento_audit_logs;
CREATE POLICY "documento_audit_logs_leitura_tenant"
  ON public.documento_audit_logs FOR SELECT
  TO authenticated
  USING (tenant_id = public.get_user_tenant_id());
