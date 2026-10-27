-- ============================================================================
-- SEG/ISOL-005 (PRODUÇÃO) — fecha a trilha de documentos entre empresas.
-- A tabela public.documento_audit_logs nasceu em produção FORA das migrations,
-- com RLS DESLIGADO -> uma empresa podia ler a trilha de documentos de outra.
-- Mesma cerca das irmãs da assinatura (assinaturas_trilha / consentimentos_
-- assinatura): RLS LIGADO + leitura só do próprio tenant. A gravação é só pela
-- RPC public.arquivar_documento_servidor (SECURITY DEFINER, ignora RLS), então
-- a trilha segue imutável e insert-only (sem política de INSERT/UPDATE/DELETE).
-- NÃO altera dado. NÃO cria tabela. Idempotente (pode rodar duas vezes).
-- ============================================================================
SET lock_timeout = '10s';

ALTER TABLE public.documento_audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "documento_audit_logs_leitura_tenant" ON public.documento_audit_logs;
CREATE POLICY "documento_audit_logs_leitura_tenant"
  ON public.documento_audit_logs FOR SELECT
  TO authenticated
  USING (tenant_id = public.get_user_tenant_id());

-- Conferência: RLS ligado (t) e a política de leitura por tenant existe (t).
SELECT
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.documento_audit_logs'::regclass) AS rls_ligado,
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'documento_audit_logs'
      AND policyname = 'documento_audit_logs_leitura_tenant'
  ) AS politica_leitura_por_tenant;
